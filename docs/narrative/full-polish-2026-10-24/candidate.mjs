import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {storyStructure,aliasIssues} from '../../../tools/zheng-story-contract.mjs';
const dir=path.dirname(fileURLToPath(import.meta.url));
const original=fs.readFileSync(path.join(dir,'baseline.json')),story=JSON.parse(original),baseline=JSON.parse(original);
const acts=['parts-1-2.json','parts-3-4.json','parts-5-6.json'].flatMap(f=>JSON.parse(fs.readFileSync(path.join(dir,f),'utf8').replace(/^\uFEFF/,'')).acts);
const coverage=[];
if(acts.length!==6)throw new Error('Incomplete six-part manuscript');
for(const [ai,a] of acts.entries()) {
 const old=baseline.acts[ai];if(a.id!==old.id||a.scenes.length!==old.scenes.length)throw new Error('Changed structure '+a.id);
 a.illustrationStatus='text-only';
 for(const [si,s] of a.scenes.entries()) {
  const before=old.scenes[si];if(s.id!==before.id)throw new Error('Changed chapter identity');
  if(!s.paragraphs?.length||!s.dialogue?.every(d=>s.paragraphs.some(p=>p.includes(d.text))))throw new Error('Incomplete prose or quoted dialogue '+s.id);
  if(!s.history?.sources?.length||!s.history?.note)throw new Error('Missing history boundary '+s.id);
  s.dialogueInParagraphs=true;s.illustrationStatus='text-only';
  coverage.push({id:s.id,title:s.title,proseChanged:JSON.stringify(before.paragraphs)!==JSON.stringify(s.paragraphs),beforeCharacters:before.paragraphs.join('').length,afterCharacters:s.paragraphs.join('').length,paragraphs:s.paragraphs.length});
 }
}
story.acts=acts;story.version='historical-reboot-polish-2026-10-24';
story.editorialRevision={...story.editorialRevision,polished:'2026-10-24',scope:'Whole-novel scene, voice, rhythm and continuity polish of the independent historical reconstruction.',report:'full-polish-2026-10-24/DELIVERY.md',baselineSourceSha256:crypto.createHash('sha256').update(original).digest('hex'),research:[...story.editorialRevision.research,'full-polish-2026-10-24/HISTORY-CHECK.md']};
story.sourceNotes[0]='本作于2026年10月23—24日依据新查史料独立重构，未采用重构以前的小说情节。24日再以这部新作为基线进行全卷精修，保留史料边界。';
if(!story.characters.some(c=>c.name.includes('七左卫门')))story.characters.push({name:'田川七左卫门',role:'郑芝龙与田川氏之子、郑成功之弟，留在日本。亲属关系据机构介绍及晚出编纂，小说中的家信与私人牵挂为重建，未核诉状原件。'});
if(acts.some(a=>a.scenes.some(s=>s.paragraphs.some(p=>p.includes('阿旺')))))story.characters.push({name:'阿旺',role:'本轮创作的虚构水手，不对应已知史籍人物。用于呈现早期入伙、分成、修船和追随中的普通人利益；其私人经历不作为史实。'});
storyStructure(story);const issues=aliasIssues(story);if(issues.length)throw new Error(issues.join('\n'));
const output=JSON.stringify(story,null,2)+'\n',sha=crypto.createHash('sha256').update(output).digest('hex');
fs.writeFileSync(path.join(dir,'candidate.json'),output);
fs.writeFileSync(path.join(dir,'coverage.json'),JSON.stringify({baselineSha256:story.editorialRevision.baselineSourceSha256,candidateSha256:sha,scope:'Editorial coverage and differences, not a literary quality score.',chapters:coverage},null,2)+'\n');
console.log(JSON.stringify({candidateSha256:sha,chapters:coverage.length,proseChanged:coverage.filter(x=>x.proseChanged).length,characters:coverage.reduce((n,c)=>n+c.afterCharacters,0)}));
