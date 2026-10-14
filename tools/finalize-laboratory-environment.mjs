import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const relative='docs/research/evidence/laboratory-environment-2026-10-14';
const directory=path.join(root,relative);
const read=p=>JSON.parse(fs.readFileSync(path.join(directory,p),'utf8'));
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const checks=[];
const check=(ok,detail)=>checks.push({ok:!!ok,detail});
const gpu=read('final/GPU_VERIFY.json'),run=read('final/gpu-run.json');
check(gpu.valid&&run.valid&&run.completionConfirmed,'final GPU proof, strict logs and unique completion');
for(const [file,digest] of Object.entries(gpu.sourceHashes))check(hash(path.join(root,file))===digest,'current GPU source '+file);
for(const c of gpu.captures){
 check(hash(path.join(directory,'final',c.image))===c.sha256,'raw image '+c.image);
 const state=read('final/'+c.state);
 check(state.image_sha256===c.sha256&&state.demo.ready,'matching PNG/state '+c.name);
}
let assertions=0;
for(const name of ['regressions.json','coverage-tests.json']){
 const tests=read('final/'+name);check(tests.summary.passedAll,'strict affected tests '+name);
 for(const test of tests.runs){const counts=[...test.stdout.matchAll(/assertions=(\d+) failures=0/g)];check(counts.length===1,'unique test result '+test.test);assertions+=Number(counts[0]?.[1]||0);}
}
for(const sub of ['production','feather-wide-study']){
 const proof=read(sub+'/GPU_VERIFY.json'),logs=read(sub+(sub==='production'?'/run-verified.json':'/run.json'));
 check(proof.valid&&logs.valid&&logs.completionConfirmed,sub+' raw proof and completed execution');
 check(proof.shader_sha256===hash(path.join(root,'modules/scene_engine/ocean/reference_game_water.gdshader')),sub+' current production shader');
}
const pack=read('final/PACK_VERIFY.json'),packRun=read('final/pack-run.json');
check(pack.valid&&packRun.valid&&packRun.completionConfirmed,'package-only menu and four demos');
for(const topic of pack.subjects)check(hash(path.join(root,topic.paper.replace('res://','')))===topic.sha256,'packed paper unchanged '+topic.id);
const artifacts=[];
for(const sub of ['final','production','feather-wide-study'])for(const filename of fs.readdirSync(path.join(directory,sub))){
 const location=path.join(directory,sub,filename);
 if(fs.statSync(location).isFile())artifacts.push({path:sub+'/'+filename,bytes:fs.statSync(location).size,sha256:hash(location)});
}
const png=(src,alt)=>`<a href="${src}"><img loading="lazy" src="${src}" alt="${alt}"></a>`;
const html=`<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>水岸融合与环境实验记录</title><style>body{background:#102129;color:#dfe9e8;font:16px/1.65 system-ui;margin:0;padding:28px;max-width:1400px;margin:auto}h1,h2{color:#eed5a4}a{color:#9fdfd1}img{display:block;width:100%;height:auto}section{margin:35px 0}small{color:#a5babc}button,input{font:inherit}.pair{position:relative}.pair>img{position:absolute;inset:0;clip-path:inset(0 0 0 50%)}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:18px}.grid figure{margin:0}input{width:100%}button{background:#29434c;color:#eef5f4;border:1px solid #55777d;padding:8px 12px;margin:4px}code{color:#d4bc8e}</style><h1>水岸融合与环境实验记录</h1><p>当前：融合宽度 <b>0.6</b> · 贴岸水色覆盖 <b>0.55</b>。靠沙滩、岸浪消散处更加透底，向外恢复正常海水；船尾与原波浪保留。</p><small>全部为实际Godot原帧。显示滑杆只比较两张同刻截图，不是实时模拟。低机位原投影缺陷未在本轮解决。</small><section><h2>正式共用世界 · 同镜头对照</h2><p>左侧原硬边，右侧当前融合。拖动分界检查码头、沙底和浪头。</p><div class="pair">${png('production/production-edge-w00.png','原硬边')}<img id="after" src="production/production-edge-w60.png" alt="当前融合"></div><input aria-label="前后对照分界" type="range" min="0" max="100" value="50" oninput="document.getElementById('after').style.clipPath='inset(0 0 0 '+this.value+'%)'"></section><section><h2>贴岸水色单独对照</h2><div class="grid"><figure>${png('final/shore-edge-water-weight-100.png','同宽度水色覆盖1')}<figcaption>范围相同，原覆盖曲线1.0。</figcaption></figure><figure>${png('final/shore-edge-water-weight-55.png','当前水色覆盖0.55')}<figcaption>当前0.55，更多透出沙底。</figcaption></figure></div></section><section><h2>岸浪连续取样</h2><p>固定时间0／6／12／18／24秒，保持原浪的推进与消散。</p><div id="times">${[0,6,12,18,24].map(t=>`<button onclick="document.getElementById('sequence').src='final/shore-close-t${String(t).padStart(3,'0')}.png'">${t}秒</button>`).join('')}</div><img id="sequence" src="final/shore-close-t012.png" alt="岸浪12秒"></section><section><h2>统一实验室</h2>${png('final/shore-close-t012-ui.png','实验室实际界面')}<div class="grid">${['ocean-camera_horizon','weather-clear-sky','weather-shadows_enabled-on'].map(name=>`<figure>${png('final/'+name+'.png',name)}<figcaption>${name}</figcaption></figure>`).join('')}</div></section><section><h2>证据与限制</h2><p>${assertions}项受影响CPU断言；44组最终实验室原帧，24张羽化时序对照，4张正式共用世界对照。打包检查${pack.assertions}项通过。这里只证明记录内条件，没有宣称所有地形、透明特效或整场FPS达标。</p><p><a href="DELIVERY_VERIFY.json">交付校验</a> · <a href="final/GPU_VERIFY.json">完整状态</a> · <a href="feather-wide-study/PIXEL_ANALYSIS.json">像素与帧间隔分析</a> · <a href="../../laboratory-environment-delivery-2026-10-14.md">完整报告</a></p></section></html>`;
fs.writeFileSync(path.join(directory,'review.html'),html);
const proof={schemaVersion:1,valid:checks.every(x=>x.ok),checks,assertions,packAssertions:pack.assertions,generatedAtUtc:new Date().toISOString(),artifacts,sourceHashes:gpu.sourceHashes,limitations:['Low diagnostic camera retained projection/large-face defect in both baseline and candidate; not accepted as overall artistic quality.','Pixel metric is exploratory baseline-derived ROI, not a preregistered frozen ROI study.','Only ordinary shared-world preview integration, not full-game FPS or all-transparent-object certification.'],scope:'Four runnable laboratory subjects; final local shore coverage width0.6/weight0.55. Frozen current GPU/CPU/package/source audit. Historical failures retained separately.'};
fs.writeFileSync(path.join(directory,'DELIVERY_VERIFY.json'),JSON.stringify(proof,null,2)+'\n');
console.log(JSON.stringify({valid:proof.valid,checks:checks.length,assertions,packAssertions:pack.assertions,failed:checks.filter(x=>!x.ok)}));
process.exitCode=proof.valid?0:1;
