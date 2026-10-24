import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {storyStructure,aliasIssues} from './zheng-story-contract.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const out='docs/production/resource-library';
const library='assets/production';
const read=p=>JSON.parse(fs.readFileSync(path.join(root,p),'utf8'));
const write=(p,value)=>{fs.mkdirSync(path.dirname(path.join(root,p)),{recursive:true});fs.writeFileSync(path.join(root,p),typeof value==='string'?value:JSON.stringify(value,null,2)+'\n');};
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,p))).digest('hex');
const exists=p=>fs.existsSync(path.join(root,p));
const safe=p=>{if(typeof p!=='string'||p.includes('..')||path.isAbsolute(p)||/[:\\]/.test(p))throw new Error('Unsafe resource path: '+p);return p;};
const categoryInfo=[
 ['named-character','剧情人物','characters'],['npc-archetype','NPC职业原型','npcs'],
 ['ship','船型','ships'],['cannon','火炮与炮架部件','cannons'],['firearm','个人火器','firearms'],
 ['melee-weapon','冷兵器','melee-weapons'],['ammunition','弹药外观','ammunition'],
 ['building','建筑与构件','buildings'],['coastal-building','沿海设施','coastal'],
 ['scene-map','场景与地图','maps'],['nature','自然与材质条件','nature'],['prop','道具与货物','props']
];
const categories=new Map(categoryInfo.map(([id,name,folder])=>[id,{id,name,folder}]));
const legacy=read('docs/design/game-ui/production-assets.json');
const story=read('docs/narrative/zheng-zhilong/zheng-zhilong-story.json');
const scenes=story.acts.flatMap(a=>a.scenes);
const currentSceneMap=new Map(scenes.map(s=>[s.id,s]));
const structure=storyStructure(story),isRewrite=['five-act-rewrite','historical-reboot'].includes(structure.edition);
if(aliasIssues(story).length)throw new Error(aliasIssues(story).join('; '));
const baseline=read(`${out}/story-baseline-v4.json`);
const sceneMap=new Map((isRewrite?baseline.scenes:scenes).map(s=>[s.id,s]));
const narrativeScope=isRewrite?`资源需求保留自旧版六幕43场。链接只指向当前${structure.acts}部${scenes.length}章的相近历史阶段，不证明该物件或人物仍在新主线演出；逐项制作范围须另行复审。`:'当前六幕43场制作需求。';
const systems=read('docs/design/game-ui/systems.json');
const pages=new Map(systems.screenGroups.flatMap(g=>g.screens).map(p=>[p.id,p]));
const parts=['characters','environment','equipment'].map(n=>read(`${out}/parts/${n}.json`));
const items=parts.flatMap(p=>p.items);
const shipPictures={
 'ship-lighter':['docs/narrative/zheng-zhilong/images/film-v4/zheng_a1_s2.png','story-context'],
 'ship-fast-junk':['docs/design/game-ui/prototype/assets/fishing-ship.png','shape-reference'],
 'ship-merchant-junk':['docs/design/game-ui/prototype/assets/fuchuan-inspection.png','shape-reference'],
 'ship-fuchuan':['docs/design/game-ui/prototype/assets/fuchuan-inspection.png','dedicated-original'],
 'ship-rescue-skiff':['docs/narrative/zheng-zhilong/images/film-v4/zheng_a3_s3.png','story-context'],
 'ship-european-merchant':['docs/design/game-ui/prototype/assets/merchant-barque.png','dedicated-original'],
 'ship-european-warship':['docs/narrative/zheng-zhilong/images/film-v4/zheng_a5_s4.png','story-context'],
 'ship-regional-craft':['docs/narrative/zheng-zhilong/images/film-v4/zheng_a3_s10.png','story-context']
};
for(const m of legacy.models.filter(x=>x.category==='船舶')){
 const [picture,role]=shipPictures[m.id];
 items.push({id:m.id,name:m.name,category:'ship',phase:m.phase,assetKind:'ship-hull-family',modelRequired:true,
 description:m.notes.join(' ')||'船体、帆装与甲板挂点共享的船型资源，实例旗帜和损伤通过配置处理。',
 visualBrief:'船体水线、船首与船尾轮廓、帆装、舵桨和炮位须分别交代；本轮图像是形制参考，正式模型需三视图、比例和挂点复验。',
 storyRefs:m.storyRefs,uiPages:m.pages,variants:m.variants,modelStrategy:'沿用原船型基模预算；LOD不重复算船型。'+m.notes.join(' '),
 historicalStatus:'art-candidate-needs-review；原型美术与旧模型均不构成精确时代形制认证。',
 existingImages:[{path:picture,role,note:role==='dedicated-original'?'已有原创船型检视概念，非生产GLB。':'只参考关联剧情或邻近船型，不能把该图当成独立船型定稿。'}],
 existingModels:m.existing.filter(x=>/\.glb$/.test(x.path)).map(x=>x.path),legacyModelIds:[m.id]});
}
const generated=read(`${out}/generated-art.json`).entries;
for(const a of generated){
 write(`${path.dirname(a.path)}/art-provenance.json`,{...a,sha256:hash(a.path),role:'dedicated-concept',status:'concept-candidate-not-production-model',promptRecord:`${out}/generated-art.json`});
}
const sketches=['environment','equipment'].flatMap(n=>{const p=`${out}/parts/${n}-sketches.json`;if(!exists(p))return [];const x=read(p);return Array.isArray(x)?x:(x.entries||x.items||[]);});
const byId=new Map();
for(const i of items){
 if(i.id==='map-shipboard-mother')i.dependencies=[...new Set([...(i.dependencies||[]),'ship-fast-junk','ship-merchant-junk','ship-fuchuan','ship-european-merchant','ship-european-warship'])];
 if(i.id==='nature-island-terrain')i.dependencies=[...new Set([...(i.dependencies||[]),'nature-rock','nature-shore-materials','nature-ground-materials'])];
 if(byId.has(i.id))throw new Error('Duplicate ID '+i.id);
 if(!categories.has(i.category))throw new Error('Unknown category '+i.category);
 byId.set(i.id,i);
}
function copyReference(item,ref){
 const src=safe(ref.path);if(!exists(src))throw new Error(`Missing reference ${item.id}: ${src}`);
 const ext=path.extname(src),stem=path.basename(src,ext);
 const dest=`${item.assetDirectory}/reference/${stem}-${hash(src).slice(0,8)}${ext}`;
 fs.mkdirSync(path.dirname(path.join(root,dest)),{recursive:true});
 if(!exists(dest))fs.copyFileSync(path.join(root,src),path.join(root,dest));
 else if(hash(src)!==hash(dest))throw new Error('Reference copy differs: '+dest);
 return {...ref,path:dest,sourcePath:src,sha256:hash(dest),rights:src.includes('reference_')||src.includes('fidelity_')?'reference-only-review-required':'project-art-or-context-review-required'};
}
for(const i of items){
 i.categoryName=categories.get(i.category).name;
 i.assetDirectory=`${library}/${categories.get(i.category).folder}/${i.id}`;
 i.storyRefs=[...new Set(i.storyRefs||[])];i.uiPages=[...new Set(i.uiPages||[])];
 for(const s of i.storyRefs)if(!sceneMap.has(s))throw new Error(`Invalid story reference ${i.id}: ${s}`);
 for(const p of i.uiPages)if(!pages.has(p))throw new Error(`Invalid UI reference ${i.id}: ${p}`);
 i.dependencies=[...new Set(i.dependencies||[])];
 for(const d of i.dependencies)if(!byId.has(d))throw new Error(`Unknown dependency ${i.id}: ${d}`);
 i.images=(i.existingImages||[]).map(r=>copyReference(i,r));
 const art=generated.filter(g=>g.id===i.id||(i.id==='building-macau-warehouse'&&g.id==='building-warehouse-front')||(i.id==='gun-deck-carriage'&&g.id==='gun-light-muzzle'));
 for(const a of art){safe(a.path);if(!exists(a.path))throw new Error('Missing new art '+a.path);i.images.unshift({path:a.path,role:'dedicated-concept',note:a.reviewNote||'新生成并检查的独立概念候选；外观参考，不是实测图、史实肖像或完成模型。',sourcePath:a.source,promptId:a.id,sha256:hash(a.path),rights:'generated-project-concept'});}
 for(const s of sketches.filter(s=>s.id===i.id)){safe(s.path);if(!exists(s.path))throw new Error('Missing sketch '+s.path);i.images.push({...s,sha256:hash(s.path),rights:'project-authored-editable-diagram'});}
 // A six-person sheet is a dedicated reference only with the audited identity crop.
 const cropped=i.images.find(x=>x.cropNormalized);
 const original=i.images.find(x=>x.role==='dedicated-original'||x.role==='portrait-original'||x.role==='ui-portrait'||x.cropNormalized);
 const sketch=i.images.find(x=>x.role==='technical-sketch');
 const native=i.images.find(x=>x.role==='dedicated-concept');
 const object=i.images.find(x=>(x.role==='item-art'||/icon|dedicated|cutout|goods|ammo|portrait/.test(x.role||''))&&!/context/.test(x.role||''));
 i.primaryImage=native||original||object||sketch||i.images[0]||null;
 if(!i.primaryImage)throw new Error('No actual image for '+i.id);
 i.evidenceStatus=native?'dedicated-concept':(original||object)?'dedicated-original':sketch?'technical-sketch':'context-reference';
 i.conceptStatus=native?'concept-candidate':i.evidenceStatus==='dedicated-original'?'existing-original-review':sketch?'editable-sketch':'context-only-needs-independent-concept';
 if(i.id==='char-anton'&&native)i.visualBrief+=' 本轮新增吕宋本地水手独立候选；旧六人图的安东面貌仅保留为此前迭代证据，不作为当前首选。';
 i.imageCount=i.images.length;
 i.storyLinks=i.storyRefs.map(id=>{const target=isRewrite?story.legacySceneAliases[id]:id;return {id:target,title:currentSceneMap.get(target).title,...(isRewrite?{legacyId:id,legacyTitle:sceneMap.get(id).title,relationship:'rewrite-successor-not-confirmed-appearance'}:{})};});
 i.narrativeScope=narrativeScope;
 i.narrativeStatus=isRewrite?'legacy-requirement-needs-mainline-audit':'current-requirement';
 i.uiLinks=i.uiPages.map(id=>({id,title:pages.get(id).title}));
 write(`${i.assetDirectory}/asset.json`,i);
 write(`${i.assetDirectory}/README.md`,[
  `# ${i.name}`,`\n资源ID：\`${i.id}\` · ${i.categoryName} · ${i.phase}`,
  `\n${i.description}`,`\n## 视觉与结构\n\n${i.visualBrief}`,
  `\n## 制作与复用\n\n${i.modelStrategy}`,`\n${i.historicalStatus}`,
  `\n此目录是生产参考，不被Godot自动导入。需要运行时使用时另行经现有资产合同导出。`,
  `\n## 图片\n`,...i.images.map(x=>`- [${x.role}：${path.basename(x.path)}](${path.relative(i.assetDirectory,x.path).replaceAll('\\','/')}) — ${x.note||''}`),
  `\n## 关联\n\n${narrativeScope}\n\n旧稿需求出处：${i.storyRefs.join('、')||'UI系统需求'}\n\nUI：${i.uiPages.join('、')}`,
  `\n原始出处、图像哈希、依赖与旧基模映射见 [asset.json](asset.json)。`
 ].join('\n')+'\n');
}
const mapped=new Set(items.flatMap(i=>i.legacyModelIds||[]));
const missingLegacy=legacy.models.filter(m=>!mapped.has(m.id)).map(m=>m.id);
const invalidLegacy=[...mapped].filter(id=>!legacy.models.some(m=>m.id===id));
if(missingLegacy.length||invalidLegacy.length)throw new Error('Legacy coverage mismatch '+JSON.stringify({missingLegacy,invalidLegacy}));
const summary={total:items.length,categories:categoryInfo.map(([id,name])=>({id,name,count:items.filter(x=>x.category===id).length})),phases:Object.fromEntries(['P0','P1','P2'].map(p=>[p,items.filter(i=>i.phase===p).length])),legacyBaseModels:legacy.models.length,
 namedCharacters:items.filter(i=>i.category==='named-character').length,onScreenCharacters:items.filter(i=>i.category==='named-character'&&i.appearance==='on-screen').length,
 mentionedOnlyCharacters:items.filter(i=>i.appearance==='mentioned-only').length,npcArchetypes:items.filter(i=>i.category==='npc-archetype').length,
 cannonBarrelTypes:items.filter(i=>i.category==='cannon'&&!/carriage|mount|chamber/.test(i.id)).length,
 cannonComponents:items.filter(i=>i.category==='cannon'&&/carriage|mount|chamber/.test(i.id)).length,
 images:items.reduce((n,i)=>n+i.images.length,0),distinctImageFiles:new Set(items.flatMap(i=>i.images.map(x=>x.path))).size,
 distinctImageContents:new Set(items.flatMap(i=>i.images.map(x=>x.sha256))).size,
 archivedReferenceSources:new Set(items.flatMap(i=>i.images.filter(x=>x.role!=='dedicated-concept'&&x.role!=='technical-sketch').map(x=>x.sourcePath))).size,
 coveredStoryScenes:new Set(items.flatMap(i=>i.storyRefs)).size,coveredUiPages:new Set(items.flatMap(i=>i.uiPages)).size,
 currentScenes:scenes.length,legacyScenes:baseline.scenes.length,mappedSuccessorScenes:new Set(items.flatMap(i=>i.storyLinks.map(link=>link.id))).size,
 uiPagesWithoutObjectLinks:[...pages.keys()].filter(id=>!items.some(i=>i.uiPages.includes(id))),
 generatedConcepts:generated.length,technicalSketches:sketches.length,evidence:Object.fromEntries(['dedicated-concept','dedicated-original','technical-sketch','context-reference'].map(x=>[x,items.filter(i=>i.evidenceStatus===x).length]))};
