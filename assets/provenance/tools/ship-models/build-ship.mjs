import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { ZHENG_ROWS } from './zheng-glyph.mjs';

/** Metres; waterline y=0, bow +Z, starboard -X. Original procedural silhouettes. */
export const SHIP_SPECS = Object.freeze({
  fuchuan: { length:32, beam:9, draft:2, freeboard:1.9, masts:[[-8,10],[0,16],[9,10]], sails:3 },
  fisherman: { length:14, beam:4.2, draft:1, freeboard:1.15, masts:[[1,7.2]], sails:1 },
  merchant: { length:36, beam:10, draft:2.8, freeboard:2.3, masts:[[-10,12],[0,17],[10,12]], sails:3 },
  voc: { length:40, beam:11, draft:3.2, freeboard:2.7, masts:[[-10,15],[0,21],[11,17]], sails:6 },
  patrol: { length:24, beam:6, draft:1.4, freeboard:1.35, masts:[[-4,9.7,-.32],[5,12,.24]], sails:2 },
  heavy: { length:52, beam:14.5, draft:4.2, freeboard:4.2, masts:[[-13,21],[0,29],[14,24]], sails:9 },
});
export const SHIP_GUN_COUNTS=Object.freeze({fuchuan:6,voc:6,patrol:3,heavy:8});

const palette = {wood:0x9a693c, darkWood:0x4a2a1c, deck:0xc18c50, brass:0xd3ae60, iron:0x33363c, rope:0x786344};
const id = n => String(n).padStart(2,'0');
const vec = p => new THREE.Vector3(...p);
const clamp = THREE.MathUtils.clamp;

function tint(geometry,color) {
  let g = geometry.index ? geometry.toNonIndexed() : geometry;
  const p=g.attributes.position;
  if(!g.attributes.normal)g.computeVertexNormals();
  if(!g.attributes.uv)g.setAttribute('uv',new THREE.Float32BufferAttribute(new Float32Array(p.count*2),2));
  const c=new THREE.Color(color), data=[];
  for(let i=0;i<p.count;i++)data.push(c.r,c.g,c.b);
  g.setAttribute('color',new THREE.Float32BufferAttribute(data,3));
  return g;
}

function namedGroup(parent,name,position=[0,0,0]) {
  const o=new THREE.Group();o.name=name;o.position.set(...position);parent.add(o);return o;
}

function beamGeometry(a,b,r,sides=6,r2=r) {
  const start=vec(a),end=vec(b),delta=end.clone().sub(start);
  const g=new THREE.CylinderGeometry(r2,r,delta.length(),sides,1);
  const q=new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0,1,0),delta.clone().normalize());
  g.applyQuaternion(q);g.translate(...start.add(end).multiplyScalar(.5).toArray());return g;
}

