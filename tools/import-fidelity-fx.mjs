/** Import completed, read-only particle/cloud/fog resources without rewriting original JSON.
 * rtk proxy node tools/import-fidelity-fx.mjs [--verify-only] [--source-root=PATH]
 * Original DDS/BC mip bytes are authoritative; RGBA/PNG are decoding adapters.
 */
import {readFile, writeFile, mkdir, readdir} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {decodeDDS, encodePNG, resolveWithin} from './import-fidelity-island.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DEFAULT_SOURCE = 'C:/Games/Pirates-REA-Reference-20261011';
const EXE_SHA256 = '0da87d60243280dea5965dbb23d099bcd0727db344de35886a5207e487a7e120';
const DATA = 'assets/data/fidelity_fx';
const TEXTURES = 'assets/textures/fidelity_fx';
const WORK = 'build/fidelity-fx-work/assets';
const PINNED = {
  'fidelity-rebuild/particles/FREEZE.json': '527b33ed3dd8b0dd6bd9c4e0c8df386389b887cc7fe439ea833ddbabded48373',
  'fidelity-rebuild/particles/source.mjs': 'dc7fcbd51ba48093df8459ea10a0cd8c59a284b7fc3ae5030563761218467ef6',
  'fidelity-rebuild/atmosphere/source-replay.mjs': 'c99fee60a93dd2357ed16955ad5248fd258b1ae46a64dfcd8e26850ec9fddcae',
  'fidelity-rebuild/atmosphere/native-semantics.mjs': '6e12e9f3459bcddfe0f1e9038ed5ca985de27f769d21269d7a892c0613689217',
  'fidelity-rebuild/atmosphere/native/source-provenance.json': '4d6508e8e33a375a38a7bee49907105a42cdce76d8498737d0c3806f05e5812b',
};
const PARTICLE_COUNTS = new Map([
  ['fx_cannon_fire_01.nif', [11, 0]],
  ['cannon_ball_splash_01.nif', [8, 7]],
  ['cannon_ball_splash_02.nif', [8, 5]],
  ['cannon_ball_splash_03.nif', [8, 7]],
]);
const ATMOSPHERE_COUNTS = new Map([
  ['domecloud1.nif', [0, 13]], ['domecloud2.nif', [0, 3]],
  ['domecloud3.nif', [0, 3]], ['domecloud4.nif', [0, 6]],
  ['domecloud5.nif', [0, 3]], ['fx_groundfog01.nif', [0, 20]],
]);
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const jsonBytes = value => Buffer.from(JSON.stringify(value, null, 2) + '\n');
const forward = relative => relative.replaceAll('\\', '/');

