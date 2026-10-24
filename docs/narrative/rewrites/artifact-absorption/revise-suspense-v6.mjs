import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..');
const target = path.join(root, 'docs/narrative/zheng-zhilong-story.json');
const directory = path.dirname(fileURLToPath(import.meta.url));
const source = fs.readFileSync(target);
const story = JSON.parse(source);
if (story.version !== 'v5-five-act-rewrite-2026-10-22') throw new Error('This migration only accepts the frozen v5 source; do not overwrite later edits.');
const backup = path.join(directory, 'baseline-v5-story.json');
if (!fs.existsSync(backup)) fs.writeFileSync(backup, source);
const changes = [];
const scenes = new Map(story.acts.flatMap(a => a.scenes).map(s => [s.id, s]));
function replace(id, oldParagraph, newParagraph, reason, reference = null) {
  const scene = scenes.get(id), index = scene.paragraphs.indexOf(oldParagraph);
  if (index < 0 || scene.paragraphs.filter(p => p === oldParagraph).length !== 1) throw new Error(`Nonunique paragraph ${id}: ${oldParagraph.slice(0, 30)}`);
  scene.paragraphs[index] = newParagraph;
  changes.push({ sceneId: id, paragraph: index + 1, oldParagraph, newParagraph, reason, reference });
}
function match(id, prefix, newParagraph, reason, reference = null) {
  const candidates = scenes.get(id).paragraphs.filter(p => p.startsWith(prefix));
  if (candidates.length !== 1) throw new Error(`Nonunique prefix ${id}: ${prefix}`);
  replace(id, candidates[0], newParagraph, reason, reference);
}
function append(id, paragraph, reason) {
  const scene = scenes.get(id); scene.paragraphs.push(paragraph);
  changes.push({sceneId:id,paragraph:scene.paragraphs.length,newParagraph:paragraph,reason,reference:'chapter-suspense-revision'});
}

const referenceA = 'code_artifact.md';
for (const item of JSON.parse(fs.readFileSync(path.join(directory, 'act3-proposals.json'), 'utf8'))) {
  const paragraph = item.newParagraph.replace('掌柜将散户那半张托单往前一递：', '掌柜指着跳板边的女人：');
  replace(item.sceneId, item.oldParagraph, paragraph, item.reason, {file:referenceA,lines:item.sourceLines});
}
for (const item of JSON.parse(fs.readFileSync(path.join(directory, 'minimax-late-proposals.json'), 'utf8'))) {
  // The old tally is not made to reappear at the Qing camp merely to close a motif.
  if (item.sceneId === 'yiguan_a5_s4' && item.oldParagraph.startsWith('【福州')) continue;
  let paragraph = item.newParagraph;
  replace(item.sceneId, item.oldParagraph, paragraph, item.reason, {file:'一官入海-v6-完整故事文本.txt',lines:item.sourceLines});
}

match('yiguan_a1_s1', '阿旺低头看一眼阿禾留下的半双草鞋',
  '阿旺看一眼等工钱的脚夫，提起工具箱：“我先看船。缝若吃不住，两只重箱得留下。”一官转头催陈添拿装货单，答得很快：“先抬上去，旺叔再看。”箱子在人背上过了门，阿旺那句没答完的话被脚步盖住。他追到船边，逐处摸补缝，再叫把重箱压低。一官却已经站到船头点人。',
  '吸收参考稿中公开报工钱形成压力的长处，并把舵工的保留条件具体化；让越权发生在可见的装货动作中。', {file:referenceA,lines:[117,129]});
match('yiguan_a1_s2', '阿旺想把凿子留下',
  '阿旺从箱里拣出一把铁凿，说余下的先扣着，容他留下这一把去找活。管事伸手，老人便将凿子递过去，又在松开前停了一下。“没家伙，我拿什么还你？”管事只把箱盖掀得更开。一官在门边听着，手指绕住昨夜割下的断绳；阿旺的拇指仍按在凿柄磨亮的地方，没有再往回抽。',
  '把生计被扣写成递凿却不能松手的动作，保留赔付压力，不沿用踹箱与夸张存活时限。', {file:referenceA,lines:[179,196]});
