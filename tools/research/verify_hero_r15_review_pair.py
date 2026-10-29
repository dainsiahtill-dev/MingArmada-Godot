"""Verify frozen Blender art-review files, camera parity and process receipts."""
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
DIR=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r15-blockout-01'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    target=DIR/'paired-review-audit-01.json'
    if target.exists():raise FileExistsError('fresh receipt required')
    rows=[];errors=[];audits=[]
    for variant in ['baseline','candidate']:
        base=DIR/(variant+'-review-01');process=DIR/(variant+'-review-01-process.json');log=DIR/(variant+'-review-01-process.log');report=base/'BLENDER_REVIEW.json'
        p=json.loads(process.read_text(encoding='utf8'));r=json.loads(report.read_text(encoding='utf8'));source=ROOT/r['source']
        checks={'exit0':p.get('exitCode')==0,'processValid':p.get('valid') is True,'reportHash':sha(report)==p.get('reportSHA256'),'sourceHash':sha(source)==r.get('sourceSHA256'),'sourceUnchanged':r.get('sourceUnchanged') is True,'rendererCPU':r.get('renderer')=='Cycles24samples CPU','threeImages':len(r.get('images',[]))==3}
        for pic in r.get('images',[]):
            image=ROOT/pic['path'];checks['image-'+image.stem]=sha(image)==pic['sha256']
        if not all(checks.values()):errors.append(variant+' invalid receipt or hash')
        rows.append({'variant':variant,'checks':checks,'processSha256':sha(process),'logSha256':sha(log),'sourceSha256':sha(source),'cameras':[{k:q[k] for k in ['eye','target','orthoScale']} for q in r['images']]})
    if rows[0]['cameras']!=rows[1]['cameras']:errors.append('camera settings differ')
    author=json.loads((DIR/'author.json').read_text(encoding='utf8'));audit=json.loads((DIR/'reopen-audit-01.json').read_text(encoding='utf8'))
    if author.get('candidateBlendSha256')!=rows[1]['sourceSha256'] or audit.get('candidateSha256')!=rows[1]['sourceSha256'] or not audit.get('pass'):errors.append('author or reopened audit mismatch')
    data={'pass':not errors,'errors':errors,'images':rows,'scope':'Two same-camera same-script CPU Blender static reviews. Not a Godot render, animated play or collision acceptance.'}
    with target.open('x',encoding='utf8') as f:json.dump(data,f,indent=2)
    print('HERO_R15_REVIEW_PAIR pass=',data['pass'],'errors=',errors)
    return 0 if not errors else 1
if __name__=='__main__':raise SystemExit(main())
