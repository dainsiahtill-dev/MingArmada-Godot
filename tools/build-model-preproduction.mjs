import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

// Independent, additive audit. Never rewrites the legacy production catalog or story.
const root = process.cwd();
const doc = 'docs/production/model-preproduction-2026-10-24';
const assetRoot = 'assets/production/model-kit-v1';
const read = p => JSON.parse(fs.readFileSync(p, 'utf8'));
const write = (p, text) => { fs.mkdirSync(path.dirname(p), {recursive:true}); fs.writeFileSync(p, text); };
const json = (p, data) => write(p, JSON.stringify(data, null, 2) + '\n');
const hash = p => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const storyPath = 'docs/narrative/zheng-zhilong-story.json';
const legacyPath = 'docs/design/game-ui/production-assets.json';
const catalogPath = 'assets/production/catalog.json';
const story = read(storyPath), legacy = read(legacyPath), catalog = read(catalogPath);
const scenes = story.acts.flatMap(a => a.scenes);
const retired = ['head-ahe-child','head-ahe-adult','head-chentian','head-duqi','head-ruan'];
const groups = {'船舶':'ships','人物身体与头部':'characters','独立服装与配件':'garments','港口与室内模块':'buildings','自然环境陈设':'environment','货物与生活道具':'props','武器与船具':'weapons'};
const additions = [
  ['head-li-dan','李旦头部','人物身体与头部'],
  ['head-xu-xinsu','许心素头部','人物身体与头部'],
  ['head-zhong-bin','钟斌头部','人物身体与头部'],
  ['head-hans-putmans','普特曼斯头部','人物身体与头部'],
  ['head-zheng-zhihu','郑芝虎头部','人物身体与头部'],
  ['head-zheng-hongkui','郑鸿逵头部','人物身体与头部'],
  ['head-longwu','隆武帝头部','人物身体与头部'],
  ['head-huang-daozhou','黄道周头部','人物身体与头部'],
  ['head-bolo','博洛头部','人物身体与头部'],
  ['head-chen-qian','陈谦头部','人物身体与头部'],
  ['garment-scholar','明末士人便服','独立服装与配件'],
  ['garment-japan-male','早江户平户男子生活衣','独立服装与配件'],
  ['garment-early-qing','1646清方军人衣甲','独立服装与配件'],
  ['gun-folangji','佛朗机炮身','武器与船具'],
  ['gun-swivel-mount','叉式旋架与甲板座','武器与船具'],
  ['gun-folangji-chamber','佛朗机可见子铳','武器与船具'],
  ['firearm-matchlock','长火绳枪','武器与船具'],
  ['weapon-spear','守船长枪','武器与船具'],
  ['weapon-longblade','接舷长刀','武器与船具'],
  ['gun-tool-set','炮组长杆工具组','武器与船具'],
  ['prop-toolbelt','船匠工具带','货物与生活道具'],
  ['prop-grapnel','接舷挠钩','货物与生活道具'],
  ['prop-boarding-plank','登离船跳板','货物与生活道具'],
  ['prop-compass','航海罗盘候选','货物与生活道具'],
  ['prop-pouch','布钱袋与药囊共享软袋','货物与生活道具'],
  ['prop-money-set','铜钱与银币银块组','货物与生活道具'],
  ['prop-command-flag','航海号令旗布面与旗杆','货物与生活道具'],
  ['prop-gong','铜锣','货物与生活道具'],
  ['prop-torch','照明火把','货物与生活道具'],
  ['prop-paper-lantern','早江户生活纸灯候选','货物与生活道具'],
  ['prop-timber-stock','修船木料组','货物与生活道具'],
  ['prop-iron-stock','铁料货组','货物与生活道具'],
  ['prop-scissors','剪刀','货物与生活道具'],
  ['prop-steelyard','验货杆秤','货物与生活道具'],
  ['tool-punt-pole','撑船篙','武器与船具'],
  ['building-japan-panel','平户木板与格栅墙模块','港口与室内模块'],
  ['building-japan-roof','平户住宅轻屋顶模块','港口与室内模块'],
  ['building-fort-wall','港防土石砖墙模块','港口与室内模块'],
  ['building-fort-gate','港防出入口模块','港口与室内模块'],
];
const reserveHeads = [
  ['head-li-guozhu','李国助头部'],['head-de-witt','德·维特头部'],
  ['head-xiong-wencan','熊文灿头部'],['head-li-kuiqi','李魁奇头部'],
  ['head-liu-xiang','刘香头部'],['head-guo-bichang','郭必昌头部'],
  ['head-tagawa-shichizaemon','田川七左卫门头部'],
];
const oldToNew = {'prop-red-thread-pouch':'prop-pouch','prop-money-pouch':'prop-pouch','prop-medicine':'prop-pouch','prop-punt-pole':'tool-punt-pole'};
const base = legacy.models.filter(m=>!retired.includes(m.id)).map(m=>({...m, scope:'production', origin:'legacy-retained', legacyStoryRefs:m.storyRefs, storyRefs:[], notes:[...(m.notes||[]),'旧预算保留项；不是既有形制已通过审定的声明。']}));
for(const [id,name,category] of additions) base.push({id,name,category,scope:'production',origin:'audit-addition',variants:[],notes:[]});
for(const [id,name] of reserveHeads) base.push({id,name,category:'人物身体与头部',scope:'reserve',origin:'current-mentioned-identity',variants:[],notes:['角色表身份；当前正文没有直接在场，不据此增加主线出演。']});
base.push({id:'firearm-short-matchlock',name:'短火绳枪待证候选',category:'武器与船具',scope:'reserve',origin:'legacy-history-pending',variants:[],notes:['旧稿明确物件，现稿未确认；须找到时间地域合适实物才决定是否制作。']});

