from contextlib import ExitStack
import fcntl
import json
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import admission


GIB = 1024 ** 3
WORKER = '''
import json
from pathlib import Path
import sys, time
sys.path.insert(0, sys.argv[1])
from queue_checks import admission
directory, root = Path(sys.argv[2]), Path(sys.argv[3])
admission.STATE = directory / 'state'
admission.LEGACY_LOCK = directory / 'legacy.lock'
snapshot = json.loads((directory / 'snapshot.json').read_text())
admission.host.sample = lambda: snapshot
admission.shutil.disk_usage = lambda path: type('Disk', (), {'free': 100 * 1024**3})()
selection = {'kind': 'sp', 'clients': 1, 'resources': {'heap_mib': 1, 'native_mib': 1, 'cpu_per_instance': .25}}
(root / 'ready').touch()
deadline = time.monotonic() + 10
while not (directory / 'start').exists():
    if time.monotonic() >= deadline:
        raise RuntimeError('worker start barrier timed out')
    time.sleep(.01)
try:
    if sys.argv[4] == 'ports':
        result = {'ports': admission.allocate_ports(root, selection)}
        (root / 'result.json').write_text(json.dumps(result))
    else:
        with admission.acquire(root, selection, {'roles': {'client1': {'cache': str(root / 'client1')}}}, wait=0):
            (root / 'result.json').write_text(json.dumps({'admitted': True}))
            while not (directory / 'release').exists():
                if time.monotonic() >= deadline:
                    raise RuntimeError('worker release barrier timed out')
                time.sleep(.01)
except Exception as error:
    (root / 'result.json').write_text(json.dumps({'error': str(error)}))
'''


def snapshot(available=8 * GIB, total=10 * GIB, cpus=16, processes=()):
    return {'total_memory': total, 'available_memory': available,
            'cpu_count': cpus, 'processes': list(processes)}


class AdmissionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.state = self.directory / 'state'
        self.legacy = self.directory / 'legacy.lock'
        self.addCleanup(patch.stopall)
        patch.object(admission, 'STATE', self.state).start()
        patch.object(admission, 'LEGACY_LOCK', self.legacy).start()
        self.sample = patch.object(admission.host, 'sample', return_value=snapshot()).start()
        patch.object(admission.shutil, 'disk_usage', return_value=SimpleNamespace(free=100 * GIB)).start()

    def run_config(self, name, kind='sp', ports=None, exclusive=False):
        root = self.directory / name
        root.mkdir()
        roles = ['server', 'client1'] if kind == 'mp' else ['client1']
        selection = {'kind': kind, 'clients': 1, 'ports': ports or [],
                     'resources': {'heap_mib': 1, 'native_mib': 1,
                                   'cpu_per_instance': .25, 'exclusive': exclusive}}
        runtime = {'roles': {role: {'cache': str(root / role)} for role in roles}}
        return root, selection, runtime

    def records(self):
        return [json.loads(path.read_text()) for path in self.state.glob('*.json')]

    def test_disk_reserves_live_peer_space_on_same_filesystem(self):
        first = self.run_config('disk-first')
        second = self.run_config('disk-second')
        with patch.object(admission.shutil, 'disk_usage', return_value=SimpleNamespace(
                free=admission.DISK_MARGIN + admission.DISK_PER_ROLE)):
            with admission.acquire(*first, wait=0):
                with self.assertRaisesRegex(RuntimeError, 'Insufficient disk space'):
                    admission.require_disk(second[0], 1, copy_bytes=128)
                with self.assertRaisesRegex(RuntimeError, 'Insufficient disk space'):
                    with admission.acquire(*second, wait=0):
                        self.fail('Second run used its peer disk reserve')
            with admission.acquire(*second, wait=0) as details:
                self.assertEqual(details['disk']['peer_reserved_bytes'], 0)

    def test_snapshot_disk_check_works_without_native_posix_launch_support(self):
        with patch.object(admission, 'fcntl', None):
            details = admission.require_disk(self.directory / 'future-run', 1, copy_bytes=321)
        self.assertEqual(details['copy_bytes'], 321)
        self.assertFalse(self.state.exists())

    def test_prepare_reconciles_crashed_run_disk_reservation(self):
        old = self.run_config('crashed-run')
        admission._directory()
        admission._save({'root': str(old[0]), 'phase': 'running', 'ports': [], 'pid': 999999999,
                        'caches': [str(old[0] / 'client1')], 'budget': admission.budget(old[1])})
        with patch.object(admission.shutil, 'disk_usage', return_value=SimpleNamespace(
                free=admission.DISK_MARGIN + admission.DISK_PER_ROLE)):
            details = admission.require_disk(self.directory / 'new-run', 1)
        self.assertEqual(details['peer_reserved_bytes'], 0)
        self.assertEqual(self.records(), [])

    def test_disk_reserve_ignores_other_filesystems_and_prepared_ports(self):
        root = self.directory / 'new' / 'nested'
        records = [{'root': '/other-device', 'phase': 'running', 'caches': ['one', 'two']},
                   {'root': '/missing-prepared', 'phase': 'prepared', 'caches': []}]
        real_stat = Path.stat
        def stat(path, *args, **kwargs):
            if str(path) == '/other-device':
                return type('Device', (), {'st_dev': -1})()
            return real_stat(path, *args, **kwargs)
        with patch.object(Path, 'stat', stat):
            permitted, details = admission.disk_capacity(root, 2, records, copy_bytes=123)
        self.assertTrue(permitted)
        self.assertEqual(details['peer_reserved_bytes'], 0)
        self.assertEqual(details['required_bytes'], admission.DISK_MARGIN + 2 * admission.DISK_PER_ROLE + 123)

    def free_ports(self):
        with ExitStack() as stack:
            streams = [stack.enter_context(socket.socket(socket.AF_INET, socket.SOCK_DGRAM)) for _ in range(2)]
            for stream in streams:
                stream.bind(('0.0.0.0', 0))
            return [stream.getsockname()[1] for stream in streams]

    def start_workers(self, count, mode):
        (self.directory / 'snapshot.json').write_text(json.dumps(self.sample.return_value))
        workers = []
        for index in range(count):
            root = self.directory / ('worker-' + str(index))
            root.mkdir()
            process = subprocess.Popen([sys.executable, '-c', WORKER,
                                        str(Path(__file__).resolve().parents[1] / 'tools'),
                                        str(self.directory), str(root), mode],
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            workers.append((process, root))
        self.addCleanup(self.stop_workers, workers)
        self.await_files([root / 'ready' for _, root in workers])
        (self.directory / 'start').touch()
        self.await_files([root / 'result.json' for _, root in workers])
        return workers

    def await_files(self, files):
        deadline = time.monotonic() + 8
        while not all(path.exists() and (path.name == 'ready' or path.stat().st_size) for path in files):
            if time.monotonic() >= deadline:
                self.fail('Timed out waiting for worker files: ' + str(files))
            time.sleep(.01)

    def stop_workers(self, workers):
        (self.directory / 'release').touch()
        for process, _ in workers:
            try:
                process.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate(timeout=3)

    def test_more_than_two_runs_share_ample_budget_and_release_records(self):
        with ExitStack() as stack:
            for index in range(5):
                stack.enter_context(admission.acquire(*self.run_config('run-' + str(index)), wait=0))
            self.assertEqual(5, len(self.records()))
        self.assertEqual([], self.records())

    def test_simultaneous_processes_admit_exactly_one_at_memory_boundary(self):
        self.sample.return_value = snapshot(available=GIB + 2 * admission.MIB)
        workers = self.start_workers(2, 'acquire')
        results = [json.loads((root / 'result.json').read_text()) for _, root in workers]
        self.assertEqual(1, sum(row.get('admitted', False) for row in results), results)
        errors = [row['error'] for row in results if 'error' in row]
        self.assertEqual(1, len(errors), results)
        self.assertRegex(errors[0], 'Insufficient resources|FIFO: waiting behind')

    def test_capacity_does_not_double_count_owned_rss_or_cpu(self):
        record = {'phase': 'running', 'caches': ['/run/client1'],
                  'budget': {'memory': 6 * GIB, 'cpu': 2}}
        processes = [{'pid': 1, 'rss': 4 * GIB, 'cpu': 1, 'game': True,
                      'command': 'java ToolkitSmokeLauncher -cachedir=/run/client1'},
                     {'pid': 2, 'rss': GIB, 'cpu': 1, 'game': False, 'command': 'other'}]
        permitted, details = admission.capacity(snapshot(total=20 * GIB, cpus=8, processes=processes),
                                                 [record], {'memory': 4 * GIB, 'cpu': 5})
        self.assertTrue(permitted)
        self.assertEqual(4 * GIB, details['memory_available'])
        self.assertEqual(5, details['cpu_available'])

    def test_startup_reserves_full_budget_before_game_rss_appears(self):
        record = {'phase': 'running', 'caches': ['/run/client1'],
                  'budget': {'memory': 4 * GIB, 'cpu': 3}}
        permitted, details = admission.capacity(snapshot(available=7 * GIB, cpus=8), [record],
                                                 {'memory': 2 * GIB, 'cpu': 5})
        self.assertTrue(permitted)
        self.assertEqual(2 * GIB, details['memory_available'])
        self.assertEqual(5, details['cpu_available'])
        self.assertFalse(admission.capacity(snapshot(available=7 * GIB, cpus=8), [record],
                                             {'memory': 2 * GIB + 1, 'cpu': 5})[0])

    def test_unregistered_cpu_consumption_can_exhaust_capacity(self):
        self.sample.return_value = snapshot(cpus=1, processes=[
            {'pid': 77, 'rss': 1, 'cpu': .9, 'game': False, 'command': 'compiler'}])
        with self.assertRaisesRegex(RuntimeError, 'Insufficient resources'):
            with admission.acquire(*self.run_config('cpu-busy'), wait=0):
                self.fail('Busy CPU admitted')
        self.assertEqual([], self.records())

    def test_real_busy_udp_endpoint_blocks_without_record(self):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as busy:
            busy.bind(('0.0.0.0', 0))
            port = busy.getsockname()[1]
            with self.assertRaisesRegex(RuntimeError, 'UDP endpoint unavailable'):
                with admission.acquire(*self.run_config('busy-port', 'mp', [port, port + 1]), wait=0):
                    self.fail('Busy UDP endpoint admitted')
        self.assertEqual([], self.records())

    def test_registered_udp_ports_block_even_before_game_binds(self):
        ports = self.free_ports()
        first = self.run_config('first-port', 'mp', ports)
        second = self.run_config('second-port', 'mp', ports)
        with admission.acquire(*first, wait=0):
            with self.assertRaisesRegex(RuntimeError, 'UDP ports reserved'):
                with admission.acquire(*second, wait=0):
                    self.fail('Reserved UDP endpoint admitted')

    def test_concurrent_auto_ports_are_unique_and_persisted(self):
        workers = self.start_workers(4, 'ports')
        results = [json.loads((root / 'result.json').read_text()) for _, root in workers]
        self.assertTrue(all('ports' in row for row in results), results)
        ports = [port for row in results for port in row['ports']]
        self.assertEqual(8, len(set(ports)))
        for row in results:
            self.assertEqual(row['ports'][0] + 1, row['ports'][1])
        self.assertEqual({tuple(row['ports']) for row in results},
                         {tuple(row['ports']) for row in self.records()})

    def test_auto_port_lease_blocks_explicit_claim(self):
        prepared = self.run_config('prepared')[0]
        ports = admission.allocate_ports(prepared, {'kind': 'mp'})
        with self.assertRaisesRegex(RuntimeError, 'UDP ports reserved'):
            with admission.acquire(*self.run_config('explicit', 'mp', ports), wait=0):
                self.fail('Prepared automatic endpoint admitted elsewhere')

    def test_legacy_exclusive_lock_blocks_new_shared_runner(self):
        with self.legacy.open('a+') as legacy:
            fcntl.flock(legacy, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(RuntimeError, 'Legacy or exclusive'):
                with admission.acquire(*self.run_config('legacy-busy'), wait=0):
                    self.fail('Legacy exclusive lock bypassed')

    def test_new_shared_runner_also_blocks_legacy_exclusive_lock(self):
        with admission.acquire(*self.run_config('new-shared'), wait=0):
            with self.legacy.open('a+') as legacy, self.assertRaises(BlockingIOError):
                fcntl.flock(legacy, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_duplicate_root_is_blocked(self):
        config = self.run_config('duplicate')
        with admission.acquire(*config, wait=0):
            with self.assertRaisesRegex(RuntimeError, 'already admitted or waiting'):
                with admission.acquire(*config, wait=0):
                    self.fail('Duplicate profile admitted')

    def test_explicit_exclusive_mode_conflicts_in_both_directions(self):
        for exclusive_first in (False, True):
            with self.subTest(exclusive_first=exclusive_first):
                first = self.run_config('exclusive-first-' + str(exclusive_first), exclusive=exclusive_first)
                second = self.run_config('exclusive-second-' + str(exclusive_first), exclusive=not exclusive_first)
                with admission.acquire(*first, wait=0):
                    with self.assertRaisesRegex(RuntimeError, 'Legacy or exclusive'):
                        with admission.acquire(*second, wait=0):
                            self.fail('Exclusive run overlapped')

    def test_orphan_game_preserves_budget_and_ports_until_it_disappears(self):
        ports = self.free_ports()
        first = self.run_config('orphan', 'mp', ports)
        self.sample.return_value = snapshot(available=GIB + 4 * admission.MIB)
        with admission.acquire(*first, wait=0):
            self.sample.return_value = snapshot(available=GIB + 4 * admission.MIB, processes=[
                {'pid': 999999, 'rss': 0, 'cpu': 0, 'game': True,
                 'command': 'java ToolkitSmokeLauncher -cachedir=' + first[2]['roles']['client1']['cache']}])
        self.assertEqual(1, len(self.records()))
        path = next(self.state.glob('*.json'))
        record = json.loads(path.read_text())
        record['pid'] = 999999999
        path.write_text(json.dumps(record))
        # No owner lease is held now; a surviving owned game must retain its record.
        with self.assertRaisesRegex(RuntimeError, 'UDP ports reserved'):
            with admission.acquire(*self.run_config('orphan-ports', 'mp', ports), wait=0):
                self.fail('Orphan ports released too early')
        with self.assertRaisesRegex(RuntimeError, 'Insufficient resources'):
            with admission.acquire(*self.run_config('orphan-budget'), wait=0):
                self.fail('Orphan budget released too early')
        self.sample.return_value = snapshot(available=GIB + 4 * admission.MIB)
        with admission.acquire(*self.run_config('after-orphan', 'mp', ports), wait=0):
            self.assertEqual(1, len(self.records()))
        self.assertEqual([], self.records())

    def test_owner_death_resamples_before_removing_last_launched_child(self):
        config = self.run_config('crash-window')
        self.sample.side_effect = [snapshot(), RuntimeError('cleanup unavailable')]
        with self.assertRaisesRegex(RuntimeError, 'cleanup unavailable'):
            with admission.acquire(*config, wait=0):
                pass
        live = snapshot(processes=[{'pid': 1, 'rss': 0, 'cpu': 0, 'game': True,
                         'command': 'launchctl asuser 501 java ToolkitSmokeLauncher -cachedir=' + str(config[0] / 'client1')}])
        self.sample.side_effect = [snapshot(), live]
        with admission._locked():
            records = admission._records(self.sample())
        self.assertEqual(len(records), 1)
        self.assertEqual(self.sample.call_count, 4)

    def test_cachedir_with_space_and_dash_keeps_owned_process(self):
        cache = str(self.directory / 'smoke -candidate/client1')
        process = {'pid': 1, 'game': True, 'command': 'java ToolkitSmokeLauncher -cachedir=' + cache}
        self.assertEqual(admission.owned({'caches': [cache]}, {'processes': [process]}), [process])
        process['command'] += ' -useTimeStampedLogFileNames=1 -debugLogFile=server'
        self.assertEqual(admission.owned({'caches': [cache]}, {'processes': [process]}), [process])
        process['command'] = 'java zombie.network.GameServer -coop -cachedir=' + cache + '-foreign -useTimeStampedLogFileNames=1 -debugLogFile=server'
        self.assertEqual(admission.owned({'caches': [cache]}, {'processes': [process]}), [])

    def test_registry_location_does_not_depend_on_tmpdir(self):
        import os
        code = "import sys;sys.path.insert(0,sys.argv[1]);from queue_checks.admission import STATE;print(STATE)"
        paths = [subprocess.check_output([sys.executable, '-c', code, str(Path(__file__).resolve().parents[1] / 'tools')],
                  env=dict(os.environ, TMPDIR=str(self.directory / name)), text=True).strip() for name in ('a', 'b')]
        self.assertEqual(paths[0], paths[1])
        self.assertEqual(Path(paths[0]), Path('/tmp') / ('pz-native-' + str(os.getuid())))

    def test_report_imports_without_posix_launch_support(self):
        code = """
import builtins, os, sys
sys.path.insert(0, sys.argv[1])
original = builtins.__import__
def imports(name, *args, **kwargs):
    if name == 'fcntl':
        raise ImportError('no POSIX locks')
    return original(name, *args, **kwargs)
builtins.__import__ = imports
del os.getuid
from queue_checks import report, native, runner
assert report.matrix({'suites': {}})['rows'] == []
"""
        subprocess.run([sys.executable, '-c', code, str(Path(__file__).resolve().parents[1] / 'tools')], check=True)

    def test_sampler_error_fails_closed_without_admission(self):
        self.sample.side_effect = RuntimeError('Cannot sample host resources: unavailable')
        with self.assertRaisesRegex(RuntimeError, 'Cannot sample host resources'):
            with admission.acquire(*self.run_config('no-sampler'), wait=0):
                self.fail('Unsampled host admitted')
        self.assertEqual([], self.records())

    def test_cleanup_sampling_error_keeps_record_for_reconciliation(self):
        self.sample.side_effect = [snapshot(), RuntimeError('Cannot sample host resources: cleanup')]
        with self.assertRaisesRegex(RuntimeError, 'cleanup'):
            with admission.acquire(*self.run_config('cleanup-sampler'), wait=0):
                pass
        self.assertEqual(1, len(self.records()))

    def test_wait_retries_when_resources_become_available(self):
        self.sample.side_effect = [snapshot(available=0), snapshot(), snapshot()]
        with patch.object(admission.time, 'sleep') as sleep:
            with admission.acquire(*self.run_config('wait'), wait=1):
                self.assertEqual(1, len(self.records()))
        self.assertEqual(1, sleep.call_count)

    def test_waiting_status_and_interrupt_release_locks_but_keep_prepared_ports(self):
        config = self.run_config('interrupted', 'mp')
        config[1]['ports'] = admission.allocate_ports(config[0], config[1])
        self.sample.return_value = snapshot(available=0)

        def interrupt(_):
            value = admission.status()
            self.assertEqual(len(value['waiting']), 1)
            row = value['waiting'][0]
            self.assertEqual((row['root'], row['position']), (str(config[0].resolve()), 1))
            self.assertIn('Insufficient resources', row['reason'])
            self.assertEqual(value['legacy_lock']['busy'], False)
            self.assertEqual(value['prepared'][0]['ports'], config[1]['ports'])
            raise KeyboardInterrupt()

        with patch.object(admission.time, 'sleep', side_effect=interrupt), self.assertRaises(KeyboardInterrupt):
            with admission.acquire(*config, wait=10):
                self.fail('Unavailable host admitted')
        value = admission.status()
        self.assertEqual(value['waiting'], [])
        self.assertEqual(len(value['prepared']), 1)
        self.assertFalse(admission._held(config[0].resolve()))
        self.sample.return_value = snapshot()
        with admission.acquire(*config, wait=0):
            self.assertEqual(admission.status()['waiting'], [])

    def test_timeout_removes_waiter_without_host_sampling_or_lock_leak(self):
        with self.legacy.open('a+') as legacy:
            fcntl.flock(legacy, fcntl.LOCK_EX | fcntl.LOCK_NB)
            config = self.run_config('timeout')
            with self.assertRaisesRegex(RuntimeError, 'resource wait expired'):
                with admission.acquire(*config, wait=0):
                    self.fail('Legacy owner bypassed')
            self.sample.assert_not_called()
            value = admission.status()
            self.assertEqual(value['waiting'], [])
            self.assertEqual(value['running'], [])
            self.assertTrue(value['legacy_lock']['busy'])
            self.assertTrue(value['legacy_lock']['exclusive'])
            self.assertFalse(admission._held(config[0].resolve()))
            # Status probes must neither release nor steal another owner's lock.
            with self.legacy.open('a+') as probe, self.assertRaises(BlockingIOError):
                fcntl.flock(probe, fcntl.LOCK_SH | fcntl.LOCK_NB)

    def test_status_keeps_old_running_schema_and_surviving_orphan_game(self):
        config = self.run_config('old-owner')
        with admission.acquire(*config, wait=0):
            path = next(self.state.glob('*.json'))
            record = json.loads(path.read_text())
            for key in ('suite', 'kind', 'mode', 'cases', 'started_at'):
                record.pop(key)
            path.write_text(json.dumps(record))
            value = admission.status()
            self.assertTrue(value['running'][0]['owner_alive'])
            self.assertTrue(value['legacy_lock']['busy'])
            self.assertFalse(value['legacy_lock']['exclusive'])
            self.sample.return_value = snapshot(processes=[
                {'pid': 88888, 'rss': 0, 'cpu': 0, 'game': True,
                 'command': 'java ToolkitSmokeLauncher -cachedir=' + str(config[0] / 'client1')}])
        value = admission.status()
        self.assertEqual(value['running'][0]['processes'][0]['pid'], 88888)
        self.assertFalse(value['running'][0]['owner_alive'])
        self.assertFalse(value['legacy_lock']['busy'])
        self.sample.return_value = snapshot()
        self.assertEqual(admission.status()['running'], [])

    def test_corrupt_waiter_and_unsafe_waiter_directory_fail_closed(self):
        admission.status()
        path = self.state / 'waiters' / 'bad.json'
        path.write_text('{}')
        with self.assertRaisesRegex(RuntimeError, 'Invalid native admission waiter'):
            admission.status()
        path.unlink()
        path.parent.chmod(0o777)
        with self.assertRaisesRegex(RuntimeError, 'mode 0700'):
            admission.status()

    def test_status_shows_orphan_discovered_after_initial_sample(self):
        config = self.run_config('status-crash-window')
        self.sample.side_effect = [snapshot(), RuntimeError('cleanup unavailable')]
        with self.assertRaisesRegex(RuntimeError, 'cleanup unavailable'):
            with admission.acquire(*config, wait=0):
                pass
        live = snapshot(processes=[{'pid': 98765, 'rss': 0, 'cpu': 0, 'game': True,
            'command': 'java ToolkitSmokeLauncher -cachedir=' + str(config[0] / 'client1')}])
        self.sample.side_effect = [snapshot(), live, live]
        row = admission.status()['running'][0]
        self.assertFalse(row['owner_alive'])
        self.assertEqual([process['pid'] for process in row['processes']], [98765])

    def test_running_record_write_failure_is_reported_and_drops_waiter(self):
        original = admission._save

        def save(record, directory=None):
            if record.get('phase') == 'running':
                raise OSError('record write failed')
            return original(record, directory)

        with patch.object(admission, '_save', side_effect=save), self.assertRaisesRegex(OSError, 'record write failed'):
            with admission.acquire(*self.run_config('write-failed'), wait=10):
                self.fail('Unrecorded profile admitted')
        value = admission.status()
        self.assertEqual(value['waiting'], [])
        self.assertEqual(value['running'], [])
        self.assertFalse(value['legacy_lock']['busy'])

    def test_default_heap_is_reserved_for_every_sp_and_host_process(self):
        for selection, instances in (({'kind': 'sp'}, 1),
                                     ({'kind': 'mp', 'clients': 1, 'options': {'mp_host': True}}, 2),
                                     ({'kind': 'mp', 'clients': 2}, 3)):
            with self.subTest(selection=selection):
                budget = admission.budget(selection)
                self.assertEqual(budget['heap_mib'], 3072)
                self.assertEqual(budget['native_mib'], 1024)
                self.assertEqual(budget['instances'], instances)
                self.assertEqual(budget['memory'], instances * 4 * GIB)
        # Previously prepared snapshots and explicit experiments retain their chosen value.
        old = admission.budget({'kind': 'sp', 'resources': {'heap_mib': 2048}})
        self.assertEqual(old['heap_mib'], 2048)
        self.assertEqual(old['memory'], 3 * GIB)

    def test_invalid_resource_budgets_and_wait_are_rejected(self):
        for resources in ({'heap_mib': 0}, {'heap_mib': True}, {'native_mib': -1},
                          {'native_mib': 1.5}, {'cpu_per_instance': 0},
                          {'cpu_per_instance': float('inf')}, {'cpu_per_instance': float('nan')},
                          {'cpu_per_instance': True}, {'exclusive': 'yes'}, {'unknown': 1}):
            with self.subTest(resources=resources), self.assertRaises(ValueError):
                admission.budget({'kind': 'sp', 'resources': resources})
        config = self.run_config('invalid-wait')
        for wait in (-1, float('inf'), float('nan'), True):
            with self.subTest(wait=wait), self.assertRaises(ValueError):
                with admission.acquire(*config, wait=wait):
                    self.fail('Invalid wait admitted')


if __name__ == '__main__':
    unittest.main()
