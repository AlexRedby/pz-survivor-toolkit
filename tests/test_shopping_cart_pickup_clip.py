"""The shopping-cart body action stays standing and has stable native idle feet."""
import json
import math
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import cart_clip_bake as baker

class ShoppingPickupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.poses=json.loads((ROOT/'assets/animations/shopping_cart_pickup.json').read_text())
        cls.clip=(ROOT/'PZSurvivorToolkit/42/media/anims_X/Bob/Toolkit_ShoppingCart_Pickup.x').read_text()
        _,cls.parents=baker.template_parts(cls.clip)

    def test_stands_throughout_acquisition_instead_of_looting_crouch(self):
        heights=[row['bones']['Bip01_Spine'][13] for row in self.poses]
        self.assertGreater(min(heights),.55)
        self.assertLess(max(heights)-min(heights),.01)
        self.assertEqual(self.poses[0]['time'],0)
        self.assertEqual(self.poses[-1]['time'],1)
        self.assertEqual(len(self.poses),41)

    def test_native_idle_endpoint_and_toe_direction_are_stable(self):
        # Independently retained native idle contacts from the metal release investigation.
        for side,x in [('L',.07056365),('R',-.07334151)]:
            self.assertAlmostEqual(self.poses[0]['bones'][f'Bip01_{side}_Foot'][12],x,delta=.00003)
            for row in self.poses:
                foot=row['bones'][f'Bip01_{side}_Foot'][12:15]
                toe=row['bones'][f'Bip01_{side}_Toe0'][12:15]
                self.assertLess(abs(math.degrees(math.atan2(toe[0]-foot[0],foot[2]-toe[2]))),.2)
                self.assertGreater(toe[1],-.0002)
                self.assertLess(toe[1],.01)

    def test_joint_lengths_are_preserved_and_asset_matches_editable_source(self):
        baseline=self.poses[0]['bones']
        for row in self.poses:
            for name,parent in self.parents.items():
                if not any(name==f'Bip01_{side}_{part}' for side in ('L','R') for part in ('Forearm','Hand','Calf','Foot','Toe0')):continue
                distance=lambda bones:math.dist(bones[name][12:15],bones[parent][12:15])
                self.assertAlmostEqual(distance(row['bones']),distance(baseline),delta=.00001,msg=(row['time'],name))
        self.assertEqual(baker.bake(self.clip,self.poses,'Toolkit_ShoppingCart_Pickup'),self.clip)

if __name__=='__main__':unittest.main()
