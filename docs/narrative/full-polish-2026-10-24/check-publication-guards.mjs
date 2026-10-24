import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const dir=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(dir,'../../..');
const source='docs/narrative/zheng-zhilong-story.json';
const story=JSON.parse(fs.readFileSync(path.join(root,source),'utf8'));
if(story.version!=='historical-reboot-polish-2026-10-24')throw new Error('Adopt the reviewed polish first');
const protectedFiles=[source,...['DELIVERY.md','CAUSE-CHAIN.md','export-verification.json','public-verification.json'].map(f=>'docs/narrative/reboot-2026-10-23/'+f),...['novel.md','screenplay.md','game-scenes.md','app.js','index.html'].map(f=>'docs/narrative/zheng-zhilong/'+f)];
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,file))).digest('hex');
const before=Object.fromEntries(protectedFiles.map(f=>[f,hash(f)]));
const cases=[
 ['docs/narrative/reboot-2026-10-23/export.mjs','This archived export entry cannot publish another editorial round'],
 ['docs/narrative/reboot-2026-10-23/verify-http.mjs','This archived verification entry cannot overwrite another round evidence'],
 ['docs/narrative/reboot-2026-10-23/merge-revisions.mjs','This archived merge cannot replace a later editorial round'],
 ['docs/narrative/full-polish-2026-10-24/verify-http.mjs','Build and exports are not current:']
];
const results=cases.map(([file,message])=>{const r=spawnSync(process.execPath,[path.join(root,file)],{cwd:root,encoding:'utf8',timeout:40000});const output=(r.stdout||'')+(r.stderr||'');return {file,exitCode:r.status,expectedError:message,matched:output.includes(message),passed:r.status!==null&&r.status!==0&&output.includes(message)};});
const protectedUnchanged=protectedFiles.every(f=>hash(f)===before[f]);
const report={checkedAt:new Date().toISOString(),sourceSha256:hash(source),scope:'Run immediately after adoption, before rebuilding stale reader files. Expected failures prove version/ownership/current-artifact guards.',passed:protectedUnchanged&&results.every(r=>r.passed),protectedUnchanged,before,results};
fs.writeFileSync(path.join(dir,'guard-verification.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report));process.exitCode=report.passed?0:1;
