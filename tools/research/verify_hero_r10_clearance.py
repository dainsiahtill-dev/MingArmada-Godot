"""Discrete R7c/R10a triangle-surface observations in the shared mast frame."""
import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

from hero_r10_triangle_distance import surface_distance
from verify_hero_palette_delta import decode_accessor, read_glb

ROOT = Path(__file__).resolve().parents[2]
TOLERANCE = 1e-7


def find_node(doc, name):
    found = [(i, node) for i, node in enumerate(doc['nodes']) if node.get('name') == name]
    if len(found) != 1:
        raise ValueError('unique node required: ' + name)
    return found[0]


def validate_frame(doc, index):
    mast_index, mast = find_node(doc, f'mast_{index}')
    for name in (f'sail_{index}', f'mast_timber_{index}'):
        idx, node = find_node(doc, name)
        if idx not in mast.get('children', []):
            raise ValueError('sail and mast timber must share their rotating parent')
        if any(k in node for k in ('matrix', 'translation', 'rotation', 'scale')):
            raise ValueError('child transform needs explicit implementation: ' + name)
    # The source mast may have a translation, but runtime applies a common rigid
    # yaw to both children, so that transform cannot change their separation.
    if 'scale' in mast and not np.allclose(mast['scale'], [1, 1, 1]):
        raise ValueError('non-unit mast scale invalidates metre distances')
    if 'matrix' in mast:
        raise ValueError('unsupported mast matrix')


def load_surface(doc, binary, node_name, material_names):
    _, node = find_node(doc, node_name)
    mesh = doc['meshes'][node['mesh']]
    target_names = mesh.get('extras', {}).get('targetNames', [])
    positions, furl, inflate, indices = [], [], [], []
    offset = 0
    selected = []
    for primitive in mesh['primitives']:
        material = doc['materials'][primitive['material']]['name']
        if material not in material_names:
            continue
        if primitive.get('mode', 4) != 4:
            raise ValueError('triangle-list geometry required')
        p = np.asarray(decode_accessor(doc, binary, primitive['attributes']['POSITION']), dtype=np.float64)
        index = np.asarray(decode_accessor(doc, binary, primitive['indices']), dtype=np.int64).reshape(-1)
        if len(index) % 3 or not len(index) or index.max() >= len(p) or index.min() < 0:
            raise ValueError('invalid triangle index')
        targets = primitive.get('targets', [])
        if node_name.startswith('sail_'):
            if target_names != ['furl', 'inflate'] or len(targets) != 2:
                raise ValueError('required sail target order differs')
            f = np.asarray(decode_accessor(doc, binary, targets[0]['POSITION']), dtype=np.float64)
            infl = np.asarray(decode_accessor(doc, binary, targets[1]['POSITION']), dtype=np.float64)
            if f.shape != p.shape or infl.shape != p.shape:
                raise ValueError('target shape mismatch')
        else:
            f = infl = np.zeros_like(p)
        positions.append(p); furl.append(f); inflate.append(infl)
        indices.append(index.reshape(-1, 3) + offset); offset += len(p)
        selected.append(material)
    if set(selected) != set(material_names):
        raise ValueError(f'{node_name}: expected material set {material_names}, found {selected}')
    return {'p': np.concatenate(positions), 'f': np.concatenate(furl), 'i': np.concatenate(inflate),
            'tri': np.concatenate(indices), 'materials': selected}


def triangles(surface, deployment, inflation):
    p = surface['p'] + (1 - deployment) * surface['f'] + inflation * surface['i']
    return p[surface['tri']]


def compact(result):
    pairs = result.pop('nearPairs')
    transverse = result.pop('transversePairs')
    result['nearPairCount'] = len(pairs)
    result['transversePairCount'] = len(transverse)
    return result, {tuple(p) for p in pairs}, {tuple(p) for p in transverse}


