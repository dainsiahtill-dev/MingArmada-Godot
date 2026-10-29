"""Measure source top-rail/post surface distances before designing R15c."""
import hashlib,json
from pathlib import Path
import numpy as np
from hero_r10_triangle_distance import surface_distance
ROOT=Path(__file__).resolve().parents[2];DIR=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r15c-baseline-rails-01'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    source=DIR/'RAIL-COMPONENTS.json';process=DIR/'process.json';out=DIR/'JOIN-BASELINE.json'
    if out.exists():raise FileExistsError('fresh output required')
    d=json.loads(source.read_text(encoding='utf8'));p=json.loads(process.read_text(encoding='utf8'))
    if not p['success'] or d['sourceSha256']!=p['sourceSha256']:raise ValueError('baseline process invalid')
    c={x['id']:x for x in d['components']}
    pairs=[('bow','starboard',1254,[864,896,928,960,992,1024]),('bow','port',3118,[2728,2760,2792,2824,2856,2888]),
           ('aft','starboard',1738,[1452,1468,1484,1500,1516,1532,1548]),('aft','port',3602,[3316,3332,3348,3364,3380,3396,3412])]
    rows=[]
    for zone,side,rail,posts in pairs:
        at=np.asarray(c[rail]['triangles'],dtype=np.float64)
        for post in posts:
            bt=np.asarray(c[post]['triangles'],dtype=np.float64);r=surface_distance(at,bt,1e-5)
            rows.append({'zone':zone,'side':side,'railComponent':rail,'postComponent':post,'postZ':(c[post]['min'][2]+c[post]['max'][2])*.5,
                         'minimumMeters':r['minimumMeters'],'nearPairs':len(r['nearPairs']),'transversePairs':len(r['transversePairs']),
                         'topologicallySeparate':rail!=post})
    report={'sourceSha256':d['sourceSha256'],'inputSha256':sha(source),'toolSha256':sha(Path(__file__)),'componentCount':len(d['components']),'rows':rows,
            'scope':'Selected top-rail/post static triangle pairs only; 1e-5m near test and positive transverse crossings are floating-point estimates, not a weld or dynamic guarantee.'}
    with out.open('x',encoding='utf8') as f:json.dump(report,f,indent=2)
    print('HERO_R15C_BASELINE_JOINS pairs=',len(rows),' separated=',sum(r['topologicallySeparate'] for r in rows),'zero=',sum(r['minimumMeters']<=1e-5 for r in rows),
          'transverse=',sum(r['transversePairs']>0 for r in rows),'maxDistance=',max(r['minimumMeters'] for r in rows))
if __name__=='__main__':main()
