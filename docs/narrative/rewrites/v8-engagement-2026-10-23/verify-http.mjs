import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
const dir=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(dir,'../../../..');
const local=path.join(root,'docs/narrative/zheng-zhilong');
const origin=process.argv[2]||'http://127.0.0.1:8794/docs/narrative/zheng-zhilong/';
const edition=process.argv[3]||'12';
if(!/^https?:\/\//.test(origin)||!origin.endsWith('/')||!/^\d+$/.test(edition))throw new Error('Usage: node verify-http.mjs [base-url-ending-in-slash] [edition-number]');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const paths=['index.html','story-data.js','zheng-zhilong-story.json','novel-v8.md','screenplay-v8.md','game-scenes-v8.md'];
const results=await Promise.all(paths.map(async file=>{
 try{
  const response=await fetch(origin+file+'?edition='+edition,{signal:AbortSignal.timeout(15000)});
  const bytes=Buffer.from(await response.arrayBuffer()),expected=fs.readFileSync(path.join(local,file));
  return {file,status:response.status,contentType:response.headers.get('content-type'),bytes:bytes.length,sha256:sha(bytes),matchesLocal:bytes.equals(expected),passed:response.status===200&&bytes.equals(expected)};
 }catch(error){return {file,passed:false,error:error.message};}
}));
const isPublic=new URL(origin).hostname==='8.138.113.205';
const output={checkedAt:new Date().toISOString(),url:origin+'?edition='+edition+'#top',passed:results.every(x=>x.passed),results,scope:isPublic?'Actual HTTP requests from this computer through the specified public endpoint; bytes compared with local files. Not an independent off-network device or visual/browser-layout acceptance.':'Actual loopback HTTP bytes only; not browser rendering, user interaction, LAN-device access or public-tunnel verification.'};
fs.writeFileSync(path.join(dir,isPublic?'public-http-verification.json':'http-verification.json'),JSON.stringify(output,null,2)+'\n');
console.log(JSON.stringify(output));
process.exitCode=output.passed?0:1;
