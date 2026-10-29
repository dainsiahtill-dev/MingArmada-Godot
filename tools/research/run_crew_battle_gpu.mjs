import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync, readdirSync, realpathSync } from 'node:fs';
import { resolve, join, relative, isAbsolute, sep } from 'node:path';
import { pathToFileURL } from 'node:url';
import { inflateSync } from 'node:zlib';

const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const hash = path => digest(readFileSync(path));
const writeNew = (path, value) => writeFileSync(path, JSON.stringify(value, null, 2) + '\n', { flag:'wx' });
const inside = (path, parent) => { const p=relative(resolve(parent),resolve(path)); return p!=='' && p!=='..' && !p.startsWith('..'+sep) && !isAbsolute(p); };
const finite = x => typeof x==='number' && Number.isFinite(x);
const equal = (a,b) => finite(a) && finite(b) && Math.abs(a-b)<=1e-6;
const arrayEqual = (a,b) => Array.isArray(a) && Array.isArray(b) && a.length===b.length && a.every((x,i)=>x===b[i]);

export function auditState(s) {
  const errors=[];
  const n=s?.native, c=s?.crew, a=s?.contract, m=s?.metrics, l=c?.ledger;
  const player=n?.ships?.find(x=>x.id==='player');
  if (!n || !c || !a || !m || !l || !player) return ['missing authority state'];
  if (!s.ready || !s.paused || s.camera_mode!=='fixed' || s.parameters?.mode!=='battle' || s.parameters?.seed!==1661 || s.parameters?.roster!=='ordinary' || s.parameters?.pressure!=='duel' || !equal(s.fixed_step,1/60) || !Number.isInteger(s.tick) || !equal(s.time,s.tick/60) || n.tick!==s.tick || !equal(n.time,s.time)) errors.push('clock or fixture differs');
  if (a.budget!==144 || a.day!==0 || a.wages_paid!==0 || Object.keys(a.phase_receipts||{}).length!==0 || !equal(a.recruitment_paid+a.wage_reserved+a.wages_paid+a.free_cash,144)) errors.push('budget or contract day changed');
  if (!Array.isArray(c.workers) || !arrayEqual(c.workers.map(x=>x.id),a.hired_ids) || new Set(c.workers.map(x=>x.id)).size!==c.workers.length || c.workers.some(w=>!finite(w.health)||w.health<0||w.health>1)) errors.push('paid roster or health invalid');
  const health=(c.workers||[]).reduce((sum,w)=>sum+w.health,0);
  if (!equal(health,c.crew_equivalent) || !equal(health,player.crew) || !equal(12-health,m.crew_lost) || !equal(l.crew_lost,m.crew_lost)) errors.push('native and worker health differ');
  if (!equal(player.hull,c.hull) || !equal(player.hull,54+m.hull_repaired-m.hull_damage_taken) || !equal(l.hull_repaired,m.hull_repaired) || !equal(l.hull_damage,m.hull_damage_taken)) errors.push('native damage or repairs do not conserve');
  if (!equal(16-c.wood,l.wood_used) || !equal(l.wood_used,m.hull_repaired*0.5) || !equal(24-c.grain,l.grain_used) || !equal(l.meals_cooked,l.grain_used) || !equal(l.meals_cooked,l.meals_eaten+c.cooked_rations)) errors.push('materials do not conserve');
  if (![c.hull,c.wood,c.grain,c.cooked_rations].every(finite) || c.hull<0 || c.hull>80 || c.wood<0 || c.grain<0 || c.cooked_rations<0 || player.ammo?.solid+m.ammo_spent!==40) errors.push('resource bounds or ammunition invalid');
  for (const key of ['fire_count','hit_count','player_fire_count','enemy_fire_count','player_hit_count','enemy_hit_count','events_count','ammo_spent']) if (!Number.isInteger(m[key]) || m[key]<0) errors.push(`invalid physical metric ${key}`);
  if (m.fire_count!==m.player_fire_count+m.enemy_fire_count || m.hit_count!==m.player_hit_count+m.enemy_hit_count || m.events_count<m.fire_count+m.hit_count) errors.push('physical event aggregation differs');
  return errors;
}

