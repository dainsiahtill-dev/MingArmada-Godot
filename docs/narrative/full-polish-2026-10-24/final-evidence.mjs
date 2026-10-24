import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
const dir=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(dir,'../../..'),reader=path.resolve(dir,'../zheng-zhilong');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex'),read=f=>fs.readFileSync(f),json=f=>JSON.parse(read(f));
const source=read(path.resolve(dir,'../zheng-zhilong-story.json')),sha=hash(source),story=JSON.parse(source),checks=[];
const check=(passed,name)=>checks.push({name,passed:!!passed});
check(source.equals(read(path.join(dir,'candidate.json'))),'adopted source equals final candidate');
check(source.equals(read(path.join(reader,'zheng-zhilong-story.json'))),'reader mirror equals source');
check(story.version==='historical-reboot-polish-2026-10-24','final edition');
for(const file of ['adoption.json','export-verification.json','cli-verification.json','public-verification.json','dom-verification.json','guard-verification.json']){
 const report=json(path.join(dir,file));check(report.sourceSha256===sha,file+' identifies final source');
 if('passed' in report)check(report.passed,file+' passed');
}
const coverage=json(path.join(dir,'coverage.json'));check(coverage.candidateSha256===sha&&coverage.chapters.length===22&&coverage.chapters.every(c=>c.proseChanged),'22 chapters polished in final candidate');
check(read(path.join(dir,'FINAL-REVIEW.md')).toString().includes(sha),'independent review identifies final source');
const pub=json(path.join(dir,'public-verification.json'));
for(const f of pub.files)check(f.passed&&hash(read(path.join(reader,f.file)))===f.sha256,'public verification still identifies local '+f.file);
const guards=json(path.join(dir,'guard-verification.json'));
for(const [f,h] of Object.entries(guards.before).filter(([f])=>f.includes('/reboot-2026-10-23/')))check(hash(read(path.join(root,f)))===h,'previous-round evidence preserved '+path.basename(f));
for(const file of [path.join(dir,'DELIVERY.md'),path.join(reader,'README.md')]){
 const text=read(file).toString();check(text.includes(sha),path.basename(file)+' identifies final source');
 for(const match of text.matchAll(/\]\(([^)]+)\)/g)){const target=match[1];if(/^[a-z]+:\/\//i.test(target)||target.startsWith('#'))continue;check(fs.existsSync(path.resolve(path.dirname(file),target.split('#')[0])),path.basename(file)+' link '+target);}
}
check(!read(path.join(dir,'PLAN.md')).toString().includes('- [ ]'),'plan complete');
const report={checkedAt:new Date().toISOString(),sourceSha256:sha,passed:checks.every(c=>c.passed),checks};
fs.writeFileSync(path.join(dir,'final-gate.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({passed:report.passed,checks:checks.length,sourceSha256:sha,failures:checks.filter(c=>!c.passed)}));process.exitCode=report.passed?0:1;
