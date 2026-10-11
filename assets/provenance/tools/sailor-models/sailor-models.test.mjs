import test from 'node:test';
import assert from 'node:assert/strict';
import {AnimationMixer, Box3, Raycaster, Vector3} from 'three';

const module = await import('./build-sailor.mjs').catch(() => null);
function create(lod=0,variant='indigo') {
  assert.ok(module?.createSailor, 'original sailor generator is required');
  return module.createSailor({lod,variant});
}
function meshOf(root) {return root.getObjectByName('sailor_body');}
const clips = ['idle','helm','haul','load-cannon','walk','lookout'];

test('feet origin and humanoid metre scale survive generated geometry',()=>{
  const root=create(), bounds=new Box3().setFromObject(root);
  const size=bounds.getSize(new Vector3());
  assert.ok(Math.abs(bounds.min.y)<.005, 'feet must rest on local deck y=0');
  assert.ok(size.y>1.60&&size.y<1.75, 'human height between 1.60 and 1.75 metres');
  assert.ok(size.x>.45&&size.x<.9, 'shoulders and arms have plausible human width');
  assert.ok(size.z>.22&&size.z<.5, 'face, body and shoes have genuine depth');
});

test('one merged skinned mesh owns normalized finite weights and legal joint indices',()=>{
  const root=create(), meshes=[];root.traverse(o=>{if(o.isMesh)meshes.push(o);});
  assert.equal(meshes.length,1);const mesh=meshOf(root);
  assert.ok(mesh.isSkinnedMesh);assert.equal(mesh.skeleton.bones.length,18);
  assert.ok(!Array.isArray(mesh.material)&&mesh.material.vertexColors);
  const g=mesh.geometry;
  assert.ok(g.attributes.color&&g.attributes.normal&&g.index);
  let blended=0;
  for(let i=0;i<g.attributes.position.count;i++) {
    let sum=0, active=0;
    for(let j=0;j<4;j++) {
      const w=g.attributes.skinWeight.array[i*4+j],joint=g.attributes.skinIndex.array[i*4+j];
      assert.ok(Number.isFinite(w)&&w>=0&&w<=1);
      assert.ok(Number.isInteger(joint)&&joint>=0&&joint<18);
      sum+=w;if(w>0)active++;
    }
    assert.ok(Math.abs(sum-1)<1e-6);if(active>1)blended++;
    for(let j=0;j<3;j++)assert.ok(Number.isFinite(g.attributes.position.array[i*3+j]));
  }
  assert.ok(blended>100,'joint transitions need real blended skin weights');
});

test('three LODs strictly reduce topology while preserving rig, face silhouette and clips',()=>{
  const roots=[0,1,2].map(lod=>create(lod));
  const counts=roots.map(root=>meshOf(root).geometry.index.count/3);
  assert.ok(counts[0]<6500&&counts[1]<3000&&counts[2]<1100);
  assert.ok(counts[0]>counts[1]*1.4&&counts[1]>counts[2]*1.4);
  for(const root of roots) {
    assert.deepEqual(root.animations.map(c=>c.name),clips);
    assert.ok(root.getObjectByName('sailor_head')&&root.getObjectByName('sailor_wrist_L'));
  }
});

test('six clips animate actual joints with fixed deck root and finite nonzero duration',()=>{
  const root=create();
  for(const clip of root.animations) {
    assert.ok(clip.duration>0&&clip.tracks.length>=3);
    assert.ok(clip.tracks.every(track=>track.name.endsWith('.quaternion')||track.name==='sailor_hips.position'));
    assert.ok(clip.tracks.every(track=>!track.name.startsWith('sailor_root.')));
    assert.ok(clip.tracks.every(track=>[...track.values,...track.times].every(Number.isFinite)));
    const mixer=new AnimationMixer(root), action=mixer.clipAction(clip);action.play();
    mixer.setTime(0);root.updateMatrixWorld(true);
    const first=meshOf(root).skeleton.bones.map(b=>b.quaternion.clone());
    mixer.setTime(clip.duration*.37);root.updateMatrixWorld(true);
    assert.ok(meshOf(root).skeleton.bones.some((b,i)=>b.quaternion.angleTo(first[i])>.03),`${clip.name} needs motion`);
    assert.deepEqual(root.position.toArray(),[0,0,0]);
    mixer.stopAllAction();mixer.uncacheRoot(root);
  }
});

test('work poses reach forward, lookout reaches brow, cannon bends knees and walk alternates legs',()=>{
  for(const [name,fraction] of [['helm',.25],['haul',.25],['lookout',.25],['load-cannon',.4],['walk',.25]]) {
    const root=create(),clip=root.animations.find(c=>c.name===name),mixer=new AnimationMixer(root);
    mixer.clipAction(clip).play();mixer.setTime(clip.duration*fraction);root.updateMatrixWorld(true);
    const wrist=root.getObjectByName('sailor_wrist_R').getWorldPosition(new Vector3());
    if(name==='helm'||name==='haul')assert.ok(wrist.y>1.05&&wrist.z>.18, `${name} work hands in front of body`);
    if(name==='lookout')assert.ok(wrist.y>1.52&&wrist.y<1.72&&wrist.z>.08&&wrist.z<.25&&Math.abs(wrist.x)<.18,'lookout hand belongs near brow');
    if(name==='load-cannon')assert.ok(root.getObjectByName('sailor_knee_R').quaternion.angleTo(root.getObjectByName('sailor_root').quaternion)>.25);
    if(name==='walk')assert.ok(root.getObjectByName('sailor_thigh_R').quaternion.angleTo(root.getObjectByName('sailor_thigh_L').quaternion)>.3);
  }
});

test('palette variants preserve shared topology and invalid options fail closed',()=>{
  const a=meshOf(create(0,'indigo')),b=meshOf(create(0,'ochre'));
  assert.deepEqual(a.geometry.attributes.position.array,b.geometry.attributes.position.array);
  assert.notDeepEqual(a.geometry.attributes.color.array,b.geometry.attributes.color.array);
  assert.throws(()=>create(-1),/LOD/);assert.throws(()=>create(3),/LOD/);
  assert.throws(()=>create(0,'pirate'),/variant/);
});

test('layered cross collar presents its outer face toward viewer',()=>{
  const root=create();root.updateMatrixWorld(true);
  const ray=new Raycaster(new Vector3(-.020,1.30,1),new Vector3(0,0,-1));
  const hit=ray.intersectObject(meshOf(root))[0];
  assert.ok(hit&&hit.point.z>.14,'visible outer collar surface must face +Z');
});

test('stationary cannon work keeps shoes planted while crouching',()=>{
  const root=create(),mesh=meshOf(root),clip=root.animations.find(c=>c.name==='load-cannon'),mixer=new AnimationMixer(root);
  mixer.clipAction(clip).play();
  for(let n=0;n<33;n++) {
    mixer.setTime(clip.duration*n/32);root.updateMatrixWorld(true);mesh.skeleton.update();
    let lowest=Infinity;const p=mesh.geometry.attributes.position;
    for(let i=0;i<p.count;i++)if(p.getY(i)<.12) {
      const v=new Vector3().fromBufferAttribute(p,i);mesh.applyBoneTransform(i,v);lowest=Math.min(lowest,v.y);
    }
    assert.ok(lowest>-.008&&lowest<.008,`crouched shoes must meet deck, got ${lowest}`);
    assert.equal(root.getObjectByName('sailor_hips').position.x,0);
    assert.equal(root.getObjectByName('sailor_hips').position.z,0);
  }
});