export function auditTimeline(report) {
  const errors=[];
  if (!report || !Array.isArray(report.sequence) || !Array.isArray(report.captures) || !Array.isArray(report.actions)) return ['missing capture report'];
  if (!report.valid || report.failures?.length || !equal(report.fixedStep,1/60) || report.ticksPerFrame!==4 || report.maximumSampledFrames!==300 || report.seed!==1661 || !report.audioMuted || report.displayServer==='headless' || !report.gpu || !report.renderer) errors.push('invalid hardware or cadence metadata');
  const rows=report.sequence, images=new Map(), ticks=rows.at(-1)?.tick;
  if (rows.length<2 || rows.length>301 || rows[0]?.frame!==0 || rows[0]?.tick!==0 || rows[0]?.ticks_advanced!==0) errors.push('invalid sequence extent');
  for (let i=0;i<rows.length;i++) {
    const r=rows[i], p=rows[i-1];
    if (r.frame!==i || !Number.isInteger(r.tick) || !equal(r.time,r.tick/60) || r.contract_day!==0 || !Array.isArray(r.visible_projectiles)) errors.push(`invalid sequence row ${i}`);
    if (i>0 && (r.ticks_advanced<1 || r.ticks_advanced>4 || r.tick!==p.tick+r.ticks_advanced || (i<rows.length-1 && r.ticks_advanced!==4) || r.physical_events_count<p.physical_events_count)) errors.push(`nonmonotonic native timeline ${i}`);
    if (r.physical_events_count!==r.metrics?.events_count || !Number.isInteger(r.native_projectile_count) || r.native_projectile_count<0) errors.push(`invalid physical projection ${i}`);
    if (i>0) for (const k of ['fire_count','hit_count','hull_damage_taken','hull_repaired','crew_lost','ammo_spent']) if (r.metrics[k]+1e-6<p.metrics[k]) errors.push(`physical metric regressed ${i}:${k}`);
  }
  if (report.physicsChecks!==ticks) errors.push('accepted physics check count differs');
  const last=rows.at(-1), early=report.earlyStop;
  if (last?.tick!==1200 && (!early?.reason || early.reason!=='native trial finished' || early.tick!==last?.tick || early.frame!==last?.frame)) errors.push('shortened sequence lacks native terminal reason');
  if (rows.length-1<120 && (!early?.reason || early.before_minimum_120_frames!==true)) errors.push('minimum 120 frame exception not recorded');
  const visible=rows.reduce((sum,r)=>sum+r.visible_projectiles.length,0);
  if (visible<1 || report.visibleProjectileSamples!==visible || !(last?.metrics?.fire_count>0) || !(last?.metrics?.hit_count>0) || !(last?.metrics?.hull_damage_taken>0)) errors.push('real firing, hit, damage or visible projectile absent');
  for (const c of report.captures) {
    if (typeof c.file!=='string' || !/^(?:battle-\d{3}|wide-start|wide-middle|wide-end|narrow-page)\.png$/.test(c.file) || images.has(c.file)) { errors.push('invalid or duplicate image identity'); continue; }
    images.set(c.file,c);
    if (!Array.isArray(c.viewport) || c.viewport.length!==2 || !c.viewport.every(x=>Number.isInteger(x)&&x>0) || !/^[a-f0-9]{64}$/.test(c.sha256||'') || !/^[a-f0-9]{64}$/.test(c.framebuffer_sha256||'') || c.framebuffer_format!=='RGBA8') errors.push(`invalid framebuffer metadata ${c.file}`);
    errors.push(...auditState(c.snapshot).map(x=>`${c.file}: ${x}`));
    const match=c.file.match(/^battle-(\d{3})\.png$/);
    if (match) {
      const row=rows[Number(match[1])], s=c.snapshot;
      if (c.kind!=='experiment' || !row || row.tick!==s.tick || !equal(row.hull,s.crew.hull) || !equal(row.crew_equivalent,s.crew.crew_equivalent) || row.physical_events_count!==s.metrics.events_count || JSON.stringify(row.metrics)!==JSON.stringify(s.metrics)) errors.push(`image-state mismatch ${c.file}`);
    } else if (c.kind!=='page' || !arrayEqual(c.viewport,c.file==='narrow-page.png'?[960,640]:[1600,900])) errors.push(`invalid full-page extent ${c.file}`);
  }
  for (let i=0;i<rows.length;i++) if (!images.has(`battle-${String(i).padStart(3,'0')}.png`)) errors.push(`missing continuous sample ${i}`);
  for (const name of ['wide-start.png','wide-middle.png','wide-end.png','narrow-page.png']) if (!images.has(name)) errors.push(`missing page ${name}`);
  if (images.size!==rows.length+4) errors.push('unexpected image count');
  const expectedActions=[60,180].filter(t=>t<=ticks);
  if (report.actions.length!==expectedActions.length) errors.push('wrong assignment attempt count');
  for (let i=0;i<report.actions.length;i++) {
    const a=report.actions[i];
    if (a.tick!==expectedActions[i] || a.action!=='repair_helpers' || a.value!==(a.tick===60?1:0) || typeof a.receipt?.ok!=='boolean' || (!a.receipt.ok && typeof a.receipt.reason!=='string') || a.before?.tick!==a.tick || a.after?.tick!==a.tick || JSON.stringify(a.before?.native)!==JSON.stringify(a.after?.native) || JSON.stringify(a.before?.contract)!==JSON.stringify(a.after?.contract)) errors.push(`invalid actual command receipt ${i}`);
  }
  if (!report.checks?.some(x=>x.name==='pause'&&x.frames===8&&x.unchanged) || !report.checks?.some(x=>x.name==='real_entry'&&x.receipt?.ok)) errors.push('entry or pause evidence absent');
  if (report.checks?.filter(x=>x.name==='page_layout').some(x=>x.layout.panels.some(p=>!p.fits))) errors.push('full-page layout needs review');
  return errors;
}

