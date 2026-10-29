import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync, readdirSync, realpathSync } from 'node:fs';
import { resolve, join, relative, isAbsolute, sep } from 'node:path';
import { pathToFileURL } from 'node:url';
import { pngFramebuffer } from './run_crew_battle_gpu.mjs';

const SCOPE = 'synthetic-progress-fixture; no real gameplay completion';
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const hash = file => digest(readFileSync(file));
const writeNew = (file, value) => writeFileSync(file, JSON.stringify(value, null, 2) + '\n', { flag: 'wx' });
const inside = (file, parent) => { const p = relative(resolve(parent), resolve(file)); return p !== '' && p !== '..' && !p.startsWith('..' + sep) && !isAbsolute(p); };
const finite = x => typeof x === 'number' && Number.isFinite(x);
const near = (a, b) => finite(a) && finite(b) && Math.abs(a - b) <= 1e-6;
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const sha = x => /^[a-f0-9]{64}$/.test(x || '');

export function auditTimeline(report) {
  const errors = [];
  if (!report?.valid || report.failures?.length || report.scope !== SCOPE || report.actualGameplayComplete !== false || !report.audioMuted || report.displayServer === 'headless' || !report.gpu || !report.renderer || report.seed !== 1661 || !near(report.fixedStep, 1 / 60) || report.ticksPerSample !== 15) errors.push('synthetic scope or actual hardware/cadence differs');
  if (!Array.isArray(report?.captures) || !Array.isArray(report?.sequences) || !Array.isArray(report?.cases) || report.cases.length !== 3 || !Array.isArray(report?.checks)) return [...errors, 'incomplete mainline fixture report'];
  const images = new Map();
  for (const image of report.captures) {
    if (!/^[a-z0-9-]+\.png$/.test(image.file || '') || images.has(image.file) || !sha(image.sha256) || !sha(image.framebuffer_sha256) || !sha(image.full_state_sha256) || image.framebuffer_format !== 'RGBA8') { errors.push('invalid image metadata'); continue; }
    images.set(image.file, image);
    if (image.kind === 'menu') continue;
    const s = image.snapshot, p = s?.progress;
    if (!s?.ready || !s.paused || s.scope !== SCOPE || s.error || s.resources?.world !== 0 || s.resources?.runtime !== 0 || s.resources?.storage !== 0 || !s.text?.includes('非真实任务通关') || !near(s.time, s.tick / 60) || image.tick !== s.tick || !near(image.time, s.time)) errors.push(`${image.file}: false scope, ownership or clock`);
    if (!p || p.campaignId !== 'zheng-family-v1' || !Number.isInteger(p.stageIndex) || p.stageIndex < 0 || p.stageIndex > 30 || !Number.isInteger(p.attempt) || p.attempt < 1 || p.protagonistId !== (p.stageIndex < 12 ? 'zheng-zhilong' : 'zheng-chenggong') || p.handoff?.done !== (p.stageIndex >= 12) || !Array.isArray(p.receipts)) { errors.push(`${image.file}: invalid progress identity`); continue; }
    const successes = p.receipts.filter(r => r.outcome === 'success');
    if (successes.length !== p.stageIndex + (p.phase === 'review' ? 1 : 0) || new Set(p.receipts.map(r => r.id)).size !== p.receipts.length) errors.push(`${image.file}: success prefix or receipt identity differs`);
    for (const r of p.receipts) for (const f of Object.values(r.evidence || {})) if (f.attempt !== r.attempt || f.stageId !== r.stageId || f.runId !== p.runId) errors.push(`${image.file}: evidence leaked across attempt`);
  }
  let accepted = 0;
  for (const [id, actions] of [['complete', 120], ['recover', 123], ['missing-handover', 120]]) {
    const c = report.cases.find(x => x.id === id), rows = report.sequences.filter(x => x.case === id);
    if (!c || c.actions !== actions || rows.length !== actions + 1 || c.last_tick !== actions * 15 || !near(c.last_time, actions / 4)) { errors.push(`${id}: extent differs`); continue; }
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i], image = images.get(row.file), s = image?.snapshot;
      if (row.action !== i || row.tick !== i * 15 || !near(row.time, i / 4) || image?.kind !== 'fixture' || image.case !== id || image.sample !== i || s?.tick !== row.tick || s?.progress?.revision !== row.revision || s?.progress?.stageIndex !== row.stageIndex || s?.progress?.phase !== row.phase || s?.transitionCount !== row.transitionCount) errors.push(`${id}: sample differs ${i}`);
    }
    const last = images.get(rows.at(-1).file)?.snapshot;
    if (!same(c.final, last)) errors.push(`${id}: final differs from image`);
    if (id === 'missing-handover') {
      if (!last?.blocked || last?.currentStage?.id !== 'T10' || last?.progress?.phase !== 'active' || last?.progress?.receipts?.length !== 29) errors.push('missing handover did not block synthetic finale');
      const target = last?.currentStage?.objectives?.find(x => x.kind === 'port-handover');
      if (!target || last.progress.objectiveProgress[target.id] !== 0) errors.push('missing final goal was manufactured');
    } else if (last?.progress?.phase !== 'complete' || last?.progress?.stageIndex !== 30 || last?.progress?.receipts?.length !== (id === 'recover' ? 31 : 30)) errors.push(`${id}: synthetic route not complete`);
    accepted += actions * 15;
  }
  if (accepted !== report.acceptedSteps) errors.push('accepted step sum differs');
  for (const phase of ['father-review', 'blocked']) {
    const p = report.checks.find(x => x.name === 'pause' && x.phase === phase);
    if (!p?.unchanged || p.frames !== 8 || !sha(p.before_sha256) || p.before_sha256 !== p.after_sha256) errors.push(`${phase}: pause absent`);
  }
  const details = report.checks.filter(x => x.name === 'detail');
  if (details.length !== 6 || details.some(x => !x.unchanged || !images.has(x.file))) errors.push('chapter/region/handoff/finale detail pairs absent');
  const reset = report.checks.find(x => x.name === 'reset');
  if (!reset?.ok || reset.after?.tick !== 0 || reset.after?.progress?.stageIndex !== 0 || reset.after?.progress?.receipts?.length !== 0) errors.push('reset did not restore empty fixture');
  if (!report.checks.some(x => x.name === 'real_entry' && x.ok) || !report.checks.some(x => x.name === 'dispose' && x.released) || !images.has('menu-before.png') || !images.has('menu-returned.png')) errors.push('actual UI entry or lifecycle absent');
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

