import {identity,nifMatrix,multiplyMatrix,transformVector,sampleKeys,controllerTime,textureUV,billboardMode0} from './native-semantics.mjs';
export const SOURCE_BASE='../../naval-study/atmosphere-fx/source-study/';
export const sourceURL=name=>SOURCE_BASE+'assets-json/'+name+'.json';
export async function loadAsset(name){const r=await fetch(sourceURL(name));if(!r.ok)throw Error('Original NIF export unavailable: '+name);return r.json();}
const vec=v=>[v.x,v.y,v.z];
export function composeTransform(parent,local){
  const moved=transformVector(parent.rotation,local.translation.map(x=>x*parent.scale));
  return {rotation:multiplyMatrix(parent.rotation,local.rotation),translation:moved.map((x,i)=>Math.fround(x+parent.translation[i])),scale:Math.fround(parent.scale*local.scale)};
}
export function staticTransform(fields){return {rotation:fields.rotation?nifMatrix(fields.rotation):identity(),translation:fields.translation?vec(fields.translation):[0,0,0],scale:fields.scale??1};}
export function originalMeshes(asset,time=0,outer={rotation:identity(),translation:[0,0,0],scale:1},{animate=false,camera}={}){
  const blocks=new Map(asset.blocks.map(b=>[b.id,b])),meshes=[];
  const ref=x=>x?blocks.get(x.ref):null;
  const controllers=block=>{const list=[];let c=ref(block.fields.controller);while(c){list.push(c);c=ref(c.fields.next_controller);}return list;};
  function visit(block,parent,properties){
    let local=staticTransform(block.fields);
    if(animate)for(const c of controllers(block))if(c.type==='NiKeyframeController'){
      const data=ref(c.fields.data)?.fields,t=controllerTime(c.fields,time);
      if(data.translations?.keys.length)local.translation=sampleKeys(data.translations,t);
      if(data.scales?.keys.length)local.scale=sampleKeys(data.scales,t);
      if(data.quaternion_keys?.length)throw Error('unresolved NIF rotation animation');
    }
    let world=composeTransform(parent,local);const props=new Map(properties);
    if(block.type==='NiBillboardNode'&&camera){if(block.fields.billboard_mode!==0)throw Error('unresolved original billboard mode '+block.fields.billboard_mode);world={...world,rotation:billboardMode0(world.rotation,camera)};}
    for(const p of block.fields.properties||[]){const property=ref(p);props.set(property.type,property);}
    if(['NiTriStrips','NiTriShape'].includes(block.type)){
      const data=ref(block.fields.data),mat=props.get('NiMaterialProperty'),texturing=props.get('NiTexturingProperty'),desc=texturing?.fields.base_texture,texture=ref(desc?.source)?.fields.file_name.toLowerCase();
      let alpha=mat?.fields.alpha??1,uvValues={};
      if(animate&&mat)for(const c of controllers(mat))if(c.type==='NiAlphaController')alpha=sampleKeys(ref(c.fields.data).fields.data,controllerTime(c.fields,time));
      if(animate&&texturing)for(const c of controllers(texturing))if(c.type==='NiTextureTransformController'){
        if(c.fields.texture_slot!==0)throw Error('unresolved non-base texture controller');
        uvValues[c.fields.operation]=sampleKeys(ref(c.fields.data).fields.data,controllerTime(c.fields,time));
      }
      const vertices=data.fields.vertices.map(v=>transformVector(world.rotation,vec(v).map(x=>x*world.scale)).map((x,i)=>Math.fround(x+world.translation[i])));
      const uvs=(data.fields.uv_sets[desc?.uv_set??0]||[]).map(v=>textureUV([v.u,v.v],desc,uvValues));
      meshes.push({asset:asset.name,block:block.id,name:block.name,texture,vertices,uvs,triangles:data.effective_triangles,alpha,color:mat?[mat.fields.diffuse_color.r,mat.fields.diffuse_color.g,mat.fields.diffuse_color.b]:[1,1,1],alphaFlags:props.get('NiAlphaProperty')?.fields.flags??0,threshold:props.get('NiAlphaProperty')?.fields.threshold??0,clampMode:desc?.clamp_mode,filterMode:desc?.filter_mode,billboardStatic:!camera&&asset.blocks.some(b=>b.type==='NiBillboardNode'),world});
    }
    for(const c of block.fields.children||[])visit(ref(c),world,props);
  }
  for(const root of asset.roots)visit(blocks.get(root),outer,new Map());
  return meshes;
}
