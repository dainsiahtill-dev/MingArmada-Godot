"""Verify that a hero candidate changes only the authored canvas image.

The original embedded BIN remains an exact prefix. An independently appended
PNG is the only new view; all other glTF JSON and bytes must be identical.
This checks structure and byte provenance, not visual quality or gameplay.
"""
import argparse
import copy
import hashlib
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'assets/models/hero_fuchuan_v3_r7c'
TARGET = ROOT / 'assets/models/hero_fuchuan_v3_r9'
PNG = ROOT / 'assets/textures/hero_fuchuan_r9/cinnabar-hemp-sail.png'
EXPECTED_PNG_SHA = 'b4bf04b8f2cd5f5558bf63a2c533e95864d7d1b5c16368db5841540dd6695ce8'
CANDIDATE_REVISION = 'r9'


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def read_glb(path):
    raw = Path(path).read_bytes()
    if len(raw) < 28:
        raise ValueError('truncated GLB')
    magic, version, length = struct.unpack_from('<4sII', raw)
    if magic != b'glTF' or version != 2 or length != len(raw):
        raise ValueError('invalid GLB header')
    chunks = []
    pos = 12
    while pos < length:
        if pos + 8 > length:
            raise ValueError('truncated chunk header')
        size, kind = struct.unpack_from('<II', raw, pos)
        pos += 8
        if size % 4 or pos + size > length:
            raise ValueError('invalid GLB chunk')
        chunks.append((kind, raw[pos:pos + size]))
        pos += size
    if [kind for kind, _ in chunks] != [0x4e4f534a, 0x004e4942]:
        raise ValueError('requires exactly JSON then BIN')
    doc = json.loads(chunks[0][1])
    binary = chunks[1][1]
    if len(doc.get('buffers', [])) != 1 or 'uri' in doc['buffers'][0]:
        raise ValueError('requires one embedded buffer')
    declared = doc['buffers'][0]['byteLength']
    if not 0 <= len(binary) - declared <= 3 or any(binary[declared:]):
        raise ValueError('invalid buffer length or padding')
    return doc, binary, raw


def texture_references(value, path=()):
    references = []
    if isinstance(value, dict):
        for key, child in value.items():
            if key.lower().endswith('texture') and isinstance(child, dict) and 'index' in child:
                references.append((path + (key,), child['index']))
            references.extend(texture_references(child, path + (key,)))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            references.extend(texture_references(child, path + (index,)))
    return references


def canvas_selection(doc, binary):
    materials = doc['materials']
    matches = [i for i, value in enumerate(materials) if value.get('name') == 'canvas']
    if len(matches) != 1:
        raise ValueError('canvas material must be unique')
    material = matches[0]
    index = materials[material]['pbrMetallicRoughness']['baseColorTexture']['index']
    references = [(i, p) for i, m in enumerate(materials) for p, t in texture_references(m) if t == index]
    if references != [(material, ('pbrMetallicRoughness', 'baseColorTexture'))]:
        raise ValueError('canvas texture is shared or referenced by another channel')
    textures = doc['textures']
    image = textures[index]['source']
    if [i for i, texture in enumerate(textures) if texture.get('source') == image] != [index]:
        raise ValueError('canvas image is shared by another texture')
    data = doc['images'][image]
    if data.get('mimeType') != 'image/png' or 'uri' in data:
        raise ValueError('canvas image must be embedded PNG')
    view_index = data['bufferView']
    if sum(1 for entry in doc['images'] if entry.get('bufferView') == view_index) != 1:
        raise ValueError('canvas view is shared with another image')
    view = doc['bufferViews'][view_index]
    if view.get('buffer', 0) != 0 or any(k in view for k in ('byteStride', 'target', 'extensions')):
        raise ValueError('unsupported canvas buffer view')
    start, size = view.get('byteOffset', 0), view['byteLength']
    if start < 0 or size <= 0 or start + size > len(binary):
        raise ValueError('canvas view exceeds binary')
    for i, other in enumerate(doc['bufferViews']):
        if i != view_index and other.get('buffer', 0) == 0:
            other_start = other.get('byteOffset', 0)
            if max(start, other_start) < min(start + size, other_start + other['byteLength']):
                raise ValueError('canvas view physically overlaps another view')
    if not binary[start:start + size].startswith(b'\x89PNG\r\n\x1a\n'):
        raise ValueError('original canvas is not PNG')
    nodes = sorted(n.get('name', '') for n in doc['nodes'] if 'mesh' in n and
                   any(p.get('material') == material for p in doc['meshes'][n['mesh']]['primitives']))
    if nodes != ['sail_0', 'sail_1', 'sail_2']:
        raise ValueError('canvas must belong to exactly the three sail nodes')
    return {'material': material, 'texture': index, 'image': image,
            'originalView': view_index, 'originalImageSha256': digest(binary[start:start + size]),
            'sailNodes': nodes}


def verify_delta(base, base_bin, candidate, candidate_bin, png):
    if not png.startswith(b'\x89PNG\r\n\x1a\n'):
        raise ValueError('candidate is not PNG')
    selected = canvas_selection(base, base_bin)
    if len(base_bin) % 4:
        raise ValueError('original BIN must be four-byte aligned')
    expected = copy.deepcopy(base)
    expected['buffers'][0]['byteLength'] = len(base_bin) + len(png)
    expected['images'][selected['image']]['bufferView'] = len(base['bufferViews'])
    expected['images'][selected['image']]['name'] = 'cinnabar-hemp-sail'
    expected['bufferViews'].append({'buffer': 0, 'byteOffset': len(base_bin), 'byteLength': len(png)})
    if candidate != expected:
        raise ValueError('candidate JSON differs beyond declared image/view/buffer changes')
    expected_binary = base_bin + png + bytes((-len(png)) % 4)
    if candidate_bin != expected_binary:
        raise ValueError('original BIN or appended PNG/padding differs')
    return {**selected, 'newView': len(base['bufferViews']), 'newImageSha256': digest(png),
            'originalBinSha256': digest(base_bin), 'originalBinUnchanged': True,
            'unchangedJsonExceptDeclaredImageAndBuffer': True}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit('fresh output required')
    results, errors = [], []
    try:
        png = PNG.read_bytes()
        if digest(png) != EXPECTED_PNG_SHA:
            raise ValueError('candidate PNG hash does not match the pre-registered input')
        for lod in range(3):
            source = BASE / f'fuchuan-lod{lod}.glb'
            target = TARGET / f'fuchuan-lod{lod}.glb'
            base, base_bin, base_raw = read_glb(source)
            result, result_bin, result_raw = read_glb(target)
            row = verify_delta(base, base_bin, result, result_bin, png)
            results.append({'lod': lod, 'source': str(source.relative_to(ROOT)),
                            'candidate': str(target.relative_to(ROOT)),
                            'sourceSha256': digest(base_raw), 'candidateSha256': digest(result_raw), **row})
    except (OSError, ValueError, KeyError, IndexError, TypeError, struct.error) as exc:
        errors.append(str(exc))
    report = {'scope': 'strict image-only GLB CPU provenance; no rendering/gameplay claim',
              'baseline': 'r7c', 'candidate': CANDIDATE_REVISION, 'candidatePngSha256': EXPECTED_PNG_SHA,
              'models': results, 'failures': errors}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x', encoding='utf8') as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    print(f'HERO_R9_TEXTURE_DELTA models={len(results)} failures={len(errors)} output={args.output}')
    for error in errors:
        print('FAIL:', error)
    raise SystemExit(1 if errors else 0)


if __name__ == '__main__':
    main()
