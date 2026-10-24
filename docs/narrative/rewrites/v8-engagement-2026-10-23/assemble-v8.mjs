import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
const dir=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(dir,'../../../..');
const source=path.join(root,'docs/narrative/zheng-zhilong-story.json');
const hash=x=>crypto.createHash('sha256').update(x).digest('hex');
const baselineBytes=fs.readFileSync(path.join(dir,'baseline/story.json'));
if(hash(fs.readFileSync(source))!==hash(baselineBytes))throw new Error('Source changed since frozen V7. Do not overwrite current edits; reconcile explicitly.');
const baseline=JSON.parse(baselineBytes);
const story=structuredClone(baseline);
const parts=['draft-acts-1-2.json','draft-acts-3-4.json','draft-act-5.json'];
const allowedAct=new Set(['id','synopsis','readerHook','nextHook','scenes']);
const allowedScene=new Set(['id','paragraphs','dialogue','summary','readerTeaser','dramaticBeat','task']);
const seenActs=new Set(),seenScenes=new Set(),changes=[];
for(const file of parts){
 const draft=JSON.parse(fs.readFileSync(path.join(dir,file),'utf8').replace(/^\uFEFF/,''));
 for(const editAct of draft.acts){
  if(seenActs.has(editAct.id))throw new Error('Duplicate act '+editAct.id);
  seenActs.add(editAct.id);
  for(const key of Object.keys(editAct))if(!allowedAct.has(key))throw new Error('Unexpected act property '+key);
  const act=story.acts.find(x=>x.id===editAct.id);
  if(!act||editAct.scenes.length!==4)throw new Error('Invalid act '+editAct.id);
  for(const key of ['synopsis','readerHook','nextHook'])if(typeof editAct[key]==='string')act[key]=editAct[key];
  for(const edit of editAct.scenes){
   if(seenScenes.has(edit.id))throw new Error('Duplicate scene '+edit.id);
   seenScenes.add(edit.id);
   for(const key of Object.keys(edit))if(!allowedScene.has(key))throw new Error('Unexpected scene property '+key);
   const scene=act.scenes.find(x=>x.id===edit.id);
   if(!scene)throw new Error('Scene in wrong act '+edit.id);
   if(edit.paragraphs.length!==scene.paragraphs.length)throw new Error('Paragraph count drift '+edit.id);
   if(!edit.paragraphs.every(x=>typeof x==='string'&&x.trim()))throw new Error('Empty paragraph '+edit.id);
   for(const line of edit.dialogue){
    if(!edit.paragraphs.some(p=>p.includes(line.text)))throw new Error('Dialogue absent from prose '+edit.id+': '+line.text);
    if(line.text.length>34)throw new Error('Dialogue too long '+edit.id);
   }
   const changed=scene.paragraphs.flatMap((before,i)=>before===edit.paragraphs[i]?[]:[{paragraph:i+1,before,after:edit.paragraphs[i]}]);
   if(changed.length===0)throw new Error('Scene not revised '+edit.id);
   changes.push({id:scene.id,title:scene.title,changedParagraphs:changed.length,beforeCharacters:scene.paragraphs.join('').length,afterCharacters:edit.paragraphs.join('').length,changes:changed});
   Object.assign(scene,edit);
   scene.currentCanon=edit.summary;
   scene.dialogueInParagraphs=true;
  }
 }
}
if(seenActs.size!==5||seenScenes.size!==20)throw new Error('Draft coverage incomplete');
story.version='v8-engagement-historical-2026-10-23';
story.narrativeContract.revision=8;
story.subtitle='五幕二十场 · 第八稿 · 晚明海上人生 · 1621—1646';
story.logline='天启年间，寄身澳门货栈的福建青年一官，想凭一张会说异乡话的嘴挣出自己的船位。他与船工结伴，在平户成家，往返于明朝海防、海外商路与海盗争夺之间，终于有了船与官身。救命的盟约、等不到的家书和朝代倾覆，一次次逼他决定先保住谁；当他要替全家选定最后一条生路，妻儿与旧友各有了不肯交出的回答。';
story.illustrationStatusNote='第八稿重写人物关系、行动因果与晚明及同期日本的时代质感。沿用现有33项图像引用：5项曾按第七稿新绘，其余28项为更早情境参考。本轮未生成新图，不将原V7图像审读冒充V8逐动作视觉验收；八处过程图段位保持。';
story.sourceNotes=[...new Set(baseline.sourceNotes)];
story.sourceNotes.push('2026-10-23 第八稿：依据用户选择，以更好读、更想追下去为目标，全篇重写人物关系、具体愿望、因果衔接和时代生活。保留五幕二十场、原编年、历史与虚构分层、单线既定行动及43条旧链接。V7文学模板是历史写作记录，不再作为每场强制转折、感官配额和器物落像的创作目标。');
story.sourceNotes.push('第八稿时代核对：澳门丝货与回程银、季风航期、平户商贸、明廷受抚与游击身份、日本对外限制的先后、南京明廷及隆武时期进入人物处境。依据见rewrites/v8-engagement-2026-10-23/HISTORICAL-TEXTURE.md；未核私人家书、婚书、船引、军饷账册或博洛原信。新增私人对白、生活与交易仍为创作，不作史实证据。');
story.sourceNotes.push('第八稿配图继续复用；早前关于暂停图片或已完成某轮视觉验收的记录只对当时版本有效。本轮没有将文本检查等同于新图验收、演员桌读或Godot可玩叙事。');
story.editorialRevision={date:'2026-10-23',beforeVersion:baseline.version,beforeSourceSha256:hash(baselineBytes),report:'rewrites/v8-engagement-2026-10-23/EDITING-REPORT.md',design:'rewrites/v8-engagement-2026-10-23/DESIGN.md',historicalTexture:'rewrites/v8-engagement-2026-10-23/HISTORICAL-TEXTURE.md',paragraphCountsPreserved:true,scope:'Full twenty-scene prose revision for character engagement, causal clarity and late-Ming / contemporary Japan context; fixed story, no gameplay implementation.',previousReport:baseline.editorialRevision?.report};
const characterChanges={
 '林阿旺':{desire:'凭手艺养人、带阿禾学会船上的活；兑现给福建女儿修门、住些日子的旧约。',arc:'从合作中接受一官，也会因生计和情分沉默。后来仍救人、修船，却逐渐不再交出自己的去处；1646携工具回女儿家，是前段生活愿望的兑现，不是站在故事外审判主角。'},
 '陈添':{desire:'挣到独立写账的柜位，不再永远跟着别人的船与账走；同时不失差事、不当替罪者。',arc:'与一官相互帮忙、一起盼出头，也逐渐参与假传与改写航记。后来的报实讯与不替未到者落名有真实代价，不能抵销从前的责任。'},
};
for(const character of story.characters)if(characterChanges[character.name])Object.assign(character,characterChanges[character.name]);
const newSources=[
 {title:'澳门文化局：李金明《十七世纪初葡萄牙在澳门的贸易》（时代背景研究）',url:'https://www.icm.gov.mo/rc/viewer/10026/447'},
 {title:'平户荷兰商馆馆史（平户与迁馆编年）',url:'https://hirado-shoukan.jp/history/'},
 {title:'日本国立国会图书馆：出岛商馆（1635—1641政策与地点的区别）',url:'https://www.ndl.go.jp/nichiran/s1/s1_2.html'},
 {title:'邱炫煜：《明史纪事本末·郑芝龙受抚》校读',url:'https://ming.cnhis.ncnu.edu.tw/wp-content/uploads/2015/10/report2004ChiuSY.pdf'},
];
story.sources=[...(story.sources||[]),...newSources];
fs.writeFileSync(source,JSON.stringify(story,null,2)+'\n');
fs.writeFileSync(path.join(dir,'changes.json'),JSON.stringify({beforeVersion:baseline.version,afterVersion:story.version,beforeSha256:hash(baselineBytes),assembledSha256:hash(fs.readFileSync(source)),scenes:changes},null,2)+'\n');
console.log(JSON.stringify({version:story.version,scenes:changes.length,changedParagraphs:changes.reduce((n,s)=>n+s.changedParagraphs,0),beforeCharacters:changes.reduce((n,s)=>n+s.beforeCharacters,0),afterCharacters:changes.reduce((n,s)=>n+s.afterCharacters,0)}));