const SOURCES = ["project.godot", "game/scenes/main/main_scene.tscn", "game/scenes/main/main_scene.gd", "game/runtime/game_router.gd", "game/ui/menu/main_menu.gd", "game/research/laboratory.gd", "game/research/catalog.gd", "assets/research/catalog.json", "assets/data/story_campaign/zheng_family_v1.json", "game/domain/story_campaign/catalog.gd", "game/domain/story_campaign/progress.gd", "game/research/demos/story_campaign_flow_experiment.gd", "game/ui/shared/maritime_art_theme.gd", "tools/research/capture_story_campaign_gpu.gd", "tools/research/capture_story_campaign_gpu.gd", "tools/research/run_story_campaign_gpu.mjs", "tools/research/run_crew_battle_gpu.mjs"];
SOURCES.push('tools/research/capture_ship_fire_gpu.gd');
const OPTIONAL_SOURCES = [];
const sourceSnapshot = () => Object.fromEntries([...SOURCES.map(file => [file, hash(file)]), ...OPTIONAL_SOURCES.map(file => [file, existsSync(file) ? hash(file) : null])]);

async function run() {
  const [mode, id, ...extra] = process.argv.slice(2);
  if (!['--gpu', '--guard'].includes(mode) || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(id || '') || id.length > 72 || extra.length) throw new Error('Usage: rtk proxy node tools/research/run_story_campaign_gpu.mjs --gpu|--guard <fresh-run-id>');
  if (!existsSync('project.godot')) throw new Error('Run from project root');
  const root = resolve('.'), evidence = resolve('docs/research/evidence/story-campaign-flow');
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
  const args = [...(mode === '--guard' ? ['--headless'] : []), '--path', root, '--script', 'res://tools/research/capture_story_campaign_gpu.gd', '--', `--output=res://docs/research/evidence/story-campaign-flow/${id}/frames`];
  writeNew(join(dest, 'start.json'), { startedUtc: new Date().toISOString(), mode, id, exe, exeSha256: hash(exe), args, profile, app, local, originalUserdir, sourceBefore, originalBefore, timeoutSeconds: 1200, scope: 'Direct-source and two original PNG freeze. Scripted actual Main/Laboratory, isolated APPDATA/LOCALAPPDATA; imported resources and transitive dependencies are not recursively frozen.' });
  console.log(`STORY_CAMPAIGN_GPU_LAUNCH mode=${mode} evidence=${dest} timeout_seconds=1200`);
  const child = spawn('rtk', ['proxy', exe, ...args], { cwd: root, env, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
  let data = '', pending = '', error = '', timedOut = false;
  const receive = chunk => {
    const text = chunk.toString(); data += text; pending += text;
    const lines = pending.split(/\r?\n/); pending = lines.pop();
    for (const line of lines) if (line.startsWith('STORY_CAMPAIGN_GPU') || /FAIL STORY CAMPAIGN GPU|SCRIPT ERROR:|\bERROR:/.test(line)) console.log(line);
  };
  child.stdout.on('data', receive); child.stderr.on('data', receive); child.on('error', value => { error = value.message; });
  const started = Date.now();
  const heartbeat = setInterval(() => console.log(`STORY_CAMPAIGN_GPU_WAIT elapsed_seconds=${Math.round((Date.now() - started) / 1000)}`), 30000);
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
  const markers = data.split(/\r?\n/).filter(line => line.startsWith('STORY_CAMPAIGN_GPU'));
  const finalMarkers = markers.filter(line => line.startsWith('STORY_CAMPAIGN_GPU captures='));
  const pass = mode === '--guard'
    ? result.code === 2 && markers.length === 1 && markers[0] === 'STORY_CAMPAIGN_GPU_GUARD_REJECTED failures=1' && data.includes('non-headless graphics required') && !existsSync(output)
    : result.code === 0 && finalMarkers.length === 1 && /^STORY_CAMPAIGN_GPU captures=\d+ samples=\d+ accepted_steps=\d+ failures=0$/.test(finalMarkers[0]) && capture !== null && errors.length === 0;
  const valid = pass && !error && !timedOut && !diagnostic && sourceUnchanged && originalUnchanged;
  writeNew(join(dest, 'process-result.json'), { finishedUtc: new Date().toISOString(), valid, ...result, error, timedOut, diagnostic, markers, sourceBefore, sourceAfter, sourceUnchanged, originalBefore, originalAfter, originalUnchanged, capture, logSha256: hash(join(dest, 'process.log')), scope: 'Actual Main/Laboratory synthetic progress fixtures, four samples per accepted second; chapter details, pauses, reset and disposal. PNG and decoded RGBA verified. No actual tasks, world asset transfer, manual play, campaign persistence or gameplay completion. Direct-source freeze includes inherited capture; not all transitive/imported assets.' });
  if (!valid) { console.error(JSON.stringify({ error, diagnostic, sourceUnchanged, originalUnchanged, errors })); process.exitCode = 1; }
  console.log(`STORY_CAMPAIGN_GPU_VALIDATION valid=${valid} evidence=${dest}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) run().catch(error => { console.error(error.stack); process.exitCode = 1; });
