import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
const root=process.cwd();
const relative='docs/migration/evidence/hull-dynamics-2026-10-14';
const base=path.join(root,relative);
const failures=[];
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const read=async p=>JSON.parse(await fs.readFile(p,'utf8'));
const expect=(ok,msg)=>{if(!ok)failures.push(msg)};
async function walk(dir){let files=[];for(const entry of await fs.readdir(dir,{withFileTypes:true})){const p=path.join(dir,entry.name);if(entry.isDirectory())files.push(...await walk(p));else files.push(p)}return files}
const files=await walk(base);
const sequences=[];
for(const file of files.filter(f=>f.endsWith('VERIFICATION.json')&&f.replaceAll('\\','/').includes('/final/'))){
 const result=await read(file);
 expect(result.failures?.length===0,`GPU receipt failed: ${file}`);
 expect(result.samples?.length>=8,`GPU sequence too short: ${file}`);
 expect(result.timeline?.length===321,`GPU timeline missing: ${file}`);
 expect(result.carrier?.startsWith('uniform'),'Final GPU carrier mismatch: '+file);
 for(const row of result.regionReadback??[]){
  const sample=result.samples.find(s=>s.tick===row.tick);
  const inferredVisible=row.carrier==='ContactSpray'?sample.contact.target_droplets>0:sample.contact.target_ribbons>0;
  // Fully dry/disabled carriers intentionally retain the old GPU surface and
  // hide it. Only vertices actually submitted for drawing must match buffers.
  if(row.visible??inferredVisible)expect(row.maximumError<=.0001&&row.UVerror<=.0001&&row.alphaError<=1/255+.00001,`GPU upload readback mismatch: ${file} tick${row.tick} ${row.carrier}`);
 }
 for(const sample of result.samples??[]){const image=await fs.readFile(path.join(path.dirname(file),sample.image));expect(image.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])),`Not PNG: ${sample.image}`)}
 sequences.push({phase:result.phase,kind:result.kind,case:result.case,camera:result.camera,layer:result.layer,maximumImpact:result.maximumImpact,peakTick:result.peakTick,images:result.samples.map(s=>({src:path.relative(base,path.join(path.dirname(file),s.image)).replaceAll('\\','/'),time:s.time,impact:s.contact.impact_strength??0,turn:s.contact.turn_bias??0,speed:Math.hypot(s.state.velocity.x,s.state.velocity.z)}))});
}
expect(sequences.some(s=>s.phase==='baseline'),'Missing baseline GPU');
for(const scenario of ['cruise','slow','turn','stop','reentry'])expect(sequences.some(s=>s.phase==='candidate'&&s.case===scenario),`Missing ${scenario} GPU`);
const actual=await read(path.join(base,'actual-entry/VERIFICATION.json'));
expect(actual.failures.length===0&&actual.activeFrames===240&&actual.finalTime>actual.initialTime,'Actual main entry failed');
const depth=await read(path.join(base,'depth/VERIFICATION.json'));
expect(depth.failures.length===0&&depth.records.length===2,'Fresh foam/spray opaque-depth GPU checks failed');
const performance=await read(path.join(base,'performance/comparison-cpu.json'));
expect(performance.failures?.length===0,'CPU comparison failed');
const gpuPerformance=await read(path.join(base,'performance/comparison-gpu.json'));
expect(gpuPerformance.failures.length===0&&gpuPerformance.pairs.length===3&&gpuPerformance.pairs.every(p=>p.inputMatch),'Paired GPU arena comparison failed');
const worldAfter=await read(path.join(base,'performance/world-cpu-after-shadow.json'));
expect(worldAfter.failures.length===0&&worldAfter.samples===12,'Fresh actual-world CPU stage checks failed');
const tail=await read(path.join(root,'Temp/hull-contact-tail-preserved.json'));
const tailFiles=Array.isArray(tail)?tail:(tail.entries??tail.files??tail.records??[]);
for(const item of tailFiles){const p=item.path??item.file??`modules/scene_engine/water/${item.name}`;const expected=item.before??item.beforeSHA256??item.sha256Before??item.sha256;const current=sha(await fs.readFile(path.isAbsolute(p)?p:path.join(root,p)));expect(current===expected,`Tail changed: ${p}`)}
expect(tailFiles.length===5,'Five tail source hashes required');
const production=['modules/scene_engine/water/hull_contact_froth.gd','modules/scene_engine/water/hull_contact_foam.gdshader','game/presentation/world/source_water_packet.gd','game/presentation/world/target_rigid_shadow_caster.gd'];
const sources=[];for(const file of production)sources.push({path:file,sha256:sha(await fs.readFile(path.join(root,file)))});
const regressions=await read(path.join(base,'regressions.json'));
expect(regressions.summary.passedAll,'Hull regressions failed');
const shadowRegressions=await read(path.join(base,'shadow-regressions.json'));
expect(shadowRegressions.summary.passedAll,'Shadow regressions failed');
for(const s of sequences.filter(s=>s.phase==='candidate'))expect(s.images.length>=8,`Missing continuous frames: ${s.kind}/${s.case}`);
for(const k of ['fuchuan','fisherman','merchant','voc','patrol','heavy'])expect(sequences.some(s=>s.phase==='candidate'&&s.kind===k),`Missing real hull GPU: ${k}`);
const artifactFiles=[];for(const file of files.filter(f=>!f.includes('before-final-tool')&&!f.includes('pre-opt-candidate')&&!f.endsWith('DELIVERY_VERIFY.json')&&!f.endsWith('review.html')))artifactFiles.push({path:path.relative(root,file).replaceAll('\\','/'),sha256:sha(await fs.readFile(file))});
const escape=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;');
const html=`<!doctype html><meta charset="utf-8"><title>船首与真实海浪验收</title><style>body{margin:0;background:#102028;color:#d9e6e6;font:16px system-ui}main{max-width:1350px;margin:auto;padding:24px}h1{font-size:24px}p{line-height:1.6}select,button{padding:10px;margin-right:8px;background:#203941;color:inherit;border:1px solid #567}img{width:100%;height:auto;display:block;margin:16px 0}output{font-variant-numeric:tabular-nums}input{width:100%}small{color:#9fbabc}</style><main><h1>船首与真实海浪 · 连续验收</h1><p>使用现有五组波浪海面、原生航行物理、实际船型与3D甲板人物。再入水压力测试明确额外抬高船体2米；其他控制场景使用原生船姿。尾部效果和操船规则保持现状。序列按模拟时间间隔播放，画面没有修饰。</p><select id="sequence"></select><button id="play">暂停</button><output id="info"></output><img id="frame"><input type="range" id="slider" min="0"><small>低角度控制场景不是完整游戏FPS证明。正常主菜单自由试航另有实际入口截图与240帧记录；CPU性能报告分离了局部层、原生水采样和整场景帧间隔。</small><p><a href="actual-entry/main-free-trial.png">正常自由试航画面</a> · <a href="actual-entry/VERIFICATION.json">实际入口记录</a> · <a href="performance/comparison-cpu.json">成对CPU比较</a> · <a href="DELIVERY_VERIFY.json">交付校验</a></p></main><script>const data=${JSON.stringify(sequences).replaceAll('<','\\u003c')};let selected=0,index=0,playing=true,timer;const sequence=document.getElementById('sequence'),frame=document.getElementById('frame'),slider=document.getElementById('slider'),info=document.getElementById('info');data.forEach((s,i)=>sequence.add(new Option([s.phase,s.kind,s.case,s.camera,s.layer].join(' / '),i)));function show(){clearTimeout(timer);const s=data[selected],f=s.images[index];frame.src=f.src;slider.max=s.images.length-1;slider.value=index;info.textContent='t '+f.time.toFixed(2)+'s · speed '+f.speed.toFixed(2)+'m/s · impact '+f.impact.toFixed(3)+' · turn '+f.turn.toFixed(3);if(playing){const next=(index+1)%s.images.length;timer=setTimeout(()=>{index=next;show()},next?Math.max(100,(s.images[next].time-f.time)*1000):800)}}sequence.onchange=()=>{selected=Number(sequence.value);index=0;show()};slider.oninput=()=>{index=Number(slider.value);show()};document.getElementById('play').onclick=e=>{playing=!playing;e.target.textContent=playing?'暂停':'播放';show()};show();</script>`;
await fs.writeFile(path.join(base,'review.html'),html,'utf8');
const report={valid:failures.length===0,failures,scope:'Bow/side local dynamics, unchanged existing tail and ocean. Controlled real-wave GPU sequences, paired CPU costs, actual main entry; no full-game universal FPS assertion.',sources,sequences:sequences.length,gpuFrames:sequences.reduce((n,s)=>n+s.images.length,0),tailFiles,actualEntry:{activeFrames:actual.activeFrames,frameIntervalsMs:actual.frameIntervalsMs},artifacts:artifactFiles};
await fs.writeFile(path.join(base,'DELIVERY_VERIFY.json'),JSON.stringify(report,null,2),'utf8');
console.log(JSON.stringify({valid:report.valid,failures,sequences:report.sequences,gpuFrames:report.gpuFrames,files:artifactFiles.length}));
if(failures.length)process.exitCode=1;
