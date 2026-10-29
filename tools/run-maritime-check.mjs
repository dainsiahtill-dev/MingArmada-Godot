import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const raw=process.argv.slice(2);
const logFlag=raw.find(value=>value.startsWith('--run-log='));
const args=raw.filter(value=>!value.startsWith('--run-log='));
if(!args.length) throw new Error('Godot arguments required');
const logPath=logFlag?path.resolve(root,logFlag.slice('--run-log='.length)):null;
if(logPath&&(!logPath.startsWith(root+path.sep)||fs.existsSync(logPath)||fs.existsSync(logPath+'.process.json'))) throw new Error('Fresh log inside workspace required');
const profile=path.join(root,'Temp/ming-maritime-profiles',String(process.pid));
fs.mkdirSync(profile,{recursive:true});
const exe=process.env.GODOT_EXE||'C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe';
// Leave time for the SceneTree watchdog to finish manifests and slot checks.
const timeoutMs=args.includes('--group=all')?1260000:360000;
const startedAtUtc=new Date().toISOString();
const startedAtMs=Date.now();
const runnerSha256=createHash('sha256').update(fs.readFileSync(fileURLToPath(import.meta.url))).digest('hex');
const result=spawnSync(exe,['--path',root,...args],{
  cwd:root,encoding:'utf8',timeout:timeoutMs,
  env:{...process.env,PARCHMENT_ORIGINAL_APPDATA:process.env.APPDATA,APPDATA:profile,LOCALAPPDATA:profile},
});
const combined=(result.stdout||'')+'\n'+(result.stderr||'');
const engineError=/SCRIPT ERROR:|\bERROR:|\b(?:Parse|Compile) Error:|Failed to load (?:script|resource)|Error loading/i.test(combined);
const runnerUnchanged=runnerSha256===createHash('sha256').update(fs.readFileSync(fileURLToPath(import.meta.url))).digest('hex');
const accepted=!result.error&&!engineError&&result.status===0&&runnerUnchanged;
if(logFlag){
  const target=logPath;
  fs.mkdirSync(path.dirname(target),{recursive:true});
  fs.writeFileSync(target,(result.stdout||'')+(result.stderr||''),{flag:'wx'});
  fs.writeFileSync(target+'.process.json',JSON.stringify({startedAtUtc,finishedAtUtc:new Date().toISOString(),durationMs:Date.now()-startedAtMs,exe,args,exitCode:result.status,signal:result.signal,processError:result.error?.message||'',engineError,accepted,profile,logSha256:createHash('sha256').update(fs.readFileSync(target)).digest('hex'),runnerSha256,runnerUnchanged},null,2),{flag:'wx'});
  process.stdout.write((result.stdout||'').split(/\r?\n/).filter(line=>!/\[\s*\d+%\s*\]|^\x1b/.test(line)).slice(-35).join('\n')+'\n');
  process.stderr.write(result.stderr||'');
}else{
  process.stdout.write(result.stdout||'');
  process.stderr.write(result.stderr||'');
}
if(result.error) console.error(result.error.message);
process.exitCode=accepted?0:1;
