import {createHash} from 'node:crypto';
import {isDeepStrictEqual} from 'node:util';
import {inspectImage} from './inspect-story-image.mjs';
import {storyStructure} from './zheng-story-contract.mjs';

export const illustratedVersion='historical-reboot-illustrated-2026-10-24';
export const illustratedSourceSha256='ff49298756869eb372fac8503a9a246eff213d7db592fc06bd2361b18d4ce53a';
const generator='ChatGPT built-in image_gen';
const oldIllustrationNote='新作采用六部二十二章与自由段落，不用旧图像锚点限制故事。旧图保留归档，本版无新插图。游戏场景稿是制作文本，尚未接入游戏引擎。';
const newIllustrationNote='新作采用六部二十二章与自由段落，不用旧图像锚点限制故事。旧图保留归档，本版新增44幅ChatGPT生成插图，逐章配两幅。游戏场景稿是制作文本，尚未接入游戏引擎。';
const array=value=>Array.isArray(value)?value:[];
const present=value=>typeof value==='string'&&!!value.trim();
const sha256=bytes=>createHash('sha256').update(bytes).digest('hex');

function literaryContent(story){
 const copy=structuredClone(story);
 delete copy.version;delete copy.illustrationStatus;delete copy.illustrationRevision;
 if(copy.editorialRevision)delete copy.editorialRevision.report;
 // Permit only this complete publication-note migration; every other source
 // note, including its history/reconstruction boundary, remains in the comparison.
 if(Array.isArray(copy.sourceNotes))copy.sourceNotes=copy.sourceNotes.map(note=>note===newIllustrationNote?oldIllustrationNote:note);
 for(const act of array(copy.acts)){
  for(const key of ['illustrationStatus','cover','coverWidth','coverHeight'])delete act[key];
  for(const scene of array(act.scenes))for(const key of ['illustrationStatus','illustrations','image','imageCaption','imageWidth','imageHeight'])delete scene[key];
 }
 return copy;
}

