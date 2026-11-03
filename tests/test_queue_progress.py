"""Slow checks and resource contention remain visible without changing their gates."""
from contextlib import redirect_stderr, redirect_stdout
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from tests import test_queue_admission as admission_fixtures, test_queue_worlds as world_fixtures

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import admission, host, progress, report, worlds


class ProgressTests(unittest.TestCase):
    def test_file_progress_is_throttled_and_json_stdout_is_preserved(self):
        now, output, stdout = [0], io.StringIO(), io.StringIO()
        with redirect_stdout(stdout), progress.Phase('verify', total=1000, clock=lambda: now[0], stream=output) as phase:
            for index in range(1000):
                now[0] = index / 100
                phase.step('file-' + str(index))
        lines = output.getvalue().splitlines()
        self.assertEqual(3, len(lines))
        self.assertIn('files="1000/1000"', lines[-1])
        self.assertIn('elapsed_seconds=10.0', lines[-1])
        self.assertEqual('', stdout.getvalue())

    def test_nested_phases_restore_parent_context_and_do_not_inherit_stale_file_details(self):
        output = io.StringIO()
        with progress.Phase('outer', suite='storage-profile', stream=output) as outer:
            outer.step('old.jar')
            with progress.Phase('inner', stream=output):
                progress.file('world.bin')
            progress.file('final.bin')
        self.assertEqual(2, outer.completed)
        self.assertNotIn('old.jar', next(line for line in output.getvalue().splitlines() if 'phase="inner"' in line))

    def test_closed_diagnostic_stream_does_not_replace_the_real_failure(self):
        output = io.StringIO()
        output.close()
        with self.assertRaisesRegex(ValueError, 'real input failure'):
            with progress.Phase('verify', stream=output):
                raise ValueError('real input failure')

    def test_slow_manifest_check_reports_intermediate_files_and_retains_drift_detection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = {}
            for index in range(50):
                path = root / ('input-' + str(index))
                path.write_text(str(index))
                manifest[str(path)] = progress.hash_file(path)
            report.write_json(root / 'inputs.json', manifest)
            now, output = [0], io.StringIO()
            original = progress.hash_file
            def slow(path):
                now[0] += 0.3
                return original(path)
            with redirect_stderr(output), patch.object(progress.time, 'perf_counter', side_effect=lambda: now[0]), \
                    patch.object(progress, 'hash_file', side_effect=slow):
                self.assertEqual([], report.verify_manifest(root, 'inputs.json', absolute=True))
            self.assertGreater(len(output.getvalue().splitlines()), 3)
            self.assertLessEqual(len(output.getvalue().splitlines()), 6)
            self.assertIn('files="50/50"', output.getvalue())
            (root / 'input-0').write_text('changed')
            self.assertTrue(report.verify_manifest(root, 'inputs.json', absolute=True))

    def test_imported_world_verification_names_its_phase_and_keeps_exact_world_hashes(self):
        fixture = world_fixtures.WorldTemplateTests()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        value = fixture.export()
        output = io.StringIO()
        with redirect_stderr(output):
            _, observed = worlds.validate(fixture.template, fixture.selection, fixture.game)
        self.assertEqual(value, observed)
        self.assertIn('phase="verify-world-template"', output.getvalue())
        self.assertIn('phase="hash-world-files"', output.getvalue())
        self.assertIn('files=', output.getvalue())

    def test_fixture_progress_exposes_only_bounded_stage_counters_and_phase_deadline(self):
        now, output = [0], io.StringIO()
        reporter = progress.Fixture({'suite': 'storage-profile', 'timeout_seconds': 900}, clock=lambda: now[0], stream=output)
        execution = {'preflight': {'setup_released': True, 'released': False, 'required_roles': ['client1'],
            'ready': {'client1': {}}, 'fixture_setup': {}, 'timing': {'setup_elapsed_seconds': 15, 'setup_timeout_seconds': 120}}}
        payload = dict(index=200, count=1000, target=5000, private_items=['secret item'] * 200)
        reporter.update({'client1': '[STORAGE_PROFILE] FILL_PROGRESS ' + json.dumps(payload)}, execution)
        self.assertIn('phase="fixture-setup"', output.getvalue())
        self.assertIn('remaining_seconds=105', output.getvalue())
        self.assertIn('fixture_target=5000', output.getvalue())
        self.assertNotIn('secret item', output.getvalue())
        execution['preflight']['released'] = True
        execution['preflight']['timing']['gameplay_elapsed_seconds'] = 3
        reporter.update({'client1': '[SMART_DEPOSIT_HOST] SCENE {"index":1,"total":6}'}, execution)
        self.assertIn('phase="gameplay"', output.getvalue())
        self.assertIn('remaining_seconds=897', output.getvalue())

    def test_host_probe_permission_error_keeps_native_stderr_and_execution_context(self):
        error = subprocess.CalledProcessError(1, ['sysctl'], stderr='Operation not permitted')
        with patch.object(host.sys, 'platform', 'darwin'), patch.object(host, '_output', side_effect=error):
            with self.assertRaisesRegex(RuntimeError, 'Operation not permitted.*outside the sandbox'):
                host.sample()

    def test_food_preparation_and_plain_catalogue_counts_are_reported_without_raw_payloads(self):
        now, output = [0], io.StringIO()
        reporter = progress.Fixture({'suite': 'food', 'timeout_seconds': 900}, clock=lambda: now[0], stream=output)
        execution = {'preflight': {'released': True, 'timing': {'gameplay_elapsed_seconds': 3}}}
        reporter.update({'client1': '[FOOD_TEST] PREPARATION_WAIT {"case":"eat","snapshot":{"private":"hidden"}}'}, execution)
        self.assertIn('stage="PREPARATION_WAIT"', output.getvalue())
        self.assertIn('fixture_case="eat"', output.getvalue())
        self.assertNotIn('hidden', output.getvalue())
        now[0] = 6
        reporter.update({'client1': '[ITEM_CATALOG] READY items=4898 crates=210 skipped=3'}, execution)
        self.assertIn('fixture_items="4898"', output.getvalue())
        now[0] = 12
        reporter.update({'client1': '[ITEM_CATALOG] PROGRESS phase=items completed=100 total=4898'}, execution)
        self.assertIn('fixture_completed="100"', output.getvalue())


