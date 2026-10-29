"""Read-only exact accessor/triangle mapping for failed Blender R8a proxies."""
import hashlib
import importlib.util
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().with_name('proxy-accessor-mapping.json')
assert not OUT.exists(), 'preserve existing mapping evidence'
spec = importlib.util.spec_from_file_location('palette_uv', ROOT / 'tools/blender/canonicalize_palette_uv.py')
uv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(uv)
sha256 = lambda data: hashlib.sha256(data).hexdigest()


def node_mesh(glb, name):
    nodes = [(index, node) for index, node in enumerate(glb.doc['nodes']) if node.get('name') == name]
    assert len(nodes) == 1, (name, len(nodes))
    index, node = nodes[0]
    return index, node['mesh'], glb.doc['meshes'][node['mesh']]


def describe(glb, accessor_index):
    accessor = glb.doc['accessors'][accessor_index]
    layout = glb.layouts[accessor_index]
    assert layout is not None, 'proxy sparse accessor unsupported'
    packed = glb.packed(layout)
    return {'accessorIndex': accessor_index, 'count': accessor['count'], 'type': accessor['type'],
            'componentType': accessor['componentType'], 'normalized': accessor.get('normalized', False),
            'bufferView': accessor['bufferView'], 'accessorByteOffset': accessor.get('byteOffset', 0),
            'absoluteStart': layout['start'], 'absoluteEnd': layout['end'],
            'byteSpan': layout['end'] - layout['start'], 'packedBytes': len(packed),
            'stride': layout['stride'], 'componentByteOffsets': list(layout['components']),
            'packedSHA256': sha256(packed)}


def index_values(glb, index):
    layout = glb.layouts[index]
    assert layout['kind'] == 'SCALAR'
    char = {5121: 'B', 5123: 'H', 5125: 'I'}[layout['component']]
    return [struct.unpack_from('<' + char, glb.raw, offset)[0] for offset in uv._component_offsets(layout)]


def references(glb, target):
    found = []
    for mesh_index, mesh in enumerate(glb.doc['meshes']):
        for primitive_index, primitive in enumerate(mesh['primitives']):
            for attribute, index in primitive.get('attributes', {}).items():
                if index == target:
                    found.append({'meshIndex': mesh_index, 'primitiveIndex': primitive_index, 'attribute': attribute})
            if primitive.get('indices') == target:
                found.append({'meshIndex': mesh_index, 'primitiveIndex': primitive_index, 'attribute': 'indices'})
    return found


report = {'scope': 'Read-only R7c/R8a hidden-proxy layout comparison; no output asset bytes modified',
          'mappingRule': 'node name -> unique mesh -> same primitive ordinal -> decoded index identity -> same attribute schema/count',
          'lods': []}
