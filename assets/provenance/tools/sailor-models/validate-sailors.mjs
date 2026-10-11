import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {AnimationMixer,Box3,Vector3} from 'three';
import {GLTFLoader} from 'three/addons/loaders/GLTFLoader.js';
import validator from 'gltf-validator';

const output=new URL('../../apps/game-client/public/models/sailors/',import.meta.url);
const clipNames=['idle','helm','haul','load-cannon','walk','lookout'];
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');

export async function reloadSailor(bytes) {
  return new GLTFLoader().parseAsync(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength),'');
}

/** Validate current delivery; does not invoke generator, overwrite files or heal hashes. */
export async function validateSailors({directory=output,log=console.log}={}) {
  const failures=[];let checked=0,errors=0,warnings=0;
  try {
    const manifest=JSON.parse(await readFile(new URL('sailors-manifest.json',directory),'utf8'));
    if(manifest.version!==1||manifest.units!=='metres'||manifest.axes?.feetY!==0||manifest.axes?.forward!=='+Z'||manifest.axes?.up!=='+Y'||manifest.assets?.length!==3)throw new Error('invalid sailor manifest contract');
    const expected=new Set(['sailor-lod0.glb','sailor-lod1.glb','sailor-lod2.glb']);
    const triangleCounts=[];
    for(const asset of manifest.assets) {
      try {
        if(!Number.isInteger(asset.lod)||asset.lod<0||asset.lod>2||asset.file!==`sailor-lod${asset.lod}.glb`||!expected.delete(asset.file)||!/^[a-f0-9]{64}$/.test(asset.sha256)||!Number.isSafeInteger(asset.bytes))throw new Error('invalid or duplicate asset metadata');
        const bytes=await readFile(new URL(asset.file,directory));
        if(bytes.length!==asset.bytes)throw new Error('byte length mismatch');
        if(hash(bytes)!==asset.sha256)throw new Error('SHA256 mismatch');
        const report=await validator.validateBytes(new Uint8Array(bytes),{uri:asset.file});
        checked++;errors+=report.issues.numErrors;warnings+=report.issues.numWarnings;
        if(report.issues.numErrors||report.issues.numWarnings)throw new Error(`glTF validator ${report.issues.numErrors} errors/${report.issues.numWarnings} warnings`);
        const loaded=await reloadSailor(bytes),scene=loaded.scene,meshes=[];scene.traverse(o=>{if(o.isMesh)meshes.push(o);});
        const mesh=scene.getObjectByName('sailor_body');
        if(meshes.length!==1||!mesh?.isSkinnedMesh||mesh.skeleton.bones.length!==18||Array.isArray(mesh.material)||!mesh.material.vertexColors)throw new Error('merged rig/material lost on roundtrip');
        const g=mesh.geometry;
        if(g.index.count/3!==asset.triangles||g.attributes.position.count!==asset.vertices)throw new Error('topology differs from manifest');
        triangleCounts[asset.lod]=g.index.count/3;
        for(let i=0;i<g.attributes.position.count;i++) {
          let sum=0;
          for(let j=0;j<4;j++) {
            const w=g.attributes.skinWeight.array[i*4+j],index=g.attributes.skinIndex.array[i*4+j];
            if(!Number.isFinite(w)||w<0||w>1||!Number.isInteger(index)||index<0||index>=18)throw new Error('invalid skin weights/joints');sum+=w;
          }
          if(Math.abs(sum-1)>1e-6)throw new Error('skin weights do not sum to 1');
          for(let j=0;j<3;j++)if(!Number.isFinite(g.attributes.position.array[i*3+j]))throw new Error('non-finite vertex');
        }
        const bounds=new Box3().setFromObject(scene),size=bounds.getSize(new Vector3());
        if(Math.abs(bounds.min.y)>.005||size.y<1.6||size.y>1.75)throw new Error('deck origin/human scale invalid');
        for(const [field,value] of [['width',size.x],['height',size.y],['depth',size.z]])if(Math.abs(value-asset.dimensions[field])>1e-5)throw new Error(`dimension ${field} differs from manifest`);
        if(loaded.animations.length!==6||loaded.animations.some((c,i)=>c.name!==clipNames[i]))throw new Error('required clips absent');
        for(const clip of loaded.animations) {
          const summary=asset.clips.find(c=>c.name===clip.name);
          if(!summary||Math.abs(clip.duration-summary.duration)>1e-6||clip.tracks.length!==summary.tracks||clip.duration<=0||clip.tracks.length<3)throw new Error(`${clip.name}: duration/tracks differ`);
          for(const track of clip.tracks) {
            if((!track.name.endsWith('.quaternion')&&track.name!=='sailor_hips.position')||track.name.startsWith('sailor_root.')||track.times.length<3||![...track.times,...track.values].every(Number.isFinite))throw new Error(`${clip.name}: invalid animation channel`);
          }
          const mixer=new AnimationMixer(scene);mixer.clipAction(clip).play();mixer.setTime(0);
          const first=mesh.skeleton.bones.map(b=>b.quaternion.clone());mixer.setTime(clip.duration*.37);
          if(!mesh.skeleton.bones.some((b,i)=>b.quaternion.angleTo(first[i])>.03))throw new Error(`${clip.name}: no actual joint motion`);
          mixer.stopAllAction();mixer.uncacheRoot(scene);
        }
        g.dispose();mesh.material.dispose();mesh.skeleton.dispose();
      } catch(error) {failures.push(`${asset.file}: ${error instanceof Error?error.message:String(error)}`);}
    }
    if(expected.size)failures.push('LOD coverage incomplete');
    if(!(triangleCounts[0]>triangleCounts[1]*1.4&&triangleCounts[1]>triangleCounts[2]*1.4))failures.push('LODs do not reduce topology');
  }catch(error){failures.push(error instanceof Error?error.message:String(error));}
  failures.forEach(message=>log(`FAIL ${message}`));
  log(`${failures.length?'FAIL':'OK'} ${checked}/3 sailor GLBs; ${failures.length} failed checks; validator ${errors} errors/${warnings} warnings; SHA256/bytes/skin/clip motion roundtrip checked`);
  return failures.length?1:0;
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)process.exitCode=await validateSailors();
