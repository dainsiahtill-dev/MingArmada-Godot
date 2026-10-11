import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

const source = new URL('./build-ship.mjs', import.meta.url);
const dimensions = { fuchuan: [32,9,2], fisherman:[14,4.2,1], merchant:[36,10,2.8], voc:[40,11,3.2], patrol:[24,6,1.4], heavy:[52,14.5,4.2] };
const limits = { fuchuan:[30000,8000,1500], fisherman:[8000,2000,500], merchant:[30000,8000,1500], voc:[30000,8000,1500], patrol:[30000,8000,1500], heavy:[30000,8000,1500] };
const gunCounts={fuchuan:6,voc:6,patrol:3,heavy:8};
const out = new URL('../../apps/game-client/public/models/ships/', import.meta.url);
const moduleReady = existsSync(source);
let api;
if(moduleReady) api = await import(source);

test('model generator supplies createShip instead of missing asset pipeline', () => {
  assert.equal(moduleReady, true, 'build-ship.mjs must exist');
  assert.equal(typeof api.createShip, 'function');
});

for(const [kind, [length,beam,draft]] of Object.entries(dimensions)) {
  for(let lod=0;lod<3;lod++) {
    test(`${kind} LOD${lod}: closed curved underwater hull, finite PBR geometry, budget`, {skip:!moduleReady}, async () => {
      const {Box3,Vector3} = await import('three');
      const ship = api.createShip(kind,lod);
      assert.equal(ship.name,'ship_root');
      const hull = ship.getObjectByName('hull');
      const b = new Box3().setFromObject(hull);
      assert.ok(Math.abs(b.max.z-b.min.z-length)<0.01, 'complete hull length');
      assert.ok(Math.abs(b.max.x-b.min.x-beam)<0.1, 'complete hull beam');
      assert.ok(Math.abs(b.min.y+draft)<0.01, 'underwater keel retained');
      assert.ok(b.max.y>1 && b.min.y<0, 'waterline passes through hull');
      assert.ok(hull.geometry.attributes.color, 'timber vertex colors');
      const edges=new Map();
      const p=hull.geometry.attributes.position, idx=hull.geometry.index;
      const key=i=>[p.getX(i),p.getY(i),p.getZ(i)].map(v=>v.toFixed(5)).join(',');
      for(let i=0;i<(idx?.count??p.count);i+=3) {
        const a=[0,1,2].map(n=>key(idx?idx.getX(i+n):i+n));
        for(let n=0;n<3;n++) {const edge=[a[n],a[(n+1)%3]].sort().join('|');edges.set(edge,(edges.get(edge)??0)+1);}
      }
      assert.ok([...edges.values()].every(n=>n===2),'hull is watertight');
      let triangles=0, meshes=0;
      const materials=new Set();
      ship.traverse(o=>{
        if(!o.isMesh)return;
        meshes++; materials.add(o.material);
        const g=o.geometry;
        triangles+=(g.index?.count??g.attributes.position.count)/3;
        for(const name of ['position','normal','uv']) {
          assert.ok(g.attributes[name],`${o.name} missing ${name}`);
          assert.ok([...g.attributes[name].array].every(Number.isFinite),`${o.name} invalid ${name}`);
        }
        const normal = g.attributes.normal;
        for(let i=0;i<normal.count;i++) assert.ok(new Vector3().fromBufferAttribute(normal,i).length()>0.8,`${o.name} zero normals`);
      });
      assert.ok(triangles<=limits[kind][lod],`${triangles} triangles exceeds budget`);
      assert.ok(materials.size<=6,'PBR material count bounded');
      assert.ok(meshes<60,'avoid per-plank draw calls');
    });
    test(`${kind} LOD${lod}: runtime controls retain names, sail deformation and gun directions`, {skip:!moduleReady}, async () => {
      const {Vector3} = await import('three');
      const ship=api.createShip(kind,lod);
      for(const name of ['deck','rudder_pivot','mast_01','sail_01','flag_01','socket_wake','socket_crew_01'])assert.ok(ship.getObjectByName(name),name);
      const sail=ship.getObjectByName('sail_01');
      assert.equal(sail.morphTargetInfluences.length,2);
      assert.equal(sail.morphTargetDictionary.furl,0);
      assert.equal(sail.morphTargetDictionary.inflate,1);
      assert.ok(sail.geometry.morphAttributes.position[0].array.some((v,i)=>Math.abs(v-sail.geometry.attributes.position.array[i])>0.1),'furl changes geometry');
      if(gunCounts[kind]) {
        ship.updateMatrixWorld(true);
        for(const side of ['port','starboard']) for(let n=1;n<=gunCounts[kind];n++) {
          const gun=ship.getObjectByName(`cannon_${side}_${String(n).padStart(2,'0')}`);
          assert.ok(gun,`${side} gun ${n}`);
          const direction=new Vector3(0,0,1).transformDirection(gun.matrixWorld);
          assert.ok(side==='port'?direction.x>0.99:direction.x<-.99,'barrel points outwards');
          assert.ok(gun.getObjectByName(`barrel_${side}_${String(n).padStart(2,'0')}`),'unique recoil child');
        }
      }
      if(lod>0) {
        const nodes=o=>{let names=[];o.traverse(x=>{if(/^(mast_|sail_|flag_|rudder_|cannon_|socket_)/.test(x.name))names.push(x.name)});return names.sort();};
        assert.deepEqual(nodes(ship),nodes(api.createShip(kind,0)),'LOD switch retains runtime node contract');
      }
    });
  }
}

