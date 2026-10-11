// Run: rtk proxy node --experimental-vm-modules tools/migration/export-ship-reference.mjs [sourceRoot]
// Source files are transpiled in memory; this never builds or writes the source checkout.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';

const sourceRoot = path.resolve(process.argv[2] ?? 'C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada');
const targetRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const expectedHead = '9ad6a44daecd4ec36a8172d83ff27493feffe5dd';
const sourceHead = execFileSync('rtk', ['git', '-C', sourceRoot, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
if (sourceHead !== expectedHead) throw new Error(`Reference source HEAD differs: ${sourceHead}`);
execFileSync('rtk', ['git', '-C', sourceRoot, 'diff', '--exit-code', 'HEAD', '--',
  'packages/physics-core/src', 'packages/naval-core/src/encounter.ts', 'packages/naval-core/src/manualHandling.ts',
  'packages/scene-engine/src/engine/water/oceanWaves.js'], { encoding: 'utf8' });
const require = createRequire(path.join(sourceRoot, 'package.json'));
const ts = require('typescript');
const context = vm.createContext({ console, Math, Number, Array, Object, Map, Set, Error, RangeError, TypeError, structuredClone });
const modules = new Map();
const hashes = {};
function load(filename) {
  filename = path.resolve(filename).replace(/\.js$/, '.ts');
  if (modules.has(filename)) return modules.get(filename);
  const source = fs.readFileSync(filename, 'utf8');
  hashes[path.relative(sourceRoot, filename).replaceAll('\\', '/')] = createHash('sha256').update(source).digest('hex');
  const code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 } }).outputText;
  const module = new vm.SourceTextModule(code, { context, identifier: filename });
  modules.set(filename, module);
  return module;
}
const entry = load(path.join(sourceRoot, 'packages/physics-core/src/index.ts'));
await entry.link((specifier, referring) => {
  if (!specifier.startsWith('.')) throw new Error(`Unexpected runtime dependency: ${specifier}`);
  return load(path.resolve(path.dirname(referring.identifier), specifier));
});
await entry.evaluate();
const { NormPhysicsEngine, DescribedOcean } = entry.namespace;
// Read original authored waves and six ship specifications from the frozen source,
// rather than reproducing parameters from the new GDScript implementation.
const waveText = fs.readFileSync(path.join(sourceRoot, 'packages/scene-engine/src/engine/water/oceanWaves.js'), 'utf8');
const waveScript = new vm.SourceTextModule(waveText, { context, identifier: 'original-oceanWaves.js' });
const three = await import(pathToFileURL(path.join(sourceRoot, 'node_modules/three/build/three.module.js')).href);
const threeModule = new vm.SyntheticModule(Object.keys(three), function () {
  for (const [key, value] of Object.entries(three)) this.setExport(key, value);
}, { context });
await waveScript.link(specifier => {
  if (specifier !== 'three') throw new Error(`Unexpected authored-wave import: ${specifier}`);
  return threeModule;
});
await waveScript.evaluate();
const waveDescriptors = structuredClone(waveScript.namespace.ORIGINAL_PROJECTED_WAVES);
const encounterText = fs.readFileSync(path.join(sourceRoot, 'packages/naval-core/src/encounter.ts'), 'utf8');
const specsLiteral = encounterText.match(/const SPECS:[\s\S]*?= (\{[\s\S]*?\r?\n\})\r?\nconst BALLISTICS/)[1];
const specs = vm.runInContext(`(${specsLiteral})`, context);
const ocean = new DescribedOcean(waveDescriptors);
const tracks = [];
const manualEntry = load(path.join(sourceRoot, 'packages/naval-core/src/manualHandling.ts'));
await manualEntry.link(() => { throw new Error('Unexpected manual budget runtime dependency'); });
await manualEntry.evaluate();
const manualBudgets = [];
for (const kind of Object.keys(specs)) for (const speed of [0, .6, 2]) for (const turnIntent of [-1, 0, 1]) {
  const ship = { kind, crew: 25, maxCrew: 100, hull: 36, maxHull: 100, sail: 81, maxSail: 100, sailDeployment: 0 };
  const request = { mode: 'assisted', turnIntent, sailIntent: 0, braking: true, recovery: false };
  manualBudgets.push({ kind, speed, turnIntent, crewFraction: .25, hullFraction: .36, sailFraction: .81,
    braking: true, sailDeployment: 0, expected: structuredClone(manualEntry.namespace.manualHandlingFor(request, ship, speed)) });
}
function capture(engine, time) {
  const visual = engine.getVisualState();
  return { ...visual, time, yawRate: engine.yawRate, heave: engine.heaveY,
    heaveRate: engine.heaveRate, pitchRate: engine.pitchRate, heelRate: engine.heelRate,
    baseY: engine.baseY, buoyancyOffsetY: engine.buoyancyOffsetY,
    rig: { sailAngle: engine.sailAngleRad, sailDeployment: engine.sailDeployment,
      sailCondition: engine.sailCondition, sailPowerScale: engine.sailPowerScale },
    mass: engine.mass, sailDebug: engine.getSailDebugInfo() };
}
function run(name, kind, initial, controls, ticks, hz = 120, changes = []) {
  const original = specs[kind];
  const params = { ...original, beam: original.width, height: original.freeboard + 2,
    massOverride: original.mass, sailInducedDragFactor: .08 };
  const engine = new NormPhysicsEngine(1.225, params);
  let time = initial.time ?? 0;
  const config = { keelAreaFactor: original.length / original.width / .8,
    keelLiftSlope: 6, keelInducedDragFactor: .08, sailPressureScale: 1,
    heaveTravelLimit: ocean.heaveExcursion + (initial.draft ?? original.draft) * 2, ...initial.config };
  engine.setConfig(config);
  engine.setCargoMass(initial.cargoMass ?? 0);
  if (initial.draft !== undefined) engine.setDraftMeters(initial.draft);
  engine.setState({ x: initial.position?.x ?? 0, y: initial.position?.z ?? 0 }, initial.heading ?? 0);
  engine.setSpeed(initial.speed ?? 0);
  const waveSampler = initial.sampler === 'flat' ? () => 0 : (x, z) => ocean.sample(x, z, time).height;
  let baseY = initial.baseY;
  if (baseY === undefined) {
    baseY = 0;
    const c = Math.cos(initial.heading ?? 0), s = Math.sin(initial.heading ?? 0);
    for (const f of [-1, 1]) for (const r of [-1, 1]) {
      const forward = Math.max(.5, original.length * .35), side = Math.max(.25, original.width * .45);
      baseY += waveSampler((initial.position?.x ?? 0) + c * forward * f - s * side * r,
        (initial.position?.z ?? 0) + s * forward * f + c * side * r) / 4;
    }
  }
  engine.setBaseY(baseY);
  engine.setWaveSampler(waveSampler);
  const wind = initial.wind ?? { direction: { x: -1, z: .3 }, speed: 9 };
  engine.setWind({ x: wind.direction.x, y: wind.direction.z }, wind.speed);
  engine.setSailAngle(initial.sailAngle ?? .8);
  engine.setSailDeployment(initial.sailDeployment ?? .8);
  engine.setSailCondition(initial.sailCondition ?? 1);
  engine.setSailPowerScale(initial.sailPowerScale ?? 1);
  engine.setControls(controls);
  const selected = new Set([0, 1, 2, 10, 60, 120, 240, 600, 1200, 3600, ticks]);
  const frames = [{ tick: 0, state: capture(engine, time) }];
  const commandLog = [];
  for (let tick = 1; tick <= ticks; tick++) {
    time = (initial.time ?? 0) + tick / hz;
    for (const change of changes.filter(item => item.tick === tick)) {
      if ('cargoMass' in change) engine.setCargoMass(change.cargoMass);
      if ('draft' in change) engine.setDraftMeters(change.draft);
      if ('sailPowerScale' in change) engine.setSailPowerScale(change.sailPowerScale);
      if ('controls' in change) engine.setControls(change.controls);
      if ('stop' in change) engine.stopHorizontalMotion();
      if ('contact' in change) engine.resolveHorizontalContact({ x: change.contact.normal.x, y: change.contact.normal.z }, { x: change.contact.offset.x, y: change.contact.offset.z });
      commandLog.push(change);
    }
    engine.step({ deltaSeconds: 1 / hz });
    if (selected.has(tick) || changes.some(item => Math.abs(item.tick - tick) <= 1)) frames.push({ tick, state: capture(engine, time) });
  }
  tracks.push({ name, kind, initial: { ...initial, baseY, wind }, controls, hz, ticks, commands: commandLog, frames });
}
for (const [i, kind] of Object.keys(specs).entries()) {
  run(`authored-${kind}-120hz`, kind, { position: { x: 13 + i * 89.1, z: -27 - i * 35.7 }, heading: .4 + i * .2,
    speed: 3, time: (i % 4) * 6 }, { throttle: 0, rudderAngleDeg: 12, crewSteeringForce: specs[kind].crew * 200 }, 7200);
}
run('authored-fuchuan-60hz-live-equipment', 'fuchuan', { position: { x: 13, z: -27 }, heading: .4, speed: 3 },
  { throttle: 0, rudderAngleDeg: 12 }, 3600, 60,
  [{ tick: 120, cargoMass: 47500, draft: 2.7, sailPowerScale: 1.69 }, { tick: 240, cargoMass: 0, draft: 2, sailPowerScale: 1 }]);