async function main(args) {
  const source = path.resolve(args.find(a => a.startsWith('--source-root='))?.slice(14) || DEFAULT_SOURCE);
  const verifyOnly = args.includes('--verify-only');
  const sources = [], outputs = [], originals = new Map(), copyChecks = [];
  const fixtureRecords = [], textureRecords = [], effects = [], atmosphereAssets = [];

  async function readSource(relative, expectedSha256, expectedBytes) {
    relative = forward(relative);
    const bytes = await readFile(resolveWithin(source, relative));
    const digest = sha256(bytes);
    if (expectedSha256) assert.equal(digest, expectedSha256, `Source identity mismatch: ${relative}`);
    if (expectedBytes !== undefined) assert.equal(bytes.length, expectedBytes, `Source size mismatch: ${relative}`);
    if (originals.has(relative)) assert.equal(digest, sha256(originals.get(relative)), `Source changed during import: ${relative}`);
    else { originals.set(relative, bytes); sources.push({path: relative, sha256: digest, bytes: bytes.length}); }
    return bytes;
  }
  async function output(relative, bytes) {
    const file = resolveWithin(ROOT, relative);
    if (verifyOnly) assert.equal(sha256(await readFile(file)), sha256(bytes), `Output drift: ${relative}`);
    else { await mkdir(path.dirname(file), {recursive: true}); await writeFile(file, bytes); }
    outputs.push({path: relative, sha256: sha256(bytes), bytes: bytes.length});
    return 'res://' + relative;
  }
  async function copy(relative, destination, expectedSha256, expectedBytes) {
    const bytes = await readSource(relative, expectedSha256, expectedBytes);
    const resource = await output(destination, bytes);
    assert.deepEqual(await readFile(resolveWithin(ROOT, destination)), bytes, `Original copy mismatch: ${destination}`);
    copyChecks.push({source: forward(relative), destination, sha256: sha256(bytes), bytes: bytes.length});
    return resource;
  }

  for (const [relative, digest] of Object.entries(PINNED)) await readSource(relative, digest);
  const frozen = JSON.parse(originals.get('fidelity-rebuild/particles/FREEZE.json'));
  assert.equal(frozen.source_exe_sha256, EXE_SHA256);
  const frozenPins = new Map(frozen.files.map(item => [forward(item.path), item]));
  const particleProvenancePath = 'fidelity-rebuild/particles/source-provenance.json';
  const particleProvenancePin = frozenPins.get(particleProvenancePath);
  assert.ok(particleProvenancePin, 'Frozen particle provenance absent');
  const particleProvenance = JSON.parse(await readSource(particleProvenancePath, particleProvenancePin.sha256, particleProvenancePin.bytes));
  const atmosphereProvenance = JSON.parse(originals.get('fidelity-rebuild/atmosphere/native/source-provenance.json'));
  assert.equal(atmosphereProvenance.native_exe_sha256, EXE_SHA256);
  assert.equal(atmosphereProvenance.status, 'pass');
  assert.equal(particleProvenance.assets.length, 4);
  assert.equal(particleProvenance.textures.length, 7);

  async function asset(group, name, sourcePath, jsonPin, rawPin, expected) {
    const bytes = await readSource(sourcePath, jsonPin.sha256, jsonPin.bytes);
    const model = JSON.parse(bytes);
    assert.equal(model.name, name);
    assert.equal(model.sha256, rawPin.sha256);
    assert.equal(forward(model.raw), forward(rawPin.raw));
    assert.equal(model.whole_file_consumed, true);
    assert.equal(model.all_buffers_exported, true);
    assert.equal(model.bytes_consumed, model.bytes);
    const counts = [model.blocks.filter(b => b.type === 'NiParticleSystem').length,
      model.blocks.filter(b => ['NiTriStrips', 'NiTriShape'].includes(b.type)).length];
    assert.deepEqual(counts, expected, `Original effect counts: ${name}`);
    const data_path = await copy(sourcePath, `${DATA}/${group}/assets-json/${name}.json`, jsonPin.sha256, jsonPin.bytes);
    const raw_source = await copy(rawPin.raw, `${DATA}/${group}/original/${name}`, rawPin.sha256, rawPin.bytes);
    return {id: name.replace(/\.nif$/, ''), file: name, data_path,
      system_count: counts[0], mesh_count: counts[1], raw_source,
      source_path: forward(sourcePath), sha256: sha256(bytes), raw_sha256: rawPin.sha256};
  }
  for (const [name, expected] of PARTICLE_COUNTS) {
    const sourcePath = `fidelity-rebuild/particles/assets-json/${name}.json`;
    const jsonPin = frozenPins.get(sourcePath);
    assert.ok(jsonPin, `Frozen original absent: ${name}`);
    const rawPin = particleProvenance.assets.find(item => path.posix.basename(forward(item.raw)) === name);
    assert.ok(rawPin, `Original identity absent: ${name}`);
    effects.push(await asset('particles', name, sourcePath, jsonPin, rawPin, expected));
  }
  for (const [name, expected] of ATMOSPHERE_COUNTS) {
    const item = atmosphereProvenance.assets.find(item => item.name === name);
    assert.ok(item, `Atmosphere original identity absent: ${name}`);
    const sourcePath = forward(item.export);
    assert.equal(sourcePath, `naval-study/atmosphere-fx/source-study/assets-json/${name}.json`);
    atmosphereAssets.push(await asset('atmosphere', name, sourcePath, {sha256: item.export_sha256}, item, expected));
  }

  // Frozen machine-code vectors, vtables, and function evidence remain exact source files.
  const particleEvidence = [...frozenPins.values()].filter(item =>
    item.path.startsWith('fidelity-rebuild/particles/') && item.path.endsWith('.json') &&
    !item.path.includes('/assets-json/') && !item.path.includes('/verification/'));
  for (const item of particleEvidence.sort((a, b) => a.path.localeCompare(b.path))) {
    const local = item.path.slice('fidelity-rebuild/particles/'.length);
    const data_path = await copy(item.path, `${DATA}/particles/${local}`, item.sha256, item.bytes);
    fixtureRecords.push({group: 'particles', file: local, data_path, sha256: item.sha256, bytes: item.bytes});
  }
  await copy('fidelity-rebuild/particles/FREEZE.json', `${DATA}/particles/FREEZE.json`, PINNED['fidelity-rebuild/particles/FREEZE.json']);
  const atmosphereNative = 'fidelity-rebuild/atmosphere/native';
  for (const name of (await readdir(resolveWithin(source, atmosphereNative))).filter(n => n.endsWith('.json')).sort()) {
    const sourcePath = `${atmosphereNative}/${name}`;
    const bytes = await readSource(sourcePath, PINNED[sourcePath]);
    const data_path = await copy(sourcePath, `${DATA}/atmosphere/native/${name}`, sha256(bytes), bytes.length);
    fixtureRecords.push({group: 'atmosphere', file: `native/${name}`, data_path, sha256: sha256(bytes), bytes: bytes.length});
  }
  // Preserve the input interpretation references alongside original NIF JSON, never import demo state.
  for (const relative of ['fidelity-rebuild/particles/source.mjs', 'fidelity-rebuild/atmosphere/source-replay.mjs',
    'fidelity-rebuild/atmosphere/native-semantics.mjs']) {
    const local = relative.slice('fidelity-rebuild/'.length);
    await copy(relative, `${DATA}/${local}`, PINNED[relative]);
  }

  const textureInputs = particleProvenance.textures.map(item => ({...item, group: 'particles'}));
  for (const name of ['cloud_bw.dds', 'fx_groundfog_crop01.dds']) {
    const item = atmosphereProvenance.textures.find(item => item.name === name);
    assert.ok(item, `Atmosphere texture absent: ${name}`);
    textureInputs.push({...item, sha256: item.raw_sha256, group: 'atmosphere'});
  }
  for (const item of textureInputs) {
    const bytes = await readSource(item.raw, item.sha256, item.bytes);
    const dds = decodeDDS(bytes);
    assert.equal(dds.fourCC, 'DXT5', `Unexpected source compression: ${item.name}`);
    if (item.width !== undefined) assert.equal(dds.levels[0].width, item.width);
    if (item.height !== undefined) assert.equal(dds.levels[0].height, item.height);
    if (item.mip_count !== undefined) assert.equal(dds.levels.length, Math.max(1, item.mip_count));
    const audited = atmosphereProvenance.textures.find(t => t.name === item.name);
    if (audited) assert.equal(sha256(dds.levels[0].bytes), audited.rgba_pixels_sha256, `Audited RGBA mismatch: ${item.name}`);
    const stem = `${TEXTURES}/${item.group}/${item.name.replace(/\.dds$/i, '')}`;
    const raw_source = await copy(item.raw, stem + '.dds', item.sha256, item.bytes);
    const texturePath = await output(stem + '.png', encodePNG(dds.levels[0].width, dds.levels[0].height, dds.levels[0].bytes));
    const compressed = Buffer.concat(dds.levels.map(level => level.original));
    assert.deepEqual(compressed, bytes.subarray(128), `Full DDS payload mismatch: ${item.name}`);
    const compressedMipPath = await output(stem + '.bc.bin', compressed);
    const rgbaMipPath = await output(stem + '.rgba.bin', Buffer.concat(dds.levels.map(level => level.bytes)));
    let rgbaOffset = 0, compressedOffset = 0;
    const levels = dds.levels.map((level, index) => {
      assert.equal(level.bytes.length, level.width * level.height * 4);
      const record = {level: index, width: level.width, height: level.height,
        rgbaOffset, rgbaBytes: level.bytes.length, rgbaSha256: sha256(level.bytes),
        compressedOffset, compressedBytes: level.original.length, compressedSha256: sha256(level.original),
        originalOffset: 128 + compressedOffset};
      rgbaOffset += level.bytes.length; compressedOffset += level.original.length;
      return record;
    });
    textureRecords.push({name: item.name, group: item.group, raw_source,
      source_path: forward(item.raw), originalSha256: item.sha256,
      compressedMipPath, rgbaMipPath, texturePath,
      width: dds.levels[0].width, height: dds.levels[0].height,
      mipmaps: dds.levels.length > 1, mipLevels: dds.levels.length,
      sourceMipCount: bytes.readUInt32LE(28), godotCompressedImageFormat: 'FORMAT_DXT5',
      format: dds.fourCC, levels,
      mipPolicy: 'DDS and BC retain every authored mip byte; RGBA decodes each authored level independently. PNG is a base-level preview. No mip regeneration.'});
  }
  assert.equal(textureRecords.length, 9);
  assert.equal(textureRecords.reduce((n, t) => n + t.mipLevels, 0), 47);
  for (const entry of sources) assert.equal(sha256(await readFile(resolveWithin(source, entry.path))), entry.sha256, `Read-only source changed: ${entry.path}`);
  const verification = {passed: true, sourceUnchanged: true, originalCopyCount: copyChecks.length,
    sourceCount: sources.length, outputCount: outputs.length + 2,
    particleSystemCount: effects.reduce((n, e) => n + e.system_count, 0),
    particleMeshCount: effects.reduce((n, e) => n + e.mesh_count, 0),
    atmosphereMeshCount: atmosphereAssets.reduce((n, e) => n + e.mesh_count, 0),
    textureCount: textureRecords.length, originalMipLevels: 47,
    auditedBaseRGBAHashes: textureInputs.filter(t => atmosphereProvenance.textures.some(a => a.name === t.name)).length,
    gpuRun: false, godotRun: false};
  const manifest = {schema_version: 1, native_exe_sha256: EXE_SHA256,
    effects, textures: textureRecords, atmosphere: {assets: atmosphereAssets,
      replay_input: 'Original source-replay.mjs NIF exports; hierarchy, UV, mesh buffers and controller keys are copied without changes.',
      source_replay_path: `res://${DATA}/atmosphere/source-replay.mjs`,
      native_semantics_path: `res://${DATA}/atmosphere/native-semantics.mjs`},
    fixtures: fixtureRecords, sources, outputs, verification,
    adaptation: {coordinates: 'Original native Z-up coordinates; consuming Godot presentation maps [x,z,-y].',
      source_dependency: 'Runtime resources use res://assets paths; importer alone uses source-root.',
      textures: 'Read compressedMipPath with declared Godot Image format and authored mipmaps flag; RGBA is explicit alternative decoding adapter.',
      scope: 'Resource import only; no original GPU frame equivalence or scene/physics changes claimed.'}};
  const manifestBytes = jsonBytes(manifest);
  await output(`${DATA}/manifest.json`, manifestBytes);
  const provenance = {schema_version: 1, native_exe_sha256: EXE_SHA256,
    source_set: 'Completed fidelity-rebuild/particles and fidelity-rebuild/atmosphere source replay inputs',
    manifest_path: `res://${DATA}/manifest.json`, manifest_sha256: sha256(manifestBytes), sources,
    original_copies: copyChecks, outputs: outputs.slice(), verification};
  await output('assets/provenance/fidelity-fx.json', jsonBytes(provenance));
  await mkdir(resolveWithin(ROOT, WORK), {recursive: true});
  await writeFile(resolveWithin(ROOT, `${WORK}/import-${verifyOnly ? 'verify' : 'result'}.json`), jsonBytes({
    schema_version: 1, mode: verifyOnly ? 'verify' : 'import',
    importer_sha256: sha256(await readFile(fileURLToPath(import.meta.url))),
    manifest_sha256: sha256(manifestBytes), ...verification, verifiedOutputFiles: outputs.length}));
  console.log(`FIDELITY_FX_${verifyOnly ? 'VERIFY' : 'IMPORT'} effects=${effects.length} particleSystems=${verification.particleSystemCount} particleMeshes=${verification.particleMeshCount} atmosphereAssets=${atmosphereAssets.length} atmosphereMeshes=${verification.atmosphereMeshCount} textures=${textureRecords.length} mips=47 fixtures=${fixtureRecords.length} sources=${sources.length} outputs=${outputs.length} passed=true`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch(error => { console.error(error.stack); process.exitCode = 1; });
}
