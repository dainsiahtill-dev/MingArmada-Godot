// Recovered native mathematical semantics. Evidence under native/.
// JS double arithmetic approximates x87 intermediates; original float stores use fround.
import {ControllerClock,textureTransform} from '../shore/native-math.mjs';
export const CONSTANTS=Object.freeze({deg2rad:0.01745329238474369,cloudThreshold:0.03333333507180214,nameScale:0.0010000000474974513,sizeFloor:9.999999747378752e-5,gravityScale:1.600000023841858,fogPhaseScale:0.05000000074505806});
const f=Math.fround;
export class OriginalCrtRand{
  // Actual shipped MSVCR71.dll 0x7C366BE9; checked against isolated native DLL execution.
  // This state is supplied explicitly. It is not the unknown live game's thread state.
  constructor(state){this.seed(state);}
  seed(state){if(!Number.isInteger(state)||state<0||state>0xffffffff)throw Error('explicit uint32 original CRT state required');this.state=state;this.draws=0;}
  next(){this.state=(Math.imul(this.state,0x343fd)+0x269ec3)>>>0;this.draws++;return (this.state>>>16)&0x7fff;}
}
export const identity=()=>[1,0,0,0,1,0,0,0,1];
// Native storage rows. NiMatrix33 serial order is m11,m21,m31,m12,... .
export const nifMatrix=r=>[r.m_11,r.m_21,r.m_31,r.m_12,r.m_22,r.m_32,r.m_13,r.m_23,r.m_33];
export function rotationZ(angle){const c=f(Math.cos(angle)),s=f(Math.sin(angle));return [c,s,0,-s,c,0,0,0,1];}
export function rotationX(angle){const c=f(Math.cos(angle)),s=f(Math.sin(angle));return [1,0,0,0,c,s,0,-s,c];}
export function multiplyMatrix(a,b){return Array.from({length:9},(_,i)=>{const r=Math.floor(i/3),c=i%3;return f(a[r*3]*b[c]+a[r*3+1]*b[3+c]+a[r*3+2]*b[6+c]);});}
export function transformVector(matrix,v){return [0,1,2].map(r=>f(matrix[r*3]*v[0]+matrix[r*3+1]*v[1]+matrix[r*3+2]*v[2]));}
export function transformTranspose(matrix,v){return [0,1,2].map(c=>f(matrix[6+c]*v[2]+matrix[3+c]*v[1]+matrix[c]*v[0]));}
export function billboardMode0(worldRotation,camera){
  // 0x546230 case0; 0x534A20 maps camera world columns to direction/up/right.
  if(!camera?.direction||!camera.up||!camera.right)throw Error('explicit camera direction/up/right required');
  const d=transformTranspose(worldRotation,camera.direction.map(x=>f(-x))),u=transformTranspose(worldRotation,camera.up),r=transformTranspose(worldRotation,camera.right);
  const length=Math.sqrt(u[1]*u[1]+r[1]*r[1]),adjust=identity();
  adjust[2]=d[0];adjust[5]=d[1];adjust[8]=d[2];
  if(length<=9.999999974752427e-7){
    adjust[0]=f(-r[0]);adjust[3]=f(-r[1]);adjust[6]=f(-r[2]);
    adjust[1]=f(-u[0]);adjust[4]=f(-u[1]);adjust[7]=f(-u[2]);
  }else{
    const v18=u[1]/length,v19=-r[1]/length;
    for(let i=0;i<3;i++){adjust[i*3]=f(u[i]*v19+r[i]*v18);adjust[i*3+1]=f(u[i]*v18-r[i]*v19);}
  }
  return multiplyMatrix(worldRotation,adjust);
}
export function createCloudRing(rand){
  if(typeof rand!=='function')throw Error('0x4D8060 requires explicit original rand() input; original seed is unresolved');
  const next=()=>{const n=rand();if(!Number.isInteger(n)||n<0||n>32767)throw Error('rand() must supply original CRT nonnegative 15-bit value');return n;};
  const nodes=[];let angle=0;
  do{
    const name=String(-(next()%1500)).padStart(5,' '),index=next()%5,tilt=-(next()%10);
    nodes.push({name,prototype:`domecloud${index+1}.nif`,azimuthDegrees:angle,tiltDegrees:tilt,translation:[0,1,0],scale:1,rotation:multiplyMatrix(rotationZ(f(angle*CONSTANTS.deg2rad)),rotationX(f(tilt*CONSTANTS.deg2rad)))});
    angle+=next()%5+10;
  }while(angle<360);
  return {nodes,accumulator:0,updates:0};
}
export function advanceClouds(state,delta){
  delta=f(delta);const accumulated=state.accumulator+delta;
  state.accumulator=f(accumulated);
  // 0x4D8300 fcom/test ah,41h: strictly greater; one subtraction, no catch-up loop.
  if(accumulated>CONSTANTS.cloudThreshold){
    state.accumulator=f(accumulated-CONSTANTS.cloudThreshold);
    for(const node of state.nodes){const angle=f(Number.parseFloat(node.name)*CONSTANTS.nameScale*delta*CONSTANTS.deg2rad);node.rotation=multiplyMatrix(rotationZ(angle),node.rotation);}
    state.updates++;
  }
  return state;
}
export function growFade(modifier,particle){
  let grow=1,fade=1;
  if(particle.generation===modifier.grow_generation&&particle.age<modifier.grow_time)grow=particle.age/modifier.grow_time;
  const remaining=f(particle.life-particle.age);
  if(particle.generation===modifier.fade_generation&&remaining<modifier.fade_time)fade=remaining/modifier.fade_time;
  return f(Math.max(CONSTANTS.sizeFloor,Math.min(grow,fade)));
}
export function sphereGravity(modifier,particle,{origin,now}){
  if(modifier.force_type!==1||modifier.turbulence!==0)throw Error('unresolved gravity branch: only original force_type=1, turbulence=0 is enabled');
  if(!origin||origin.length!==3)throw Error('gravity origin must already be transformed into particle-system coordinates');
  const dx=f(origin[0])-f(particle.position[0]),dy=f(origin[1])-f(particle.position[1]),dz=f(origin[2])-f(particle.position[2]);
  // 5B4AAC stores Z before sqrt, then 5B4AED stores normalized Z; X/Y stay x87.
  const storedZ=f(dz),length=Math.sqrt(dz*storedZ+dy*dy+dx*dx),inverse=length?1/length:1;
  const nx=dx*inverse,ny=dy*inverse,nz=f(storedZ*inverse);
  const decay=f(modifier.decay===0?1:Math.exp(-length*f(modifier.decay))),strength=f(modifier.strength),dt=f(f(now)-f(particle.lastUpdate));
  // X, Y, Z have different original fstp sites. Do not collapse them into one vector expression.
  const xScaled=f(f(nx*decay)*strength)*CONSTANTS.gravityScale;
  const yScaled=f(f(ny*decay*strength)*CONSTANTS.gravityScale);
  const zScaled=f(strength*(nz*decay)*CONSTANTS.gravityScale);
  const delta=[f(xScaled*dt),f(yScaled*dt),f(f(zScaled+0)*dt)];
  return {...particle,velocity:particle.velocity.map((x,i)=>f(delta[i]+f(x)))};
}
export function positionUpdate(particle,now){
  now=f(now);const dt=now-particle.lastUpdate;
  return {...particle,position:particle.position.map((x,i)=>f(x+dt*particle.velocity[i])),lastUpdate:now};
}
export const linear=(t,a,b)=>f((1-t)*a+t*b);
export function cubic(t,p0,outgoing,p1,incoming){
  // 0x57F750 tangents are stored interval coefficients; no invented dt multiplication.
  return f((((outgoing+incoming-2*(p1-p0))*t+3*(p1-p0)-(2*outgoing+incoming))*t+outgoing)*t+p0);
}
const valueArray=value=>typeof value==='number'?value:value.x!==undefined?[value.x,value.y,value.z]:value.r!==undefined?[value.r,value.g,value.b,value.a]:null;
export function sampleKeys(group,time){
  time=f(time);
  const keys=group.keys;if(!keys?.length)throw Error('empty key group requires original fallback value');
  if(![1,2].includes(group.interpolation))throw Error('unresolved interpolation '+group.interpolation);
  const first=valueArray(keys[0].value),last=valueArray(keys.at(-1).value);
  if(time<=keys[0].time)return first;if(time>=keys.at(-1).time)return last;
  let i=0;while(i+1<keys.length&&time>keys[i+1].time)i++;
  const a=keys[i],b=keys[i+1],t=f((f(time)-a.time)/(b.time-a.time)),av=valueArray(a.value),bv=valueArray(b.value);
  if(group.interpolation===2){
    if(typeof av!=='number')throw Error('unresolved non-scalar cubic keys');
    return cubic(t,av,a.backward,bv,b.forward);
  }
  if(typeof av==='number')return linear(t,av,bv);
  // Native vector/color routines fstore products before adding components.
  return av.map((x,j)=>f(f((1-t)*x)+f(t*bv[j])));
}
export function particleColor(group,particle){
  const t=Math.max(group.keys[0].time,Math.min(group.keys.at(-1).time,f(particle.age/particle.life)));
  return sampleKeys(group,t).map(x=>Math.max(0,Math.min(1,x)));
}
export function visibilityAt(keys,time){
  if(!keys.length)throw Error('empty visibility: unresolved fallback');let i=0;
  while(i+1<keys.length&&time>=keys[i+1].time)i++;
  return Boolean(keys[i].value);
}
export function controllerTime(fields,input){
  // Diagnostic seek from explicit epoch0, using shared original 0x54FFE0 state semantics.
  // Full ongoing engine scheduling must retain a ControllerClock instance per native controller.
  if(!(fields.flags&8))throw Error('inactive original controller');
  const clock=new ControllerClock(fields);if(fields.flags&1)clock.advance(0);return clock.advance(input);
}
export function textureUV(uv,desc,values={}){
  if(!desc.has_texture_transform)return uv;
  const M=textureTransform(desc,{translationU:values[0],translationV:values[1],rotation:values[2],scaleU:values[3],scaleV:values[4]});
  return [f(M[0]*uv[0]+M[3]*uv[1]+M[6]),f(M[1]*uv[0]+M[4]*uv[1]+M[7])];
}
export function generateParticles(){throw Error('unresolved original birth scheduling, modifier world transforms and native scheduler; particle generation disabled');}
export function sampleBoxBirth(emitter,{now,age,emitterTransform},rand){
  // 0x5AD110 followed by 0x5BA2B0/0x5B7980. Caller supplies exact relative NiTransform and rand stream.
  if(typeof rand!=='function')throw Error('original rand input required');
  const next=()=>{const n=rand();if(!Number.isInteger(n)||n<0||n>32767)throw Error('invalid original rand value');return n;};
  const norm=3.0518509447574615e-5,symmetric=6.103701889514923e-5;
  const speed=f((next()*norm-.5)*emitter.speed_variation+emitter.speed);
  const declination=f((next()*symmetric-1)*emitter.declination_variation+emitter.declination);
  const planar=(next()*symmetric-1)*emitter.planar_angle_variation+emitter.planar_angle;
  const x=f(Math.cos(planar)*Math.sin(declination));
  const localVelocity=[f(x*speed),f(Math.sin(declination)*Math.sin(planar)*speed),f(Math.cos(declination)*speed)];
  const life=f((next()*norm-.5)*emitter.life_span_variation+emitter.life_span);
  const y=f(next()*norm),xx=f(next()*norm),z=next()*norm;
  const localPosition=[f((xx-.5)*emitter.width),f((y-.5)*emitter.height),f((z-.5)*emitter.depth)];
  const transformed=transformVector(emitterTransform.rotation,localPosition);
  const position=transformed.map((v,i)=>f(f(v*emitterTransform.scale)+emitterTransform.translation[i]));
  return {position,velocity:transformVector(emitterTransform.rotation,localVelocity),age:f(age),life,lastUpdate:f(f(now)-f(age)),generation:0,radius:emitter.initial_radius,size:1,color:[emitter.initial_color.r,emitter.initial_color.g,emitter.initial_color.b,emitter.initial_color.a]};
}
