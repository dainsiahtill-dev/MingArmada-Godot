import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {inspectImage} from '../../../tools/inspect-story-image.mjs';

const dir=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(dir,'../../..');
const groups=process.argv.slice(2);
if(groups.length!==7 || new Set(groups.map(x=>x.replace(/-r\d+$/,''))).size!==7 || groups.some(x=>!/^gpu-(menu|mingqi|legacy|naval|catalog|practice|auxiliary)-r\d+$/.test(x))) throw new Error('Pass exactly seven final GPU group directories.');
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const readJson=file=>JSON.parse(fs.readFileSync(file,'utf8'));
const resPath=resource=>{
  if(!resource.startsWith('res://'))throw new Error('Invalid resource path');
  const resolved=path.resolve(root,resource.slice(6));
  if(!resolved.startsWith(root+path.sep))throw new Error('Resource escapes repository');
  return resolved;
};
const report={date:'2026-10-25',scope:'Godot UI render, layout and listed viewport input checks; not FPS or continuous gameplay validation.',groups:[],assets:[],icons:[],previews:[]};
for(const groupDir of groups){
  const source=path.join(dir,'evidence',groupDir,'capture-result.json');
  const result=readJson(source);
  if(result.failures!==0 || result.errors.length || !result.originalSlotsUnchanged || JSON.stringify(result.profileSlotsBefore)!==JSON.stringify(result.profileSlotsAfter))throw new Error(groupDir+': failed checks or changed save state');
  for(const [resource,hash] of Object.entries(result.sourceHashes)){
    if(sha(fs.readFileSync(resPath(resource)))!==hash)throw new Error(groupDir+': source drift '+resource);
  }
  const captures=result.captures.map(capture=>{
    const bytes=fs.readFileSync(resPath(capture.png));
    if(sha(bytes)!==capture.sha256)throw new Error('Capture hash mismatch: '+capture.png);
    const image=inspectImage(bytes);
    if(image.format!=='PNG' || !image.rasterValidated)throw new Error('Invalid PNG: '+capture.png);
    return {...capture,width:image.width,height:image.height,rasterValidated:image.rasterValidated};
  });
  report.groups.push({directory:groupDir,group:result.group,assertions:result.assertions,failures:result.failures,originalSlotsUnchanged:true,profileSlotsUnchanged:true,currentSourceHashesMatch:true,sourceHashes:result.sourceHashes,captures});
}
for(const asset of readJson(path.join(dir,'assets.json')).assets){
  const bytes=fs.readFileSync(path.join(root,asset.file));
  const image=inspectImage(bytes);
  if(sha(bytes)!==asset.sha256 || image.width!==asset.width || image.height!==asset.height || !image.rasterValidated)throw new Error('Asset mismatch: '+asset.file);
  report.assets.push({...asset,review:'Original PNG decoded and hash verified; active UI materials reviewed in final GPU captures. Chart background and menu draft are retained alternatives.'});
}
for(const name of fs.readdirSync(path.join(root,'assets/ui/parchment')).filter(x=>x.endsWith('.svg')).sort()){
  const file='assets/ui/parchment/'+name;
  report.icons.push({file,sha256:sha(fs.readFileSync(path.join(root,file)))});
}
const previews=[['menu','menu-normal-1600','main-menu'],['menu','menu-settings-1600','settings'],['mingqi','mingqi-port-1600','port'],['naval','naval-fleet-hud-1600','naval']];
for(const [group,label,name] of previews){
  const capture=report.groups.find(x=>x.group===group)?.captures.find(x=>x.label===label);
  if(!capture)throw new Error('Missing preview '+label);
  const file='ming-armada-ui-preview-'+name+'-2026-10-25.png';
  const dest=path.join(root,file),bytes=fs.readFileSync(resPath(capture.png));
  if(fs.existsSync(dest) && sha(fs.readFileSync(dest))!==capture.sha256)throw new Error('Existing preview differs; preserve it: '+file);
  if(!fs.existsSync(dest))fs.writeFileSync(dest,bytes,{flag:'wx'});
  report.previews.push({file,source:capture.png,sha256:capture.sha256,width:capture.width,height:capture.height});
}
report.totalCaptures=report.groups.reduce((n,g)=>n+g.captures.length,0);
report.totalAssertions=report.groups.reduce((n,g)=>n+g.assertions,0);
fs.writeFileSync(path.join(dir,'evidence/final-delivery-manifest.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({groups:report.groups.map(g=>({group:g.group,captures:g.captures.length,assertions:g.assertions})),totalCaptures:report.totalCaptures,totalAssertions:report.totalAssertions,assets:report.assets.length,icons:report.icons.length,previews:report.previews.map(p=>p.file)},null,2));
