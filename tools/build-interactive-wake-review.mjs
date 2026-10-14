import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const folder=path.resolve(process.argv[2]||'docs/research/evidence/wake-flow/interactive-lab-2');
const names=['source-cruise','cruise','side','turn-left','turn-right','stop','reentry','small','height','foam'];
const labels=['原尾迹／同条件对照','新场／直航','新场／侧面','新场／左转','新场／右转','新场／收帆停止','新场／升沉与重新入水','新场／小船','实际局部波高诊断','实际泡沫密度诊断'];
const rows=[];
for(let i=0;i<names.length;i++){
 const name=names[i],dir=path.join(folder,name),receipt=path.join(dir,'GPU_VERIFY.json');
 if(!fs.existsSync(receipt))continue;
 const r=JSON.parse(fs.readFileSync(receipt,'utf8'));
 if(!r.valid||!r.captures?.length)throw Error('Unverified run '+name);
 const frames=r.captures;
 const lines=[];
 for(let j=0;j<frames.length;j++){
  const f=frames[j];if(!/^t\d+\.png$/.test(f.image))throw Error('Unexpected frame name');
  const dt=j+1<frames.length?(frames[j+1].observer_time??frames[j+1].time)-(f.observer_time??f.time):.125;
  if(!(dt>0))throw Error('Nonpositive frame interval');
  lines.push(`file '${f.image}'`,`duration ${dt.toFixed(9)}`);
 }
 lines.push(`file '${frames.at(-1).image}'`);
 const list=path.join(dir,'preview-frames.txt');fs.writeFileSync(list,lines.join('\n')+'\n');
 const video=path.join(dir,'preview.mp4');
 if(!fs.existsSync(video)){
  const out=spawnSync('rtk',['proxy','ffmpeg','-hide_banner','-loglevel','error','-n','-f','concat','-safe','0','-i',list,'-fps_mode','vfr','-c:v','libx264','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',video],{windowsHide:true,encoding:'utf8'});
  if(out.status!==0)throw Error(out.stderr||'ffmpeg failed');
 }
 rows.push({name,label:labels[i],frames:frames.length,seconds:r.final.time,foam:r.readback?.max_foam??null,height:r.readback?.max_abs_height_m??null,mode:r.mode});
}
const baseline=JSON.parse(fs.readFileSync(path.join(folder,'source-cruise/GPU_VERIFY.json'),'utf8'));
const candidate=JSON.parse(fs.readFileSync(path.join(folder,'cruise/GPU_VERIFY.json'),'utf8'));
const pair=baseline.captures.length===candidate.captures.length&&baseline.captures.every((a,i)=>{let b=candidate.captures[i];return a.ship_sha256===b.ship_sha256&&a.time===b.time&&JSON.stringify(a.camera_transform)===JSON.stringify(b.camera_transform)&&JSON.stringify(a.camera_projection)===JSON.stringify(b.camera_projection);});
if(!pair)throw Error('A/B ship, camera or clock mismatch');
fs.writeFileSync(path.join(folder,'REVIEW_SUMMARY.json'),JSON.stringify({rawFrameSources:'GPU_VERIFY.json in each run; videos are H.264 derivatives without overlays, cropping or color editing',pairedCruise:{matchingShipCameraTime:true},rows},null,2)+'\n');
const buttons=rows.map((r,i)=>`<button data-index="${i}">${r.label}</button>`).join('');
const html=`<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>双侧船尾迹 · 实测对照</title><style>body{margin:0;background:#10232b;color:#dce9eb;font:16px system-ui}main{max-width:1320px;margin:28px auto;padding:0 24px}h1{font-size:26px;margin:0 0 12px}p{line-height:1.7;color:#aec6cc}nav{display:flex;gap:8px;flex-wrap:wrap;margin:18px 0}button,a{color:#b8f1e5}button{background:#1d3942;border:1px solid #385862;padding:10px 14px;cursor:pointer}button[aria-pressed=true]{background:#367668;color:white}video{width:100%;max-height:72vh;background:black}#facts{font-variant-numeric:tabular-nums;line-height:1.8;padding:14px 0}a{margin-right:22px}.notice{border-left:3px solid #e2bc75;padding:8px 16px;color:#e9d3ac}</style><main><h1>双侧船尾迹 · Godot 实测对照</h1><p>同一船模、3D船员、五组原海浪与接受时钟。直航对照已逐帧核对船体、镜头和时间相同。视频由原始PNG按实际观察间隔编码，原帧与GPU记录均保留。</p><p class="notice">这是独立实验的记录。侧面图顶部的边缘属于384米有限水面载体，后续将以正式投影海面复验；本组不代表完整游戏FPS。中线失败候选未启用。</p><nav>${buttons}</nav><video id="video" controls muted loop playsinline></video><div id="facts"></div><a id="raw" target="_blank">GPU记录与源代码散列</a><a id="frame" target="_blank">末帧原始PNG</a><p>左／右转均在4秒后施舵；停止场景4秒收帆，继续运行到24秒。重新入水包含明确的2米姿态压力测试。灰色和黑色诊断背景用于读取实际场，不是正常海面。</p></main><script>const runs=${JSON.stringify(rows)};const video=document.querySelector('#video');function select(i){const r=runs[i];video.src=r.name+'/preview.mp4';document.querySelector('#facts').textContent=r.label+' · '+r.frames+'张原帧 · 接受时间 '+r.seconds.toFixed(2)+' s'+(r.height===null?'':' · 局部波高峰值 '+r.height.toFixed(4)+' m · 泡沫峰值 '+r.foam.toFixed(4));document.querySelector('#raw').href=r.name+'/GPU_VERIFY.json';document.querySelector('#frame').href=r.name+'/t'+String(r.name==='stop'?768:r.name.startsWith('turn')?512:r.name==='height'?128:(r.name==='reentry'||r.name==='foam')?256:384).padStart(4,'0')+'.png';document.querySelectorAll('button').forEach((b,j)=>b.setAttribute('aria-pressed',String(j===i)));}document.querySelectorAll('button').forEach((b,i)=>b.onclick=()=>select(i));select(1);</script></html>`;
fs.writeFileSync(path.join(folder,'review.html'),html);
console.log(JSON.stringify({valid:true,runs:rows.length,pair,review:path.join(folder,'review.html')}));
