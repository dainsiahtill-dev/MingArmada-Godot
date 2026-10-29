import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync, readFileSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';

// Research-only witness. A new directory/profile is required for every run.
const [runId, ...tests] = process.argv.slice(2);
if (!/^[a-z0-9-]+$/.test(runId || '') || !tests.length || tests.some(x => !/^[a-z0-9_]+$/.test(x))) throw new Error('Expected unique run ID and test names');
const dest = resolve('docs/research/evidence/broadside-receipt-readability', runId);
if (existsSync(dest)) throw new Error('Evidence exists: ' + dest);
mkdirSync(join(dest, 'profile', 'roaming'), {recursive: true});
mkdirSync(join(dest, 'profile', 'local'), {recursive: true});
const env = {...process.env, APPDATA: join(dest, 'profile', 'roaming'), LOCALAPPDATA: join(dest, 'profile', 'local')};
const exe = 'C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe';
// Declared direct sources only; not a recursive freeze of the engine/project.
const source = ['tools/research/run_broadside_receipt_cpu.mjs','game/research/catalog.gd','assets/research/catalog.json','assets/research/papers/broadside-receipt-readability.md', 'game/research/demos/broadside_receipt_experiment.gd', 'game/research/demos/broadside_receipt_projection.gd','modules/naval_simulation/encounter.gd','modules/naval_simulation/combat/cannon_system.gd','game/runtime/mingqi_runtime.gd','game/scenes/mingqi/mingqi_scene.gd', ...tests.map(t => 'tests/'+t+'.gd')];
const digest = p => existsSync(p) ? createHash('sha256').update(readFileSync(p)).digest('hex') : null;
const original = JSON.parse(readFileSync('docs/migration/evidence/opening-story/gameplay-current-20261027/original-slots-before.json','utf8'));
const slots = () => Object.fromEntries(Object.entries(original.slots).map(([name,old]) => { const file=join(original.directory,name); const hash=digest(file); return [name,{exists:hash!==null,sha256:hash || '',match:(hash!==null)===old.exists && (hash || '')===old.sha256}]; }));
const slotsBefore=slots();
const before = Object.fromEntries(source.map(p => [p,digest(p)]));
const records = [];
for (const test of tests) {
  const args = ['--headless','--path',resolve('.'),'--script',`res://tests/${test}.gd`];
  const start = new Date().toISOString();
  const r = spawnSync(exe,args,{env,encoding:'utf8',timeout:120000,maxBuffer:1024*1024*8});
  const out = (r.stdout || '') + (r.stderr || '');
  const log = `${test}.log`;
  writeFileSync(join(dest,log),out,{flag:'wx'});
  records.push({test,start,end:new Date().toISOString(),args,exitCode:r.status,signal:r.signal,error:r.error?.message || '',log,logSha256:digest(join(dest,log)),markers:out.split(/\r?\n/).filter(s => /assertions=/.test(s)),engineError:/^(?:SCRIPT )?ERROR:/m.test(out)});
  process.stdout.write(out);
}
const after = Object.fromEntries(source.map(p => [p,digest(p)]));
const slotsAfter=slots();
writeFileSync(join(dest,'manifest.json'),JSON.stringify({scope:'isolated headless CPU research; no GPU or gameplay; direct source list only, not a complete dependency freeze',runId,exe,exeSha256:digest(exe),appdata:env.APPDATA,localappdata:env.LOCALAPPDATA,slotBaseline:'docs/migration/evidence/opening-story/gameplay-current-20261027/original-slots-before.json',slotsBefore,slotsAfter,sourceBefore:before,sourceAfter:after,records},null,2),{flag:'wx'});
if (records.some(r => r.exitCode !== 0 || r.engineError || r.markers.length !== 1 || !/failures=0\s*$/.test(r.markers[0])) || JSON.stringify(before)!==JSON.stringify(after) || Object.values(slotsBefore).some(x=>!x.match) || Object.values(slotsAfter).some(x=>!x.match)) process.exitCode = 1;
