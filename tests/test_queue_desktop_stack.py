"""Owned stack sampling keeps useful symbols without process headers or source paths."""
import json
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import desktop_stack as stack


REPORT = '''Process: private process [123]
Path: /private/user/executable
Arguments: private argument

Call graph:
    90 Thread_999 DispatchQueue_1: com.apple.main-thread (serial)
      90 start  (in dyld) + 10 [0x123]
        90 -[NSApplication run]  (in AppKit) + 1 [0x456]
          90 privateFunction  (in /private/user/library) + 2
          90 /private/user/source.c  (in library) + 2
    20 Thread_888 private thread name
      20 unrelated_function  (in library) + 3
    10 Thread_777 private Cocoa thread name
      10 __CFRunLoopRun  (in CoreFoundation) + 1
        10 mach_msg  (in libsystem_kernel.dylib) + 4
Total number in stack: 4
Binary Images:
/private/user/hidden-library
'''


class StackTests(unittest.TestCase):
    def test_retains_only_main_and_cocoa_symbols_not_paths_headers_or_other_threads(self):
        value = stack.parse(REPORT, 123)
        self.assertEqual(value['status'], 'returned')
        self.assertEqual([r['kind'] for r in value['threads']], ['main', 'cocoa'])
        self.assertEqual([r['symbol'] for r in value['threads'][0]['frames']], ['start', '-[NSApplication run]'])
        for forbidden in ('private', 'unrelated', '0x123', 'Thread_999'):
            self.assertNotIn(forbidden, json.dumps(value))

    def test_rejects_wrong_report_identity_and_missing_graph(self):
        for text in (REPORT.replace('[123]', '[124]'), REPORT.replace('Call graph:', 'Missing:')):
            self.assertEqual(stack.parse(text, 123)['reason'], 'invalid-report-identity')
        self.assertEqual(stack.parse(REPORT.replace('com.apple.main-thread', 'other').replace('-[NSApplication run]', 'other').replace('__CFRunLoopRun', 'other'), 123)['reason'], 'window-thread-not-found')

    def test_frame_and_thread_retention_is_bounded(self):
        report = 'Process: target [123]\n\nCall graph:\n'
        for i in range(stack.MAX_THREADS + 1):
            report += f'    90 Thread_{i} DispatchQueue_1: com.apple.main-thread\n'
            report += '      90 start  (in dyld) + 10\n' * (stack.MAX_FRAMES + 1)
        value = stack.parse(report, 123)
        self.assertEqual(value['status'], 'limited')
        self.assertEqual(len(value['threads']), stack.MAX_THREADS)
        self.assertTrue(all(row['limited'] and len(row['frames']) == stack.MAX_FRAMES for row in value['threads']))

    def test_numeric_pid_only_and_no_sampler_on_other_platforms(self):
        with patch.object(stack.subprocess, 'run') as run:
            for pid in (True, 0, -1, None, '123', 2**31):
                self.assertEqual(stack.capture(pid)['reason'], 'invalid-pid')
            with patch.object(stack.sys, 'platform', 'linux'):
                self.assertEqual(stack.capture(123)['reason'], 'not-macos')
            run.assert_not_called()

    def test_timeout_unavailable_and_sampler_failure_have_no_raw_error_text(self):
        with patch.object(stack.sys, 'platform', 'darwin'):
            for error, reason in ((subprocess.TimeoutExpired('private arguments', 4), 'sampler-timeout'),
                                  (OSError('private path'), 'sampler-unavailable')):
                with patch.object(stack.subprocess, 'run', side_effect=error):
                    value = stack.capture(123)
                self.assertEqual(value['reason'], reason)
                self.assertNotIn('private', json.dumps(value))
            with patch.object(stack.subprocess, 'run', return_value=SimpleNamespace(returncode=1)):
                self.assertEqual(stack.capture(123)['reason'], 'sampler-exited')

    def test_worker_exec_and_output_are_bounded_without_parent_limits(self):
        def run(argv, **kw):
            self.assertEqual(argv[:4], [sys.executable, '-I', str(Path(stack.__file__).resolve()), '--worker'])
            self.assertEqual(argv[4], '123')
            self.assertEqual(kw['timeout'], stack.TIMEOUT_SECONDS)
            self.assertEqual((kw['stdin'], kw['stdout'], kw['stderr']), (subprocess.DEVNULL,) * 3)
            Path(argv[5]).write_text(REPORT)
            return SimpleNamespace(returncode=0)
        with patch.object(stack.sys, 'platform', 'darwin'), patch.object(stack.subprocess, 'run', side_effect=run):
            self.assertEqual(stack.capture(123)['status'], 'returned')
        with patch.object(stack.sys, 'argv', ['stack', '--worker', '123', '/temporary/report']), \
             patch.object(stack.sys, 'platform', 'darwin'), patch('resource.setrlimit') as limit, \
             patch.object(stack.os, 'execv', side_effect=OSError) as execute:
            self.assertEqual(stack._main(), 2)
        self.assertEqual(limit.call_args.args[1], (stack.MAX_REPORT_BYTES,) * 2)
        self.assertEqual(execute.call_args.args, ('/usr/bin/sample', ['sample', '123', '1', '10', '-mayDie', '-file', '/temporary/report']))


if __name__ == '__main__':
    unittest.main()
