"""Independent R8a proxy-top candidate; immutable R6 builders and R7c inputs.

Blender --background --python this_file -- --review-run=unique --export-only
Python this_file --self-test checks the exact tuple-edit boundary without bpy.
"""
import hashlib
import importlib.util
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/models/hero_fuchuan_v3_r8a'
SOURCE = ROOT / 'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r8a.blend'
TEXTURE = ROOT / 'assets/textures/hero_fuchuan_r7/sunwashed-teak.png'
CANONICALIZER = ROOT / 'tools/blender/canonicalize_palette_uv.py'
REFERENCE = ROOT / 'assets/models/hero_fuchuan_v3_r7c'
BROAD = {'Solid gun bulwark', 'Tapered stern side', 'stern_transom', 'Stern forward bulkhead'}
MID = {'Faired hull strake', 'Shaped stern transom', 'Gunport sill', 'Gunport jamb',
       'Deep window reveal jamb', 'Deep window reveal sill', 'Window side frame',
       'Window cross frame', 'Door jamb', 'Door lintel', 'Cabin corner stile'}
TARGETS = {'Closed shadow shell', 'Shadow bulwark with open gunports', 'shadow_deck'}


def adjusted_vertices(name, vertices, sheer):
    original = [tuple(v) for v in vertices]
    if name == 'Closed shadow shell':
        assert len(original) == 21 * 13, 'unexpected shell ring count/layout'
        indices = [j * 13 + i for j in range(21) for i in (5, 6, 7)]
        distance = .036
    elif name == 'shadow_deck':
        assert len(original) == 13 * 4, 'unexpected deck ring count/layout'
        indices = [j * 4 + i for j in range(13) for i in (0, 1)]
        distance = .004
    elif name == 'Shadow bulwark with open gunports':
        assert len(original) == 8, 'unexpected bulwark block layout'
        indices = [i for i, vertex in enumerate(original)
                   if math.isclose(vertex[1], sheer(vertex[2]), rel_tol=0, abs_tol=1e-10)]
        assert indices in ([], [0, 1, 4, 5]), 'only original sheer bottom edges may move'
        distance = .036
    else:
        return original, []
    modified = list(original)
    for index in indices:
        x, y, z = original[index]
        modified[index] = (x, y - distance, z)
    assert all(after[0] == before[0] and after[2] == before[2]
               for before, after in zip(original, modified))
    assert [i for i, pair in enumerate(zip(original, modified)) if pair[0] != pair[1]] == indices
    return modified, indices