class ContentionProgressTests(unittest.TestCase):
    def test_300_second_exclusive_wait_and_1800_second_resume_preserve_the_same_snapshot(self):
        fixture = admission_fixtures.AdmissionTests()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        # Admission uses real lifetime locks and records. Only the host inventory
        # and clock are controlled; no admission/exclusivity checks are bypassed.
        fixture.sample.return_value = admission_fixtures.snapshot(available=30 * 1024**3, total=40 * 1024**3)
        blocker, selection, runtime = fixture.run_config('exclusive-work', exclusive=True)
        selection['suite'] = 'storage-profile'
        root, candidate, config = fixture.run_config('smart-deposit-host', kind='mp', ports=[29171, 29172])
        candidate.update(suite='smart-deposit', options={'mp_host': True, 'world_template': '/sealed/imported-world'})
        snapshot = root / 'snapshot-hashes.json'
        snapshot.write_text('{"prepared":"unchanged"}')
        before = snapshot.read_bytes()
        now, output = [0], io.StringIO()
        def sleep(seconds):
            now[0] += seconds
        with redirect_stderr(output), patch.object(admission.time, 'monotonic', side_effect=lambda: now[0]), \
                patch.object(admission.time, 'sleep', side_effect=sleep), \
                patch.object(progress.time, 'perf_counter', side_effect=lambda: now[0]):
            with admission.acquire(blocker, selection, runtime, wait=0):
                with self.assertRaisesRegex(RuntimeError, 'resource wait expired'):
                    with admission.acquire(root, candidate, config, wait=300):
                        self.fail('exclusive lease was bypassed')
            with admission.acquire(root, candidate, config, wait=1800):
                self.assertEqual(before, snapshot.read_bytes())
        self.assertEqual(300, now[0])
        text = output.getvalue()
        self.assertIn('"storage-profile"', text)
        self.assertIn('suite="smart-deposit"', text)
        self.assertIn('position=1', text)
        self.assertIn('wait_limit_seconds=300', text)
        self.assertIn('wait_limit_seconds=1800', text)
        self.assertIn('status="expired"', text)
        self.assertIn('status="admitted"', text)
        self.assertGreater(len(text.splitlines()), 20)
        self.assertLess(len(text.splitlines()), 65)


if __name__ == '__main__':
    unittest.main()
