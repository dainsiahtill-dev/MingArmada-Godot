import fs from 'node:fs';
import crypto from 'node:crypto';
const base='docs/research/evidence/cloud-ocean-composition-2026-10-14';
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const read=p=>JSON.parse(fs.readFileSync(p,'utf8'));
const checks=[],failures=[];
function check(ok,n){checks.push({ok,description:n});if(!ok)failures.push(n);}
fs.mkdirSync(base+'/contracts',{recursive:true});
const unique=new Set();
for(const name of ['cloud-order-green-2','cloud-atmosphere-regression','cloud-laboratory-regression']){
 const source='Temp/'+name+'.json',dest=base+'/contracts/'+name+'.json';
 if(fs.existsSync(source))fs.copyFileSync(source,dest);
 const j=read(dest);check(j.runs.length>0&&j.runs.every(r=>r.passed&&r.exitCode===0&&!r.timedOut),name);
 for(const r of j.runs)unique.add(r.test);
}
for(const n of ['cloud-order-red','cloud-order-red-2','cloud-order-green']){
 const p='Temp/'+n+'.json';if(fs.existsSync(p))fs.copyFileSync(p,base+'/contracts/'+n+'.json');
}
if(fs.existsSync('Temp/cloud-composition-gpu-run.json'))fs.copyFileSync('Temp/cloud-composition-gpu-run.json',base+'/production-1/RUN.json');
const run=read(base+'/production-1/RUN.json');
const completed=run.stdout.split(/\r?\n/).filter(x=>x.startsWith('INTERACTIVE_WAKE_PRODUCTION_GPU '));
check(run.valid&&completed.length===1&&/failures=0$/.test(completed[0]),'unique successful GPU completion and no Godot errors');
const gpu=read(base+'/production-1/COMPOSITION_VERIFY.json');
check(gpu.valid&&gpu.failures.length===0&&gpu.captures.length===17,'17 main-camera captures and GPU assertions');
for(const [file,expected]of Object.entries(gpu.sources))check(hash(file)===expected,'frozen source '+file);
for(const f of gpu.captures)check(hash(base+'/production-1/'+f.image)===f.sha256,'original PNG '+f.image);
const mirrors=['mirror-production.png','mirror-no-storm.png'].map(image=>({image,sha256:hash(base+'/production-1/'+image),hashStage:'post-capture evidence audit'}));
check(gpu.metrics.every(m=>m.occluded_difference_pixels===0),'opaque occlusion retained for all three views');
check(gpu.metrics[0].mirror_cloud_pixels>100,'world cloud still present in actual mirror viewport');
check(gpu.metrics[1].production_cloud_pixels>gpu.metrics[1].baseline_cloud_pixels,'reproduced partial horizon cut restored');
check(gpu.metrics[2].production_cloud_pixels>gpu.metrics[2].baseline_cloud_pixels*10,'reproduced total ocean overdraw restored');
const result={valid:failures.length===0,createdUtc:new Date().toISOString(),failures,checks,testFiles:[...unique],originalFrames:19,mirrors,metrics:gpu.metrics,scope:'Actual world cloud object; render order repair, depth testing preserved. Main-camera images cover baseline, production, hidden-cloud control, opaque foreground control, world movement and quality rebuild. No changes to cloud geometry/texture/RNG or original world motion.',limitations:['Magenta box is an isolated opaque depth fixture.','Cloud artistry, rain, original full pixel parity and full-game frame rate are outside this repair.']};
fs.writeFileSync(base+'/VERIFY.json',JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({valid:result.valid,tests:unique.size,originalFrames:19,failures}));
process.exitCode=failures.length?1:0;
