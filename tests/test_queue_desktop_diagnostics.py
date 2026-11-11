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


class AccessibilityCaptureTests(unittest.TestCase):
    def setUp(self):
        platform = patch.object(diagnostics.sys, 'platform', 'darwin')
        platform.start()
        self.addCleanup(platform.stop)
        self.payload = diagnostics._ax_empty(123, 'returned', 'helper-returned')
        self.payload['trusted'] = True
        self.payload['timeout_error_code'] = 0
        self.payload['windows'].update(status='returned', error_code=0)

    def invoke(self, payload=None, returncode=0, raw=None):
        def run(command, **kwargs):
            self.command, self.options = command, kwargs
            kwargs['stdout'].write(raw if raw is not None else json.dumps(
                self.payload if payload is None else payload).encode())
            return SimpleNamespace(returncode=returncode)
        with patch.object(diagnostics.subprocess, 'run', side_effect=run):
            return diagnostics.capture_accessibility(123)

    def test_separate_worker_deadline_and_no_parent_native_probe(self):
        with patch.object(diagnostics, '_Accessibility', side_effect=AssertionError('parent native call')):
            result = self.invoke()
        self.assertEqual(result['status'], 'returned')
        self.assertEqual(self.command, [sys.executable, '-I', str(Path(diagnostics.__file__).resolve()),
                                       '--accessibility-worker', '123'])
        self.assertEqual(self.options['timeout'], diagnostics.AX_TIMEOUT_SECONDS)
        self.assertEqual(self.options['stdin'], subprocess.DEVNULL)
        self.assertEqual(self.options['stderr'], subprocess.DEVNULL)
        self.assertGreaterEqual(result['elapsed_ms'], 0)

    def test_transport_allowlist_and_typed_evidence(self):
        self.payload.update(secret='private', elapsed_ms='private')
        self.payload['windows']['items'] = [
            {'pid': 124, 'minimized': True, 'title': 'foreign private'},
            {'pid': True, 'minimized': True},
            {'pid': 123, 'id': True, 'minimized': 1, 'window_id_error_code': 0,
             'minimized_error_code': 0, 'title': 'private'},
            {'pid': 123, 'id': 42, 'minimized': False, 'window_id_error_code': 0,
             'minimized_error_code': 0, 'timeout_error_code': 0, 'elapsed_ms': 2},
            {'pid': 123, 'id': 44, 'minimized': True, 'window_id_error_code': -25204,
             'minimized_error_code': -25205, 'elapsed_ms': float('inf')}]
        result = self.invoke()
        rows = result['windows']['items']
        self.assertEqual([row['id'] for row in rows], [None, 42, None])
        self.assertEqual([row['minimized'] for row in rows], [None, False, None])
        self.assertIsNone(rows[-1]['elapsed_ms'])
        self.assertNotIn('private', json.dumps(result))
        self.assertNotIn('secret', result)

    def test_spoofed_envelopes_and_bounded_rows_fail_closed(self):
        for payload in ([], {'pid': 124, 'status': 'returned'},
                        {'pid': True, 'status': 'returned'}, {'pid': 123, 'status': 'timeout'}):
            self.assertEqual(self.invoke(payload)['reason'], 'invalid-helper-output')
        self.payload['windows']['items'] = [{}] * (diagnostics.MAX_OWNED_WINDOWS + 1)
        self.assertEqual(self.invoke()['reason'], 'invalid-helper-output')
        for raw, reason in ((b'not-json', 'invalid-helper-output'), (b'\xff', 'invalid-helper-output'),
                            (b' ' * (diagnostics.MAX_OUTPUT_BYTES + 1), 'helper-output-limit')):
            self.assertEqual(self.invoke(raw=raw)['reason'], reason)

    def test_failure_and_unknown_do_not_claim_known_window_state(self):
        self.payload['windows']['items'] = [{'pid': 123, 'id': 42, 'minimized': False,
                                             'window_id_error_code': 0, 'minimized_error_code': 0, 'timeout_error_code': 0}]
        for status, trusted, window_status in (('unavailable', True, 'returned'),
                                               ('returned', False, 'returned'),
                                               ('returned', True, 'unsupported')):
            self.payload.update(status=status, trusted=trusted)
            self.payload['windows']['status'] = window_status
            self.assertEqual(self.invoke()['windows']['items'], [])
        self.assertEqual(self.invoke(returncode=-11)['reason'], 'helper-exited')
        for error, status in ((subprocess.TimeoutExpired('private', 1.5), 'timeout'),
                              (OSError('private'), 'unavailable')):
            with patch.object(diagnostics.subprocess, 'run', side_effect=error):
                result = diagnostics.capture_accessibility(123)
            self.assertEqual(result['status'], status)
            self.assertNotIn('private', json.dumps(result))

    def test_invalid_pid_and_platform_never_launch(self):
        with patch.object(diagnostics.subprocess, 'run') as run:
            for pid in (True, None, 0, -1, 2**31, '123', 123.):
                self.assertEqual(diagnostics.capture_accessibility(pid)['reason'], 'invalid-pid')
            with patch.object(diagnostics.sys, 'platform', 'linux'):
                self.assertEqual(diagnostics.capture_accessibility(123)['reason'], 'not-macos')
            run.assert_not_called()

    def test_failed_messaging_or_window_list_cannot_spoof_known_rows(self):
        row = {'pid': 123, 'id': 42, 'minimized': False, 'timeout_error_code': 0,
               'window_id_error_code': 0, 'minimized_error_code': 0}
        self.payload['windows']['items'] = [row]
        self.payload['timeout_error_code'] = -25204
        self.assertEqual(self.invoke()['windows']['status'], 'unavailable')
        self.assertEqual(self.invoke()['windows']['items'], [])
        self.payload['timeout_error_code'] = 0
        self.payload['windows']['error_code'] = -25205
        self.assertEqual(self.invoke()['windows']['status'], 'error')
        self.assertEqual(self.invoke()['windows']['items'], [])
        self.payload['windows']['error_code'] = 0
        row['timeout_error_code'] = -25204
        result = self.invoke()['windows']['items'][0]
        self.assertIsNone(result['id'])
        self.assertIsNone(result['minimized'])

    def test_worker_dispatch_keeps_file_limit(self):
        output = SimpleNamespace(buffer=Mock())
        with patch.object(diagnostics.sys, 'argv', ['diagnostics', '--accessibility-worker', '123']), \
                patch.object(diagnostics, 'collect_accessibility', return_value=self.payload), \
                patch.object(diagnostics, 'collect', side_effect=AssertionError('wrong worker')), \
                patch.object(diagnostics.sys, 'stdout', output), patch('resource.setrlimit') as limit:
            self.assertEqual(diagnostics._main(), 0)
            self.assertEqual(limit.call_args.args[1], (diagnostics.MAX_OUTPUT_BYTES, diagnostics.MAX_OUTPUT_BYTES))