// A complete closed cross-section loft including keel and sheer. Top edge closes each section.
function hullGeometry(s,lod,kind) {
  const rings=[32,18,8][lod], arc=[16,10,6][lod], p=[],uv=[],colors=[],index=[];
  for(let i=0;i<=rings;i++) {
    const t=-1+2*i/rings,z=t*s.length/2;
    const fullness=kind==='fisherman'?.78:kind==='merchant'?.55:kind==='voc'?.65:kind==='heavy'?.42:kind==='patrol'?.94:.70;
    const w=s.beam/2*Math.max(.035,Math.pow(Math.max(0,1-t*t),fullness)*(1-.12*t));
    // Exact maximum beam at midship, no width beyond specification.
    const width=Math.min(s.beam/2,w);
    const top=s.freeboard+.48*t*t+(kind==='fuchuan'?1.0:kind==='voc'?.65:kind==='heavy'?1.3:kind==='patrol'?.2:.35)*Math.pow(Math.max(0,-t),4);
    const depth=s.draft*(.16+.84*Math.pow(Math.max(0,1-t*t),.52));
    for(let j=0;j<=arc;j++) {
      const a=j/arc*Math.PI;
      const x=width*Math.cos(a), y=top-(top+depth)*Math.pow(Math.sin(a),.82);
      p.push(x,y,z);uv.push(i/rings,j/arc);
      const waterTone=y<-.15?.67:1;
      const plank=(Math.floor((y+s.draft)*4)%2===0?.91:1.07);
      const wear=.94+.06*Math.sin(i*1.37+j*.69);
      const c=new THREE.Color(kind==='voc'?0x65513b:kind==='heavy'?0x554431:kind==='patrol'?0x8c5837:kind==='fisherman'?0x956943:0x805534).multiplyScalar(waterTone*plank*wear);
      colors.push(c.r,c.g,c.b);
    }
  }
  const stride=arc+1;
  for(let i=0;i<rings;i++)for(let j=0;j<stride;j++) {
    const a=i*stride+j,b=i*stride+(j+1)%stride,c=(i+1)*stride+j,d=(i+1)*stride+(j+1)%stride;
    index.push(a,b,d,a,d,c);
  }
  // Polygon caps; fan stays on the endpoint section plane.
  for(let j=1;j<stride-1;j++) {index.push(0,j+1,j);const o=rings*stride;index.push(o,o+j,o+j+1);}
  const g=new THREE.BufferGeometry();
  g.setAttribute('position',new THREE.Float32BufferAttribute(p,3));
  g.setAttribute('uv',new THREE.Float32BufferAttribute(uv,2));
  for(let i=0;i<index.length;i+=3)[index[i+1],index[i+2]]=[index[i+2],index[i+1]];
  g.setAttribute('color',new THREE.Float32BufferAttribute(colors,3));g.setIndex(index);g.computeVertexNormals();
  return g;
}

function deckGeometry(s,lod) {
  const shape=new THREE.Shape(), steps=[28,16,8][lod];
  for(let side=0;side<2;side++) for(let i=0;i<=steps;i++) {
    const t=side===0?-1+2*i/steps:1-2*i/steps;
    const x=(side===0?1:-1)*s.beam*.46*Math.max(.025,Math.pow(Math.max(0,1-t*t),.64));
    if(side===0&&i===0)shape.moveTo(x,t*s.length/2);else shape.lineTo(x,t*s.length/2);
  }
  shape.closePath();
  const g=new THREE.ShapeGeometry(shape);g.rotateX(-Math.PI/2);g.translate(0,s.freeboard+.035,0);
  return g;
}

/** Cloth grid and integral coloured batten strips share deformable morph targets. */
function sailGeometry(width,height,lod,{western=false,red=true}={}) {
  const nx=[14,7,2][lod],ny=[18,8,2][lod],p=[],furl=[],inflate=[],uv=[],colors=[],indices=[];
  const sample=(u,v,offset=0)=>{
    const taper=western?1-.27*v:.74+.26*v;
    const x=(u-.5)*width*taper+(western?0:(v-.5)*width*.14);
    const y=v*height+(western?0:u*height*.11);
    const z=.045+Math.sin(u*Math.PI)*Math.sin(v*Math.PI)*width*.10+offset;
    return [x,y,z];
  };
  const vertex=(u,v,color,offset=0)=>{
    const a=sample(u,v,offset);p.push(...a);uv.push(u,v);
    furl.push(a[0],height*.96+(a[1]-height*.96)*.055,Math.sin(v*8*Math.PI)*.07+offset);
    inflate.push(a[0],a[1],a[2]+Math.sin(u*Math.PI)*Math.sin(v*Math.PI)*width*.19);
    const c=new THREE.Color(color);colors.push(c.r,c.g,c.b);return p.length/3-1;
  };
  for(let y=0;y<=ny;y++)for(let x=0;x<=nx;x++) {
    const seam=x%3===0||y%4===0;
    vertex(x/nx,y/ny,red?(seam?0x9d4c36:0xb36243):(seam?0xc7bb99:0xe7d9b5));
  }
  for(let y=0;y<ny;y++)for(let x=0;x<nx;x++) {
    const a=y*(nx+1)+x,b=a+1,c=a+nx+1,d=c+1;indices.push(a,b,d,a,d,c);
  }
  // Batten ribs/sewn reinforcements travel with the sail under furl and inflate.
  const rows=western?[.12,.88]:Array.from({length:[8,5,3][lod]},(_,i)=>(i+1)/([8,5,3][lod]+1));
  for(const v of rows) for(let x=0;x<nx;x++) {
    const u=x/nx,u2=(x+1)/nx,th=.015/height;
    const a=vertex(u,v-th,western?0xa79a7c:palette.darkWood,.055),b=vertex(u2,v-th,western?0xa79a7c:palette.darkWood,.055),c=vertex(u2,v+th,western?0xa79a7c:palette.darkWood,.055),d=vertex(u,v+th,western?0xa79a7c:palette.darkWood,.055);
    indices.push(a,b,c,a,c,d);
  }
  const g=new THREE.BufferGeometry();
  g.setAttribute('position',new THREE.Float32BufferAttribute(p,3));g.setAttribute('uv',new THREE.Float32BufferAttribute(uv,2));g.setAttribute('color',new THREE.Float32BufferAttribute(colors,3));g.setIndex(indices);g.computeVertexNormals();
  g.morphAttributes.position=[new THREE.Float32BufferAttribute(furl,3),new THREE.Float32BufferAttribute(inflate,3)];
  g.morphAttributes.position[0].name='furl';g.morphAttributes.position[1].name='inflate';
  // Export normals for every morph too; no shading seam appears while animating cloth.
  g.morphAttributes.normal=g.morphAttributes.position.map(attr=>{const copy=g.clone();copy.morphAttributes={};copy.setAttribute('position',attr.clone());copy.computeVertexNormals();return copy.attributes.normal;});
  return g;
}

