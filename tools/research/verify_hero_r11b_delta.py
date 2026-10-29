"""Strict R9b→R11b canvas COLOR_0 verification; no rendering claim.

Every non-target byte, including original GLB header/JSON and entire BIN
outside three exclusive COLOR_0 float32 spans, must remain identical.
"""
import argparse
import hashlib
import json
import math
import struct
from pathlib import Path
from verify_hero_r9_texture_delta import read_glb

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'assets/models/hero_fuchuan_v3_r9b'
TARGET = ROOT / 'assets/models/hero_fuchuan_v3_r11b'
COEFFICIENTS = (
    ((1.04,0.96,0.88),(1.10,1.03,0.93),(1.04,1.11,1.00),(0.95,1.04,0.91),(0.90,0.96,1.01)),
    ((0.99,1.10,1.02),(0.94,1.12,1.04),(1.02,1.07,0.90),(1.10,0.98,0.88),(1.01,0.93,0.96)),
    ((0.92,1.01,1.08),(1.01,1.09,0.95),(1.11,1.00,0.90),(1.02,0.91,0.98),(0.94,0.99,1.04)),
)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def accessor_uses(doc, wanted):
    uses = []
    for mi, mesh in enumerate(doc.get('meshes', [])):
        for pi, primitive in enumerate(mesh.get('primitives', [])):
            if primitive.get('indices') == wanted:
                uses.append(('indices', mi, pi))
            for name, index in primitive.get('attributes', {}).items():
                if index == wanted: uses.append(('attribute', mi, pi, name))
            for ti, target in enumerate(primitive.get('targets', [])):
                for name, index in target.items():
                    if index == wanted: uses.append(('morph', mi, pi, ti, name))
    for si, skin in enumerate(doc.get('skins', [])):
        if skin.get('inverseBindMatrices') == wanted: uses.append(('skin', si))
    for ai, animation in enumerate(doc.get('animations', [])):
        for si, sampler in enumerate(animation.get('samplers', [])):
            for key in ('input', 'output'):
                if sampler.get(key) == wanted: uses.append(('animation', ai, si, key))
    return uses


def read_accessor(doc, binary, index, width):
    item = doc['accessors'][index]
    if item.get('componentType') != 5126 or item.get('type') != f'VEC{width}' or item.get('normalized', False) or 'sparse' in item:
        raise ValueError('requires non-sparse float32 vector accessor')
    view = doc['bufferViews'][item['bufferView']]
    if view.get('buffer', 0) != 0 or 'extensions' in view:
        raise ValueError('unsupported buffer view')
    start = view.get('byteOffset', 0) + item.get('byteOffset', 0)
    stride = view.get('byteStride', width * 4)
    count = item['count']
    if start < 0 or count <= 0 or stride < width * 4 or item.get('byteOffset', 0) + (count-1)*stride + width*4 > view['byteLength'] or start + (count-1)*stride + width*4 > len(binary):
        raise ValueError('accessor exceeds its view')
    result = [struct.unpack_from('<' + 'f'*width, binary, start + i*stride) for i in range(count)]
    if any(not math.isfinite(v) for row in result for v in row):
        raise ValueError('non-finite accessor component')
    return result


def selections(doc, binary):
    mats = [i for i, mat in enumerate(doc['materials']) if mat.get('name') == 'canvas']
    if len(mats) != 1:
        raise ValueError('canvas material is not unique')
    selected = []
    for sail in range(3):
        nodes = [n for n in doc['nodes'] if n.get('name') == f'sail_{sail}' and 'mesh' in n]
        if len(nodes) != 1:
            raise ValueError('sail node missing or duplicated')
        mesh_index = nodes[0]['mesh']
        mesh = doc['meshes'][mesh_index]
        primitives = [(i, p) for i, p in enumerate(mesh['primitives']) if p.get('material') == mats[0]]
        if len(primitives) != 1:
            raise ValueError('each sail requires exactly one canvas primitive')
        primitive_index, primitive = primitives[0]
        attributes = primitive['attributes']
        color_index, uv_index, position_index = (attributes[name] for name in ('COLOR_0', 'TEXCOORD_0', 'POSITION'))
        if accessor_uses(doc, color_index) != [('attribute', mesh_index, primitive_index, 'COLOR_0')]:
            raise ValueError('canvas COLOR_0 accessor is shared or aliased')
        color = doc['accessors'][color_index]
        view_index = color['bufferView']
        if any(i != color_index and (entry.get('bufferView') == view_index or
               entry.get('sparse', {}).get('indices', {}).get('bufferView') == view_index or
               entry.get('sparse', {}).get('values', {}).get('bufferView') == view_index)
               for i, entry in enumerate(doc['accessors'])):
            raise ValueError('canvas COLOR_0 view is shared by another accessor')
        view = doc['bufferViews'][view_index]
        if color.get('byteOffset', 0) != 0 or 'min' in color or 'max' in color or 'byteStride' in view or view['byteLength'] != color['count']*12:
            raise ValueError('COLOR_0 must occupy its complete tightly packed view')
        start, size = view.get('byteOffset', 0), view['byteLength']
        for vi, other in enumerate(doc['bufferViews']):
            if vi == view_index or other.get('buffer', 0) != 0: continue
            other_start = other.get('byteOffset', 0)
            if max(start, other_start) < min(start+size, other_start+other['byteLength']):
                raise ValueError('canvas COLOR_0 view overlaps another view')
        colors = read_accessor(doc, binary, color_index, 3)
        uvs = read_accessor(doc, binary, uv_index, 2)
        positions = read_accessor(doc, binary, position_index, 3)
        if len(colors) != len(uvs) or len(colors) != len(positions):
            raise ValueError('canvas color, UV and position counts differ')
        seen = {}
        for pos, uv in zip(positions, uvs):
            if not (0.0 <= uv[0] <= 1.0 and 0.0 <= uv[1] <= 1.0):
                raise ValueError('canvas nominal UV outside 0..1')
            key = tuple(0.0 if value == 0.0 else value for value in pos)
            if key in seen and seen[key] != uv:
                raise ValueError('same canvas position has conflicting nominal UVs')
            seen[key] = uv
        selected.append({'sail': sail, 'accessor': color_index, 'view': view_index,
                         'start': start, 'size': size, 'colors': colors, 'uvs': uvs,
                         'positions': positions, 'mesh': mesh_index, 'primitive': primitive_index})
    if len({s['accessor'] for s in selected}) != 3 or len({s['view'] for s in selected}) != 3:
        raise ValueError('canvas color storage must be exclusive per sail')
    return selected


