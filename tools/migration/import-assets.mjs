import { readFile, writeFile, mkdir, readdir, copyFile, access } from 'node:fs/promises'
import { createHash } from 'node:crypto'
import { resolve, dirname, relative, extname } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const targetRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..')
const sourceRoot = resolve(process.argv[2] ?? 'C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada')
const sourceHead = '9ad6a44daecd4ec36a8172d83ff27493feffe5dd'
if (sourceRoot.toLowerCase() === targetRoot.toLowerCase()) throw new Error('Source and target must be independent directories')
const hash = bytes => createHash('sha256').update(bytes).digest('hex')
const slash = value => value.replaceAll('\\', '/')
const files = []
const protectedFiles = new Set(['assets/textures/waternormals.jpg', 'assets/textures/foam.png', 'assets/models/ships/fuchuan-lod0.glb'])
async function exists(path) { try { await access(path); return true } catch { return false } }
async function copy(from, to, category) {
  const bytes = await readFile(resolve(sourceRoot, from))
  const dest = resolve(targetRoot, to)
  if (!dest.startsWith(targetRoot + '\\') && !dest.startsWith(targetRoot + '/')) throw new Error('Target escaped workspace')
  await mkdir(dirname(dest), { recursive: true })
  if (protectedFiles.has(to) && await exists(dest)) {
    if (hash(await readFile(dest)) !== hash(bytes)) throw new Error('Existing accepted asset bytes differ: ' + to)
  } else if (!await exists(dest) || hash(await readFile(dest)) !== hash(bytes)) {
    await copyFile(resolve(sourceRoot, from), dest)
  }
  files.push({ category, from: slash(from), to: slash(to), sha256: hash(bytes), bytes: bytes.length })
}
async function list(directory) {
  const result = []
  for (const entry of await readdir(resolve(sourceRoot, directory), { withFileTypes: true })) {
    const path = directory + '/' + entry.name
    if (entry.isDirectory()) result.push(...await list(path))
    else if (entry.isFile()) result.push(path)
  }
  return result.sort()
}
for (const path of await list('apps/game-client/public')) {
  await copy(path, 'assets/' + path.slice('apps/game-client/public/'.length), 'public')
}
for (const toolRoot of ['tools/ship-models', 'tools/sailor-models', 'tools/workspace']) {
  for (const path of await list(toolRoot)) {
    if (['.mjs', '.cjs', '.js', '.ts', '.json', '.md', '.patch'].includes(extname(path))) {
      await copy(path, 'assets/provenance/' + path, 'author-source')
    }
  }
}
for (const path of ['packages/adventure-core/src/mingqi/geography.ts', 'packages/adventure-core/src/catalog.ts',
  'packages/scene-engine/src/engine/assets/Assets.js', 'packages/scene-engine/src/engine/world/IslandMesh.js',
  'packages/scene-engine/src/config/constants.js', 'apps/game-client/src/simulation/NavalSceneView.ts',
  'apps/game-client/src/simulation/SailRig.ts']) {
  await copy(path, 'assets/provenance/' + path, 'reference-source')
}
const publicFiles = files.filter(file => file.category === 'public')
if (publicFiles.filter(file => extname(file.to) === '.glb').length !== 21) throw new Error('Expected eighteen ships and three sailors')

// Evaluate the original pure height function read-only. Do not derive the oracle
// from the native port. The already captured ports retain exact source doubles.
const terrainFixture = JSON.parse(await readFile(resolve(targetRoot, 'tests/fixtures/water-probe-terrain.json'), 'utf8'))
const ports = terrainFixture.ports
const originalSource = await readFile(resolve(sourceRoot, 'packages/adventure-core/src/mingqi/geography.ts'), 'utf8')
const originalFunction = originalSource.slice(originalSource.indexOf('export function sampleMingqiTerrainHeight'), originalSource.indexOf('export function mingqiTerrainSample'))
  .replace('export function', 'function').replaceAll(': number', '')
const [home, destination] = ports
const length = Math.hypot(destination.x - home.x, destination.z - home.z)
const ux = (destination.x - home.x) / length, uz = (destination.z - home.z) / length
const sample = new Function('MINGQI_PORT_GEOMETRY', 'home', 'length', 'ux', 'uz', originalFunction + '; return sampleMingqiTerrainHeight')(ports, home, length, ux, uz)
const points = [[0, 0], [3000, -3000], [-480, -60], [420, 160], [-60, 390]]
for (const port of ports) {
  points.push([port.x, port.z])
  for (const fraction of [0, .25, .5, .75, 1, 1.1]) {
    for (const angle of [0, .7, 1.9, 3.1, 4.8]) {
      points.push([port.islandX + Math.cos(angle) * port.radius * fraction, port.islandZ + Math.sin(angle) * port.radius * .82 * fraction])
    }
  }
}
for (const along of [.2, .32, .5, .68, .8]) {
  for (const across of [-140, -135, -110, -90, 0, 90, 110, 135, 140]) {
    points.push([home.x + ux * length * along - uz * across, home.z + uz * length * along + ux * across])
  }
}
await mkdir(resolve(targetRoot, 'assets/reference'), { recursive: true })
await writeFile(resolve(targetRoot, 'assets/reference/mingqi-geography.json'), JSON.stringify({sourceHead,
  source: 'packages/adventure-core/src/mingqi/geography.ts', sourceSha256: hash(Buffer.from(originalSource)),
  ports, samples: points.map(([x, z]) => ({x, z, height: sample(x, z)}))}, null, 2) + '\n')
// Preserve the original procedural geometry rather than replacing trees by cones.
// Randomized broadleaf/grass authoring uses a recorded deterministic seed here.
const authored = await import(pathToFileURL(resolve(sourceRoot, 'packages/scene-engine/src/engine/assets/Assets.js')))
const savedRandom = Math.random
let seed = 1650
Math.random = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 4294967296 }
const geometry = {}
try {
  for (const [name, create] of Object.entries({palm: authored.createPalmTreeGeometry,
    broadleaf: authored.createBroadleafTreeGeometry, grass: authored.createGrassPatchGeometry,
    shell: authored.createShellGeometry, starfish: authored.createStarfishGeometry, pebble: authored.createPebbleGeometry})) {
    const model = create()
    geometry[name] = {positions: Array.from(model.getAttribute('position').array),
      normals: Array.from(model.getAttribute('normal').array),
      colors: model.getAttribute('color') ? Array.from(model.getAttribute('color').array) : [],
      indices: model.index ? Array.from(model.index.array) : []}
    model.dispose()
  }
} finally { Math.random = savedRandom }
await writeFile(resolve(targetRoot, 'assets/reference/vegetation-geometry.json'), JSON.stringify({sourceHead,
  source: 'packages/scene-engine/src/engine/assets/Assets.js', seed: 1650, geometry}) + '\n')
await writeFile(resolve(targetRoot, 'assets/migration-manifest.json'), JSON.stringify({schemaVersion: 1,
  sourceRoot: slash(sourceRoot), sourceHead, targetRoot: slash(targetRoot),
  notes: 'Original bytes copied read-only. Native import data is generated separately by Godot. Source identity is the approved committed migration baseline.',
  files: files.sort((a, b) => a.to.localeCompare(b.to))}, null, 2) + '\n')
console.log(`ASSET_IMPORT public=${publicFiles.length} glb=21 provenance=${files.length - publicFiles.length} height_goldens=${points.length} manifest=assets/migration-manifest.json`)
