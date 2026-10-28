"""Privacy, CF ownership and process isolation for native incident metadata."""
import json
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import desktop_diagnostics as diagnostics


def node(kind, value):
    return (kind, value)


def dictionary(**values):
    return node('Dictionary', values)


def number(value):
    return node('Number', value)


class FakeCF:
    def __init__(self):
        self.released = []
        self.reads = []
        self.CFRelease = self.released.append

    def CFGetTypeID(self, value):
        return value[0]

    def CFDictionaryGetValue(self, row, key):
        key = key[1] if isinstance(key, tuple) else key
        self.reads.append(key)
        return row[1].get(key)

    def CFArrayGetCount(self, values):
        return len(values[1])

    def CFArrayGetValueAtIndex(self, values, index):
        return values[1][index]

    def CFNumberGetValue(self, value, kind, target):
        if value[1] == 'invalid':
            return False
        target._obj.value = value[1] if kind == 6 else int(value[1])
        return True

    def CFBooleanGetValue(self, value):
        return value[1]

    def CFStringCreateWithCString(self, allocator, name, encoding):
        return node('String', name.decode('ascii'))


class MetadataTests(unittest.TestCase):
    def setUp(self):
        self.metadata = diagnostics._Metadata.__new__(diagnostics._Metadata)
        self.cf = self.metadata.cf = FakeCF()
        self.metadata.types = {kind: kind for kind in ('Array', 'Dictionary', 'Number', 'Boolean')}
        self.metadata.keys = {name: name for name in (
            'kCGWindowOwnerPID', 'kCGWindowNumber', 'kCGWindowLayer', 'kCGWindowAlpha',
            'kCGWindowIsOnscreen', 'kCGWindowBounds')}
        self.cg = self.metadata.cg = SimpleNamespace()

    def row(self, pid=123, **overrides):
        values = {'kCGWindowOwnerPID': number(pid), 'kCGWindowNumber': number(99),
                  'kCGWindowLayer': number(0), 'kCGWindowAlpha': number(0.5),
                  'kCGWindowIsOnscreen': node('Boolean', True),
                  'kCGWindowBounds': dictionary(X=number(-20), Y=number(40), Width=number(800), Height=number(600)),
                  'kCGWindowName': node('String', 'private title'),
                  'kCGWindowOwnerName': node('String', 'private app')}
        values.update(overrides)
        return dictionary(**values)

    def windows(self, rows):
        values = node('Array', rows)
        self.cg.CGWindowListCopyWindowInfo = Mock(return_value=values)
        return values, self.metadata.windows(123)

    def test_filters_exact_pid_before_reading_or_persisting_metadata(self):
        foreign = self.row(124)
        owned = self.row()
        values, result = self.windows([foreign, owned, self.row(kCGWindowOwnerPID=node('String', '123'))])
        self.assertEqual(result, {'status': 'returned', 'items': [
            {'pid': 123, 'id': 99, 'layer': 0, 'alpha': .5, 'onscreen': True,
             'bounds': {'x': -20., 'y': 40., 'width': 800., 'height': 600.}}]})
        self.assertEqual(self.cf.reads.count('kCGWindowNumber'), 1)
        self.assertNotIn('kCGWindowName', self.cf.reads)
        self.assertNotIn('kCGWindowOwnerName', self.cf.reads)
        self.assertNotIn('private', json.dumps(result))
        self.assertIn(values, self.cf.released)
        self.cg.CGWindowListCopyWindowInfo.assert_called_once_with(0, 0)

    def test_missing_wrong_types_and_failed_conversions_remain_unknown(self):
        _, result = self.windows([self.row(kCGWindowNumber=None, kCGWindowLayer=number('invalid'),
                                          kCGWindowAlpha=node('Boolean', True),
                                          kCGWindowIsOnscreen=number(1), kCGWindowBounds=node('String', 'bad'))])
        self.assertEqual(result['items'], [{'pid': 123, 'id': None, 'layer': None,
                                           'alpha': None, 'onscreen': None, 'bounds': None}])
        self.assertIsNone(self.metadata.number(number(float('nan')), True))
        self.assertIsNone(self.metadata.number(number(float('inf')), True))

    def test_release_windows_even_when_reader_fails(self):
        values = node('Array', [self.row()])
        self.cg.CGWindowListCopyWindowInfo = Mock(return_value=values)
        self.cf.CFArrayGetValueAtIndex = Mock(side_effect=ValueError('reader failed'))
        with self.assertRaises(ValueError):
            self.metadata.windows(123)
        self.assertEqual(self.cf.released, [values])

    def test_window_enumeration_and_owned_results_are_bounded(self):
        values, result = self.windows([self.row()] * (diagnostics.MAX_ENUMERATED_WINDOWS + 1))
        self.assertEqual(result, {'status': 'limited', 'items': []})
        self.assertEqual(self.cf.reads, [])
        self.assertIn(values, self.cf.released)
        _, result = self.windows([self.row()] * (diagnostics.MAX_OWNED_WINDOWS + 1))
        self.assertEqual(result['status'], 'limited')
        self.assertEqual(len(result['items']), diagnostics.MAX_OWNED_WINDOWS)

    def test_null_or_wrong_type_array_is_unavailable_or_error(self):
        self.cg.CGWindowListCopyWindowInfo = Mock(return_value=None)
        self.assertEqual(self.metadata.windows(123), {'status': 'unavailable', 'items': []})
        value = node('Dictionary', {})
        self.cg.CGWindowListCopyWindowInfo.return_value = value
        self.assertEqual(self.metadata.windows(123), {'status': 'error', 'items': []})
        self.assertEqual(self.cf.released, [value])

    def test_session_only_reads_allowlisted_typed_booleans_and_releases_keys(self):
        value = dictionary(CGSSessionScreenIsLocked=node('Boolean', False),
                           kCGSSessionOnConsoleKey=node('Boolean', True), kCGSessionLoginDoneKey=number(1),
                           kCGSessionUserNameKey=node('String', 'private user'))
        self.cg.CGSessionCopyCurrentDictionary = Mock(return_value=value)
        self.assertEqual(self.metadata.session(), {'status': 'returned', 'screen_locked': False,
                                                  'on_console': True, 'login_done': None})
        self.assertEqual(self.cf.reads, ['CGSSessionScreenIsLocked', 'kCGSSessionOnConsoleKey', 'kCGSessionLoginDoneKey'])
        self.assertEqual(len(self.cf.released), 4)
        self.assertEqual(self.cf.released[-1], value)

    def test_session_unavailable_is_unknown_and_session_released_on_failure(self):
        result = self.metadata.session()
        self.assertEqual(result, {'status': 'unavailable', 'screen_locked': None, 'on_console': None, 'login_done': None})
        value = dictionary()
        self.cg.CGSessionCopyCurrentDictionary = Mock(return_value=value)
        self.cf.CFDictionaryGetValue = Mock(side_effect=OSError('CF failed'))
        with self.assertRaises(OSError):
            self.metadata.session()
        self.assertEqual(self.cf.released[-1], value)
        self.assertEqual(len(self.cf.released), 2)


