"""FIFO integration checks use isolated workers and never launch a game."""
import json
from pathlib import Path
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
admission.host.sample = lambda: json.loads((directory / 'snapshot.json').read_text())
admission.shutil.disk_usage = lambda path: type('Disk', (), {'free': 100 * 1024**3})()
sleep = time.sleep
def poll(seconds):
    while (root / 'pause-poll').exists():
        (root / 'poll-paused').touch()
        sleep(.01)
    sleep(min(.02, seconds))
admission.time.sleep = poll
selection = json.loads(sys.argv[4])
runtime = {'roles': {'client1': {'cache': str(root / 'client1')}}}
deadline = time.monotonic() + 20
try:
    with admission.acquire(root, selection, runtime, wait=15):
        (root / 'admitted').touch()
        while not (root / 'release').exists():
            if time.monotonic() >= deadline:
                raise RuntimeError('worker release barrier timed out')
            sleep(.01)
except Exception as error:
    (root / 'error').write_text(str(error))
    raise
'''


class FifoTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name).resolve()
        self.workers = []
        self.addCleanup(self.stop_workers)
        self.addCleanup(patch.stopall)
        patch.object(admission, 'STATE', self.directory / 'state').start()
        patch.object(admission, 'LEGACY_LOCK', self.directory / 'legacy.lock').start()
        patch.object(admission.host, 'sample', side_effect=self.sample).start()
        patch.object(admission.shutil, 'disk_usage', return_value=SimpleNamespace(free=100 * GIB)).start()
        self.set_memory(8 * GIB)

    def sample(self):
        return json.loads((self.directory / 'snapshot.json').read_text())

    def set_memory(self, available, cpus=16):
        temporary = self.directory / 'snapshot.tmp'
        temporary.write_text(json.dumps({'total_memory': 10 * GIB, 'available_memory': available,
                                         'cpu_count': cpus, 'processes': []}))
        temporary.replace(self.directory / 'snapshot.json')

    def start_worker(self, name, exclusive=False, heap_mib=1, cpu=.25, paused=False):
        root = self.directory / name
        root.mkdir(exist_ok=True)
        for marker in ('admitted', 'release', 'error', 'poll-paused', 'pause-poll'):
            (root / marker).unlink(missing_ok=True)
        if paused:
            (root / 'pause-poll').touch()
        selection = {'kind': 'sp', 'clients': 1,
                     'resources': {'heap_mib': heap_mib, 'native_mib': 1,
                                   'cpu_per_instance': cpu, 'exclusive': exclusive}}
        process = subprocess.Popen([sys.executable, '-c', WORKER,
                                    str(Path(__file__).resolve().parents[1] / 'tools'),
                                    str(self.directory), str(root), json.dumps(selection)],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.workers.append((process, root))
        return process, root

    def until(self, predicate, message):
        deadline = time.monotonic() + 8
        while True:
            for process, root in self.workers:
                if (root / 'error').exists():
                    self.fail('Worker failed: ' + (root / 'error').read_text())
            value = predicate()
            if value:
                return value
            if time.monotonic() >= deadline:
                self.fail(message)
            time.sleep(.01)

    def waiting(self, roots):
        expected = [str(root) for root in roots]
        return self.until(lambda: [row['root'] for row in admission.status()['waiting']] == expected,
                          'Expected FIFO waiters: ' + str(expected))

    def admitted(self, root):
        self.until(lambda: (root / 'admitted').exists(), 'Worker was not admitted: ' + str(root))

    def waiter(self, root):
        return next(row for row in admission.status()['waiting'] if row['root'] == str(root))

    def reason(self, root, prefix):
        self.until(lambda: self.waiter(root)['reason'].startswith(prefix),
                   'Waiter did not report ' + prefix + ': ' + str(root))

    def backfills(self, root):
        return self.waiter(root)['scheduling']['backfill_count']

    def release(self, worker):
        process, root = worker
        (root / 'release').touch()
        stdout, stderr = process.communicate(timeout=4)
        self.assertEqual(process.returncode, 0, stdout + stderr)

    def stop_workers(self):
        for _, root in self.workers:
            (root / 'release').touch()
            (root / 'pause-poll').unlink(missing_ok=True)
        for process, _ in self.workers:
            if process.poll() is None:
                process.kill()
            process.communicate(timeout=4)

    def test_exclusive_head_cannot_be_overtaken_or_blocked_by_new_shared_waiter(self):
        holder = self.start_worker('holder')
        self.admitted(holder[1])
        exclusive = self.start_worker('exclusive', exclusive=True)
        self.waiting([exclusive[1]])
        later = self.start_worker('later-shared')
        self.waiting([exclusive[1], later[1]])
        self.assertFalse((later[1] / 'admitted').exists())

        self.release(holder)
        self.admitted(exclusive[1])
        self.waiting([later[1]])
        self.assertFalse((later[1] / 'admitted').exists())
        self.release(exclusive)
        self.admitted(later[1])
        self.release(later)
        self.assertEqual(admission.status()['waiting'], [])

    def test_killed_waiting_head_allows_next_shared_run_to_join_holder(self):
        holder = self.start_worker('holder')
        self.admitted(holder[1])
        head = self.start_worker('head', exclusive=True)
        self.waiting([head[1]])
        later = self.start_worker('later')
        self.waiting([head[1], later[1]])

        head[0].kill()
        head[0].communicate(timeout=4)
        self.admitted(later[1])
        status = admission.status()
        self.assertEqual({row['root'] for row in status['running']}, {str(holder[1]), str(later[1])})
        self.assertEqual(status['waiting'], [])
        self.release(later)
        self.release(holder)

    def test_smaller_request_backfills_memory_or_cpu_starved_predecessor(self):
        for resource, exclusive in [('memory', False), ('cpu', False), ('memory', True)]:
            with self.subTest(resource=resource, exclusive=exclusive):
                name = resource + str(exclusive)
                self.set_memory(GIB + 4 * admission.MIB if resource == 'memory' else 8 * GIB,
                                cpus=1 if resource == 'cpu' else 16)
                large = self.start_worker(name + '-large', exclusive=exclusive,
                                          heap_mib=5 if resource == 'memory' else 1,
                                          cpu=2 if resource == 'cpu' else .25)
                self.waiting([large[1]])
                small = self.start_worker(name + '-small')
                self.admitted(small[1])
                self.assertFalse((large[1] / 'admitted').exists())
                self.assertEqual(self.backfills(large[1]), 1)
                self.release(small)
                self.set_memory(GIB + 6 * admission.MIB if resource == 'memory' else 8 * GIB,
                                cpus=2 if resource == 'cpu' else 16)
                self.admitted(large[1])
                self.release(large)

    def test_three_successful_backfills_exhaust_waiter_lifetime_allowance(self):
        self.set_memory(GIB + 4 * admission.MIB)
        large = self.start_worker('bounded-large', heap_mib=7)
        self.waiting([large[1]])
        for count in range(1, 4):
            small = self.start_worker('bounded-small-' + str(count))
            self.admitted(small[1])
            self.assertEqual(self.backfills(large[1]), count)
            # Let the predecessor update its own resource reason while this
            # reservation exists, then again after it disappears.
            self.until(lambda: '%.2f CPU' % (16 - .25) in self.waiter(large[1])['reason'],
                       'Predecessor did not refresh resource availability')
            self.release(small)
            self.until(lambda: '16.00 CPU' in self.waiter(large[1])['reason'],
                       'Predecessor did not refresh released resources')
            self.assertEqual(self.backfills(large[1]), count)
        fourth = self.start_worker('bounded-fourth')
        self.waiting([large[1], fourth[1]])
        self.reason(fourth[1], 'FIFO:')
        self.assertFalse((fourth[1] / 'admitted').exists())
        self.assertEqual(self.backfills(large[1]), 3)
        self.set_memory(GIB + 8 * admission.MIB)
        self.admitted(large[1])
        self.assertFalse((fourth[1] / 'admitted').exists())
        self.release(large)
        self.admitted(fourth[1])
        self.release(fourth)

    def test_unsatisfied_follower_does_not_spend_backfill_allowance(self):
        self.set_memory(GIB + 4 * admission.MIB)
        large = self.start_worker('unsatisfied-head', heap_mib=5)
        self.waiting([large[1]])
        denied = self.start_worker('unsatisfied-follower', heap_mib=7)
        self.waiting([large[1], denied[1]])
        self.reason(denied[1], 'Insufficient resources:')
        self.assertEqual(self.backfills(large[1]), 0)
        denied[0].kill()
        denied[0].communicate(timeout=4)
        self.waiting([large[1]])
        small = self.start_worker('after-unsatisfied')
        self.admitted(small[1])
        self.assertEqual(self.backfills(large[1]), 1)
        self.release(small)
        self.set_memory(GIB + 6 * admission.MIB)
        self.admitted(large[1])
        self.release(large)

    def test_fresh_capacity_recovery_preserves_predecessor_priority(self):
        self.set_memory(GIB + 4 * admission.MIB)
        large = self.start_worker('recovered-head', heap_mib=5, paused=True)
        self.waiting([large[1]])
        self.until(lambda: (large[1] / 'poll-paused').exists(), 'Head did not pause between checks')
        self.set_memory(GIB + 6 * admission.MIB)
        small = self.start_worker('after-recovery')
        self.waiting([large[1], small[1]])
        self.reason(small[1], 'FIFO:')
        self.assertFalse((small[1] / 'admitted').exists())
        self.assertEqual(self.backfills(large[1]), 0)
        (large[1] / 'pause-poll').unlink()
        self.admitted(large[1])
        self.assertFalse((small[1] / 'admitted').exists())
        self.release(large)
        self.admitted(small[1])
        self.release(small)

    def test_successful_backfill_counts_each_resource_starved_predecessor(self):
        self.set_memory(GIB + 4 * admission.MIB)
        first = self.start_worker('multiple-first', heap_mib=5)
        self.waiting([first[1]])
        second = self.start_worker('multiple-second', heap_mib=7)
        self.waiting([first[1], second[1]])
        small = self.start_worker('multiple-small')
        self.admitted(small[1])
        self.assertEqual([self.backfills(worker[1]) for worker in (first, second)], [1, 1])
        self.release(small)
        self.set_memory(GIB + 6 * admission.MIB)
        self.admitted(first[1])
        self.assertFalse((second[1] / 'admitted').exists())
        self.release(first)
        self.set_memory(GIB + 8 * admission.MIB)
        self.admitted(second[1])
        self.release(second)

    def test_restarted_root_joins_after_existing_waiter(self):
        self.set_memory(GIB + 4 * admission.MIB)
        old = self.start_worker('restarted', heap_mib=5)
        self.waiting([old[1]])
        other = self.start_worker('other', heap_mib=5)
        self.waiting([old[1], other[1]])
        old[0].kill()
        old[0].communicate(timeout=4)

        restarted = self.start_worker('restarted', heap_mib=5)
        # Observe the new lease before status can prune the old record itself.
        self.until(lambda: admission._held(str(restarted[1])), 'Restarted worker did not take its lease')
        self.waiting([other[1], restarted[1]])
        self.set_memory(GIB + 6 * admission.MIB)
        self.admitted(other[1])
        self.waiting([restarted[1]])
        self.assertFalse((restarted[1] / 'admitted').exists())
        self.release(other)
        self.admitted(restarted[1])
        self.release(restarted)


if __name__ == '__main__':
    unittest.main()
