"""Strict CPU GLB contract for a material-only hero palette candidate.

Compares every referenced triangle corner and morph attribute, independent of
primitive/vertex/index order. Winding is preserved. There is no epsilon switch.
Packed accessor layout and material-induced vertex duplication may differ;
decoded numeric values must be exactly equal (signed zero is canonicalized).
"""
import argparse
import collections
import copy
import hashlib
import json
import math
import struct
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEXTURE_SHA = 'aec881ec7005d468a9dbf4e7d5f13ca2e4ebabe93f8bb092e04ffa22e99ebc3c'
NEW_MATERIALS = {'sunwashed_teak': [1., 1., 1., 1.],
                 'aged_hull_teak': [.68, .65, .61, 1.]}
ALLOWED_REPLACEMENTS = {
    'hull': {'sunwashed_teak', 'aged_hull_teak'},
    'sterncastle': {'sunwashed_teak'},
    'stern_transom': {'sunwashed_teak'},
    'deck_fittings': {'aged_hull_teak'},
}
COMPONENTS = {5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2),
              5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}
WIDTHS = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def read_glb(path):
    raw = path.read_bytes()
    magic, version, length = struct.unpack_from('<4sII', raw)
    if magic != b'glTF' or version != 2 or length != len(raw):
        raise ValueError(f'Invalid GLB header: {path}')
    chunks = {}
    offset = 12
    while offset < length:
        size, kind = struct.unpack_from('<II', raw, offset)
        offset += 8
        if offset + size > length or kind in chunks:
            raise ValueError(f'Invalid GLB chunk: {path}')
        chunks[kind] = raw[offset:offset + size]
        offset += size
    document = json.loads(chunks[0x4e4f534a])
    if len(document.get('buffers', [])) != 1 or 'uri' in document['buffers'][0]:
        raise ValueError('Only one embedded GLB buffer is supported')
    return document, chunks[0x004e4942], sha(raw)


def decode_accessor(document, binary, index):
    a = document['accessors'][index]
    char, component_size = COMPONENTS[a['componentType']]
    width = WIDTHS[a['type']]
    size = component_size * width
    fmt = '<' + char * width
    values = [(0,) * width for _ in range(a['count'])]

    def read_view(view_index, offset, count, format_string, stride=None):
        view = document['bufferViews'][view_index]
        if view.get('buffer', 0) != 0:
            raise ValueError('External buffer unsupported')
        start = view.get('byteOffset', 0) + offset
        item_size = struct.calcsize(format_string)
        step = stride or item_size
        if count and offset + (count - 1) * step + item_size > view['byteLength']:
            raise ValueError('Accessor exceeds its bufferView')
        return [struct.unpack_from(format_string, binary, start + i * step) for i in range(count)]

    if 'bufferView' in a:
        view = document['bufferViews'][a['bufferView']]
        values = read_view(a['bufferView'], a.get('byteOffset', 0), a['count'], fmt,
                           view.get('byteStride', size))
    if 'sparse' in a:
        sparse = a['sparse']
        indices = sparse['indices']
        if indices['componentType'] not in (5121, 5123, 5125):
            raise ValueError('Invalid sparse index component type')
        code = COMPONENTS[indices['componentType']][0]
        sparse_indices = read_view(indices['bufferView'], indices.get('byteOffset', 0),
                                   sparse['count'], '<' + code)
        replacement = sparse['values']
        sparse_values = read_view(replacement['bufferView'], replacement.get('byteOffset', 0),
                                  sparse['count'], fmt)
        previous = -1
        for (target,), value in zip(sparse_indices, sparse_values):
            if target <= previous or target >= a['count']:
                raise ValueError('Invalid sparse accessor indices')
            values[target] = value
            previous = target
    if a.get('normalized'):
        divisor = {5120: 127, 5121: 255, 5122: 32767, 5123: 65535}.get(a['componentType'])
        if divisor is None:
            raise ValueError('Invalid normalized accessor component type')
        values = [tuple(max(-1., x / divisor) for x in row) for row in values]
    if any(not math.isfinite(x) for row in values for x in row):
        raise ValueError('Non-finite attribute value')
    return values


