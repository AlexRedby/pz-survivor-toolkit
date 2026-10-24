"""Owned-window isolation and the acknowledgement that lets the game become opaque."""
from pathlib import Path
from types import SimpleNamespace
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import desktop
import test_queue_runner


class DesktopTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'Lua').mkdir()
        self.log = self.root / 'client-launch.log'
        self.log.write_text('[QUEUE_TEST] WINDOW_ROUTING_READY pid=123 glfw=456\n')
        self.process = SimpleNamespace(pid=123, poll=lambda: None)
        self.rows = '789|123|C\n'
        self.visible = 'C\n'
        self.focused = '99'
        self.version = '0.21.3-Beta'
        self.fail_command = None
        self.command_error = None
        self.exit_on_failure = False
        self.moved = False
        self.commands = []
        self.binary = patch.object(desktop.shutil, 'which', return_value='/aerospace')
        self.binary.start()
        self.addCleanup(self.binary.stop)
        self.cli = patch.object(desktop.subprocess, 'run', side_effect=self.command)
        self.cli.start()
        self.addCleanup(self.cli.stop)
        self.display = 'awake'
        probe = patch.object(desktop, 'display_state', side_effect=lambda: {
            'state': self.display, 'displays': [{'id': 1, 'asleep': self.display == 'asleep'}]})
        self.probe = probe.start()
        self.addCleanup(probe.stop)
        sleep = patch.object(desktop.time, 'sleep')
        sleep.start()
        self.addCleanup(sleep.stop)

    def command(self, argv, **kwargs):
        self.assertEqual(argv[0], '/aerospace', 'unexpected system-state command')
        self.commands.append(argv[1:])
        if argv[1] == self.fail_command:
            if self.exit_on_failure:
                self.process.poll = lambda: -11
            raise self.command_error or subprocess.CalledProcessError(1, argv)
        if argv[1] == '--version':
            value = self.version
        elif argv[1] == 'list-workspaces':
            value = self.visible
        elif argv[1] == 'list-windows' and '--pid' in argv:
            self.assertEqual(argv[argv.index('--pid') + 1], '123')
            value = self.rows.replace('|C', '|PZ-TEST') if self.moved else self.rows
        elif argv[1] == 'list-windows':
            value = self.focused if argv[-1] == '%{app-pid}' else '55'
        elif argv[1] == 'move-node-to-workspace':
            self.moved = True
            value = ''
        else:
            value = ''
        return SimpleNamespace(stdout=value)

    def manager(self, mode):
        return desktop.prepare({'options': {'desktop_mode': mode}})

    def clear_gate(self):
        (self.root / 'Lua/test-window-routed.txt').unlink(missing_ok=True)
        (self.root / 'Lua/test-window-visible.txt').unlink(missing_ok=True)

    def assert_current(self, manager, mode, reason):
        self.assertEqual((self.root / 'Lua/test-window-routed.txt').read_text(), '123:456:current\n')
        self.assertFalse((self.root / 'Lua/test-window-visible.txt').exists())
        self.assertEqual(manager.evidence['requested_mode'], mode)
        self.assertEqual(manager.evidence['mode'], 'current')
        self.assertIsNone(manager.evidence['workspace'])
        self.assertEqual(manager.evidence['glfw_handles'], {'123': '456'})
        self.assertEqual(manager.evidence['client_modes'], {'123': 'current'})
        self.assertEqual(manager.evidence['fallback_reason'], reason)
        self.assertEqual(manager.evidence['display_probes']['123']['state'], 'asleep')
        manager.check(self.process)

    def test_move_only_exact_owned_window_without_switching_or_focus_then_acknowledge(self):
        manager = desktop.prepare({})
        manager.route(self.process, self.root, self.log)
        self.assertEqual(manager.evidence['requested_mode'], 'auto')
        self.assertEqual(manager.evidence['mode'], 'aerospace')
        self.assertEqual((self.root / 'Lua/test-window-routed.txt').read_text(), '123:456\n')
        changes = [argv for argv in self.commands if argv[0] in ('layout', 'move-node-to-workspace')]
        self.assertEqual(changes, [['layout', '--window-id', '789', 'floating'],
                                   ['move-node-to-workspace', '--window-id', '789', 'PZ-TEST']])
        self.assertFalse(any(argv[0] in ('workspace', 'focus', 'summon-workspace') or '--focus-follows-window' in argv for argv in self.commands))
        manager.check(self.process)

    def test_every_mode_tries_available_aerospace_first_without_display_probe(self):
        for mode in ('auto', 'current', 'aerospace'):
            with self.subTest(mode=mode):
                self.clear_gate()
                self.moved = False
                manager = self.manager(mode)
                manager.route(self.process, self.root, self.log)
                self.assertEqual(manager.evidence['mode'], 'aerospace')
                self.assertEqual(manager.evidence['client_modes'], {'123': 'aerospace'})
                self.assertEqual(manager.evidence['requested_mode'], mode)
                self.assertEqual(manager.evidence['display_probes'], {})
                self.assertTrue(self.moved)
        self.probe.assert_not_called()

    def test_visible_target_and_user_focus_are_allowed_at_startup(self):
        self.visible = 'PZ-TEST\n'
        self.focused = '123'
        self.rows = '789|123|PZ-TEST\n'
        manager = desktop.prepare({})
        manager.route(self.process, self.root, self.log)
        self.assertEqual((self.root / 'Lua/test-window-routed.txt').read_text(), '123:456\n')
        manager.check(self.process)

    def test_auto_and_current_fall_back_only_with_fresh_confirmed_sleep(self):
        self.rows = ''
        for mode in ('auto', 'current'):
            for state in ('awake', 'unknown', 'asleep'):
                with self.subTest(mode=mode, state=state):
                    self.clear_gate()
                    self.display = state
                    manager = self.manager(mode)
                    with patch.object(desktop.time, 'monotonic', side_effect=[0, 0, 31]):
                        if state == 'asleep':
                            manager.route(self.process, self.root, self.log)
                            self.assert_current(manager, mode, 'display-asleep-owned-window-discovery-timeout')
                        else:
                            with self.assertRaisesRegex(RuntimeError, 'sleeping displays'):
                                manager.route(self.process, self.root, self.log)
                            self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())
                    self.assertEqual(manager.evidence['display_probes']['123']['state'], state)
        self.assertEqual(self.probe.call_count, 6)
        self.assertFalse(any(argv[0] in ('layout', 'move-node-to-workspace') for argv in self.commands))

    def test_discovery_timeout_never_falls_back_after_an_owned_window_was_seen(self):
        self.display = 'asleep'
        for mode in ('auto', 'current'):
            with self.subTest(mode=mode):
                manager = self.manager(mode)
                with patch.object(manager, 'owned', side_effect=[{'789': 'C'}, {}, {}]), \
                     patch.object(Path, 'read_text', side_effect=['', '[QUEUE_TEST] WINDOW_ROUTING_READY pid=123 glfw=456\n',
                                                              '[QUEUE_TEST] WINDOW_ROUTING_READY pid=123 glfw=456\n']), \
                     patch.object(desktop.time, 'monotonic', side_effect=[0, 1, 2, 33]), \
                     patch.object(desktop.time, 'sleep'):
                    with self.assertRaisesRegex(RuntimeError, 'within 30 seconds'):
                        manager.route(self.process, self.root, self.log)
                self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())
        self.probe.assert_not_called()

    def test_slow_start_gets_full_discovery_budget_after_owned_glfw_ready(self):
        self.rows = ''
        self.display = 'asleep'
        manager = self.manager('auto')
        ready = '[QUEUE_TEST] WINDOW_ROUTING_READY pid=123 glfw=456\n'
        with patch.object(Path, 'read_text', side_effect=['', ready, ready]), \
             patch.object(desktop.time, 'monotonic', side_effect=[0, 80, 119, 150]):
            manager.route(self.process, self.root, self.log)
        self.assert_current(manager, 'auto', 'display-asleep-owned-window-discovery-timeout')
        self.assertEqual(self.probe.call_count, 1)
        self.assertEqual(len([command for command in self.commands if command[0] == 'list-windows']), 4)

    def test_slow_start_still_allows_aerospace_discovery_after_startup_deadline(self):
        manager = self.manager('auto')
        ready = '[QUEUE_TEST] WINDOW_ROUTING_READY pid=123 glfw=456\n'
        with patch.object(Path, 'read_text', side_effect=['', ready, ready]), \
             patch.object(manager, 'owned', side_effect=[{}, {}, {'789': 'C'}, {'789': 'C'},
                                                         {'789': 'C'}, {'789': 'PZ-TEST'}]), \
             patch.object(desktop.time, 'monotonic', side_effect=[0, 80, 119, 148]):
            manager.route(self.process, self.root, self.log)
        self.assertEqual(manager.evidence['client_modes'], {'123': 'aerospace'})
        self.assertEqual((self.root / 'Lua/test-window-routed.txt').read_text(), '123:456\n')
        self.probe.assert_not_called()

    def test_first_ready_after_startup_deadline_is_not_acknowledged(self):
        manager = self.manager('auto')
        with patch.object(desktop.time, 'monotonic', side_effect=[0, 121]):
            with self.assertRaisesRegex(RuntimeError, 'within 120 seconds'):
                manager.route(self.process, self.root, self.log)
        self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())
        self.probe.assert_not_called()

    def test_missing_aerospace_refuses_every_mode_before_launch_even_asleep(self):
        self.display = 'asleep'
        for mode in ('auto', 'current', 'aerospace'):
            with self.subTest(mode=mode), patch.object(desktop.shutil, 'which', return_value=None):
                with self.assertRaisesRegex(RuntimeError, 'AeroSpace.*no game launched'):
                    self.manager(mode)
        self.assertEqual(self.commands, [])
        self.probe.assert_not_called()

    def test_bad_version_and_cli_errors_refuse_every_mode_even_asleep(self):
        self.display = 'asleep'
        faults = [('version', None), ('--version', OSError('CLI unavailable')),
                  ('--version', subprocess.TimeoutExpired('/aerospace', 5)),
                  ('--version', subprocess.CalledProcessError(1, '/aerospace'))]
        for mode in ('auto', 'current', 'aerospace'):
            for command, error in faults:
                with self.subTest(mode=mode, command=command, error=error):
                    self.version = 'invalid' if command == 'version' else '0.21.3-Beta'
                    self.fail_command = None if command == 'version' else command
                    self.command_error = error
                    with self.assertRaisesRegex(RuntimeError, 'AeroSpace'):
                        self.manager(mode)
                    self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())
        self.probe.assert_not_called()

    def test_cli_discovery_failure_remains_fatal_even_asleep(self):
        self.display = 'asleep'
        self.fail_command = 'list-windows'
        for mode in ('auto', 'current', 'aerospace'):
            with self.subTest(mode=mode):
                with self.assertRaisesRegex(RuntimeError, 'AeroSpace isolation failed'):
                    self.manager(mode).route(self.process, self.root, self.log)
                self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())
        self.probe.assert_not_called()

    def test_layout_and_move_command_failure_remain_fatal_even_asleep(self):
        self.display = 'asleep'
        for mode in ('auto', 'current', 'aerospace'):
            for command in ('layout', 'move-node-to-workspace'):
                with self.subTest(mode=mode, command=command):
                    self.moved = False
                    self.fail_command = command
                    with self.assertRaisesRegex(RuntimeError, 'AeroSpace isolation failed'):
                        self.manager(mode).route(self.process, self.root, self.log)
                    self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())
        self.probe.assert_not_called()

    def test_owned_window_disappearing_or_unplaced_before_ack_remains_fatal(self):
        self.display = 'asleep'
        sequences = [
            [{'789': 'C'}, {}],
            [{'789': 'C'}, {'789': 'C'}, {}],
            [{'789': 'C'}, {'789': 'C'}, {'789': 'C'}, {}],
            [{'789': 'C'}, {'789': 'C'}, {'789': 'C'}, {'789': 'C'}],
        ]
        for mode in ('auto', 'current', 'aerospace'):
            for sequence in sequences:
                with self.subTest(mode=mode, sequence=sequence):
                    manager = self.manager(mode)
                    with patch.object(manager, 'owned', side_effect=sequence):
                        with self.assertRaisesRegex(RuntimeError, 'disappeared|did not isolate'):
                            manager.route(self.process, self.root, self.log)
                    self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())
        self.probe.assert_not_called()

    def test_foreign_identity_during_placement_remains_a_hard_failure(self):
        for mode in ('auto', 'current', 'aerospace'):
            with self.subTest(mode=mode):
                manager = self.manager(mode)
                original = manager.owned
                calls = 0
                def replace_after_discovery(process):
                    nonlocal calls
                    calls += 1
                    if calls > 1:
                        self.rows = '789|999|C\n'
                    return original(process)
                self.rows = '789|123|C\n'
                with patch.object(manager, 'owned', side_effect=replace_after_discovery):
                    with self.assertRaisesRegex(RuntimeError, 'owned client PID'):
                        manager.route(self.process, self.root, self.log)
                self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())
        self.assertFalse(any(argv[0] in ('layout', 'move-node-to-workspace') for argv in self.commands))

    def test_routing_failure_does_not_acknowledge_a_process_that_exited(self):
        self.fail_command = 'move-node-to-workspace'
        self.exit_on_failure = True
        with self.assertRaisesRegex(RuntimeError, 'AeroSpace isolation failed'):
            desktop.prepare({}).route(self.process, self.root, self.log)
        self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())

    def test_client_exiting_during_final_window_query_never_releases_gate(self):
        manager = self.manager('auto')
        original = manager.owned
        def exit_after_placement(process):
            rows = original(process)
            if self.moved:
                process.poll = lambda: -11
            return rows
        with patch.object(manager, 'owned', side_effect=exit_after_placement):
            with self.assertRaisesRegex(RuntimeError, 'exited before window acknowledgement'):
                manager.route(self.process, self.root, self.log)
        self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())
        self.assertEqual(manager.evidence['client_modes'], {})

    def test_strict_aerospace_does_not_probe_sleep_for_discovery_timeout(self):
        self.display = 'asleep'
        self.rows = ''
        manager = self.manager('aerospace')
        with patch.object(desktop.time, 'monotonic', side_effect=[0, 0, 31]):
            with self.assertRaisesRegex(RuntimeError, 'within 30 seconds'):
                manager.route(self.process, self.root, self.log)
        self.probe.assert_not_called()
        self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())

    def test_strict_aerospace_never_falls_back_on_discovery_or_routing_failure(self):
        for command in (None, 'list-windows', 'layout', 'move-node-to-workspace'):
            with self.subTest(command=command):
                self.rows = '' if command is None else '789|123|C\n'
                self.fail_command = command
                manager = self.manager('aerospace')
                with patch.object(desktop.time, 'monotonic', side_effect=[0, 0, 31]):
                    with self.assertRaises(RuntimeError):
                        manager.route(self.process, self.root, self.log)
                self.assertEqual(manager.evidence['mode'], 'aerospace')
                self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())

    def test_foreign_malformed_zero_and_duplicate_window_rows_never_fall_back(self):
        for mode in ('auto', 'current', 'aerospace'):
            for rows in ('789|999|C\n', 'broken\n', '0|123|C\n', '789|123|\n', '789|123|C\n789|123|C\n'):
                self.rows = rows
                with self.subTest(mode=mode, rows=rows), self.assertRaisesRegex(RuntimeError, 'owned client PID'):
                    self.manager(mode).route(self.process, self.root, self.log)
                self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())
        self.assertFalse(any(argv[0] in ('layout', 'move-node-to-workspace') for argv in self.commands))

    def test_foreign_or_zero_glfw_handshake_is_never_acknowledged_even_asleep(self):
        self.display = 'asleep'
        self.rows = ''
        for mode in ('auto', 'current', 'aerospace'):
            for marker, reason in (('pid=999 glfw=456', 'owned client PID'), ('pid=123 glfw=0', 'nonzero')):
                self.log.write_text('[QUEUE_TEST] WINDOW_ROUTING_READY ' + marker + '\n')
                with self.subTest(mode=mode, marker=marker):
                    with self.assertRaisesRegex(RuntimeError, reason):
                        self.manager(mode).route(self.process, self.root, self.log)
                    self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())
        self.probe.assert_not_called()
        self.assertFalse(any(argv[0] in ('layout', 'move-node-to-workspace') for argv in self.commands))

    def test_missing_or_malformed_handshake_and_dead_process_never_release_gate(self):
        self.display = 'asleep'
        self.rows = ''
        for mode in ('auto', 'current', 'aerospace'):
            for marker in ('', '[QUEUE_TEST] WINDOW_ROUTING_READY pid=123 glfw=broken\n'):
                self.log.write_text(marker)
                with self.subTest(mode=mode, marker=marker):
                    manager = self.manager(mode)
                    with patch.object(desktop.time, 'monotonic', side_effect=[0, 121]):
                        with self.assertRaisesRegex(RuntimeError, 'GLFW handle.*within 120 seconds'):
                            manager.route(self.process, self.root, self.log)
                    dead = SimpleNamespace(pid=123, poll=lambda: -11)
                    with self.assertRaisesRegex(RuntimeError, 'exited'):
                        manager.route(dead, self.root, self.log)
                    self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())
        self.probe.assert_not_called()

    def test_current_run_still_rejects_dead_owned_process(self):
        self.display = 'asleep'
        self.rows = ''
        manager = desktop.prepare({})
        with patch.object(desktop.time, 'monotonic', side_effect=[0, 0, 31]):
            manager.route(self.process, self.root, self.log)
        with self.assertRaisesRegex(RuntimeError, 'exited'):
            manager.check(SimpleNamespace(pid=123, poll=lambda: -11))

    def fallback(self):
        self.rows = ''
        self.display = 'asleep'
        manager = self.manager('auto')
        with patch.object(desktop.time, 'monotonic', side_effect=[0, 0, 31]):
            manager.route(self.process, self.root, self.log)
        return manager

    def test_wake_discovery_routes_window_and_keeps_original_gate_and_sleep_evidence(self):
        manager = self.fallback()
        gate = self.root / 'Lua/test-window-routed.txt'
        gate_before = gate.stat()
        self.rows = '789|123|C\n'
        self.display = 'awake'
        count = len(self.commands)
        with patch.object(Path, 'open', side_effect=AssertionError('wake must not rewrite the gate')):
            manager.check(self.process)
        self.assertEqual(manager.evidence['mode'], 'aerospace')
        self.assertEqual(manager.evidence['workspace'], 'PZ-TEST')
        self.assertEqual(manager.evidence['client_modes'], {'123': 'aerospace'})
        self.assertEqual(manager.evidence['windows'], {'123': ['789']})
        self.assertEqual(manager.evidence['glfw_handles'], {'123': '456'})
        self.assertEqual(manager.evidence['display_probes']['123']['state'], 'asleep')
        self.assertEqual(manager.evidence['fallback_reason'], 'display-asleep-owned-window-discovery-timeout')
        self.assertEqual(gate.stat().st_mtime_ns, gate_before.st_mtime_ns)
        self.assertEqual(gate.read_text(), '123:456:current\n')
        self.assertEqual((self.root / 'Lua/test-window-visible.txt').read_text(), '123:456\n')
        self.assertEqual(list((self.root / 'Lua').glob('.test-window-visible-*')), [])
        changes = [argv for argv in self.commands[count:] if argv[0] != 'list-windows']
        self.assertEqual(changes, [['layout', '--window-id', '789', 'floating'],
                                   ['move-node-to-workspace', '--window-id', '789', 'PZ-TEST']])
        self.probe.assert_called_once_with()
        manager.check(self.process)
        self.rows = '790|123|PZ-TEST\n'
        with self.assertRaisesRegex(RuntimeError, 'escaped.*pid=123'):
            manager.check(self.process)

    def test_current_run_keeps_waiting_while_owned_discovery_remains_empty(self):
        manager = self.fallback()
        self.display = 'awake'
        manager.check(self.process)
        self.assertEqual(manager.evidence['client_modes'], {'123': 'current'})
        self.assertFalse(any(command[0] == 'layout' for command in self.commands))
        self.probe.assert_called_once_with()

    def test_wake_cli_and_mutation_errors_are_fatal_without_marking_recovery(self):
        for command in ('list-windows', 'layout', 'move-node-to-workspace'):
            with self.subTest(command=command):
                self.clear_gate()
                self.fail_command = None
                self.moved = False
                manager = self.fallback()
                self.rows = '789|123|C\n'
                self.fail_command = command
                with self.assertRaisesRegex(RuntimeError, 'AeroSpace isolation failed'):
                    manager.check(self.process)
                self.assertEqual(manager.evidence['client_modes'], {'123': 'current'})
                self.assertEqual(manager.evidence['windows'], {})
                self.assertEqual((self.root / 'Lua/test-window-routed.txt').read_text(), '123:456:current\n')
                self.assertFalse((self.root / 'Lua/test-window-visible.txt').exists())

    def test_wake_foreign_window_is_never_mutated(self):
        manager = self.fallback()
        self.rows = '789|999|C\n'
        count = len(self.commands)
        with self.assertRaisesRegex(RuntimeError, 'owned client PID'):
            manager.check(self.process)
        self.assertEqual([argv[0] for argv in self.commands[count:]], ['list-windows'])
        self.assertEqual(manager.evidence['client_modes'], {'123': 'current'})

    def test_wake_replacement_disappearance_and_unplaced_windows_are_fatal(self):
        sequences = [
            [{'789': 'C'}, {}],
            [{'789': 'C'}, {'789': 'C'}, {}],
            [{'789': 'C'}, {'789': 'C'}, {'789': 'C'}, {'790': 'PZ-TEST'}],
            [{'789': 'C'}, {'789': 'C'}, {'789': 'C'}, {'789': 'C'}],
        ]
        for sequence in sequences:
            with self.subTest(sequence=sequence):
                self.clear_gate()
                manager = self.fallback()
                with patch.object(manager, 'owned', side_effect=sequence):
                    with self.assertRaisesRegex(RuntimeError, 'disappeared|did not isolate'):
                        manager.check(self.process)
                self.assertEqual(manager.evidence['client_modes'], {'123': 'current'})

    def test_wake_exit_during_discovery_never_marks_recovery(self):
        manager = self.fallback()
        def exit_after_discovery(process):
            process.poll = lambda: -11
            return {}
        with patch.object(manager, 'owned', side_effect=exit_after_discovery):
            with self.assertRaisesRegex(RuntimeError, 'exited'):
                manager.check(self.process)
        self.assertEqual(manager.evidence['client_modes'], {'123': 'current'})

    def test_wake_rechecks_window_identity_before_publishing_complete_visibility_token(self):
        manager = self.fallback()
        sequence = [{'789': 'C'}, {'789': 'C'}, {'789': 'C'}, {'789': 'PZ-TEST'}, {'790': 'PZ-TEST'}]
        with patch.object(manager, 'owned', side_effect=sequence):
            with self.assertRaisesRegex(RuntimeError, 'changed before visibility acknowledgement'):
                manager.check(self.process)
        self.assertFalse((self.root / 'Lua/test-window-visible.txt').exists())
        self.assertEqual(list((self.root / 'Lua').glob('.test-window-visible-*')), [])
        self.assertEqual(manager.evidence['client_modes'], {'123': 'current'})

    def test_wake_never_overwrites_a_preexisting_visibility_file_or_symlink(self):
        target = self.root / 'preserve.txt'
        target.write_text('foreign-token\n')
        for symlink in (False, True):
            with self.subTest(symlink=symlink):
                self.clear_gate()
                self.moved = False
                manager = self.fallback()
                visible = self.root / 'Lua/test-window-visible.txt'
                if symlink:
                    visible.symlink_to(target)
                else:
                    visible.write_text('foreign-token\n')
                self.rows = '789|123|C\n'
                with self.assertRaises(FileExistsError):
                    manager.check(self.process)
                self.assertEqual(visible.read_text(), 'foreign-token\n')
                self.assertEqual(target.read_text(), 'foreign-token\n')
                self.assertEqual(list((self.root / 'Lua').glob('.test-window-visible-*')), [])
                self.assertEqual(manager.evidence['client_modes'], {'123': 'current'})

    def test_process_exiting_during_sleep_probe_never_releases_gate(self):
        self.rows = ''
        def exit_during_probe():
            self.process.poll = lambda: -11
            return {'state': 'asleep', 'displays': [{'id': 1, 'asleep': True}]}
        self.probe.side_effect = exit_during_probe
        with patch.object(desktop.time, 'monotonic', side_effect=[0, 0, 31]):
            with self.assertRaisesRegex(RuntimeError, 'exited'):
                desktop.prepare({}).route(self.process, self.root, self.log)
        self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())

    def test_unknown_desktop_mode_is_not_an_implicit_fallback(self):
        for mode in ('invalid', '', None, []):
            with self.subTest(mode=mode), self.assertRaisesRegex(ValueError, 'desktop_mode'):
                desktop.prepare({'options': {'desktop_mode': mode}})
        self.assertEqual(self.commands, [])

    def test_missing_replaced_or_moved_window_is_rejected_after_successful_routing(self):
        manager = desktop.prepare({})
        manager.route(self.process, self.root, self.log)
        self.visible = 'PZ-TEST\n'
        self.focused = '123'
        self.moved = False
        count = len(self.commands)
        for rows in ('', '790|123|PZ-TEST\n', '789|123|C\n'):
            with self.subTest(rows=rows):
                self.rows = rows
                with self.assertRaisesRegex(RuntimeError, 'escaped.*pid=123.*observed='):
                    manager.check(self.process)
        self.assertTrue(all(argv[0] in ('list-windows', 'list-workspaces') for argv in self.commands[count:]))

    def test_visiting_workspace_during_routing_allows_acknowledgement(self):
        manager = desktop.prepare({})
        original = manager.call
        def reveal_on_move(*args):
            result = original(*args)
            if args[0] == 'move-node-to-workspace':
                self.visible = 'PZ-TEST\n'
                self.focused = '123'
            return result
        with patch.object(manager, 'call', side_effect=reveal_on_move):
            manager.route(self.process, self.root, self.log)
        self.assertEqual((self.root / 'Lua/test-window-routed.txt').read_text(), '123:456\n')
        manager.check(self.process)

    def test_automated_run_can_be_watched_and_left_after_silent_routing(self):
        manager = desktop.prepare({})
        manager.route(self.process, self.root, self.log)
        for visible, focused in [('PZ-TEST\n', '123'), ('C\n', '99'), ('PZ-TEST\n', '123')]:
            self.visible, self.focused = visible, focused
            manager.check(self.process)
        self.assertTrue(self.moved)

    def test_every_mode_requires_agent_and_fresh_acknowledgement(self):
        for mode in ('auto', 'current', 'aerospace'):
            with self.subTest(mode=mode):
                self.clear_gate()
                (self.root / 'test-window-agent.jar').unlink(missing_ok=True)
                manager = self.manager(mode)
                with self.assertRaisesRegex(RuntimeError, 'agent is missing'):
                    manager.arguments(self.root, self.root)
                (self.root / 'test-window-agent.jar').touch()
                args = manager.arguments(self.root, self.root)
                self.assertTrue(args[0].startswith('-javaagent:'))
                self.assertIn('-Dtoolkit.test.windowGate=' + str(self.root / 'Lua/test-window-routed.txt'), args)
                (self.root / 'Lua/test-window-routed.txt').write_text('old\n')
                with self.assertRaisesRegex(RuntimeError, 'already exists'):
                    manager.arguments(self.root, self.root)

    def test_visible_acknowledgement_must_also_be_fresh_before_launch(self):
        (self.root / 'test-window-agent.jar').touch()
        for symlink in (False, True):
            with self.subTest(symlink=symlink):
                self.clear_gate()
                visible = self.root / 'Lua/test-window-visible.txt'
                if symlink:
                    visible.symlink_to(self.root / 'missing-target')
                else:
                    visible.write_text('123:456\n')
                with self.assertRaisesRegex(RuntimeError, 'already exists'):
                    self.manager('auto').arguments(self.root, self.root)

    def test_acknowledgement_never_overwrites_a_gate_created_after_arguments(self):
        (self.root / 'test-window-agent.jar').touch()
        target = self.root / 'existing-target.txt'
        target.write_text('preserve\n')
        gate = self.root / 'Lua/test-window-routed.txt'
        for fallback in (False, True):
            for kind in ('file', 'symlink'):
                with self.subTest(fallback=fallback, kind=kind):
                    self.clear_gate()
                    self.rows = '' if fallback else '789|123|C\n'
                    self.display = 'asleep'
                    manager = self.manager('auto')
                    manager.arguments(self.root, self.root)
                    if kind == 'file':
                        gate.write_text('preserve\n')
                    else:
                        gate.symlink_to(target)
                    with patch.object(desktop.time, 'monotonic', side_effect=[0, 0, 31]):
                        with self.assertRaises(FileExistsError):
                            manager.route(self.process, self.root, self.log)
                    self.assertEqual(gate.read_text(), 'preserve\n')
                    self.assertEqual(target.read_text(), 'preserve\n')
                    self.assertEqual(manager.evidence['client_modes'], {})

    def second_client(self):
        cache = self.root / 'second'
        (cache / 'Lua').mkdir(parents=True)
        log = cache / 'launch.log'
        log.write_text('[QUEUE_TEST] WINDOW_ROUTING_READY pid=124 glfw=457\n')
        return SimpleNamespace(pid=124, poll=lambda: None), cache, log

    def test_fallback_for_first_client_keeps_second_client_aerospace_checks(self):
        self.rows = ''
        self.display = 'asleep'
        manager = self.manager('auto')
        with patch.object(desktop.time, 'monotonic', side_effect=[0, 0, 31]):
            manager.route(self.process, self.root, self.log)
        second, cache, log = self.second_client()
        second_rows = {'790': 'PZ-TEST'}
        with patch.object(manager, 'owned', side_effect=lambda process: second_rows if process.pid == 124 else {}) as owned:
            manager.route(second, cache, log)
            calls = owned.call_count
            manager.check(self.process)
            self.assertEqual(owned.call_count, calls + 1)
            manager.check(second)
            self.assertEqual(owned.call_count, calls + 2)
            second_rows['790'] = 'C'
            with self.assertRaisesRegex(RuntimeError, 'escaped.*pid=124'):
                manager.check(second)
        self.assertEqual(manager.evidence['client_modes'], {'123': 'current', '124': 'aerospace'})
        self.assertEqual((cache / 'Lua/test-window-routed.txt').read_text(), '124:457\n')
        self.probe.assert_called_once_with()

    def test_second_client_rechecks_sleep_instead_of_reusing_first_client_probe(self):
        self.rows = ''
        self.probe.side_effect = [
            {'state': 'asleep', 'displays': [{'id': 1, 'asleep': True}]},
            {'state': 'awake', 'displays': [{'id': 1, 'asleep': False}]},
        ]
        manager = self.manager('auto')
        with patch.object(desktop.time, 'monotonic', side_effect=[0, 0, 31]):
            manager.route(self.process, self.root, self.log)
        second, cache, log = self.second_client()
        with patch.object(manager, 'owned', return_value={}), \
             patch.object(desktop.time, 'monotonic', side_effect=[0, 0, 31]):
            with self.assertRaisesRegex(RuntimeError, 'sleeping displays'):
                manager.route(second, cache, log)
        self.assertEqual(self.probe.call_count, 2)
        self.assertEqual(manager.evidence['display_probes']['123']['state'], 'asleep')
        self.assertEqual(manager.evidence['display_probes']['124']['state'], 'awake')
        self.assertEqual(manager.evidence['client_modes'], {'123': 'current'})
        self.assertFalse((cache / 'Lua/test-window-routed.txt').exists())

    def test_first_clients_observed_window_does_not_prevent_second_clients_fallback(self):
        manager = self.manager('auto')
        manager.route(self.process, self.root, self.log)
        self.display = 'asleep'
        second, cache, log = self.second_client()
        with patch.object(manager, 'owned', return_value={}), \
             patch.object(desktop.time, 'monotonic', side_effect=[0, 0, 31]):
            manager.route(second, cache, log)
        self.assertEqual(manager.evidence['client_modes'], {'123': 'aerospace', '124': 'current'})
        self.assertEqual((cache / 'Lua/test-window-routed.txt').read_text(), '124:457:current\n')
        self.probe.assert_called_once_with()

    def test_wake_recovery_updates_each_client_without_losing_other_current_or_routed_checks(self):
        manager = self.fallback()
        second, cache, log = self.second_client()
        second_rows = {}
        original_owned = manager.owned
        with patch.object(manager, 'owned', side_effect=lambda process: second_rows if process.pid == 124 else original_owned(process)):
            with patch.object(desktop.time, 'monotonic', side_effect=[0, 0, 31]):
                manager.route(second, cache, log)
            self.rows = '789|123|C\n'
            manager.check(self.process)
            self.assertEqual(manager.evidence['client_modes'], {'123': 'aerospace', '124': 'current'})
            self.assertEqual(manager.evidence['mode'], 'current')
            self.assertIsNone(manager.evidence['workspace'])
            manager.check(second)
            second_rows['790'] = 'PZ-TEST'
            manager.check(second)
            self.assertEqual(manager.evidence['client_modes'], {'123': 'aerospace', '124': 'aerospace'})
            self.assertEqual(manager.evidence['mode'], 'aerospace')
            self.assertEqual(manager.evidence['workspace'], 'PZ-TEST')
            self.assertEqual(manager.evidence['windows'], {'123': ['789'], '124': ['790']})
            self.assertEqual(manager.evidence['glfw_handles'], {'123': '456', '124': '457'})
            manager.check(self.process)
            second_rows.clear()
            second_rows['791'] = 'PZ-TEST'
            with self.assertRaisesRegex(RuntimeError, 'escaped.*pid=124'):
                manager.check(second)
        self.assertEqual((cache / 'Lua/test-window-routed.txt').read_text(), '124:457:current\n')
        self.assertEqual((cache / 'Lua/test-window-visible.txt').read_text(), '124:457\n')
        self.assertEqual(set(manager.evidence['display_probes']), {'123', '124'})
        self.assertEqual(self.probe.call_count, 2)


