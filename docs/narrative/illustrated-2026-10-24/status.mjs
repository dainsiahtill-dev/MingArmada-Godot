import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const dir=path.dirname(fileURLToPath(import.meta.url)),read=f=>JSON.parse(fs.readFileSync(path.join(dir,f),'utf8'));
const jobs=['boards-1-3.json','boards-4-6.json'].flatMap(f=>read(f).assets);
const receipts=fs.readdirSync(path.join(dir,'receipts')).filter(f=>f.endsWith('.json')).map(f=>read('receipts/'+f));
const ids=new Set(receipts.map(r=>r.id));
const requested=process.argv.slice(2);
console.log(JSON.stringify(requested.length?receipts.filter(r=>requested.includes(r.id)):{expected:jobs.length,selected:receipts.length,missing:jobs.filter(j=>!ids.has(j.id)).map(j=>j.id),bytes:receipts.reduce((sum,r)=>sum+r.bytes,0)}));
