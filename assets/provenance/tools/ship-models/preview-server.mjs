import http from 'node:http';
import {readFile} from 'node:fs/promises';
import {resolve,extname,sep} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../../',import.meta.url));
const types={'.html':'text/html','.js':'text/javascript','.mjs':'text/javascript','.glb':'model/gltf-binary','.json':'application/json'};
http.createServer(async(req,res)=>{
  try {
    const path=decodeURIComponent(new URL(req.url,'http://localhost').pathname),absolute=resolve(root,'.'+path);
    if(!absolute.startsWith(resolve(root)+sep)||!['/node_modules/three/','/tools/ship-models/','/apps/game-client/public/models/ships/'].some(p=>path.startsWith(p))) {res.writeHead(403);res.end();return;}
    const bytes=await readFile(absolute);res.writeHead(200,{'Content-Type':types[extname(absolute)]??'application/octet-stream'});res.end(bytes);
  }catch{res.writeHead(404);res.end();}
}).listen(4177,'127.0.0.1',()=>console.log('Ship inspection: http://127.0.0.1:4177/tools/ship-models/preview.html'));
