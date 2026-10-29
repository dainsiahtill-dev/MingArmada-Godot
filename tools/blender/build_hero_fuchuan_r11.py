"""Inside Blender: author R11 color bands, then patch only R9b canvas COLOR_0."""
import hashlib
import json
import math
import struct
import sys
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/research'))
import verify_hero_r11_delta as check

SOURCE_BLEND = ROOT / 'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r9b.blend'
NEW_BLEND = ROOT / 'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r11.blend'
SOURCE_MANIFEST = check.BASE / 'manifest.json'
MANIFEST = check.TARGET / 'manifest.json'
BRIEF = ROOT / 'docs/production/hero-fuchuan-2026-10-26-art/R11-SAIL-WEATHERING-BRIEF.md'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def f32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


def position_key(point):
    return tuple(0.0 if v == 0.0 else f32(v) for v in point)


def gain(sail, t):
    if not math.isfinite(t) or not 0.0 <= t <= 1.0:
        raise ValueError('nominal sail height outside 0..1')
    knots = check.COEFFICIENTS[sail]
    position = t*8.0
    lower = min(7, int(position))
    u = position-lower
    ease = u*u*(3.0-2.0*u)
    # Keep one prescribed evaluation order across authoring and independent
    # checker: equivalent algebra can round to a different float32 component.
    return knots[lower] + (knots[lower+1]-knots[lower])*ease


def target_color(color, sail, t):
    factor = gain(sail, t)
    return tuple(f32(max(0.0, min(1.0, value*factor))) for value in color)


def prepare_authoring(glb_rows, glb_candidates):
    edits = []
    for sail in range(3):
        obj = bpy.data.objects.get(f'sail_{sail}')
        if obj is None or obj.type != 'MESH': raise ValueError('missing Blender sail mesh')
        mesh = obj.data
        color = mesh.color_attributes.get('SailAge')
        uv = mesh.uv_layers.active
        if color is None or color.domain != 'POINT' or color.data_type != 'FLOAT_COLOR' or uv is None:
            raise ValueError('POINT float SailAge and active UV are required')
        canvas, other, coords = set(), set(), {}
        for polygon in mesh.polygons:
            material = mesh.materials[polygon.material_index]
            for loop_index in polygon.loop_indices:
                vertex = mesh.loops[loop_index].vertex_index
                if material is not None and material.name == 'canvas':
                    canvas.add(vertex)
                    pair = tuple(float(value) for value in uv.data[loop_index].uv)
                    if vertex in coords and coords[vertex] != pair:
                        raise ValueError('Blender canvas vertex has multiple UVs')
                    coords[vertex] = pair
                else: other.add(vertex)
        if canvas & other: raise ValueError('Blender canvas shares vertices with another material')
        row = next(row for row in glb_rows if row['sail'] == sail)
        expected_colors = check.read_accessor(glb_candidates[0], glb_candidates[1], row['accessor'], 3)
        matched = {}
        for position, texcoord, old, result in zip(row['positions'], row['uvs'], row['colors'], expected_colors):
            key = position_key(position)
            if key in matched: raise ValueError('duplicate GLB canvas position')
            matched[key] = (texcoord, old, result)
        if len(canvas) != len(matched): raise ValueError('LOD0 Blender and GLB vertex counts differ')
        for vertex in canvas:
            co = mesh.vertices[vertex].co
            key = position_key((co.x, co.z, -co.y))
            if key not in matched: raise ValueError('author canvas vertex missing from GLB')
            gltf_uv, gltf_color, gltf_result = matched.pop(key)
            author_uv = coords[vertex]
            exported_uv = (f32(author_uv[0]), f32(1.0-author_uv[1]))
            old = tuple(float(value) for value in color.data[vertex].color)
            if exported_uv != gltf_uv or old[:3] != gltf_color:
                raise ValueError('Blender→GLB UV/color is not bit-exact')
            # Canonicalize the authored t through the float32 glTF V flip.
            # Both formats then apply the same authored gain to the same t.
            t = 1.0-exported_uv[1]
            result = target_color(old[:3],sail,t)
            if result != gltf_result:
                raise ValueError('author result differs from GLB float32 result')
            edits.append((color,vertex,result+(old[3],)))
        if matched: raise ValueError('unmatched GLB canvas vertices')
    return edits


