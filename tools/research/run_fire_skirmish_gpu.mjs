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
const sha = value => /^[a-f0-9]{64}$/.test(value || '');
const findShip = (s, id) => s?.packet?.naval?.ships?.find(ship => ship.id === id);

export function auditState(s) {
  const errors = [], n = s?.packet?.naval, r = s?.packet?.runtime, view = s?.atmosphere;
  if (!n || r?.mode !== 'fire' || n.ships?.length !== 2 || !Number.isInteger(n.tick) || n.tick < 0 || !near(n.time, n.tick / 60) || typeof r.paused !== 'boolean') return ['missing actual fire practice clock/fixture'];
  for (const id of ['player', 'enemy-1']) {
    const ship = n.ships.find(row => row.id === id), f = ship?.fireControl, launcher = ship?.fireLauncher;
    if (!ship || ship.kind !== 'fuchuan' || !f || !launcher) { errors.push(`${id}: real equipped ship absent`); continue; }
    if (!['hull', 'maxHull', 'sail', 'maxSail', 'crew', 'maxCrew'].every(key => finite(ship[key]) && ship[key] >= 0) || ship.hull > ship.maxHull || ship.sail > ship.maxSail || ship.crew > ship.maxCrew) errors.push(`${id}: canonical health outside bounds`);
    if (f.version !== 'ship-fire-r1' || ![f.heat, f.fuelSeconds, f.wetness, f.workCarry, f.crewDamageCarry].every(finite) || f.heat < 0 || f.heat > 100 || f.fuelSeconds < 0 || f.fuelSeconds > 72 || f.wetness < 0 || f.wetness > 1 || f.workCarry < 0 || f.workCarry >= 2 || f.crewDamageCarry < 0 || f.crewDamageCarry >= 1) errors.push(`${id}: canonical fire state invalid`);
    if (![f.supplies, f.assignedFirefighters, f.pendingFirefighters, f.transferTicks].every(value => Number.isInteger(value) && value >= 0) || f.supplies > 24 || f.transferTicks > 120 || f.assignedFirefighters > Math.floor(ship.crew) || f.pendingFirefighters > Math.floor(ship.crew)) errors.push(`${id}: finite preparation/team counters invalid`);
    if (!['fire-ball', 'thorn-ball'].every(payload => Number.isInteger(launcher.ammo?.[payload]) && launcher.ammo[payload] >= 0 && launcher.ammo[payload] <= 2) || !finite(launcher.cooldownSeconds) || launcher.cooldownSeconds < 0 || launcher.cooldownSeconds > 12 + 1e-6 || !finite(launcher.operationSeconds) || launcher.operationSeconds < 0 || launcher.operationSeconds > 2 + 1e-6) errors.push(`${id}: finite auxiliary launcher invalid`);
    if (!['x', 'y', 'z'].every(axis => finite(ship.visual?.position?.[axis]))) errors.push(`${id}: actual position absent`);
  }
  if (!view?.ready || !view.enabled || !near(view.time, n.time + (s.tail?.elapsed || 0)) || !Number.isInteger(view.active_flames) || !Number.isInteger(view.active_smoke) || view.draw_calls > 3 || view.reserved_particles > view.capacity) errors.push('actual production fire projection invalid');
  if (s.audio?.seaGain !== 0 || s.audio?.windGain !== 0 || s.audio?.musicGain !== 0 || s.audio?.activeVoices !== 0) errors.push('fresh-profile production audio is not disabled');
  return errors;
}

