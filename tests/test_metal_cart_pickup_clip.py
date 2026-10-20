"""Metal pickup reduces the hinge without changing planted legs or losing the measured grips."""
import json
import math
import re
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import cart_clip_bake as baker
import retarget_metal_cart_pickup as retarget


def position(matrix):
    return matrix[12:15]


def distance(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


class MetalPickupClipTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.wood = json.loads((ROOT / 'assets/animations/wood_cart_pickup.json').read_text())
        cls.metal = json.loads((ROOT / 'assets/animations/metal_cart_pickup.json').read_text())
        cls.clip = (ROOT / 'PZSurvivorToolkit/42/media/anims_X/Bob/Toolkit_MetalCart_Pickup.x').read_text()
        _, cls.parents = baker.template_parts(cls.clip)

    def test_keeps_all_lower_body_samples_and_body_endpoints_exact(self):
        self.assertEqual([r['time'] for r in self.metal], [r['time'] for r in self.wood])
        self.assertEqual(self.metal[0], self.wood[0], 'pickup approach must start at the accepted native pose')
        for old, new in zip(self.wood, self.metal):
            for bone in self.parents:
                if not retarget.upper_body(bone, self.parents):
                    self.assertEqual(new['bones'][bone], old['bones'][bone], (old['time'], bone))
        for bone in self.parents:
            if not any(retarget.descendant(bone, f'Bip01_{s}_Clavicle', self.parents) for s in ('L', 'R')):
                self.assertEqual(self.metal[-1]['bones'][bone], self.wood[-1]['bones'][bone], bone)

    def test_reduces_only_the_existing_hinge_envelope_and_preserves_rigid_links(self):
        torso = retarget.torso_poses(self.wood, self.parents)
        for old, new, expected in zip(self.wood, self.metal, torso):
            for bone in ('Bip01_Spine', 'Bip01_Spine1', 'Bip01_Neck', 'Bip01_Head'):
                self.assertEqual(new['bones'][bone], expected['bones'][bone], (old['time'], bone))
            for bone, parent in self.parents.items():
                # Native finger-tip Nub markers interpolate through the existing
                # runtime finger-close blend; they are not arm/leg segments.
                if parent is None or bone.endswith('Nub'):
                    continue
                a = distance(position(old['bones'][parent]), position(old['bones'][bone]))
                b = distance(position(new['bones'][parent]), position(new['bones'][bone]))
                self.assertLess(abs(a - b), .000005, (old['time'], bone, 'link length changed'))
        peak = next(i for i, r in enumerate(self.metal) if .44 <= r['time'] <= .48)
        angles = [math.degrees(math.atan2(-rows[peak]['bones']['Bip01_Spine'][2],
                                         rows[peak]['bones']['Bip01_Spine'][1])) for rows in (self.wood, self.metal)]
        self.assertAlmostEqual(angles[0] - angles[1], 18, places=5)
        self.assertLess(angles[1], 47)

    def test_contacts_measured_metal_ground_and_held_handles_with_unlocked_elbows(self):
        # Independent native01 post-grounding observations, not values computed by the generator target.
        peak = next(r for r in self.metal if .44 <= r['time'] <= .48)
        expected = {'L': (.17458296, .39120993, -.05802308),
                    'R': (-.17289883, .39121008, -.058022946)}
        held = {'L': (.17488745, .5312701, -.083618924),
                'R': (-.17256463, .53127027, -.083618864)}
        for side in ('L', 'R'):
            names = [f'Bip01_{side}_{part}' for part in ('UpperArm', 'Forearm', 'Hand')]
            self.assertLess(distance(position(peak['bones'][names[2]]), expected[side]), .00001)
            self.assertLess(distance(position(self.metal[-1]['bones'][names[2]]), held[side]), .00001)
            s, e, w = [position(peak['bones'][name]) for name in names]
            a, b, d = distance(s, e), distance(e, w), distance(s, w)
            flex = math.degrees(math.acos(max(-1, min(1, (d*d-a*a-b*b)/(2*a*b)))))
            self.assertGreater(flex, 15, 'avoid a locked elbow')
            self.assertLess(flex, 50, 'metal pickup should keep the arms straighter than the wood source')

    def test_native_clip_matches_all_editable_poses(self):
        self.assertEqual(baker.bake(self.clip, self.metal, 'Toolkit_MetalCart_Pickup'), self.clip)
        self.assertEqual(len(re.findall(r'^  AnimationKey \{', self.clip, re.M)), 45)
        self.assertEqual(self.clip.count(';16;'), 45 * len(self.metal))


if __name__ == '__main__':
    unittest.main()
