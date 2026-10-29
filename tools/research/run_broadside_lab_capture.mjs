import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync, createWriteStream, readdirSync } from 'node:fs';
import { resolve, join, dirname, relative, isAbsolute, sep } from 'node:path';
import { pathToFileURL } from 'node:url';

export const validRunId = id => typeof id === 'string' && /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(id) && id.length <= 72;
export function strictlyInside(path, parent) {
  const rel = relative(resolve(parent), resolve(path));
  return rel !== '' && rel !== '..' && !rel.startsWith('..'+sep) && !isAbsolute(rel);
}
const hash = path => existsSync(path) ? createHash('sha256').update(readFileSync(path)).digest('hex') : null;
const writeNew = (path, value) => writeFileSync(path, JSON.stringify(value,null,2), {flag:'wx'});
const sorted = value => Array.isArray(value) ? value.map(sorted) : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map(k=>[k,sorted(value[k])])) : value;
const canonical = value => JSON.stringify(sorted(value));
export const fixtureHash = fixture => createHash('sha256').update(canonical(fixture)).digest('hex');

export function auditTimeline(report) {
  const errors=[];
  if (!report || !Array.isArray(report.fixture) || !Array.isArray(report.captures)) return ['missing fixture or captures'];
  if (report.fixtureSha256!==fixtureHash(report.fixture)) errors.push('fixture hash mismatch');
  const expectedEvents=[[4,'e1','fire'],[8,'e2','fire'],[12,'e3','fire'],[14,'e4','fire'],[16,'e5','hit'],[20,'e6','splash']];
  if (canonical(report.fixture.map(r=>[r.tick,r.event?.id,r.event?.type]))!==canonical(expectedEvents)) errors.push('fixture event sequence differs from registered study');
  if (report.captures.length!==452 || report.comparisons!==226 || report.fixedStep!==1/32 || report.lastTick!==112 || !report.valid) errors.push('wrong sequence extent or invalid report');
  const frames=new Map();
  for (const f of report.captures) {
    if (!Array.isArray(f.viewport) || !f.snapshot || !Number.isInteger(f.tick) || f.tick<0 || f.tick>112 || !['baseline','candidate'].includes(f.variant)) {errors.push('invalid frame metadata');continue;}
    const key=`${f.viewport[0]}x${f.viewport[1]}:${f.variant}:${f.tick}`;
    if (frames.has(key)) errors.push(`duplicate frame ${key}`); else frames.set(key,f);
    const s=f.snapshot;
    const expected=report.fixture.filter(row=>row.tick===f.tick).map(row=>row.event);
    if (canonical(f.events)!==canonical(expected) || s.fixture_events!==report.fixture.filter(row=>row.tick<=f.tick).length) errors.push(`event trace mismatch ${key}`);
    if (f.time!==f.tick/32 || s.tick!==f.tick || s.time!==f.time || s.step_seconds!==1/32 || s.camera_mode!=='fixed' || s.paused!==true || !s.ready || s.parameters?.candidate_enabled!==(f.variant==='candidate') || s.parameters?.paused!==true) errors.push(`clock or state mismatch ${key}`);
    if (f.variant==='baseline' ? s.visible_receipt!=='' : s.visible_receipt!==s.receipt?.text) errors.push(`visible receipt mismatch ${key}`);
    const layout=f.layout;
    const fits = r => Array.isArray(r) && r.length===4 && r.every(Number.isFinite) && r[0]>=0 && r[1]>=0 && r[2]>=0 && r[3]>=0 && r[0]+r[2]<=layout.viewport[0] && r[1]+r[3]<=layout.viewport[1];
    if (!layout || !Array.isArray(layout.viewport) || layout.viewport.length!==2 || !layout.viewport.every(x=>Number.isFinite(x)&&x>0) || !fits(layout.paintedBounds) || !Array.isArray(layout.labels) || layout.labels.length!==3 || !layout.labels.every(fits)) errors.push(`clipped or missing layout ${key}`);
  }
  for (const [w,h] of [[1600,900],[1280,720]]) {
    for (let tick=0;tick<=112;tick++) {
      const a=frames.get(`${w}x${h}:baseline:${tick}`), b=frames.get(`${w}x${h}:candidate:${tick}`);
      if (!a || !b) {errors.push(`missing pair ${w}x${h}:${tick}`);continue;}
      for (const key of ['tick','time','step_seconds','fixture_events','receipt','naive_text']) if (canonical(a.snapshot[key])!==canonical(b.snapshot[key])) errors.push(`paired state differs ${w}x${h}:${tick}:${key}`);
      if (canonical(a.layout)!==canonical(b.layout)) errors.push(`paired layout differs ${w}x${h}:${tick}`);
    }
    const at=t=>frames.get(`${w}x${h}:candidate:${t}`)?.snapshot?.visible_receipt;
    if (at(16)!=='右舷命中 · 敌船倭船' || at(20)!==at(16) || at(112)!=='') errors.push(`expected hit, mixed and expiry states missing ${w}x${h}`);
  }
  return errors;
}

