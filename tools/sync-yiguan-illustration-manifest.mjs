// Re-index packaged v4 pictures for the new screenplay without claiming that
// they were newly generated or newly approved for the changed scene action.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {projectRoot,storyPath,readerDirectory} from './build-zheng-story.mjs';
import {storyStructure} from './zheng-story-contract.mjs';

const manifestPath=path.join(readerDirectory,'illustration-manifest.json');
const baselinePath=path.join(projectRoot,'docs/narrative/zheng-illustration-manifest.v4-2026-10-22.json');
const story=JSON.parse(fs.readFileSync(storyPath,'utf8'));
if(storyStructure(story).edition!=='five-act-rewrite')throw new Error('This command only re-indexes the five-act rewrite.');
if(!fs.existsSync(baselinePath)){
 const current=JSON.parse(fs.readFileSync(manifestPath,'utf8'));
 if(!current.illustrations?.some(item=>item.id==='zheng_a1_s1'))throw new Error('Original v4 manifest required to establish the preserved source record.');
 fs.writeFileSync(baselinePath,JSON.stringify(current,null,2)+'\n');
}
const baseline=JSON.parse(fs.readFileSync(baselinePath,'utf8'));
const byPath=new Map(baseline.illustrations.map(item=>[item.path,item]));
const current=JSON.parse(fs.readFileSync(manifestPath,'utf8'));
const newByPath=new Map((current.illustrations||[]).filter(item=>item.reused===false&&item.adopted===true&&item.narrativeStatus==='reviewed-v7-scene').map(item=>[item.path,item]));
const references=[];
for(const act of story.acts){
 references.push({id:act.id,path:act.cover,caption:act.title,status:act.illustrationStatus??story.illustrationStatus});
 for(const scene of act.scenes){
  references.push({id:scene.id,path:scene.image,caption:scene.imageCaption||scene.title,status:scene.illustrationStatus??act.illustrationStatus??story.illustrationStatus});
  for(const frame of scene.illustrations||[])references.push({id:frame.id,path:frame.image,caption:frame.caption,status:frame.illustrationStatus??scene.illustrationStatus??act.illustrationStatus??story.illustrationStatus});
 }
}
const usedPaths=new Set();
const illustrations=references.map(reference=>{
 const newlyReviewed=newByPath.get(reference.path);
 const prior=newlyReviewed||byPath.get(reference.path);
 if(!prior)throw new Error(`No preserved original image provenance for ${reference.id}: ${reference.path}`);
 if(usedPaths.has(reference.path))throw new Error(`Repeated packaged picture in new scene references: ${reference.path}`);
 usedPaths.add(reference.path);
 const bytes=fs.readFileSync(path.join(readerDirectory,reference.path));
 const sha=crypto.createHash('sha256').update(bytes).digest('hex');
 if(sha!==prior.sha256)throw new Error(`Image bytes changed: ${reference.path}`);
 if(newlyReviewed){
  if(prior.id!==reference.id)throw new Error(`New illustration ID drift: ${reference.id}`);
  return {...prior,caption:reference.caption};
 }
 return {...prior,id:reference.id,caption:reference.caption,reused:true,
  originalId:prior.id,originalVersion:'v4-maritime-illustrated-2026-10-22',
  originalReview:prior.review,
  review:'保留旧稿已生成图及原始审读证据；本轮只核对文件、来源和新引用关系。该图作为旧稿情境参考，不据此宣称新场动作已完成重新绘制或新一轮视觉验收。',
  narrativeStatus:reference.status==='needs-redraw'?'needs-redraw':'prior-concept-context-reference'};
});
const manifest={schemaVersion:1,generator:'built-in imagegen',updated:'2026-10-23',storyVersion:story.version,
 disclaimer:'包含保留的旧稿情境参考与按第七稿新绘并目视审读的插图；逐项以reused及review区分。概念图不是历史现场证据。',
 baselineManifest:path.relative(projectRoot,baselinePath).replaceAll('\\','/'),illustrations};
fs.writeFileSync(manifestPath,JSON.stringify(manifest,null,2)+'\n');
console.log(JSON.stringify({storyVersion:story.version,reindexed:illustrations.length,reviewedNewAssets:illustrations.filter(x=>!x.reused).length,generatedByThisSync:0,baselineRetained:baseline.illustrations.length}));
