import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {inspectImage} from '../../../tools/inspect-story-image.mjs';
const dir=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(dir,'../../..');
const specs=JSON.parse(fs.readFileSync(path.join(dir,'asset-prompts.json'),'utf8')).assets;
const assets=[];
for(const s of specs){const b=fs.readFileSync(s.sourcePath),info=inspectImage(b),destination=path.join(root,s.file);if(fs.existsSync(destination)&&!fs.readFileSync(destination).equals(b))throw new Error('Refuse overwrite '+s.file);fs.copyFileSync(s.sourcePath,destination);assets.push({id:s.id,file:s.file,...info,bytes:b.length,sha256:crypto.createHash('sha256').update(b).digest('hex'),review:'Generated output visually inspected: standalone material/background, no baked text or UI. Final in-engine legibility still requires GPU capture.'});}
for(const file of ['ming-armada-ui-background-parchment.png','ming-armada-ui-background-parchment-draft-v1.png']){const b=fs.readFileSync(path.join(root,file));assets.push({id:file.includes('draft')?'menu-draft':'menu',file,...inspectImage(b),bytes:b.length,sha256:crypto.createHash('sha256').update(b).digest('hex')});}
fs.writeFileSync(path.join(dir,'assets.json'),JSON.stringify({provider:'ChatGPT built-in image_gen',assets},null,2)+'\n');console.log(JSON.stringify(assets.map(({id,file,width,height,bytes})=>({id,file,width,height,bytes}))));
