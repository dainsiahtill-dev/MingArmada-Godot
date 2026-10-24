import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const dir=path.dirname(fileURLToPath(import.meta.url)),files=process.argv.slice(2);
for(const file of files){const x=JSON.parse(fs.readFileSync(path.join(dir,file),'utf8'));for(const a of x.assets)console.log(JSON.stringify(a));}
