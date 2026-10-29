import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';

const base = 'docs/research/evidence/ship-fire-control/';
const load = file => JSON.parse(readFileSync(file, 'utf8'));
const hash = file => createHash('sha256').update(readFileSync(file)).digest('hex');
const gpuPath = base + 'zones-gpu-02/process-result.json';
const cpuPath = base + 'zones-regression-01.json';
const gpu = load(gpuPath), cpu = load(cpuPath);
const cpuBefore = load(base + 'zones-cpu-source-before-01.json');
const current = Object.fromEntries(Object.keys(cpuBefore).map(file => [file, hash(file)]));
assert.deepEqual(current, cpuBefore, 'CPU source changed during/after final regression');
assert.equal(cpu.summary.passedAll, true);
assert.equal(cpu.summary.selected, 7);
assert.equal(gpu.valid, true);
assert.equal(gpu.sourceUnchanged, true);
assert.equal(gpu.originalUnchanged, true);
assert.deepEqual(gpu.capture.errors, []);
for (const [file, expected] of Object.entries(gpu.sourceAfter)) {
  if (expected !== null) assert.equal(hash(file), expected, `GPU source is stale: ${file}`);
}
const auditPath = base + 'zones-audit-green-01.json';
assert.equal(load(auditPath).exit, 0);
const networkPath = 'docs/production/gameplay-showcase-2026-10-29/three-zone-fire-network.json';
const network = load(networkPath);
assert.equal(network.passed, true);
const reviews = ['stern-page.png', 'stern-spread-near.png', 'mid-030.png'];
const report = load(base + 'zones-gpu-02/frames/capture-result.json');
for (const file of reviews) assert.equal(hash(base + 'zones-gpu-02/frames/' + file), report.captures.find(x => x.file === file).sha256);
const result = {
  valid: true, wholeGoalComplete: false, stage: 'H5 independent experiment only',
  finalizedAtUtc: new Date().toISOString(), cpuSourceUnchanged: true, sourceCurrentMatchesGpu: true,
  cpu: { file: cpuPath, sha256: hash(cpuPath), tests: cpu.runs.map(r => ({ file: r.test, passed: r.passed, completion: r.stdout.trim().split(/\r?\n/).at(-1) })) },
  gpu: { file: gpuPath, sha256: hash(gpuPath), captures: gpu.capture.captures, samples: gpu.capture.sampledFrames, acceptedSteps: gpu.capture.acceptedSteps, gpu: gpu.capture.gpu, renderer: gpu.capture.renderer, originalUserdirUnchanged: true },
  audit: { file: auditPath, sha256: hash(auditPath), tests: 6, failures: 0 },
  imageReviews: reviews.map(file => ({ file: base + 'zones-gpu-02/frames/' + file, sha256: hash(base + 'zones-gpu-02/frames/' + file), method: 'root visually inspected original PNG via view_image' })),
  web: { file: networkPath, sha256: hash(networkPath), tests: network.tests, passed: true, publicFrpTested: false, browserVisualTested: false },
  cpuSource: current,
  limitations: ['controlled ignition, no true contact classification', 'production fire mode remains r1 one-click', 'no bucket or dousing animation', 'no campaign/save integration', 'no manual long play or whole-game frame-time/balance conclusion', 'GPU direct sources frozen, not all transitive/imported assets'],
};
writeFileSync(base + 'zones-experiment-delivery.json', JSON.stringify(result, null, 2) + '\n', { flag: 'wx' });
console.log(`ZONES_EXPERIMENT_DELIVERY valid=${result.valid} tests=${cpu.runs.length} captures=${gpu.capture.captures} wholeGoalComplete=false`);