def expected_channel(original, gltf_u, gltf_v, sail):
    t = 1.0 - gltf_v
    vertical = t * 4.0
    low_t = min(int(vertical), 3)
    ft = vertical - low_t
    st = ft*ft*(3.0 - 2.0*ft)
    horizontal = gltf_u * 2.0
    low_u = min(int(horizontal), 1)
    fu = horizontal - low_u
    su = fu*fu*(3.0 - 2.0*fu)
    knots = COEFFICIENTS[sail]
    bottom = knots[low_t][low_u] + (knots[low_t][low_u+1]-knots[low_t][low_u])*su
    top = knots[low_t+1][low_u] + (knots[low_t+1][low_u+1]-knots[low_t+1][low_u])*su
    gain = bottom + (top-bottom)*st
    return struct.unpack('<f', struct.pack('<f', max(0.0, min(1.0, original*gain))))[0]


def verify_delta(base, base_bin, base_raw, candidate, candidate_bin, candidate_raw):
    if candidate != base or len(candidate_bin) != len(base_bin) or len(candidate_raw) != len(base_raw):
        raise ValueError('GLB JSON or length changed')
    bin_start = len(base_raw) - len(base_bin)
    if candidate_raw[:bin_start] != base_raw[:bin_start]:
        raise ValueError('GLB header or JSON bytes changed')
    chosen = selections(base, base_bin)
    spans = sorted((row['start'], row['start']+row['size']) for row in chosen)
    cursor = 0
    for start, end in spans:
        if start < cursor or candidate_bin[cursor:start] != base_bin[cursor:start]:
            raise ValueError('non-canvas or overlapping BIN bytes changed')
        cursor = end
    if candidate_bin[cursor:] != base_bin[cursor:]:
        raise ValueError('non-canvas trailing BIN bytes changed')
    rows = []
    for row in chosen:
        actual = read_accessor(candidate, candidate_bin, row['accessor'], 3)
        changed = 0
        gain_min, gain_max = 2.0, -1.0
        for old, uv, new in zip(row['colors'], row['uvs'], actual):
            expected = tuple(expected_channel(channel, uv[0], uv[1], row['sail']) for channel in old)
            if new != expected:
                raise ValueError(f'sail_{row["sail"]} canvas COLOR_0 differs from declared knots')
            if new != old: changed += 1
            for value in new:
                if not 0.0 <= value <= 1.0: raise ValueError('candidate color exceeds linear 0..1')
            for old_value, new_value in zip(old,new):
                if old_value > 0.0:
                    ratio=new_value/old_value;gain_min=min(gain_min,ratio);gain_max=max(gain_max,ratio)
        if changed == 0:
            raise ValueError(f'sail_{row["sail"]} has no changed canvas colors')
        rows.append({'sail':row['sail'],'vertices':len(actual),'changedVertices':changed,
                     'accessor':row['accessor'],'view':row['view'],'span':[row['start'],row['start']+row['size']],
                     'minimumActualGain':gain_min,'maximumActualGain':gain_max})
    return {'sails':rows,'nonTargetBytesIdentical':True,'headerAndJsonBytesIdentical':True}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output',required=True,type=Path);args=parser.parse_args()
    if args.output.exists():raise SystemExit('fresh output required')
    results,errors=[],[]
    try:
        manifest=json.loads((BASE/'manifest.json').read_text(encoding='utf8'))
        for lod in range(3):
            source=BASE/f'fuchuan-lod{lod}.glb';destination=TARGET/f'fuchuan-lod{lod}.glb'
            a,ab,ar=read_glb(source);b,bb,br=read_glb(destination)
            if sha(ar)!=manifest['lods'][lod]['candidateSha256']:raise ValueError('source R9b manifest SHA mismatch')
            results.append({'lod':lod,'sourceSha256':sha(ar),'candidateSha256':sha(br),**verify_delta(a,ab,ar,b,bb,br)})
    except (OSError,ValueError,KeyError,IndexError,TypeError,struct.error) as exc:errors.append(str(exc))
    report={'baseline':'r9b','candidate':'r11b','scope':'exact CPU GLB delta; no visual or gameplay claim','models':results,'failures':errors}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with args.output.open('x',encoding='utf8') as stream:json.dump(report,stream,ensure_ascii=False,indent=2);stream.write('\n')
    print(f'HERO_R11B_GLTF_DELTA models={len(results)} failures={len(errors)}')
    for error in errors:print('FAIL:',error)
    raise SystemExit(1 if errors else 0)


if __name__=='__main__':main()
