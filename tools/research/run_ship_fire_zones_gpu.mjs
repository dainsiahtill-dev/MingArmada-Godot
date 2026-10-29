import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync, readdirSync, realpathSync } from 'node:fs';
import { resolve, join, relative, isAbsolute, sep } from 'node:path';
import { pathToFileURL } from 'node:url';
import { pngFramebuffer } from './run_crew_battle_gpu.mjs';
import { auditState as auditLegacyState } from './run_ship_fire_gpu.mjs';

const SCOPE = 'controlled ignition candidate; no live ballistic/campaign/production claim';
const ZONES = ['bow', 'mid', 'stern'];
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const hash = file => digest(readFileSync(file));
const writeNew = (file, value) => writeFileSync(file, JSON.stringify(value, null, 2) + '\n', { flag: 'wx' });
const inside = (file, parent) => { const p = relative(resolve(parent), resolve(file)); return p !== '' && p !== '..' && !p.startsWith('..' + sep) && !isAbsolute(p); };
const finite = value => typeof value === 'number' && Number.isFinite(value);
const near = (a, b) => finite(a) && finite(b) && Math.abs(a - b) <= 1e-6;
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const sha = value => /^[a-f0-9]{64}$/.test(value || '');
const heat = state => state?.heatByZone?.reduce((a, b) => a + b, 0);
const cold = s => ['baseline', 'candidate'].every(id => heat(s?.lanes?.[id]?.fireControl) === 0);
const finished = s => cold(s) && ['baseline', 'candidate'].every(id => s.lanes[id].reservedCrew === 0 && s.lanes[id].fireControl.transferTicks === 0) && ['living_fires', 'burning_zones', 'reserved_particles', 'active_smoke', 'active_flames', 'active_embers'].every(key => s.fire_view?.[key] === 0);
const summary = f => ({ version: 'ship-fire-r1', heat: heat(f), fuelSeconds: f.fuelSeconds, wetness: f.wetness, crewDamageCarry: f.crewDamageCarry, assignedFirefighters: f.assignedFirefighters, pendingFirefighters: f.pendingFirefighters, transferTicks: f.transferTicks, supplies: f.supplies, workCarry: f.workCarry });

