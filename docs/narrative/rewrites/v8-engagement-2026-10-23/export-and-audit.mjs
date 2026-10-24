import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import vm from 'node:vm';
import {fileURLToPath} from 'node:url';
const dir=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(dir,'../../../..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const sourceText=read('docs/narrative/zheng-zhilong-story.json'),story=JSON.parse(sourceText),before=JSON.parse(fs.readFileSync(path.join(dir,'baseline/story.json'),'utf8'));
const sha=x=>crypto.createHash('sha256').update(x).digest('hex');
const checks=[];
const check=(id,value)=>checks.push({id,passed:!!value});
const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
check('canonical IDs',same(story.acts.map(a=>[a.id,a.scenes.map(s=>s.id)]),before.acts.map(a=>[a.id,a.scenes.map(s=>s.id)])));
check('43 legacy aliases unchanged',Object.keys(story.legacySceneAliases).length===43&&same(story.legacySceneAliases,before.legacySceneAliases));
const rows=[];
let paragraphs=0,dialogue=0;
for(const [ai,act] of story.acts.entries()){
 const oldAct=before.acts[ai];
 for(const key of ['years','cover','coverWidth','coverHeight','illustrationStatus','illustrationScope'])check(act.id+':'+key,same(act[key],oldAct[key]));
 for(const [si,scene] of act.scenes.entries()){
  const old=oldAct.scenes[si];
  for(const key of ['id','year','location','history','image','imageWidth','imageHeight','imagePrompt','imageCaption','illustrationStatus','choices'])check(scene.id+':'+key,same(scene[key],old[key]));
  const withoutCaptions=frames=>(frames||[]).map(({caption,...rest})=>rest);
  check(scene.id+':process-image-contract',same(withoutCaptions(scene.illustrations),withoutCaptions(old.illustrations)));
  for(const frame of scene.illustrations||[]){
   const prior=old.illustrations.find(x=>x.id===frame.id);
   const expected=frame.id==='yiguan_a4_s3_process2'?'专留的接应轻艇绕回烟里，把落水的人接回来。（旧稿战斗情境参考）':prior.caption;
   check(frame.id+':caption-reviewed-or-preserved',frame.caption===expected);
  }
  check(scene.id+':paragraph-count',scene.paragraphs.length===old.paragraphs.length);
  check(scene.id+':rewritten',!same(scene.paragraphs,old.paragraphs));
  check(scene.id+':dialogue-extracted',scene.dialogue.every(d=>scene.paragraphs.some(p=>p.includes(d.text))));
  check(scene.id+':nonempty-goals',typeof scene.task==='string'&&scene.task.trim()&&['want','obstacle','decision','result','next'].every(k=>scene.dramaticBeat[k]?.trim()));
  paragraphs+=scene.paragraphs.length;dialogue+=scene.dialogue.length;
  rows.push({id:scene.id,title:scene.title,paragraphs:scene.paragraphs.length,beforeCharacters:old.paragraphs.join('').length,characters:scene.paragraphs.join('').length,changedParagraphs:scene.paragraphs.filter((p,i)=>p!==old.paragraphs[i]).length,frames:(scene.illustrations||[]).map(f=>({id:f.id,afterParagraph:f.afterParagraph}))});
 }
}
check('reader JSON exact source bytes',read('docs/narrative/zheng-zhilong/zheng-zhilong-story.json')===sourceText);
const context={window:{}};vm.runInNewContext(read('docs/narrative/zheng-zhilong/story-data.js'),context);
check('reader script exact story object',same(context.window.ZHENG_STORY,story));
const generated=read('docs/narrative/zheng-zhilong-campaign-script-2026-10-21.md');
check('generated screenplay contains every paragraph',story.acts.every(a=>a.scenes.every(s=>s.paragraphs.every(p=>generated.includes(p)))));
const currentManifest=JSON.parse(read('docs/narrative/zheng-zhilong/illustration-manifest.json'));
const oldManifest=JSON.parse(fs.readFileSync(path.join(dir,'baseline/illustration-manifest.json'),'utf8'));
check('all 33 image files and original hashes unchanged',currentManifest.illustrations.length===33&&currentManifest.illustrations.every(i=>oldManifest.illustrations.some(o=>o.id===i.id&&o.path===i.path&&o.sha256===i.sha256)));
const report={version:story.version,sourceSha256:sha(sourceText),baselineSha256:sha(fs.readFileSync(path.join(dir,'baseline/story.json'))),scenes:rows.length,paragraphs,dialogue,checks:checks.length,passed:checks.every(x=>x.passed),failures:checks.filter(x=>!x.passed),rows,scope:'Content/export/invariant verification only. Does not assess literary preference, all artwork, real browser rendering, performance or playable game integration.'};
fs.writeFileSync(path.join(dir,'content-verification.json'),JSON.stringify(report,null,2)+'\n');
fs.writeFileSync(path.join(dir,'final-changes.json'),JSON.stringify({baselineSha256:report.baselineSha256,finalSha256:report.sourceSha256,scenes:story.acts.flatMap((a,ai)=>a.scenes.map((s,si)=>({id:s.id,changes:s.paragraphs.flatMap((p,i)=>p===before.acts[ai].scenes[si].paragraphs[i]?[]:[{paragraph:i+1,before:before.acts[ai].scenes[si].paragraphs[i],after:p}])})))},null,2)+'\n');
if(!report.passed){console.log(JSON.stringify(report.failures));process.exitCode=1;}else{
 const numeral=['一','二','三','四','五'];
 const novel=[`# ${story.title}`,story.subtitle,'> 历史改编小说。编年有来源；私人对白、具体生活与部分人物属创作。逐场史实说明与来源见完整文学剧本。',story.logline];
 const game=[`# ${story.title} · 游戏场景改编工作稿`,story.subtitle,'> 本稿整理固定主线的场面目标、行动与衔接，供游戏叙事制作；未接入Godot、未验证玩家操作，不将文字任务表视为已实现玩法。完整文学正文及史实边界见同目录screenplay-v8.md。'];
 for(const [ai,act] of story.acts.entries()){
  novel.push(`## 第${numeral[ai]}幕 · ${act.title}`);
  game.push(`## 第${numeral[ai]}幕 · ${act.title}`);
  for(const scene of act.scenes){
   novel.push(`### ${scene.title}`,`${scene.year} · ${scene.location}`,...scene.paragraphs);
   game.push(`### ${scene.id} · ${scene.title}`,`${scene.year} · ${scene.location}`,`**场面目标：**${scene.task}`,`**人物想得到什么：**${scene.dramaticBeat.want}`,`**阻碍与可见压力：**${scene.dramaticBeat.obstacle}`,`**主线既定行动：**${scene.dramaticBeat.decision}`,`**直接后果：**${scene.dramaticBeat.result}`,`**衔接下一场：**${scene.dramaticBeat.next}`,'**对白摘记：**',scene.dialogue.map(d=>`- ${d.speaker}：${d.text}`).join('\n'),`**史实边界：**${scene.history.note}`);
  }
 }
 const reader=path.join(root,'docs/narrative/zheng-zhilong');
 fs.writeFileSync(path.join(reader,'novel-v8.md'),novel.join('\n\n')+'\n');
 fs.writeFileSync(path.join(reader,'game-scenes-v8.md'),game.join('\n\n')+'\n');
 fs.writeFileSync(path.join(reader,'screenplay-v8.md'),generated.replaceAll('](zheng-zhilong/images/','](images/').replaceAll('](../research/','](../../research/'));
 console.log(JSON.stringify({version:report.version,scenes:report.scenes,paragraphs,dialogue,checks:report.checks,passed:report.passed,sourceSha256:report.sourceSha256,characters:rows.reduce((n,s)=>n+s.characters,0),changedParagraphs:rows.reduce((n,s)=>n+s.changedParagraphs,0)}));
}