const characterRows = [
  ['zheng','郑芝龙','head-zheng','production','郑芝龙|一官|芝龙','young adult and middle-aged, Fujian seafarer to Ming officer; same identity, no Qing queue in Ming scenes'],
  ['tagawamatsu','田川氏','head-tagawamatsu','production','田川氏','Japanese Hirado woman, early1620s then1645 middle age, small-sleeved kosode and modest narrow sash, no late Edo obi or geisha styling'],
  ['chenggong','郑成功','head-chenggong','production','福松|郑森|成功','Fujian educated young man in1644-1646, hair in Ming topknot, restrained scholar clothing, no later Qing portrait costume'],
  ['li-dan','李旦','head-li-dan','production','李旦','older Chinese merchant in Hirado c1623, sober good cloth robe, no invented official rank badge'],
  ['xu-xinsu','许心素','head-xu-xinsu','production','许心素','Fujian merchant intermediary1627, mature, practical robe, no fantasy pirate uniform'],
  ['zhong-bin','钟斌','head-zhong-bin','production','钟斌','Chinese armed merchant captain1630, sturdy working layers and modest protection, no stereotyped criminal markers'],
  ['hans-putmans','普特曼斯','head-hans-putmans','production','普特曼斯','Dutch VOC official1633, restrained dark doublet and knee breeches, falling linen collar, unpowered natural posture; no18c tricorne'],
  ['zheng-zhihu','郑芝虎','head-zheng-zhihu','production','芝虎','Chinese maritime commander1630s, practical padded protection over working layers, not flamboyant imperial armour'],
  ['zheng-hongkui','郑鸿逵','head-zheng-hongkui','production','鸿逵','Ming military commander1645, practical lamellar or padded protection candidate, distinctive silhouette, no Qing queue'],
  ['longwu','隆武帝','head-longwu','production','朱聿键|隆武帝|唐王','Southern Ming ruler1645, restrained informal court robe reconstruction, costume rank details require review, no Qing court beads'],
  ['huang-daozhou','黄道周','head-huang-daozhou','production','黄道周','elderly late Ming scholar official1645, lean face and plain scholar layers, not Qing mandarins'],
  ['bolo','博洛','head-bolo','production','博洛','Qing Manchu commander1646, early Qing riding robe and appropriate hairstyle, restrained military silhouette, not18c imperial parade robes'],
  ['chen-qian','陈谦','head-chen-qian','production','陈谦','Ming envoy and military officer1645-46, travel robe, dignity rather than costume ornament'],
  ['awang','阿旺','head-awang','production','阿旺','fictional ordinary Fujian sailor1620s, working tunic, sunworn skin, independent personality; do not import old Lin family biography'],
  ['li-guozhu','李国助','head-li-guozhu','reserve','李国助','Chinese maritime merchant,1620s-30s Hirado trade network'],
  ['de-witt','德·维特','head-de-witt','reserve','德·维特','Dutch VOC official1620s, sober doublet and breeches, not18c uniform'],
  ['xiong-wencan','熊文灿','head-xiong-wencan','reserve','熊文灿','Ming provincial official1628, dated Ming robe and winged official cap candidate'],
  ['li-kuiqi','李魁奇','head-li-kuiqi','reserve','李魁奇','Chinese armed merchant captain1629, practical deck clothing'],
  ['liu-xiang','刘香','head-liu-xiang','reserve','刘香','Chinese maritime rival1630s, differentiated face not demonized villain costume'],
  ['guo-bichang','郭必昌','head-guo-bichang','reserve','郭必昌','Quanzhou local gentry1646, plain literati robe'],
  ['tagawa-shichizaemon','田川七左卫门','head-tagawa-shichizaemon','reserve','七左卫门','younger son remains Japan, age staged from story rather than invented fixed age'],
];
const characters = characterRows.map(([id,name,head,scope,aliases,brief])=>({id,name,head,scope,brief,appearance:scope==='production'?'direct-presence-research-audit':'mentioned-or-mediated',sceneMentions:scenes.filter(s=>new RegExp(aliases).test(s.paragraphs.join('\n'))).map(s=>s.id),portraitStatus:'creative-reconstruction-not-verified-likeness'}));
const people = new Set(base.filter(m=>['characters','garments'].includes(groups[m.category])).map(m=>m.id));
const jobs = [];
const addJob = (id,title,group,covers,brief,scope='production') => jobs.push({id,title,group,scope,covers,brief,requiredViews:group==='characters'?['front','profile','rear','head-detail']:['front','side','rear','top'],imagePath:`${assetRoot}/${group}/${id}/multiview-v1.png`,status:'not-generated'});
for(const m of base.filter(m=>!people.has(m.id))) addJob(m.id,m.name,groups[m.category],[m.id],m.notes.join(' '),m.scope);
for(const c of characters) addJob(`char-${c.id}`,c.name,'characters',[c.head],c.brief,c.scope);
addJob('char-fusong-child','福松幼年（约6岁）','characters',['head-fusong-child','body-child'],'The same Zheng family child c1630, age six, natural child proportions, clothed in plain period layers; no scaled-down adult anatomy.');
addJob('body-adult-male','成年男性服装适配基体','characters',['body-adult-male'],'Adult male neutral A-pose, clothed in simple period underlayers; anatomy reference, front side back, no modern underwear.');
addJob('body-adult-female','成年女性服装适配基体','characters',['body-adult-female'],'Adult female neutral relaxed A-pose, plain modest opaque underrobe; front side back, no nudity.');
addJob('npc-eastasia','普通东亚水手头部','characters',['head-eastasia-male'],'Individual ordinary Fujian deck worker, varied plausible face rather than racial caricature, plain work clothes.');
addJob('npc-european','普通欧籍水手头部','characters',['head-european-male'],'Individual ordinary17c Dutch seafarer, linen shirt and plain breeches, no pirate tricorne.');
addJob('npc-regional','区域商路水手头部','characters',['head-regional-male'],'Individual Malay coastal trading sailor, specific regional clothing still needs source review; do not infer ethnicity from language.');
for(const m of base.filter(m=>groups[m.category]==='garments')) addJob(m.id,m.name,'garments',[m.id],'Clothing object turnaround on a simple neutral mannequin; show front side rear and one seam/closure detail. Distinguish garment from body mesh.');

