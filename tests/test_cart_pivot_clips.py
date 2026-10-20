"""Keep editable pivot poses, rigid leg links and planted toes consistent."""
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('cart_clip_bake', ROOT / 'tools/cart_clip_bake.py')
baker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(baker)


class PivotClipTests(unittest.TestCase):
    def test_baked_clips_match_editable_poses_and_preserve_rigid_leg_links(self):
        for direction in ('left', 'right'):
            with self.subTest(direction=direction):
                frames = json.loads((ROOT / f'assets/animations/wood_cart_pivot_{direction}.json').read_text())
                name = f'Toolkit_WoodCartPivot_{direction.title()}'
                clip = (ROOT / f'PZSurvivorToolkit/42/media/anims_X/Bob/{name}.x').read_text()
                self.assertEqual(baker.bake(clip, frames, name), clip)
                for side in ('L', 'R'):
                    chain = [f'Bip01_{side}_{part}' for part in ('Thigh', 'Calf', 'Foot', 'Toe0')]
                    for parent, child in zip(chain, chain[1:]):
                        translations = [baker.multiply(baker.inverse_rigid(f['bones'][parent]),
                                                       f['bones'][child])[12:15] for f in frames]
                        for axis in zip(*translations):
                            self.assertLess(max(axis) - min(axis), .0001, (direction, parent, child))
                for bone, start in frames[0]['bones'].items():
                    if bone == 'Translation_Data':
                        continue
                    self.assertLess(max(abs(a - b) for a, b in zip(start, frames[-1]['bones'][bone])),
                                    .002, (direction, bone, 'loop seam'))

    def test_stance_toes_hold_the_ground_with_extracted_root_motion(self):
        # Native source support windows (exclude lift/plant blending). The right
        # clip has a small original slip. Limits bound the measured native
        # toe/root span scaled by1.35, with <.002 model units of tolerance.
        windows = {'left': [('L', .12, .56, .0065), ('R', .8, 1, .0015)],
                   'right': [('L', 0, .36, .002), ('R', .4, .86, .017)]}
        for direction, feet in windows.items():
            frames = json.loads((ROOT / f'assets/animations/wood_cart_pivot_{direction}.json').read_text())
            for side, start, stop, tolerance in feet:
                positions = [f['bones'][f'Bip01_{side}_Toe0'][12] + f['bones']['Translation_Data'][12]
                             for f in frames if start <= f['time'] / frames[-1]['time'] <= stop]
                self.assertGreater(len(positions), 5)
                self.assertLess(max(positions) - min(positions), tolerance, (direction, side))


if __name__ == '__main__':
    unittest.main()