const calm = { sampler: 'flat', sailDeployment: 0, wind: { direction: { x: 1, z: 0 }, speed: 0 } };
for (const sign of [-1, 1]) run(`crew-steering-${sign}`, 'fuchuan', calm, { throttle: 0, rudderAngleDeg: sign * 30, crewSteeringForce: 7400 }, 600);
run('zero-crew-from-rest', 'fuchuan', calm, { throttle: 0, rudderAngleDeg: 30, crewSteeringForce: 0 }, 600);
run('drive-forward', 'fisherman', calm, { throttle: 1, rudderAngleDeg: 0 }, 600);
run('drive-reverse', 'fisherman', calm, { throttle: -1, rudderAngleDeg: 0 }, 600);
const assist = { targetYawRateRad: 8 * Math.PI / 180, maxYawAccelerationRad: 11 * Math.PI / 180,
  powerFraction: 1, neutralYawDamping: 0, brakeDeceleration: 0, coastInNoGo: true };
for (const [name, extra, power] of [['manual-turn', {}, 1], ['manual-cargo', { cargoMass: 95000 }, 1], ['manual-quarter-crew', {}, .25]])
  run(name, 'fuchuan', { ...calm, ...extra }, { throttle: 0, manualAssist: { ...assist, powerFraction: power } }, 600);
