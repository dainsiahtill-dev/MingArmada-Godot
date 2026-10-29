"""Non-destructively archive R12 raw Blender exports for reproducible audits."""
import hashlib,json,shutil
from datetime import datetime,timezone
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
EVIDENCE=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r12-author-01'
TEMP=ROOT/'Temp/hero-fuchuan-r12/r12-author-01'
ARCHIVE=ROOT/'assets/production/hero-fuchuan-blender/r12-author-01-intermediates'

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    rows=[]
    if ARCHIVE.exists() or (EVIDENCE/'r12-author-mirror-01.json').exists():raise FileExistsError('fresh archive and receipt required')
    for lod in range(3):
        source=TEMP/f'fuchuan-lod{lod}.glb';receipt=json.loads((EVIDENCE/f'blender-lod{lod}.json').read_text(encoding='utf-8'))
        if not source.is_file() or sha(source)!=receipt['candidateRawSha256']:raise ValueError('author raw GLB hash mismatch')
        rows.append((lod,source,ARCHIVE/source.name,receipt['candidateRawSha256']))
    ARCHIVE.mkdir(parents=True,exist_ok=False)
    for lod,source,destination,expected in rows:
        with source.open('rb') as s,destination.open('xb') as t:shutil.copyfileobj(s,t,1024*1024)
        if sha(destination)!=expected or sha(source)!=expected:raise ValueError('mirror mismatch')
    report={'createdUtc':datetime.now(timezone.utc).isoformat(),'scope':'Exact author intermediates, non-sail geometry remains LOD0; not shippable',
            'files':[{'lod':i,'source':str(s.relative_to(ROOT)),'archive':str(d.relative_to(ROOT)),'sha256':h} for i,s,d,h in rows]}
    with (EVIDENCE/'r12-author-mirror-01.json').open('x',encoding='utf-8') as f:json.dump(report,f,indent=2)
    with (ARCHIVE/'README.md').open('x',encoding='utf-8') as f:f.write('# R12 Blender author intermediates\n\nExact preserved raw exports, not shippable lower LOD models. Non-sail geometry remains LOD0; see r12-author-mirror-01.json and independent verification in docs/production/hero-fuchuan-2026-10-26-art/r12-author-01.\n')
    print('HERO_R12_AUTHOR_MIRRORED files=3')

if __name__=='__main__':main()
