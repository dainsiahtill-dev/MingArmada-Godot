"""Append only two Blender-authored R14B coamings to each exact R7c LOD GLB."""
import argparse,copy,hashlib,json,sys
from datetime import datetime,timezone
from pathlib import Path
from transfer_hero_shadow_geometry import dense,encode,identity,read_checked

ROOT=Path(__file__).resolve().parents[2]
NAMES=['cargo_hold_coaming_-3.2','cargo_hold_coaming_5.8']
def sha(data):return hashlib.sha256(data).hexdigest()
def unique(items,key,value):
    found=[(i,x) for i,x in enumerate(items) if x.get(key)==value]
    if len(found)!=1:raise ValueError('unique '+str(value)+' required')
    return found[0]
def texture_bytes(doc,data,material):
    idx=material['pbrMetallicRoughness']['baseColorTexture']['index']
    img=doc['images'][doc['textures'][idx]['source']];view=doc['bufferViews'][img['bufferView']]
    start=view.get('byteOffset',0);return data[start:start+view['byteLength']]

def pack(base,base_bin,raw,raw_bin):
    root=identity(base,'hero-fuchuan-v3-r7c');identity(raw,'hero-fuchuan-v3-r7c')
    if any(any(n.get('name')==name for n in base['nodes']) for name in NAMES):raise ValueError('candidate nodes already exist')
    bi,bmat=unique(base['materials'],'name','teak');ri,rmat=unique(raw['materials'],'name','teak')
    if bmat!=rmat or texture_bytes(base,base_bin,bmat)!=texture_bytes(raw,raw_bin,rmat):raise ValueError('teak material or source image differs')
    out=copy.deepcopy(base);binary=bytearray(base_bin);outroot=identity(out,'hero-fuchuan-v3-r7c')
    outroot.setdefault('extras',{})['candidate_experiment']='hero-fuchuan-v3-r14b'
    ranges=[]
    for name in NAMES:
        _,node=unique(raw['nodes'],'name',name)
        if set(node)-{'name','mesh','extras'} or node.get('extras')!={'deck_obstacle':True}:raise ValueError('unexpected authored node schema')
        mesh=raw['meshes'][node['mesh']]
        if len(mesh['primitives'])!=1:raise ValueError('exactly one primitive required')
        prim=mesh['primitives'][0]
        if set(prim)!={'attributes','indices','material'} or set(prim['attributes'])!={'POSITION','NORMAL','TEXCOORD_0'} or prim['material']!=ri:raise ValueError('unexpected authored geometry schema')
        newprim={'attributes':{},'material':bi}
        for key,index in [(k,prim['attributes'][k]) for k in ['POSITION','NORMAL','TEXCOORD_0']]+[('indices',prim['indices'])]:
            accessor,(start,end),data,values=dense(raw,raw_bin,index)
            if accessor.get('componentType') not in ([5123,5125] if key=='indices' else [5126]):raise ValueError('unexpected component type')
            if accessor.get('type')!=('SCALAR' if key=='indices' else 'VEC2' if key=='TEXCOORD_0' else 'VEC3'):raise ValueError('unexpected attribute type')
            while len(binary)%4:binary.append(0)
            offset=len(binary);binary.extend(data);view_index=len(out['bufferViews']);out['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(data)})
            spec=copy.deepcopy(accessor);spec['bufferView']=view_index;spec.pop('byteOffset',None)
            accessor_index=len(out['accessors']);out['accessors'].append(spec)
            if key=='indices':newprim['indices']=accessor_index
            else:newprim['attributes'][key]=accessor_index
            ranges.append({'node':name,'attribute':key,'start':offset,'end':len(binary),'sourceStart':start,'sourceEnd':end,'sha256':sha(data)})
        newmesh={'name':mesh['name'],'primitives':[newprim]};mesh_index=len(out['meshes']);out['meshes'].append(newmesh)
        newnode={'name':name,'mesh':mesh_index,'extras':{'deck_obstacle':True}}
        outroot.setdefault('children',[]).append(len(out['nodes']));out['nodes'].append(newnode)
    out['buffers'][0]['byteLength']=len(binary)
    if bytes(binary[:len(base_bin)])!=base_bin:raise ValueError('baseline bytes changed')
    return out,bytes(binary),ranges

def main():
    p=argparse.ArgumentParser();p.add_argument('--baseline',type=Path,required=True);p.add_argument('--authored',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args()
    if a.output.exists() or a.report.exists():p.error('fresh output and report required')
    inputs=[a.baseline/f'fuchuan-lod{i}.glb' for i in range(3)]+[a.authored/f'fuchuan-lod{i}.glb' for i in range(3)]
    before={str(x):sha(x.read_bytes()) for x in inputs};prepared=[]
    for lod in range(3):
        base,bb,_=read_checked(a.baseline/f'fuchuan-lod{lod}.glb');raw,rb,_=read_checked(a.authored/f'fuchuan-lod{lod}.glb')
        doc,data,ranges=pack(base,bb,raw,rb);prepared.append((lod,encode(doc,data),ranges))
    if before!={str(x):sha(x.read_bytes()) for x in inputs}:raise ValueError('input changed')
    a.output.mkdir(parents=True,exist_ok=False);lods=[]
    for lod,data,ranges in prepared:
        out=a.output/f'fuchuan-lod{lod}.glb'
        with out.open('xb') as f:f.write(data)
        lods.append({'lod':lod,'sha256':sha(data),'newAttributeRanges':ranges})
    report={'pass':True,'asset':'hero-fuchuan-v3-r14b','inputSha256':before,'lods':lods,'toolSha256':sha(Path(__file__).read_bytes()),'finishedUTC':datetime.now(timezone.utc).isoformat(),'scope':'Two added coaming nodes and their buffers; prior R7c geometry and bytes unchanged. Not a Blender full re-export, nor GPU/collision acceptance.'}
    with (a.output/'manifest.json').open('x',encoding='utf-8') as f:json.dump(report,f,indent=2)
    a.report.parent.mkdir(parents=True,exist_ok=True)
    with a.report.open('x',encoding='utf-8') as f:json.dump(report,f,indent=2)
    print('HERO_R14B_COAMING_PACK_PASS lods=3')
if __name__=='__main__':main()
