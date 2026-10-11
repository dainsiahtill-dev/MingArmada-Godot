"""Import the parsed cannon splash evidence without modifying its reference tree.

Output keeps the exact exported local geometry/keys/parameters. Scene-to-metre
scale, seeded variation and particle allocation are Godot presentation choices.
"""
from pathlib import Path
import hashlib
import json
import math

ROOT = Path(__file__).resolve().parents[1]
REF = Path('C:/Games/Pirates-REA-Reference-20261011')
STUDY = REF / 'naval-study'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def matrix(fields):
    r = fields['rotation']
    return [[r[f'm_{row}{column}'] * fields['scale'] for column in range(1, 4)] for row in range(1, 4)]

def mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]

def vector(a, p):
    return [sum(a[i][j] * p[j] for j in range(3)) for i in range(3)]

def xyz(v):
    return [v[k] for k in 'xyz']

def main():
    geometry_path = STUDY / 'selected-geometry.json'
    complete_path = STUDY / 'deep/asset-details/complete-assets.json'
    particle_path = STUDY / 'deep/asset-details/particle-systems.json'
    asset = next(a for a in json.loads(complete_path.read_text(encoding='utf-8'))['assets'] if a['name'] == 'cannon_ball_splash.nif')
    blocks = {b['id']: b for b in asset['blocks']}
    ref = lambda value: blocks[value['ref']] if value else None
    geometries = [g for g in json.loads(geometry_path.read_text(encoding='utf-8'))['meshes'] if g['asset'] == asset['name']]
    systems = [s for s in json.loads(particle_path.read_text(encoding='utf-8')) if s['name'] == asset['name']]

    def texture(properties):
        prop = next(ref(p) for p in properties if p['type'] == 'NiTexturingProperty')
        return ref(prop['fields']['base_texture']['source'])['fields']['file_name'] + '.png'

    def group_keys(group):
        assert group['interpolation'] == 1, 'This importer requires authored linear keys'
        return group['keys']

    def world_transform(node_id):
        block = blocks[node_id]
        local = matrix(block['fields'])
        point = xyz(block['fields']['translation'])
        if not block['parent_nodes']:
            return local, point
        assert len(block['parent_nodes']) == 1
        parent, translation = world_transform(block['parent_nodes'][0])
        rotated = vector(parent, point)
        return mul(parent, local), [rotated[i]+translation[i] for i in range(3)]

    meshes = []
    for mesh in geometries:
        block = blocks[mesh['block_id']]
        material = next(ref(p) for p in block['fields']['properties'] if p['type'] == 'NiMaterialProperty')
        alpha = ref(material['fields']['controller'])
        tex = next(ref(p) for p in block['fields']['properties'] if p['type'] == 'NiTexturingProperty')
        uv = ref(tex['fields']['controller'])
        parent = blocks[block['parent_nodes'][0]]
        animation = {}
        if parent['fields']['controller']:
            controller = ref(parent['fields']['controller'])
            keys = ref(controller['fields']['data'])['fields']
            assert keys['rotation_type'] == 4
            animation = {'translations': group_keys(keys['translations']), 'scales': group_keys(keys['scales']), 'rotations': [group_keys(g) for g in keys['xyz_rotations']]}
        meshes.append({**mesh, 'texture': texture(block['fields']['properties']), 'alphaKeys': group_keys(ref(alpha['fields']['data'])['fields']['data']) if alpha else [], 'alpha': material['fields']['alpha'], 'uvKeys': group_keys(ref(uv['fields']['data'])['fields']['data']) if uv else [], 'uvOperation': uv['fields']['operation'] if uv else None, 'animation': animation})

    particles = []
    for system in systems:
        modifier = lambda kind: next(m for m in system['modifiers'] if m['type'] == kind)
        emitter = modifier('NiPSysBoxEmitter')['fields']
        gravity = modifier('NiPSysGravityModifier')['fields']
        grow = modifier('NiPSysGrowFadeModifier')['fields']
        color = ref(modifier('NiPSysColorModifier')['fields']['data'])['fields']['data']
        controller = next(c for c in system['controllers'] if c['type'] == 'NiPSysEmitterCtlr')
        emitter_matrix, emitter_point = world_transform(emitter['emitter_object']['ref'])
        gravity_matrix, _ = world_transform(gravity['gravity_object']['ref'])
        acceleration = [v*gravity['strength'] for v in vector(gravity_matrix, xyz(gravity['gravity_axis']))]
        particles.append({'id': system['system']['id'], 'capacity': system['data']['fields']['num_vertices'], 'worldSpace': system['system']['fields']['world_space'], 'texture': texture(system['system']['fields']['properties']), 'emitter': emitter, 'gravity': gravity, 'grow': grow, 'birthRateKeys': group_keys(controller['data']['fields']['float_keys']), 'enabledKeys': controller['data']['fields']['visibility_keys'], 'colorKeys': group_keys(color), 'emitterMatrix': emitter_matrix, 'emitterTranslation': emitter_point, 'acceleration': acceleration, 'modifierOrder': [[m['id'], m['type'], m['fields']['order']] for m in system['modifiers']], 'modifierEvidence': [{'id': m['id'], 'type': m['type'], 'fields': m['fields']} for m in system['modifiers']], 'controllerEvidence': system['controllers']})

    raw_path = STUDY / 'selected-assets' / asset['raw']
    assert sha(raw_path) == asset['sha256']
    assert len(meshes) == 7 and sum(len(m['vertices']) for m in meshes) == 176
    assert sum(len(m['triangles']) for m in meshes) == 262
    assert len(particles) == 8 and sum(p['capacity'] for p in particles) == 82
    textures = sorted({m['texture'] for m in meshes}|{p['texture'] for p in particles})
    texture_evidence = []
    for name in textures:
        target = ROOT / 'assets/textures/pirates_reference' / name
        candidates = list((REF / 'preview/images/fpk').rglob(name))
        assert target.exists() and any(sha(p)==sha(target) for p in candidates), name
        texture_evidence.append({'resource': 'res://assets/textures/pirates_reference/'+name, 'sha256': sha(target), 'referencePreview': str(next(p for p in candidates if sha(p)==sha(target)))})
    result = {'schemaVersion': 1, 'source': {'asset': asset['name'], 'raw': asset['raw'], 'sha256': asset['sha256'], 'inputs': {str(p.relative_to(REF)): sha(p) for p in [geometry_path, complete_path, particle_path]}}, 'coordinateNote': 'Exact local NIF Z-up geometry. Godot uses (x,z,-y), with explicit chosen 0.01 metre display scale. Keys are not resampled. Particle random distribution, allocation and engine draw path were not recovered.', 'meshes': meshes, 'systems': particles}
    data_path = ROOT / 'assets/data/reference_cannon_splash.json'
    data_path.write_text(json.dumps(result, ensure_ascii=False, separators=(',', ':'))+'\n', encoding='utf-8')
    provenance = {'source': result['source'], 'output': {'resource': 'res://assets/data/reference_cannon_splash.json', 'sha256': sha(data_path)}, 'textures': texture_evidence, 'meshCount': 7, 'vertices': 176, 'triangles': 262, 'particleSystems': 8, 'particleCapacity': 82, 'runtimeChoices': {'metresPerSourceUnit': .01, 'seededVariation': 'uniform deterministic presentation supplement', 'births': 'half-open enabled windows; immediate birth at enable then 1/rate grid; truncated by authored capacity', 'lifetimeVariation': 'not applied; base authored lifespan and color keys determine visible tail', 'sourceColumnOpacityGain': 18, 'sourceRingOpacityGain': .35, 'sourceParticlesOpacityGain': .40}}
    (ROOT / 'assets/provenance/reference-cannon-splash.json').write_text(json.dumps(provenance, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print('REFERENCE_SPLASH_IMPORT meshes=7 vertices=176 triangles=262 systems=8 capacity=82 textures='+str(len(textures))+' failures=0')

if __name__ == '__main__':
    main()