class GuiAccessTests(unittest.TestCase):
    def test_awake_and_sleeping_displays_both_authorize_gui_access(self):
        for state in ('awake', 'asleep'):
            probe = {'state': state, 'displays': [{'id': 1, 'asleep': state == 'asleep'}]}
            with self.subTest(state=state), patch.object(desktop, 'display_state', return_value=probe):
                self.assertIs(desktop.require_gui_access(), probe)

    def test_unknown_probe_explains_gui_access_and_preserves_reason_without_asking_to_wake_display(self):
        with patch.object(desktop, 'display_state', return_value={
                'state': 'unknown', 'displays': [], 'reason': 'invalid-online-display-count'}):
            with self.assertRaisesRegex(RuntimeError, 'GUI display access unavailable.*invalid-online-display-count') as error:
                desktop.require_gui_access()
        self.assertIn('outside the sandbox in the logged-in macOS session', str(error.exception))
        self.assertIn('no game launched', str(error.exception))
        self.assertIn('Waking the display is not a remedy', str(error.exception))


class DisplayStateTests(unittest.TestCase):
    def probe(self, ids, asleep=None, *, counts=(), errors=()):
        counts, errors = iter(counts), iter(errors)
        asleep = asleep if asleep is not None else {value: True for value in ids}
        def online(maximum, displays, count):
            count._obj.value = next(counts, len(ids))
            if displays is not None:
                for index, value in enumerate(ids[:maximum]):
                    displays[index] = value
            return next(errors, 0)
        graphics = SimpleNamespace(CGGetOnlineDisplayList=Mock(side_effect=online),
                                   CGDisplayIsAsleep=Mock(side_effect=lambda value: asleep[value]))
        with patch.object(desktop.sys, 'platform', 'darwin'), \
             patch.object(desktop.ctypes, 'CDLL', return_value=graphics):
            return desktop.display_state()

    def test_every_online_display_must_be_asleep(self):
        self.assertEqual(self.probe([1, 2]), {'state': 'asleep', 'displays': [
            {'id': 1, 'asleep': True}, {'id': 2, 'asleep': True}]})
        for states in ({1: True, 2: False}, {1: False, 2: True}, {1: False, 2: False}):
            with self.subTest(states=states):
                self.assertEqual(self.probe([1, 2], states)['state'], 'awake')

    def test_zero_oversized_failed_or_changing_enumeration_is_unknown(self):
        cases = [
            ('zero-online', [], (), ()),
            ('oversized', [1], (129,), ()),
            ('initial-api-error', [1], (), (1000,)),
            ('fetch-api-error', [1], (), (0, 1000)),
            ('final-api-error', [1], (), (0, 0, 1000)),
            ('fetch-grew', [1], (1, 2), ()),
            ('fetch-shrank', [1], (1, 0), ()),
            ('final-grew', [1], (1, 1, 2), ()),
            ('final-shrank', [1], (1, 1, 0), ()),
        ]
        for name, ids, counts, errors in cases:
            with self.subTest(name=name):
                result = self.probe(ids, counts=counts, errors=errors)
                self.assertEqual(result['state'], 'unknown')
                self.assertEqual(result['displays'], [])
                self.assertTrue(result['reason'])

    def test_zero_or_duplicate_display_identities_are_unknown(self):
        for ids in ([0], [1, 1]):
            with self.subTest(ids=ids):
                self.assertEqual(self.probe(ids)['state'], 'unknown')

    def test_unavailable_coregraphics_and_non_macos_are_unknown(self):
        for error in (OSError('unavailable'), AttributeError('missing API')):
            with self.subTest(error=error), patch.object(desktop.sys, 'platform', 'darwin'), \
                 patch.object(desktop.ctypes, 'CDLL', side_effect=error):
                self.assertEqual(desktop.display_state()['state'], 'unknown')
        with patch.object(desktop.sys, 'platform', 'linux'), patch.object(desktop.ctypes, 'CDLL') as load:
            self.assertEqual(desktop.display_state()['state'], 'unknown')
            load.assert_not_called()


class DesktopRunnerTests(unittest.TestCase):
    def setUp(self):
        self.harness = test_queue_runner.NativeRunnerTests()
        self.harness.setUp()
        self.addCleanup(self.harness.doCleanups)

    def test_routing_failure_stops_only_the_new_client_and_marks_run_failed(self):
        def fail(*args):
            raise RuntimeError('owned-window routing failed')
        self.harness.desktop.route = fail
        result, kills = self.harness.invoke()
        self.assertEqual(result['status'], 'failed')
        self.assertIn('owned-window routing failed', result['error'])
        self.assertEqual([call.args[0] for call in kills], [101])
        self.assertTrue(all(stream.closed for stream in self.harness.streams))

    def test_host_client_receives_window_agent_and_keeps_server_loader(self):
        self.harness.prepare_host()
        self.harness.desktop.arguments = lambda *args: ['-javaagent:/owned/window-agent.jar']
        result, _ = self.harness.invoke()
        command = next(argv for argv in self.harness.commands if 'ToolkitSmokeLauncher' in argv)
        self.assertIn('-javaagent:/owned/window-agent.jar', command)
        self.assertEqual(result['status'], 'completed')


if __name__ == '__main__':
    unittest.main()
