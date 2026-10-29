"""R10a: independent geometric invariants of the declared candidate."""
import math
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/blender'))
from hero_r10_sail_formula import breadth, inverse_uv, surface


class SailFormContract(unittest.TestCase):
    def test_fixed_width_ends_and_declared_shoulder(self):
        for width in (6.8, 7.7, 12.0):
            self.assertAlmostEqual(breadth(0, width, .06), width, places=12)
            self.assertAlmostEqual(breadth(1, width, .06), width * .6, places=12)
            self.assertAlmostEqual(breadth(.5, width, .06), breadth(.5, width, 0), places=12)
            self.assertAlmostEqual(breadth(.25, width, .06) - breadth(.25, width, 0), width * .015, places=12)
            self.assertAlmostEqual(breadth(.75, width, .06) - breadth(.75, width, 0), -width * .015, places=12)

    def test_inverse_for_real_sails_and_shape_key_domain(self):
        for height, width, base in ((10.3, 7.7, 4.6), (17, 12, 4.05), (9, 6.8, 5.35)):
            for coefficient in (0, .06):
                for ui in range(21):
                    for vi in range(21):
                        u, v = ui / 20, vi / 20
                        _, y, z = surface(u, v, height, width, base, coefficient)
                        got_u, got_v = inverse_uv(y, z, height, width, base, coefficient)
                        self.assertAlmostEqual(u, got_u, delta=2e-6)
                        self.assertAlmostEqual(v, got_v, delta=2e-6)

    def test_no_zero_or_reversed_width_over_declared_domain(self):
        for coefficient in (0, .06):
            for i in range(1001):
                self.assertGreater(breadth(i / 1000, 12, coefficient), 0)


if __name__ == '__main__':
    unittest.main()
