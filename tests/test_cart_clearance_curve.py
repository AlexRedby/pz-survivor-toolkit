"""Keep the authored Blender curve and shipped Java sampler in sync."""
import json
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import cart_blender_clearance as authoring


class ClearanceCurveContract(unittest.TestCase):
    def test_runtime_sampler_matches_authored_asset(self):
        data=json.loads((ROOT/'assets/animations/curves/wood_cart_equip_clearance.json').read_text())
        self.assertEqual(data['schema'],'pz-cart-clearance-curve-v1')
        values=data['samples']
        self.assertEqual((values[0],values[-1]),(0,0))
        self.assertTrue(all(0<=value<=.0081 for value in values))
        self.assertLess(data['maximumApproximationError'],2e-6)
        runtime=ROOT/'JavaPatches/src/net/alexredby/pztoolkitjavapatches/CartEquipClearanceCurve.java'
        self.assertEqual(runtime.read_text(),authoring.java_sampler(values),
                         'Regenerate and deliver both the curve JSON and Java sampler')


if __name__=='__main__':unittest.main()
