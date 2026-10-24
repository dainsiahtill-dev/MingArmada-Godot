import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
const dir=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(dir,'../../..');
const current=JSON.parse(fs.readFileSync(path.join(root,'docs/narrative/zheng-zhilong-story.json')));
if(current.editorialRevision?.report!=='reboot-2026-10-23/DELIVERY.md')throw new Error('This archived verification entry cannot overwrite another round evidence');
const base='http://8.138.113.205:18794/docs/narrative/zheng-zhilong/';
const files=['index.html','app.js','styles.css','story-data.js','zheng-zhilong-story.json','novel.md','screenplay.md','game-scenes.md'];
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const results=await Promise.all(files.map(async file=>{
  try {
    const response=await fetch(base+file+'?edition=11&verify='+Date.now(),{signal:AbortSignal.timeout(30000),cache:'no-store'});
    const remote=Buffer.from(await response.arrayBuffer());
    const local=fs.readFileSync(path.join(root,'docs/narrative/zheng-zhilong',file));
    return {file,status:response.status,bytes:remote.length,sha256:hash(remote),sameAsLocal:remote.equals(local),passed:response.ok&&remote.equals(local)};
  } catch(error) {return {file,passed:false,error:error.message};}
}));
const report={checkedAt:new Date().toISOString(),url:base+'?edition=11#top',sourceSha256:hash(fs.readFileSync(path.join(root,'docs/narrative/zheng-zhilong-story.json'))),passed:results.every(r=>r.passed),files:results,scope:'Public HTTP responses byte-equal to local files; not rendered-browser or visual evidence.'};
fs.writeFileSync(path.join(dir,'public-verification.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report));
process.exitCode=report.passed?0:1;