export function auditTimeline(report) {
  const errors = [];
  if (!report?.valid || report.failures?.length || report.displayServer === 'headless' || !report.gpu || !report.renderer || !near(report.fixedStep, 1 / 60) || report.ticksPerSample !== 12 || report.nominalSamplesPerAcceptedSecond !== 5 || report.maximumPhysicsCallbackSeconds !== 18) errors.push('invalid hardware or callback cadence metadata');
  if (!Array.isArray(report?.captures) || !Array.isArray(report?.sequences) || !Array.isArray(report?.checks) || !Array.isArray(report?.commands) || !Array.isArray(report?.observed_projectiles) || !Array.isArray(report?.observed_events) || !Array.isArray(report?.presented_event_ids_without_observed_body) || !Array.isArray(report?.limitations)) return [...errors, 'incomplete production report'];
  const images = new Map();
  for (const image of report.captures) {
    if (!/^[a-z0-9-]+\.png$/.test(image.file || '') || images.has(image.file) || !sha(image.sha256) || !sha(image.framebuffer_sha256) || !sha(image.full_state_sha256) || image.framebuffer_format !== 'RGBA8' || !Array.isArray(image.viewport) || image.viewport.length !== 2 || !image.viewport.every(value => Number.isInteger(value) && value > 0)) { errors.push('invalid or duplicate GPU image'); continue; }
    images.set(image.file, image);
    if (image.kind !== 'menu') {
      errors.push(...auditState(image.snapshot).map(value => `${image.file}: ${value}`));
      if (image.tick !== image.snapshot?.packet?.naval?.tick || !near(image.time, image.snapshot?.packet?.naval?.time)) errors.push(`${image.file}: image coordinate differs from native snapshot`);
    }
  }
  const entry = report.checks.find(row => row.name === 'entry');
  if (!entry?.ordinary_button || entry.mode !== 'fire' || !entry.startup?.ok || entry.scene !== 'res://game/scenes/naval_practice/naval_practice.gd') errors.push('actual Main fire menu route absent');
  const rows = report.sequences, end = rows.at(-1), nativeTerminal = ['victory', 'defeat', 'surrendered'].includes(report.terminal?.status);
  if (rows.length < 2 || rows.length > 91 || rows[0]?.sample !== 0 || rows[0]?.physics_callbacks !== 0 || rows[0]?.accepted_steps !== 0 || rows[0]?.tick !== report.initialTick) errors.push('invalid production sequence extent');
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i], prev = rows[i - 1], image = images.get(row.file), n = image?.snapshot?.packet?.naval;
    if (row.file !== `fire-${String(i).padStart(3, '0')}.png` || row.sample !== i || row.physics_callbacks !== i * 12 || row.tick !== n?.tick || !near(row.time, n?.time) || !near(row.visual_time, image?.snapshot?.atmosphere?.time) || !sha(row.native_sha256) || row.full_state_sha256 !== image?.full_state_sha256 || row.accepted_steps !== row.tick - report.initialTick || !same(image?.viewport, [1600, 900])) errors.push(`native sequence/GPU image mismatch ${i}`);
    if (prev && (row.tick < prev.tick || row.tick > prev.tick + 12 || !near(row.time - prev.time, (row.tick - prev.tick) / 60))) errors.push(`accepted native clock mismatch ${i}`);
  }
  if (end?.physics_callbacks !== report.physicsCallbacks || end?.accepted_steps !== report.acceptedSteps || report.physicsCallbacks > 1080 || (!nativeTerminal && report.physicsCallbacks !== 1080) || (nativeTerminal && report.terminal.tick !== end?.tick)) errors.push('callback budget or real early-terminal accounting differs');
  const combat = report.checks.find(row => row.name === 'combat');
  if (!(combat?.player_heat_tick >= 0) || !(combat?.enemy_heat_tick >= 0) || !(combat?.assignment_tick >= combat?.player_heat_tick)) errors.push('actual player/hostile ignition or response assignment absent');
  if (!report.commands.some(row => row.intent?.type === 'launch-fire' && row.intent.payload === 'fire-ball') || !report.commands.some(row => row.intent?.type === 'fire-control' && row.intent.crew === 4 && row.tick >= combat?.player_heat_tick)) errors.push('actual fire_ball/team-four UI intents absent');
  const shots = report.observed_projectiles.map(row => row.projectile).filter(Boolean), ids = new Set();
  for (const row of report.observed_projectiles) {
    const shot = row.projectile;
    if (!shot || typeof shot.id !== 'string' || ids.has(shot.id) || !Number.isInteger(row.first_tick) || !near(row.first_time, row.first_tick / 60) || !['x', 'y', 'z'].every(axis => finite(shot.position?.[axis]))) errors.push('invalid real projectile observation');
    ids.add(shot?.id);
  }
  if (!shots.some(shot => shot.shipId === 'player' && shot.kind === 'fire-payload' && shot.payload === 'fire-ball') || !shots.some(shot => shot.shipId === 'enemy-1' && shot.kind === 'fire-payload') || !shots.some(shot => shot.shipId === 'enemy-1' && ['solid', 'chain', 'grape'].includes(shot.ammo))) errors.push('player fireball, hostile auxiliary counterfire or actual enemy cannon shot unobserved');
  const eventIds = new Set();
  for (const event of report.observed_events) {
    if (typeof event.id !== 'string' || eventIds.has(event.id) || !finite(event.time)) errors.push('invalid observed canonical event');
    eventIds.add(event.id);
    if (event.type === 'fire-payload-hit' && (!ids.has(event.projectileId) || !['player', 'enemy-1'].includes(event.targetId))) errors.push('observed payload hit lacks prior real trajectory');
  }
  if (!report.limitations.some(value => value.includes('Immediate production presentation'))) errors.push('partial event-observation boundary not disclosed');
  const pause = report.checks.find(row => row.name === 'pause'), before = images.get('active-pause-before.png'), after = images.get('active-pause-after.png');
  if (!pause?.unchanged || pause.frames !== 8 || !sha(pause.before_sha256) || pause.before_sha256 !== pause.after_sha256 || pause.before_sha256 !== before?.full_state_sha256 || pause.after_sha256 !== after?.full_state_sha256 || !before?.snapshot?.packet?.runtime?.paused || before?.tick !== after?.tick) errors.push('exact eight-rendered-frame actual pause absent');
  if (!rows.some(row => { const s = images.get(row.file)?.snapshot; const p = findShip(s, 'player'); return p?.fireControl?.supplies < 24 && (p.fireControl.assignedFirefighters === 4 || p.fireControl.pendingFirefighters === 4); })) errors.push('assigned player team never consumed real finite preparation');
  const restart = report.checks.find(row => row.name === 'restart'), reset = images.get('restarted.png')?.snapshot, resetPlayer = findShip(reset, 'player');
  if (!restart?.ok || reset?.packet?.naval?.tick !== 0 || reset?.packet?.naval?.time !== 0 || resetPlayer?.fireControl?.heat !== 0 || resetPlayer?.fireControl?.supplies !== 24 || resetPlayer?.fireLauncher?.ammo?.['fire-ball'] !== 2 || resetPlayer?.fireLauncher?.ammo?.['thorn-ball'] !== 2 || !same(restart.after, reset)) errors.push('actual restart did not restore clean initial fire equipment');
  for (const size of [[800, 600], [320, 480]]) {
    const layout = report.checks.find(row => row.name === 'narrow_layout' && same(row.viewport, size));
    if (!layout || layout.controls?.length !== 4 || layout.controls.some(control => control.enabled !== (control.id !== 'fight_fire') || control.expected_enabled !== (control.id !== 'fight_fire') || !control.visible || !control.fits || !control.hover_hit)) errors.push(`${size.join('x')}: actual fire controls have incorrect availability or are clipped/pointer-occluded`);
    const corresponding = report.captures.filter(image => image.file.startsWith(`narrow-${size[0]}x${size[1]}-`));
    if (corresponding.length !== 4 || corresponding.some(image => !same(image.viewport, size))) errors.push(`${size.join('x')}: per-control layout framebuffer missing`);
  }
  const input = report.checks.find(row => row.name === 'actual_input_probe');
  const popupOpen = images.get('target-popup-open.png'), popupSurface = images.get('target-popup-surface.png'), restored = images.get('input-restored.png');
  if (!input?.popup_opened || !input.popup_closed || !input.sole_item_selected || input.popup_item_activations?.length !== 1 || input.popup_item_activations[0] !== input.sole_item_id || input.selected_target_id !== 'enemy-1' || !input.focus_released || input.focus_after_selection === 'FireTarget' || !input.w_received || !input.w_released || !input.held_down?.includes('KeyW') || input.held_up?.includes('KeyW') || !input.dragging_started || !input.dragging_released || input.camera_before?.dragging || !input.camera_during?.dragging || input.camera_after?.dragging || !input.native_time_unchanged || !same(input.before_clock, input.after_clock) || input.physics_callbacks_before !== input.physics_callbacks_after || input.physics_callbacks_after !== report.physicsCallbacks || !same(input.world_point, [600, 250]) || !same(input.motion, [35, -12])) errors.push('actual popup selection, keyboard return or world camera input proof absent');
  if (!input?.w_held_before_popup || !input.held_cleared_on_popup || !Array.isArray(input.held_before_open) || !input.held_before_open.includes('KeyW') || !Array.isArray(input.held_after_open) || input.held_after_open.length !== 0 || !Array.isArray(input.held_after_popup_keyup) || input.held_after_popup_keyup.length !== 0 || input.unpaused_before_popup !== true || input.unpaused_during_popup !== true || input.unpaused_after_popup !== true || input.popup_window_before?.runtime_paused !== false || input.popup_window_open?.runtime_paused !== false || input.popup_window_keyup?.runtime_paused !== false || input.popup_window_after?.runtime_paused !== false) errors.push('owned target popup did not release a previously held W without pausing');
  if (!popupOpen || !popupSurface || !restored || !same(popupOpen.viewport, [1600, 900]) || !same(restored.viewport, [1600, 900]) || popupSurface.viewport_source !== 'PopupMenu' || popupSurface.kind !== 'input-popup' || popupOpen.tick !== restored.tick || !near(popupOpen.time, restored.time) || restored.tick !== input?.after_clock?.tick || !near(restored.time, input?.after_clock?.time)) errors.push('actual popup/open-restored GPU framebuffer or unchanged native clock evidence absent');
  if (!report.checks.some(row => row.name === 'leave' && row.released) || !images.has('menu-before.png') || !images.has('menu-returned.png')) errors.push('actual main-menu exit and owned scene release absent');
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
  'game/runtime/game_router.gd', 'game/ui/menu/main_menu.gd', 'game/ui/naval_practice.gd',
  'game/scenes/naval_practice/naval_practice.gd', 'game/runtime/naval_practice_runtime.gd',
  'game/runtime/sailing_simulation.gd', 'game/scenes/common/terminal_presentation_clock.gd',
  'game/scenes/common/sea_services.gd', 'game/persistence/user_settings.gd',
  'game/ui/shared/maritime_art_theme.gd', 'game/ui/shared/parchment_theme.gd',
  'modules/naval_simulation/encounter.gd', 'modules/naval_simulation/combat/fire_control.gd',
  'modules/naval_simulation/combat/fire_profile.gd', 'modules/naval_simulation/combat/fire_launcher.gd',
  'modules/naval_simulation/combat/projectiles.gd', 'game/presentation/world/naval_world_view.gd',
  'modules/naval_simulation/combat/cannon_system.gd', 'game/presentation/water/water_splashes.gd',
  'game/presentation/ships/ship_view.gd', 'game/presentation/ships/ship_damage.gd',
  'game/presentation/crew/crew_view.gd', 'game/presentation/combat/combat_effects.gd',
  'game/presentation/combat/combat_atmosphere.gd', 'game/presentation/combat/ship_fire_view.gd',
  'assets/textures/combat_atmosphere/r1/smoke-puff.png', 'assets/textures/combat_atmosphere/r1/flame.png',
  'tools/research/capture_fire_skirmish_gpu.gd', 'tools/research/run_fire_skirmish_gpu.mjs',
  'tools/research/run_crew_battle_gpu.mjs'
];

