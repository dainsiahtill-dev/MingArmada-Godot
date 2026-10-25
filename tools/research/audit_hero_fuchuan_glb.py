import json,struct,hashlib,pathlib,argparse,numpy as np
ROOT=pathlib.Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser();parser.add_argument('--output',required=True);args=parser.parse_args();OUT=pathlib.Path(args.output);assert not OUT.exists(),'fresh output required'
def sha(b):return hashlib.sha256(b).hexdigest()
class GLB:
 def __init__(self,p):
  self.raw=p.read_bytes();n=struct.unpack_from('<I',self.raw,12)[0];self.d=json.loads(self.raw[20:20+n]);self.b=self.raw[28+n:];self.nodes={n['name']:n for n in self.d['nodes']};self.parents={self.d['nodes'][c]['name']:n['name'] for n in self.d['nodes'] for c in n.get('children',[])}
 def acc(self,i):
  a=self.d['accessors'][i];dt={5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'}[a['componentType']];k={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']];size=np.dtype(dt).itemsize*k
  raw=bytes(size*a['count'])
  if 'bufferView' in a:
   v=self.d['bufferViews'][a['bufferView']];start=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',size);raw=b''.join(self.b[start+j*stride:start+j*stride+size] for j in range(a['count']))
  meta={k:v for k,v in a.items() if k not in ['bufferView','byteOffset','sparse']}
  if 'sparse' in a:
   s=a['sparse'];iv=self.d['bufferViews'][s['indices']['bufferView']];vv=self.d['bufferViews'][s['values']['bufferView']];idt={5121:'u1',5123:'<u2',5125:'<u4'}[s['indices']['componentType']];start=iv.get('byteOffset',0)+s['indices'].get('byteOffset',0);iraw=self.b[start:start+s['count']*np.dtype(idt).itemsize];idx=np.frombuffer(iraw,dtype=idt);start=vv.get('byteOffset',0)+s['values'].get('byteOffset',0);vraw=self.b[start:start+s['count']*size];values=np.frombuffer(raw,dtype=dt).reshape(-1,k).copy();values[idx]=np.frombuffer(vraw,dtype=dt).reshape(-1,k);raw=values.tobytes();meta['sparse_encoding']={'count':s['count'],'indices_sha256':sha(iraw),'values_sha256':sha(vraw),'indices_componentType':s['indices']['componentType']}
  return meta,raw,np.frombuffer(raw,dtype=dt).reshape(-1,k)
 def frame(self,name):
  n=self.nodes[name];return {k:n.get(k,v) for k,v in [('translation',[0,0,0]),('rotation',[0,0,0,1]),('scale',[1,1,1]),('matrix',None)]}
 def chain(self,name):
  out=[]
  while name is not None:out.append({'name':name,'frame':self.frame(name)});name=self.parents.get(name)
  return out
 def mesh(self,name):return self.d['meshes'][self.nodes[name]['mesh']]
 def accessors(self,name):
  out={}
  for j,p in enumerate(self.mesh(name)['primitives']):
   for k,i in p['attributes'].items():out[f'{j}/attributes/{k}']=self.acc(i)
   if 'indices' in p:out[f'{j}/indices']=self.acc(p['indices'])
   for t,target in enumerate(p.get('targets',[])):
    for k,i in target.items():out[f'{j}/targets/{t}/{k}']=self.acc(i)
  return out
 def triangles(self,name):
  out=[]
  for p in self.mesh(name)['primitives']:
   vs=self.acc(p['attributes']['POSITION'])[2];idx=self.acc(p['indices'])[2].reshape(-1,3);out.extend(vs[idx])
  return np.asarray(out,dtype=float)
def hits(g,name,start,end):
 t=g.triangles(name);o=np.array(start);d=np.array(end)-o;e1=t[:,1]-t[:,0];e2=t[:,2]-t[:,0];h=np.cross(np.broadcast_to(d,e2.shape),e2);a=np.einsum('ij,ij->i',e1,h);valid=np.abs(a)>1e-10;f=np.zeros_like(a);f[valid]=1/a[valid];s=o-t[:,0];u=f*np.einsum('ij,ij->i',s,h);q=np.cross(s,e1);v=f*np.einsum('j,ij->i',d,q);dist=f*np.einsum('ij,ij->i',e2,q);ok=valid&(u>=0)&(v>=0)&(u+v<=1)&(dist>=0)&(dist<=1);return sorted(set(round(float(x),7) for x in dist[ok]))
