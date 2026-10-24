import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
const dir=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(dir,'../../../..');
const source=path.join(root,'docs/narrative/zheng-zhilong-story.json');
const bytes=fs.readFileSync(source),sha=b=>crypto.createHash('sha256').update(b).digest('hex');
if(sha(bytes)!=='5e94bb490275d38c2978bc487aa0a72afc1cc9f1f8b57b214bf91bec9551e736')throw new Error('Expected reviewed input; do not replay against later edits.');
const story=JSON.parse(bytes),scenes=new Map(story.acts.flatMap(a=>a.scenes).map(s=>[s.id,s])),changes=[];
const change=(id,index,from,to,reason)=>{
 const s=scenes.get(id),old=s.paragraphs[index-1];
 if(!old.includes(from)||old.split(from).length!==2)throw new Error('Unique original phrase missing '+id+':'+index);
 s.paragraphs[index-1]=old.replace(from,to);
 changes.push({id,paragraph:index,before:old,after:s.paragraphs[index-1],reason});
};
change('yiguan_a2_s1',14,'锯赶在解缆前还入阿旺箱里，一官上了船，岸上的话仍有一句没说。','阿旺也接了这一航的修缮活，带阿禾同船去大员。锯赶在解缆前还入老人箱里，阿禾跑去收篙；一官跟着上船，保人那句话仍没有说。','R2：明确叔侄随航，保人仍不知情。');
change('yiguan_a3_s3',13,'阿旺把工具倒进衣襟','阿旺打开工具箱，把工具倒进衣襟','物件表述：明确腾空的是贯穿的工具箱。');
change('yiguan_a4_s1',1,'杜七让他把锅底也刮干净','顺生沉后，杜七借来一条旧船，带着还愿跟他的人接零散航次。芝虎这碗粥便是从那边端来的。杜七让他把锅底也刮干净','R3：沉船后借船再起的过渡。');
change('yiguan_a4_s2',1,'杜七正给舵柄换绳','两年间，杜七拿合货所得抵价，陆续接下三条旧船，眼下顶外侧的便是其中一条。他正给舵柄换绳','R3：说明战船与另两条余船的来源，保留未清债。');
const fifth=scenes.get('yiguan_a5_s2');
const copperIndex=fifth.paragraphs.findIndex(p=>p.includes('焦扣'));
if(copperIndex<0)throw new Error('Copper button reference missing');
change('yiguan_a5_s2',copperIndex+1,'焦扣','烧焦的铜扣','明确承接芝虎护衣上的铜扣。');
const teasers={
 yiguan_a1_s1:'码头缺一个随货赴日的人。一官只听懂半句洋话，眼下却人人等他开口。',
 yiguan_a1_s2:'一只手还扣在舷边，两箱货堵住救人的位置。天亮后，这笔损失要算在谁头上？',
 yiguan_a1_s3:'船位空出来了，旧债还没还清。舅父将一份三年分成的契纸推到他面前。',
 yiguan_a1_s4:'旧木筹对不上新筹。水口外的炮口朝着他们，阮老六却先问船上谁会补缝。',
 yiguan_a2_s1:'在平户，一官会问货价，却修不好一处屋檐。屋里的女人替他扶住梯子。',
 yiguan_a2_s2:'雇主迟迟不发译费，眼前唐船又不肯落帆。炮衣掀起，一官只能先试着把人叫过来。',
 yiguan_a2_s3:'周船主的货没讨回，阮老六又来催路钱。两人凑出的银，买不起船，倒够装成一笔买路钱。',
 yiguan_a2_s4:'平户来信说，福松已经出生。归船等风，合货的船主也在等他答话。',
 yiguan_a3_s1:'欠钱的人不露面，替他运货的船却到了。撬开舱盖，箱上写的名字与欠单不同。',
 yiguan_a3_s2:'船上只剩明日半天的水，新伙计说岸上能兑银。杜七的十四包私货还整齐堆在舱里。',
 yiguan_a3_s3:'左翼三起援旗，艉后追船逼近。退潮前还剩半个时辰，能接人的小艇只有一条。',
 yiguan_a3_s4:'杜七带来一块碎舵叶，只问接应艇为什么掉头。陈添在门边，阿禾躺在里屋。',
 yiguan_a4_s1:'地方官递来愿意周旋的信，船上却已快揭不开锅。六把刀收好了，杜七的第七把还在腰间。',
 yiguan_a4_s2:'这天没有雾。蓝灰补片再次升到桅顶，阿禾盯着对面还未动的接应艇。',
 yiguan_a4_s3:'福松从平户带来一张添了帆的船图。三年后的料罗湾，阿禾要一官答应留住四条接人的艇。',
 yiguan_a4_s4:'报捷的人在身后等盖印。二十八枚回信牌只交回二十七枚，芝龙又从头数了一遍。',
 yiguan_a5_s1:'杜七来领自己的船，码头上却已叫起新船名。森坐在父亲案旁，认得那面缴过钱的旗。',
 yiguan_a5_s2:'父亲给森备好了南京的衣、药与交游名单。到了那里，他见到的人和听到的消息，开始超出名单上的安排。',
 yiguan_a5_s3:'田川氏踏上安平的跳板，先把沉甸甸的布包递过去。岸上那个高大的青年，还应不应她叫一声福松？',
 yiguan_a5_s4:'箱已装好，随行单上也写了妻儿的名。福州清营的答复尚未亲耳听见，家里的人先要他把话说清。',
};
for(const [id,text] of Object.entries(teasers))scenes.get(id).readerTeaser=text;
story.acts[1].readerHook='平户的窄屋里，一官有了愿意一起过日子的人。海上那份高工钱，又催他离岸。';
story.acts[3].readerHook='来信说愿意周旋。船上的人想知道，交了刀能不能换来饭与上岸的路。';
const frame=scenes.get('yiguan_a4_s3').illustrations.find(f=>f.id==='yiguan_a4_s3_process2');
const captionBefore=frame.caption;
frame.caption='专留的接应轻艇绕回烟里，把落水的人接回来。（旧稿战斗情境参考）';
scenes.get('yiguan_a2_s1').summary+='阿旺另接同航修缮活，带阿禾随船去大员，仍不知自己被填作保人。';
scenes.get('yiguan_a4_s1').summary='顺生沉后，杜七先借旧船带人做零散航次。'+scenes.get('yiguan_a4_s1').summary;
scenes.get('yiguan_a4_s2').summary='两年间杜七以合货所得抵价，陆续接下三条旧船。'+scenes.get('yiguan_a4_s2').summary;
for(const id of ['yiguan_a2_s1','yiguan_a4_s1','yiguan_a4_s2'])scenes.get(id).currentCanon=scenes.get(id).summary;
story.editorialRevision.review='rewrites/v8-engagement-2026-10-23/REVIEW.md';
story.editorialRevision.reviewPatch='rewrites/v8-engagement-2026-10-23/review-patch.json';
fs.writeFileSync(path.join(dir,'before-review-story.json'),bytes);
fs.writeFileSync(source,JSON.stringify(story,null,2)+'\n');
const report={beforeSha256:sha(bytes),afterSha256:sha(fs.readFileSync(source)),changes,sceneTeasers:teasers,actHooks:[2,4],caption:{id:frame.id,before:captionBefore,after:frame.caption},scope:'R1-R4 and two clear object names; no image bytes, IDs, dates, paragraph counts or history records changed.'};
fs.writeFileSync(path.join(dir,'review-patch.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({paragraphEdits:changes.length,teasers:20,caption:frame.id,sha256:report.afterSha256}));