def mesh_records(document, binary, mesh_index):
    geometry = collections.Counter()
    materials = collections.defaultdict(collections.Counter)
    cache = {}

    def accessor(index):
        if index not in cache:
            cache[index] = decode_accessor(document, binary, index)
        return cache[index]

    for primitive in document['meshes'][mesh_index]['primitives']:
        if primitive.get('mode', 4) != 4:
            raise ValueError('Only TRIANGLES mode is supported; comparison refused')
        if primitive.get('extensions'):
            raise ValueError('Primitive extensions need explicit decoding; comparison refused')
        attributes = dict(primitive['attributes'])
        for target_index, target in enumerate(primitive.get('targets', [])):
            attributes.update({f'MORPH_{target_index}/{name}': index for name, index in target.items()})
        ordered = sorted(attributes, key=lambda name: (name != 'POSITION', name))
        arrays = [accessor(attributes[name]) for name in ordered]
        count = len(arrays[0])
        if any(len(array) != count for array in arrays):
            raise ValueError('Attribute accessor lengths differ')
        schema = tuple((name, len(array[0])) for name, array in zip(ordered, arrays))
        corners = []
        for i in range(count):
            flat = [float(x) if x else 0. for array in arrays for x in array[i]]
            corners.append(struct.pack('<' + 'd' * len(flat), *flat))
        indices = [x[0] for x in accessor(primitive['indices'])] if 'indices' in primitive else list(range(count))
        if len(indices) % 3 or any(not isinstance(i, int) or i < 0 or i >= count for i in indices):
            raise ValueError('Invalid triangle indices')
        material = document['materials'][primitive['material']]['name'] if 'material' in primitive else '<default>'
        for i in range(0, len(indices), 3):
            a, b, c = (corners[k] for k in indices[i:i + 3])
            # Cyclic starts are interchangeable; reversed winding is not.
            key = (schema, min(a + b + c, b + c + a, c + a + b))
            geometry[key] += 1
            materials[key][material] += 1
    return geometry, materials


def triangle_records(document, binary, mesh_index=0):
    return mesh_records(document, binary, mesh_index)[0]


def canonical_hash(records):
    digest = hashlib.sha256()
    for (schema, raw), count in sorted(records.items()):
        encoded = json.dumps(schema, separators=(',', ':')).encode()
        digest.update(struct.pack('<III', len(encoded), len(raw), count))
        digest.update(encoded)
        digest.update(raw)
    return digest.hexdigest()


