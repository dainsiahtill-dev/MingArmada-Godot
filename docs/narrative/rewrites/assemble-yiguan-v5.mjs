import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { acts as opening } from './yiguan-v5-acts-1-2.mjs';
import { act as endingAct } from './yiguan-v5-act-5.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const read = p => JSON.parse(fs.readFileSync(path.join(root, p), 'utf8'));
const baseline = read('docs/narrative/rewrites/baseline-v4-2026-10-22/story.json');
const middle = read('docs/narrative/rewrites/yiguan-v5-acts-3-4.json').acts;
const acts = [...opening, ...middle, endingAct];
const oldScenes = new Map(baseline.acts.flatMap(a => a.scenes).map(s => [s.id, s]));
const aliasesByAct = [
  { 1:'1_1',2:'1_1',3:'1_2',4:'1_3',5:'1_3',6:'1_4' },
  { 1:'2_1',2:'2_1',3:'2_2',4:'2_4',5:'2_4',6:'2_2',7:'2_3',8:'3_2' },
  { 1:'3_1',2:'3_1',3:'3_3',4:'3_4',5:'4_1',6:'3_1',7:'3_1',8:'3_2',9:'3_2',10:'3_2' },
  { 1:'4_1',2:'4_1',3:'4_2',4:'4_2',5:'5_1',6:'4_1',7:'4_3' },
  { 1:'4_3',2:'4_3',3:'4_3',4:'4_3',5:'4_4',6:'5_1',7:'5_1' },
  { 1:'5_2',2:'5_3',3:'5_4',4:'5_4',5:'5_4' }
];
const legacySceneAliases = Object.fromEntries(aliasesByAct.flatMap((map,a) => Object.entries(map).map(([s,to]) => [`zheng_a${a+1}_s${s}`, `yiguan_a${to.replace('_','_s')}`])));
const sceneCaptions = {
  yiguan_a1_s1:'误译之后，滚散的橘子让争执暂时停住。',
  yiguan_a1_s2:'驳船遇险，保货与救人已不能两全。',
  yiguan_a1_s3:'一官以未来的分成换取随船位置。',
  yiguan_a1_s4:'第一次过路交钱，木筹背后的武力才是真正凭据。',
  yiguan_a2_s1:'平户窄屋，两个人共同修补日常。',
  yiguan_a2_s2:'炮船下的保证，不能由说保证的人独自兑现。',
  yiguan_a2_s3:'诱计被识破以后，夺船必须靠同伴配合。',
  yiguan_a2_s4:'本要寄回的银袋，被留在合货桌上。',
  yiguan_a3_s1:'红封被撬开，索赔越过了散户货物的边界。',
  yiguan_a3_s2:'以货赎人的旧稿船间交接参考；新稿改在岸埠交换。',
  yiguan_a3_s3:'旧图未表现本稿海雾与赭黄援旗，暂停显示。',
  yiguan_a3_s4:'杜七追问沉船缘由，陈添把谎言续了下去。',
  yiguan_a4_s1:'没有官印的承诺，先换走了众人的刀。',
  yiguan_a4_s2:'厦门狭口再起援旗，未说出的两年在炮火中破裂。',
  yiguan_a4_s3:'料罗湾，重新集结的船与火船推进。',
  yiguan_a4_s4:'胜战之后，搜救艇还在寻找未归的弟弟。',
  yiguan_a5_s1:'令旗与旧友的权力关系：旧稿参考，须按断手与新场关系重画。',
  yiguan_a5_s2:'父子读书与交游控制：旧稿图片不对应本场，正文优先。',
  yiguan_a5_s3:'重聚的母子，已不能补回的年月。',
  yiguan_a5_s4:'行李已备好，愿不愿走却尚未问过。'
};
for (const [a,act] of acts.entries()) {
  const coverIndex = [0,1,2,4,5][a];
  Object.assign(act,{cover:baseline.acts[coverIndex].cover,coverWidth:baseline.acts[coverIndex].coverWidth,coverHeight:baseline.acts[coverIndex].coverHeight,illustrationStatus:'ready',illustrationScope:'v4-atmosphere-reference'});
  for (const scene of act.scenes) {
    const legacy = scene.imageLegacyId ? oldScenes.get(scene.imageLegacyId) : [...oldScenes.values()].find(s => s.image === scene.suggestedLegacyIllustration);
    if (!legacy) throw new Error(`Missing illustration reference ${scene.id}`);
    Object.assign(scene,{image:legacy.image,imageWidth:legacy.imageWidth,imageHeight:legacy.imageHeight,imagePrompt:legacy.imagePrompt,imageCaption:`${sceneCaptions[scene.id]}（旧稿情境参考）`,illustrationScope:'v4-atmosphere-reference',illustrationStatus:['yiguan_a3_s3','yiguan_a5_s1','yiguan_a5_s2'].includes(scene.id)?'needs-redraw':'ready',dialogueInParagraphs:true});
    scene.history.sources = [{title:'五幕新稿史实护栏、编年与来源',url:'../research/yiguan-v5-historical-guardrails-2026-10-22.md'}];
    if (a === 2) scene.history.note = '1625年李旦、颜思齐先后去世及郑氏网络发展属于历史背景；本场扣货、无风、被擒、赎人、顺生沉没、援旗及隐瞒全部为原创F，不冒充史实中的特定事件。李、颜关系与早年年表存在材料层次差异。';
    if (a === 3) scene.history.note = ({
      yiguan_a4_s1:'1626早期招抚接触与1628正式受抚分开。本场交刀、使者用语、空米船、阮老六设伏与抢粮、分粮全属F，不把劫掠写成可确证的劫富济贫原案。',
      yiguan_a4_s2:'1628郑芝龙与明军、许心素所处冲突及受抚后授游击为历史骨架。杜七、阿禾、陈添、援旗揭密、战术配置、断手与停船核账均为F；不用私人决斗代替史实，也不宣称找到当日战术原图。',
      yiguan_a4_s3:'1630郑成功由日本赴明、1633荷方袭击厦门及料罗湾战役为史实骨架；父子初见、木箱、画船、四条接应艇及战中对白全F。火攻有史料基础，不固化争议中的舰数、火船数与单舰归属。',
      yiguan_a4_s4:'1635击败刘香及郑芝虎在相关战事中死亡采用通行编年；各版本战况、尸体与死法叙述不同。本场寻弟、护衣、存活伤者与创伤控制心理均F，不拍定一种死法。'
    })[scene.id];
    if (a === 4) scene.history.note = ({
      yiguan_a5_s1:'1630赴明、1638入县学及郑氏海商秩序为背景；1636—1639杜七案、旗费退还、申诉受阻、父子看账、家庭控制均F。令旗收费不写全国一律固定三千两，也不将17世纪保护与垄断合理化为现代制度。',
      yiguan_a5_s2:'1641成家、1644南京太学采用地方人物志与纪念馆等编年；不把1641错写入太学年。本场家书被滞留、名单、父子辩论、陈添纠报、书箱等全F；所有所读内容为创作中的人物实践，不冒作史书原话。',
      yiguan_a5_s3:'1645隆武帝赐姓朱、改名成功及田川氏赴明为史实骨架；月日先后不锁定。码头相认、私宅饭食、歪船图与派人争执全F。田川氏家世、姓名通称和生活细节保留来源边界，不把她写成全知的道德裁判。',
      yiguan_a5_s4:'1646降清、赴福州、随后被挟北上，郑成功不从及田川氏罹难为史实骨架，郑芝龙1661遇害。许官说法见后出编纂，未核原信，故用传话而非亲核承诺。家中拒行、箱子、对话、原画、原创建造者结局与北上短渡细节为F；不据本剧私场解释全部政治史。'
    })[scene.id];
    delete scene.imageLegacyId; delete scene.suggestedLegacyIllustration;
  }
}
const scenes = acts.flatMap(a=>a.scenes);
const scene = id => scenes.find(s=>s.id===id);
function frames(target, legacy, placements) {
  scene(target).illustrations = (oldScenes.get(legacy).illustrations ?? []).map((f,i)=>({...f,id:`${target}_process${i+1}`,afterParagraph:placements[i],caption:`${f.caption}（旧稿战斗情境参考）`,illustrationStatus:'ready',illustrationScope:'v4-atmosphere-reference'}));
}
frames('yiguan_a2_s3','zheng_a2_s7',[8,11]);
frames('yiguan_a4_s2','zheng_a4_s3',[4,9]);
frames('yiguan_a4_s3','zheng_a5_s4',[10,12]);
scene('yiguan_a5_s4').illustrations = ['zheng_a6_s4','zheng_a6_s5'].map((id,i)=>{
  const s=oldScenes.get(id);return {id:`yiguan_a5_s4_after${i+1}`,image:s.image,caption:i?'北上途中的孤独舟影：旧稿氛围参考，不将赴福州与北上写成一次自愿海航。':'不随行者各有去路：旧稿情境参考。',afterParagraph:i?18:15,width:s.imageWidth,height:s.imageHeight,illustrationStatus:i?'needs-redraw':'ready',illustrationScope:'v4-atmosphere-reference'};
});
const story={
  title:'一官入海',subtitle:'五幕重写本 · 文学剧本第四稿 · 1621—1646',
  logline:'一个不愿再被别人当作筹码的海上青年，靠替人担保、冒险与结盟取得自己的船。他一度能替众船挡住刀与炮，后来也学会把伙伴和妻儿放进自己的安排。等他试图为全家买下一条活路，最亲的人却不肯再由他答应。',
  version:'v5-five-act-rewrite-2026-10-22',narrativeContract:{revision:5,acts:5,scenesPerAct:4,canonicalPrefix:'yiguan'},legacySceneAliases,
  illustrationStatus:'ready',illustrationStatusNote:'本轮完成正文重写。沿用经来源归档的旧稿图片作情境参考，非新稿逐场新绘；不符的三场主图和一幅结尾舟影暂缓，不让旧画改变新剧情。',
  characters:[
    {name:'郑芝龙／一官',role:'历史人物，主角；不锁定有争议的生年与早年确切年龄',desire:'不再靠别人给一处船位活命，让自己与身边的人不被随意舍弃。',arc:'机敏、爱体面，也有救人的勇气；习惯先替别人应下，再靠把事做成来补解释。真实本领使这一招屡次奏效，损失则使他愈发要控制所有人的退路。降清不是忽然变蠢，是旧方法在新权力面前失败；个人缺陷不替代全部史因。'},
    {name:'田川氏／松',role:'历史人物；具体早年家庭、私生活及对白为创作',desire:'经营可一起生活的家，同时保有自己的知情与决定。',arc:'主动与一官成家、出钱租屋、同样向往好日子；她不预知丈夫全部败局，也不能用忍耐让他改变。送子与渡海都是真决定，最后留箱仍有爱，不以预言或训诫赢得道德胜利。'},
    {name:'福松／郑森／郑成功',role:'历史人物；1624出生、1630赴明、1638县学、1644太学、1645赐姓改名',desire:'幼时认父，成年后承担自己领受的名分与责任，不只做被接走的人。',arc:'父亲的庇护、财力与教育都真实有益；他也从这些书、账和承诺中学会问父亲不愿回答的问题。1646拒随有长期积累，不用重复未亲历的澳门台词来完成精神独立。'},
    {name:'杜七',role:'原创海上盟友，与真实人物无一一对应；顺生为船名',desire:'自己领船、兑现伙伴之间的平等与回援，也争自己的利。',arc:'会分赃、抢货，也交出真本钱救一官。误信让恩情加深，揭密使亲密不能恢复；1628失左手，后来仍可能劫错人，最终失船存活，不靠壮烈一死被洗白。'},
    {name:'林阿旺',role:'原创船匠与舵工，阿禾叔父',desire:'凭手艺养人，知道自己掌的船会把谁带到哪里；晚年回女儿身边住下。',arc:'被救后肯共患难，却非无限保人。他既会在压力中沉默，也渐渐坚持掌舵者的判断。1646提箱回家，终止了总被下一航推迟的承诺。'},
    {name:'林阿禾',role:'原创水手；1621约13，1626约18，1628约20',desire:'从被准许上船的孩子成为能对人负责、也能拒绝调遣的船工。',arc:'见证撤援，受伤后依赖叔父、药钱与同伙，不敢说出真相；隐瞒的责任首先属于作决定和施压的成年人。重见援旗使沉默破裂，随后搜救和留海是自己承担，不等于原谅。'},
    {name:'陈添',role:'原创伙计、书记与传话者',desire:'不失差事、不当败局的替罪者，也不愿眼看旧事重演。',arc:'从解缆到假传、改写航记，逐步参与谎言；不是口误造成偶然惨祸。后来坚持损船与死伤都报、未到的人不算齐，没有一场忏悔便抵销旧债。'},
    {name:'郑芝虎',role:'历史人物；具体手足互动与搜索场面为创作',desire:'在兄长的事业中有所作为，也按自己的急与勇行事。',arc:'先有拌嘴、护衣、吃饭和战场配合，1635未归才有具体失落。死亡方式不拍定；其损失推动芝龙控制亲人，但不把创伤写成免罪理由。'},
    {name:'阮老六',role:'原创海盗头目',desire:'靠地利、武力与别人急着赶路谋利。',arc:'看穿旧筹与假旗，败后活逃，知道一官候抚缺粮便设空米船局；不是每章重置的愚蠢敌人。'},
    {name:'黄程',role:'有来源的澳门亲族接引者；本剧交易、对白为F',desire:'给亲族机会，但不无限替错误承担损失。',arc:'不因救人便抹去先前越权，也不将青年永远逐出门；明确契约使一官第一次拿自己的未来而非别人手艺作押。'},
    {name:'李旦、颜思齐；蔡善继、熊文灿；许心素、刘香；荷方公司及华商代理',role:'历史网络、官员、对手和机构背景；代理等为合成人物',desire:'各有商路、部众、职务与政治利益，不以国籍或官盗名号给出统一性格。',arc:'不扩成一次性奇遇主角。具体私人暗谋、索酬、劫货与家中场景不据机构史自动成立；史实与F见逐场注。'}
  ],acts,
  plotThreads:[
    {name:'话与舌头',plant:'1.1误译后补救，不肯完整认错；2.2以个人名义保证收帆平安。',payoff:'3.3假传、3.4用陈添背书；4.2承认延迟到伤害再次发生；5.2陈添改报实话，5.4不把不愿随行者凑齐。最终芝龙自己的承诺无人接回。'},
    {name:'缺口木筹、援旗与令旗',plant:'1.4交钱换一次退路；2.3争共同决定；3.2定三起援旗。',payoff:'3.3眼见不救，4.2晴天重缝援旗揭密；4.3以写明不调走的四艇兑现一次约定，仍有人死；5.1买旗者仍可失船，5.4对清营的通行纸失去效力。'},
    {name:'歪船图：传递必须可追踪',plant:'2.1田川氏画无帆船身；2.4包过挪用的家用后，图随无银的信寄回平户。',payoff:'4.3福松添帆带来安平，父亲保留；5.3田川氏重见图纸与银渍；5.4芝龙收在衣袋北行。图在纸上合拢，人的选择不能被折进去。'},
    {name:'箱子：货、工具与家的边界',plant:'1.1重箱致险，1.2抛货救人后险扣阿旺工具；3.3阿旺弃工具箱腾救人位置。',payoff:'4.3父子推重箱相认，5.2保留旧箱并以书填满；5.4妻子拆回自己行李，阿旺工具箱到女儿家。箱子可以搬，不等于人已答应。'},
    {name:'教育不是服从的抵押',plant:'4.3父亲教森字，希望儿子不再讨船位。',payoff:'5.1学会看账，5.2县学到太学后追问责任，5.3对自己派人的承诺负责，5.4承认父亲供养却拒随。儿子的政治道路不写成父亲授予的终极奖励。'}
  ],
  ending:{fixed:'1646郑芝龙降清后被挟北上，郑成功不从，田川氏罹难；郑芝龙1661遇害。家中对话、拒行和道具均F，不能替代复杂政治史或证明具体死法。',personal:'杜七失船而活，阿禾留海但不恢复旧信任，陈添按实报名；阿旺回女儿家住下。谁的选择都不替主角完成一种体面的赎罪。',lastImage:'起毛的歪船图随芝龙北行；另一处屋檐下，阿旺把漏风的门修好，没有再许下一航。'},
  sourceNotes:[
    '本稿采用用户指定的唯一主脑、缺陷在压力下显露、伏笔信息差、不可逆代价与终局回扣作为写作约束；它们不是文学评分公式。单一英雄旅程不是所有经典的唯一结构，多巴胺/内啡肽二分也不作为本项目已证实的审美神经科学结论。',
    '顺生真相在1626隐瞒，1628厦门战才揭露；修正用户示范中“三天后自白”与延迟引爆的冲突，以及两年误作三年的笔误。',
    '海上谋生与受压是本剧选择的从盗因果，不宣称为郑芝龙可唯一证实的心理。船、人、粮、潮、信用各有限制；首次夺船与各原创战事均F。',
    '本轮只重写文学主线与独立网页，不把章节阅读器当成Godot游戏已接入的新任务线。旧43场ID保留重定向，原资源与UI演示的旧需求不等于新20场仍有这些情节。',
    '本轮没有新生成图片。合宜旧图标为情境参考；雾中撤援、1636后令旗案与太学三场旧图不符，暂停显示；结尾旧孤舟图也暂停，避免把赴福州和被挟北上混成自愿航程。'
  ]
};
const output=path.join(root,'docs/narrative/zheng-zhilong-story.json');
fs.writeFileSync(output,JSON.stringify(story,null,2)+'\n');
console.log(JSON.stringify({file:output,acts:acts.length,scenes:scenes.length,bodyCharacters:scenes.reduce((n,s)=>n+s.paragraphs.join('').length,0),paragraphs:scenes.reduce((n,s)=>n+s.paragraphs.length,0),aliases:Object.keys(legacySceneAliases).length}));
