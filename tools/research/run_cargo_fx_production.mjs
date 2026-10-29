import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync, readdirSync, realpathSync } from 'node:fs';
import { resolve, join, relative, isAbsolute, sep } from 'node:path';
import { pathToFileURL } from 'node:url';
import { pngFramebuffer } from './run_crew_battle_gpu.mjs';

const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const hash = file => digest(readFileSync(file));
const same = (a,b) => JSON.stringify(a) === JSON.stringify(b);
const near = (a,b) => Number.isFinite(a) && Number.isFinite(b) && Math.abs(a-b)<1e-6;
const writeNew = (file,value) => writeFileSync(file,JSON.stringify(value,null,2)+'\n',{flag:'wx'});
const inside = (file,parent) => { const p=relative(resolve(parent),resolve(file));return p!==''&&p!=='..'&&!p.startsWith('..'+sep)&&!isAbsolute(p); };

export function auditTimeline(report) {
  const errors=[];
  if (!report || !Array.isArray(report.captures) || !Array.isArray(report.sequences) || !Array.isArray(report.checks) || !Array.isArray(report.commands) || !Array.isArray(report.projectiles)) return ['missing production report'];
  if (!report.valid || report.failures?.length || !report.defaultSoundDisabled || report.masterMuteForced!==false || !near(report.fixedStep,1/60) || report.ticksPerFrame!==4 || report.nominalSamplesPerAcceptedSecond!==15 || report.acceptedSteps!==720) errors.push('incomplete fixed-step/default-audio proof');
  const byFile=new Map();
  for (const image of report.captures) {
    if (typeof image.file!=='string'||!/^[a-z0-9-]+\.png$/.test(image.file)||byFile.has(image.file)) {errors.push('invalid duplicate image identity');continue;}
    byFile.set(image.file,image);
    if (!same(image.viewport,[1600,900])||image.framebuffer_format!=='RGBA8'||!/^[a-f0-9]{64}$/.test(image.sha256||'')||!/^[a-f0-9]{64}$/.test(image.framebuffer_sha256||'')) errors.push(image.file+': invalid GPU image metadata');
    if (image.kind==='menu') continue;
    const s=image.snapshot,a=s?.audio,fx=s?.atmosphere;
    if (!s?.packet?.naval || !a || !fx?.ready || !fx.enabled || !Array.isArray(fx.particles) || fx.particles.length>fx.capacity || !near(fx.time,s.packet.naval.time+(s.tail?.elapsed||0))) errors.push(image.file+': missing production state/effects');
    if (a?.seaGain!==0||a?.windGain!==0||a?.musicGain!==0||a?.activeVoices!==0)errors.push(image.file+': actual audio not disabled');
    if (!['cargo','duel-near','duel-wide','normal'].includes(s?.camera?.mode)||!Array.isArray(s?.camera?.position)||s.camera.position.length!==3||!s.camera.position.every(Number.isFinite))errors.push(image.file+': missing camera evidence');
    if (image.kind==='mingqi') {
      const cargo=s.cargo, campaign=s.packet.campaign;
      if (!cargo?.ready||cargo.errors?.length||!campaign||cargo.floating?.length) {errors.push(image.file+': invalid real cargo projection');continue;}
      for (const [id,deck] of Object.entries(cargo.decks||{})) {
        if (!same(deck.manifest,campaign.vessels[id]?.cargo)||deck.overflow_goods?.length)errors.push(image.file+': cargo manifest differs '+id);
        if ((deck.manifest.grain||0)>0&&!deck.goods?.some(g=>g.good==='grain'))errors.push(image.file+': loaded grain not represented '+id);
      }
    }
  }
  const required=['menu-before.png','mingqi-opening.png','mingqi-convoy-loaded.png','mingqi-grain-bought.png','mingqi-grain-sold.png','mingqi-grain-restored.png','mingqi-paused.png','duel-000.png','duel-paused.png','menu-returned.png'];
  for (const file of required)if(!byFile.has(file))errors.push('missing image '+file);
  const quantity=file=>{const s=byFile.get(file)?.snapshot;return s?.packet?.campaign?.vessels[s.packet.campaign.flagshipId]?.cargo.grain;};
  if(quantity('mingqi-grain-bought.png')!==10||quantity('mingqi-grain-sold.png')!==7||quantity('mingqi-grain-restored.png')!==10)errors.push('buy/sell/readback quantities differ');
  if(byFile.get('mingqi-grain-sold.png')?.snapshot.cargo.epoch===byFile.get('mingqi-grain-restored.png')?.snapshot.cargo.epoch)errors.push('checkpoint did not replace cargo generation');
  const loaded=byFile.get('mingqi-convoy-loaded.png')?.snapshot;
  if(loaded&&Object.values(loaded.cargo.decks).filter(d=>(d.manifest.grain||0)>0&&d.goods.length>0).length<2)errors.push('convoy grain missing');
  if(loaded) {
    const id=loaded.camera?.subjectShipId,crew=loaded.crew?.[id],deck=loaded.cargo.decks[id];
    if(loaded.camera.subjectKind!=='merchant'||!id?.endsWith('-grain-a')||!(crew?.visible>0)||!crew.stations?.length||crew.drawn?.length!==crew.visible||!deck?.goods?.some(g=>g.good==='grain'))errors.push('merchant inspection lacks real cargo/crew/stations');
    for(const station of crew?.stations||[])if(!Array.isArray(station.world_position)||station.world_position.length!==3||!station.world_position.every(Number.isFinite))errors.push('invalid recorded merchant station');
  }
  for(const mode of ['mingqi','duel']) {
    const entry=report.checks.find(c=>c.name==='entry'&&c.mode===mode),leave=report.checks.find(c=>c.name==='leave'&&c.mode===mode);
    const path=mode==='mingqi'?'res://game/scenes/mingqi/mingqi_scene.gd':'res://game/scenes/naval_practice/naval_practice.gd';
    if(!entry?.ordinary_button||!entry.startup?.ok||entry.scene!==path||!leave?.released)errors.push(mode+': actual menu lifecycle incomplete');
  }
  if(!report.checks.some(c=>c.name==='mingqi-pause'&&c.unchanged&&c.frames===8))errors.push('missing cargo pause proof');
  const combat=report.checks.find(c=>c.name==='duel-combat');
  if(!combat?.pause_unchanged||!(combat.max_smoke>0)||!(combat.player_projectiles>0)||!(combat.hostile_projectiles>0))errors.push('real player/AI combat proof missing');
  const sequences=report.sequences;
  if(sequences.length!==181)errors.push('wrong continuous sample count');
  for(let i=0;i<sequences.length;i++) {
    const row=sequences[i],state=byFile.get(row.file)?.snapshot,n=state?.packet?.naval,previous=sequences[i-1];
    if(row.file!==`duel-${String(i).padStart(3,'0')}.png`||row.sample!==i||row.physics_steps!==i*4||row.tick!==n?.tick||!near(row.time,n?.time)||!near(row.visual_time,state?.atmosphere?.time))errors.push('sequence/frame state mismatch '+i);
    if(previous&&(row.tick<previous.tick||row.tick>previous.tick+4||!near(row.time-previous.time,(row.tick-previous.tick)/60)||row.visual_time<previous.visual_time||row.visual_time>previous.visual_time+4/60+1e-6))errors.push('accepted clock mismatch '+i);
  }
  const first=byFile.get('duel-000.png')?.snapshot.packet.naval;
  if(first) {
    const player=first.playerId,hostiles=new Set(first.ships.filter(s=>s.team==='hostile').map(s=>s.id));
    if(!report.projectiles.some(p=>p.shipId===player)||!report.projectiles.some(p=>hostiles.has(p.shipId)))errors.push('observed native projectiles lack both combat owners');
    const ids=new Set();
    for(const p of report.projectiles){if(typeof p.id!=='string'||ids.has(p.id)||!Object.values(p.position||{}).every(Number.isFinite))errors.push('invalid native projectile');ids.add(p.id);}
  }
  for(const kind of ['accept-convoy','buy','sell','save-checkpoint','adopt-checkpoint'])if(!report.commands.some(c=>c.mode==='mingqi'&&c.command.type===kind&&c.receipt.ok))errors.push('real command receipt missing '+kind);
  return errors;
}

