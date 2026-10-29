"""Locate the strict R16 fore/hull crossing samples relative to the hull wall top."""
import hashlib,json
from pathlib import Path
import numpy as np
from hero_r10_triangle_distance import surface_distance
ROOT=Path(__file__).resolve().parents[2];DIR=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r16-blockout-01'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def sheer(z):return 1.92+1.8*(max(0,z)/16)**3.2+.7*(max(0,-z)/16)**2.6
def main():
    source=DIR/'FORE-CONTACT-TRIANGLES.json';target=DIR/'FORE-CONTACT-HEIGHT.json'
    if target.exists():raise FileExistsError('fresh output required')
    d=json.loads(source.read_text(encoding='utf8'));h=np.asarray(d['hullTriangles'],dtype=np.float64);rows=[]
    for side,item in d['walls'].items():
        a=np.asarray(item['triangles'],dtype=np.float64);r=surface_distance(a,h,1e-5)
        ids=sorted({i for i,j in r['transversePairs']});centers=a[ids].mean(axis=1)
        heights=[float(v[1]-sheer(v[2])-.94) for v in centers]
        rows.append({'side':side,'crossedWallTriangleCount':len(ids),'centroidHeightAboveOldWallTopMinMeters':min(heights) if heights else None,
            'centroidHeightAboveOldWallTopMaxMeters':max(heights) if heights else None,'centroidsMoreThan10cmAboveTop':sum(v>.1 for v in heights),
            'crossingPairCount':len(r['transversePairs'])})
    result={'sourceSha256':sha(source),'candidateSha256':d['candidateSha256'],'toolSha256':sha(Path(__file__)),'rows':rows,
        'scope':'Wall triangle centroid location is an approximate locator; not exact crossing point or penetration depth.'}
    with target.open('x',encoding='utf8') as f:json.dump(result,f,indent=2)
    print('HERO_R16_FORE_CROSSING_HEIGHT',rows)
if __name__=='__main__':main()
