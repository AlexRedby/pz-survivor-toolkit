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
        self.fail_move = False
        self.moved = False
        self.commands = []
        self.binary = patch.object(desktop.shutil, 'which', return_value='/aerospace')
        self.binary.start()
        self.addCleanup(self.binary.stop)
        self.cli = patch.object(desktop.subprocess, 'run', side_effect=self.command)
        self.cli.start()
        self.addCleanup(self.cli.stop)

    def command(self, argv, **kwargs):
        self.commands.append(argv[1:])
        if argv[1] == '--version':
            value = '0.21.3-Beta'
        elif argv[1] == 'list-workspaces':
            value = self.visible
        elif argv[1] == 'list-windows' and '--pid' in argv:
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
