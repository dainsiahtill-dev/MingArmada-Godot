"""Independent verifier rejects undeclared ship or author-payload mutations."""
import copy
import json
import sys
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'tools/blender'),str(ROOT/'tools/research')]
from verify_hero_palette_delta import read_glb
from verify_hero_r10_sail_delta import compare, verify_author_receipt


class IndependentDelta(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.a,cls.ab,_=read_glb(ROOT/'assets/models/hero_fuchuan_v3_r7c/fuchuan-lod0.glb')
        cls.b,cls.bb,_=read_glb(ROOT/'assets/models/hero_fuchuan_v3_r10a/fuchuan-lod0.glb')
        cls.c,cls.cb,_=read_glb(ROOT/'Temp/hero-fuchuan-r10a/r10a-author-02/fuchuan-lod0.glb')

    def test_real_output_is_exactly_author_sails_and_original_ship(self):
        result=compare(self.a,self.ab,self.b,self.bb,self.c,self.cb)
        self.assertTrue(result['pass'],result)

    def test_rejects_unrelated_bin_or_json_changes(self):
        bad=bytearray(self.bb);bad[3]^=1
        self.assertFalse(compare(self.a,self.ab,self.b,bytes(bad),self.c,self.cb)['pass'])
        doc=copy.deepcopy(self.b);doc['nodes'][0]['name']='tampered unrelated node'
        self.assertFalse(compare(self.a,self.ab,doc,self.bb,self.c,self.cb)['pass'])

    def test_blender_receipt_binds_authored_bytes_and_refuses_tampering(self):
        directory=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r10a-author-02'
        author=json.loads((directory/'blender-lod0.json').read_text(encoding='utf-8'))
        process=json.loads((directory/'blender-lod0-process.json').read_text(encoding='utf-8'))
        raw=ROOT/'Temp/hero-fuchuan-r10a/r10a-author-02/fuchuan-lod0.glb'
        blend=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r10a-author-02.blend'
        self.assertTrue(verify_author_receipt(author,process,(directory/'blender-lod0.log').read_bytes(),raw,blend,0))
        altered=copy.deepcopy(author);altered['candidateRawSha256']='0'*64
        self.assertFalse(verify_author_receipt(altered,process,(directory/'blender-lod0.log').read_bytes(),raw,blend,0))
        altered=copy.deepcopy(author);altered['baselineSources']={}
        self.assertFalse(verify_author_receipt(altered,process,(directory/'blender-lod0.log').read_bytes(),raw,blend,0))


if __name__=='__main__': unittest.main()
