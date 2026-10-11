import {mkdir,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {GLTFExporter} from 'three/addons/exporters/GLTFExporter.js';
import validator from 'gltf-validator';
import {createShip,SHIP_SPECS,SHIP_GUN_COUNTS,shipStatistics} from './build-ship.mjs';

// GLTFExporter only needs Blob -> ArrayBuffer for texture-free binary exports.
globalThis.FileReader ??= class FileReader {
  readAsArrayBuffer(blob) {blob.arrayBuffer().then(result=>{this.result=result;this.onload?.({target:this});this.onloadend?.({target:this});}).catch(error=>this.onerror?.(error));}
  readAsDataURL(blob) {blob.arrayBuffer().then(result=>{this.result=`data:${blob.type};base64,${Buffer.from(result).toString('base64')}`;this.onload?.({target:this});this.onloadend?.({target:this});}).catch(error=>this.onerror?.(error));}
};
const output=new URL('../../apps/game-client/public/models/ships/',import.meta.url);
await mkdir(output,{recursive:true});
const assets=[],validation=[];
for(const kind of Object.keys(SHIP_SPECS))for(let lod=0;lod<3;lod++) {
  const ship=createShip(kind,lod),stats=shipStatistics(ship),file=`${kind}-lod${lod}.glb`;
  const binary=await new GLTFExporter().parseAsync(ship,{binary:true,onlyVisible:false});
  const bytes=Buffer.from(binary);
  const report=await validator.validateBytes(new Uint8Array(bytes),{uri:file});
  validation.push({file,errors:report.issues.numErrors,warnings:report.issues.numWarnings,infos:report.issues.numInfos,messages:report.issues.messages});
  if(report.issues.numErrors>0)throw new Error(`${file}: ${JSON.stringify(report.issues.messages)}`);
  await writeFile(new URL(file,output),bytes);
  const {length,beam,draft,freeboard}=SHIP_SPECS[kind];
  assets.push({kind,lod,file,url:`/models/ships/${file}`,dimensions:{length,beam,draft,freeboard},sailCount:SHIP_SPECS[kind].sails,gunsPerSide:SHIP_GUN_COUNTS[kind]??0,...stats,bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')});
  console.log(`${file}: ${stats.triangles} triangles, ${stats.meshes} meshes, ${bytes.length} bytes, validator ${report.issues.numErrors} errors/${report.issues.numWarnings} warnings`);
}
await writeFile(new URL('ships-manifest.json',output),JSON.stringify({version:1,units:'metres',axes:{up:'+Y',forward:'+Z',starboard:'-X',waterline:0},controls:{sails:{node:'sail_XX',morphTargets:{furl:0,inflate:1},range:[0,1]},rudder:{node:'rudder_pivot',axis:'rotation.y',units:'radians'},cannons:{node:'cannon_port_XX / cannon_starboard_XX',fireAxis:'local +Z',recoil:'child barrel_port_XX / barrel_starboard_XX.position.z (rest=0; recoil negative)'},flag:{node:'flag_01',animation:'small rotation.y and rotation.z sway'},wake:{node:'socket_wake'}},assets},null,2)+'\n');
await writeFile(new URL('validation-report.json',import.meta.url),JSON.stringify(validation,null,2)+'\n');
