import fs from 'node:fs';
import assert from 'node:assert/strict';
const manifest=JSON.parse(fs.readFileSync('assets/data/fidelity_naval/ships-manifest.json'));
let triangles=0,vertices=0,meshes=0;
for(const entry of Object.values(manifest.mappings)){
  const source=JSON.parse(fs.readFileSync(entry.sourceJsonPath.replace('res://','')));
  const originals={hull:JSON.parse(fs.readFileSync(`Temp/reference-ships-import/${entry.family}-lowend.json`)),battle:JSON.parse(fs.readFileSync(`Temp/reference-ships-import/${entry.family}-battle.json`))};
  for(const part of ['hull','battle'])assert.equal(originals[part].source.sha256,source.sources.find(item=>item.raw===originals[part].source.raw).sha256);
  for(const mesh of source.meshes){
    const native=originals[mesh.sourcePart].meshes.find(item=>item.node_id===mesh.sourceId);
    const vertexIds=mesh.sourceVertexIndices??native.vertices.map((_,i)=>i);
    const triangleIds=mesh.sourceTriangleIndices??native.triangles.map((_,i)=>i);
    for(let i=0;i<vertexIds.length;i++){
      assert.deepEqual(mesh.sourceVertices[i],native.vertices[vertexIds[i]]);
      for(let uv=0;uv<mesh.uvSets.length;uv++)assert.deepEqual(mesh.uvSets[uv][i],native.uv_sets[uv][vertexIds[i]]);
    }
    for(let i=0;i<triangleIds.length;i++)assert.deepEqual(mesh.triangles[i].map(vertex=>vertexIds[vertex]),native.triangles[triangleIds[i]]);
    triangles+=triangleIds.length;vertices+=vertexIds.length;meshes++;
  }
}
console.log(JSON.stringify({nativeSourceComparison:'pass',meshes,triangles,vertices,scope:'All generated subsets checked against unchanged original NIF-loader export, including exact original triangle and vertex indices plus UV streams.'}));