export function auditState(s) {
  const errors = [], converted = structuredClone(s), view = s?.fire_view;
  if (s?.parameters?.fire_model !== 'zones' || !ZONES.includes(s?.parameters?.ignition_zone) || !['overview', 'near', 'baseline-near'].includes(s?.camera_mode)) return ['missing declared spatial fixture'];
  converted.camera_mode = s.camera_mode === 'baseline-near' ? 'near' : s.camera_mode;
  let burning = 0, living = 0;
  for (const id of ['baseline', 'candidate']) {
    const lane = s?.lanes?.[id], f = lane?.fireControl, ship = s?.visual?.ships?.find(x => x.id === id);
    const fields = ['version', 'heatByZone', 'exposureTicks', 'fuelSeconds', 'wetness', 'crewDamageCarry', 'assignedFirefighters', 'pendingFirefighters', 'transferTicks', 'supplies', 'workCarry'];
    if (!f || Object.keys(f).length !== fields.length || fields.some(k => !(k in f)) || f.version !== 'ship-fire-r2-zones' || !Array.isArray(f.heatByZone) || f.heatByZone.length !== 3 || f.heatByZone.some(x => !finite(x) || x < 0 || x > 100) || !Array.isArray(f.exposureTicks) || f.exposureTicks.length !== 3 || f.exposureTicks.some(x => !Number.isInteger(x) || x < 0 || x > 360)) { errors.push(`${id}: invalid r2 authority`); continue; }
    if (!ship || !same(ship.fireSpread, f) || !near(ship.fireControl?.heat, heat(f)) || Object.keys(summary(f)).some(k => k !== 'heat' && ship.fireControl?.[k] !== summary(f)[k])) errors.push(`${id}: read-only projections differ`);
    converted.lanes[id].fireControl = summary(f);
    if (ship) converted.visual.ships.find(x => x.id === id).fireControl = converted.lanes[id].fireControl;
    if (!Number.isInteger(lane.spreadCount) || lane.spreadCount < 0 || !Array.isArray(lane.spreadEvents) || lane.spreadEvents.length !== Math.min(lane.spreadCount, 32) || lane.spreadEvents.some(e => !ZONES.includes(e.fromZone) || !ZONES.includes(e.toZone) || Math.abs(ZONES.indexOf(e.fromZone) - ZONES.indexOf(e.toZone)) !== 1 || e.heat !== 12)) errors.push(`${id}: invalid bounded spatial ledger`);
    if (heat(f) > 0 && lane.hull > 0) living++;
    for (let index = 0; index < 3; index++) if (f.heatByZone[index] > 0 && lane.hull > 0) {
      burning++;
      const zone = ZONES[index], anchor = view?.zone_anchors?.[`${id}|${zone}`];
      if (!anchor?.available || anchor.shipId !== id || anchor.zone !== zone || !near(anchor.time, s.time) || !near(anchor.heat, f.heatByZone[index]) || !Array.isArray(anchor.position) || anchor.position.length !== 3 || !anchor.position.every(finite) || anchor.position[1] <= 0) errors.push(`${id}|${zone}: current real-deck anchor absent`);
    }
    const emission = view?.ships?.[id];
    if (!emission) errors.push(`${id}: emission budget record missing`);
    if (emission) {
      const slot = emission.last_slot, allocations = Object.values(slot?.zones || {});
      if (!Number.isInteger(emission.slot) || emission.slot < 0 || slot?.slot !== emission.slot || emission.emitted_smoke > (emission.slot + 1) * 3 || emission.emitted_flames > (emission.slot + 1) * 4) errors.push(`${id}: cumulative emission budget exceeds accepted slots`);
      if (!Number.isInteger(emission.slot) || emission.slot > Math.floor(s.time / .25) || !Number.isInteger(emission.emitted_smoke) || !Number.isInteger(emission.emitted_flames) || emission.emitted_smoke < 0 || emission.emitted_flames < 0 || !slot || slot.smoke !== 3 || slot.flame !== 4 || allocations.length < 1 || allocations.length > 3 || allocations.some(a => !Number.isInteger(a.smoke) || a.smoke < 1 || !Number.isInteger(a.flame) || a.flame < 1) || allocations.reduce((a, x) => a + x.smoke, 0) !== 3 || allocations.reduce((a, x) => a + x.flame, 0) !== 4) errors.push(`${id}: total per-ship slot budget differs from 3+4`);
    }
  }
  if (living !== view?.living_fires || burning !== view?.burning_zones || view?.capacity !== 384 || view?.draw_calls > 3 || view?.reserved_particles > 384) errors.push('zone counts or global particle budget differs');
  for (const p of view?.particles || []) if (!['baseline', 'candidate'].includes(p.ship_id) || !ZONES.includes(p.zone)) errors.push('visible particle lacks real ship and canonical zone');
  if (!errors.some(x => x.includes('invalid r2 authority'))) errors.push(...auditLegacyState(converted));
  return errors;
}

