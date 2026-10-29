"""Adversarial checks for the R9 image-only GLB contract using real inputs."""
import copy
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/research'))
import verify_hero_r9_texture_delta as contract


class R9ImageOnly(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.png = contract.PNG.read_bytes()
        cls.base, cls.base_bin, _ = contract.read_glb(contract.BASE / 'fuchuan-lod0.glb')
        cls.actual, cls.actual_bin, _ = contract.read_glb(contract.TARGET / 'fuchuan-lod0.glb')

    def test_all_three_real_lods_preserve_every_non_image_byte_and_json_field(self):
        for lod in range(3):
            with self.subTest(lod=lod):
                base, bbin, _ = contract.read_glb(contract.BASE / f'fuchuan-lod{lod}.glb')
                candidate, cbin, _ = contract.read_glb(contract.TARGET / f'fuchuan-lod{lod}.glb')
                self.assertTrue(contract.verify_delta(base, bbin, candidate, cbin, self.png)['originalBinUnchanged'])

    def test_non_image_json_changes_are_rejected(self):
        candidate = copy.deepcopy(self.actual)
        candidate['nodes'][0]['name'] += '-changed'
        with self.assertRaisesRegex(ValueError, 'candidate JSON differs'):
            contract.verify_delta(self.base, self.base_bin, candidate, self.actual_bin, self.png)

    def test_material_uv_transform_changes_are_rejected(self):
        candidate = copy.deepcopy(self.actual)
        canvas = next(x for x in candidate['materials'] if x.get('name') == 'canvas')
        canvas['pbrMetallicRoughness']['baseColorTexture']['extensions']['KHR_texture_transform']['scale'][0] += 1
        with self.assertRaisesRegex(ValueError, 'candidate JSON differs'):
            contract.verify_delta(self.base, self.base_bin, candidate, self.actual_bin, self.png)

    def test_original_bin_tampering_is_rejected(self):
        tampered = bytearray(self.actual_bin)
        tampered[0] ^= 1
        with self.assertRaisesRegex(ValueError, 'original BIN'):
            contract.verify_delta(self.base, self.base_bin, self.actual, bytes(tampered), self.png)

    def test_appended_image_tampering_is_rejected(self):
        tampered = bytearray(self.actual_bin)
        tampered[len(self.base_bin) + 20] ^= 1
        with self.assertRaisesRegex(ValueError, 'appended PNG'):
            contract.verify_delta(self.base, self.base_bin, self.actual, bytes(tampered), self.png)

    def test_original_image_shared_by_other_texture_is_rejected(self):
        shared = copy.deepcopy(self.base)
        selected = contract.canvas_selection(shared, self.base_bin)
        shared['textures'].append({'source': selected['image']})
        with self.assertRaisesRegex(ValueError, 'shared by another texture'):
            contract.canvas_selection(shared, self.base_bin)

    def test_original_texture_shared_by_other_material_is_rejected(self):
        shared = copy.deepcopy(self.base)
        selected = contract.canvas_selection(shared, self.base_bin)
        shared['materials'][0]['normalTexture'] = {'index': selected['texture']}
        with self.assertRaisesRegex(ValueError, 'shared or referenced'):
            contract.canvas_selection(shared, self.base_bin)


if __name__ == '__main__':
    unittest.main(verbosity=2)
