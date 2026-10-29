"""Locate already-observed strict triangle crossings for art diagnosis."""
import json,hashlib
from pathlib import Path
import numpy as np
from hero_r10_triangle_distance import surface_distance
ROOT=Path(__file__).resolve().parents[2];DIR=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r15b-blockout-01'
def main():
    src=DIR/'join-triangles-01.json';out=DIR/'join-crossing-locations-01.json'
    if out.exists():raise FileExistsError('fresh output required')
    d=json.loads(src.read_text(encoding='utf8'));rail=np.asarray(d['triangles']['bulwark_rails'],dtype=np.float64);rows=[]
    posts=np.asarray([-15.6,-14.633333,-13.666667,-12.7,-11.733333,-10.766667,-9.8])
    for name in ['r15b_foreworks_port','r15b_foreworks_starboard','r15b_sternrail_port','r15b_sternrail_starboard']:
        geom=np.asarray(d['triangles'][name],dtype=np.float64);r=surface_distance(geom,rail,1e-6);pairs=np.asarray(r['transversePairs'],dtype=np.int64)
        zs=((geom[pairs[:,0]].mean(axis=1)+rail[pairs[:,1]].mean(axis=1))*.5)[:,2] if len(pairs) else np.asarray([])
        near_post=np.min(np.abs(zs[:,None]-posts[None,:]),axis=1)<.15 if len(zs) and 'stern' in name else np.asarray([],dtype=bool)
        row={'node':name,'strictCrossings':len(pairs),'zRange':[float(zs.min()),float(zs.max())] if len(zs) else None,
             'zMedian':float(np.median(zs)) if len(zs) else None,'sternWithin15cmOfPostOrEnd':int(near_post.sum()) if len(near_post) else None,
             'sternOutside15cmOfPostOrEnd':int((~near_post).sum()) if len(near_post) else None}
        rows.append(row);print('HERO_R15B_CROSSING_LOCATION',json.dumps(row))
    with out.open('x',encoding='utf8') as f:json.dump({'rows':rows,'trianglesSha256':hashlib.sha256(src.read_bytes()).hexdigest(),'toolSha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'scope':'Centroid-based crossing localization, not exact intersection coordinates; discrete static model, not a penetration or dynamic physics proof.'},f,indent=2)
if __name__=='__main__':main()
