#!/usr/bin/env node
/**
 * Resource-only import. Raw authored records are not a runtime particle evaluator.
 * Full contract: 276 systems; compact-demo's ten teaching systems are not an input.
 * External images resolve from source block references through the whole fpk tree.
 */
import {readFile,writeFile,mkdir,readdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const ROOT=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const DEFAULT_REFERENCE='C:/Games/Pirates-REA-Reference-20261011';
const A='naval-study/atmosphere-fx/source-study';
const D='naval-study/deep/asset-details/complete-assets.json';
const S='naval-study/island-water/source-study';
const DATA='assets/data/reference_atmosphere';
const TEX='assets/textures/reference_atmosphere';
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const slash=value=>value.replaceAll('\\','/');
const compare=(a,b)=>a<b?-1:a>b?1:0;
// JSON.stringify erases float32 negative zero. Preserve it together with every authored value.
function stableJSON(value,depth=0) {
  if(typeof value==='number'&&Object.is(value,-0))return '-0.0';
  if(value===null||typeof value!=='object')return JSON.stringify(value);
  const indent='  '.repeat(depth),inner=indent+'  ';
  if(Array.isArray(value))return value.length?'[\n'+value.map(x=>inner+(stableJSON(x,depth+1)??'null')).join(',\n')+'\n'+indent+']':'[]';
  const keys=Object.keys(value).filter(key=>value[key]!==undefined).sort(compare);
  return keys.length?'{\n'+keys.map(key=>inner+JSON.stringify(key)+': '+stableJSON(value[key],depth+1)).join(',\n')+'\n'+indent+'}':'{}';
}
const jsonBytes=value=>Buffer.from(stableJSON(value)+'\n');

export function safeInside(root,relative) {
  if(path.isAbsolute(relative)||/^[A-Za-z]:/.test(relative))throw new Error(`absolute path outside resource root: ${relative}`);
  const resolved=path.resolve(root,relative),prefix=path.resolve(root)+path.sep;
  if(!resolved.toLowerCase().startsWith(prefix.toLowerCase()))throw new Error(`path outside resource root: ${relative}`);
  return resolved;
}

// Exact spelling ignores case, but never changes an extension or picks one Pak variant.
export function resolveNamedTexture(fileName,catalog) {
  const name=slash(fileName).replace(/^\.\//,'').toLowerCase();
  const exact=catalog.filter(item=>{
    const raw=slash(item.raw).toLowerCase();
    return raw===name||raw.replace(/^raw\//,'')===name;
  });
  if(exact.length)return exact.sort((a,b)=>compare(a.raw,b.raw));
  if(/^(?:raw\/)?fpk\//.test(name))return []; // A named archive cannot fall back to another Pak.
  const base=name.split('/').at(-1);
  return catalog.filter(item=>item.name.toLowerCase()===base).sort((a,b)=>compare(a.raw,b.raw));
}

// Includes shader texture arrays and legacy NiTextureProperty.image, retaining slot paths.
export function textureSlots(property) {
  const result=[];
  function visit(value,keys) {
    if(!value||typeof value!=='object')return;
    if(Number.isInteger(value.ref)&&['NiSourceTexture','NiImage'].includes(value.type)) {
      let slot=keys.join('.').replace(/\.(source|image)$/,'');
      if(!slot)slot=keys.at(-1)||'image';
      result.push({slot,ref:value.ref,reference:value});return;
    }
    for(const [key,item] of Object.entries(value))visit(item,[...keys,key]);
  }
  visit(property.fields,[]);return result;
}

function countTypes(items,typeOf=x=>x.type) {
  const result={};for(const item of items){const name=typeOf(item);result[name]=(result[name]||0)+1;}return result;
}

// Batch Pillow check independently decodes original DDS/TGA and chosen full-tree PNGs.
// NiPixelData cloud is decoded from exported bytes, masks and mip offset, never a lookalike.
const PIXEL_CHECK=String.raw`
import sys,json,pathlib,hashlib
from PIL import Image
items=json.load(sys.stdin); output=[]
for item in items:
    png=Image.open(item['png']).convert('RGBA'); pixels=png.tobytes()
    if item.get('embedded_json'):
        asset=json.loads(pathlib.Path(item['embedded_json']).read_text(encoding='utf-8'))
        block=next(b for b in asset['blocks'] if b['id']==item['pixel_block_id'])
        f=block['fields']; mip=f['mipmaps'][0]
        if f['bits_per_pixel']!=32 or f['bytes_per_pixel']!=4: raise ValueError('unsupported embedded pixel layout')
        data=bytes(v for row in f['pixel_data'] for v in row)
        start=mip['offset']; size=mip['width']*mip['height']*4
        packed=data[start:start+size]; decoded=bytearray()
        masks=[f['red_mask'],f['green_mask'],f['blue_mask'],f['alpha_mask']]
        for i in range(0,len(packed),4):
            value=int.from_bytes(packed[i:i+4],'little')
            for mask in masks:
                if not mask: decoded.append(255); continue
                shift=(mask & -mask).bit_length()-1; maximum=mask>>shift
                decoded.append(round(((value & mask)>>shift)*255/maximum))
        original=Image.frombytes('RGBA',(mip['width'],mip['height']),bytes(decoded))
    else: original=Image.open(item['raw']).convert('RGBA')
    if original.size!=png.size or original.tobytes()!=pixels: raise ValueError('decoded original/PNG mismatch: '+item['id'])
    if item.get('expected_rgba') and hashlib.sha256(pixels).hexdigest()!=item['expected_rgba']: raise ValueError('study RGBA SHA mismatch: '+item['id'])
    alphas=list(png.getchannel('A').getdata()); zero=alphas.count(0); opaque=alphas.count(255)
    hist=png.getchannel('A').histogram(); w,h=png.size
    border=[png.getpixel((x,0))[3] for x in range(w)]+[png.getpixel((x,h-1))[3] for x in range(w)]+[png.getpixel((0,y))[3] for y in range(h)]+[png.getpixel((w-1,y))[3] for y in range(h)]
    output.append({'id':item['id'],'width':w,'height':h,'decoded_rgba_sha256':hashlib.sha256(pixels).hexdigest(),'decoded_original_equal':True,'channel_ranges':dict(zip('RGBA',[list(x) for x in png.getextrema()])),'alpha_histogram':{str(i):n for i,n in enumerate(hist) if n},'alpha_zero_pixels':zero,'alpha_opaque_pixels':opaque,'alpha_partial_pixels':len(alphas)-zero-opaque,'border_alpha_range':[min(border),max(border)],'transparent_nonblack_rgb_pixels':sum(1 for r,g,b,a in png.getdata() if a==0 and (r or g or b)),'rgb_greater_than_alpha_pixels':sum(1 for r,g,b,a in png.getdata() if max(r,g,b)>a)})
print(json.dumps(output,separators=(',',':')))
`;

export async function importReference({referenceRoot=DEFAULT_REFERENCE,outputRoot=ROOT,verifyOnly=false}={}) {
  referenceRoot=path.resolve(referenceRoot);outputRoot=path.resolve(outputRoot);
  if(referenceRoot.toLowerCase()===outputRoot.toLowerCase()||outputRoot.toLowerCase().startsWith((referenceRoot+path.sep).toLowerCase()))throw new Error('Reference tree is read-only; output must be separate');
  const inputs=new Map(),outputs=new Map(),rawHashes=new Map();
  async function input(relative) {
    if(inputs.has(relative))return inputs.get(relative).data;
    const bytes=await readFile(safeInside(referenceRoot,relative));const data=JSON.parse(bytes.toString('utf8'));
    inputs.set(relative,{data,sha256:sha(bytes),bytes:bytes.length});return data;
  }
  async function verifiedRaw(raw,expected) {
    if(!rawHashes.has(raw))rawHashes.set(raw,sha(await readFile(safeInside(referenceRoot,raw))));
    const actual=rawHashes.get(raw);
    if(expected&&actual!==expected)throw new Error(`Original SHA mismatch: ${raw}`);
    return actual;
  }
  const contract=await input(`${A}/particle-contract.json`);
  if(contract.contract_version!==1||contract.systems.length!==276)throw new Error('Expected full v1, 276-system particle contract');
  const studied=await input(`${A}/textures.json`);
  if(studied.textures.length!==53||studied.unresolved.length)throw new Error('Atmosphere study dependency contract changed');
  const manifest=await input('reports/extraction-manifest.json');
  const entries=manifest.archives.flatMap(x=>x.entries);
  const entryByRaw=new Map(entries.map(x=>[x.output,x]));
  const catalogAll=await input('reports/resource-catalog.json');
  const catalog=catalogAll.filter(x=>x.preview?.startsWith('preview/images/fpk/'));
  const refTextures=new Map();
  for(const texture of studied.textures)for(const ref of texture.references) {
    const key=`${ref.raw}#${ref.texture_block_id??`pixel-${ref.pixel_block_id}`}`;
    if(!refTextures.has(key))refTextures.set(key,[]);
    refTextures.get(key).push(texture);
  }

  const assets=new Map();
  function addAsset(asset,source,scope) {
    if(assets.has(asset.raw)) {
      const current=assets.get(asset.raw);
      if(current.asset.sha256!==asset.sha256)throw new Error(`Two parsed sources disagree: ${asset.raw}`);
      current.scopes.add(scope);current.sources.add(source);return;
    }
    assets.set(asset.raw,{asset,scopes:new Set([scope]),sources:new Set([source])});
  }
  const atmosphereFiles=(await readdir(safeInside(referenceRoot,`${A}/assets-json`))).filter(x=>x.endsWith('.json')).sort(compare);
  for(const filename of atmosphereFiles)addAsset(await input(`${A}/assets-json/${filename}`),`${A}/assets-json/${filename}`,'atmosphere');
  const deep=await input(D);
  const waterSurfaceNames=['waterbasin.nif','reflectivewater.nif','water.nif'];
  for(const asset of deep.assets)if(/splash|froth/i.test(asset.name)||waterSurfaceNames.includes(asset.name.toLowerCase()))addAsset(asset,D,waterSurfaceNames.includes(asset.name.toLowerCase())?'water_surface':'water_effect');
  const shore=await input(`${S}/nif-structures.json`);
  for(const asset of shore)addAsset(asset,`${S}/nif-structures.json`,'shoreline');
  const orderedAssets=[...assets.values()].sort((a,b)=>compare(a.asset.raw,b.asset.raw));
  for(const item of orderedAssets) {
    await verifiedRaw(item.asset.raw,item.asset.sha256);
    if(!item.asset.whole_file_consumed||item.asset.bytes!==item.asset.bytes_consumed)throw new Error(`Incomplete parsed asset: ${item.asset.raw}`);
    item.resource=`res://${DATA}/definitions/assets/${item.asset.raw.replace(/^raw\/fpk\//,'')}.json`;
    outputs.set(item.resource.slice(6),jsonBytes(item.asset));
    item.blockMap=new Map(item.asset.blocks.map(block=>[block.id,block]));
  }

  const textureRecords=new Map(),unresolved=[],boundAssets=[];
  async function registerTexture(raw,study=null) {
    const kind=raw.endsWith('.nif')?'embedded':'external';
    const id=kind==='embedded'?`${raw}#pixel-0`:raw;
    if(textureRecords.has(id))return textureRecords.get(id);
    const entry=entryByRaw.get(raw);
    if(!entry)throw new Error(`Original missing in extraction manifest: ${raw}`);
    const rawHash=await verifiedRaw(raw,study?.sha256||entry.sha256);
    let preview,relative,embeddedJson;
    if(kind==='embedded') {
      if(raw!=='raw/fpk/Pak5/cloud.nif'||!study)throw new Error(`Unrecovered embedded layout: ${raw}`);
      preview=`${A}/${study.png}`;
      relative=`${TEX}/embedded/Pak5/cloud.nif/embedded-0.png`;
      embeddedJson=safeInside(referenceRoot,`${A}/assets-json/cloud.nif.json`);
    } else {
      const cat=catalog.find(x=>x.raw===raw);
      if(!cat)throw new Error(`Bound texture has no full-fpk PNG: ${raw}`);
      preview=cat.preview;relative=`${TEX}/${raw.replace(/^raw\//,'')}.png`;
    }
    const pngBytes=await readFile(safeInside(referenceRoot,preview));
    if(study) {
      // Independent study PNG can use a different PNG encoder; pixel equality is checked below.
      const studyBytes=await readFile(safeInside(referenceRoot,`${A}/${study.png}`));
      if(sha(studyBytes)!==study.png_sha256)throw new Error(`Study PNG SHA mismatch: ${raw}`);
    }
    const record={id,kind,raw,raw_sha256:rawHash,raw_sha256_verified:true,preview,resource:`res://${relative}`,png_sha256:sha(pngBytes),png_bytes:pngBytes.length,
      ...(kind==='embedded'?{pixel_block_id:0,embedded_mip:0}:{}),references:[],
      ...(study?{study_png:`${A}/${study.png}`,study_png_sha256:study.png_sha256,study_decoded_rgba_sha256:study.decoded_rgba_sha256}:{}),
      _pixels:{id,png:safeInside(referenceRoot,preview),raw:safeInside(referenceRoot,raw),expected_rgba:study?.decoded_rgba_sha256,...(embeddedJson?{embedded_json:embeddedJson,pixel_block_id:0}:{})}};
    textureRecords.set(id,record);outputs.set(relative,pngBytes);return record;
  }
  async function bindProperty(assetInfo,property) {
    const textureBindings={};
    for(const slot of textureSlots(property)) {
      const source=assetInfo.blockMap.get(slot.ref);
      if(!source)throw new Error(`Texture source block missing: ${assetInfo.asset.raw}#${slot.ref}`);
      const evidence=refTextures.get(`${assetInfo.asset.raw}#${slot.ref}`);
      const candidates=evidence?evidence.map(x=>({raw:x.raw,study:x})):resolveNamedTexture(source.fields.file_name||'',catalog).map(x=>({raw:x.raw,study:studied.textures.find(t=>t.raw===x.raw)}));
      const files=[];
      for(const candidate of candidates) {
        const texture=await registerTexture(candidate.raw,candidate.study);
        const consumer={asset_raw:assetInfo.asset.raw,asset_sha256:assetInfo.asset.sha256,property_block_id:property.id,source_texture_block_id:source.id,slot:slot.slot,scopes:[...assetInfo.scopes].sort(compare)};
        if(!texture.references.some(x=>JSON.stringify(x)===JSON.stringify(consumer)))texture.references.push(consumer);
        files.push({id:texture.id,raw:texture.raw,raw_sha256:texture.raw_sha256,resource:texture.resource,png_sha256:texture.png_sha256});
      }
      const selection=evidence?'source_study_asset_and_block_reference':candidates.length>1?'ambiguous_exact_filename_variants':'whole_fpk_exact_filename';
      textureBindings[slot.slot]={source_texture_block_id:source.id,source_texture_type:source.type,fields:source.fields,descriptor:slot.slot.split('.').reduce((v,k)=>v?.[k],property.fields),selection,files};
      if(!files.length)unresolved.push({asset_raw:assetInfo.asset.raw,property_block_id:property.id,source_texture_block_id:source.id,slot:slot.slot,file_name:source.fields.file_name||null,reason:'No exact filename dependency; no extension/name substitution imposed'});
    }
    return textureBindings;
  }
  for(const item of orderedAssets) {
    const properties=[];
    for(const prop of item.asset.blocks.filter(x=>['NiTexturingProperty','NiTextureProperty'].includes(x.type))) {
      const owners=item.asset.blocks.filter(x=>x.fields?.properties?.some(p=>p.ref===prop.id)).map(x=>({id:x.id,name:x.name,type:x.type,scene_paths:x.scene_paths}));
      properties.push({property_block_id:prop.id,property:prop,owners,texture_bindings:await bindProperty(item,prop)});
    }
    boundAssets.push({raw:item.asset.raw,sha256:item.asset.sha256,name:item.asset.name,version:item.asset.version,scopes:[...item.scopes].sort(compare),source_json:[...item.sources].sort(compare),resource:item.resource,properties});
  }
  // A legacy cloud asset contains only NiPixelData and has no texturing property itself.
  for(const texture of studied.textures)await registerTexture(texture.raw,texture);

  const systems=[];
  for(const original of contract.systems) {
    const assetInfo=assets.get(original.raw);
    if(!assetInfo||assetInfo.asset.sha256!==original.sha256)throw new Error(`Particle source asset mismatch: ${original.raw}`);
    const texturePaths=[];
    for(const chain of original.property_chains) {
      const properties=[];
      for(const declared of chain)properties.push({...declared,texture_bindings:await bindProperty(assetInfo,declared.property)});
      texturePaths.push({properties});
    }
    systems.push({...original,id:`${original.raw}#${original.system_id}`,particle_capacity:original.data.fields.num_vertices,source_asset:assetInfo.resource,texture_paths:texturePaths});
  }
  const effects=[...new Set(systems.map(x=>x.raw))].sort(compare).map(raw=>({id:raw,name:assets.get(raw).asset.name,raw,sha256:assets.get(raw).asset.sha256,source_asset:assets.get(raw).resource,system_ids:systems.filter(x=>x.raw===raw).map(x=>x.id)}));

  const textures=[...textureRecords.values()].sort((a,b)=>compare(a.id,b.id));
  const pixelRun=spawnSync('rtk',['proxy','python','-X','utf8','-c',PIXEL_CHECK],{input:JSON.stringify(textures.map(x=>x._pixels)),encoding:'utf8',maxBuffer:32*1024*1024,windowsHide:true});
  if(pixelRun.error||pixelRun.status!==0)throw new Error(`Pixel verification failed: ${pixelRun.error||pixelRun.stderr||pixelRun.stdout}`);
  let pixels;try { pixels=JSON.parse(pixelRun.stdout.trim()); }catch{throw new Error(`Pixel verifier did not return JSON: ${pixelRun.stdout.slice(0,500)}`);}
  const pixelById=new Map(pixels.map(x=>[x.id,x]));
  for(const texture of textures){delete texture._pixels;Object.assign(texture,pixelById.get(texture.id));}
  for(const asset of boundAssets)for(const prop of asset.properties)for(const slot of Object.values(prop.texture_bindings))for(const file of slot.files) {
    const record=textureRecords.get(file.id);file.decoded_rgba_sha256=record.decoded_rgba_sha256;file.width=record.width;file.height=record.height;file.channel_ranges=record.channel_ranges;
  }
  for(const system of systems)for(const p of system.texture_paths)for(const prop of p.properties)for(const slot of Object.values(prop.texture_bindings))for(const file of slot.files){const record=textureRecords.get(file.id);file.decoded_rgba_sha256=record.decoded_rgba_sha256;file.width=record.width;file.height=record.height;file.channel_ranges=record.channel_ranges;}

  const shaderFiles=[
    ['WaterShader/OceanWaterEMBM_ps11.nsf','reflection_and_ocean'],
    ['WaterShader/OceanWaterSparkle_ps11.nsf','ocean_whitecaps'],
    ['SparkleShader/WaterSparkle.nsf','water_sparkle']
  ];
  const shaderSlots=[];
  for(const [name,role] of shaderFiles) {
    const relative=`naval-study/original-shaders/Assets/Shaders/FX/${name}`,bytes=await readFile(safeInside(referenceRoot,relative)),text=bytes.toString('utf8');
    inputs.set(relative,{data:null,sha256:sha(bytes),bytes:bytes.length});
    const stages=[...text.matchAll(/NTM_(Base|Detail)/g)].map(x=>x[0]);
    shaderSlots.push({source:relative,sha256:sha(bytes),role,authored_slots:stages,binding_kind:'authored_shader_slot_semantics',runtime_binding_verified:false,bound_filename:null});
    if(text.includes('"empty.dds"'))shaderSlots.push({source:relative,sha256:sha(bytes),slot:'tReflectionTexture',default_filename:'empty.dds',binding_kind:'authored_shader_default',runtime_binding_verified:false,bound_filename:null,
      candidates:resolveNamedTexture('empty.dds',catalog).map(x=>({raw:x.raw,preview:x.preview})),boundary:'Declared fallback only; native runtime reflection target is not this image binding'});
  }
  const unboundCaustic=await input(`${S}/unbound-texture-candidates.json`);
  const wholeInventory=[];
  const actualFpk=[];
  async function pngTree(relative) {
    for(const entry of (await readdir(safeInside(referenceRoot,relative),{withFileTypes:true})).sort((a,b)=>compare(a.name,b.name))) {
      const p=`${relative}/${entry.name}`;
      if(entry.isDirectory())await pngTree(p);
      else if(entry.name.toLowerCase().endsWith('.png'))actualFpk.push(p);
    }
  }
  await pngTree('preview/images/fpk');
  const catByPreview=new Map(catalog.map(x=>[x.preview,x]));
  for(const preview of actualFpk) {
    const cat=catByPreview.get(preview),raw=cat?.raw||preview.replace(/^preview\/images\//,'raw/').replace(/\.png$/i,'');
    const bytes=await readFile(safeInside(referenceRoot,preview));
    wholeInventory.push({raw,preview,name:path.posix.basename(raw),pak:raw.split('/')[2],png_sha256:sha(bytes),png_bytes:bytes.length,raw_sha256:entryByRaw.get(raw)?.sha256||null,width:cat?.width??null,height:cat?.height??null,catalogued:!!cat,imported:textures.some(x=>x.raw===raw)});
  }
  const groups=new Map();for(const entry of wholeInventory){const key=entry.name.toLowerCase();if(!groups.has(key))groups.set(key,[]);groups.get(key).push(entry);}
  const duplicateNames=[...groups].filter(([,items])=>items.length>1).map(([name,items])=>({name,variants:items.map(x=>({raw:x.raw,raw_sha256:x.raw_sha256,png_sha256:x.png_sha256})),different_original_sha256:new Set(items.map(x=>x.raw_sha256)).size>1}));
  const candidatePattern=/(water|foam|froth|splash|spash|sparkle|spaarkle|wake|surf|caustic|smoke|fog|mist|cloud|cannon|explosion|ember|spark|flame|fire|lightning|storm|rain)/i;
  const unboundCandidates=wholeInventory.filter(x=>candidatePattern.test(x.name)&&!x.imported).map(x=>({...x,binding_verified:false,association:'filename search only; no selected authored source texture reference'}));
  if(!unboundCandidates.some(x=>x.raw===unboundCaustic.raw))unboundCandidates.push({...unboundCaustic,binding_verified:false});

  const sourceAssets=orderedAssets.map(item=>({raw:item.asset.raw,sha256:item.asset.sha256,version:item.asset.version,name:item.asset.name,scopes:[...item.scopes].sort(compare),resource:item.resource,source_json:[...item.sources].sort(compare),block_count:item.asset.block_count,whole_file_consumed:item.asset.whole_file_consumed}));
  const defs={schema_version:1,source_contract:Object.fromEntries(Object.entries(contract).filter(([key])=>key!=='systems')),source_assets:sourceAssets,effects,systems};
  const coverage={schema_version:1,atmosphere:{systems:systems.length,particle_roots:effects.length,parsed_assets:sourceAssets.filter(x=>x.scopes.includes('atmosphere')).length,authored_particle_capacity:systems.reduce((n,x)=>n+x.particle_capacity,0),capacity_boundary:'particle_capacity preserves static data.fields.num_vertices; it is not a verified original dynamic maximum. Runtime spawning needs an explicit game capacity policy.',system_types:countTypes(systems,x=>x.system.type),modifier_types:countTypes(systems.flatMap(x=>x.modifiers)),controller_types:countTypes(systems.flatMap(x=>x.controllers)),studied_texture_dependencies:studied.textures.length,studied_texture_dependencies_imported:studied.textures.filter(x=>textures.some(t=>t.raw===x.raw)).length},
    sources:{parsed_assets:sourceAssets.length,water_effect_assets:sourceAssets.filter(x=>x.scopes.includes('water_effect')).length,water_surface_assets:sourceAssets.filter(x=>x.scopes.includes('water_surface')).length,shoreline_assets:sourceAssets.filter(x=>x.scopes.includes('shoreline')).length},
    textures:{whole_fpk_png:wholeInventory.length,catalogued_fpk_png:catalog.length,imported:textures.length,external:textures.filter(x=>x.kind==='external').length,embedded:textures.filter(x=>x.kind==='embedded').length,unresolved_binding_slots:unresolved.length,ambiguous_binding_slots:boundAssets.flatMap(x=>x.properties).flatMap(x=>Object.values(x.texture_bindings)).filter(x=>x.selection==='ambiguous_exact_filename_variants').length,duplicate_filenames:duplicateNames.length,unbound_filename_candidates:unboundCandidates.length,raw_sha256_verified:textures.length,decoded_original_png_equal:textures.length,with_transparent_pixels:textures.filter(x=>x.alpha_zero_pixels>0).length,with_partial_alpha:textures.filter(x=>x.alpha_partial_pixels>0).length},
    runtime:{all_276_behaviors_restored:false,original_game_gpu_verified:false,resource_definitions_verified:true,unit_conversion_imposed:false,unknowns:contract.unrecovered_runtime,boundary:'Full authored resource import only. Runtime modifier ordering/formulas, cycle evaluation, shader overrides and scheduling need a separate implementation and live Godot acceptance.'}};
  outputs.set(`${DATA}/definitions/systems.json`,jsonBytes(defs));
  outputs.set(`${DATA}/coverage.json`,jsonBytes(coverage));
  outputs.set(`${DATA}/binding-index.json`,jsonBytes({schema_version:1,assets:boundAssets,shader_slots:shaderSlots,unresolved,unbound_candidates:unboundCandidates,boundary:'Property/block references are authored evidence. Shader slot names and filename-only candidates do not prove an original-game runtime binding.'}));
  outputs.set(`${DATA}/whole-fpk-inventory.json`,jsonBytes({schema_version:1,files:wholeInventory,duplicate_filenames:duplicateNames,association:'Inventory is not a list of bound water/particle textures'}));
  const firstEffect=effects.find(x=>x.raw===systems[0].raw);
  outputs.set(`${DATA}/definitions/schema.json`,jsonBytes({schema_version:1,entry:'res://assets/data/reference_atmosphere/definitions/systems.json',system_id:'raw/fpk/PakN/asset.nif#numericBlockId',raw_record:'Every original particle-contract system key remains unchanged. Added keys: id, particle_capacity, source_asset, texture_paths.',texture_paths:'One item per original property_chains parent path; .properties retains declared_owner_id/property, adds .texture_bindings[slot].files[] with raw/resource/SHA/RGBA. All ambiguous variants remain separate.',source_asset:'Complete parsed NIF/KF JSON. Preserve raw fields, controller data refs and all full arrays.',coordinates:contract.units,unimplemented_behavior:contract.unrecovered_runtime,consumer_example:{effect:firstEffect.id,systems:firstEffect.system_ids,first_system:systems[0].id,read_emission:'emitters[*].emission_controllers[*].data.fields.float_keys.keys',read_visibility:'emitters[*].emission_controllers[*].data.fields.visibility_keys',read_color:'modifiers[type=NiPSysColorModifier].data_resolved.fields.data.keys',read_texture:'texture_paths[*].properties[*].texture_bindings.base_texture.files[*].resource'},alpha_policy:'Straight RGBA pixels preserved. Raw NiAlphaProperty flags/threshold and blend factors remain in each property path; importer never premultiplies, darkens, white-tints or guesses a billboard material.'}));
  const artifacts=[...outputs].filter(([name])=>!name.startsWith(TEX+'/')).map(([name,bytes])=>({resource:`res://${name}`,sha256:sha(bytes),bytes:bytes.length}));
  outputs.set('assets/provenance/reference-atmosphere.json',jsonBytes({schema_version:1,reference_root:slash(referenceRoot),importer:'tools/import-reference-atmosphere.mjs',importer_sha256:sha(await readFile(fileURLToPath(import.meta.url))),pixel_verifier_sha256:sha(Buffer.from(PIXEL_CHECK)),source_inputs:[...inputs].map(([name,x])=>({path:name,sha256:x.sha256,bytes:x.bytes})),source_assets:sourceAssets,textures,artifacts,verification:coverage.runtime,boundary:'Images copied only from exact package PNGs or validated embedded NiPixelData. Original reference files are not modified.'}));

  // All source/PNG/pixel checks finish before any output mutation. Verify-only never writes.
  if(verifyOnly) {
    for(const [relative,bytes] of outputs){const actual=await readFile(safeInside(outputRoot,relative));if(sha(actual)!==sha(bytes))throw new Error(`Imported output changed: ${relative}`);}
  } else {
    for(const [relative,bytes] of outputs){const destination=safeInside(outputRoot,relative);await mkdir(path.dirname(destination),{recursive:true});await writeFile(destination,bytes);}
  }
  return {mode:verifyOnly?'verify':'import',outputs:outputs.size,coverage};
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const arg=name=>process.argv.includes(name)?process.argv[process.argv.indexOf(name)+1]:undefined;
  try {
    const result=await importReference({referenceRoot:arg('--reference-root'),outputRoot:arg('--output-root'),verifyOnly:process.argv.includes('--verify-only')});
    console.log(JSON.stringify(result));
  }catch(error){console.error(error.stack||error.message);process.exitCode=1;}
}