class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.platform = patch.object(diagnostics.sys, 'platform', 'darwin')
        self.platform.start()
        self.addCleanup(self.platform.stop)
        self.payload = diagnostics._empty(123, 'returned', 'helper-returned')

    def invoke(self, payload=None, returncode=0):
        def run(command, **kwargs):
            self.command, self.options = command, kwargs
            kwargs['stdout'].write(json.dumps(payload if payload is not None else self.payload).encode())
            return SimpleNamespace(returncode=returncode)
        with patch.object(diagnostics.subprocess, 'run', side_effect=run):
            return diagnostics.capture(123)

    def test_isolated_helper_has_deadline_no_ui_or_stderr_and_no_parent_native_calls(self):
        with patch.object(diagnostics, '_Metadata', side_effect=AssertionError('parent native call')):
            result = self.invoke()
        self.assertEqual(result['status'], 'returned')
        self.assertEqual(self.command, [sys.executable, '-I', str(Path(diagnostics.__file__).resolve()), '--worker', '123'])
        self.assertLessEqual(self.options['timeout'], 2)
        self.assertEqual(self.options['stdin'], subprocess.DEVNULL)
        self.assertEqual(self.options['stderr'], subprocess.DEVNULL)

    def test_transport_filters_foreign_rows_and_unapproved_fields(self):
        self.payload.update(secret='private')
        self.payload['windows'] = {'status': 'returned', 'items': [
            {'pid': 124, 'id': 1, 'title': 'foreign private'},
            {'pid': 123, 'id': 2, 'title': 'owned private', 'application': 'private',
             'onscreen': 1, 'alpha': float('nan'), 'layer': True,
             'bounds': {'x': 0, 'y': 0, 'width': -1, 'height': 1}}]}
        result = self.invoke()
        self.assertEqual(result['windows']['items'], [{'pid': 123, 'id': 2, 'layer': None,
                                                      'alpha': None, 'onscreen': None, 'bounds': None}])
        self.assertNotIn('private', json.dumps(result))
        self.assertNotIn('secret', result)

    def test_invalid_pids_and_non_macos_do_not_launch_helper(self):
        with patch.object(diagnostics.subprocess, 'run') as run:
            for pid in (True, False, None, 0, -1, 2**31, '123', 123.):
                self.assertEqual(diagnostics.capture(pid)['reason'], 'invalid-pid')
            with patch.object(diagnostics.sys, 'platform', 'linux'):
                self.assertEqual(diagnostics.capture(123)['reason'], 'not-macos')
            run.assert_not_called()

    def test_timeout_failure_and_unavailable_are_structured_without_exception_text(self):
        for error, status, reason in (
                (subprocess.TimeoutExpired('private path', 1.5, output=b'private'), 'timeout', 'helper-timeout'),
                (OSError('private environment'), 'unavailable', 'helper-unavailable')):
            with self.subTest(error=type(error).__name__), patch.object(diagnostics.subprocess, 'run', side_effect=error):
                result = diagnostics.capture(123)
                self.assertEqual((result['status'], result['reason']), (status, reason))
                self.assertNotIn('private', json.dumps(result))
        self.assertEqual(self.invoke(returncode=-11)['reason'], 'helper-exited')

    def test_malformed_wrong_identity_and_oversized_output_fail_closed(self):
        for payload in ([], {'pid': 124, 'status': 'returned'}, {'pid': 123, 'status': 'invented'}):
            self.assertEqual(self.invoke(payload)['reason'], 'invalid-helper-output')
        for raw, reason in ((b'not json', 'invalid-helper-output'),
                            (b'\xff', 'invalid-helper-output'),
                            (b' ' * (diagnostics.MAX_OUTPUT_BYTES + 1), 'helper-output-limit')):
            def run(command, **kwargs):
                kwargs['stdout'].write(raw)
                return SimpleNamespace(returncode=0)
            with patch.object(diagnostics.subprocess, 'run', side_effect=run):
                self.assertEqual(diagnostics.capture(123)['reason'], reason)

    def test_unavailable_sections_cannot_claim_known_fields(self):
        self.payload['session'] = {'status': 'unavailable', 'screen_locked': True}
        self.payload['windows'] = {'status': 'unavailable', 'items': [{'pid': 123, 'id': 2}]}
        result = self.invoke()
        self.assertIsNone(result['session']['screen_locked'])
        self.assertEqual(result['windows']['items'], [])

    def test_worker_file_limit_and_payload_cap(self):
        raw = diagnostics._empty(123, 'returned', 'helper-returned')
        output = SimpleNamespace(buffer=Mock())
        with patch.object(diagnostics.sys, 'argv', ['diagnostics', '--worker', '123']), \
                patch.object(diagnostics, 'collect', return_value=raw), \
                patch.object(diagnostics.sys, 'stdout', output), \
                patch('resource.setrlimit') as limit:
            self.assertEqual(diagnostics._main(), 0)
            self.assertEqual(limit.call_args.args[1], (diagnostics.MAX_OUTPUT_BYTES, diagnostics.MAX_OUTPUT_BYTES))
            self.assertLessEqual(len(output.buffer.write.call_args.args[0]), diagnostics.MAX_OUTPUT_BYTES)

    def test_display_and_session_do_not_coerce_unknown_or_inconsistent_metadata(self):
        self.payload['display'] = {'state': 'awake', 'displays': []}
        self.payload['session'] = {'status': 'returned', 'screen_locked': 1, 'on_console': 'true', 'login_done': None}
        result = self.invoke()
        self.assertEqual(result['display'], {'state': 'unknown', 'displays': []})
        self.assertEqual(result['session'], {'status': 'returned', 'screen_locked': None,
                                            'on_console': None, 'login_done': None})
        self.payload['display'] = {'state': 'awake', 'displays': [{'id': 1, 'asleep': True}]}
        self.assertEqual(self.invoke()['display']['state'], 'unknown')
        self.payload['display'] = {'state': 'asleep', 'displays': [{'id': 1, 'asleep': True}]}
        self.assertEqual(self.invoke()['display']['state'], 'asleep')


if __name__ == '__main__':
    unittest.main()
