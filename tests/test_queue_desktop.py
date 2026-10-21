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
        self.fail_move = False
        self.fail_list = False
        self.display = 'awake'
        self.moved = False
        self.commands = []
        self.binary = patch.object(desktop.shutil, 'which', return_value='/aerospace')
        self.binary.start()
        self.addCleanup(self.binary.stop)
        self.cli = patch.object(desktop.subprocess, 'run', side_effect=self.command)
        self.cli.start()
        self.addCleanup(self.cli.stop)
        self.probe = patch.object(desktop, 'display_state', side_effect=lambda: {'state': self.display, 'displays': []})
        self.probe.start()
        self.addCleanup(self.probe.stop)

    def command(self, argv, **kwargs):
        self.commands.append(argv[1:])
        if argv[1] == '--version':
            value = '0.21.3-Beta'
        elif argv[1] == 'list-workspaces':
            value = self.visible
        elif argv[1] == 'list-windows' and '--pid' in argv:
            if self.fail_list:
                raise subprocess.CalledProcessError(1, argv)
            self.assertEqual(argv[argv.index('--pid') + 1], '123')
            value = self.rows.replace('|C', '|PZ-TEST') if self.moved else self.rows
        elif argv[1] == 'list-windows':
            value = self.focused if argv[-1] == '%{app-pid}' else '55'
        elif argv[1] == 'move-node-to-workspace':
            if self.fail_move:
                raise subprocess.CalledProcessError(1, argv)
            self.moved = True
            value = ''
        else:
            value = ''
        return SimpleNamespace(stdout=value)

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

    def test_missing_aerospace_refuses_before_window_mutations(self):
        with patch.object(desktop.shutil, 'which', return_value=None):
            with self.assertRaisesRegex(RuntimeError, 'no game launched'):
                desktop.prepare({})
        self.assertFalse(any(argv[0] == 'layout' for argv in self.commands))

    def test_visible_target_and_user_focus_are_allowed_at_startup(self):
        self.visible = 'PZ-TEST\n'
        self.focused = '123'
        self.rows = '789|123|PZ-TEST\n'
        manager = desktop.prepare({})
        manager.route(self.process, self.root, self.log)
        self.assertEqual((self.root / 'Lua/test-window-routed.txt').read_text(), '123:456\n')
        manager.check(self.process)

    def test_current_desktop_is_only_a_sleeping_display_discovery_fallback(self):
        self.display = 'asleep'
        self.rows = ''
        manager = desktop.prepare({'options': {'desktop_mode': 'current'}})
        with patch.object(desktop.time, 'monotonic', side_effect=[0, 31]):
            manager.route(self.process, self.root, self.log)
        manager.check(self.process)
        self.assertEqual([command[0] for command in self.commands], ['--version', 'list-windows'])
        self.assertEqual((self.root / 'Lua/test-window-routed.txt').read_text(), '123:456\n')
        self.assertEqual(manager.evidence['mode'], 'current')
        self.assertEqual(manager.evidence['requested_mode'], 'current')
        self.assertIsNone(manager.evidence['workspace'])
        self.assertEqual(manager.evidence['glfw_handles'], {'123': '456'})
        self.assertEqual(manager.evidence['client_modes'], {'123': 'current'})
        self.assertEqual(manager.evidence['fallback_reason'], 'display-asleep-owned-window-discovery-timeout')

    def test_explicit_current_refuses_awake_unknown_and_missing_aerospace(self):
        for state in ('awake', 'unknown'):
            self.display = state
            with self.subTest(state=state), self.assertRaisesRegex(RuntimeError, 'confirmed sleeping displays'):
                desktop.prepare({'options': {'desktop_mode': 'current'}})
        self.display = 'asleep'
        with patch.object(desktop.shutil, 'which', return_value=None):
            with self.assertRaisesRegex(RuntimeError, 'AeroSpace is required'):
                desktop.prepare({'options': {'desktop_mode': 'current'}})
        self.assertEqual(self.commands, [])

    def test_current_desktop_refuses_foreign_or_missing_handshake_and_dead_process(self):
        self.display = 'asleep'
        self.rows = ''
        manager = desktop.prepare({'options': {'desktop_mode': 'current'}})
        self.log.write_text('[QUEUE_TEST] WINDOW_ROUTING_READY pid=999 glfw=456\n')
        with self.assertRaisesRegex(RuntimeError, 'owned client PID'):
            manager.route(self.process, self.root, self.log)
        self.log.write_text('')
        with patch.object(desktop.time, 'monotonic', side_effect=[0, 31]):
            with self.assertRaisesRegex(RuntimeError, 'owned GLFW handle'):
                manager.route(self.process, self.root, self.log)
        dead = SimpleNamespace(pid=123, poll=lambda: -11)
        with self.assertRaisesRegex(RuntimeError, 'exited'):
            manager.route(dead, self.root, self.log)
        with self.assertRaisesRegex(RuntimeError, 'exited'):
            manager.check(dead)
        self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())
        self.assertFalse(any(argv[0] in ('layout', 'move-node-to-workspace') for argv in self.commands))

    def test_unknown_desktop_mode_is_not_an_implicit_fallback(self):
        for mode in ('invalid', '', None, []):
            with self.subTest(mode=mode), self.assertRaisesRegex(ValueError, 'desktop_mode'):
                desktop.prepare({'options': {'desktop_mode': mode}})
        self.assertEqual(self.commands, [])

    def test_current_desktop_still_requires_agent_and_fresh_acknowledgement(self):
        self.display = 'asleep'
        manager = desktop.prepare({'options': {'desktop_mode': 'current'}})
        with self.assertRaisesRegex(RuntimeError, 'agent is missing'):
            manager.arguments(self.root, self.root)
        (self.root / 'test-window-agent.jar').touch()
        self.assertIn('-Dtoolkit.test.windowGate=' + str(self.root / 'Lua/test-window-routed.txt'),
                      manager.arguments(self.root, self.root))
        (self.root / 'Lua/test-window-routed.txt').write_text('old\n')
        with self.assertRaisesRegex(RuntimeError, 'already exists'):
            manager.arguments(self.root, self.root)

    def test_auto_falls_back_only_for_confirmed_sleep_at_empty_discovery_timeout(self):
        self.rows = ''
        for state in ('awake', 'unknown', 'asleep'):
            with self.subTest(state=state):
                self.display = state
                manager = desktop.prepare({})
                with patch.object(desktop.time, 'monotonic', side_effect=[0, 31]):
                    if state == 'asleep':
                        manager.route(self.process, self.root, self.log)
                        self.assertEqual(manager.evidence['requested_mode'], 'auto')
                        self.assertEqual(manager.evidence['mode'], 'current')
                        self.assertEqual(manager.evidence['display_probe']['state'], 'asleep')
                    else:
                        with self.assertRaisesRegex(RuntimeError, 'within 30 seconds'):
                            manager.route(self.process, self.root, self.log)
                        self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())
        self.assertFalse(any(argv[0] in ('layout', 'move-node-to-workspace') for argv in self.commands))

    def test_strict_aerospace_never_falls_back_even_asleep(self):
        self.display = 'asleep'
        self.rows = ''
        manager = desktop.prepare({'options': {'desktop_mode': 'aerospace'}})
        with patch.object(desktop.time, 'monotonic', side_effect=[0, 31]):
            with self.assertRaisesRegex(RuntimeError, 'within 30 seconds'):
                manager.route(self.process, self.root, self.log)
        self.assertEqual(manager.evidence['mode'], 'aerospace')
        self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())

    def test_primary_routing_is_used_even_for_sleeping_explicit_current(self):
        self.display = 'asleep'
        manager = desktop.prepare({'options': {'desktop_mode': 'current'}})
        manager.route(self.process, self.root, self.log)
        self.assertEqual(manager.evidence['mode'], 'aerospace')
        self.assertEqual(manager.evidence['client_modes'], {'123': 'aerospace'})
        self.assertTrue(self.moved)

    def test_sleep_does_not_hide_invalid_ownership_cli_or_routing_errors(self):
        self.display = 'asleep'
        for rows in ('789|999|C\n', 'broken\n', '0|123|C\n', '789|123|\n', '789|123|C\n789|123|C\n'):
            self.rows = rows
            with self.subTest(rows=rows), self.assertRaisesRegex(RuntimeError, 'owned client PID'):
                desktop.prepare({}).route(self.process, self.root, self.log)
        self.rows = ''
        self.fail_list = True
        with self.assertRaisesRegex(RuntimeError, 'AeroSpace isolation failed'):
            desktop.prepare({}).route(self.process, self.root, self.log)
        self.fail_list = False
        self.rows = '789|123|C\n'
        self.fail_move = True
        with self.assertRaisesRegex(RuntimeError, 'AeroSpace isolation failed'):
            desktop.prepare({}).route(self.process, self.root, self.log)
        self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())

    def test_sleep_does_not_hide_zero_handle_or_disappearing_owned_window(self):
        self.display = 'asleep'
        self.rows = ''
        self.log.write_text('[QUEUE_TEST] WINDOW_ROUTING_READY pid=123 glfw=0\n')
        with self.assertRaisesRegex(RuntimeError, 'nonzero'):
            desktop.prepare({}).route(self.process, self.root, self.log)
        manager = desktop.prepare({})
        with patch.object(manager, 'owned', side_effect=[{'789': 'C'}, {}]), \
             patch.object(Path, 'read_text', side_effect=['', '[QUEUE_TEST] WINDOW_ROUTING_READY pid=123 glfw=456\n']), \
             patch.object(desktop.time, 'monotonic', side_effect=[0, 1, 31]), \
             patch.object(desktop.time, 'sleep'):
            with self.assertRaisesRegex(RuntimeError, 'within 30 seconds'):
                manager.route(self.process, self.root, self.log)
        self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())

    def test_explicit_current_rechecks_sleep_after_discovery_and_rejects_malformed_aerospace(self):
        self.display = 'asleep'
        manager = desktop.prepare({'options': {'desktop_mode': 'current'}})
        self.rows = ''
        self.display = 'awake'
        with patch.object(desktop.time, 'monotonic', side_effect=[0, 31]):
            with self.assertRaisesRegex(RuntimeError, 'within 30 seconds'):
                manager.route(self.process, self.root, self.log)
        with patch.object(desktop.subprocess, 'run', return_value=SimpleNamespace(stdout='invalid')):
            with self.assertRaisesRegex(RuntimeError, 'malformed version'):
                desktop.prepare({})
        self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())

    def test_foreign_window_or_foreign_handshake_is_never_mutated_or_acknowledged(self):
        for row, marker in [('789|999|C\n', 'pid=123 glfw=456'), ('789|123|C\n', 'pid=999 glfw=456')]:
            with self.subTest(row=row, marker=marker):
                self.rows = row
                self.log.write_text('[QUEUE_TEST] WINDOW_ROUTING_READY ' + marker + '\n')
                with self.assertRaisesRegex(RuntimeError, 'owned client PID'):
                    desktop.prepare({}).route(self.process, self.root, self.log)
                self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())
        self.assertFalse(any(argv[0] == 'layout' for argv in self.commands))

    def test_move_failure_does_not_release_window_gate(self):
        self.fail_move = True
        with self.assertRaises(RuntimeError):
            desktop.prepare({}).route(self.process, self.root, self.log)
        self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())

    def test_exited_process_and_unmanaged_window_timeout_do_not_release_gate(self):
        manager = desktop.prepare({})
        dead = SimpleNamespace(pid=123, poll=lambda: -11)
        with self.assertRaisesRegex(RuntimeError, 'exited'):
            manager.route(dead, self.root, self.log)
        self.rows = ''
        with patch.object(desktop.time, 'monotonic', side_effect=[0, 31]):
            with self.assertRaisesRegex(RuntimeError, 'within 30 seconds'):
                manager.route(self.process, self.root, self.log)
        self.assertFalse((self.root / 'Lua/test-window-routed.txt').exists())

    def test_missing_replaced_or_moved_window_is_rejected_even_while_watching(self):
        self.display = 'asleep'
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

    def test_agent_is_required_and_stale_acknowledgement_is_rejected(self):
        manager = desktop.prepare({})
        with self.assertRaisesRegex(RuntimeError, 'agent is missing'):
            manager.arguments(self.root, self.root)
        (self.root / 'test-window-agent.jar').touch()
        args = manager.arguments(self.root, self.root)
        self.assertTrue(args[0].startswith('-javaagent:'))
        (self.root / 'Lua/test-window-routed.txt').write_text('old\n')
        with self.assertRaisesRegex(RuntimeError, 'already exists'):
            manager.arguments(self.root, self.root)


