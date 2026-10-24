// Deliberate visual revision of a newly generated selection; preserve former bytes and receipt.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {inspectImage} from '../../../tools/verify-zheng-story.mjs';
const dir=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(dir,'../../..');
const [id,newFile,reason]=process.argv.slice(2);
if(!/^zzl_a[1-6]_s[1-4]_0[12]$/.test(id||'')||!reason?.trim())throw new Error('Explicit asset identity and revision reason required');
const source=path.resolve(newFile||''),allowed=path.resolve('C:/Users/dains/.codex/generated_images')+path.sep;
if(!source.startsWith(allowed)||!source.endsWith('.png'))throw new Error('Expected generated PNG source');
const newBytes=fs.readFileSync(source);inspectImage(newBytes);
const selected=path.resolve(dir,'../zheng-zhilong/images/illustrated-2026-10-24',id+'.png');
if(!selected.startsWith(root+path.sep))throw new Error('Selection escaped workspace');
const oldBytes=fs.readFileSync(selected),hash=b=>crypto.createHash('sha256').update(b).digest('hex');
if(hash(oldBytes)===hash(newBytes))throw new Error('Revision has identical bytes');
const archive=path.join(dir,'variants',id+'-'+hash(oldBytes).slice(0,12)+'.png');
fs.mkdirSync(path.dirname(archive),{recursive:true});if(fs.existsSync(archive))throw new Error('Archived variant already exists');
const receipt=JSON.parse(fs.readFileSync(path.join(dir,'receipts',id+'.json')));
fs.renameSync(selected,archive);
const result=spawnSync(process.execPath,[path.join(dir,'record-generation.mjs'),id,source],{cwd:root,encoding:'utf8'});
if(result.status!==0){fs.copyFileSync(archive,selected);throw new Error(result.stderr||result.stdout||'Revision recording failed; prior selected bytes restored');}
const report={id,reason,previous:receipt,previousArchive:path.relative(root,archive).replaceAll('\\','/'),newSha256:hash(newBytes),revisedAt:new Date().toISOString()};
fs.writeFileSync(path.join(dir,'variants',id+'-'+hash(oldBytes).slice(0,12)+'.json'),JSON.stringify(report,null,2)+'\n');console.log(result.stdout.trim());
