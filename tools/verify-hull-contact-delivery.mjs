import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
const base=process.cwd(), evidence=path.join(base,'docs/migration/evidence/hull-contact-redesign-2026-10-14');
const sha=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const checks=[
 'hull-contact-froth-green.json','hull-contact-owner-final-review-20261014.json',
 'hull-contact-owner-tail-final-review-20261014.json','hull-waterline-independent-review-20261014.json',
 'hull-contact-final.json','hull-contact-final-tail-checks.json','hull-contact-packet-regression.json'];
fs.mkdirSync(path.join(evidence,'checks'),{recursive:true});
const receipts=checks.map(name=>{
 const source=path.join(base,'Temp',name),doc=JSON.parse(fs.readFileSync(source,'utf8').replace(/^\uFEFF/,''));
 fs.copyFileSync(source,path.join(evidence,'checks',name));
 return {name,summary:doc.summary,valid:doc.summary?.passedAll===true};
});
const tail=JSON.parse(fs.readFileSync(path.join(base,'Temp/hull-contact-tail-preserved.json'),'utf8'));
tail.entries=tail.entries.map(entry=>({...entry,current:sha(path.join(base,'modules/scene_engine/water',entry.name))}));
tail.unchanged=tail.entries.every(entry=>entry.sha256===entry.current);
fs.writeFileSync(path.join(evidence,'checks/tail-preserved.json'),JSON.stringify(tail,null,2));
const depth=JSON.parse(fs.readFileSync(path.join(evidence,'depth/current/VERIFICATION.json'),'utf8'));
const missing=[];
for(const phase of ['before','after'])for(const angle of ['low-front','low-side','high'])for(const frame of [64,72,80,88,96,192,256]){
 const file=path.join(evidence,phase,angle,'all',`t${String(frame).padStart(3,'0')}.png`);if(!fs.existsSync(file))missing.push(file);
}
for(const frame of [64,72,80,88,96])if(!fs.existsSync(path.join(evidence,'after/low-front-heave/all',`t${String(frame).padStart(3,'0')}.png`)))missing.push('heave '+frame);
for(const file of ['live-wide-01.jpg','live-close-01.jpg','live-close-02.jpg'])if(!fs.existsSync(path.join(evidence,file)))missing.push(file);
let links=0;
for(const file of [path.join(evidence,'review.html'),path.join(base,'docs/migration/hull-contact-redesign-2026-10-14.md')]){
 const body=fs.readFileSync(file,'utf8');const regex=file.endsWith('.html')?/href="([^"]+)"/g:/\]\(([^)]+)\)/g;
 for(const match of body.matchAll(regex)){if(/^(https?:|#)/.test(match[1]))continue;links++;const target=path.resolve(path.dirname(file),match[1]);if(!fs.existsSync(target))missing.push(target);}
}
const code=['game/presentation/ships/hull_waterline_profile.gd','game/presentation/world/source_water_packet.gd','modules/scene_engine/water/source_wake_renderer.gd','modules/scene_engine/water/hull_contact_froth.gd','modules/scene_engine/water/hull_contact_foam.gdshader','modules/scene_engine/water/hull_contact_spray.gdshader','modules/scene_engine/water/hull_contact_depth.gdshaderinc','tests/test_hull_contact_froth.gd','tests/test_hull_contact_integration.gd','tests/test_hull_waterline_heave_profile.gd','tools/verify-hull-contact-gpu.gd','tools/verify-hull-contact-depth-gpu.gd'];
const sources=code.map(name=>({path:name,sha256:sha(path.join(base,name))}));
const files=[];function walk(dir){for(const name of fs.readdirSync(dir)){const file=path.join(dir,name);if(fs.statSync(file).isDirectory())walk(file);else if(name!=='DELIVERY_VERIFY.json')files.push({path:path.relative(evidence,file).replaceAll('\\','/'),bytes:fs.statSync(file).size,sha256:sha(file)});}}walk(evidence);
const result={valid:receipts.every(r=>r.valid)&&tail.unchanged&&depth.failures.length===0&&missing.length===0,scope:'Scoped local-water contracts, tail isolation, shader occlusion, recorded controlled GPU frames and normal free-trial screenshots. Not an automated aesthetics or FPS acceptance.',receipts,tailUnchanged:tail.unchanged,depthChecks:6,depthFailures:depth.failures,links,missing,sources,files};
fs.writeFileSync(path.join(evidence,'DELIVERY_VERIFY.json'),JSON.stringify(result,null,2));
console.log(JSON.stringify({valid:result.valid,receipts:receipts.length,tailUnchanged:tail.unchanged,depthFailures:depth.failures.length,links,missing,files:files.length}));
process.exitCode=result.valid?0:1;
