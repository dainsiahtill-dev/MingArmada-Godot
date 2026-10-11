import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Validate saved native captures. Fixed simulation ticks never establish FPS.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const evidence = path.join(root, 'docs/migration/evidence');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const qaLabels = ['fleet', 'damage', 'sink', 'impact', 'impact-weak', 'benchmark',
  'shore-escape', 'wave-fisherman', 'wave-patrol',
  ...['fuchuan', 'fisherman', 'merchant', 'voc', 'patrol', 'heavy'].map(kind => `crew-${kind}`),
  'sink-real-hit', 'impact-real-hit', 'impact-weak-real-hit', 'impact-weak-recovered', 'fleet-narrow'];
const orbitLabels = ['quarter-before', 'orbit-after-chord', 'pan-after', 'zoom-after'];

export function pngDimensions(bytes) {
  assert.ok(bytes.length >= 33, 'PNG header is truncated');
  assert.equal(bytes.subarray(0, 8).toString('hex'), '89504e470d0a1a0a', 'PNG signature');
  assert.equal(bytes.readUInt32BE(8), 13, 'PNG IHDR length');
  assert.equal(bytes.subarray(12, 16).toString('ascii'), 'IHDR', 'PNG first chunk');
  const dimensions = [bytes.readUInt32BE(16), bytes.readUInt32BE(20)];
  assert.ok(dimensions.every(value => value > 0), 'PNG dimensions must be positive');
  return dimensions;
}

function near(actual, expected, detail, tolerance = 1e-6) {
  assert.ok(Number.isFinite(actual) && Math.abs(actual - expected) < tolerance, detail);
}

export function validateMetadata(label, metadata, dimensions, qa) {
  assert.deepEqual(dimensions, metadata.viewport, `${label}: PNG/metadata viewport agreement`);
  assert.deepEqual(dimensions, label === 'fleet-narrow' ? [320, 480] : [1600, 900], `${label}: native capture dimensions`);
  assert.deepEqual([metadata.engine.major, metadata.engine.minor, metadata.engine.patch], [4, 7, 2], `${label}: Godot version`);
  assert.equal(metadata.engine.status, 'stable', `${label}: stable Godot`);
  assert.equal(metadata.engine.build, 'official', `${label}: official Godot`);
  assert.equal(metadata.engine.hash, 'ed1daf0bf001b61586d9930840f2f1394092c079', `${label}: Godot build hash`);
  assert.match(metadata.gpu, /Intel.*Arc.*130T/i, `${label}: actual GPU metadata`);
  if (qa) {
    assert.equal(metadata.quality, 'balanced', `${label}: isolated QA uses balanced quality`);
    assert.equal(metadata.route, 'actual project MainScene menu QA button', `${label}: actual menu route`);
    assert.match(metadata.scope, /Fixed capture ticks are not a wall-time FPS benchmark/, `${label}: capture scope`);
    const scenario = label.replace(/-(real-hit|recovered|narrow)$/, '');
    assert.equal(metadata.runtime.runtime.scenario, scenario, `${label}: selected scenario`);
    assert.equal(metadata.runtime.runtime.handlingMode, 'realistic', `${label}: native handling`);
    const naval = metadata.runtime.naval;
    const sailors = metadata.inspection.sailors;
    assert.equal(sailors.battleId, naval.battleId, `${label}: inspection uses same battle`);
    assert.equal(sailors.tick, naval.tick, `${label}: sailors use accepted native tick`);
    near(sailors.simulationTime, naval.time, `${label}: sailors use accepted native time`);
    assert.equal(sailors.impacts.active, sailors.impacts.bodies.length, `${label}: active body count`);
    assert.ok(sailors.impacts.active <= sailors.impacts.cap, `${label}: impact cap`);
    for (const body of sailors.impacts.bodies) {
      assert.equal(body.boneCount, 18, `${label}: active skeleton bones`);
      assert.equal(body.jointCount, 17, `${label}: active physical joints`);
      assert.equal(body.bonePositions.length, body.boneCount, `${label}: physical bone positions`);
      assert.ok(body.bonePositions.every(point => ['x', 'y', 'z'].every(axis => Number.isFinite(point[axis]))), `${label}: finite physical bones`);
      assert.equal(body.targetId, 'inspection-voc', `${label}: actual struck target`);
      assert.ok(target(metadata, body.targetId), `${label}: actual native target exists`);
      assert.match(body.eventId, /^event-\d+$/, `${label}: native hit event`);
      assert.match(body.id, /^impact_/, `${label}: physical body identity`);
      assert.equal(typeof body.casualty, 'boolean', `${label}: casualty/recovery distinction`);
      assert.ok(Number.isInteger(body.slot) && body.slot >= 0 && body.age > 0, `${label}: physical body slot and age`);
    }
  } else {
    assert.match(metadata.scope, /actual root-routed pointer input; no performance claim/, `${label}: orbit scope`);
    assert.equal(metadata.state.kind, 'fuchuan', `${label}: actual model kind`);
    assert.equal(metadata.state.lod, 0, `${label}: actual model LOD`);
    assert.equal(metadata.state.path, 'res://assets/models/ships/fuchuan-lod0.glb', `${label}: actual model resource`);
    assert.ok(Number.isFinite(metadata.state.distance) && metadata.state.distance > 0, `${label}: camera distance`);
    vector(metadata.cameraPosition); vector(metadata.target);
  }
}

