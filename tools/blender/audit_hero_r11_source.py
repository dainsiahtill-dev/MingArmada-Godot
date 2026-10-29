"""Read-only Blender/GLB vertex, UV and linear-color correspondence audit."""
import hashlib
import json
import struct
import sys
from pathlib import Path
import bpy


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def f32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


def accessor(doc, binary, index, width):
    item = doc['accessors'][index]
    view = doc['bufferViews'][item['bufferView']]
    if item.get('componentType') != 5126 or item.get('type') != f'VEC{width}' or 'sparse' in item:
        raise ValueError('expected float32 vector accessor')
    start = view.get('byteOffset', 0) + item.get('byteOffset', 0)
    stride = view.get('byteStride', width * 4)
    if start < 0 or item['count'] and start + (item['count'] - 1) * stride + width * 4 > len(binary):
        raise ValueError('accessor exceeds binary')
    return [struct.unpack_from('<' + 'f' * width, binary, start + i * stride) for i in range(item['count'])]


def glb(path):
    raw = path.read_bytes()
    magic, version, length = struct.unpack_from('<4sII', raw)
    if magic != b'glTF' or version != 2 or length != len(raw):
        raise ValueError('invalid GLB header')
    size, kind = struct.unpack_from('<II', raw, 12)
    if kind != 0x4e4f534a:
        raise ValueError('JSON chunk missing')
    doc = json.loads(raw[20:20 + size])
    bin_size, bin_kind = struct.unpack_from('<II', raw, 20 + size)
    if bin_kind != 0x004e4942 or 28 + size + bin_size != len(raw):
        raise ValueError('BIN chunk malformed')
    return doc, raw[28 + size:]


def point_key(point):
    return tuple(0.0 if value == 0.0 else f32(value) for value in point)


def main():
    blend, model, output = map(Path, sys.argv[sys.argv.index('--') + 1:])
    if output.exists():
        raise ValueError('fresh output required')
    before = [digest(path) for path in (blend, model)]
    if Path(bpy.data.filepath).resolve() != blend.resolve():
        raise ValueError('open the stated baseline blend first')
    doc, binary = glb(model)
    errors, rows = [], []
    for i in range(3):
        name = f'sail_{i}'
        obj = bpy.data.objects.get(name)
        if obj is None or obj.type != 'MESH':
            errors.append(f'{name}: Blender mesh missing');continue
        mesh = obj.data
        color = mesh.color_attributes.get('SailAge')
        uv = mesh.uv_layers.active
        if color is None or color.domain != 'POINT' or color.data_type != 'FLOAT_COLOR' or uv is None:
            errors.append(f'{name}: missing POINT float color or UV');continue
        canvas, other = set(), set()
        uvs = {}
        for face in mesh.polygons:
            material = mesh.materials[face.material_index]
            for loop_id in face.loop_indices:
                vertex = mesh.loops[loop_id].vertex_index
                if material and material.name == 'canvas':
                    canvas.add(vertex)
                    uv_value = tuple(float(x) for x in uv.data[loop_id].uv)
                    if vertex in uvs and uvs[vertex] != uv_value:
                        errors.append(f'{name}: canvas vertex {vertex} has multiple UVs')
                    uvs[vertex] = uv_value
                else:
                    other.add(vertex)
        if canvas & other:
            errors.append(f'{name}: canvas shares {len(canvas & other)} vertices with another material')
        authored = {}
        for vertex in canvas:
            co = mesh.vertices[vertex].co
            key = point_key((co.x, co.z, -co.y))
            if key in authored:
                errors.append(f'{name}: duplicate authored canvas position')
            authored[key] = {'uv': uvs[vertex], 'rgb': tuple(float(x) for x in color.data[vertex].color[:3])}
        nodes = [node for node in doc['nodes'] if node.get('name') == name and 'mesh' in node]
        if len(nodes) != 1:
            errors.append(f'{name}: GLB node not unique');continue
        prims = [p for p in doc['meshes'][nodes[0]['mesh']]['primitives'] if doc['materials'][p['material']].get('name') == 'canvas']
        if len(prims) != 1:
            errors.append(f'{name}: canvas primitive not unique');continue
        attributes = prims[0]['attributes']
        positions = accessor(doc, binary, attributes['POSITION'], 3)
        coords = accessor(doc, binary, attributes['TEXCOORD_0'], 2)
        colors = accessor(doc, binary, attributes['COLOR_0'], 3)
        if len(positions) != len(coords) or len(positions) != len(colors):
            errors.append(f'{name}: GLB accessor count mismatch');continue
        missing = uv_mismatch = color_mismatch = 0
        max_uv_diff = max_color_diff = 0.0
        for position, gltf_uv, rgb in zip(positions, coords, colors):
            old = authored.get(point_key(position))
            if old is None:
                missing += 1;continue
            uv_expected = (f32(old['uv'][0]), f32(1.0 - old['uv'][1]))
            max_uv_diff = max(max_uv_diff, *(abs(a-b) for a,b in zip(uv_expected,gltf_uv)))
            max_color_diff = max(max_color_diff, *(abs(a-b) for a,b in zip(old['rgb'],rgb)))
            if uv_expected != gltf_uv: uv_mismatch += 1
            if old['rgb'] != rgb: color_mismatch += 1
        if missing or uv_mismatch or color_mismatch or len(authored) != len(positions):
            errors.append(f'{name}: correspondence differs missing={missing} UV={uv_mismatch} COLOR={color_mismatch}')
        rows.append({'sail':name,'blenderCanvasVertices':len(canvas),'gltfCanvasVertices':len(positions),
                     'sharedWithNonCanvas':len(canvas & other),'missing':missing,'uvMismatch':uv_mismatch,
                     'colorMismatch':color_mismatch,'maxUvDifference':max_uv_diff,'maxColorDifference':max_color_diff})
    if [digest(path) for path in (blend, model)] != before:
        errors.append('source changed during inspection')
    report = {'scope':'read-only exact Blender point UV and linear color vs LOD0 raw glTF; no render or production change',
              'sourceBlendSha256':before[0],'sourceGlbSha256':before[1], 'rows':rows,'failures':errors}
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('x', encoding='utf8') as stream:
        json.dump(report,stream,ensure_ascii=False,indent=2);stream.write('\n')
    print(f'R11_BLEND_SOURCE_AUDIT sails={len(rows)} failures={len(errors)}')
    if errors:
        for message in errors: print('FAIL:',message)
        raise RuntimeError('source correspondence audit failed')


main()
