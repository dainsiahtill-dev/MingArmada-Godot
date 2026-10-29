import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync, readdirSync, realpathSync } from 'node:fs';
import { resolve, join, relative, isAbsolute, sep } from 'node:path';
import { pathToFileURL } from 'node:url';
import { pngFramebuffer } from './run_crew_battle_gpu.mjs';

const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const hash = file => digest(readFileSync(file));
const writeNew = (file, value) => writeFileSync(file, JSON.stringify(value, null, 2) + '\n', { flag: 'wx' });
const inside = (file, parent) => { const p = relative(resolve(parent), resolve(file)); return p !== '' && p !== '..' && !p.startsWith('..' + sep) && !isAbsolute(p); };
const finite = value => typeof value === 'number' && Number.isFinite(value);
const near = (a, b) => finite(a) && finite(b) && Math.abs(a - b) <= 1e-6;
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
export function auditTimeline(report) {
 const errors=[];
 if(!report?.valid || report.failures?.length || !report.audioMuted || report.cases?.length!==3 || report.captures?.length<540) errors.push('incomplete GPU cargo proof');
 const images=new Map((report.captures||[]).map(x=>[x.file,x]));
 for(const id of ['wood-combat','porcelain-combat']) {
  const c=report.cases?.find(x=>x.id===id), rows=(report.sequences||[]).filter(x=>x.case===id);
  if(!c?.airborne||!c?.floating||!c?.pause||!(c?.lost>0)||!(c?.splash_count>0)||rows.length!==271)errors.push(id+': missing phase proof');
  if(id==='porcelain-combat'&&!c?.sinking)errors.push('porcelain did not sink');
  for(let i=0;i<rows.length;i++) {
   const row=rows[i], state=images.get(row.file)?.snapshot;
   if(row.sample!==i||row.tick!==i*4||row.steps!==(i?4:0)||!state?.ready||!state.paused||state.tick!==row.tick||state.cargo?.errors?.length)errors.push(id+': sequence/state mismatch '+i);
   for(const lot of state?.cargo?.floating||[]) {
    const drop=state.drops.find(d=>d.dropId===lot.dropId);
    if(!drop||drop.goodId!==lot.goodId||drop.quantity!==lot.quantity||!lot.position.every(Number.isFinite))errors.push(id+': unbacked lot');
   }
  }
 }
 return errors;
}
function snapshotTree(directory) {
  const result = {};
  const visit = (dir, prefix = '') => {
    if (!existsSync(dir)) return;
    for (const entry of readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const file = join(dir, entry.name), key = prefix + entry.name;
      if (entry.isDirectory()) visit(file, key + '/');
      else if (entry.isFile()) result[key] = hash(file);
      else result[key] = 'non-regular-entry';
    }
  };
  visit(directory);
  return result;
}

const SOURCES = [
  "game/presentation/combat/combat_atmosphere.gd",
  "assets/textures/combat_atmosphere/r1/smoke-puff.png",
  "assets/textures/combat_atmosphere/r1/flame.png",
  "project.godot",
  "game/scenes/main/main_scene.tscn",
  "game/scenes/main/main_scene.gd",
  "game/runtime/game_router.gd",
  "game/ui/menu/main_menu.gd",
  "game/research/laboratory.gd",
  "game/research/catalog.gd",
  "assets/research/catalog.json",
  "game/research/demos/cargo_deck_drift_experiment.gd",
  "game/presentation/cargo/cargo_world_view.gd",
  "game/presentation/cargo/cargo_deck_view.gd",
  "game/presentation/cargo/cargo_models.gd",
  "game/presentation/cargo/cargo_drift.gd",
  "game/domain/mingqi/cargo_damage.gd",
  "game/presentation/world/naval_world_view.gd",
  "game/presentation/ships/ship_view.gd",
  "game/presentation/combat/combat_effects.gd",
  "modules/naval_simulation/encounter.gd",
  "modules/contracts/wave_descriptor.gd",
  "assets/models/cargo_pack/r1/manifest.json",
  "tools/research/capture_cargo_deck_gpu.gd",
  "tools/research/run_cargo_deck_gpu.mjs",
  "assets/models/cargo_pack/r1/grain.glb",
  "assets/models/cargo_pack/r1/water.glb",
  "assets/models/cargo_pack/r1/wood.glb",
  "assets/models/cargo_pack/r1/iron.glb",
  "assets/models/cargo_pack/r1/powder.glb",
  "assets/models/cargo_pack/r1/cloth.glb",
  "assets/models/cargo_pack/r1/silk.glb",
  "assets/models/cargo_pack/r1/porcelain.glb",
  "assets/models/cargo_pack/r1/tea.glb",
  "assets/models/cargo_pack/r1/sugar.glb",
  "assets/models/cargo_pack/r1/salt.glb",
  "assets/models/cargo_pack/r1/spices.glb"
];

