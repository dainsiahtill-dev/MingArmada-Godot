import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';

const base = 'docs/research/evidence/story-campaign-flow/';
const load = p => JSON.parse(readFileSync(p, 'utf8'));
const hash = p => createHash('sha256').update(readFileSync(p)).digest('hex');
const files = ['final-core-01.json', 'final-catalog-01.json', 'final-laboratory-01.json'];
const runs = [];
for (const file of files) {
  const report = load(base + file);
  assert.equal(report.summary.passedAll, true);
  for (const run of report.runs) {
    assert.equal(run.passed, true); assert.equal(run.exitCode, 0);
    runs.push({ ...run, sourceReport: base + file, currentTestSha256: hash(run.test) });
  }
}
assert.equal(runs.length, 5);
const gpuPath = base + 'framework-gpu-02/process-result.json', gpu = load(gpuPath);
assert.equal(gpu.valid, true); assert.equal(gpu.sourceUnchanged, true); assert.equal(gpu.originalUnchanged, true);
assert.deepEqual(gpu.capture.errors, []);
for (const [file, expected] of Object.entries(gpu.sourceAfter)) if (expected !== null) assert.equal(hash(file), expected, `GPU source stale: ${file}`);
const total = { schemaVersion:1, scope:'five focused files; no whole-game suite or real mainline playthrough', summary:{selected:5,passed:5,failed:0,passedAll:true}, sources:files.map(file => ({file:base + file,sha256:hash(base + file)})), runs };
writeFileSync(base + 'final-regression-01.json', JSON.stringify(total, null, 2) + '\n', { flag:'wx' });
const captures = load(base + 'framework-gpu-02/frames/capture-result.json');
assert.equal(captures.actualGameplayComplete, false);
const images = ['complete-000.png','detail-038.png','detail-118.png'].map(file => {
  const path = base + 'framework-gpu-02/frames/' + file, expected = captures.captures.find(x => x.file === file);
  assert.equal(hash(path), expected.sha256);
  return {file:path,sha256:hash(path),method:'root visually inspected original PNG via view_image'};
});
const report = {
  valid:true, wholeGoalComplete:false, actualGameplayComplete:false, finalizedUtc:new Date().toISOString(),
  stage:'machine-readable whole-mainline content and synthetic progress framework',
  content:{chapters:24,stages:30,acts:6}, focusedTests:5,
  cpu:{file:base + 'final-regression-01.json',sha256:hash(base + 'final-regression-01.json')},
  gpu:{file:gpuPath,sha256:hash(gpuPath),captures:gpu.capture.captures,samples:gpu.capture.sampledFrames,acceptedSteps:gpu.capture.acceptedSteps,gpu:gpu.capture.gpu,renderer:gpu.capture.renderer,sourceCurrentMatchesGpu:true,originalUserdirUnchanged:true},
  imageReviews:images,
  limitations:['all new real-world task adapters pending','no actual world asset handoff or complete campaign persistence','no actual task/sea-battle/trade playthrough','no manual long play, game FPS or final balance proof','direct source freeze only, not all transitive/imported assets','failure archives retain summaries and recent raw failures, not all original failure facts'],
};
writeFileSync(base + 'framework-delivery.json', JSON.stringify(report, null, 2) + '\n', { flag:'wx' });
console.log(`MAINLINE_FRAMEWORK_DELIVERY valid=true focused_tests=${runs.length} gpu_images=${gpu.capture.captures} actualGameplayComplete=false wholeGoalComplete=false`);
