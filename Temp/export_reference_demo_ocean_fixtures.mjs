import {writeFileSync,readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const source='C:/Games/Pirates-REA-Reference-20261011/naval-study/island-water/demo/';
const m=await import(pathToFileURL(source+'model.mjs').href);
const samples=[];
let seed=16611011;
const random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};
for(let i=0;i<240;i++){
  const x=(random()-.5)*4000,z=(random()-.5)*4000,time=(random()-.1)*200;
  const tide=[-3,0,1.25,4][i%4],strength=[0,.65,1,1.8,2,-1,3][i%7],footprint=[0,.4,.9,1.5,3,7,20][i%7];
  samples.push({x,z,time,tide,strength,footprint,...m.waveAt(x,z,time,tide,strength,footprint)});
}
const visibility=[];for(const length of [4.2,7,11,18])for(const footprint of [0,length*.25,length*.375,length*.5,length])visibility.push({length,footprint,value:m.waveVisibility(length,footprint)});
const mesh=m.oceanMesh(192),meshSamples=[];for(const i of [0,1,48,95,96,97,143,191,192,96*193+96,193*193-1])meshSamples.push({index:i,position:Array.from(mesh.positions.subarray(i*3,i*3+3)),footprint:mesh.footprint[i]});
const reflection=[];for(const tide of [-3,0,4])reflection.push({eye:[-87,116,115],target:[0,0,0],tide,...m.reflectCamera([-87,116,115],[0,0,0],tide)});
const sha256=Object.fromEntries(['model.mjs','shaders.mjs','renderer.mjs','app.mjs'].map(name=>[name,createHash('sha256').update(readFileSync(source+name)).digest('hex')]));
const fixture={source:source+'model.mjs',sha256,waves:m.WAVES,Q:m.Q,samples,visibility,mesh:{resolution:192,vertices:mesh.positions.length/3,indices:mesh.indices.length,samples:meshSamples,firstIndices:Array.from(mesh.indices.subarray(0,12))},reflection};
writeFileSync('C:/Users/dains/Documents/Git/ming-armada/tests/fixtures/reference-demo-ocean.json',JSON.stringify(fixture,null,2)+'\n');
console.log('REFERENCE_DEMO_OCEAN_FIXTURES',JSON.stringify({samples:samples.length,meshVertices:fixture.mesh.vertices,sha256}));
