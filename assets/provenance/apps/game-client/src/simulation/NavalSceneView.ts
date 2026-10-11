import * as THREE from 'three'
import { GLTFLoader, type GLTF } from 'three/examples/jsm/loaders/GLTFLoader.js'
import { clone } from 'three/examples/jsm/utils/SkeletonUtils.js'
import type { CombatEvent, EncounterSnapshot, ShipSnapshot, ShipKind } from '@ming-armada/naval-core'
import { PORTS, sampleTerrainHeight, type Port } from './world-layout.js'
import { createWakeTexture, updateWakeMesh } from './WakeTexture.js'
import {SailRig,sailInflationSign} from './SailRig.js'
import {SailingAudio,type SailingSound,type SoundPosition} from './SailingAudio.js'
import { CannonRecoil, ProjectileVisuals, SailDamageMap } from './CombatVisuals.js'
import {SailorAssets,SailorDeckView,allocateSailors} from './SailorDeckView.js'
import {DescribedOcean} from '@ming-armada/physics-core'
import {SailorImpactPhysics,phaseDeckCollider,type ImpactPerformance} from './SailorImpactPhysics.js'
import {loadedShoreDeck,loadedShoreDeckEntry,loadedShoreClearance,type DeckSupport,type ShoreClearance,type ShoreClearancePoint} from './NavalDeckSupport.js'
type Vessel={kind:ShipKind;group:THREE.Group;lod:THREE.LOD;materials:THREE.MeshStandardMaterial[];wake:THREE.Mesh;sailDamage:SailDamageMap;recoil:CannonRecoil;rig:SailRig;sailors:SailorDeckView;death?:number;disposed?:boolean}
type Particle={sprite:THREE.Sprite;velocity:THREE.Vector3;age:number;life:number;size:number;gravity:number}
type SceneGeography={ports?:readonly Port[];sampleTerrainHeight?:(x:number,z:number)=>number;profileSailors?:boolean}
type SailorPerformanceFrame=ImpactPerformance&{index:number;battleId:string;nativeTick:number;simulationSeconds:number;acceptedSeconds:number;startedAtMs:number;completedAtMs:number;viewMs:number;standingMs:number;standingSailors:number}
const PERFORMANCE_FRAME_CAP=5000
const KINDS:ShipKind[]=['fuchuan','fisherman','merchant','voc','patrol','heavy']
/** Loaded model prototypes own shared GPU resources; cloned vessels borrow them. */
function disposeModelResources(objects:readonly THREE.Object3D[]) {
  const geometries=new Set<THREE.BufferGeometry>(),materials=new Set<THREE.Material>(),textures=new Set<THREE.Texture>()
  const skeletons=new Set<THREE.Skeleton>()
  for(const root of objects)root.traverse(object=>{
    if(!(object instanceof THREE.Mesh))return
    if(object instanceof THREE.SkinnedMesh)skeletons.add(object.skeleton)
    geometries.add(object.geometry)
    for(const material of(Array.isArray(object.material)?object.material:[object.material])){
      materials.add(material)
      for(const value of Object.values(material))if(value instanceof THREE.Texture)textures.add(value)
    }
  })
  geometries.forEach(geometry=>geometry.dispose());materials.forEach(material=>material.dispose())
  skeletons.forEach(skeleton=>skeleton.dispose())
  const images=new Set<{close:()=>void}>()
  for(const texture of textures){texture.dispose();for(const image of(Array.isArray(texture.image)?texture.image:[texture.image]))if(typeof image?.close==='function')images.add(image)}
  images.forEach(image=>image.close())
}
export class NavalSceneView {
  private static owners=new WeakMap<THREE.Scene,NavalSceneView>()
  private models=new Map<ShipKind,THREE.Group[]>()
  private sailorAssets?:SailorAssets
  private vessels=new Map<string,Vessel>()
  private particles:Particle[]=[]
  private root=new THREE.Group()
  private ports=new THREE.Group()
  private particleTexture:THREE.CanvasTexture
  private projectiles:ProjectileVisuals
  private impacts:SailorImpactPhysics
  private impactPrevious?:EncounterSnapshot
  private impactFrames=new Map<string,{kind:ShipKind;tick:number;matrix:THREE.Matrix4}>()
  private seenHits=new Set<string>()
  private hitFloor=-Infinity
  private fireVelocities=new Map<string,THREE.Vector3>()
  private time=0
  private sailorClock?:{battleId:string;tick:number;time:number}
  private reducedMotion=false
  private audio=new SailingAudio()
  private performanceFrames:SailorPerformanceFrame[]=[]
  private performanceOrdinal=0
  private performanceDropped=0
  private disposed=false
  private deckStamp=0
  private cancelLoading?:()=>void
  private constructor(private scene:THREE.Scene,private geography:SceneGeography={}) {
    this.root.name='naval_scene'
    this.scene.add(this.root,this.ports)
    this.impacts=new SailorImpactPhysics(this.root,id=>{
      const vessel=this.vessels.get(id),frame=this.impactFrames.get(id)
      if(!vessel||!frame)return
      vessel.group.updateWorldMatrix(true,false)
      return frame.matrix.clone().multiply(vessel.group.matrixWorld.clone().invert())
    })
    this.projectiles=new ProjectileVisuals(this.root)
    const canvas=document.createElement('canvas');canvas.width=canvas.height=64
    const ctx=canvas.getContext('2d')!
    const gradient=ctx.createRadialGradient(32,32,1,32,32,30)
    gradient.addColorStop(0,'rgba(255,255,255,0.9)');gradient.addColorStop(0.35,'rgba(255,255,255,0.55)');gradient.addColorStop(1,'rgba(255,255,255,0)')
    ctx.fillStyle=gradient;ctx.fillRect(0,0,64,64)
    this.particleTexture=new THREE.CanvasTexture(canvas)
    this.buildPorts()
  }
  static async create(scene:THREE.Scene,progress?:(value:number)=>void,options?:SceneGeography) {
    // A newer owner of the same scene supersedes any in-flight older preload.
    NavalSceneView.owners.get(scene)?.dispose()
    const view=new NavalSceneView(scene,options)
    NavalSceneView.owners.set(scene,view)
    const loader=new GLTFLoader()
    let pending:THREE.Group[]=[]
    const cancelled=new Promise<never>((_,reject)=>{
      view.cancelLoading=()=>{disposeModelResources(pending);pending=[];reject(new Error('Naval scene load superseded or disposed'))}
    })
    const preload=(async()=>{try {
      let loaded=0
      for(const kind of KINDS) {
        for(let lod=0;lod<3;lod++) {
          const model=await loader.loadAsync('/models/ships/'+kind+'-lod'+lod+'.glb')
          if(view.disposed||NavalSceneView.owners.get(scene)!==view){disposeModelResources([model.scene]);throw new Error('Naval scene load superseded or disposed')}
          pending.push(model.scene);progress?.(++loaded/(KINDS.length*3+3))
          if(view.disposed)throw new Error('Naval scene load superseded or disposed')
        }
        view.models.set(kind,pending);pending=[]
      }
      const sailors:GLTF[]=[]
      for(let lod=0;lod<3;lod++) {
        const model=await loader.loadAsync(`/models/sailors/sailor-lod${lod}.glb`)
        if(view.disposed||NavalSceneView.owners.get(scene)!==view){disposeModelResources([model.scene]);throw new Error('Naval scene load superseded or disposed')}
        sailors.push(model);pending.push(model.scene);progress?.(++loaded/(KINDS.length*3+3))
        if(view.disposed)throw new Error('Naval scene load superseded or disposed')
      }
      view.sailorAssets=new SailorAssets(sailors);pending=[]
      return view
    } catch(error) {disposeModelResources(pending);pending=[];view.cancelLoading=undefined;view.dispose();throw error}})()
    try{return await Promise.race([preload,cancelled])}finally{view.cancelLoading=undefined}
  }
  setSound(enabled:boolean) {this.audio.setEnabled(enabled);if(enabled)this.audio.arm()}
  setVolume(volume:number){this.audio.setVolume(volume)}
  private audioListener:SoundPosition|undefined
  setAudioListener(position?:SoundPosition){this.audioListener=position?{x:position.x,z:position.z}:undefined}
  setReducedMotion(reduced:boolean){this.reducedMotion=reduced}
  /** Borrowed prototypes remain owned here; callers must dispose clones before this view. */
  borrowSailorAssets():Pick<SailorAssets,'models'|'instantiate'>|undefined{
    const assets=this.sailorAssets
    if(this.disposed||!assets)return undefined
    return {models:assets.models,instantiate:(lod:number)=>{
      if(this.disposed||this.sailorAssets!==assets)throw new Error('Naval sailor asset owner disposed')
      return assets.instantiate(lod)
    }}
  }
  shoreDeckSupport(shipId:string,worldXZ:Readonly<{x:number;z:number}>):DeckSupport|null{
    const vessel=this.vessels.get(shipId)
    if(this.disposed||!vessel||vessel.disposed||vessel.death!==undefined||!vessel.group.visible)return null
    const model=vessel.lod.levels[0]?.object
    return model?loadedShoreDeck(model,worldXZ,this.deckStamp):null
  }
  shoreDeckEntry(shipId:string,pier:Readonly<{x:number;z:number}>):DeckSupport|null{
    const vessel=this.vessels.get(shipId)
    if(this.disposed||!vessel||vessel.disposed||vessel.death!==undefined||!vessel.group.visible)return null
    const model=vessel.lod.levels[0]?.object
    return model?loadedShoreDeckEntry(model,pier,this.deckStamp):null
  }
  shoreClearance(shipId:string,a:ShoreClearancePoint|readonly ShoreClearancePoint[],b?:ShoreClearancePoint):ShoreClearance{
    const vessel=this.vessels.get(shipId),model=vessel?.lod.levels[0]?.object
    if(this.disposed||!vessel||vessel.disposed||vessel.death!==undefined||!vessel.group.visible||!model)return {clear:false,reason:'deck vessel unavailable'}
    return loadedShoreClearance(model,a,b)
  }
  armAudio() {this.audio.arm()}
  audioDiagnostics(){return this.audio.diagnostics()}
  sailorDiagnostics(){const latest=this.performanceFrames.at(-1);return {visible:[...this.vessels.values()].reduce((n,v)=>n+v.sailors.diagnostics().visible,0),budget:120,impacts:this.impacts.diagnostics(),ships:[...this.vessels.entries()].map(([id,v])=>({id,...v.sailors.diagnostics()})),performance:latest?{...latest}:undefined}}
  sailorPerformanceDiagnostics(){return {schema:'ming-armada-sailor-performance-v1',enabled:!!this.geography.profileSailors,cap:PERFORMANCE_FRAME_CAP,droppedFrames:this.performanceDropped,timing:'Wall-clock nested spans overlap: kernel includes contact/water; contact includes raycasts; spawn includes initial pose. Substeps count observed distinct kernel contact phases. Frames include positive presentation deltas only.',frames:this.performanceFrames.map(frame=>({...frame}))}}
  playFeedback(type:SailingSound,position?:SoundPosition,listener:SoundPosition|undefined=this.audioListener){this.audio.play(type,position,listener)}
  private soundEffect(type:'fire'|'hit'|'splash',position:SoundPosition) {this.audio.play(type,position,this.audioListener)}
  private makeVessel(ship:ShipSnapshot):Vessel {
    const group=new THREE.Group();group.name=ship.id
    const lod=new THREE.LOD(),materials:THREE.MeshStandardMaterial[]=[]
    const sailDamage=new SailDamageMap(ship.id)
    const variants=this.models.get(ship.kind)
    if(!variants?.length){sailDamage.dispose();throw new Error(`Ship model not loaded: ${ship.kind}`)}
    for(let index=0;index<variants.length;index++) {
      const variant=clone(variants[index]) as THREE.Group
      const local=new Map<string,THREE.MeshStandardMaterial>()
      variant.traverse(object=>{
        if(!(object instanceof THREE.Mesh))return
        object.castShadow=true;object.receiveShadow=true
        const cloneMaterial=(material:THREE.Material)=>{
          // Generated cloth is also shared with flags; only true sails receive holes.
          const sail=/^sail_\d+$/.test(object.name),key=material.uuid+(sail?':sail':':fittings')
          let copy=local.get(key)
          if(!copy) {
            copy=material.clone() as THREE.MeshStandardMaterial
            copy.userData.originalColor=copy.color?.clone();local.set(key,copy);materials.push(copy)
            if(sail)sailDamage.bind(copy)
          }
          return copy
        }
        object.material=Array.isArray(object.material)?object.material.map(cloneMaterial):cloneMaterial(object.material)
      })
      lod.addLevel(variant,[0,220,650][index])
    }
    group.add(lod)
    const wake=new THREE.Mesh(new THREE.PlaneGeometry(ship.dimensions.width*1.35,ship.dimensions.length,8,16),
      new THREE.MeshBasicMaterial({map:createWakeTexture(),color:0xffffff,transparent:true,opacity:0.12,alphaTest:.003,depthWrite:false,side:THREE.DoubleSide}))
    const wakePositions=wake.geometry.getAttribute('position')
    if(wakePositions instanceof THREE.BufferAttribute)wakePositions.setUsage(THREE.DynamicDrawUsage)
    wake.frustumCulled=false;wake.renderOrder=3;this.root.add(wake)
    this.root.add(group)
    sailDamage.update(ship.sail,ship.maxSail)
    if(!this.sailorAssets)throw new Error('Sailor models not loaded')
    const sailors=new SailorDeckView(group,ship.kind,variants,this.sailorAssets)
    const vessel={kind:ship.kind,group,lod,materials,wake,sailDamage,recoil:new CannonRecoil(lod),rig:new SailRig(lod),sailors};this.vessels.set(ship.id,vessel);return vessel
  }
  update(snapshot:EncounterSnapshot,events:CombatEvent[],deltaSeconds:number,camera:THREE.Camera,acceptedNativeSnapshot:EncounterSnapshot=snapshot) {
    if(this.disposed)return
    this.deckStamp++
    // renderSnapshot.time is interpolated and may snap on pause without a step.
    // Native tick is authoritative (fixed 1/60s); repeated render frames cannot bill it.
    const previousClock=this.sailorClock
    const native=acceptedNativeSnapshot,validClock=Number.isSafeInteger(native.tick)&&native.tick>=0&&Number.isFinite(native.time)
    this.sailorClock=validClock?{battleId:native.battleId,tick:native.tick,time:native.time}:undefined
    const acceptedSailorDelta=validClock&&previousClock&&previousClock.battleId===native.battleId&&native.tick>previousClock.tick&&native.time>=previousClock.time&&Number.isFinite(deltaSeconds)&&deltaSeconds>0
      ?(native.tick-previousClock.tick)/60:0
    const reset=previousClock&&(previousClock.battleId!==native.battleId||native.tick<previousClock.tick||native.time<previousClock.time)
    if(reset){this.impacts.reset();this.impactPrevious=undefined;this.impactFrames.clear();this.seenHits.clear();this.fireVelocities.clear();this.hitFloor=-Infinity;this.performanceFrames.length=0;this.performanceOrdinal=0;this.performanceDropped=0}
    const profiling=!!this.geography.profileSailors&&Number.isFinite(deltaSeconds)&&deltaSeconds>0
    const startedAtMs=profiling?performance.now():0,stats=profiling?this.impacts.startPerformanceFrame():undefined
    // Always consume the baseline, including explicit pause, rewind or epoch switch;
    // never catch up a skipped interval. Do not clamp legitimate accelerated ticks to RAF.
    const cameraWorld=camera.getWorldPosition(new THREE.Vector3())
    this.audio.updateWind(snapshot.wind.speed,snapshot.time,deltaSeconds===0)
    this.time+=Math.max(0,deltaSeconds)
    const active=new Set(snapshot.ships.map(s=>s.id))
    for(const [id,vessel] of this.vessels) {
      if(!active.has(id)) {this.impacts.removeShip(id);this.impactFrames.delete(id);this.removeVessel(vessel);this.vessels.delete(id)}
    }
    for(const ship of snapshot.ships) {
      let vessel=this.vessels.get(ship.id)
      if(vessel&&vessel.kind!==ship.kind){this.impacts.removeShip(ship.id);this.impactFrames.delete(ship.id);this.removeVessel(vessel);this.vessels.delete(ship.id);vessel=undefined}
      vessel??=this.makeVessel(ship)
      const state=ship.visual
      if(ship.hull<=0)vessel.death??=this.time
      else vessel.death=undefined
      const sinking=vessel.death===undefined?0:Math.min(16,(this.time-vessel.death)*1.8)
      vessel.group.position.set(state.position.x,state.position.y-sinking,state.position.z)
      vessel.group.rotation.set(-state.pitch,Math.PI/2-state.heading,state.heel,'YXZ')
      vessel.group.visible=sinking<16
      vessel.lod.updateWorldMatrix(true,false)
      vessel.lod.update(camera)
      vessel.sailDamage.update(ship.sail,ship.maxSail)
      vessel.recoil.update(deltaSeconds)
      vessel.rig.update(ship.sailAngle)
      const inflationSign=sailInflationSign(ship,snapshot.wind)
      const speed=Math.hypot(state.velocity.x,state.velocity.z)
      updateWakeMesh(vessel.wake as THREE.Mesh<THREE.BufferGeometry,THREE.MeshBasicMaterial>,state,ship.dimensions.length,speed,snapshot.oceanWaves,snapshot.time)
      if(ship.hull<=0)vessel.wake.visible=false
      vessel.lod.traverse(object=>{
        if(object instanceof THREE.Mesh&&object.morphTargetDictionary&&object.morphTargetInfluences) {
          const furl=object.morphTargetDictionary.furl,inflate=object.morphTargetDictionary.inflate
          if(furl!==undefined)object.morphTargetInfluences[furl]=1-ship.sailDeployment
          if(inflate!==undefined)object.morphTargetInfluences[inflate]=inflationSign*Math.min(1,snapshot.wind.speed/18)*ship.sail/ship.maxSail*ship.sailDeployment
        }
        if(object.name==='rudder_pivot')object.rotation.y=ship.rudder*0.42
        if(object.name.startsWith('flag_'))object.rotation.z=this.reducedMotion?0:Math.sin(this.time*4)*0.025
      })
      for(const material of vessel.materials) {
        if(material.color&&material.userData.originalColor)material.color.copy(material.userData.originalColor).multiplyScalar(0.58+0.42*ship.hull/ship.maxHull)
      }
    }
    this.updateImpacts(native,events,acceptedSailorDelta,stats)
    const standingStarted=stats?performance.now():0
    const requests=snapshot.ships.map(ship=>{const vessel=this.vessels.get(ship.id)!;return {id:ship.id,requested:vessel.sailors.requestBudget(ship,cameraWorld),distance:vessel.group.getWorldPosition(new THREE.Vector3()).distanceTo(cameraWorld)}})
    const allocation=allocateSailors(requests)
    for(const ship of snapshot.ships){const vessel=this.vessels.get(ship.id)!;vessel.sailors.update(ship,events,acceptedSailorDelta,allocation.get(ship.id)??0,this.reducedMotion,vessel.lod.getCurrentLevel())}
    const standingMs=stats?performance.now()-standingStarted:0
    const standingSailors=stats?[...this.vessels.values()].reduce((n,v)=>n+v.sailors.diagnostics().visible,0):0
    for(const event of events)this.emit(event)
    this.projectiles.update(snapshot.projectiles)
    for(let i=this.particles.length-1;i>=0;i--) {
      const particle=this.particles[i];particle.age+=deltaSeconds
      if(particle.age>=particle.life) {
        this.root.remove(particle.sprite);particle.sprite.material.dispose();this.particles.splice(i,1);continue
      }
      particle.sprite.position.addScaledVector(particle.velocity,deltaSeconds)
      particle.velocity.y-=deltaSeconds*particle.gravity
      particle.sprite.material.opacity=Math.pow(1-particle.age/particle.life,1.6)*0.8
      particle.sprite.scale.setScalar(particle.size*(1+particle.age*0.5))
    }
    if(stats){
      const impactStats=this.impacts.finishPerformanceFrame()!,completedAtMs=performance.now()
      this.performanceFrames.push({...impactStats,index:++this.performanceOrdinal,battleId:native.battleId,nativeTick:native.tick,simulationSeconds:native.time,acceptedSeconds:acceptedSailorDelta,startedAtMs,completedAtMs,viewMs:completedAtMs-startedAtMs,standingMs,standingSailors})
      if(this.performanceFrames.length>PERFORMANCE_FRAME_CAP){this.performanceFrames.shift();this.performanceDropped++}
    }
  }
  private updateImpacts(snapshot:EncounterSnapshot,events:readonly CombatEvent[],accepted:number,stats?:ImpactPerformance){
    const ocean=new DescribedOcean(snapshot.oceanWaves)
    this.root.updateWorldMatrix(true,false)
    const decks=new Map<string,ReturnType<typeof phaseDeckCollider>>()
    // Only actual consumed Native endpoints enter contact history. Same-tick
    // render interpolation and pause snaps cannot overwrite an endpoint.
    for(const ship of snapshot.ships){
      const vessel=this.vessels.get(ship.id);if(!vessel||vessel.kind!==ship.kind)continue
      const before=this.impactFrames.get(ship.id)
      const endpoint=before&&before.tick===snapshot.tick&&before.kind===ship.kind?before:{kind:ship.kind,tick:snapshot.tick,matrix:new THREE.Matrix4().compose(
        new THREE.Vector3(ship.visual.position.x,ship.visual.position.y,ship.visual.position.z),
        new THREE.Quaternion().setFromEuler(new THREE.Euler(-ship.visual.pitch,Math.PI/2-ship.visual.heading,ship.visual.heel,'YXZ')),new THREE.Vector3(1,1,1)).premultiply(this.root.matrixWorld)}
      if(ship.hull>0){
        const prototype=this.models.get(vessel.kind)![vessel.lod.getCurrentLevel()]
        decks.set(ship.id,phaseDeckCollider(prototype,before?.matrix??endpoint.matrix,endpoint.matrix,(before?.tick??snapshot.tick)/60,snapshot.tick/60,stats))
      }
      this.impactFrames.set(ship.id,endpoint)
    }
    this.impacts.update(accepted,snapshot.tick/60,{water:(x,z,time)=>ocean.sample(x,z,time).height,deck:(id,point,previous,time,previousTime)=>{
      return decks.get(id)?.(point,previous,time,previousTime)
    }})
    for(const event of events)if(event.type==='fire')this.fireVelocities.set(event.projectileId,new THREE.Vector3(event.velocity.x,event.velocity.y,event.velocity.z))
    while(this.fireVelocities.size>256)this.fireVelocities.delete(this.fireVelocities.keys().next().value!)
    const previous=this.impactPrevious
    const lost=new Map(snapshot.ships.map(ship=>{const before=previous?.ships.find(s=>s.id===ship.id);return [ship.id,before?Math.max(0,Math.floor(before.crew-ship.crew+1e-8)):0]}))
    const nonlethal=new Set<string>()
    for(const event of events){
      if(event.type!=='hit'||this.seenHits.has(event.id)||event.time<=this.hitFloor)continue
      this.seenHits.add(event.id)
      // Keep a bounded same-time ID window; older evicted events cannot replay.
      if(this.seenHits.size>256){this.seenHits.delete(this.seenHits.values().next().value!);this.hitFloor=Math.max(this.hitFloor,event.time)}
      const target=snapshot.ships.find(s=>s.id===event.targetId),before=previous?.ships.find(s=>s.id===event.targetId),vessel=this.vessels.get(event.targetId)
      if(accepted<=0||!target||!before||!vessel||event.damage.crew<=0||target.crew>=before.crew||target.hull>before.hull)continue
      const projectile=previous?.projectiles.find(p=>p.id===event.projectileId)
      const shooter=previous?.ships.find(s=>s.id===event.shipId)
      const position=new THREE.Vector3(event.position.x,event.position.y,event.position.z)
      const direction=projectile?new THREE.Vector3(projectile.velocity.x,0,projectile.velocity.z):this.fireVelocities.get(event.projectileId)?.clone()??(shooter?position.clone().sub(new THREE.Vector3(shooter.visual.position.x,event.position.y,shooter.visual.position.z)):undefined)
      if(!direction||!Number.isFinite(direction.lengthSq())||direction.lengthSq()<1e-8)continue
      direction.y=0;direction.normalize().multiplyScalar(event.ammo==='grape'?7:10)
      let count=Math.min(lost.get(target.id)??0,Math.max(0,Math.ceil(event.damage.crew)),this.impacts.available)
      while(count-->0&&vessel.sailors.impact(this.impacts,target.id,event.id,position,direction,this.reducedMotion))lost.set(target.id,(lost.get(target.id)??0)-1)
      if((lost.get(target.id)??0)===0&&before.crew-target.crew<1&&target.hull>0&&!nonlethal.has(target.id)){
        if(vessel.sailors.impact(this.impacts,target.id,event.id,position,direction,this.reducedMotion,false))nonlethal.add(target.id)
      }
    }
    // Keep detached native facts; caller snapshots may be interpolated or reused.
    const replacedRoster=previous&&(previous.ships.length!==snapshot.ships.length||snapshot.ships.some(s=>previous.ships.find(p=>p.id===s.id)?.kind!==s.kind))
    if(!previous||previous.battleId!==snapshot.battleId||previous.tick!==snapshot.tick||replacedRoster)this.impactPrevious={...snapshot,ships:snapshot.ships.map(s=>({...s,visual:{...s.visual,position:{...s.visual.position}}})),projectiles:snapshot.projectiles.map(p=>({...p,velocity:{...p.velocity}}))}
  }
  private particle(position:{x:number;y:number;z:number},color:number,life:number,size:number,velocity:THREE.Vector3,gravity=-.3) {
    if(this.particles.length>=256) {
      const old=this.particles.shift()!;this.root.remove(old.sprite);old.sprite.material.dispose()
    }
    const sprite=new THREE.Sprite(new THREE.SpriteMaterial({map:this.particleTexture,color,transparent:true,depthWrite:false}))
    sprite.position.set(position.x,position.y,position.z);sprite.scale.setScalar(size);sprite.renderOrder=5
    this.root.add(sprite);this.particles.push({sprite,velocity,age:0,life,size,gravity})
  }
  private emit(event:CombatEvent) {
    if(event.type==='fire') {
      this.soundEffect('fire',event.position)
      this.particle(event.position,0xffd68b,0.16,4.2,new THREE.Vector3(),0)
      for(let i=0;i<(this.reducedMotion?3:6);i++)this.particle(event.position,0xc6c5b9,2.6+i*0.09,2.8,new THREE.Vector3(event.velocity.x*0.035+(Math.random()-.5)*2,0.8+Math.random(),event.velocity.z*0.035+(Math.random()-.5)*2))
      const vessel=this.vessels.get(event.shipId)
      vessel?.recoil.fire(event.side,event.position)
    } else if(event.type==='victory'||event.type==='defeat') {
      this.audio.play(event.type)
    } else if(event.type==='surrender') {
      this.audio.play('defeat')
    } else if(event.type==='hit') {
      this.soundEffect('hit',event.position)
      for(let i=0;i<7;i++)this.particle(event.position,i<2?0xffac55:0x9b7449,0.55+Math.random()*0.4,i<2?1.8:.85,new THREE.Vector3((Math.random()-.5)*5,Math.random()*4,(Math.random()-.5)*5),6.5)
    } else if(event.type==='splash') {
      this.soundEffect('splash',event.position)
      for(let i=0;i<8;i++)this.particle(event.position,0xd1f5ee,0.9+Math.random()*0.4,1.3,new THREE.Vector3((Math.random()-.5)*2,3+Math.random()*4,(Math.random()-.5)*2),9.81)
    }
  }
  private buildPorts() {
    const wood=new THREE.MeshStandardMaterial({color:0x785033,roughness:0.9})
    const walls=new THREE.MeshStandardMaterial({color:0xddd7c5,roughness:0.95})
    const roof=new THREE.MeshStandardMaterial({color:0xa6573e,roughness:0.9})
    const addBox=(parent:THREE.Group,w:number,h:number,d:number,x:number,y:number,z:number,material:THREE.Material)=>{
      const mesh=new THREE.Mesh(new THREE.BoxGeometry(w,h,d),material);mesh.position.set(x,y,z);mesh.castShadow=mesh.receiveShadow=true;parent.add(mesh);return mesh
    }
    for(const port of this.geography.ports??PORTS) {
      const group=new THREE.Group();group.position.set(port.x,0,port.z)
      const dx=port.islandX-port.x,dz=port.islandZ-port.z
      const angle=Math.atan2(dx,dz);group.rotation.y=angle;this.ports.add(group)
      addBox(group,8,0.5,55,0,1.5,20,wood)
      for(let z=-4;z<48;z+=9)for(const x of[-3.1,3.1])addBox(group,0.55,8,0.55,x,-2,z,wood)
      for(let n=0;n<9;n++) {
        const x=port.islandX+Math.cos(n*2.15)*port.radius*0.42
        const z=port.islandZ+Math.sin(n*2.15)*port.radius*0.32
        const y=(this.geography.sampleTerrainHeight??sampleTerrainHeight)(x,z)
        if(y<2)continue
        const house=new THREE.Group();house.position.set(x,y,z);house.rotation.y=n*0.7;this.ports.add(house)
        const width=8+n%3*2,height=4+n%2,depth=7
        addBox(house,width,height,depth,0,height/2,0,walls)
        addBox(house,width*0.32,height*0.65,0.15,0,height*0.325,depth/2+0.08,wood)
        for(const side of[-1,1]) {
          const slope=new THREE.Mesh(new THREE.BoxGeometry(width+2,0.35,depth*0.72),roof)
          slope.position.set(0,height+1.4,side*depth*0.28);slope.rotation.x=side*0.42;slope.castShadow=true;house.add(slope)
        }
        addBox(house,width+2,0.4,0.55,0,height+2.8,0,roof)
      }
    }
  }
  private removeVessel(vessel:Vessel) {
    if(vessel.disposed)return
    vessel.disposed=true
    vessel.sailors.dispose()
    vessel.sailDamage.dispose()
    this.root.remove(vessel.group,vessel.wake);vessel.materials.forEach(m=>m.dispose())
    vessel.wake.geometry.dispose()
    const wakeMaterial=vessel.wake.material as THREE.MeshBasicMaterial
    wakeMaterial.map?.dispose();wakeMaterial.dispose()
  }
  dispose() {
    if(this.disposed)return
    this.disposed=true;this.cancelLoading?.();this.cancelLoading=undefined
    if(NavalSceneView.owners.get(this.scene)===this)NavalSceneView.owners.delete(this.scene)
    this.impacts.dispose();this.impactPrevious=undefined;this.impactFrames.clear();this.seenHits.clear();this.fireVelocities.clear();this.performanceFrames.length=0
    for(const vessel of this.vessels.values())this.removeVessel(vessel)
    this.vessels.clear()
    for(const particle of this.particles)particle.sprite.material.dispose()
    this.particles=[]
    this.particleTexture.dispose();this.projectiles.dispose()
    this.sailorAssets?.dispose();this.sailorAssets=undefined
    disposeModelResources([...Array.from(this.models.values()).flat(),this.ports])
    this.scene.remove(this.root,this.ports);this.models.clear()
    this.audio.dispose()
  }
}
