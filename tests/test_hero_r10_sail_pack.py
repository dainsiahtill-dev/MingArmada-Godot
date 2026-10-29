"""Exercise real Blender-authored sail payload packaging and refusal boundaries."""
import copy
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/blender'))
from transfer_hero_shadow_geometry import read_checked
from pack_hero_r10_sail import pack_documents, sail_primitives


class SailPacking(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base, cls.base_bin, _ = read_checked(ROOT/'assets/models/hero_fuchuan_v3_r7c/fuchuan-lod0.glb')
        cls.raw, cls.raw_bin, _ = read_checked(ROOT/'Temp/hero-fuchuan-r10a/r10a-author-02/fuchuan-lod0.glb')

    def test_real_candidate_changes_only_declared_sail_intervals(self):
        doc, binary, audit = pack_documents(self.base, self.base_bin, self.raw, self.raw_bin)
        self.assertEqual(doc['nodes'][next(i for i,n in enumerate(doc['nodes']) if n.get('name')=='HeroFuchuan')]['extras']['authored_asset'], 'hero-fuchuan-v3-r10a')
        self.assertEqual(len(audit), 3*4*6)
        intervals = sorted((p['start'],p['end']) for p in audit)
        self.assertTrue(all(a < b for a,b in intervals))
        self.assertTrue(all(intervals[i][1] <= intervals[i+1][0] for i in range(len(intervals)-1)))
        cursor = 0
        for start,end in intervals:
            self.assertEqual(self.base_bin[cursor:start], binary[cursor:start])
            cursor=end
        self.assertEqual(self.base_bin[cursor:], binary[cursor:])
        self.assertTrue(all(any(p['changed_bytes'] for p in audit if p['node']==name and p['attribute']=='POSITION' and p['target'] is None) for name in ('sail_0','sail_1','sail_2')))

    def test_rejects_changed_triangle_index_and_nominal_uv(self):
        for attribute in ('indices','TEXCOORD_0'):
            altered=bytearray(self.raw_bin)
            primitive=sail_primitives(self.raw,'sail_0')[0]
            index=primitive['indices'] if attribute=='indices' else primitive['attributes'][attribute]
            accessor=self.raw['accessors'][index];view=self.raw['bufferViews'][accessor['bufferView']]
            offset=view.get('byteOffset',0)+accessor.get('byteOffset',0)
            altered[offset] ^= 1
            with self.assertRaisesRegex(ValueError, 'indices|attribute'):
                pack_documents(self.base,self.base_bin,self.raw,bytes(altered))

    def test_rejects_target_shared_storage(self):
        altered=copy.deepcopy(self.base)
        p=sail_primitives(altered,'sail_0')[0]
        other=sail_primitives(altered,'sail_1')[0]
        p['attributes']['POSITION']=other['attributes']['POSITION']
        with self.assertRaisesRegex(ValueError, 'unique|exclusive|alias'):
            pack_documents(altered,self.base_bin,self.raw,self.raw_bin)


if __name__=='__main__': unittest.main()
