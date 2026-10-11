#!/usr/bin/env node
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const source=process.argv[process.argv.indexOf('--source-dir')+1] && process.argv.includes('--source-dir') ? path.resolve(process.argv[process.argv.indexOf('--source-dir')+1]) : 'C:/Games/Pirates-REA-Reference-20261011/naval-study/island-water/source-study/data';
const output=path.join(root,'assets/data/reference_islands');
const expected={cat_island:'d1b4f3b42347916ef7f85262e1ac16a65234c4981a374039b55ab0b417d30a1c',coastal2:'ce35636beb51ec4865e8073bd0d0803c75c88e3633770517233c657a254d950d',virgin_islands:'5224fcf8947623796cf50f4ffffbb1a59a385af3df9a4c8604a2ad3fbc6fe06f'};
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const referenceRoot=path.resolve(source,'../../../..');
const records=[];
// Read and validate every source before creating or replacing any project asset.
for(const [id,digest] of Object.entries(expected)) {
  const sourcePath=path.join(source,`${id}_h.bmp.json`);
  const bytes=await readFile(sourcePath);
  if(hash(bytes)!==digest)throw new Error(`source hash changed: ${id}`);
  const data=JSON.parse(bytes.toString('utf8'));
  if(!Number.isInteger(data.width)||data.width<2||!Number.isInteger(data.height)||data.height<2||!Array.isArray(data.values)||data.values.length!==data.width*data.height||data.values.some(v=>!Number.isInteger(v)||v<0||v>255))throw new Error(`invalid complete height indices: ${id}`);
  const rawBytes=await readFile(path.join(referenceRoot,data.source.raw));
  if(hash(rawBytes)!==data.source.sha256||rawBytes.length!==data.source.bytes)throw new Error(`original BMP provenance mismatch: ${id}`);
  records.push({id,bytes,data,provenance:{schema:'ming-armada-reference-island-v1',id,sourceJson:sourcePath,sourceJsonSha256:digest,sourceBitmap:data.source,dimensions:[data.width,data.height],indexCount:data.values.length,indexRange:[Math.min(...data.values),Math.max(...data.values)],encoding:data.encoding,originalWorldUnits:data.world_units,originalHeightScale:data.world_height_scale,adaptation:{seaIndex:128,seaIndexStatus:'Explicit game threshold; original sea level not recovered.',horizontal:'Preserve source silhouette and aspect; scale land extent to each game port radius, rotate toward the dock.',vertical:'Original positive indices normalized to port peak; negative indices normalized to 24 m seabed.',harbor:'Only a local navigation approach and pier landing apron are adapted.',boundary:'Close source image edges into deep water; coastal2 originally continues as mainland.'}}});
}
if(process.argv.includes('--verify')) {
  for(const record of records) {
    const bytes=await readFile(path.join(output,record.id,'height.json'));
    if(hash(bytes)!==expected[record.id])throw new Error(`imported height hash mismatch: ${record.id}`);
    const provenance=JSON.parse(await readFile(path.join(output,record.id,'provenance.json'),'utf8'));
    if(provenance.sourceJsonSha256!==expected[record.id]||provenance.sourceBitmap.sha256!==record.data.source.sha256||provenance.indexCount!==record.data.values.length)throw new Error(`imported provenance mismatch: ${record.id}`);
  }
} else {
  for(const record of records) {
    const target=path.join(output,record.id);await mkdir(target,{recursive:true});
    await writeFile(path.join(target,'height.json'),record.bytes);
    await writeFile(path.join(target,'provenance.json'),JSON.stringify(record.provenance,null,2)+'\n');
  }
}
console.log(`REFERENCE_ISLAND_IMPORT profiles=${records.length} indices=${records.reduce((sum,r)=>sum+r.data.values.length,0)} failures=0 mode=${process.argv.includes('--verify')?'verify':'import'}`);
