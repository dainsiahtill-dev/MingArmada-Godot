import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {AnimationMixer} from 'three';
import {createSailor} from './build-sailor.mjs';

const exporter=await import('./export-sailors.mjs').catch(()=>null);
const validation=await import('./validate-sailors.mjs').catch(()=>null);
const clips=['idle','helm','haul','load-cannon','walk','lookout'];

test('binary GLTF roundtrip retains skin weights, all authored keys and effective animation',async()=>{
  assert.ok(exporter?.exportSailorBinary&&validation?.reloadSailor,'binary export and roundtrip API required');
  const source=createSailor(),bytes=await exporter.exportSailorBinary(source);
  const loaded=await validation.reloadSailor(bytes),mesh=loaded.scene.getObjectByName('sailor_body');
  assert.ok(mesh.isSkinnedMesh);assert.equal(mesh.skeleton.bones.length,18);
  assert.equal(mesh.material.vertexColors,true);
  assert.deepEqual([...mesh.geometry.attributes.skinWeight.array],[...source.getObjectByName('sailor_body').geometry.attributes.skinWeight.array]);
  assert.deepEqual(loaded.animations.map(c=>c.name),clips);
  for(const original of source.animations) {
    const actual=loaded.animations.find(c=>c.name===original.name);
    assert.ok(Math.abs(actual.duration-original.duration)<1e-6);
    assert.equal(actual.tracks.length,original.tracks.length);
    for(const track of original.tracks) {
      const reloaded=actual.tracks.find(t=>t.name===track.name);
      assert.ok(reloaded,track.name);assert.deepEqual([...reloaded.times],[...track.times]);
      assert.deepEqual([...reloaded.values],[...track.values]);
    }
    const mixer=new AnimationMixer(loaded.scene);mixer.clipAction(actual).play();mixer.setTime(0);
    const first=mesh.skeleton.bones.map(b=>b.quaternion.clone());mixer.setTime(actual.duration*.37);
    assert.ok(mesh.skeleton.bones.some((b,i)=>b.quaternion.angleTo(first[i])>.03));
    mixer.stopAllAction();mixer.uncacheRoot(loaded.scene);
  }
});

test('exported three LODs pass validator and read-only validation rejects tampered delivery',async()=>{
  assert.ok(exporter?.exportSailors&&validation?.validateSailors,'delivery export and validation required');
  const directory=pathToFileURL((await mkdtemp(join(tmpdir(),'ming-sailors-'))).replaceAll('\\','/')+'/');
  const result=await exporter.exportSailors({directory,log:()=>{}});
  assert.equal(result.manifest.assets.length,3);
  assert.equal(result.reports.length,3);
  for(const report of result.reports){assert.equal(report.report.issues.numErrors,0);assert.equal(report.report.issues.numWarnings,0);}
  assert.equal(await validation.validateSailors({directory,log:()=>{}}),0);
  const target=new URL('sailor-lod1.glb',directory),original=await readFile(target);
  const damaged=Buffer.from(original);damaged[damaged.length-1]^=1;await writeFile(target,damaged);
  const messages=[];
  assert.equal(await validation.validateSailors({directory,log:message=>messages.push(message)}),1);
  assert.ok(messages.some(m=>m.includes('SHA256')),'integrity check catches changed binary');
  assert.deepEqual(await readFile(target),damaged,'validator must not repair or regenerate');
});
