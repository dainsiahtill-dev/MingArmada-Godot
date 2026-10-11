import {readFile,readdir,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const folder=new URL('./evidence/',import.meta.url);
const files=(await readdir(folder)).filter(f=>f.endsWith('.jpg')).sort();
if(files.length!==75)throw new Error(`Expected 75 final inspection images, got ${files.length}`);
const images=[];
for(const file of files){const data=await readFile(new URL(file,folder));images.push({file,bytes:data.length,sha256:createHash('sha256').update(data).digest('hex')});}
const manifest=JSON.parse(await readFile(new URL('../../apps/game-client/public/models/ships/ships-manifest.json',import.meta.url),'utf8'));
await writeFile(new URL('evidence-index.json',folder),JSON.stringify({capturedAt:new Date().toISOString(),browser:'Codex In-app Browser',viewport:{width:1280,height:720},scope:'6 kinds x 8 azimuths (0..315 step45), plus each kind LOD1/LOD2/underwater/animated cloth and VOC/patrol/heavy cannon recoil',assets:manifest.assets.map(({file,sha256})=>({file,sha256})),images},null,2)+'\n');
console.log(`Recorded ${images.length} screenshots against ${manifest.assets.length} current GLB hashes.`);
