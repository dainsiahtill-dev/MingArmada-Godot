"""Discrete source mesh triangle proximity for new and remaining rail pieces."""
import hashlib,json
from pathlib import Path
import numpy as np
from hero_r10_triangle_distance import surface_distance
ROOT=Path(__file__).resolve().parents[2];DIR=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r15b-blockout-01'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    source=DIR/'join-triangles-01.json';receipt=DIR/'join-extract-01-process.json';target=DIR/'join-surface-analysis-01.json'
    if target.exists():raise FileExistsError('fresh output required')
    p=json.loads(receipt.read_text(encoding='utf8'));d=json.loads(source.read_text(encoding='utf8'))
    if not p['success'] or p['exitCode']!=0 or p['outputSha256']!=sha(source) or p['sourceSha256']!=d['sourceSha256']:raise ValueError('extraction receipt invalid')
    rail=np.asarray(d['triangles']['bulwark_rails'],dtype=np.float64);rows=[]
    for name in ['r15b_foreworks_port','r15b_foreworks_starboard','r15b_sternrail_port','r15b_sternrail_starboard']:
        geom=np.asarray(d['triangles'][name],dtype=np.float64);x=surface_distance(geom,rail,1e-6)
        row={'node':name,'minimumMeters':x['minimumMeters'],'nearPairCount':len(x['nearPairs']),'transversePairCount':len(x['transversePairs']),'narrowPhasePairs':x['narrowPhasePairs'],'targetTriangles':len(geom),'originalRailTriangles':len(rail)}
        rows.append(row);print('HERO_R15B_JOIN',name,'minimum=',row['minimumMeters'],'near=',row['nearPairCount'],'transverse=',row['transversePairCount'])
    with target.open('x',encoding='utf8') as f:json.dump({'rows':rows,'sourceTrianglesSha256':sha(source),'extractionProcessSha256':sha(receipt),'toolSha256':sha(Path(__file__)),'scope':'Discrete floating-point triangle proximity, with positive strict transverse crossing evidence only; nonzero near pairs include intended connections, and no dynamic or visual acceptance.'},f,indent=2)
if __name__=='__main__':main()
