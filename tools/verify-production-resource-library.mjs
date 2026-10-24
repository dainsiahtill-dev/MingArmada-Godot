import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import {storyStructure,aliasIssues,legacySceneIds} from './zheng-story-contract.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const output=path.join(root,'docs/production/resource-library/verification.json');
const library=path.join(root,'assets/production');
const checks=[];
const expected={'named-character':26,'npc-archetype':28,ship:8,cannon:6,firearm:2,'melee-weapon':3,ammunition:4,building:15,'coastal-building':6,'scene-map':15,nature:10,prop:47};
const folders={'named-character':'characters','npc-archetype':'npcs',ship:'ships',cannon:'cannons',firearm:'firearms','melee-weapon':'melee-weapons',ammunition:'ammunition',building:'buildings','coastal-building':'coastal','scene-map':'maps',nature:'nature',prop:'props'};
const prefixes={'named-character':'char-','npc-archetype':'npc-',ship:'ship-',cannon:'gun-',firearm:'firearm-','melee-weapon':'weapon-',ammunition:'ammo-',building:'building-','coastal-building':'coastal-','scene-map':'map-',nature:'nature-',prop:'prop-'};
const required=['id','name','category','phase','description','visualBrief','storyRefs','uiPages','variants','modelStrategy','historicalStatus','existingModels','legacyModelIds','assetDirectory','dependencies','images','primaryImage','evidenceStatus','conceptStatus','imageCount'];
const hashCache=new WeakMap();
const sha=value=>{if(Buffer.isBuffer(value)&&hashCache.has(value))return hashCache.get(value);const digest=crypto.createHash('sha256').update(value).digest('hex');if(Buffer.isBuffer(value))hashCache.set(value,digest);return digest;};
const equal=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const within=(candidate,base)=>{const relative=path.relative(base,candidate);return relative===''||(!relative.startsWith('..'+path.sep)&&relative!=='..'&&!path.isAbsolute(relative));};
function bounded(relative,base=root){
 if(typeof relative!=='string'||!relative||/[:\\%?#\u0000-\u001f]/.test(relative)||relative.startsWith('/')||relative.split('/').some(x=>x==='..'||x==='.'||!x)) throw new Error('unsafe relative path');
 const absolute=path.resolve(root,relative);
 if(!within(absolute,base))throw new Error('path outside allowed root');
 if(fs.existsSync(absolute)&&!within(fs.realpathSync(absolute),fs.realpathSync(base)))throw new Error('symlink outside allowed root');
 return absolute;
}
const cache=new Map();
const readBytes=relative=>{const absolute=bounded(relative);if(!cache.has(relative))cache.set(relative,fs.readFileSync(absolute));return cache.get(relative);};
const readJSON=relative=>JSON.parse(readBytes(relative).toString('utf8').replace(/^\uFEFF/,''));
const doc=readJSON('docs/production/resource-library/catalog.json');
const generated=readJSON('docs/production/resource-library/generated-art.json').entries;
const budget=readJSON('docs/design/game-ui/production-assets.json');
const story=readJSON('docs/narrative/zheng-zhilong/zheng-zhilong-story.json');
const systems=readJSON('docs/design/game-ui/systems.json');
const structure=storyStructure(story),isRewrite=['five-act-rewrite','historical-reboot'].includes(structure.edition);
const canonicalScenes=new Map(story.acts.flatMap(a=>a.scenes).map(x=>[x.id,x]));
const storyBaseline=readJSON('docs/production/resource-library/story-baseline-v4.json');
const scenes=new Map((isRewrite?storyBaseline.scenes:story.acts.flatMap(a=>a.scenes)).map(x=>[x.id,x]));
const pages=new Map(systems.screenGroups.flatMap(x=>x.screens).map(x=>[x.id,x]));
const legacy=new Set(budget.models.map(x=>x.id));
const bodyFamilies=new Set(budget.models.filter(x=>x.id.startsWith('body-')).map(x=>x.id));
const inputPaths=['docs/production/resource-library/catalog.json','docs/production/resource-library/data.js','assets/production/catalog.json','docs/production/resource-library/generated-art.json','docs/production/resource-library/resource-register.csv','docs/production/resource-library/story-baseline-v4.json','docs/narrative/zheng-zhilong/zheng-zhilong-story.json','docs/design/game-ui/systems.json','docs/design/game-ui/production-assets.json','tools/verify-production-resource-library.mjs','tools/zheng-story-contract.mjs'];
const initialInputs=Object.fromEntries(inputPaths.map(p=>[p,sha(readBytes(p))]));
const categoryCounts=items=>Object.fromEntries(Object.keys(expected).map(k=>[k,items.filter(i=>i.category===k).length]));
const add=(id,issues,details={})=>checks.push({id,status:issues.length?'failed':'passed',errors:issues,...details});
const issue=(errors,code,id,detail)=>errors.push({code,id,detail});
function crop(image){
 const raw=image?.cropNormalized;if(raw==null)return null;
 const values=Array.isArray(raw)?raw:[raw.x,raw.y,raw.width??raw.w,raw.height??raw.h];
 return values.length===4&&values.every(Number.isFinite)&&values[0]>=0&&values[1]>=0&&values[2]>0&&values[3]>0&&values[0]+values[2]<=1.000001&&values[1]+values[3]<=1.000001?values:false;
}
function validateCatalog(data,read=readBytes){
 const errors=[],items=Array.isArray(data.items)?data.items:[],ids=new Set(),mapped=new Set(),primaryIdentities=new Map();
 for(const i of items){
  if(ids.has(i.id))issue(errors,'duplicate-id',i.id,'ID must be unique');ids.add(i.id);
  for(const key of required)if(!(key in i))issue(errors,'required-field',i.id,key);
  for(const key of ['id','name','description','visualBrief','modelStrategy','historicalStatus'])if(typeof i[key]!=='string'||!i[key].trim())issue(errors,'text-field',i.id,key);
  for(const key of ['storyRefs','uiPages','variants','existingModels','legacyModelIds','dependencies','images'])if(!Array.isArray(i[key]))issue(errors,'array-field',i.id,key);
  if(!expected[i.category]||!i.id?.startsWith(prefixes[i.category]||'?')||!/^[a-z][a-z0-9-]*$/.test(i.id||''))issue(errors,'category-prefix',i.id,i.category);
  if(!['P0','P1','P2'].includes(i.phase))issue(errors,'phase',i.id,i.phase);
  try{bounded(i.assetDirectory,library);if(i.assetDirectory!=='assets/production/'+folders[i.category]+'/'+i.id)throw new Error('directory category/ID mismatch');}catch(e){issue(errors,'asset-path',i.id,e.message);}
  for(const r of i.storyRefs||[])if(!scenes.has(r))issue(errors,'story-reference',i.id,r);
  if(isRewrite){
   if(i.narrativeStatus!=='legacy-requirement-needs-mainline-audit'||!i.narrativeScope?.includes('不证明'))issue(errors,'narrative-scope',i.id,'Legacy inventory must not imply current mainline appearance');
   if(!Array.isArray(i.storyLinks)||i.storyLinks.length!==i.storyRefs.length)issue(errors,'story-link-count',i.id,'Every baseline reference needs an explicit successor');
   for(const link of i.storyLinks||[])if(!i.storyRefs.includes(link.legacyId)||story.legacySceneAliases[link.legacyId]!==link.id||!canonicalScenes.has(link.id)||link.relationship!=='rewrite-successor-not-confirmed-appearance')issue(errors,'story-link-alias',i.id,link.legacyId);
  }
  for(const r of i.uiPages||[])if(!pages.has(r))issue(errors,'ui-reference',i.id,r);
  for(const r of i.legacyModelIds||[]){mapped.add(r);if(!legacy.has(r))issue(errors,'unknown-legacy',i.id,r);}
  for(const model of i.existingModels||[])try{if(!fs.statSync(bounded(model)).isFile())throw new Error('not a file');}catch(e){issue(errors,'existing-model',i.id,model+': '+e.message);}
  if(i.imageCount!==(i.images||[]).length)issue(errors,'image-count',i.id,i.imageCount);
  const expectedConceptStatus={'dedicated-concept':'concept-candidate','dedicated-original':'existing-original-review','technical-sketch':'editable-sketch','context-reference':'context-only-needs-independent-concept'};
  if(!Object.hasOwn(expectedConceptStatus,i.evidenceStatus)||i.conceptStatus!==expectedConceptStatus[i.evidenceStatus])issue(errors,'evidence-status',i.id,'Evidence and concept status must agree');
  if(!i.images?.length)issue(errors,'image-coverage',i.id,'No image');
  for(const image of i.images||[]){
   try{
    bounded(image.path,library);
    if(!/\.(png|jpe?g|svg)$/i.test(image.path))throw new Error('Unsupported image extension');
    const bytes=read(image.path);
    if(!bytes.length)throw new Error('Empty file');
    if(!/^[0-9a-f]{64}$/.test(image.sha256||'')||sha(bytes)!==image.sha256)issue(errors,'image-hash',i.id,image.path);
   }catch(e){issue(errors,'missing-image',i.id,image.path+': '+e.message);}
   if(typeof image.role!=='string'||!image.role)issue(errors,'image-role',i.id,image.path);
   if(typeof image.rights!=='string'||!image.rights)issue(errors,'image-rights',i.id,image.path);
   if(crop(image)===false)issue(errors,'invalid-crop',i.id,image.path);
   if(image.role==='portrait-atlas-crop'&&!crop(image))issue(errors,'atlas-without-crop',i.id,image.path);
   if(image.role==='technical-sketch'&&(!image.path?.startsWith(i.assetDirectory+'/sketch/')||!image.path?.endsWith('.svg')))issue(errors,'sketch-path',i.id,image.path);
   if(!['dedicated-concept','technical-sketch'].includes(image.role)){
    try{
     if(!image.path.startsWith(i.assetDirectory+'/reference/'))throw new Error('reference copy outside item directory');
     const source=read(image.sourcePath),dest=read(image.path);
     if(sha(source)!==sha(dest)||sha(source)!==image.sha256)issue(errors,'reference-hash',i.id,image.path);
    }catch(e){issue(errors,'reference-source',i.id,e.message);}
    if(/reference_atmosphere|pirates_reference|pirates_damage_reference|fidelity_naval|fidelity_fx/.test(image.sourcePath||'')&&image.rights!=='reference-only-review-required')issue(errors,'reference-rights',i.id,image.sourcePath);
   }
  }
  if(!i.primaryImage||!(i.images||[]).some(x=>equal(x,i.primaryImage)))issue(errors,'primary-membership',i.id,'Primary must be an exact member of images');
  const p=i.primaryImage;
  if(p){
   if(crop(p)===false)issue(errors,'invalid-crop',i.id,p.path);
   if(i.evidenceStatus==='dedicated-concept'&&p.role!=='dedicated-concept')issue(errors,'evidence-role',i.id,p.role);
   if(i.evidenceStatus==='technical-sketch'&&p.role!=='technical-sketch')issue(errors,'evidence-role',i.id,p.role);
   if(i.evidenceStatus==='dedicated-original'&&!['portrait','portrait-original','portrait-atlas-crop','dedicated-original','ui-portrait','item-art'].includes(p.role))issue(errors,'evidence-role',i.id,p.role);
  }
  if(i.category==='named-character'&&i.appearance==='on-screen'){
   const role=p?.role||'';
   if(!['dedicated-concept','portrait','portrait-original','portrait-atlas-crop','dedicated-original','ui-portrait'].includes(role))issue(errors,'onscreen-primary',i.id,role);
   if(/crew-portraits/.test(p?.path||'')&&!crop(p))issue(errors,'onscreen-atlas-crop',i.id,'Atlas must have audited crop');
   if(i.modelRequired!==true)issue(errors,'onscreen-model',i.id,'Expected model requirement');
   const identity=(p?.sha256||'')+':'+JSON.stringify(crop(p));
   if(primaryIdentities.has(identity))issue(errors,'duplicate-character-image',i.id,primaryIdentities.get(identity));
   primaryIdentities.set(identity,i.id);
  }
  if(i.category==='named-character'&&i.appearance==='mentioned-only'){
   if(i.modelRequired!==false||(i.legacyModelIds||[]).some(x=>/^(body-|head-)/.test(x)))issue(errors,'mentioned-body',i.id,'Mentioned-only identity must not imply a body/head');
   if(!/不要求身体|不需要身体|no.body/i.test(i.modelStrategy||''))issue(errors,'mentioned-body-note',i.id,'Explicit no-body note missing');
   if(i.evidenceStatus!=='context-reference'||!['scene-context','story-context','ui-context'].includes(p?.role))issue(errors,'mentioned-portrait-claim',i.id,'Context cannot be promoted to independent likeness');
  }
  if(i.category==='npc-archetype'){
   if(!/共享/.test(i.modelStrategy||''))issue(errors,'npc-body-family',i.id,'Must explicitly share body/heads');
   if((i.baseMeshCount||0)>0||i.independentBody===true)issue(errors,'npc-independent-body',i.id,'Occupation is not an independent body mesh');
   if(!(i.legacyModelIds||[]).some(x=>bodyFamilies.has(x))||(i.legacyModelIds||[]).some(x=>x.startsWith('body-')&&!bodyFamilies.has(x)))issue(errors,'npc-body-family',i.id,'Only known shared body families allowed');
  }
 }
 for(const i of items)for(const dependency of i.dependencies||[])if(!ids.has(dependency)||dependency===i.id)issue(errors,'dependency',i.id,dependency);
 for(const old of legacy)if(!mapped.has(old))issue(errors,'legacy-coverage',old,'Legacy base model unmapped');
 return errors;
}
add('catalog-fields-identities-paths-images-and-references',validateCatalog(doc),{items:doc.items.length});
const countErrors=[];
if(doc.items.length!==170)countErrors.push('Expected 170 requirements');
if(!equal(categoryCounts(doc.items),expected))countErrors.push({expected,actual:categoryCounts(doc.items)});
const phaseCounts=Object.fromEntries(['P0','P1','P2'].map(k=>[k,doc.items.filter(i=>i.phase===k).length]));
if(!equal(phaseCounts,{P0:88,P1:72,P2:10}))countErrors.push({phaseCounts});
if(scenes.size!==43||pages.size!==72||legacy.size!==83)countErrors.push('Input contract changed: re-audit expected coverage');
if(isRewrite){
 countErrors.push(...aliasIssues(story));
 if(canonicalScenes.size!==structure.sceneCount||story.acts.length!==structure.acts||story.acts.some((a,i)=>a.scenes.length!==(structure.sceneCounts?.[i]||structure.scenesPerAct)))countErrors.push('Current narrative differs from its explicit structural contract');
 if(!equal([...scenes.keys()].sort(),[...legacySceneIds].sort()))countErrors.push('Preserved resource baseline must contain the 43 published scenes');
 if(doc.summary.currentScenes!==structure.sceneCount||doc.summary.legacyScenes!==43||doc.storyVersion!==story.version||doc.storyBaseline!==storyBaseline.version)countErrors.push('Current and legacy narrative scopes are not separated');
}
if(doc.summary.total!==170||doc.summary.legacyBaseModels!==83||doc.summary.generatedConcepts!==21||doc.summary.technicalSketches!==108)countErrors.push('Catalog summary totals differ');
for(const [k,v] of Object.entries(expected))if(doc.summary.categories.find(x=>x.id===k)?.count!==v)countErrors.push('Wrong summary category '+k);
if(!equal(doc.summary.phases,phaseCounts))countErrors.push('Wrong summary phases');
if(doc.summary.images!==doc.items.reduce((sum,i)=>sum+i.images.length,0)||doc.summary.distinctImageFiles!==new Set(doc.items.flatMap(i=>i.images.map(x=>x.path))).size)countErrors.push('Image summary totals differ');
add('expected-counts',countErrors,{categories:categoryCounts(doc.items),phases:phaseCounts,legacyBaseModels:legacy.size});
const roles=doc.items.filter(x=>x.category==='named-character'),identityErrors=[],aliasOwners=new Map();
for(const i of roles)for(const alias of new Set([i.name,...(i.aliases||[])])){if(aliasOwners.has(alias)&&aliasOwners.get(alias)!==i.id)identityErrors.push({ambiguousAlias:alias,ids:[aliasOwners.get(alias),i.id]});aliasOwners.set(alias,i.id);}
if(roles.filter(x=>x.appearance==='on-screen').length!==18)identityErrors.push('Expected 18 on-screen identities');
if(roles.filter(x=>x.appearance==='mentioned-only').length!==8)identityErrors.push('Expected 8 mentioned-only identities');
if(doc.items.filter(x=>x.category==='npc-archetype').length!==28)identityErrors.push('Expected 28 NPC occupations');
add('character-and-profession-counting',identityErrors,{onScreen:18,mentionedOnly:8,npcArchetypes:28,sharedNpcBodyFamilies:[...new Set(doc.items.filter(x=>x.category==='npc-archetype').flatMap(x=>x.legacyModelIds.filter(y=>bodyFamilies.has(y))))]});
const usedScenes=new Set(doc.items.flatMap(x=>x.storyRefs)),usedPages=new Set(doc.items.flatMap(x=>x.uiPages));
add('story-and-ui-reference-domains',[
 ...[...usedScenes].filter(x=>!scenes.has(x)).map(x=>'Unknown scene '+x),
 ...[...usedPages].filter(x=>!pages.has(x)).map(x=>'Unknown UI page '+x),
 ...[...scenes.keys()].filter(x=>!usedScenes.has(x)).map(x=>'Uncovered scene '+x)
],{validSceneDomain:scenes.size,currentScenes:canonicalScenes.size,legacyScenes:storyBaseline.scenes.length,validUiDomain:pages.size,referencedScenes:usedScenes.size,referencedUiPages:usedPages.size,pagesWithoutPhysicalAssetMapping:[...pages.keys()].filter(x=>!usedPages.has(x)),interpretation:'Resource references retain their published v4 provenance. Rewrite successors preserve navigation, not confirmation of current mainline appearance. UI pages without a physical asset are listed, not silently counted as covered.'});
const bundleErrors=[];
try{
 const assets=readJSON('assets/production/catalog.json');
 const js=readBytes('docs/production/resource-library/data.js').toString('utf8');
 const match=/^\s*window\.MING_RESOURCE_LIBRARY\s*=\s*([\s\S]+);\s*$/.exec(js);
 if(!match)throw new Error('Unexpected data.js wrapper');
 const embedded=JSON.parse(match[1]);
 if(!equal(doc,assets)||!equal(doc,embedded))bundleErrors.push('catalog/data.js/assets catalog differ');
 for(const i of doc.items){
  if(!equal(readJSON(i.assetDirectory+'/asset.json'),i))bundleErrors.push('asset.json mismatch '+i.id);
  const readme=readBytes(i.assetDirectory+'/README.md').toString('utf8');
  if(!readme.includes(i.id)||!readme.includes(i.name))bundleErrors.push('README missing ID/name '+i.id);
 }
}catch(e){bundleErrors.push(e.message);}
add('bundle-and-per-item-record-consistency',bundleErrors,{recordsCompared:170});
const provenanceErrors=[];
const generatedHashes=new Set(),generatedCounts={characters:0,buildings:0,cannons:0,firearms:0,'melee-weapons':0};
for(const art of generated){
 try{
  if(art.tool!=='native-imagegen'||typeof art.prompt!=='string'||art.prompt.length<80||typeof art.source!=='string')throw new Error('Missing native tool/prompt/source metadata');
  bounded(art.path,library);
  const item=doc.items.find(i=>i.id===art.id);if(!item)throw new Error('Generated ID has no requirement');
  if(art.path!==item.assetDirectory+'/concept/original-v1.png')throw new Error('Original not under owner concept directory');
  const provenance=readJSON(item.assetDirectory+'/concept/art-provenance.json');
  if(provenance.id!==art.id||provenance.prompt!==art.prompt||provenance.source!==art.source||provenance.path!==art.path||provenance.tool!=='native-imagegen')throw new Error('Per-art provenance sidecar differs');
  const canonicalSource=path.resolve(art.source);
  const allowedGenerated=path.join(os.homedir(),'.codex','generated_images');
  if(!within(canonicalSource,allowedGenerated)||!fs.statSync(canonicalSource).isFile())throw new Error('Codex source is missing or outside generated_images');
  const original=readBytes(art.path),source=fs.readFileSync(canonicalSource);
  if(sha(original)!==sha(source))throw new Error('Original bytes differ from Codex generated source');
  if(provenance.sha256!==sha(original))throw new Error('Sidecar sha256 missing or differs');
  generatedHashes.add(sha(original));generatedCounts[art.category]=(generatedCounts[art.category]||0)+1;
  if(!item.images.some(x=>x.path===art.path&&x.role==='dedicated-concept'&&x.promptId===art.id&&x.sourcePath===art.source))throw new Error('Generated art not attached with correct role and prompt ID');
 }catch(e){provenanceErrors.push({id:art.id,error:e.message});}
}
if(generated.length!==21||generatedHashes.size!==21)provenanceErrors.push('Expected 21 distinct native originals');
if(!equal(generatedCounts,{characters:12,buildings:3,cannons:3,firearms:1,'melee-weapons':2}))provenanceErrors.push({actualGeneratedCategories:generatedCounts});
add('native-imagegen-originals-and-provenance',provenanceErrors,{entries:generated.length,distinctOriginalHashes:generatedHashes.size,categories:generatedCounts});
function parseCSV(text){
 const rows=[];let row=[],cell='',quoted=false;
 for(let i=0;i<text.length;i++){
  const a=text[i];if(a==='"'){if(quoted&&text[i+1]==='"'){cell+='"';i++;}else quoted=!quoted;}
  else if(a===','&&!quoted){row.push(cell);cell='';}
  else if((a==='\r'||a==='\n')&&!quoted){if(a==='\r'&&text[i+1]==='\n')i++;row.push(cell);rows.push(row);row=[];cell='';}
  else cell+=a;
 }
 if(quoted)throw new Error('Unclosed CSV quote');if(cell||row.length){row.push(cell);rows.push(row);}return rows;
}
const csvErrors=[];let csvRows=[];
try{
 csvRows=parseCSV(readBytes('docs/production/resource-library/resource-register.csv').toString('utf8').replace(/^\uFEFF/,''));
 if(csvRows.length!==171||csvRows.some(r=>r.length!==11))throw new Error('CSV must have header + 170 data rows, 11 columns');
 if(new Set(csvRows.slice(1).map(x=>x[0])).size!==170)throw new Error('Duplicate CSV resource ID');
 for(const row of csvRows.slice(1)){
  const i=doc.items.find(x=>x.id===row[0]);if(!i)throw new Error('Unknown CSV ID '+row[0]);
  const expectedRow=[i.id,i.name,i.categoryName,i.phase,i.appearance||i.assetKind||'',i.evidenceStatus,String(i.images.length),i.assetDirectory,i.legacyModelIds.join('|'),i.storyRefs.join('|'),i.uiPages.join('|')];
  if(!equal(row,expectedRow))csvErrors.push('CSV row mismatch '+i.id);
 }
}catch(e){csvErrors.push(e.message);}
add('csv-register',csvErrors,{dataRows:Math.max(0,csvRows.length-1)});
const negativeControls=[];
function negative(name,mutate,expectedCode,read=readBytes){
 const candidate=structuredClone(doc);mutate(candidate);
 const errors=validateCatalog(candidate,read);
 negativeControls.push({name,expectedCode,rejected:errors.some(x=>x.code===expectedCode),observedCodes:[...new Set(errors.map(x=>x.code))]});
}
negative('duplicate ID',x=>x.items[1].id=x.items[0].id,'duplicate-id');
negative('invalid category',x=>x.items[0].category='profession-is-body','category-prefix');
negative('path escape',x=>x.items[0].assetDirectory='assets/production/../outside','asset-path');
negative('missing image',x=>{x.items[0].images[0].path=x.items[0].assetDirectory+'/reference/nonexistent-negative-control.png';x.items[0].primaryImage=x.items[0].images[0];},'missing-image');
negative('bad hash',x=>x.items[0].images[0].sha256='0'.repeat(64),'image-hash');
const referenceControl=doc.items.flatMap(i=>i.images).find(i=>i.path.includes('/reference/'));
negative('reference source bytes changed',()=>{},'reference-hash',p=>p===referenceControl.sourcePath?Buffer.from('in-memory altered source image'):readBytes(p));
negative('unknown scene',x=>x.items[0].storyRefs=['zheng_a99_s99'],'story-reference');
negative('unknown UI page',x=>x.items[0].uiPages=['unknown-page'],'ui-reference');
negative('unknown dependency',x=>x.items[0].dependencies=['prop-does-not-exist'],'dependency');
const oldId=[...legacy][0];
negative('legacy coverage removed',x=>x.items.forEach(i=>i.legacyModelIds=i.legacyModelIds.filter(v=>v!==oldId)),'legacy-coverage');
negative('invalid portrait crop',x=>{const i=x.items.find(i=>i.primaryImage.cropNormalized);i.primaryImage.cropNormalized={x:.9,y:0,width:.5,height:.5};},'invalid-crop');
negative('context passed as on-screen portrait',x=>{const i=x.items.find(i=>i.appearance==='on-screen');i.primaryImage={...i.images[0],role:'scene-context'};},'onscreen-primary');
negative('NPC occupation gets independent body',x=>x.items.find(i=>i.category==='npc-archetype').baseMeshCount=1,'npc-independent-body');
negative('mentioned identity gets a body',x=>x.items.find(i=>i.appearance==='mentioned-only').modelRequired=true,'mentioned-body');
add('in-memory-contract-negative-controls',negativeControls.filter(x=>!x.rejected),{controls:negativeControls});
const gdignoreErrors=[];
try{const p=bounded('assets/production/.gdignore',library);if(!fs.statSync(p).isFile())throw new Error('not file');}catch(e){gdignoreErrors.push(e.message);}
add('godot-production-library-exclusion',gdignoreErrors,{path:'assets/production/.gdignore',meaning:'Godot source-art directory exclusion marker exists; no import or runtime loading was exercised.'});
const allLibraryImages=[];
function scan(directory){
 for(const e of fs.readdirSync(directory,{withFileTypes:true})){
  const absolute=path.join(directory,e.name);
  if(e.isSymbolicLink()){if(!within(fs.realpathSync(absolute),library))throw new Error('Library symlink escapes '+absolute);}
  if(e.isDirectory())scan(absolute);else if(e.isFile()&&/\.(png|jpe?g|svg)$/i.test(e.name))allLibraryImages.push(path.relative(root,absolute).split(path.sep).join('/'));
 }
}
scan(library);
const imagePaths=[...new Set([...allLibraryImages,...doc.items.flatMap(i=>i.images.map(x=>x.path))])].sort();
const rasterPaths=imagePaths.filter(x=>!x.endsWith('.svg'));
const svgPaths=imagePaths.filter(x=>x.endsWith('.svg'));
const crops=doc.items.filter(i=>i.category==='named-character'&&i.appearance==='on-screen').map(i=>({id:i.id,path:i.primaryImage.path,crop:crop(i.primaryImage)||null}));
const dependencyBase=path.join(os.homedir(),'.cache','codex-runtimes','codex-primary-runtime','dependencies');
const python=process.env.MING_RESOURCE_PYTHON||path.join(dependencyBase,'python',process.platform==='win32'?'python.exe':'bin/python3');
const nodeModules=process.env.MING_RESOURCE_NODE_MODULES||path.join(dependencyBase,'node','node_modules');
const require=createRequire(import.meta.url);
let sharp;
try{sharp=require(require.resolve('sharp',{paths:[nodeModules]}));}catch(e){add('bundled-svg-renderer',[e.message]);}
const pythonCode=String.raw`
import sys,json,io,re,hashlib,xml.etree.ElementTree as ET
from pathlib import Path
from PIL import Image
data=json.load(sys.stdin); root=Path(data['root'])
result={'rasters':[],'svgs':[],'crops':[],'errors':[],'negativeControls':[]}
def svg_errors(text):
    errors=[]
    if re.search(r'<!DOCTYPE|<!ENTITY',text,re.I): errors.append('doctype-or-entity')
    try: node=ET.fromstring(text)
    except Exception: return errors+['malformed-xml']
    if node.tag!='{http://www.w3.org/2000/svg}svg': errors.append('not-svg-root')
    box=node.attrib.get('viewBox','').replace(',',' ').split()
    try:
        box=[float(v) for v in box]
        if len(box)!=4 or box[2]<=0 or box[3]<=0 or any(not(-1e8<v<1e8) for v in box): errors.append('invalid-viewBox')
    except Exception: errors.append('invalid-viewBox')
    for e in node.iter():
        tag=e.tag.split('}')[-1].lower()
        if tag in ['script','foreignobject','iframe','object','embed','audio','video']: errors.append('active-content:'+tag)
        for k,v in e.attrib.items():
            key=k.split('}')[-1].lower()
            if key.startswith('on'): errors.append('event-handler')
            if key in ['href','src'] and v and not v.startswith('#'): errors.append('external-link')
            if key=='style' and '@import' in v.lower(): errors.append('css-import')
            for url in re.findall(r'url\s*\((.*?)\)',v,re.I):
                if not url.strip(" \t'\"").startswith('#'): errors.append('external-css-url')
        if tag=='style':
            css=e.text or ''
            if '@import' in css.lower(): errors.append('css-import')
            for url in re.findall(r'url\s*\((.*?)\)',css,re.I):
                if not url.strip(" \t'\"").startswith('#'): errors.append('external-css-url')
    if not any(e.tag.split('}')[-1] in ['path','rect','circle','ellipse','polygon','polyline','line','text'] for e in node.iter()): errors.append('no-visible-elements')
    return errors
for relative in data['rasters']:
    try:
        p=root/relative
        with Image.open(p) as im: im.verify()
        with Image.open(p) as im:
            im.load()
            expected='PNG' if p.suffix.lower()=='.png' else 'JPEG'
            if im.format!=expected: raise ValueError('extension/format mismatch '+str(im.format))
            if im.width<=0 or im.height<=0: raise ValueError('zero dimensions')
            result['rasters'].append({'path':relative,'width':im.width,'height':im.height,'format':im.format,'mode':im.mode,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
    except Exception as e: result['errors'].append({'path':relative,'error':str(e)})
for relative in data['svgs']:
    try:
        errors=svg_errors((root/relative).read_text(encoding='utf-8'))
        if errors: result['errors'].append({'path':relative,'error':errors})
        else: result['svgs'].append({'path':relative,'xml':'valid','scriptExternalLinks':'none'})
    except Exception as e: result['errors'].append({'path':relative,'error':str(e)})
for record in data['crops']:
    try:
        with Image.open(root/record['path']) as im:
            im.load()
            crop=record['crop']
            if crop:
                x,y,w,h=crop
                box=(round(x*im.width),round(y*im.height),min(im.width,round((x+w)*im.width)),min(im.height,round((y+h)*im.height)))
                clipped=im.crop(box);clipped.load()
                if min(clipped.size)<=0: raise ValueError('empty normalized crop')
                dims=clipped.size
            else: dims=im.size
            result['crops'].append({'id':record['id'],'path':record['path'],'hasCrop':bool(crop),'width':dims[0],'height':dims[1],'decoded':True})
    except Exception as e: result['errors'].append({'id':record['id'],'error':'portrait crop: '+str(e)})
first=(root/data['rasters'][0]).read_bytes()
for name,raw in [('corrupt raster',b'not an image'),('truncated raster',first[:max(40,len(first)//3)])]:
    try:
        with Image.open(io.BytesIO(raw)) as im: im.load()
        rejected=False
    except Exception: rejected=True
    result['negativeControls'].append({'name':name,'rejected':rejected})
for name,text in [('malformed SVG','<svg><path>'),('SVG script','<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 5 5"><script>alert(1)</script></svg>'),('SVG external link','<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 5 5"><image href="https://invalid.example/a.png"/></svg>'),('SVG event handler','<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 5 5" onload="alert(1)"><rect width="2" height="2"/></svg>')]:
    errors=svg_errors(text)
    result['negativeControls'].append({'name':name,'rejected':bool(errors),'observed':errors})
print('MEDIA_VERIFY_JSON '+json.dumps(result,ensure_ascii=False))
`;
let media={rasters:[],svgs:[],crops:[],errors:[],negativeControls:[]};
try{
 if(!fs.statSync(python).isFile())throw new Error('Bundled Python not found: '+python);
 const child=spawnSync('rtk',['proxy',python,'-c',pythonCode],{cwd:root,input:JSON.stringify({root,rasters:rasterPaths,svgs:svgPaths,crops}),encoding:'utf8',maxBuffer:16*1024*1024,timeout:240000,windowsHide:true});
 if(child.error)throw child.error;
 if(child.status!==0)throw new Error('Python decoder exit '+child.status+': '+(child.stderr||child.stdout).slice(-2500));
 const marker='MEDIA_VERIFY_JSON ',start=child.stdout.indexOf(marker);
 if(start<0)throw new Error('No decoder JSON result: '+child.stdout.slice(-1000));
 media=JSON.parse(child.stdout.slice(start+marker.length).trim());
 const decodedPaths=new Set(media.rasters.map(x=>x.path));
 const missingNativeDecodes=generated.filter(x=>!decodedPaths.has(x.path)).map(x=>'Native original did not decode: '+x.id);
 add('raster-decode-svg-xml-and-portrait-crop',[...media.errors,...missingNativeDecodes],{rasterFilesDecoded:media.rasters.length,svgXmlValidated:media.svgs.length,primaryPortraitsDecoded:media.crops.length,nativeOriginalsDecoded:21-missingNativeDecodes.length,filesExpected:imagePaths.length,python});
 add('media-in-memory-negative-controls',media.negativeControls.filter(x=>!x.rejected),{controls:media.negativeControls});
}catch(e){add('raster-decode-svg-xml-and-portrait-crop',[e.message],{python});}
const renders=[],renderErrors=[];
if(sharp){
 for(const svg of media.svgs){
  try{
   const bytes=readBytes(svg.path);
   const png=await sharp(bytes,{limitInputPixels:100000000}).png().toBuffer();
   const stats=await sharp(png).stats();
   const info=await sharp(png).metadata();
   if(!info.width||!info.height||!stats.channels.some(x=>x.stdev>0))throw new Error('Empty or uniform rendered SVG');
   renders.push({path:svg.path,width:info.width,height:info.height,sourceSha256:sha(bytes),renderedPixelSha256:sha(await sharp(png).raw().toBuffer()),rendered:true});
  }catch(e){renderErrors.push({path:svg.path,error:e.message});}
 }
 try{await sharp(Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"><path>')).png().toBuffer();renderErrors.push('Renderer accepted malformed SVG negative control');}catch{}
 if(renders.length!==108||svgPaths.length!==108)renderErrors.push({expectedSvg:108,rendered:renders.length,found:svgPaths.length});
 add('all-svg-actual-render',renderErrors,{filesRendered:renders.length,renderer:'bundled sharp/libvips',nodeModules,malformedSvgNegativeRejected:!renderErrors.includes('Renderer accepted malformed SVG negative control')});
}
const referred=new Set(doc.items.flatMap(i=>i.images.map(x=>x.path)));
add('input-snapshot-stability',inputPaths.filter(p=>sha(fs.readFileSync(bounded(p)))!==initialInputs[p]).map(p=>'Input changed during verification: '+p));
const assertions=checks.length,failed=checks.filter(x=>x.status==='failed').length;
const report={
 schemaVersion:1,verifiedAt:new Date().toISOString(),status:failed?'failed':'passed',
 scope:'Independent structural, metadata, provenance, path, decode and SVG-render verification. Browser behavior, visual taste, historical shape certification, licensing clearance and production 3D acceptance are outside this report.',
 summary:{checks:assertions,passed:assertions-failed,failed,requirements:doc.items.length,categories:categoryCounts(doc.items),phases:phaseCounts,legacyBaseModels:legacy.size,referencedScenes:usedScenes.size,validSceneDomain:scenes.size,referencedUiPages:usedPages.size,validUiDomain:pages.size,nativeOriginals:generated.length,rasterDecoded:media.rasters.length,svgXmlValidated:media.svgs.length,svgRendered:renders.length,totalImageFiles:imagePaths.length,unreferencedLibraryImages:allLibraryImages.filter(x=>!referred.has(x)).length,negativeControls:negativeControls.length+media.negativeControls.length+1},
 snapshots:initialInputs,
 checks,primaryPortraits:media.crops,rasterImages:media.rasters,svgRenders:renders,
 unreferencedLibraryImages:allLibraryImages.filter(x=>!referred.has(x)),
 limitations:['All referenced scene/UI IDs are validated; UI pages without physical-asset mappings are reported separately.','Raster decode checks every PNG/JPG file in the production tree, including any unreferenced files. SVGs are parsed and rendered individually.','No production asset was changed by negative controls; failures are injected only into in-memory catalogs, XML strings and raster byte buffers.','A passing report certifies the above checks for its recorded hashes, not 3D models, exact historical reconstruction, rights clearance, browser rendering or full visual review.']
};
fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n','utf8');
console.log('RESOURCE_LIBRARY_VERIFIED '+JSON.stringify(report.summary));
if(failed){for(const c of checks.filter(x=>x.status==='failed'))console.error(c.id+': '+JSON.stringify(c.errors));process.exitCode=1;}

