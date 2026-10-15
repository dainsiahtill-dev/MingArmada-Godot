import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
const root=process.cwd(), base='docs/research/evidence/ship-buoyancy-2026-10-14';
const read=p=>JSON.parse(fs.readFileSync(p,'utf8'));
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const errors=[],checks=[];
function check(ok,description){checks.push({ok,description});if(!ok)errors.push(description);}
const tests=['buoyancy-final-contracts','buoyancy-ship-final','buoyancy-naval-regression','buoyancy-sailing-regression','buoyancy-sea-regression','buoyancy-laboratory-regression','buoyancy-arrival-regression','buoyancy-contact-water-regression'];
fs.mkdirSync(base+'/contracts',{recursive:true});
const unique=new Set();
for(const name of tests){
 const source='Temp/'+name+'.json', target=base+'/contracts/'+name+'.json';
 if(fs.existsSync(source))fs.copyFileSync(source,target);
 const data=read(target);
 check(data.runs.length>0&&data.runs.every(r=>r.passed&&r.exitCode===0&&!r.timedOut),name);
 for(const run of data.runs)unique.add(run.test);
}
for(const [source,target] of [
 ['Temp/buoyancy-default-game-final-run.json','default-game-final/RUN.json'],
 ['Temp/buoyancy-default-game-run.json','default-game-1/RUN.json'],
 ['Temp/buoyancy-six-ships-gpu-run.json','six-ships-1/RUN.json'],
 ['Temp/buoyancy-duplicate-time-red.json','contracts/duplicate-time-RED.json'],
 ['Temp/buoyancy-lab-red.json','contracts/laboratory-RED.json'],
 ['Temp/buoyancy-model-geometry-run.json','model-geometry-RUN.json']
]){if(fs.existsSync(source))fs.copyFileSync(source,base+'/'+target);}
let imageCount=0;
const gpu=[];
for(const folder of ['shore-baseline-1','shore-candidate-1','six-ships-1','default-game-final']){
 const data=read(base+'/'+folder+'/GPU_VERIFY.json');
 const run=read(base+'/'+folder+'/RUN.json');
 check(data.valid&&data.failures.length===0&&run.valid,folder+' execution');
 const frames=data.captures;
 let accepted=0;
 for(const frame of frames){
  const image=frame.image;
  const expected=frame.image_sha256||frame.sha256;
  check(fs.existsSync(base+'/'+folder+'/'+image)&&hash(base+'/'+folder+'/'+image)===expected,folder+'/'+image+' original image hash');
  // Setup t=0 was captured before the rebuilt body's packet reached the runtime cache.
  if(folder.startsWith('shore-')&&frame.time===0)continue;
  accepted++;imageCount++;
 }
 gpu.push({folder,captures:accepted,stage:folder==='default-game-final'?'final production source':'historical controlled comparison before duplicate-time guard'});
 if(folder==='default-game-final'){
  for(const [file,expected]of Object.entries(data.sources))check(hash(file)===expected,'final production source '+file);
  check(frames.length===6,'normal production six command/quality checkpoints');
 }
}
const geometry=read(base+'/model-geometry-final.json');
check(geometry.records.length===12&&geometry.records.every(r=>r.airFrames===0&&r.maxLowestKeelClearance<-.25),'six actual hulls / two depths / 120s keel samples remain immersed');
const finalContract=read(base+'/contracts/buoyancy-final-contracts.json');
const metrics=JSON.parse(finalContract.runs[0].stdout.split(/\r?\n/).find(x=>x.startsWith('BUOYANCY_CONTACT_METRICS ')).slice('BUOYANCY_CONTACT_METRICS '.length));
const old=read(base+'/RED.json');
const oldMetrics=JSON.parse(old.runs[0].stdout.split(/\r?\n/).find(x=>x.startsWith('BUOYANCY_CONTACT_METRICS ')).slice('BUOYANCY_CONTACT_METRICS '.length));
const comparison=metrics.filter(x=>x.depth===20).map(x=>({kind:x.kind,baselineMaxRelativeError:oldMetrics.find(y=>y.kind===x.kind&&y.depth===20).peak,finalMaxRelativeError:x.peak,finalRms:x.rms}));
const report={valid:errors.length===0,createdUtc:new Date().toISOString(),checks,errors,uniqueTestFiles:[...unique].sort(),acceptedImages:imageCount,gpu,comparison,scope:'Bounded four-support buoyancy repair. Final normal-entry GPU hashes match current sources. Earlier controlled comparisons precede duplicate-time guard; unchanged periodic wave response is rechecked by final CPU contracts.',
 exclusions:['shore-00.png in both shore comparisons: setup snapshot cache not yet refreshed; excluded from paired timing analysis.','No claim of exact replay of user screenshot, complete displaced hull volume, extreme storm or full-game FPS.'],
 visualReview:'Root inspected one t=9s frame for each of six models, shore candidate t=18s and normal entry stop checkpoint. Shore pier occludes part of stern; six-model lab is unobstructed.',
 sources:Object.fromEntries(['modules/physics_engine/ships/ship_dynamics.gd','modules/contracts/physics_types.gd','modules/naval_simulation/encounter.gd','game/research/demos/hull_contact_experiment.gd','game/research/laboratory.gd','tests/test_buoyancy_contact.gd','tests/test_buoyancy_laboratory.gd'].map(p=>[p,hash(p)]))};
fs.writeFileSync(base+'/VERIFY.json',JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({valid:report.valid,tests:unique.size,acceptedImages:imageCount,errors,comparison}));
process.exitCode=errors.length?1:0;