// Reconstruct the actual RGBA8 framebuffer from PNG scanlines independently of
// the Godot report. Both lossless file identity and raw pixel identity are checked.
export function pngFramebuffer(bytes) {
  if (bytes.length<33 || bytes.subarray(0,8).toString('hex')!=='89504e470d0a1a0a') throw new Error('invalid PNG signature');
  const width=bytes.readUInt32BE(16), height=bytes.readUInt32BE(20), depth=bytes[24], color=bytes[25];
  if (!width || !height || width*height>20_000_000 || depth!==8 || ![2,6].includes(color) || bytes[28]!==0) throw new Error('unsupported PNG geometry or format');
  const chunks=[];
  for (let offset=8;offset+12<=bytes.length;) {
    const size=bytes.readUInt32BE(offset), type=bytes.toString('ascii',offset+4,offset+8);
    if (offset+12+size>bytes.length) throw new Error('truncated PNG chunk');
    if (type==='IDAT') chunks.push(bytes.subarray(offset+8,offset+8+size));
    offset+=12+size;
    if (type==='IEND') break;
  }
  const channels=color===6?4:3, stride=width*channels, expected=(stride+1)*height;
  const raw=inflateSync(Buffer.concat(chunks),{maxOutputLength:expected});
  if (raw.length!==expected) throw new Error('PNG scanline length differs');
  const pixels=Buffer.alloc(stride*height);
  const paeth=(a,b,c)=>{const p=a+b-c,pa=Math.abs(p-a),pb=Math.abs(p-b),pc=Math.abs(p-c);return pa<=pb&&pa<=pc?a:pb<=pc?b:c;};
  for (let y=0;y<height;y++) {
    const filter=raw[y*(stride+1)];
    if (filter>4) throw new Error('unknown PNG filter');
    for (let x=0;x<stride;x++) {
      const left=x>=channels?pixels[y*stride+x-channels]:0, up=y?pixels[(y-1)*stride+x]:0, corner=y&&x>=channels?pixels[(y-1)*stride+x-channels]:0;
      const add=filter===1?left:filter===2?up:filter===3?Math.floor((left+up)/2):filter===4?paeth(left,up,corner):0;
      pixels[y*stride+x]=(raw[y*(stride+1)+1+x]+add)&255;
    }
  }
  let rgba=pixels;
  if (channels===3) { rgba=Buffer.alloc(width*height*4); for(let p=0;p<width*height;p++){rgba[p*4]=pixels[p*3];rgba[p*4+1]=pixels[p*3+1];rgba[p*4+2]=pixels[p*3+2];rgba[p*4+3]=255;} }
  return {width,height,sha256:digest(rgba)};
}

function snapshotTree(directory) {
  const result={};
  const visit=(dir,prefix='')=>{
    if (!existsSync(dir)) return;
    for (const entry of readdirSync(dir,{withFileTypes:true}).sort((a,b)=>a.name.localeCompare(b.name))) {
      const path=join(dir,entry.name), key=prefix+entry.name;
      if (entry.isDirectory()) visit(path,key+'/');
      else if (entry.isFile()) result[key]=hash(path);
      else result[key]='non-regular-entry';
    }
  };
  visit(directory);
  return result;
}

