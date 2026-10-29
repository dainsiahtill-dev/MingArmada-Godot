"""Independent R7 material partition; unchanged R6 geometry/UV generation.

Blender --background --python this_file -- --review-run=unique [--export-only]
The R6 builder, source Blend and GLBs are never overwritten.
"""
import bpy
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VARIANT = next((a.split('=', 1)[1] for a in sys.argv if a.startswith('--variant=')), 'r7b')
if VARIANT not in ['r7a', 'r7b', 'r7c']:
    raise RuntimeError('unsupported palette output version')
OUT = ROOT / f'assets/models/hero_fuchuan_v3_{VARIANT}'
SOURCE = ROOT / f'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-{VARIANT}.blend'
TEXTURE = ROOT / 'assets/textures/hero_fuchuan_r7/sunwashed-teak.png'
CANONICALIZER = ROOT / 'tools/blender/canonicalize_palette_uv.py'
canonicalizer_before = hashlib.sha256(CANONICALIZER.read_bytes()).hexdigest() if VARIANT == 'r7c' else None
if OUT.exists() or SOURCE.exists():
    raise RuntimeError('R7a output already exists; preserve it and use a new version')
if '--refine-stern' not in sys.argv:
    sys.argv.append('--refine-stern')
spec = importlib.util.spec_from_file_location('hero_r6', ROOT / 'tools/blender/build_hero_fuchuan_v3.py')
R6 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(R6)
B = R6.B
WATCHED = [ROOT / 'tools/blender/build_hero_fuchuan_v3.py', ROOT / 'tools/blender/build_hero_fuchuan.py',
           ROOT / 'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r6.blend']
WATCHED += sorted((ROOT / 'assets/models/hero_fuchuan_v3_r6').glob('*.glb'))
WATCHED += sorted((ROOT / 'assets/textures/hero_fuchuan_v2').glob('*.png'))


def hashes():
    return {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in WATCHED}


before = hashes()
B.OUT = OUT
B.OUT.mkdir(parents=True)
B.BLEND_NAME = SOURCE.name
B.ASSET = 'hero-fuchuan-v3-' + VARIANT
original_setup = B.setup_materials
assignments = {}


def new_wood(name, gain):
    material = B.MATS['teak'].copy()
    material.name = name
    tree = material.node_tree
    texture = next(node for node in tree.nodes if node.type == 'TEX_IMAGE')
    texture.image = bpy.data.images.load(str(TEXTURE), check_existing=True)
    texture.image.colorspace_settings.name = 'sRGB'
    texture.image.pack()
    bsdf = tree.nodes.get('Principled BSDF')
    if gain != (1, 1, 1):
        # Blender's glTF exporter recognizes modern MIX/RGBA constant factors;
        # the legacy MIX_RGB node was rendered by Blender but omitted in R7a.
        multiply = tree.nodes.new('ShaderNodeMix')
        multiply.data_type = 'RGBA'
        multiply.blend_type = 'MULTIPLY'
        multiply.inputs[0].default_value = 1
        multiply.inputs[7].default_value = (*gain, 1)
        tree.links.new(texture.outputs['Color'], multiply.inputs[6])
        tree.links.new(multiply.outputs[2], bsdf.inputs['Base Color'])
    B.MATS[name] = material


def setup_materials():
    original_setup()
    new_wood('sunwashed_teak', (1, 1, 1))
    new_wood('aged_hull_teak', (.68, .65, .61))


original_mesh = B.mesh
original_curve = B.curve
BROAD = {'Solid gun bulwark', 'Tapered stern side', 'stern_transom', 'Stern forward bulkhead'}
MID = {'Faired hull strake', 'Shaped stern transom', 'Gunport sill', 'Gunport jamb',
       'Deep window reveal jamb', 'Deep window reveal sill', 'Window side frame',
       'Window cross frame', 'Door jamb', 'Door lintel', 'Cabin corner stile'}


def record(name, original, replacement):
    key = f'{name}: {original}->{replacement}'
    assignments[key] = assignments.get(key, 0) + 1


def mesh(name, vertices, faces, mat='teak', parent=None):
    # Build original topology, normals and UV axis choice before changing a slot.
    obj = original_mesh(name, vertices, faces, mat, parent)
    replacement = 'sunwashed_teak' if mat == 'teak' and name in BROAD else 'aged_hull_teak' if mat == 'teak' and name in MID else mat
    if replacement != mat:
        obj.data.materials[0] = B.MATS[replacement]
        record(name, mat, replacement)
    return obj


def curve(name, points, radius=.035, mat='hemp', parent=None):
    replacement = 'aged_hull_teak' if mat == 'teak' and name == 'External frame head' else mat
    if replacement != mat:
        record(name, mat, replacement)
    return original_curve(name, points, radius, replacement, parent)


B.setup_materials = setup_materials
B.mesh = mesh
B.curve = curve
B.main()
manifest_path = OUT / 'manifest.json'
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
canonicalization = []
if VARIANT == 'r7c':
    uv_spec = importlib.util.spec_from_file_location('palette_uv', CANONICALIZER)
    uv_module = importlib.util.module_from_spec(uv_spec)
    uv_spec.loader.exec_module(uv_module)
    for entry in manifest['lods']:
        candidate = ROOT / entry['path']
        reference = ROOT / f"assets/models/hero_fuchuan_v3_r6/fuchuan-lod{entry['lod']}.glb"
        receipt = uv_module.canonicalize_rudder_uv(reference, candidate)
        receipt['lod'] = entry['lod']
        canonicalization.append(receipt)
        entry['sha256'] = hashlib.sha256(candidate.read_bytes()).hexdigest()
manifest.update({'provenance': 'Original R6 geometry with partitioned materials; retained four image_gen base colors plus one new image_gen sunwashed wood and retained procedural tar',
                 'retainedTextureProvenance': 'assets/textures/hero_fuchuan_v2/provenance.json',
                 'textureProvenance': 'assets/textures/hero_fuchuan_r7/provenance.json',
                 'paletteVariant': VARIANT})
manifest['rudderUVCanonicalization'] = canonicalization
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
after = hashes()
if before != after:
    raise RuntimeError('R6 source/resource changed during R7 build')
if VARIANT == 'r7c' and hashlib.sha256(CANONICALIZER.read_bytes()).hexdigest() != canonicalizer_before:
    raise RuntimeError('UV canonicalizer changed during R7 build')
proof = {'scope': 'R7 material partitions only; geometry generated by unchanged R6 functions',
         'variant': VARIANT, 'wrapperSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
         'canonicalizerSHA256': canonicalizer_before,
         'sourcesBefore': before, 'sourcesAfter': after, 'oldResourcesUnchanged': before == after,
         'texture': TEXTURE.relative_to(ROOT).as_posix(),
         'textureSHA256': hashlib.sha256(TEXTURE.read_bytes()).hexdigest(),
         'materialAssignments': assignments, 'commandArguments': sys.argv,
         'rudderUVCanonicalization': canonicalization,
         'materialGainsLinear': {'sunwashed_teak': [1, 1, 1], 'aged_hull_teak': [.68, .65, .61]},
         'limitations': ['New texture not certified strictly seamless', 'No GPU/game acceptance implied by export']}
(B.EVIDENCE / 'palette-build.json').write_text(json.dumps(proof, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('HERO_FUCHUAN_R7_PALETTE_OK')
