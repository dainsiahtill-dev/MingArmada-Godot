import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const [jobId, source, notesFile, revision='v1'] = process.argv.slice(2);
const jobs=JSON.parse(fs.readFileSync('docs/production/model-preproduction-2026-10-24/art-jobs.json','utf8'));
const job=jobs.find(j=>j.id===jobId);
if(!job||!source) throw new Error('Usage: register-model-sketch.mjs <jobId> <source.png> [review.json]');
const data=fs.readFileSync(source);
if(data.subarray(0,8).toString('hex')!=='89504e470d0a1a0a') throw new Error('Expected PNG');
const sha256=crypto.createHash('sha256').update(data).digest('hex');
const directory=path.dirname(job.imagePath);
if(!/^v[1-9][0-9]*$/.test(revision))throw new Error('Invalid revision');
const target=revision==='v1'?job.imagePath:path.join(directory,`multiview-${revision}.png`);
fs.mkdirSync(directory,{recursive:true});
if(fs.existsSync(target)) {
  const old=crypto.createHash('sha256').update(fs.readFileSync(target)).digest('hex');
  if(old!==sha256) throw new Error('Destination exists; preserve version and request a sibling revision');
} else fs.copyFileSync(source,target);
const review=notesFile?JSON.parse(fs.readFileSync(notesFile,'utf8')):{status:'not-yet-visually-reviewed',notes:[]};
const promptPath=`${directory}/${revision==='v1'?'prompt':`prompt-${revision}`}.txt`;
const result={jobId,revision,tool:'built-in-imagegen',generatedAt:new Date().toISOString(),sourcePath:path.resolve(source),imagePath:target.split(path.sep).join('/'),sha256,width:data.readUInt32BE(16),height:data.readUInt32BE(20),review,modelingApproved:false,historyApproved:false,promptPath:fs.existsSync(promptPath)?promptPath:null};
fs.writeFileSync(`${directory}/${revision==='v1'?'generation':`generation-${revision}`}.json`,JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({jobId,path:target,width:result.width,height:result.height,review:review.status}));