export function createShip(kind,lod=0) {
  const s=SHIP_SPECS[kind];if(!s)throw new Error(`Unknown ship kind: ${kind}`);
  if(!Number.isInteger(lod)||lod<0||lod>2)throw new Error('LOD must be 0, 1, or 2');
  const root=new THREE.Group();root.name='ship_root';root.userData={kind,lod,dimensions:{length:s.length,beam:s.beam,draft:s.draft},axes:'bow +Z; starboard -X; waterline Y=0'};
  const materials={
    wood:new THREE.MeshStandardMaterial({name:'aged_timber',color:0xffffff,vertexColors:true,roughness:.82}),
    deck:new THREE.MeshStandardMaterial({name:'honey_deck',color:0xffffff,vertexColors:true,roughness:.9}),
    cloth:new THREE.MeshStandardMaterial({name:'woven_sailcloth',color:0xffffff,vertexColors:true,roughness:1,side:THREE.DoubleSide}),
    iron:new THREE.MeshStandardMaterial({name:'forged_iron',color:0xffffff,vertexColors:true,metalness:.67,roughness:.57}),
    trim:new THREE.MeshStandardMaterial({name:'brass_and_rope',color:0xffffff,vertexColors:true,metalness:.3,roughness:.72}),
  };
  const batches={wood:[],deck:[],iron:[],trim:[]};
  const add=(g,material='wood',color=palette.wood)=>batches[material].push(tint(g,color));
  const box=(size,pos,color=palette.wood,material='wood')=>{const g=new THREE.BoxGeometry(...size);g.translate(...pos);add(g,material,color);};
  const beam=(a,b,r=.06,color=palette.rope,material='trim')=>add(beamGeometry(a,b,r,lod===0?6:lod===1?4:3),material,color);
  const feature=(name,parent=root)=>namedGroup(parent,name);
  const featureBox=(name,size,pos,color=palette.wood,material='wood',parent=root)=>{
    const node=feature(name,parent),mesh=new THREE.Mesh(tint(new THREE.BoxGeometry(...size),color),materials[material]);
    mesh.position.set(...pos);mesh.name=`${name}_body`;node.add(mesh);return node;
  };
  const h=new THREE.Mesh(hullGeometry(s,lod,kind),materials.wood);h.name='hull';root.add(h);
  const deck=new THREE.Mesh(tint(deckGeometry(s,lod),palette.deck),materials.deck);deck.name='deck';root.add(deck);
  const y=s.freeboard;
  // Deck plank joins and caulking: merged geometry, never one draw per plank.
  const plankSpacing=kind==='fisherman'&&lod===1?.44:.22;
  if(lod<2)for(let n=-Math.floor(s.beam*.44/plankSpacing);n<=Math.floor(s.beam*.44/plankSpacing);n++) {
    const x=n*plankSpacing,zExtent=s.length*.46*Math.sqrt(Math.max(.0,1-(x/(s.beam*.47))**2));
    if(zExtent>1)box([.013,.012,zExtent*2],[x,y+.055,0],palette.darkWood,'deck');
  }
  // Sheer rails follow hull curvature. Keep a clean silhouette even at distance.
  const railSteps=(kind==='fisherman'?[20,8,5]:[24,12,5])[lod];
  if(kind!=='fisherman'||lod<2)for(const side of [-1,1]) {
    let previous;
    for(let i=0;i<=railSteps;i++) {
      const t=-.92+1.84*i/railSteps;
      const x=side*s.beam*.465*Math.pow(1-t*t,.64),z=t*s.length/2,ry=y+.75+.5*t*t;
      const point=[x,ry,z];if(previous) {
        beam(previous,point,lod===2?.09:.065,palette.brass);
        if(kind!=='fisherman') {
          const delta=vec(point).sub(vec(previous)),g=new THREE.BoxGeometry(.065,.56,Math.hypot(delta.x,delta.z));
          g.rotateY(Math.atan2(delta.x,delta.z));g.translate((x+previous[0])/2,(ry+previous[1])/2-.35,(z+previous[2])/2);add(g,'wood',palette.darkWood);
        }
      }
      if(lod<2&&(i%2===0))beam([x,y+.1,z],point,.055,palette.wood,'wood');
      previous=point;
    }
  }
  // Thick waterline rubbing strakes, finely faceted keel; longitudinal beams echo planking.
  if(lod<2)for(const side of [-1,1])for(const level of (kind==='fisherman'&&lod===1?[0,.6]:[0,.6,1.25])) {
    const segments=kind==='fisherman'?(lod===0?16:6):(lod===0?20:10);
    for(let i=0;i<segments;i++) {
      const t=-.94+1.88*i/segments,t2=-.94+1.88*(i+1)/segments;
      const a=[side*s.beam*.48*Math.pow(1-t*t,.68),level,t*s.length/2],b=[side*s.beam*.48*Math.pow(1-t2*t2,.68),level,t2*s.length/2];
      beam(a,b,.065,level===1.25?palette.brass:palette.darkWood,level===1.25?'trim':'wood');
    }
  }
  // Cabin, working deck, and steps shape are intentionally different for each vessel.
  if(kind==='fuchuan') {
    featureBox('sterncastle',[s.beam*.68,2.25,5.4],[0,y+1.15,-s.length*.34],palette.darkWood);
    box([s.beam*.74,.22,5.65],[0,y+2.36,-s.length*.34],palette.deck,'deck');
    if(lod<2) {
      for(const side of [-1,1])for(let n=0;n<4;n++) {
        box([.07,.84,.67],[side*s.beam*.345,y+1.28,-s.length*.40+n*1.18],0x181e22,'iron');
        for(const dz of [-.37,.37])box([.09,.96,.05],[side*s.beam*.35,y+1.28,-s.length*.40+n*1.18+dz],palette.brass,'trim');
      }
      for(let n=0;n<5;n++)box([2.2,.18,.43],[0,y+.16+n*.43,-7.6-n*.4],palette.deck,'deck');
      for(const side of [-1,1]) {
        const g=new THREE.SphereGeometry(.6,12,6);g.scale(.12,1,1);g.translate(side*1.54,y+.25,s.length*.425);add(g,'trim',palette.brass);
        const pupil=new THREE.SphereGeometry(.26,10,6);pupil.scale(.16,1,1);pupil.translate(side*1.60,y+.25,s.length*.426);add(pupil,'iron',0x111419);
      }
      for(let n=-2;n<=2;n++) {const g=new THREE.TorusGeometry(.29,.045,4,12);g.translate(n*1.0,y+1.1,-s.length*.426);add(g,'trim',palette.brass);}
    }
  } else if(kind==='fisherman') {
    featureBox('fishing_canopy',[2.7,.12,3.6],[0,y+1.6,-2.8],0x87724d,'deck');
    if(lod<2)for(const x of [-1.3,1.3])for(const z of [-4.5,-1.1])beam([x,y,z],[x,y+1.57,z],.04,palette.wood,'wood');
    if(lod<2)for(const x of [-.85,.85]) {
      const g=new THREE.CylinderGeometry(.46,.3,.55,lod===0?12:6,1,true);g.translate(x,y+.28,3.1);add(g,'wood',0xb09659);
      if(lod===0)for(let n=0;n<3;n++){const ring=new THREE.TorusGeometry(.35+n*.03,.025,3,12);ring.rotateX(Math.PI/2);ring.translate(x,y+.1+n*.17,3.1);add(ring,'trim',palette.rope);}
    }
    // Visible side oars are functional silhouette details, lower LOD keeps a single sweep.
    for(const side of (lod===2?[1]:[-1,1]))beam([side*1.3,y+.3,0],[side*3.0,.3,-2.2],.045,palette.wood,'wood');
    if(lod===0)for(let n=0;n<9;n++)beam([-.7+n*.16,y+.06,1.7],[.5+n*.06,y+.07,2.8],.015,palette.rope);
  } else if(kind==='merchant') {
    featureBox('cargo_hold',[s.beam*.57,.55,7.4],[0,y+.28,-3],palette.darkWood);
    box([s.beam*.61,.12,7.7],[0,y+.61,-3],0x6a624c,'deck');
    box([s.beam*.61,1.5,4.2],[0,y+.78,-s.length*.36],palette.wood);
    if(lod<2) {
      for(const x of [-2.6,2.6])for(let n=0;n<4;n++) {
        box([1.45,1.0,1.15],[x,y+.52,3+n*1.25],n%2===0?0xae7946:0x735236);
        box([1.47,.065,1.17],[x,y+.82,3+n*1.25],palette.rope,'trim');
      }
      beam([2.6,y,7.1],[2.6,y+5,7.1],.11,palette.wood,'wood');beam([2.6,y+5,7.1],[-1,y+4.4,8.3],.095,palette.wood,'wood');beam([-1,y+4.4,8.3],[-1,y+1.5,8.3],.025);
    }
  } else if(kind==='patrol') {
    featureBox('patrol_stern_house',[s.beam*.52,1.02,3.1],[0,y+.52,-7.1],palette.darkWood);
    box([s.beam*.59,.16,3.4],[0,y+1.12,-7.1],palette.deck,'deck');
    featureBox('bow_firing_platform',[3.45,.26,3.2],[0,y+.16,7.9],palette.deck,'deck');
    featureBox('shield_rack',[2.7,.62,.15],[0,y+.60,6.55],0x69412c);
    if(lod<2) {
      for(const x of [-1.0,0,1.0]) {
        const shield=new THREE.CylinderGeometry(.38,.38,.10,lod===0?10:6);shield.rotateX(Math.PI/2);shield.translate(x,y+.72,6.69);add(shield,'wood',0xa4623b);
        const boss=new THREE.SphereGeometry(.12,lod===0?8:5,4);boss.scale(1,1,.5);boss.translate(x,y+.72,6.77);add(boss,'trim',palette.brass);
      }
      for(const side of [-1,1]) {
        box([.05,.50,.82],[side*1.57,y+.62,-7.4],0x1c2628,'iron');
        box([.06,.06,.87],[side*1.6,y+.61,-7.4],palette.brass,'trim');
      }
      for(let n=0;n<3;n++)box([1.2,.15,.43],[0,y+.12+n*.31,-5.0-n*.39],palette.deck,'deck');
      // Paired sweeping oars and bow cross-beam distinguish the fast escort from a cargo hull.
      for(const side of [-1,1])beam([side*2.2,y+.1,-2],[side*4.0,.2,-5],.055,palette.wood,'wood');
      beam([-1.9,y+.34,8.7],[1.9,y+.34,8.7],.075,palette.brass);
    }
  } else if(kind==='heavy') {
    const gallery=feature('admiral_stern_gallery');
    const tiers=[{width:.70,height:2.2,y:1.15,z:-.35,length:8.4},{width:.59,height:2.0,y:3.3,z:-.367,length:7.4},{width:.46,height:1.8,y:5.25,z:-.385,length:6.3}];
    for(let ti=0;ti<tiers.length;ti++) {
      const t=tiers[ti],centerZ=s.length*t.z,centerY=y+t.y,width=s.beam*t.width;
      featureBox(`stern_tier_${id(ti+1)}`,[width,t.height,t.length],[0,centerY,centerZ],ti===0?0x38443f:0x464235,'wood',gallery);
      box([width+.48,.18,t.length+.35],[0,centerY+t.height/2+.08,centerZ],palette.deck,'deck');
      // Gold entablatures give the command stern three unmistakable horizontal storeys.
      for(const side of [-1,1])beam([side*(width/2+.06),centerY+t.height*.39,centerZ-t.length/2],[side*(width/2+.06),centerY+t.height*.39,centerZ+t.length/2],.09,palette.brass);
      if(lod<2) {
        const windowCount=lod===0?6:3;
        for(const side of [-1,1])for(let n=0;n<windowCount;n++) {
          const wz=centerZ-t.length*.38+n*t.length*.76/(windowCount-1);
          box([.08,.98,.72],[side*(width/2+.025),centerY,wz],0x162b32,'iron');
          box([.10,.08,.78],[side*(width/2+.075),centerY,wz],palette.brass,'trim');
          for(const dz of [-.4,.4])box([.10,1.08,.06],[side*(width/2+.075),centerY,wz+dz],palette.brass,'trim');
        }
        for(let n=0;n<(lod===0?5:3);n++) {
          const wx=-width*.36+n*width*.72/((lod===0?5:3)-1),tz=centerZ-t.length/2-.06;
          box([.82,1.0,.09],[wx,centerY,tz],0x182b35,'iron');
          box([.9,.08,.10],[wx,centerY,tz-.02],palette.brass,'trim');
          box([.07,1.07,.10],[wx,centerY,tz-.02],palette.brass,'trim');
        }
      }
    }
    beam([0,y+1.0,s.length*.41],[0,y+4.2,s.length*.63],.26,palette.wood,'wood');
    if(lod<2) {
      for(const side of [-1,1]) {
        beam([0,y+4.2,s.length*.63],[side*4.1,y+.7,s.length*.30],.035);
        for(let n=0;n<8;n++)box([.12,.18,.8],[side*s.beam*.39,y+1.03,-s.length*.25+n*3.4],palette.brass,'trim');
      }
      for(let n=0;n<7;n++)box([2.8,.19,.5],[0,y+.15+n*.32,-12.7-n*.47],palette.deck,'deck');
      const crest=new THREE.TorusGeometry(.85,.1,5,16);crest.translate(0,y+5.32,-s.length*.445);add(crest,'trim',palette.brass);
    }
  } else {
    featureBox('stern_gallery',[s.beam*.64,2.25,6.2],[0,y+1.15,-s.length*.35],0x3c403b);
    box([s.beam*.79,.22,6.5],[0,y+2.42,-s.length*.35],palette.deck,'deck');
    if(lod<2)for(const side of [-1,1])for(let n=0;n<5;n++) {
      box([.07,.82,.78],[side*s.beam*.325,y+1.22,-s.length*.414+n*1.13],0x162632,'iron');
      box([.10,.06,.8],[side*s.beam*.33,y+1.25,-s.length*.414+n*1.13],palette.brass,'trim');
    }
    beam([0,y+.8,s.length*.40],[0,y+2.8,s.length*.61],.18,palette.wood,'wood');
    if(lod<2) {beam([0,y+2.8,s.length*.61],[-3,y+.8,s.length*.3],.025);beam([0,y+2.8,s.length*.61],[3,y+.8,s.length*.3],.025);}
  }
  // Control nodes: no animation naming changes across any LOD.
  const rudder=namedGroup(root,'rudder_pivot',[0,-.45,-s.length*.48]);
  const rudderMesh=new THREE.Mesh(tint(new THREE.BoxGeometry(.17,s.draft*1.08,1.25),palette.darkWood),materials.wood);rudderMesh.position.set(0,-s.draft*.32,-.35);rudder.add(rudderMesh);
  let sailNumber=1;
  for(let mi=0;mi<s.masts.length;mi++) {
    const [z,height,trim=0]=s.masts[mi],mast=namedGroup(root,`mast_${id(mi+1)}`,[0,y,z]);mast.rotation.y=trim;
    const g=beamGeometry([0,0,0],[0,height,0],kind==='fisherman'?.1:.18,lod===0?10:lod===1?6:4,.07);
    const mesh=new THREE.Mesh(tint(g,palette.darkWood),materials.wood);mesh.name=`mast_timber_${id(mi+1)}`;mast.add(mesh);
    const western=kind==='voc'||kind==='heavy';
    const levels=kind==='heavy'?3:western?2:1;
    for(let level=0;level<levels;level++) {
      const width=kind==='heavy'?s.beam*[1.14,.86,.58][level]:western?s.beam*(level===0?1.11:.78):s.beam*(mi===1?1.06:.87);
      const clothHeight=kind==='heavy'?height*[.30,.25,.18][level]:western?height*(level===0?.39:.3):height*.75;
      const clothBottom=kind==='heavy'?height*[.08,.46,.79][level]:western?height*(level===0?.12:.57):height*.13;
      const sail=new THREE.Mesh(sailGeometry(width,clothHeight,lod,{western,red:kind==='fuchuan'||kind==='patrol'}),materials.cloth);
      sail.name=`sail_${id(sailNumber++)}`;sail.position.set(0,clothBottom,.13);sail.userData.control={furl:0,inflate:1};mast.add(sail);
      const yard=beamGeometry([-width*.52,clothBottom+clothHeight,0],[width*.52,clothBottom+clothHeight,0],.065,lod===0?6:3);
      const yardMesh=new THREE.Mesh(tint(yard,palette.wood),materials.wood);mast.add(yardMesh);
    }
    if(lod<2)for(const side of [-1,1]) {
      beam([0,y+height*.92,z],[side*s.beam*.39,y+.3,z-3],.025);
      beam([0,y+height*.68,z],[side*s.beam*.41,y+.3,z+3],.02);
      if(lod===0)for(let rung=0;rung<10;rung++) {
        const t=rung/10;beam([side*s.beam*.39*(1-t),y+.3+height*.8*t,z-3*(1-t)],[side*s.beam*.41*(1-t),y+.3+height*.8*t,z+3*(1-t)],.016);
      }
    }
  }
  const gunCount=SHIP_GUN_COUNTS[kind]??0;
  for(const side of ['port','starboard'])for(let n=1;n<=gunCount;n++) {
    const sign=side==='port'?1:-1,z=-s.length*.23+(n-1)*s.length*.46/(gunCount-1),curve=Math.pow(1-(z/(s.length/2))**2,.64);
    const gun=namedGroup(root,`cannon_${side}_${id(n)}`,[sign*s.beam*.435*curve,y+.30,z]);gun.rotation.y=sign*Math.PI/2;
    const barrelParts=[tint(beamGeometry([0,0,-.45],[0,0,.85],.15,lod===0?10:lod===1?6:4,.19),palette.iron)];
    if(lod<2) {const muzzle=new THREE.CircleGeometry(.13,lod===0?10:6);muzzle.translate(0,0,.856);barrelParts.push(tint(muzzle,0x06080b));}
    const barrel=new THREE.Mesh(mergeGeometries(barrelParts),materials.iron);barrel.name=`barrel_${side}_${id(n)}`;barrel.userData={restPositionZ:0,role:'cannon_recoil'};gun.add(barrel);
    box([.76,.32,.77],[sign*s.beam*.405*curve,y+.10,z],palette.darkWood);
    if(lod<2)box([.035,.52,.72],[sign*(s.beam*.465*curve+.04),y+.37,z],0x17171b,'iron');
    const socket=namedGroup(gun,`socket_smoke_${side}_${id(n)}`,[0,0,.87]);socket.userData.effect='cannon-smoke';
  }
  const [,flagHeight]=s.masts[kind==='fisherman'?0:1],flagZ=s.masts[kind==='fisherman'?0:1][0];
  const flag=feature('flag_01');flag.position.set(0,y+flagHeight+.2,flagZ);
  const fp=[],fc=[],fu=[],fi=[],flagWidth=kind==='fisherman'?.9:2.5,flagH=kind==='fisherman'?.45:1.1;
  const cols=lod===0?8:lod===1?4:2;
  for(let j=0;j<4;j++)for(let i=0;i<=cols;i++) {
    const u=i/cols,v=j/3;fp.push(u*flagWidth,(-v)*flagH,Math.sin(u*8)*u*.17);fu.push(u,v);
    const c=new THREE.Color(kind==='voc'||kind==='heavy'?[0xbd6436,0xf3dfb4,0x35526b,0x35526b][j]:kind==='fuchuan'||kind==='patrol'?(j===0||j===3?0xb25134:0xe7bb68):0x987341);fc.push(c.r,c.g,c.b);
  }
  for(let j=0;j<3;j++)for(let i=0;i<cols;i++){const a=j*(cols+1)+i,b=a+1,c=a+cols+1,d=c+1;fi.push(a,b,d,a,d,c);}
  const fg=new THREE.BufferGeometry();fg.setAttribute('position',new THREE.Float32BufferAttribute(fp,3));fg.setAttribute('uv',new THREE.Float32BufferAttribute(fu,2));fg.setAttribute('color',new THREE.Float32BufferAttribute(fc,3));fg.setIndex(fi);fg.computeVertexNormals();flag.add(new THREE.Mesh(fg,materials.cloth));
  if((kind==='fuchuan'||kind==='patrol')&&lod<2) {
    const lettering=[];
    ZHENG_ROWS.forEach((row,j)=>{
      for(let i=0;i<row.length;i++)if(row[i]==='#') {
        const first=i;while(row[i+1]==='#')i++;
        const x=.93+(first+i+1)/2/row.length*.67,yy=-.14-(j+.5)/ZHENG_ROWS.length*.81;
        const g=new THREE.PlaneGeometry((i-first+1)/row.length*.67,.81/ZHENG_ROWS.length);
        const a=g.attributes.position;
        for(let k=0;k<a.count;k++){const xx=a.getX(k)+x;a.setXYZ(k,xx,a.getY(k)+yy,Math.sin(xx/flagWidth*8)*(xx/flagWidth)*.17+.013);}
        g.computeVertexNormals();lettering.push(tint(g,0x221d18));
      }
    });
    const mark=new THREE.Mesh(mergeGeometries(lettering),materials.cloth);mark.name='zheng_pennant_mark';flag.add(mark);
  }
  namedGroup(root,'socket_wake',[0,0,-s.length*.48]);
  namedGroup(root,'socket_crew_01',[s.beam*.22,y+.1,1.0]);
  namedGroup(root,'socket_crew_02',[-s.beam*.22,y+.1,-1.0]);
  // Four merged static batches; hull/deck and animated sails/guns stay individually addressable.
  for(const [key,geometries] of Object.entries(batches))if(geometries.length) {
    const mesh=new THREE.Mesh(mergeGeometries(geometries),materials[key]);mesh.name=`fittings_${key}`;root.add(mesh);
  }
  root.traverse(o=>{if(o.isMesh){o.castShadow=true;o.receiveShadow=true;}});
  root.updateMatrixWorld(true);
  return root;
}

export function shipStatistics(ship) {
  let triangles=0,meshes=0;const materials=new Set(),nodes=[];
  ship.traverse(o=>{if(o.name)nodes.push(o.name);if(o.isMesh){meshes++;triangles+=(o.geometry.index?.count??o.geometry.attributes.position.count)/3;materials.add(o.material.name);}});
  return {triangles,meshes,materialCount:materials.size,materials:[...materials],nodes:[...new Set(nodes)].sort()};
}
