"""Real FIFO, inherited measurement locks and bounded loopback attestations."""
from contextlib import contextmanager
import ctypes
from ctypes import wintypes  # Import before emulating Windows on a POSIX host.
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

TOOLS = str(Path(__file__).resolve().parents[1] / 'tools')
sys.path.insert(0, TOOLS)
from queue_checks import admission, preparation_process, timing

GIB = 1024 ** 3
SNAPSHOT = dict(total_memory=16*GIB, available_memory=12*GIB, cpu_count=8, processes=[])
WORKER = '''
import json, sys, time
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from queue_checks import admission, preparation_process
base, root, phase = Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4]
admission.STATE, admission.LEGACY_LOCK = base / 'state', base / 'legacy.lock'
admission.host.sample = lambda: json.loads(sys.argv[5])
admission.shutil.disk_usage = lambda path: type('Disk', (), {'free': 100*1024**3})()
sleep = time.sleep
admission.time.sleep = lambda seconds: sleep(min(.02, seconds))
selection = {'kind': 'sp', 'resources': {'exclusive': True}}
context = (admission.measuring(root, 'unit', wait=10) if phase in ('timing', 'orphan') else
           admission.preparing(root, selection, wait=10) if phase == 'preparing' else
           admission.acquire(root, selection, {'roles': {'client1': {'cache': str(root / 'client1')}}}, wait=10))
with context:
    (root / 'admitted').touch()
    if phase == 'orphan':
        preparation_process.run([sys.executable, '-c', sys.argv[6], str(root)], check=True)
    else:
        deadline = time.monotonic() + 15
        while not (root / 'release').exists():
            if time.monotonic() >= deadline:
                raise RuntimeError('release barrier expired')
            sleep(.01)
'''
CHILD = '''
import os, sys, time
from pathlib import Path
root = Path(sys.argv[1])
(root / 'child.pid').write_text(str(os.getpid()))
deadline = time.monotonic() + 15
while not (root / 'release').exists() and time.monotonic() < deadline:
    time.sleep(.01)
(root / 'finished').touch()
'''
CLIENT = '''
import os, socket, sys
message = sys.argv[2].replace('{PID}', str(os.getpid())).encode('ascii')
with socket.create_connection(('127.0.0.1', int(sys.argv[1])), timeout=3) as connection:
    connection.sendall(message)
    connection.shutdown(socket.SHUT_WR)
    try:
        data = connection.recv(1024)
    except ConnectionResetError:
        data = b''
print(data.decode('ascii'), end='')
'''


