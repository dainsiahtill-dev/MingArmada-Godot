// One-time assembly of independent literary proposals. Never runs the V7 assembler.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const here=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(here,'../../../..');
const source=path.join(root,'docs/narrative/zheng-zhilong-story.json');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const baseline=fs.readFileSync(path.join(here,'before-story.json'));
const expected='7a5f37d3fe93193671cb8b7201b9a7f0b2765bc978a6979d94e0421dce73ceca';
if(hash(baseline)!==expected||hash(fs.readFileSync(source))!==expected)throw Error('Baseline/source guard failed; do not overwrite a later edit.');
const story=JSON.parse(baseline);
const scenes=story.acts.flatMap(a=>a.scenes),byId=new Map(scenes.map(s=>[s.id,s]));
const allowed=new Set(['paragraphs','dialogue','summary','task','dramaticBeat','dramaticMode','currentCanon','readerTeaser','suspense']);
const preserved=new Set(['yiguan_a3_s3','yiguan_a4_s2','yiguan_a5_s1']);
const proposed=new Map();
for(const name of ['opening','partners','family']){
 const p=JSON.parse(fs.readFileSync(path.join(here,`${name}-proposal.json`),'utf8'));
 if(p.baselineSha256!==expected)throw Error(`${name}: wrong baseline`);
 for(const candidate of p.scenes){
  const old=byId.get(candidate.id);
  if(!old||preserved.has(candidate.id)||proposed.has(candidate.id))throw Error(`Unexpected/duplicate scene ${candidate.id}`);
  if(JSON.stringify(Object.keys(old).sort())!==JSON.stringify(Object.keys(candidate).sort()))throw Error(`${candidate.id}: field-set drift`);
  for(const key of Object.keys(old))if(!allowed.has(key)&&JSON.stringify(old[key])!==JSON.stringify(candidate[key]))throw Error(`${candidate.id}: protected ${key}`);
  if(candidate.paragraphs.length!==old.paragraphs.length||candidate.paragraphs.some(p=>typeof p!=='string'||!p.trim()))throw Error(`${candidate.id}: paragraph drift`);
  if(JSON.stringify(old.paragraphs)===JSON.stringify(candidate.paragraphs))throw Error(`${candidate.id}: no body edit`);
  proposed.set(candidate.id,candidate);
 }
}
if(proposed.size!==17)throw Error(`Expected seventeen proposals, received ${proposed.size}`);
for(const act of story.acts)act.scenes=act.scenes.map(s=>proposed.get(s.id)||s);
story.version='v7-full-polish-2026-10-23';
story.subtitle='五幕二十场 · 文学剧本第七稿·全卷节奏修订 · 1621—1646';
story.editorialRevision={...story.editorialRevision,date:'2026-10-23',
 previousReport:story.editorialRevision.report,
 report:'rewrites/v7-full-polish-2026-10-23/EDITING-REPORT.md',
 beforeSourceSha256:expected,
 scope:'Subtractive edit of the remaining seventeen scenes; preserve the prior three confrontations, history, causal chains and illustration anchors. Independent reading and current browser evidence required.'};
fs.writeFileSync(source,JSON.stringify(story,null,2)+'\n');
console.log(JSON.stringify({proposedScenes:proposed.size,preservedScenes:[...preserved],version:story.version}));
