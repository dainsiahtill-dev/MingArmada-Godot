import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {deflateSync} from 'node:zlib';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {renderRebootExports} from './render-zheng-reboot-exports.mjs';
import * as validation from './verify-zheng-reboot.mjs';

const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const baselineBytes=readFileSync(new URL('../docs/narrative/full-polish-2026-10-24/candidate.json',import.meta.url));
const baselineStory=JSON.parse(baselineBytes);
const oldIllustrationNote='新作采用六部二十二章与自由段落，不用旧图像锚点限制故事。旧图保留归档，本版无新插图。游戏场景稿是制作文本，尚未接入游戏引擎。';
const newIllustrationNote='新作采用六部二十二章与自由段落，不用旧图像锚点限制故事。旧图保留归档，本版新增44幅ChatGPT生成插图，逐章配两幅。游戏场景稿是制作文本，尚未接入游戏引擎。';
function png(index){
 const chunk=(name,data)=>{const body=Buffer.concat([Buffer.from(name),data]);let crc=0xffffffff;for(const byte of body){crc^=byte;for(let b=0;b<8;b++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}const out=Buffer.alloc(data.length+12);out.writeUInt32BE(data.length);body.copy(out,4);out.writeUInt32BE((crc^0xffffffff)>>>0,out.length-4);return out;};
 const header=Buffer.alloc(13);header.writeUInt32BE(1,0);header.writeUInt32BE(1,4);header[8]=8;header[9]=6;
 return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',header),chunk('IDAT',deflateSync(Buffer.from([0,index,90,180,255]))),chunk('IEND',Buffer.alloc(0))]);
}
function fixture(){
 const story=structuredClone(baselineStory);Object.assign(story,{version:'historical-reboot-illustrated-2026-10-24',illustrationStatus:'ready',illustrationRevision:{edition:'chapter-pairs',minimumPerScene:2,sourceVersion:'historical-reboot-polish-2026-10-24',sourceSha256:'ff49298756869eb372fac8503a9a246eff213d7db592fc06bd2361b18d4ce53a',report:'illustrated-2026-10-24/DELIVERY.md',generator:'ChatGPT built-in image_gen'}});story.editorialRevision.report='illustrated-2026-10-24/DELIVERY.md';
 story.sourceNotes=story.sourceNotes.map(note=>note===oldIllustrationNote?newIllustrationNote:note);
 const images=new Map(),illustrations=[];let index=0;
 for(const act of story.acts){
  act.illustrationStatus='ready';
  for(const scene of act.scenes){
   scene.illustrationStatus='ready';scene.illustrations=[];
   for(let n=1;n<=2;n++){
    const id=`${scene.id}_${n}`,image=`images/illustrated-2026-10-24/${id}.png`,bytes=png(++index);
    const frame={id,image,afterParagraph:n,caption:`船员行动${index}`,alt:`船员在甲板拉绳${index}`,width:1,height:1,illustrationStatus:'ready'};scene.illustrations.push(frame);images.set(image,bytes);
    illustrations.push({...frame,sceneId:scene.id,sha256:hash(bytes),generator:'ChatGPT built-in image_gen'});
   }
  }
 }
 const sourceSha256=hash(Buffer.from(JSON.stringify(story)));
 return {story,baselineStory,baselineSourceSha256:hash(baselineBytes),manifest:{schemaVersion:2,storyVersion:story.version,sourceSha256,illustrations},sourceSha256,readImage:image=>{if(!images.has(image))throw new Error('Missing fixture image');return images.get(image);},images};
}
function run(input){assert.equal(typeof validation.validateIllustrations,'function','illustrated contract must be available');return validation.validateIllustrations(input);}
function reject(input,name){const result=run(input);assert.equal(result.valid,false,name);assert.ok(result.failures.length,name);return result;}

test('44 independent PNGs satisfy the complete chapter-pairs contract',()=>{const result=run(fixture());assert.equal(result.valid,true,JSON.stringify(result.failures));assert.equal(result.summary.presentImages,44);assert.equal(result.summary.uniqueImageHashes,44);});
test('only the exact illustrated source note migration is allowed',()=>{const f=fixture();assert.equal(f.story.sourceNotes.at(-1),newIllustrationNote);assert.deepEqual(f.story.sourceNotes.slice(0,-1),baselineStory.sourceNotes.slice(0,-1));assert.equal(run(f).valid,true);});
test('the illustrated edition must not retain the no-new-art source note',()=>{const f=fixture();f.story.sourceNotes[f.story.sourceNotes.length-1]=oldIllustrationNote;reject(f,'obsolete no-art statement');});
test('the illustration note migration does not permit changing source reliability notes',()=>{const f=fixture();f.story.sourceNotes[1]='本轮已核全部原档影像。';const result=reject(f,'historical sourcing claim changed');assert.ok(result.failures.some(item=>item.name==='illustration:all literary text identities and aliases unchanged'));});
test('other wording within the migrated note must remain exact',()=>{const f=fixture();f.story.sourceNotes[f.story.sourceNotes.length-1]=newIllustrationNote.replace('尚未接入游戏引擎','已经接入游戏引擎');reject(f,'engine status changed');});
test('the illustration note migration does not permit changing chapter history',()=>{const f=fixture();f.story.acts[0].scenes[0].history.note+='已证明所有私人对白。';reject(f,'chapter history changed');});
test('a missing chapter image cannot be hidden by an extra image in another chapter',()=>{const f=fixture();const moved=f.story.acts[0].scenes[0].illustrations.pop(),destination=f.story.acts[0].scenes[1];moved.afterParagraph=3;destination.illustrations.push(moved);Object.assign(f.manifest.illustrations.find(item=>item.id===moved.id),{sceneId:destination.id,afterParagraph:3});const result=reject(f,'each chapter needs two images');assert.ok(result.failures.some(item=>item.name==='zzl_a1_s1:at least two new illustrations'));});
test('two paths containing identical PNG bytes cannot count as two new pictures',()=>{const f=fixture();const [a,b]=f.manifest.illustrations;f.images.set(b.image,f.images.get(a.image));b.sha256=a.sha256;const result=reject(f,'duplicate content');assert.ok(result.failures.some(item=>item.name.endsWith(':independent image bytes')));});
test('duplicate source image paths are rejected even with distinct frame IDs',()=>{const f=fixture();f.story.acts[0].scenes[0].illustrations[1].image=f.story.acts[0].scenes[0].illustrations[0].image;reject(f,'duplicate paths');});
for(const position of [0,999,1.5,'2'])test(`paragraph position ${JSON.stringify(position)} is rejected`,()=>{const f=fixture();f.story.acts[0].scenes[0].illustrations[0].afterParagraph=position;reject(f,'invalid position');});
test('reversed scene placement is rejected',()=>{const f=fixture();f.story.acts[0].scenes[0].illustrations.reverse();reject(f,'nonascending positions');});
test('truncated PNG is rejected even if its manifest hash matches',()=>{const f=fixture();const item=f.manifest.illustrations[0],bad=f.images.get(item.image).subarray(0,40);f.images.set(item.image,bad);item.sha256=hash(bad);reject(f,'corrupt PNG');});
test('manifest must identify the exact current source bytes',()=>{const f=fixture();f.manifest.sourceSha256='0'.repeat(64);reject(f,'wrong source hash');});
for(const key of ['id','sceneId','image','afterParagraph','caption','alt','width','height'])test(`manifest mismatch in ${key} is rejected`,()=>{const f=fixture();f.manifest.illustrations[0][key]=key==='width'||key==='height'||key==='afterParagraph'?99:'wrong';reject(f,`wrong ${key}`);});
test('a manifest entry cannot conceal a changed asset',()=>{const f=fixture();f.manifest.illustrations[0].sha256='0'.repeat(64);reject(f,'wrong image hash');});
for(const image of ['images/old/scene.png','images/illustrated-2026-10-24/../scene.png','https://example.com/scene.png'])test(`unsafe or old path ${image} is rejected before reading`,()=>{const f=fixture();f.story.acts[0].scenes[0].illustrations[0].image=image;reject(f,'invalid path');});
test('source dimensions must agree with the actual PNG',()=>{const f=fixture();f.story.acts[0].scenes[0].illustrations[0].width=2;f.manifest.illustrations[0].width=2;reject(f,'wrong dimensions');});
test('unknown illustrated source versions are rejected',()=>{const f=fixture();f.story.version='historical-reboot-illustrated-unknown';reject(f,'unknown version');});
test('a ready primary image cannot duplicate a paragraph illustration',()=>{const f=fixture();f.story.acts[0].scenes[0].image=f.manifest.illustrations[0].image;reject(f,'primary image not allowed');});
test('changing one prose character is rejected',()=>{const f=fixture();f.story.acts[0].scenes[0].paragraphs[0]+='改';reject(f,'prose changed');});
test('a valid but different legacy alias target is rejected',()=>{const f=fixture();const id=Object.keys(f.story.legacySceneAliases)[0];f.story.legacySceneAliases[id]='zzl_a6_s3';reject(f,'bookmark period changed');});
test('a substitute text baseline cannot approve changed prose',()=>{const f=fixture();f.baselineSourceSha256='0'.repeat(64);reject(f,'wrong baseline');});
test('an altered baseline object cannot borrow the approved baseline hash',()=>{const f=fixture();f.baselineStory=structuredClone(f.baselineStory);f.story.acts[0].scenes[0].paragraphs[0]+='改';f.baselineStory.acts[0].scenes[0].paragraphs[0]+='改';reject(f,'baseline content changed');});
test('illustrated editorial artifacts cannot target the prior report directory',()=>{const f=fixture();f.story.editorialRevision.report='full-polish-2026-10-24/DELIVERY.md';reject(f,'wrong publication directory');});
test('illustrated downloads insert images after the intended paragraphs with reader-local paths',()=>{
 const story=structuredClone(baselineStory);story.version='historical-reboot-illustrated-2026-10-24';story.illustrationStatus='ready';
 const scene=story.acts[0].scenes[0];scene.illustrationStatus='ready';scene.illustrations=[{id:'test-1',image:'images/illustrated-2026-10-24/test-1.png',afterParagraph:1,caption:'甲板行动',alt:'船员拉绳',illustrationStatus:'ready'}];
 const exports=renderRebootExports(story);
 for(const file of ['novel.md','screenplay.md']){
  const text=exports[file],paragraph=text.indexOf(scene.paragraphs[0]),image=text.indexOf('](images/illustrated-2026-10-24/test-1.png)'),next=text.indexOf(scene.paragraphs[1]);
  assert.ok(paragraph>=0&&image>paragraph&&next>image,`${file}: image belongs after first paragraph`);
  assert.equal((text.match(/test-1\.png/g)||[]).length,1);
  assert.ok(!text.includes('](zheng-zhilong/images/'));
 }
 assert.ok(!exports['screenplay.md'].includes('本版为文字新作'));
});
test('existing text-only downloads remain byte-identical',()=>{
 const rendered=renderRebootExports(baselineStory);
 const expected={'novel.md':'b41f9ca16214c9b5c1597151214c2ebc22e9cb8cd36a606200a83b9cef042280','screenplay.md':'6a49ef143b38985cbf472234921015dea6e26828c3158a568cec3e39d6ecc78a','game-scenes.md':'d8e5617893c76cff2f720bdcf8f52f6946ed3f0a79fe637433c9e5bdbc076f07'};
 for(const [file,digest] of Object.entries(expected))assert.equal(hash(Buffer.from(rendered[file])),digest,file);
});
test('the historical text-only edition still rejects inserted art',()=>{
 const story=structuredClone(baselineStory);story.acts[0].scenes[0].illustrations=[{id:'old-art',image:'images/old.png',afterParagraph:1,caption:'不得采用'}];
 const result=validation.verifyReboot({story,writeReport:false});
 assert.equal(result.valid,false);assert.ok(result.failures.some(item=>item.name==='zzl_a1_s1:no reused fictional scene picture'));
});
test('reader normalization retains a descriptive alt and the illustrated edition identity',()=>{
 const source=readFileSync(new URL('../docs/narrative/zheng-zhilong/app.js',import.meta.url),'utf8'),context={history:{},window:{}};
 const prefix=source.slice(0,source.indexOf('  function element('));vm.runInNewContext(prefix+'window.normalize=normalize;})();',context);
 const normalized=context.window.normalize(fixture().story);
 assert.equal(normalized.version,'historical-reboot-illustrated-2026-10-24');
 assert.equal(normalized.acts[0].scenes[0].illustrations[0].alt,'船员在甲板拉绳1');
});