async function run() {
  const [mode, id, ...extra] = process.argv.slice(2);
  if (!['--gpu', '--guard'].includes(mode) || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(id || '') || id.length > 72 || extra.length) throw new Error('Usage: rtk proxy node tools/research/run_cargo_deck_gpu.mjs --gpu|--guard <fresh-run-id>');
  if (!existsSync('project.godot')) throw new Error('Run from project root');
  const root = resolve('.'), evidence = resolve('docs/research/evidence/cargo-deck-drift');
  mkdirSync(evidence, { recursive: true });
  const canonicalEvidence = realpathSync(evidence), dest = join(canonicalEvidence, id);
  if (!inside(dest, canonicalEvidence)) throw new Error('Output outside topic');
  mkdirSync(dest);
  const profile = join(dest, 'profile'), app = join(profile, 'roaming'), local = join(profile, 'local'), output = join(dest, 'frames');
  mkdirSync(app, { recursive: true }); mkdirSync(local);
  const originalAppdata = process.env.APPDATA;
  if (!originalAppdata || inside(profile, originalAppdata) || inside(originalAppdata, profile) || resolve(profile).toLowerCase() === resolve(originalAppdata).toLowerCase()) throw new Error('Invalid original profile or overlap');
  const originalUserdir = join(originalAppdata, 'Godot', 'app_userdata', 'MingArmada');
  const originalBefore = snapshotTree(originalUserdir), sourceBefore = Object.fromEntries(SOURCES.map(p => [p, hash(p)]));
  const exe = process.env.GODOT_EXE || 'C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe';
  const env = { ...process.env, APPDATA: app, LOCALAPPDATA: local, CARGO_DECK_PROFILE_ROOT: profile, CARGO_DECK_ORIGINAL_APPDATA: originalAppdata, CARGO_DECK_CAPTURE_OUTPUT: output };
  const args = [...(mode === '--guard' ? ['--headless'] : []), '--path', root, '--script', 'res://tools/research/capture_cargo_deck_gpu.gd', '--', `--output=res://docs/research/evidence/cargo-deck-drift/${id}/frames`];
  writeNew(join(dest, 'start.json'), { startedUtc: new Date().toISOString(), mode, id, exe, exeSha256: hash(exe), args, profile, app, local, originalUserdir, sourceBefore, originalBefore, timeoutSeconds: 1200, scope: 'Direct-source list and generated PNG freeze, not a recursive dependency/imported-resource freeze. Scripted actual menu/laboratory; isolated Windows userdata.' });
  console.log(`CARGO_DECK_GPU_LAUNCH mode=${mode} evidence=${dest} timeout_seconds=1200`);
  const child = spawn('rtk', ['proxy', exe, ...args], { cwd: root, env, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
  let data = '', pending = '', error = '', timedOut = false;
  const receive = chunk => {
    const text = chunk.toString(); data += text; pending += text;
    const lines = pending.split(/\r?\n/); pending = lines.pop();
    for (const line of lines) if (line.startsWith('CARGO_DECK_GPU') || /FAIL CARGO DECK GPU|SCRIPT ERROR:|\bERROR:/.test(line)) console.log(line);
  };
  child.stdout.on('data', receive); child.stderr.on('data', receive); child.on('error', value => { error = value.message; });
  const started = Date.now();
  const heartbeat = setInterval(() => console.log(`CARGO_DECK_GPU_WAIT elapsed_seconds=${Math.round((Date.now() - started) / 1000)}`), 30000);
  const timeout = setTimeout(() => { timedOut = true; if (child.pid) spawn('rtk', ['proxy', 'taskkill', '/PID', String(child.pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' }); }, 1200000);
  const result = await new Promise(done => child.on('close', (code, signal) => done({ code, signal })));
  clearTimeout(timeout); clearInterval(heartbeat);
  writeFileSync(join(dest, 'process.log'), data, { flag: 'wx' });
  const sourceAfter = Object.fromEntries(SOURCES.map(p => [p, hash(p)])), originalAfter = snapshotTree(originalUserdir);
  const sourceUnchanged = same(sourceBefore, sourceAfter), originalUnchanged = same(originalBefore, originalAfter);
  const diagnostic = /SCRIPT ERROR:|\bERROR:|\b(?:Parse|Compile) Error:|Failed to load (?:script|resource)/i.test(data);
  const errors = [];
  let capture = null;
  const reportPath = join(output, 'capture-result.json');
  if (mode === '--gpu' && existsSync(reportPath)) {
    const report = JSON.parse(readFileSync(reportPath, 'utf8'));
    errors.push(...auditTimeline(report));
    for (const image of report.captures || []) {
      if (typeof image.file !== 'string' || !/^[a-z0-9-]+\.png$/.test(image.file)) { errors.push('unsafe image path'); continue; }
      const file = join(output, image.file);
      if (!inside(file, output) || !existsSync(file)) { errors.push(`missing image ${image.file}`); continue; }
      try {
        const bytes = readFileSync(file), pixels = pngFramebuffer(bytes);
        if (digest(bytes) !== image.sha256 || !same([pixels.width, pixels.height], image.viewport) || pixels.sha256 !== image.framebuffer_sha256) errors.push(`PNG or decoded framebuffer differs ${image.file}`);
      } catch (failure) { errors.push(`${image.file}: ${failure.message}`); }
    }
    if (readdirSync(output).filter(p => p.endsWith('.png')).length !== report.captures.length) errors.push('unreported or missing PNGs');
    capture = { sha256: hash(reportPath), gpu: report.gpu, renderer: report.renderer, captures: report.captures.length, sampledFrames: report.sequences.length, acceptedSteps: report.acceptedSteps, cases: report.cases, errors };
  }
  const markers = data.split(/\r?\n/).filter(line => line.startsWith('CARGO_DECK_GPU'));
  const finalMarkers = markers.filter(line => line.startsWith('CARGO_DECK_GPU captures='));
  const pass = mode === '--guard'
    ? result.code === 2 && markers.length === 1 && markers[0] === 'CARGO_DECK_GPU_GUARD_REJECTED failures=1' && data.includes('non-headless graphics required') && !existsSync(output)
    : result.code === 0 && finalMarkers.length === 1 && /^CARGO_DECK_GPU captures=\d+ samples=\d+ accepted_steps=\d+ failures=0$/.test(finalMarkers[0]) && capture !== null && errors.length === 0;
  const valid = pass && !error && !timedOut && !diagnostic && sourceUnchanged && originalUnchanged;
  writeNew(join(dest, 'process-result.json'), { finishedUtc: new Date().toISOString(), valid, ...result, error, timedOut, diagnostic, markers, sourceBefore, sourceAfter, sourceUnchanged, originalBefore, originalAfter, originalUnchanged, capture, logSha256: hash(join(dest, 'process.log')), scope: 'Scripted real menu/laboratory, 15 GPU samples per accepted second, actual cargo quantity conservation and water-entry checks, decoded RGBA PNG checks. Direct-source freeze only. Visual quality still needs review; no manual play, game FPS or production acceptance.' });
  if (!valid) { console.error(JSON.stringify({ error, diagnostic, sourceUnchanged, originalUnchanged, errors })); process.exitCode = 1; }
  console.log(`CARGO_DECK_GPU_VALIDATION valid=${valid} evidence=${dest}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) run().catch(error => { console.error(error.stack); process.exitCode = 1; });
