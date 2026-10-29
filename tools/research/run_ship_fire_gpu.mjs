import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync, readdirSync, realpathSync } from 'node:fs';
import { resolve, join, relative, isAbsolute, sep } from 'node:path';
import { pathToFileURL } from 'node:url';
import { pngFramebuffer } from './run_crew_battle_gpu.mjs';

const SCOPE = 'controlled ignition candidate; no live ballistic/campaign/production claim';
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const hash = file => digest(readFileSync(file));
const writeNew = (file, value) => writeFileSync(file, JSON.stringify(value, null, 2) + '\n', { flag: 'wx' });
const inside = (file, parent) => { const p = relative(resolve(parent), resolve(file)); return p !== '' && p !== '..' && !p.startsWith('..' + sep) && !isAbsolute(p); };
const finite = value => typeof value === 'number' && Number.isFinite(value);
const near = (a, b) => finite(a) && finite(b) && Math.abs(a - b) <= 1e-6;
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const sha = value => /^[a-f0-9]{64}$/.test(value || '');
const cold = s => ['baseline', 'candidate'].every(id => s?.lanes?.[id]?.fireControl?.heat === 0);
const finished = s => cold(s) && ['baseline', 'candidate'].every(id => s.lanes[id].reservedCrew === 0 && s.lanes[id].fireControl.transferTicks === 0) && ['living_fires', 'reserved_particles', 'active_smoke', 'active_flames', 'active_embers'].every(key => s.fire_view?.[key] === 0);

export function auditState(s) {
  const errors = [];
  if (!s?.ready || !s.paused || s.scope !== SCOPE || s.topic !== 'ship-fire-control' || s.error || s.resources?.storage !== 0 || s.resources?.runtime !== 0 || !Array.isArray(s.events) || s.events.length) errors.push('controlled scope or isolated ownership differs');
  const p = s?.parameters;
  if (!p || p.seed !== 1661 || p.payload !== 'thorn-ball' || p.firefighters !== 4 || ![4, 24].includes(p.supplies) || p.moisture !== 'dry' || p.load !== 'clear' || !['overview', 'near'].includes(s.camera_mode)) errors.push('controlled fixture differs');
  if (!Number.isInteger(s?.tick) || s.tick < 0 || !near(s?.fixed_step, 1 / 60) || !near(s?.time, s.tick / 60) || s.template?.tick !== 0 || s.template?.time !== 0 || !sha(s.template?.sha256) || s.visual?.tick !== s.tick || !near(s.visual?.time, s.time) || s.context?.rain01 !== 0 || s.context?.flammableLoad !== 0) errors.push('accepted clock template or experiment context differs');
  if (s?.visual?.ships?.length !== 2 || new Set(s.visual.ships.map(ship => ship.id)).size !== 2) errors.push('two rendered independent ships absent');
  for (const id of ['baseline', 'candidate']) {
    const lane = s?.lanes?.[id], f = lane?.fireControl, d = lane?.damage, ship = s?.visual?.ships?.find(x => x.id === id);
    if (!lane || !f || !d || !ship) { errors.push(`${id}: missing experiment account`); continue; }
    if (!['hull', 'sail', 'workSeconds', 'lastWorkSeconds'].every(key => finite(lane[key]) && lane[key] >= 0) || lane.hull > 100 || lane.sail > 100 || !near(lane.hull + d.hull, 100) || !near(lane.sail + d.sail, 100)) errors.push(`${id}: health or integral does not conserve`);
    if (![lane.crew, lane.maxCrew, d.crew, lane.reservedCrew, lane.suppliesSpent, f.supplies, f.transferTicks, f.assignedFirefighters, f.pendingFirefighters].every(x => Number.isInteger(x) && x >= 0) || lane.crew + d.crew !== lane.maxCrew || lane.reservedCrew > lane.crew || f.supplies + lane.suppliesSpent !== p?.supplies || !near(lane.workSeconds, lane.suppliesSpent * 2 + f.workCarry)) errors.push(`${id}: personnel preparation or work account differs`);
    if (![f.heat, f.fuelSeconds, f.wetness, f.workCarry, f.crewDamageCarry].every(finite) || f.heat < 0 || f.heat > 100 || f.fuelSeconds < 0 || f.fuelSeconds > 72 || f.wetness < 0 || f.wetness > 1 || f.workCarry < 0 || f.workCarry >= 2 || f.crewDamageCarry < 0 || f.crewDamageCarry >= 1 || f.transferTicks > 120 || f.version !== 'ship-fire-r1') errors.push(`${id}: fire state outside declared bounds`);
    if (ship.hull !== lane.hull || ship.sail !== lane.sail || ship.crew !== lane.crew || !same(ship.fireControl, f) || !Object.values(ship.visual?.position || {}).every(finite)) errors.push(`${id}: rendered health/fire differs from experiment account`);
    if (id === 'baseline' && (lane.workSeconds !== 0 || lane.reservedCrew !== 0 || f.assignedFirefighters !== 0 || f.pendingFirefighters !== 0)) errors.push('unattended baseline acquired workers');
  }
  const view = s?.fire_view;
  if (!view?.ready || !view.enabled || !near(view.time, s?.time) || !['living_fires', 'reserved_particles', 'active_smoke', 'active_flames', 'active_embers', 'draw_calls'].every(key => Number.isInteger(view[key]) && view[key] >= 0) || view.draw_calls > 3 || view.living_fires > 2 || view.reserved_particles > view.capacity) errors.push('heat-driven view metadata invalid');
  return errors;
}