class DisplayStateTests(unittest.TestCase):
    def probe(self, states, *, error=0, counts=None):
        def online(maximum, ids, count):
            count._obj.value = counts.pop(0) if counts else len(states)
            if ids is not None:
                for index, value in enumerate(list(states)[:maximum]):
                    ids[index] = value
            return error
        graphics = SimpleNamespace(CGGetOnlineDisplayList=Mock(side_effect=online),
                                   CGDisplayIsAsleep=Mock(side_effect=lambda value: states[value]))
        with patch.object(desktop.sys, 'platform', 'darwin'), patch.object(desktop.ctypes, 'CDLL', return_value=graphics):
            return desktop.display_state()

    def test_all_online_displays_must_be_asleep(self):
        asleep = self.probe({1: True, 2: True})
        self.assertEqual(asleep, {'state': 'asleep', 'displays': [{'id': 1, 'asleep': True}, {'id': 2, 'asleep': True}]})
        self.assertEqual(self.probe({1: True, 2: False})['state'], 'awake')
        self.assertEqual(self.probe({1: False})['state'], 'awake')

    def test_no_online_displays_api_errors_invalid_ids_and_topology_changes_are_unknown(self):
        self.assertEqual(self.probe({})['state'], 'unknown')
        self.assertEqual(self.probe({1: True}, error=1000)['state'], 'unknown')
        self.assertEqual(self.probe({0: True})['state'], 'unknown')
        self.assertEqual(self.probe({1: True}, counts=[1, 2])['state'], 'unknown')
        self.assertEqual(self.probe({1: True}, counts=[1, 0])['state'], 'unknown')

    def test_unavailable_coregraphics_and_non_macos_are_unknown(self):
        with patch.object(desktop.sys, 'platform', 'darwin'), patch.object(desktop.ctypes, 'CDLL', side_effect=OSError('unavailable')):
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
