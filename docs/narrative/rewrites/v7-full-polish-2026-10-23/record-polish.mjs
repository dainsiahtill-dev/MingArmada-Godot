// Compare the final coordinated text with this task's frozen source.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
const here=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(here,'../../../..');
const read=p=>fs.readFileSync(p);
const digest=b=>crypto.createHash('sha256').update(b).digest('hex');
const oldBytes=read(path.join(here,'before-story.json'));
const newBytes=read(path.join(root,'docs/narrative/zheng-zhilong-story.json'));
const old=JSON.parse(oldBytes),now=JSON.parse(newBytes);
const all=s=>s.acts.flatMap(a=>a.scenes);
const metrics=s=>({acts:s.acts.length,scenes:all(s).length,paragraphs:all(s).reduce((n,x)=>n+x.paragraphs.length,0),characters:all(s).reduce((n,x)=>n+x.paragraphs.join('').length,0),dialogue:all(s).reduce((n,x)=>n+x.dialogue.length,0),aliases:Object.keys(s.legacySceneAliases).length,processFrames:all(s).reduce((n,x)=>n+(x.illustrations||[]).length,0)});
const allowed=new Set(['paragraphs','dialogue','summary','task','dramaticBeat','dramaticMode','currentCanon','readerTeaser','suspense']);
const preserved=['yiguan_a3_s3','yiguan_a4_s2','yiguan_a5_s1'];
const changes=[];let protectedComparisons=0;
if(now.version!=='v7-full-polish-2026-10-23')throw Error('Wrong current source version');
if(JSON.stringify(old.legacySceneAliases)!==JSON.stringify(now.legacySceneAliases))throw Error('Legacy alias drift');
for(const [i,a] of now.acts.entries()){
 const oa=old.acts[i];
 for(const key of Object.keys(oa))if(!['scenes','readerHook','nextHook','synopsis','suspense'].includes(key)&&JSON.stringify(a[key])!==JSON.stringify(oa[key]))throw Error(`${a.id}: protected act ${key}`);
 for(const [j,s] of a.scenes.entries()){
  const b=oa.scenes[j];
  if(JSON.stringify(Object.keys(s).sort())!==JSON.stringify(Object.keys(b).sort()))throw Error(`${s.id}: field drift`);
  for(const key of Object.keys(b))if(!allowed.has(key)){
   if(JSON.stringify(s[key])!==JSON.stringify(b[key]))throw Error(`${s.id}: protected ${key}`);
   protectedComparisons++;
  }
  if(b.paragraphs.length!==s.paragraphs.length)throw Error(`${s.id}: paragraph count`);
  const paragraphs=s.paragraphs.map((after,k)=>({paragraph:k+1,before:b.paragraphs[k],after})).filter(x=>x.before!==x.after);
  if(preserved.includes(s.id)&&paragraphs.length)throw Error(`${s.id}: prior focus body changed`);
  if(!preserved.includes(s.id)&&!paragraphs.length)throw Error(`${s.id}: missing editorial pass`);
  changes.push({id:s.id,title:s.title,paragraphCount:s.paragraphs.length,beforeCharacters:b.paragraphs.join('').length,afterCharacters:s.paragraphs.join('').length,changedParagraphs:paragraphs.length,paragraphs,beforeTeaser:b.readerTeaser,afterTeaser:s.readerTeaser,lastParagraph:s.paragraphs.at(-1),nextScene:all(now)[all(now).findIndex(x=>x.id===s.id)+1]?.id||null});
 }
}
const before=metrics(old),after=metrics(now);
for(const k of ['acts','scenes','paragraphs','aliases','processFrames'])if(before[k]!==after[k])throw Error(`Count drift ${k}`);
const report={baselineSha256:digest(oldBytes),sourceSha256:digest(newBytes),unit:'JavaScript string length; body paragraphs concatenated without separators; includes punctuation',before,after,removedCharacters:before.characters-after.characters,protectedComparisons,preservedSceneBodies:preserved,changes};
fs.writeFileSync(path.join(here,'changes.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({...report,changes:changes.map(({id,beforeCharacters,afterCharacters,changedParagraphs})=>({id,beforeCharacters,afterCharacters,changedParagraphs}))}));