def self_test():
    sheer = lambda z: 2.0 + z * z * .001
    shell = [(float(i % 13), 4.0, float(i // 13)) for i in range(21 * 13)]
    changed, indices = adjusted_vertices('Closed shadow shell', shell, sheer)
    assert indices == [j * 13 + i for j in range(21) for i in (5, 6, 7)]
    for index, (before, after) in enumerate(zip(shell, changed)):
        assert after == (before[0], before[1] - (.036 if index in indices else 0), before[2])
    deck = [(float(i % 4), 4.5 if i % 4 < 2 else 4.33, float(i // 4)) for i in range(13 * 4)]
    changed, indices = adjusted_vertices('shadow_deck', deck, sheer)
    assert indices == [j * 4 + i for j in range(13) for i in (0, 1)]
    assert all(after == (before[0], before[1] - (.004 if i in indices else 0), before[2])
               for i, (before, after) in enumerate(zip(deck, changed)))
    for low, expected in [(sheer(3), [0, 1, 4, 5]), (2.76, [])]:
        block = [(0, low, 3), (1, low, 3), (1, 3.2, 3), (0, 3.2, 3),
                 (0.1, low, 3), (0.9, low, 3), (0.9, 3.2, 3), (0.1, 3.2, 3)]
        changed, indices = adjusted_vertices('Shadow bulwark with open gunports', block, sheer)
        assert indices == expected
        assert all(changed[i] == block[i] for i in (2, 3, 6, 7))
    for name, count in [('Closed shadow shell', 272), ('shadow_deck', 51),
                        ('Shadow bulwark with open gunports', 7)]:
        try:
            adjusted_vertices(name, [(0, 0, 0)] * count, sheer)
        except AssertionError:
            pass
        else:
            raise AssertionError('malformed target was not rejected: ' + name)
    assert adjusted_vertices('visible hull', [(1, 2, 3)], sheer) == ([(1, 2, 3)], [])
    print('HERO_FUCHUAN_R8_TUPLE_TEST_OK')


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def review_run():
    names = [arg.split('=', 1)[1] for arg in sys.argv if arg.startswith('--review-run=')]
    assert len(names) == 1 and names[0] and Path(names[0]).name == names[0], 'one safe --review-run is required'
    return names[0]


def launch_build():
    """Capture Blender combined output without PowerShell native-stderr coercion."""
    import subprocess
    from datetime import datetime, timezone
    blender = Path('C:/Tools/blender-5.4.0-alpha+main.fbe82a461016-windows.amd64-release/blender.exe')
    evidence = ROOT / 'docs/production/hero-fuchuan-2026-10-26-art' / review_run()
    if OUT.exists() or SOURCE.exists() or evidence.exists():
        raise RuntimeError('candidate or review output exists; preserve it and use a new version')
    arguments = [str(blender), '--background', '--python-exit-code', '1', '--python',
                 str(Path(__file__).resolve()), '--', '--review-run=' + review_run(),
                 '--refine-stern', '--export-only']
    started = datetime.now(timezone.utc).isoformat()
    result = subprocess.run(arguments, cwd=ROOT, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, check=False)
    finished = datetime.now(timezone.utc).isoformat()
    evidence.mkdir(parents=True, exist_ok=True)
    log = evidence / 'blender-build.log'
    log.write_bytes(result.stdout)
    marker = b'HERO_FUCHUAN_R8_PROXY_OK' in result.stdout
    receipt = {'command': arguments, 'cwd': str(ROOT), 'startedUTC': started,
               'finishedUTC': finished, 'processExitCode': result.returncode,
               'successMarkerPresent': marker, 'success': result.returncode == 0 and marker,
               'stdoutAndStderr': log.relative_to(ROOT).as_posix(),
               'logSHA256': sha256(log), 'blenderExecutableSHA256': sha256(blender),
               'wrapperSHA256': sha256(__file__),
               'scope': 'background export only; no Godot/GPU/native acceptance'}
    (evidence / 'blender-process.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    print(result.stdout.decode('utf-8', errors='replace')[-6500:])
    print(json.dumps(receipt, indent=2))
    if not receipt['success']:
        raise SystemExit(result.returncode or 1)


def main():
    import bpy
    import struct
    if OUT.exists() or SOURCE.exists():
        raise RuntimeError('R8a output already exists; preserve it and use a new version')
    run = review_run()
    evidence = ROOT / 'docs/production/hero-fuchuan-2026-10-26-art' / run
    if evidence.exists():
        raise RuntimeError('review evidence already exists; preserve it')
    if '--refine-stern' not in sys.argv:
        sys.argv.append('--refine-stern')
    self_test()
    watched = [ROOT / 'tools/blender/build_hero_fuchuan_v3.py',
               ROOT / 'tools/blender/build_hero_fuchuan.py',
               ROOT / 'tools/blender/build_hero_fuchuan_r7_palette.py', CANONICALIZER,
               ROOT / 'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r6.blend',
               ROOT / 'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r7c.blend',
               ROOT / 'docs/production/hero-fuchuan-2026-10-26-art/v3-r7c-palette-01/palette-build.json']
    for folder in ['assets/models/hero_fuchuan_v3_r6', 'assets/models/hero_fuchuan_v3_r7c',
                   'assets/textures/hero_fuchuan_v2', 'assets/textures/hero_fuchuan_r7']:
        watched.extend(path for path in sorted((ROOT / folder).iterdir())
                       if path.is_file() and path.suffix in {'.glb', '.png', '.json'})
    before = {path.relative_to(ROOT).as_posix(): sha256(path) for path in watched}
    texture_provenance = json.loads((TEXTURE.parent / 'provenance.json').read_text(encoding='utf-8'))
    assert texture_provenance['sha256'] == sha256(TEXTURE), 'generated raw texture hash differs'
    old_recipe = json.loads(watched[6].read_text(encoding='utf-8'))
    assert old_recipe['wrapperSHA256'] == sha256(watched[2]), 'R7 palette recipe no longer matches its receipt'
    for key, expected in old_recipe['sourcesAfter'].items():
        assert before[key] == expected, 'R6 original differs from R7c receipt: ' + key
    spec = importlib.util.spec_from_file_location('hero_r6', watched[0])
    R6 = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(R6)
    B = R6.B
    assert R6.REFINED
    B.OUT = OUT
    B.OUT.mkdir(parents=True)
    B.BLEND_NAME = SOURCE.name
    B.ASSET = 'hero-fuchuan-v3-r8a'
    original_setup, original_mesh, original_curve, original_build = B.setup_materials, B.mesh, B.curve, B.build
    assignments, edits, lod_checks = {}, [], []

    def record(name, original, replacement):
        key = f'{name}: {original}->{replacement}'
        assignments[key] = assignments.get(key, 0) + 1

    def new_wood(name, gain):
        # Exact R7c material construction; original image_gen pixels, no edits.
        material = B.MATS['teak'].copy()
        material.name = name
        tree = material.node_tree
        texture = next(node for node in tree.nodes if node.type == 'TEX_IMAGE')
        texture.image = bpy.data.images.load(str(TEXTURE), check_existing=True)
        texture.image.colorspace_settings.name = 'sRGB'
        texture.image.pack()
        bsdf = tree.nodes.get('Principled BSDF')
        if gain != (1, 1, 1):
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

    def uv_bytes(obj):
        return b''.join(struct.pack('<2f', *value.uv) for value in obj.data.uv_layers.active.data)

    def mesh(name, vertices, faces, mat='teak', parent=None):
        originals = [tuple(vertex) for vertex in vertices] if name in TARGETS else vertices
        # Original UV construction must see original input, original material.
        obj = original_mesh(name, originals, faces, mat, parent)
        if name in TARGETS:
            assert mat == 'pitch', 'proxy source material changed'
            modified, indices = adjusted_vertices(name, originals, R6.sheer)
            expected_faces = {'Closed shadow shell': 262, 'Shadow bulwark with open gunports': 6, 'shadow_deck': 50}
            assert len(obj.data.polygons) == expected_faces[name]
            old_uv = uv_bytes(obj)
            old_topology = [tuple(polygon.vertices) for polygon in obj.data.polygons]
            for index in indices:
                old_coordinate = obj.data.vertices[index].co.copy()
                obj.data.vertices[index].co = B.point(modified[index])
                new_coordinate = obj.data.vertices[index].co
                assert new_coordinate.x == old_coordinate.x and new_coordinate.y == old_coordinate.y
            obj.data.update()
            assert uv_bytes(obj) == old_uv, 'original proxy UV bytes changed'
            assert old_topology == [tuple(polygon.vertices) for polygon in obj.data.polygons]
            edits.append({'lod': B.LOD, 'label': name, 'vertices': len(originals),
                          'faces': len(faces), 'changedVertexCount': len(indices), 'changedIndices': indices,
                          'changedTuples': [{'index': i, 'before': originals[i], 'after': modified[i]} for i in indices],
                          'UVSHA256Before': hashlib.sha256(old_uv).hexdigest(),
                          'UVSHA256After': hashlib.sha256(uv_bytes(obj)).hexdigest(),
                          'topologySHA256': hashlib.sha256(json.dumps(old_topology).encode()).hexdigest()})
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

    # Independently derive expected block calls from the unchanged R6 section rules.
    ports = [32 * (-.138 + i * .092) for i in range(4)]
    breaks = sorted(set([-16 + 32 * j / 20 for j in range(21)] + [z + d for z in ports for d in [-.58, .58]]))
    blocks, moved_blocks = 0, 0
    for _side in [-1, 1]:
        for za, zb in zip(breaks, breaks[1:]):
            opening = any(abs((za + zb) / 2 - z) < .58 for z in ports)
            for section in (['bottom', 'top'] if opening else ['whole']):
                lowa, lowb = R6.sheer(za), R6.sheer(zb)
                higha, highb = lowa + .94, lowb + .94
                if section == 'bottom':
                    higha = highb = 1.99
                if section == 'top':
                    lowa = lowb = 2.76
                if min(higha - lowa, highb - lowb) < .015:
                    continue
                blocks += 1
                moved_blocks += section != 'top'

    def build(lod):
        root, path = original_build(lod)
        calls = [edit for edit in edits if edit['lod'] == lod]
        shells = [edit for edit in calls if edit['label'] == 'Closed shadow shell']
        decks = [edit for edit in calls if edit['label'] == 'shadow_deck']
        walls = [edit for edit in calls if edit['label'] == 'Shadow bulwark with open gunports']
        assert len(shells) == len(decks) == 1 and len(walls) == blocks
        assert shells[0]['changedVertexCount'] == 63 and decks[0]['changedVertexCount'] == 26
        assert sum(edit['changedVertexCount'] for edit in walls) == moved_blocks * 4
        proxies = sorted(obj.name for obj in bpy.context.scene.objects if obj.get('hero_shadow_resource'))
        expected = ['shadow_deck', 'shadow_hull', 'shadow_mast_timber_0', 'shadow_mast_timber_1', 'shadow_mast_timber_2']
        assert proxies == expected, 'all five original proxy nodes must survive'
        lod_checks.append({'lod': lod, 'proxyNodes': proxies, 'shellChangedVertices': 63,
                           'deckChangedVertices': 26, 'bulwarkBlocks': blocks,
                           'bulwarkMovedBlocks': moved_blocks, 'bulwarkChangedVertices': moved_blocks * 4,
                           'closedProxyAssertion': 'unchanged R6.shadow_resource bmesh assertion ran before export'})
        return root, path

    B.setup_materials, B.mesh, B.curve, B.build = setup_materials, mesh, curve, build
    B.main()
    assert assignments == old_recipe['materialAssignments'], 'R7c material partition call counts changed'
    manifest_path = OUT / 'manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    uv_spec = importlib.util.spec_from_file_location('palette_uv', CANONICALIZER)
    uv_module = importlib.util.module_from_spec(uv_spec)
    uv_spec.loader.exec_module(uv_module)
    canonicalization = []
    for entry in manifest['lods']:
        candidate = ROOT / entry['path']
        receipt = uv_module.canonicalize_rudder_uv(REFERENCE / candidate.name, candidate)
        receipt['lod'] = entry['lod']
        canonicalization.append(receipt)
        entry['sha256'] = sha256(candidate)
        entry['bytes'] = candidate.stat().st_size
    manifest.update({'provenance': 'Unchanged R6 visible geometry and exact R7c palette recipe; local pre-join hidden proxy top edits only',
                     'textureProvenance': 'assets/textures/hero_fuchuan_r7/provenance.json',
                     'retainedTextureProvenance': 'assets/textures/hero_fuchuan_v2/provenance.json',
                     'paletteVariant': 'r7c', 'proxyVariant': 'r8a',
                     'rudderUVCanonicalization': canonicalization})
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    after = {path.relative_to(ROOT).as_posix(): sha256(path) for path in watched}
    assert before == after, 'original source/resource changed during candidate build'
    proof = {'scope': 'R8a hidden proxy local top edits; independent non-production candidate',
             'wrapperSHA256': sha256(__file__), 'sourceBlendSHA256': sha256(SOURCE),
             'sourcesBefore': before, 'sourcesAfter': after, 'oldResourcesUnchanged': before == after,
             'materialRecipeSource': watched[2].relative_to(ROOT).as_posix(),
             'materialRecipeSourceSHA256': sha256(watched[2]),
             'materialRecipePolicy': 'Exact copied R7c new_wood setup and BROAD/MID assignments; original teak before replacement',
             'materialAssignments': assignments,
             'materialGainsLinear': {'sunwashed_teak': [1, 1, 1], 'aged_hull_teak': [.68, .65, .61]},
             'texture': TEXTURE.relative_to(ROOT).as_posix(), 'textureSHA256': sha256(TEXTURE),
             'textureGeneratedRawSHA256': texture_provenance['sha256'], 'texturePixelEdits': texture_provenance['pixelEdits'],
             'ruling': 'Build original mesh from original tuples/material first, then update only selected vertex coordinates before R6 join/recalc; original UV bytes must remain exact',
             'coordinateBasis': 'Input (X,Y,Z) is Godot Y-up meters; B.point gives Blender (X,-Z,Y); only authored Y / Blender Z changes',
             'hullTopDeltaMeters': -.036, 'deckTopDeltaMeters': -.004,
             'lodChecks': lod_checks, 'preJoinEdits': edits,
             'rudderUVCanonicalization': canonicalization, 'commandArguments': sys.argv,
             'limitations': ['No full hull footprint/containment proof implied by local top edits',
                             'No Godot/GPU/native/continuous-motion or art acceptance implied by background export',
                             'No production provider/default entrypoint integration',
                             'Retained generated wood texture not certified strictly seamless']}
    (B.EVIDENCE / 'proxy-build.json').write_text(json.dumps(proof, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('HERO_FUCHUAN_R8_PROXY_OK ' + json.dumps({'sourceSHA256': sha256(SOURCE), 'lodChecks': lod_checks,
                                                'oldResourcesUnchanged': True}))


if __name__ == '__main__':
    if '--self-test' in sys.argv:
        self_test()
    elif '--launch-build' in sys.argv:
        launch_build()
    else:
        main()
