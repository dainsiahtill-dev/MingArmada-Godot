"""Negative isolation checks for R14b coaming compatibility packaging."""
import copy,sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'tools/blender'),str(ROOT/'tools/research')]
from pack_hero_r14b_coamings import pack
from verify_hero_palette_delta import read_glb
from verify_hero_r14b_coamings import verify
class R14BPipelineTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base,cls.bb,_=read_glb(ROOT/'assets/models/hero_fuchuan_v3_r7c/fuchuan-lod0.glb')
        cls.candidate,cls.cb,_=read_glb(ROOT/'assets/models/hero_fuchuan_v3_r14b/fuchuan-lod0.glb')
        cls.authored,cls.ab,_=read_glb(ROOT/'Temp/hero-fuchuan-r14b/r14b-author-01/fuchuan-lod0.glb')
    def test_candidate_valid(self):self.assertTrue(verify(self.base,self.bb,self.candidate,self.cb,self.authored,self.ab)['pass'])
    def test_old_binary_tamper_rejected(self):
        data=bytearray(self.cb);data[3]^=1
        self.assertFalse(verify(self.base,self.bb,self.candidate,bytes(data),self.authored,self.ab)['pass'])
    def test_added_geometry_tamper_rejected(self):
        node=next(n for n in self.candidate['nodes'] if n.get('name')=='cargo_hold_coaming_5.8')
        primitive=self.candidate['meshes'][node['mesh']]['primitives'][0]
        acc=self.candidate['accessors'][primitive['attributes']['POSITION']];view=self.candidate['bufferViews'][acc['bufferView']]
        data=bytearray(self.cb);data[view.get('byteOffset',0)]^=1
        self.assertFalse(verify(self.base,self.bb,self.candidate,bytes(data),self.authored,self.ab)['pass'])
    def test_old_node_tamper_rejected(self):
        candidate=copy.deepcopy(self.candidate);next(n for n in candidate['nodes'] if n.get('name')=='deck')['name']='wrong_deck'
        self.assertFalse(verify(self.base,self.bb,candidate,self.cb,self.authored,self.ab)['pass'])
    def test_obstacle_metadata_tamper_rejected(self):
        candidate=copy.deepcopy(self.candidate);next(n for n in candidate['nodes'] if n.get('name')=='cargo_hold_coaming_-3.2')['extras']['deck_obstacle']=False
        self.assertFalse(verify(self.base,self.bb,candidate,self.cb,self.authored,self.ab)['pass'])
    def test_high_wall_cannot_masquerade_as_r14b(self):
        old,old_bin,_=read_glb(ROOT/'assets/production/hero-fuchuan-blender/r14-author-01-intermediates/fuchuan-lod0.glb')
        candidate,data,_=pack(self.base,self.bb,old,old_bin)
        result=verify(self.base,self.bb,candidate,data,old,old_bin)
        self.assertFalse(result['pass']);self.assertTrue(any('outer dimensions' in e for e in result['errors']),result)
if __name__=='__main__':unittest.main()
