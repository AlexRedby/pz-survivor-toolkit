"""Host selection, child identity and raw log separation are fail-closed."""
from pathlib import Path
import sys
import io
from types import SimpleNamespace
from unittest.mock import patch
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import coop, report


class CoopTests(unittest.TestCase):
    def test_host_requires_mp_and_allows_sealed_templates(self):
        self.assertFalse(coop.enabled({'kind': 'mp'}))
        self.assertTrue(coop.enabled({'kind': 'mp', 'options': {'mp_host': True}}))
        self.assertTrue(coop.enabled({'kind': 'mp', 'options': {'mp_host': True, 'world_template': '/sealed'}}))
        for selection in ({'kind': 'sp', 'options': {'mp_host': True}},
                          {'kind': 'mp', 'options': {'mp_host': 1}},
                          {'kind': 'mp', 'options': {'mp_host': True, 'seed_run': '/old'}},
                          {'kind': 'mp', 'options': {'mp_host': True, 'startup_connection': {'username': 'other'}}}):
            with self.subTest(selection=selection), self.assertRaises(ValueError):
                coop.enabled(selection)

    def test_host_graceful_save_requires_exact_child_exit_acknowledgement(self):
        owner = SimpleNamespace(pid=11, poll=lambda: None, stdin=io.StringIO())
        result = coop.save_host(owner, 22, lambda: '[QUEUE_TEST] HOST_SAVED_EXIT pid=22 exit=0\n')
        self.assertEqual({'pid': 22, 'exit_code': 0}, result)
        self.assertEqual('QUEUE_HOST_SAVE_QUIT\n', owner.stdin.getvalue())
        for text in ('[QUEUE_TEST] HOST_SAVED_EXIT pid=99 exit=0\n',
                     '[QUEUE_TEST] HOST_SAVED_EXIT pid=22 exit=1\n',
                     '[QUEUE_TEST] HOST_SAVED_EXIT pid=22 exit=0\n' * 2,
                     '[QUEUE_TEST] FAIL host save child still alive\n',
                     '[QUEUE_TEST] HOST_SAVED_EXIT pid=22 exit=0\n[QUEUE_TEST] FAIL host save later failure\n'):
            with self.subTest(text=text), self.assertRaises(RuntimeError):
                coop.save_host(owner, 22, lambda: text)
        with patch.object(coop.time, 'monotonic', side_effect=[0, 36]):
            with self.assertRaisesRegex(RuntimeError, 'timed out'):
                coop.save_host(owner, 22, lambda: '')
        owner.poll = lambda: 0
        with self.assertRaisesRegex(RuntimeError, 'live owner'):
            coop.save_host(owner, 22, lambda: '')

    def test_child_requires_unique_actual_owner(self):
        self.assertEqual(22, coop.child('[QUEUE_TEST] HOST_CHILD pid=22 parent=11\n', 11))
        for text in ('', '[QUEUE_TEST] HOST_CHILD pid=22 parent=99\n',
                     '[QUEUE_TEST] HOST_CHILD pid=11 parent=11\n',
                     '[QUEUE_TEST] HOST_CHILD pid=22 parent=11\n' * 2):
            with self.subTest(text=text), self.assertRaises(RuntimeError):
                coop.child(text, 11)

    def test_loader_quotes_one_agent_and_rejects_unrepresentable_input(self):
        value = coop.loader_options('-javaagent:/game path/ZombieBuddy.jar=config_dir=/own path/zombie-buddy')
        self.assertEqual(1, value.count('-javaagent:'))
        self.assertTrue(value.startswith('"-javaagent:'))
        for bad in ('a"b', 'a\nb', 'a\rb'):
            with self.assertRaises(ValueError):
                coop.loader_options(bad)

    def test_host_logs_preserve_full_server_and_archived_client_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            logs = root / 'client1/Logs'
            (logs / 'logs_old').mkdir(parents=True)
            client = logs / 'logs_old/old_DebugLog.txt'
            server = logs / 'new_DebugLog-server.txt'
            client.write_text('client error\n'); server.write_text('server error\n')
            (root / 'client1/coop-console.txt').write_text('full server console\n')
            coop.mirror_logs(root)
            self.assertEqual('full server console\n', (root / 'server-launch.log').read_text())
            self.assertIn(client, report.log_paths(root, 'client1'))
            self.assertNotIn(server, report.log_paths(root, 'client1'))
            copied = root / 'server/Logs/new_DebugLog-server.txt'
            self.assertIn(copied, report.log_paths(root, 'server'))
            self.assertEqual(server.read_bytes(), copied.read_bytes())


if __name__ == '__main__':
    unittest.main()