export function auditTimeline(report) {
  const errors = [];
  if (!report?.valid || report.failures?.length || report.scope !== SCOPE || !report.audioMuted || report.displayServer === 'headless' || !report.gpu || !report.renderer || report.seed !== 1661 || !near(report.fixedStep, 1 / 60) || report.ticksPerSample !== 12 || report.nominalSamplesPerAcceptedSecond !== 5 || report.maximumSamplesPerCase !== 241 || report.maximumDefaultAcceptedSeconds !== 48) errors.push('invalid GPU cadence or scope metadata');
  if (!Array.isArray(report?.captures) || !Array.isArray(report?.sequences) || !Array.isArray(report?.cases) || report.cases.length !== 2 || !Array.isArray(report?.checks)) return [...errors, 'incomplete capture report'];
  const images = new Map();
  for (const image of report.captures) {
    if (!/^[a-z0-9-]+\.png$/.test(image.file || '') || images.has(image.file) || !sha(image.sha256) || !sha(image.framebuffer_sha256) || !sha(image.full_state_sha256) || image.framebuffer_format !== 'RGBA8' || !Array.isArray(image.viewport) || image.viewport.length !== 2 || !image.viewport.every(x => Number.isInteger(x) && x > 0)) { errors.push('invalid or duplicate PNG metadata'); continue; }
    images.set(image.file, image);
    if (image.kind !== 'menu') {
      errors.push(...auditState(image.snapshot).map(x => `${image.file}: ${x}`));
      if (image.tick !== image.snapshot?.tick || !near(image.time, image.snapshot?.time)) errors.push(`${image.file}: per-image accepted coordinates differ`);
    }
  }
  let acceptedSteps = 0;
  for (const id of ['default', 'low-supplies']) {
    const c = report.cases.find(x => x.id === id), rows = report.sequences.filter(x => x.case === id);
    if (!c || rows.length < 2 || rows.length > (id === 'default' ? 241 : 41) || c.samples !== rows.length) { errors.push(`${id}: invalid sequence extent`); continue; }
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i], image = images.get(row.file), s = image?.snapshot;
      if (row.sample !== i || row.tick !== i * 12 || row.steps !== (i ? 12 : 0) || !near(row.time, row.tick / 60) || row.camera_mode !== 'overview' || image?.kind !== 'experiment' || image.case !== id || image.sample !== i || image.steps !== row.steps || image.full_state_sha256 !== row.state_sha256 || s?.tick !== row.tick || !same(row.lanes, s?.lanes) || !same(row.fire_view, s?.fire_view)) errors.push(`${id}: sequence/image/account mismatch ${i}`);
      if (i && rows[i - 1].lanes && row.lanes) for (const lane of ['baseline', 'candidate']) for (const key of ['workSeconds', 'suppliesSpent']) if (row.lanes[lane][key] + 1e-6 < rows[i - 1].lanes[lane][key]) errors.push(`${id}: resource ledger regressed ${i}`);
    }
    const first = images.get(rows[0].file)?.snapshot, last = images.get(rows.at(-1).file)?.snapshot;
    if (first?.lanes?.baseline?.fireControl?.heat !== 28 || first?.lanes?.candidate?.fireControl?.heat !== 28 || first?.lanes?.candidate?.fireControl?.fuelSeconds !== 36) errors.push(`${id}: controlled initial ignition differs`);
    if (c.last_tick !== rows.at(-1).tick || !near(c.last_time, rows.at(-1).time) || !same(c.final, last)) errors.push(`${id}: final report differs from sampled state`);
    if (id === 'default' && (!c.completed || !c.active_pause || !c.extinguished_pause || !finished(last) || c.last_time > 48 || !(last?.lanes?.candidate?.hull > last?.lanes?.baseline?.hull) || !(last?.lanes?.candidate?.hull < 100))) errors.push('default lacks cold returned crew and completely expired VFX');
    if (id === 'low-supplies' && (rows.length !== 41 || c.last_tick !== 480 || !near(c.last_time, 8) || last?.lanes?.candidate?.fireControl?.supplies !== 0 || !(last?.lanes?.candidate?.fireControl?.heat > 0) || !(last?.lanes?.candidate?.workSeconds > 0))) errors.push('four-share case lacks exhausted-but-burning eight-second proof');
    acceptedSteps += rows.at(-1).tick;
  }
  if (acceptedSteps !== report.acceptedSteps) errors.push('accepted host-step total differs');
  for (const phase of ['active', 'extinguished']) {
    const pause = report.checks.find(x => x.name === 'pause' && x.phase === phase), pair = report.checks.find(x => x.name === 'camera_pair' && x.phase === phase);
    const before = images.get(`default-${phase}-pause-before.png`), after = images.get(`default-${phase}-pause-after.png`);
    if (!pause?.unchanged || pause.frames !== 8 || !sha(pause.before_sha256) || pause.before_sha256 !== pause.after_sha256 || pause.before_sha256 !== before?.full_state_sha256 || pause.after_sha256 !== after?.full_state_sha256 || before?.tick !== after?.tick) errors.push(`${phase}: eight-rendered-frame full-state pause absent`);
    if (phase === 'active' && !(before?.snapshot?.fire_view?.active_flames > 0)) errors.push('active pause has no observed flames');
    if (phase === 'extinguished' && !cold(before?.snapshot)) errors.push('extinguished pause still has controlled heat');
    const wide = images.get(pair?.overview_file), detail = images.get(pair?.near_file);
    if (!pair?.unchanged || !sha(pair.before_authority_sha256) || pair.before_authority_sha256 !== pair.after_authority_sha256 || wide?.tick !== detail?.tick || wide?.tick !== pair.tick || wide?.snapshot?.camera_mode !== 'overview' || detail?.snapshot?.camera_mode !== 'near' || !same(wide?.snapshot?.lanes, detail?.snapshot?.lanes) || !same(wide?.snapshot?.visual, detail?.snapshot?.visual)) errors.push(`${phase}: same-tick overview/near evidence differs`);
  }
  const reset = report.checks.find(x => x.name === 'reset_inventory');
  if (!reset?.ok || reset.before?.lanes?.candidate?.fireControl?.supplies !== 0 || reset.after?.tick !== 0 || reset.after?.lanes?.candidate?.fireControl?.supplies !== 24 || reset.after?.lanes?.candidate?.suppliesSpent !== 0 || reset.after?.lanes?.candidate?.workSeconds !== 0 || reset.after?.lanes?.candidate?.hull !== 100 || !same(reset.after, images.get('reset-restored.png')?.snapshot)) errors.push('explicit host reset did not restore initial inventory and accounts');
  if (!report.checks.some(x => x.name === 'real_entry' && x.ok) || !report.checks.some(x => x.name === 'dispose' && x.released) || !images.has('menu-before.png') || !images.has('menu-returned.png')) errors.push('actual entry or owned-world release absent');
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
  'tools/research/capture_ship_fire_gpu.gd', 'tools/research/run_ship_fire_gpu.mjs',
  'tools/research/run_crew_battle_gpu.mjs'
];
const OPTIONAL_SOURCES = ['modules/naval_simulation/combat/fire_launcher.gd'];
const sourceSnapshot = () => Object.fromEntries([...SOURCES.map(file => [file, hash(file)]), ...OPTIONAL_SOURCES.map(file => [file, existsSync(file) ? hash(file) : null])]);

async function run() {
  const [mode, id, ...extra] = process.argv.slice(2);
  if (!['--gpu', '--guard'].includes(mode) || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(id || '') || id.length > 72 || extra.length) throw new Error('Usage: rtk proxy node tools/research/run_ship_fire_gpu.mjs --gpu|--guard <fresh-run-id>');
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
  const args = [...(mode === '--guard' ? ['--headless'] : []), '--path', root, '--script', 'res://tools/research/capture_ship_fire_gpu.gd', '--', `--output=res://docs/research/evidence/ship-fire-control/${id}/frames`];
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