async function run() {
  const [mode,id,...extra] = process.argv.slice(2);
  if (!['--guard','--gpu'].includes(mode) || !validRunId(id) || extra.length) throw new Error('Usage: --guard|--gpu <new-lowercase-run-id>');
  if (!existsSync('project.godot')) throw new Error('Run from the project root');
  const root = realpathSync(resolve('docs/research/evidence/broadside-receipt-readability'));
  const dest = join(root,id);
  if (!strictlyInside(dest,root)) throw new Error('Output escapes evidence root');
  // Atomic exclusive create: an existing run is never opened or overwritten.
  mkdirSync(dest);
  const profile = join(dest,'profile'); const app = join(profile,'roaming'); const local = join(profile,'local');
  mkdirSync(profile); mkdirSync(app); mkdirSync(local);
  if (!strictlyInside(realpathSync(profile),realpathSync(dest))) throw new Error('Profile escaped run');
  const old = JSON.parse(readFileSync('docs/migration/evidence/opening-story/gameplay-current-20261027/original-slots-before.json','utf8'));
  const originalAppdata = dirname(dirname(dirname(old.directory)));
  if (strictlyInside(profile,originalAppdata) || strictlyInside(originalAppdata,profile) || resolve(profile).toLowerCase() === resolve(originalAppdata).toLowerCase()) throw new Error('Original profile overlap');
  const snapshot = () => Object.fromEntries(Object.entries(old.slots).map(([name,b]) => {const h=hash(join(old.directory,name));return [name,{exists:h!==null,sha256:h||'',matchesHistoricalBaseline:(h!==null)===b.exists&&(h||'')===b.sha256}]}));
  const before = snapshot();
  const source = ['project.godot','game/scenes/main/main_scene.tscn','game/scenes/main/main_scene.gd','game/runtime/game_router.gd','game/ui/menu/main_menu.gd','game/research/laboratory.gd','game/research/catalog.gd','game/research/paper_reader.gd','game/research/parameter_panel.gd','game/ui/shared/parchment_theme.gd','game/ui/shared/maritime_art_theme.gd','game/ui/shared/painted_window_style.gd','assets/ui/ming_maritime/painted/quiet/runtime/command-panel.png','assets/ui/ming_maritime/painted/quiet/runtime/command-panel.png.import','assets/ui/ming_maritime/painted/quiet/framed/runtime/command-panel.png','assets/ui/ming_maritime/painted/quiet/framed/runtime/command-panel.png.import','assets/research/catalog.json','assets/research/papers/broadside-receipt-readability.md','game/research/demos/broadside_receipt_experiment.gd','game/research/demos/broadside_receipt_projection.gd','tools/research/broadside_capture_contract.gd','tools/research/capture_broadside_lab_gpu.gd','tools/research/run_broadside_lab_capture.mjs','tests/test_broadside_capture_guards.gd','tests/test_broadside_capture_entry.gd','tests/test_broadside_receipt_layout.gd','tests/test_broadside_capture_launcher.mjs'];
  const sourceBefore = Object.fromEntries(source.map(p=>[p,hash(p)]));
  if (Object.values(sourceBefore).some(h=>h===null)) throw new Error('A declared source is missing');
  const exe = 'C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe';
  const output = join(dest,'frames');
  const resourceOutput = `res://docs/research/evidence/broadside-receipt-readability/${id}/frames`;
  const env = {...process.env,APPDATA:app,LOCALAPPDATA:local,BROADSIDE_PROFILE_ROOT:profile,BROADSIDE_ORIGINAL_APPDATA:originalAppdata,BROADSIDE_CAPTURE_OUTPUT:output};
  const commands = mode === '--guard' ? [
    {label:'contract',args:['--headless','--path',resolve('.'),'--script','res://tests/test_broadside_capture_guards.gd']},
    {label:'entry',args:['--headless','--path',resolve('.'),'--script','res://tests/test_broadside_capture_entry.gd']},
    {label:'layout',args:['--headless','--path',resolve('.'),'--script','res://tests/test_broadside_receipt_layout.gd']},
    {label:'headless-rejection',args:['--headless','--path',resolve('.'),'--script','res://tools/research/capture_broadside_lab_gpu.gd','--',`--output=${resourceOutput}`]}
  ] : [{label:'gpu-capture',args:['--path',resolve('.'),'--script','res://tools/research/capture_broadside_lab_gpu.gd','--',`--output=${resourceOutput}`]}];
  const expectedGuard = {contract:/^BROADSIDE_CAPTURE_GUARDS assertions=\d+ failures=0$/,entry:/^BROADSIDE_CAPTURE_ENTRY assertions=\d+ failures=0$/,layout:/^BROADSIDE_RECEIPT_LAYOUT assertions=\d+ failures=0$/};
  writeNew(join(dest,'start.json'),{startedUtc:new Date().toISOString(),mode,id,exe,exeSha256:hash(exe),profile,app,local,originalAppdata,output,sourceBefore,originalSlotsBefore:before,scope:'Declared direct source hashes, not recursive project dependency closure; isolated registered laboratory fixture, not actual gameplay.'});
  const records=[];
  for (const command of commands) {
    const started = new Date().toISOString();
    const child = spawn(exe,command.args,{env,stdio:['ignore','pipe','pipe'],windowsHide:mode==='--guard'});
    const outputStream=createWriteStream(join(dest,`${command.label}.log`),{flags:'wx'});
    let data='';
    const collect = chunk => {data += chunk.toString(); outputStream.write(chunk);};
    child.stdout.on('data',collect); child.stderr.on('data',collect);
    writeNew(join(dest,`${command.label}-started.json`),{startedUtc:started,pid:child.pid,exe,args:command.args,profile,app,local});
    const result = await new Promise(resolveDone => {let error='';child.on('error',e=>{error=e.message;});child.on('close',(code,signal)=>resolveDone({code,signal,error}));});
    await new Promise(done=>outputStream.end(done));
    const markers = data.split(/\r?\n/).filter(s => s.startsWith('BROADSIDE_'));
    const record={...command,startedUtc:started,finishedUtc:new Date().toISOString(),pid:child.pid,...result,markers,engineError:/^(?:SCRIPT )?ERROR:/m.test(data),logSha256:hash(join(dest,`${command.label}.log`))};
    records.push(record); process.stdout.write(data);
    if (mode === '--guard' && (command.label === 'headless-rejection' ? result.code!==2 || !markers.includes('BROADSIDE_LAB_GPU_GUARD_REJECTED failures=1') || !data.includes('FAIL BROADSIDE GPU: non-headless graphics required') || existsSync(output) : result.code!==0 || !markers.some(s=>expectedGuard[command.label].test(s)))) break;
    if (mode === '--gpu' && result.code!==0) break;
  }
  const after=snapshot(); const sourceAfter=Object.fromEntries(source.map(p=>[p,hash(p)]));
  const unchanged=Object.keys(before).every(k=>before[k].exists===after[k].exists&&before[k].sha256===after[k].sha256);
  let capture=null; const imageFailures=[];
  if (mode==='--gpu' && existsSync(join(output,'capture-result.json'))) {
    const captureFile=join(output,'capture-result.json'); const report=JSON.parse(readFileSync(captureFile,'utf8'));
    imageFailures.push(...auditTimeline(report));
    const keys=new Set();
    for (const f of report.captures || []) {
      const expected=`${f.viewport[0]}x${f.viewport[1]}-${f.variant}-${String(f.tick).padStart(3,'0')}.png`;
      if (f.file!==expected || keys.has(f.file) || !['baseline','candidate'].includes(f.variant) || ![1600,1280].includes(f.viewport[0]) || f.viewport[1] !== (f.viewport[0]===1600?900:720) || f.tick<0 || f.tick>112) {imageFailures.push(`invalid frame identity ${f.file}`);continue;}
      keys.add(f.file); const full=join(output,f.file);
      if (!strictlyInside(full,output) || !existsSync(full)) {imageFailures.push(`missing ${f.file}`);continue;}
      const buf=readFileSync(full); const signature=buf.subarray(0,8).toString('hex');
      if (hash(full)!==f.sha256 || signature!=='89504e470d0a1a0a' || buf.length<24 || buf.readUInt32BE(16)!==f.viewport[0] || buf.readUInt32BE(20)!==f.viewport[1]) imageFailures.push(`invalid image bytes ${f.file}`);
    }
    const pngs=readdirSync(output).filter(f=>f.endsWith('.png'));
    if (keys.size!==452 || pngs.length!==452 || report.captures.length!==452 || report.comparisons!==226 || !report.valid) imageFailures.push('incomplete frame sequence or failed paired states');
    capture={resultSha256:hash(captureFile),fixtureSha256:report.fixtureSha256,count:keys.size,comparisons:report.comparisons,renderer:report.renderer,gpu:report.gpu,displayServer:report.displayServer,imageFailures};
  }
  const valid = records.length===commands.length && records.every(r=>!r.engineError && !r.error) && unchanged && JSON.stringify(sourceBefore)===JSON.stringify(sourceAfter) && (mode==='--guard' ? records.slice(0,3).every(r=>r.code===0 && r.markers.some(s=>expectedGuard[r.label].test(s))) && records[3].code===2 && records[3].markers.includes('BROADSIDE_LAB_GPU_GUARD_REJECTED failures=1') && !existsSync(output) : records[0].code===0 && records[0].markers.some(s=>/^BROADSIDE_LAB_GPU captures=452 comparisons=226 failures=0$/.test(s)) && capture!==null && imageFailures.length===0);
  writeNew(join(dest,'process-result.json'),{finishedUtc:new Date().toISOString(),valid,records,sourceBefore,sourceAfter,originalSlotsBefore:before,originalSlotsAfter:after,originalSlotsUnchanged:unchanged,capture,scope:'Graphics, when run, concern fixed registered laboratory fixture only; no real player input, main game, FPS or enjoyment claim. Direct source list is not a complete recursive freeze.'});
  if (!valid) process.exitCode=1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) run().catch(e=>{console.error(e.stack||e);process.exitCode=1;});
