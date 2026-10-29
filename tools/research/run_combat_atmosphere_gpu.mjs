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
const CASES = [
  { id: 'calm-baseline', enabled: false, wind: 'calm', camera_mode: 'battle' },
  { id: 'calm-candidate', enabled: true, wind: 'calm', camera_mode: 'battle' },
  { id: 'crosswind-candidate', enabled: true, wind: 'crosswind', camera_mode: 'battle' },
  { id: 'near-candidate', enabled: true, wind: 'calm', camera_mode: 'near' },
];

export function auditState(state, fixture) {
  const errors = [], n = state?.native, a = state?.atmosphere, t = state?.tail, p = state?.parameters;
  if (!n || !a || !t || !p || !Array.isArray(n.ships) || !Array.isArray(a.particles)) return ['missing authority or particle state'];
  if (!state.ready || !state.paused || !near(state.fixed_step, 1 / 60) || !Number.isInteger(state.tick) || state.tick < 0 || n.tick > state.tick || !near(state.visual_time, n.time + t.elapsed) || !near(state.time, state.visual_time)) errors.push('accepted clock or paused state invalid');
  if (p.seed !== 1661 || p.enabled !== fixture.enabled || p.wind !== fixture.wind || p.camera_mode !== fixture.camera_mode || state.camera_mode !== fixture.camera_mode || n.ships.length !== 2 || !near(n.wind?.speed, fixture.wind === 'calm' ? 0 : 12)) errors.push('fixture differs');
  if (!a.ready || a.enabled !== fixture.enabled || !near(a.time, state.visual_time) || a.capacity !== 384 || !Number.isInteger(a.draw_calls) || a.draw_calls < 0 || a.draw_calls > 3 || a.particles.length > a.capacity) errors.push('particle renderer bounds invalid');
  if (!fixture.enabled && (a.particles.length || a.draw_calls)) errors.push('disabled baseline contains candidate particles');
  const counts = { smoke: 0, flame: 0, ember: 0 }, ids = new Set();
  for (const particle of a.particles) {
    if (!Object.hasOwn(counts, particle.kind) || typeof particle.id !== 'string' || ids.has(particle.id)) { errors.push('invalid particle identity'); continue; }
    ids.add(particle.id); counts[particle.kind]++;
    if (!Array.isArray(particle.position) || particle.position.length !== 3 || !particle.position.every(finite) || !finite(particle.size) || particle.size <= 0 || !finite(particle.alpha) || particle.alpha < 0 || particle.alpha > 1 || !finite(particle.born) || !finite(particle.expires) || particle.born > state.visual_time || particle.expires <= state.visual_time || particle.expires > particle.born + 9.000001) errors.push('invalid finite particle envelope');
  }
  if (counts.smoke !== a.active_smoke || counts.flame !== a.active_flames || counts.ember !== a.active_embers) errors.push('reported particle counts differ from actual state inventory');
  if (!Array.isArray(a.bounds?.position) || !Array.isArray(a.bounds?.size) || !a.bounds.position.every(finite) || !a.bounds.size.every(v => finite(v) && v >= 0)) errors.push('invalid render bounds');
  for (const kind of ['fire', 'hit', 'sink', 'destruction-explosion']) if (!Number.isInteger(state.event_counts?.[kind]) || state.event_counts[kind] < 0) errors.push('invalid real event counts');
  return errors;
}

