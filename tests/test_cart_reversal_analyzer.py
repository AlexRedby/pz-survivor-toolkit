"""Reversal motion gates reject incomplete and unsafe native evidence."""
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).parent / 'native_queue/contributions/wooden_cart_motion/analyze-reversal.py'
spec = importlib.util.spec_from_file_location('cart_reversal_analyzer', SCRIPT)
analyzer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analyzer)


def evidence():
    lines = ['[WOOD_BANK] RUN_STARTED']
    for index, (sex, cargo, scenario) in enumerate((sex, cargo, scenario) for sex in ('male', 'female')
            for cargo in ('empty', 'full') for scenario in analyzer.SPECS):
        name, start = f'{sex}-{cargo}-{scenario}', 100000 + index * 15000
        lines.append(f'[WOOD_BANK] COMPLETE {name} wall={start}')
        for elapsed in range(0, 12000, 100):
            direction = -1 if 4000 <= elapsed < 8000 else 1
            braking = 3000 <= elapsed < 4000 or 7000 <= elapsed < 8000
            lines.append(f'[WOOD_BANK_SAMPLE] case={name} wall={start + elapsed} elapsed={elapsed} '
                f'x=0 y=0 stepX=0 stepY={direction} run=false sprint=false '
                f'reversal=direction:{direction},requested:{direction},active:false,braking:{str(braking).lower()},neutral:0,actualDistance:0,'
                ' ramp=speed:0,velocity:0,load:0,heading:0,')
    return '\n'.join(lines + ['[WOOD_BANK] ALL_COMPLETE cases=20'])


class ReversalAnalyzerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.log = evidence()

    def test_complete_motion_protocol(self):
        report = analyzer.analyze(self.log)
        self.assertTrue(report['motionPass'])
        self.assertEqual(report['caseCount'], 20)
        self.assertTrue(all(row['samples'] == 120 for row in report['cases']))
        self.assertIn('not a guaranteed 25ms cadence', report['limit'])

    def test_native_track_suffix_and_unused_diagnostics_cannot_replace_coordinates(self):
        log = '\n'.join(line + ' tracks=Bob_RunToStop2H_Heavy=1.0@0.013897641;'
                        if '[WOOD_BANK_SAMPLE]' in line else line for line in self.log.splitlines())
        log = log.replace('velocity:0,', 'velocity:1.0@0.013897641;,')
        self.assertTrue(analyzer.analyze(log)['motionPass'])
        with self.assertRaises(AssertionError):
            analyzer.analyze(log.replace('heading:0,', 'heading:nan,', 1))

    def test_missing_duplicate_or_wrong_cases_and_wrong_final_count(self):
        lines = self.log.splitlines()
        first = next(line for line in lines if ' COMPLETE ' in line)
        for log in (self.log.replace(first, ''), self.log + '\n' + first,
                    self.log.replace('male-empty-walk-switch', 'unexpected'),
                    self.log.replace('ALL_COMPLETE cases=20', 'ALL_COMPLETE cases=200')):
            with self.subTest(log=log[-80:]), self.assertRaises(AssertionError):
                analyzer.analyze(log)

    def test_each_case_needs_full_finite_ordered_sample_coverage(self):
        for log in (self.log.replace('heading:0,', 'heading:nan,', 1),
                    self.log.replace('active:false', 'active:unknown', 1),
                    self.log.replace('run=false', 'run=unknown', 1),
                    '\n'.join(line for line in self.log.splitlines() if not ('SAMPLE]' in line and 'case=male-empty-walk-switch ' in line)),
                    '\n'.join(line for line in self.log.splitlines() if not ('SAMPLE]' in line and int(re.search(r'elapsed=(\d+)', line)[1]) >= 11500)),
                    self.log.replace('elapsed=100 ', 'elapsed=0 ', 1)):
            with self.subTest(log=log[:80]), self.assertRaises(AssertionError):
                analyzer.analyze(log)

    def test_preserved_motion_gates(self):
        samples = self.log.splitlines()
        variants = {
            'flip before measured rest': '\n'.join(line.replace('speed:0,', 'speed:1,') if 'elapsed=3900 ' in line else line for line in samples),
            'field reverses before stop': self.log.replace('stepY=1 ', 'stepY=-1 '),
            'fast reverse': self.log.replace('run=false', 'run=true'),
            'opposite displacement while braking': '\n'.join(line.replace('x=0 ', 'x=-1 ') if 'elapsed=3200 ' in line else line for line in samples),
            'expected two complete flips': self.log.replace('direction:-1,', 'direction:1,'),
        }
        for gate, log in variants.items():
            with self.subTest(gate=gate):
                report = analyzer.analyze(log)
                self.assertFalse(report['motionPass'])
                self.assertIn(gate, [failure[1] for failure in report['failures']])

    def test_cli_uses_explicit_stdout_and_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log, output = root / 'client1-launch.log', root / 'motion.json'
            log.write_text(self.log.replace('run=false', 'run=true'))
            (root / 'native-launch.log').write_text('wrong legacy log')
            command = [sys.executable, str(SCRIPT), '--profile', str(root), '--log', str(log), '--output', str(output)]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertFalse(json.loads(output.read_text())['motionPass'])
            original = output.read_bytes()
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            self.assertEqual(output.read_bytes(), original)


if __name__ == '__main__':
    unittest.main()