const componentExtras = [
  ['prop-cooking-hearth','船岸小灶/安全炉台','生活空间中的锅不能悬放；先核具体场景和火灾限制。'],
  ['prop-anchor-rig','锚、滑轮、绞盘、舵与帆索','船体资源的可拆子件清单；沿各船型细分，不另重复计入当前整船制作项。'],
  ['prop-ledger-seal','账册、砚笔与印盒','UI/剧情桌面陈设，先利用纸张/书册和容器部件；若近景独立交互再拆新模。'],
];
const scenePackages = [
  ['scene-open-sea','外海与海战','海面、海天、天气、既有船资源装配，海水不是静态模型。'],
  ['scene-shipboard','甲板与有限船舱','各船模型的可用区域与内景替身，不按每场增加新船。'],
  ['scene-hirado-port','1620年代平户唐船泊处','木屋、石阶、仓栈；禁止提前使用1639荷兰石仓。'],
  ['scene-hirado-home','平户家居','早江户住宅模块组合；不照搬后来纪念馆的所有细节。'],
  ['scene-dayuan-1624','1624—25大员泊地','按工事发展阶段；不能使用1634完工堡垒全貌。'],
  ['scene-fujian-harbor','福建工作港/厦门港','仓栈、船坞、岸防、码头和港火状态。'],
  ['scene-fujian-hidden','闽海锚地','礁岸、临时棚、有限补给设施。'],
  ['scene-anping-house','安平家宅','门廊、前院、家庭室内，非整城漫游。'],
  ['scene-liaoluo','料罗湾','地形/舰阵/火船配置，非一艘独立新火船底模。'],
  ['scene-tianweiyang','田尾洋战后','搜索艇、破船木、低照明与漂流状态。'],
  ['scene-nanjing','南京求学差异包','国子监/城景只按剧情可见范围制作，不虚报完整南京城。'],
  ['scene-fuzhou-court','福州议事与行在','堂屋装配与仪仗道具，非重复整套住宅模型。'],
  ['scene-grain-road','闽北运粮山路','道路、担架/担子/牲口仍需镜头与玩法范围二次审核。'],
  ['scene-fuzhou-qing','1646福州清营与羁留处','同地区建筑换装配/人员与警戒配置；不默认新建一整城。'],
];
for(const m of base) {
  m.group = groups[m.category];
  m.artJobs = jobs.filter(j=>j.covers.includes(m.id)).map(j=>j.id);
  m.assetDirectory = `${assetRoot}/${m.group}/${m.id}`;
  m.historyStatus = m.group==='characters'?'identity-known-face-reconstructed':'evidence-and-shape-review-required';
  m.research = `${doc}/research-${m.group==='ships'||m.group==='weapons'?'ships-weapons':m.group==='characters'||m.group==='garments'?'characters-clothing':'environment-props'}.md`;
  m.originalRequirements = catalog.items.filter(i=>i.legacyModelIds.includes(m.id)||i.id===(oldToNew[m.id]||m.id)).map(i=>i.id);
  m.sketchStatus = m.artJobs.some(id=>fs.existsSync(jobs.find(j=>j.id===id).imagePath))?'generated-review-required':'not-generated';
  json(`${m.assetDirectory}/model-brief.json`,m);
}
for(const j of jobs) {
  const resultPath = `${assetRoot}/${j.group}/${j.id}/generation.json`;
  if(fs.existsSync(j.imagePath)) { j.status='generated-review-required'; j.sha256=hash(j.imagePath); }
  if(fs.existsSync(resultPath)) j.generation=read(resultPath);
  json(`${assetRoot}/${j.group}/${j.id}/art-brief.json`,j);
}
const baseIds = new Set(base.map(m=>m.id));
const requirementAudit = catalog.items.map(i=>({id:i.id,name:i.name,category:i.category,oldModelIds:i.legacyModelIds,newModelIds:[...new Set(i.legacyModelIds.filter(id=>baseIds.has(id)).concat(baseIds.has(i.id)?[i.id]:[],oldToNew[i.id]?[oldToNew[i.id]]:[]))],disposition:i.category==='named-character'?(characters.some(c=>i.name.includes(c.name)||c.name.includes(i.name))?'current-identity-review':'legacy-not-auto-current'):['scene-map'].includes(i.category)?'scene-or-2d-not-base-model':['npc-archetype'].includes(i.category)?'shared-body-costume-assembly':'retained-or-shared-shape-review',note:'原链接为旧稿映射，不能当作新稿出演证明。'}));
const manifest = {
  schemaVersion:1,date:'2026-10-24',scope:'historical-model-preproduction',
  countingRule:'基础模型制作项（整船/独立部件/共享身体/头部/衣装）。不等同Blender对象数、唯一网格数、GLB数或LOD交付数。场景、职业配置、材质变体另外登记。',
  inputFiles:[storyPath,legacyPath,catalogPath].map(p=>({path:p,sha256:hash(p)})),storyVersion:story.version,
  summary:{legacyRequirements:catalog.items.length,legacyBaseItems:legacy.models.length,retiredLegacyHeads:retired.length,models:base.length,production:base.filter(m=>m.scope==='production').length,reserve:base.filter(m=>m.scope==='reserve').length,characters:characters.length,directCharacters:characters.filter(c=>c.scope==='production').length,scenePackages:scenePackages.length,artJobs:jobs.length,generatedImages:jobs.filter(j=>j.status!=='not-generated').length},
  models:base,characters,artJobs:jobs,retired:retired.map(id=>({id,reason:'旧虚构角色头部，当前22章未沿用；保留旧文件，不删除。'})),
  requirements:requirementAudit,
  scenePackages:scenePackages.map(([id,name,note])=>({id,name,note,status:'layout-not-generated'})),
  unresolvedComponents:componentExtras.map(([id,name,note])=>({id,name,note,status:'scope-review'})),
  limits:['当前预算是前期制作基线，图像审定和镜头拆解可能增加/合并模型项。','面貌、尺寸与无法找到同期原件的结构为创作推定。','草图未过逐视图一致性与历史审查，不作为可直接照造的精确蓝图。','旧原版提取模型不等于商业分发已获授权。','未开展新Blender建模或Godot导入/性能验收。'],
};
json(`${doc}/manifest.json`,manifest);
json(`${doc}/art-jobs.json`,jobs);
write(`${doc}/data.js`,`window.MODEL_PREPRODUCTION=${JSON.stringify(manifest)};\n`);
const csv = [['ID','名称','类别','范围','草图状态','资源目录','研究文档'],...base.map(m=>[m.id,m.name,m.category,m.scope,m.sketchStatus,m.assetDirectory,m.research])].map(row=>row.map(x=>'"'+String(x).replaceAll('"','""')+'"').join(',')).join('\r\n');
write(`${doc}/model-register.csv`,'\uFEFF'+csv);
write(`${doc}/README.md`,`# 历史模型前期资源台账\n\n当前故事：${story.version}；${scenes.length}章。\n\n## 计数\n\n- 旧需求包${catalog.items.length}项、旧预算${legacy.models.length}项；不覆盖旧件。\n- 新制作基线${manifest.summary.production}项，预备${manifest.summary.reserve}项；合计${base.length}项。不是唯一网格数。\n- 当前21个人物身份，14人直接在场；7人预备。\n- 场景装配${scenePackages.length}包，不能加进独立模型总数。\n- 多视图计划${jobs.length}张，已生成${manifest.summary.generatedImages}张；生成不等于审定。\n\n## 审阅入口\n\n[图文目录](index.html) · [完整JSON](manifest.json) · [CSV](model-register.csv) · [绘图任务](art-jobs.json)\n\n## 考据\n\n[船舰兵器](research-ships-weapons.md) · [人物衣装](research-characters-clothing.md) · [建筑器物](research-environment-props.md)\n\n## 制作顺序\n\n史料/剧情对照 → 多视图 → 逐方向一致性复核 → 比例/尺寸设计 → Blender灰模 → 材质/骨骼/LOD → Godot导入与运行验收。\n\n本轮只到草图与考据。每项的model-brief.json、art-brief.json与generation.json分别记录需求、绘图覆盖和实际生成。旧炮模型仍为流程试验。\n\n## 仍需范围决策\n\n船具可拆清单、运粮牲口/担具等应按实际可见镜头继续拆解；不在未审定时伪称穷尽未来全游戏。罗盘、短铳、部分旗号/武器包装须进一步核形制。\n`);
console.log(JSON.stringify(manifest.summary,null,2));