export function auditTimeline(report) {
  const errors = [];
  if (!report || !Array.isArray(report.cases) || !Array.isArray(report.captures) || !Array.isArray(report.sequences) || !Array.isArray(report.checks)) return ['missing GPU capture report'];
  if (!report.valid || report.failures?.length || !near(report.fixedStep, 1 / 60) || report.ticksPerFrame !== 4 || report.nominalSamplesPerAcceptedSecond !== 15 || report.maximumSamplesPerCase !== 601 || report.seed !== 1661 || !report.audioMuted || report.displayServer === 'headless' || !report.gpu || !report.renderer) errors.push('invalid hardware or cadence metadata');
  if (!same(report.cases.map(c => c.id), CASES.map(c => c.id))) errors.push('four declared cases not completed in order');
  const images = new Map(), baseline = new Map();
  for (const capture of report.captures) {
    if (typeof capture.file !== 'string' || !/^[a-z0-9-]+\.png$/.test(capture.file) || images.has(capture.file)) { errors.push('invalid or duplicate PNG identity'); continue; }
    images.set(capture.file, capture);
    if (!Array.isArray(capture.viewport) || capture.viewport.length !== 2 || !capture.viewport.every(v => Number.isInteger(v) && v > 0) || !/^[a-f0-9]{64}$/.test(capture.sha256 || '') || !/^[a-f0-9]{64}$/.test(capture.framebuffer_sha256 || '') || capture.framebuffer_format !== 'RGBA8') errors.push(`invalid framebuffer metadata ${capture.file}`);
    if (capture.kind === 'menu') {
      if (!['menu-before.png', 'menu-returned.png'].includes(capture.file) || capture.case !== '' || !same(capture.viewport, [1600, 900])) errors.push(`invalid menu capture ${capture.file}`);
      continue;
    }
    const fixture = CASES.find(c => c.id === capture.case);
    if (!fixture) { errors.push(`unknown fixture ${capture.file}`); continue; }
    errors.push(...auditState(capture.snapshot, fixture).map(e => `${capture.file}: ${e}`));
    if (capture.kind === 'page' && !same(capture.viewport, [1600, 900])) errors.push(`page extent differs ${capture.file}`);
  }
  let steps = 0;
  for (const fixture of CASES) {
    const summary = report.cases.find(c => c.id === fixture.id), rows = report.sequences.filter(r => r.case === fixture.id);
    if (!summary || rows.length < 2 || rows.length > 601 || summary.sampled_frames !== rows.length || !summary.finished || !near(summary.tail_elapsed, 10) || summary.first_terminal_tick < 1) { errors.push(`incomplete terminal case ${fixture.id}`); continue; }
    if (fixture.enabled && (!(summary.largest_smoke > 0) || !(summary.largest_flame > 0) || !summary.paused_wreck)) errors.push(`missing candidate plume or wreck pause ${fixture.id}`);
    let frozen = null;
    for (let index = 0; index < rows.length; index++) {
      const row = rows[index], previous = rows[index - 1], file = `${fixture.id}-${String(index).padStart(3, '0')}.png`, capture = images.get(file), state = capture?.snapshot;
      if (row.sample !== index || row.file !== file || !capture || capture.kind !== 'experiment' || !state || state.tick !== row.tick || state.native.tick !== row.native_tick || !near(state.native.time, row.native_time) || !near(state.visual_time, row.visual_time) || !near(state.tail.elapsed, row.tail_elapsed) || !same(state.event_counts, row.event_counts) || !/^[a-f0-9]{64}$/.test(row.native_sha256 || '')) { errors.push(`image-state sequence differs ${file}`); continue; }
      if (index === 0 ? row.tick !== 0 || row.ticks_advanced !== 0 : !Number.isInteger(row.ticks_advanced) || row.ticks_advanced < 1 || row.ticks_advanced > 4 || row.tick !== previous.tick + row.ticks_advanced || (index < rows.length - 1 && row.ticks_advanced !== 4) || row.visual_time < previous.visual_time) errors.push(`sampling cadence differs ${file}`);
      steps += row.ticks_advanced;
      if (fixture.id === 'calm-baseline') baseline.set(row.tick, state.native);
      else if (fixture.wind === 'calm' && (!row.same_calm_authority || !same(state.native, baseline.get(row.tick)))) errors.push(`baseline authority differs ${file}`);
      if (['victory', 'defeat'].includes(state.native.status)) {
        if (frozen === null) frozen = state.native;
        if (!same(frozen, state.native)) errors.push(`terminal authority advanced ${file}`);
      }
      if (row.active_smoke !== state.atmosphere.active_smoke || row.active_flames !== state.atmosphere.active_flames || row.active_embers !== state.atmosphere.active_embers) errors.push(`particle sample counts differ ${file}`);
    }
    const last = images.get(rows.at(-1)?.file)?.snapshot;
    if (!last || !last.finished || !near(last.tail.elapsed, 10) || last.atmosphere.particles.length || last.tick !== summary.accepted_tick || !same(last.event_counts, summary.event_counts)) errors.push(`terminal cleanup differs ${fixture.id}`);
    for (const kind of ['fire', 'hit', 'sink', 'destruction-explosion']) if (!(summary.event_counts?.[kind] > 0)) errors.push(`real ${kind} absent ${fixture.id}`);
    for (const suffix of ['page-start', 'page-end']) if (!images.has(`${fixture.id}-${suffix}.png`)) errors.push(`page capture missing ${fixture.id}-${suffix}`);
    if (fixture.enabled) {
      const before = images.get(`${fixture.id}-pause-before.png`), after = images.get(`${fixture.id}-pause-after.png`);
      if (!before || !after || !same(before.snapshot, after.snapshot) || !(before.snapshot.atmosphere.active_flames > 0) || !(before.snapshot.event_counts['destruction-explosion'] > 0) || !report.checks.some(c => c.name === 'wreck_pause' && c.case === fixture.id && c.frames === 8 && c.unchanged)) errors.push(`paused wreck evidence differs ${fixture.id}`);
    }
  }
  if (steps !== report.acceptedSteps) errors.push('accepted step count differs');
  if (!images.has('menu-before.png') || !images.has('menu-returned.png') || !report.checks.some(c => c.name === 'real_entry' && c.ok) || !report.checks.some(c => c.name === 'dispose' && c.released)) errors.push('entry or release evidence missing');
  const expected = report.sequences.length + CASES.length * 2 + CASES.filter(c => c.enabled).length * 2 + 2;
  if (images.size !== expected) errors.push('unexpected image inventory');
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
  'project.godot', 'game/scenes/main/main_scene.tscn', 'game/scenes/main/main_scene.gd', 'game/runtime/game_router.gd', 'game/ui/menu/main_menu.gd',
  'game/research/laboratory.gd', 'game/research/catalog.gd', 'game/research/parameter_panel.gd', 'assets/research/catalog.json', 'assets/research/papers/naval-combat-atmosphere.md',
  'game/research/demos/naval_combat_atmosphere_experiment.gd', 'game/presentation/combat/combat_atmosphere.gd', 'game/presentation/combat/combat_effects.gd', 'game/scenes/common/terminal_presentation_clock.gd',
  'game/presentation/world/naval_world_view.gd', 'game/presentation/ships/ship_view.gd', 'game/presentation/ships/ship_damage.gd', 'game/presentation/crew/deck_stations.gd',
  'modules/naval_simulation/encounter.gd', 'modules/naval_simulation/combat/cannon_system.gd', 'modules/naval_simulation/combat/projectiles.gd', 'modules/contracts/physics_types.gd',
  'modules/scene_engine/fidelity_fx/presentation.gd', 'modules/scene_engine/fidelity_fx/particle.gdshader', 'modules/scene_engine/fidelity_fx/particle_add.gdshader', 'modules/scene_engine/world/world_view.gd', 'modules/scene_engine/ocean/projected_ocean.gd', 'modules/scene_engine/ocean/reference_game_water.gdshader',
  'game/ui/shared/maritime_art_theme.gd', 'game/ui/shared/painted_window_style.gd', 'assets/textures/combat_atmosphere/r1/smoke-puff.png', 'assets/textures/combat_atmosphere/r1/flame.png',
  'tools/research/capture_combat_atmosphere_gpu.gd', 'tools/research/run_combat_atmosphere_gpu.mjs', 'tools/research/run_crew_battle_gpu.mjs',
];