function vector(value) {
  assert.equal(typeof value, 'string', 'Vector3 metadata string');
  assert.match(value, /^\([^()]+\)$/, 'Vector3 metadata format');
  const components = value.slice(1, -1).split(',').map(Number);
  assert.ok(components.length === 3 && components.every(Number.isFinite), 'finite Vector3 components');
  return components;
}

function target(metadata, id) {
  const ship = metadata.runtime.naval.ships.find(ship => ship.id === id);
  assert.ok(ship, `native target ${id} exists`);
  return ship;
}

export function validateQaSequence(metadata) {
  const realHits = [];
  for (const scenario of ['impact', 'impact-weak', 'sink']) {
    const before = metadata.get(scenario);
    const after = metadata.get(`${scenario}-real-hit`);
    const impacts = after.inspection.sailors.impacts;
    assert.equal(after.runtime.runtime.generation, before.runtime.runtime.generation, `${scenario}: same scenario generation`);
    assert.ok(after.runtime.naval.tick > before.runtime.naval.tick, `${scenario}: actual hit advances accepted ticks`);
    assert.ok(impacts.active > 0, `${scenario}: actual cannon hit has active Jolt bodies`);
    for (const body of impacts.bodies) {
      assert.ok(target(after, body.targetId).hull < target(before, body.targetId).hull, `${scenario}: target hull took actual damage`);
      assert.ok(target(after, body.targetId).crew < target(before, body.targetId).crew, `${scenario}: target crew took actual damage`);
    }
    realHits.push({ label: `${scenario}-real-hit`, activeJoltBodies: impacts.active,
      bodies: impacts.bodies.map(({ id, eventId, targetId, boneCount, jointCount, casualty, slot }) =>
        ({ id, eventId, targetId, boneCount, jointCount, casualty, slot })) });
  }
  assert.equal(target(metadata.get('sink-real-hit'), 'inspection-voc').hull, 0, 'real sink target reaches zero hull');

  const hit = metadata.get('impact-weak-real-hit');
  const recovered = metadata.get('impact-weak-recovered');
  assert.equal(recovered.runtime.runtime.generation, hit.runtime.runtime.generation, 'weak recovery retains scenario generation');
  assert.ok(recovered.runtime.naval.time > hit.runtime.naval.time + 2, 'weak recovery follows actual simulation hold');
  const recoverable = hit.inspection.sailors.impacts.bodies.filter(body => !body.casualty);
  assert.ok(recoverable.length > 0, 'weak hit has a recoverable noncasualty');
  const remaining = recovered.inspection.sailors.impacts.bodies;
  assert.ok(recoverable.every(body => !remaining.some(active => active.id === body.id)), 'noncasualty body releases after recovery');
  const hitSailors = hit.inspection.sailors.ships.find(ship => ship.id === 'inspection-voc');
  const recoveredSailors = recovered.inspection.sailors.ships.find(ship => ship.id === 'inspection-voc');
  assert.ok(recoveredSailors.visible > hitSailors.visible, 'recovered sailor returns to visible target crew');

  const waveHolds = [];
  for (const kind of ['fisherman', 'patrol']) {
    const label = `wave-${kind}`;
    const capture = metadata.get(label);
    assert.deepEqual(capture.runtime.runtime.pauseReasons, ['wave'], `${label}: source wave pause authority`);
    assert.equal(capture.runtime.runtime.paused, true, `${label}: held wave is paused`);
    assert.equal(capture.runtime.runtime.phase, 'paused', `${label}: paused runtime phase`);
    near(capture.runtime.naval.time, 4.6, `${label}: real 4.6 second wave hold`);
    assert.equal(capture.runtime.naval.tick, 276, `${label}: real accepted wave tick`);
    assert.equal(target(capture, 'player').kind, kind, `${label}: actual vessel kind`);
    waveHolds.push({ label, acceptedTime: capture.runtime.naval.time, acceptedTick: capture.runtime.naval.tick, pauseReasons: ['wave'] });
  }
  return { realHits, weakRecovery: { label: 'impact-weak-recovered', releasedBodyIds: recoverable.map(body => body.id),
    activeBodiesBefore: hit.inspection.sailors.impacts.active, activeBodiesAfter: remaining.length,
    targetVisibleBefore: hitSailors.visible, targetVisibleAfter: recoveredSailors.visible,
    acceptedTime: recovered.runtime.naval.time }, waveHolds };
}

