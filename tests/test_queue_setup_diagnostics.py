"""Timeout diagnostics target only live owned clients and never hide setup failure."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import setup_diagnostics as diagnostics


class SetupDiagnosticsTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        jdk = self.root / 'jdk'
        tool = jdk / 'bin' / ('jcmd.exe' if os.name == 'nt' else 'jcmd')
        tool.parent.mkdir(parents=True)
        tool.write_text('diagnostic tool input')
        self.runtime = {'jdk': str(jdk.resolve())}
        self.client = SimpleNamespace(pid=123, poll=Mock(return_value=None))
        self.foreign = SimpleNamespace(pid=456, poll=Mock(return_value=None))
        self.processes = {'client1': self.client, 'unrelated': self.foreign}
        self.failure = dict(kind='fixture-setup', role='client1', phase='fixture-setup', reason='Fixture setup deadline expired',
                            evidence={'deadline_exceeded': True, 'pending_roles': ['client1'],
                                      'setup_started': {'client1': {'line': 2, 'paused': True}}})
        self.execution = dict(setup_failure=self.failure, preflight={'required_roles': ['client1']},
                              processes={'client1': {'pid': 123}})

    def collect(self):
        diagnostics.capture(self.root, self.runtime, self.processes, self.execution)
        self.assertIs(self.failure, self.execution['setup_failure'])
        return self.execution['setup_diagnostics']['client1']

    def test_read_only_thread_capture_has_owned_pid_time_bound_and_pause_receipt(self):
        def run(command, **options):
            self.assertEqual(['123', 'Thread.print', '-l'], command[1:])
            self.assertEqual(5, options['timeout'])
            options['stdout'].write(b'owned thread snapshot\n')
            return SimpleNamespace(returncode=0)
        with patch.object(diagnostics.subprocess, 'run', side_effect=run) as called:
            item = self.collect()
        called.assert_called_once()
        self.assertEqual('captured', item['status'])
        self.assertEqual(b'owned thread snapshot\n', (self.root / item['file']).read_bytes())
        self.assertEqual({'line': 2, 'paused': True}, item['pause_at_setup_start'])
        self.foreign.poll.assert_not_called()

    def test_stale_or_exited_client_does_not_attach_to_a_pid(self):
        for mismatch, exited in ((True, False), (False, True)):
            with self.subTest(mismatch=mismatch, exited=exited):
                self.client.pid = 999 if mismatch else 123
                self.client.poll.return_value = 0 if exited else None
                with patch.object(diagnostics.subprocess, 'run') as called:
                    self.assertEqual('unavailable', self.collect()['status'])
                called.assert_not_called()

    def test_hung_diagnostic_preserves_partial_output_and_original_failure(self):
        def hang(command, **options):
            options['stdout'].write(b'partial owned dump')
            raise subprocess.TimeoutExpired(command, options['timeout'])
        with patch.object(diagnostics.subprocess, 'run', side_effect=hang):
            item = self.collect()
        self.assertEqual('timed-out', item['status'])
        self.assertEqual(b'partial owned dump', (self.root / item['file']).read_bytes())
        self.assertEqual(5, item['timeout_seconds'])

    def test_output_is_bounded_and_existing_evidence_is_never_overwritten(self):
        def oversized(command, **options):
            options['stdout'].write(b'x' * (diagnostics.MAX_OUTPUT_BYTES + 1))
            return SimpleNamespace(returncode=0)
        with patch.object(diagnostics.subprocess, 'run', side_effect=oversized):
            item = self.collect()
            self.assertTrue(item['truncated'])
            path = self.root / item['file']
            self.assertEqual(diagnostics.MAX_OUTPUT_BYTES, path.stat().st_size)
            path.write_bytes(b'preserved evidence')
            self.assertEqual('error', self.collect()['status'])
            self.assertEqual(b'preserved evidence', path.read_bytes())

    def test_missing_tool_is_explicit_and_ordinary_gameplay_failure_is_not_probed(self):
        self.runtime.clear()
        with patch.object(diagnostics.subprocess, 'run') as called:
            item = self.collect()
            self.assertEqual('unavailable', item['status'])
            self.assertIn('JDK', item['reason'])
            self.execution.pop('setup_diagnostics')
            self.failure['evidence'] = {}
            diagnostics.capture(self.root, self.runtime, self.processes, self.execution)
            self.assertNotIn('setup_diagnostics', self.execution)
        called.assert_not_called()


if __name__ == '__main__':
    unittest.main()
