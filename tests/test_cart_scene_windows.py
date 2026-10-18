"""Selected native cart receipts and phase windows, without a game launch."""
import importlib.util
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location(
    'cart_scene_windows', ROOT / 'tests/native_queue/contributions/wooden_cart_motion/evidence/scene_windows.py')
windows = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(windows)


class CartSceneWindowTests(unittest.TestCase):
    names = ['male-empty-back-modifiers', 'female-full-back-arc-left']

    def scene(self, name, start, *, attempt=0, seconds=11.966666666666667, phases=None):
        # scenario-reverse.lua: actual commands, including gait-only changes while reversing.
        phases = phases if phases is not None else [(1019, '0', 3), (3510, '1', 3),
                                                    (5515, '2', 3), (7510, '0', 3), (9510, '0', 0)]
        return ('[WOOD_BANK] CASE ' + name + f' attempt={attempt} wall={start}\n'
                + ''.join(f'[WOOD_RAMP_EVENT] case={name} elapsed={at} gait={gait} drive={drive}\n'
                          for at, gait, drive in phases)
                + f'[WOOD_BANK] COMPLETE {name} wall={start} file=/owned/videos/{name}-{attempt}/capture.mp4'
                  f' frames=359 seconds={seconds}\n')

    def log(self, names=None):
        names = self.names if names is None else names
        return ('[WOOD_BANK] RUN_STARTED\n'
                + ''.join(self.scene(name, 100000 + i * 15000) for i, name in enumerate(names))
                + f'[WOOD_BANK] ALL_COMPLETE cases={len(names)}\n')

    def parse(self, text, names=None, bank='reverse'):
        return windows.completed_windows(text, windows.contract(bank, self.names if names is None else names))

    def test_reverse_subset_uses_exact_selected_names_and_native_phase_labels(self):
        result = self.parse(self.log())
        self.assertEqual(list(result), self.names)
        scene = result[self.names[0]]
        self.assertEqual((scene['measurementStartMs'], scene['measurementEndMs']), (800, 11800))
        self.assertEqual(windows.phase_at(scene, 4000), 'drive=3,gait=1')
        self.assertEqual(windows.phase_at(scene, 500), 'idle')

    def test_missing_extra_reordered_or_duplicate_scene_receipts_are_rejected(self):
        a, b = self.names
        for names in ([a], [a, b, 'male-full-back-modifiers'], [b, a], [a, a]):
            with self.subTest(names=names), self.assertRaises(ValueError):
                self.parse(self.log(names))

    def test_wrong_start_count_duration_and_overlapping_windows_are_rejected(self):
        text = self.log()
        name = self.names[0]
        invalid = {
            'start': text.replace(f'COMPLETE {name} wall=100000', f'COMPLETE {name} wall=100001'),
            'count': text.replace('ALL_COMPLETE cases=2', 'ALL_COMPLETE cases=16'),
            'duration': text.replace('seconds=11.966666666666667', 'seconds=10.9', 1),
            'overlap': text.replace('wall=115000', 'wall=111999'),
            'duplicate-final': text + '[WOOD_BANK] ALL_COMPLETE cases=2\n',
        }
        for reason, log in invalid.items():
            with self.subTest(reason=reason), self.assertRaises(ValueError):
                self.parse(log)

    def test_started_scene_without_complete_is_rejected(self):
        text = self.log()
        lines = [line for line in text.splitlines() if not line.startswith('[WOOD_BANK] COMPLETE ' + self.names[1])]
        with self.assertRaises(ValueError):
            self.parse('\n'.join(lines))

    def test_new_case_cannot_silently_replace_unfinished_attempt(self):
        name = self.names[0]
        abandoned = f'[WOOD_BANK] CASE {name} attempt=0 wall=80000\n'
        with self.assertRaises(ValueError):
            self.parse(self.log().replace('[WOOD_BANK] RUN_STARTED\n', '[WOOD_BANK] RUN_STARTED\n' + abandoned))

    def test_retry_discards_failed_attempt_phases(self):
        name = self.names[0]
        text = ('[WOOD_BANK] RUN_STARTED\n'
                f'[WOOD_BANK] CASE {name} attempt=0 wall=80000\n'
                f'[WOOD_RAMP_EVENT] case={name} elapsed=1000 gait=2 drive=7\n'
                f'[WOOD_BANK] RETRY {name} reason=encoder failed\n'
                + self.scene(name, 100000, attempt=1)
                + '[WOOD_BANK] ALL_COMPLETE cases=1\n')
        result = self.parse(text, [name])[name]
        self.assertEqual(result['start'], 100000)
        self.assertNotIn((1000, 'drive=7,gait=2'), result['phases'])
        self.assertEqual(windows.phase_at(result, 4000), 'drive=3,gait=1')

    def test_nil_gait_keeps_prior_commanded_gait(self):
        name = self.names[0]
        text = ('[WOOD_BANK] RUN_STARTED\n'
                + self.scene(name, 100000, phases=[(1000, 'nil', 0), (1800, '2', 2), (3000, 'nil', 1)])
                + '[WOOD_BANK] ALL_COMPLETE cases=1\n')
        scene = self.parse(text, [name])[name]
        self.assertEqual(windows.phase_at(scene, 1200), 'drive=0,gait=0')
        self.assertEqual(windows.phase_at(scene, 3100), 'drive=1,gait=2')

    def test_equal_time_commands_keep_order_and_exact_time_is_transition(self):
        name = 'male-empty-run-stop'
        # scenario-stop.lua can apply multiple commands on one slow tick. Separate
        # probe streams cannot establish which of those commands preceded a pose.
        text = ('[WOOD_BANK] RUN_STARTED\n'
                + self.scene(name, 100000, phases=[(1000, '1', 2), (5500, '0', 2), (5500, '0', 0)])
                + '[WOOD_BANK] ALL_COMPLETE cases=1\n')
        scene = self.parse(text, [name], bank='stop')[name]
        self.assertEqual(scene['phases'][-2:], [(5500, 'drive=2,gait=0'), (5500, 'drive=0,gait=0')])
        self.assertEqual(windows.phase_at(scene, 5500), 'transition')
        self.assertEqual(windows.phase_at(scene, 5501), 'drive=0,gait=0')

    def test_missing_reversed_out_of_window_or_foreign_phases_are_rejected(self):
        name = self.names[0]
        for phases in ([], [(2000, '0', 3), (1000, '1', 3)], [(12300, '0', 3)]):
            text = ('[WOOD_BANK] RUN_STARTED\n' + self.scene(name, 100000, phases=phases)
                    + '[WOOD_BANK] ALL_COMPLETE cases=1\n')
            with self.subTest(phases=phases), self.assertRaises(ValueError):
                self.parse(text, [name])
        with self.assertRaises(ValueError):
            self.parse(self.log().replace('case=' + name, 'case=unselected', 1))

    def test_malformed_input_phase_cannot_be_accepted_or_silently_skipped(self):
        text = self.log()
        for field, malformed in [('gait=0', 'gait=banana'), ('gait=0', 'gait=3'),
                                 ('drive=3', 'drive=999'), ('elapsed=1019', 'elapsed=-1')]:
            with self.subTest(malformed=malformed), self.assertRaises(ValueError):
                self.parse(text.replace(field, malformed, 1))

    def test_path_uses_real_snapshot_event_keys_and_native_event_names(self):
        name, start = 'male-empty-corner', 100000
        text = f'[WOOD_BANK] RUN_STARTED\n[WOOD_BANK] CASE {name} attempt=0 wall={start}\n'
        phases = [(0, 'prepared'), (1010, 'queued'), (4050, 'terminal'),
                  (4310, 'manual'), (5210, 'manualStopped'), (12010, 'settled')]
        for elapsed, event in phases:
            # scenario-path.lua event() extends snapshot(now), not a synthetic
            # phase field or the WOOD_RAMP_EVENT command schema.
            row = dict(case=name, start=start, wall=start + elapsed, elapsed=elapsed,
                       event=event, id=42, female=False, x=10825.5, y=10142.5, z=7,
                       cargo=0, hasPath=event == 'queued', nativeActions=0, luaActions=0,
                       motion=False, pivot=False, result='', heading=0, drive=0,
                       goalX=10830.5, goalY=10142.5, startX=10825.5, startY=10142.5,
                       wallX=10828, gapY=10142, doorOpen=False)
            text += '[CART_PATH_EVENT] ' + json.dumps(row) + '\n'
        text += (f'[WOOD_BANK] COMPLETE {name} wall={start} file=/owned/videos/capture.mp4'
                 ' frames=361 seconds=12.033\n[WOOD_BANK] ALL_COMPLETE cases=1\n')
        scene = self.parse(text, [name], bank='path')[name]
        self.assertEqual(scene['phases'], phases)
        self.assertEqual(windows.phase_at(scene, 4500), 'manual')
        self.assertEqual(windows.phase_at(scene, 4050), 'transition')
        with self.assertRaises(ValueError):
            self.parse(text.replace('"start": 100000', '"start": 99999', 1), [name], bank='path')
        with self.assertRaises(ValueError):
            self.parse(text.replace('"event": "prepared"', '"event": 17', 1), [name], bank='path')


if __name__ == '__main__':
    unittest.main()