def run_lod(lod, mast_indices, deployments, signs):
    paths = [ROOT / 'assets/models/hero_fuchuan_v3_r7c' / f'fuchuan-lod{lod}.glb',
             ROOT / 'assets/models/hero_fuchuan_v3_r10a' / f'fuchuan-lod{lod}.glb']
    models = [read_glb(p) for p in paths]
    records = []
    for mast in mast_indices:
        surfaces = []
        for doc, data, _ in models:
            validate_frame(doc, mast)
            surfaces.append({
                'canvas': load_surface(doc, data, f'sail_{mast}', ['canvas']),
                'bamboo': load_surface(doc, data, f'sail_{mast}', ['bamboo']),
                'mast': load_surface(doc, data, f'mast_timber_{mast}', ['teak', 'hemp']),
            })
        for role in ('canvas', 'bamboo', 'mast'):
            if not np.array_equal(surfaces[0][role]['tri'], surfaces[1][role]['tri']):
                raise ValueError('baseline/candidate triangle identity differs: ' + role)
        if not np.array_equal(surfaces[0]['mast']['p'], surfaces[1]['mast']['p']):
            raise ValueError('baseline/candidate mast vertex mismatch')
        for deployment in deployments:
            actual_signs = [0] if deployment == 0 else signs
            for sign in actual_signs:
                inflation = sign * deployment
                result = {'lod': lod, 'mast': mast, 'deployment': deployment,
                          'furl': 1 - deployment, 'inflate': inflation, 'pairs': {}}
                for other in ('mast', 'bamboo'):
                    runs = []
                    for surface in surfaces:
                        raw = surface_distance(triangles(surface['canvas'], deployment, inflation),
                                               triangles(surface[other], deployment, inflation), TOLERANCE)
                        runs.append(compact(raw))
                    (baseline, bp, bt), (candidate, cp, ct) = runs
                    introduced = cp - bp
                    result['pairs']['canvas_' + other] = {
                        'baseline': baseline, 'candidate': candidate,
                        'candidateMinusBaselineMinimumMeters': candidate['minimumMeters'] - baseline['minimumMeters'],
                        'newNearPairCount': len(introduced), 'removedNearPairCount': len(bp - cp),
                        'newNearPairsFirst20': [list(x) for x in sorted(introduced)[:20]],
                        'newTransversePairCount': len(ct - bt), 'removedTransversePairCount': len(bt - ct),
                        'newTransversePairsFirst20': [list(x) for x in sorted(ct - bt)[:20]],
                    }
                records.append(result)
                print(f'R10_CLEARANCE lod={lod} mast={mast} deployment={deployment} inflation={inflation}', flush=True)
    return {'lod': lod, 'files': [{'path': str(p.relative_to(ROOT)), 'sha256': m[2]} for p, m in zip(paths, models)],
            'records': records}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--lod', type=int, choices=[0, 1, 2], action='append', required=True)
    parser.add_argument('--mast', type=int, choices=[0, 1, 2], action='append', required=True)
    parser.add_argument('--deployment', type=float, action='append', required=True)
    parser.add_argument('--sign', type=int, choices=[-1, 0, 1], action='append', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if any(not 0 <= x <= 1 for x in args.deployment):
        raise ValueError('deployment outside runtime bounds')
    if args.output.exists():
        raise FileExistsError('preserve existing evidence')
    inputs = [ROOT / 'tools/research/verify_hero_r10_clearance.py', ROOT / 'tools/research/hero_r10_triangle_distance.py',
              ROOT / 'tools/research/verify_hero_palette_delta.py', ROOT / 'game/presentation/ships/ship_view.gd']
    def hashes():
        return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    before = hashes()
    report = {'type': 'discrete-near-contact-observation', 'startedUtc': datetime.now(timezone.utc).isoformat(),
              'sourceSha256': before, 'toleranceMeters': TOLERANCE,
              'limitations': ['Floating point, not exact predicates or certified collision proof',
                  'near pair includes touches and crossings; not a penetration classification',
                  'transverse pair requires opposite edge endpoints 10 nm from the face and a strict face-interior crossing; boundary/coplanar cases omitted',
                  'discrete sampled morph states only; no continuous motion or all geometry',
                  'canvas includes repair patch; mast includes teak and hemp bindings',
                  'common mast yaw preserves these pairwise distances; no hull or other mast tested'],
              'lods': [run_lod(lod, args.mast, args.deployment, args.sign) for lod in args.lod]}
    if hashes() != before:
        raise ValueError('analysis source changed during run')
    for lod in report['lods']:
        for item in lod['files']:
            if hashlib.sha256((ROOT / item['path']).read_bytes()).hexdigest() != item['sha256']:
                raise ValueError('asset changed during run')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print('HERO_R10_DISCRETE_CLEARANCE_COMPLETE', flush=True)


if __name__ == '__main__':
    main()
