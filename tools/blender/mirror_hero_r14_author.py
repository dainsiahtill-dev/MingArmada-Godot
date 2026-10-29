"""Archive R14 raw Blender files byte-for-byte; never overwrite evidence."""
import hashlib,json,shutil
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
EVIDENCE=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r14-author-01'
TEMP=ROOT/'Temp/hero-fuchuan-r14/r14-author-01'
ARCHIVE=ROOT/'assets/production/hero-fuchuan-blender/r14-author-01-intermediates'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    if ARCHIVE.exists() or (EVIDENCE/'r14-author-mirror-01.json').exists():raise FileExistsError('fresh destination required')
    rows=[]
    for i in range(3):
        path=TEMP/f'fuchuan-lod{i}.glb';receipt=json.loads((EVIDENCE/f'blender-lod{i}.json').read_text(encoding='utf-8'))
        if sha(path)!=receipt['candidateRawSha256']:raise ValueError('raw export differs from author receipt')
        rows.append((i,path,ARCHIVE/path.name,receipt['candidateRawSha256']))
    ARCHIVE.mkdir(parents=True,exist_ok=False)
    for i,source,target,digest in rows:
        with source.open('rb') as a,target.open('xb') as b:shutil.copyfileobj(a,b,1024*1024)
        if sha(source)!=digest or sha(target)!=digest:raise ValueError('mirror hash differs')
    report={'createdUtc':datetime.now(timezone.utc).isoformat(),'scope':'Raw Blender exports; all non-coaming geometry remains LOD0, not shippable','files':[{'lod':i,'source':str(s.relative_to(ROOT)),'archive':str(t.relative_to(ROOT)),'sha256':h} for i,s,t,h in rows]}
    with (EVIDENCE/'r14-author-mirror-01.json').open('x',encoding='utf-8') as f:json.dump(report,f,indent=2)
    with (ARCHIVE/'README.md').open('x',encoding='utf-8') as f:f.write('# R14 Blender author intermediates\n\nRaw exports preserve LOD0 original body and are not shippable LOD models. See the R14 author process and mirror receipts.\n')
    print('HERO_R14_AUTHOR_MIRRORED files=3')
if __name__=='__main__':main()
