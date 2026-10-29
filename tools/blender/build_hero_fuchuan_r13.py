"""Author R13 from R9b and package three image-only candidates; no promotion."""
import hashlib
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
import build_hero_fuchuan_r9 as core

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'assets/models/hero_fuchuan_v3_r9b'
TARGET = ROOT / 'assets/models/hero_fuchuan_v3_r13'
SOURCE = ROOT / 'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r9b.blend'
DEST = ROOT / 'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r13.blend'
PNG = ROOT / 'assets/textures/hero_fuchuan_r13/weathered-cinnabar-hemp.png'
BLENDER = core.BLENDER
SCRIPT = ROOT / 'tools/blender/create_hero_r13_blend.py'
EVIDENCE = ROOT / 'docs/research/evidence/hero-fuchuan/r13-cloth-20261027'
SOURCE_SHA = '2961f7f28d31cfc71a16638fbd634b4245912adb1fcf79bc55bfc5d00722d2e8'
PNG_SHA = '0a25b0a8833eb81e8b03708f113e6e10238fec03c3adeb4b72143333917c8c3b'
LOD_SHA = ['89f3498555d73c981c35f28831330aeb4d3700d8e8838a0617af2867e5bd555e',
           '9538ace6fcdd4df672bf5413f015413daadb10786ddb5dc39a014d1fda700032',
           '4881423c772747be3a6371e7c572c23eb343ca32290c5c1c6fc8708253e4126b']


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    if TARGET.exists() or DEST.exists() or EVIDENCE.exists():
        raise RuntimeError('fresh target, Blend and evidence directories required')
    originals = [BASE / ('fuchuan-lod%d.glb' % i) for i in range(3)]
    if sha(PNG) != PNG_SHA or sha(SOURCE) != SOURCE_SHA or [sha(p) for p in originals] != LOD_SHA:
        raise RuntimeError('pre-registered R9b baseline or R13 image changed')
    png = PNG.read_bytes()
    packaged = []
    for path in originals:
        doc, binary, _ = core.read_glb(path)
        packaged.append(core.make_candidate(doc, binary, png))
    EVIDENCE.mkdir(parents=True)
    receipt = EVIDENCE / 'blender-r13.json'
    log = EVIDENCE / 'blender-r13.log'
    command = [str(BLENDER),'--background',str(SOURCE),'--python-exit-code','1','--python',str(SCRIPT),
               '--',str(PNG),str(DEST),str(receipt)]
    started = datetime.now(timezone.utc).isoformat()
    proc = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
    with log.open('xb') as stream: stream.write(proc.stdout)
    marker = b'HERO_R13_BLEND_SAVED '
    accepted = proc.returncode == 0 and proc.stdout.count(marker) == 1 and receipt.is_file() and DEST.is_file()
    process = {'command':command,'startedUtc':started,'finishedUtc':datetime.now(timezone.utc).isoformat(),
               'exitCode':proc.returncode,'markerCount':proc.stdout.count(marker),'accepted':accepted,
               'logSha256':sha(log),'blenderSha256':sha(BLENDER),'scriptSha256':sha(SCRIPT)}
    with (EVIDENCE / 'blender-r13.process.json').open('x',encoding='utf8') as stream:
        json.dump(process,stream,ensure_ascii=False,indent=2)
    if not accepted: raise RuntimeError('Blender failed; evidence retained')
    if sha(PNG) != PNG_SHA or sha(SOURCE) != SOURCE_SHA or [sha(p) for p in originals] != LOD_SHA:
        raise RuntimeError('source changed during Blender authoring')
    TARGET.mkdir(parents=True)
    rows = []
    for lod, (path, (binary, selected)) in enumerate(zip(originals,packaged,strict=True)):
        output = TARGET / ('fuchuan-lod%d.glb' % lod)
        with output.open('xb') as stream: stream.write(binary)
        before, before_bin, _ = core.read_glb(path)
        after, after_bin, _ = core.read_glb(output)
        verified = core.verify_delta(before,before_bin,after,after_bin,png)
        rows.append({'lod':lod,'source':str(path.relative_to(ROOT)),'sourceSha256':sha(path),
                     'candidate':str(output.relative_to(ROOT)),'candidateSha256':sha(output),
                     'oldImageSha256':selected['originalImageSha256'],'newImageSha256':verified['newImageSha256']})
    if sha(SOURCE) != SOURCE_SHA or [sha(p) for p in originals] != LOD_SHA:
        raise RuntimeError('baseline changed during packaging')
    manifest = {'asset':'hero-fuchuan-v3-r13','baseline':'hero-fuchuan-v3-r9b',
                'authorBlend':str(DEST.relative_to(ROOT)),'authorBlendSha256':sha(DEST),
                'sourceBlend':str(SOURCE.relative_to(ROOT)),'sourceBlendSha256':SOURCE_SHA,
                'png':str(PNG.relative_to(ROOT)),'pngSha256':PNG_SHA,'lods':rows,
                'construction':'Blender author blend; R9b GLB bytes retained and PNG appended as canvas image view, not a Blender GLB export',
                'formalProviderUnchanged':True,'scope':'CPU candidate; no GPU, visual, performance or gameplay acceptance'}
    with (TARGET / 'manifest.json').open('x',encoding='utf8') as stream:
        json.dump(manifest,stream,ensure_ascii=False,indent=2)
    print('HERO_R13_BUILD_COMPLETE lods=3 source_unchanged=true',flush=True)


if __name__ == '__main__': main()
