import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {rebootAliases} from '../../../tools/zheng-reboot-aliases.mjs';
import {storyStructure,aliasIssues} from '../../../tools/zheng-story-contract.mjs';
const dir=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(dir,'../../..');
const file=path.join(root,'docs/narrative/zheng-zhilong-story.json');
const original=fs.readFileSync(file),story=JSON.parse(original);
if(story.narrativeContract?.edition!=='historical-reboot')throw new Error('Only the new manuscript may be edited');
if(story.editorialRevision?.report!=='reboot-2026-10-23/DELIVERY.md')throw new Error('This archived merge cannot replace a later editorial round');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const acts=['parts-1-2.json','parts-3-4.json','parts-5-6.json'].flatMap(f=>JSON.parse(fs.readFileSync(path.join(dir,f),'utf8')).acts);
const changes=[];
for(const [ai,a] of acts.entries()) {
 if(a.id!==story.acts[ai].id)throw new Error('Unexpected part identity');
 a.illustrationStatus='text-only';
 for(const [si,s] of a.scenes.entries()) {
  s.illustrationStatus='text-only';s.dialogueInParagraphs=true;
  if(s.id!==story.acts[ai].scenes[si].id)throw new Error('Unexpected chapter identity');
  if(JSON.stringify(s)!==JSON.stringify(story.acts[ai].scenes[si]))changes.push(s.id);
  if(!s.dialogue.every(d=>s.paragraphs.some(p=>p.includes(d.text))))throw new Error('Dialogue mismatch '+s.id);
 }
}
story.acts=acts;story.legacySceneAliases={...rebootAliases};
for(const character of [
 {name:'陈谦',role:'与郑芝龙有旧的明方将领，曾奉弘光诏授郑封爵，后奉鲁王使赴闽，在隆武朝遭杀害。案件细节依后出史籍，私人现场为重建。'},
 {name:'郭必昌',role:'与郑芝龙交厚的泉州乡绅，参与清方招纳传书。身份关系据《明季南略》，具体递送现场为重建。'}
])if(!story.characters.some(c=>c.name===character.name))story.characters.push(character);
if(!story.editorialRevision.research.includes('reboot-2026-10-23/SOURCES-SUPPLEMENT.md')) story.editorialRevision.research.push('reboot-2026-10-23/SOURCES-SUPPLEMENT.md');
storyStructure(story);const issues=aliasIssues(story);if(issues.length)throw new Error(issues.join('\n'));
const output=JSON.stringify(story,null,2)+'\n';fs.writeFileSync(file,output);
const record={at:new Date().toISOString(),before:hash(original),after:hash(output),chaptersChanged:changes};
fs.appendFileSync(path.join(dir,'editorial-merges.jsonl'),JSON.stringify(record)+'\n');
console.log(JSON.stringify(record));