export function auditTimeline(report) {
  const errors = [];
  if (!report?.valid || report.failures?.length || report.scope !== SCOPE || !report.audioMuted || report.displayServer === 'headless' || !report.gpu || !report.renderer || report.seed !== 1661 || !near(report.fixedStep, 1 / 60) || report.ticksPerSample !== 12 || report.nominalSamplesPerAcceptedSecond !== 5 || report.maximumSamplesPerCase !== 241 || report.maximumDefaultAcceptedSeconds !== 48) errors.push('invalid hardware cadence or controlled scope');
  if (!Array.isArray(report?.captures) || !Array.isArray(report?.sequences) || !Array.isArray(report?.cases) || report.cases.length !== 4 || !Array.isArray(report?.checks)) return [...errors, 'incomplete spatial report'];
  const images = new Map();
  for (const image of report.captures) {
    if (!/^[a-z0-9-]+\.png$/.test(image.file || '') || images.has(image.file) || !sha(image.sha256) || !sha(image.framebuffer_sha256) || !sha(image.full_state_sha256) || image.framebuffer_format !== 'RGBA8' || !Array.isArray(image.viewport) || image.viewport.length !== 2 || !image.viewport.every(x => Number.isInteger(x) && x > 0)) { errors.push('invalid or duplicate PNG metadata'); continue; }
    images.set(image.file, image);
    if (image.kind !== 'menu') {
      errors.push(...auditState(image.snapshot).map(x => `${image.file}: ${x}`));
      if (image.tick !== image.snapshot?.tick || !near(image.time, image.snapshot?.time)) errors.push(`${image.file}: accepted image clock differs`);
    }
  }
  let accepted = 0;
  for (const id of ['stern', 'bow', 'mid', 'low-supplies']) {
    const c = report.cases.find(x => x.id === id), rows = report.sequences.filter(x => x.case === id);
    if (!c || rows.length < 2 || rows.length > (id === 'stern' ? 241 : 41) || c.samples !== rows.length) { errors.push(`${id}: missing sequence extent`); continue; }
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i], image = images.get(row.file), s = image?.snapshot;
      if (row.sample !== i || row.tick !== i * 12 || row.steps !== (i ? 12 : 0) || !near(row.time, row.tick / 60) || row.camera_mode !== 'overview' || image?.kind !== 'experiment' || image.case !== id || image.sample !== i || image.steps !== row.steps || image.full_state_sha256 !== row.state_sha256 || s?.tick !== row.tick || !same(row.lanes, s?.lanes) || !same(row.fire_view, s?.fire_view)) errors.push(`${id}: image/sequence mismatch ${i}`);
      if (i && row.lanes && rows[i - 1].lanes) for (const lane of ['baseline', 'candidate']) for (const key of ['workSeconds', 'suppliesSpent', 'spreadCount']) if (row.lanes[lane][key] + 1e-6 < rows[i - 1].lanes[lane][key]) errors.push(`${id}: ledger regressed ${i}`);
      if (i) for (const lane of ['baseline', 'candidate']) {
        const prev = rows[i - 1].fire_view?.ships?.[lane], next = row.fire_view?.ships?.[lane];
        if (!prev || !next) { errors.push(`${id}: cumulative emission budget record missing ${i}`); continue; }
        const slots = next.slot - prev.slot;
        if (slots < 0 || !Number.isInteger(slots) || next.emitted_smoke < prev.emitted_smoke || next.emitted_flames < prev.emitted_flames || next.emitted_smoke - prev.emitted_smoke > slots * 3 || next.emitted_flames - prev.emitted_flames > slots * 4) errors.push(`${id}: cumulative emission budget changed outside new slots ${i}`);
      }
    }
    const first = images.get(rows[0].file)?.snapshot, last = images.get(rows.at(-1).file)?.snapshot;
    const startZone = id === 'low-supplies' ? 'stern' : id;
    for (const lane of ['baseline', 'candidate']) if (!same(first?.lanes?.[lane]?.fireControl?.heatByZone, ZONES.map(z => z === startZone ? 28 : 0))) errors.push(`${id}: controlled zone start differs`);
    if (c.last_tick !== rows.at(-1).tick || !near(c.last_time, rows.at(-1).time) || !same(c.final, last)) errors.push(`${id}: final state mismatch`);
    if (id === 'stern' && (!c.completed || !c.active_pause || !c.extinguished_pause || !c.spread_pause || !finished(last) || c.last_time > 48 || last?.lanes?.baseline?.spreadCount !== 2 || last?.lanes?.candidate?.spreadCount !== 0 || !(last?.lanes?.candidate?.hull > last?.lanes?.baseline?.hull) || !(last?.lanes?.candidate?.hull < 100))) errors.push('stern full lifecycle missing');
    if (id !== 'stern' && (rows.length !== 41 || c.last_tick !== 480 || !near(c.last_time, 8))) errors.push(`${id}: eight-second interval missing`);
    if (id === 'bow' && (last?.lanes?.baseline?.spreadCount !== 1 || last?.lanes?.baseline?.fireControl?.heatByZone?.[2] !== 0)) errors.push('bow incorrectly jumped to stern');
    if (id === 'mid' && (last?.lanes?.baseline?.spreadCount !== 2 || !last?.lanes?.baseline?.fireControl?.heatByZone?.every(x => x > 0))) errors.push('mid adjacent spread missing');
    if (id === 'low-supplies' && (last?.lanes?.candidate?.fireControl?.supplies !== 0 || !(heat(last?.lanes?.candidate?.fireControl) > 0) || !(last?.lanes?.candidate?.workSeconds > 0))) errors.push('exhausted-but-burning evidence missing');
    accepted += rows.at(-1).tick;
  }
  if (accepted !== report.acceptedSteps) errors.push('accepted step total differs');
  for (const phase of ['active', 'spread', 'extinguished']) {
    const pause = report.checks.find(x => x.name === 'pause' && x.phase === phase), before = images.get(`stern-${phase}-pause-before.png`), after = images.get(`stern-${phase}-pause-after.png`);
    if (!pause?.unchanged || pause.frames !== 8 || !sha(pause.before_sha256) || pause.before_sha256 !== pause.after_sha256 || pause.before_sha256 !== before?.full_state_sha256 || pause.after_sha256 !== after?.full_state_sha256 || before?.tick !== after?.tick) errors.push(`${phase}: full-state eight-frame pause missing`);
    if (phase !== 'extinguished' && !(before?.snapshot?.fire_view?.active_flames > 0)) errors.push(`${phase}: pause has no visible flames`);
    if (phase === 'extinguished' && !cold(before?.snapshot)) errors.push('cold pause still burning');
  }
  for (const phase of ['active', 'extinguished']) {
    const pair = report.checks.find(x => x.name === 'camera_pair' && x.phase === phase), wide = images.get(pair?.overview_file), detail = images.get(pair?.near_file);
    if (!pair?.unchanged || !sha(pair.before_authority_sha256) || pair.before_authority_sha256 !== pair.after_authority_sha256 || wide?.tick !== detail?.tick || wide?.tick !== pair.tick || detail?.snapshot?.camera_mode !== 'near' || !same(wide?.snapshot?.lanes, detail?.snapshot?.lanes) || !same(wide?.snapshot?.visual, detail?.snapshot?.visual)) errors.push(`${phase}: camera authority differs`);
    if (!same(wide?.snapshot?.fire_view, detail?.snapshot?.fire_view)) errors.push(`${phase}: camera emission or presentation changed without accepted time`);
  }
  const detail = report.checks.find(x => x.name === 'baseline_detail'), wide = images.get(detail?.overview_file), close = images.get(detail?.near_file);
  if (!detail?.unchanged || !sha(detail.before_authority_sha256) || detail.before_authority_sha256 !== detail.after_authority_sha256 || wide?.tick !== close?.tick || close?.snapshot?.camera_mode !== 'baseline-near' || close?.snapshot?.fire_view?.burning_zones !== 3 || !same(wide?.snapshot?.lanes, close?.snapshot?.lanes) || !same(wide?.snapshot?.visual, close?.snapshot?.visual)) errors.push('same-tick close real-deck three-zone evidence missing');
  if (!same(wide?.snapshot?.fire_view, close?.snapshot?.fire_view)) errors.push('spread camera emission or presentation changed without accepted time');
  const reset = report.checks.find(x => x.name === 'reset_inventory');
  if (!reset?.ok || reset.before?.lanes?.candidate?.fireControl?.supplies !== 0 || reset.after?.tick !== 0 || reset.after?.lanes?.candidate?.fireControl?.supplies !== 24 || reset.after?.lanes?.candidate?.spreadCount !== 0 || reset.after?.lanes?.candidate?.suppliesSpent !== 0 || reset.after?.lanes?.candidate?.workSeconds !== 0 || !same(reset.after, images.get('reset-restored.png')?.snapshot)) errors.push('explicit reset missing');
  if (!report.checks.some(x => x.name === 'real_entry' && x.ok) || !report.checks.some(x => x.name === 'dispose' && x.released) || !images.has('menu-before.png') || !images.has('menu-returned.png')) errors.push('entry or release missing');
  return errors;
}

