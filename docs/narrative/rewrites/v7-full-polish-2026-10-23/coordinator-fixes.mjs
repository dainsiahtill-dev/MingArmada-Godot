import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
const here=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(here,'../../../..');
const file=path.join(root,'docs/narrative/zheng-zhilong-story.json'),bytes=fs.readFileSync(file);
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
if(hash(bytes)!=='f30a453470d8a806ce5b11db18ad18ef708292f35e50ba8d909a08ea7f63f859')throw Error('Expected pre-review coordinated draft only.');
const story=JSON.parse(bytes),scenes=new Map(story.acts.flatMap(a=>a.scenes).map(s=>[s.id,s])),fixes=[];
function change(id,key,index,before,after,reason){
 const scene=scenes.get(id),old=index===null?scene[key]:scene[key][index];
 if(!old.includes(before))throw Error(`${id}: missing exact text ${before}`);
 const next=old.replace(before,after);
 if(index===null)scene[key]=next;else scene[key][index]=next;
 fixes.push({id,key,paragraph:index===null?null:index+1,before,after,reason});
}
change('yiguan_a1_s2','readerTeaser',null,'人从黑水里捞回来了。天亮来清点的管事，却先掀开了阿旺的工具箱。','人从黑水里捞回来了。天亮清点过货箱，管事又来取阿旺的工具箱。','Correct the public teaser order: cargo counted before the later tool seizure.');
change('yiguan_a2_s1','readerTeaser',null,'窄屋檐下晾着三件收了钱的衣裳。','窄屋檐下晾着三件替邻家洗的衣裳。','Do not invent advance payment absent from the prose.');
change('yiguan_a1_s3','paragraphs',10,'合货总账','合货账本','Use the established object name; no ledger action added.');
change('yiguan_a2_s4','paragraphs',0,'家用布袋','家用银袋','Identify the recurring family silver bag at its introduction.');
change('yiguan_a2_s3','paragraphs',12,'在薄木上写下阿金二字','在薄木牌上写下阿金的姓名','Name the existing marker and inscription explicitly.');
change('yiguan_a4_s4','paragraphs',15,'单子誊清','家人出入单誊清','Identify the already-written family travel sheet.');
change('yiguan_a5_s2','paragraphs',8,'新讯一日数变。','京师陷落的消息传到南京，随后新讯一日数变。','Make the existing 1644 political rupture visible at the transition, without adding an event.');
change('yiguan_a5_s2','paragraphs',11,'这个我答不上来。','这事轮不到你去问。','Make the existing refusal to authorize his son clear rather than an unclear pronoun.');
const line=scenes.get('yiguan_a5_s2').dialogue.find(x=>x.text==='这个我答不上来。');
if(!line)throw Error('Dialogue excerpt missing');line.text='这事轮不到你去问。';
const after=JSON.stringify(story,null,2)+'\n';fs.writeFileSync(file,after);
fs.writeFileSync(path.join(here,'coordinator-fixes.json'),JSON.stringify({beforeSha256:hash(bytes),afterSha256:hash(after),fixes},null,2)+'\n');
console.log(JSON.stringify({fixes:fixes.length,sourceSha256:hash(after)}));
