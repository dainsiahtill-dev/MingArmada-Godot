/** Source-bound Cat Island importer. No game source, physics, source assets or evidence are mutated.
 * Run: rtk proxy node tools/import-fidelity-island.mjs [--verify-only] [--source-root=PATH]
 * Original DDS bytes/mips are retained; decoded PNG/RGBA are explicitly adapters, not original GPU frames.
 */
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {deflateSync} from 'node:zlib';
import assert from 'node:assert/strict';

const DEFAULT_SOURCE='C:/Games/Pirates-REA-Reference-20261011';
const ROOT=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const PINNED={
 'fidelity-rebuild/island/terrain-native.mjs':'5e8d38d96506e2264e3da6d9b231e01a83a833f51d45750a07de0be919d35cba',
 'fidelity-rebuild/island/light-native.mjs':'4d5c2f6de0d4276c690905d88b1ac7394db8b26eeb15df6a61ce31daff173d2b',
 'fidelity-rebuild/island/vegetation-native.mjs':'cc27feda3f912820f75d25db0da9509fd84e349e679cb3bb26a88845ba245ea3',
 'fidelity-rebuild/shore/source-data.mjs':'29399c0eaa1ec3862f0e5b90a183ea7cc9e601ce8d1be1d9c305acbc5aeb9278',
 'fidelity-rebuild/shore/native-math.mjs':'699617341b38d96b971c6fb3713dfa4c5154749cb2d2ed7c1b1c710113e64ddf',
 'fidelity-rebuild/island/data/cat-island-original.json':'3b5fdc5b3b4bff1be775b869bb338bcdcaf46518755f1353bf036423c33a11ca',
 'fidelity-rebuild/island/data/vegetation-original.json':'cb898b13e069efef569a3652b441fce73329cb477d6fed60f5ce6db521059667',
 'fidelity-rebuild/island/data/timeofday-original.json':'35b617251173d3f1fd69411b2271b2de5bd121e0d5197657b526d98b93617407',
 'fidelity-rebuild/island/data/native-light-fixtures.json':'08895d3a30fac4918cc9afa61fbb8e335887428fdf58d46db4330e33eee13ef6',
 'fidelity-rebuild/island/data/canopy-native-fixtures.json':'17bb65307116cead3e9421af668d217e1f7ca3916038704c7133dfd9519ec2c5',
 'fidelity-rebuild/island/data/geometry-color-native-fixtures.json':'1a548824db4f54c2040fdc920a1a81929e33c46a2f8b31c20c17207118b8a52d',
 'naval-study/island-water/source-study/geometry/cat_island_s.nif.json':'6a22748844510fde21a46a2b4761612296111e3825664dd7378126111dfa97d0',
 'naval-study/island-water/shore-source/island-authored-evidence.json':'f14bffa1435307857dd66a0c277be0a79cdbfac223874a542b146f0b987b92c5',
 'raw/fpk/Pak1/landscape.ini':'ab1db1891a3e64eea678a2781c4556a1c20290b70e45834b0bd9b80162681b9d',
 'raw/fpk/Pak2/surf_bart3.dds':'471d4cbe0c0106b5bfde7433c3179d839fc385c27c08d7f77d53d31edc4a20df',
};
const HASH=data=>createHash('sha256').update(data).digest('hex');
const jsonBytes=value=>Buffer.from(JSON.stringify(value,(_k,v)=>ArrayBuffer.isView(v)?Array.from(v):v)+'\n');
export function resolveWithin(root,relative){
 const base=path.resolve(root),target=path.resolve(base,relative),r=path.relative(base,target);
 if(r.startsWith('..')||path.isAbsolute(r))throw Error(`Path escape rejected: ${relative}`);return target;
}
function rgb565(v){const r=v>>>11,g=v>>>5&63,b=v&31;return [(r<<3)|(r>>>2),(g<<2)|(g>>>4),(b<<3)|(b>>>2)];}
function compressedPixels(bytes,w,h,kind){
 const output=Buffer.alloc(w*h*4),step=kind==='DXT1'?8:16;let offset=0;
 for(let by=0;by<Math.ceil(h/4);by++)for(let bx=0;bx<Math.ceil(w/4);bx++,offset+=step){
  const colorOffset=offset+(kind==='DXT1'?0:8),c0=bytes.readUInt16LE(colorOffset),c1=bytes.readUInt16LE(colorOffset+2),palette=[rgb565(c0),rgb565(c1)];
  if(c0>c1||kind!=='DXT1')palette.push(palette[0].map((v,i)=>Math.floor((2*v+palette[1][i])/3)),palette[0].map((v,i)=>Math.floor((v+2*palette[1][i])/3)));
  else palette.push(palette[0].map((v,i)=>Math.floor((v+palette[1][i])/2)),[0,0,0]);
  const selector=bytes.readUInt32LE(colorOffset+4),alpha=[];
  if(kind==='DXT5'){
   alpha.push(bytes[offset],bytes[offset+1]);
   if(alpha[0]>alpha[1])for(let i=1;i<=6;i++)alpha.push(Math.floor(((7-i)*alpha[0]+i*alpha[1])/7));
   else{for(let i=1;i<=4;i++)alpha.push(Math.floor(((5-i)*alpha[0]+i*alpha[1])/5));alpha.push(0,255);}
  }
  let alphaBits=0n;if(kind==='DXT5')for(let i=0;i<6;i++)alphaBits|=BigInt(bytes[offset+2+i])<<BigInt(i*8);
  for(let y=0;y<4;y++)for(let x=0;x<4;x++){
   const px=bx*4+x,py=by*4+y;if(px>=w||py>=h)continue;const p=y*4+x,c=selector>>>(2*p)&3,n=(px+py*w)*4;
   palette[c].forEach((v,k)=>output[n+k]=v);
   output[n+3]=kind==='DXT3'?((bytes[offset+(p>>>1)]>>((p&1)*4))&15)*17:kind==='DXT5'?alpha[Number(alphaBits>>BigInt(p*3)&7n)]:(c===3&&c0<=c1?0:255);
  }
 }
 return output;
}
export function decodeDDS(input){
 const bytes=Buffer.from(input);if(bytes.length<128||bytes.toString('ascii',0,4)!=='DDS '||bytes.readUInt32LE(4)!==124)throw Error('Invalid DDS header');
 const kind=bytes.toString('ascii',84,88),compressed=['DXT1','DXT3','DXT5'].includes(kind);let width=bytes.readUInt32LE(16),height=bytes.readUInt32LE(12),offset=128;
 const mipCount=Math.max(1,bytes.readUInt32LE(28));if(!width||!height||width>16384||height>16384||mipCount>32)throw Error('Invalid DDS dimensions');
 const masks=[92,96,100,104].map(p=>bytes.readUInt32LE(p));if(!compressed&&(bytes.readUInt32LE(88)!==32||kind!=='\0\0\0\0'))throw Error(`Unsupported DDS ${JSON.stringify(kind)}`);
 const levels=[];
 const unpack=(word,mask,defaultValue)=>{if(!mask)return defaultValue;let shift=0;while(((mask>>>shift)&1)===0)shift++;const m=mask>>>shift;return Math.round(((word&mask)>>>shift)*255/m);};
 for(let i=0;i<mipCount;i++){
  const n=compressed?Math.ceil(width/4)*Math.ceil(height/4)*(kind==='DXT1'?8:16):width*height*4;if(offset+n>bytes.length)throw Error('Truncated DDS mip');
  const original=bytes.subarray(offset,offset+n);let rgba;
  if(compressed)rgba=compressedPixels(original,width,height,kind);
  else{rgba=Buffer.alloc(n);for(let p=0;p<n;p+=4){const word=original.readUInt32LE(p);masks.forEach((m,c)=>rgba[p+c]=unpack(word,m,c===3?255:0));}}
  levels.push({width,height,bytes:rgba,original});offset+=n;width=Math.max(1,width>>>1);height=Math.max(1,height>>>1);
 }
 if(offset!==bytes.length)throw Error('Unparsed DDS trailing bytes');return {fourCC:compressed?kind:'RGBA32',levels,compressed};
}
function crc32(bytes){let c=0xffffffff;for(const b of bytes){c^=b;for(let k=0;k<8;k++)c=(c>>>1)^(c&1?0xedb88320:0);}return (c^0xffffffff)>>>0;}
export function encodePNG(width,height,rgba){
 if(rgba.length!==width*height*4)throw Error('RGBA PNG size mismatch');const chunk=(name,data)=>{const t=Buffer.from(name),head=Buffer.alloc(4),crc=Buffer.alloc(4);head.writeUInt32BE(data.length);crc.writeUInt32BE(crc32(Buffer.concat([t,data])));return Buffer.concat([head,t,data,crc]);};
 const header=Buffer.alloc(13);header.writeUInt32BE(width);header.writeUInt32BE(height,4);header[8]=8;header[9]=6;
 const rows=Buffer.alloc((width*4+1)*height);for(let r=0;r<height;r++)Buffer.from(rgba).copy(rows,r*(width*4+1)+1,r*width*4,(r+1)*width*4);
 return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',header),chunk('IDAT',deflateSync(rows)),chunk('IEND',Buffer.alloc(0))]);
}
export function shaderCanopySample(color,table){
 const [r,g,x,y]=color,address=Math.trunc((r*6+.04)*8+(g*6+.04));if(address<0||address+9>=64)throw Error('Canopy CXD address outside64');
 const value=c=>table[address*4+c]*(1-x)*(1-y)+table[(address+8)*4+c]*x*(1-y)+table[(address+1)*4+c]*(1-x)*y+table[(address+9)*4+c]*x*y;
 return {address,height:value(0),cull:value(1),shadow:value(2)};
}