// Launch and evidence I/O follow the existing controlled-fire runner. The
// source list below includes both inherited capture code and this extension.
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
  visit(directory); return result;
}

const SOURCES = [
  'project.godot', 'game/scenes/main/main_scene.tscn', 'game/scenes/main/main_scene.gd',
  'game/runtime/game_router.gd', 'game/ui/menu/main_menu.gd', 'game/research/laboratory.gd',
  'game/research/catalog.gd', 'assets/research/catalog.json',
  'modules/naval_simulation/combat/fire_control.gd', 'modules/naval_simulation/combat/fire_profile.gd',
  'modules/naval_simulation/encounter.gd', 'modules/physics_engine/ocean/wave_field.gd',
  'game/presentation/combat/ship_fire_view.gd', 'game/presentation/combat/combat_atmosphere.gd',
  'game/presentation/combat/combat_effects.gd', 'game/research/demos/ship_fire_control_experiment.gd',
  'game/presentation/world/naval_world_view.gd', 'game/presentation/ships/ship_view.gd',
  'game/presentation/ships/ship_damage.gd', 'game/presentation/crew/crew_view.gd',
  'assets/textures/combat_atmosphere/r1/smoke-puff.png', 'assets/textures/combat_atmosphere/r1/flame.png',
  'tools/research/capture_ship_fire_zones_gpu.gd', 'tools/research/run_ship_fire_zones_gpu.mjs',
  'tools/research/run_crew_battle_gpu.mjs'
];
SOURCES.push('tools/research/capture_ship_fire_gpu.gd', 'tools/research/run_ship_fire_gpu.mjs', 'modules/naval_simulation/combat/fire_spread.gd', 'game/research/demos/ship_fire_zone_anchors.gd', 'game/research/demos/ship_fire_zone_view.gd', 'game/presentation/crew/deck_stations.gd');
const OPTIONAL_SOURCES = ['modules/naval_simulation/combat/fire_launcher.gd'];
const sourceSnapshot = () => Object.fromEntries([...SOURCES.map(file => [file, hash(file)]), ...OPTIONAL_SOURCES.map(file => [file, existsSync(file) ? hash(file) : null])]);

