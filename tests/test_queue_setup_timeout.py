"""Deterministic phase budgets: paused/stalled setup cannot consume gameplay time."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.preflight import ClientPreflight, PREFIX, RELEASE, setup_timeout


class SetupTimeoutTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.now = 0
        self.roles, self.token = ['client1', 'client2'], 'a' * 32
        self.selection = dict(kind='mp', clients=2, options={'fixture_setup_timeout_seconds': 5})
        self.runtime = dict(fixture={'preflight': dict(version=2, token=self.token, roles=self.roles,
                            setup_timeout_seconds=5)}, roles={role: {'cache': str(self.root / role)} for role in self.roles})
        for role in self.roles:
            (self.root / role / 'Lua').mkdir(parents=True)
        self.monitor = ClientPreflight(self.root, self.runtime, self.selection, clock=lambda: self.now)
        self.monitor.begin(10)
        self.logs, self.execution = {role: '' for role in self.roles}, {}

    def receipt(self, role, event, **fields):
        self.logs[role] += PREFIX + json.dumps(dict(event=event, token=self.token, role=role, **fields)) + '\n'

    def ready(self):
        for role in self.roles:
            self.receipt(role, 'ready')
        self.monitor.check(self.logs, self.execution)

    def assert_no_gameplay_grants(self):
        for role in self.roles:
            self.assertFalse((self.root / role / 'Lua' / RELEASE).exists())

    def test_setup_bound_has_a_positive_integer_default_and_cannot_be_disabled(self):
        self.assertEqual(120, setup_timeout({}))
        self.assertEqual(600, setup_timeout({'options': {'fixture_setup_timeout_seconds': 600}}))
        for value in (None, False, True, 0, -1, 1.5, '120', [], {}):
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, 'positive integer'):
                setup_timeout({'options': {'fixture_setup_timeout_seconds': value}})

    def test_launch_refuses_missing_old_or_mismatched_frozen_setup_bound(self):
        for patch in ({'version': 1}, {'setup_timeout_seconds': None}, {'setup_timeout_seconds': 6},
                      {'setup_timeout_seconds': True}):
            runtime = copy.deepcopy(self.runtime)
            runtime['fixture']['preflight'].update(patch)
            with self.subTest(patch=patch), self.assertRaisesRegex(ValueError, 'fresh snapshot'):
                ClientPreflight(self.root, runtime, self.selection)

    def test_no_coordinator_ticks_after_grant_expires_without_running_gameplay(self):
        self.ready()
        self.now = 4.9
        self.assertFalse(self.monitor.check(self.logs, self.execution))
        self.now = 5
        with self.assertRaisesRegex(RuntimeError, 'Fixture setup deadline expired'):
            self.monitor.check(self.logs, self.execution)
        failure = self.execution['setup_failure']
        self.assertEqual(('fixture-setup', 'fixture-setup'), (failure['kind'], failure['phase']))
        self.assertEqual(self.roles, failure['evidence']['pending_roles'])
        self.assertEqual({}, failure['evidence']['setup_started'])
        self.assert_no_gameplay_grants()

    def test_stalled_callback_retains_last_observed_pause_state_and_missing_peer(self):
        self.ready()
        self.receipt('client1', 'setup-started', paused=False)
        self.receipt('client1', 'setup-ready')
        self.receipt('client2', 'setup-started', paused=True)
        self.now = 3
        self.monitor.check(self.logs, self.execution)
        self.now = 5
        with self.assertRaises(RuntimeError):
            self.monitor.check(self.logs, self.execution)
        failure = self.execution['setup_failure']
        self.assertEqual('client2', failure['role'])
        self.assertEqual(['client2'], failure['evidence']['pending_roles'])
        self.assertIs(True, failure['evidence']['setup_started']['client2']['paused'])
        self.assert_no_gameplay_grants()

    def test_repeated_receipts_do_not_reset_setup_clock_and_late_ready_cannot_release(self):
        self.ready()
        for now in (1, 2, 4.9):
            self.now = now
            self.monitor.check(self.logs, self.execution)
        for role in self.roles:
            self.receipt(role, 'setup-ready')
        self.now = 5
        with self.assertRaisesRegex(RuntimeError, 'Fixture setup deadline expired'):
            self.monitor.check(self.logs, self.execution)
        self.assert_no_gameplay_grants()

    def test_readiness_setup_and_gameplay_each_receive_their_own_budget(self):
        self.now = 9
        self.ready()
        self.now = 13.5  # Readiness + setup already exceed the old ten-second total.
        for role in self.roles:
            self.receipt(role, 'setup-ready')
        self.assertTrue(self.monitor.check(self.logs, self.execution))
        self.assertEqual(4.5, self.execution['preflight']['timing']['setup_elapsed_seconds'])
        self.now = 23.4
        self.assertTrue(self.monitor.check(self.logs, self.execution))
        self.now = 23.5
        with self.assertRaisesRegex(RuntimeError, 'gameplay deadline expired'):
            self.monitor.check(self.logs, self.execution)
        self.assertNotIn('setup_failure', self.execution)

    def test_readiness_is_bounded_even_when_no_setup_grant_was_sent(self):
        self.receipt('client1', 'ready')
        self.now = 10
        with self.assertRaisesRegex(RuntimeError, 'readiness deadline expired'):
            self.monitor.check(self.logs, self.execution)
        self.assertEqual('client2', self.execution['setup_failure']['role'])
        self.assertFalse(self.monitor.setup_released)

    def test_explicit_failure_wins_at_deadline_and_cleanup_never_grants_or_extends(self):
        self.ready()
        self.receipt('client2', 'failed', phase='fixture-setup', reason='native allocation failed')
        self.now = 5
        with self.assertRaisesRegex(RuntimeError, 'native allocation failed'):
            self.monitor.check(self.logs, self.execution)
        first = self.execution['setup_failure']
        self.now = 500
        with self.assertRaisesRegex(RuntimeError, 'native allocation failed'):
            self.monitor.check(self.logs, self.execution, release=False)
        self.assertIs(first, self.execution['setup_failure'])
        self.assert_no_gameplay_grants()

    def test_final_audit_does_not_retroactively_expire_completed_setup_or_gameplay(self):
        self.ready()
        for role in self.roles:
            self.receipt(role, 'setup-ready')
        self.now = 1
        self.monitor.check(self.logs, self.execution)
        self.now = 500
        self.assertTrue(self.monitor.check(self.logs, self.execution, release=False))
        self.assertNotIn('setup_failure', self.execution)
        self.assertEqual(1, self.execution['preflight']['timing']['setup_elapsed_seconds'])


if __name__ == '__main__':
    unittest.main()
