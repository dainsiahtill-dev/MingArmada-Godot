import http from 'node:http';
import { createHash } from 'node:crypto';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const siteRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const options = process.argv.slice(2);
let lanHost = null;
let outputPath = null;
for (let index = 0; index < options.length; index++) {
  if (options[index] === '--lan' && options[index + 1]) lanHost = options[++index];
  else if (options[index] === '--output' && options[index + 1]) outputPath = path.resolve(options[++index]);
  else throw new Error('Usage: node scripts/check-service.mjs [--lan IPv4] [--output report.json]');
}
if (lanHost && !/^\d{1,3}(?:\.\d{1,3}){3}$/.test(lanHost)) throw new Error('--lan must be an IPv4 address');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const manifest = JSON.parse(await readFile(path.join(siteRoot, 'dist/manifest.json'), 'utf8'));
const indexHash = hash(await readFile(path.join(siteRoot, 'dist/index.html')));
const observations = [];

function request({ host = '127.0.0.1', requestPath = '/', method = 'GET', headers = {} }) {
  return new Promise((resolve, reject) => {
    const req = http.request({ host, port: 4173, path: requestPath, method, headers, timeout: 5000 }, response => {
      const chunks = [];
      response.on('data', chunk => chunks.push(chunk));
      response.on('end', () => resolve({ host, requestPath, method, status: response.statusCode,
        contentType: response.headers['content-type'], cacheControl: response.headers['cache-control'],
        sha256: hash(Buffer.concat(chunks)) }));
    });
    req.on('error', reject);
    req.on('timeout', () => req.destroy(new Error('Request timed out')));
    req.end();
  });
}

async function check(input, expectedStatus, expectedHash) {
  try {
    const result = await request(input);
    result.passed = result.status === expectedStatus && (!expectedHash || result.sha256 === expectedHash);
    observations.push(result);
  } catch (error) {
    observations.push({ ...input, passed: false, error: error.message });
  }
}

await check({}, 200, indexHash);
if (lanHost) await check({ host: lanHost }, 200, indexHash);
await check({ headers: { Host: 'naval-game.example.test', Origin: 'https://naval-game.example.test',
  'X-Forwarded-Host': 'naval-game.example.test', 'X-Forwarded-Proto': 'https', 'X-Forwarded-For': '203.0.113.40' } }, 200, indexHash);
for (const artifact of manifest.outputs) {
  await check({ requestPath: '/' + artifact.path }, 200, artifact.sha256);
}
await check({ requestPath: '/game/domain/mingqi/campaign.gd' }, 404);
await check({ requestPath: '/../AGENTS.md' }, 403);
await check({ requestPath: '/assets/' }, 403);
await check({ method: 'POST' }, 405);
const report = { verifiedAtUtc: new Date().toISOString(), revisionHash: manifest.revisionHash,
  passed: observations.every(row => row.passed), tests: observations.length, observations,
  boundaries: { lanIpProbedFromSameMachine: Boolean(lanHost), secondLanDeviceTested: false,
    customProxyHeadersTested: true, publicFrpRouteTested: false, browserVisualValidation: false } };
if (outputPath) {
  await mkdir(path.dirname(outputPath), { recursive: true });
  await writeFile(outputPath, JSON.stringify(report, null, 2) + '\n');
}
console.log(JSON.stringify({ passed: report.passed, tests: report.tests, revision: report.revisionHash.slice(0, 12),
  failures: observations.filter(row => !row.passed), report: outputPath }));
if (!report.passed) process.exitCode = 1;
