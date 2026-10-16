"""Synthetic evidence checks; no game, meshes or probe attachment required."""
import csv
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
FIELDS = ['spineRootOrientationMaxDelta', 'spineRootDx', 'spineRootDy', 'spineRootDz',
          'maxLegMatrixDelta', 'leftArmLengthBefore', 'leftArmLengthAfter',
          'rightArmLengthBefore', 'rightArmLengthAfter', 'contactLocalY']


class AnalyzerEvidenceTests(unittest.TestCase):
    def fixture(self, root):
        profile, output = root / 'profile', root / 'output'
        profile.mkdir()
        output.mkdir()
        log = ['[WOOD_BANK] RUN_STARTED']
        body, grip, triangles = [], [], []
        identity = [float(i % 5 == 0) for i in range(16)]
        for index in range(16):
            name = f"{'female' if index >= 8 else 'male'}-{'full' if index % 8 >= 4 else 'empty'}-" + ['comparison', 'direct', 'gait', 'runstop'][index % 4] + ('-right' if index % 8 >= 4 else '-left')
            start = 100000 + index * 20000
            log.extend([f'[WOOD_BANK] COMPLETE {name} wall={start}',
                        f'[WOOD_BANK_SAMPLE] case={name} wall={start + 2400} run=true sprint=false'])
            cart = identity.copy()
            cart[13] = .008 + .0041269097 + .001062454
            body.append({'wallTimeMillis': start + 2400, 'cart': cart,
                         'bones': {f'Bip01_{side}_Foot': identity for side in 'LR'}})
            grip.append({'wallTimeMillis': start + 2400, 'result': True})
            triangles.append({'time': start + 2400, 'L': 0, 'R': 0})
        log.append('[WOOD_BANK] ALL_COMPLETE cases=16')
        (profile / 'console.txt').write_text('\n'.join(log))
        for filename, rows in [('body-clearance.jsonl', body), ('wood-grip-poses.jsonl', grip)]:
            (profile / filename).write_text(''.join(json.dumps(row) + '\n' for row in rows))
        for filename in ['hip-triangle-frames.json', 'pants-triangle-frames.json']:
            (output / filename).write_text(json.dumps(triangles))
        self.csv(profile, [{field: 0 for field in FIELDS}])
        return profile, output

    def csv(self, profile, rows):
        with (profile / 'wood-wheel-native.csv').open('w') as stream:
            writer = csv.DictWriter(stream, fieldnames=['event', *FIELDS])
            writer.writeheader()
            for row in rows:
                writer.writerow({'event': 'grounding', **row})

    def analyze(self, profile, output, log=None):
        command = [sys.executable, str(HERE / 'analyze-native.py'), '--profile', str(profile), '--output', str(output)]
        if log is not None:
            command += ['--log', str(log)]
        return subprocess.run(command, capture_output=True, text=True)

    def test_complete_finite_evidence_passes(self):
        with tempfile.TemporaryDirectory() as temp:
            result = self.analyze(*self.fixture(Path(temp)))
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_explicit_stdout_overrides_rotated_console_without_rewriting_it(self):
        with tempfile.TemporaryDirectory() as temp:
            profile, output = self.fixture(Path(temp))
            log = profile.parent / 'client1-launch.log'
            original = (profile / 'console.txt').read_text()
            log.write_text(original)
            (profile / 'console.txt').write_text('[WOOD_BANK] ALL_COMPLETE cases=16\n')
            result = self.analyze(profile, output, log)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads((output / 'native-metrics.json').read_text())['validatedCartCases'], 16)
            self.assertEqual(log.read_text(), original)
            self.assertEqual((profile / 'console.txt').read_text(), '[WOOD_BANK] ALL_COMPLETE cases=16\n')

    def test_missing_explicit_stdout_does_not_fall_back_to_console(self):
        with tempfile.TemporaryDirectory() as temp:
            profile, output = self.fixture(Path(temp))
            self.assertNotEqual(self.analyze(profile, output, profile / 'missing.log').returncode, 0)
            self.assertFalse((output / 'native-metrics.json').exists())

    def test_empty_or_missing_case_geometry_fails(self):
        for filename in ['hip-triangle-frames.json', 'pants-triangle-frames.json', 'body-clearance.jsonl']:
            for empty in [True, False]:
                with self.subTest(filename=filename, empty=empty), tempfile.TemporaryDirectory() as temp:
                    profile, output = self.fixture(Path(temp))
                    path = (profile if filename.endswith('jsonl') else output) / filename
                    if filename.endswith('jsonl'):
                        lines = path.read_text().splitlines()
                        path.write_text('' if empty else '\n'.join(lines[1:]) + '\n')
                    else:
                        rows = json.loads(path.read_text())
                        path.write_text(json.dumps([] if empty else rows[1:]))
                    self.assertNotEqual(self.analyze(profile, output).returncode, 0)

    def test_nonfinite_native_measurement_after_valid_row_fails(self):
        for field in FIELDS:
            for value in ['NaN', 'Infinity', '-Infinity']:
                with self.subTest(field=field, value=value), tempfile.TemporaryDirectory() as temp:
                    profile, output = self.fixture(Path(temp))
                    valid = {name: 0 for name in FIELDS}
                    self.csv(profile, [valid, {**valid, field: value}])
                    self.assertNotEqual(self.analyze(profile, output).returncode, 0)

    def test_nonfinite_geometry_after_valid_frame_fails(self):
        for filename in ['body-clearance.jsonl', 'hip-triangle-frames.json', 'pants-triangle-frames.json']:
            with self.subTest(filename=filename), tempfile.TemporaryDirectory() as temp:
                profile, output = self.fixture(Path(temp))
                path = (profile if filename.endswith('jsonl') else output) / filename
                if filename.endswith('jsonl'):
                    rows = [json.loads(line) for line in path.read_text().splitlines()]
                    rows[1]['cart'][5] = float('nan')
                    path.write_text(''.join(json.dumps(row) + '\n' for row in rows))
                else:
                    rows = json.loads(path.read_text())
                    rows[1]['L'] = float('nan')
                    path.write_text(json.dumps(rows))
                self.assertNotEqual(self.analyze(profile, output).returncode, 0)


if __name__ == '__main__':
    unittest.main()
