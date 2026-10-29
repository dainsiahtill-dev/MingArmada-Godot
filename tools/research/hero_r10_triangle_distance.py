"""Vectorized triangle-surface distance in metres, including edge/face crossings.

Discrete floating-point observations, not a certified exact-predicate solver.
"""
import numpy as np
from scipy.spatial import cKDTree


def dot(a, b):
    return np.einsum('...i,...i->...', a, b)


def point_segment_sq(p, a, b):
    d = b - a
    denominator = dot(d, d)
    t = np.divide(dot(p - a, d), denominator, out=np.zeros_like(denominator), where=denominator > 1e-28)
    return dot(p - a - np.clip(t, 0, 1)[..., None] * d, p - a - np.clip(t, 0, 1)[..., None] * d)


def barycentric(p, tri, interior=False):
    a, b, c = tri[:, 0], tri[:, 1], tri[:, 2]
    u, v, w = b - a, c - a, p - a
    uu, uv, vv, wu, wv = dot(u, u), dot(u, v), dot(v, v), dot(w, u), dot(w, v)
    denominator = uu * vv - uv * uv
    valid = denominator > 1e-28
    s = np.divide(wu * vv - wv * uv, denominator, out=np.zeros_like(denominator), where=valid)
    t = np.divide(wv * uu - wu * uv, denominator, out=np.zeros_like(denominator), where=valid)
    if interior:
        return valid & (s > 1e-9) & (t > 1e-9) & (s + t < 1 - 1e-9)
    return valid & (s >= -1e-10) & (t >= -1e-10) & (s + t <= 1 + 1e-10)


def point_triangle_sq(p, tri):
    a, b, c = tri[:, 0], tri[:, 1], tri[:, 2]
    n = np.cross(b - a, c - a)
    nn = dot(n, n)
    height = dot(p - a, n)
    scale = np.divide(height, nn, out=np.zeros_like(height), where=nn > 1e-28)
    projection = p - scale[:, None] * n
    plane_sq = np.divide(height * height, nn, out=np.full_like(height, np.inf), where=nn > 1e-28)
    result = np.minimum.reduce([point_segment_sq(p, a, b), point_segment_sq(p, b, c), point_segment_sq(p, c, a)])
    return np.where(barycentric(projection, tri), np.minimum(result, plane_sq), result)


def segment_segment_sq(a, b, c, d):
    u, v, w = b - a, d - c, a - c
    uu, uv, vv, uw, vw = dot(u, u), dot(u, v), dot(v, v), dot(u, w), dot(v, w)
    den = uu * vv - uv * uv
    valid = den > 1e-28
    s = np.divide(uv * vw - vv * uw, den, out=np.zeros_like(den), where=valid)
    t = np.divide(uu * vw - uv * uw, den, out=np.zeros_like(den), where=valid)
    inside = valid & (s >= 0) & (s <= 1) & (t >= 0) & (t <= 1)
    delta = w + s[:, None] * u - t[:, None] * v
    interior = np.where(inside, dot(delta, delta), np.inf)
    return np.minimum.reduce([interior, point_segment_sq(a, c, d), point_segment_sq(b, c, d),
                              point_segment_sq(c, a, b), point_segment_sq(d, a, b)])


def segment_intersects_triangle(p, q, tri):
    a, b, c = tri[:, 0], tri[:, 1], tri[:, 2]
    n = np.cross(b - a, c - a)
    denominator = dot(q - p, n)
    t = np.divide(dot(a - p, n), denominator, out=np.zeros_like(denominator), where=np.abs(denominator) > 1e-25)
    return (np.abs(denominator) > 1e-25) & (t >= 0) & (t <= 1) & barycentric(p + t[:, None] * (q - p), tri)


def segment_transversely_crosses_triangle(p, q, tri):
    a, b, c = tri[:, 0], tri[:, 1], tri[:, 2]
    n = np.cross(b - a, c - a)
    normal_length = np.linalg.norm(n, axis=1)
    start = np.divide(dot(p - a, n), normal_length, out=np.zeros_like(normal_length), where=normal_length > 1e-14)
    end = np.divide(dot(q - a, n), normal_length, out=np.zeros_like(normal_length), where=normal_length > 1e-14)
    # Endpoints must be strictly on opposite sides by at least 10 nm.
    opposite = ((start > 1e-8) & (end < -1e-8)) | ((end > 1e-8) & (start < -1e-8))
    t = np.divide(start, start - end, out=np.zeros_like(start), where=np.abs(start - end) > 1e-20)
    return opposite & barycentric(p + t[:, None] * (q - p), tri, interior=True)


