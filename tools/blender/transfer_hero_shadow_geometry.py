"""Package only two Blender-authored proxy POSITION/NORMAL payloads onto R7c.

This is a compatibility package, not a Blender re-export. No tolerance switch.
Every input is validated before an output file is opened. Unsupported layouts
are refused rather than guessed. The companion verifier is independent.
"""
import argparse
import copy
import hashlib
import json
import math
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/research'))
from verify_hero_palette_delta import read_glb, decode_accessor, COMPONENTS, WIDTHS

TARGETS = ('shadow_hull', 'shadow_deck')
OLD_ID = 'hero-fuchuan-v3-r7c'
AUTHOR_ID = 'hero-fuchuan-v3-r8a'
NEW_ID = 'hero-fuchuan-v3-r8b'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_checked(path):
    document, binary, digest = read_glb(path)
    raw = path.read_bytes()
    offset = 12
    kinds = []
    while offset < len(raw):
        size, kind = struct.unpack_from('<II', raw, offset)
        if size % 4:
            raise ValueError('Unaligned GLB chunk')
        kinds.append(kind)
        offset += 8 + size
    if kinds != [0x4e4f534a, 0x004e4942] or offset != len(raw):
        raise ValueError('Exactly one JSON and one internal BIN chunk required')
    declared = document['buffers'][0]['byteLength']
    if not isinstance(declared, int) or declared < 0 or not 0 <= len(binary) - declared <= 3:
        raise ValueError('Invalid internal buffer length')
    for view in document.get('bufferViews', []):
        start, size = view.get('byteOffset', 0), view['byteLength']
        if (view.get('buffer', 0) != 0 or not isinstance(start, int) or not isinstance(size, int)
                or start < 0 or size < 0 or start + size > declared):
            raise ValueError('bufferView exceeds internal buffer')
    return document, binary, digest


def references(value, key):
    """All bufferView uses, including image and sparse payloads."""
    if isinstance(value, dict):
        for name, child in value.items():
            if name == key and isinstance(child, int):
                yield child
            yield from references(child, key)
    elif isinstance(value, list):
        for child in value:
            yield from references(child, key)