const master={schemaVersion:1,generatedAt:new Date().toISOString(),scope:isRewrite?`旧版43场资源需求保留；新主线为${structure.acts}部${scenes.length}章，需求关联待逐项复审。`:'当前43场剧本、72页UI与相关场景制作资源；条目数不等于独立基模数。',narrativeScope,storyBaseline:baseline.version,storyVersion:story.version,summary,
 countingRules:['同一个人的别名/年龄/换装归一身份；NPC职业不等于新增身体。','火炮炮身类型与炮架、旋架、子铳分开；个人火器另列。','建筑模块与装配、场景母版与差异包、海图图层分列但不重复算基模。','每项均有真实本地图像或可编辑结构草图；情境参考不冒称单体原画。','生成概念与SVG结构示意均须正式生产复核；原83基模预算保留，不被170项需求直接替换。'],
 sourceFiles:['docs/narrative/zheng-zhilong/zheng-zhilong-story.json',`${out}/story-baseline-v4.json`,'docs/design/game-ui/systems.json','docs/design/game-ui/production-assets.json'],items};
write(`${library}/.gdignore`,'');
write(`${library}/catalog.json`,master);
write(`${out}/catalog.json`,master);
write(`${out}/data.js`,'window.MING_RESOURCE_LIBRARY='+JSON.stringify(master)+';\n');
const csvCell=x=>'"'+String(x??'').replaceAll('"','""')+'"';
write(`${out}/resource-register.csv`,'\uFEFF'+[['资源ID','名称','分类','阶段','出现方式','图像级别','图像数','目录','旧基模映射','剧情','UI'],...items.map(i=>[i.id,i.name,i.categoryName,i.phase,i.appearance||i.assetKind||'',i.evidenceStatus,i.images.length,i.assetDirectory,(i.legacyModelIds||[]).join('|'),i.storyRefs.join('|'),i.uiPages.join('|')])].map(row=>row.map(csvCell).join(',')).join('\r\n')+'\r\n');
write(`${library}/README.md`,'# 海上明旗 · 生产资源原画库\n\n按分类与稳定资源ID归档，统筹清单见 [catalog.json](catalog.json)。每项目录包含asset.json、README、reference原图与可能的concept/sketch。\n\n本目录使用.gdignore避免将源原画批量导入Godot。运行时仅导出实际需要的成品，不在此处修改原生产资源。\n\n资源条目不等于基模；当前基模预算仍为83，按装配、共享骨架、服装与LOD分别管理。图鉴位于 docs/production/resource-library/index.html。\n');
const roleNames={'dedicated-concept':'新概念原画候选','dedicated-original':'既有独立原图候选','technical-sketch':'结构草图','context-reference':'情境参考'};
const guide=[
 '# 海上明旗 · 全游戏资源统筹与原画库',
 `\n依据旧版43场剧本、72页网页UI、实际项目资源及原83基模预算，保留170项制作需求。${narrativeScope}`,
 ...(isRewrite?['\n马努埃尔、吉平、阿隆索、安东、依斯迈等旧稿独立海上奇遇人物已转为支线或后续候选；其既有原画与资料保留，不再因旧稿标注“演出”而宣称是新版主线必需角色。原人物26／演出18等数字是旧制作基线，并非新版主线演员统计。']:[]),
 '\n[打开可筛选图鉴](index.html) · [下载CSV总表](resource-register.csv) · [机器可读总表](catalog.json) · [原画生成与采用记录](generated-art.json) · [验收记录](verification.json)',
 '\n## 分类与数量\n\n|分类|资源条目数|\n|---|---:|',
 ...summary.categories.map(c=>`|${c.name}|${c.count}|`),
 `|合计|${summary.total}|`,
 '\n人物26个身份包括18个实际演出、8个仅提及。别名、年龄和换装不重复算人。28种NPC是职业原型，可以复用身体、服装和动作，不等于28个全新身体。',
 '\n火炮6项包括3种炮身候选（轻型前装炮、佛朗机、红夷式重炮）及轮式炮架、叉式旋架、子铳3个部件。个人火器2项是长火绳枪和形制仍待证的短铳，不把炮算成个人枪械。',
 '\n15项场景/地图分为4个共享母场景、9个地域/战场差异包、2份二维海图图层；没有把43幅剧情插图当成43张独立可玩地图。建筑15项也包括可复用构件和命名装配，不直接算15座新建筑模型。',
 `\n优先级：P0 ${summary.phases.P0}项，P1 ${summary.phases.P1}项，P2 ${summary.phases.P2}项。`,
 '\n## 文件已准备到哪里',
 '\n源资源根目录为 [assets/production](../../../assets/production/README.md)。按分类文件夹、稳定ID分别归档。每项目录有README与asset.json，可直接查图片、用途、变体、依赖、来源和旧基模映射。',
 '\n```text\nassets/production/\n  catalog.json\n  .gdignore\n  characters/char-tagawamatsu/\n    asset.json\n    README.md\n    concept/original-v1.png\n    concept/art-provenance.json\n    reference/原图名-内容哈希.png\n  cannons/gun-folangji/\n    concept/original-v1.png\n    sketch/structure-v1.svg\n  buildings/building-hirado-home/\n    concept/original-v1.png\n    sketch/structure-v1.svg\n  maps/map-liaoluo-bay/\n    sketch/structure-v1.svg\n    reference/剧情情境图.png\n```',
 `\n实际去重图像内容${summary.distinctImageContents}份：${summary.archivedReferenceSources}份既有参考、${summary.generatedConcepts}张新增ImageGen概念原画、${summary.technicalSketches}张可编辑SVG结构草图。它们形成${summary.images}条资源关联；归档路径${summary.distinctImageFiles}个，重复引用和副本不当成新的原创图片。`,
 '\n新增原画包括12个人物身份、3个建筑对象、4张炮/枪图与2种刀具。现有6个人物身份使用已采用的一官立绘或经核对的人物图集分区，因此18个演出人物均有独立身份候选图。安东新增吕宋本地水手候选，旧图保留为迭代证据。',
 '\nSVG是可编辑结构/布局草图：建筑构件与装配、码头桩梁、道具外观、地图浅滩与航路关系各自绘制；不冒充写实原画、实测工程图或真实历史地图。',
 '\n## 后续Agent如何使用',
 '\n1. 按中文名、ID、场景章节或UI页在图鉴检索，先阅读图像级别和历史边界。\n2. 打开对应资源目录的asset.json；原图、结构草图、来源、复用和依赖均在条目内。\n3. UI可从既有图/新概念导出适合用途的裁图；模型制作先补比例、正侧背、服装层次与挂点复核。原图不覆盖。\n4. 建筑用构件装配，场景用母版＋差异包；地图示意不直接充当导航坐标数据。\n5. 验证后的运行时资产再经项目既有引擎资产合同接入，避免生产参考原画全量导入Godot。',
 '\n## 基模预算与制作边界',
 '\n原83基模ID已全部映射，可继续追溯 [上一轮模型预算](../../design/game-ui/production-assets.md)。170是资源工作包数量，不能直接宣布需要170个独立模型。角色身份深化可能增加头部/服装制作工时；模型总数还需在角色定型、比例和复用策略确认后复算，83仍是基线预算而非全部模型已经完成。',
 '\n所有新ImageGen图均为创作概念候选，非历史肖像或文物精确复原。普通剧情图只标情境参考；8位仅提及人物没有借别人的脸冒充专用肖像。旧原版提取模型和贴图仍是参考资料，未由此获得商业发行授权。',
 `\n旧稿资源出处覆盖${summary.coveredStoryScenes}/${baseline.scenes.length}场；当前主线${summary.currentScenes}章。${isRewrite?'旧资源链接转向相近历史阶段，仅作导航，不能用此宣称新作实体需求已经逐项复核。':''}当前${summary.coveredUiPages}/72个UI页面有旧实体/场景需求关联。以下页面尚未建立本次物件需求关联，不据此虚增模型：${summary.uiPagesWithoutObjectLinks.join('、')}。`,
 '\n## 全量逐项清单',
 ...summary.categories.flatMap(c=>[`\n### ${c.name} · ${c.count}\n\n|ID / 名称|阶段|当前首选图像|资源说明|\n|---|---|---|---|`,...items.filter(i=>i.category===c.id).map(i=>`|\`${i.id}\` · ${i.name}|${i.phase}|${roleNames[i.evidenceStatus]}|[目录与图片](../../../${i.assetDirectory}/README.md)|`)]),
 '\n## 分册审查与重建\n\n[人物审计](characters-audit.md) · [环境审计](environment-audit.md) · [装备审计](equipment-audit.md) · [独立总审查](independent-review.md)\n\n```powershell\nrtk proxy node tools/build-environment-resource-sketches.mjs\nrtk proxy node tools/build-equipment-resource-sketches.mjs\nrtk proxy node tools/build-production-resource-library.mjs\nrtk proxy node tools/verify-production-resource-library.mjs\n```'
];
write(`${out}/README.md`,guide.join('\n')+'\n');
console.log('RESOURCE_LIBRARY_BUILT '+JSON.stringify(summary));
