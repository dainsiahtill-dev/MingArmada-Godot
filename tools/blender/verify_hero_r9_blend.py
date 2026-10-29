"""Reopen both authoring blends in real Blender and compare authored structure."""
import array
import hashlib
import json
import sys
from pathlib import Path
import bpy


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def packed(collection, field, width, code):
    values = array.array(code, [0]) * (len(collection) * width)
    collection.foreach_get(field, values)
    return digest(values.tobytes())


def snapshot():
    objects = []
    for obj in sorted(bpy.data.objects, key=lambda value: value.name):
        row = {'name': obj.name, 'type': obj.type, 'parent': obj.parent.name if obj.parent else None,
               'matrix': [float(value) for row in obj.matrix_local for value in row],
               'data': obj.data.name if obj.data else None}
        if obj.type == 'MESH':
            mesh = obj.data
            row['geometry'] = {
                'vertices': packed(mesh.vertices, 'co', 3, 'f'),
                'loops': packed(mesh.loops, 'vertex_index', 1, 'i'),
                'polygonStarts': packed(mesh.polygons, 'loop_start', 1, 'i'),
                'polygonSizes': packed(mesh.polygons, 'loop_total', 1, 'i'),
                'polygonMaterialIndices': packed(mesh.polygons, 'material_index', 1, 'i'),
                'uv': [(layer.name, packed(layer.data, 'uv', 2, 'f')) for layer in mesh.uv_layers],
                'shapeKeys': [(key.name, packed(key.data, 'co', 3, 'f')) for key in
                              (mesh.shape_keys.key_blocks if mesh.shape_keys else [])],
                'materials': [material.name if material else None for material in mesh.materials],
            }
        objects.append(row)
    materials = []
    for material in sorted(bpy.data.materials, key=lambda value: value.name):
        if not material.node_tree:
            materials.append({'name': material.name, 'nodes': None, 'links': None})
            continue
        materials.append({'name': material.name,
                          'nodes': sorted((node.name, node.bl_idname,
                                           node.image.name if node.type == 'TEX_IMAGE' and node.image else None)
                                          for node in material.node_tree.nodes),
                          'links': sorted((link.from_node.name, link.from_socket.name,
                                           link.to_node.name, link.to_socket.name)
                                          for link in material.node_tree.links)})
    return {'objects': objects, 'materials': materials}


def main():
    source, candidate, png, output = map(Path, sys.argv[sys.argv.index('--') + 1:])
    if output.exists():
        raise RuntimeError('fresh evidence output required')
    source_sha, candidate_sha, png_sha = [digest(path.read_bytes()) for path in [source, candidate, png]]
    errors = []
    bpy.ops.wm.open_mainfile(filepath=str(source.resolve()))
    baseline = snapshot()
    bpy.ops.wm.open_mainfile(filepath=str(candidate.resolve()))
    current = snapshot()
    original_canvas = next(row for row in baseline['materials'] if row['name'] == 'canvas')
    current_canvas = next(row for row in current['materials'] if row['name'] == 'canvas')
    old_nodes = [list(node) for node in original_canvas['nodes']]
    new_nodes = [list(node) for node in current_canvas['nodes']]
    changed = [(old, new) for old, new in zip(old_nodes, new_nodes) if old != new]
    if len(changed) != 1 or changed[0][0][2] != 'antique-hemp-sail.png' or changed[0][1][2] != 'cinnabar-hemp-sail.png' or changed[0][0][:2] != changed[0][1][:2]:
        errors.append('unexpected canvas node image difference')
    current_canvas['nodes'] = original_canvas['nodes']
    if baseline['objects'] != current['objects']:
        errors.append('object structure, transforms, mesh topology, UV or shape keys differ')
    if baseline['materials'] != current['materials']:
        errors.append('material nodes or links differ outside canvas image')
    node = next(node for node in bpy.data.materials['canvas'].node_tree.nodes if node.type == 'TEX_IMAGE')
    packed_sha = digest(bytes(node.image.packed_file.data)) if node.image and node.image.packed_file else None
    if packed_sha != png_sha:
        errors.append('packed candidate PNG differs from supplied image')
    if [digest(path.read_bytes()) for path in [source, candidate, png]] != [source_sha, candidate_sha, png_sha]:
        errors.append('source files changed while inspecting')
    report = {'blender': bpy.app.version_string, 'objectsCompared': len(baseline['objects']),
              'meshObjectsCompared': sum(obj['type'] == 'MESH' for obj in baseline['objects']),
              'materialsCompared': len(baseline['materials']), 'sourceBlendSha256': source_sha,
              'candidateBlendSha256': candidate_sha, 'pngSha256': png_sha, 'packedImageSha256': packed_sha,
              'checks': ['object parent/data/transform', 'mesh vertex positions, topology, material indices, UVs and shape keys',
                         'material names, node types, image names and links'],
              'failures': errors, 'scope': 'Blender authored structure subset and exact packed image; no rendering/gameplay claim'}
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('x', encoding='utf8') as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    print('HERO_R9_BLEND_VERIFY objects=%d materials=%d failures=%d' % (len(baseline['objects']), len(baseline['materials']), len(errors)))
    if errors:
        raise RuntimeError('; '.join(errors))


main()
