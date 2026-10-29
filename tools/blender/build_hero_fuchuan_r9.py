"""Build independent R9 authoring blend and strictly bounded image-only GLBs."""
import copy
import hashlib
import json
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/research'))
from verify_hero_r9_texture_delta import BASE, PNG, TARGET, EXPECTED_PNG_SHA, canvas_selection, read_glb, verify_delta

BLENDER = Path('C:/Tools/blender-5.4.0-alpha+main.fbe82a461016-windows.amd64-release/blender.exe')
SOURCE_BLEND = ROOT / 'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r7c.blend'
NEW_BLEND = ROOT / 'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r9.blend'
BLENDER_SCRIPT = ROOT / 'tools/blender/create_hero_r9_blend.py'
EVIDENCE = ROOT / 'docs/research/evidence/hero-fuchuan/r9-cinnabar-20261027'
RECEIPT = EVIDENCE / 'blender-r9.json'
LOG = EVIDENCE / 'blender-r9.log'
MANIFEST = TARGET / 'manifest.json'
SOURCE_HASHES = [
    'b87af112855cb6883faf97ec02a5eeb5fd61a5d504f204d3b3a573e73735d02d',
    'db9f01b8968f66f2a1c27c689e9a9e0cdd7f03ea27d86a9b6f2bb911872e461a',
    '16aa79cb89074879354d82402540f478e9ad5279085d2c53d7f92d579aa2291d',
]
BLEND_HASH = 'ac057d349395a5e0547ec20e382188c34ed2c6481778b5142a99c4d920045fb3'
REVISION = 'r9'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def encode_glb(doc, binary):
    json_bytes = json.dumps(doc, ensure_ascii=False, separators=(',', ':')).encode('utf8')
    json_bytes += b' ' * ((-len(json_bytes)) % 4)
    if len(binary) % 4:
        raise ValueError('GLB BIN must be padded to four bytes')
    total = 12 + 8 + len(json_bytes) + 8 + len(binary)
    return (struct.pack('<4sII', b'glTF', 2, total)
            + struct.pack('<II', len(json_bytes), 0x4e4f534a) + json_bytes
            + struct.pack('<II', len(binary), 0x004e4942) + binary)


def make_candidate(base, binary, png):
    selected = canvas_selection(base, binary)
    candidate = copy.deepcopy(base)
    candidate['buffers'][0]['byteLength'] = len(binary) + len(png)
    candidate['images'][selected['image']]['bufferView'] = len(base['bufferViews'])
    candidate['images'][selected['image']]['name'] = 'cinnabar-hemp-sail'
    candidate['bufferViews'].append({'buffer': 0, 'byteOffset': len(binary), 'byteLength': len(png)})
    appended = binary + png + bytes((-len(png)) % 4)
    # The independent contract checker compares the entire JSON and BIN.
    verify_delta(base, binary, candidate, appended, png)
    return encode_glb(candidate, appended), selected


def main():
    destinations = [NEW_BLEND, RECEIPT, LOG, MANIFEST] + [TARGET / f'fuchuan-lod{i}.glb' for i in range(3)]
    if any(path.exists() for path in destinations):
        raise SystemExit('all candidate destinations must be fresh; no output was overwritten')
    if not BLENDER.is_file():
        raise SystemExit('configured Blender executable does not exist')
    png = PNG.read_bytes()
    if sha(png) != EXPECTED_PNG_SHA or sha(SOURCE_BLEND.read_bytes()) != BLEND_HASH:
        raise SystemExit('pre-registered PNG or Blender source hash mismatch')
    originals = []
    for lod in range(3):
        path = BASE / f'fuchuan-lod{lod}.glb'
        doc, binary, raw = read_glb(path)
        if sha(raw) != SOURCE_HASHES[lod]:
            raise SystemExit(f'pre-registered source LOD{lod} hash mismatch')
        candidate, selected = make_candidate(doc, binary, png)
        originals.append((path, candidate, selected))

    EVIDENCE.mkdir(parents=True, exist_ok=True)
    result = subprocess.run([str(BLENDER), '--background', str(SOURCE_BLEND), '--python', str(BLENDER_SCRIPT),
                             '--', str(PNG), str(NEW_BLEND), str(RECEIPT), EXPECTED_PNG_SHA],
                            cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf8', errors='replace')
    with LOG.open('x', encoding='utf8') as stream:
        stream.write(result.stdout)
    if result.returncode != 0 or result.stdout.count('HERO_R9_BLEND_SAVED ') != 1 or not RECEIPT.is_file() or not NEW_BLEND.is_file():
        raise SystemExit('Blender candidate authoring failed; log and any generated output retained')
    if sha(SOURCE_BLEND.read_bytes()) != BLEND_HASH or sha(PNG.read_bytes()) != EXPECTED_PNG_SHA:
        raise SystemExit('source blend or generated PNG changed during Blender process')
    TARGET.mkdir(parents=True, exist_ok=True)
    rows = []
    for lod, (source, candidate, selected) in enumerate(originals):
        if sha(source.read_bytes()) != SOURCE_HASHES[lod]:
            raise SystemExit(f'source LOD{lod} changed before candidate write')
        destination = TARGET / f'fuchuan-lod{lod}.glb'
        with destination.open('xb') as stream:
            stream.write(candidate)
        doc, binary, raw = read_glb(destination)
        before_doc, before_binary, _ = read_glb(source)
        verify_delta(before_doc, before_binary, doc, binary, png)
        rows.append({'lod': lod, 'source': str(source.relative_to(ROOT)), 'sourceSha256': SOURCE_HASHES[lod],
                     'candidate': str(destination.relative_to(ROOT)), 'candidateSha256': sha(raw),
                     'canvasImage': selected['image'], 'oldImageSha256': selected['originalImageSha256']})
    if [sha(row[0].read_bytes()) for row in originals] != SOURCE_HASHES:
        raise SystemExit('source model changed during build')
    manifest = {'asset': 'hero-fuchuan-v3-' + REVISION, 'baseline': 'hero-fuchuan-v3-r7c',
                'authorBlend': str(NEW_BLEND.relative_to(ROOT)), 'authorBlendSha256': sha(NEW_BLEND.read_bytes()),
                'sourceBlend': str(SOURCE_BLEND.relative_to(ROOT)), 'sourceBlendSha256': BLEND_HASH,
                'png': str(PNG.relative_to(ROOT)), 'pngSha256': EXPECTED_PNG_SHA,
                'construction': 'Blender author blend; R7c GLB packaging appends original image bytes and redirects only canvas image view; not a fresh Blender GLB export',
                'lods': rows, 'formalProviderUnchanged': True,
                'scope': 'candidate CPU provenance only, not art, GPU, performance or gameplay acceptance'}
    with MANIFEST.open('x', encoding='utf8') as stream:
        json.dump(manifest, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    print('HERO_R9_BUILD_COMPLETE revision=' + REVISION + ' lods=3 canvas=1 source_sha_unchanged=true')


if __name__ == '__main__':
    main()
