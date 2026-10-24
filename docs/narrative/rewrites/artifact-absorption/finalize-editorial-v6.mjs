import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const directory=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(directory,'../../../..');
const target=path.join(root,'docs/narrative/zheng-zhilong-story.json');
const story=JSON.parse(fs.readFileSync(target,'utf8'));
if(story.version!=='v6-suspense-integrated-2026-10-22')throw new Error('Expected the integrated v6.');
const scenes=new Map(story.acts.flatMap(a=>a.scenes).map(s=>[s.id,s]));
const log=JSON.parse(fs.readFileSync(path.join(directory,'applied-changes.json'),'utf8'));
const corrections=[];
function edit(id,prefix,transform,reason){
 const s=scenes.get(id),found=s.paragraphs.map((p,i)=>({p,i})).filter(x=>x.p.startsWith(prefix));
 if(found.length!==1)throw new Error(`Expected unique paragraph: ${id} ${prefix}`);
 const {p,i}=found[0],next=transform(p);
 if(next===p)return;
 s.paragraphs[i]=next;corrections.push({sceneId:id,paragraph:i+1,oldParagraph:p,newParagraph:next,reason});
}
edit('yiguan_a4_s4','出入单誊清后',()=> '出入单誊清后，陈添问少爷是不是也该过目。一官已将印收进匣里：“给他照着走就是。”他把信封封好，压在报捷文书下面。两份纸一起送回安平，报捷文书张在前堂，另一份被管事收进册中。往后家人每次上船，先照这张单验人。','删去次日已改阿旺同一名单的重复事件，1636年的实际争执留给第五幕上演。');
edit('yiguan_a5_s1','芝龙叫人先给受伤船工结药钱',p=>p.replace('散席后，森替父亲收册，将案边的副纸一并放进自己的书匣。',''),'不要在杜七尚未离开前先跳到散席收册。');
edit('yiguan_a5_s1','杜七离开时',p=>p.includes('回屋后，森替父亲收册')?p:p+'回屋后，森替父亲收册，将案边的两张副纸一并放进自己的书匣。','将副纸收存动作放在送还单据以后，保持当场动作时序，连接1638夹书。');
story.acts[4].readerHook='家人每次上船，都要先照新单验人。十二岁的郑森坐到船账旁，还不明白，护人的规矩能管到哪一步。';
scenes.get('yiguan_a3_s2').readerTeaser='没有风，水只够到明日午前。岸上有人放话，肯用现银收货。';
scenes.get('yiguan_a4_s4').dramaticBeat.next='出入单发往安平并开始用来验人；下一幕阿旺的外岛修船差事被改到港内，控制扩及妻儿，最后被1646的拒绝击穿。';
fs.writeFileSync(target,JSON.stringify(story,null,2)+'\n');
if(corrections.length)log.finalEditorialCorrections=corrections;
log.metadataCorrections=['第五幕引子改从1636实际开场入题，避免无标记跳到1646。','第三幕收货话归给消息来源，不替骗局作全知担保。'];
fs.writeFileSync(path.join(directory,'applied-changes.json'),JSON.stringify(log,null,2)+'\n');
console.log(JSON.stringify({paragraphCorrections:corrections.length,bodyCharacters:[...scenes.values()].reduce((n,s)=>n+s.paragraphs.join('').length,0)}));
