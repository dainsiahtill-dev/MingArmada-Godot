import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
const here=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(here,'../../../..');
const source=path.join(root,'docs/narrative/zheng-zhilong-story.json');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const expected='a2a1131ee38683e6530eda7ca86370b93896260d81fb1674894dfb0b0ed67b2e';
const baseline=fs.readFileSync(path.join(here,'before-story.json'));
if(hash(baseline)!==expected||hash(fs.readFileSync(source))!==expected)throw Error('Readthrough source changed; do not replay.');
const story=JSON.parse(baseline),scene=story.acts.flatMap(a=>a.scenes).find(s=>s.id==='yiguan_a2_s3');
const patches=[
 {paragraph:2,after:'杜七摊开周船主的货记号，指着代理的泊地，要叫人去夺。一官拦住他：货夺回来，也得有船运出去。阮老六的人这时送来新木筹，路钱照旧；往后替他指认装得足的船，可以少收两成。杜七把那块筹翻过来，丢在板上。',reason:'明确此时想追讨的是代理扣下的周船主货物；后续先夺阮老六的快船，不将两方混成同一货主。'},
 {paragraph:12,after:'前舱捆着四个人，一人肩上的旧伤被绳勒开。一官割断绑绳，四人报出姓名，指认舱里被阮老六夺去的货。杜七拿周船主的记号逐包对过，没有那两包生丝。货主搬到最后几包，杜七伸手拦住，要留下算作战利。一官把货签转向认货的人。那人念出自己的姓，杜七松开了手。',reason:'区分获救货主取回自己的货与仍未追回的周船主生丝，保留杜七想留战利、一官让货主领回的冲突。'}
].map(p=>({id:scene.id,field:'paragraphs',...p,before:scene.paragraphs[p.paragraph-1]}));
for(const p of patches)scene.paragraphs[p.paragraph-1]=p.after;
story.version='v7-readthrough-2026-10-23';
story.editorialRevision={...story.editorialRevision,previousReport:story.editorialRevision.report,report:'rewrites/v7-readthrough-2026-10-23/READTHROUGH-REPORT.md',beforeSourceSha256:expected,scope:'Complete continuous reading and character-voice audit; two paragraphs in one scene clarify cargo ownership. No structural rewrite or deletion target.'};
const after=JSON.stringify(story,null,2)+'\n';
fs.writeFileSync(source,after);
const chars=s=>s.acts.flatMap(a=>a.scenes.flatMap(s=>s.paragraphs)).join('').length;
const changes={beforeSha256:expected,afterSha256:hash(after),beforeCharacters:chars(JSON.parse(baseline)),afterCharacters:chars(story),patches};
fs.writeFileSync(path.join(here,'changes.json'),JSON.stringify(changes,null,2)+'\n');
const html=path.join(root,'docs/narrative/zheng-zhilong/index.html');
fs.writeFileSync(html,fs.readFileSync(html,'utf8').replaceAll('20261023-v7-second-pass','20261023-v7-readthrough'));
console.log(JSON.stringify({version:story.version,editedScenes:1,paragraphChanges:2,...changes,patches:undefined}));
