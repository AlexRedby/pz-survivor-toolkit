"""Owned-window isolation and the acknowledgement that lets the game become opaque."""
from pathlib import Path
from types import SimpleNamespace
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

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
        # Desktop policy must not inspect display sleep, screen lock or Mac availability.
        self.graphics = patch('ctypes.CDLL', side_effect=AssertionError('unexpected system-state probe'))
        self.graphics.start()
        self.addCleanup(self.graphics.stop)

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

    def assert_current(self, manager, mode, reason):
        self.assertEqual((self.root / 'Lua/test-window-routed.txt').read_text(), '123:456\n')
        self.assertEqual(manager.evidence['requested_mode'], mode)
        self.assertEqual(manager.evidence['mode'], 'current')
        self.assertIsNone(manager.evidence['workspace'])
        self.assertEqual(manager.evidence['glfw_handles'], {'123': '456'})
        self.assertEqual(manager.evidence['client_modes'], {'123': 'current'})
        self.assertEqual(manager.evidence['fallback_reason'], reason)
        self.assertNotIn('display_probe', manager.evidence)
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

    def test_every_mode_tries_available_aerospace_first_without_system_state_probes(self):
        self.assertFalse(hasattr(desktop, 'display_state'))
        for mode in ('auto', 'current', 'aerospace'):
            with self.subTest(mode=mode):
                self.clear_gate()
                self.moved = False
                manager = self.manager(mode)
                manager.route(self.process, self.root, self.log)
                self.assertEqual(manager.evidence['mode'], 'aerospace')
                self.assertEqual(manager.evidence['client_modes'], {'123': 'aerospace'})
                self.assertEqual(manager.evidence['requested_mode'], mode)
                self.assertNotIn('display_probe', manager.evidence)
                self.assertTrue(self.moved)

    def test_visible_target_and_user_focus_are_allowed_at_startup(self):
        self.visible = 'PZ-TEST\n'
        self.focused = '123'
        self.rows = '789|123|PZ-TEST\n'
        manager = desktop.prepare({})
        manager.route(self.process, self.root, self.log)
        self.assertEqual((self.root / 'Lua/test-window-routed.txt').read_text(), '123:456\n')
        manager.check(self.process)

    def test_auto_and_current_fall_back_after_owned_window_discovery_timeout(self):
        self.rows = ''
        for mode in ('auto', 'current'):
            with self.subTest(mode=mode):
                self.clear_gate()
                manager = self.manager(mode)
                with patch.object(desktop.time, 'monotonic', side_effect=[0, 31]):
                    manager.route(self.process, self.root, self.log)
                self.assert_current(manager, mode, 'owned-window-discovery-timeout')
        self.assertFalse(any(argv[0] in ('layout', 'move-node-to-workspace') for argv in self.commands))

    def test_discovery_timeout_can_fall_back_after_an_owned_window_was_seen(self):
        for mode in ('auto', 'current'):
            with self.subTest(mode=mode):
                self.clear_gate()
                manager = self.manager(mode)
                with patch.object(manager, 'owned', side_effect=[{'789': 'C'}, {}]), \
                     patch.object(Path, 'read_text', side_effect=['', '[QUEUE_TEST] WINDOW_ROUTING_READY pid=123 glfw=456\n']), \
                     patch.object(desktop.time, 'monotonic', side_effect=[0, 1, 31]), \
                     patch.object(desktop.time, 'sleep'):
                    manager.route(self.process, self.root, self.log)
                self.assert_current(manager, mode, 'owned-window-discovery-timeout')

    def test_missing_aerospace_falls_back_with_owned_glfw_for_auto_and_current(self):
        for mode in ('auto', 'current'):
            with self.subTest(mode=mode):
                self.clear_gate()
                with patch.object(desktop.shutil, 'which', return_value=None):
                    manager = self.manager(mode)
                manager.route(self.process, self.root, self.log)
                self.assert_current(manager, mode, 'aerospace-unavailable')
                self.assertTrue(manager.evidence['aerospace_error'])
        self.assertEqual(self.commands, [])

    def test_bad_version_and_cli_errors_fall_back_without_losing_error_evidence(self):
        faults = [('version', None), ('--version', OSError('CLI unavailable')),
                  ('--version', subprocess.TimeoutExpired('/aerospace', 5)),
                  ('--version', subprocess.CalledProcessError(1, '/aerospace'))]
        for mode in ('auto', 'current'):
            for command, error in faults:
                with self.subTest(mode=mode, command=command, error=error):
                    self.clear_gate()
                    self.version = 'invalid' if command == 'version' else '0.21.3-Beta'
                    self.fail_command = None if command == 'version' else command
                    self.command_error = error
                    manager = self.manager(mode)
                    manager.route(self.process, self.root, self.log)
                    self.assert_current(manager, mode, 'aerospace-unavailable')
                    self.assertTrue(manager.evidence['aerospace_error'])

    def test_cli_discovery_failure_falls_back_for_auto_and_current(self):
        for mode in ('auto', 'current'):
            with self.subTest(mode=mode):
                self.clear_gate()
                self.fail_command = 'list-windows'
                manager = self.manager(mode)
                manager.route(self.process, self.root, self.log)
                self.assert_current(manager, mode, 'aerospace-unavailable')
                self.assertTrue(manager.evidence['aerospace_error'])

    def test_layout_and_move_command_failure_can_fall_back_for_valid_owned_window(self):
        for mode in ('auto', 'current'):
            for command in ('layout', 'move-node-to-workspace'):
                with self.subTest(mode=mode, command=command):
                    self.clear_gate()
                    self.moved = False
                    self.fail_command = command
                    manager = self.manager(mode)
                    manager.route(self.process, self.root, self.log)
                    self.assert_current(manager, mode, 'aerospace-routing-unavailable')
                    self.assertTrue(manager.evidence['aerospace_error'])
                    changes = [argv for argv in self.commands if argv[0] in ('layout', 'move-node-to-workspace')]
                    self.assertTrue(all(argv[1:3] == ['--window-id', '789'] for argv in changes))

    def test_owned_window_disappearing_or_unplaced_before_ack_can_fall_back(self):
        sequences = [
            [{'789': 'C'}, {}],
            [{'789': 'C'}, {'789': 'C'}, {}],
            [{'789': 'C'}, {'789': 'C'}, {'789': 'C'}, {}],
            [{'789': 'C'}, {'789': 'C'}, {'789': 'C'}, {'789': 'C'}],
        ]
        for mode in ('auto', 'current', 'aerospace'):
            for sequence in sequences:
                with self.subTest(mode=mode, sequence=sequence):
                    self.clear_gate()
                    manager = self.manager(mode)
                    with patch.object(manager, 'owned', side_effect=sequence):
                        if mode == 'aerospace':
                            with self.assertRaises(desktop.AeroSpaceUnavailable):
                                manager.route(self.process, self.root, self.log)
                        else:
                            manager.route(self.process, self.root, self.log)
                    if mode == 'aerospace':
                        self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())
                    else:
                        self.assert_current(manager, mode, 'aerospace-routing-unavailable')

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
        with self.assertRaisesRegex(RuntimeError, 'exited'):
            desktop.prepare({}).route(self.process, self.root, self.log)
        self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())

    def test_strict_aerospace_rejects_missing_invalid_and_failing_cli(self):
        with patch.object(desktop.shutil, 'which', return_value=None):
            with self.assertRaisesRegex(RuntimeError, 'AeroSpace'):
                self.manager('aerospace')
        self.version = 'invalid'
        with self.assertRaisesRegex(RuntimeError, 'malformed version'):
            self.manager('aerospace')
        self.version = '0.21.3-Beta'
        self.fail_command = '--version'
        with self.assertRaisesRegex(RuntimeError, 'AeroSpace'):
            self.manager('aerospace')
        self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())

    def test_strict_aerospace_never_falls_back_on_discovery_or_routing_failure(self):
        for command in (None, 'list-windows', 'layout', 'move-node-to-workspace'):
            with self.subTest(command=command):
                self.rows = '' if command is None else '789|123|C\n'
                self.fail_command = command
                manager = self.manager('aerospace')
                with patch.object(desktop.time, 'monotonic', side_effect=[0, 31]):
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

    def test_foreign_or_zero_glfw_handshake_is_never_acknowledged_even_without_aerospace(self):
        for mode in ('auto', 'current'):
            for available in (True, False):
                for marker, reason in (('pid=999 glfw=456', 'owned client PID'), ('pid=123 glfw=0', 'nonzero')):
                    self.log.write_text('[QUEUE_TEST] WINDOW_ROUTING_READY ' + marker + '\n')
                    with self.subTest(mode=mode, available=available, marker=marker), \
                         patch.object(desktop.shutil, 'which', return_value='/aerospace' if available else None):
                        with self.assertRaisesRegex(RuntimeError, reason):
                            self.manager(mode).route(self.process, self.root, self.log)
                        self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())
        self.assertFalse(any(argv[0] in ('layout', 'move-node-to-workspace') for argv in self.commands))

    def test_missing_handshake_and_dead_process_never_release_gate(self):
        self.log.write_text('')
        for mode in ('auto', 'current'):
            for available in (True, False):
                with self.subTest(mode=mode, available=available), \
                     patch.object(desktop.shutil, 'which', return_value='/aerospace' if available else None):
                    manager = self.manager(mode)
                    with patch.object(desktop.time, 'monotonic', side_effect=[0, 31]):
                        with self.assertRaisesRegex(RuntimeError, 'GLFW handle|within 30 seconds'):
                            manager.route(self.process, self.root, self.log)
                    dead = SimpleNamespace(pid=123, poll=lambda: -11)
                    with self.assertRaisesRegex(RuntimeError, 'exited'):
                        manager.route(dead, self.root, self.log)
                    self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())

    def test_current_run_still_rejects_dead_owned_process(self):
        with patch.object(desktop.shutil, 'which', return_value=None):
            manager = desktop.prepare({})
        manager.route(self.process, self.root, self.log)
        with self.assertRaisesRegex(RuntimeError, 'exited'):
            manager.check(SimpleNamespace(pid=123, poll=lambda: -11))

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
            for available in (True, False):
                if mode == 'aerospace' and not available:
                    continue
                with self.subTest(mode=mode, available=available), \
                     patch.object(desktop.shutil, 'which', return_value='/aerospace' if available else None):
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
