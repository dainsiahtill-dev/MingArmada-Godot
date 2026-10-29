"""Compare preselected actual R9b/R15c top-rail/post triangle surfaces."""
import hashlib,json
from pathlib import Path
import numpy as np
from hero_r10_triangle_distance import surface_distance
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r15c-baseline-rails-01'
DIR=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r15c-blockout-01'
CAND=DIR/'candidate-rail-components-01'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    output=DIR/'JOIN-COMPARISON.json'
    if output.exists():raise FileExistsError('fresh output required')
    inputs=[BASE/'RAIL-COMPONENTS.json',BASE/'JOIN-BASELINE.json',BASE/'process.json',CAND/'RAIL-COMPONENTS.json',CAND/'process.json',DIR/'reopen-audit-01.json']
    old,prior,oldproc,new,newproc,audit=[json.loads(p.read_text(encoding='utf8')) for p in inputs]
    if not oldproc['success'] or not newproc['success'] or not audit['pass']:raise ValueError('audit or extraction failed')
    if old['sourceSha256']!=audit['baselineSha256'] or new['sourceSha256']!=audit['candidateSha256']:raise ValueError('wrong source identity')
    oc={v['id']:v for v in old['components']};nc={v['id']:v for v in new['components']}
    if set(oc)!=set(nc) or len(nc)!=168:raise ValueError('component identity changed')
    rows=[]
    for p in prior['rows']:
        i,j=p['railComponent'],p['postComponent']
        r=surface_distance(np.asarray(nc[i]['triangles'],dtype=np.float64),np.asarray(nc[j]['triangles'],dtype=np.float64),1e-5)
        rows.append({'zone':p['zone'],'side':p['side'],'railComponent':i,'postComponent':j,
            'baselineMinimumMeters':p['minimumMeters'],'candidateMinimumMeters':r['minimumMeters'],
            'gapIncreaseMeters':max(0.,r['minimumMeters']-p['minimumMeters']),
            'baselineTransversePairs':p['transversePairs'],'candidateTransversePairs':len(r['transversePairs'])})
    result={'inputSha256':{p.relative_to(ROOT).as_posix():sha(p) for p in inputs},'toolSha256':sha(Path(__file__)),
        'baselineSha256':old['sourceSha256'],'candidateSha256':new['sourceSha256'],'componentCount':len(nc),'pairCount':len(rows),
        'maxGapIncreaseMeters':max(r['gapIncreaseMeters'] for r in rows),'overOneCentimeter':sum(r['gapIncreaseMeters']>.01 for r in rows),'rows':rows,
        'scope':'Only 26 selected rail/post surface pairs at a static pose, using float triangle distances; no general intersection, visual or animation acceptance.'}
    with output.open('x',encoding='utf8') as f:json.dump(result,f,indent=2)
    print('HERO_R15C_JOIN_COMPARE pairs=',len(rows),'maxGap=',result['maxGapIncreaseMeters'],'overOneCentimeter=',result['overOneCentimeter'])
if __name__=='__main__':main()
