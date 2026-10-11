import {mkdir,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {GLTFExporter} from 'three/addons/exporters/GLTFExporter.js';
import validator from 'gltf-validator';
import {createSailor,sailorStatistics,SAILOR_VARIANTS} from './build-sailor.mjs';

// Texture-free GLTFExporter needs only browser FileReader's Blob bridge in Node.
globalThis.FileReader??=class FileReader {
  readAsArrayBuffer(blob) {blob.arrayBuffer().then(result=>{this.result=result;this.onload?.({target:this});this.onloadend?.({target:this});}).catch(error=>this.onerror?.(error));}
};

export const SAILOR_OUTPUT=new URL('../../apps/game-client/public/models/sailors/',import.meta.url);

export async function exportSailorBinary(root) {
  // glTF skins must be scene roots: export mesh directly, keeping all bones beneath it.
  // Runtime may attach a SkeletonUtils clone to a vessel with Three's attached bind mode.
  const binary=await new GLTFExporter().parseAsync(root.getObjectByName('sailor_body'),{binary:true,onlyVisible:false,animations:root.animations});
  return Buffer.from(binary);
}

export async function exportSailors({directory=SAILOR_OUTPUT,log=console.log}={}) {
  await mkdir(directory,{recursive:true});
  const assets=[],reports=[];
  for(let lod=0;lod<3;lod++) {
    const root=createSailor({lod}),stats=sailorStatistics(root),file=`sailor-lod${lod}.glb`;
    const bytes=await exportSailorBinary(root),report=await validator.validateBytes(new Uint8Array(bytes),{uri:file});
    reports.push({file,report});
    if(report.issues.numErrors||report.issues.numWarnings)throw new Error(`${file}: ${JSON.stringify(report.issues)}`);
    await writeFile(new URL(file,directory),bytes);
    assets.push({lod,variant:'indigo',file,url:`/models/sailors/${file}`,...stats,nodes:stats.nodes-1,bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')});
    log(`${file}: ${stats.triangles} tris, ${stats.vertices} vertices, ${stats.bones} bones, 6 clips, ${bytes.length} bytes; validator 0 errors/0 warnings`);
    root.getObjectByName('sailor_body').geometry.dispose();root.getObjectByName('sailor_body').material.dispose();root.getObjectByName('sailor_body').skeleton.dispose();
  }
  const manifest={version:1,units:'metres',axes:{up:'+Y',forward:'+Z',feetY:0},
    authoring:'Original procedural late-Ming maritime cotton tunic, trousers, puttees and tied headcloth; no external mesh or texture assets',
    rig:{mesh:'sailor_body',rootBone:'sailor_root',hipsBone:'sailor_hips',bones:18,skin:'normalized linear blend skinning',rootMotion:false},
    material:{name:'sailor_worn_cotton',vertexColors:true,textures:0,roughness:.91},
    variants:SAILOR_VARIANTS,
    animation:{clock:'accepted simulation delta only',loop:true,clips:{idle:'small breathing and head scan',helm:'hands forward, alternate wheel/tiller work',haul:'both arms reach and pull sheet/line',
      'load-cannon':'crouch and two-handed rammer reach; triggered by actual fire/cooldown',walk:'alternating legs and arms in place; bounded deck patrol assigned by renderer',lookout:'raise right hand to brow and scan'}},
    assets};
  await writeFile(new URL('sailors-manifest.json',directory),JSON.stringify(manifest,null,2)+'\n');
  await writeFile(new URL('validation-report.json',directory),JSON.stringify(reports,null,2)+'\n');
  return {manifest,reports};
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)await exportSailors();
