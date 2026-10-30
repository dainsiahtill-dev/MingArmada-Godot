import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync, readdirSync, realpathSync } from 'node:fs';
import { resolve, join, relative, isAbsolute, sep } from 'node:path';
import { pathToFileURL } from 'node:url';
import { pngFramebuffer } from './run_crew_battle_gpu.mjs';

// Step-4 story voyage GPU/input acceptance slice wrapper. Real entry, real UI
// intents, real save; source + original-userdir freezes; PNG/RGBA audits.

const SCOPE = 'story-voyage-gpu-slice; real entry, real UI intents, real save';
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const hash = file => digest(readFileSync(file));
const writeNew = (file, value) => writeFileSync(file, JSON.stringify(value, null, 2) + '\n', { flag: 'wx' });
const inside = (file, parent) => { const p = relative(resolve(parent), resolve(file)); return p !== '' && p !== '..' && !p.startsWith('..' + sep) && !isAbsolute(p); };
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

export function auditStoryVoyage(report) {
  const errors = [];
  const images = new Map();
  for (const image of report.captures || []) images.set(image.file, image);
  if (!report.checks.some(x => x.name === 'real_entry' && x.ok)) errors.push('real story entry absent');
  if (!report.checks.some(x => x.name === 'honest_failure' && x.ok)) errors.push('honest failure settle absent');
  if (!report.checks.some(x => x.name === 'save' && x.ok)) errors.push('real story save absent');
  if (!report.checks.some(x => x.name === 'restore' && x.ok)) errors.push('real restore through the continue entry absent');
  if (!report.checks.some(x => x.name === 'dispose' && x.released)) errors.push('runtime disposal absent');
  for (const name of ['menu-before.png', 'story-initial.png', 'ch01-briefing.png', 'voyage-00.png', 'voyage-05.png', 'ch01-failure.png', 'ch01-save.png', 'menu-returned.png', 'ch01-restored.png', 'menu-final.png']) {
    if (!images.has(name)) errors.push(`missing capture ${name}`);
  }
  const failure = images.get('ch01-failure.png')?.snapshot;
  if (failure?.lastOutcome !== 'failure' || failure?.receipts < 1) errors.push('failure capture lacks the honest receipt');
  const saved = images.get('ch01-save.png')?.snapshot;
  if (saved?.phase !== 'active' || saved?.attempt !== 2) errors.push('retry state not captured before save');
  const restored = images.get('ch01-restored.png')?.snapshot;
  if (restored?.attempt !== 2 || restored?.receipts !== 1) errors.push('restored capture does not match the saved state');
  for (const image of report.captures || []) {
    const s = image.snapshot;
    if (s?.scope !== SCOPE || s.actualGameplayComplete !== false) errors.push(`${image.file}: false scope or completion claim`);
  }
  return errors;
}

