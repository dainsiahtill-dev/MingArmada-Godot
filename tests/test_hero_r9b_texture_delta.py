"""Reuse all R9 adversarial checks against R9b, without relaxing the contract."""
import sys
import unittest
from pathlib import Path

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'tests'))
import test_hero_r9_texture_delta as checks

class TestR9BImageOnly(checks.R9ImageOnly):
    @classmethod
    def setUpClass(cls):
        cls._old_png, cls._old_target = checks.contract.PNG, checks.contract.TARGET
        checks.contract.PNG = root / 'assets/textures/hero_fuchuan_r9/sunfaded-cinnabar-hemp-sail.png'
        checks.contract.TARGET = root / 'assets/models/hero_fuchuan_v3_r9b'
        super().setUpClass()

    @classmethod
    def tearDownClass(cls):
        checks.contract.PNG, checks.contract.TARGET = cls._old_png, cls._old_target


if __name__ == '__main__':
    unittest.main(verbosity=2)
