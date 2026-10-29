"""Snapshot the exact R14b pre-registration pinned by its author receipt."""
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BRIEF=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/R14-DECK-HATCH-BRIEF.md'
DIR=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r14b-author-01'
def main():
    raw=BRIEF.read_bytes();digest=hashlib.sha256(raw).hexdigest()
    receipt=json.loads((DIR/'blender-lod0.json').read_text(encoding='utf-8'))
    expected=receipt['baselineSources']['docs/production/hero-fuchuan-2026-10-26-art/R14-DECK-HATCH-BRIEF.md']
    if digest!=expected:raise ValueError('brief changed since author receipt')
    output=DIR/'r14b-preregistration.md';proof=DIR/'r14b-brief-snapshot-01.json'
    if output.exists() or proof.exists():raise FileExistsError('fresh output required')
    with output.open('xb') as f:f.write(raw)
    with proof.open('x',encoding='utf-8') as f:json.dump({'snapshotSha256':digest,'authorReceiptSha256':expected,'scope':'Exact R14b brief at author freeze, before any subsequent results.'},f,indent=2)
    print('HERO_R14B_BRIEF_SNAPSHOT sha256='+digest)
if __name__=='__main__':main()
