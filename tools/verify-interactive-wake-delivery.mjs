import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

// Read-only evidence audit by default. --write creates the manifest once.
// --refresh-final replaces only the already-archived initial delivery receipt.
// Neither mode launches Godot, rewrites GPU evidence or changes runtime.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const base = 'docs/research/evidence/wake-flow';
const output = `${base}/DELIVERY_VERIFY.json`;
const artifacts = new Map();
const failures = [];
let assertions = 0;
const check = (ok, detail) => { assertions++; if (!ok) failures.push(detail); };
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const full = p => path.join(root, p.replace(/^res:\/\//, ''));
function artifact(p, expected) {
  p = p.replace(/^res:\/\//, '').replaceAll('\\', '/');
  check(fs.existsSync(full(p)), `existing artifact: ${p}`);
  if (!fs.existsSync(full(p))) return null;
  if (!artifacts.has(p)) {
    const bytes = fs.readFileSync(full(p));
    const record = { path: p, bytes: bytes.length, sha256: hash(bytes) };
    if (p.endsWith('.png')) {
      check(bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])), `PNG signature: ${p}`);
      record.width = bytes.readUInt32BE(16); record.height = bytes.readUInt32BE(20);
    }
    artifacts.set(p, record);
  }
  const record = artifacts.get(p);
  if (expected) check(record.sha256 === expected, `SHA256 matches receipt: ${p}`);
  return record;
}
function json(p) { artifact(p); return JSON.parse(fs.readFileSync(full(p), 'utf8')); }
const same = (a,b) => JSON.stringify(a) === JSON.stringify(b);
function wrapper(p) {
  const r=json(p);
  check(r.valid===true && r.exitCode===0 && r.completionConfirmed===true && r.timedOut===false && r.diagnostics.length===0, `successful strict wrapper: ${p}`);
  const lines=r.stdout.split(/\r?\n/).filter(s=>s.startsWith(r.expectedCompletionMarker));
  check(lines.length===1 && /failures=0$/.test(lines[0]), `one successful terminal marker: ${p}`);
  return {path:p,sha256:artifacts.get(p).sha256,exitCode:r.exitCode,marker:lines[0],args:r.args,startedAtUtc:r.startedAtUtc,finishedAtUtc:r.finishedAtUtc};
}
function gpu(p, expectedCount) {
  const r=json(p); check(r.valid===true && r.failures.length===0, `GPU receipt valid: ${p}`);
  if (r.captures) {
    check(r.captures.length===expectedCount, `capture count ${expectedCount}: ${p}`);
    check(new Set(r.captures.map(c=>c.image)).size===expectedCount, `unique capture filenames: ${p}`);
    for (const c of r.captures) artifact(`${path.posix.dirname(p)}/${c.image}`,c.image_sha256);
    if (r.readback?.file) artifact(`${path.posix.dirname(p)}/${r.readback.file}`,r.readback.sha256);
  }
  return r;
}
function pair(a,b,label) {
  check(a.captures.length===b.captures.length, `${label}: equal inventory`);
  for (let i=0;i<a.captures.length;i++) {
    const x=a.captures[i],y=b.captures[i];
    check(x.tick===y.tick && x.time===y.time && same(x.native_ship,y.native_ship) && x.ship_sha256===y.ship_sha256 && same(x.camera_transform,y.camera_transform) && same(x.camera_projection,y.camera_projection), `${label}: actual ship/camera/time frame ${i}`);
  }
  return {frames:a.captures.length,sameNativeShip:true,sameDeclaredShipDigest:true,sameCameraTransform:true,sameCameraProjection:true,sameAcceptedTime:true};
}
function suite(p) {
  const r=json(p); check(r.summary.passedAll===true && r.summary.failed===0, `headless suite passed: ${p}`);
  const runs=r.runs.map(v=>{
    const line=v.stdout.split(/\r?\n/).find(s=>/assertions=\d+/.test(s));
    check(v.passed===true && v.exitCode===0 && !v.timedOut && !!line && /failures=0/.test(line), `test completion: ${v.test}`);
    return {test:v.test,assertions:Number(line.match(/assertions=(\d+)/)[1]),failures:0};
  });
  return {path:p,sha256:artifacts.get(p).sha256,selected:r.summary.selected,runs,startedAtUtc:r.startedAtUtc,finishedAtUtc:r.finishedAtUtc};
}

