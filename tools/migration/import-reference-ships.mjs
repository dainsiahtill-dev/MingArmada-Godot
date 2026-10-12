import fs from 'node:fs';
import nodePath from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { deflateSync } from 'node:zlib';
import { execFileSync } from 'node:child_process';
import { parseDDS, decodeDDSLevel } from './reference_ship_dds.mjs';

const project = fileURLToPath(new URL('../../', import.meta.url));
const mapping = { fuchuan: ['barque', 32], fisherman: ['sloop1', 14], merchant: ['ship_merman', 36], voc: ['frigate', 40], patrol: ['ship_brigantine', 24], heavy: ['treasure_galleon', 52] };
const hash = data => createHash('sha256').update(data).digest('hex');
const canonical = v => [v[0], v[2], -v[1]];
const resource = path => `res://${path.replaceAll('\\', '/')}`;
function write(path, data) { fs.mkdirSync(nodePath.dirname(path), { recursive: true }); fs.writeFileSync(path, data); }
const jsonWrite = (path, value) => write(path, `${JSON.stringify(value)}\n`);
function bounds(vertices) {
  const min = [Infinity, Infinity, Infinity], max = [-Infinity, -Infinity, -Infinity];
  for (const v of vertices) for (let a = 0; a < 3; a += 1) { min[a] = Math.min(min[a], v[a]); max[a] = Math.max(max[a], v[a]); }
  return { min, max, size: max.map((value, axis) => value - min[axis]) };
}

// Split only disconnected original triangles. Weld duplicate seam positions for
// connectivity (one thousandth of a native unit); never merge/export vertices.
function rigComponents(mesh) {
  const parents = mesh.vertices.map((_, index) => index);
  const find = index => parents[index] === index ? index : parents[index] = find(parents[index]);
  const welded = new Map();
  mesh.worldVertices.forEach((vertex, index) => {
    const key = vertex.map(value => Math.round(value * 1000)).join(',');
    if (welded.has(key)) parents[find(index)] = find(welded.get(key));
    else welded.set(key, index);
  });
  for (const [a, b, c] of mesh.triangles) { parents[find(a)] = find(b); parents[find(c)] = find(b); }
  const parts = new Map();
  mesh.triangles.forEach((triangle, index) => {
    const root = find(triangle[0]); if (!parts.has(root)) parts.set(root, []); parts.get(root).push(index);
  });
  return [...parts.values()].map((triangleIds, componentId) => triangleSubset(mesh, triangleIds, componentId));
}
function triangleSubset(mesh, triangleIds, componentId) {
  const vertexIds = [...new Set(triangleIds.flatMap(index => mesh.triangles[index]))].sort((a, b) => a - b);
  const remap = new Map(vertexIds.map((index, mapped) => [index, mapped]));
  const subset = values => vertexIds.map(index => values[index]);
  const worldVertices = subset(mesh.worldVertices);
  const sampleIndices = [...new Set([0, Math.floor(vertexIds.length / 2), vertexIds.length - 1])];
  return { ...mesh, componentId, sourceVertexIndices: vertexIds, sourceTriangleIndices: triangleIds,
    sourceMeshTriangleCount: mesh.triangles.length, vertices: subset(mesh.vertices), worldVertices,
    normals: subset(mesh.normals), worldNormals: subset(mesh.worldNormals),
    uv_sets: mesh.uv_sets.map(subset), triangles: triangleIds.map(index => mesh.triangles[index].map(vertex => remap.get(vertex))),
    worldSamples: sampleIndices.map(index => ({ index, value: worldVertices[index] })) };
}
const crcTable = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
function crc(bytes) { let c = 0xffffffff; for (const byte of bytes) c = crcTable[(c ^ byte) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; }
function pngChunk(type, bytes) { const t = Buffer.from(type), b = Buffer.alloc(12 + bytes.length); b.writeUInt32BE(bytes.length); t.copy(b, 4); bytes.copy(b, 8); b.writeUInt32BE(crc(Buffer.concat([t, bytes])), b.length - 4); return b; }
function png(width, height, rgba) {
  const header = Buffer.alloc(13); header.writeUInt32BE(width); header.writeUInt32BE(height, 4); header[8] = 8; header[9] = 6;
  const rows = Buffer.alloc(height * (width * 4 + 1));
  for (let y = 0; y < height; y += 1) Buffer.from(rgba).copy(rows, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), pngChunk('IHDR', header), pngChunk('IDAT', deflateSync(rows)), pngChunk('IEND', Buffer.alloc(0))]);
}

