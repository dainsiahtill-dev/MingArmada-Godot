import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';

const dir=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(dir,'../../../..');
const target=path.join(root,'docs/narrative/zheng-zhilong-story.json');
const input=fs.readFileSync(target);
const digest=b=>crypto.createHash('sha256').update(b).digest('hex');
const proposal=JSON.parse(fs.readFileSync(path.join(dir,'proposed-paragraph-fixes.json'),'utf8'));
if(digest(input)!==proposal.sourceSha256)throw new Error('Review source changed; do not overwrite later edits.');
const story=JSON.parse(input),scenes=story.acts.flatMap(a=>a.scenes),byId=new Map(scenes.map(s=>[s.id,s]));
const edits=[];
function paragraph(id,n,next,reason){
 const s=byId.get(id),old=s.paragraphs[n-1];
 if(typeof old!=='string'||!next||old===next)throw new Error(`Invalid paragraph edit ${id}:${n}`);
 s.paragraphs[n-1]=next;edits.push({sceneId:id,paragraph:n,oldText:old,newText:next,reason});
}
function phrase(id,n,old,next,reason){
 const p=byId.get(id).paragraphs[n-1];
 if(!p.includes(old))throw new Error(`Missing phrase ${id}:${n}`);
 paragraph(id,n,p.replace(old,next),reason);
}
for(const fix of proposal.fixes){
 let replacement=fix.replacement;
 if(fix.sceneId==='yiguan_a5_s4'&&fix.paragraph===18){
  const original=byId.get(fix.sceneId).paragraphs[17],at=original.indexOf('\n\n【史后记】');
  if(at<0)throw new Error('Historical postscript must remain in paragraph 18.');
  replacement+=original.slice(at);
 }
 paragraph(fix.sceneId,fix.paragraph,replacement,fix.reason);
 if(fix.dialogueSync){const d=fix.dialogueSync,line=byId.get(fix.sceneId).dialogue.find(x=>x.speaker===d.speaker&&x.text===d.oldText);if(!line)throw new Error('Dialogue sync missing');line.text=d.newText;}
}
phrase('yiguan_a2_s3',11,'水面上那层银还浮着。','方才撒银的地方只剩碎波，银早沉了。','银钱不可能在海面漂浮，保持先前撒银的不可挽回代价。');
phrase('yiguan_a3_s2',13,'不是叫我替我争货','不是叫你替我争货','修正否定句人称。');
const flagLine=byId.get('yiguan_a3_s2').dialogue.find(x=>x.text.includes('不是叫我替我争货'));
if(!flagLine)throw new Error('Flag dialogue missing');flagLine.text=flagLine.text.replace('不是叫我替我争货','不是叫你替我争货');
phrase('yiguan_a2_s1',14,'他把锯抱紧了些，转身跨上跳板。','他先把锯递回阿旺手里，才转身跨上跳板。','还锯必须落成动作，不能抱着借物直接登船。');
phrase('yiguan_a5_s2',12,'他没有说不许，只把册子从桌角收走，叫他先不许往外派人','他没有答谁能去，只把册子从桌角收走，叫他先不许往外派人','消除前后一句不许与没说不许的字面互撞。');
story.acts[0].readerHook=story.acts[0].readerHook.replace('两个词','一个词');
byId.get('yiguan_a4_s3').readerTeaser='泊位上先起了烟，而挡住救艇水路的那根索，正是他刚下令绷紧的。秋日再战，四条接应艇各有名字；有人要借走一条，水里的人还没有上来。';
const fire=byId.get('yiguan_a4_s3');
fire.summary='1630年初见，福松带来母亲画、自己添帆的歪船图。1633年厦门泊位起火，一官割断自己下令绷紧的护舰索，给救艇开路；秋日料罗湾再战，四条轻艇实名专做接应。芝虎一侧要借艇拖绳抢战位，艇边却正挂着落水者，一官没有调走它。四艇返回，仍有人没能上艇；阿满只留下一截断袖。';
Object.assign(fire.dramaticBeat,{
 obstacle:'战位需要拖船，接应艇却正在搭救落水者；腾艇抢上风就要把舷边的人留下。火海和断桅仍会使救援错过人。',
 result:'接应专用约定兑现，四艇一条不少返回并救回敌我落水者；火船倒桅时阿满仍未能获救，只带回一截断袖。兑现一次承诺没有抹去旧债，也不能担保无人再死。',
 next:'1635年，他仍会派出搜救艇，然而号令不能使海面交出未归的弟弟。'
});
if(fire.currentCanon)fire.currentCanon=fire.summary;
const toolbox=story.plotThreads.find(x=>x.name.includes('箱子'));
if(toolbox)toolbox.plant='1.1重箱致险，1.2抛货救人后工具被折抵一部分；3.3阿旺收拢工具、挪箱腾出救人位置。';
story.subtitle='五幕二十场 · 文学剧本第七稿 · 1621—1646';
story.version='v7-reviewed-illustrated-2026-10-23';story.narrativeContract.revision=7;
story.editorialRevision={date:'2026-10-23',receivedSourceSha256:proposal.sourceSha256,report:'rewrites/v7-review-2026-10-23/EDITORIAL-ACCEPTANCE.md',paragraphCountsPreserved:true,scope:'Correct verified continuity and physical-causality errors; preserve the expanded author draft and its history boundaries.'};
const received=JSON.parse(input);
if(scenes.some((s,i)=>s.paragraphs.length!==received.acts.flatMap(a=>a.scenes)[i].paragraphs.length))throw new Error('Paragraph count drift');
if(JSON.stringify(story.legacySceneAliases)!==JSON.stringify(received.legacySceneAliases))throw new Error('Alias drift');
fs.writeFileSync(target,JSON.stringify(story,null,2)+'\n');
fs.writeFileSync(path.join(dir,'applied-continuity-fixes.json'),JSON.stringify({date:'2026-10-23',receivedSourceSha256:proposal.sourceSha256,paragraphEdits:edits.length,edits},null,2)+'\n');
console.log(JSON.stringify({edits:edits.length,paragraphs:scenes.reduce((n,s)=>n+s.paragraphs.length,0),chars:scenes.reduce((n,s)=>n+s.paragraphs.join('').length,0)}));