const numerical=gpu(`${base}/interactive-field-gpu-4/GPU_VERIFY.json`);
check(numerical.receipts.length===9,'numerical GPU has nine receipts');
for (const receipt of numerical.receipts) {
  artifact(`${base}/interactive-field-gpu-4/${receipt.label}.rgba32f`,receipt.sha256);
  artifact(`${base}/interactive-field-gpu-4/${receipt.label}.exr`);
  check(receipt.diagnostics.ready && receipt.diagnostics.dropped_steps===0,'numerical published state/no dropped steps: '+receipt.label);
}
const numericalLabels=Object.fromEntries(numerical.receipts.map(r=>[r.label,r]));
check(numericalLabels['01-impulse'].sha256===numericalLabels['02-duplicate'].sha256,'duplicate leaves raw GPU state identical');
check(numericalLabels['05-rewind-reset'].max_abs_height===0 && numericalLabels['05-rewind-reset'].foam_sum===0,'rewind zeroes field');
check(numericalLabels['07-stopped-decay'].foam_sum<numericalLabels['06-dual-foam'].foam_sum,'stopped foam sum decays');
check(numericalLabels['08-dry-mask'].diagnostics.land_masked===true,'numerical mask enabled');

const review=json(`${base}/interactive-lab-2/REVIEW_SUMMARY.json`);
check(review.rows.length===10,'lab2 has ten declared scenarios');
const lab2={};
for (const row of review.rows) {
  const p=`${base}/interactive-lab-2/${row.name}/GPU_VERIFY.json`,r=gpu(p,row.frames);
  check(Math.abs(r.final.time-row.seconds)<1e-9,'lab2 accepted final time: '+row.name);
  if(r.mode==='field') check(r.captures.every(c=>c.field_bound && c.field_status==='ready' && c.field.dropped_steps===0),'lab2 real field ready/no dropped steps: '+row.name);
  lab2[row.name]={receipt:r,path:p,frames:r.captures.length,time:r.final.time,kind:r.options.kind,mode:r.mode,scenario:r.options.scenario,camera:r.options.camera_mode,maxHeightM:r.readback?.max_abs_height_m??null,maxFoam:r.readback?.max_foam??null};
}
const lab2Pair=pair(lab2['source-cruise'].receipt,lab2.cruise.receipt,'lab2 cruise pair');
const lab3Source=gpu(`${base}/interactive-lab-3/source/GPU_VERIFY.json`,97);
const lab3Field=gpu(`${base}/interactive-lab-3/field/GPU_VERIFY.json`,97);
const lab3Pair=pair(lab3Source,lab3Field,'lab3 projected pair');
for (const r of [lab3Source,lab3Field]) check(r.captures.every(c=>c.carrier.mode==='projected' && c.carrier.resolution===80 && c.carrier.vertices===6561 && c.carrier.indices===38400),'lab3 actual production80 carrier');
check(lab3Field.captures.every(c=>c.field_bound && c.field_status==='ready' && c.field.dropped_steps===0 && Math.abs(c.field.time-c.field_requested_time)<1e-6),'lab3 published accepted time and zero dropped steps');
check(json(`${base}/interactive-lab-3/PAIR_VERIFY.json`).valid===true,'existing lab3 pair receipt also valid');

