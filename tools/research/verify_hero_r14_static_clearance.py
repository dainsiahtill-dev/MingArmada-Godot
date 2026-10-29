"""Discrete triangle distances for coamings against preserved hatch and fittings."""
import argparse,hashlib,json
from pathlib import Path
import numpy as np
from hero_r10_triangle_distance import surface_distance
from verify_hero_palette_delta import read_glb,decode_accessor

ROOT=Path(__file__).resolve().parents[2]
def triangles(doc,data,name):
    matches=[(i,n) for i,n in enumerate(doc['nodes']) if n.get('name')==name]
    if len(matches)!=1:raise ValueError('unique node required')
    index,node=matches[0]
    root=next(n for n in doc['nodes'] if n.get('name')=='HeroFuchuan')
    if index not in root['children'] or any(k in node for k in ('translation','rotation','scale','matrix')) or any(k in root for k in ('translation','rotation','scale','matrix')):raise ValueError('unexpected node frame')
    parts=[]
    for p in doc['meshes'][node['mesh']]['primitives']:
        if p.get('mode',4)!=4:raise ValueError('non-triangle mesh')
        vertices=np.asarray(decode_accessor(doc,data,p['attributes']['POSITION']),dtype=np.float64)
        indices=np.asarray(decode_accessor(doc,data,p['indices']),dtype=np.int64).reshape(-1)
        if len(indices)%3 or indices.max()>=len(vertices):raise ValueError('invalid triangle index')
        parts.append(vertices[indices.reshape(-1,3)])
    return np.concatenate(parts)

def main():
    p=argparse.ArgumentParser();p.add_argument('--model-dir',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    if a.output.exists():p.error('fresh output required')
    rows=[]
    for lod in range(3):
        path=a.model_dir/f'fuchuan-lod{lod}.glb';doc,data,digest=read_glb(path);fittings=triangles(doc,data,'deck_fittings')
        for center in ['-3.2','5.8']:
            coaming=triangles(doc,data,'cargo_hold_coaming_'+center)
            for other,mesh in [('deck_fittings',fittings),('cargo_hold_'+center,triangles(doc,data,'cargo_hold_'+center))]:
                measure=surface_distance(coaming,mesh,1e-7)
                rows.append({'lod':lod,'coaming':center,'other':other,'minimumMeters':measure['minimumMeters'],'nearPairCount':len(measure['nearPairs']),'transversePairCount':len(measure['transversePairs']),'coamingTriangles':len(coaming),'otherTriangles':len(mesh),'narrowPhasePairs':measure['narrowPhasePairs'],'glbSha256':digest})
                print('HERO_R14_CLEARANCE',lod,center,other,measure['minimumMeters'],flush=True)
    report={'rows':rows,'toolSha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'scope':'Discrete static triangle-surface distances; deck_fittings contains original hatch grids and other merged fittings. No moving sails, rotating guns, crew paths, GPU or certified exact predicates.'}
    a.output.parent.mkdir(parents=True,exist_ok=True)
    with a.output.open('x',encoding='utf-8') as f:json.dump(report,f,indent=2)
if __name__=='__main__':main()
