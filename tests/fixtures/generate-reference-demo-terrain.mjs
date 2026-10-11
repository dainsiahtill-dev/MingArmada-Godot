import fs from 'node:fs';
import {createHash} from 'node:crypto';
import * as model from 'file:///C:/Games/Pirates-REA-Reference-20261011/naval-study/island-water/demo/model.mjs';
const source='C:/Games/Pirates-REA-Reference-20261011/naval-study/island-water/source-study/data/cat_island_h.bmp.json';
const field={...JSON.parse(fs.readFileSync(source,'utf8')),extent:160,heightScale:.35,seaIndex:128};
const xs=[[-80,-80],[80,80],[0,0],[12.2,-36.7],[-33.8,21.4],[79.999,0],[-80.001,0],[0,80.001]];
let seed=0xcafe1729;
for(let i=0;i<120;i++){seed=(Math.imul(seed,1664525)+1013904223)>>>0;const x=seed/4294967296*160-80;seed=(Math.imul(seed,1664525)+1013904223)>>>0;xs.push([x,seed/4294967296*160-80]);}
const vec=(arr,index)=>Array.from(arr.slice(index*3,index*3+3));
const sha=arr=>createHash('sha256').update(Buffer.from(arr.buffer,arr.byteOffset,arr.byteLength)).digest('hex');
const terrain=[];
for(const resolution of [1,4,160]){
 const data=model.terrainMesh(field,resolution),count=data.positions.length/3;
 const ids=[...new Set([0,1,resolution,resolution+1,Math.floor(count*.37),Math.floor(count*.61),count-2,count-1])];
 const heights=Float32Array.from({length:count},(_,i)=>data.positions[i*3+1]);
 terrain.push({resolution,vertexCount:count,indexCount:data.indices.length,positionsSha256:sha(data.positions),normalsSha256:sha(data.normals),uvSha256:sha(data.uv),indicesSha256:sha(new Int32Array(data.indices)),heightLutSha256:sha(heights),vertices:ids.map(index=>({index,position:vec(data.positions,index),normal:vec(data.normals,index),uv:Array.from(data.uv.slice(index*2,index*2+2))})),indices:Array.from(data.indices.slice(0,18)),lastIndices:Array.from(data.indices.slice(-18))});
}
const apron=[];
for(const segments of [4,160]){
 const data=model.seabedApron(field,segments),count=data.positions.length/3;
 const ids=[0,1,segments-1,segments,segments*4-1,segments*4,Math.floor(count*.51),count-1];
 apron.push({segments,vertexCount:count,indexCount:data.indices.length,positionsSha256:sha(data.positions),normalsSha256:sha(data.normals),indicesSha256:sha(new Int32Array(data.indices)),vertices:ids.map(index=>({index,position:vec(data.positions,index),normal:vec(data.normals,index)})),indices:Array.from(data.indices.slice(0,18)),lastIndices:Array.from(data.indices.slice(-18))});
}
const fixtures={sourceModule:'naval-study/island-water/demo/model.mjs',sourceData:'naval-study/island-water/source-study/data/cat_island_h.bmp.json',generator:'Original JavaScript functions executed by Node; float32 values are the actual typed-array payload.',samples:xs.map(([x,z])=>({x,z,height:model.heightAt(field,x,z),meshHeight:model.meshHeightAt(field,x,z,160)})),terrain,apron};
fs.mkdirSync('tests/fixtures',{recursive:true});fs.writeFileSync('tests/fixtures/reference-demo-terrain.json',JSON.stringify(fixtures,null,2)+'\n');
console.log('ORIGINAL_TERRAIN_FIXTURES '+xs.length+' heights, '+terrain.length+' terrain resolutions, '+apron.length+' apron resolutions');