export function parseGlb(buffer) {
  if (buffer.readUInt32LE(0) !== 0x46546c67 || buffer.readUInt32LE(4) !== 2 || buffer.readUInt32LE(8) !== buffer.length) throw Error('invalid GLB');
  const length = buffer.readUInt32LE(12), json = JSON.parse(buffer.toString('utf8', 20, 20 + length).trim());
  const offset = 20 + length;
  if (buffer.readUInt32LE(offset + 4) !== 0x004e4942) throw Error('missing original geometry BIN');
  return { json, bin: buffer.subarray(offset + 8, offset + 8 + buffer.readUInt32LE(offset)) };
}

function glbWriter() {
  const doc = { asset: { version: '2.0', generator: 'Original NIF rigid asset adapter; no invented geometry' }, scene: 0, scenes: [{ nodes: [0] }], nodes: [{ name: 'ship_root', children: [] }], meshes: [], materials: [], images: [], textures: [], samplers: [{ magFilter: 9729, minFilter: 9987, wrapS: 33071, wrapT: 33071 }], accessors: [], bufferViews: [], buffers: [{ byteLength: 0 }] };
  const chunks = []; let offset = 0;
  function view(data, target) { const padded = Buffer.alloc(Math.ceil(data.length / 4) * 4); data.copy(padded); const index = doc.bufferViews.length; doc.bufferViews.push({ buffer: 0, byteOffset: offset, byteLength: data.length, ...(target ? { target } : {}) }); chunks.push(padded); offset += padded.length; return index; }
  function numeric(values, size, index = false) {
    const data = Buffer.alloc(values.length * 4); values.forEach((value, i) => index ? data.writeUInt32LE(value, i * 4) : data.writeFloatLE(value, i * 4));
    const min = Array(size).fill(Infinity), max = Array(size).fill(-Infinity);
    values.forEach((value, i) => { min[i % size] = Math.min(min[i % size], value); max[i % size] = Math.max(max[i % size], value); });
    const id = doc.accessors.length; doc.accessors.push({ bufferView: view(data, index ? 34963 : 34962), componentType: index ? 5125 : 5126, count: values.length / size, type: ['SCALAR', 'VEC2', 'VEC3', 'VEC4'][size - 1], min, max }); return id;
  }
  const imageIds = new Map();
  function texture(name, bytes) { if (imageIds.has(name)) return imageIds.get(name); const image = doc.images.length; doc.images.push({ name, bufferView: view(bytes), mimeType: 'image/png' }); const id = doc.textures.length; doc.textures.push({ sampler: 0, source: image }); imageIds.set(name, id); return id; }
  return { doc, numeric, texture, finish() { doc.buffers[0].byteLength = offset; const raw = Buffer.from(JSON.stringify(doc)), json = Buffer.alloc(Math.ceil(raw.length / 4) * 4, 32); raw.copy(json); const bin = Buffer.concat(chunks), header = Buffer.alloc(20); header.writeUInt32LE(0x46546c67); header.writeUInt32LE(2, 4); header.writeUInt32LE(28 + json.length + bin.length, 8); header.writeUInt32LE(json.length, 12); header.writeUInt32LE(0x4e4f534a, 16); const bh = Buffer.alloc(8); bh.writeUInt32LE(bin.length); bh.writeUInt32LE(0x004e4942, 4); return Buffer.concat([header, json, bh, bin]); } };
}

