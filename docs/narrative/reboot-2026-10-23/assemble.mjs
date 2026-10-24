import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {storyStructure,aliasIssues} from '../../../tools/zheng-story-contract.mjs';
import {rebootAliases} from '../../../tools/zheng-reboot-aliases.mjs';
const dir=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(dir,'../../..');
const source=path.join(root,'docs/narrative/zheng-zhilong-story.json');
const prior=fs.readFileSync(path.join(dir,'archive/prior-source.json'));
if(!fs.readFileSync(source).equals(prior))throw new Error('Active source has changed since the opaque archive; reconcile instead of overwriting.');
const acts=['parts-1-2.json','parts-3-4.json','parts-5-6.json'].flatMap(p=>JSON.parse(fs.readFileSync(path.join(dir,p),'utf8').replace(/^\uFEFF/,'' )).acts);
const expected=[4,4,4,4,3,3];
if(acts.length!==6)throw new Error('Incomplete novel');
for(const [ai,a] of acts.entries()){
 if(a.id!==`act-${ai+1}`||a.scenes.length!==expected[ai])throw new Error('Invalid part '+a.id);
 a.illustrationStatus='text-only';
 for(const [si,s] of a.scenes.entries()){
  if(s.id!==`zzl_a${ai+1}_s${si+1}`)throw new Error('Invalid chapter '+s.id);
  for(const line of s.dialogue)if(!s.paragraphs.some(p=>p.includes(line.text)))throw new Error('Dialogue not in prose '+s.id+': '+line.text);
  if(!s.history.sources.length)throw new Error('Missing evidence '+s.id);
  s.illustrationStatus='text-only';s.dialogueInParagraphs=true;
 }
}
const aliases={...rebootAliases};
const characters=[
 ['郑芝龙／一官','跨语言通译、武装海商、海盗首领，后受明廷招抚并进入军政中枢。早年私人动机与具体现场为文学重建。'],
 ['田川氏','郑成功生母，与郑氏跨海家庭有关。家世、姓名及死难纪年存在异说；私人家庭场景为重建。'],
 ['福松／郑森／郑成功','幼年由日本赴明，接受士人教育，后受隆武赐姓，1646未随父降清。'],
 ['李旦','活跃于平户、台湾和中国沿海的华商领袖与交涉者；荷方对其控诉只代表该方记录。'],
 ['李国助','李旦之子，独立经营海上势力，曾与VOC竞争或合作；不等同郑氏部下。'],
 ['许心素','与福建官府及荷方贸易相连的海商；面临军事、贸易和官府问责的多重压力。'],
 ['德·维特','VOC驻台湾长官之一，郑芝龙早期海上活动的合作与交涉方。'],
 ['熊文灿','福建巡抚，参与郑芝龙受抚及随后的海防秩序。'],
 ['李魁奇与钟斌','曾与郑芝龙势力发生隶属、结盟或反叛关系的海上首领，各有独立人众和利益。'],
 ['汉斯·普特曼斯','1629年起任荷方台湾长官，寻求扩大贸易，以海上结盟和武力施压。其报告不等于中方全部事实。'],
 ['刘香','郑芝龙的海上对手，曾与VOC及李国助合作，1635败亡；具体最后战斗各书有异。'],
 ['郑芝虎','郑芝龙之弟，参与海上战争；阵亡传统有据，具体死法与早次失踪记录必须区分。'],
 ['郑鸿逵','郑芝龙之弟，军事与拥立活动中有自己的角色，不能写成兄长的无意志工具。'],
 ['朱聿键／隆武帝','1645在福建即位，依靠郑氏军财而仍有自身政治与军事目标。'],
 ['黄道周','拥立联盟与隆武朝的重要文臣，主张及行动不能归结为与郑氏的私人斗气。'],
 ['博洛','清方征闽与招降郑芝龙的关键人物；招降及挟北有记载，私下对白为重建。'],
].map(([name,role])=>({name,role}));
const story={title:'海上明旗：郑芝龙',subtitle:'史料重构历史小说 · 从海上谋生到明清易代 · 约1623—1646',version:'historical-reboot-2026-10-24',narrativeContract:{edition:'historical-reboot',revision:9,acts:6,sceneCounts:expected,canonicalPrefix:'zzl'},illustrationStatus:'text-only',logline:'一个在异乡学会替人说话的福建青年，离开通译的职位，带人进入武装海贸。他要有船，就得找货；要养人，就得争海路；要摆脱追捕，又必须接受朝廷的条件。旧合作者成为敌人，旧对手变作盟友，直到他掌握海上的力量，却迎来一个从陆地改变天下的对手。',characters,acts,legacySceneAliases:aliases,aliasScope:'旧链接仅导航到相近历史阶段；旧情节已撤换，不表示故事对应或延续。',plotThreads:[],ending:{fixed:'1646年郑芝龙赴福州降清后受控北上；郑成功没有随父整体归降。郑芝龙1661年被杀。田川氏死难的具体纪年、地点与方式有异说，见末章史注。'},sourceNotes:['本作于2026-10-23启动、24日完成重构工作。创作者使用本轮新查史料，不读取此前小说、人物关系、改写圣经或评论。','事实来源包括学术研究及其所引VOC档案、后出明清史籍、机构资料。论文转引不等于本轮已核原档影像；相似古籍可能互相承袭。','每章history分别说明事件骨架、争议和文学重建。具体对白、私下思考、现场感官和少量衔接均为创作，不作为史料引文。','新作采用六部二十二章与自由段落，不用旧图像锚点限制故事。旧图保留归档，本版无新插图。游戏场景稿是制作文本，尚未接入游戏引擎。'],editorialRevision:{started:'2026-10-23',completed:'2026-10-24',scope:'Complete independent reconstruction from fresh source research; no prior prose or plot used.',report:'reboot-2026-10-23/DELIVERY.md',research:['reboot-2026-10-23/SOURCES-EARLY.md','reboot-2026-10-23/SOURCES-WAR.md','reboot-2026-10-23/SOURCES-LATE.md']} };
storyStructure(story);const errors=aliasIssues(story);if(errors.length)throw new Error(errors.join('\n'));
fs.writeFileSync(source,JSON.stringify(story,null,2)+'\n');
fs.writeFileSync(path.join(dir,'assembled.json'),JSON.stringify({sourceSha256:crypto.createHash('sha256').update(fs.readFileSync(source)).digest('hex'),chapterCount:22,parts:acts.map(a=>({id:a.id,chapters:a.scenes.length,characters:a.scenes.reduce((n,s)=>n+s.paragraphs.join('').length,0)})),scope:'First assembled manuscript; later editorial fixes recorded separately.'},null,2)+'\n');
console.log('Assembled independent historical novel: six parts, 22 chapters.');