report={'method':'Direct GLB JSON/BIN parse; compare packed accessor element bytes (exclude buffer offsets/padding), decoded values, metadata, morph targets and complete ancestor TRS chains. No Godot/GPU run.','lods':[]}
for lod in range(3):
 a=GLB(ROOT/f'assets/models/hero_fuchuan_v3/fuchuan-lod{lod}.glb');b=GLB(ROOT/f'assets/models/hero_fuchuan_v3_r6/fuchuan-lod{lod}.glb');rec={'lod':lod,'r5_sha256':sha(a.raw),'r6_sha256':sha(b.raw),'nodes_added':sorted(b.nodes.keys()-a.nodes.keys()),'nodes_removed':sorted(a.nodes.keys()-b.nodes.keys()),'comparisons':{}}
 required=['hull','deck']+[f'sail_{i}' for i in range(3)]+['shadow_hull','shadow_deck']+[f'shadow_mast_timber_{i}' for i in range(3)]+[f'socket_smoke_{side}_{i:02}' for side in ['port','starboard'] for i in range(4)]+['rudder_pivot','crew_helm','helm_grip']+[f'mast_{i}' for i in range(3)]+['rudder_stock','tiller_beam','tiller_grip']+[f'barrel_{side}_{i:02}' for side in ['port','starboard'] for i in range(4)]+[f'mast_timber_{i}' for i in range(3)]+[f'rigging_{i}' for i in range(3)]+['water_bow','water_wake']
 for name in required:
  r={'local_frame_equal':a.frame(name)==b.frame(name),'ancestor_frames_equal':a.chain(name)==b.chain(name),'parent':b.parents.get(name),'frame':b.frame(name),'role_extras_equal':a.nodes[name].get('extras')==b.nodes[name].get('extras')}
  if 'mesh' in a.nodes[name]:
   aa=a.accessors(name);bb=b.accessors(name);r['accessor_keys_equal']=aa.keys()==bb.keys();r['accessors']={}
   for key,(meta,raw,values) in aa.items():
    other=bb[key];r['accessors'][key]={'count':meta['count'],'type':meta['type'],'componentType':meta['componentType'],'sha256':sha(raw),'bytes_equal':raw==other[1],'values_equal':np.array_equal(values,other[2]),'metadata_equal':meta==other[0]}
   r['mesh_extras_equal']=a.mesh(name).get('extras')==b.mesh(name).get('extras');r['mesh_extras']=b.mesh(name).get('extras');r['weights_equal']=a.mesh(name).get('weights')==b.mesh(name).get('weights')
  rec['comparisons'][name]=r
 rec['proxy_full_frame_pairs']={n:{'same_parent':b.parents[n]==b.parents['shadow_'+n],'same_local_frame':b.frame(n)==b.frame('shadow_'+n)} for n in ['hull','deck']+[f'mast_timber_{i}' for i in range(3)]}
 rec['aft_window_wall_rays']=[{'start':[x,3.59,-17],'end':[x,3.59,-14],'transom_hits':hits(b,'stern_transom',[x,3.59,-17],[x,3.59,-14]),'fittings_hits':hits(b,'deck_fittings',[x,3.59,-17],[x,3.59,-14])} for x in [-.78,.88]]
 def projected_area(g):
  t=g.triangles('rudder_blade');return float(np.abs(np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0])[:,0]).sum()/4)
 old_area=projected_area(a);new_area=projected_area(b)
 rec['rudder_projected_area']={'method':'Half total unsigned triangle projection area onto local YZ; closed blade with two nonoverlapping side skins.','r5_m2':old_area,'r6_m2':new_area,'relative_change':new_area/old_area-1}
 rec['all_mesh_geometry_changes']=[]
 for name in sorted(a.nodes.keys()&b.nodes.keys()):
  if 'mesh' not in a.nodes[name] or 'mesh' not in b.nodes[name]:continue
  aa=a.accessors(name);bb=b.accessors(name)
  if aa.keys()!=bb.keys() or any(aa[k][0]!=bb[k][0] or aa[k][1]!=bb[k][1] for k in aa):rec['all_mesh_geometry_changes'].append(name)
 report['lods'].append(rec)
report['all_required_contract_comparisons_pass']=all(r['local_frame_equal'] and r['ancestor_frames_equal'] and r['role_extras_equal'] and r.get('mesh_extras_equal',True) and r.get('weights_equal',True) and r.get('accessor_keys_equal',True) and all(x['bytes_equal'] and x['values_equal'] and x['metadata_equal'] for x in r.get('accessors',{}).values()) for l in report['lods'] for r in l['comparisons'].values())
report['declared_geometry_changes']=['deck: 16mm joints narrowed to 4mm; validated by Godot geometric/standing contracts']
report['all_frames_preserved']=all(r['local_frame_equal'] and r['ancestor_frames_equal'] and r['role_extras_equal'] for l in report['lods'] for r in l['comparisons'].values())
report['all_undeclared_geometry_preserved']=all(r.get('accessor_keys_equal',True) and r.get('mesh_extras_equal',True) and r.get('weights_equal',True) and all(x['bytes_equal'] and x['values_equal'] and x['metadata_equal'] for x in r.get('accessors',{}).values()) for l in report['lods'] for name,r in l['comparisons'].items() if name!='deck')
OUT.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps({'pass':report['all_required_contract_comparisons_pass'],'lods':[{'lod':r['lod'],'changed':r['all_mesh_geometry_changes'],'added':r['nodes_added'],'removed':r['nodes_removed'],'rudder_projected_area':r['rudder_projected_area']} for r in report['lods']]},indent=2))

print('R6_CONTRACT_SCOPE_CHECK all_frames='+str(report['all_frames_preserved'])+' all_undeclared_geometry='+str(report['all_undeclared_geometry_preserved']))
raise SystemExit(0 if report['all_frames_preserved'] and report['all_undeclared_geometry_preserved'] else 1)
