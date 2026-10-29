import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const dir=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(dir,'../../..');
const name=process.argv[2];
if(!/^mingqi-20261027-[a-z0-9-]+$/.test(name||''))throw new Error('Specify a fresh mingqi-20261027-... capture name');
const evidence=path.join(root,'docs/design/2026-10-25-parchment-ui/evidence',name);
if(fs.existsSync(evidence))throw new Error('Capture directory already exists');
const profile=path.join(root,'Temp/parchment-ui-profiles',name);
if(fs.existsSync(profile))throw new Error('Capture profile already exists');
const original=process.env.APPDATA;
if(!original)throw new Error('Original APPDATA required for player-save protection');
fs.mkdirSync(path.join(profile,'roaming'),{recursive:true});
fs.mkdirSync(path.join(profile,'local'),{recursive:true});
const exe='C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe';
const output='res://docs/design/2026-10-25-parchment-ui/evidence/'+name;
const child=spawn(exe,['--path',root,'--script','res://tools/capture-parchment-ui.gd','--','--group=mingqi','--output='+output],{
  cwd:root,windowsHide:true,env:{...process.env,PARCHMENT_ORIGINAL_APPDATA:original,APPDATA:path.join(profile,'roaming'),LOCALAPPDATA:path.join(profile,'local')},stdio:['ignore','pipe','pipe']
});
const log=fs.createWriteStream(path.join(dir,name+'.log'),{flags:'wx'});
child.stdout.on('data',x=>{process.stdout.write(x);log.write(x);});
child.stderr.on('data',x=>{process.stderr.write(x);log.write(x);});
child.on('error',error=>{console.error(error);process.exitCode=1;log.end();});
child.on('exit',code=>{log.end();process.exitCode=code??1;});
