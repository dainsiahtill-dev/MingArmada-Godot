import {spawn} from 'node:child_process';
import {mkdir,writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
// Explicit argument JSON avoids shell quoting and preserves complete raw logs.
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const [output,argsJSON,cwdArg]=process.argv.slice(2);
if(!output||!argsJSON) throw Error('Usage: run-research-proof.mjs output.json GodotArgsJSON [cwd]');
const args=JSON.parse(argsJSON);
if(!Array.isArray(args)||!args.every(x=>typeof x==='string')) throw Error('Expected string argument array');
const godot=process.env.GODOT_EXE||'C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe';
const destination=path.resolve(root,output);
await mkdir(path.dirname(destination),{recursive:true});
const result={startedAtUtc:new Date().toISOString(),godot,args,cwd:cwdArg||root,exitCode:null,stdout:'',stderr:'',timedOut:false};
const child=spawn('rtk',['proxy',godot,...args],{cwd:result.cwd,windowsHide:true,stdio:['ignore','pipe','pipe']});
child.stdout.on('data',x=>{result.stdout+=x;});child.stderr.on('data',x=>{result.stderr+=x;});
const timer=setTimeout(()=>{result.timedOut=true;spawn('rtk',['proxy','taskkill','/PID',String(child.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});},180000);
await new Promise(resolve=>{child.on('error',e=>{result.processError=String(e);resolve();});child.on('close',code=>{result.exitCode=code;resolve();});});
clearTimeout(timer);result.finishedAtUtc=new Date().toISOString();
result.diagnostics=(result.stdout+'\n'+result.stderr).split(/\r?\n/).filter(x=>/SCRIPT ERROR:|\bERROR:|\b(?:Parse|Compile) Error:|Failed to load (?:script|resource)/i.test(x));
result.valid=result.exitCode===0&&!result.timedOut&&!result.processError&&result.diagnostics.length===0;
const markers={
 'res://tools/verify-laboratory-environment-gpu.gd':'LABORATORY_ENVIRONMENT_GPU ',
 'res://tools/verify-shore-edge-gpu.gd':'SHORE_EDGE_GPU ',
 'res://tools/verify-shore-edge-production.gd':'SHORE_EDGE_PRODUCTION ',
 'res://tools/verify-wake-flow-gpu.gd':'WAKE_FLOW_GPU ',
 'res://tools/verify-wake-production-gpu.gd':'WAKE_PRODUCTION_GPU ',
 'res://tools/verify-interactive-wake-field-gpu.gd':'INTERACTIVE_WAKE_GPU ',
 'res://tools/verify-interactive-wake-lab-gpu.gd':'INTERACTIVE_WAKE_LAB_GPU ',
 'res://tools/verify-interactive-wake-production-gpu.gd':'INTERACTIVE_WAKE_PRODUCTION_GPU ',
 'res://tools/diagnose-ship-water-optics.gd':'INTERACTIVE_WAKE_PRODUCTION_GPU ',
 'res://tools/verify-water-transmission-shore.gd':'WATER_TRANSMISSION_SHORE ',
 'res://tools/diagnose-voyage-ship-line.gd':'VOYAGE_SHIP_LINE ',
 'res://tools/verify-shadow-directed-boundary-gpu.gd':'VOYAGE_SHIP_LINE ',
};
const script=args[args.indexOf('--script')+1];
const marker=markers[script]||(script?.endsWith('verify-laboratory-pack.gd')?'LABORATORY_PACK_TESTS ':null);
if(marker){
 result.expectedCompletionMarker=marker;
 const lines=result.stdout.split(/\r?\n/).filter(x=>x.startsWith(marker));
 result.completionConfirmed=lines.length===1&&/failures=0$/.test(lines[0]);
 result.valid=result.valid&&result.completionConfirmed;
}
await writeFile(destination,JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({valid:result.valid,exitCode:result.exitCode,diagnostics:result.diagnostics,output:destination}));
process.exitCode=result.valid?0:1;
