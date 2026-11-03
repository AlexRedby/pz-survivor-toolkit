"""Backfill uses real leases and all admission guards, without launching a game."""
from contextlib import contextmanager
from copy import deepcopy
import fcntl
import json
import os
import socket
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from tests import test_queue_admission as fixtures
from queue_checks import admission


class BackfillGuardTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.AdmissionTests(methodName='runTest')
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.fixture.sample.return_value = fixtures.snapshot(available=fixtures.GIB + 4 * admission.MIB)
        self.head = self.fixture.run_config('head')
        self.head[1]['resources']['heap_mib'] = 5

    @contextmanager
    def waiting(self, config=None, *, phase='running', sequence=1, legacy=False, pid=None):
        root, selection, _ = config or self.head
        request = (admission.preparation_budget(selection) if phase == 'preparing' else
                   admission.timing_budget() if phase == 'timing' else admission.budget(selection))
        row = dict(root=str(root), phase=phase, pid=pid or os.getpid(), sequence=sequence,
                   queued_at=1, exclusive=request['exclusive'], kind=selection['kind'], reason='stale reason')
        if not legacy:
            row['scheduling'] = dict(schema_version=1, budget=request, ports=selection.get('ports', []) if phase == 'running' else [],
                                     backfill_count=0)
        admission._directory()
        with (self.fixture.state / (admission._key(root) + '.lease')).open('a+') as lease:
            fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
            path = self.fixture.state / 'waiters' / (admission._key(root) + '.json')
            with admission._locked():
                admission._directory(path.parent)
                admission._save(row, path.parent)
            try:
                yield path
            finally:
                with admission._locked():
                    path.unlink(missing_ok=True)

    def assert_blocked(self, reason, config=None):
        candidate = config or self.fixture.run_config('follower')
        with self.assertRaisesRegex(RuntimeError, reason):
            with admission.acquire(*candidate, wait=0):
                self.fail('FIFO barrier was bypassed')

    def test_legacy_waiter_stays_fifo_without_sampling_or_inventing_a_budget(self):
        with self.waiting(legacy=True):
            self.assert_blocked('legacy waiter; no backfill contract')
            self.fixture.sample.assert_not_called()
            self.assertEqual(0, admission.status()['waiting'][0]['backfill_remaining'])

    def test_reserved_predecessor_ports_preserve_fifo_even_when_memory_is_short(self):
        self.head[1]['ports'] = self.fixture.free_ports()
        other = self.fixture.run_config('reserved')[0]
        admission._directory()
        admission._save(dict(root=str(other), phase='prepared', caches=[], ports=self.head[1]['ports']))
        with self.waiting() as path:
            self.assert_blocked('UDP ports reserved')
            self.assertEqual(0, json.loads(path.read_text())['scheduling']['backfill_count'])

    def test_busy_predecessor_endpoint_is_not_classified_as_only_resource_starved(self):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as busy:
            busy.bind(('0.0.0.0', 0))
            self.head[1]['ports'] = [busy.getsockname()[1]]
            with self.waiting():
                self.assert_blocked('UDP endpoint unavailable')

    def test_predecessor_disk_shortage_is_a_fifo_barrier(self):
        with self.waiting(), patch.object(admission.shutil, 'disk_usage', side_effect=lambda path:
                SimpleNamespace(free=1 if path.resolve() == self.head[0].resolve() else 100 * fixtures.GIB)):
            self.assert_blocked('insufficient disk space')

    def test_external_predecessor_game_without_registry_record_is_a_fifo_barrier(self):
        self.fixture.sample.return_value = fixtures.snapshot(available=fixtures.GIB + 4 * admission.MIB, processes=[
            dict(pid=9999999, game=True, rss=0, cpu=0,
                 command='java ToolkitSmokeLauncher -cachedir=' + str(self.head[0] / 'client1'))])
        with self.waiting():
            self.assert_blocked('existing profile process')

    def test_profile_already_launched_is_a_fifo_barrier(self):
        (self.head[0] / 'execution.json').write_text('{}')
        with self.waiting():
            self.assert_blocked('profile has already launched')

    def test_candidate_endpoint_failure_does_not_charge_predecessor(self):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as busy:
            busy.bind(('0.0.0.0', 0))
            config = self.fixture.run_config('busy-candidate', kind='mp', ports=[busy.getsockname()[1]])
            with self.waiting() as path:
                self.assert_blocked('UDP endpoint unavailable', config)
                self.assertEqual(0, json.loads(path.read_text())['scheduling']['backfill_count'])

    def test_actual_legacy_holder_cannot_be_bypassed(self):
        with self.waiting(), self.fixture.legacy.open('a+') as legacy:
            fcntl.flock(legacy, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assert_blocked('legacy or exclusive resource lease is busy')
            self.fixture.sample.assert_not_called()

    def test_each_intermediate_predecessor_retains_priority_when_it_fits(self):
        second = self.fixture.run_config('second')
        with self.waiting() as first, self.waiting(second, sequence=2) as intermediate:
            self.assert_blocked('resources available; FIFO priority')
            for path in (first, intermediate):
                self.assertEqual(0, json.loads(path.read_text())['scheduling']['backfill_count'])

    def test_preparation_and_timing_priority_uses_the_predecessor_owner_rss(self):
        for phase, rss in [('preparing', admission.PREPARATION_MEMORY), ('timing', admission.timing_budget()['memory'])]:
            with self.subTest(phase=phase):
                self.fixture.sample.return_value = fixtures.snapshot(available=fixtures.GIB + 4 * admission.MIB, processes=[
                    dict(pid=12345, game=False, rss=rss, cpu=1, command='prepared owner')])
                with self.waiting(phase=phase, pid=12345):
                    self.assert_blocked('resources available; FIFO priority', self.fixture.run_config('after-' + phase))

    def test_preparation_and_timing_can_backfill_using_their_own_budget(self):
        self.fixture.sample.return_value = fixtures.snapshot(available=4 * fixtures.GIB)
        self.head[1]['resources']['heap_mib'] = 4096
        with self.waiting() as path:
            for phase in ('preparing', 'timing'):
                root = self.fixture.directory / ('backfill-' + phase)
                root.mkdir()
                context = (admission.preparing(root, {'kind': 'sp'}, wait=0) if phase == 'preparing' else
                           admission.measuring(root, 'backfill-unit', wait=0))
                with context:
                    value = admission.status()
                    self.assertEqual(phase, value[phase][0]['phase'])
                self.assertEqual(1 if phase == 'preparing' else 2, json.loads(path.read_text())['scheduling']['backfill_count'])

    def test_same_live_sample_drives_predecessor_and_candidate_capacity(self):
        low = fixtures.snapshot(available=fixtures.GIB + 4 * admission.MIB)
        recovered = fixtures.snapshot(available=8 * fixtures.GIB)
        self.fixture.sample.side_effect = [low, recovered]  # second sample is cleanup, not a newer admission decision
        with self.waiting() as path:
            with admission.acquire(*self.fixture.run_config('consistent-sample'), wait=0):
                self.assertEqual(1, self.fixture.sample.call_count)
                self.assertEqual(1, json.loads(path.read_text())['scheduling']['backfill_count'])
        self.assertEqual(2, self.fixture.sample.call_count)

    def test_failed_record_publication_conservatively_keeps_charged_slot(self):
        save = admission._save
        def failed(record, directory=None):
            if record.get('phase') == 'running' and 'scheduling' not in record:
                raise OSError('publication failed')
            return save(record, directory)

        with self.waiting() as path, patch.object(admission, '_save', side_effect=failed):
            with self.assertRaisesRegex(OSError, 'publication failed'):
                with admission.acquire(*self.fixture.run_config('failed-publication'), wait=0):
                    self.fail('Unpublished admission escaped')
            value = admission.status()
            self.assertEqual([], value['running'])
            self.assertFalse(value['legacy_lock']['busy'])
            self.assertEqual(1, json.loads(path.read_text())['scheduling']['backfill_count'])

    def test_backfill_sampler_failure_is_closed_without_charging_quota(self):
        with self.waiting() as path:
            self.fixture.sample.side_effect = RuntimeError('sampler failed')
            with self.assertRaisesRegex(RuntimeError, 'sampler failed'):
                with admission.acquire(*self.fixture.run_config('failed-sampling'), wait=0):
                    self.fail('Unsampled admission escaped')
            self.assertEqual(0, json.loads(path.read_text())['scheduling']['backfill_count'])
            self.fixture.sample.side_effect = None
            value = admission.status()
            self.assertFalse(value['legacy_lock']['busy'])
            self.assertEqual([str(self.head[0])], [row['root'] for row in value['waiting']])

    def test_invalid_scheduling_inputs_fail_closed(self):
        with self.waiting() as path:
            original = json.loads(path.read_text())
            variants = [dict(schema_version=True), dict(schema_version=2), dict(backfill_count=-1),
                        dict(backfill_count=4), dict(backfill_count=True), dict(ports=['invalid']), dict(budget={})]
            for change in variants:
                value = deepcopy(original)
                value['scheduling'].update(change)
                path.write_text(json.dumps(value))
                with self.subTest(change=change), self.assertRaisesRegex(RuntimeError, 'Invalid native admission waiter'):
                    admission.status()
            path.write_text(json.dumps(original))


if __name__ == '__main__':
    unittest.main()