function snapshotTree(directory) {
  const result={};
  const visit=(dir,prefix='')=>{if(!existsSync(dir))return;for(const entry of readdirSync(dir,{withFileTypes:true}).sort((a,b)=>a.name.localeCompare(b.name))){const file=join(dir,entry.name),key=prefix+entry.name;if(entry.isDirectory())visit(file,key+'/');else if(entry.isFile())result[key]=hash(file);else result[key]='non-regular-entry';}};
  visit(directory);return result;
}
const SOURCES=[
  'project.godot','game/scenes/main/main_scene.tscn','game/scenes/main/main_scene.gd','game/runtime/game_router.gd','game/ui/menu/main_menu.gd',
  'game/scenes/mingqi/mingqi_scene.gd','game/runtime/mingqi_runtime.gd','game/domain/mingqi/campaign.gd','game/domain/mingqi/cargo_damage.gd','game/domain/persistence/save_codec.gd','game/runtime/near_field_bridge.gd',
  'game/scenes/naval_practice/naval_practice.gd','game/runtime/naval_practice_runtime.gd','game/runtime/sailing_simulation.gd','game/scenes/common/terminal_presentation_clock.gd','game/scenes/common/sea_services.gd',
  'game/presentation/world/naval_world_view.gd','game/presentation/ships/ship_view.gd','game/presentation/ships/ship_damage.gd','game/presentation/combat/combat_effects.gd','game/presentation/combat/combat_atmosphere.gd',
  'game/presentation/cargo/cargo_models.gd','game/presentation/cargo/cargo_deck_view.gd','game/presentation/cargo/cargo_world_view.gd','game/presentation/cargo/cargo_drift.gd',
  'game/presentation/crew/deck_stations.gd','game/presentation/crew/crew_view.gd','modules/scene_engine/assets/asset_library.gd','modules/scene_engine/assets/ship_model_provider.gd','modules/scene_engine/assets/hero_ship_provider.gd',
  'game/persistence/user_settings.gd','game/persistence/save_coordinator.gd','game/presentation/audio/game_audio.gd','modules/naval_simulation/encounter.gd','modules/contracts/wave_descriptor.gd',
  'assets/models/cargo_pack/r1/manifest.json','assets/textures/combat_atmosphere/r1/smoke-puff.png','assets/textures/combat_atmosphere/r1/flame.png',
  'tools/research/capture_cargo_fx_production.gd','tools/research/run_cargo_fx_production.mjs','tools/research/run_crew_battle_gpu.mjs',
  ...['grain','water','wood','iron','powder','cloth','silk','porcelain','tea','sugar','salt','spices'].map(g=>`assets/models/cargo_pack/r1/${g}.glb`),
];

