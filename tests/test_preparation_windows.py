"""Windows preparation ownership contracts, with real gated helpers on any host."""
import ctypes
import inspect
import os
from pathlib import Path
import pickle
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import preparation_windows as windows


class PreparationWindowsTests(unittest.TestCase):
    def setUp(self):
        self.kernel = SimpleNamespace(**{name: Mock(return_value=1) for name in
            ('CreateJobObjectW', 'SetInformationJobObject', 'AssignProcessToJobObject',
             'TerminateJobObject', 'QueryInformationJobObject', 'CloseHandle')})
        self.kernel.CreateJobObjectW.return_value = 47
        self.patch = patch.object(windows, '_kernel32', return_value=self.kernel)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)

    def local_job(self):
        job = windows._Job()
        # Host-independent execution checks exercise the real gate/worker/streams;
        # separate API tests verify the actual process handle assignment.
        job._assign = Mock()
        self.addCleanup(job.close)
        return job

    def test_job_is_noninheritable_kill_on_close_and_only_worker_is_assigned(self):
        with windows.contain() as job:
            self.kernel.CreateJobObjectW.assert_called_once_with(None, None)
            handle, information, pointer, length = self.kernel.SetInformationJobObject.call_args.args
            self.assertEqual((handle, information, length), (47, 9, ctypes.sizeof(windows._ExtendedLimits)))
            self.assertEqual(pointer._obj.basic.flags, 0x2000)
            self.kernel.AssignProcessToJobObject.assert_not_called()
            job._assign(SimpleNamespace(_handle=91))
            self.kernel.AssignProcessToJobObject.assert_called_once_with(47, 91)
        self.kernel.TerminateJobObject.assert_called_once_with(47, 1)
        self.kernel.CloseHandle.assert_called_once_with(47)

    def test_cleanup_waits_until_descendants_stop_before_closing(self):
        events = []
        active = iter([3, 1, 0])

        def query(handle, information, pointer, length, returned):
            pointer._obj.active_processes = next(active)
            events.append(pointer._obj.active_processes)
            return 1

        self.kernel.QueryInformationJobObject.side_effect = query
        self.kernel.CloseHandle.side_effect = lambda handle: events.append('close') or 1
        with patch.object(windows.time, 'sleep'):
            with windows.contain():
                pass
        self.assertEqual(events, [3, 1, 0, 'close'])

    def test_setup_failure_closes_job_without_running_a_command(self):
        self.kernel.SetInformationJobObject.return_value = 0
        with patch.object(windows, '_windows_error', return_value=OSError('limits failed')):
            with self.assertRaisesRegex(OSError, 'limits failed'):
                windows._Job()
        self.kernel.CloseHandle.assert_called_once_with(47)
        self.kernel.AssignProcessToJobObject.assert_not_called()

    def test_assignment_failure_never_opens_gate(self):
        job = self.local_job()
        marker = self.directory / 'started'
        job._assign.side_effect = OSError('assignment failed')
        with self.assertRaisesRegex(OSError, 'assignment failed'):
            job.run([sys.executable, '-c', 'from pathlib import Path; Path(__import__("sys").argv[1]).touch()',
                     str(marker)])
        self.assertFalse(marker.exists())

    def test_assignment_precedes_gate_and_command_start(self):
        job = self.local_job()
        marker = self.directory / 'started'

        def assigned(process):
            self.assertFalse(marker.exists())
            self.assertFalse((Path(process.args[-1]) / 'gate').exists())

        job._assign.side_effect = assigned
        command = [sys.executable, '-c', 'from pathlib import Path; Path(__import__("sys").argv[1]).touch()',
                   str(marker)]
        result = job.run(command, check=True)
        self.assertTrue(marker.exists())
        self.assertEqual(result.args, command)
        self.assertEqual(result.returncode, 0)

    def test_worker_without_gate_exits_bounded_without_reading_command(self):
        # There is deliberately no payload: an orphan must not even read it.
        self.assertEqual(windows._worker(self.directory, gate_timeout=.02), 1)
        self.assertFalse((self.directory / 'result').exists())

    def test_worker_without_gate_never_starts_payload(self):
        marker = self.directory / 'started'
        command = [sys.executable, '-c', 'from pathlib import Path; Path(__import__("sys").argv[1]).touch()',
                   str(marker)]
        with (self.directory / 'command').open('wb') as stream:
            pickle.dump((command, {}), stream)
        self.assertEqual(windows._worker(self.directory, gate_timeout=.02), 1)
        self.assertFalse(marker.exists())

    def test_binary_input_capture_and_failed_exit_keep_original_command(self):
        job = self.local_job()
        command = [sys.executable, '-c',
                   'import sys; sys.stdout.buffer.write(sys.stdin.buffer.read()); '
                   'sys.stderr.buffer.write(bytes([255])); sys.exit(7)']
        with self.assertRaises(subprocess.CalledProcessError) as caught:
            job.run(command, input=b'\x00\xff', capture_output=True, check=True)
        self.assertEqual(caught.exception.cmd, command)
        self.assertEqual(caught.exception.returncode, 7)
        self.assertEqual(caught.exception.stdout, b'\x00\xff')
        self.assertEqual(caught.exception.stderr, b'\xff')

    def test_text_cwd_environment_and_merged_stderr(self):
        job = self.local_job()
        command = [sys.executable, '-c',
                   'import os,sys; print(os.getcwd()); print(os.environ["PREPARATION_TEST"]); '
                   'print(sys.stdin.read()); print("error", file=sys.stderr)']
        environment = dict(os.environ, PREPARATION_TEST='private-value')
        result = job.run(command, cwd=self.directory, env=environment, input='caf\u00e9',
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8')
        self.assertIn(str(self.directory), result.stdout)
        self.assertIn('private-value', result.stdout)
        self.assertIn('caf\u00e9', result.stdout)
        self.assertIn('error', result.stdout)
        self.assertIsNone(result.stderr)

    def test_redirected_file_and_missing_executable(self):
        job = self.local_job()
        with (self.directory / 'output').open('wb') as stream:
            result = job.run([sys.executable, '-c', 'print("saved")'], stdout=stream, check=True)
        self.assertIsNone(result.stdout)
        self.assertEqual((self.directory / 'output').read_bytes(), b'saved' + os.linesep.encode())
        with self.assertRaises(FileNotFoundError):
            job.run([str(self.directory / 'missing-command')], capture_output=True)

    def test_timeout_terminates_job_and_retains_captured_output(self):
        job = self.local_job()
        command = ['compiler', 'some input']
        process = Mock()
        process.__enter__ = Mock(return_value=process)
        process.__exit__ = Mock(return_value=False)
        process.returncode = 1
        events = []
        process._handle.Close.side_effect = lambda: events.append('handle-closed')
        self.kernel.QueryInformationJobObject.side_effect = lambda *args: events.append('job-drained') or 1
        process.communicate.side_effect = [subprocess.TimeoutExpired('worker', .5, b'partial'),
                                           (b'partial output', b'diagnostic')]
        launcher = Mock(return_value=process)
        launcher.__signature__ = inspect.signature(subprocess.Popen)
        with patch.object(windows.subprocess, 'Popen', launcher):
            with self.assertRaises(subprocess.TimeoutExpired) as caught:
                job.run(command, capture_output=True, timeout=.5)
        self.kernel.TerminateJobObject.assert_called_once_with(47, 1)
        self.assertEqual(caught.exception.cmd, command)
        self.assertEqual(caught.exception.timeout, .5)
        self.assertEqual(caught.exception.stdout, b'partial output')
        self.assertEqual(caught.exception.stderr, b'diagnostic')
        self.assertLess(events.index('handle-closed'), events.index('job-drained'))

    def test_stream_conflicts_and_closed_context_are_rejected(self):
        job = self.local_job()
        with self.assertRaises(ValueError):
            job.run(['compiler'], input=b'input', stdin=subprocess.PIPE)
        with self.assertRaises(ValueError):
            job.run(['compiler'], capture_output=True, stderr=subprocess.STDOUT)
        job.close()
        with self.assertRaisesRegex(RuntimeError, 'closed'):
            job.run(['compiler'])


if __name__ == '__main__':
    unittest.main()