async function run() {
  const [mode, id, ...extra] = process.argv.slice(2);
  if (!['--gpu', '--guard'].includes(mode) || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(id || '') || id.length > 72 || extra.length) throw new Error('Usage: rtk proxy node tools/research/run_fire_skirmish_gpu.mjs --gpu|--guard <fresh-run-id>');
  if (!existsSync('project.godot')) throw new Error('Run from project root');
  const root = resolve('.'), evidence = resolve('docs/research/evidence/fire-skirmish');
  mkdirSync(evidence, { recursive: true });
  const canonicalEvidence = realpathSync(evidence), dest = join(canonicalEvidence, id);
  if (!inside(dest, canonicalEvidence)) throw new Error('Output outside topic');
  mkdirSync(dest);
  const profile = join(dest, 'profile'), app = join(profile, 'roaming'), local = join(profile, 'local'), output = join(dest, 'frames');
  mkdirSync(app, { recursive: true }); mkdirSync(local);
  const originalAppdata = process.env.APPDATA;
  if (!originalAppdata || inside(profile, originalAppdata) || inside(originalAppdata, profile) || resolve(profile).toLowerCase() === resolve(originalAppdata).toLowerCase()) throw new Error('Invalid original profile or overlap');
  const originalUserdir = join(originalAppdata, 'Godot', 'app_userdata', 'MingArmada');
  const sourceSnapshot = () => Object.fromEntries(SOURCES.map(file => [file, hash(file)]));
  const originalBefore = snapshotTree(originalUserdir), sourceBefore = sourceSnapshot();
  const exe = process.env.GODOT_EXE || 'C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe';
  const env = { ...process.env, APPDATA: app, LOCALAPPDATA: local, FIRE_SKIRMISH_PROFILE_ROOT: profile, FIRE_SKIRMISH_ORIGINAL_APPDATA: originalAppdata, FIRE_SKIRMISH_CAPTURE_OUTPUT: output };
  const args = [...(mode === '--guard' ? ['--headless'] : []), '--path', root, '--script', 'res://tools/research/capture_fire_skirmish_gpu.gd', '--', `--output=res://docs/research/evidence/fire-skirmish/${id}/frames`];
  writeNew(join(dest, 'start.json'), { startedUtc: new Date().toISOString(), mode, id, exe, exeSha256: hash(exe), args, profile, app, local, originalUserdir, sourceBefore, originalBefore, timeoutSeconds: 1200, scope: 'Direct production source and two sprite PNG freeze. Actual menu/UI callbacks; isolated APPDATA/LOCALAPPDATA. Transitive/imported dependencies are not recursively frozen.' });
  console.log(`FIRE_SKIRMISH_GPU_LAUNCH mode=${mode} evidence=${dest} timeout_seconds=1200`);
  const child = spawn('rtk', ['proxy', exe, ...args], { cwd: root, env, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
  let data = '', pending = '', error = '', timedOut = false;
  const receive = chunk => {
    const text = chunk.toString(); data += text; pending += text;
    const lines = pending.split(/\r?\n/); pending = lines.pop();
    for (const line of lines) if (line.startsWith('FIRE_SKIRMISH_GPU') || /FAIL FIRE SKIRMISH GPU|SCRIPT ERROR:|\bERROR:/.test(line)) console.log(line);
  };
  child.stdout.on('data', receive); child.stderr.on('data', receive); child.on('error', value => { error = value.message; });
  const started = Date.now();
  const heartbeat = setInterval(() => console.log(`FIRE_SKIRMISH_GPU_WAIT elapsed_seconds=${Math.round((Date.now() - started) / 1000)}`), 30000);
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
    capture = { sha256: hash(reportPath), gpu: report.gpu, renderer: report.renderer, captures: report.captures.length, sampledFrames: report.sequences.length, physicsCallbacks: report.physicsCallbacks, acceptedSteps: report.acceptedSteps, limitations: report.limitations, errors };
  }
  const markers = data.split(/\r?\n/).filter(line => line.startsWith('FIRE_SKIRMISH_GPU'));
  const finalMarkers = markers.filter(line => line.startsWith('FIRE_SKIRMISH_GPU captures='));
  const pass = mode === '--guard'
    ? result.code === 2 && markers.length === 1 && markers[0] === 'FIRE_SKIRMISH_GPU_GUARD_REJECTED failures=1' && data.includes('non-headless graphics required') && !existsSync(output)
    : result.code === 0 && finalMarkers.length === 1 && /^FIRE_SKIRMISH_GPU captures=\d+ samples=\d+ callbacks=\d+ accepted_steps=\d+ failures=0$/.test(finalMarkers[0]) && capture !== null && errors.length === 0;
  const valid = pass && !error && !timedOut && !diagnostic && sourceUnchanged && originalUnchanged;
  writeNew(join(dest, 'process-result.json'), { finishedUtc: new Date().toISOString(), valid, ...result, error, timedOut, diagnostic, markers, sourceBefore, sourceAfter, sourceUnchanged, originalBefore, originalAfter, originalUnchanged, capture, logSha256: hash(join(dest, 'process.log')), scope: 'Actual Main fire route with scripted real UI button signals and real physics callbacks, 5Hz GPU samples, native projectiles/counterfire/team accounts, exact pause, restart, narrow pointer hover and disposal. PNG/RGBA hashes verified. Event bodies can be partial after immediate production drains. No manual play, game FPS, campaign or whole-game completion claim.' });
  if (!valid) { console.error(JSON.stringify({ error, diagnostic, sourceUnchanged, originalUnchanged, errors })); process.exitCode = 1; }
  console.log(`FIRE_SKIRMISH_GPU_VALIDATION valid=${valid} evidence=${dest}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) run().catch(error => { console.error(error.stack); process.exitCode = 1; });
