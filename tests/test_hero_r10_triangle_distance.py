import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools' / 'research'))
from hero_r10_triangle_distance import triangle_distance, surface_distance, transverse_crossing


class TriangleDistanceTest(unittest.TestCase):
    def test_face_distance_not_nearest_vertex(self):
        a = np.array([[[0, 0, 0], [4, 0, 0], [0, 4, 0]]], dtype=float)
        b = np.array([[[1, 1, 0.5], [1.2, 1, 0.5], [1, 1.2, 0.5]]], dtype=float)
        self.assertAlmostEqual(triangle_distance(a, b)[0], 0.5)

    def test_edge_crossing_and_coplanar_overlap(self):
        a = np.array([[[0, 0, 0], [2, 0, 0], [0, 2, 0]]] * 2, dtype=float)
        b = np.array([[[0.5, 0.5, -1], [0.5, 0.5, 1], [1.5, 0.5, 1]],
                      [[0.5, 0.5, 0], [2, 0.5, 0], [0.5, 2, 0]]], dtype=float)
        np.testing.assert_allclose(triangle_distance(a, b), [0, 0], atol=1e-10)
        self.assertTrue(transverse_crossing(a, b)[0])
        self.assertFalse(transverse_crossing(a, b)[1])

    def test_skew_edges_and_degenerate(self):
        a = np.array([[[0, 0, 0], [2, 0, 0], [2, -1, 0]],
                      [[0, 0, 0], [0, 0, 0], [0, 0, 0]]], dtype=float)
        b = np.array([[[1, -0.5, 1], [1, 0.5, 1], [1, 0.5, 2]],
                      [[1, 0, 0], [1, 1, 0], [1, 0, 1]]], dtype=float)
        np.testing.assert_allclose(triangle_distance(a, b), [1, 1], atol=1e-10)

    def test_parallel_separated_coplanar(self):
        a = np.array([[[0, 0, 0], [1, 0, 0], [0, 1, 0]]], dtype=float)
        b = np.array([[[2, 0, 0], [3, 0, 0], [2, 1, 0]]], dtype=float)
        self.assertAlmostEqual(triangle_distance(a, b)[0], 1.0)

    def test_surface_search_reports_face_distance_and_contact_pairs(self):
        a = np.array([[[0, 0, 0], [4, 0, 0], [0, 4, 0]],
                      [[10, 0, 0], [11, 0, 0], [10, 1, 0]]], dtype=float)
        b = np.array([[[1, 1, 0.5], [1.2, 1, 0.5], [1, 1.2, 0.5]],
                      [[10.1, 0.1, -1], [10.1, 0.1, 1], [10.5, 0.1, 1]]], dtype=float)
        result = surface_distance(a, b, 1e-7)
        self.assertEqual(result['nearPairs'], [[1, 1]])
        self.assertEqual(result['transversePairs'], [[1, 1]])
        self.assertAlmostEqual(result['minimumMeters'], 0.0)
        result = surface_distance(a[:1], b[:1], 1e-7)
        self.assertEqual(result['nearPairs'], [])
        self.assertAlmostEqual(result['minimumMeters'], 0.5)

    def test_broad_phase_matches_all_triangle_pairs(self):
        rng = np.random.default_rng(229)
        a = rng.uniform(-1, 1, (12, 3, 3))
        b = rng.uniform(-1, 1, (13, 3, 3))
        tolerance = 1e-7
        all_dist = triangle_distance(np.repeat(a, len(b), axis=0), np.tile(b, (len(a), 1, 1)))
        brute_pairs = [[int(i // len(b)), int(i % len(b))] for i in np.flatnonzero(all_dist <= tolerance)]
        result = surface_distance(a, b, tolerance)
        self.assertAlmostEqual(result['minimumMeters'], float(all_dist.min()), places=12)
        self.assertEqual(sorted(result['nearPairs']), sorted(brute_pairs))


if __name__ == '__main__':
    unittest.main()
