import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {verifyReboot} from '../../../tools/verify-zheng-reboot.mjs';
const dir=path.dirname(fileURLToPath(import.meta.url)),reader=path.resolve(dir,'../zheng-zhilong'),sourcePath=path.resolve(dir,'../zheng-zhilong-story.json');
const source=fs.readFileSync(sourcePath),story=JSON.parse(source),hash=b=>crypto.createHash('sha256').update(b).digest('hex');
if(story.version!=='historical-reboot-illustrated-2026-10-24'||story.illustrationRevision?.report!=='illustrated-2026-10-24/DELIVERY.md')throw new Error('Current source is not this illustrated edition');
const local=verifyReboot({writeReport:false});if(!local.valid)throw new Error('Build/exports/illustrations not current: '+local.failures.map(f=>f.name).join(', '));
const images=story.acts.flatMap(a=>a.scenes.flatMap(s=>s.illustrations.map(i=>i.image)));
const files=['index.html','app.js','styles.css','story-data.js','zheng-zhilong-story.json','illustration-manifest.json','novel.md','screenplay.md','game-scenes.md',...images];
const base='http://8.138.113.205:18794/docs/narrative/zheng-zhilong/',results=[];
for(let i=0;i<files.length;i+=6){const batch=await Promise.all(files.slice(i,i+6).map(async file=>{try{const response=await fetch(base+file+'?verify='+Date.now(),{signal:AbortSignal.timeout(45000),cache:'no-store'});const bytes=Buffer.from(await response.arrayBuffer()),expected=fs.readFileSync(path.join(reader,file));return {file,status:response.status,bytes:bytes.length,sha256:hash(bytes),sameAsLocal:bytes.equals(expected),passed:response.ok&&bytes.equals(expected)};}catch(error){return {file,passed:false,error:error.message};}}));results.push(...batch);console.log('HTTP checked '+results.length+'/'+files.length);}
const sourceUnchanged=source.equals(fs.readFileSync(sourcePath));const report={checkedAt:new Date().toISOString(),sourceSha256:hash(source),version:story.version,sourceUnchanged,localSourceAndExportsVerified:true,url:base+'?edition=11#top',passed:sourceUnchanged&&results.length===53&&results.every(r=>r.passed),files:results,scope:'All 44 image files and 9 reader/data/export files via public HTTP. Not browser layout or visual-historical evidence.'};
fs.writeFileSync(path.join(dir,'public-verification.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({passed:report.passed,files:results.length,images:images.length,sourceSha256:report.sourceSha256,failures:results.filter(r=>!r.passed)}));process.exitCode=report.passed?0:1;