export function importReferenceShips(reference, reuseInput = false) {
  const input = nodePath.join(project, 'Temp/reference-ships-import');
  if (!reuseInput) execFileSync('rtk', ['proxy', 'python', '-B', nodePath.join(project, 'tools/migration/read-reference-ship-nif.py'), reference, input], { stdio: 'inherit' });
  const inventory = JSON.parse(fs.readFileSync(nodePath.join(reference, 'naval-study/deep/asset-details/source-inventory.json'), 'utf8'));
  const catalog = new Map();
  for (const directory of fs.readdirSync(nodePath.join(reference, 'raw/fpk'))) {
    const folder = nodePath.join(reference, 'raw/fpk', directory); if (!fs.statSync(folder).isDirectory()) continue;
    for (const file of fs.readdirSync(folder)) if (file.toLowerCase().endsWith('.dds') && !catalog.has(file.toLowerCase())) catalog.set(file.toLowerCase(), nodePath.join(folder, file));
  }
  const textureCache = new Map();
  function originalTexture(name) {
    name = nodePath.basename(name.replaceAll('\\', '/'));
    if (textureCache.has(name)) return textureCache.get(name);
    const source = catalog.get(name.toLowerCase()); if (!source) throw Error(`missing original DDS ${name}`);
    const raw = fs.readFileSync(source), data = parseDDS(raw.buffer.slice(raw.byteOffset, raw.byteOffset + raw.byteLength));
    const stem = name.replace(/\.dds$/i, ''), folder = 'assets/textures/fidelity_naval/';
    const ddsPath = folder + name, bcPath = folder + stem + '.bc.bin', rgbaPath = folder + stem + '.rgba.bin';
    const decoded = data.levels.map((level, index) => Buffer.from(decodeDDSLevel(data, index)));
    write(nodePath.join(project, ddsPath), raw); write(nodePath.join(project, bcPath), Buffer.concat(data.levels.map(level => Buffer.from(level.bytes)))); write(nodePath.join(project, rgbaPath), Buffer.concat(decoded));
    const entry = { name, originalSource: nodePath.relative(reference, source).replaceAll('\\', '/'), originalSha256: hash(raw), ddsPath: resource(ddsPath), compressedMipPath: resource(bcPath), rgbaMipPath: resource(rgbaPath), width: data.width, height: data.height, format: data.fourcc, godotCompressedImageFormat: `FORMAT_${data.fourcc}`, mipmaps: data.mipCount > 1, mipLevels: data.mipCount, levels: data.levels.map((level, index) => ({ level: index, width: level.width, height: level.height, rgbaSha256: hash(decoded[index]) })) };
    const item = { entry, png: png(data.width, data.height, decoded[0]) }; textureCache.set(name, item); return item;
  }
  const manifest = { version: 2, axes: { up: '+Y', forward: '+Z', starboard: '-X', waterline: 0, units: 'metres' }, scope: 'Temporary Western original-reference appearances mapped onto unchanged game kinds; no Chinese historical reconstruction claim. Original rigid lowend geometry, hidden authored folded cloth, original DDS and authored mip bytes. Disconnected original triangles partitioned unchanged; rig attachment selection is a game assembly adapter. Original dynamic cloth/FFP/Sail shader/event scheduling unclosed.', mappings: {}, sources: [] };
  for (const [kind, [family, length]] of Object.entries(mapping)) {
    const read = profile => JSON.parse(fs.readFileSync(nodePath.join(input, `${family}-${profile}.json`), 'utf8'));
    const hull = read('lowend'), battle = read('battle'), anchors = read('anchors');
    if (hull.meshes.some(mesh => mesh.skin_instance)) throw Error('rigid profile unexpectedly contains skin');
    const body = hull.meshes.filter(mesh => !(mesh.flags & 1));
    const hullMeshes = body.filter(mesh => /^hull/i.test(mesh.name) && !/ship_sail_|ship_masts|ship_ropes|flag_/i.test(mesh.texture.slots?.base?.texture || ''));
    const structural = [...hullMeshes.filter(mesh => /ship_playercolor_/i.test(mesh.texture.slots?.base?.texture || ''))].sort((a, b) => b.triangles.length - a.triangles.length)[0];
    if (!structural) throw Error(`missing actual structural hull ${family}`);
    const nativeHullBounds = bounds(structural.worldVertices);
    const scale = length / nativeHullBounds.size[1];
    const gamePoint = value => canonical(value).map(x => x * scale);
    let sourceMasts = anchors.nodes.filter(node => /^mast_(main|fore|aft|mizzen)$/i.test(node.name));
    let mastSource = anchors.source.raw;
    if (sourceMasts.length === 0) sourceMasts = anchors.nodes.filter(node => /^mast_(main|fore|aft|mizzen)_topsail$/i.test(node.name));
    if (sourceMasts.length === 0) { sourceMasts = hull.nodes.filter(node => /^fx_mast_\d+$/i.test(node.name)); mastSource = hull.source.raw; }
    sourceMasts.sort((a, b) => a.worldOrigin[1] - b.worldOrigin[1]);
    const writer = glbWriter(), semantic = { hullMeshes: [], sailMeshes: [], sailFurledMeshes: [], mastMeshes: [], riggingMeshes: [], deckMeshes: [], masts: [], rudderName: 'rudder_pivot', cannons: [], flags: [], wakeName: 'socket_wake' };
    const group = (name, pivot, extra = {}) => { const index = writer.doc.nodes.length; writer.doc.nodes.push({ name, translation: pivot, children: [], extras: extra }); writer.doc.nodes[0].children.push(index); return index; };
    for (const [index, mast] of sourceMasts.entries()) { const name = `mast_${String(index + 1).padStart(2, '0')}`, pivot = gamePoint(mast.worldOrigin); const node = group(name, pivot); semantic.masts.push({ name, pivot, node, sourceId: mast.id, sourceName: mast.name, sourceFile: mastSource, sourceBasis: mast.rotation }); }
    const rudder = anchors.nodes.find(node => /^rudder$/i.test(node.name));
    group('rudder_pivot', rudder ? gamePoint(rudder.worldOrigin) : [0, 0, 0], { sourceId: rudder?.id, sourceName: rudder?.name, limitation: 'Source lowend has baked rigid rudder geometry; pivot retained without inventing separate rudder triangles.' });
    const wake = hull.nodes.find(node => /^Dummy_Wake$/i.test(node.name)); group('socket_wake', wake ? gamePoint(wake.worldOrigin) : [0, 0, 0]);
    const materials = [], meshes = [], textures = {};
    const folded = hull.meshes.filter(mesh => mesh.flags & 1 && /^Sails?_Furled:/i.test(mesh.name));
    const draw = body.concat(folded).flatMap(mesh => {
      const isFold = folded.includes(mesh);
      const open = isFold ? body.find(candidate => /^Sails?_Unfurled:/i.test(candidate.name) && candidate.name.split(':')[1] === mesh.name.split(':')[1]) : null;
      if (isFold && (!open || JSON.stringify(open.triangles) !== JSON.stringify(mesh.triangles) || JSON.stringify(open.uv_sets) !== JSON.stringify(mesh.uv_sets))) throw Error(`unmatched original fold ${family}/${mesh.name}`);
      // The verified barque lowend hull:1 packs six disconnected shroud panels
      // into the same player/decal diffuse stream as its connected hull.
      const mixedBarqueHull = family === 'barque' && mesh.node_id === 50;
      const isSplit = mixedBarqueHull || /ship_sail_|ship_masts|ship_ropes|ship_shrouds|flag_/i.test(mesh.texture.slots?.base?.texture || '');
      const parts = isSplit ? rigComponents(open || mesh) : [mesh];
      return parts.map(part => ({ mesh: isFold ? triangleSubset(mesh, part.sourceTriangleIndices, part.componentId) : part, original: mesh, part: 'hull', folded: isFold, pairedOpenId: open?.node_id }));
    }).concat(battle.meshes.filter(mesh => !(mesh.flags & 1) && !mesh.crew && !/crewman/i.test(mesh.texture.slots?.base?.texture || '')).map(mesh => ({ mesh, original: mesh, part: 'battle', folded: false })));
    for (const { mesh, original, part, folded: isFold, pairedOpenId } of draw) {
      const slots = mesh.texture.slots || {}, player = slots.base?.texture?.toLowerCase().startsWith('ship_playercolor_') ? slots.base.texture : null;
      const base = player ? slots.decal_0?.texture : slots.base?.texture;
      if (!base) throw Error(`source ${family}/${mesh.name} has no actual diffuse atlas`);
      const nativeBase = originalTexture(base); textures[base] = nativeBase.entry;
      let upgrade = null; if (player) { const p = originalTexture(player), u = originalTexture('ship_upgrade_empty.dds'); textures[player] = p.entry; textures['ship_upgrade_empty.dds'] = u.entry; upgrade = 'ship_upgrade_empty.dds'; }
      // Native names sometimes say Sail for rope-only geometry (barque Sail:4).
      // Material provenance prevents rigging from acquiring cloth/deck controls.
      const isBakedHullRig = family === 'barque' && part === 'hull' && mesh.node_id === 50 && mesh.componentId !== undefined && mesh.vertices.length === 26 && mesh.triangles.length === 36 && bounds(mesh.worldVertices.map(gamePoint)).max[1] > 10;
      const isSail = !/ship_ropes|ship_masts|ship_shrouds|flag_/i.test(base) && (/^Sail/i.test(mesh.name) || /ship_sail_/i.test(base)), isFlag = /^flag_/i.test(base);
      const isTimber = /ship_masts/i.test(base), isRope = isBakedHullRig || /ship_ropes|ship_shrouds/i.test(base);
      const isHull = part === 'hull' && hullMeshes.includes(original) && !isBakedHullRig;
      let parent = 0, pivot = [0, 0, 0], rotation = null, mastName = null;
      const sourceParent = part === 'battle' ? battle.nodes.find(node => node.id === battle.nodes.find(node => node.id === mesh.node_id).parent) : null;
      const gun = part === 'battle' && /cannon/i.test(base) ? sourceParent?.name.match(/^cannon_([ps])_(\d+)/i) : null;
      const suffix = mesh.componentId === undefined ? '' : `_component_${String(mesh.componentId).padStart(2, '0')}`;
      let name = `${isFold ? 'sail_furled' : isSail ? 'sail' : isFlag ? 'flag' : isHull ? 'hull' : 'native'}_${part}_${mesh.node_id}${suffix}`;
      if (gun) {
        const side = gun[1].toLowerCase() === 'p' ? 'port' : 'starboard', id = gun[2].padStart(2, '0');
        const sourceNode = sourceParent;
        pivot = gamePoint(sourceNode.worldOrigin);
        const cannonName = `cannon_${side}_${id}`, barrelName = `barrel_${side}_${id}`, socketName = `socket_smoke_${side}_${id}`;
        const g = group(cannonName, pivot), angle = side === 'port' ? Math.PI / 2 : -Math.PI / 2;
        writer.doc.nodes[g].rotation = [0, Math.sin(angle / 2), 0, Math.cos(angle / 2)];
        const barrel = writer.doc.nodes.length; writer.doc.nodes.push({ name: barrelName, children: [] }); writer.doc.nodes[g].children.push(barrel); parent = barrel; rotation = angle;
        const extent = bounds(mesh.worldVertices.map(gamePoint)), muzzle = [side === 'port' ? extent.max[0] : extent.min[0], (extent.min[1] + extent.max[1]) / 2, (extent.min[2] + extent.max[2]) / 2];
        const relative = muzzle.map((v, axis) => v - pivot[axis]), local = [Math.cos(angle) * relative[0] - Math.sin(angle) * relative[2], relative[1], Math.sin(angle) * relative[0] + Math.cos(angle) * relative[2]];
        const smoke = writer.doc.nodes.length; writer.doc.nodes.push({ name: socketName, translation: local }); writer.doc.nodes[g].children.push(smoke);
        semantic.cannons.push({ name: cannonName, barrelName, socketName, sourceId: sourceNode.id, sourceName: sourceNode.name, sourceFile: battle.source.raw, side, pivot, muzzle });
      } else if ((isSail || isTimber || isRope || isFlag) && semantic.masts.length) {
        // Fold endpoints must share the open panel's coordinate space. Rigging
        // uses its highest actual attachment; external bow/stern poles remain fixed.
        const pairing = isFold ? draw.find(item => !item.folded && item.mesh.node_id === pairedOpenId && item.mesh.componentId === mesh.componentId).mesh : mesh;
        const points = pairing.worldVertices.map(gamePoint), extent = bounds(points);
        const high = [...points].sort((a, b) => b[1] - a[1])[0];
        const z = isSail || isTimber ? (extent.min[2] + extent.max[2]) / 2 : high[2];
        const mast = [...semantic.masts].sort((a, b) => Math.abs(a.pivot[2] - z) - Math.abs(b.pivot[2] - z))[0];
        // A single tilted mast has no neighbouring pivot to bound its top.
        // Its wider verified envelope still excludes the stern flag/bow spar.
        const margin = length * (semantic.masts.length === 1 ? 0.20 : 0.12);
        const inside = z >= Math.min(...semantic.masts.map(item => item.pivot[2])) - margin && z <= Math.max(...semantic.masts.map(item => item.pivot[2])) + margin;
        if (isSail || isBakedHullRig || inside && extent.max[1] >= mast.pivot[1] + 0.25) { parent = mast.node; pivot = mast.pivot; mastName = mast.name; }
      }
      const vertices = mesh.worldVertices.map(value => { const v = gamePoint(value).map((x, axis) => x - pivot[axis]); return rotation === null ? v : [Math.cos(rotation) * v[0] - Math.sin(rotation) * v[2], v[1], Math.sin(rotation) * v[0] + Math.cos(rotation) * v[2]]; });
      const normals = mesh.worldNormals.map(value => { const v = canonical(value), l = Math.hypot(...v) || 1; const n = v.map(x => x / l); return rotation === null ? n : [Math.cos(rotation) * n[0] - Math.sin(rotation) * n[2], n[1], Math.sin(rotation) * n[0] + Math.cos(rotation) * n[2]]; });
      const alphaFlags = mesh.alpha?.flags || 0, materialId = writer.doc.materials.length;
      writer.doc.materials.push({ name: `${family}_${part}_${mesh.node_id}`, doubleSided: true, pbrMetallicRoughness: { baseColorFactor: [...(mesh.material.diffuse || [1, 1, 1]), mesh.material.alpha ?? 1], baseColorTexture: { index: writer.texture(base, nativeBase.png) }, metallicFactor: 0, roughnessFactor: 0.82 }, ...(player ? {} : alphaFlags & 512 ? { alphaMode: 'MASK', alphaCutoff: mesh.alpha.threshold / 255 } : alphaFlags & 1 ? { alphaMode: 'BLEND' } : {}) });
      materials.push({ nodeName: name, sourceId: mesh.node_id, sourcePart: part, baseTexture: base, playerTexture: player, upgradeTexture: upgrade, damageUv2: mesh.uv_sets.length > 1, sourceMaterial: mesh.material, sourceTextureSlots: slots, alpha: mesh.alpha, zbuffer: mesh.zbuffer, stencil: mesh.stencil });
      const attributes = { POSITION: writer.numeric(vertices.flat(), 3), NORMAL: writer.numeric(normals.flat(), 3) };
      mesh.uv_sets.forEach((uv, index) => { attributes[`TEXCOORD_${index}`] = writer.numeric(uv.flat(), 2); });
      const meshId = writer.doc.meshes.length; writer.doc.meshes.push({ name, primitives: [{ attributes, indices: writer.numeric(mesh.triangles.flat(), 1, true), material: materialId }] });
      const nodeId = writer.doc.nodes.length; writer.doc.nodes.push({ name, mesh: meshId, extras: { sourceNodeId: mesh.node_id, sourceName: mesh.name, sourcePart: part, restVisible: !isFold } }); writer.doc.nodes[parent].children.push(nodeId);
      const role = { name, sourceId: mesh.node_id, sourceName: mesh.name, sourcePart: part, componentId: mesh.componentId, mastName, restVisible: !isFold };
      if (isHull) { semantic.hullMeshes.push(role); semantic.deckMeshes.push(role); }
      if (isFold) semantic.sailFurledMeshes.push({ ...role, pairedOpenName: `sail_hull_${pairedOpenId}${suffix}`, pairedSourceId: pairedOpenId, sourceTopologyMatch: true });
      else if (isSail) semantic.sailMeshes.push(role);
      if (isTimber) semantic.mastMeshes.push(role);
      if (isRope) semantic.riggingMeshes.push(role);
      if (isFlag) semantic.flags.push(role);
      meshes.push({ name, sourceId: mesh.node_id, sourcePart: part, sourceName: mesh.name, sourceVertices: mesh.vertices, triangles: mesh.triangles, uvSets: mesh.uv_sets, worldSamples: mesh.worldSamples, restVisible: !isFold, gameBounds: bounds(mesh.worldVertices.map(gamePoint)), sourceVertexIndices: mesh.sourceVertexIndices, sourceTriangleIndices: mesh.sourceTriangleIndices, sourceMeshTriangleCount: mesh.sourceMeshTriangleCount });
    }
    const modelPath = `assets/models/fidelity_naval/${family}.glb`, sourcePath = `assets/data/fidelity_naval/${family}-source.json`, glb = writer.finish(); write(nodePath.join(project, modelPath), glb);
    const source = { family, sources: [hull.source, battle.source, anchors.source], meshes, nativeNodes: { lowend: hull.nodes, battle: battle.nodes, anchors: anchors.nodes }, scope: manifest.scope };
    jsonWrite(nodePath.join(project, sourcePath), source);
    const entry = { family, modelPath: resource(modelPath), sourceJsonPath: resource(sourcePath), convertedSha256: hash(glb), sourceJsonSha256: hash(fs.readFileSync(nodePath.join(project, sourcePath))), hullBounds: bounds(hullMeshes.flatMap(mesh => mesh.worldVertices.map(gamePoint))), nativeHullBounds, waterline: 0, uniformScale: scale, lodPolicy: 'same_source_lowend', storedTriangles: meshes.reduce((sum, mesh) => sum + mesh.triangles.length, 0), renderedTriangles: meshes.filter(mesh => mesh.restVisible).reduce((sum, mesh) => sum + mesh.triangles.length, 0), renderedVertices: meshes.filter(mesh => mesh.restVisible).reduce((sum, mesh) => sum + mesh.sourceVertices.length, 0), foldedControl: folded.length ? 'original_authored_fold' : 'game_fold2D_no_authored_lowend_fold', semantics: semantic, materials, textures };
    manifest.mappings[kind] = entry; manifest.sources.push(...source.sources.map(record => ({ family, raw: record.raw, sha256: record.sha256, bytes: record.bytes })));
    console.log(JSON.stringify({ kind, family, meshes: meshes.length, triangles: entry.renderedTriangles, vertices: entry.renderedVertices, masts: semantic.masts.map(mast => ({ name: mast.name, sourceName: mast.sourceName, pivot: mast.pivot })), guns: semantic.cannons.length, scale }));
  }
  manifest.converter = { path: 'tools/migration/import-reference-ships.mjs', ddsDecoderOriginalSource: 'fidelity-rebuild/naval/dds.mjs', ddsDecoderSha256: hash(fs.readFileSync(new URL('./reference_ship_dds.mjs', import.meta.url))) };
  jsonWrite(nodePath.join(project, 'assets/data/fidelity_naval/ships-manifest.json'), manifest);
  return manifest;
}

if (process.argv[1] && nodePath.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  importReferenceShips(nodePath.resolve(process.argv[2] || 'C:/Games/Pirates-REA-Reference-20261011'), process.argv.includes('--reuse-input'));
}
