import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
const dir=path.dirname(fileURLToPath(import.meta.url)),reader=path.resolve(dir,'../zheng-zhilong');
const read=f=>fs.readFileSync(f),json=f=>JSON.parse(read(f)),hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const source=read(path.resolve(dir,'../zheng-zhilong-story.json')),sourceSha256=hash(source),story=JSON.parse(source),checks=[];
const check=(value,name)=>checks.push({name,passed:!!value});
check(source.equals(read(path.join(dir,'candidate.json'))),'source equals reviewed illustrated candidate');
check(source.equals(read(path.join(reader,'zheng-zhilong-story.json'))),'reader mirror equals source');
check(story.version==='historical-reboot-illustrated-2026-10-24','explicit edition');
for(const file of ['adoption.json','decode-verification.json','export-verification.json','cli-verification.json','public-verification.json','dom-verification.json']){
 const r=json(path.join(dir,file));check(r.sourceSha256===sourceSha256,file+' bound to source');if('passed'in r)check(r.passed,file+' passed');
}
const manifest=json(path.join(reader,'illustration-manifest.json'));
const qa=['QA-EARLY.json','QA-LATE.json','QA-ROOT.json','QA-SUPPLEMENT.json'].flatMap(f=>json(path.join(dir,f)).reviews);
check(manifest.sourceSha256===sourceSha256&&manifest.illustrations.length===44,'44-image manifest bound to source');
check(qa.length===44&&new Set(qa.map(r=>r.id)).size===44,'44 independent final visual reviews');
for(const i of manifest.illustrations)check(hash(read(path.join(reader,i.image)))===i.sha256&&qa.some(q=>q.id===i.id&&q.sha256===i.sha256&&q.status==='accepted'),i.id+' selected bytes reviewed');
const publicReport=json(path.join(dir,'public-verification.json'));
check(publicReport.files.length===53,'53 public files checked');for(const f of publicReport.files)check(f.passed&&hash(read(path.join(reader,f.file)))===f.sha256,'public evidence current '+f.file);
const earlier=json(path.join(dir,'previous-evidence.json'));for(const [f,h]of Object.entries(earlier.hashes))check(hash(read(path.resolve(dir,'..',earlier.directory,f)))===h,'previous-round evidence preserved '+f);
for(const file of [path.join(dir,'DELIVERY.md'),path.join(reader,'README.md')]){
 const text=read(file).toString();check(text.includes(sourceSha256),path.basename(file)+' identifies final source');
 for(const m of text.matchAll(/\]\(([^)]+)\)/g)){const target=m[1];if(/^[a-z]+:\/\//i.test(target)||target.startsWith('#'))continue;check(fs.existsSync(path.resolve(path.dirname(file),target.split('#')[0])),path.basename(file)+' link '+target);}
}
check(!read(path.join(dir,'PLAN.md')).toString().includes('- [ ]'),'planned work complete');
const report={checkedAt:new Date().toISOString(),sourceSha256,passed:checks.every(c=>c.passed),checks};
fs.writeFileSync(path.join(dir,'final-gate.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({passed:report.passed,checks:checks.length,sourceSha256,failures:checks.filter(c=>!c.passed)}));process.exitCode=report.passed?0:1;
