"""Reject incomplete evidence and verify common-frame placement against the existing draw analyzer."""
import copy
import importlib.util
from pathlib import Path
import unittest
import numpy as np

HERE = Path(__file__).resolve().parent

def load(path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

clearance = load(HERE/'check-impact-clearance.py')
impact = load(HERE.parent/'analyze-impact.py')


class ImpactClearanceTests(unittest.TestCase):
    def test_native_camera_composition_matches_existing_cart_points(self):
        matrix = np.array([[72., 1, 3, .01], [2, 73, 5, .12], [-1, 4, 74, -.3], [0, 0, 0, 1]])
        for angle in ([0, 0, 0], [13, -27, 81], [-19, 42, 193]):
            row = dict(angle=angle, x=10822.3, y=10142.5, z=7.00175, transform=matrix.T.reshape(-1).tolist())
            expected = impact.world_cart_points(row)
            for name, point in impact.CART_POINTS.items():
                np.testing.assert_allclose((clearance.world_matrix(row) @ [*point, 1])[:3], expected[name], atol=1e-10)
        for angle in (0, .7, 3.14, -1.9):
            row = dict(slotX=10822.3, slotY=10142.5, slotZ=7., slotAngle=angle, cart=matrix.T.reshape(-1).tolist())
            expected = impact.held_cart_points(row)
            for name, point in impact.CART_POINTS.items():
                np.testing.assert_allclose((clearance.actor_matrix(row) @ matrix @ [*point, 1])[:3], expected[name], atol=1e-10)

    def test_pairing_requires_exact_cart_and_post_release_coverage(self):
        tails = [dict(wallTimeMillis=2000+i*33, impact=True, female=False, cartModel=False) for i in range(50)]
        worlds = [dict(wallTimeMillis=2001+i*33, renderStatus='Ready', itemId=42) for i in range(50)]
        self.assertEqual(len(list(clearance.paired_frames(tails, worlds, 1000, 42, 2001))), 49)
        for mutation in ('wrong_item', 'missing', 'held', 'gap', 'stale', 'late_only'):
            t, w = copy.deepcopy(tails), copy.deepcopy(worlds)
            if mutation == 'wrong_item':
                for r in w: r['itemId'] = 43
            if mutation == 'missing': t = t[:5]
            if mutation == 'held': t[8]['cartModel'] = True
            if mutation == 'gap': del t[8:15]
            if mutation == 'stale': w = w[:2]
            if mutation == 'late_only': t = t[15:]
            with self.subTest(mutation=mutation), self.assertRaises(AssertionError):
                list(clearance.paired_frames(t, w, 1000, 42, 2001))

    def test_leg_region_includes_thigh_only_and_calf_only_faces(self):
        mesh = (6, [('Bip01_R_Thigh', np.array([0]), np.array([1.]), None),
                    ('Bip01_R_Calf', np.array([3]), np.array([1.]), None)], {}, np.array([[0, 1, 2], [3, 4, 5]]))
        np.testing.assert_array_equal(clearance.leg_faces(mesh, 'R'), mesh[3])
        with self.assertRaises(AssertionError): clearance.leg_faces(mesh, 'L')


if __name__ == '__main__': unittest.main()
