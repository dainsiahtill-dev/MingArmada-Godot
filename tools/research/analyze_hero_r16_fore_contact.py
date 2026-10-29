"""Check R16 fore-strake triangles against nearby original hull triangles."""
import hashlib,json
from pathlib import Path
import numpy as np
from hero_r10_triangle_distance import surface_distance
ROOT=Path(__file__).resolve().parents[2];DIR=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r16-blockout-01'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    source=DIR/'FORE-CONTACT-TRIANGLES.json';process=DIR/'fore-extract-process.json';out=DIR/'FORE-CONTACT.json'
    if out.exists():raise FileExistsError('fresh output required')
    d=json.loads(source.read_text(encoding='utf8'));p=json.loads(process.read_text(encoding='utf8'))
    if not p['success'] or not d['sourceUnchanged'] or d['candidateSha256']!=p['candidateSha256']:raise ValueError('invalid extraction')
    h=np.asarray(d['hullTriangles'],dtype=np.float64);rows=[]
    for side,item in d['walls'].items():
        r=surface_distance(np.asarray(item['triangles'],dtype=np.float64),h,1e-5)
        rows.append({'side':side,'wallTriangles':len(item['triangles']),'hullTriangles':len(h),'minimumMeters':r['minimumMeters'],
            'nearPairs':len(r['nearPairs']),'strictTransversePairs':len(r['transversePairs'])})
    report={'sourceSha256':sha(source),'processSha256':sha(process),'toolSha256':sha(Path(__file__)),'candidateSha256':d['candidateSha256'],'rows':rows,
        'scope':'Floating-point triangle test against filtered original hull, rest pose only; strict crossings are positive evidence, count does not establish penetration volume.'}
    with out.open('x',encoding='utf8') as f:json.dump(report,f,indent=2)
    print('HERO_R16_FORE_CONTACT',rows)
if __name__=='__main__':main()
