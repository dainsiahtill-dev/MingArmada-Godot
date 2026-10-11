import type * as THREE from 'three'
import type { ShipSnapshot, Wind } from '@ming-armada/naval-core'

type Mast={object:THREE.Object3D;authoredYaw:number}

/** Drives generated mast pivots from the effective angle already resolved by naval-core. */
export class SailRig {
  private masts:Mast[]=[]
  constructor(model:THREE.Object3D) {
    model.traverse(object=>{
      if(/^mast_\d+$/.test(object.name))this.masts.push({object,authoredYaw:object.rotation.y})
    })
  }
  update(angleRad:number) {
    const angle=Number.isFinite(angleRad)?Math.max(-Math.PI/2,Math.min(Math.PI/2,angleRad)):0
    // Core's sail plane follows heading + angle. Models face +Z with cloth width +X,
    // while vessel yaw is PI/2 - heading: the cloth needs PI/2 - angle locally.
    for(const mast of this.masts)mast.object.rotation.y=mast.authoredYaw+Math.PI/2-angle
  }
  reset() {
    for(const mast of this.masts)mast.object.rotation.y=mast.authoredYaw
  }
}

/** Orient the generated +Z inflation morph into the air flow relative to the ship. */
export function sailInflationSign(ship:Pick<ShipSnapshot,'visual'|'sailAngle'>,wind:Wind):1|-1 {
  const angle=ship.visual.heading+ship.sailAngle
  const lengthSq=wind.direction.x**2+wind.direction.y**2
  // Match NormPhysicsEngine's normalization and degenerate wind direction fallback.
  const windFromX=lengthSq<1e-8?1:wind.direction.x/Math.sqrt(lengthSq)
  const windFromZ=lengthSq<1e-8?0:wind.direction.y/Math.sqrt(lengthSq)
  const airflowX=-windFromX*wind.speed-ship.visual.velocity.x
  const airflowZ=-windFromZ*wind.speed-ship.visual.velocity.z
  // After both vessel and mast yaw, the authored +Z normal is (sin(angle), -cos(angle)).
  return airflowX*Math.sin(angle)-airflowZ*Math.cos(angle)<0?-1:1
}
