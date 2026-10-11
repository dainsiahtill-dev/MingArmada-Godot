import * as THREE from 'three';
import {mergeGeometries} from 'three/addons/utils/BufferGeometryUtils.js';

/** Original late-Ming deck worker. Metres, feet y=0, facing +Z; no copied assets. */
export const SAILOR_VARIANTS=Object.freeze({
  indigo:{cloth:0x4b6266,lining:0x9a8e71,pants:0x514b42,headcloth:0x79715d,skin:0xad7f58},
  ochre:{cloth:0x967147,lining:0xb7aa85,pants:0x485552,headcloth:0x585c53,skin:0xb78761},
  umber:{cloth:0x715747,lining:0xa89a77,pants:0x585a52,headcloth:0x877b63,skin:0x9b6c4c},
});
export const SAILOR_CLIPS=Object.freeze(['idle','helm','haul','load-cannon','walk','lookout']);

function rig() {
  const bones=[],indices={},world={};
  function bone(name,parent,position) {
    const b=new THREE.Bone();b.name=`sailor_${name}`;
    const p=new THREE.Vector3(...position);world[name]=p;
    b.position.copy(parent?p.clone().sub(world[parent]):p);
    if(parent)bones[indices[parent]].add(b);
    indices[name]=bones.length;bones.push(b);return b;
  }
  bone('root',null,[0,0,0]);bone('hips','root',[0,.87,0]);
  bone('spine','hips',[0,1.05,0]);bone('chest','spine',[0,1.27,0]);
  bone('neck','chest',[0,1.425,0]);bone('head','neck',[0,1.49,0]);
  for(const [side,sign] of [['L',1],['R',-1]]) {
    bone(`arm_${side}`,'chest',[sign*.205,1.355,0]);
    bone(`elbow_${side}`,`arm_${side}`,[sign*.265,1.115,0]);
    bone(`wrist_${side}`,`elbow_${side}`,[sign*.3,.895,.015]);
    bone(`thigh_${side}`,'hips',[sign*.115,.86,0]);
    bone(`knee_${side}`,`thigh_${side}`,[sign*.13,.455,0]);
    bone(`ankle_${side}`,`knee_${side}`,[sign*.13,.095,0]);
  }
  return {bones,indices};
}

/** Closed elliptical cloth loft. Rings supply [y, radiusX, radiusZ, centreX, centreZ]. */
function loft(rings,sides,fold=0) {
  const p=[],index=[];
  for(let r=0;r<rings.length;r++) {
    const [y,rx,rz,x=0,z=0]=rings[r];
    for(let n=0;n<sides;n++) {
      const a=n/sides*Math.PI*2,wear=1+fold*Math.sin(a*5+r*.7);
      p.push(x+Math.cos(a)*rx*wear,y,z+Math.sin(a)*rz*wear);
    }
  }
  for(let r=0;r<rings.length-1;r++)for(let n=0;n<sides;n++) {
    const a=r*sides+n,b=r*sides+(n+1)%sides,c=(r+1)*sides+n,d=(r+1)*sides+(n+1)%sides;
    index.push(a,c,b,b,c,d);
  }
  for(const [r,reverse] of [[0,true],[rings.length-1,false]]) {
    const [y,,,x=0,z=0]=rings[r],c=p.length/3;p.push(x,y,z);
    for(let n=0;n<sides;n++) {
      const a=r*sides+n,b=r*sides+(n+1)%sides;index.push(...(reverse?[c,a,b]:[c,b,a]));
    }
  }
  const g=new THREE.BufferGeometry();g.setAttribute('position',new THREE.Float32BufferAttribute(p,3));g.setIndex(index);g.computeVertexNormals();return g;
}

function ellipsoid(center,scale,sides,rows) {
  const g=new THREE.SphereGeometry(1,sides,rows);g.scale(...scale);g.translate(...center);return g;
}

function ribbon(points,width,depth) {
  // Small closed tapered ribbon for layered collar, headcloth tails and belt ties.
  const p=[],index=[];
  for(let i=0;i<points.length;i++) {
    const [x,y,z]=points[i],w=width*(1-i/(points.length+1)*.38);
    p.push(x-w,y,z-depth/2,x+w,y,z-depth/2,x-w,y,z+depth/2,x+w,y,z+depth/2);
  }
  for(let i=0;i<points.length-1;i++) {
    const a=i*4,b=a+4;index.push(a,b,a+1,a+1,b,b+1,a+2,a+3,b+2,a+3,b+3,b+2,a,a+2,b,a+2,b+2,b,a+1,b+1,a+3,a+3,b+1,b+3);
  }
  const e=(points.length-1)*4;index.push(0,1,2,1,3,2,e,e+2,e+1,e+1,e+2,e+3);
  for(let i=0;i<index.length;i+=3)[index[i+1],index[i+2]]=[index[i+2],index[i+1]];
  const g=new THREE.BufferGeometry();g.setAttribute('position',new THREE.Float32BufferAttribute(p,3));g.setIndex(index);g.computeVertexNormals();return g;
}

