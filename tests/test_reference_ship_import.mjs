import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

const root = new URL('../', import.meta.url);
const converterUrl = new URL('tools/migration/import-reference-ships.mjs', root);
assert.ok(existsSync(converterUrl), 'original reference ship converter exists');
const { parseGlb } = await import(converterUrl.href);
const manifest = JSON.parse(readFileSync(new URL('assets/data/fidelity_naval/ships-manifest.json', root), 'utf8'));
const expected = { fuchuan: 'barque', fisherman: 'sloop1', merchant: 'ship_merman', voc: 'frigate', patrol: 'ship_brigantine', heavy: 'treasure_galleon' };
const path = value => new URL(value.replace(/^res:\/\//, ''), root);
const hash = value => createHash('sha256').update(value).digest('hex');

function worldPoint(document, index, point) {
  let result = [...point];
  let current = index;
  while (current >= 0) {
    const node = document.nodes[current];
    result = result.map((value, axis) => value * (node.scale?.[axis] ?? 1));
    if (node.rotation) {
      const [x, y, z, w] = node.rotation;
      const t = [2 * (y * result[2] - z * result[1]), 2 * (z * result[0] - x * result[2]), 2 * (x * result[1] - y * result[0])];
      result = [result[0] + w * t[0] + y * t[2] - z * t[1], result[1] + w * t[1] + z * t[0] - x * t[2], result[2] + w * t[2] + x * t[1] - y * t[0]];
    }
    result = result.map((value, axis) => value + (node.translation?.[axis] ?? 0));
    current = document.nodes.findIndex(parent => parent.children?.includes(current));
  }
  return result;
}

// Independent original NIF row-vector TRS evaluation, rather than the
// converter's API-prebaked worldVertices or selected worldSamples.
function nativeWorldPoint(nodes, nodeId, point) {
  let result = [...point];
  let node = nodes.find(item => item.id === nodeId);
  while (node && node.parent !== null) {
    result = [0, 1, 2].map(column => result.reduce((sum, value, row) => sum + value * node.rotation[row][column], 0) * node.scale + node.translation[column]);
    node = nodes.find(item => item.id === node.parent);
  }
  return result;
}

function accessor(glb, index) {
  const a = glb.json.accessors[index];
  const view = glb.json.bufferViews[a.bufferView];
  const count = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4 }[a.type];
  const bytes = { 5126: 4, 5125: 4, 5123: 2 }[a.componentType];
  assert.ok(count && bytes, 'original geometry accessor is numeric');
  const offset = (view.byteOffset || 0) + (a.byteOffset || 0);
  const values = [];
  for (let i = 0; i < a.count * count; i += 1) {
    values.push(a.componentType === 5126 ? glb.bin.readFloatLE(offset + i * bytes)
      : a.componentType === 5125 ? glb.bin.readUInt32LE(offset + i * bytes) : glb.bin.readUInt16LE(offset + i * bytes));
  }
  return values;
}

test('all six temporary appearances are project-contained original reference families', () => {
  assert.deepEqual(Object.fromEntries(Object.entries(manifest.mappings).map(([kind, entry]) => [kind, entry.family])), expected);
  assert.deepEqual(manifest.axes, { up: '+Y', forward: '+Z', starboard: '-X', waterline: 0, units: 'metres' });
  assert.match(manifest.scope, /temporary|临时/i);
  for (const entry of Object.values(manifest.mappings)) {
    assert.ok(existsSync(path(entry.modelPath)) && existsSync(path(entry.sourceJsonPath)));
    assert.equal(hash(readFileSync(path(entry.modelPath))), entry.convertedSha256);
    assert.equal(entry.waterline, 0);
    assert.ok(Number.isFinite(entry.uniformScale) && entry.uniformScale > 0);
    assert.equal(entry.lodPolicy, 'same_source_lowend');
  }
});

for (const [kind, family] of Object.entries(expected)) {
  test(`${family} GLB contains real source positions, triangles, UV and material roles`, () => {
    const entry = manifest.mappings[kind];
    const source = JSON.parse(readFileSync(path(entry.sourceJsonPath), 'utf8'));
    const glb = parseGlb(readFileSync(path(entry.modelPath)));
    assert.equal(source.family, family);
    assert.ok(source.sources.some(item => item.raw.endsWith(`${family}-lowend.nif`) && /^[a-f0-9]{64}$/.test(item.sha256)));
    assert.ok(source.meshes.length > 8 && source.meshes.every(mesh => mesh.sourceVertices.length > 0));
    let triangles = 0;
    let vertices = 0;
    for (const mesh of source.meshes) {
      const index = glb.json.nodes.findIndex(node => node.name === mesh.name);
      assert.ok(index >= 0, `source mesh ${mesh.name} is actually in the GLB`);
      const node = glb.json.nodes[index];
      const primitive = glb.json.meshes[node.mesh].primitives[0];
      const position = accessor(glb, primitive.attributes.POSITION);
      const indices = accessor(glb, primitive.indices);
      assert.deepEqual(indices, mesh.triangles.flat(), 'actual original triangles survive export');
      assert.equal(position.length, mesh.sourceVertices.length * 3);
      const nativeNodes = source.nativeNodes[mesh.sourcePart === 'hull' ? 'lowend' : 'battle'];
      for (let vertex = 0; vertex < mesh.sourceVertices.length; vertex += 1) {
        const original = nativeWorldPoint(nativeNodes, mesh.sourceId, mesh.sourceVertices[vertex]);
        const actual = worldPoint(glb.json, index, position.slice(vertex * 3, vertex * 3 + 3));
        const target = [original[0], original[2], -original[1]].map(value => value * entry.uniformScale);
        for (let axis = 0; axis < 3; axis += 1) assert.ok(Math.abs(actual[axis] - target[axis]) < 0.00002, 'every rest vertex survives original hierarchy and component reparenting');
      }
      for (const sample of mesh.worldSamples) {
        const original = sample.value;
        const actual = worldPoint(glb.json, index, position.slice(sample.index * 3, sample.index * 3 + 3));
        const target = [original[0], original[2], -original[1]].map(value => value * entry.uniformScale);
        for (let axis = 0; axis < 3; axis += 1) assert.ok(Math.abs(actual[axis] - target[axis]) < 0.00002, 'canonical vertices agree with independent original API world samples');
      }
      if (mesh.uvSets.length > 0) assert.deepEqual(accessor(glb, primitive.attributes.TEXCOORD_0), mesh.uvSets[0].flat().map(Math.fround));
      if (mesh.uvSets.length > 1) assert.deepEqual(accessor(glb, primitive.attributes.TEXCOORD_1), mesh.uvSets[1].flat().map(Math.fround));
      assert.ok(glb.json.materials[primitive.material].pbrMetallicRoughness.baseColorTexture, 'native diffuse texture is present');
      triangles += indices.length / 3;
      vertices += position.length / 3;
    }
    assert.ok(triangles > 300 && vertices > 700, 'no symbolic/proxy hull can stand in for the original mesh');
    assert.equal(triangles, entry.storedTriangles ?? entry.renderedTriangles);
    assert.ok(entry.semantics.deckMeshes.length > 0, 'crew deck support identifies actual original hull meshes');
    assert.ok(entry.semantics.masts.length > 0 && entry.semantics.cannons.length > 0, 'original mast and gun source anchors are exposed');
    for (const material of entry.materials.filter(item => item.playerTexture)) {
      assert.notEqual(material.baseTexture, material.playerTexture, 'four-pixel player tint never replaces the wood atlas');
      assert.ok(material.baseTexture && material.upgradeTexture);
    }
  });
}

test('every original DDS and authored mip payload is retained byte-for-byte', () => {
  const seen = new Set();
  for (const entry of Object.values(manifest.mappings)) {
    for (const texture of Object.values(entry.textures)) {
      if (seen.has(texture.ddsPath)) continue;
      seen.add(texture.ddsPath);
      const dds = readFileSync(path(texture.ddsPath));
      assert.equal(hash(dds), texture.originalSha256);
      assert.equal(dds.readUInt32LE(16), texture.width);
      assert.equal(dds.readUInt32LE(12), texture.height);
      assert.equal(Math.max(1, dds.readUInt32LE(28)), texture.mipLevels);
      assert.deepEqual(readFileSync(path(texture.compressedMipPath)), dds.subarray(128));
      const rgba = readFileSync(path(texture.rgbaMipPath));
      const expectedBytes = texture.levels.reduce((sum, level) => sum + level.width * level.height * 4, 0);
      assert.equal(rgba.length, expectedBytes, 'decoded fallback has each original mip, not regenerated mipmaps');
    }
  }
  assert.ok(seen.size > 20, 'actual multi-family wood, sails, rigging and gun textures are present');
});

test('source ropes, masts, flags and hidden cloth cannot enter the default cloth or deck supports', () => {
  for (const entry of Object.values(manifest.mappings)) {
    const source = JSON.parse(readFileSync(path(entry.sourceJsonPath), 'utf8'));
    const cloth = new Set(entry.semantics.sailMeshes.map(mesh => mesh.name));
    const deck = new Set(entry.semantics.deckMeshes.map(mesh => mesh.name));
    for (const material of entry.materials) {
      if (/ship_ropes|ship_masts|flag_/i.test(material.baseTexture)) {
        assert.ok(!cloth.has(material.nodeName), `${entry.family}: ${material.baseTexture} is not cloth`);
        assert.ok(!deck.has(material.nodeName), `${entry.family}: ${material.baseTexture} is not a crew floor`);
      }
    }
    for (const mesh of source.meshes) {
      const nodes = source.nativeNodes[mesh.sourcePart === 'hull' ? 'lowend' : 'battle'];
      const original = nodes.find(node => node.id === mesh.sourceId);
      if (original.flags & 1) {
        assert.equal(mesh.restVisible, false, `${entry.family}: native hidden cloth stays hidden at rest`);
        assert.ok(entry.semantics.sailFurledMeshes.some(item => item.name === mesh.name), 'hidden resource is an explicitly controlled authored fold');
        assert.ok(!cloth.has(mesh.name) && !deck.has(mesh.name), 'default controls exclude hidden resources');
      } else assert.notEqual(mesh.restVisible, false);
    }
  }
});

test('real native folded cloth pairs preserve source topology under the same mast as the open panel', () => {
  const expectedFoldCount = { barque: 0, sloop1: 4, ship_merman: 5, frigate: 6, ship_brigantine: 6, treasure_galleon: 5 };
  for (const entry of Object.values(manifest.mappings)) {
    const source = JSON.parse(readFileSync(path(entry.sourceJsonPath), 'utf8'));
    const glb = parseGlb(readFileSync(path(entry.modelPath)));
    const folded = entry.semantics.sailFurledMeshes;
    assert.ok(Array.isArray(folded), 'authored folded resources are exposed separately');
    assert.equal(new Set(folded.map(item => item.sourceId)).size, expectedFoldCount[entry.family], 'every original folded source mesh is retained even when packed panels are partitioned');
    for (const item of folded) {
      const fold = source.meshes.find(mesh => mesh.name === item.name);
      const open = source.meshes.find(mesh => mesh.name === item.pairedOpenName);
      assert.ok(fold && open, 'both actual source poses are stored');
      assert.equal(item.restVisible, false);
      assert.equal(fold.restVisible, false);
      assert.deepEqual(fold.triangles, open.triangles);
      assert.deepEqual(fold.uvSets, open.uvSets);
      assert.equal(fold.sourceVertices.length, open.sourceVertices.length);
      const foldedNode = glb.json.nodes.findIndex(node => node.name === item.name);
      const openNode = glb.json.nodes.findIndex(node => node.name === item.pairedOpenName);
      assert.equal(glb.json.nodes.findIndex(node => node.children?.includes(foldedNode)), glb.json.nodes.findIndex(node => node.children?.includes(openNode)), 'authored endpoints share the actual mast coordinate space');
    }
  }
});

test('native timber components fall with actual masts while fixed bow and stern attachments stay on the hull', () => {
  for (const entry of Object.values(manifest.mappings)) {
    const source = JSON.parse(readFileSync(path(entry.sourceJsonPath), 'utf8'));
    const glb = parseGlb(readFileSync(path(entry.modelPath)));
    assert.ok(entry.semantics.mastMeshes?.some(item => item.mastName), `${entry.family}: actual wood is carried by the mast`);
    const originals = new Map();
    for (const item of [...entry.semantics.mastMeshes, ...entry.semantics.riggingMeshes, ...entry.semantics.flags]) {
      const nodeIndex = glb.json.nodes.findIndex(node => node.name === item.name);
      const parent = glb.json.nodes.find(node => node.children?.includes(nodeIndex));
      assert.equal(parent.name, item.mastName || 'ship_root', 'source rig is attached once to its selected original pivot');
      const mesh = source.meshes.find(mesh => mesh.name === item.name);
      assert.ok(mesh.sourceTriangleIndices, 'rigging is a traceable original triangle component');
    }
    // Mixed diffuse meshes may contain both fixed hull and carried rigging.
    // Coverage is checked over every component, including the fixed hull part.
    for (const mesh of source.meshes.filter(item => item.sourceTriangleIndices)) {
      const key = `${mesh.sourcePart}/${mesh.sourceId}`;
      if (!originals.has(key)) originals.set(key, { count: mesh.sourceMeshTriangleCount, ids: [] });
      originals.get(key).ids.push(...mesh.sourceTriangleIndices);
    }
    for (const { count, ids } of originals.values()) assert.deepEqual(ids.sort((a, b) => a - b), Array.from({ length: count }, (_, i) => i), 'component partition preserves every original triangle exactly once');
  }
  assert.deepEqual(manifest.mappings.fuchuan.semantics.masts.map(item => item.sourceId), [44, 12, 65], 'barque uses its actual fore/main/mizzen source anchors');
  const frigate = manifest.mappings.voc;
  const source = JSON.parse(readFileSync(path(frigate.sourceJsonPath), 'utf8'));
  const bow = frigate.semantics.mastMeshes.filter(item => source.meshes.find(mesh => mesh.name === item.name).gameBounds.min[2] > 22);
  assert.ok(bow.length > 0 && bow.every(item => item.mastName === null), 'original frigate forward angled spar stays fixed instead of falling as a whole body');
});

test('packed hull rigging and shroud atlases follow actual masts without carrying the connected hull', () => {
  const barque = manifest.mappings.fuchuan;
  const barqueSource = JSON.parse(readFileSync(path(barque.sourceJsonPath), 'utf8'));
  const barqueGlb = parseGlb(readFileSync(path(barque.modelPath)));
  const rig = barqueSource.meshes.filter(mesh => mesh.sourceId === 50 && mesh.triangles.length === 36 && mesh.sourceVertices.length === 26 && mesh.gameBounds.max[1] > 10);
  assert.equal(rig.length, 6, 'all six real high shroud pieces packed in the barque diffuse mesh are partitioned');
  for (const mesh of rig) {
    assert.ok(barque.semantics.riggingMeshes.some(item => item.name === mesh.name && item.mastName), 'packed high rig is actually carried');
    assert.ok(!barque.semantics.deckMeshes.some(item => item.name === mesh.name), 'high shrouds never become crew floors');
  }
  const hull = barqueSource.meshes.find(mesh => mesh.sourceId === 50 && mesh.triangles.length === 544);
  assert.ok(hull && barque.semantics.hullMeshes.some(item => item.name === hull.name), 'the real connected hull is retained separately');
  const hullNode = barqueGlb.json.nodes.findIndex(node => node.name === hull.name);
  assert.equal(barqueGlb.json.nodes.find(node => node.children?.includes(hullNode)).name, 'ship_root', 'the hull stays fixed while its disconnected high rig falls');
  for (const [kind, sourceId, threshold] of [['fisherman', 81, 11], ['merchant', 15, 20], ['voc', 21, 27], ['patrol', 31, 17], ['heavy', 25, 31]]) {
    const entry = manifest.mappings[kind];
    const source = JSON.parse(readFileSync(path(entry.sourceJsonPath), 'utf8'));
    const glb = parseGlb(readFileSync(path(entry.modelPath)));
    const high = source.meshes.filter(mesh => mesh.sourcePart === 'hull' && mesh.sourceId === sourceId && mesh.gameBounds.max[1] > threshold);
    assert.ok(high.length > 0, 'actual upper source structure is present');
    for (const mesh of high) {
      const index = glb.json.nodes.findIndex(node => node.name === mesh.name);
      assert.match(glb.json.nodes.find(node => node.children?.includes(index)).name, /^mast_\d+$/, `${kind}: the actual high source structure is not left upright on the hull`);
    }
  }
});
