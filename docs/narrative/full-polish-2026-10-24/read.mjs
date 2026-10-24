import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const dir=path.dirname(fileURLToPath(import.meta.url)),requests=(process.argv[2]||'1,2,3,4,5,6').split(',');
const file=process.argv[3]||'candidate.json',acts=JSON.parse(fs.readFileSync(path.join(dir,file),'utf8')).acts;
for(const a of acts){const n=Number(a.id.replace('act-',''));if(!requests.some(r=>Number(r.split('.')[0])===n))continue;console.log('\n'+a.id+' '+a.title);for(const [i,s] of a.scenes.entries()){if(!requests.includes(String(n))&&!requests.includes(`${n}.${i+1}`))continue;console.log('\n'+s.id+' '+s.title+' '+s.year+' '+s.location);s.paragraphs.forEach((p,i)=>console.log('P'+(i+1)+' '+p));console.log('史注 '+s.history.note);}}