def main():
    sources = [check.BASE / f'fuchuan-lod{i}.glb' for i in range(3)]
    outputs = [check.TARGET / f'fuchuan-lod{i}.glb' for i in range(3)]
    if any(path.exists() for path in [NEW_BLEND,MANIFEST,*outputs]):
        raise ValueError('all R11 outputs must be fresh; no existing file was overwritten')
    if Path(bpy.data.filepath).resolve() != SOURCE_BLEND.resolve():
        raise ValueError('must open preserved R9b authoring blend')
    source_manifest_raw = SOURCE_MANIFEST.read_bytes()
    source_manifest = json.loads(source_manifest_raw)
    blend_hash = sha(SOURCE_BLEND.read_bytes())
    if blend_hash != source_manifest['authorBlendSha256']:
        raise ValueError('R9b author blend does not match its frozen manifest')
    texture = ROOT / 'assets/textures/hero_fuchuan_r9/sunfaded-cinnabar-hemp-sail.png'
    texture_hash = sha(texture.read_bytes())
    if texture_hash != source_manifest['pngSha256']:
        raise ValueError('R9b texture differs from its manifest')
    image_node = next(node for node in bpy.data.materials['canvas'].node_tree.nodes if node.type == 'TEX_IMAGE')
    if image_node.image is None or image_node.image.packed_file is None or sha(bytes(image_node.image.packed_file.data)) != texture_hash:
        raise ValueError('Blender authoring PNG is not the original packed image')
    all_candidates = []
    for lod, source in enumerate(sources):
        doc, binary, raw = check.read_glb(source)
        source_hash = sha(raw)
        if source_hash != source_manifest['lods'][lod]['candidateSha256']:
            raise ValueError(f'R9b source LOD{lod} does not match frozen manifest')
        rows = check.selections(doc,binary)
        candidate = bytearray(raw)
        binary_start = len(raw)-len(binary)
        for row in rows:
            for vertex, (old, uv) in enumerate(zip(row['colors'],row['uvs'])):
                result = target_color(old,row['sail'],1.0-uv[1])
                struct.pack_into('<3f',candidate,binary_start+row['start']+vertex*12,*result)
        candidate = bytes(candidate)
        candidate_bin = candidate[binary_start:]
        proof = check.verify_delta(doc,binary,raw,doc,candidate_bin,candidate)
        all_candidates.append({'lod':lod,'path':source,'sourceSha256':source_hash,
                               'output':outputs[lod],'bytes':candidate,'proof':proof,
                               'doc':doc,'binary':candidate_bin,'rows':rows})
    # No mutation of Blender authoring data until every GLB passes its CPU gate.
    lod0 = all_candidates[0]
    edits = prepare_authoring(lod0['rows'],(lod0['doc'],lod0['binary']))
    for color, vertex, values in edits: color.data[vertex].color = values
    if 'FINISHED' not in bpy.ops.wm.save_as_mainfile(filepath=str(NEW_BLEND.resolve()), compress=True):
        raise ValueError('Blender failed to save candidate authoring file')
    if sha(SOURCE_BLEND.read_bytes())!=blend_hash or sha(texture.read_bytes())!=texture_hash or sha(SOURCE_MANIFEST.read_bytes())!=sha(source_manifest_raw):
        raise ValueError('baseline authoring or texture changed during build')
    check.TARGET.mkdir(parents=True,exist_ok=True)
    models=[]
    for row in all_candidates:
        if sha(row['path'].read_bytes())!=row['sourceSha256']:raise ValueError('baseline GLB changed during build')
        with row['output'].open('xb') as stream:stream.write(row['bytes'])
        models.append({'lod':row['lod'],'source':row['path'].relative_to(ROOT).as_posix(),
                       'sourceSha256':row['sourceSha256'],'candidate':row['output'].relative_to(ROOT).as_posix(),
                       'candidateSha256':sha(row['bytes']),'canvas':row['proof']['sails']})
    manifest={'asset':'hero-fuchuan-v3-r11','baseline':'hero-fuchuan-v3-r9b',
              'sourceBlend':SOURCE_BLEND.relative_to(ROOT).as_posix(),'sourceBlendSha256':blend_hash,
              'authorBlend':NEW_BLEND.relative_to(ROOT).as_posix(),'authorBlendSha256':sha(NEW_BLEND.read_bytes()),
              'png':texture.relative_to(ROOT).as_posix(),'pngSha256':texture_hash,
              'briefSha256BeforeBuild':sha(BRIEF.read_bytes()),'builderSha256':sha(Path(__file__).read_bytes()),
              'checkerSha256':sha(Path(check.__file__).read_bytes()),'coefficients':check.COEFFICIENTS,
              'interpolation':'smoothstep between nine nominal-UV height knots; linear RGB clamped to 0..1',
              'construction':'Blender authoring file with canvas POINT SailAge edits; GLBs are original R9b bytes with only exclusive canvas COLOR_0 float32 values changed',
              'lods':models,'formalProviderUnchanged':True,
              'scope':'CPU provenance candidate; no GPU, performance or gameplay acceptance'}
    with MANIFEST.open('x',encoding='utf8') as stream:json.dump(manifest,stream,ensure_ascii=False,indent=2);stream.write('\n')
    print(f'HERO_R11_BUILD_COMPLETE lods=3 authoredVertices={len(edits)} unchangedBaseline=true')


if __name__=='__main__':main()