def numeric_diagnostics(left, right):
    """Diagnostic pairing only. No approximate pairing can make equality pass."""
    removed = list((left - right).elements())
    added = list((right - left).elements())
    maxima = {}
    comparable = 0
    for (schema_a, raw_a), (schema_b, raw_b) in zip(sorted(removed), sorted(added)):
        if schema_a != schema_b:
            continue
        values_a = struct.unpack('<' + 'd' * (len(raw_a) // 8), raw_a)
        values_b = struct.unpack('<' + 'd' * (len(raw_b) // 8), raw_b)
        offset = 0
        for _ in range(3):
            for name, width in schema_a:
                delta = max(abs(a - b) for a, b in zip(values_a[offset:offset + width], values_b[offset:offset + width]))
                maxima[name] = max(maxima.get(name, 0.), delta)
                offset += width
        comparable += 1
    def sample(records):
        return [{'schema': schema, 'corner_data_sha256': sha(raw)} for schema, raw in sorted(records)[:3]]
    return {'removed_triangles': len(removed), 'added_triangles': len(added),
            'diagnostic_pairing': 'Lexicographic rank of unmatched full corner records; not vertex correspondence',
            'comparable_sorted_pairs': comparable, 'max_abs_float_delta_sorted_pairs': maxima,
            'removed_samples': sample(removed), 'added_samples': sample(added)}


def image_signature(document, binary, index):
    item = copy.deepcopy(document['images'][index])
    if 'bufferView' not in item:
        raise ValueError('Only embedded images are supported')
    view = document['bufferViews'][item.pop('bufferView')]
    offset = view.get('byteOffset', 0)
    item['sha256'] = sha(binary[offset:offset + view['byteLength']])
    return item


def material_signature(document, binary, material):
    def texture_signature(index):
        texture = copy.deepcopy(document['textures'][index])
        if 'extensions' in texture:
            raise ValueError('Texture extensions need explicit resource resolution')
        texture['image'] = image_signature(document, binary, texture.pop('source'))
        texture['sampler'] = document.get('samplers', [])[texture['sampler']] if 'sampler' in texture else '<default>'
        return texture
    def walk(value, key=''):
        if isinstance(value, list):
            return [walk(item) for item in value]
        if not isinstance(value, dict):
            return value
        result = {name: walk(item, name) for name, item in value.items()}
        if key.lower().endswith('texture') and 'index' in result:
            result['texture'] = texture_signature(result.pop('index'))
        return result
    return walk(material)


def compare_materials(left, left_binary, right, right_binary):
    old = {m['name']: material_signature(left, left_binary, m) for m in left['materials']}
    new = {m['name']: material_signature(right, right_binary, m) for m in right['materials']}
    if len(old) != len(left['materials']) or len(new) != len(right['materials']):
        raise ValueError('Duplicate material names')
    result = {'missing_old_materials': sorted(old.keys() - new.keys()),
              'added_materials': sorted(new.keys() - old.keys()), 'preserved_original_materials': {}, 'new_materials': {}}
    for name in old.keys() & new.keys():
        result['preserved_original_materials'][name] = old[name] == new[name]
        if old[name] != new[name]:
            result.setdefault('changed_original_materials', {})[name] = {'before': old[name], 'after': new[name]}
    template = copy.deepcopy(old['teak'])
    template.pop('name', None)
    for field in ['baseColorTexture', 'baseColorFactor']:
        template['pbrMetallicRoughness'].pop(field, None)
    for name, requested in NEW_MATERIALS.items():
        if name not in new:
            result['new_materials'][name] = {'present': False, 'pass': False}
            continue
        material = new[name]
        pbr = material.get('pbrMetallicRoughness', {})
        expected = [struct.unpack('<f', struct.pack('<f', value))[0] for value in requested]
        actual = pbr.get('baseColorFactor', [1., 1., 1., 1.])
        image = pbr.get('baseColorTexture', {}).get('texture', {}).get('image', {})
        comparable = copy.deepcopy(material)
        comparable.pop('name', None)
        for field in ['baseColorTexture', 'baseColorFactor']:
            comparable['pbrMetallicRoughness'].pop(field, None)
        entry = {'present': True, 'factor_property_present': 'baseColorFactor' in pbr,
                 'requested_linear_factor': requested, 'expected_float32_factor': expected,
                 'actual_json_factor_or_default': actual, 'factor_exact': actual == expected,
                 'embedded_image': image, 'image_sha_exact': image.get('sha256') == TEXTURE_SHA,
                 'remaining_teak_settings_exact': comparable == template}
        entry['pass'] = entry['factor_exact'] and entry['image_sha_exact'] and entry['remaining_teak_settings_exact']
        result['new_materials'][name] = entry
    result['pass'] = (not result['missing_old_materials'] and set(result['added_materials']) == set(NEW_MATERIALS)
                      and all(result['preserved_original_materials'].values())
                      and all(item['pass'] for item in result['new_materials'].values()))
    return result


def transition_allowed(node_name, old, new):
    return old == 'teak' and new in ALLOWED_REPLACEMENTS.get(node_name, set())


def material_transitions(node_name, left, right):
    transitions = collections.Counter()
    for key in left.keys() | right.keys():
        same = left.get(key, collections.Counter()) & right.get(key, collections.Counter())
        old = left.get(key, collections.Counter()) - same
        new = right.get(key, collections.Counter()) - same
        if sum(old.values()) != sum(new.values()):
            return {'pass': False, 'reason': 'Triangle geometry differs; exact material correspondence unavailable'}
        a, b = sorted(old.elements()), sorted(new.elements())
        transitions.update(zip(a, b))
    changes = [{'from': old, 'to': new, 'triangles': count,
                'allowed_node_role': transition_allowed(node_name, old, new)}
               for (old, new), count in sorted(transitions.items())]
    return {'pass': all(item['allowed_node_role'] for item in changes), 'changes': changes}


def node_table(document):
    names = [node.get('name', '') for node in document['nodes']]
    if len(names) != len(set(names)) or '' in names:
        raise ValueError('Node names must be unique for unambiguous identity matching')
    parents = {}
    for i, node in enumerate(document['nodes']):
        for child in node.get('children', []):
            if child in parents:
                raise ValueError('Node has multiple parents')
            parents[child] = names[i]
    result = {}
    for i, node in enumerate(document['nodes']):
        description = copy.deepcopy(node)
        description.pop('mesh', None)
        description['has_mesh'] = 'mesh' in node
        description['parent'] = parents.get(i)
        description['children'] = sorted(names[c] for c in node.get('children', []))
        for field, default in [('translation', [0., 0., 0.]), ('rotation', [0., 0., 0., 1.]), ('scale', [1., 1., 1.])]:
            description.setdefault(field, default)
        result[names[i]] = description
    return result


def compare_lod(baseline, candidate, lod):
    a, ab, ah = read_glb(baseline / f'fuchuan-lod{lod}.glb')
    b, bb, bh = read_glb(candidate / f'fuchuan-lod{lod}.glb')
    at, bt = node_table(a), node_table(b)
    result = {'lod': lod, 'baseline_sha256': ah, 'candidate_sha256': bh,
              'nodes_removed': sorted(at.keys() - bt.keys()), 'nodes_added': sorted(bt.keys() - at.keys()),
              'node_contract_differences': {}, 'asset_identity_metadata_differences': {}, 'meshes': {}}
    for name in at.keys() & bt.keys():
        left, right = copy.deepcopy(at[name]), copy.deepcopy(bt[name])
        old_asset = left.get('extras', {}).pop('authored_asset', None)
        new_asset = right.get('extras', {}).pop('authored_asset', None)
        if old_asset != new_asset:
            allowed = (name == 'HeroFuchuan' and old_asset == baseline.name.replace('_', '-')
                       and new_asset == candidate.name.replace('_', '-'))
            result['asset_identity_metadata_differences'][name] = {'before': old_asset, 'after': new_asset,
                                                                  'declared_asset_identity_only': allowed}
        if left != right:
            result['node_contract_differences'][name] = {'before': left, 'after': right}
    def scene_roots(document):
        return {'scene': document.get('scene'), 'scenes': [dict(scene, nodes=sorted(document['nodes'][i]['name'] for i in scene.get('nodes', [])))
                                                         for scene in document.get('scenes', [])]}
    result['scene_roots_exact'] = scene_roots(a) == scene_roots(b)
    an = {node['name']: node for node in a['nodes']}
    bn = {node['name']: node for node in b['nodes']}
    for name in sorted(an.keys() & bn.keys()):
        if 'mesh' not in an[name] or 'mesh' not in bn[name]:
            continue
        ar, am = mesh_records(a, ab, an[name]['mesh'])
        br, bm = mesh_records(b, bb, bn[name]['mesh'])
        old_meta = {k: v for k, v in a['meshes'][an[name]['mesh']].items() if k not in ('name', 'primitives')}
        new_meta = {k: v for k, v in b['meshes'][bn[name]['mesh']].items() if k not in ('name', 'primitives')}
        entry = {'triangle_corners_exact': ar == br, 'metadata_exact': old_meta == new_meta,
                 'baseline_triangles': sum(ar.values()), 'candidate_triangles': sum(br.values()),
                 'baseline_canonical_sha256': canonical_hash(ar), 'candidate_canonical_sha256': canonical_hash(br),
                 'attribute_schemas': sorted(set(schema for schema, _ in ar)),
                 'shadow_proxy': bool(an[name].get('extras', {}).get('hero_shadow_resource'))}
        if ar != br:
            entry['differences'] = numeric_diagnostics(ar, br)
        if old_meta != new_meta:
            entry['metadata_differences'] = {'before': old_meta, 'after': new_meta}
        entry['material_assignments'] = material_transitions(name, am, bm)
        entry['pass'] = entry['triangle_corners_exact'] and entry['metadata_exact'] and entry['material_assignments']['pass']
        result['meshes'][name] = entry
    # Animation/skin channels would require an additional referenced-accessor contract.
    result['no_unchecked_animation_or_skin_channels'] = not any(a.get(k) or b.get(k) for k in ('animations', 'skins'))
    result['markers_exact'] = not any(name in result['node_contract_differences'] for name, node in an.items() if 'mesh' not in node)
    result['all_shadow_proxy_geometry_exact'] = all(item['triangle_corners_exact'] and item['metadata_exact']
                                                   for item in result['meshes'].values() if item['shadow_proxy'])
    result['materials'] = compare_materials(a, ab, b, bb)
    result['geometry_exact'] = all(item['triangle_corners_exact'] and item['metadata_exact'] for item in result['meshes'].values())
    result['pass'] = (not result['nodes_added'] and not result['nodes_removed'] and not result['node_contract_differences']
                      and all(item['declared_asset_identity_only'] for item in result['asset_identity_metadata_differences'].values())
                      and result['scene_roots_exact'] and result['no_unchecked_animation_or_skin_channels']
                      and all(item['pass'] for item in result['meshes'].values()) and result['materials']['pass'])
    return result


def synthetic_mesh():
    document = {'bufferViews': [], 'accessors': [], 'materials': [{'name': 'teak'}]}
    binary = bytearray()

    def accessor(values, kind):
        offset = len(binary)
        for value in values:
            binary.extend(struct.pack('<' + 'f' * len(value), *value))
        view = len(document['bufferViews'])
        document['bufferViews'].append({'byteOffset': offset, 'byteLength': len(binary) - offset})
        index = len(document['accessors'])
        document['accessors'].append({'bufferView': view, 'componentType': 5126,
                                      'count': len(values), 'type': kind})
        return index

    attrs = {'POSITION': accessor([(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)], 'VEC3'),
             'NORMAL': accessor([(0, 0, 1)] * 4, 'VEC3'),
             'TEXCOORD_0': accessor([(0, 0), (1, 0), (1, 1), (0, 1)], 'VEC2'),
             'COLOR_0': accessor([(1, 1, 1, 1)] * 4, 'VEC4')}
    morph = accessor([(0, 0, 0), (0, 0, .25), (0, 0, .25), (0, 0, 0)], 'VEC3')
    indices = accessor([(0,), (1,), (2,), (0,), (2,), (3,)], 'SCALAR')
    # Integer indices are encoded separately from the floating point attributes.
    item = document['accessors'][indices]
    offset = document['bufferViews'][item['bufferView']]['byteOffset']
    binary[offset:] = struct.pack('<6I', 0, 1, 2, 0, 2, 3)
    item['componentType'] = 5125
    document['meshes'] = [{'primitives': [{'attributes': attrs, 'indices': indices,
                                          'targets': [{'POSITION': morph}], 'material': 0}]}]
    return document, bytes(binary)


class ComparatorControls(unittest.TestCase):
    def test_complete_corners_detect_normal_change_without_bounds_change(self):
        document, binary = synthetic_mesh()
        self.assertEqual(sum(triangle_records(document, binary).values()), 2)
        altered = bytearray(binary)
        normal = document['accessors'][document['meshes'][0]['primitives'][0]['attributes']['NORMAL']]
        offset = document['bufferViews'][normal['bufferView']]['byteOffset'] + 8
        altered[offset:offset + 4] = struct.pack('<I', 0x3f800001)
        self.assertNotEqual(triangle_records(document, binary), triangle_records(document, altered))

    def test_material_splits_and_cyclic_index_starts_do_not_change_geometry(self):
        document, binary = synthetic_mesh()
        candidate = copy.deepcopy(document)
        primitive = candidate['meshes'][0]['primitives'][0]
        index = primitive['indices']
        base = candidate['accessors'][index]
        base['count'] = 3
        other = copy.deepcopy(base)
        other['byteOffset'] = 12
        candidate['accessors'].append(other)
        second = copy.deepcopy(primitive)
        second['indices'] = len(candidate['accessors']) - 1
        candidate['materials'].append({'name': 'sunwashed_teak'})
        second['material'] = 1
        candidate['meshes'][0]['primitives'] = [second, primitive]
        changed = bytearray(binary)
        offset = candidate['bufferViews'][base['bufferView']]['byteOffset']
        changed[offset:] = struct.pack('<6I', 2, 0, 1, 3, 0, 2)
        self.assertEqual(triangle_records(document, binary), triangle_records(candidate, changed))
        before = mesh_records(document, binary, 0)[1]
        after = mesh_records(candidate, changed, 0)[1]
        self.assertTrue(material_transitions('hull', before, after)['pass'])
        self.assertFalse(material_transitions('mast_timber_0', before, after)['pass'])

    def test_reversed_winding_is_rejected(self):
        document, binary = synthetic_mesh()
        primitive = document['meshes'][0]['primitives'][0]
        accessor = document['accessors'][primitive['indices']]
        offset = document['bufferViews'][accessor['bufferView']]['byteOffset']
        changed = bytearray(binary)
        changed[offset:] = struct.pack('<6I', 0, 2, 1, 0, 2, 3)
        self.assertNotEqual(triangle_records(document, binary), triangle_records(document, changed))

    def test_uv_color_and_morph_changes_are_all_observed(self):
        document, binary = synthetic_mesh()
        primitive = document['meshes'][0]['primitives'][0]
        for name, index in [('UV', primitive['attributes']['TEXCOORD_0']),
                            ('COLOR', primitive['attributes']['COLOR_0']),
                            ('MORPH', primitive['targets'][0]['POSITION'])]:
            with self.subTest(attribute=name):
                changed = bytearray(binary)
                accessor = document['accessors'][index]
                offset = document['bufferViews'][accessor['bufferView']]['byteOffset']
                changed[offset:offset + 4] = struct.pack('<f', .125)
                self.assertNotEqual(triangle_records(document, binary), triangle_records(document, changed))

    def test_sparse_morph_payload_is_compared(self):
        document, binary = synthetic_mesh()
        candidate = copy.deepcopy(document)
        target = candidate['accessors'][candidate['meshes'][0]['primitives'][0]['targets'][0]['POSITION']]
        target.pop('bufferView')
        i = len(candidate['bufferViews'])
        candidate['bufferViews'].extend([{'byteOffset': len(binary), 'byteLength': 4},
                                        {'byteOffset': len(binary) + 4, 'byteLength': 24}])
        target['sparse'] = {'count': 2, 'indices': {'bufferView': i, 'componentType': 5123},
                            'values': {'bufferView': i + 1}}
        sparse_binary = binary + struct.pack('<2H6f', 1, 2, 0, 0, .25, 0, 0, .25)
        self.assertEqual(triangle_records(document, binary), triangle_records(candidate, sparse_binary))
        changed = bytearray(sparse_binary)
        changed[-4:] = struct.pack('<f', .125)
        self.assertNotEqual(triangle_records(document, binary), triangle_records(candidate, changed))

    def test_parent_and_marker_frame_changes_are_detected(self):
        document, _ = synthetic_mesh()
        document['nodes'] = [{'name': 'root', 'children': [1, 2]}, {'name': 'hull', 'mesh': 0},
                              {'name': 'marker', 'translation': [0, 1, 0]}]
        candidate = copy.deepcopy(document)
        candidate['nodes'][0]['children'] = [1]
        candidate['nodes'][1]['children'] = [2]
        self.assertNotEqual(node_table(document), node_table(candidate))
        candidate = copy.deepcopy(document)
        candidate['nodes'][2]['translation'][1] = 1.0000001
        self.assertNotEqual(node_table(document), node_table(candidate))

    def test_unsupported_triangle_modes_are_refused(self):
        document, binary = synthetic_mesh()
        document['meshes'][0]['primitives'][0]['mode'] = 5
        with self.assertRaisesRegex(ValueError, 'Only TRIANGLES'):
            triangle_records(document, binary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, default=ROOT / 'assets/models/hero_fuchuan_v3_r6')
    parser.add_argument('--candidate', type=Path, default=ROOT / 'assets/models/hero_fuchuan_v3_r7a')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(ComparatorControls)
        return 0 if unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful() else 1
    if args.output is None:
        parser.error('--output is required for asset comparisons')
    if args.output.exists():
        parser.error('Fresh output required; preserve earlier evidence')
    report = {'record_type': 'cpu-contract', 'started_utc': datetime.now(timezone.utc).isoformat(),
              'baseline': str(args.baseline.resolve()), 'candidate': str(args.candidate.resolve()),
              'tool_sha256': sha(Path(__file__).read_bytes()), 'command': sys.argv,
              'method': 'All referenced triangle corners: POSITION/NORMAL/UV/COLOR/all other attributes and all morphs. Sparse and normalized accessors decoded. Cyclic triangle start and primitive/vertex order canonicalized; winding retained. Exact decoded numeric equality; no epsilon. Signed zero canonicalized. Packed accessor layout is not claimed byte-identical.',
              'material_role_contract': {name: sorted(allowed) for name, allowed in ALLOWED_REPLACEMENTS.items()},
              'limitations': ['CPU only; no visual, GPU, performance or gameplay acceptance.',
                              'Fine pre-join object labels are absent from GLB; material role audit uses exported node identities and exact per-triangle old/new material correspondence.',
                              'Only the explicit authored_asset identity update is excluded from node role equality; every such delta is recorded.',
                              'Geometry mismatch diagnostics pair unmatched records by sorted rank; those maxima are not vertex correspondence and never relax equality.'],
              'lods': []}
    for lod in range(3):
        try:
            result = compare_lod(args.baseline.resolve(), args.candidate.resolve(), lod)
        except (ValueError, KeyError, IndexError, struct.error, OSError) as error:
            result = {'lod': lod, 'pass': False, 'comparison_refused': str(error)}
        report['lods'].append(result)
        print(json.dumps({'lod': lod, 'pass': result['pass'], 'geometry_exact': result.get('geometry_exact'),
                          'failed_meshes': [name for name, value in result.get('meshes', {}).items() if not value['pass']],
                          'materials_pass': result.get('materials', {}).get('pass'),
                          'comparison_refused': result.get('comparison_refused')}), flush=True)
    report['pass'] = all(item['pass'] for item in report['lods'])
    report['finished_utc'] = datetime.now(timezone.utc).isoformat()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('HERO_PALETTE_DELTA_' + ('PASS' if report['pass'] else 'FAIL'))
    return 0 if report['pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