async function run() {
  const [mode, id, ...extra] = process.argv.slice(2);
  if (!['--gpu', '--guard'].includes(mode) || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(id || '') || id.length > 72 || extra.length) throw new Error('Usage: rtk proxy node tools/research/run_combat_atmosphere_gpu.mjs --gpu|--guard <fresh-run-id>');
  if (!existsSync('project.godot')) throw new Error('Run from project root');
  const root = resolve('.'), evidence = resolve('docs/research/evidence/naval-combat-atmosphere');
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
  const env = { ...process.env, APPDATA: app, LOCALAPPDATA: local, COMBAT_ATMOSPHERE_PROFILE_ROOT: profile, COMBAT_ATMOSPHERE_ORIGINAL_APPDATA: originalAppdata, COMBAT_ATMOSPHERE_CAPTURE_OUTPUT: output };
  const args = [...(mode === '--guard' ? ['--headless'] : []), '--path', root, '--script', 'res://tools/research/capture_combat_atmosphere_gpu.gd', '--', `--output=res://docs/research/evidence/naval-combat-atmosphere/${id}/frames`];
  writeNew(join(dest, 'start.json'), { startedUtc: new Date().toISOString(), mode, id, exe, exeSha256: hash(exe), args, profile, app, local, originalUserdir, sourceBefore, originalBefore, timeoutSeconds: 1200, scope: 'Direct-source list and generated PNG freeze, not a recursive dependency/imported-resource freeze. Scripted actual menu/laboratory; isolated Windows userdata.' });
  console.log(`COMBAT_ATMOSPHERE_GPU_LAUNCH mode=${mode} evidence=${dest} timeout_seconds=1200`);
  const child = spawn('rtk', ['proxy', exe, ...args], { cwd: root, env, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
  let data = '', pending = '', error = '', timedOut = false;
  const receive = chunk => {
    const text = chunk.toString(); data += text; pending += text;
    const lines = pending.split(/\r?\n/); pending = lines.pop();
    for (const line of lines) if (line.startsWith('COMBAT_ATMOSPHERE_GPU') || /FAIL COMBAT ATMOSPHERE GPU|SCRIPT ERROR:|\bERROR:/.test(line)) console.log(line);
  };
  child.stdout.on('data', receive); child.stderr.on('data', receive); child.on('error', value => { error = value.message; });
  const started = Date.now();
  const heartbeat = setInterval(() => console.log(`COMBAT_ATMOSPHERE_GPU_WAIT elapsed_seconds=${Math.round((Date.now() - started) / 1000)}`), 30000);
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
  const markers = data.split(/\r?\n/).filter(line => line.startsWith('COMBAT_ATMOSPHERE_GPU'));
  const finalMarkers = markers.filter(line => line.startsWith('COMBAT_ATMOSPHERE_GPU captures='));
  const pass = mode === '--guard'
    ? result.code === 2 && markers.length === 1 && markers[0] === 'COMBAT_ATMOSPHERE_GPU_GUARD_REJECTED failures=1' && data.includes('non-headless graphics required') && !existsSync(output)
    : result.code === 0 && finalMarkers.length === 1 && /^COMBAT_ATMOSPHERE_GPU captures=\d+ samples=\d+ accepted_steps=\d+ failures=0$/.test(finalMarkers[0]) && capture !== null && errors.length === 0;
  const valid = pass && !error && !timedOut && !diagnostic && sourceUnchanged && originalUnchanged;
  writeNew(join(dest, 'process-result.json'), { finishedUtc: new Date().toISOString(), valid, ...result, error, timedOut, diagnostic, markers, sourceBefore, sourceAfter, sourceUnchanged, originalBefore, originalAfter, originalUnchanged, capture, logSha256: hash(join(dest, 'process.log')), scope: 'Scripted real menu/laboratory, 15 GPU samples per accepted second, exact calm A/B authority and official terminal-tail checks, decoded RGBA PNG checks. Direct-source freeze only. Visual quality still needs review; no manual play, game FPS or production acceptance.' });
  if (!valid) { console.error(JSON.stringify({ error, diagnostic, sourceUnchanged, originalUnchanged, errors })); process.exitCode = 1; }
  console.log(`COMBAT_ATMOSPHERE_GPU_VALIDATION valid=${valid} evidence=${dest}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) run().catch(error => { console.error(error.stack); process.exitCode = 1; });
