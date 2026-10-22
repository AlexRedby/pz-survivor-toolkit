"""The cart graph has exact aliases; unfamiliar names cannot prove native gait."""
from pathlib import Path
import runpy
import unittest

NAMES = runpy.run_path(str(Path(__file__).parent / 'native_queue/contributions/wooden_cart_motion/clip_names.py'))


class CartClipNameTests(unittest.TestCase):
    def test_exact_eleven_alias_contract_and_historical_names(self):
        expected = dict(Idle='Bob_Idle', Walk='Bob_Walk', Run='Bob_Run', Sprint='Bob_Sprint',
                        Backward='Bob_WalkBwdNoAim1Hand', StrafeLeft='Bob_StrafeNoAim_Left',
                        StrafeRight='Bob_StrafeNoAim_Right', WoodLeft='Bob_StrafeNoAim_Left',
                        WoodRight='Bob_StrafeNoAim_Right', StopRun='Bob_RunToStop2H_Heavy',
                        StopSprint='Bob_SprintToStop2h_Heavy')
        for suffix, stock in expected.items():
            with self.subTest(suffix=suffix):
                alias = 'Toolkit_CartPivot_' + suffix
                self.assertEqual(NAMES['native_clip'](alias), stock)
                self.assertEqual(NAMES['native_clip'](stock), stock)
                self.assertIn(alias, NAMES['clip_aliases'](stock))
        for side in ('Left', 'Right'):
            self.assertEqual(NAMES['native_clip']('Toolkit_WoodCartPivot_' + side), 'Bob_StrafeNoAim_' + side)

    def test_no_prefix_substring_case_or_wrong_gait_matches(self):
        walk = NAMES['clip_aliases']('Bob_Walk')
        for name in ('Toolkit_CartPivot_walk', 'Toolkit_CartPivot_WalkExtra', 'ForeignToolkit_CartPivot_Walk',
                     'Toolkit_CartPivot_Unknown', 'Bob_WalkExtra', 'Toolkit_CartPivot_Run',
                     'Toolkit_CartPivot_Backward', 'Toolkit_CartPivot_StopRun'):
            with self.subTest(name=name):
                self.assertNotIn(name, walk)
                self.assertNotEqual(NAMES['native_clip'](name), 'Bob_Walk')
        self.assertEqual(NAMES['clip_aliases']('unknown'), ('unknown',))