const SOURCES=[
  'project.godot','game/scenes/main/main_scene.tscn','game/scenes/main/main_scene.gd','game/runtime/game_router.gd','game/ui/menu/main_menu.gd',
  'game/research/laboratory.gd','game/research/catalog.gd','game/research/paper_reader.gd','game/research/parameter_panel.gd','assets/research/catalog.json','assets/research/papers/crew-role-effects.md',
  'game/research/demos/crew_role_experiment.gd','game/research/demos/crew_workshop_experiment.gd','game/research/demos/crew_battle_experiment.gd','game/research/demos/crew_battle_trial.gd','game/research/demos/crew_role_rules.gd','game/research/demos/crew_contract.gd',
  'game/ui/shared/parchment_theme.gd','game/ui/shared/maritime_art_theme.gd','game/ui/shared/painted_window_style.gd','assets/ui/ming_maritime/painted/quiet/runtime/command-panel.png',
  'modules/naval_simulation/encounter.gd','modules/naval_simulation/combat/cannon_system.gd','modules/naval_simulation/combat/projectiles.gd','modules/contracts/physics_types.gd',
  'game/presentation/world/naval_world_view.gd','game/presentation/ships/ship_view.gd','game/presentation/crew/crew_view.gd','game/presentation/combat/combat_effects.gd','modules/scene_engine/world/world_view.gd','modules/scene_engine/ocean/projected_ocean.gd','modules/scene_engine/ocean/reference_game_water.gdshader',
  'tools/research/capture_crew_battle_gpu.gd','tools/research/run_crew_battle_gpu.mjs'
];