function blend(a,b,t) {return [[a,1-t],[b,t]].filter(([,w])=>w>0);}
function smooth(value,lo,hi) {return THREE.MathUtils.smoothstep(value,lo,hi);}

export function createSailor({lod=0,variant='indigo'}={}) {
  if(!Number.isInteger(lod)||lod<0||lod>2)throw new RangeError('LOD must be 0, 1 or 2');
  if(!Object.hasOwn(SAILOR_VARIANTS,variant))throw new RangeError('Unknown sailor variant');
  const palette=SAILOR_VARIANTS[variant],{bones,indices}=rig(),parts=[];
  const sides=[12,8,5][lod],rows=[7,5,3][lod];
  function add(g,color,weights) {
    g.deleteAttribute('uv');
    const p=g.attributes.position,c=[],si=[],sw=[],base=new THREE.Color(color);
    for(let i=0;i<p.count;i++) {
      const x=p.getX(i),y=p.getY(i),z=p.getZ(i);
      // Subtle deterministic vertex fabric wear, matching timber's restrained palette.
      const tone=.94+.06*Math.sin(x*35+y*27+z*19);c.push(base.r*tone,base.g*tone,base.b*tone);
      const pairs=typeof weights==='function'?weights(x,y,z):[[weights,1]];
      for(let j=0;j<4;j++){si.push(j<pairs.length?indices[pairs[j][0]]:0);sw.push(j<pairs.length?pairs[j][1]:0);}
    }
    g.setAttribute('color',new THREE.Float32BufferAttribute(c,3));
    g.setAttribute('skinIndex',new THREE.Uint16BufferAttribute(si,4));
    g.setAttribute('skinWeight',new THREE.Float32BufferAttribute(sw,4));parts.push(g);
  }
  const torsoWeight=(_x,y)=>y<1.13?blend('hips','spine',smooth(y,.94,1.1)):blend('spine','chest',smooth(y,1.16,1.32));
  // Tunic: broad shoulder yoke, tailored waist, flared short split-looking hem.
  add(loft([[.785,.185,.125],[.845,.194,.126],[.96,.157,.115],[1.075,.167,.125],[1.245,.218,.135],[1.355,.226,.12],[1.405,.083,.073]],sides,lod<2?.025:0),palette.cloth,torsoWeight);
  add(loft([[1.398,.071,.064],[1.449,.059,.054]],sides),palette.skin,'neck');
  add(ellipsoid([0,1.548,.008],[.118,.153,.108],sides,rows),palette.skin,'head');
  // Raised nose bridge/rounded chin, ears and dark brows remain readable from close camera.
  add(ellipsoid([0,1.555,.112],[.025,.04,.034],Math.max(5,sides-2),Math.max(3,rows-2)),palette.skin,'head');
  if(lod<2) {
    for(const sign of [-1,1]) {
      add(ellipsoid([sign*.118,1.552,.004],[.022,.038,.022],6,4),palette.skin,'head');
      add(ellipsoid([sign*.044,1.581,.104],[.011,.007,.007],6,3),0x2c2821,'head');
      add(ribbon([[sign*.062,1.599,.102],[sign*.029,1.601,.114]],.004,.003),0x433629,'head');
    }
    add(ellipsoid([0,1.516,.11],[.03,.004,.004],6,3),0x74513e,'head');
  }
  // Tied cloth cap over crown; broad folded band and two restrained rear tails.
  add(ellipsoid([0,1.655,.005],[.124,.051,.112],sides,Math.max(3,rows-1)),palette.headcloth,'head');
  add(loft([[1.617,.122,.111,0,.005],[1.642,.127,.115,0,.005],[1.655,.121,.11,0,.005]],sides),palette.headcloth,'head');
  add(ellipsoid([.087,1.625,-.084],[.031,.032,.026],6,3),palette.headcloth,'head');
  if(lod<2)for(const sign of [-1,1])add(ribbon([[.082,1.625,-.096],[.08+sign*.025,1.566,-.122],[.087+sign*.035,1.501,-.115]],.016,.008),palette.headcloth,'head');
  // Overlapping cross collar/inner placket establishes layered cotton jacket, not armor.
  if(lod<2) {
    add(ribbon([[-.075,1.398,.07],[-.034,1.319,.139],[.051,1.205,.137],[.058,1.073,.13]],.018,.008),palette.lining,torsoWeight);
    add(ribbon([[.075,1.398,.07],[.035,1.322,.139],[-.037,1.231,.137]],.014,.008),palette.lining,torsoWeight);
    for(const x of [-.086,.078])add(ribbon([[x,.959,.115],[x*1.3,.838,.127],[x*1.3,.792,.125]],.006,.004),palette.lining,torsoWeight);
  }
  add(loft([[.941,.167,.123],[.981,.164,.124],[.995,.162,.122]],sides),0x66533b,torsoWeight);
  add(ellipsoid([.08,.967,.123],[.037,.026,.018],6,3),0x776344,'hips');
  if(lod<2)add(ribbon([[.085,.958,.138],[.095,.881,.145],[.124,.819,.147]],.021,.009),0x776344,'hips');

  for(const [side,sign] of [['L',1],['R',-1]]) {
    const arm=`arm_${side}`,elbow=`elbow_${side}`,wrist=`wrist_${side}`;
    const armWeight=(_x,y)=>blend(arm,elbow,1-smooth(y,1.08,1.16));
    const sleeve=[[.955,.057,.055,sign*.295,.008],[1.055,.066,.062,sign*.28,0],[1.115,.072,.066,sign*.265,0],[1.21,.081,.074,sign*.24,0],[1.33,.088,.077,sign*.212,0],[1.377,.073,.068,sign*.207,0]];
    add(loft(sleeve,sides,lod<2?.025:0),palette.cloth,armWeight);
    add(loft([[.947,.061,.058,sign*.295,.009],[.977,.063,.059,sign*.291,.007]],sides),palette.lining,elbow);
    add(loft([[.879,.038,.034,sign*.302,.014],[.952,.043,.038,sign*.295,.009]],sides),palette.skin,(_x,y)=>blend(wrist,elbow,smooth(y,.895,.945)));
    add(ellipsoid([sign*.305,.852,.021],[.043,.055,.029],sides,Math.max(3,rows-2)),palette.skin,wrist);
    if(lod===0) {
      add(ellipsoid([sign*.273,.856,.046],[.019,.034,.018],6,4),palette.skin,wrist);
      for(let f=0;f<3;f++)add(ellipsoid([sign*(.287+f*.018),.811,.023],[.012,.018,.02],5,3),palette.skin,wrist);
    }
    const thigh=`thigh_${side}`,knee=`knee_${side}`,ankle=`ankle_${side}`;
    const legWeight=(_x,y)=>y>.31?blend(thigh,knee,1-smooth(y,.405,.505)):blend(knee,ankle,1-smooth(y,.12,.22));
    add(loft([[.131,.056,.059,sign*.13,0],[.285,.067,.065,sign*.13,0],[.455,.083,.078,sign*.13,0],[.60,.095,.092,sign*.125,0],[.78,.111,.104,sign*.115,0],[.867,.108,.108,sign*.115,0]],sides,lod<2?.025:0),palette.pants,legWeight);
    // Cloth gaiters, winding stripes in near model; compact traditional cloth shoes.
    add(loft([[.12,.058,.06,sign*.13,0],[.26,.066,.065,sign*.13,0]],sides),palette.lining,legWeight);
    if(lod===0)for(let n=0;n<3;n++)add(loft([[.139+n*.036,.06+n*.002,.063,sign*.13,0],[.149+n*.036,.061+n*.002,.064,sign*.13,0]],sides),0x8f876d,legWeight);
    add(ellipsoid([sign*.13,.054,.044],[.065,.054,.132],sides,Math.max(3,rows-2)),0x423b30,ankle);
    add(loft([[0,.059,.116,sign*.13,.044],[.012,.065,.123,sign*.13,.044]],sides),0x61523c,ankle);
  }
  const geometry=mergeGeometries(parts);parts.forEach(g=>g.dispose());
  geometry.computeBoundingBox();geometry.computeBoundingSphere();
  const material=new THREE.MeshStandardMaterial({vertexColors:true,roughness:.91,metalness:0});material.name='sailor_worn_cotton';
  const mesh=new THREE.SkinnedMesh(geometry,material);mesh.name='sailor_body';mesh.add(bones[0]);mesh.bind(new THREE.Skeleton(bones));
  const root=new THREE.Group();root.name='late_ming_sailor';root.add(mesh);
  root.userData={units:'metres',lod,variant,forward:'+Z',feetOrigin:0,originalAsset:true};
  root.animations=createSailorAnimations();root.updateMatrixWorld(true);return root;
}