match('yiguan_a1_s3', '他写了数，又擦去',
  '他写了数，又擦去，算到窗纸暗下来。纸上先写旧损、再写垫本，每笔都从自己的分成里扣。他在末尾补上一行“以本人所得偿之”，又将阿旺的工钱单推到契纸外面。黄程看了一遍，没有多压一成，也没少算一文。一官按好手印，抬头问船上缺不缺通译。舅父把契纸吹干：“有正经请的通译。你先洗桨、守夜。”',
  '吸收MiniMax由自己承担契约的具体笔迹，不采用错误字数计量或反复解释主脑。', {file:'一官入海-v6-完整故事文本.txt',lines:[199,209]});
match('yiguan_a1_s4', '远处传来日本近岸商船的号声',
  '入港前，管事把下一航留用的人逐一读给船工听。念完了，一官还站着，等自己的名字。管事将单子卷起：“你随的是黄掌柜送来的货，卸清便结这一程。返航的活有人了。”一官问还能不能做别的，对方指指岸上，说去别家问。阿旺过来接自己的工具，一官替他托住箱底；眼前的山已近了，哪一扇门能让他们过夜，他还不知道。',
  '以返程位置落空留下第一幕具体未决困境，下一幕立即用在平户找活及修屋回应，不靠新阴谋或空问号。');
const firstJapan = scenes.get('yiguan_a2_s1');
firstJapan.paragraphs.unshift('回程船卸完货开走，一官没追。阿旺与阿禾在码头问到补船的活，他沿货栈廊下挨户问有没有能做的工。吃住都须现钱，黄程那张契纸却没有因此少一行。他暂借一把锯，先答应替人修屋；主人指了指还在漏的檐角，说等水走对了地方，再给钱。');
changes.push({sceneId:firstJapan.id,paragraph:1,newParagraph:firstJapan.paragraphs[0],reason:'第一幕船位悬念的即时兑现：从无处落脚到必须凭手艺挣一处屋檐。'});
match(firstJapan.id, '平户下雨的日子',
  '平户下雨的日子，货栈廊下总有人等修屋漏。一官跟阿旺学的几手补缝，才在船上派过用场。他照着在底舱补木的办法钉了檐片，水没落在原地方，反从田川氏晾衣的竹竿上滴下来。',
  '新添落脚转场后，删去重复自荐修屋，让应聘与修坏连成一次行动。');
match('yiguan_a2_s1', '两个人成家时',
  '两个人成家时，一官拿不出置屋的钱。田川氏把自己攒的一小串钱放在桌上，说靠海的窄屋租价已问过，后间放活计，窗下能坐两个人。他先想把钱推回去，问可否等自己挣够。她没有把钱再推给他，只收起屋主写的地址：“那就等。屋子也许会先租给旁人。”他伸手拦住那张纸，停了一会儿，才说一起去看。',
  '吸收MiniMax让田川氏有自己的本钱与行动的长处，用租屋机会推动恋爱决定，删去两人抢着说我们等作者算盘。', {file:'一官入海-v6-完整故事文本.txt',lines:[302,310]});
match('yiguan_a2_s2', '大员的工钱不是上岸便结',
  '结账那日，两页货册只摊开了中文的一页。陈添写完脚钱与译费，等另一页对数，管货者却将它夹回桌内，说下一航一并结。一官用指头按住自己的姓名：“这一航做完了。”华商代理指指水口外还没收帆的唐船，让他先把那条船劝停；桌上的钱袋一直没有打开。',
  '吸收两页账册与扣酬的可见障碍，让劝停要求从拿不到的钱里生长，而非空泛的强权表情。', {file:referenceA,lines:[405,407]});
