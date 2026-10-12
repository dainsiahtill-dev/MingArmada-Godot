/** Read-only source extraction for original Coastal2 / Virgin Islands material fields.
 * rtk proxy node tools/import-fidelity-material-variants.mjs [--verify-only] [--source-root=PATH]
 * The existing Cat material record and height authority are never regenerated.
 */
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';

const ROOT=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const SOURCE_ROOT='C:/Games/Pirates-REA-Reference-20261011';
const DATA='assets/data/fidelity_island';
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const jsonBytes=value=>Buffer.from(JSON.stringify(value)+'\n');
const DEFINITIONS=[
 {id:'coastal2',file:'coastal2-original.json',terrain:'Terrain4',width:329,height:193,
  sources:{height:['Pak1','h.bmp','8e49e57988fc08a1f0d7011e7171eefa5a051ca291f93cec7b004bf51cc7454c'],normal:['Pak7','n.tga','fdddb3d6c0cc02560af463b40de15e35ee599385937b388c2eaa57ae1eb5f6ed'],blend:['Pak0','b.tga','adc247e0598890c18d62036c12d69cc154ec8a6ae8159a82407c0beecdbae907'],bhi:['Pak4','b.tga.bhi','5ad92b02e54c118de5fe154fcd9e5eac245c2c120709c97e9dc35010ac177033']}},
 {id:'virgin_islands',file:'virgin-islands-original.json',terrain:'Terrain33',width:160,height:77,
  sources:{height:['Pak0','h.bmp','b51f493d475896b370c7df4ab60fdbc4fb13ca4c6b02b6e49c65770a002c9047'],normal:['Pak0','n.tga','d1b8c1c53bab49ba124a53ca38a403f4cb85b2d94beebbc0b274e5f53c53bce4'],blend:['Pak6','b.tga','7d91024375ca74138915b5e3749c7e47df4e1055f0cff796423e5b8330b2a66b'],bhi:['Pak4','b.tga.bhi','193c5a6394e8bbe05274f245f7aaf42a97245c04624829a2126ea24ed9dc7587']}}
];
const WEIGHT_IDS=[1,2,3,16,17,32,33,64,48,49];

