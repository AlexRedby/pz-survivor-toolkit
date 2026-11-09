"""Probe retries retain queue ownership without admitting stale capacity."""
from contextlib import contextmanager
import fcntl
import json
import os
import unittest
from unittest.mock import patch

from tests import test_queue_admission as fixtures
from queue_checks import admission, host


class ProbeRetryTests(unittest.TestCase):
    def setUp(self):
        # Reuse the isolated registry helpers without inheriting its test methods.
        self.fixture = fixtures.AdmissionTests(methodName='runTest')
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.fixture.directory = self.fixture.directory.resolve()
        self.now = 0
        self.sleeps = []
        self.waiters_at_sleep = []
        self.addCleanup(patch.stopall)
        patch.object(admission.time, 'monotonic', side_effect=lambda: self.now).start()
        self.sleep = patch.object(admission.time, 'sleep', side_effect=self.advance).start()
        self.updates = patch.object(admission.progress, 'Phase').start().return_value

    def advance(self, seconds):
        self.sleeps.append(seconds)
        self.waiters_at_sleep.append(self.waiters())
        # A retry must release the lifetime compatibility lock before sleeping.
        with self.fixture.legacy.open('a+') as stream:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        self.now += seconds

    def waiters(self):
        return [json.loads(path.read_text()) for path in (self.fixture.state / 'waiters').glob('*.json')]

    def assert_released(self, root):
        self.assertEqual([], self.waiters())
        self.assertFalse(admission._held(root))
        with self.fixture.legacy.open('a+') as stream:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)

    @contextmanager
    def predecessor(self, config):
        root, selection, _ = config
        row = dict(root=str(root), phase='running', pid=os.getpid(), sequence=1,
                   queued_at=1, exclusive=False, kind=selection['kind'], reason='old diagnostic',
                   resource_request=dict(schema_version=1, budget=admission.budget(selection), ports=[]))
        admission._directory()
        with (self.fixture.state / (admission._key(root) + '.lease')).open('a+') as lease:
            fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
            directory = self.fixture.state / 'waiters'
            admission._directory(directory)
            admission._save(row, directory)
            path = directory / (admission._key(root) + '.json')
            try:
                yield path
            finally:
                path.unlink(missing_ok=True)

    def test_timeout_recovery_retains_waiter_and_uses_fresh_capacity(self):
        config = self.fixture.run_config('recovery')
        observed = []

        def sample():
            if len(observed) < 2:
                observed.append(self.waiters()[0])
                if len(observed) == 1:
                    raise host.ProbeTimeout('temporary ps timeout')
            return fixtures.snapshot(available=6 * fixtures.GIB, cpus=12)

        self.fixture.sample.side_effect = sample
        with admission.acquire(*config, wait=10) as details:
            self.assertEqual(5 * fixtures.GIB, details['memory_available'])
            self.assertEqual(12, details['cpu_available'])
            self.assertEqual(1, len(self.fixture.records()))
        self.assertEqual(1, len(self.sleeps))
        for key in ('root', 'pid', 'sequence', 'queued_at', 'resource_request'):
            self.assertEqual(observed[0][key], observed[1][key])
        self.assert_released(config[0])
        self.assertEqual([], self.fixture.records())

    def test_repeated_timeouts_expire_at_original_deadline(self):
        config = self.fixture.run_config('expired')
        self.fixture.sample.side_effect = host.ProbeTimeout('ps timeout')
        with self.assertRaisesRegex(RuntimeError, 'ps timeout.*resource wait expired'):
            with admission.acquire(*config, wait=5):
                self.fail('Unknown capacity admitted')
        self.assertEqual(5, self.now)
        self.assertEqual([2, 2, 1], self.sleeps)
        self.assertEqual(3, self.fixture.sample.call_count)
        identities = [(rows[0]['sequence'], rows[0]['queued_at']) for rows in self.waiters_at_sleep]
        self.assertEqual(1, len(set(identities)))
        self.assert_released(config[0])
        self.assertEqual([], self.fixture.records())

    def test_successful_probe_finishing_after_deadline_cannot_admit(self):
        config = self.fixture.run_config('late-capacity')

        def late_sample():
            self.now += 6
            return fixtures.snapshot()

        self.fixture.sample.side_effect = late_sample
        with self.assertRaisesRegex(RuntimeError, 'resource wait expired'):
            with admission.acquire(*config, wait=5):
                self.fail('Late capacity admitted')
        self.assertEqual(1, self.fixture.sample.call_count)
        self.sleep.assert_not_called()
        self.assert_released(config[0])
        self.assertEqual([], self.fixture.records())

    def test_probe_timeout_itself_can_consume_the_remaining_wait(self):
        config = self.fixture.run_config('slow-timeout')

        def slow_probe():
            self.now += 10
            raise host.ProbeTimeout('slow ps timeout')

        self.fixture.sample.side_effect = slow_probe
        with self.assertRaisesRegex(RuntimeError, 'slow ps timeout.*resource wait expired'):
            with admission.acquire(*config, wait=5):
                self.fail('Expired request admitted')
        self.assertEqual(1, self.fixture.sample.call_count)
        self.sleep.assert_not_called()
        self.assert_released(config[0])

    def test_zero_wait_timeout_is_one_attempt_without_sleep(self):
        config = self.fixture.run_config('no-wait')
        self.fixture.sample.side_effect = host.ProbeTimeout('ps timeout')
        with self.assertRaisesRegex(RuntimeError, 'ps timeout'):
            with admission.acquire(*config, wait=0):
                self.fail('Unknown capacity admitted')
        self.assertEqual(1, self.fixture.sample.call_count)
        self.sleep.assert_not_called()
        self.assert_released(config[0])

    def test_permanent_probe_error_is_immediate_even_with_wait_budget(self):
        config = self.fixture.run_config('permission')
        error = RuntimeError('Cannot sample host resources: permission denied')
        self.fixture.sample.side_effect = error
        with self.assertRaises(RuntimeError) as raised:
            with admission.acquire(*config, wait=10):
                self.fail('Permission failure admitted')
        self.assertIs(error, raised.exception)
        self.assertEqual(1, self.fixture.sample.call_count)
        self.sleep.assert_not_called()
        self.assert_released(config[0])

    def test_timeout_from_admitted_body_propagates_without_repeating_work(self):
        config = self.fixture.run_config('body-timeout')
        error = host.ProbeTimeout('body owns its own probe')
        launches = []
        with self.assertRaises(host.ProbeTimeout) as raised:
            with admission.acquire(*config, wait=10):
                launches.append('entered')
                raise error
        self.assertIs(error, raised.exception)
        self.assertEqual(['entered'], launches)
        self.assertEqual(2, self.fixture.sample.call_count)  # admission and release reconciliation
        self.sleep.assert_not_called()
        self.assert_released(config[0])
        self.assertEqual([], self.fixture.records())

    def test_cleanup_timeout_propagates_and_keeps_record_for_reconciliation(self):
        config = self.fixture.run_config('cleanup-timeout')
        error = host.ProbeTimeout('release inventory unavailable')
        self.fixture.sample.side_effect = [fixtures.snapshot(), error]
        with self.assertRaises(host.ProbeTimeout) as raised:
            with admission.acquire(*config, wait=10):
                pass
        self.assertIs(error, raised.exception)
        self.assertEqual(2, self.fixture.sample.call_count)
        self.sleep.assert_not_called()
        self.assert_released(config[0])
        self.assertEqual([str(config[0])], [row['root'] for row in self.fixture.records()])

    def test_timeout_clears_previous_capacity_diagnostics_before_recovery(self):
        config = self.fixture.run_config('mixed')
        self.fixture.sample.side_effect = [fixtures.snapshot(available=0),
            host.ProbeTimeout('temporary inventory timeout'), fixtures.snapshot(), fixtures.snapshot()]
        with admission.acquire(*config, wait=10):
            pass
        reasons = [call.kwargs for call in self.updates.update.call_args_list if 'reason' in call.kwargs]
        self.assertIn('Insufficient resources', reasons[0]['reason'])
        self.assertIsNotNone(reasons[0]['available_memory_gib'])
        retry = next(row for row in reasons if 'temporary inventory timeout' in row['reason'])
        self.assertIsNone(retry['available_memory_gib'])
        self.assertIsNone(retry['available_cpu'])
        self.assertNotIn('Insufficient resources', retry['reason'])
        self.assertIsNone(reasons[-1]['reason'])
        self.assertIsNotNone(reasons[-1]['available_memory_gib'])
        self.assertIsNotNone(reasons[-1]['available_cpu'])
        self.assertEqual(2, len(self.sleeps))
        self.assert_released(config[0])

    def test_cancellation_in_probe_or_retry_sleep_preserves_reservations(self):
        for location in ('probe', 'sleep'):
            with self.subTest(location=location):
                config = self.fixture.run_config('cancel-' + location, kind='mp')
                self.fixture.sample.side_effect = None
                config[1]['ports'] = admission.allocate_ports(config[0], config[1])
                prepared = next(row for row in self.fixture.records() if row['root'] == str(config[0]))
                orphan = self.fixture.run_config('orphan-' + location)
                admission._save(dict(root=str(orphan[0]), phase='running', ports=[], pid=999999999,
                    caches=[str(orphan[0] / 'client1')], budget=admission.budget(orphan[1])))
                original = self.fixture.records()
                interrupt = KeyboardInterrupt()
                self.fixture.sample.side_effect = (interrupt if location == 'probe' else
                                                   host.ProbeTimeout('temporary ps timeout'))

                def cancel_sleep(seconds):
                    self.advance(seconds)
                    self.assertIn('temporary ps timeout', next(
                        row['reason'] for row in self.waiters() if row['root'] == str(config[0])))
                    raise interrupt

                self.sleep.side_effect = cancel_sleep
                with self.assertRaises(KeyboardInterrupt) as raised:
                    with admission.acquire(*config, wait=10):
                        self.fail('Cancelled request admitted')
                self.assertIs(interrupt, raised.exception)
                self.updates.finish.assert_any_call('cancelled')
                self.assert_released(config[0])
                self.assertCountEqual(original, self.fixture.records())
                self.assertIn(prepared, self.fixture.records())

    def test_backfill_probe_timeout_rechecks_newly_ready_predecessor(self):
        head = self.fixture.run_config('head')
        head[1]['resources']['heap_mib'] = 4096
        follower = self.fixture.run_config('follower')
        self.fixture.sample.side_effect = [host.ProbeTimeout('backfill timeout')]

        def recover(seconds):
            self.advance(seconds)
            self.fixture.sample.side_effect = None
            self.fixture.sample.return_value = fixtures.snapshot()

        self.sleep.side_effect = recover
        with self.predecessor(head) as path:
            original = path.read_bytes()
            with self.assertRaisesRegex(RuntimeError, 'resources available; FIFO priority'):
                with admission.acquire(*follower, wait=5):
                    self.fail('Follower bypassed ready older waiter')
            self.assertEqual(original, path.read_bytes())
            self.assertEqual([str(head[0])], [row['root'] for row in self.waiters()])
        self.assert_released(follower[0])
        self.assertEqual([], self.fixture.records())

    def test_owner_death_resample_timeout_retries_without_removing_orphan(self):
        orphan = self.fixture.run_config('last-child')
        admission._directory()
        admission._save(dict(root=str(orphan[0]), phase='running', ports=[], pid=999999999,
            caches=[str(orphan[0] / 'client1')], budget=admission.budget(orphan[1])))
        live = fixtures.snapshot(processes=[dict(pid=999999, rss=0, cpu=0, game=True,
            command='java ToolkitSmokeLauncher -cachedir=' + str(orphan[0] / 'client1'))])
        self.fixture.sample.side_effect = [fixtures.snapshot(), host.ProbeTimeout('owner-death timeout'), live, live]
        candidate = self.fixture.run_config('after-resample')
        with admission.acquire(*candidate, wait=10):
            self.assertEqual(2, len(self.fixture.records()))
        self.assertEqual([str(orphan[0])], [row['root'] for row in self.fixture.records()])
        self.assertEqual(1, len(self.sleeps))
        self.assert_released(candidate[0])

    def test_preparation_and_measurement_share_probe_retry_contract(self):
        for phase in ('preparing', 'timing'):
            with self.subTest(phase=phase):
                config = self.fixture.run_config('shared-' + phase)
                self.fixture.sample.side_effect = [host.ProbeTimeout(phase + ' timeout'), fixtures.snapshot()]
                self.sleep.side_effect = self.advance
                context = (admission.preparing(config[0], config[1], wait=5) if phase == 'preparing' else
                    admission.measuring(config[0], 'probe-retry', wait=5, heap_mib=1, native_mib=1, cpu=1))
                with context:
                    records = list((self.fixture.state / phase).glob('*.json'))
                    self.assertEqual(1, len(records))
                    self.assertEqual(phase, json.loads(records[0].read_text())['phase'])
                self.assertEqual([], list((self.fixture.state / phase).glob('*.json')))
                self.assert_released(config[0])


if __name__ == '__main__':
    unittest.main()
