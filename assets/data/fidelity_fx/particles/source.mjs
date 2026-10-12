import {MeshViewer} from '../atmosphere/viewer.mjs';
import {parseDDS,uploadDDS} from '../water/dds.mjs';
export async function loadParticleAsset(name){const response=await fetch(new URL('./assets-json/'+name+'.json',import.meta.url));if(!response.ok)throw Error('Original particle asset HTTP '+response.status);return response.json();}
export class OriginalParticleViewer extends MeshViewer{
 async loadTextures(meshes){
  const provenance=await fetch(new URL('./source-provenance.json',import.meta.url)).then(r=>{if(!r.ok)throw Error('Original texture source map HTTP '+r.status);return r.json();});
  const paths=new Map(provenance.textures.map(t=>[t.name,t.raw]));
  for(const mesh of meshes){
   const key=`${mesh.texture}:${mesh.clampMode}:${mesh.filterMode}`;if(this.textures.has(key))continue;
   const raw=paths.get(mesh.texture);if(!raw)throw Error('Missing original DDS source '+mesh.texture);
   const response=await fetch(new URL('../../'+raw,import.meta.url));if(!response.ok)throw Error('Original DDS HTTP '+response.status);
   const dds=parseDDS(await response.arrayBuffer()),texture=uploadDDS(this.gl,dds,{clampMode:mesh.clampMode,filterMode:mesh.filterMode});
   this.textures.set(key,{texture,mipCount:dds.levels.length,raw,clampMode:mesh.clampMode,filterMode:mesh.filterMode});
  }
 }
 render(meshes,{camera,center,span}){
  const gl=this.gl,c=this.canvas;c.width=Math.round(c.clientWidth);c.height=Math.round(c.clientHeight);gl.viewport(0,0,c.width,c.height);gl.clearColor(.055,.075,.09,1);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);gl.disable(gl.DEPTH_TEST);gl.disable(gl.CULL_FACE);gl.useProgram(this.program);gl.bindVertexArray(this.vertexArray);
  for(const [key,v] of Object.entries({right:camera.right,up:camera.up,forward:camera.direction,center}))gl.uniform3fv(gl.getUniformLocation(this.program,key),v);
  gl.uniform2f(gl.getUniformLocation(this.program,'halfSpan'),span*c.width/c.height,span);gl.uniform1i(gl.getUniformLocation(this.program,'originalTexture'),0);let draws=0,triangles=0;
  const ordered=[...meshes].sort((a,b)=>b.world.translation.reduce((n,x,i)=>n+x*camera.direction[i],0)-a.world.translation.reduce((n,x,i)=>n+x*camera.direction[i],0));
  for(const mesh of ordered){
   const original=this.textures.get(`${mesh.texture}:${mesh.clampMode}:${mesh.filterMode}`);if(!original)throw Error('Original texture/sampler missing');
   const data=[];for(const tri of mesh.triangles)for(const i of tri)data.push(...mesh.vertices[i],...mesh.uvs[i]);gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array(data),gl.DYNAMIC_DRAW);gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_2D,original.texture);
   if(mesh.alphaFlags&1){const source=(mesh.alphaFlags>>1)&15,destination=(mesh.alphaFlags>>5)&15;if(source!==6||![0,7].includes(destination))throw Error(`Unported original blend ${source}/${destination}`);gl.enable(gl.BLEND);gl.blendFunc(gl.SRC_ALPHA,destination===0?gl.ONE:gl.ONE_MINUS_SRC_ALPHA);}else gl.disable(gl.BLEND);
   gl.uniform4fv(gl.getUniformLocation(this.program,'material'),[...mesh.color,mesh.alpha]);const testEnabled=(mesh.alphaFlags&512)!==0,test=(mesh.alphaFlags>>10)&7;if(testEnabled&&test!==4)throw Error('Unported original alpha comparison '+test);gl.uniform1f(gl.getUniformLocation(this.program,'threshold'),testEnabled?mesh.threshold/255:-1);gl.drawArrays(gl.TRIANGLES,0,data.length/5);draws++;triangles+=mesh.triangles.length;
  }
  const error=gl.getError();if(error)this.errors.push(error);this.stats={draws,triangles,width:c.width,height:c.height,glErrors:[...this.errors]};return this.stats;
 }
}