for lod in range(3):
    reference_path = ROOT / f'assets/models/hero_fuchuan_v3_r7c/fuchuan-lod{lod}.glb'
    candidate_path = ROOT / f'assets/models/hero_fuchuan_v3_r8a/fuchuan-lod{lod}.glb'
    reference = uv._Glb(reference_path.read_bytes())
    candidate = uv._Glb(candidate_path.read_bytes())
    entry = {'lod': lod, 'reference': reference_path.relative_to(ROOT).as_posix(),
             'candidate': candidate_path.relative_to(ROOT).as_posix(),
             'referenceSHA256': sha256(reference.raw), 'candidateSHA256': sha256(candidate.raw), 'nodes': []}
    for name in ['shadow_hull', 'shadow_deck']:
        rn, rm, rmesh = node_mesh(reference, name)
        cn, cm, cmesh = node_mesh(candidate, name)
        item = {'name': name, 'referenceNode': rn, 'candidateNode': cn,
                'referenceMesh': rm, 'candidateMesh': cm,
                'referencePrimitiveCount': len(rmesh['primitives']), 'candidatePrimitiveCount': len(cmesh['primitives']),
                'primitives': []}
        assert len(rmesh['primitives']) == len(cmesh['primitives']), 'primitive count changed'
        for ordinal, (rp, cp) in enumerate(zip(rmesh['primitives'], cmesh['primitives'])):
            ri = index_values(reference, rp['indices'])
            ci = index_values(candidate, cp['indices'])
            primitive = {'primitiveOrdinal': ordinal, 'referenceMode': rp.get('mode', 4), 'candidateMode': cp.get('mode', 4),
                         'referenceMaterial': rp.get('material'), 'candidateMaterial': cp.get('material'),
                         'attributeSetsExact': rp['attributes'].keys() == cp['attributes'].keys(),
                         'indices': {'reference': describe(reference, rp['indices']), 'candidate': describe(candidate, cp['indices']),
                                     'decodedValuesAndOrderExact': ri == ci,
                                     'firstDifferentIndex': next((i for i, values in enumerate(zip(ri, ci)) if values[0] != values[1]), None),
                                     'countExact': len(ri) == len(ci), 'referenceMin': min(ri), 'referenceMax': max(ri),
                                     'candidateMin': min(ci), 'candidateMax': max(ci)}, 'attributes': {}}
            for attribute in sorted(set(rp['attributes']) | set(cp['attributes'])):
                assert attribute in rp['attributes'] and attribute in cp['attributes']
                ra, ca = rp['attributes'][attribute], cp['attributes'][attribute]
                rd, cd = describe(reference, ra), describe(candidate, ca)
                primitive['attributes'][attribute] = {
                    'reference': rd, 'candidate': cd,
                    'schemaExact': all(rd[key] == cd[key] for key in ('count', 'type', 'componentType', 'normalized')),
                    'byteSpanSameLength': rd['byteSpan'] == cd['byteSpan'],
                    'packedByteLengthExact': rd['packedBytes'] == cd['packedBytes'],
                    'packedBytesExact': rd['packedSHA256'] == cd['packedSHA256'],
                    'referenceAccessorReferences': references(reference, ra),
                    'candidateAccessorReferences': references(candidate, ca)}
            item['primitives'].append(primitive)
        entry['nodes'].append(item)
    report['lods'].append(entry)
report['allProxyPrimitiveCountsExact'] = all(item['referencePrimitiveCount'] == item['candidatePrimitiveCount']
                                           for lod in report['lods'] for item in lod['nodes'])
primitives = [primitive for lod in report['lods'] for node in lod['nodes'] for primitive in node['primitives']]
report['allProxyIndicesDecodedExact'] = all(primitive['indices']['decodedValuesAndOrderExact'] for primitive in primitives)
report['allProxyAttributeSchemasExact'] = all(attribute['schemaExact'] for primitive in primitives for attribute in primitive['attributes'].values())
report['allProxyPositionNormalByteSpansSameLength'] = all(primitive['attributes'][name]['byteSpanSameLength']
                                                       for primitive in primitives for name in ['POSITION', 'NORMAL'])
report['allProxyUVBytesExact'] = all(primitive['attributes']['TEXCOORD_0']['packedBytesExact'] for primitive in primitives)
OUT.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(json.dumps({key: value for key, value in report.items() if key != 'lods'}, indent=2))
for lod in report['lods']:
    for node in lod['nodes']:
        for primitive in node['primitives']:
            print(json.dumps({'lod': lod['lod'], 'node': node['name'],
                              'primitiveOrdinal': primitive['primitiveOrdinal'],
                              'indicesExact': primitive['indices']['decodedValuesAndOrderExact'],
                              'attributes': {name: {'count': value['reference']['count'],
                                                    'referenceSpan': value['reference']['byteSpan'],
                                                    'candidateSpan': value['candidate']['byteSpan'],
                                                    'bytesExact': value['packedBytesExact']}
                                             for name, value in primitive['attributes'].items()}}))
