import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const runId=new Date().toISOString().replace(/[:.]/g,'-');
const output=path.join(root,'docs/design/2026-10-26-ming-maritime/evidence/native',runId);
const profile=path.join(root,'Temp/ming-maritime-profiles/native',runId);
const original=path.join(process.env.APPDATA,'Godot/app_userdata/MingArmada');
function slots(directory){
  const result={};
  for(const name of ['settings.json','saves/mingqi-v2.json','saves/legacy-v1.json']) for(const suffix of ['', '.backup','.rollback','.staged']){
    const relative=name+suffix, file=path.join(directory,relative);
    result[relative]=fs.existsSync(file)?createHash('sha256').update(fs.readFileSync(file)).digest('hex'):null;
  }
  return result;
}
fs.mkdirSync(output,{recursive:true}); fs.mkdirSync(profile,{recursive:true});
const stdout=fs.openSync(path.join(output,'game.log'),'wx');
const exe=process.env.GODOT_EXE||'C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe';
const before=slots(original);
const args=['--path',root,'--resolution','1600x900'];
const child=spawn(exe,args,{cwd:root,detached:true,windowsHide:false,stdio:['ignore',stdout,stdout],env:{...process.env,APPDATA:profile,LOCALAPPDATA:profile}});
const receipt={runId,pid:child.pid,output,profile,exe,args,originalDirectory:original,originalSlotsBefore:before,scope:'Normal project entry, isolated fresh settings and saves; native controls, no scripted scene replacement.'};
fs.writeFileSync(path.join(output,'launch.json'),JSON.stringify(receipt,null,2));
child.unref(); fs.closeSync(stdout);
console.log(JSON.stringify({pid:child.pid,output,profile}));
