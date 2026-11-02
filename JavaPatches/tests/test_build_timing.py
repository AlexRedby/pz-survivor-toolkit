"""Build CLI timing admission is explicit and separate from ordinary checks."""
import json
import os
import subprocess
import traceback
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from JavaPatches import build
from JavaPatches.tests import test_build_checks as fixtures
from tools.queue_checks import admission, timing


class BuildTimingTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.BuildChecks(methodName='runTest')
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.root
        for context in (
                patch.object(admission, 'STATE', self.root / 'state'),
                patch.object(admission, 'LEGACY_LOCK', self.root / 'legacy.lock'),
                patch.object(admission.host, 'sample', return_value={
                    'total_memory': 16 * 1024**3, 'available_memory': 12 * 1024**3, 'cpu_count': 8, 'processes': []}),
                patch.object(admission.shutil, 'disk_usage', return_value=SimpleNamespace(free=100 * 1024**3)),
                patch.object(timing, '_owned_pid', side_effect=lambda pid, owner: pid == os.getpid())):
            context.start()
            self.addCleanup(context.stop)

    def test_untimed_checks_need_no_admission_even_when_they_have_optional_banks(self):
        with patch.object(build, 'timing_modules', side_effect=AssertionError('untimed import')), \
                patch.object(timing, 'acquire', side_effect=AssertionError('untimed lease')):
            self.fixture.run_build('--test', 'NativeTransferRequestsChecks')
        self.assertNotIn('--measure', self.fixture.java_calls()[0].args[0])
        self.assertFalse(list((self.root / 'build').glob('*.timing.json')))

    def test_measure_admits_only_supported_selected_banks_and_saves_attestation(self):
        with patch.object(timing, 'acquire', wraps=timing.acquire) as acquire:
            self.fixture.run_build('--test', 'MediaChecks', '--test', 'QueueLeafTransferFactsChecks',
                                   '--measure', '--resource-wait', '0')
        self.assertEqual(acquire.call_count, 1)
        command = self.fixture.java_calls()[1].args[0]
        self.assertEqual(command[-2:], ['net.alexredby.pztoolkitjavapatches.QueueLeafTransferFactsChecks', '--measure'])
        self.assertIn('-Xmx2048m', command)
        self.assertNotIn('--measure', self.fixture.java_calls()[0].args[0])
        evidence = json.loads((self.root / 'build/QueueLeafTransferFactsChecks.timing.json').read_text())
        self.assertEqual(evidence['status'], 'attested')
        self.assertTrue(evidence['registration']['attested'])
        self.assertTrue(evidence['registration']['admission']['exclusive'])
        self.assertEqual(admission.status()['timing'], [])
        for token in self.fixture.timing_tokens:
            self.assertNotIn(token, json.dumps(evidence))

    def test_measure_rejects_unsupported_selections_before_compilation(self):
        for flags in (['--measure'], ['--measure', '--test', 'MediaChecks'],
                      ['--test', 'QueueLeafTransferFactsChecks', '--measure', '--resource-wait', 'nan']):
            with self.subTest(flags=flags), self.assertRaises(SystemExit) as error:
                self.fixture.run_build(*flags)
            self.assertEqual(error.exception.code, 2)
            self.assertEqual(self.fixture.sentinel.read_text(), 'previous Java mod')

    def test_unregistered_jvm_cannot_attest_even_with_the_functional_pass_marker(self):
        self.fixture.register_timing = False
        with self.assertRaisesRegex(ValueError, 'TIMING_ADMISSION'):
            self.fixture.run_build('--test', 'QueueLeafTransferFactsChecks', '--measure', '--resource-wait', '0')
        self.assertEqual(self.fixture.sentinel.read_text(), 'previous Java mod')
        self.assertEqual(admission.status()['timing'], [])

    def test_timing_wait_stops_before_jvm_and_preserves_previous_artifact(self):
        with admission.preparing(self.root / 'native', {'kind': 'sp', 'resources': {'exclusive': True}}, wait=0):
            with self.assertRaisesRegex(RuntimeError, 'exclusive'):
                self.fixture.run_build('--test', 'QueueLeafTransferFactsChecks', '--measure', '--resource-wait', '0')
        self.assertEqual(self.fixture.java_calls(), [])
        self.assertEqual(self.fixture.sentinel.read_text(), 'previous Java mod')
        evidence = json.loads((self.root / 'build/QueueLeafTransferFactsChecks.timing.json').read_text())
        self.assertEqual(evidence['status'], 'failed')

    def test_failures_release_timing_lease_and_redact_exception_commands(self):
        for case in ('exit', 'timeout'):
            def failed(command):
                if case == 'timeout':
                    return subprocess.TimeoutExpired(command, 9, output='partial')
                return subprocess.CompletedProcess(command, 7, stdout='partial')
            with self.subTest(case=case), self.assertRaises((subprocess.CalledProcessError, RuntimeError)) as error:
                self.fixture.run_build('--test', 'QueueLeafTransferFactsChecks', '--measure',
                                       '--resource-wait', '0', java_result=failed)
            evidence = json.loads((self.root / 'build/QueueLeafTransferFactsChecks.timing.json').read_text())
            self.assertEqual(evidence['status'], 'failed')
            self.assertEqual(admission.status()['timing'], [])
            for token in self.fixture.timing_tokens:
                self.assertNotIn(token, json.dumps(evidence))
                self.assertNotIn(token, ''.join(traceback.format_exception(error.exception)))


if __name__ == '__main__':
    unittest.main()
