"""Independently compare all authored sail morph deltas with R12 reefing logic.

This tests GLB numeric meaning, not intersections, continuous motion or gameplay.
"""
import argparse, hashlib, json, math
from pathlib import Path
from verify_hero_palette_delta import decode_accessor, read_glb

PARAMS=[(10.3,7.4,4.6,.25,.12),(17.,11.8,4.05,.40,.17),(9.,6.8,5.35,.54,.09)]
MATERIALS=['canvas','bamboo','canvas_seam','hemp']

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def shape_expected(pos,height,width,base,k,rake):
    x,y,z=pos
    v=max(0.,min(1.,(y-base)/(height*1.12)))
    for _ in range(12):
        breadth=width*(1+.10*math.sin(math.pi*v)-k*v*v)
        u=max(0.,min(1.,(z+width*.045*v*v)/breadth+.70))
        v=max(0.,min(1.,(y-base)/height-rake*(1-u)*v**2.2))
    # Blender glTF exporter packs a shape key as a relative displacement.
    furl=(.32+(x-.32)*.2-x,base+(y-base)*.038-y,0.)
    inflate=(width*.019*math.sin(math.pi*v)*math.sin(math.pi*u) if x>.25 else 0.,0.,0.)
    return furl,inflate

def main():
    p=argparse.ArgumentParser();p.add_argument('--model-dir',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    if a.output.exists():p.error('fresh report required')
    results=[]; failures=[]
    for lod in range(3):
        path=a.model_dir/f'fuchuan-lod{lod}.glb';doc,binbuf,digest=read_glb(path)
        for i,params in enumerate(PARAMS):
            matches=[n for n in doc['nodes'] if n.get('name')=='sail_'+str(i)]
            if len(matches)!=1:raise ValueError('expected one sail node')
            mesh=doc['meshes'][matches[0]['mesh']]
            if mesh.get('extras',{}).get('targetNames')!=['furl','inflate']:raise ValueError('shape key names changed')
            prims=mesh['primitives']
            if [doc['materials'][p['material']]['name'] for p in prims]!=MATERIALS:raise ValueError('material schema changed')
            for primitive in prims:
                material=doc['materials'][primitive['material']]['name']
                positions=decode_accessor(doc,binbuf,primitive['attributes']['POSITION'])
                furl=decode_accessor(doc,binbuf,primitive['targets'][0]['POSITION'])
                inflate=decode_accessor(doc,binbuf,primitive['targets'][1]['POSITION'])
                if len(positions)!=len(furl) or len(positions)!=len(inflate):raise ValueError('morph vertex count differs')
                max_furl=max_inflate=0.
                for pos,f,inf in zip(positions,furl,inflate,strict=True):
                    ef,ei=shape_expected(pos,*params)
                    max_furl=max(max_furl,max(abs(a-b) for a,b in zip(f,ef)))
                    max_inflate=max(max_inflate,max(abs(a-b) for a,b in zip(inf,ei)))
                passed=max_furl<.00002 and max_inflate<.00002
                row={'lod':lod,'sail':i,'material':material,'vertices':len(positions),'maxFurlErrorMeters':max_furl,'maxInflateErrorMeters':max_inflate,'pass':passed,'glbSha256':digest}
                results.append(row)
                if not passed:failures.append(row)
    report={'pass':not failures,'checks':len(results),'failures':failures,'results':results,'toolSha256':sha(Path(__file__)),'scope':'Per-vertex declared shape-key displacement for three LODs, three sails and four material primitives; no physical clearance, runtime animation, GPU or art acceptance.'}
    a.output.parent.mkdir(parents=True,exist_ok=True)
    with a.output.open('x',encoding='utf-8') as f:json.dump(report,f,indent=2)
    print('HERO_R12_MORPH checks=',len(results),' failures=',len(failures))
    if failures:print(json.dumps(failures,indent=2))
    return 1 if failures else 0

if __name__=='__main__':raise SystemExit(main())
