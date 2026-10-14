import { readFile, readdir, stat, writeFile, mkdir } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const evidence = path.join(root, 'docs/research/evidence/laboratory-2026-10-14');
const failures = [];
const check = (ok, label) => { if (!ok) failures.push(label); };
const json = async name => JSON.parse(await readFile(path.join(evidence, name), 'utf8'));
async function hash(file) {
  const h = createHash('sha256');
  for await (const chunk of createReadStream(file)) h.update(chunk);
  return h.digest('hex');
}
async function text(file) {
  const b = await readFile(path.join(root, file));
  return b[0] === 255 && b[1] === 254 ? b.subarray(2).toString('utf16le') : b.toString('utf8');
}
async function walk(dir) {
  const result = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    if (entry.name === 'initial-gpu') continue;
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) result.push(...await walk(file));
    else if (entry.name !== 'DELIVERY_VERIFY.json') result.push(file);
  }
  return result;
}
const catalog = JSON.parse(await text('assets/research/catalog.json'));
check(catalog.topics.length === 5, 'five subject registrations');
const papers = [];
for (const item of catalog.topics) {
  const relative = item.paper.replace('res://', '');
  const paper = await text(relative);
  for (const h of ['问题与假设','方案比较','算法与实现','实验设计','结果与证据','局限与失败','集成与复现']) check(paper.includes(`## ${h}`), `${item.id}: ${h}`);
  papers.push({ id: item.id, path: relative, sha256: await hash(path.join(root, relative)), demo: item.demo, retrospective: item.retrospective });
}
const regressions = await json('regressions.json');
check(regressions.summary.passedAll && regressions.runs.length === 4, 'four focused laboratory suites pass');
const gpu = await json('GPU_VERIFY.json');
check(gpu.valid && gpu.failures.length === 0 && gpu.captures.length === 43 && gpu.sequences.length === 5, 'final GPU/state capture contracts');
check(gpu.persistedBefore && JSON.stringify(gpu.persistedBefore) === JSON.stringify(gpu.persistedAfter), 'actual GPU route leaves saves/settings unchanged');
const ui = await json('UI_VERIFY.json');
check(ui.valid && ui.captures.length === 7, 'final paper/caption UI captured');
for (const capture of [...gpu.captures, ...ui.captures]) check(await hash(path.join(evidence, capture.image)) === capture.sha256, `original frame SHA: ${capture.image}`);
const on = gpu.captures.find(c => c.name === 'comparison-contact-on').laboratory.demo;
for (const k of ['camera_transform','camera_projection']) check(on[k]?.length === 16, `actual matrix metadata: ${k}`);
check(Number.isInteger(on.waterpacket_seed) && typeof on.froth_rng_state_decimal === 'string', 'concrete reproducible random metadata');
const exportedImage = await json('native-demo-export.png.json');
check(await hash(path.join(evidence, 'native-demo-export.png')) === exportedImage.image_sha256, 'native in-game frame export SHA');
check(gpu.carrierPairs.length === 2 && JSON.stringify(gpu.carrierPairs[0].state.native_ship) === JSON.stringify(gpu.carrierPairs[1].state.native_ship), 'carrier paired native pose');
const pack = await json('PACK_VERIFY.json');
check(pack.valid && pack.failures.length === 0, 'package-only contract passes');
for (const paper of papers) check(pack.subjects.find(s => s.id === paper.id)?.sha256 === paper.sha256, `packed current paper SHA: ${paper.id}`);
for (const log of ['Temp/laboratory-final-gpu.log','Temp/laboratory-final-ui.log','Temp/laboratory-pack-final.log','Temp/laboratory-export-final.log']) check(!/(?:^|\n)\s*(?:SCRIPT ERROR|ERROR):/m.test(await text(log)), `no engine error in ${log}`);
const sourceNames = ['AGENTS.md','export_presets.cfg','game/ui/menu/main_menu.gd','game/runtime/game_router.gd','game/research/catalog.gd','game/research/paper_reader.gd','game/research/laboratory.gd','game/research/demos/hull_contact_experiment.gd','assets/research/catalog.json','docs/research/README.md','docs/research/TOPIC_TEMPLATE.md','docs/research/laboratory-delivery-2026-10-14.md','tools/verify-laboratory-gpu.gd','tools/verify-laboratory-pack.gd','tools/study-laboratory-carrier.gd','tools/verify-laboratory-delivery.mjs','tests/test_laboratory_catalog.gd','tests/test_laboratory_demo.gd','tests/test_laboratory_entry.gd','tests/test_laboratory_ui.gd'];
const sources = {};
for (const name of sourceNames) sources[name] = await hash(path.join(root, name));
for (const [name, sha] of Object.entries(ui.sourceHashes)) check(sources[name.replace('res://','')] === sha, `final UI source binding: ${name}`);
check(sources['game/research/demos/hull_contact_experiment.gd'] === '23cc79c90991875c96c5bf1a49bce6386b6259fa294f722f017932c819ea561c', 'frozen carrier/demo code verified');
const preserved = {};
const before = JSON.parse(await text('Temp/hull-contact-tail-preserved.json'));
for (const entry of before.entries) {
  const file = `modules/scene_engine/water/${entry.name}`;
  const actual = await hash(path.join(root, file));
  preserved[file] = actual;
  check(actual === entry.sha256, `tail/source surface unchanged: ${entry.name}`);
}
let broad = { status: 'not-finished' };
try {
  const full = await json('full-regressions.json');
  broad = { ...full.summary, failures: full.runs.filter(r => !r.passed).map(r => ({ test: r.test, reasons: r.reasons, stderr: r.stderr })) };
} catch { /* A broad audit is not the feature acceptance gate. */ }
const artifacts = [];
for (const file of await walk(evidence)) artifacts.push({ path: path.relative(root, file).replaceAll('\\','/'), bytes: (await stat(file)).size, sha256: await hash(file) });
const result = { schemaVersion: 1, valid: failures.length === 0, failures, generatedAtUtc: new Date().toISOString(), papers, sources, preservedTailAndSurface: preserved, focusedTests: regressions.runs.map(r => ({ test: r.test, passed: r.passed, stdout: r.stdout })), gpu: { captures: gpu.captures.length, sequences: gpu.sequences.length, nativeFrameExports: 1, uiCaptures: ui.captures.length, device: gpu.gpu, scope: gpu.scope }, package: { assertions: pack.assertions, path: 'Temp/laboratory-export-final.pck', sha256: await hash(path.join(root, 'Temp/laboratory-export-final.pck')) }, broaderRegressionAudit: broad, artifacts, limitations: ['The four other papers do not yet have new independent demos.', 'Low-angle hull/water observations remain faceted and foam subtle; capture contracts are not blanket artistic acceptance.', 'Carrier density improves numerical interpolation error; it does not establish the root cause of weak contact rendering.', 'PCK was verified headless in an empty directory; no packaged Windows EXE/GPU acceptance claimed.', 'Broader failures/timeouts are recorded separately and do not become passing results; only the vegetation failure was established as preexisting in this review.'] };
await mkdir(evidence, { recursive: true });
await writeFile(path.join(evidence, 'DELIVERY_VERIFY.json'), JSON.stringify(result, null, 2));
console.log(JSON.stringify({ valid: result.valid, failures, papers: papers.length, gpuCaptures: gpu.captures.length, finalUiCaptures: ui.captures.length, artifacts: artifacts.length, broad: { selected: broad.selected, passed: broad.passed, failed: broad.failed, failures: broad.failures?.map(r => r.test) } }));
process.exitCode = result.valid ? 0 : 1;
