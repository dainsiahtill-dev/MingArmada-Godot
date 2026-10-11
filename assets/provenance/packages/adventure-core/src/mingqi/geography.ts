import { PORTS } from '../catalog.js'

export type MingqiPortGeometry = Readonly<{
  id: string; name: string; faction: 'zheng' | 'qing' | 'voc' | 'pirates'
  x: number; z: number; islandX: number; islandZ: number; radius: number; peak: number
}>
type Point = Readonly<{ x: number; z: number }>
const geometry = (id: string): MingqiPortGeometry => {
  const port = PORTS.find(value => value.id === id)!
  return Object.freeze({ id: port.id, name: port.name, faction: port.faction, x: port.x, z: port.z,
    islandX: port.islandX, islandZ: port.islandZ, radius: port.radius, peak: port.peak })
}
export const MINGQI_PORT_GEOMETRY: readonly MingqiPortGeometry[] = Object.freeze([
  geometry('xiamen'), geometry('kinmen'),
  Object.freeze({ id: 'forward-supply', name: '近岸补给点', faction: 'zheng', x: -60, z: 320, islandX: -60, islandZ: 390, radius: 90, peak: 28 }),
])
const [home, destination] = MINGQI_PORT_GEOMETRY
const length = Math.hypot(destination.x - home.x, destination.z - home.z)
const ux = (destination.x - home.x) / length, uz = (destination.z - home.z) / length
function point(along: number, across = 0): Point {
  return Object.freeze({ x: home.x + ux * length * along - uz * across, z: home.z + uz * length * along + ux * across })
}
const line = (...points: Point[]) => Object.freeze(points)
/** Routes share safe deep endpoints; only the middle route crosses the broad shelf. */
export const MINGQI_ROUTE_GEOMETRY: Readonly<Record<string, readonly Point[]>> = Object.freeze({
  'xiamen-kinmen-shallow': line(point(0), point(.2), point(.8), point(1)),
  'xiamen-kinmen-deep': line(point(0), point(.2, -230), point(.8, -230), point(1)),
  'xiamen-kinmen-outer': line(point(0), point(.15, 260), point(.85, 260), point(1)),
  'kinmen-supply-deep': line(point(1),point(.85,260),Object.freeze({x:-60,z:250}),Object.freeze({x:-60,z:320})),
})
export const MINGQI_SPAWN_POINTS: Readonly<Record<string, Point>> = Object.freeze({
  flagship: point(.05, -20), heritage: point(0, -65), 'grain-a': point(.12, -75), 'grain-b': point(.19, -135),
  fast: point(.23, -25), enemy: point(.9, -400), 'background-grain-01': point(.4, 260),
})
/** Deep sea plus islands and a 2.4m shelf. Water surface and waves are independent. */
export function sampleMingqiTerrainHeight(x: number, z: number): number {
  if (!Number.isFinite(x) || !Number.isFinite(z)) return NaN
  let height = -24
  for (const island of MINGQI_PORT_GEOMETRY) {
    const dx = (x - island.islandX) / island.radius, dz = (z - island.islandZ) / (island.radius * .82)
    const d2 = dx * dx + dz * dz
    if (d2 < 1) {
      const body = (1 - d2) ** 1.65
      const ridge = (Math.sin(x * .044 + z * .018) + Math.sin(z * .056 - x * .013)) * 2.2 * body
      height = Math.max(height, -24 + (island.peak + 24) * body + ridge)
    }
  }
  const along = (x - home.x) * ux + (z - home.z) * uz
  const across = -(x - home.x) * uz + (z - home.z) * ux
  const endDistance = Math.max(length * .32 - along, 0, along - length * .68)
  const distance = Math.hypot(across, endDistance)
  if (distance < 135) {
    const t = Math.max(0, Math.min(1, (135 - distance) / 45))
    height = Math.max(height, -24 + 21.6 * t * t * (3 - 2 * t))
  }
  return height
}
export function mingqiTerrainSample(x: number, z: number) {
  const height = sampleMingqiTerrainHeight(x, z)
  return { height, normalized: height < 0 ? .6 + height / 50 : .6 + height / 150, isUnderwater: height < 0 }
}
