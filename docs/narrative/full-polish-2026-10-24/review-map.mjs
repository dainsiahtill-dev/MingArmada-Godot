import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const dir=path.dirname(fileURLToPath(import.meta.url)),story=JSON.parse(fs.readFileSync(path.join(dir,process.argv[2]||'candidate.json'),'utf8'));
for(const a of story.acts){console.log('\n'+a.title+' '+a.years);for(const s of a.scenes)console.log(JSON.stringify({id:s.id,title:s.title,year:s.year,paragraphs:s.paragraphs.length,characters:s.paragraphs.join('').length,opening:s.paragraphs[0],ending:s.paragraphs.at(-1),next:s.dramaticBeat.next}));}