def accessor_references(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key == 'attributes' and isinstance(child, dict):
                yield from (v for v in child.values() if isinstance(v, int))
            elif key == 'targets' and isinstance(child, list):
                for target in child:
                    yield from target.values()
            elif key in ('indices', 'input', 'output', 'inverseBindMatrices') and isinstance(child, int):
                yield child
            yield from accessor_references(child)
    elif isinstance(value, list):
        for child in value:
            yield from accessor_references(child)


def dense(document, binary, index, exclusive=False):
    a = document['accessors'][index]
    if 'sparse' in a or 'bufferView' not in a or a.get('normalized', False):
        raise ValueError('Dense non-normalized accessor required')
    view_index = a['bufferView']
    view = document['bufferViews'][view_index]
    char, component_size = COMPONENTS[a['componentType']]
    width = WIDTHS[a['type']]
    size = component_size * width
    count, local = a['count'], a.get('byteOffset', 0)
    if (not isinstance(count, int) or count <= 0 or not isinstance(local, int) or local < 0
            or view.get('byteStride', size) != size or local % component_size
            or local + count * size > view['byteLength']):
        raise ValueError('Unsupported interleaving, alignment or accessor bounds')
    start = view.get('byteOffset', 0) + local
    end = start + count * size
    if start % component_size:
        raise ValueError('Unaligned accessor')
    if exclusive:
        if list(accessor_references(document)).count(index) != 1:
            raise ValueError('Target accessor must have one unique reference')
        if list(references(document, 'bufferView')).count(view_index) != 1:
            raise ValueError('Target bufferView must be exclusive')
        lo, hi = view.get('byteOffset', 0), view.get('byteOffset', 0) + view['byteLength']
        for vi, other in enumerate(document['bufferViews']):
            if vi == view_index:
                continue
            ol = other.get('byteOffset', 0)
            if max(lo, ol) < min(hi, ol + other['byteLength']):
                raise ValueError('Other accessor/sparse/image bufferView aliases target storage')
    values = decode_accessor(document, binary, index)
    return a, (start, end), binary[start:end], values


def target(document, name):
    found = [node for node in document['nodes'] if node.get('name') == name]
    if len(found) != 1 or 'mesh' not in found[0]:
        raise ValueError('Exactly one target node with mesh required: ' + name)
    node = found[0]
    mesh_index = node['mesh']
    if sum(n.get('mesh') == mesh_index for n in document['nodes']) != 1:
        raise ValueError('Target mesh is shared by another node')
    mesh = document['meshes'][mesh_index]
    if len(mesh['primitives']) != 1:
        raise ValueError('Target mesh must have one primitive')
    primitive = mesh['primitives'][0]
    if primitive.get('mode', 4) != 4 or 'indices' not in primitive or primitive.get('targets') or primitive.get('extensions'):
        raise ValueError('Only indexed TRIANGLES with no target morph/extension supported')
    if not {'POSITION', 'NORMAL'} <= primitive['attributes'].keys():
        raise ValueError('Target POSITION and NORMAL required')
    return node, primitive


def frame_chain(document, selected):
    nodes = document['nodes']
    parents = {}
    for i, node in enumerate(nodes):
        for c in node.get('children', []):
            if c in parents:
                raise ValueError('Multiple node parents unsupported')
            parents[c] = i
    i = next(i for i, n in enumerate(nodes) if n is selected)
    seen, chain = set(), []
    while True:
        if i in seen:
            raise ValueError('Cyclic node hierarchy')
        seen.add(i)
        n = nodes[i]
        chain.append({k:n[k] for k in ('name', 'translation', 'rotation', 'scale', 'matrix') if k in n})
        if i not in parents:
            return chain
        i = parents[i]


def identity(document, expected):
    roots = [n for n in document['nodes'] if n.get('name') == 'HeroFuchuan']
    if len(roots) != 1 or roots[0].get('extras', {}).get('authored_asset') != expected:
        raise ValueError('Unexpected HeroFuchuan authored_asset identity; expected ' + expected)
    return roots[0]


def schema(accessor):
    return {k:accessor.get(k, False if k == 'normalized' else None)
            for k in ('componentType', 'type', 'count', 'normalized')}


def encode(document, binary):
    j = json.dumps(document, ensure_ascii=False, allow_nan=False, separators=(',', ':')).encode('utf8')
    j += b' ' * (-len(j) % 4)
    return (struct.pack('<III', 0x46546c67, 2, 28 + len(j) + len(binary))
            + struct.pack('<II', len(j), 0x4e4f534a) + j
            + struct.pack('<II', len(binary), 0x004e4942) + bytes(binary))


def prepare(reference, authored):
    a, ab, ah = read_checked(reference)
    b, bb, bh = read_checked(authored)
    identity(a, OLD_ID)
    identity(b, AUTHOR_ID)
    output = copy.deepcopy(a)
    identity(output, OLD_ID)['extras']['authored_asset'] = NEW_ID
    binary = bytearray(ab)
    changes = []
    for name in TARGETS:
        an, ap = target(a, name)
        bn, bp = target(b, name)
        if frame_chain(a, an) != frame_chain(b, bn) or ap['attributes'].keys() != bp['attributes'].keys():
            raise ValueError('Target frame chain or attribute set differs: ' + name)
        if {k:v for k,v in ap.items() if k not in ('attributes', 'indices')} != {k:v for k,v in bp.items() if k not in ('attributes', 'indices')}:
            raise ValueError('Target primitive metadata differs: ' + name)
        ai, _, airaw, av = dense(a, ab, ap['indices'])
        bi, _, biraw, bv = dense(b, bb, bp['indices'])
        if (schema(ai) != schema(bi) or ai['type'] != 'SCALAR' or ai['componentType'] not in (5121,5123,5125)
                or airaw != biraw or av != bv or len(av) % 3):
            raise ValueError('Target indices/schema/order differ: ' + name)
        count = None
        for attr in sorted(ap['attributes']):
            ia, ib = ap['attributes'][attr], bp['attributes'][attr]
            aa, interval, ar, va = dense(a, ab, ia, attr in ('POSITION', 'NORMAL'))
            ba, authored_interval, br, vb = dense(b, bb, ib, attr in ('POSITION', 'NORMAL'))
            if schema(aa) != schema(ba):
                raise ValueError('Target attribute schema/count differs: ' + name + '/' + attr)
            if count is None:
                count = aa['count']
            if aa['count'] != count:
                raise ValueError('Target attribute vertex counts differ')
            if attr not in ('POSITION', 'NORMAL'):
                if ar != br or va != vb:
                    raise ValueError('Unchanged target attribute differs: ' + name + '/' + attr)
                continue
            if aa['type'] != 'VEC3' or aa['componentType'] != 5126 or not all(math.isfinite(v) for row in vb for v in row):
                raise ValueError('Finite FLOAT VEC3 P/N required')
            start, end = interval
            binary[start:end] = br
            if attr == 'POSITION':
                output['accessors'][ia]['min'] = [min(v[k] for v in vb) for k in range(3)]
                output['accessors'][ia]['max'] = [max(v[k] for v in vb) for k in range(3)]
            changes.append({'node':name, 'attribute':attr, 'reference_accessor':ia, 'authored_accessor':ib,
                            'bin_interval_half_open':[start,end], 'authored_bin_interval_half_open':list(authored_interval),
                            'component_count':aa['count']*3, 'changed_bytes':sum(x!=y for x,y in zip(ar,br)),
                            'changed_float32_components':sum(ar[i:i+4]!=br[i:i+4] for i in range(0,len(ar),4)),
                            'reference_payload_sha256':sha(ar), 'authored_payload_sha256':sha(br)})
        if any(i[0] >= count for i in av):
            raise ValueError('Target index outside vertex bounds')
    packed = encode(output, binary)
    receipt = {'reference':str(reference.resolve()), 'authored':str(authored.resolve()),
               'reference_sha256':ah, 'authored_sha256':bh, 'output_sha256':sha(packed),
               'reference_authoring_identity':OLD_ID, 'source_authoring_identity':AUTHOR_ID,
               'output_identity':NEW_ID, 'allowed_byte_intervals':changes,
               'bin_length_unchanged':len(binary)==len(ab), 'bin_changed_bytes':sum(x!=y for x,y in zip(ab,binary)),
               'method':'Reference BIN clone; copy only matched dense exclusive FLOAT VEC3 proxy P/N; reference JSON clone except declared identity and target POSITION bounds.',
               'input_files_unchanged':sha(reference.read_bytes())==ah and sha(authored.read_bytes())==bh}
    if not receipt['input_files_unchanged']:
        raise ValueError('Input changed during validation')
    return packed, receipt


def transfer(reference: Path, authored: Path, output: Path) -> dict:
    reference, authored, output = Path(reference), Path(authored), Path(output)
    if output.exists():
        raise FileExistsError('Fresh output required: ' + str(output))
    packed, receipt = prepare(reference, authored)
    with output.open('xb') as stream:
        stream.write(packed)
    receipt['output'] = str(output.resolve())
    receipt['input_files_unchanged'] = (sha(reference.read_bytes())==receipt['reference_sha256']
                                       and sha(authored.read_bytes())==receipt['authored_sha256'])
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ('reference-dir','authored-dir','output-dir','source-blend','report'):
        parser.add_argument('--'+option, required=True, type=Path)
    args = parser.parse_args()
    if args.output_dir.exists() or args.report.exists():
        parser.error('Fresh output directory and report required')
    if args.report.resolve().is_relative_to(args.output_dir.resolve()):
        parser.error('Report must be outside the packaged output directory')
    source_sha = sha(args.source_blend.read_bytes())
    prepared = []
    for lod in range(3):
        filename = f'fuchuan-lod{lod}.glb'
        packed, receipt = prepare(args.reference_dir/filename, args.authored_dir/filename)
        receipt['lod'] = lod
        receipt['output'] = str((args.output_dir/filename).resolve())
        prepared.append((filename, packed, receipt))
    # No output exists before all three LOD inputs and source provenance pass.
    if sha(args.source_blend.read_bytes()) != source_sha:
        raise ValueError('Source Blend changed during validation')
    for _, _, receipt in prepared:
        if (sha(Path(receipt['reference']).read_bytes()) != receipt['reference_sha256']
                or sha(Path(receipt['authored']).read_bytes()) != receipt['authored_sha256']):
            raise ValueError('GLB input changed during three-LOD validation')
    args.output_dir.mkdir(parents=True, exist_ok=False)
    for filename, packed, receipt in prepared:
        with (args.output_dir/filename).open('xb') as stream:
            stream.write(packed)
        receipt['input_files_unchanged'] = (
            sha(Path(receipt['reference']).read_bytes()) == receipt['reference_sha256']
            and sha(Path(receipt['authored']).read_bytes()) == receipt['authored_sha256'])
        if not receipt['input_files_unchanged']:
            raise ValueError('GLB input changed during output writing')
    manifest = {'asset':NEW_ID, 'packaging_method':'Bounded R7c BIN compatibility package; not Blender re-export',
                'source':str(args.source_blend.resolve()), 'source_sha256':source_sha,
                'source_authoring_identity':AUTHOR_ID, 'reference_identity':OLD_ID,
                'lods':[r for _,_,r in prepared], 'tool_sha256':sha(Path(__file__).read_bytes()),
                'limitations':['CPU payload packaging only; no GPU, gameplay, visual or performance acceptance.']}
    with (args.output_dir/'manifest.json').open('x',encoding='utf8') as stream:
        json.dump(manifest,stream,ensure_ascii=False,indent=2)
        stream.write('\n')
    report = dict(manifest, record_type='cpu-transfer', completed_utc=datetime.now(timezone.utc).isoformat(),
                  source_blend_unchanged=sha(args.source_blend.read_bytes())==source_sha,
                  pass_=True, command=sys.argv)
    report['pass'] = report.pop('pass_')
    args.report.parent.mkdir(parents=True,exist_ok=True)
    with args.report.open('x',encoding='utf8') as stream:
        json.dump(report,stream,ensure_ascii=False,indent=2)
        stream.write('\n')
    print('HERO_PROXY_TRANSFER_PASS')
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ValueError, OSError, KeyError, IndexError, struct.error) as error:
        print('HERO_PROXY_TRANSFER_REFUSED: '+str(error), file=sys.stderr)
        raise SystemExit(1)
