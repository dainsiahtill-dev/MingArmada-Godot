import fs from 'node:fs';
const manifest=JSON.parse(fs.readFileSync('assets/data/fidelity_naval/ships-manifest.json'));
for(const entry of Object.values(manifest.mappings)){
  const source=JSON.parse(fs.readFileSync(`Temp/reference-ships-import/${entry.family}-lowend.json`));
  for(const mesh of source.meshes.filter(x=>entry.family==='barque'?x.node_id===50:/ship_shrouds/i.test(x.texture.slots?.base?.texture||''))){
    const parent=mesh.vertices.map((_,i)=>i),find=i=>parent[i]===i?i:parent[i]=find(parent[i]);
    const weld=new Map();
    mesh.worldVertices.forEach((v,i)=>{const key=v.map(x=>Math.round(x*1000)).join(',');if(weld.has(key))parent[find(i)]=find(weld.get(key));else weld.set(key,i);});
    for(const [a,b,c]of mesh.triangles){parent[find(a)]=find(b);parent[find(c)]=find(b);}
    const components=new Map();
    mesh.triangles.forEach((t,i)=>{const key=find(t[0]);if(!components.has(key))components.set(key,[]);components.get(key).push(i);});
    const report=[...components.values()].map(tris=>{const ids=[...new Set(tris.flatMap(i=>mesh.triangles[i]))],vs=ids.map(i=>mesh.worldVertices[i]).map(v=>[v[0],v[2],-v[1]].map(x=>x*entry.uniformScale));const min=[0,1,2].map(a=>Math.min(...vs.map(v=>v[a]))),max=[0,1,2].map(a=>Math.max(...vs.map(v=>v[a])));return{t:tris.length,v:ids.length,min:min.map(x=>+x.toFixed(2)),max:max.map(x=>+x.toFixed(2)),high:vs.sort((a,b)=>b[1]-a[1])[0].map(x=>+x.toFixed(2))};}).sort((a,b)=>b.t-a.t);
    console.log(JSON.stringify({family:entry.family,id:mesh.node_id,texture:mesh.texture.slots.base.texture,components:report}));
  }
}
