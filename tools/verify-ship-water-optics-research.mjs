import fs from 'node:fs';
import crypto from 'node:crypto';
import path from 'node:path';
const base='docs/research/evidence/ship-water-optics-2026-10-14';
const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const read=p=>JSON.parse(fs.readFileSync(p,'utf8'));
const failures=[],runs=[];let images=0;
const check=(v,m)=>{if(!v)failures.push(m);};
const oldFiles={
 'modules/scene_engine/ocean/reference_game_water.gdshader':base+'/reference-pre-integration.gdshader.txt',
 'modules/scene_engine/ocean/projected_ocean.gd':base+'/projected-ocean-pre-integration.gd.txt'
};
for(const [name,count,historical] of [['research-1',18,true],['research-2',8,true],['tuning-3',10,true],['integrated-close-r3',18,false],['integrated-shore-r3',6,false],['default-game-r2',6,false]]){
 const dir=path.join(base,name),receipt=read(path.join(dir,'GPU_VERIFY.json'));
 check(receipt.valid&&receipt.failures.length===0,name+' GPU receipt');
 check(receipt.captures.length===count,name+' capture count');
 for(const r of receipt.captures){
  check(sha(path.join(dir,r.image))===(r.image_sha256||r.sha256),name+'/'+r.image+' SHA');images++;
 }
 for(const [file,hash] of Object.entries(receipt.sources)){
  if(file.startsWith('tools/'))continue;
  check(sha(historical?(oldFiles[file]||file):file)===hash,name+' '+(historical?'frozen historical':'current')+' source '+file);
 }
 if(historical){
  check(sha(path.join(dir,'driver.gd.txt'))===receipt.sources['tools/diagnose-ship-water-optics.gd'],name+' archived driver');
  const cameras={};
  for(const r of receipt.captures){
   const angle=r.label.split('-')[0];
   cameras[angle]??=r.camera;
   check(r.camera===cameras[angle]&&r.time===8,name+' same state and camera');
  }
 }
 if(name==='default-game-r2'){
  check(receipt.candidate_opt_in===false&&!receipt.baseline,'ordinary default');
  const stopped=receipt.captures.find(r=>r.label==='05-stop-10s').ship_states.find(x=>x.id==='player');
  check(stopped.sailDeployment===0&&Math.hypot(stopped.visual.velocity.x,stopped.visual.velocity.z)<.05,'actual stop reached');
  for(const r of receipt.captures){
   check(r.transmission.scattering===.35&&r.transmission.linear&&r.transmission.preserve_shallows,'all default captures selected optical controls');
   check(r.field.bound&&r.field.field.dropped_steps===0,'water field remains active without skipped accepted steps');
   check(r.shadow.casterAdapter.errors.length===0,'no caster errors');
  }
  check(receipt.captures.at(-1).field.field.total_steps===receipt.captures.at(-2).field.field.total_steps,'quality rebuild retains field history');
 }
 if(name==='integrated-close-r3'){
  const motion=receipt.captures.filter(r=>r.label.startsWith('motion-'));
  check(motion.length===12,'twelve buoyancy observations');
  check(new Set(motion.map(r=>r.ship_states[0].visual.position.y)).size===12,'actual heave changes');
  for(const angle of ['low','high']){
   const rows=receipt.captures.filter(r=>r.label.startsWith(angle+'-'));
   check(rows.length===3&&rows.every(r=>r.camera===rows[0].camera&&r.time===8),angle+' candidate and production same camera/time');
  }
 }
 if(name==='integrated-shore-r3'){
  for(const angle of ['wide','edge']){
   const rows=receipt.captures.filter(r=>r.angle===angle);
   check(rows.length===3&&rows.every(r=>r.camera===rows[0].camera&&r.time===24&&r.shore_width===.6&&r.shore_weight===.55),'shore same scene and preserved feather '+angle);
  }
 }
 runs.push({name,captures:count,historical,receipt_sha256:sha(path.join(dir,'GPU_VERIFY.json'))});
}
const shore=read(base+'/integrated-shore-r3/SHORE_COMPARE.json');
check(shore.regions.near_sand.selected.mean_abs_rgb_8bit===0,'measured near-sand ROI retains original RGB');
check(shore.regions.outer_shallows.selected.mean_abs_rgb_8bit<shore.regions.outer_shallows.global035.mean_abs_rgb_8bit,'outer shallows approach original more closely');
const match=read(base+'/integrated-close-r3/CANDIDATE_MATCH.json');
for(const angle of ['low','high'])check(match[angle].mean_abs_rgb_8bit<.01,angle+' production matches selected 0.35 candidate');
const proof={valid:failures.length===0,failures,totalCaptures:images,runs,shoreComparison:shore,selectedCandidateMatch:match,scope:'Selected 0.35 linear transmission integrated into shared production ocean, with original shallow-coast transmission blending into offshore response. One free-sail ship, 12 heave observations, coast comparison and ordinary-game quality lifecycle; no full-fleet FPS claim.'};
fs.writeFileSync(base+'/VERIFY.json',JSON.stringify(proof,null,2)+'\n');
const cell=(src,label)=>'<figure><a href="'+src+'"><img src="'+src+'" alt="'+label+'"></a><figcaption>'+label+'</figcaption></figure>';
const html='<!doctype html><html lang="zh"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>海水透射 · 最终接入对照</title><style>body{margin:0;padding:32px;background:#101c21;color:#e5eeee;font:16px/1.65 system-ui}main{max-width:1800px;margin:auto}h1{font-size:28px}p{max-width:90ch;color:#bbd0d5}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:14px}figure{margin:0}img{width:100%;display:block}figcaption{padding:9px 0}a{color:#8ed7e2}@media(max-width:850px){.grid{grid-template-columns:1fr}}</style><main><h1>0.35 档船底透射，保留原浅滩</h1><p>正式方案：远海采用用户选定的 0.35 消光＋线性透射；浅滩保留原色与通透，按海底深度和离岸距离平滑过渡。下图是实际 Godot 原始帧，点击查看原图。</p><h2>海滩：同一镜头与潮位</h2><div class="grid">'+cell('integrated-shore-r3/edge-baseline.png','原海滩')+cell('integrated-shore-r3/edge-global035.png','全海域统一 0.35（r2 的方案）')+cell('integrated-shore-r3/edge-selected.png','最终：保留原浅滩，向深水过渡')+'</div><h2>船底：相同船姿和时间</h2><div class="grid">'+cell('integrated-close-r3/low-baseline.png','原透射')+cell('integrated-close-r3/low-linear-035.png','用户选定的 0.35 候选')+cell('integrated-close-r3/low-production.png','正式材质：0.35＋浅滩保护')+'</div><p>这组验证不等于全部船型、天气或整场 FPS 验收。研究与历史失败均保留。</p><p><a href="../../water-transmission-integration-2026-10-14.md">接入报告</a> · <a href="VERIFY.json">核验记录</a></p></main></html>';
fs.writeFileSync(base+'/review.html',html);
console.log(JSON.stringify({valid:proof.valid,failures,totalCaptures:images}));
process.exitCode=proof.valid?0:1;
