import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..');
const story=JSON.parse(fs.readFileSync(process.argv[3]?path.resolve(process.argv[3]):path.join(root,'docs/narrative/zheng-zhilong-story.json'),'utf8'));
const arg=process.argv[2]||'outline';
if(arg==='outline') {
 console.log(JSON.stringify(Object.fromEntries(Object.entries(story).filter(([k])=>!['acts','legacySceneAliases'].includes(k))),null,2));
 for(const act of story.acts){
  console.log(JSON.stringify(Object.fromEntries(Object.entries(act).filter(([k])=>k!=='scenes'))));
  for(const scene of act.scenes) console.log(JSON.stringify({id:scene.id,title:scene.title,year:scene.year,location:scene.location,summary:scene.summary,dramaticBeat:scene.dramaticBeat,readerTeaser:scene.readerTeaser,illustrations:scene.illustrations?.map(x=>({id:x.id,afterParagraph:x.afterParagraph,caption:x.caption}))}));
 }
} else {
 for(const act of story.acts.filter(x=>arg.split(',').includes(x.id.replace('act-','')))){
  console.log('\n'+act.title);
  for(const scene of act.scenes){
   console.log('\n'+scene.id+' '+scene.title+' '+scene.year+' '+scene.location);
   scene.paragraphs.forEach((p,i)=>console.log('P'+(i+1)+' '+p));
   console.log('DIALOGUE '+JSON.stringify(scene.dialogue));
  }
 }
}