export function validateOrbitSequence(metadata) {
  const before = metadata.get('quarter-before');
  const orbit = metadata.get('orbit-after-chord');
  const pan = metadata.get('pan-after');
  const zoom = metadata.get('zoom-after');
  assert.notDeepEqual(vector(before.cameraPosition), vector(orbit.cameraPosition), 'actual orbit changes camera');
  assert.deepEqual(vector(before.target), vector(orbit.target), 'orbit retains model target');
  assert.notDeepEqual(vector(orbit.target), vector(pan.target), 'actual pan changes model target');
  near(pan.state.distance, orbit.state.distance, 'pan retains orbit distance within native damping precision', 1e-4);
  assert.ok(zoom.state.distance < pan.state.distance, 'actual wheel input zooms inward');
  return { orbitCameraBefore: vector(before.cameraPosition), orbitCameraAfter: vector(orbit.cameraPosition),
    panTargetBefore: vector(orbit.target), panTargetAfter: vector(pan.target),
    zoomDistanceBefore: pan.state.distance, zoomDistanceAfter: zoom.state.distance };
}

async function collection(name, labels, qa) {
  const directory = path.join(evidence, name);
  const files = await readdir(directory);
  for (const extension of ['png', 'json']) {
    const actual = files.filter(file => file.endsWith(`.${extension}`) && file !== 'integrity.json').sort();
    assert.deepEqual(actual, labels.map(label => `${label}.${extension}`).sort(), `${name}: exact paired capture inventory`);
  }
  const captures = [];
  const metadata = new Map();
  for (const label of labels) {
    const png = await readFile(path.join(directory, `${label}.png`));
    const metadataBytes = await readFile(path.join(directory, `${label}.json`));
    const packet = JSON.parse(metadataBytes.toString('utf8'));
    const dimensions = pngDimensions(png);
    validateMetadata(label, packet, dimensions, qa);
    metadata.set(label, packet);
    captures.push({ label, viewport: dimensions, engine: packet.engine.string, gpu: packet.gpu,
      ...(qa ? { quality: packet.quality, scenario: packet.runtime.runtime.scenario,
        acceptedTime: packet.runtime.naval.time, acceptedTick: packet.runtime.naval.tick,
        activeJoltBodies: packet.inspection.sailors.impacts.active } : { state: packet.state }),
      pngBytes: png.length, metadataBytes: metadataBytes.length, pngSha256: hash(png), metadataSha256: hash(metadataBytes) });
  }
  return { directory, captures, checks: qa ? validateQaSequence(metadata) : validateOrbitSequence(metadata) };
}