def transverse_crossing(a, b):
    """Positive evidence only; coplanar/touching and degenerate cases excluded."""
    answer = np.zeros(len(a), dtype=bool)
    for i in range(3):
        answer |= segment_transversely_crosses_triangle(a[:, i], a[:, (i + 1) % 3], b)
        answer |= segment_transversely_crosses_triangle(b[:, i], b[:, (i + 1) % 3], a)
    return answer


def triangle_distance(a, b):
    a, b = np.asarray(a, dtype=np.float64), np.asarray(b, dtype=np.float64)
    if a.shape != b.shape or a.ndim != 3 or a.shape[1:] != (3, 3):
        raise ValueError('matching N x 3 x 3 triangle batches required')
    best = np.full(len(a), np.inf)
    crossing = np.zeros(len(a), dtype=bool)
    for i in range(3):
        best = np.minimum(best, point_triangle_sq(a[:, i], b))
        best = np.minimum(best, point_triangle_sq(b[:, i], a))
        crossing |= segment_intersects_triangle(a[:, i], a[:, (i + 1) % 3], b)
        crossing |= segment_intersects_triangle(b[:, i], b[:, (i + 1) % 3], a)
        for j in range(3):
            best = np.minimum(best, segment_segment_sq(a[:, i], a[:, (i + 1) % 3],
                                                        b[:, j], b[:, (j + 1) % 3]))
    return np.sqrt(np.maximum(0, np.where(crossing, 0, best)))


def surface_distance(a, b, contact_tolerance):
    """Search all potentially closest/near pairs by enclosing spheres and AABBs.

    Indices refer to original triangle order. No vertex-only estimate is returned
    as the answer. Tolerance is a near-contact classification, not penetration.
    """
    a, b = np.asarray(a, dtype=np.float64), np.asarray(b, dtype=np.float64)
    if not len(a) or not len(b) or not np.isfinite(a).all() or not np.isfinite(b).all():
        raise ValueError('finite, nonempty triangle surfaces required')
    ac, bc = a.mean(axis=1), b.mean(axis=1)
    ar = np.linalg.norm(a - ac[:, None], axis=2).max(axis=1)
    br = np.linalg.norm(b - bc[:, None], axis=2).max(axis=1)
    # Any vertex pair supplies a valid upper bound for the true surface minimum.
    upper = float(cKDTree(b.reshape(-1, 3)).query(a.reshape(-1, 3), k=1)[0].min())
    search = max(upper, contact_tolerance) + 1e-10
    candidates = cKDTree(bc).query_ball_point(ac, ar + br.max() + search)
    ai = np.repeat(np.arange(len(a)), [len(row) for row in candidates])
    bi = np.asarray([x for row in candidates for x in row], dtype=int)
    if not len(ai):
        raise RuntimeError('broad phase omitted an existing upper bound')
    amin, amax, bmin, bmax = a.min(axis=1), a.max(axis=1), b.min(axis=1), b.max(axis=1)
    delta = np.maximum(0, np.maximum(amin[ai] - bmax[bi], bmin[bi] - amax[ai]))
    keep = np.linalg.norm(delta, axis=1) <= search
    ai, bi = ai[keep], bi[keep]
    best = np.inf
    near, transverse = [], []
    for start in range(0, len(ai), 20000):
        ii, jj = ai[start:start + 20000], bi[start:start + 20000]
        dist = triangle_distance(a[ii], b[jj])
        if len(dist):
            best = min(best, float(dist.min()))
            selected = dist <= contact_tolerance
            near.extend(zip(ii[selected].tolist(), jj[selected].tolist()))
            cross = transverse_crossing(a[ii[selected]], b[jj[selected]])
            transverse.extend(zip(ii[selected][cross].tolist(), jj[selected][cross].tolist()))
    if not np.isfinite(best) or best > upper + 1e-8:
        raise RuntimeError('triangle result exceeds provable vertex upper bound')
    return {'minimumMeters': best, 'nearPairs': [list(p) for p in near],
            'transversePairs': [list(p) for p in transverse],
            'nearToleranceMeters': contact_tolerance, 'narrowPhasePairs': int(len(ai)),
            'vertexUpperBoundMeters': upper}