// This validates candidate data and bytes without publishing or reading the adopted story.
// A valid PNG/hash proves a resource contract, not authorship or visual/historical quality.
export function validateIllustrations({story,manifest,sourceSha256,baselineStory,baselineSourceSha256,readImage}={}){
 const checks=[],imageRecords=[],check=(passed,name,scope='illustration')=>{checks.push({name,passed:!!passed,scope});return !!passed;};
 check(story?.version===illustratedVersion,'illustration:explicit source version');
 try{check(storyStructure(story).edition==='historical-reboot','illustration:historical structure');}catch(error){check(false,'illustration:structure '+error.message);}
 const revision=story?.illustrationRevision;
 check(revision?.edition==='chapter-pairs'&&revision.minimumPerScene===2&&revision.sourceVersion==='historical-reboot-polish-2026-10-24'&&revision.sourceSha256===illustratedSourceSha256&&revision.report==='illustrated-2026-10-24/DELIVERY.md'&&revision.generator===generator,'illustration:bounded revision provenance');
 check(story?.editorialRevision?.report==='illustrated-2026-10-24/DELIVERY.md','illustration:separate publication report directory');
 // The approved baseline is a known pretty-printed JSON artifact. Bind its parsed
 // object as well as the caller's byte digest so a substituted object cannot pass.
 check(baselineSourceSha256===illustratedSourceSha256&&baselineStory?.version==='historical-reboot-polish-2026-10-24'&&sha256(Buffer.from(JSON.stringify(baselineStory,null,2)+'\n'))===illustratedSourceSha256,'illustration:frozen literary baseline','text');
 check(Array.isArray(story?.sourceNotes)&&story.sourceNotes.at(-1)===newIllustrationNote,'illustration:current publication source note required','text');
 check(!!story&&!!baselineStory&&isDeepStrictEqual(literaryContent(story),literaryContent(baselineStory)),'illustration:all literary text identities and aliases unchanged','text');
 check(story?.illustrationStatus==='ready','illustration:source ready');
 check(manifest?.schemaVersion===2&&manifest.storyVersion===story?.version,'illustration:manifest schema and version');
 check(/^[a-f0-9]{64}$/.test(sourceSha256||'')&&manifest?.sourceSha256===sourceSha256,'illustration:manifest current source hash');
 const records=array(manifest?.illustrations),byId=new Map(records.map(record=>[record?.id,record]));
 check(records.length===44&&byId.size===44,'illustration:44 unique manifest entries');
 const ids=new Set(),paths=new Set(),hashes=new Set();let references=0,scenes=0;
 for(const act of array(story?.acts)){
  check(act.illustrationStatus==='ready'&&!act.cover,`${act.id}:ready without duplicated cover`);
  for(const scene of array(act.scenes)){
   scenes++;
   check(scene.illustrationStatus==='ready'&&!scene.image,`${scene.id}:ready with paragraph frames only`);
   const frames=array(scene.illustrations);check(frames.length>=2,`${scene.id}:at least two new illustrations`);
   check(array(scene.paragraphs).length>0&&scene.paragraphs.every(p=>present(p)),`${scene.id}:nonempty stable paragraph positions`);
   let previous=0;
   for(const frame of frames){
    references++;
    check(typeof frame.id==='string'&&/^[a-zA-Z0-9_-]+$/.test(frame.id)&&!ids.has(frame.id),`${scene.id}:unique frame id ${frame.id}`);ids.add(frame.id);
    check(Number.isInteger(frame.afterParagraph)&&frame.afterParagraph>previous&&frame.afterParagraph<=array(scene.paragraphs).length,`${frame.id}:ascending valid paragraph position`);previous=frame.afterParagraph;
    check(present(frame.caption)&&present(frame.alt)&&frame.illustrationStatus==='ready',`${frame.id}:ready descriptive caption and alt`);
    check(Number.isInteger(frame.width)&&frame.width>0&&Number.isInteger(frame.height)&&frame.height>0,`${frame.id}:positive actual dimensions`);
    const safePath=typeof frame.image==='string'&&/^images\/illustrated-2026-10-24\/[a-zA-Z0-9_-]+\.png$/.test(frame.image);
    check(safePath&&!paths.has(frame.image),`${frame.id}:unique current-edition local PNG path`);paths.add(frame.image);
    const record=byId.get(frame.id);
    check(!!record&&record.sceneId===scene.id&&['id','image','afterParagraph','caption','alt','width','height'].every(key=>record[key]===frame[key]),`${frame.id}:manifest matches scene and frame`);
    check(record?.generator===generator,`${frame.id}:manifest generator recorded`);
    if(!safePath)continue;
    try{
     const bytes=readImage(frame.image),info=inspectImage(bytes),digest=sha256(bytes);
     check(info.format==='PNG',`${frame.id}:complete PNG raster`);
     check(info.width===frame.width&&info.height===frame.height,`${frame.id}:decoded dimensions match source`);
     check(record?.sha256===digest,`${frame.id}:manifest image SHA-256`);
     check(!hashes.has(digest),`${frame.id}:independent image bytes`);hashes.add(digest);
     imageRecords.push({id:frame.id,sceneId:scene.id,image:frame.image,afterParagraph:frame.afterParagraph,caption:frame.caption,alt:frame.alt,width:info.width,height:info.height,sha256:digest,bytes:bytes.length,format:info.format});
    }catch(error){check(false,`${frame.id}:PNG read and decode ${error.message}`);}
   }
  }
 }
 check(scenes===22,'illustration:22 illustrated chapters');
 check(references===44&&ids.size===44&&paths.size===44,'illustration:44 unique source references');
 check(records.every(record=>ids.has(record?.id)),'illustration:no unreferenced manifest images');
 check(imageRecords.length===44&&hashes.size===44,'illustration:44 complete independent PNG assets');
 const failures=checks.filter(entry=>!entry.passed);
 return {valid:failures.length===0,checks,failures,imageRecords,summary:{expectedIllustrations:44,presentImages:imageRecords.length,uniqueImageHashes:hashes.size}};
}
