"""Preparation/run coordination without starting a game or copying game inputs."""
import ctypes
from ctypes import wintypes  # Load before tests temporarily emulate os.name == nt.
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import admission

GIB = 1024 ** 3
TOOLS = str(Path(__file__).resolve().parents[1] / 'tools')
WORKER = '''
import json, sys, time
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from queue_checks import admission
base, root = Path(sys.argv[2]), Path(sys.argv[3])
admission.STATE = base / 'state'
admission.LEGACY_LOCK = base / 'legacy.lock'
admission.host.sample = lambda: {'total_memory': 10*1024**3, 'available_memory': 8*1024**3, 'cpu_count': 16, 'processes': []}
admission.shutil.disk_usage = lambda path: type('Disk', (), {'free': 100*1024**3})()
original_sleep = time.sleep
admission.time.sleep = lambda seconds: original_sleep(min(.02, seconds))
selection = {'kind': 'sp', 'clients': 1, 'resources': {'exclusive': sys.argv[5] == 'exclusive'}}
try:
    context = (admission.preparing(root, selection, wait=10) if sys.argv[4] == 'prepare' else
               admission.acquire(root, selection, {'roles': {'client1': {'cache': str(root / 'client1')}}}, wait=10))
    with context:
        (root / 'admitted').touch()
        while not (root / 'release').exists():
            original_sleep(.01)
except Exception as error:
    (root / 'error').write_text(str(error))
    raise
'''


def snapshot(available=8*GIB, processes=()):
    return {'total_memory': 10*GIB, 'available_memory': available, 'cpu_count': 16,
            'processes': list(processes)}


class PreparationAdmissionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.state = self.base / 'state'
        self.legacy = self.base / 'legacy.lock'
        self.addCleanup(patch.stopall)
        patch.object(admission, 'STATE', self.state).start()
        patch.object(admission, 'LEGACY_LOCK', self.legacy).start()
        self.sample = patch.object(admission.host, 'sample', return_value=snapshot()).start()
        patch.object(admission.shutil, 'disk_usage', return_value=SimpleNamespace(free=100*GIB)).start()
        self.workers = []
        self.addCleanup(self.stop_workers)

    def config(self, name, exclusive=False):
        root = self.base / name
        root.mkdir()
        selection = {'kind': 'sp', 'clients': 1, 'resources': {'exclusive': exclusive}}
        runtime = {'roles': {'client1': {'cache': str(root / 'client1')}}}
        return root, selection, runtime

    def start(self, name, phase='prepare', exclusive=False):
        root = self.base / name
        root.mkdir()
        process = subprocess.Popen([sys.executable, '-c', WORKER, TOOLS, str(self.base), str(root),
                                    phase, 'exclusive' if exclusive else 'shared'],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        self.workers.append((process, root))
        return process, root

    def until(self, condition):
        deadline = time.monotonic() + 5
        while not condition():
            if time.monotonic() >= deadline:
                self.fail('Timed out waiting for subprocess admission state')
            time.sleep(.01)

    def stop_workers(self):
        for process, root in self.workers:
            (root / 'release').touch()
            try:
                process.communicate(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate(timeout=2)

    def test_budget_is_fixed_and_preparation_needs_no_runtime_roles(self):
        selection = {'kind': 'mp', 'clients': 4, 'resources': {'heap_mib': 8000, 'exclusive': True}}
        request = admission.preparation_budget(selection)
        self.assertEqual(request, {'memory': GIB, 'cpu': 1, 'exclusive': True})
        root, _, _ = self.config('small')
        self.sample.return_value = snapshot(available=2*GIB)
        with admission.preparing(root, selection, wait=0) as details:
            self.assertEqual(details['budget'], request)
            self.assertEqual(admission.status()['preparing'][0]['phase'], 'preparing')
            self.assertEqual(list(self.state.glob('*.json')), [])
        self.assertEqual(admission.status()['preparing'], [])

    def test_active_preparation_budget_blocks_runtime_and_deducts_owner_usage(self):
        root, selection, _ = self.config('prepare')
        run = self.config('run')
        self.sample.return_value = snapshot(available=2*GIB)
        with admission.preparing(root, selection, wait=0):
            with self.assertRaisesRegex(RuntimeError, 'Insufficient resources'):
                with admission.acquire(*run, wait=0):
                    self.fail('Runtime ignored active preparation memory')
        record = {'phase': 'preparing', 'pid': 17, 'budget': admission.preparation_budget(selection)}
        process = {'pid': 17, 'rss': GIB//2, 'cpu': .5, 'game': False, 'command': 'python prepare'}
        permitted, details = admission.capacity(snapshot(available=2*GIB, processes=[process]), [record],
                                                 {'memory': GIB//2, 'cpu': 1})
        self.assertTrue(permitted)
        self.assertEqual(details['memory_available'], GIB//2)
        self.assertEqual(details['active_preparations'], 1)
        self.assertFalse(admission.capacity(snapshot(available=GIB, processes=[dict(process, pid=os.getpid())]), [],
                                             record['budget'], os.getpid())[0])
        self.assertTrue(admission.capacity(snapshot(available=GIB+GIB//2, processes=[dict(process, pid=os.getpid())]), [],
                                           record['budget'], os.getpid())[0])

    def test_same_python_owner_usage_is_attributed_only_once(self):
        request = admission.preparation_budget({'kind': 'sp'})
        record = {'phase': 'preparing', 'pid': 17, 'budget': request}
        process = {'pid': 17, 'rss': GIB//2, 'cpu': .5, 'game': False, 'command': 'python prepare'}
        permitted, details = admission.capacity(snapshot(available=3*GIB, processes=[process]),
                                                 [record, record], {'memory': GIB//2, 'cpu': 1}, 17)
        self.assertTrue(permitted)
        self.assertEqual(details['memory_available'], GIB//2)
        self.assertFalse(admission.capacity(snapshot(available=3*GIB, processes=[process]),
                                            [record, record], request, 17)[0])

    def test_prepared_ports_survive_success_exception_and_interruption(self):
        root, selection, _ = self.config('ports')
        for exception in (None, ValueError('copy failed'), KeyboardInterrupt()):
            with self.subTest(exception=exception):
                try:
                    with admission.preparing(root, selection, wait=0):
                        ports = admission.allocate_ports(root, selection)
                        if exception:
                            raise exception
                except (ValueError, KeyboardInterrupt):
                    pass
                status = admission.status()
                self.assertEqual(status['preparing'], [])
                self.assertEqual(status['waiting'], [])
                self.assertEqual(status['prepared'][0]['ports'], ports)
                self.assertFalse(status['legacy_lock']['busy'])
                self.assertFalse(admission._held(root))

    def test_preparation_legacy_lock_blocks_in_both_directions(self):
        root, selection, _ = self.config('legacy')
        with self.legacy.open('a+') as legacy:
            fcntl.flock(legacy, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(RuntimeError, 'resource wait expired'):
                with admission.preparing(root, selection, wait=0):
                    self.fail('Preparation bypassed old runner')
        self.assertEqual(admission.status()['waiting'], [])
        with admission.preparing(root, selection, wait=0):
            with self.legacy.open('a+') as legacy, self.assertRaises(BlockingIOError):
                fcntl.flock(legacy, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(RuntimeError, 'already admitted or waiting'):
                with admission.preparing(root, selection, wait=0):
                    self.fail('Duplicate root admitted')

    def test_real_process_exclusive_conflicts_in_both_directions(self):
        for first_phase, exclusive in [('prepare', False), ('prepare', True), ('run', False), ('run', True)]:
            with self.subTest(first_phase=first_phase, exclusive=exclusive):
                process, root = self.start(first_phase + str(exclusive), first_phase, exclusive)
                self.until(lambda: (root / 'admitted').exists())
                config = self.config('second-' + first_phase + str(exclusive), not exclusive)
                second = admission.acquire(*config, wait=0) if first_phase == 'prepare' else admission.preparing(*config[:2], wait=0)
                with self.assertRaisesRegex(RuntimeError, 'Legacy or exclusive'):
                    with second:
                        self.fail('Exclusive preparation/run overlap')
                (root / 'release').touch()
                process.communicate(timeout=3)
                self.assertEqual(process.returncode, 0)

    def test_surviving_orphan_game_keeps_exclusive_guard_for_preparation(self):
        old_root, old_selection, _ = self.config('orphan-runtime', exclusive=True)
        root, selection, _ = self.config('after-orphan')
        admission._directory()
        admission._save({'root': str(old_root), 'phase': 'running', 'ports': [], 'pid': 999999999,
                         'caches': [str(old_root / 'client1')], 'budget': admission.budget(old_selection)})
        self.sample.return_value = snapshot(processes=[{'pid': 55555, 'rss': 0, 'cpu': 0, 'game': True,
            'command': 'java ToolkitSmokeLauncher -cachedir=' + str(old_root / 'client1')}])
        with self.assertRaisesRegex(RuntimeError, 'Exclusive native run still has live game processes'):
            with admission.preparing(root, selection, wait=0):
                self.fail('Preparation bypassed surviving exclusive orphan game')
        self.assertEqual(admission.status()['preparing'], [])
        self.assertEqual(len(admission.status()['running']), 1)
        self.sample.return_value = snapshot()
        with admission.preparing(root, selection, wait=0):
            self.assertEqual(admission.status()['running'], [])

    def test_real_fifo_preparation_then_runtime_then_preparation(self):
        with self.legacy.open('a+') as legacy:
            fcntl.flock(legacy, fcntl.LOCK_EX | fcntl.LOCK_NB)
            processes = []
            for index, phase in enumerate(('prepare', 'run', 'prepare'), 1):
                processes.append(self.start('fifo-' + str(index), phase, True))
                self.until(lambda: len(admission.status()['waiting']) == index)
            waiting = admission.status()['waiting']
            self.assertEqual([row['phase'] for row in waiting], ['preparing', 'running', 'preparing'])
            self.assertEqual([row['position'] for row in waiting], [1, 2, 3])
        for index, (process, root) in enumerate(processes):
            self.until(lambda: (root / 'admitted').exists())
            self.assertTrue(all(not (other / 'admitted').exists() for _, other in processes[index+1:]))
            (root / 'release').touch()
            process.communicate(timeout=3)
            self.assertEqual(process.returncode, 0)
        self.assertEqual(admission.status()['waiting'], [])

    def test_real_owner_death_reconciles_active_and_waiting_preparations(self):
        process, root = self.start('dead-active', exclusive=True)
        self.until(lambda: (root / 'admitted').exists())
        self.assertEqual(len(admission.status()['preparing']), 1)
        ports = admission.allocate_ports(root, {'kind': 'mp'})
        process.kill()
        process.communicate(timeout=3)
        self.assertEqual(admission.status()['preparing'], [])
        self.assertEqual(admission.status()['prepared'][0]['ports'], ports)
        with self.legacy.open('a+') as legacy:
            fcntl.flock(legacy, fcntl.LOCK_EX | fcntl.LOCK_NB)
            first, first_root = self.start('dead-waiter')
            self.until(lambda: len(admission.status()['waiting']) == 1)
            second, second_root = self.start('live-waiter')
            self.until(lambda: len(admission.status()['waiting']) == 2)
            first.kill()
            first.communicate(timeout=3)
            self.until(lambda: len(admission.status()['waiting']) == 1)
            self.assertEqual(admission.status()['waiting'][0]['root'], str(second_root))
        self.until(lambda: (second_root / 'admitted').exists())
        (second_root / 'release').touch()
        second.communicate(timeout=3)
        # Reusing a crashed preparation root must not inherit its old record.
        with admission.preparing(root, {'kind': 'sp'}, wait=0):
            self.assertEqual(len(admission.status()['preparing']), 1)

    def test_wait_cancellation_and_record_write_failure_drop_waiters(self):
        root, selection, _ = self.config('cancel')
        self.sample.return_value = snapshot(available=0)
        def interrupt(_):
            self.assertEqual(admission.status()['waiting'][0]['phase'], 'preparing')
            raise KeyboardInterrupt()
        with patch.object(admission.time, 'sleep', side_effect=interrupt), self.assertRaises(KeyboardInterrupt):
            with admission.preparing(root, selection, wait=10):
                self.fail('Preparation admitted on unavailable host')
        self.assertEqual(admission.status()['waiting'], [])
        self.sample.return_value = snapshot()
        save = admission._save
        def fail(record, directory=None):
            if record.get('phase') == 'preparing':
                raise OSError('preparation record write failed')
            return save(record, directory)
        with patch.object(admission, '_save', side_effect=fail), self.assertRaisesRegex(OSError, 'write failed'):
            with admission.preparing(root, selection, wait=0):
                pass
        self.assertEqual(admission.status()['preparing'], [])
        self.assertFalse(admission.status()['legacy_lock']['busy'])

    def test_invalid_preparation_records_fail_closed_and_missing_locks_do_not_bypass(self):
        admission.status()
        path = self.state / 'preparing' / 'invalid.json'
        path.write_text('{}')
        root, selection, _ = self.config('corrupt')
        with self.assertRaisesRegex(RuntimeError, 'Invalid native preparation record'):
            with admission.preparing(root, selection, wait=0):
                self.fail('Invalid reservation bypassed')
        path.unlink()
        with patch.object(admission, 'fcntl', None), self.assertRaisesRegex(ValueError, 'POSIX file locks'):
            with admission.preparing(root, selection, wait=0):
                self.fail('Missing locking support bypassed')
        for wait in (-1, True, float('nan'), float('inf')):
            with self.subTest(wait=wait), self.assertRaises(ValueError):
                with admission.preparing(root, selection, wait=wait):
                    pass

    def windows_kernel(self, result=0, available=8*GIB):
        kernel = Mock()
        kernel.CreateMutexW.return_value = 123
        kernel.WaitForSingleObject.return_value = result
        def memory(pointer):
            pointer._obj.total = 10*GIB
            pointer._obj.available = available
            return True
        kernel.GlobalMemoryStatusEx.side_effect = memory
        return kernel

    def test_windows_uses_shared_host_mutex_and_releases_on_exception_or_abandoned_owner(self):
        for result in (0, 0x80):
            kernel = self.windows_kernel(result)
            with patch.object(admission, 'fcntl', None), patch.object(admission.os, 'name', 'nt'), \
                    patch('ctypes.WinDLL', return_value=kernel, create=True):
                with self.assertRaisesRegex(ValueError, 'copy failed'):
                    with admission.preparing('unused', {'kind': 'mp', 'clients': 4}, wait=0) as details:
                        self.assertEqual(details['budget']['memory'], GIB)
                        self.assertIn('no FIFO', details['limits'][0])
                        raise ValueError('copy failed')
            kernel.CreateMutexW.assert_called_once_with(None, False, 'Local\\PZToolkitNativeWindowsHost')
            kernel.ReleaseMutex.assert_called_once_with(123)
            kernel.CloseHandle.assert_called_once_with(123)

    def test_windows_timeout_and_low_memory_fail_closed_with_handle_cleanup(self):
        for result, available, message, releases in ((0x102, 8*GIB, 'resource wait expired', 0),
                                                    (0, GIB, 'Insufficient available memory', 1)):
            kernel = self.windows_kernel(result, available)
            with patch.object(admission, 'fcntl', None), patch.object(admission.os, 'name', 'nt'), \
                    patch('ctypes.WinDLL', return_value=kernel, create=True):
                with self.assertRaisesRegex(RuntimeError, message):
                    with admission.preparing('unused', {'kind': 'sp'}, wait=0):
                        self.fail('Unavailable Windows host admitted')
            self.assertEqual(kernel.ReleaseMutex.call_count, releases)
            kernel.CloseHandle.assert_called_once_with(123)


if __name__ == '__main__':
    unittest.main()
