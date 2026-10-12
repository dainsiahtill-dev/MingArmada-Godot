import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {readFile} from 'node:fs/promises';
import {fileURLToPath,pathToFileURL} from 'node:url';
import path from 'node:path';
import {createHash} from 'node:crypto';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const importer=path.join(root,'tools/import-fidelity-material-variants.mjs');
assert.ok(existsSync(importer),'original per-profile material importer exists');
const {buildVariantRecords}=await import(pathToFileURL(importer));
const records=await buildVariantRecords('C:/Games/Pirates-REA-Reference-20261011');
const hash=b=>createHash('sha256').update(b).digest('hex');
let assertions=1;
for(const item of records){
 const source=item.source;
 const expected=item.id==='coastal2'?[329,193,'Coastal2_H.bmp','4.0','0.412699']:[160,77,'Virgin_Islands_H.bmp','2.0','0.0'];
 assert.deepEqual([source.width,source.height,source.terrain.heightmap,source.terrain.texturescale,source.terrain.textureoffx],expected);assertions++;
 assert.equal(source.provenance.bhi.path,`raw/fpk/Pak4/${item.id}_b.tga.bhi`);assertions++;
 assert.equal(source.blend_byte_order,'RGBA');assertions++;
 assert.equal(source.packing_validation.RGBA.valid_group_pixels,source.width*source.height);assertions++;
 const existing=JSON.parse(await readFile(path.join(root,'assets/data/reference_islands',item.id,'height.json'),'utf8'));
 assert.deepEqual(source.height_indices,existing.values,'source heights remain identical to retained authority');assertions++;
 assert.equal(item.weights.length,source.width*source.height*10*4);assertions++;
 assert.equal(item.normals.length,source.width*source.height*3*4);assertions++;
 assert.equal(source.textures.length,10);assertions++;
 const output=await readFile(path.join(root,'assets/data/fidelity_island',item.file));
 assert.equal(hash(output),hash(item.bytes),'portable decoded source matches all original source bytes and parameters');assertions++;
}
assert.equal(records.length,2);assertions++;
console.log(`FIDELITY_MATERIAL_IMPORT assertions=${assertions} failures=0`);