async function run() {
  const [mode, id, ...extra] = process.argv.slice(2);
  if (!['--gpu', '--guard'].includes(mode) || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(id || '') || id.length > 72 || extra.length) throw new Error('Usage: rtk proxy node tools/research/run_ship_fire_zones_gpu.mjs --gpu|--guard <fresh-run-id>');
  if (!existsSync('project.godot')) throw new Error('Run from project root');
  const root = resolve('.'), evidence = resolve('docs/research/evidence/ship-fire-control');
  mkdirSync(evidence, { recursive: true });
  const canonicalEvidence = realpathSync(evidence), dest = join(canonicalEvidence, id);
  if (!inside(dest, canonicalEvidence)) throw new Error('Output outside topic');
  mkdirSync(dest);
  const profile = join(dest, 'profile'), app = join(profile, 'roaming'), local = join(profile, 'local'), output = join(dest, 'frames');
  mkdirSync(app, { recursive: true }); mkdirSync(local);
  const originalAppdata = process.env.APPDATA;
  if (!originalAppdata || inside(profile, originalAppdata) || inside(originalAppdata, profile) || resolve(profile).toLowerCase() === resolve(originalAppdata).toLowerCase()) throw new Error('Invalid original profile or overlap');
  const originalUserdir = join(originalAppdata, 'Godot', 'app_userdata', 'MingArmada');
  const originalBefore = snapshotTree(originalUserdir), sourceBefore = sourceSnapshot();
  const exe = process.env.GODOT_EXE || 'C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe';
  const env = { ...process.env, APPDATA: app, LOCALAPPDATA: local, SHIP_FIRE_PROFILE_ROOT: profile, SHIP_FIRE_ORIGINAL_APPDATA: originalAppdata, SHIP_FIRE_CAPTURE_OUTPUT: output };
  const args = [...(mode === '--guard' ? ['--headless'] : []), '--path', root, '--script', 'res://tools/research/capture_ship_fire_zones_gpu.gd', '--', `--output=res://docs/research/evidence/ship-fire-control/${id}/frames`];
  writeNew(join(dest, 'start.json'), { startedUtc: new Date().toISOString(), mode, id, exe, exeSha256: hash(exe), args, profile, app, local, originalUserdir, sourceBefore, originalBefore, timeoutSeconds: 1200, scope: 'Direct-source and two original PNG freeze. Scripted actual Main/Laboratory, isolated APPDATA/LOCALAPPDATA; imported resources and transitive dependencies are not recursively frozen.' });
  console.log(`SHIP_FIRE_GPU_LAUNCH mode=${mode} evidence=${dest} timeout_seconds=1200`);
  const child = spawn('rtk', ['proxy', exe, ...args], { cwd: root, env, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
  let data = '', pending = '', error = '', timedOut = false;
  const receive = chunk => {
    const text = chunk.toString(); data += text; pending += text;
    const lines = pending.split(/\r?\n/); pending = lines.pop();
    for (const line of lines) if (line.startsWith('SHIP_FIRE_GPU') || /FAIL SHIP FIRE GPU|SCRIPT ERROR:|\bERROR:/.test(line)) console.log(line);
  };
  child.stdout.on('data', receive); child.stderr.on('data', receive); child.on('error', value => { error = value.message; });
  const started = Date.now();
  const heartbeat = setInterval(() => console.log(`SHIP_FIRE_GPU_WAIT elapsed_seconds=${Math.round((Date.now() - started) / 1000)}`), 30000);
  const timeout = setTimeout(() => { timedOut = true; if (child.pid) spawn('rtk', ['proxy', 'taskkill', '/PID', String(child.pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' }); }, 1200000);
  const result = await new Promise(done => child.on('close', (code, signal) => done({ code, signal })));
  clearTimeout(timeout); clearInterval(heartbeat);
  writeFileSync(join(dest, 'process.log'), data, { flag: 'wx' });
  const sourceAfter = sourceSnapshot(), originalAfter = snapshotTree(originalUserdir);
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
        if (digest(bytes) !== image.sha256 || !same([pixels.width, pixels.height], image.viewport) || pixels.sha256 !== image.framebuffer_sha256) errors.push(`PNG or decoded RGBA differs ${image.file}`);
      } catch (failure) { errors.push(`${image.file}: ${failure.message}`); }
    }
    if (readdirSync(output).filter(file => file.endsWith('.png')).length !== report.captures.length) errors.push('unreported or missing PNGs');
    capture = { sha256: hash(reportPath), gpu: report.gpu, renderer: report.renderer, captures: report.captures.length, sampledFrames: report.sequences.length, acceptedSteps: report.acceptedSteps, cases: report.cases, errors };
  }
  const markers = data.split(/\r?\n/).filter(line => line.startsWith('SHIP_FIRE_GPU'));
  const finalMarkers = markers.filter(line => line.startsWith('SHIP_FIRE_GPU captures='));
  const pass = mode === '--guard'
    ? result.code === 2 && markers.length === 1 && markers[0] === 'SHIP_FIRE_GPU_GUARD_REJECTED failures=1' && data.includes('non-headless graphics required') && !existsSync(output)
    : result.code === 0 && finalMarkers.length === 1 && /^SHIP_FIRE_GPU captures=\d+ samples=\d+ accepted_steps=\d+ failures=0$/.test(finalMarkers[0]) && capture !== null && errors.length === 0;
  const valid = pass && !error && !timedOut && !diagnostic && sourceUnchanged && originalUnchanged;
  writeNew(join(dest, 'process-result.json'), { finishedUtc: new Date().toISOString(), valid, ...result, error, timedOut, diagnostic, markers, sourceBefore, sourceAfter, sourceUnchanged, originalBefore, originalAfter, originalUnchanged, capture, logSha256: hash(join(dest, 'process.log')), scope: 'Scripted actual menu/laboratory; 5 GPU samples per accepted second; controlled fire accounts and complete VFX expiry, same-tick cameras, pauses, reset and disposal. PNG and decoded RGBA verified. Direct-source freeze only; no manual play, game FPS, live-ballistic/campaign/production acceptance.' });
  if (!valid) { console.error(JSON.stringify({ error, diagnostic, sourceUnchanged, originalUnchanged, errors })); process.exitCode = 1; }
  console.log(`SHIP_FIRE_GPU_VALIDATION valid=${valid} evidence=${dest}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) run().catch(error => { console.error(error.stack); process.exitCode = 1; });
