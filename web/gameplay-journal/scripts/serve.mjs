import { lstat, open, realpath } from 'node:fs/promises';
import { createServer as createHttpServer } from 'node:http';
import { isIP } from 'node:net';
import { networkInterfaces } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_PATH = fileURLToPath(import.meta.url);
const DIST_ROOT = path.resolve(path.dirname(SCRIPT_PATH), '../dist');
const USAGE = 'Usage: node web/gameplay-journal/scripts/serve.mjs [--host <IP|localhost>] [--port <1-65535>] [--help]';
const TYPES = new Map([
  ['.html', 'text/html; charset=utf-8'],
  ['.css', 'text/css; charset=utf-8'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.mjs', 'text/javascript; charset=utf-8'],
  ['.json', 'application/json; charset=utf-8'],
  ['.txt', 'text/plain; charset=utf-8'],
  ['.svg', 'image/svg+xml; charset=utf-8'],
  ['.xml', 'application/xml; charset=utf-8'],
  ['.png', 'image/png'],
  ['.jpg', 'image/jpeg'],
  ['.jpeg', 'image/jpeg'],
  ['.gif', 'image/gif'],
  ['.webp', 'image/webp'],
  ['.avif', 'image/avif'],
  ['.ico', 'image/x-icon'],
  ['.woff', 'font/woff'],
  ['.woff2', 'font/woff2'],
]);
const MESSAGES = new Map([[400, 'Bad request'], [403, 'Forbidden'], [404, 'Not found'], [405, 'Method not allowed']]);

function inside(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === '' || (relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative));
}

function reject(status) {
  const error = new Error(MESSAGES.get(status));
  error.status = status;
  throw error;
}

function validatePath(value) {
  // Validate before any URL or filesystem normalization can erase traversal.
  if (!value.startsWith('/') || value.startsWith('//') || /[\\\u0000-\u001f\u007f:<>"|*?#]/.test(value)) reject(403);
  const parts = value.slice(1).split('/');
  if (parts.some((part, index) => part === '.' || part === '..' || /[. ]$/.test(part) || (part === '' && index < parts.length - 1))) reject(403);
}

function requestPath(target) {
  const rawPath = target.split('?', 1)[0];
  validatePath(rawPath);
  let decoded;
  try {
    decoded = decodeURIComponent(rawPath);
  } catch {
    reject(400);
  }
  validatePath(decoded);
  // No build output needs literal percent signs; reject nested encodings too.
  if (decoded.includes('%')) reject(403);
  return decoded === '/' ? 'index.html' : decoded.slice(1);
}

function errorStatus(error) {
  if (MESSAGES.has(error.status)) return error.status;
  if (['EACCES', 'EPERM', 'ELOOP'].includes(error.code)) return 403;
  return 404;
}

function sendError(request, response, status) {
  if (response.headersSent) return response.destroy();
  const body = Buffer.from(`${MESSAGES.get(status)}\n`);
  response.statusCode = status;
  response.setHeader('Content-Type', 'text/plain; charset=utf-8');
  response.setHeader('Content-Length', body.length);
  response.end(request.method === 'HEAD' ? undefined : body);
}

/** Return an unbound HTTP server; callers own listen/close. CLI root is fixed to dist. */
export async function createServer({ root = DIST_ROOT } = {}) {
  const absoluteRoot = path.resolve(root);
  const rootInfo = await lstat(absoluteRoot);
  const actualRoot = await realpath(absoluteRoot);
  if (!rootInfo.isDirectory() || rootInfo.isSymbolicLink() || path.relative(absoluteRoot, actualRoot) !== '') {
    throw new Error('Public root must be a real directory, with no symbolic link ancestors.');
  }

  return createHttpServer(async (request, response) => {
    response.setHeader('Cache-Control', 'no-store, max-age=0');
    response.setHeader('Pragma', 'no-cache');
    response.setHeader('Expires', '0');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    if (!['GET', 'HEAD'].includes(request.method)) {
      response.setHeader('Allow', 'GET, HEAD');
      sendError(request, response, 405);
      return;
    }

    let file;
    try {
      const relative = requestPath(request.url ?? '');
      const candidate = path.resolve(actualRoot, ...relative.split('/'));
      if (!inside(actualRoot, candidate)) reject(403);
      const actualPath = await realpath(candidate);
      if (!inside(actualRoot, actualPath)) reject(403);
      file = await open(actualPath, 'r');
      const info = await file.stat();
      if (!info.isFile()) reject(403);
      response.setHeader('Content-Type', TYPES.get(path.extname(relative).toLowerCase()) ?? 'application/octet-stream');
      response.setHeader('Content-Length', info.size);
      if (request.method === 'HEAD') {
        await file.close();
        file = undefined;
        response.end();
        return;
      }
      const stream = file.createReadStream();
      file = undefined;
      stream.once('error', () => sendError(request, response, 404));
      response.once('close', () => stream.destroy());
      stream.pipe(response);
    } catch (error) {
      if (file) await file.close().catch(() => {});
      sendError(request, response, errorStatus(error));
    }
  });
}

export function parseArgs(args) {
  const result = { host: '0.0.0.0', port: 4173, help: false };
  if (args.length === 1 && args[0] === '--help') return { ...result, help: true };
  const seen = new Set();
  for (let index = 0; index < args.length; index += 2) {
    const option = args[index];
    const value = args[index + 1];
    if (!['--host', '--port'].includes(option) || seen.has(option) || !value) throw new Error(USAGE);
    seen.add(option);
    if (option === '--host') {
      if (value !== 'localhost' && isIP(value) === 0) throw new Error(`Invalid host. ${USAGE}`);
      result.host = value;
    } else {
      if (!/^\d+$/.test(value) || Number(value) < 1 || Number(value) > 65535) throw new Error(`Invalid port. ${USAGE}`);
      result.port = Number(value);
    }
  }
  return result;
}

/** IPv4 candidates only; interface presence alone does not prove LAN reachability. */
export function lanAddresses(interfaces = networkInterfaces()) {
  return [...new Set(Object.values(interfaces).flat().filter((entry) => entry
    && (entry.family === 'IPv4' || entry.family === 4) && !entry.internal
    && isIP(entry.address) === 4 && !/^(?:127\.|169\.254\.|0\.)/.test(entry.address))
    .map((entry) => entry.address))].sort();
}

if (process.argv[1] && path.resolve(process.argv[1]) === SCRIPT_PATH) {
  try {
    const options = parseArgs(process.argv.slice(2));
    if (options.help) {
      console.log(USAGE);
    } else {
      const server = await createServer();
      await new Promise((resolve, rejectListen) => {
        server.once('error', rejectListen);
        server.listen(options.port, options.host, resolve);
      });
      const host = isIP(options.host) === 6 ? `[${options.host}]` : options.host;
      console.log(`Serving gameplay journal dist: http://${host}:${options.port}/`);
      if (['0.0.0.0', '::'].includes(options.host)) {
        console.log(`Local: http://127.0.0.1:${options.port}/`);
        for (const address of lanAddresses()) console.log(`LAN candidate: http://${address}:${options.port}/`);
      }
    }
  } catch (error) {
    console.error(error.code ? `Cannot start gameplay journal server (${error.code}).` : error.message);
    process.exitCode = 1;
  }
}