async function run() {
  const [mode,id,...extra]=process.argv.slice(2);
  if (!['--gpu','--guard'].includes(mode) || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(id||'') || id.length>72 || extra.length) throw new Error('Usage: rtk proxy node tools/research/run_crew_battle_gpu.mjs --gpu|--guard <fresh-run-id>');
  if (!existsSync('project.godot')) throw new Error('Run from project root');
  const root=resolve('.'), evidence=resolve('docs/research/evidence/crew-role-effects');
  mkdirSync(evidence,{recursive:true});
  const canonicalEvidence=realpathSync(evidence), dest=join(canonicalEvidence,id);
  if (!inside(dest,canonicalEvidence)) throw new Error('Output outside study');
  mkdirSync(dest);
  const profile=join(dest,'profile'), app=join(profile,'roaming'), local=join(profile,'local'), output=join(dest,'frames');
  mkdirSync(app,{recursive:true}); mkdirSync(local);
  const originalAppdata=process.env.APPDATA;
  if (!originalAppdata || inside(profile,originalAppdata) || inside(originalAppdata,profile) || resolve(profile).toLowerCase()===resolve(originalAppdata).toLowerCase()) throw new Error('Invalid original profile or overlap');
  const originalUserdir=join(originalAppdata,'Godot','app_userdata','MingArmada');
  const originalBefore=snapshotTree(originalUserdir), sourceBefore=Object.fromEntries(SOURCES.map(p=>[p,hash(p)]));
  const exe=process.env.GODOT_EXE || 'C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe';
  const env={...process.env,APPDATA:app,LOCALAPPDATA:local,CREW_BATTLE_PROFILE_ROOT:profile,CREW_BATTLE_ORIGINAL_APPDATA:originalAppdata,CREW_BATTLE_CAPTURE_OUTPUT:output};
  const args=[...(mode==='--guard'?['--headless']:[]),'--path',root,'--script','res://tools/research/capture_crew_battle_gpu.gd','--',`--output=res://docs/research/evidence/crew-role-effects/${id}/frames`];
  writeNew(join(dest,'start.json'),{startedUtc:new Date().toISOString(),mode,id,exe,exeSha256:hash(exe),args,profile,app,local,originalUserdir,sourceBefore,originalBefore,timeoutSeconds:600,scope:'Declared direct source and renderer entry files only; not a recursive dependency or imported-resource freeze. Actual laboratory, isolated profile.'});
  console.log(`CREW_BATTLE_GPU_LAUNCH mode=${mode} evidence=${dest} timeout_seconds=600`);
  const child=spawn('rtk',['proxy',exe,...args],{cwd:root,env,stdio:['ignore','pipe','pipe'],windowsHide:true});
  let data='', pending='', error='', timedOut=false;
  const receive=chunk=>{
    const value=chunk.toString(); data+=value; pending+=value;
    const lines=pending.split(/\r?\n/); pending=lines.pop();
    for(const line of lines) if (line.startsWith('CREW_BATTLE_GPU') || /FAIL CREW BATTLE GPU|SCRIPT ERROR:|\bERROR:/.test(line)) console.log(line);
  };
  child.stdout.on('data',receive); child.stderr.on('data',receive); child.on('error',e=>{error=e.message;});
  const started=Date.now();
  const heartbeat=setInterval(()=>console.log(`CREW_BATTLE_GPU_WAIT elapsed_seconds=${Math.round((Date.now()-started)/1000)}`),30000);
  const timeout=setTimeout(()=>{timedOut=true;if(child.pid)spawn('rtk',['proxy','taskkill','/PID',String(child.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});},600000);
  const result=await new Promise(done=>child.on('close',(code,signal)=>done({code,signal})));
  clearTimeout(timeout); clearInterval(heartbeat);
  writeFileSync(join(dest,'process.log'),data,{flag:'wx'});
  const sourceAfter=Object.fromEntries(SOURCES.map(p=>[p,hash(p)])), originalAfter=snapshotTree(originalUserdir);
  const sourceUnchanged=JSON.stringify(sourceBefore)===JSON.stringify(sourceAfter), originalUnchanged=JSON.stringify(originalBefore)===JSON.stringify(originalAfter);
  const diagnostic=/SCRIPT ERROR:|\bERROR:|\b(?:Parse|Compile) Error:|Failed to load (?:script|resource)/i.test(data);
  const errors=[];
  let capture=null;
  if (mode==='--gpu' && existsSync(join(output,'capture-result.json'))) {
    const report=JSON.parse(readFileSync(join(output,'capture-result.json'),'utf8'));
    errors.push(...auditTimeline(report));
    for (const image of report.captures||[]) {
      if (typeof image.file!=='string' || !/^[a-z0-9-]+\.png$/.test(image.file)) { errors.push('unsafe image path'); continue; }
      const file=join(output,image.file);
      if (!inside(file,output) || !existsSync(file)) { errors.push(`missing image ${image.file}`); continue; }
      try {
        const bytes=readFileSync(file), framebuffer=pngFramebuffer(bytes);
        if (digest(bytes)!==image.sha256 || framebuffer.width!==image.viewport[0] || framebuffer.height!==image.viewport[1] || framebuffer.sha256!==image.framebuffer_sha256) errors.push(`PNG or framebuffer differs ${image.file}`);
      } catch(e) { errors.push(`${image.file}: ${e.message}`); }
    }
    if (readdirSync(output).filter(p=>p.endsWith('.png')).length!==report.captures.length) errors.push('unreported or missing PNG files');
    capture={sha256:hash(join(output,'capture-result.json')),gpu:report.gpu,renderer:report.renderer,captures:report.captures.length,sampledFrames:report.sequence.length,physicsTicks:report.physicsChecks,earlyStop:report.earlyStop,errors};
  }
  const markers=data.split(/\r?\n/).filter(s=>s.startsWith('CREW_BATTLE_GPU'));
  const finalMarkers=markers.filter(s=>s.startsWith('CREW_BATTLE_GPU captures='));
  const pass=mode==='--guard'
    ? result.code===2 && markers.length===1 && markers[0]==='CREW_BATTLE_GPU_GUARD_REJECTED failures=1' && data.includes('non-headless graphics required') && !existsSync(output)
    : result.code===0 && finalMarkers.length===1 && /^CREW_BATTLE_GPU captures=\d+ samples=\d+ physics_ticks=\d+ failures=0$/.test(finalMarkers[0]) && capture!==null && errors.length===0;
  const valid=pass && !error && !timedOut && !diagnostic && sourceUnchanged && originalUnchanged;
  writeNew(join(dest,'process-result.json'),{finishedUtc:new Date().toISOString(),valid,...result,error,timedOut,diagnostic,markers,sourceBefore,sourceAfter,sourceUnchanged,originalBefore,originalAfter,originalUnchanged,capture,logSha256:hash(join(dest,'process.log')),scope:'Scripted actual menu/laboratory GPU, physical-state conservation and decoded framebuffer checks. Direct-source freeze only. No 60fps, per-physics-step imagery, manual play, campaign or full-game FPS acceptance.'});
  if (!valid) {console.error(JSON.stringify({error,diagnostic,sourceUnchanged,originalUnchanged,errors}));process.exitCode=1;}
  console.log(`CREW_BATTLE_GPU_VALIDATION valid=${valid} evidence=${dest}`);
}

if (process.argv[1] && import.meta.url===pathToFileURL(resolve(process.argv[1])).href) run().catch(error=>{console.error(error.stack);process.exitCode=1;});