function decodeHeight(bytes){
 assert.equal(bytes.toString('ascii',0,2),'BM');
 assert.equal(bytes.readUInt16LE(28),8,'height stream must retain original palette indices');
 assert.equal(bytes.readUInt32LE(30),0,'only original uncompressed indexed BMP is accepted');
 const width=bytes.readInt32LE(18),signedHeight=bytes.readInt32LE(22),height=Math.abs(signedHeight),stride=(width+3)&~3,offset=bytes.readUInt32LE(10);
 assert.ok(width>1&&height>1&&bytes.length>=offset+stride*height);
 const values=[];
 for(let y=0;y<height;y++){const start=offset+(signedHeight>0?height-1-y:y)*stride;for(let x=0;x<width;x++)values.push(bytes[start+x]);}
 return {width,height,values};
}
function decodeTga(bytes,channels){
 assert.deepEqual([...bytes.subarray(0,3)],[0,0,2],'native FTGALoader uncompressed/no-ID/no-palette input');
 assert.equal(bytes[16],channels*8);assert.ok(bytes[17]&32,'source row order is top-origin');assert.equal(bytes[17]&16,0);
 const width=bytes.readUInt16LE(12),height=bytes.readUInt16LE(14);assert.equal(bytes.length,18+width*height*channels);
 const pixels=Buffer.from(bytes.subarray(18));
 for(let i=0;i<pixels.length;i+=channels){const b=pixels[i];pixels[i]=pixels[i+2];pixels[i+2]=b;}
 return {width,height,pixels};
}
function decodeBhi(bytes){
 assert.equal((bytes.length-4)%9,0);const groups={};
 for(let offset=4;offset<bytes.length;offset+=9){const key=bytes.readUInt32LE(offset);assert.ok(!(key in groups));groups[key]=[...bytes.subarray(offset+4,offset+9)];}
 return groups;
}
function parseIni(bytes){
 const sections={};let current;
 for(const line of bytes.toString('latin1').split(/\r?\n/)){
  const section=line.match(/^\s*\[([^\]]+)\]/);if(section){current=sections[section[1]]={};continue;}
  const entry=line.match(/^\s*([^;#=]+?)\s*=\s*(.*?)\s*$/);if(entry&&current)current[entry[1].toLowerCase()]=entry[2];
 }
 return sections;
}
async function pinnedRead(root,relative,digest){
 const bytes=await readFile(path.join(root,relative));assert.equal(hash(bytes),digest,`original source SHA changed: ${relative}`);return bytes;
}
export async function buildVariantRecords(sourceRoot=SOURCE_ROOT){
 const configPath='raw/fpk/Pak1/landscape.ini',configSha='ab1db1891a3e64eea678a2781c4556a1c20290b70e45834b0bd9b80162681b9d';
 const nativePath='fidelity-rebuild/island/terrain-native.mjs',nativeSha='5e8d38d96506e2264e3da6d9b231e01a83a833f51d45750a07de0be919d35cba';
 const config=parseIni(await pinnedRead(sourceRoot,configPath,configSha));
 await pinnedRead(sourceRoot,nativePath,nativeSha);
 const native=await import(pathToFileURL(path.join(sourceRoot,nativePath)));
 const records=[];
 for(const definition of DEFINITIONS){
  const originals={},provenance={};
  for(const [key,[pak,suffix,sha256]] of Object.entries(definition.sources)){
   const relative=`raw/fpk/${pak}/${definition.id}_${suffix}`;originals[key]=await pinnedRead(sourceRoot,relative,sha256);provenance[key]={path:relative,sha256};
  }
  const H=decodeHeight(originals.height),N=decodeTga(originals.normal,3),B=decodeTga(originals.blend,4),groups=decodeBhi(originals.bhi);
  assert.deepEqual([H.width,H.height],[definition.width,definition.height]);assert.deepEqual([N.width,N.height],[H.width,H.height]);assert.deepEqual([B.width,B.height],[H.width,H.height]);
  assert.equal(config[definition.terrain].heightmap.toLowerCase(),`${definition.id}_h.bmp`);
  const packing={},streams={};
  for(const [label,order] of [['RGBA',[0,1,2,3]],['BGRA',[2,1,0,3]]]){
   const values=[];for(let i=0;i<B.pixels.length;i+=4)values.push(order.reduce((v,c,k)=>v+B.pixels[i+c]*2**(8*k),0));
   packing[label]={valid_group_pixels:values.filter(v=>groups[v&4095]).length,total:values.length,first:values.slice(0,8)};streams[label]=values;
  }
  assert.equal(packing.RGBA.valid_group_pixels,H.width*H.height,'FTGALoader B/R swap must yield valid native BHI for every pixel');
  const source={id:definition.id,authority:'original shipped H/N/B/BHI image bytes and matching landscape section; no synthetic height material weights',provenance,width:H.width,height:H.height,
   height_indices:H.values,normal_rgb:[...N.pixels],blend_u32:streams.RGBA,blend_byte_order:'RGBA',packing_validation:packing,bhi_header_hex:originals.bhi.subarray(0,4).toString('hex'),bhi_groups:groups,
   global:config.Global,terrain:config[definition.terrain],textures:Array.from({length:10},(_,i)=>({...config[`Texture${i}`],section:`Texture${i}`})),
   normal_byte_order:'native FTGALoader 51DED0 B/R swap -> RGB; original top-origin TGA bytes',lights:config.NavLights,
   parameter_provenance:{path:configPath,sha256:configSha,section:definition.terrain},native_oracle:{path:nativePath,sha256:nativeSha}};
  const weights=Buffer.alloc(H.width*H.height*10*4),normals=Buffer.alloc(H.width*H.height*3*4);
  for(let index=0;index<H.width*H.height;index++){
   const pixel=native.decodeBlendPixel(source,index);
   for(let channel=0;channel<WEIGHT_IDS.length;channel++){const slot=pixel.ids.indexOf(WEIGHT_IDS[channel]);weights.writeFloatLE(slot<0?0:pixel.weights[slot],(index*10+channel)*4);}
   [N.pixels[index*3+1],N.pixels[index*3],N.pixels[index*3+2]].forEach((byte,axis)=>normals.writeFloatLE(Math.fround((byte-128)*0.007874015718698502),(index*3+axis)*4));
  }
  records.push({...definition,source,originals,weights,normals,bytes:jsonBytes(source)});
 }
 return records;
}
async function main(args){
 const sourceRoot=args.find(a=>a.startsWith('--source-root='))?.slice(14)||SOURCE_ROOT,verifyOnly=args.includes('--verify-only');
 const records=await buildVariantRecords(sourceRoot),outputs=[];
 const write=async(relative,bytes)=>{
  const file=path.join(ROOT,relative);if(verifyOnly)assert.equal(hash(await readFile(file)),hash(bytes),`generated material drift: ${relative}`);
  else{await mkdir(path.dirname(file),{recursive:true});await writeFile(file,bytes);}outputs.push({path:`res://${relative}`,sha256:hash(bytes),bytes:bytes.length});return `res://${relative}`;
 };
 const variants=[];
 for(const item of records){
  const dataPath=await write(`${DATA}/${item.file}`,item.bytes);
  const weightPath=await write(`${DATA}/${item.id}-weights-f32.bin`,item.weights),normalPath=await write(`${DATA}/${item.id}-normals-f32.bin`,item.normals);
  for(const [key,bytes] of Object.entries(item.originals))await write(`${DATA}/original/${path.basename(item.source.provenance[key].path)}`,bytes);
  variants.push({id:item.id,dataPath,sha256:hash(item.bytes),width:item.width,height:item.height,weightPath,normalPath,weightIds:WEIGHT_IDS,
   sources:item.source.provenance,parameters:item.source.parameter_provenance,nativeOracle:item.source.native_oracle,
   nativeTextureScale:Math.fround(Math.fround(Number(item.source.terrain.texturescale))*Math.fround(Number(item.source.global.navtexturescaling))),
   nativeTextureOffset:[Number(item.source.terrain.textureoffx),Number(item.source.terrain.textureoffy)],sourcePixels:item.width*item.height});
 }
 await write(`${DATA}/material-variants.json`,jsonBytes({schemaVersion:1,variants,outputs,sourceReadOnly:true,scope:'Original per-profile material/normal streams, matching native landscape parameters; geometry/physics/sea unchanged'}));
 console.log(JSON.stringify({mode:verifyOnly?'verify':'import',variants:variants.map(v=>({id:v.id,pixels:v.sourcePixels,sha256:v.sha256})),files:outputs.length,sourceReadOnly:true,gpuRun:false}));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main(process.argv.slice(2)).catch(error=>{console.error(error.stack);process.exitCode=1;});
