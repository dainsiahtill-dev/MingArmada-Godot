#!/usr/bin/env node
// Read-only completed-reference import for the island observer's NR water.
import assert from 'node:assert/strict';
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath, pathToFileURL} from 'node:url';
import path from 'node:path';
import {decodeDDS, encodePNG, resolveWithin} from './import-fidelity-island.mjs';

const ROOT=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const DEFAULT_SOURCE='C:/Games/Pirates-REA-Reference-20261011';
const PINS={
 'fidelity-rebuild/water/source-water.json':'70eecd16357ad4d4f3b3518dad21408952d27ea834b462c3c788b113ead1b383',
 'raw/fpk/Pak5/water_shader.dds':'a8cbf294cd6ec5b69a68b25b2765c1e16066b113eed11ef05d99604d6886a634',
};
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const jsonBytes=value=>Buffer.from(JSON.stringify(value)+'\n');

async function main(args){
 const source=path.resolve(args.find(a=>a.startsWith('--source-root='))?.slice(14)||DEFAULT_SOURCE),verify=args.includes('--verify-only');
 const sources=[],outputs=[];
 const read=async relative=>{const bytes=await readFile(resolveWithin(source,relative)),sha256=hash(bytes);if(PINS[relative])assert.equal(sha256,PINS[relative],`Read-only source changed: ${relative}`);sources.push({path:relative,sha256,bytes:bytes.length});return bytes;};
 const write=async(relative,bytes)=>{const destination=resolveWithin(ROOT,relative);if(verify)assert.equal(hash(await readFile(destination)),hash(bytes),`Generated water drift: ${relative}`);else{await mkdir(path.dirname(destination),{recursive:true});await writeFile(destination,bytes);}outputs.push({path:relative,sha256:hash(bytes),bytes:bytes.length});return 'res://'+relative;};
 const sourceBytes=await read('fidelity-rebuild/water/source-water.json'),ddsBytes=await read('raw/fpk/Pak5/water_shader.dds');
 await read('fidelity-rebuild/water/source-water.mjs');await read('fidelity-rebuild/island/water-pass.mjs');
 const {readWaterAsset,oceanCoordinates,oceanNRColor}=await import(pathToFileURL(resolveWithin(source,'fidelity-rebuild/water/source-water.mjs')));
 const mesh=readWaterAsset(JSON.parse(sourceBytes),'reflectivewater.nif'),dds=decodeDDS(ddsBytes);
 assert.equal(mesh.positions.length,12);assert.equal(mesh.uv.length,8);assert.equal(mesh.indices.length,6);
 assert.equal(dds.fourCC,'DXT1');assert.equal(dds.levels[0].width,256);assert.equal(dds.levels[0].height,256);assert.equal(dds.levels.length,9);
 const folder='assets/textures/fidelity_island/water/water_shader';
 const texture={originalSource:'raw/fpk/Pak5/water_shader.dds',originalSha256:PINS['raw/fpk/Pak5/water_shader.dds'],
  ddsPath:await write(folder+'.dds',ddsBytes),texturePath:await write(folder+'.png',encodePNG(256,256,dds.levels[0].bytes)),
  compressedMipPath:await write(folder+'.bc.bin',Buffer.concat(dds.levels.map(l=>l.original))),
  rgbaMipPath:await write(folder+'.rgba.bin',Buffer.concat(dds.levels.map(l=>l.bytes))),
  width:256,height:256,mipmaps:true,mipLevels:9,godotCompressedImageFormat:'FORMAT_DXT1',format:'DXT1',
  mipPolicy:'Original DDS compressed and independently decoded RGBA mip chain; no regeneration or PNG-import mip substitution.'};
 let rgbaOffset=0,bcOffset=0;texture.levels=dds.levels.map((level,i)=>{const record={level:i,width:level.width,height:level.height,rgbaOffset,rgbaBytes:level.bytes.length,rgbaSha256:hash(level.bytes),compressedOffset:bcOffset,compressedBytes:level.original.length,compressedSha256:hash(level.original)};rgbaOffset+=level.bytes.length;bcOffset+=level.original.length;return record;});
 const scene={schemaVersion:1,sourceSha256:PINS['fidelity-rebuild/water/source-water.json'],raw:mesh.source.raw,rawSha256:mesh.source.sha256,node:mesh.node,positions:Array.from(mesh.positions),uv:Array.from(mesh.uv),indices:Array.from(mesh.indices),texture:mesh.texture,authority:'Completed fidelity-rebuild/island/water-pass.mjs NR observation branch; gameplay physical waves are separate.'};
 const scenePath=await write('assets/data/fidelity_island/water-scene.json',jsonBytes(scene));
 const samples=[];
 for(const time of [-100,-45,-1,0,12,45,100])for(const uv of [[0,0],[.137,.892],[1,1]])samples.push({time,uv,scale:1,...oceanCoordinates(uv,time,1)});
 const ambient=[.4888235628604889,.5750980377197266,.7633333802223206],fogColor=[.458823561668396,.6941176652908325,.8509804606437683],colors=[];
 for(const [a,b]of[[[.41,.6,.72],[.65,.76,.87]],[[0,0,0],[1,1,1]],[[1,1,1],[1,1,1]]])for(const fog of [0,.35,1]){const nr=oceanNRColor(a,b,ambient),display=nr.slice(0,3).map((v,i)=>((1-fog)*v+fog*fogColor[i])*.4+fogColor[i]*.6);colors.push({a,b,ambient,fogColor,fog,nr,display});}
 const oracle={producer:'Completed read-only source-water.mjs oceanCoordinates/oceanNRColor; source display .4 alpha precomposition',samples,colors};
 const manifest={schemaVersion:1,mode:'completed-source-nr',sources,scenePath,texture,oracle,adaptation:{
  geometry:'Original four-vertex reflectivewater mesh, native [x,y,z] => Godot[x,z,-y], 9 source100000-unit tiles. Flat original Z0 water plane.',
  uv:'Original mesh UV*45, source signed45-second phase; no kilometre-scale formal normal map.',
  composition:'NR ambient/product shader, alpha.4 over source fog clear in display RGB; Godot precomposes display RGB then converts once to linear. No water depth write; base-water transparent queue precedes original surf.',
  physics:'Observer-only. No terrain sampler, water height, wave descriptor, navigation or formal-ocean changes.',
  scope:'Completed demo observation branch; original active game graphics-quality branch and full original framebuffer equivalence remain unproven.'},outputs};
 await write('assets/data/fidelity_island/water-manifest.json',jsonBytes(manifest));
 for(const entry of sources)assert.equal(hash(await readFile(resolveWithin(source,entry.path))),entry.sha256,`Source changed during import: ${entry.path}`);
 const work=resolveWithin(ROOT,'build/fidelity-wave-work/sea');await mkdir(work,{recursive:true});
 await writeFile(path.join(work,`import-${verify?'verify':'result'}.json`),jsonBytes({mode:verify?'verify':'import',sourceUnchanged:true,vertices:4,triangles:2,tiles:9,mipLevels:9,sourcePins:sources.length,outputs}));
 console.log(`FIDELITY_WATER_${verify?'VERIFY':'IMPORT'} sources=${sources.length} outputs=${outputs.length} vertices=4 triangles=2 tiles=9 mips=9 sourceUnchanged=true`);
}
main(process.argv.slice(2)).catch(error=>{console.error(error.stack);process.exitCode=1;});
