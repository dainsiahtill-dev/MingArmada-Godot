"""Independently compare R13 to R9b under the image-only GLB contract."""
import hashlib
import json
import sys
from pathlib import Path
import verify_hero_r9_texture_delta as check

root=Path(__file__).resolve().parents[2]
base=root/'assets/models/hero_fuchuan_v3_r9b'
target=root/'assets/models/hero_fuchuan_v3_r13'
png=root/'assets/textures/hero_fuchuan_r13/weathered-cinnabar-hemp.png'
output=root/'docs/research/evidence/hero-fuchuan/r13-cloth-20261027/r13-independent-delta.json'
if output.exists(): raise SystemExit('fresh output required')
data=png.read_bytes(); sha=lambda v:hashlib.sha256(v).hexdigest()
if sha(data)!='0a25b0a8833eb81e8b03708f113e6e10238fec03c3adeb4b72143333917c8c3b':
    raise SystemExit('candidate image SHA mismatch')
rows=[];errors=[]
for lod in range(3):
    try:
        a,ab,ar=check.read_glb(base/('fuchuan-lod%d.glb'%lod))
        b,bb,br=check.read_glb(target/('fuchuan-lod%d.glb'%lod))
        entry=check.verify_delta(a,ab,b,bb,data)
        rows.append({'lod':lod,'baselineSha256':sha(ar),'candidateSha256':sha(br),**entry})
    except (OSError,ValueError,KeyError,IndexError,TypeError) as exc:
        errors.append('LOD%d: %s'%(lod,exc))
report={'baseline':'r9b','candidate':'r13','pngSha256':sha(data),'models':rows,'failures':errors,
        'scope':'exact image-only JSON and original BIN prefix; no GPU or gameplay claim'}
with output.open('x',encoding='utf8') as stream:json.dump(report,stream,ensure_ascii=False,indent=2)
print('HERO_R13_TEXTURE_DELTA models=%d failures=%d'%(len(rows),len(errors)))
sys.exit(1 if errors else 0)