/** Hand-authored joint poses; in-place clips. Deck movement belongs to renderer. */
export function createSailorAnimations() {
  const durations={idle:4,helm:3,haul:2.4,'load-cannon':3.2,walk:1.15,lookout:5};
  function poses(name,t) {
    const s=Math.sin(t*Math.PI*2),c=Math.cos(t*Math.PI*2),p={};
    const put=(bone,x=0,y=0,z=0)=>{p[bone]=[x,y,z];};
    put('spine',.015*s,0,.012*c);put('chest',.012*c);put('head',0,.06*s);
    put('arm_L',-.07+.025*s,0,.06);put('arm_R',-.07-.025*s,0,-.06);
    put('elbow_L',-.13);put('elbow_R',-.13);
    if(name==='helm') {
      put('chest',.02,.09*s);put('arm_L',-1.12+.10*s,0,.10);put('arm_R',-1.12-.10*s,0,-.10);
      put('elbow_L',-.45-.10*s);put('elbow_R',-.45+.10*s);put('wrist_L',0,0,-.15);put('wrist_R',0,0,.15);
    } else if(name==='haul') {
      put('spine',.055-.09*c);put('arm_L',-1.05-.35*c,0,.12);put('arm_R',-1.05-.35*c,0,-.12);
      put('elbow_L',-.45+.35*c);put('elbow_R',-.45+.35*c);put('head',.10,0,.025*s);
    } else if(name==='load-cannon') {
      // Knees flex while hips rotate back; torso bows and both hands reach rammer height.
      const work=.5+.5*c;
      const h=-.10-.13*work,thigh=-.28-.15*work,knee=.55+.2*work;
      put('hips',h);put('thigh_L',thigh);put('thigh_R',thigh);
      put('knee_L',knee);put('knee_R',knee);put('ankle_L',-h-thigh-knee);put('ankle_R',-h-thigh-knee);
      // Analytic leg-chain height keeps both cloth shoe soles at deck y=0.
      // Only pelvis y shifts: stationary root, no planar drift or root-motion authority.
      const ankleY=.87-.01*Math.cos(h)-.405*Math.cos(h+thigh)-.36*Math.cos(h+thigh+knee);
      p.hips_position=[0,.87-(ankleY-.095),0];
      put('spine',.30+.15*work);put('chest',.10,0,.035*s);put('head',.18);
      put('arm_L',-1.1-.2*c,0,.16);put('arm_R',-1.1-.2*c,0,-.16);
      put('elbow_L',-.28+.16*c);put('elbow_R',-.28+.16*c);
    } else if(name==='walk') {
      put('thigh_L',.35*s);put('thigh_R',-.35*s);
      put('knee_L',.10+.36*Math.max(0,-s));put('knee_R',.10+.36*Math.max(0,s));
      put('ankle_L',-.07-.10*s);put('ankle_R',-.07+.10*s);
      put('arm_L',-.22*s,0,.04);put('arm_R',.22*s,0,-.04);put('chest',0,.055*s);
    } else if(name==='lookout') {
      put('arm_R',-1.7+.025*c,0,.85);put('elbow_R',-1.7+.04*s);put('wrist_R',.3,0,.15);
      put('head',-.045,.28*s);put('chest',0,.07*s);put('elbow_L',-.2);
    }
    return p;
  }
  return SAILOR_CLIPS.map(name=>{
    const duration=durations[name],frames=17,tracks=[],samples=[];
    for(let n=0;n<frames;n++)samples.push(poses(name,n/(frames-1)));
    const names=new Set(samples.flatMap(p=>Object.keys(p)));
    for(const bone of names) {
      if(bone==='hips_position')continue;
      const times=[],values=[];
      for(let n=0;n<frames;n++) {
        times.push(duration*n/(frames-1));const e=samples[n][bone]??[0,0,0];
        values.push(...new THREE.Quaternion().setFromEuler(new THREE.Euler(...e,'XYZ')).toArray());
      }
      tracks.push(new THREE.QuaternionKeyframeTrack(`sailor_${bone}.quaternion`,times,values));
    }
    if(name==='load-cannon')tracks.push(new THREE.VectorKeyframeTrack('sailor_hips.position',samples.map((_,n)=>duration*n/(frames-1)),samples.flatMap(p=>p.hips_position)));
    return new THREE.AnimationClip(name,duration,tracks);
  });
}

export function sailorStatistics(root) {
  const mesh=root.getObjectByName('sailor_body'),size=new THREE.Box3().setFromObject(root).getSize(new THREE.Vector3());
  let nodes=0;root.traverse(()=>nodes++);
  return {dimensions:{width:size.x,height:size.y,depth:size.z},triangles:mesh.geometry.index.count/3,vertices:mesh.geometry.attributes.position.count,meshes:1,materials:1,bones:mesh.skeleton.bones.length,nodes,clips:root.animations.map(c=>({name:c.name,duration:c.duration,tracks:c.tracks.length}))};
}
