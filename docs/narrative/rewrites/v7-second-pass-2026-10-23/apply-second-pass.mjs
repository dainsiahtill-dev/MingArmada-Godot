import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
const here=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(here,'../../../..');
const source=path.join(root,'docs/narrative/zheng-zhilong-story.json');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const baseline=fs.readFileSync(path.join(here,'before-story.json'));
const expected='7fc5969a5620718364e862ebf1333e9fa191bc9e8ed5351c7a866f72f5ff48f5';
if(hash(baseline)!==expected||hash(fs.readFileSync(source))!==expected)throw Error('Starting source changed; do not replay.');
const story=JSON.parse(baseline),sceneList=story.acts.flatMap(a=>a.scenes),byId=new Map(sceneList.map(s=>[s.id,s]));
const reviews=[],patches=[];
for(const name of ['opening','partners']){
 const proposal=JSON.parse(fs.readFileSync(path.join(here,`${name}-patches.json`),'utf8'));
 if(proposal.baselineSha256!==expected)throw Error(`${name}: stale proposal`);
 reviews.push(...proposal.reviews);patches.push(...proposal.patches);
}
const rootReviews=[
 {id:'yiguan_a4_s4',verdict:'保留',reason:'何贵握橹不松与一官继续找弟弟已经构成真实冲突；返回本艇、四艇续搜与家人出入单各有结果。',endingFunction:'未能决定弟弟生死，却已替家人排好出入，把代价送入第五幕。'},
 {id:'yiguan_a5_s1',verdict:'只读保留',reason:'杜七要的是自己的船，一官给药钱、月米与代管差事；动作已把不相容的要求摆明。原纸和抄本流转完整。',endingFunction:'父亲取回原纸，森留下抄本；供养与独立判断的冲突继续。'},
 {id:'yiguan_a5_s2',verdict:'微修第9段',reason:'在已经写明的借米困境中增加森与许谦分米的相互接触，使后文退回银信、借书无处归还牵住一个相识的人；删抽象的同纸读出相反意思。',endingFunction:'仍受父供养的儿子已试着承担别人的困境，失联的朋友和未经允许的军粮差事都没有被新衣解决。'},
 {id:'yiguan_a5_s3',verdict:'微修第2段',reason:'将重复的取包、站稳下船过程换成母亲从陌生面孔里找福松，父亲叫森；同一个人有两种称呼，接下一段摸到成年儿子的衣领。',endingFunction:'成功自己认饷、提衣向海，芝龙独自返回内院；1646拒同行已有行为前因。'},
 {id:'yiguan_a5_s4',verdict:'微修第16段',reason:'保留妻儿姓名空下的决定，只合并旧银袋和歪船图的收取，不重复点空、折纸、分装；让段末留汤的照料有空间。',endingFunction:'入清营后的去路已由别人决定，尾声阿旺住下；完整收束，不添续篇谜团。'}
];
reviews.push(...rootReviews);
function paragraph(id,n,after,reason){patches.push({id,field:'paragraphs',paragraph:n,before:byId.get(id).paragraphs[n-1],after,reason});}
paragraph('yiguan_a5_s2',9,'京师陷落的消息传到南京。有人连夜收行李，有人在廊下哭。天亮借米，森排到缸前，木斗已刮着底。许谦端碗来，看见只剩这些，往后退了一步。森叫住他，将碗里的米倒过去一半。两人端碗回屋，午后才去抄传新讯；念到前后不合的地方，森拿来原纸重对。夜里隔廊还亮着许谦的灯，半箱书已经捆上绳。','把现有借米处境落到森与许谦的短暂相处上，增强后文失联的具体代价；只是场内虚构微动作，不新增历史事件。');
paragraph('yiguan_a5_s3',2,'板下跪着一排人。她抱着布包，从最前一张脸看到后头，问福松在哪里。芝龙朝人群后叫了一声森。她跟着转过脸，仍站在跳板口，没有把包交出去。阿禾收紧缆，桩上吱了一声。','让团聚的期待先落在母亲认人和父亲叫名，替换重复收包与试板流程；儿子仍在下一段走出来。');
paragraph('yiguan_a5_s4',16,'夜里芝龙重抄家人出入单，写完自己的名字，笔移到田川氏那行，没有落下；下一行的森也空着。他从箱里取回旧银袋，把它和折好的歪船图收进贴身衣袋。灶上半锅汤还温着，姜气随揭盖的人散出来。他叫留给屋里的人。','保留不再代填妻儿的动作，将物件收取合成一次，不再重复说明银袋已空。');
const protectedIds=new Set(['yiguan_a3_s3','yiguan_a4_s2','yiguan_a5_s1']);
const seen=new Set();
for(const p of patches){
 const key=`${p.id}:${p.field}:${p.paragraph??''}`;if(seen.has(key)||protectedIds.has(p.id))throw Error(`Duplicate/protected ${key}`);seen.add(key);
 const scene=byId.get(p.id);if(!scene)throw Error(`Unknown scene ${p.id}`);
 if(p.field!=='paragraphs')throw Error('This pass expects paragraph-only proposals.');
 if(scene.paragraphs[p.paragraph-1]!==p.before||!p.after.trim())throw Error(`Exact paragraph guard failed ${key}`);
 scene.paragraphs[p.paragraph-1]=p.after;
}
if(new Set(reviews.map(r=>r.id)).size!==20||reviews.length!==20)throw Error('Incomplete scene-by-scene reading record');
const beat=byId.get('yiguan_a1_s3').dramaticBeat;
const metaBefore=beat.next;
beat.next='陈添的工钱仍要等合货清账，一官仍被催去洗桨；前方水口又有人要拿手艺和船上的人来定价。';
story.version='v7-second-pass-2026-10-23';
story.subtitle='五幕二十场 · 文学剧本第七稿·叙事精修 · 1621—1646';
story.editorialRevision={...story.editorialRevision,previousReport:story.editorialRevision.report,report:'rewrites/v7-second-pass-2026-10-23/EDITING-REPORT.md',beforeSourceSha256:expected,scope:'Second reading of all twenty scenes; seven targeted paragraph refinements, no deletion target, three prior focus scenes preserved.'};
const after=JSON.stringify(story,null,2)+'\n';fs.writeFileSync(source,after);
const chars=s=>s.acts.flatMap(a=>a.scenes.flatMap(x=>x.paragraphs)).join('').length;
fs.writeFileSync(path.join(here,'changes.json'),JSON.stringify({beforeSha256:expected,afterSha256:hash(after),beforeCharacters:chars(JSON.parse(baseline)),afterCharacters:chars(story),reviews,patches,editorialFields:[{id:'yiguan_a1_s3',field:'dramaticBeat.next',before:metaBefore,after:beat.next}]},null,2)+'\n');
console.log(JSON.stringify({version:story.version,reviewedScenes:reviews.length,editedScenes:new Set(patches.map(p=>p.id)).size,paragraphChanges:patches.length,beforeCharacters:chars(JSON.parse(baseline)),afterCharacters:chars(story),sha256:hash(after)}));
