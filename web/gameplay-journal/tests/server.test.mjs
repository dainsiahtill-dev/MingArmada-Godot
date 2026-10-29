import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFile } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, symlink, writeFile } from 'node:fs/promises';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const script = fileURLToPath(new URL('../scripts/serve.mjs', import.meta.url));
const dist = fileURLToPath(new URL('../dist/', import.meta.url));
const runFile = promisify(execFile);
const hash = (bytes) => createHash('sha256').update(bytes).digest('hex');

function request(server, target, { method = 'GET', headers = {} } = {}) {
  return new Promise((resolve, reject) => {
    const outgoing = http.request({ hostname: '127.0.0.1', port: server.address().port, path: target, method, headers }, (response) => {
      const chunks = [];
      response.on('data', (chunk) => chunks.push(chunk));
      response.on('end', () => resolve({ status: response.statusCode, headers: response.headers, body: Buffer.concat(chunks) }));
      response.on('error', reject);
    });
    outgoing.on('error', reject);
    outgoing.end();
  });
}

async function listen(server, t) {
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  t.after(() => new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve())));
  return server;
}

test('static service serves only its public directory over real HTTP', async (t) => {
  const api = await import('../scripts/serve.mjs').catch((error) => ({ error }));
  assert.equal(typeof api.createServer, 'function', `static server factory missing: ${api.error?.code ?? 'no export'}`);

  const temporary = await mkdtemp(path.join(os.tmpdir(), 'ming-journal-server-'));
  t.after(() => rm(temporary, { recursive: true, force: true }));
  const root = path.join(temporary, 'public');
  const privateRoot = path.join(temporary, 'private');
  await mkdir(path.join(root, 'assets'), { recursive: true });
  await mkdir(privateRoot);
  const html = Buffer.from('<!doctype html><title>海上明旗</title>');
  const image = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3]);
  await Promise.all([
    writeFile(path.join(root, 'index.html'), html),
    writeFile(path.join(root, 'styles.css'), 'body { color: black; }'),
    writeFile(path.join(root, 'app.js'), 'window.ready = true;'),
    writeFile(path.join(root, 'manifest.json'), '{"version":1}'),
    writeFile(path.join(root, '航志.txt'), '持续更新'),
    writeFile(path.join(root, 'assets', 'ship.png'), image),
    writeFile(path.join(privateRoot, 'secret.txt'), 'private source must never be served'),
  ]);
  const server = await listen(await api.createServer({ root }), t);

  await t.test('GET and HEAD preserve bytes, UTF-8 MIME, and content length', async () => {
    const get = await request(server, '/?revision=1');
    assert.equal(get.status, 200);
    assert.deepEqual(get.body, html);
    assert.equal(get.headers['content-type'], 'text/html; charset=utf-8');
    assert.equal(Number(get.headers['content-length']), html.length);
    const head = await request(server, '/', { method: 'HEAD' });
    assert.equal(head.status, 200);
    assert.equal(head.body.length, 0);
    assert.equal(head.headers['content-length'], get.headers['content-length']);
    for (const [target, type] of [
      ['/styles.css', 'text/css; charset=utf-8'],
      ['/app.js', 'text/javascript; charset=utf-8'],
      ['/manifest.json', 'application/json; charset=utf-8'],
      ['/%E8%88%AA%E5%BF%97.txt', 'text/plain; charset=utf-8'],
      ['/assets/ship.png', 'image/png'],
    ]) {
      const response = await request(server, target);
      assert.equal(response.status, 200, target);
      assert.equal(response.headers['content-type'], type, target);
    }
    assert.equal(hash((await request(server, '/assets/ship.png')).body), hash(image));
  });

  await t.test('missing sources return 404 and directories cannot be browsed', async () => {
    for (const target of ['/missing.html', '/src/index.html', '/docs/secret.txt', '/scripts/serve.mjs', '/content/gameplay.json']) {
      const response = await request(server, target);
      assert.equal(response.status, 404, target);
      assert.equal(response.body.toString(), 'Not found\n');
      assert.ok(!response.body.includes(Buffer.from(temporary)));
    }
    for (const target of ['/assets', '/assets/']) assert.equal((await request(server, target)).status, 403, target);
    assert.equal((await request(server, '/missing.html', { method: 'HEAD' })).body.length, 0);
  });

  await t.test('raw and encoded traversal never reaches parent paths or Windows aliases', async () => {
    for (const target of [
      '/../private/secret.txt', '/assets/../../private/secret.txt', '/./index.html',
      '/%2e%2e/private/secret.txt', '/assets%2f..%2f..%2fprivate/secret.txt',
      '/..\\private\\secret.txt', '/%5c..%5cprivate%5csecret.txt',
      '/%252e%252e/private/secret.txt', '/C:/Users/secret.txt',
      '/assets/ship.png::$DATA', '/%00secret', '//private/secret.txt',
      '/assets/..%20/private/secret.txt', '/assets/%2e%2e./private/secret.txt',
    ]) {
      const response = await request(server, target);
      assert.equal(response.status, 403, target);
      assert.equal(response.body.toString(), 'Forbidden\n');
    }
    for (const target of ['/%E0%A4%A', '/%zz']) assert.equal((await request(server, target)).status, 400, target);
  });

  await t.test('only GET and HEAD are accepted', async () => {
    for (const method of ['POST', 'PUT', 'DELETE', 'OPTIONS']) {
      const response = await request(server, '/', { method });
      assert.equal(response.status, 405, method);
      assert.equal(response.headers.allow, 'GET, HEAD');
    }
  });

  await t.test('updates are visible without browser cache reuse or server restart', async () => {
    const updated = '<title>更新航志</title>';
    await writeFile(path.join(root, 'index.html'), updated);
    const response = await request(server, '/', { headers: { 'If-Modified-Since': new Date().toUTCString(), 'If-None-Match': '*' } });
    assert.equal(response.status, 200);
    assert.equal(response.body.toString(), updated);
    assert.match(response.headers['cache-control'], /no-store/);
    assert.equal(response.headers['x-content-type-options'], 'nosniff');
  });

  await t.test('realpath containment rejects an escaping directory junction', async (context) => {
    try {
      await symlink(privateRoot, path.join(root, 'escape'), process.platform === 'win32' ? 'junction' : 'dir');
    } catch (error) {
      if (['EPERM', 'EACCES', 'ENOTSUP'].includes(error.code)) return context.skip(`symlink unavailable: ${error.code}`);
      throw error;
    }
    const response = await request(server, '/escape/secret.txt');
    assert.equal(response.status, 403);
    assert.equal(response.body.toString(), 'Forbidden\n');
    await assert.rejects(api.createServer({ root: path.join(root, 'escape') }), /real directory|symbolic link/i);
  });

  await t.test('CLI rejects invalid bind options and cannot override the public root', async () => {
    assert.deepEqual(api.parseArgs([]), { host: '0.0.0.0', port: 4173, help: false });
    assert.deepEqual(api.parseArgs(['--host', '127.0.0.1', '--port', '8080']), { host: '127.0.0.1', port: 8080, help: false });
    for (const args of [
      ['--root', privateRoot], ['--port', '0'], ['--port', '65536'], ['--port', '12x'],
      ['--port', '-1'], ['--port'], ['--host', 'evil.example'], ['--host', '0.0.0.0/path'],
      ['--host'], ['--port', '4173', '--port', '4174'],
    ]) assert.throws(() => api.parseArgs(args), /Usage|host|port|option/i, args.join(' '));
    const help = await runFile(process.execPath, [script, '--help']);
    assert.match(help.stdout, /Usage:.*serve\.mjs/);
    await assert.rejects(runFile(process.execPath, [script, '--root', privateRoot]), (error) => error.code === 1 && /Usage|option/i.test(error.stderr));
  });

  await t.test('LAN candidates contain only usable non-loopback IPv4 addresses', () => {
    assert.deepEqual(api.lanAddresses({
      first: [
        { family: 'IPv4', address: '192.168.2.9', internal: false },
        { family: 'IPv4', address: '127.0.0.2', internal: false },
        { family: 'IPv4', address: '169.254.3.4', internal: false },
        { family: 'IPv6', address: '::1', internal: false },
      ],
      second: [{ family: 4, address: '10.0.0.7', internal: false }, { family: 'IPv4', address: '192.168.2.9', internal: false }],
    }), ['10.0.0.7', '192.168.2.9']);
  });

  await t.test('default root serves the built site byte-for-byte and no repository source', async (context) => {
    const builtServer = await listen(await api.createServer(), context);
    const response = await request(builtServer, '/');
    assert.equal(response.status, 200);
    assert.equal(hash(response.body), hash(await readFile(path.join(dist, 'index.html'))));
    const manifest = JSON.parse(await readFile(path.join(dist, 'manifest.json'), 'utf8'));
    const imageRecord = manifest.outputs.find((entry) => entry.path.startsWith('assets/'));
    assert.ok(imageRecord, 'built site must contain an image');
    const builtImage = await request(builtServer, `/${imageRecord.path}`);
    assert.equal(builtImage.status, 200);
    assert.equal(hash(builtImage.body), imageRecord.sha256);
    for (const target of ['/src/index.html', '/docs/research/README.md', '/AGENTS.md', '/scripts/build.mjs']) {
      assert.equal((await request(builtServer, target)).status, 404, target);
    }
  });
});
