import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const dir=path.dirname(fileURLToPath(import.meta.url)),requests=(process.argv[2]||'1,2,3,4,5,6').split(','),want=requests.map(n=>Number(n.split('.')[0]));
const files=[...new Set(want.map(n=>n<=2?'parts-1-2.json':n<=4?'parts-3-4.json':'parts-5-6.json'))];
const acts=process.argv[3]==='final'?JSON.parse(fs.readFileSync(path.resolve(dir,'../zheng-zhilong-story.json'),'utf8')).acts:files.flatMap(f=>JSON.parse(fs.readFileSync(path.join(dir,f),'utf8')).acts);
for(const a of acts.filter(a=>want.includes(Number(a.id.replace('act-',''))))){
 console.log('\n'+a.id+' '+a.title);
 for(const [i,s] of a.scenes.entries()){const n=Number(a.id.replace('act-',''));if(!requests.includes(String(n))&&!requests.includes(`${n}.${i+1}`))continue;console.log('\n'+s.id+' '+s.title+' '+s.year+' '+s.location);s.paragraphs.forEach((p,i)=>console.log('P'+(i+1)+' '+p));console.log('史注 '+s.history.note);}
}
