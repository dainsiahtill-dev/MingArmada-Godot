import fs from 'node:fs';
import crypto from 'node:crypto';
import path from 'node:path';
const base='docs/research/evidence/ship-water-optics-2026-10-14';
const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const failures=[],runs=[];
const check=(v,m)=>{if(!v)failures.push(m);};
for(const [name,count] of [['research-1',18],['research-2',8]]){
 const dir=path.join(base,name), receipt=JSON.parse(fs.readFileSync(path.join(dir,'GPU_VERIFY.json')));
 check(receipt.valid&&receipt.failures.length===0,name+' GPU receipt');
 check(receipt.captures.length===count,name+' capture count');
 check(sha(path.join(dir,'driver.gd.txt'))===receipt.sources['tools/diagnose-ship-water-optics.gd'],name+' archived driver SHA');
 const cameras={};
 for(const r of receipt.captures){
  check(sha(path.join(dir,r.image))===r.image_sha256,name+'/'+r.image+' SHA');
  check(r.time===8,name+' accepted time');
  const angle=r.label.split('-')[0];
  if(!cameras[angle])cameras[angle]=r.camera;
  check(r.camera===cameras[angle],name+' same '+angle+' camera');
  check(r.geometry.minimum_clearance_m<-.25,name+' hull enters water beyond wake bound');
  check(r.optics.reflection_enabled&&r.optics.refraction_enabled,name+' production optics capability');
 }
 for(const [file,hash] of Object.entries(receipt.sources)){
  if(file.startsWith('tools/'))continue;
  check(sha(file)===hash,name+' unmodified runtime '+file);
 }
 runs.push({name,valid:receipt.valid,captures:receipt.captures.length,receipt_sha256:sha(path.join(dir,'GPU_VERIFY.json')),cameras,geometry:receipt.captures[0].geometry});
}
check(JSON.stringify(runs[0].cameras)===JSON.stringify(runs[1].cameras),'both rounds same cameras');
check(JSON.stringify(runs[0].geometry)===JSON.stringify(runs[1].geometry),'both rounds same hull geometry');
const proof={valid:failures.length===0,failures,runs,totalCaptures:runs.reduce((n,r)=>n+r.captures,0),scope:'Research-only memory shader variants in actual free-sail. No production default modified; no live FPS or full-scene visual acceptance.'};
fs.writeFileSync(path.join(base,'VERIFY.json'),JSON.stringify(proof,null,2)+'\n');
const figures=(angle)=>[['baseline','现有方案'],['extinction-linear','研究候选：消光＋线性合成'],['no-transmission','诊断极端：完全关闭透射']].map(([mode,label])=>'<figure><a href="research-2/'+angle+'-'+mode+'.png"><img src="research-2/'+angle+'-'+mode+'.png" alt="'+label+'"></a><figcaption>'+label+'</figcaption></figure>').join('');
const html='<!doctype html><html lang="zh"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>船与水面接触 · 研究对照</title><style>body{margin:0;padding:32px;background:#101c21;color:#e5eeee;font:16px/1.65 system-ui}main{max-width:1700px;margin:auto}h1{font-size:28px}p{max-width:80ch;color:#bbd0d5}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}figure{margin:0}img{width:100%;display:block}figcaption{padding:9px 0}a{color:#8ed7e2}@media(max-width:850px){.grid{grid-template-columns:1fr}}</style><main><h1>船与水面接触：同态对照</h1><p>两个机位，同一艘船、同一姿态与 8 秒模拟时间。候选仅修改独立进程里的 shader，正式海水默认值未改。点击图片查看原始 PNG。候选并非最终验收；还需检查岸线、多船型与连续浮动。</p><h2>低机位</h2><div class="grid">'+figures('low')+'</div><h2>高机位</h2><div class="grid">'+figures('high')+'</div><p>候选在原消光系数上加 0.65 m⁻¹ 的中性项，再用线性颜色合成；该数值是艺术实验，不是海水实测值。完全关闭透射只用于定位问题。</p><p><a href="../../ship-water-contact-optics-research-2026-10-14.md">完整研究报告</a> · <a href="VERIFY.json">可复核证据</a></p></main></html>';
fs.writeFileSync(path.join(base,'review.html'),html);
console.log(JSON.stringify({valid:proof.valid,failures,totalCaptures:proof.totalCaptures,runtimeUnchanged:failures.every(x=>!x.includes('runtime'))}));
process.exitCode=proof.valid?0:1;
