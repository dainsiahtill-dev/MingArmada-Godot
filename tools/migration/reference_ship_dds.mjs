// Read the original DDS blocks and mip chain directly; no painted/rebuilt texture.
export function parseDDS(buffer){
 const d=new DataView(buffer);if(d.getUint32(0,true)!==0x20534444||d.getUint32(4,true)!==124)throw Error('invalid original DDS');
 const height=d.getUint32(12,true),width=d.getUint32(16,true),mipCount=Math.max(1,d.getUint32(28,true)),fourcc=String.fromCharCode(...new Uint8Array(buffer,84,4));
 if(!['DXT1','DXT3','DXT5'].includes(fourcc))throw Error('unclosed original DDS format '+fourcc);
 const blockBytes=fourcc==='DXT1'?8:16,levels=[];let offset=128,w=width,h=height;
 for(let i=0;i<mipCount;i++){
  const bytes=Math.max(1,Math.ceil(w/4))*Math.max(1,Math.ceil(h/4))*blockBytes;
  if(offset+bytes>buffer.byteLength)throw Error('truncated original DDS mip '+i);
  levels.push({width:w,height:h,bytes:new Uint8Array(buffer,offset,bytes)});offset+=bytes;w=Math.max(1,w>>1);h=Math.max(1,h>>1);
 }
 if(offset!==buffer.byteLength)throw Error('unconsumed original DDS bytes');
 return {width,height,mipCount,fourcc,levels,wholeFileConsumed:true};
}
const rgb565=v=>[(v>>11)*255/31,((v>>5)&63)*255/63,(v&31)*255/31];
export function decodeDDSLevel(dds,level=0){
 const m=dds.levels[level],out=new Uint8Array(m.width*m.height*4),d=new DataView(m.bytes.buffer,m.bytes.byteOffset,m.bytes.byteLength),step=dds.fourcc==='DXT1'?8:16;
 let offset=0;
 for(let by=0;by<Math.ceil(m.height/4);by++)for(let bx=0;bx<Math.ceil(m.width/4);bx++,offset+=step){
  const colorOffset=offset+(step===8?0:8),c0=d.getUint16(colorOffset,true),c1=d.getUint16(colorOffset+2,true),colors=[rgb565(c0),rgb565(c1)];
  const four=dds.fourcc!=='DXT1'||c0>c1;
  colors.push(colors[0].map((v,i)=>four?(2*v+colors[1][i])/3:(v+colors[1][i])/2));colors.push(four?colors[0].map((v,i)=>(v+2*colors[1][i])/3):[0,0,0]);
  const colorBits=d.getUint32(colorOffset+4,true),alpha=[];
  if(dds.fourcc==='DXT5'){
   const a0=d.getUint8(offset),a1=d.getUint8(offset+1);alpha.push(a0,a1);
   if(a0>a1)for(let i=1;i<=6;i++)alpha.push(((7-i)*a0+i*a1)/7);
   else {for(let i=1;i<=4;i++)alpha.push(((5-i)*a0+i*a1)/5);alpha.push(0,255);}
  }
  let alphaBits=0n;if(dds.fourcc==='DXT5')for(let j=0;j<6;j++)alphaBits|=BigInt(d.getUint8(offset+2+j))<<BigInt(8*j);
  for(let p=0;p<16;p++){
   const x=bx*4+(p&3),y=by*4+(p>>2);if(x>=m.width||y>=m.height)continue;
   const ci=(colorBits>>>(2*p))&3,index=4*(y*m.width+x);
   for(let c=0;c<3;c++)out[index+c]=Math.round(colors[ci][c]);
   out[index+3]=dds.fourcc==='DXT1'?(!four&&ci===3?0:255):dds.fourcc==='DXT3'?((d.getUint8(offset+(p>>1))>>((p&1)*4))&15)*17:Math.round(alpha[Number((alphaBits>>BigInt(p*3))&7n)]);
  }
 }
 return out;
}
export function uploadDDS(gl,dds){
 const ext=gl.getExtension('WEBGL_compressed_texture_s3tc'),texture=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,texture);
 const format=ext?.[{'DXT1':'COMPRESSED_RGBA_S3TC_DXT1_EXT','DXT3':'COMPRESSED_RGBA_S3TC_DXT3_EXT','DXT5':'COMPRESSED_RGBA_S3TC_DXT5_EXT'}[dds.fourcc]];
 for(let i=0;i<dds.levels.length;i++){const m=dds.levels[i];if(format)gl.compressedTexImage2D(gl.TEXTURE_2D,i,format,m.width,m.height,0,m.bytes);else gl.texImage2D(gl.TEXTURE_2D,i,gl.RGBA,m.width,m.height,0,gl.RGBA,gl.UNSIGNED_BYTE,decodeDDSLevel(dds,i));}
 gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_BASE_LEVEL,0);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAX_LEVEL,dds.levels.length-1);
 gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,dds.mipCount>1?gl.LINEAR_MIPMAP_LINEAR:gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
 return {texture,dds,nativeCompressedUpload:Boolean(format)};
}
