"""Stop timing needs independent inputs, observed Walk and complete native samples."""
import csv
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).parent/'native_queue/contributions/wooden_cart_motion/analyze-stop-timing.py'
spec = importlib.util.spec_from_file_location('stop_timing', SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def evidence():
    lines = ['[WOOD_BANK] RUN_STARTED']
    wheel = []
    for i, name in enumerate(sorted(module.CASES)):
        start = 100000+i*20000
        gait = 2 if 'sprint' in name else 1
        events = [(1000,gait,2),(2500,0,0),(6000,gait,2),(7500,0,2),
                  (7600,0,0),(11000,gait,2),(12500,0,2),(12800,0,0)]
        lines.append(f'[WOOD_BANK] CASE {name} attempt=0 wall={start}')
        for t,g,d in events:
            lines.append(f'[WOOD_RAMP_EVENT] case={name} elapsed={t} gait={g} drive={d} frame={t//25} keyRun={str(g==1).lower()} keySprint={str(g==2).lower()} keyMove={str(d!=0).lower()}')
        for t in range(0,16000,25):
            x = sum(max(0,min(t-begin,end-begin))*.001 for begin,end in ((1000,3100),(6000,7650),(11000,12850)))
            fast = any(begin <= t < end for begin,end in ((1000,2500),(6000,7575),(11000,12575)))
            run, sprint = str(fast and gait==1).lower(), str(fast and gait==2).lower()
            clip = 'Bob_SprintToStop2h_Heavy' if gait==2 else 'Bob_RunToStop2H_Heavy'
            stop_start = next((begin for begin in (2500,7600,12800) if begin<=t<begin+1700),None)
            tracks = f'{clip}@1/{(t-stop_start)/1000}/1/true;' if stop_start is not None else ''
            lines.append(f'[WOOD_BANK_SAMPLE] case={name} wall={start+t} elapsed={t} x={x} y=0 pace=1 speed=.8 run={run} sprint={sprint} item=SaucedWheelbarrow.WheelbarrowWood cartMotion=true native=tracks:{tracks},bones:')
            offset = .4+max(0,4000-t)*.00001 if 2500<=t<4000 else .4
            wheel.append(dict(event='grounding', time=(start+t)/1000, wallTimeMillis=start+t, playerX=x,playerY=0,wheelX=x+offset,wheelY=0,phase=0,lean=0))
        lines.append(f'[WOOD_BANK] COMPLETE {name} wall={start} file=fixture.mp4')
    lines.append('[WOOD_BANK] ALL_COMPLETE cases=4')
    return '\n'.join(lines),wheel


class StopTimingAnalyzerTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.text,self.wheel = evidence()

    def analyze(self, text=None, wheel=None, selected_cases=None):
        rows = self.wheel if wheel is None else wheel
        with (self.root/'wood-wheel-native.csv').open('w') as stream:
            writer = csv.DictWriter(stream, fieldnames=rows[0]);writer.writeheader();writer.writerows(rows)
        return module.analyze(self.root, self.text if text is None else text, selected_cases)

    def test_measures_both_release_clocks_and_real_track(self):
        report = self.analyze()
        self.assertTrue(report['timingVerified'])
        self.assertEqual(report['measurementStartAfterCaseMs'],800)
        direct,walk100,walk300 = report['cases'][0]['stops']
        self.assertEqual([s['modifierLeadMs'] for s in (direct,walk100,walk300)],[0,100,300])
        self.assertEqual(walk100['fromModifierRelease']['lastObservedMovementAfterReleaseMs'],150)
        self.assertEqual(walk100['fromDirectionRelease']['lastObservedMovementAfterReleaseMs'],50)
        self.assertAlmostEqual(walk100['fromModifierRelease']['sampledPathTiles'],.15)
        self.assertTrue(walk100['observedWalkBeforeDirection'])
        self.assertFalse(walk100['nativeBeforeDirection']['run'])
        self.assertTrue(direct['heavyTrack']['behaviorMatchesExpectation'])
        self.assertEqual(walk100['heavyTrack']['observedNames'],['Bob_RunToStop2H_Heavy'])
        self.assertTrue(report['residualBrakingVerified'])
        self.assertTrue(direct['wheelRelativeSettling']['observed'])
        self.assertNotIn('pass',direct['wheelRelativeSettling'])

    def test_missing_heavy_after_walk_fails_residual_braking_gate(self):
        lines = []
        for line in self.text.splitlines():
            if '[WOOD_BANK_SAMPLE]' in line and any(f'elapsed={t} ' in line for t in range(7600,9300,25)):
                line = line.split('native=')[0]+'native=tracks:,bones:'
            lines.append(line)
        report = self.analyze('\n'.join(lines))
        self.assertTrue(report['timingVerified'])
        self.assertFalse(report['residualBrakingVerified'])

    def test_native_planted_track_can_have_zero_rate_and_rewound_clock(self):
        report = self.analyze(self.text.replace('native=tracks:', 'native=tracks:Bob_Idle@.2/-.1/0/true;'))
        self.assertTrue(report['timingVerified'])

    def test_nearest_sample_reports_offset_without_interpolation(self):
        text = self.text.replace('elapsed=7600 gait=0','elapsed=7607 gait=0',1)
        stop = self.analyze(text)['cases'][0]['stops'][1]
        self.assertEqual(stop['modifierLeadMs'],107)
        self.assertEqual(stop['fromDirectionRelease']['nearestSampleOffsetMs'],-7)
        self.assertEqual(stop['fromDirectionRelease']['lastObservedMovementAfterReleaseMs'],43)

    def test_unexpected_heavy_track_remains_descriptive(self):
        report = self.analyze(self.text.replace('Bob_RunToStop2H_Heavy','Bob_SprintToStop2h_Heavy'))
        run = next(case for case in report['cases'] if case['case']=='male-empty-run-stop')
        self.assertFalse(run['stops'][0]['heavyTrack']['behaviorMatchesExpectation'])
        self.assertFalse(report['residualBrakingVerified'])
        self.assertTrue(report['timingVerified'])

    def test_rejects_missing_keys_order_collapsed_frames_and_wrong_delay(self):
        for before,after in (
            (' keyRun=true keySprint=false keyMove=true',''),
            ('elapsed=7600 gait=0 drive=0','elapsed=7600 gait=0 drive=2'),
            ('frame=304 keyRun=false','frame=300 keyRun=false'),
            ('elapsed=7600 gait=0 drive=0','elapsed=7500 gait=0 drive=0'),
            ('elapsed=7600 gait=0 drive=0','elapsed=7800 gait=0 drive=0'),
            ('keyRun=true keySprint=false keyMove=true','keyRun=false keySprint=false keyMove=true'),
        ):
            with self.subTest(after=after),self.assertRaises((ValueError,KeyError)):
                self.analyze(self.text.replace(before,after,1))

    def test_rejects_missing_case_mismatched_attempt_failure_and_missing_walk(self):
        for text in (
            self.text.replace('[WOOD_BANK] CASE','[MISSING]',1),
            self.text.replace('COMPLETE male-empty-run-stop wall=100000','COMPLETE male-empty-run-stop wall=100001'),
            self.text+'\n[WOOD_BANK] FAIL capture',
            self.text.replace('run=false sprint=false','run=true sprint=false'),
        ):
            with self.subTest(text=text[:60]),self.assertRaises(ValueError):self.analyze(text)

    def test_rejects_nonfinite_and_gapped_samples(self):
        for key in ('playerX','wheelX','phase','time'):
            rows = [dict(row) for row in self.wheel];rows[120][key] = float('nan')
            with self.subTest(key=key),self.assertRaises(ValueError):self.analyze(wheel=rows)
        for text in (self.text.replace('pace=1','pace=nan',1),
                     '\n'.join(line for line in self.text.splitlines() if not ('[WOOD_BANK_SAMPLE]' in line and any(f'elapsed={t} ' in line for t in range(2700,3000,25))))):
            with self.assertRaises(ValueError):self.analyze(text)
        with self.assertRaises(ValueError):
            self.analyze(wheel=[row for row in self.wheel if not 102700<=row['wallTimeMillis']<103000])

    def test_reset_nan_outside_case_windows_is_ignored(self):
        resets = []
        for start in (100000,120000,140000,160000):
            reset = dict(self.wheel[0], wallTimeMillis=start-1800, phase=float('nan'),
                         playerX='reset-only', time=float('nan'))
            resets.append(reset)
        report = self.analyze(wheel=resets+self.wheel)
        self.assertTrue(report['timingVerified'])
        inside = dict(resets[0], wallTimeMillis=102000)
        with self.assertRaises(ValueError):self.analyze(wheel=[inside]+self.wheel)
        invalid_clock = dict(resets[0], wallTimeMillis=float('nan'))
        with self.assertRaises(ValueError):self.analyze(wheel=[invalid_clock]+self.wheel)

    def test_pose_can_be_right_censored_without_visual_pass(self):
        rows = [dict(row) for row in self.wheel]
        for row in rows:
            if 103200 <= row['wallTimeMillis'] < 106000:
                row['wheelX'] += (row['wallTimeMillis']-103200)*.0001
        pose = self.analyze(wheel=rows)['cases'][0]['stops'][0]['wheelRelativeSettling']
        self.assertFalse(pose['observed'])
        self.assertIsNone(pose['afterDirectionReleaseMs'])
        self.assertNotIn('pass',pose)

    def test_missing_track_telemetry_and_incomplete_edges_are_rejected(self):
        for text in (self.text.replace('native=tracks:','native=missing:',1),
                     self.text.replace('@1/0.0/1/true;','@bad;',1),
                     '\n'.join(line for line in self.text.splitlines() if not ('[WOOD_BANK_SAMPLE]' in line and any(f'elapsed={t} ' in line for t in range(15500,16000,25))))):
            with self.assertRaises(ValueError):self.analyze(text)
        # Video startup before the uniform 800ms measurement boundary need not be sampled.
        self.assertTrue(self.analyze(wheel=[row for row in self.wheel if row['wallTimeMillis'] >= 100250])['timingVerified'])
        for start,end in ((100800,101100),(101125,101650)):
            with self.subTest(start=start),self.assertRaises(ValueError):
                self.analyze(wheel=[row for row in self.wheel if not start<=row['wallTimeMillis']<end])
            text = '\n'.join(line for line in self.text.splitlines() if not ('[WOOD_BANK_SAMPLE]' in line and
                         any(f'wall={wall} ' in line for wall in range(start,end,25))))
            with self.subTest(bank_start=start),self.assertRaises(ValueError):self.analyze(text)

    def test_selection_scopes_timing_without_weakening_gap_validation(self):
        # The gap lies inside the first scene's Walk100 stop.
        text = '\n'.join(line for line in self.text.splitlines() if not ('[WOOD_BANK_SAMPLE] case=male-empty-run-stop ' in line and
                     any(f'elapsed={t} ' in line for t in range(7700,8250,25))))
        with self.assertRaises(ValueError):self.analyze(text)
        with self.assertRaises(ValueError):self.analyze(text,selected_cases=['male-empty-run-stop'])
        report = self.analyze(text,selected_cases=['male-empty-sprint-stop'])
        self.assertTrue(report['timingVerified'])
        self.assertTrue(report['partialCoverage'])
        self.assertEqual(report['selectedCases'],['male-empty-sprint-stop'])
        self.assertEqual(len(report['cases']),1)
        self.assertEqual(report['evidenceInputs']['groundingCompression'],'none')
        # Independent receipts and finite raw values are still required for every scene.
        with self.assertRaises(ValueError):
            self.analyze(text.replace('[WOOD_BANK] COMPLETE male-full-run-stop','[MISSING] male-full-run-stop'),selected_cases=['male-empty-sprint-stop'])
        rows = [dict(row) for row in self.wheel];rows[110]['phase'] = float('nan')
        with self.assertRaises(ValueError):self.analyze(wheel=rows,selected_cases=['male-empty-sprint-stop'])
        self.assertFalse(self.analyze()['partialCoverage'])

    def test_rejects_unknown_empty_and_duplicate_selections(self):
        for selected in ([],['unknown'],['male-empty-run-stop','male-empty-run-stop']):
            with self.subTest(selected=selected),self.assertRaises(ValueError):
                self.analyze(selected_cases=selected)

    def test_cli_uses_explicit_log_and_refuses_overwrite(self):
        self.analyze()
        log = self.root/'explicit.log';log.write_text(self.text)
        (self.root/'native-launch.log').write_text('wrong log')
        output = self.root/'result.json'
        command = [sys.executable,str(SCRIPT),'--profile',str(self.root),'--log',str(log),'--output',str(output),
                   '--case','male-empty-run-stop','--case','male-full-sprint-stop']
        result = subprocess.run(command,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertTrue(json.loads(output.read_text())['timingVerified'])
        self.assertEqual(len(json.loads(output.read_text())['selectedCases']),2)
        original = output.read_text()
        self.assertNotEqual(subprocess.run(command,capture_output=True).returncode,0)
        self.assertEqual(output.read_text(),original)


if __name__ == '__main__':unittest.main()