match('yiguan_a2_s2', '杜七站在艇上，见他迟疑',
  '杜七站在艇上，见他迟疑，又问了一遍：“到底查册，还是扣货？”一官回头，管货者已经示意人揭炮衣，代理却没给那张保证上一个字。他望向周船的帆，双手拢到嘴边：“先收帆！人过来验，我在这里，不伤你们。”杜七仍没叫艇离开，等着他把后半句说完；他只指向自己胸口，又喊了一遍。',
  '具体化承诺缺口与对方等待，保留一官只能保证不伤人的原话，避免参考中已保不夺货却被回复从没保货的对话错配。', {file:referenceA,lines:[413,425]});
append('yiguan_a2_s2', '索赔书写完，杜七让他把自己的那一联收好。次晨陈添送来退件，纸角添了一道墨杠，没有结钱的印。一官认得那道杠——自己等过几日工钱，等来的也是它。杜七在旁边看着，问这回还要等谁开口。',
  '让索赔失败成为下一场武装夺船的直接压力，回应本场担保能否兑现的悬念。');
match('yiguan_a2_s3', '周船主的索赔书被转回来了',
  '杜七将那张退回的索赔书摊在一官面前，签名还在，纸角的墨杠已经干了。华商代理只让来人带一句话：下次别妨碍做生意。杜七要直接夺回被扣的货，一官拦住：没有能走的船，抢到货也出不去。',
  '接续上一场退件，不重复投递一次；将夺船需要落在现实障碍上。');
append('yiguan_a2_s3', '陈添追上来，手里不是新的货单，是明日要发的工食。“船上的人还照今日算么？”一官接过那张纸，数到新船舱里留下的几个人，笔停了一下。快船已经归他，养这条船的钱却没有随舵绳一起交过来。',
  '将首次得船的胜利转为必须供养船员的现实压力，下一场合货与家用冲突因而必需。');
append('yiguan_a2_s4', '转年后的一夜，陈添来报一条红封舱的合货船明早要过水口，船行的私记与当初扣译费的是同一家。他把一直没结清的欠单也带来了。一官将信纸移开，把欠单铺在海图上，先问那船带了多少护卫。窗外杜七还在催着添淡水，听见这句话，慢慢停住了手。',
  '以可追索的欠款与具体来船承接第三幕，把读者期待从寄钱转为他将怎样取回钱；第三幕并不自动把夺回写成正义。');
append('yiguan_a3_s4', '来传话的小艇天黑才靠岸。陈添接过一封没有官印的信，信中说蔡公愿替海上诸人周旋，先请他们约束部众、暂避兵锋。一官读了两遍，问杜七走了没有。陈添说还在里屋。一官把信折好：“明早叫几条船的当家都来，商量这封信。”',
  '旧谎暂时保住联盟，新招抚邀约立即要求更大信任，形成第三幕到第四幕的真实新决定。');
match('yiguan_a4_s1', '使者来的那天',
  '那封邀信往返了几回，过了数月，使者才正式上船接洽。一官把碎舵叶从桌上移开，换上一块新布。杜七的伤手才勉强能握刀，便又得把刀放下。他问交到谁手里，一官说先封在自己船上，官船到后再验，免得交涉的人看见他们仍备着厮杀。阿旺问拿什么凭证，使者从袖里取出一封新信，仍没有官印。',
  '保留沉船养伤与招抚往返所需的时间；三幕收到邀信并不等于次日已经正式交刀。');
append('yiguan_a4_s4', '出入单誊清后，陈添问少爷是不是也该过目。一官已将印收进匣里：“给他照着走就是。”他把信封封好，压在报捷文书下面。两份纸一起送回安平，报捷文书张在前堂，另一份被管事收进册中。往后家人每次上船，先照这张单验人。',
  '将胜后控制变成送回家、下一幕必须面对的实际命令；悬念不止是旁白说性格转变。');

