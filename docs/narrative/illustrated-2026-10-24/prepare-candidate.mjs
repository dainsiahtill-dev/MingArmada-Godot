import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
const dir=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(dir,'../../..'),reader=path.resolve(dir,'../zheng-zhilong');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex'),read=f=>fs.readFileSync(f),json=f=>JSON.parse(read(f));
const baselineBytes=read(path.join(dir,'baseline.json')),story=JSON.parse(baselineBytes);
if(hash(baselineBytes)!=='ff49298756869eb372fac8503a9a246eff213d7db592fc06bd2361b18d4ce53a')throw new Error('Unexpected literary baseline');
const jobs=['boards-1-3.json','boards-4-6.json'].flatMap(f=>json(path.join(dir,f)).assets);
if(jobs.length!==44||new Set(jobs.map(j=>j.id)).size!==44)throw new Error('44 distinct jobs required');
const records=[],hashes=new Set();
for(const a of story.acts){a.illustrationStatus='ready';for(const s of a.scenes){
 const selected=jobs.filter(j=>j.sceneId===s.id).sort((a,b)=>a.slot-b.slot);
 if(selected.length!==2||selected[0].slot!==1||selected[1].slot!==2||selected[0].afterParagraph>=selected[1].afterParagraph)throw new Error('Two distinct ordered moments required '+s.id);
 s.image='';s.imageCaption='';s.illustrationStatus='ready';
 s.illustrations=selected.map(j=>{
  if(!Number.isInteger(j.afterParagraph)||j.afterParagraph<1||j.afterParagraph>s.paragraphs.length||!j.caption?.trim()||!j.alt?.trim()||!j.prompt?.trim())throw new Error('Incomplete storyboard '+j.id);
  const receipt=json(path.join(dir,'receipts',j.id+'.json')),image='images/illustrated-2026-10-24/'+j.id+'.png',bytes=read(path.join(reader,image)),sha256=hash(bytes);
  if(receipt.sha256!==sha256||receipt.id!==j.id||receipt.provider!=='ChatGPT built-in image_gen')throw new Error('Generation receipt mismatch '+j.id);
  if(hashes.has(sha256))throw new Error('Reused raster '+j.id);hashes.add(sha256);
  const frame={id:j.id,image,afterParagraph:j.afterParagraph,caption:j.caption,alt:j.alt,width:receipt.width,height:receipt.height,illustrationStatus:'ready'};
  records.push({...frame,sceneId:s.id,sha256,generator:receipt.provider});return frame;
 });
}}
story.version='historical-reboot-illustrated-2026-10-24';story.illustrationStatus='ready';
const oldArtNote='新作采用六部二十二章与自由段落，不用旧图像锚点限制故事。旧图保留归档，本版无新插图。游戏场景稿是制作文本，尚未接入游戏引擎。';
story.sourceNotes=story.sourceNotes.map(note=>note===oldArtNote?note.replace('本版无新插图。','本版新增44幅ChatGPT生成插图，逐章配两幅。'):note);
story.editorialRevision={...story.editorialRevision,report:'illustrated-2026-10-24/DELIVERY.md'};
story.illustrationRevision={edition:'chapter-pairs',minimumPerScene:2,sourceVersion:'historical-reboot-polish-2026-10-24',sourceSha256:hash(baselineBytes),report:'illustrated-2026-10-24/DELIVERY.md',generator:'ChatGPT built-in image_gen',note:'全部插图为依本稿生成的文学重建画面，不是历史现场记录或人物真容。'};
const output=JSON.stringify(story,null,2)+'\n',sourceSha256=hash(output),manifest={schemaVersion:2,storyVersion:story.version,sourceSha256,illustrations:records};
fs.writeFileSync(path.join(dir,'candidate.json'),output);fs.writeFileSync(path.join(dir,'candidate-manifest.json'),JSON.stringify(manifest,null,2)+'\n');
fs.writeFileSync(path.join(dir,'art-coverage.json'),JSON.stringify({sourceSha256,baselineSha256:hash(baselineBytes),chapters:22,images:44,uniqueHashes:hashes.size,jobs:jobs.map(j=>({id:j.id,sceneId:j.sceneId,afterParagraph:j.afterParagraph,title:j.title,historyBoundary:j.historyBoundary}))},null,2)+'\n');
console.log(JSON.stringify({sourceSha256,chapters:22,images:records.length,uniqueHashes:hashes.size}));