const production={};
const expectedLabels=['01-start','02-cruise-4s','03-cruise-12s','04-turn-8s','05-stop-10s','06-quality-paused'];
for (const mode of ['baseline','candidate','default','final']) {
  const p=`${base}/interactive-production-1/${mode}/GPU_VERIFY.json`,r=gpu(p,6);
  check(same(r.captures.map(c=>c.label),expectedLabels),'production complete stages: '+mode);
  check(same(r.captures.map(c=>c.time),[0,4,12,20,30,30]),'production accepted stage times: '+mode);
  check(r.baseline===(mode==='baseline') && r.candidate_opt_in===(mode==='candidate'),'actual baseline/opt-in selection: '+mode);
  if(mode!=='baseline') for(const c of r.captures) {
    check(c.field.bound===true && c.field.covered.includes(c.player_id) && c.field.covered.length<=3 && c.field.field.land_masked===true && c.field.field.dropped_steps===0 && c.mask.valid===true,'production bound/player/mask/no dropped steps: '+mode+'/'+c.label);
    check(c.source_visible.player===false,'covered player source suppressed: '+mode+'/'+c.label);
    if(mode==='final')check(Array.isArray(c.shadow?.errors) && c.shadow.errors.length===0 && c.shadow.casterAdapter.errors.length===0 && c.shadow.gpu.error==='','final joint-render shadow diagnostics clean: '+c.label);
  }
  const stopped=r.captures[4],quality=r.captures[5];
  check(stopped.physics_sha256===quality.physics_sha256 && same(stopped.ship_states,quality.ship_states) && stopped.camera===quality.camera,'quality change preserves accepted ship/camera: '+mode);
  if(mode!=='baseline')check(stopped.field.field.tick===1800 && quality.field.field.tick===1800 && stopped.field.field.total_steps===1800 && quality.field.field.total_steps===1800 && stopped.field.field.resets===quality.field.field.resets,'quality change preserves1800 field steps without reset: '+mode);
  production[mode]={receipt:r,path:p,frames:r.captures.length,candidateOptIn:r.candidate_opt_in,stages:r.captures.map(c=>({label:c.label,time:c.time,bound:c.field.bound??false,covered:c.field.covered,landMasked:c.field.field?.land_masked??false,droppedSteps:c.field.field?.dropped_steps??null,fieldTick:c.field.field?.tick??null,fieldTotalSteps:c.field.field?.total_steps??null,sourceVisible:c.source_visible,mask:c.mask,shadow:c.shadow?{backend:c.shadow.backend,stencilActive:c.shadow.stencilActive,errors:c.shadow.errors,casterErrors:c.shadow.casterAdapter.errors,gpuError:c.shadow.gpu.error}:null}))};
}
for(const mode of ['candidate','default','final'])for(let i=0;i<6;i++) {
  const a=production.baseline.receipt.captures[i],b=production[mode].receipt.captures[i];
  check(same(a.ship_states,b.ship_states) && a.time===b.time && a.camera===b.camera,'production recorded ship states/camera/time match baseline: '+mode+'/'+i);
}
for(let i=0;i<6;i++) {
  const a=production.default.receipt.captures[i],b=production.final.receipt.captures[i];
  check(same(a.ship_states,b.ship_states) && a.time===b.time && a.camera===b.camera,'final recorded ship/camera/time also matches previous default: '+i);
}
const wrappers=['Temp/interactive-field-gpu-4-run.json','Temp/interactive-projected-source-3-run.json','Temp/interactive-projected-field-3-run.json','Temp/interactive-production-baseline-1-run.json','Temp/interactive-production-candidate-1-run.json','Temp/interactive-production-default-1-run.json','Temp/interactive-production-final-r1-run.json'].map(wrapper);
for(const w of wrappers.filter(w=>/production-(?:default|final)-/.test(w.path)))check(!w.args.includes('--candidate') && !w.args.includes('--baseline'),'ordinary default wrapper has no opt-in/baseline flag: '+w.path);
const tests=['Temp/interactive-wake-final-components.json','Temp/interactive-wake-final-catalog-2.json','Temp/interactive-wake-delivery-laboratory-ui.json','Temp/interactive-wake-delivery-laboratory-entry.json'].map(suite);
const systemArchive=json(`${base}/delivery-2026-10-14/system-contract.json`);
check(systemArchive.sourceFreezeHeld===true && systemArchive.summary.passedAll===true && systemArchive.runs[0].stdout.includes('assertions=62 failures=0'),'fresh archived system62/0 with before/after source freeze');
artifact(systemArchive.originalReceipt.path,systemArchive.originalReceipt.sha256);
for(const [p,digest] of Object.entries(systemArchive.sources))artifact(p,digest);
const frozenWakeSources={};
for(const p of ['game/presentation/water/wake_trails.gd','modules/scene_engine/water/interactive_wake_system.gd','modules/scene_engine/water/interactive_wake_field.gd','modules/scene_engine/water/interactive_wake_field_rd.gd','modules/scene_engine/water/interactive_wake_foam.glsl','modules/scene_engine/water/interactive_wake_height.glsl','modules/scene_engine/water/ship_water_interaction.gd','modules/scene_engine/water/source_surface.gd','modules/scene_engine/water/source_wake_renderer.gd','modules/scene_engine/water/terrain_wet_mask.gd','modules/scene_engine/ocean/interactive_wake_surface.gdshaderinc']) {
  const entry=artifact(p,production.default.receipt.sources[p]);check(entry.sha256===production.final.receipt.sources[p],'wake source unchanged in final joint run: '+p);frozenWakeSources[p]=entry.sha256;
}
const initialDelivery=`${base}/delivery-2026-10-14/DELIVERY_VERIFY.initial.json`;
artifact(initialDelivery);
artifact(`${base}/delivery-2026-10-14/interactive-wake-delivery.initial.md`);
artifact(`${base}/delivery-2026-10-14/verify-interactive-wake-delivery.initial.mjs`);