run('manual-neutral-contact-anchor', 'fuchuan', calm, { throttle: 0, manualAssist: assist }, 600, 120,
  [{ tick: 120, contact: { normal: { x: 0, z: 1 }, offset: { x: 16, z: -4.5 } } },
    { tick: 240, controls: { throttle: 0, manualAssist: { ...assist, targetYawRateRad: 0, neutralYawDamping: 2.5 } } }, { tick: 480, stop: true }]);
for (const enabled of [false, true]) run(`headwind-coast-${enabled}`, 'fuchuan', { ...calm, speed: 5, sailDeployment: 1,
  wind: { direction: { x: 1, z: 0 }, speed: 9 } }, { throttle: 0, ...(enabled ? { manualAssist: { ...assist, targetYawRateRad: 0 } } : {}) }, 600);
run('manual-brake', 'fuchuan', { ...calm, speed: .03 }, { throttle: 0, manualAssist: { ...assist, targetYawRateRad: 0, brakeDeceleration: .2 } }, 600);
run('no-buoyancy-roll', 'fuchuan', { wind: { direction: { x: 0, z: 1 }, speed: 8 }, sailAngle: Math.PI / 4, sailDeployment: 1,
  config: { buoyancyEnabled: false } }, { throttle: 0, rudderAngleDeg: 15 }, 480);
for (const heading of [0, Math.PI / 2, Math.PI, -Math.PI / 2])
  run(`cardinal-${heading}`, 'fisherman', { ...calm, heading, speed: 3 }, { throttle: 0 }, 120);
hashes['packages/naval-core/src/encounter.ts'] = createHash('sha256').update(encounterText).digest('hex');
hashes['packages/scene-engine/src/engine/water/oceanWaves.js'] = createHash('sha256').update(waveText).digest('hex');
const fixture = { schema: 1, sourceHead, sourceCase: 'actual frozen NormPhysicsEngine runtime (in-memory TypeScript transpilation)',
  units: { position: 'm', velocity: 'm/s', mass: 'kg', angles: 'rad', time: 's', forces: 'N' },
  sourceHashes: hashes, specs, waveDescriptors, samplerId: 'ORIGINAL_PROJECTED_WAVES', manualBudgets, tracks };
const output = path.join(targetRoot, 'tests/fixtures/ship-reference.json');
fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, `${JSON.stringify(fixture, null, 2)}\n`);
console.log(`SHIP_REFERENCE tracks=${tracks.length} frames=${tracks.reduce((sum, track) => sum + track.frames.length, 0)} sourceHead=${sourceHead}`);