class AccessibilityNativeTests(unittest.TestCase):
    def setUp(self):
        self.native = diagnostics._Accessibility.__new__(diagnostics._Accessibility)
        self.cf = self.native.cf = FakeCF()
        self.native.types = {kind: kind for kind in ('AXUIElement', 'Array', 'Boolean')}
        self.ax = self.native.ax = SimpleNamespace()
        self.ax.AXUIElementSetMessagingTimeout = Mock(return_value=0)
        self.ax.AXIsProcessTrusted = Mock(return_value=True)
        self.app = node('AXUIElement', 123)
        self.ax.AXUIElementCreateApplication = Mock(return_value=self.app)
        self.ax.AXUIElementGetPid = Mock(side_effect=self.get_pid)
        self.native.window_id = Mock(side_effect=self.window_id)
        self.attributes = {}
        self.native.attribute = Mock(side_effect=self.attribute)

    def get_pid(self, row, target):
        target._obj.value = row[1]
        return 0

    def window_id(self, row, target):
        target._obj.value = 42
        return 0

    def attribute(self, element, name):
        return self.attributes.get((element, name), (0, None))

    def windows(self, rows):
        # The fake native values are hashable handles except CFArray containers.
        values = node('Array', rows)
        self.attributes[(self.app, 'AXWindows')] = (0, values)
        return values, self.native.windows(self.app, 123)

    def test_filters_pid_before_other_native_reads_and_releases_only_owned_copies(self):
        foreign, owned = node('AXUIElement', 124), node('AXUIElement', 123)
        minimized = node('Boolean', False)
        self.attributes[(owned, 'AXMinimized')] = (0, minimized)
        values, result = self.windows([foreign, owned, node('String', 'private')])
        self.assertEqual(result['status'], 'limited')
        self.assertEqual(result['items'][0]['minimized'], False)
        self.assertEqual(result['items'][0]['id'], 42)
        self.ax.AXUIElementSetMessagingTimeout.assert_called_once_with(owned, diagnostics.AX_MESSAGE_TIMEOUT_SECONDS)
        self.native.window_id.assert_called_once()
        self.assertEqual(self.native.attribute.call_args_list[-1].args, (owned, 'AXMinimized'))
        self.assertEqual(self.cf.released, [minimized, values])
        self.assertNotIn('private', json.dumps(result))

    def test_owner_lookup_failure_never_reads_attributes_and_retains_code(self):
        self.ax.AXUIElementGetPid.return_value = -25202
        self.ax.AXUIElementGetPid.side_effect = None
        _, result = self.windows([node('AXUIElement', 123)])
        self.assertEqual(result['pid_error_codes'], [-25202])
        self.assertEqual(result['items'], [])
        self.ax.AXUIElementSetMessagingTimeout.assert_not_called()
        self.native.window_id.assert_not_called()
        self.assertEqual(self.native.attribute.call_count, 1)

    def test_unknown_wrong_type_and_unsupported_attributes_are_not_false(self):
        self.native.window_id = None
        for error, value in ((0, node('Number', 0)), (-25205, node('Boolean', False)), (0, None)):
            with self.subTest(error=error, value=value):
                self.attributes[(self.app, 'AXMinimized')] = (error, value)
                _, result = self.windows([self.app])
                self.assertIsNone(result['items'][0]['minimized'])
                self.assertIsNone(result['items'][0]['id'])
                self.assertEqual(result['items'][0]['minimized_error_code'], error)
                self.assertIsNone(result['items'][0]['window_id_error_code'])
                if value:
                    self.assertIn(value, self.cf.released)

    def test_array_errors_caps_and_row_timeout_failure(self):
        for error, status in ((-25205, 'unsupported'), (-25208, 'unsupported'), (-25204, 'error')):
            copied = node('Array', [])
            self.attributes[(self.app, 'AXWindows')] = (error, copied)
            result = self.native.windows(self.app, 123)
            self.assertEqual((result['status'], result['error_code']), (status, error))
            self.assertIn(copied, self.cf.released)
        _, result = self.windows([self.app] * (diagnostics.MAX_OWNED_WINDOWS + 1))
        self.assertEqual(result['status'], 'limited')
        self.ax.AXUIElementGetPid.assert_not_called()
        self.ax.AXUIElementSetMessagingTimeout.return_value = -25202
        _, result = self.windows([self.app])
        self.assertEqual(result['items'][0]['timeout_error_code'], -25202)
        self.assertIsNone(result['items'][0]['minimized'])
        self.native.window_id.assert_not_called()

    def test_copied_array_released_when_window_read_raises(self):
        self.native.window_id.side_effect = ValueError('private')
        with self.assertRaises(ValueError):
            self.windows([self.app])
        self.assertEqual(self.cf.released[-1][0], 'Array')

    def test_read_only_trust_denial_avoids_application_and_returns_unknown(self):
        self.ax.AXIsProcessTrusted.return_value = False
        with patch.object(diagnostics.sys, 'platform', 'darwin'), \
                patch.object(diagnostics, '_Accessibility', return_value=self.native):
            result = diagnostics.collect_accessibility(123)
        self.assertEqual(result['reason'], 'ax-untrusted')
        self.assertFalse(result['trusted'])
        self.assertEqual(result['windows']['items'], [])
        self.ax.AXUIElementCreateApplication.assert_not_called()
        self.ax.AXUIElementSetMessagingTimeout.assert_not_called()

    def test_successful_collection_releases_application_and_preserves_typed_evidence(self):
        values, minimized = node('Array', [self.app]), node('Boolean', True)
        self.attributes[(self.app, 'AXWindows')] = (0, values)
        self.attributes[(self.app, 'AXMinimized')] = (0, minimized)
        with patch.object(diagnostics.sys, 'platform', 'darwin'), \
                patch.object(diagnostics, '_Accessibility', return_value=self.native):
            result = diagnostics.collect_accessibility(123)
        self.assertEqual(result['status'], 'returned')
        self.assertEqual(result['windows']['items'][0]['id'], 42)
        self.assertIs(result['windows']['items'][0]['minimized'], True)
        self.ax.AXUIElementCreateApplication.assert_called_once_with(123)
        self.assertEqual(self.cf.released, [minimized, values, self.app])

    def test_application_release_on_timeout_configuration_failure_and_native_exception(self):
        with patch.object(diagnostics.sys, 'platform', 'darwin'), \
                patch.object(diagnostics, '_Accessibility', return_value=self.native):
            self.ax.AXUIElementSetMessagingTimeout.return_value = -25202
            result = diagnostics.collect_accessibility(123)
            self.assertEqual(result['reason'], 'messaging-timeout-failed')
            self.assertEqual(result['timeout_error_code'], -25202)
            self.assertEqual(self.cf.released, [self.app])
            self.ax.AXUIElementSetMessagingTimeout.return_value = 0
            self.native.attribute.side_effect = OSError('private')
            result = diagnostics.collect_accessibility(123)
            self.assertEqual(result['reason'], 'native-probe-failed')
            self.assertEqual(self.cf.released, [self.app, self.app])

    def test_attribute_copy_releases_key_and_error_value_on_exception(self):
        # Exercise real pointer-output ownership rather than the row-level fake.
        self.native.attribute = diagnostics._Accessibility.attribute.__get__(self.native)
        def copy(element, key, target):
            target._obj.value = 42
            raise ValueError('private')
        self.ax.AXUIElementCopyAttributeValue = Mock(side_effect=copy)
        with self.assertRaises(ValueError):
            self.native.attribute(self.app, 'AXWindows')
        self.assertEqual(self.cf.released, [42, node('String', 'AXWindows')])
        self.ax.AXUIElementCopyAttributeValue.side_effect = lambda element, key, target: -25205
        self.assertEqual(self.native.attribute(self.app, 'AXMinimized'), (-25205, None))
        self.assertEqual(self.cf.released[-1], node('String', 'AXMinimized'))

    def test_native_bindings_expose_only_read_api_and_local_timeout(self):
        cf, ax = Mock(), Mock()
        with patch.object(diagnostics.ctypes, 'CDLL', side_effect=[ax, cf]):
            native = diagnostics._Accessibility()
        self.assertEqual(ax.AXUIElementCreateApplication.argtypes, [diagnostics.ctypes.c_int])
        self.assertEqual(ax.AXIsProcessTrusted.argtypes, [])
        self.assertEqual(ax.AXUIElementSetMessagingTimeout.argtypes,
                         [diagnostics.ctypes.c_void_p, diagnostics.ctypes.c_float])
        self.assertEqual(native.window_id.restype, diagnostics.ctypes.c_int)
        bound = set(ax._mock_children)
        self.assertNotIn('AXUIElementCreateSystemWide', bound)
        self.assertNotIn('AXIsProcessTrustedWithOptions', bound)
        self.assertNotIn('AXUIElementSetAttributeValue', bound)
        self.assertNotIn('AXUIElementPerformAction', bound)


if __name__ == '__main__':
    unittest.main()