for(const p of [`${base}/2026-10-14-fallback-eligibility/manifest.json`,`${base}/2026-10-14-t2-water-interaction/manifest.json`,`${base}/2026-10-14-world-wet-mask/manifest.json`,`${base}/2026-10-14-t2-field-review/manifest.json`]) {
  const r=json(p),dir=path.posix.dirname(p);
  for(const [name,record] of Object.entries(r.files??{}))artifact(`${dir}/${name}`,record.sha256);
  for(const record of r.artifacts??[])artifact(`${dir}/${record.path}`,record.sha256);
}
const legacy=[`${base}/20261014-gpu-2/baseline-cruise/GPU_VERIFY.json`,`${base}/interactive-field-gpu-1/GPU_VERIFY.json`].map(p=>{const r=json(p);check(r.valid===false && r.failures.length>0,'historical failed run retained: '+p);return{path:p,valid:r.valid,failures:r.failures};});
artifact(`${base}/20261014-gpu-2/candidate-close/GPU_VERIFY.json`);
artifact('docs/superpowers/plans/playable-voyage-work/t3-interactive-field-lab-report.md');
artifact('Temp/research/interactive-system-reset-failure-green.json');
const catalog=json('assets/research/catalog.json'),topic=catalog.topics.find(t=>t.id==='wake-flow');
check(topic?.status==='integrated' && topic.demo==='wake-flow','current wake-flow catalog integrated and reachable');
for(const reference of [topic.paper,...topic.sources,...topic.evidence])artifact(reference);
for(const p of ['game/presentation/world/naval_world_view.gd','game/presentation/water/wake_trails.gd','modules/scene_engine/water/source_surface.gd','modules/scene_engine/water/source_wake_renderer.gd','modules/scene_engine/water/interactive_wake_system.gd','modules/scene_engine/water/interactive_wake_field.gd','modules/scene_engine/ocean/projected_ocean.gd','modules/scene_engine/ocean/interactive_wake_surface.gdshaderinc'])artifact(p);
artifact('tools/verify-interactive-wake-delivery.mjs');
const deliveryDoc='docs/research/interactive-wake-delivery-2026-10-14.md';
if(fs.existsSync(full(deliveryDoc))) {
  artifact(deliveryDoc);
  const content=fs.readFileSync(full(deliveryDoc),'utf8');
  for(const match of content.matchAll(/\]\(([^)]+)\)/g)) {
    const target=path.posix.normalize(path.posix.join(path.posix.dirname(deliveryDoc),match[1]));
    check(fs.existsSync(full(target)) || (process.argv.includes('--write') && target===output),'delivery document link exists: '+target);
  }
} else if(process.argv.includes('--write'))check(false,'delivery document must exist before publication');
const pngs=[...artifacts.values()].filter(a=>a.path.endsWith('.png'));
const strip=({receipt,...rest})=>rest;
const result={schemaVersion:1,topic:'wake-flow',recordType:'delivery-evidence-audit',verifiedAtUtc:new Date().toISOString(),valid:failures.length===0,assertions,failures,
  scope:'Existing evidence integrity + narrow fresh headless laboratory UI/entry. No GPU rerun, whole-tree-green, whole-game completion or full-game FPS claim.',
  visualAcceptance:{source:'Root inspected actual PNGs; human feedback relayed by root in this task',feedback:'好很多',finalJointRunReview:'Root inspected final cruise/turn/stop PNGs: dual wakes retained and long black line gone.',independentVisualReplayByThisAudit:false},
  numerical:{manifest:`${base}/interactive-field-gpu-4/GPU_VERIFY.json`,gpu:numerical.gpu,renderer:numerical.renderer,receipts:numerical.receipts.map(r=>({label:r.label,time:r.diagnostics.time,sha256:r.sha256,maxAbsHeightM:r.max_abs_height,foamSum:r.foam_sum,droppedSteps:r.diagnostics.dropped_steps})),foamDecayFraction:1-numericalLabels['07-stopped-decay'].foam_sum/numericalLabels['06-dual-foam'].foam_sum,publicationChecks:numerical.publication_checks},
  lab2:{runs:Object.values(lab2).map(strip),frames:Object.values(lab2).reduce((s,r)=>s+r.frames,0),cruisePair:lab2Pair,limitation:'Historical finite PlaneMesh matrix; side edge discovered and superseded by lab3 projected carrier.'},
  lab3:{pair:lab3Pair,frames:194,carrier:lab3Field.final.carrier,fieldReadback:lab3Field.readback,sourceManifest:`${base}/interactive-lab-3/source/GPU_VERIFY.json`,fieldManifest:`${base}/interactive-lab-3/field/GPU_VERIFY.json`},
  production:Object.fromEntries(Object.entries(production).map(([k,v])=>[k,strip(v)])),wrappers,tests,systemArchive:`${base}/delivery-2026-10-14/system-contract.json`,frozenWakeSources,catalogTopic:topic,legacyFailures:legacy,supersedes:{path:initialDelivery,sha256:artifacts.get(initialDelivery).sha256},
  limits:['At most3 nearby safe-field ships; production captures cover player, with distant fisher/merchant retaining source fallback.','World wet mask in production evidence is511 samples with approximately4.868493m x3.581213m cells; not exact shoreline, pier or small-rock hydrodynamics.','Local96m/256 field is one-way ship-to-water presentation, not a full fluid or buoyancy solver.','Lab/prod captured fixed-time GPU sequences are not live whole-game FPS measurements.','Final joint render is included; the broader shadow investigation remains separately reported.'],
  statistics:{pngFiles:pngs.length,pngBytes:pngs.reduce((s,a)=>s+a.bytes,0),artifacts:[...artifacts.values()].length},artifacts:[...artifacts.values()].sort((a,b)=>a.path.localeCompare(b.path))};
console.log(JSON.stringify({valid:result.valid,assertions,failures,statistics:result.statistics,lab2:result.lab2.runs,lab3:result.lab3.pair,foamDecayFraction:result.numerical.foamDecayFraction,tests:tests.map(t=>({path:t.path,runs:t.runs}))},null,2));
if(process.argv.includes('--write') || process.argv.includes('--refresh-final')) {
  const refresh=process.argv.includes('--refresh-final');
  if(refresh) {
    if(!fs.existsSync(full(output)) || hash(fs.readFileSync(full(output)))!==artifacts.get(initialDelivery).sha256)throw new Error('Final refresh requires the unchanged archived initial delivery receipt.');
  } else if(fs.existsSync(full(output)))throw new Error('Delivery manifest already exists; use the default read-only audit.');
  if(failures.length)throw new Error('Refusing to publish a failed delivery audit.');
  fs.writeFileSync(full(output),JSON.stringify(result,null,2)+'\n',{flag:refresh?'w':'wx'});
  console.log(`INTERACTIVE_WAKE_DELIVERY artifacts=${result.statistics.artifacts} pngs=${pngs.length} failures=0`);
}
process.exitCode=failures.length?1:0;