async function run() {
  const [mode,id,...extra]=process.argv.slice(2);
  if(!['--gpu','--guard'].includes(mode)||!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(id||'')||id.length>72||extra.length)throw new Error('Usage: rtk proxy node tools/research/run_cargo_fx_production.mjs --gpu|--guard <fresh-run-id>');
  if(!existsSync('project.godot'))throw new Error('Run from project root');
  const root=resolve('.'),evidence=resolve('docs/research/evidence/cargo-fx-production');mkdirSync(evidence,{recursive:true});
  const canonicalEvidence=realpathSync(evidence),dest=join(canonicalEvidence,id);if(!inside(dest,canonicalEvidence))throw new Error('Output outside topic');mkdirSync(dest);
  const profile=join(dest,'profile'),app=join(profile,'roaming'),local=join(profile,'local'),output=join(dest,'frames');mkdirSync(app,{recursive:true});mkdirSync(local);
  const originalAppdata=process.env.APPDATA;
  if(!originalAppdata||inside(profile,originalAppdata)||inside(originalAppdata,profile)||resolve(profile).toLowerCase()===resolve(originalAppdata).toLowerCase())throw new Error('Invalid original profile or overlap');
  const originalUserdir=join(originalAppdata,'Godot','app_userdata','MingArmada');
  const originalBefore=snapshotTree(originalUserdir),sourceBefore=Object.fromEntries(SOURCES.map(p=>[p,hash(p)]));
  const exe=process.env.GODOT_EXE||'C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe';
  const env={...process.env,APPDATA:app,LOCALAPPDATA:local,CARGO_FX_PRODUCTION_PROFILE_ROOT:profile,CARGO_FX_PRODUCTION_ORIGINAL_APPDATA:originalAppdata,CARGO_FX_PRODUCTION_CAPTURE_OUTPUT:output};
  const args=[...(mode==='--guard'?['--headless']:[]),'--path',root,'--script','res://tools/research/capture_cargo_fx_production.gd','--',`--output=res://docs/research/evidence/cargo-fx-production/${id}/frames`];
  writeNew(join(dest,'start.json'),{startedUtc:new Date().toISOString(),mode,id,exe,exeSha256:hash(exe),args,profile,app,local,originalUserdir,sourceBefore,originalBefore,timeoutSeconds:1200,scope:'Direct-source/assets freeze; ordinary production menu routes with scripted real commands and explicitly recorded inspection camera. Not recursive dependency freeze or manual play.'});
  console.log(`CARGO_FX_PRODUCTION_LAUNCH mode=${mode} evidence=${dest} timeout_seconds=1200`);
  const child=spawn('rtk',['proxy',exe,...args],{cwd:root,env,stdio:['ignore','pipe','pipe'],windowsHide:true});
  let data='',pending='',error='',timedOut=false;
  const receive=chunk=>{const text=chunk.toString();data+=text;pending+=text;const lines=pending.split(/\r?\n/);pending=lines.pop();for(const line of lines)if(line.startsWith('CARGO_FX_PRODUCTION')||/FAIL CARGO FX PRODUCTION|SCRIPT ERROR:|\bERROR:/.test(line))console.log(line);};
  child.stdout.on('data',receive);child.stderr.on('data',receive);child.on('error',v=>{error=v.message;});
  const started=Date.now(),heartbeat=setInterval(()=>console.log(`CARGO_FX_PRODUCTION_WAIT elapsed_seconds=${Math.round((Date.now()-started)/1000)}`),30000);
  const timeout=setTimeout(()=>{timedOut=true;if(child.pid)spawn('rtk',['proxy','taskkill','/PID',String(child.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});},1200000);
  const result=await new Promise(done=>child.on('close',(code,signal)=>done({code,signal})));clearTimeout(timeout);clearInterval(heartbeat);
  writeFileSync(join(dest,'process.log'),data,{flag:'wx'});
  const sourceAfter=Object.fromEntries(SOURCES.map(p=>[p,hash(p)])),originalAfter=snapshotTree(originalUserdir),sourceUnchanged=same(sourceBefore,sourceAfter),originalUnchanged=same(originalBefore,originalAfter);
  const diagnostic=/SCRIPT ERROR:|\bERROR:|\b(?:Parse|Compile) Error:|Failed to load (?:script|resource)/i.test(data),errors=[];
  let capture=null;const reportPath=join(output,'capture-result.json');
  if(mode==='--gpu'&&existsSync(reportPath)) {
    const report=JSON.parse(readFileSync(reportPath,'utf8'));errors.push(...auditTimeline(report));
    for(const image of report.captures||[]) {
      if(typeof image.file!=='string'||!/^[a-z0-9-]+\.png$/.test(image.file)){errors.push('unsafe image path');continue;}
      const file=join(output,image.file);if(!inside(file,output)||!existsSync(file)){errors.push('missing '+image.file);continue;}
      try{const bytes=readFileSync(file),pixels=pngFramebuffer(bytes);if(digest(bytes)!==image.sha256||!same([pixels.width,pixels.height],image.viewport)||pixels.sha256!==image.framebuffer_sha256)errors.push('PNG/decoded framebuffer differs '+image.file);}catch(failure){errors.push(image.file+': '+failure.message);}
    }
    if(readdirSync(output).filter(p=>p.endsWith('.png')).length!==report.captures.length)errors.push('unreported/missing PNG');
    capture={sha256:hash(reportPath),gpu:report.gpu,renderer:report.renderer,captures:report.captures.length,sampledFrames:report.sequences.length,acceptedSteps:report.acceptedSteps,checks:report.checks,errors};
  }
  const markers=data.split(/\r?\n/).filter(l=>l.startsWith('CARGO_FX_PRODUCTION')),finalMarkers=markers.filter(l=>l.startsWith('CARGO_FX_PRODUCTION captures='));
  const pass=mode==='--guard'?result.code===2&&markers.length===1&&markers[0]==='CARGO_FX_PRODUCTION_GUARD_REJECTED failures=1'&&data.includes('non-headless graphics required')&&!existsSync(output):result.code===0&&finalMarkers.length===1&&/^CARGO_FX_PRODUCTION captures=\d+ samples=\d+ accepted_steps=\d+ failures=0$/.test(finalMarkers[0])&&capture!==null&&errors.length===0;
  const valid=pass&&!error&&!timedOut&&!diagnostic&&sourceUnchanged&&originalUnchanged;
  writeNew(join(dest,'process-result.json'),{finishedUtc:new Date().toISOString(),valid,...result,error,timedOut,diagnostic,markers,sourceBefore,sourceAfter,sourceUnchanged,originalBefore,originalAfter,originalUnchanged,capture,logSha256:hash(join(dest,'process.log')),scope:'Scripted ordinary production menu routes, real command receipts, GPU samples after four fixed callbacks, actual audio gains and saved cargo restoration. Direct-source freeze only. Visual art still requires review; no manual play or game FPS claim.'});
  if(!valid){console.error(JSON.stringify({error,diagnostic,sourceUnchanged,originalUnchanged,errors}));process.exitCode=1;}
  console.log(`CARGO_FX_PRODUCTION_VALIDATION valid=${valid} evidence=${dest}`);
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)run().catch(error=>{console.error(error.stack);process.exitCode=1;});
