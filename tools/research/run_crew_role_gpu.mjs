import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync, readdirSync, realpathSync } from 'node:fs';
import { resolve, join, relative, isAbsolute, sep } from 'node:path';
import { pathToFileURL } from 'node:url';

const hash = path => createHash('sha256').update(readFileSync(path)).digest('hex');
const writeNew = (path,value) => writeFileSync(path,JSON.stringify(value,null,2)+'\n',{flag:'wx'});
const inside = (path,parent) => { const rel=relative(resolve(parent),resolve(path)); return rel!=='' && rel!=='..' && !rel.startsWith('..'+sep) && !isAbsolute(rel); };
const finite = value => typeof value==='number' && Number.isFinite(value);
const equal = (a,b) => Math.abs(a-b)<1e-6;

export function auditTimeline(report) {
  const errors=[];
  if (!report || !Array.isArray(report.captures) || !Array.isArray(report.sequence)) return ['missing capture report'];
  if (!report.valid || report.fixedStep!==1/32 || report.lastTick!==384 || report.seed!==0 || report.audioMuted!==true || report.displayServer==='headless' || !report.gpu) errors.push('invalid execution metadata');
  if (report.captures.length!==395 || report.sequence.length!==739) errors.push('incomplete sequence');
  const series=new Map();
  for (const row of report.sequence) {
    const limit={candidate:384,baseline:256,scarce:96}[row.variant];
    const key=`${row.variant}:${row.tick}`;
    if (limit===undefined || !Number.isInteger(row.tick) || row.tick<0 || row.tick>limit || row.time!==row.tick/32 || series.has(key)) { errors.push(`invalid tick ${key}`); continue; }
    series.set(key,row);
    const l=row.ledger;
    const grain=row.variant==='scarce'?0.5:24, wood=row.variant==='scarce'?1:16;
    if (!l || ![row.hull,row.wood,row.grain,row.cooked,row.morale,row.gun_efficiency,...Object.values(l)].every(finite) || !equal(grain-row.grain,l.grain_used) || !equal(l.grain_used,l.meals_cooked) || !equal(l.meals_cooked,row.cooked+l.meals_eaten) || !equal(wood-row.wood,l.wood_used) || !equal(l.wood_used,l.hull_repaired*0.5) || !equal(row.hull-54,l.hull_repaired) || row.grain<0 || row.wood<0 || row.cooked<0 || row.hull>80 || row.morale<0 || row.morale>100 || row.gun_efficiency<0 || row.gun_efficiency>1) errors.push(`nonconservation ${key}`);
  }
  for (const [variant,last] of Object.entries({candidate:384,baseline:256,scarce:96})) for (let tick=0;tick<=last;tick++) if (!series.has(`${variant}:${tick}`)) errors.push(`missing tick ${variant}:${tick}`);
  const keys=new Set();
  for (const f of report.captures) {
    if (typeof f.file!=='string' || !/^(?:candidate-\d{3}|baseline-(?:000|128|256)|scarce-(?:000|048|096)|wide-start|wide-detached|narrow-top|narrow-roster-bottom)\.png$/.test(f.file) || keys.has(f.file)) {errors.push(`invalid image identity ${f.file}`);continue;}
    keys.add(f.file);
    if (!['experiment','page'].includes(f.kind) || !Array.isArray(f.viewport) || f.viewport.length!==2 || !f.viewport.every(x=>Number.isInteger(x)&&x>0) || !/^[a-f0-9]{64}$/.test(f.sha256||'')) errors.push(`invalid image metadata ${f.file}`);
    const s=f.snapshot;
    if (!s || s.fixed_step!==1/32 || s.time!==s.tick/32 || !s.paused || !s.ready || s.camera_mode!=='fixed' || s.parameters?.paused!==true) errors.push(`invalid capture state ${f.file}`);
    const match=f.file.match(/^(candidate|baseline|scarce)-(\d{3})\.png$/);
    if (match) {
      const row=series.get(`${match[1]}:${Number(match[2])}`);
      if (f.kind!=='experiment' || !row || s.tick!==row.tick || !equal(s.state?.hull,row.hull) || !equal(s.state?.wood,row.wood) || !equal(s.state?.grain,row.grain) || !equal(s.state?.gun_efficiency,row.gun_efficiency)) errors.push(`capture differs from same-frame state ${f.file}`);
    } else {
      const size=f.file.startsWith('wide-')?[1280,720]:[960,640];
      if (f.kind!=='page' || f.viewport[0]!==size[0] || f.viewport[1]!==size[1]) errors.push(`invalid page viewport ${f.file}`);
    }
  }
  for (let tick=0;tick<=384;tick++) if (!keys.has(`candidate-${String(tick).padStart(3,'0')}.png`)) errors.push(`missing candidate image ${tick}`);
  for (const name of ['baseline-000.png','baseline-128.png','baseline-256.png','scarce-000.png','scarce-048.png','scarce-096.png','wide-start.png','wide-detached.png','narrow-top.png','narrow-roster-bottom.png']) if (!keys.has(name)) errors.push(`missing checkpoint ${name}`);
  const before=series.get('candidate:255'), after=series.get('candidate:256'), end=series.get('candidate:384'), baseline=series.get('baseline:256'), scarce=series.get('scarce:96');
  if (!before || !after || before.gun_efficiency!==1 || after.gun_efficiency!==0.75 || !end || !baseline || after.hull<=baseline.hull || after.ledger.meals_cooked<=baseline.ledger.meals_cooked || !scarce || !equal(scarce.hull,56) || !equal(scarce.wood,0) || !equal(scarce.grain,0) || scarce.ledger.meals_eaten!==0) errors.push('required gameplay differences absent');
  if (!report.checks?.some(x=>x.name==='pause'&&x.frames===8&&x.unchanged) || report.actions?.length!==1 || report.actions[0].tick!==256 || report.actions[0].action!=='repair_detachment') errors.push('pause or assignment evidence missing');
  return errors;
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

async function run() {
  const [mode,id,...extra]=process.argv.slice(2);
  if (!['--gpu','--guard'].includes(mode) || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(id||'') || id.length>72 || extra.length) throw new Error('Usage: rtk proxy node tools/research/run_crew_role_gpu.mjs --gpu|--guard <fresh-run-id>');
  if (!existsSync('project.godot')) throw new Error('Run from project root');
  const root=resolve('.'), evidence=resolve('docs/research/evidence/crew-role-effects');
  mkdirSync(evidence,{recursive:true});
  const dest=join(realpathSync(evidence),id);
  if (!inside(dest,evidence)) throw new Error('Output outside study');
  mkdirSync(dest); // Exclusive: an existing run is not reused or overwritten.
  const profile=join(dest,'profile'), app=join(profile,'roaming'), local=join(profile,'local'), output=join(dest,'frames');
  mkdirSync(app,{recursive:true}); mkdirSync(local);
  const originalAppdata=process.env.APPDATA;
  if (!originalAppdata || inside(profile,originalAppdata) || inside(originalAppdata,profile) || resolve(profile).toLowerCase()===resolve(originalAppdata).toLowerCase()) throw new Error('Invalid original profile or overlap');
  const originalUserdir=join(originalAppdata,'Godot','app_userdata','MingArmada');
  const originalBefore=snapshotTree(originalUserdir);
  const sources=['project.godot','game/scenes/main/main_scene.tscn','game/scenes/main/main_scene.gd','game/runtime/game_router.gd','game/ui/menu/main_menu.gd','game/research/laboratory.gd','game/research/catalog.gd','game/research/paper_reader.gd','game/research/parameter_panel.gd','game/ui/shared/parchment_theme.gd','game/ui/shared/maritime_art_theme.gd','game/ui/shared/painted_window_style.gd','assets/ui/ming_maritime/painted/quiet/runtime/command-panel.png','assets/ui/ming_maritime/painted/quiet/framed/runtime/command-panel.png','assets/research/catalog.json','assets/research/papers/crew-role-effects.md','game/research/demos/crew_role_rules.gd','game/research/demos/crew_role_experiment.gd','tools/research/capture_crew_role_gpu.gd','tools/research/run_crew_role_gpu.mjs'];
  const sourceBefore=Object.fromEntries(sources.map(p=>[p,hash(p)]));
  const exe=process.env.GODOT_EXE || 'C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe';
  const env={...process.env,APPDATA:app,LOCALAPPDATA:local,CREW_PROFILE_ROOT:profile,CREW_ORIGINAL_APPDATA:originalAppdata,CREW_CAPTURE_OUTPUT:output};
  const args=[...(mode==='--guard'?['--headless']:[]),'--path',root,'--script','res://tools/research/capture_crew_role_gpu.gd','--',`--output=res://docs/research/evidence/crew-role-effects/${id}/frames`];
  writeNew(join(dest,'start.json'),{startedUtc:new Date().toISOString(),mode,id,exe,exeSha256:hash(exe),args,profile,app,local,originalUserdir,sourceBefore,originalBefore,scope:'Declared direct sources; not a recursive dependency freeze. Isolated laboratory, not production campaign.'});
  const child=spawn('rtk',['proxy',exe,...args],{cwd:root,env,stdio:['ignore','pipe','pipe'],windowsHide:mode==='--guard'});
  let data='',error='',timedOut=false;
  child.stdout.on('data',chunk=>{data+=chunk;}); child.stderr.on('data',chunk=>{data+=chunk;});
  child.on('error',e=>{error=e.message;});
  const timeout=setTimeout(()=>{
    timedOut=true;
    if (child.pid) spawn('rtk',['proxy','taskkill','/PID',String(child.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});
  },240000);
  const result=await new Promise(done=>child.on('close',(code,signal)=>done({code,signal})));
  clearTimeout(timeout);
  writeFileSync(join(dest,'process.log'),data,{flag:'wx'});
  const sourceAfter=Object.fromEntries(sources.map(p=>[p,hash(p)]));
  const originalAfter=snapshotTree(originalUserdir);
  const sourceUnchanged=JSON.stringify(sourceBefore)===JSON.stringify(sourceAfter), originalUnchanged=JSON.stringify(originalBefore)===JSON.stringify(originalAfter);
  const diagnostic=/SCRIPT ERROR:|\bERROR:|\b(?:Parse|Compile) Error:|Failed to load (?:script|resource)/i.test(data);
  const errors=[];
  let capture=null;
  if (mode==='--gpu' && existsSync(join(output,'capture-result.json'))) {
    const report=JSON.parse(readFileSync(join(output,'capture-result.json'),'utf8'));
    errors.push(...auditTimeline(report));
    for (const f of report.captures||[]) {
      if (typeof f.file!=='string' || !/^[a-z0-9-]+\.png$/.test(f.file)) {errors.push('unsafe image path');continue;}
      const file=join(output,f.file);
      if (!inside(file,output) || !existsSync(file)) {errors.push(`missing image ${f.file}`);continue;}
      const bytes=readFileSync(file);
      if (bytes.length<24 || bytes.subarray(0,8).toString('hex')!=='89504e470d0a1a0a' || bytes.readUInt32BE(16)!==f.viewport[0] || bytes.readUInt32BE(20)!==f.viewport[1] || hash(file)!==f.sha256) errors.push(`image differs ${f.file}`);
    }
    if (readdirSync(output).filter(p=>p.endsWith('.png')).length!==395) errors.push('wrong PNG file count');
    capture={sha256:hash(join(output,'capture-result.json')),gpu:report.gpu,renderer:report.renderer,captures:report.captures?.length,ticks:report.sequence?.length,errors};
  }
  const markers=data.split(/\r?\n/).filter(s=>s.startsWith('CREW_ROLE_GPU'));
  const pass=mode==='--guard' ? result.code===2 && markers.length===1 && markers[0]==='CREW_ROLE_GPU_GUARD_REJECTED failures=1' && data.includes('non-headless graphics required') && !existsSync(output) : result.code===0 && markers.length===1 && markers[0]==='CREW_ROLE_GPU captures=395 ticks=739 failures=0' && capture!==null && errors.length===0;
  const valid=pass && !error && !timedOut && !diagnostic && sourceUnchanged && originalUnchanged;
  writeNew(join(dest,'process-result.json'),{finishedUtc:new Date().toISOString(),valid,...result,error,timedOut,diagnostic,markers,sourceBefore,sourceAfter,sourceUnchanged,originalBefore,originalAfter,originalUnchanged,capture,logSha256:hash(join(dest,'process.log')),scope:'Scripted actual laboratory GPU and data checks only; no formal campaign, manual play, full-game FPS or enjoyment claim.'});
  process.stdout.write(data);
  console.log(`CREW_GPU_VALIDATION valid=${valid} evidence=${dest}`);
  if (!valid) process.exitCode=1;
}

if (process.argv[1] && import.meta.url===pathToFileURL(resolve(process.argv[1])).href) run().catch(error=>{console.error(error.stack);process.exitCode=1;});