async function record(checkOnly) {
  const verificationBytes = await readFile(path.join(evidence, 'verification.json'));
  const verification = JSON.parse(verificationBytes.toString('utf8'));
  assert.equal(verification.filter, null, 'whole suite verification required');
  assert.deepEqual(verification.summary, { selected: 53, passed: 53, failed: 0, passedAll: true }, 'full suite evidence');
  assert.equal(verification.discoveredTests.length, 53, 'all discovered tests verified');
  assert.equal(verification.runs.length, 53, 'one completed run per discovered test');
  assert.ok(verification.runs.every(run => run.passed && run.exitCode === 0 && !run.timedOut && !run.processError), 'each full suite run passed');
  assert.match(verification.version.stdout, /4\.7\.2\.stable\.official\.ed1daf0bf/, 'verified Godot matches capture build');
  const diagnostics = [verification.version, ...verification.runs].flatMap(run =>
    `${run.stdout}\n${run.stderr}`.split(/\r?\n/).filter(line => /^\s*(WARNING:|ERROR:|SCRIPT ERROR:)/.test(line)));
  assert.deepEqual(diagnostics, [], 'Godot warnings/errors need investigation');

  const sources = [];
  const qaSource = await readFile(path.join(root, 'tools/capture-native-qa.gd'));
  assert.match(qaSource.toString('utf8'), /var prefix := "user:\/\/tests\/native-qa-capture-%d" % OS\.get_process_id\(\)/, 'QA uses process-isolated test storage');
  assert.match(qaSource.toString('utf8'), /"settings_storage":Settings\.new\(prefix\+"-settings\.json"\)/, 'QA injects isolated settings into actual router');
  const project = await readFile(path.join(root, 'project.godot'));
  assert.match(project.toString('utf8'), /3d\/physics_engine="Jolt Physics"/, 'native project selects Jolt');
  for (const source of ['tools/capture-native-qa.gd', 'tools/capture-ship-book-orbit.gd', 'project.godot']) {
    const bytes = await readFile(path.join(root, source));
    sources.push({ path: source, sha256: hash(bytes) });
  }
  const qa = await collection('visual-qa', qaLabels, true);
  const orbit = await collection('shipbook-orbit', orbitLabels, false);
  const recordedAtUtc = new Date().toISOString();
  const shared = { schemaVersion: 1, recordedAtUtc,
    scope: 'Saved native GPU capture integrity and metadata checks. Visual judgment belongs to separate review. Fixed capture ticks exclude FPS/performance claims.',
    sources, verification: { path: 'docs/migration/evidence/verification.json', sha256: hash(verificationBytes), summary: verification.summary, godotWarningsAndErrors: diagnostics } };
  const reports = [
    { ...shared, tool: 'tools/capture-native-qa.gd', captures: qa.captures, checks: qa.checks,
      isolatedQuality: { quality: 'balanced', qualityVerifiedInAllCaptureMetadata: true,
        sourceVerifiedStoragePrefix: 'user://tests/native-qa-capture-%d', settingsSuffix: '-settings.json',
        processIdIsolationVerifiedInCurrentCaptureSource: true, captureMetadataContainsStoragePath: false } },
    { ...shared, tool: 'tools/capture-ship-book-orbit.gd', captures: orbit.captures, checks: orbit.checks },
  ];
  if (!checkOnly) {
    for (const [index, group] of [qa, orbit].entries()) {
      await writeFile(path.join(group.directory, 'integrity.json'), JSON.stringify(reports[index], null, 2) + '\n');
    }
  }
  console.log(`NATIVE_QA_CAPTURE_INTEGRITY visualQa=${qa.captures.length} shipbookOrbit=${orbit.captures.length} realHits=${qa.checks.realHits.length} waveHolds=${qa.checks.waveHolds.length} tests=53 failures=0 godotWarningsAndErrors=0 mode=${checkOnly ? 'check-only' : 'record'}`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.ok(process.argv.slice(2).every(argument => argument === '--check-only'), 'only --check-only is supported');
  await record(process.argv.includes('--check-only'));
}