test('six silhouettes retain real identifying feature geometry', {skip:!moduleReady}, async () => {
  const {Box3,Vector3}=await import('three');
  for(const [kind,feature,width,height] of [['fuchuan','sterncastle',5,1.5],['fisherman','fishing_canopy',2,.05],['merchant','cargo_hold',4,.4],['voc','stern_gallery',5,1.5],['patrol','bow_firing_platform',2,.1],['heavy','admiral_stern_gallery',8,1.7]]) {
    const node=api.createShip(kind).getObjectByName(feature);
    assert.ok(node,`${kind} needs ${feature}`);
    const b=new Box3().setFromObject(node);
    assert.equal(b.isEmpty(),false,`${feature} must contain geometry, not an empty marker`);
    const size=b.getSize(new Vector3());
    assert.ok(size.x>width&&size.y>height,`${feature} visible feature volume`);
  }
  assert.throws(()=>api.createShip('unknown'),/Unknown/);
  assert.throws(()=>api.createShip('voc',3),/LOD/);
});

test('patrol and heavy have different sail plans and substantial original stern architecture', {skip:!moduleReady}, async () => {
  const {Box3}=await import('three');
  for(const [kind,sails] of [['patrol',2],['heavy',9]]) {
    const ship=api.createShip(kind);let sailCount=0,gunCount=0;
    ship.traverse(o=>{if(/^sail_\d+$/.test(o.name))sailCount++;if(/^cannon_(port|starboard)_\d+$/.test(o.name))gunCount++;});
    assert.equal(sailCount,sails);
    assert.equal(gunCount,kind==='patrol'?6:16);
  }
  const patrol=api.createShip('patrol'),heavy=api.createShip('heavy');
  assert.ok(patrol.getObjectByName('shield_rack'),'visible light bow equipment');
  for(const name of ['stern_tier_01','stern_tier_02','stern_tier_03'])assert.ok(heavy.getObjectByName(name),'three real stern tiers');
  const p=new Box3().setFromObject(patrol.getObjectByName('patrol_stern_house'));
  const h=new Box3().setFromObject(heavy.getObjectByName('admiral_stern_gallery'));
  assert.ok(p.max.y<4,'patrol stays low');
  assert.ok(h.max.y>10,'heavy command stern rises above ordinary VOC');
});

test('all 18 exported GLBs reload with stable controls and validator has zero errors', {skip:!moduleReady}, async () => {
  const {GLTFLoader}=await import('three/addons/loaders/GLTFLoader.js');
  const validator=await import('gltf-validator');
  assert.ok(existsSync(new URL('ships-manifest.json',out)),'export ships first');
  const manifest=JSON.parse(readFileSync(new URL('ships-manifest.json',out),'utf8'));
  assert.equal(manifest.assets.length,18);
  for(const entry of manifest.assets) {
    assert.equal(entry.gunsPerSide,gunCounts[entry.kind]??0,'manifest runtime gun count');
    assert.equal(entry.sailCount,({fuchuan:3,fisherman:1,merchant:3,voc:6,patrol:2,heavy:9})[entry.kind],'manifest sail plan');
    const bytes=readFileSync(new URL(entry.file,out));
    assert.equal(bytes.readUInt32LE(0),0x46546c67,'GLB magic');
    assert.equal(createHash('sha256').update(bytes).digest('hex'),entry.sha256);
    const report=await validator.validateBytes(new Uint8Array(bytes),{uri:entry.file});
    assert.equal(report.issues.numErrors,0,JSON.stringify(report.issues.messages));
    const gltf=await new GLTFLoader().parseAsync(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength),'');
    for(const node of ['ship_root','hull','sail_01','rudder_pivot'])assert.ok(gltf.scene.getObjectByName(node),`${entry.file}: ${node}`);
    assert.equal(gltf.scene.getObjectByName('sail_01').morphTargetInfluences.length,2);
    assert.deepEqual(gltf.scene.getObjectByName('sail_01').morphTargetDictionary,{furl:0,inflate:1});
    if(gunCounts[entry.kind])for(const side of ['port','starboard'])for(let n=1;n<=gunCounts[entry.kind];n++) {
      const number=String(n).padStart(2,'0');
      const gun=gltf.scene.getObjectByName(`cannon_${side}_${number}`);
      assert.ok(gun.getObjectByName(`barrel_${side}_${number}`),`${entry.file}: stable recoil name after GLTFLoader`);
    }
  }
});
