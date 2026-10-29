"""Recover the exact pre-R14b brief prefix pinned by the R14 author receipt."""
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BRIEF=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/R14-DECK-HATCH-BRIEF.md'
DIR=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r14-author-01'
def main():
    raw=BRIEF.read_bytes();mark=raw.index(b'## R14 ');prefix=raw[:mark-1]
    receipt=json.loads((DIR/'blender-lod0.json').read_text(encoding='utf-8'))
    expected=receipt['baselineSources']['docs/production/hero-fuchuan-2026-10-26-art/R14-DECK-HATCH-BRIEF.md']
    digest=hashlib.sha256(prefix).hexdigest()
    if digest!=expected:raise ValueError('pre-R14b prefix does not equal original author hash')
    output=DIR/'r14-original-preregistration.md';proof=DIR/'r14-brief-snapshot-01.json'
    if output.exists() or proof.exists():raise FileExistsError('fresh output required')
    with output.open('xb') as f:f.write(prefix)
    with proof.open('x',encoding='utf-8') as f:json.dump({'sourceBriefCurrentSha256':hashlib.sha256(raw).hexdigest(),'snapshotSha256':digest,'authorReceiptSha256':expected,'scope':'Exact prefix verified against original R14 author receipt after R14b section was appended.'},f,indent=2)
    print('HERO_R14_BRIEF_SNAPSHOT sha256='+digest)
if __name__=='__main__':main()
