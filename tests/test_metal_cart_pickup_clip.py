"""Grounded metal pickup keeps its feet planted and reaches rigidly with natural knees."""
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

    def test_preserves_foot_targets_and_body_endpoints(self):
        self.assertEqual([r['time'] for r in self.metal], [r['time'] for r in self.wood])
        for bone in self.parents:
            if not any(retarget.descendant(bone, f'Bip01_{s}_Thigh', self.parents) for s in ('L', 'R')):
                self.assertEqual(self.metal[0]['bones'][bone], self.wood[0]['bones'][bone], bone)
        for old, new in zip(self.wood, self.metal):
            if old['time'] < .11818218976259232:
                continue
            for bone in self.parents:
                if any(retarget.descendant(bone, f'Bip01_{s}_Foot', self.parents) for s in ('L', 'R')):
                    self.assertLess(max(abs(a-b) for a,b in zip(new['bones'][bone], old['bones'][bone])),
                                    .000001, (old['time'], bone, 'planted foot moved'))
        for bone in self.parents:
            if not any(retarget.descendant(bone, f'Bip01_{s}_Clavicle', self.parents) for s in ('L', 'R')):
                self.assertEqual(self.metal[-1]['bones'][bone], self.wood[-1]['bones'][bone], bone)

    def test_idle_endpoint_matches_native_feet_without_a_release_twist(self):
        # Settled Bob_Idle from native03 action-tail-poses.jsonl, wall 1792540229454.
        # The new endpoint must meet the native fade target, independently of the
        # arriving source pose that had 25-27 degree outward-pointing feet.
        idle = {'L': ((.07056365, .06529306, .043610204),
                      (.07056385, -.00007939339, -.022839691)),
                'R': ((-.07334151, .06529245, .04361728),
                      (-.07334125, -.00007596612, -.022836585))}
        axes = {'Foot': ((0, -1, 0), (-1, 0, 0), (0, 0, -1)),
                'Toe0': ((0, 0, -1), (-1, 0, 0), (0, 1, 0))}
        for side in ('L', 'R'):
            for part, target in zip(('Foot', 'Toe0'), idle[side]):
                matrix = self.metal[0]['bones'][f'Bip01_{side}_{part}']
                self.assertLess(distance(position(matrix), target), .00003, (side, part))
                for column, expected in enumerate(axes[part]):
                    axis = matrix[column*4:column*4+3]
                    cosine = sum(a*b for a,b in zip(axis, expected)) / distance(axis, (0, 0, 0))
                    self.assertLess(math.degrees(math.acos(max(-1, min(1, cosine)))), .1,
                                    (side, part, 'idle orientation mismatch'))
        for posed in self.metal:
            if posed['time'] >= .11818218976259232:
                break
            for side in ('L', 'R'):
                foot = position(posed['bones'][f'Bip01_{side}_Foot'])
                toe = position(posed['bones'][f'Bip01_{side}_Toe0'])
                forward = [a-b for a,b in zip(toe, foot)]
                self.assertLess(abs(math.degrees(math.atan2(forward[0], -forward[2]))), .1,
                                (posed['time'], side, 'idle-end toes twist outward'))
                self.assertAlmostEqual(toe[1], idle[side][1][1], delta=.00003,
                                       msg=(posed['time'], side, 'toe leaves the floor'))

    def test_grounded_body_envelope_preserves_rigid_links(self):
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
        self.assertAlmostEqual(angles[1] - angles[0], 5, places=5)
        self.assertAlmostEqual(self.wood[peak]['bones']['Bip01_Spine'][13] -
                               self.metal[peak]['bones']['Bip01_Spine'][13], .05, places=6)

    def test_contacts_measured_metal_ground_and_held_handles_with_unlocked_elbows(self):
        # First fully closed grip, before appreciable wheel lift; open hands still follow the shaft bypass.
        peak = next(r for r in self.metal if .48 <= r['time'] <= .50)
        # Physical handle centers measured before the wrist-angle change. These
        # remain fixed while the hand rotates around its .057 X + .036 Z grasp.
        expected = {'L': (.1488610450, .2143914815, .0082985286),
                    'R': (-.1471768658, .2143914434, .0082986037)}
        held = {'L': (0.18883420526981354, 0.4896041333079338, 0.0456046145260334),
                'R': (-0.1865113526582718, 0.4896042338758707, 0.04560464821755886)}
        for side in ('L', 'R'):
            names = [f'Bip01_{side}_{part}' for part in ('UpperArm', 'Forearm', 'Hand')]
            hand = peak['bones'][names[2]]
            palm = [hand[12+i] + .057*hand[i] + .036*hand[8+i] for i in range(3)]
            self.assertLess(distance(palm, expected[side]), .00001, (side, 'palm misses handle'))
            forearm = [a-b for a,b in zip(position(hand), position(peak['bones'][names[1]]))]
            cosine = sum(a*b for a,b in zip(forearm, hand[:3])) / (
                distance(forearm, (0, 0, 0)) * distance(hand[:3], (0, 0, 0)))
            bend = math.degrees(math.acos(max(-1, min(1, cosine))))
            self.assertLessEqual(bend, 45, (side, 'ground wrist bends too far'))
            self.assertLess(distance(position(self.metal[-1]['bones'][names[2]]), held[side]), .00001)
            shoulder, elbow, wrist = [position(self.metal[-1]['bones'][name]) for name in names]
            a, b, d = distance(shoulder, elbow), distance(elbow, wrist), distance(shoulder, wrist)
            neutral_flex = math.degrees(math.acos(max(-1, min(1, (d*d-a*a-b*b)/(2*a*b)))))
            self.assertLess(abs(wrist[2]-shoulder[2]), .035, 'held wrist must hang beside the body')
            self.assertGreater(neutral_flex, 5, 'keep soft elbows rather than locking them')
            self.assertLess(neutral_flex, 25, 'held metal arms must stay almost straight')
            s, e, w = [position(peak['bones'][name]) for name in names]
            a, b, d = distance(s, e), distance(e, w), distance(s, w)
            flex = math.degrees(math.acos(max(-1, min(1, (d*d-a*a-b*b)/(2*a*b)))))
            self.assertGreater(flex, 15, 'avoid a locked elbow')
            self.assertLess(flex, 50, 'metal pickup should keep the arms straighter than the wood source')

    def test_partial_reach_is_applied_only_by_the_live_body_solver(self):
        torso = retarget.torso_poses(self.wood, self.parents)
        for posed, baseline in zip(self.metal, torso):
            if posed['time'] >= .44:
                continue
            for bone in self.parents:
                if any(retarget.descendant(bone, f'Bip01_{s}_Clavicle', self.parents) for s in ('L', 'R')):
                    self.assertLess(max(abs(a-b) for a,b in zip(posed['bones'][bone], baseline['bones'][bone])),
                                    .000001, (posed['time'], bone, 'partial reach was baked twice'))

    def test_knees_follow_planted_toes_and_clavicles_stay_bounded(self):
        torso = retarget.torso_poses(self.wood, self.parents)
        def vector(a, b):
            return [x-y for x,y in zip(a,b)]
        def dot(a, b):
            return sum(x*y for x,y in zip(a,b))
        def length(a):
            return math.sqrt(dot(a,a))
        def project(a, axis):
            return [x-dot(a,axis)*y for x,y in zip(a,axis)]
        for posed, baseline in zip(self.metal[:-1], torso[:-1]):
            for side in ('L','R'):
                p = lambda name: position(posed['bones'][f'Bip01_{side}_{name}'])
                b = lambda name: position(baseline['bones'][f'Bip01_{side}_{name}'])
                axis = vector(p('Foot'),p('Thigh'))
                axis = [x/length(axis) for x in axis]
                knee = project(vector(p('Calf'),p('Thigh')),axis)
                toes = vector(p('Toe0'),p('Foot'))
                toes[1] = 0
                toes = project(toes,axis)
                self.assertGreater(dot(knee,toes)/length(knee)/length(toes), .999,
                                   (posed['time'],side,'reversed knee'))
                before = vector(b('UpperArm'),b('Clavicle'))
                after = vector(p('UpperArm'),p('Clavicle'))
                angle = math.degrees(math.acos(max(-1,min(1,dot(before,after)/length(before)/length(after)))))
                self.assertLess(angle,35.01,(posed['time'],side,'clavicle limit'))

    def test_native_clip_matches_all_editable_poses(self):
        self.assertEqual(baker.bake(self.clip, self.metal, 'Toolkit_MetalCart_Pickup'), self.clip)
        self.assertEqual(len(re.findall(r'^  AnimationKey \{', self.clip, re.M)), 45)
        self.assertEqual(self.clip.count(';16;'), 45 * len(self.metal))


if __name__ == '__main__':
    unittest.main()
