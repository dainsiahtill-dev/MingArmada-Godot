"""Adversarial image-only contract for R9b -> R13 real GLBs."""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tests'))
import test_hero_r9_texture_delta as checks


class TestR13ImageOnly(checks.R9ImageOnly):
    @classmethod
    def setUpClass(cls):
        cls.old = checks.contract.BASE, checks.contract.PNG, checks.contract.TARGET
        checks.contract.BASE = ROOT / 'assets/models/hero_fuchuan_v3_r9b'
        checks.contract.PNG = ROOT / 'assets/textures/hero_fuchuan_r13/weathered-cinnabar-hemp.png'
        checks.contract.TARGET = ROOT / 'assets/models/hero_fuchuan_v3_r13'
        super().setUpClass()

    @classmethod
    def tearDownClass(cls):
        checks.contract.BASE, checks.contract.PNG, checks.contract.TARGET = cls.old


if __name__ == '__main__':
    unittest.main(verbosity=2)
