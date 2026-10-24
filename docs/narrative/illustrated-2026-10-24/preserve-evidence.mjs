import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
const dir=path.dirname(fileURLToPath(import.meta.url)),out=path.join(dir,'previous-evidence.json');
if(fs.existsSync(out))throw new Error('Previous evidence snapshot already exists');
const files=['DELIVERY.md','CAUSE-CHAIN.md','export-verification.json','public-verification.json','dom-verification.json','FINAL-REVIEW.md','candidate.json'];
const hashes=Object.fromEntries(files.map(f=>[f,crypto.createHash('sha256').update(fs.readFileSync(path.resolve(dir,'../full-polish-2026-10-24',f))).digest('hex')]));
fs.writeFileSync(out,JSON.stringify({at:new Date().toISOString(),directory:'full-polish-2026-10-24',hashes},null,2)+'\n');console.log('Preserved '+files.length+' previous-round evidence hashes');
