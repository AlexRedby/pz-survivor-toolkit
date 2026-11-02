"""Inherited preparation leases remain held by real compiler-like workers."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import admission, preparation_process as processes

CHILD = """
import os, sys, time
from pathlib import Path
directory = Path(sys.argv[1])
(directory / 'child.pid').write_text(str(os.getpid()))
deadline = time.monotonic() + 15
while not (directory / 'release').exists():
    if time.monotonic() > deadline:
        raise RuntimeError('child release timed out')
    time.sleep(.01)
(directory / 'finished').touch()
"""

OWNER = """
import json, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from queue_checks import admission, preparation_process
directory = Path(sys.argv[2])
admission.STATE = directory / 'state'
admission.LEGACY_LOCK = directory / 'legacy.lock'
admission.host.sample = lambda: json.loads((directory / 'host.json').read_text())
admission.shutil.disk_usage = lambda path: type('Disk', (), {'free': 100 * 1024**3})()
selection = {'kind': 'sp', 'resources': {'exclusive': sys.argv[3] == 'exclusive'}}
with admission.preparing(directory / 'owner', selection, wait=0):
    preparation_process.run([sys.executable, '-c', sys.argv[4], str(directory)], check=True)
"""


@unittest.skipIf(admission.fcntl is None, 'POSIX inherited file locks required')
class PreparationProcessTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        snapshot = dict(total_memory=16 * 1024**3, available_memory=12 * 1024**3,
                        cpu_count=8, processes=[])
        (self.root / 'host.json').write_text(json.dumps(snapshot))
        for context in (patch.object(admission, 'STATE', self.root / 'state'),
                        patch.object(admission, 'LEGACY_LOCK', self.root / 'legacy.lock'),
                        patch.object(admission.host, 'sample', return_value=snapshot),
                        patch.object(admission.shutil, 'disk_usage', return_value=SimpleNamespace(free=100 * 1024**3))):
            context.start()
            self.addCleanup(context.stop)

    def until(self, predicate):
        deadline = time.monotonic() + 10
        while not predicate():
            if time.monotonic() >= deadline:
                self.fail('worker barrier timed out')
            time.sleep(.01)

    def owner(self, exclusive):
        owner = subprocess.Popen([sys.executable, '-c', OWNER, str(ROOT / 'tools'), str(self.root),
                                  'exclusive' if exclusive else 'shared', CHILD],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        def cleanup():
            (self.root / 'release').touch()
            if owner.poll() is None:
                owner.kill()
            owner.communicate(timeout=20)
        self.addCleanup(cleanup)
        self.until(lambda: (self.root / 'child.pid').exists())
        return owner

    def test_owner_sigkill_keeps_child_lease_and_both_exclusive_guards(self):
        for exclusive in (False, True):
            with self.subTest(exclusive=exclusive):
                for name in ('child.pid', 'release', 'finished'):
                    (self.root / name).unlink(missing_ok=True)
                owner = self.owner(exclusive)
                owner.kill()
                owner.wait(timeout=5)
                status = admission.status()
                self.assertEqual([str(self.root / 'owner')], [row['root'] for row in status['preparing']])
                self.assertIs(status['preparing'][0]['owner_alive'], False)
                self.assertTrue(status['legacy_lock']['busy'])
                # A legacy caller must also wait, without knowing the new record schema.
                with admission.LEGACY_LOCK.open('a+') as legacy:
                    with self.assertRaises(BlockingIOError):
                        admission.fcntl.flock(legacy, admission.fcntl.LOCK_EX | admission.fcntl.LOCK_NB)
                selection = {'kind': 'sp', 'resources': {'exclusive': not exclusive}}
                with self.assertRaisesRegex(RuntimeError, 'exclusive'):
                    with admission.preparing(self.root / 'next', selection, wait=0):
                        self.fail('Worker was still using its preparation lease')
                (self.root / 'release').touch()
                self.until(lambda: (self.root / 'finished').exists())
                self.until(lambda: not admission.status()['preparing'])
                with admission.preparing(self.root / 'next', selection, wait=0):
                    pass
                self.assertEqual(admission.status()['preparing'], [])

    def test_context_cleanup_retains_a_worker_that_inherited_the_descriptors(self):
        worker = None
        with self.assertRaisesRegex(RuntimeError, 'preparation failed'):
            with admission.preparing(self.root / 'owner', {'kind': 'sp'}, wait=0):
                # Model an exception escaping a custom worker launcher. The normal
                # run wrapper waits/reaps; admission must still preserve held locks.
                with patch.object(processes.subprocess, 'run') as launch:
                    processes.run(['unused'])
                    descriptors = launch.call_args.kwargs['pass_fds']
                worker = subprocess.Popen([sys.executable, '-c', CHILD, str(self.root)],
                                          pass_fds=descriptors)
                self.addCleanup(worker.wait, timeout=20)
                self.addCleanup((self.root / 'release').touch)
                self.until(lambda: (self.root / 'child.pid').exists())
                raise RuntimeError('preparation failed')
        self.assertEqual(len(admission.status()['preparing']), 1)
        with self.assertRaisesRegex(RuntimeError, 'exclusive'):
            with admission.preparing(self.root / 'next', {'kind': 'sp', 'resources': {'exclusive': True}}, wait=0):
                pass
        (self.root / 'release').touch()
        worker.wait(timeout=10)
        self.assertEqual(admission.status()['preparing'], [])

    def test_wrapper_outputs_failures_timeouts_and_descriptor_scope(self):
        with admission.preparing(self.root / 'owner', {'kind': 'sp'}, wait=0):
            result = processes.run([sys.executable, '-c', 'print(input().upper())'],
                                   input='hello', capture_output=True, text=True, check=True)
            self.assertEqual(result.stdout, 'HELLO\n')
            self.assertEqual(processes.check_output([sys.executable, '-c', 'print("ok")'], text=True), 'ok\n')
            with self.assertRaises(subprocess.CalledProcessError) as failure:
                processes.run([sys.executable, '-c', 'import sys; print("bad"); sys.exit(7)'],
                              capture_output=True, text=True, check=True)
            self.assertEqual((failure.exception.returncode, failure.exception.stdout), (7, 'bad\n'))
            with self.assertRaises(subprocess.TimeoutExpired):
                processes.run([sys.executable, '-c', 'import time; time.sleep(10)'], timeout=.1)
            with patch.object(processes.subprocess, 'run') as launch:
                processes.run(['unused'], pass_fds=(1,))
                self.assertEqual(len(launch.call_args.kwargs['pass_fds']), 3)
        self.assertEqual(admission.status()['preparing'], [])
        with patch.object(processes.subprocess, 'run') as launch:
            processes.run(['outside'])
            self.assertNotIn('pass_fds', launch.call_args.kwargs)


if __name__ == '__main__':
    unittest.main()