const dialogueRevisions = {
  yiguan_a3_s1: [
    ['一官','大员欠我的译费、脚钱，还有周老船主那两包生丝。只拿这些。'],
    ['阿旺','那就留在这里，去岸上对。'],
    ['一官','我们空着手到岸，他还会认我这张单？'],
    ['掌柜','我的货去哪儿领，我晓得。她也得借条艇，去外海找你？']
  ],
  yiguan_a3_s2: [
    ['杜七','下回是我掉在这里，你来不来？'],
    ['杜七','三起，求接人。不是叫你替我争货。'],
    ['一官','往后不管我押着什么货，你起这面旗，我回来接。'],
    ['阿旺','这些是他和老船员自己的本钱，不是公货。']
  ],
  yiguan_a5_s1: [
    ['郑森','不能按走几航算？'],['杜七','我的船，你替我结得倒快。'],
    ['郑森','这两张，也照册结么？'],['杜七','你父亲叫你送的？']
  ],
  yiguan_a5_s2: [
    ['陈添','报到您这儿的不是那几个字。'],['郑森','是您。所以我回来问您。'],
    ['芝龙','我眼下答不上来。'],['阿旺','掌舵的人得知道前头要把谁丢下。']
  ]
};
for (const [id, lines] of Object.entries(dialogueRevisions)) {
  scenes.get(id).dialogue = lines.map(([speaker,text])=>({speaker,text}));
}
Object.assign(scenes.get('yiguan_a1_s4').dramaticBeat,{
  result:'未救回路钱，也险将阿旺押出；留下旧木筹。抵港时才知自己不在下一航留用名单内。',
  next:'这一程的船位不能换来平户住处，他须从找活、挣租钱重新开始。'
});
Object.assign(scenes.get('yiguan_a2_s1').dramaticBeat,{
  obstacle:'远航佣工结这一程便散，普通工钱只能暂供吃住；武装通译酬高，却有未必能退出的风险。'
});
scenes.get('yiguan_a3_s4').dramaticBeat.next='真相暂被压住；一封无官印的招抚信到了，他召各船当家商议。数月往返后正式接洽，他将提出交刀这一更大的信任要求。';
scenes.get('yiguan_a4_s4').dramaticBeat.next='出入单发往安平并开始用来验人；下一幕阿旺的外岛修船差事被改到港内，控制扩及妻儿，最后被1646的拒绝击穿。';

