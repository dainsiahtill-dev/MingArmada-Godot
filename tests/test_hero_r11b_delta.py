"""Real R9b/R11b delta plus adversarial inputs for the strict color-only gate."""
import copy
import struct
import sys
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools/research'))
import verify_hero_r11b_delta as gate


class TestR11bStrictDelta(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base,cls.base_bin,cls.base_raw=gate.read_glb(gate.BASE/'fuchuan-lod0.glb')
        cls.new,cls.new_bin,cls.new_raw=gate.read_glb(gate.TARGET/'fuchuan-lod0.glb')
        cls.selected=gate.selections(cls.base,cls.base_bin)

    def test_three_real_lods_preserve_all_noncanvas_bytes(self):
        for lod in range(3):
            with self.subTest(lod=lod):
                a,ab,ar=gate.read_glb(gate.BASE/f'fuchuan-lod{lod}.glb')
                b,bb,br=gate.read_glb(gate.TARGET/f'fuchuan-lod{lod}.glb')
                self.assertTrue(gate.verify_delta(a,ab,ar,b,bb,br)['nonTargetBytesIdentical'])

    def test_declared_knots_and_smooth_midpoint(self):
        f32=lambda value:struct.unpack('<f',struct.pack('<f',value))[0]
        self.assertEqual(gate.expected_channel(0.8,0.0,1.0,0),f32(0.8*1.04))
        self.assertEqual(gate.expected_channel(0.8,0.25,1.0,0),f32(0.8*1.00))
        self.assertEqual(gate.expected_channel(0.8,0.5,1.0,0),f32(0.8*0.96))
        self.assertEqual(gate.expected_channel(0.8,0.0,0.875,0),f32(0.8*1.07))
        self.assertEqual(gate.expected_channel(0.8,1.0,0.0,0),f32(0.8*1.01))
        self.assertEqual(gate.expected_channel(1.0,0.0,0.75,0),1.0)

    def test_noncanvas_bin_tampering_is_rejected(self):
        binary=bytearray(self.new_bin);binary[0]^=1
        raw=self.new_raw[:-len(binary)]+bytes(binary)
        with self.assertRaisesRegex(ValueError,'non-canvas'):
            gate.verify_delta(self.base,self.base_bin,self.base_raw,self.new,bytes(binary),raw)

    def test_wrong_color_inside_authorized_span_is_rejected(self):
        binary=bytearray(self.new_bin);binary[self.selected[0]['start']]^=1
        raw=self.new_raw[:-len(binary)]+bytes(binary)
        with self.assertRaisesRegex(ValueError,'differs from declared knots'):
            gate.verify_delta(self.base,self.base_bin,self.base_raw,self.new,bytes(binary),raw)

    def test_noncanvas_material_json_change_is_rejected(self):
        candidate=copy.deepcopy(self.new);candidate['materials'][0]['name']+='-tampered'
        with self.assertRaisesRegex(ValueError,'JSON or length'):
            gate.verify_delta(self.base,self.base_bin,self.base_raw,candidate,self.new_bin,self.new_raw)

    def test_shared_color_accessor_is_rejected(self):
        source=copy.deepcopy(self.base);target=self.selected[0]
        primitive=source['meshes'][target['mesh']]['primitives'][target['primitive']]
        primitive['attributes']['TEXCOORD_9']=target['accessor']
        with self.assertRaisesRegex(ValueError,'shared or aliased'):
            gate.selections(source,self.base_bin)

    def test_shared_color_view_is_rejected(self):
        source=copy.deepcopy(self.base);target=self.selected[0]
        other=next(i for i in range(len(source['accessors'])) if i!=target['accessor'])
        source['accessors'][other]['bufferView']=target['view']
        with self.assertRaisesRegex(ValueError,'shared by another accessor'):
            gate.selections(source,self.base_bin)

    def test_overlapping_buffer_view_is_rejected(self):
        source=copy.deepcopy(self.base);target=self.selected[0]
        other=next(i for i in range(len(source['bufferViews'])) if i!=target['view'])
        source['bufferViews'][other]['byteOffset']=target['start']
        with self.assertRaisesRegex(ValueError,'overlaps another view'):
            gate.selections(source,self.base_bin)

    def test_duplicate_position_with_different_uv_is_rejected(self):
        binary=bytearray(self.base_bin);target=self.selected[0]
        primitive=self.base['meshes'][target['mesh']]['primitives'][target['primitive']]
        accessor=self.base['accessors'][primitive['attributes']['POSITION']]
        view=self.base['bufferViews'][accessor['bufferView']]
        start=view.get('byteOffset',0)+accessor.get('byteOffset',0)
        stride=view.get('byteStride',12)
        self.assertNotEqual(target['uvs'][0],target['uvs'][1])
        binary[start+stride:start+stride+12]=binary[start:start+12]
        with self.assertRaisesRegex(ValueError,'conflicting nominal UVs'):
            gate.selections(self.base,bytes(binary))


if __name__=='__main__':unittest.main(verbosity=2)