async function main(args){
 const source=path.resolve(args.find(a=>a.startsWith('--source-root='))?.slice(14)||DEFAULT_SOURCE),verifyOnly=args.includes('--verify-only');
 const dataDir='assets/data/fidelity_island',texDir='assets/textures/fidelity_island',modelDir='assets/models/fidelity_island',sourceRecords=[],outputs=[];
 const readPinned=async(relative,digest)=>{const file=resolveWithin(source,relative),bytes=await readFile(file),sha256=HASH(bytes);if(digest&&sha256!==digest)throw Error(`Source SHA mismatch ${relative}: ${sha256}`);const prior=sourceRecords.find(s=>s.path===relative);if(prior)assert.equal(prior.sha256,sha256,`Source changed during read ${relative}`);else sourceRecords.push({path:relative,sha256,bytes:bytes.length});return bytes;};
 const originals=new Map();for(const [name,digest] of Object.entries(PINNED))originals.set(name,await readPinned(name,digest));
 const write=async(relative,bytes)=>{const file=resolveWithin(ROOT,relative);if(verifyOnly){const actual=await readFile(file);assert.equal(HASH(actual),HASH(bytes),`Generated output drift ${relative}`);}else{await mkdir(path.dirname(file),{recursive:true});await writeFile(file,bytes);}outputs.push({path:relative,sha256:HASH(bytes),bytes:bytes.length});return 'res://'+relative;};
 const writeJSON=(relative,value)=>write(relative,jsonBytes(value));
 const readJSON=name=>JSON.parse(originals.get(name));
 const cat=readJSON('fidelity-rebuild/island/data/cat-island-original.json'),vegetation=readJSON('fidelity-rebuild/island/data/vegetation-original.json'),time=readJSON('fidelity-rebuild/island/data/timeofday-original.json');
 for(const key of ['cat-island-original','vegetation-original','timeofday-original','native-light-fixtures','canopy-native-fixtures','geometry-color-native-fixtures'])await write(`${dataDir}/${key}.json`,originals.get(`fidelity-rebuild/island/data/${key}.json`));
 const textureRecords=[];
 async function texture(group,name,relative,digest,id=null){
  const bytes=await readPinned(relative,digest),dds=decodeDDS(bytes),stem=name.toLowerCase().replace(/\.dds$/,'').replace(/[^a-z0-9_-]/g,'_'),folder=`${texDir}/${group}/${stem}`;
  const originalPath=await write(folder+'.dds',bytes),texturePath=await write(folder+'.png',encodePNG(dds.levels[0].width,dds.levels[0].height,dds.levels[0].bytes));
  const rgbaMipPath=await write(folder+'.rgba.bin',Buffer.concat(dds.levels.map(l=>l.bytes)));
  const compressedMipPath=dds.compressed?await write(folder+'.bc.bin',Buffer.concat(dds.levels.map(l=>l.original))):null;
  let rgbaOffset=0,compressedOffset=0;const levels=dds.levels.map((l,i)=>{const info={level:i,width:l.width,height:l.height,rgbaOffset,rgbaBytes:l.bytes.length,rgbaSha256:HASH(l.bytes),originalOffset:128+compressedOffset,originalBytes:l.original.length,originalSha256:HASH(l.original)};rgbaOffset+=l.bytes.length;compressedOffset+=l.original.length;return info;});
  const record={group,name,id,originalSource:relative,originalSha256:digest,ddsPath:originalPath,texturePath,rgbaMipPath,compressedMipPath,width:dds.levels[0].width,height:dds.levels[0].height,mipmaps:dds.levels.length>1,mipLevels:dds.levels.length,format:dds.fourCC,godotCompressedImageFormat:dds.compressed?'FORMAT_'+dds.fourCC:null,levels,mipPolicy:'Original DDS and BC payload preserve authored mip bytes. RGBA chain independently decodes every authored mip, never regenerates. PNG contains decoded top level only; ordinary Godot PNG import may generate new mips and is not equivalent.'};
  textureRecords.push(record);return record;
 }
 for(const t of cat.textures)await texture('terrain',t.texturemap,t.original_path,t.sha256,Number(t.textureid));
 for(const asset of vegetation.assets){await write(`${modelDir}/${path.basename(asset.raw)}`,await readPinned(asset.raw,asset.sha256));const t=asset.meshes[0].texture;await texture('vegetation',path.basename(t.raw),t.raw,t.sha256);}
 for(const item of Object.values(cat.provenance))await write(`${dataDir}/original/${path.basename(item.path)}`,await readPinned(item.path,item.sha256));
 for(const item of Object.values(vegetation.maps))await write(`${dataDir}/original/${path.basename(item.raw)}`,await readPinned(item.raw,item.sha256));
 await write(`${dataDir}/original/timeofday.nif`,await readPinned(time.raw,time.sha256));
 await write(`${dataDir}/original/landscape.ini`,originals.get('raw/fpk/Pak1/landscape.ini'));
 const imp=async relative=>import(pathToFileURL(resolveWithin(source,relative)));
 const terrainNative=await imp('fidelity-rebuild/island/terrain-native.mjs'),vegetationNative=await imp('fidelity-rebuild/island/vegetation-native.mjs'),shoreNative=await imp('fidelity-rebuild/shore/source-data.mjs'),lightNative=await imp('fidelity-rebuild/island/light-native.mjs');
 const terrain=terrainNative.buildTerrainScene(cat),plants=vegetationNative.buildVegetationScene(vegetation,terrain);
 const terrainOut={schemaVersion:1,coordinateSystem:'native right-handed Z-up; Godot map [x,z,-y] is applied by presentation, never physics',managerAxes:terrain.managerAxes,effectiveScale:terrain.effectiveScale,translation:terrain.translation,surfLocalTranslation:terrain.surfLocalTranslation,waterLevel:terrain.waterLevel,textureScale:terrain.textureScale,textureOffset:terrain.textureOffset,shaderHeightModifier:terrain.shaderHeightModifier,textures:terrain.textures,cells:terrain.cells,vertexCount:terrain.vertexCount,triangleCount:terrain.triangleCount,authority:terrain.authority};
 await writeJSON(`${dataDir}/terrain-scene.json`,terrainOut);
 const mesh=m=>({positions:m.positions,normals:m.normals,uv:m.uv,indices:m.indices,colors:m.colors,texture:m.texture,texturing:m.texturing,material:m.material,alpha:m.alpha});
 await writeJSON(`${dataDir}/vegetation-scene.json`,{schemaVersion:1,coordinateSystem:'native Z-up',palm:mesh(plants.palm),canopy:mesh(plants.canopy),scale:plants.scale,dimensions:plants.dimensions,patches:plants.patches,treeTranslation:plants.treeTranslation,authority:plants.authority,scope:plants.scope,colorPacking:'Geometry5C5860, float32 multiply255 then nearest-even FISTP at explicit experimental FPCW037F; real game FPCW unobserved'});
 const geo=readJSON('naval-study/island-water/source-study/geometry/cat_island_s.nif.json'),authored=readJSON('naval-study/island-water/shore-source/island-authored-evidence.json'),shore=shoreNative.buildAuthoredScene(geo,authored);
 await write(`${modelDir}/cat_island_s.nif`,await readPinned(shore.source.raw,shore.source.sha256));
 const surf=await texture('shore','surf_bart3.dds','raw/fpk/Pak2/surf_bart3.dds',PINNED['raw/fpk/Pak2/surf_bart3.dds']);
 await writeJSON(`${dataDir}/shore-scene.json`,{schemaVersion:1,coordinateSystem:'native Z-up',meshes:shore.meshes,curves:shore.curves,root:shore.root,source:{raw:shore.source.raw,sha256:shore.source.sha256},translation:terrain.translation.map((v,i)=>Math.fround(v+terrain.surfLocalTranslation[i])),texture:surf,scope:'Original8 fixed short mesh segments; no generated full-ring shoreline. Complete original fixed-function lighting remains unconfirmed.'});
 const lightingSamples=[];for(let authoredTime=0;authoredTime<=24;authoredTime+=.25)lightingSamples.push(lightNative.daylightAt(time,authoredTime));
 await writeJSON(`${dataDir}/daylight-samples.json`,{schemaVersion:1,sampleInterval:.25,timeUnits:'original authoring time; no civil-time reinterpretation',initialFogValues:lightNative.initialFogValues(30000),samples:lightingSamples,scope:'Quarter-hour samples for preview; continuous exact keys remain in timeofday-original.json. Scene dimmer excluded from terrain/canopy shader LightColor; palm diagnostic dimmer included.'});
 const ids=cat.textures.map(t=>Number(t.textureid)),atlases=[];
 for(let group=0;group<Math.ceil(ids.length/4);group++){
  const rgba=Buffer.alloc(cat.width*cat.height*4),groupIds=ids.slice(group*4,group*4+4);
  for(let p=0;p<cat.height_indices.length;p++){const blend=terrainNative.decodeBlendPixel(cat,p);groupIds.forEach((id,c)=>{const k=blend.ids.indexOf(id);rgba[p*4+c]=k<0?0:blend.packedWeights[k];});}
  const atlasPath=await write(`${texDir}/terrain/weights_${group}.png`,encodePNG(cat.width,cat.height,rgba));atlases.push({ids:groupIds,path:atlasPath,encoding:'Original packed weight bytes; each nibble*1/15*heightFade independently. Never renormalized. Linear data sampling required.'});
 }
 const rawWeights=Buffer.alloc(cat.width*cat.height*ids.length*4);
 for(let p=0;p<cat.height_indices.length;p++){const b=terrainNative.decodeBlendPixel(cat,p);ids.forEach((id,c)=>rawWeights.writeFloatLE(b.weights[b.ids.indexOf(id)]??0,(p*ids.length+c)*4));}
 await write(`${dataDir}/terrain-weights-f32.bin`,rawWeights);
 const verification={sourcePins:0,canopyScalars:0,colorVertices:0,colorBoundaries:0,lightScalars:0,lightCoefficients:0,pathSamples:0,lookAtSamples:0,shore:{meshes:shore.meshes.length,vertices:shore.meshes.reduce((s,m)=>s+m.vertices.length/3,0),triangles:shore.meshes.reduce((s,m)=>s+m.indices.length/3,0)},passed:true};
 assert.equal(terrain.vertexCount,17182);assert.equal(terrain.triangleCount,11462);assert.deepEqual(plants.dimensions,[26,31]);assert.equal(plants.palm.positions.length/3,1612);assert.equal(plants.palm.indices.length/3,1046);assert.equal(plants.canopy.positions.length/3,3312);assert.equal(plants.canopy.indices.length/3,3519);assert.equal(surf.mipLevels,8);
 for(const c of readJSON('fidelity-rebuild/island/data/canopy-native-fixtures.json').cases){assert.deepEqual(Array.from(vegetationNative.canopyTable(vegetation,terrain,c.column,c.row).data),c.data);verification.canopyScalars+=c.data.length;}
 const colorFixture=readJSON('fidelity-rebuild/island/data/geometry-color-native-fixtures.json');vegetation.assets[1].meshes[0].colors.forEach((rgba,i)=>{assert.equal(vegetationNative.packGeometryColorARGB(rgba),colorFixture.canopy.packed_argb[i]);verification.colorVertices++;});colorFixture.boundaries.rgba.forEach((rgba,i)=>{assert.equal(vegetationNative.packGeometryColorARGB(rgba),colorFixture.boundaries.packed_argb[i]);verification.colorBoundaries++;});
 const lights=readJSON('fidelity-rebuild/island/data/native-light-fixtures.json'),blocks=new Map(time.blocks.map(b=>[b.id,b]));
 for(const c of lights.coefficient_cases){const keys=lightNative.vectorKeys(blocks.get(c.group).fields.data);assert.deepEqual(keys.coeff,c.segments);verification.lightCoefficients+=c.segments.length;}
 for(const c of lights.vector_cases){const keys=lightNative.vectorKeys(blocks.get(c.group).fields.data);assert.deepEqual(keys.value(c.segment,c.t),c.value);assert.deepEqual(keys.derivative(c.segment,c.t),c.derivative);verification.lightScalars+=6;}
 const lightPath=lightNative.constantSpeedPath(blocks.get(31).fields.data);assert.deepEqual(lightPath.lengths,lights.path_lengths);for(const c of lights.path_cases){assert.deepEqual(lightPath.at(c.fraction).position,c.position);verification.pathSamples++;}
 for(const c of lights.lookat_cases){assert.deepEqual(lightNative.lightDirection(c.position,c.target),c.direction);verification.lookAtSamples++;}
 assert.deepEqual(lightNative.initialFogValues(lights.fog_case.far),lights.fog_case.bindings.f3FogValues);
 for(const entry of sourceRecords)assert.equal(HASH(await readFile(resolveWithin(source,entry.path))),entry.sha256,`Source changed during import ${entry.path}`);
 verification.sourcePins=sourceRecords.length;
 const manifest={schemaVersion:1,sourceRoot:'Read-only original export; runtime has no dependency on absolute source directory',binarySha256:'0da87d60243280dea5965dbb23d099bcd0727db344de35886a5207e487a7e120',sources:sourceRecords,textures:textureRecords,terrain:{dataPath:`res://${dataDir}/cat-island-original.json`,scenePath:`res://${dataDir}/terrain-scene.json`,weightAtlases:atlases,rawWeightsPath:`res://${dataDir}/terrain-weights-f32.bin`,weightIds:ids,normalAxes:'[source.G-128,source.R-128,source.B-128]*original float1/127; Godot remaps [x,z,-y]',sandColor:[255/255,251/255,255/255],wetSandColor:[222/255,205/255,160/255],heightFade:'H<100=0; H>120=1; else(H-100)/20; independent nibble weights, no normalization'},vegetation:{originalPath:`res://${dataDir}/vegetation-original.json`,scenePath:`res://${dataDir}/vegetation-scene.json`},shore:{scenePath:`res://${dataDir}/shore-scene.json`},lighting:{originalPath:`res://${dataDir}/timeofday-original.json`,samplesPath:`res://${dataDir}/daylight-samples.json`},adaptation:{nativeCoordinates:'[x,y,z] Z-up => Godot[x,z,-y], determinant+1; mesh winding still must follow Godot engine clockwise frontface conventions',physics:'Imported data visual-only; existing port/collision/physics heights retain authority',unknown:['Original camera/LOD/pool lifecycle not executed','Complete palm FFP and shoreline FFP shading unknown','Original GPU D3D queue/8bit color accumulation not proven','DDS RGBA decoder is a presentation adapter, not proof of original GPU texels','Original live FPCW and whole original game frame unobserved'],water:'Existing project water shader deliberately untouched; original water_shader DDS can be reviewed separately'},verification,outputs};
 const manifestBytes=jsonBytes(manifest);
 await write(`${dataDir}/manifest.json`,manifestBytes);
 await mkdir(resolveWithin(ROOT,'build/fidelity-island-work'),{recursive:true});
 await writeFile(resolveWithin(ROOT,`build/fidelity-island-work/import-${verifyOnly?'verify':'result'}.json`),jsonBytes({schemaVersion:1,mode:verifyOnly?'verify':'import',importerSha256:HASH(await readFile(fileURLToPath(import.meta.url))),manifestSha256:HASH(manifestBytes),sourceRecords:sourceRecords.length,outputFiles:outputs.length,textureAssets:textureRecords.length,originalMipLevels:textureRecords.reduce((n,t)=>n+t.mipLevels,0),verification,sourceUnchanged:true,godotRun:false,gpuRun:false}));
 console.log(`FIDELITY_ISLAND_${verifyOnly?'VERIFY':'IMPORT'} sources=${sourceRecords.length} outputs=${outputs.length} textures=${textureRecords.length} canopyScalars=${verification.canopyScalars} colors=${verification.colorVertices}+${verification.colorBoundaries} lightScalars=${verification.lightScalars} passed=true`);
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main(process.argv.slice(2)).catch(error=>{console.error(error.stack);process.exitCode=1;});