@unittest.skipIf(admission.fcntl is None, 'POSIX scheduler tests')
class TimingAdmissionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.state = self.base / 'state'
        self.legacy = self.base / 'legacy.lock'
        for context in (patch.object(admission, 'STATE', self.state),
                        patch.object(admission, 'LEGACY_LOCK', self.legacy),
                        patch.object(admission.host, 'sample', return_value=SNAPSHOT),
                        patch.object(admission.shutil, 'disk_usage', return_value=SimpleNamespace(free=100*GIB))):
            context.start()
            self.addCleanup(context.stop)
        self.workers = []
        self.addCleanup(self.stop_workers)

    def until(self, condition):
        deadline = time.monotonic() + 5
        while not condition():
            if time.monotonic() >= deadline:
                self.fail('Timed out waiting for measurement worker')
            time.sleep(.01)

    def start(self, name, phase):
        root = self.base / name
        root.mkdir()
        process = subprocess.Popen([sys.executable, '-c', WORKER, TOOLS, str(self.base),
                                    str(root), phase, json.dumps(SNAPSHOT), CHILD],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        self.workers.append((process, root))
        return process, root

    def stop_workers(self):
        for process, root in self.workers:
            (root / 'release').touch()
            if process.poll() is None:
                process.kill()
            process.communicate(timeout=20)

    def assert_clear(self):
        state = admission.status()
        self.assertEqual(state['waiting'], [])
        self.assertEqual(state['timing'], [])
        self.assertFalse(state['legacy_lock']['busy'])

    def client(self, registration, message=None):
        if message is None:
            properties = dict(option[2:].split('=', 1) for option in registration.java_options if option.startswith('-D'))
            message = 'PZ_TIMING_V1\t%s\t%s\t{PID}\n' % (properties['pz.timing.token'], registration.bank)
        return preparation_process.check_output([sys.executable, '-c', CLIENT, str(registration.port), message], text=True)

    def trickle(self, registration):
        connection = socket.create_connection(('127.0.0.1', registration.port), timeout=1)
        stop, denied = threading.Event(), threading.Event()
        def send():
            try:
                while not stop.is_set():
                    connection.sendall(b'x')
                    stop.wait(.01)
            except OSError:
                denied.set()
        thread = threading.Thread(target=send)
        thread.start()
        def cleanup():
            stop.set()
            connection.close()
            thread.join(timeout=1)
        self.addCleanup(cleanup)
        return denied

    def test_budget_phase_and_no_game_endpoints_or_disk_requirement(self):
        with patch.object(admission, '_udp', side_effect=AssertionError('UDP game endpoint used')), \
                patch.object(admission, 'disk_capacity', side_effect=AssertionError('game disk required')):
            with admission.measuring(self.base / 'timing', 'unit', wait=0) as details:
                self.assertEqual(details['budget']['memory'], 2560*admission.MIB)
                self.assertEqual(details['budget']['cpu'], 1)
                self.assertTrue(details['exclusive'])
                record = admission.status()['timing'][0]
                self.assertEqual(record['phase'], 'timing')
                self.assertNotIn('ports', record)
                self.assertNotIn('caches', record)
                self.assertEqual(list(self.state.glob('*.json')), [])
                with self.assertRaisesRegex(RuntimeError, 'already admitted'):
                    with admission.measuring(self.base / 'timing', 'unit', wait=0):
                        self.fail('Duplicate root admitted')
        self.assert_clear()
        request = admission.timing_budget(100, 20, 2)
        record = dict(phase='timing', pid=999999, budget=request)
        _, details = admission.capacity(SNAPSHOT, [record], request)
        self.assertEqual(details['active_timings'], 1)
        self.assertEqual(details['cpu_available'], 6)
        self.assertEqual(details['memory_available'], SNAPSHOT['available_memory'] - 120*admission.MIB - int(1.6*GIB))

    def test_invalid_configuration_and_server_start_failure_release_lease(self):
        for kwargs in ({'wait': -1}, {'heap_mib': True}, {'native_mib': 0}, {'cpu': float('inf')},
                       {'cpu': float('nan')}, {'cpu': True}, {'cpu': .5}, {'cpu': 1.0}):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                with timing.acquire(self.base / 'invalid', 'unit', **kwargs):
                    pass
        with self.assertRaises(ValueError):
            with timing.acquire(self.base / 'invalid', 'bad\tbank'):
                pass
        with patch.object(timing.socket, 'socket', side_effect=OSError('bind failed')):
            with self.assertRaisesRegex(OSError, 'bind failed'):
                with timing.acquire(self.base / 'failed', 'unit', wait=0):
                    pass
        self.assert_clear()
        with self.assertRaisesRegex(RuntimeError, 'bank failed'):
            with timing.acquire(self.base / 'retry', 'unit', wait=0):
                raise RuntimeError('bank failed')
        self.assert_clear()

    def test_real_fifo_preparation_measurement_runtime_and_measurement(self):
        with self.legacy.open('a+') as legacy:
            admission.fcntl.flock(legacy, admission.fcntl.LOCK_EX)
            workers = []
            phases = ('preparing', 'timing', 'running', 'timing')
            for index, phase in enumerate(phases, 1):
                workers.append(self.start('fifo-' + str(index), phase))
                self.until(lambda: len(admission.status()['waiting']) == index)
            self.assertEqual([item['phase'] for item in admission.status()['waiting']], list(phases))
            self.assertEqual([item.get('bank') for item in admission.status()['waiting']],
                             [None, 'unit', None, 'unit'])
        for index, (process, root) in enumerate(workers):
            self.until(lambda: (root / 'admitted').exists())
            self.assertTrue(all(not (other / 'admitted').exists() for _, other in workers[index+1:]))
            (root / 'release').touch()
            _, stderr = process.communicate(timeout=3)
            self.assertEqual(process.returncode, 0, stderr)
        self.assert_clear()

    def test_real_owner_death_retains_inherited_lease_until_child_exits(self):
        process, root = self.start('orphan', 'orphan')
        self.until(lambda: (root / 'child.pid').exists())
        process.kill()
        process.wait(timeout=3)
        record = admission.status()['timing'][0]
        self.assertFalse(record['owner_alive'])
        self.assertTrue(admission.status()['legacy_lock']['busy'])
        with self.assertRaisesRegex(RuntimeError, 'resource wait expired'):
            with admission.preparing(self.base / 'next', {'kind': 'sp'}, wait=0):
                self.fail('Orphaned timing JVM lost its admission')
        (root / 'release').touch()
        self.until(lambda: (root / 'finished').exists())
        self.until(lambda: not admission.status()['timing'])
        self.assert_clear()

    def test_live_registration_exact_marker_and_token_free_evidence(self):
        with timing.acquire(self.base / 'registration', 'unit', wait=0, heap_mib=64, native_mib=32) as registration:
            self.assertIn('-Xmx64m', registration.java_options)
            with self.assertRaisesRegex(ValueError, 'live TIMING_ADMISSION'):
                registration.validate('TIMING_ADMISSION %s unit pid=123' % registration.registration_id)
            reply = self.client(registration)
            protocol, identifier, bank, pid = reply.strip().split('\t')
            self.assertEqual((protocol, identifier, bank), ('PZ_TIMING_OK', registration.registration_id, 'unit'))
            marker = 'TIMING_ADMISSION %s unit pid=%s' % (identifier, pid)
            evidence = registration.validate('other bank output\n' + marker + '\n')
            self.assertTrue(evidence['attested'])
            self.assertEqual(evidence['validated_pid'], int(pid))
            self.assertEqual(len(evidence['registered_processes']), 1)
            token = next(option.split('=', 1)[1] for option in registration.java_options if option.startswith('-Dpz.timing.token='))
            self.assertNotIn(token, json.dumps(evidence))
            for invalid in (marker + '\n' + marker, marker + ' extra', marker.replace(' unit ', ' other '), marker.replace('pid=', 'pid=9')):
                with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                    registration.validate(invalid)
        with self.assertRaisesRegex(ValueError, 'no longer live'):
            registration.validate(marker)
        with self.assertRaises(OSError):
            socket.create_connection(('127.0.0.1', registration.port), timeout=.2)
        self.assert_clear()

    def test_malformed_wrong_token_bank_and_unrelated_pid_are_rejected(self):
        with timing.acquire(self.base / 'reject', 'unit', wait=0) as registration:
            token = next(option.split('=', 1)[1] for option in registration.java_options if option.startswith('-Dpz.timing.token='))
            for message in ('garbage\n', 'x'*600 + '\n',
                            'PZ_TIMING_V1\t%s\tunit\t{PID}\n' % ('0'*64),
                            'PZ_TIMING_V1\t%s\tother\t{PID}\n' % token,
                            'PZ_TIMING_V1\t%s\tunit\t0\n' % token,
                            'PZ_TIMING_V1\t%s\tunit\t1\n' % token,
                            'PZ_TIMING_V1\t%s\tunit\t999999999\n' % token):
                with self.subTest(message=message[:20]):
                    self.assertEqual(self.client(registration, message), '')
            self.assertEqual(registration.evidence()['registered_processes'], [])
            self.assertTrue(self.client(registration).startswith('PZ_TIMING_OK'))

    def test_initial_registration_timeout_closes_server_and_validation_fails(self):
        with patch.object(timing, '_REGISTRATION_TIMEOUT', .01):
            with timing.acquire(self.base / 'timeout', 'unit', wait=0) as registration:
                registration._thread.join(timeout=1)
                self.assertFalse(registration._thread.is_alive())
                with self.assertRaisesRegex(ValueError, 'no longer live'):
                    registration.validate('')
                with self.assertRaises(OSError):
                    socket.create_connection(('127.0.0.1', registration.port), timeout=.2)
        self.assert_clear()

    def test_stale_lease_token_and_incomplete_connection_cannot_authorize_next_lease(self):
        with timing.acquire(self.base / 'stale', 'unit', wait=0) as previous:
            stale_token = next(option.split('=', 1)[1] for option in previous.java_options if option.startswith('-Dpz.timing.token='))
            old_reply = self.client(previous).strip().split('\t')
            old_marker = 'TIMING_ADMISSION %s unit pid=%s' % (old_reply[1], old_reply[3])
        with patch.object(timing, '_CONNECTION_TIMEOUT', .05):
            with timing.acquire(self.base / 'stale', 'unit', wait=0) as current:
                self.assertEqual(self.client(current, 'PZ_TIMING_V1\t%s\tunit\t{PID}\n' % stale_token), '')
                with socket.create_connection(('127.0.0.1', current.port), timeout=1) as incomplete:
                    incomplete.sendall(b'PZ_TIMING_V1\t')
                    self.assertEqual(incomplete.recv(1024), b'')
                self.assertTrue(self.client(current).startswith('PZ_TIMING_OK'))
                with self.assertRaises(ValueError):
                    current.validate(old_marker)
        self.assert_clear()

    def test_trickle_request_has_absolute_deadline_and_next_jvm_can_register(self):
        with patch.object(timing, '_CONNECTION_TIMEOUT', .12):
            with timing.acquire(self.base / 'trickle-denied', 'unit', wait=0) as registration:
                denied = self.trickle(registration)
                self.assertTrue(denied.wait(.8), 'Trickle client extended the connection deadline')
                self.assertEqual(registration.evidence()['registered_processes'], [])
                self.assertTrue(self.client(registration).startswith('PZ_TIMING_OK'))
        self.assert_clear()

    def test_context_cleanup_interrupts_active_trickle_and_releases_lease(self):
        with patch.object(timing, '_CONNECTION_TIMEOUT', 2):
            with timing.acquire(self.base / 'trickle-close', 'unit', wait=0) as registration:
                denied = self.trickle(registration)
                self.until(lambda: registration._connection is not None)
                started = time.monotonic()
            self.assertLess(time.monotonic() - started, .8)
            self.assertFalse(registration._thread.is_alive())
            self.assertTrue(denied.wait(.8))
        self.assert_clear()

    def test_windows_reuses_host_mutex_and_closes_job_before_release(self):
        from queue_checks import preparation_windows
        kernel = Mock()
        kernel.CreateMutexW.return_value = 123
        kernel.WaitForSingleObject.return_value = 0
        def memory(pointer):
            pointer._obj.total, pointer._obj.available = 16*GIB, 12*GIB
            return True
        kernel.GlobalMemoryStatusEx.side_effect = memory
        events = []
        @contextmanager
        def contain():
            events.append('job-open')
            try:
                yield object()
            finally:
                events.append('job-close')
        kernel.ReleaseMutex.side_effect = lambda handle: events.append('mutex-release')
        with patch.object(admission, 'fcntl', None), patch.object(admission.os, 'name', 'nt'), \
                patch.object(preparation_windows, 'contain', side_effect=contain), \
                patch('ctypes.WinDLL', return_value=kernel, create=True):
            with self.assertRaisesRegex(ValueError, 'failed'):
                with admission.measuring('unused', 'unit', wait=0) as details:
                    self.assertEqual(details['phase'], 'timing')
                    self.assertTrue(details['budget']['exclusive'])
                    raise ValueError('failed')
        kernel.CreateMutexW.assert_called_once_with(None, False, admission.WINDOWS_HOST_MUTEX)
        self.assertEqual(events, ['job-open', 'job-close', 'mutex-release'])
        kernel.CloseHandle.assert_called_once_with(123)


if __name__ == '__main__':
    unittest.main()
