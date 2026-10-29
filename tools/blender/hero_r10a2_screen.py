"""R10a2 finite-sample screening only; not an analytic proof of no fold."""
import argparse
import hashlib
import json
import math
from datetime import datetime, timezone
from pathlib import Path

from hero_r10_sail_formula import breadth, surface, inverse_uv

ROOT = Path(__file__).resolve().parents[2]
PARAMS = [(10.3, 7.7, 4.6), (17., 12., 4.05), (9., 6.8, 5.35)]


def screen(coefficient, intervals=128):
    minimum_j = math.inf
    minimum_breadth = math.inf
    inverse_max = 0.
    finite = True
    count = 0
    worst = None
    for sail, (height, width, base) in enumerate(PARAMS):
        for vi in range(intervals + 1):
            v = vi / intervals
            b = breadth(v, width, coefficient)
            minimum_breadth = min(minimum_breadth, b / width)
            for ui in range(intervals + 1):
                u = ui / intervals
                u0, u1 = max(0., u - 1e-5), min(1., u + 1e-5)
                v0, v1 = max(0., v - 1e-5), min(1., v + 1e-5)
                p = surface(u, v, height, width, base, coefficient)
                pu0, pu1 = surface(u0, v, height, width, base, coefficient), surface(u1, v, height, width, base, coefficient)
                pv0, pv1 = surface(u, v0, height, width, base, coefficient), surface(u, v1, height, width, base, coefficient)
                dydu, dzdu = (pu1[1] - pu0[1]) / (u1 - u0), (pu1[2] - pu0[2]) / (u1 - u0)
                dydv, dzdv = (pv1[1] - pv0[1]) / (v1 - v0), (pv1[2] - pv0[2]) / (v1 - v0)
                # Original (u,v)->(y,z) orientation is negative.
                normalized_j = -(dydu * dzdv - dydv * dzdu) / (height * width)
                values = (*p, b, normalized_j)
                if not all(math.isfinite(x) for x in values):
                    finite = False
                if normalized_j < minimum_j:
                    minimum_j = normalized_j
                    worst = {'sail': sail, 'u': u, 'v': v}
                if b > 0 and all(math.isfinite(x) for x in p):
                    ru, rv = inverse_uv(p[1], p[2], height, width, base, coefficient)
                    finite &= math.isfinite(ru) and math.isfinite(rv)
                    inverse_max = max(inverse_max, abs(ru - u), abs(rv - v))
                count += 1
    return {'coefficient': coefficient, 'intervalsEachAxis': intervals, 'sails': len(PARAMS),
            'sampleCount': count, 'allFinite': finite, 'minimumNormalizedJacobian': minimum_j,
            'minimumBreadthOverWidth': minimum_breadth, 'worstSample': worst,
            'maxInverseParameterError': inverse_max,
            'pass': finite and minimum_j > 0 and minimum_breadth > 0,
            'scope': 'uniform discrete UV grid and finite differences only; no continuous proof, morph/clearance, rendering or GPU'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('preserve previous screening output')
    files = [Path(__file__), ROOT / 'tools/blender/hero_r10_sail_formula.py',
             ROOT / 'docs/production/hero-fuchuan-2026-10-26-art/R10-SAIL-FORM-BRIEF.md']
    def hashes():
        return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    before = hashes()
    results = [screen(0.), screen(.20)]
    if before != hashes():
        raise ValueError('screen sources changed during run')
    inverse_no_worse_than_baseline = results[1]['maxInverseParameterError'] <= results[0]['maxInverseParameterError'] + 1e-12
    report = {'type': 'discrete-form-screen', 'timestampUtc': datetime.now(timezone.utc).isoformat(),
              'sourceSha256': before, 'results': results,
              'inverseNoWorseThanBaseline': inverse_no_worse_than_baseline,
              'pass': all(x['pass'] for x in results) and inverse_no_worse_than_baseline}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('HERO_R10A2_SCREEN_' + ('PASS' if report['pass'] else 'FAIL'), flush=True)
    if not report['pass']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
