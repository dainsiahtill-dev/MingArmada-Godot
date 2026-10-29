import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools' / 'blender'))
from hero_r10a2_screen import screen


class ScreenTest(unittest.TestCase):
    def test_registered_parameter_has_positive_sampled_orientation(self):
        result = screen(.20, intervals=24)
        self.assertTrue(result['pass'])
        self.assertGreater(result['minimumNormalizedJacobian'], 0)
        self.assertTrue(result['allFinite'])

    def test_refuses_a_folded_parameter(self):
        result = screen(4., intervals=24)
        self.assertFalse(result['pass'])
        self.assertLessEqual(result['minimumNormalizedJacobian'], 0)


if __name__ == '__main__':
    unittest.main()
