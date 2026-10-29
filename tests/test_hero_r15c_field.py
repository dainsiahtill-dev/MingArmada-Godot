"""Mathematical checks for the preregistered field, not a mesh acceptance."""
import math,sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools/research'))
from hero_r15c_field import displacement,quarter_y,sheer
class RailFieldTest(unittest.TestCase):
    def test_outside_and_lower_are_identity(self):
        for z in [-100,-15.6,-9.8,0,10.3,15.7,100]:
            for y in [-10,0,5,30]:self.assertEqual(displacement(y,z),0.)
        for z in [10.31,12,13,15.69]:self.assertAlmostEqual(displacement(sheer(z)+.85,z),0.,places=14)
        for z in [-15.59,-14,-12.7,-9.81]:self.assertAlmostEqual(displacement(quarter_y(z)+.30,z),0.,places=14)
    def test_known_top_amplitudes(self):
        self.assertAlmostEqual(displacement(sheer(13.)+1.34,13.),.85,places=12)
        self.assertAlmostEqual(displacement(quarter_y(-12.7)+.76,-12.7),.55,places=12)
    def test_nonnegative_bounded_monotone_y(self):
        for z in [-15.59,-14.6,-13,-10.5,-9.81,10.31,11.5,13,14.5,15.69]:
            values=[y/20.+displacement(y/20.,z) for y in range(-40,181)]
            self.assertTrue(all(a<b for a,b in zip(values,values[1:])),str(z))
            self.assertTrue(all(0.<=displacement(y/20.,z)<=.850000001 for y in range(-40,181)))
    def test_smooth_endpoints(self):
        for z in [-15.6,-9.8,10.3,15.7]:
            for delta in [-1e-6,1e-6]:self.assertLess(displacement(10.,z+delta),1e-10)
    def test_no_nan_in_finite_domain(self):
        self.assertTrue(all(math.isfinite(displacement(y,z)) for z in range(-20,21) for y in range(-3,12)))
if __name__=='__main__':unittest.main()
