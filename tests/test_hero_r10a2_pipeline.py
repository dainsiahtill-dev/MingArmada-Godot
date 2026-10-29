"""Verify R10a2 isolation and reject an R10a payload as a +0.20 sail."""
import copy
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / 'tools/blender'), str(ROOT / 'tools/research')]
from pack_hero_r10a2_sail import pack_documents
from verify_hero_palette_delta import read_glb
from verify_hero_r10a2_sail_delta import compare, verify_author_receipt


class PipelineTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base, cls.base_bin, _ = read_glb(ROOT / 'assets/models/hero_fuchuan_v3_r7c/fuchuan-lod0.glb')
        cls.old, cls.old_bin, _ = read_glb(ROOT / 'assets/production/hero-fuchuan-blender/r10a-author-02-intermediates/fuchuan-lod0.glb')

    def test_old_coefficient_cannot_pass_new_formula_verifier(self):
        packed, data, audit = pack_documents(self.base, self.base_bin, self.old, self.old_bin)
        self.assertEqual(len(audit), 72)
        report = compare(self.base, self.base_bin, packed, data, self.old, self.old_bin)
        self.assertFalse(report['pass'])
        self.assertTrue(any('0.20 shoulder formula' in x for x in report['errors']), report)

    def test_old_uv_tamper_remains_rejected(self):
        altered = copy.deepcopy(self.old)
        node = next(n for n in altered['nodes'] if n.get('name') == 'sail_0')
        primitive = altered['meshes'][node['mesh']]['primitives'][0]
        index = primitive['attributes']['TEXCOORD_0']
        accessor = altered['accessors'][index]
        view = altered['bufferViews'][accessor['bufferView']]
        data = bytearray(self.old_bin)
        data[view.get('byteOffset', 0) + accessor.get('byteOffset', 0)] ^= 1
        with self.assertRaises(ValueError):
            pack_documents(self.base, self.base_bin, altered, bytes(data))

    def test_actual_candidate_and_author_receipts(self):
        for lod in range(3):
            base, bb, _ = read_glb(ROOT / f'assets/models/hero_fuchuan_v3_r7c/fuchuan-lod{lod}.glb')
            candidate, cb, _ = read_glb(ROOT / f'assets/models/hero_fuchuan_v3_r10a2/fuchuan-lod{lod}.glb')
            raw_path = ROOT / f'Temp/hero-fuchuan-r10a2/r10a2-author-02/fuchuan-lod{lod}.glb'
            authored, ab, _ = read_glb(raw_path)
            result = compare(base, bb, candidate, cb, authored, ab)
            self.assertTrue(result['pass'], result)
            evidence = ROOT / 'docs/production/hero-fuchuan-2026-10-26-art/r10a2-author-02'
            author = json.loads((evidence / f'blender-lod{lod}.json').read_text(encoding='utf-8'))
            process = json.loads((evidence / f'blender-lod{lod}-process.json').read_text(encoding='utf-8'))
            log = (evidence / f'blender-lod{lod}.log').read_bytes()
            blend = ROOT / 'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r10a2-author-02.blend'
            self.assertTrue(verify_author_receipt(author, process, log, raw_path, blend, lod))
            changed = copy.deepcopy(author); changed['baselineSources'] = {}
            self.assertFalse(verify_author_receipt(changed, process, log, raw_path, blend, lod))
            corrupt = bytearray(cb); corrupt[3] ^= 1
            self.assertFalse(compare(base, bb, candidate, bytes(corrupt), authored, ab)['pass'])


if __name__ == '__main__':
    unittest.main()
