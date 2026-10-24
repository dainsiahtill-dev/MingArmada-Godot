import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import crypto from 'node:crypto';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {storyStructure,aliasIssues} from './zheng-story-contract.mjs';
import {renderRebootExports,editorialOutputDirectory} from './render-zheng-reboot-exports.mjs';
import {rebootAliases} from './zheng-reboot-aliases.mjs';
import {illustratedVersion,validateIllustrations} from './zheng-illustration-contract.mjs';
export {validateIllustrations} from './zheng-illustration-contract.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
export function verifyReboot({story,writeReport=true}={}){
 const relative='docs/narrative/zheng-zhilong-story.json',reader='docs/narrative/zheng-zhilong';
 const bytes=fs.readFileSync(path.join(root,relative));
 story??=JSON.parse(bytes);
 const checks=[],check=(value,name)=>checks.push({name,passed:!!value,scope:'text'}),illustrated=story.version===illustratedVersion;
 let structure;
 try{structure=storyStructure(story);check(structure.edition==='historical-reboot','explicit historical edition');}catch(e){check(false,e.message);}
 const expected=[4,4,4,4,3,3],seen=new Set();let year=0,paragraphs=0,dialogues=0,characters=0;
 check(story.acts?.length===6,'six parts');
 check(story.illustrationStatus===(illustrated?'ready':'text-only'),illustrated?'new illustration edition explicitly ready':'new text does not claim old artwork');
 check(story.characters?.length>0,'historical cast provided');
 check(aliasIssues(story).length===0,'all 63 old links have direct navigation successors');
 check(Object.entries(rebootAliases).every(([id,target])=>story.legacySceneAliases?.[id]===target),'all published bookmarks keep audited historical periods');
 for(const [a,act] of (story.acts||[]).entries()){
  check(act.id===`act-${a+1}`,'part id '+act.id);
  check(act.scenes?.length===expected[a],'chapter count '+act.id);
  check(!!act.title&&!!act.readerHook&&!!act.synopsis,'part metadata '+act.id);
  check(a===5||!!act.nextHook,'part transition '+act.id);
  check(!act.cover,'no inherited cover '+act.id);
  for(const [b,s] of (act.scenes||[]).entries()){
   check(s.id===`zzl_a${a+1}_s${b+1}`&&!seen.has(s.id),'new chapter identity '+s.id);seen.add(s.id);
   for(const k of ['title','year','location','summary','readerTeaser','task'])check(typeof s[k]==='string'&&s[k].trim(),s.id+':'+k);
   const first=Number(s.year?.match(/16\d\d/)?.[0]);check(first>=year&&first<=1646,s.id+':time sequence');year=first;
   check(Array.isArray(s.paragraphs)&&s.paragraphs.length>=2&&s.paragraphs.every(p=>typeof p==='string'&&p.trim()),s.id+':complete prose');
   check(Array.isArray(s.dialogue)&&s.dialogue.length>=2&&s.dialogue.every(d=>d.speaker&&d.text&&s.paragraphs.some(p=>p.includes(d.text))),s.id+':dialogue exact in prose');
   check(Array.isArray(s.choices)&&s.choices.length===0,s.id+':fixed historical events');
   check(s.history?.level==='adaptation'&&!!s.history.note,s.id+':reconstruction boundary');
   check(s.history?.sources?.length>0&&s.history.sources.every(q=>q.title&&/^https?:\/\//.test(q.url)),s.id+':attributed sources');
   check(['want','obstacle','decision','result','next'].every(k=>s.dramaticBeat?.[k]?.trim()),s.id+':causal editorial notes');
   if(!illustrated)check(!s.image&&!(s.illustrations||[]).length,s.id+':no reused fictional scene picture');
   paragraphs+=s.paragraphs.length;dialogues+=s.dialogue.length;characters+=s.paragraphs.join('').length;
  }
 }
 check(seen.size===22,'all 22 chapters');
 const mirror=fs.readFileSync(path.join(root,reader,'zheng-zhilong-story.json'));
 check(mirror.equals(bytes),'download JSON byte-identical');
 const data=fs.readFileSync(path.join(root,reader,'story-data.js'),'utf8'),context={window:{}};
 vm.runInNewContext(data,context,{timeout:2000});check(JSON.stringify(context.window.ZHENG_STORY)===JSON.stringify(story),'classic script matches source');
 const html=fs.readFileSync(path.join(root,reader,'index.html'),'utf8');
 check(!/<(?:script|link)\b[^>]*(?:src|href)=["']https?:/i.test(html),'local runtime dependencies');
 check(html.indexOf('story-data.js')<html.indexOf('app.js'),'data loads before app');
 const script=fs.readFileSync(path.join(root,reader,'app.js'),'utf8');
 try{new vm.Script(script);check(true,'reader syntax');}catch(e){check(false,'reader syntax '+e.message);}
 check(!/\bfetch\s*\(/.test(script),'file-protocol-compatible data load');
 for(const [name,expectedText] of Object.entries(renderRebootExports(story))) {
  const destination=name==='CAUSE-CHAIN.md'?editorialOutputDirectory(story):reader;
  const file=path.join(root,destination,name);
  check(fs.existsSync(file)&&fs.readFileSync(file,'utf8')===expectedText,'complete same-source export '+name);
 }
 const sourceSha256=crypto.createHash('sha256').update(bytes).digest('hex');
 let illustrationValidation={status:'not-applicable-text-edition',valid:true};
 if(illustrated){
  try{
   const baselineBytes=fs.readFileSync(path.join(root,'docs/narrative/full-polish-2026-10-24/candidate.json'));
   const result=validateIllustrations({story,manifest:JSON.parse(fs.readFileSync(path.join(root,reader,'illustration-manifest.json'),'utf8')),sourceSha256,baselineStory:JSON.parse(baselineBytes),baselineSourceSha256:crypto.createHash('sha256').update(baselineBytes).digest('hex'),readImage:image=>fs.readFileSync(path.join(root,reader,image))});
   checks.push(...result.checks);illustrationValidation={...result,status:result.valid?'passed':'failed'};
  }catch(error){checks.push({name:'illustration:resources '+error.message,passed:false,scope:'illustration'});illustrationValidation={status:'failed',valid:false};}
 }
 const failures=checks.filter(c=>!c.passed),valid=!failures.length,textValid=checks.filter(c=>c.scope==='text').every(c=>c.passed);
 const report={version:story.version,sourceSha256,status:valid?'passed':'failed',valid,summary:{checks:checks.length,passed:checks.length-failures.length,failed:failures.length,acts:6,scenes:seen.size,paragraphs,dialogues,characters,...(illustrationValidation.summary||{expectedIllustrations:illustrated?44:0,presentImages:0,uniqueImageHashes:0})},checks,failures,textValidation:{status:textValid?'passed':'failed',valid:textValid},illustrationValidation,browserValidation:{status:'not-assessed'},scope:'Text, attribution presence, structure, exports and (for the explicit illustrated edition) PNG resource integrity. Generation provenance, source reliability, literary engagement and browser visuals require independent evidence.'};
 if(writeReport)fs.writeFileSync(path.join(root,reader,'verification.json'),JSON.stringify(report,null,2)+'\n');
 return report;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){try{const r=verifyReboot();console.log(JSON.stringify({status:r.status,...r.summary,sourceSha256:r.sourceSha256}));for(const f of r.failures)console.error(f.name);process.exitCode=r.valid?0:1;}catch(e){console.error(e.message);process.exitCode=1;}}
