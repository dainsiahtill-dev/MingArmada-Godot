import fs from 'node:fs';
import crypto from 'node:crypto';
const root='docs/production/model-preproduction-2026-10-24';
const data=JSON.parse(fs.readFileSync(`${root}/manifest.json`,'utf8'));
const errors=[],warnings=[];
const check=(condition,message)=>{if(!condition)errors.push(message);};
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const unique=(list,key)=>new Set(list.map(x=>x[key])).size===list.length;
check(unique(data.models,'id'),'模型ID重复');check(unique(data.artJobs,'id'),'草图ID重复');
check(data.requirements.length===170,'旧170项需求未完整保留审计');
check(unique(data.requirements,'id'),'需求审计ID重复');
for(const input of data.inputFiles)check(hash(input.path)===input.sha256,`输入基线发生变化：${input.path}`);
const models=new Set(data.models.map(m=>m.id));
for(const m of data.models){check(m.artJobs.length>0,`模型无绘图任务：${m.id}`);check(fs.existsSync(`${m.assetDirectory}/model-brief.json`),`缺模型简报：${m.id}`);check(fs.existsSync(m.research),`缺考据报告：${m.id}`);}
for(const r of data.requirements){check(Boolean(r.disposition&&r.note),`需求未分类：${r.id}`);for(const id of r.newModelIds)check(models.has(id),`需求引用无效模型：${r.id}->${id}`);}
check(!data.requirements.some(r=>r.category!=='named-character'&&r.category!=='npc-archetype'&&r.newModelIds.some(id=>id.startsWith('head-'))),'非人物资源错误引用角色头部');
check(JSON.stringify(data.requirements.find(r=>r.id==='prop-punt-pole')?.newModelIds)===JSON.stringify(['tool-punt-pole']),'撑篙重定向未替换旧手桨');
check(data.models.find(m=>m.id==='tool-punt-pole')?.originalRequirements.includes('prop-punt-pole'),'撑篙反向来源缺失');
check(data.models.find(m=>m.id==='prop-pouch')?.originalRequirements.includes('prop-medicine'),'共享软袋反向来源缺失');
check(!models.has('prop-chart')&&data.sharedConfigurations.some(c=>c.id==='prop-chart'&&c.sharedGeometryWith==='prop-letter'),'纸图几何重复计数');
let imageCount=0,reviewed=0,redraw=0;
for(const j of data.artJobs){
  for(const id of j.covers)check(models.has(id),`草图覆盖未知模型：${j.id}->${id}`);
  check(j.imagePath.startsWith('assets/production/model-kit-v1/'),`资源目录越界：${j.id}`);
  if(j.status==='not-generated'){warnings.push(`尚未生成：${j.id}`);continue;}
  imageCount++;
  check(fs.existsSync(j.imagePath),`缺PNG：${j.id}`);
  const bytes=fs.readFileSync(j.imagePath);
  check(bytes.subarray(0,8).toString('hex')==='89504e470d0a1a0a',`PNG签名错误：${j.id}`);
  const width=bytes.readUInt32BE(16),height=bytes.readUInt32BE(20);
  check(Math.max(width,height)>=1536&&Math.min(width,height)>=768&&width*height>=1_000_000,`图片过小：${j.id}`);
  check(hash(j.imagePath)===j.sha256,`图片哈希不匹配：${j.id}`);
  const dir=j.imagePath.slice(0,j.imagePath.lastIndexOf('/'));
  for(const filename of ['prompt.txt','shape-notes.md','review.json','generation.json'])check(fs.existsSync(`${dir}/${filename}`),`缺${filename}：${j.id}`);
  const g=j.generation;
  check(Boolean(g),`未注册生成：${j.id}`);
  if(g){check(g.tool==='built-in-imagegen',`生成路线错误：${j.id}`);check(g.modelingApproved===false&&g.historyApproved===false,`未经审定提前批准：${j.id}`);}
  const review=j.review||g?.review;
  if(review&&review.status!=='not-yet-visually-reviewed')reviewed++;else warnings.push(`尚未目视审查：${j.id}`);
  if(review?.status==='needs-redraw'){redraw++;warnings.push(`待修：${j.id}`);}
  if(j.preferredImagePath){check(fs.existsSync(j.preferredImagePath),`优先修订图片不存在：${j.id}`);check(hash(j.preferredImagePath)===j.preferredSha256,`优先修订图片哈希不符：${j.id}`);}
}
check(imageCount===data.summary.generatedImages,'生成图片统计不一致');
check(data.models.length===data.summary.models,'模型总数不一致');
check(data.models.filter(m=>m.scope==='production').length===data.summary.production,'制作基线统计不一致');
check(data.models.filter(m=>m.scope==='reserve').length===data.summary.reserve,'预备统计不一致');
const result={checkedAt:new Date().toISOString(),catalogValid:errors.length===0,models:data.models.length,artJobs:data.artJobs.length,generatedImages:imageCount,visuallyReviewed:reviewed,needsRedraw:redraw,allSketchesGenerated:imageCount===data.artJobs.length,modelingReady:false,browserQA:{status:'not-completed',reason:'cua browser protocol policy rejected local file URL; no workaround attempted'},errors,warnings};
fs.writeFileSync(`${root}/verification.json`,JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify(result,null,2));
if(errors.length)process.exitCode=1;
