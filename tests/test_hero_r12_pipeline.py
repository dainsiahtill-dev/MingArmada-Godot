"""Reject non-R12 sail payloads and undeclared geometry/UV/receipt tampering."""
import copy,json,sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'tools/blender'),str(ROOT/'tools/research')]
from pack_hero_r12_sail import pack_documents
from verify_hero_palette_delta import read_glb
from verify_hero_r12_sail_delta import compare,verify_author_receipt

class PipelineTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base,cls.base_bin,_=read_glb(ROOT/'assets/models/hero_fuchuan_v3_r7c/fuchuan-lod0.glb')
        cls.other,cls.other_bin,_=read_glb(ROOT/'assets/production/hero-fuchuan-blender/r10a2-author-02-intermediates/fuchuan-lod0.glb')
        cls.raw,cls.raw_bin,_=read_glb(ROOT/'Temp/hero-fuchuan-r12/r12-author-01/fuchuan-lod0.glb')
        cls.candidate,cls.candidate_bin,_=read_glb(ROOT/'assets/models/hero_fuchuan_v3_r12/fuchuan-lod0.glb')

    def test_previous_silhouette_is_not_r12(self):
        document,data,changes=pack_documents(self.base,self.base_bin,self.other,self.other_bin)
        self.assertEqual(len(changes),72)
        result=compare(self.base,self.base_bin,document,data,self.other,self.other_bin)
        self.assertFalse(result['pass'])
        self.assertTrue(any('R12 declared surface' in error for error in result['errors']),result)

    def test_changed_uv_is_rejected(self):
        target=next(n for n in self.raw['nodes'] if n.get('name')=='sail_0')
        primitive=self.raw['meshes'][target['mesh']]['primitives'][0]
        accessor=self.raw['accessors'][primitive['attributes']['TEXCOORD_0']]
        view=self.raw['bufferViews'][accessor['bufferView']]
        corrupt=bytearray(self.raw_bin);corrupt[view.get('byteOffset',0)+accessor.get('byteOffset',0)]^=1
        with self.assertRaises(ValueError):pack_documents(self.base,self.base_bin,self.raw,bytes(corrupt))

    def test_target_geometry_corruption_is_rejected(self):
        target=next(n for n in self.candidate['nodes'] if n.get('name')=='sail_0')
        primitive=self.candidate['meshes'][target['mesh']]['primitives'][0]
        accessor=self.candidate['accessors'][primitive['attributes']['POSITION']]
        view=self.candidate['bufferViews'][accessor['bufferView']]
        corrupt=bytearray(self.candidate_bin);corrupt[view.get('byteOffset',0)+accessor.get('byteOffset',0)]^=1
        self.assertFalse(compare(self.base,self.base_bin,self.candidate,bytes(corrupt),self.raw,self.raw_bin)['pass'])

    def test_unrelated_binary_corruption_is_rejected(self):
        corrupt=bytearray(self.candidate_bin);corrupt[3]^=1
        self.assertFalse(compare(self.base,self.base_bin,self.candidate,bytes(corrupt),self.raw,self.raw_bin)['pass'])

    def test_receipts_and_full_lod_data(self):
        evidence=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r12-author-01'
        blend=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r12-author-01.blend'
        for lod in range(3):
            base,bb,_=read_glb(ROOT/f'assets/models/hero_fuchuan_v3_r7c/fuchuan-lod{lod}.glb')
            candidate,cb,_=read_glb(ROOT/f'assets/models/hero_fuchuan_v3_r12/fuchuan-lod{lod}.glb')
            raw=ROOT/f'Temp/hero-fuchuan-r12/r12-author-01/fuchuan-lod{lod}.glb';authored,ab,_=read_glb(raw)
            self.assertTrue(compare(base,bb,candidate,cb,authored,ab)['pass'])
            author=json.loads((evidence/f'blender-lod{lod}.json').read_text(encoding='utf-8'))
            process=json.loads((evidence/f'blender-lod{lod}-process.json').read_text(encoding='utf-8'))
            log=(evidence/f'blender-lod{lod}.log').read_bytes()
            self.assertTrue(verify_author_receipt(author,process,log,raw,blend,lod))
            bad=copy.deepcopy(author);bad['baselineSources']={}
            self.assertFalse(verify_author_receipt(bad,process,log,raw,blend,lod))

if __name__=='__main__':unittest.main()