const chapterHooks = [
  { readerHook:'码头第一次等他开口。他其实只听懂了两个词，却已替掌舵的人答应了夜航。', nextHook:'船到了平户，回程的名册却没有他的名字。岸上没有等他的屋子，他得先挣到明日的住处。', question:'失去别人给的船位后，他怎样在陌生海港活下去，又将拿什么换自己的位置？', payoff:['yiguan_a2_s1','yiguan_a2_s2','yiguan_a2_s3'] },
  { readerHook:'平户的窄屋刚能挡雨，一份酬钱更高的差事到了。没有写进家书的，是那条船上的炮。', nextHook:'寄给妻儿的银袋空了，那家扣过译费的船行却又驶进水口。这一次，他不打算只递一张索赔书。', question:'夺到船以后，他能否把家用和别人欠他的款取回来，又会越过谁的边界？', payoff:['yiguan_a3_s1','yiguan_a3_s2'] },
  { readerHook:'旧欠还没讨回，养船的账又到了。红封舱就在水口，舱里的货却不只属于欠钱的人。', nextHook:'顺生的事暂时没有再被问起。一封没有官印的招抚信到了，一官要先把几条船的当家请到一处。', question:'阿禾知道的旧事会在怎样的新危险里说破？新的官府承诺是否又由一官替别人答应？', payoff:['yiguan_a4_s1','yiguan_a4_s2'] },
  { readerHook:'刀已封好，官船迟迟不来。杜七仍同他出海，阿禾却开始替杜七看旗。', nextHook:'海上的船照他的号令排好了位置。送回家中的另一张名单，也已经替妻儿排好了路。', question:'当保护变成家里的出入名单，妻儿还能否自己决定要走的路？', payoff:['yiguan_a5_s1','yiguan_a5_s2','yiguan_a5_s4'] },
  { readerHook:'家人每次上船，都要先照新单验人。十二岁的郑森坐到船账旁，还不明白，护人的规矩能管到哪一步。', nextHook:'', question:'谁肯随行，谁决定留下？他的活路究竟有没有答应过他所需的条件？', payoff:['yiguan_a5_s4'] }
];
for (const [i,act] of story.acts.entries()) {
  Object.assign(act,{readerHook:chapterHooks[i].readerHook,nextHook:chapterHooks[i].nextHook});
  act.suspense={question:chapterHooks[i].question,payoffSceneIds:chapterHooks[i].payoff,scope:'editorial-only; not rendered as reader copy',type:['处境与前程','利益与道德边界','观众知情的长期隐瞒','保护异化为控制','多方抉择与失去议价'][i]};
}
const teasers = [
  ['一笔多出来的工钱，让所有人以为他听懂了。催货单这时到了。','他能否靠抢答得到船位，而不让掌船者替自己付账？','yiguan_a1_s2'],
  ['两只货箱已经沉了。天亮以后，货主要拿走的却是阿旺吃饭的家伙。','救人之后，他会不会认下导致这场险情的决定？','yiguan_a1_s3'],
  ['黄程肯给另一航的位置，先把未来三年的账推到了他面前。','拿自己的未来出资，究竟能换到什么位置？','yiguan_a1_s4'],
  ['去年买过的路，今年又要重买。阮老六偏偏有一条正在漏水的船。','他发现的弱点能谈价，还是会把同伴押出去？','yiguan_a2_s1'],
  ['雨从他修过的地方落到了她的衣裳上。这一回，她等他把活做完。','这个家能否由两个人共同决定，而不是靠一句保证？','yiguan_a2_s2'],
  ['工钱还锁在另一页账里。他得先去劝一条唐船落帆。','他用自己名义作的保证，持炮的人肯不肯认？','yiguan_a2_s3'],
  ['索赔书退了回来，阮老六又要路钱。两个人终于肯把自己的银子摆到一起。','诱局失算时，两船约好的配合能否赶到？','yiguan_a2_s4'],
  ['报生的信到了，归船也有了。偏在这时，两船合货还缺一份现银。','他已经答应的归期，会不会又让位给下一航？','yiguan_a3_s1'],
  ['扣过译费的私记就在舱门上。陈添抽出的托单，却不只一个货主。','他要追的旧欠，会不会从别人的生计里讨回来？','yiguan_a3_s2'],
  ['没有风，水只够到明日午前。岸上有人放话，肯用现银收货。','缺水的两船拿什么换出路，信谁又要付什么价？','yiguan_a3_s3'],
  ['援旗已经升了三次。阿旺看不见左翼，还在等他回答。','他怎样选择，谁亲眼知道，谁会相信之后的航记？','yiguan_a3_s4'],
  ['杜七带着碎舵叶进门，先问接人的艇为什么掉了头。陈添端水的手停住了。','杜七能否问到真话，阿禾能否在依附中说出来？','yiguan_a4_s2'],
  ['信上没有官印，来人还没把条件说完，一官已请众人交刀。','没到手的招抚能让人等多久，失信以后谁还跟他走？','yiguan_a4_s2'],
  ['这天没有雾。阿禾重新升起赭黄援旗，远处的接应艇却仍守着狭口。','同样的援旗再次出现，旧谎还能不能继续？','yiguan_a4_s3'],
  ['厦门泊地先起了火。再集船时，阿禾先问：救人的艇会不会又被调走？','这一次写下的接应安排能否兑现，兑现后又是否无人付价？','yiguan_a4_s4'],
  ['捷报已经备好，回信的小牌却还少一块。一官让众船暂缓回岸。','能号令众船的人，能不能把未归的弟弟找回来？','yiguan_a5_s1'],
  ['杜七拿着买过令旗的凭据，来讨被扣下的船。少年郑森在旁边翻账。','买过保护的人为何仍失船，少年会怎样理解父亲的公道？','yiguan_a5_s2'],
  ['父亲送他读书，也替他备了一张应当结交谁的名单。','被供养的人，能不能用学来的道理作自己的决定？','yiguan_a5_s3'],
  ['田川氏终于下船，先问福松在哪儿。走来的青年，已经有了另一个名字。','相认以后，还能否回到一同过日子、共同作答的关系？','yiguan_a5_s4'],
  ['箱子已经扎好，随行名单也已誊清。田川氏的手却按住了箱盖。','一条由家主排好的活路，哪些人会拒绝，对方又会承认多少？','yiguan_a5_s4']
];
for (const [index,scene] of [...scenes.values()].entries()) {
  scene.readerTeaser=teasers[index][0];
  scene.suspense={question:teasers[index][1],payoffSceneIds:[teasers[index][2]],status:'editorial-plan-with-written-payoff'};
}
const payoffLocations = [
  ['yiguan_a1_s1','yiguan_a1_s2'], ['yiguan_a1_s2','yiguan_a1_s3'],
  ['yiguan_a1_s3','yiguan_a1_s4','yiguan_a2_s1'], ['yiguan_a1_s4'],
  ['yiguan_a2_s1','yiguan_a2_s2'], ['yiguan_a2_s2'], ['yiguan_a2_s3'], ['yiguan_a2_s4','yiguan_a3_s1'],
  ['yiguan_a3_s1'], ['yiguan_a3_s2'], ['yiguan_a3_s3','yiguan_a3_s4','yiguan_a4_s2'], ['yiguan_a4_s2'],
  ['yiguan_a4_s1','yiguan_a4_s2'], ['yiguan_a4_s2','yiguan_a5_s1'], ['yiguan_a4_s3'], ['yiguan_a4_s4'],
  ['yiguan_a5_s1'], ['yiguan_a5_s2','yiguan_a5_s4'], ['yiguan_a5_s3','yiguan_a5_s4'], ['yiguan_a5_s4']
];
for (const [index,scene] of [...scenes.values()].entries()) scene.suspense.payoffSceneIds=payoffLocations[index];
story.acts[1].years='约1623—1625年初';
scenes.get('yiguan_a2_s4').year='1624年后段—1625年初';
story.subtitle='五幕二十场 · 悬念润色稿 · 1621—1646';
story.version='v6-suspense-integrated-2026-10-22';
story.narrativeContract.revision=6;
story.referenceAbsorption={
  date:'2026-10-22',method:'Selective action, subtext and chapter carry-forward revision; preserve history and the delayed reveal.',
  sources:[
    {path:'C:/Users/dains/Downloads/code_artifact.md',sha256:crypto.createHash('sha256').update(fs.readFileSync('C:/Users/dains/Downloads/code_artifact.md')).digest('hex'),author:'user supplied; model not attributed',coverage:'12 completed scenes and the opening of scene 13; incomplete'},
    {path:'C:/Users/dains/Downloads/一官入海-v6-完整故事文本.txt',sha256:crypto.createHash('sha256').update(fs.readFileSync('C:/Users/dains/Downloads/一官入海-v6-完整故事文本.txt')).digest('hex'),author:'MiniMax, as identified by user',coverage:'20 scenes and appendices'}
  ]
};
story.sourceNotes.push('2026-10-22择优吸收两份用户提供参考稿的动作、谈判障碍、照护与隐瞒并存的潜台词；逐章加入有正文兑现的未决问题。制作／伏笔解析默认折叠，不把后文结果放在公开引子里。');
fs.writeFileSync(target,JSON.stringify(story,null,2)+'\n');
fs.writeFileSync(path.join(directory,'applied-changes.json'),JSON.stringify({version:story.version,changes},null,2)+'\n');
console.log(JSON.stringify({version:story.version,bodyEdits:changes.length,chapterHooks:5,sceneTeasers:20,bodyCharacters:[...scenes.values()].reduce((n,s)=>n+s.paragraphs.join('').length,0)}));