export function auditStoryEndgame(report) {
  const errors = [];
  const images = new Map();
  for (const image of report.captures || []) images.set(image.file, image);
  if (!report.checks.some(x => x.name === 'restore' && x.ok)) errors.push('endgame restore absent');
  if (!report.checks.some(x => x.name === 'settle' && x.ok && x.outcome === 'success')) errors.push('three-gate settle success absent');
  if (!report.checks.some(x => x.name === 'ending' && x.ok && x.phase === 'complete')) errors.push('campaign ending absent');
  if (!report.checks.some(x => x.name === 'dispose' && x.released)) errors.push('runtime disposal absent');
  for (const name of ['menu-before.png', 'endgame-restored.png', 'endgame-terms.png', 'endgame-evacuate.png', 'endgame-handover.png', 'endgame-depart.png', 'endgame-complete.png', 'endgame-ending.png', 'endgame-summary.png', 'menu-final.png']) {
    if (!images.has(name)) errors.push(`missing capture ${name}`);
  }
  const restored = images.get('endgame-restored.png')?.snapshot;
  if (restored?.stageIndex !== 29 || restored?.receipts !== 29 || restored?.phase !== 'active') errors.push('restored endgame state does not match the prepared checkpoint');
  const ending = images.get('endgame-ending.png')?.snapshot;
  if (ending?.phase !== 'complete') errors.push('ending capture lacks the complete phase');
  for (const image of report.captures || []) {
    const s = image.snapshot;
    if (s?.actualGameplayComplete !== false) errors.push(`${image.file}: false completion claim`);
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
  visit(directory); return result;
}

const SOURCES = [
  'project.godot', 'game/scenes/main/main_scene.tscn', 'game/scenes/main/main_scene.gd',
  'game/runtime/game_router.gd', 'game/ui/menu/main_menu.gd',
  'game/scenes/story/story_scene.gd', 'game/ui/story/story_interface.gd',
  'game/runtime/story_runtime.gd', 'game/runtime/story_encounter_coordinator.gd',
  'game/domain/story_world/story_world_session.gd', 'game/domain/story_world/story_rules.gd', 'game/domain/story_world/story_save.gd',
  'game/domain/story_campaign/catalog.gd', 'game/domain/story_campaign/progress.gd', 'game/domain/story_campaign/scenarios.gd', 'game/domain/story_campaign/fact_adapter.gd',
  'game/domain/story_campaign/data/zheng_family_v1.json', 'game/domain/story_campaign/data/scenarios_v1.json', 'game/domain/story_campaign/data/geography_v1.json',
  'tools/research/capture_ship_fire_gpu.gd', 'tools/research/capture_story_voyage_gpu.gd', 'tools/research/run_story_voyage_gpu.mjs',
];
const sourceSnapshot = () => Object.fromEntries(SOURCES.map(file => [file, hash(file)]));

async function run() {
  const [mode, id, ...extra] = process.argv.slice(2);
  if (!['--gpu', '--guard', '--gpu-endgame', '--guard-endgame'].includes(mode) || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(id || '') || id.length > 72 || extra.length) throw new Error('Usage: rtk proxy node tools/research/run_story_voyage_gpu.mjs --gpu|--guard|--gpu-endgame|--guard-endgame <fresh-run-id>');
  if (!existsSync('project.godot')) throw new Error('Run from project root');
  const endgame = mode.endsWith('-endgame');
  const guard = mode.startsWith('--guard');
  const captureScript = endgame ? 'res://tools/research/capture_story_endgame_gpu.gd' : 'res://tools/research/capture_story_voyage_gpu.gd';
  const marker = endgame ? 'STORY_ENDGAME_GPU' : 'STORY_VOYAGE_GPU';
  const root = resolve('.'), evidence = resolve('docs/research/evidence/story-campaign-flow');
  mkdirSync(evidence, { recursive: true });
  const canonicalEvidence = realpathSync(evidence), dest = join(canonicalEvidence, id);
  if (!inside(dest, canonicalEvidence)) throw new Error('Output outside topic');
  mkdirSync(dest);
  const profile = join(dest, 'profile'), app = join(profile, 'roaming'), local = join(profile, 'local'), output = join(dest, 'frames');
  mkdirSync(app, { recursive: true }); mkdirSync(local);
  const originalAppdata = process.env.APPDATA;
  if (!originalAppdata || inside(profile, originalAppdata) || inside(originalAppdata, profile)) throw new Error('Invalid original profile or overlap');
  const originalUserdir = join(originalAppdata, 'Godot', 'app_userdata', 'MingArmada');
  const exe = process.env.GODOT_EXE || 'C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe';
  const env = { ...process.env, APPDATA: app, LOCALAPPDATA: local, SHIP_FIRE_PROFILE_ROOT: profile, SHIP_FIRE_ORIGINAL_APPDATA: originalAppdata, SHIP_FIRE_CAPTURE_OUTPUT: output };
  // Endgame slices restore a checkpoint prepared through the real settlement
  // layer. The prep runs against the default profile (a dedicated prep slot,
  // never the user's story-v1), then the file is copied into the isolated
  // profile as the story slot before the capture starts.
  let prepBytes = null;
  if (endgame && !guard) {
    const prepArgs = ['--headless', '--path', root, '--script', 'res://tools/research/prepare_story_endgame_save.gd'];
    await new Promise(done => {
      const prep = spawn('rtk', ['proxy', exe, ...prepArgs], { cwd: root, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
      let text = '';
      prep.stdout.on('data', c => { text += c.toString(); });
      prep.stderr.on('data', c => { text += c.toString(); });
      prep.on('close', () => {
        if (/ENDGAME_PREP_READY=true/.test(text)) {
          const slot = join(originalUserdir, 'saves', 'story-endgame-prep.json');
          if (existsSync(slot)) prepBytes = readFileSync(slot, 'utf8');
        }
        if (!prepBytes) console.log('ENDGAME_PREP_FAILED');
        done();
      });
    });
    if (!prepBytes) throw new Error('endgame preparation failed');
    mkdirSync(join(app, 'Godot', 'app_userdata', 'MingArmada', 'saves'), { recursive: true });
    writeFileSync(join(app, 'Godot', 'app_userdata', 'MingArmada', 'saves', 'story-v1.json'), prepBytes);
  }
  const originalBefore = snapshotTree(originalUserdir), sourceBefore = sourceSnapshot();
  const args = [...(guard ? ['--headless'] : []), '--path', root, '--script', captureScript, '--', `--output=res://docs/research/evidence/story-campaign-flow/${id}/frames`];
  writeNew(join(dest, 'start.json'), { startedUtc: new Date().toISOString(), mode, id, exe, exeSha256: hash(exe), args, profile, app, local, originalUserdir, prepBytes: prepBytes ? digest(Buffer.from(prepBytes)) : null, sourceBefore, originalBefore, timeoutSeconds: 600, scope: endgame ? 'Direct-source and original userdir freeze. Real restore of a prepared T10 checkpoint through the menu continue entry; three-gate ending via real UI buttons.' : 'Direct-source and original userdir freeze. Scripted actual Main/story entry with real UI intents and a real save; voyage slice only.' });
  console.log(`${marker}_LAUNCH mode=${mode} evidence=${dest} timeout_seconds=600`);
  const child = spawn('rtk', ['proxy', exe, ...args], { cwd: root, env, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
  let data = '', pending = '', error = '', timedOut = false;
  const receive = chunk => {
    const text = chunk.toString(); data += text; pending += text;
    const lines = pending.split(/\r?\n/); pending = lines.pop();
    for (const line of lines) if (line.startsWith(marker) || /FAIL STORY|SCRIPT ERROR:|\bERROR:/.test(line)) console.log(line);
  };
  child.stdout.on('data', receive); child.stderr.on('data', receive); child.on('error', value => { error = value.message; });
  const started = Date.now();
  const heartbeat = setInterval(() => console.log(`${marker}_WAIT elapsed_seconds=${Math.round((Date.now() - started) / 1000)}`), 30000);
  const timeout = setTimeout(() => { timedOut = true; if (child.pid) spawn('rtk', ['proxy', 'taskkill', '/PID', String(child.pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' }); }, 600000);
  const result = await new Promise(done => child.on('close', (code, signal) => done({ code, signal })));
  clearTimeout(timeout); clearInterval(heartbeat);
  writeFileSync(join(dest, 'process.log'), data, { flag: 'wx' });
  const sourceAfter = sourceSnapshot(), originalAfter = snapshotTree(originalUserdir);
  const sourceUnchanged = same(sourceBefore, sourceAfter), originalUnchanged = same(originalBefore, originalAfter);
  const diagnostic = /SCRIPT ERROR:|\bERROR:|\b(?:Parse|Compile) Error:|Failed to load (?:script|resource)/i.test(data);
  const errors = [];
  let capture = null;
  const reportPath = join(output, 'capture-result.json');
  if (!guard && existsSync(reportPath)) {
    const report = JSON.parse(readFileSync(reportPath, 'utf8'));
    errors.push(...(endgame ? auditStoryEndgame(report) : auditStoryVoyage(report)));
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
    capture = { sha256: hash(reportPath), gpu: report.gpu, renderer: report.renderer, captures: report.captures.length, checks: report.checks, errors };
  }
  const markers = data.split(/\r?\n/).filter(line => line.startsWith(marker));
  const finalMarkers = markers.filter(line => line.startsWith(`${marker} captures=`));
  const pass = guard
    ? result.code === 2 && markers.length === 1 && markers[0] === `${marker}_GUARD_REJECTED failures=1` && data.includes('non-headless graphics required') && !existsSync(output)
    : result.code === 0 && finalMarkers.length === 1 && new RegExp(`^${marker} captures=\\d+ samples=\\d+ accepted_steps=\\d+ failures=0$`).test(finalMarkers[0]) && capture !== null && errors.length === 0;
  const valid = pass && !error && !timedOut && !diagnostic && sourceUnchanged && originalUnchanged;
  writeNew(join(dest, 'process-result.json'), { finishedUtc: new Date().toISOString(), valid, ...result, error, timedOut, diagnostic, markers, sourceBefore, sourceAfter, sourceUnchanged, originalBefore, originalAfter, originalUnchanged, prepBytes: prepBytes ? prepBytes.length : null, capture, logSha256: hash(join(dest, 'process.log')), scope: endgame ? 'Real restore of a prepared T10 checkpoint via the menu continue entry and the three-gate ending via real UI buttons. Not a human keyboard playthrough of the full voyage. PNG/RGBA verified; direct-source freeze.' : 'Real story entry slice with real UI intents and a real save. Voyage slice only — not the full 30-stage playthrough, no manual keyboard play. PNG and decoded RGBA verified. Direct-source freeze; not all transitive assets.' });
  if (!valid) { console.error(JSON.stringify({ error, diagnostic, sourceUnchanged, originalUnchanged, errors })); process.exitCode = 1; }
  console.log(`${marker}_VALIDATION valid=${valid} evidence=${dest}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) run().catch(error => { console.error(error.stack); process.exitCode = 1; });
