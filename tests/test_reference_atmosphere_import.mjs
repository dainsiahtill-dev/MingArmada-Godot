#!/usr/bin/env node
// Offline resource-contract checks; no GPU or production particle evaluator is involved.
import assert from 'node:assert/strict';
import { readFile, access } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const reference = process.argv.includes('--reference-root')
  ? path.resolve(process.argv[process.argv.indexOf('--reference-root') + 1])
  : 'C:/Games/Pirates-REA-Reference-20261011';
let checks = 0;
const check = (condition, message) => { assert.ok(condition, message); checks++; };
const same = (actual, expected, message) => { assert.deepEqual(actual, expected, message); checks++; };
const digest = value => createHash('sha256').update(value).digest('hex');
const load = async name => JSON.parse(await readFile(path.join(root, name), 'utf8'));

try {
  try { await access(path.join(root, 'tools/import-reference-atmosphere.mjs')); }
  catch { throw new Error('Missing full reference-resource importer; compact ten-system teaching data cannot satisfy the contract.'); }
  const mod = await import('../tools/import-reference-atmosphere.mjs');
  const fixture = [
    {raw:'raw/fpk/Pak0/smoke.dds',name:'smoke.dds',preview:'preview/images/fpk/Pak0/smoke.dds.png',sha256:'a'},
    {raw:'raw/fpk/Pak7/smoke.dds',name:'smoke.dds',preview:'preview/images/fpk/Pak7/smoke.dds.png',sha256:'b'},
    {raw:'raw/fpk/Pak6/wavesdudv.tga',name:'wavesdudv.tga',preview:'preview/images/fpk/Pak6/wavesdudv.tga.png',sha256:'c'}
  ];
  same(mod.resolveNamedTexture('SMOKE.DDS', fixture).map(x=>x.raw), fixture.slice(0,2).map(x=>x.raw), 'Pak variants remain distinct');
  same(mod.resolveNamedTexture('fpk/Pak7/smoke.dds', fixture).map(x=>x.raw), [fixture[1].raw], 'Explicit package path wins');
  same(mod.resolveNamedTexture('WavesDUDV.tga', fixture).map(x=>x.raw), [fixture[2].raw], 'Case-insensitive original extension');
  same(mod.resolveNamedTexture('smoke.tga', fixture), [], 'Do not silently swap extension');
  same(mod.resolveNamedTexture('fpk/Pak9/smoke.dds', fixture), [], 'No substitution for an explicit missing archive');
  assert.throws(()=>mod.safeInside(root,'../outside.png'), /outside/); checks++;
  assert.throws(()=>mod.safeInside(root,'C:/outside.png'), /absolute|outside/); checks++;
  await assert.rejects(mod.importReference({referenceRoot:reference,outputRoot:reference}), /read-only/); checks++;
  const property = {id:18,type:'NiTexturingProperty',fields:{base_texture:{source:{ref:19,type:'NiSourceTexture'},clamp_mode:0},detail_texture:{source:{ref:20,type:'NiSourceTexture'}},controller:{ref:2,type:'NiTextureTransformController'}}};
  same(mod.textureSlots(property).map(x=>[x.slot,x.ref]), [['base_texture',19],['detail_texture',20]], 'Only actual texture references are slots');

  const systems = await load('assets/data/reference_atmosphere/definitions/systems.json');
  const coverage = await load('assets/data/reference_atmosphere/coverage.json');
  const bindings = await load('assets/data/reference_atmosphere/binding-index.json');
  const provenance = await load('assets/provenance/reference-atmosphere.json');
  const contract = JSON.parse(await readFile(path.join(reference,'naval-study/atmosphere-fx/source-study/particle-contract.json'),'utf8'));
  same(systems.schema_version,1,'Stable public schema');
  same(systems.systems.length,276,'Full system count, not compact ten');
  same(coverage.atmosphere.systems,276,'Coverage agrees');
  same(systems.effects.length,16,'All particle roots represented');
  same(systems.source_contract, Object.fromEntries(Object.entries(contract).filter(([key])=>key!=='systems')), 'Contract semantic boundaries preserved');
  const sourceById = new Map(contract.systems.map(x=>[`${x.raw}#${x.system_id}`,x]));
  for(const item of systems.systems) {
    const original = sourceById.get(item.id);
    check(original, `Original source identity ${item.id}`);
    for(const [key,value] of Object.entries(original)) same(item[key],value,`${item.id}: raw ${key} preserved`);
    same(item.particle_capacity,original.data.fields.num_vertices,'Capacity is authored data');
    same(item.texture_paths.length,original.property_chains.length,'Every inherited property path retained');
    for(let i=0;i<item.texture_paths.length;i++) {
      same(item.texture_paths[i].properties.length,original.property_chains[i].length,'Every property type retained');
      for(let j=0;j<item.texture_paths[i].properties.length;j++) {
        const normalized=item.texture_paths[i].properties[j];
        same(normalized.property,original.property_chains[i][j].property,'Material and alpha flags remain exact');
        if(normalized.property.type==='NiTexturingProperty') {
          check(Object.keys(normalized.texture_bindings).length>0,'Particle texture actually resolved through property reference');
          for(const slot of Object.values(normalized.texture_bindings)) check(slot.files.length>0,'Particle texture has real source files');
        }
      }
    }
  }
  check(coverage.runtime.all_276_behaviors_restored===false,'Resource coverage does not claim runtime reconstruction');
  check(coverage.runtime.original_game_gpu_verified===false,'No original-game GPU claim');
  same(provenance.textures.length,coverage.textures.imported,'Texture count reconciles');
  const resourceToFile = uri => path.join(root,uri.replace(/^res:\/\//,''));
  for(const tex of provenance.textures) {
    same(digest(await readFile(resourceToFile(tex.resource))),tex.png_sha256,`Copied PNG SHA ${tex.id}`);
    check(tex.width>0&&tex.height>0,'Decoded dimensions retained');
    same(tex.alpha_zero_pixels+tex.alpha_opaque_pixels+tex.alpha_partial_pixels,tex.width*tex.height,'Every pixel accounted');
    check(/^[0-9a-f]{64}$/.test(tex.decoded_rgba_sha256),'RGBA pixel hash retained');
    check(tex.raw_sha256_verified&&tex.decoded_original_equal,'Original bytes and pixels verified');
    if(tex.kind==='external') check(tex.preview.startsWith('preview/images/fpk/'),'External texture comes from entire fpk inventory');
  }
  check(provenance.textures.some(x=>x.raw==='raw/fpk/Pak5/cloud.nif'&&x.kind==='embedded'),'Real cloud NiPixelData, not substitute cloud_bw');
  const water = bindings.assets.find(x=>x.raw==='raw/fpk/Pak3/reflectivewater.nif');
  const names = water.properties.flatMap(x=>Object.values(x.texture_bindings)).map(x=>x.fields.file_name);
  check(names.includes('water_shader.dds')&&names.includes('WavesDUDV.tga'),'Water base/detail actual references');
  const shaderDefault = bindings.shader_slots.find(x=>x.default_filename==='empty.dds');
  check(shaderDefault&&shaderDefault.binding_kind==='authored_shader_default'&&!shaderDefault.runtime_binding_verified,'Reflection default cannot stand in for runtime render target');
  check(bindings.unbound_candidates.some(x=>x.name==='dg_caustic.dds'&&x.binding_verified===false),'Unbound caustics candidacy remains explicit');
  for(const artifact of provenance.artifacts) same(digest(await readFile(resourceToFile(artifact.resource))),artifact.sha256,'Definition hash receipt');
  for(const asset of systems.source_assets) {
    const output=JSON.parse(await readFile(resourceToFile(asset.resource),'utf8'));
    const source=asset.source_json[0];
    const input=JSON.parse(await readFile(path.join(reference,source),'utf8'));
    const original=Array.isArray(input)?input.find(x=>x.raw===asset.raw):input.assets?input.assets.find(x=>x.raw===asset.raw):input;
    same(output,original,`All raw blocks, mesh arrays and negative zero retained: ${asset.raw}`);
  }
  console.log(JSON.stringify({test:'reference_atmosphere_import',checks,failures:0,systems:systems.systems.length,textures:provenance.textures.length,unresolved:bindings.unresolved.length}));
} catch(error) {
  console.error(JSON.stringify({test:'reference_atmosphere_import',checks,failures:1,error:error.message}));
  process.exitCode=1;
}
