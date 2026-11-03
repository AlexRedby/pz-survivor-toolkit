"""Exercise Windows Host failure routing with owned-job APIs replaced by fakes."""
from contextlib import ExitStack, nullcontext
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import windows


class WindowsFixtureFailureTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.cache = self.root / 'client1'
        (self.cache / 'Lua').mkdir(parents=True)
        self.token = 'a' * 32
        source = self.cache / 'mods/GeneratedFixture/42/media/lua/client/ZZFixture.lua'
        source.parent.mkdir(parents=True)
        source.write_text('local fixture = true\n')
        (self.cache / 'mods/GeneratedFixture/42/mod.info').write_text('name=Generated fixture\nid=GeneratedFixture\n')
        self.selection = {'suite': 'startup', 'kind': 'mp', 'mods': [], 'clients': 1,
                          'timeout_seconds': 5, 'ports': [16761, 16762], 'options': {'mp_host': True}}
        self.runtime = {'game': str(self.root / 'game'), 'java': 'fake-java',
                        'fixture': {'mods': ['GeneratedFixture'], 'preflight': {
                            'version': 2, 'token': self.token, 'roles': ['client1'], 'setup_timeout_seconds': 120}}, 'host_cache': str(self.cache),
                        'roles': {'client1': {'cache': str(self.cache), 'classes': str(self.cache / 'classes')},
                                  'server': {'cache': str(self.root / 'server')}}}
        for name, value in (('selection.json', self.selection), ('runtime.json', self.runtime),
                            ('game-inputs.json', {'game': self.runtime['game'],
                                                  'trees': {'media/lua': {}, 'media/scripts': {}}})):
            (self.root / name).write_text(json.dumps(value))
        self.normal = 'LOG : Lua > [QUEUE_TEST] HOST_CHILD pid=124 parent=123\n'
        self.error = ('Oct 29, 2026 4:52:47 PM zombie.Lua.LuaManager RunLuaInternal\n'
                      'SEVERE: attempt to index a nil value\n'
                      'Oct 29, 2026 4:52:47 PM zombie.Lua.LuaManager RunLuaInternal\n'
                      'SEVERE: at ZZFixture.lua:12\nLOG : Lua > next record\n')
        self.process = SimpleNamespace(pid=123, _handle=567, returncode=None,
                                       poll=Mock(return_value=None), kill=Mock())

        def wait(**kwargs):
            self.process.returncode = 0
            return 0

        self.process.wait = Mock(side_effect=wait)
        names = ('CreateMutexW', 'WaitForSingleObject', 'CreateJobObjectW', 'AssignProcessToJobObject',
                 'TerminateJobObject', 'CloseHandle', 'ReleaseMutex', 'SetInformationJobObject',
                 'QueryInformationJobObject', 'GlobalMemoryStatusEx')
        self.kernel = SimpleNamespace(**{name: Mock(return_value=True) for name in names})
        self.kernel.CreateMutexW.return_value = 41
        self.kernel.WaitForSingleObject.return_value = 0
        self.kernel.CreateJobObjectW.return_value = 42

        def memory(pointer):
            pointer._obj.total = 32 * 1024**3
            pointer._obj.available = 24 * 1024**3
            return True

        self.kernel.GlobalMemoryStatusEx.side_effect = memory
        self.ntdll = SimpleNamespace(NtResumeProcess=Mock(return_value=0))

    def run_fake(self, client, server='', complete=True, *, setup_ready=True, advance=None):
        client += '[QUEUE_PREFLIGHT] ' + json.dumps({'event': 'ready', 'token': self.token, 'role': 'client1'}) + '\n'
        expected = [client]
        def popen(command, **kwargs):
            kwargs['stdout'].write(client)
            kwargs['stdout'].flush()
            return self.process

        def mirror(root):
            if server:
                (root / 'server-launch.log').write_text(server)

        def sleep(seconds):
            if advance is not None:
                advance(seconds)
            if setup_ready and (self.cache / 'Lua/queue-preflight-setup.txt').is_file() and len(expected) == 1:
                receipt = '[QUEUE_PREFLIGHT] ' + json.dumps({'event': 'setup-ready', 'token': self.token, 'role': 'client1'}) + '\n'
                with (self.root / 'client1-launch.log').open('a') as stream:
                    stream.write(receipt)
                expected.append(receipt)

        adapter = SimpleNamespace(complete=Mock(return_value=complete))
        budget = {'memory': 1024**3, 'instances': 2, 'heap_mib': 2048}
        with ExitStack() as stack:
            patches = (
                patch.object(windows.ctypes, 'WinDLL', create=True,
                             side_effect=lambda name, **kwargs: self.kernel if name == 'kernel32' else self.ntdll),
                patch.object(windows, 'verify_manifest', return_value=[]),
                patch('queue_checks.runner._verify_live_inputs'),
                patch.object(windows.admission, 'budget', return_value=budget),
                patch.object(windows.admission, 'require_disk'),
                patch.object(windows.admission, '_udp', return_value=nullcontext()),
                patch.object(windows, 'loader_agent', return_value='-javaagent:owned.jar'),
                patch.object(windows.subprocess, 'Popen', side_effect=popen),
                patch.object(windows.coop, 'mirror_logs', side_effect=mirror),
                patch.object(windows.adapters, 'get', return_value=adapter),
                patch.object(windows.time, 'sleep', side_effect=sleep),
            )
            for context in patches:
                stack.enter_context(context)
            execution = windows.run(self.root)
        self.assertEqual(json.loads((self.root / 'execution.json').read_text()), execution)
        self.kernel.AssignProcessToJobObject.assert_called_once()
        self.kernel.TerminateJobObject.assert_called_once_with(42, 0)
        self.kernel.QueryInformationJobObject.assert_called_once()
        self.kernel.ReleaseMutex.assert_called_once_with(41)
        self.assertEqual([call.args[0] for call in self.kernel.CloseHandle.call_args_list], [42, 41])
        self.process.wait.assert_called_once_with(timeout=15)
        self.process.kill.assert_not_called()
        self.assertEqual(execution['host_cleanup'], {'remaining_pids': [], 'active_job_processes': 0})
        self.assertEqual((self.root / 'client1-launch.log').read_text(), ''.join(expected))
        if server:
            self.assertEqual((self.root / 'server-launch.log').read_text(), server)
        return execution, adapter

    def test_client_fixture_failure_wins_over_adapter_completion_and_cleans_owned_job(self):
        result, adapter = self.run_fake(self.normal + self.error)
        self.assertEqual(result['status'], 'failed')
        self.assertEqual(result['fixture_load_error']['role'], 'client1')
        self.assertEqual(result['fixture_load_error']['phase'], 'execution')
        adapter.complete.assert_not_called()

    def test_host_server_fixture_failure_preserves_both_logs_and_cleans_owned_job(self):
        result, adapter = self.run_fake(self.normal, self.error)
        self.assertEqual(result['status'], 'failed')
        self.assertEqual(result['fixture_load_error']['role'], 'server')
        self.assertEqual(result['fixture_load_error']['kind'], 'runtime')
        adapter.complete.assert_not_called()

    def test_normal_completion_retains_child_evidence_and_owned_job_cleanup(self):
        result, adapter = self.run_fake(self.normal)
        self.assertEqual(result['status'], 'completed')
        self.assertEqual(result['processes']['server']['pid'], 124)
        self.assertNotIn('fixture_load_error', result)
        adapter.complete.assert_called_once()

    def test_execution_seal_follows_final_owned_job_cleanup_and_log_mirror(self):
        def seal(root):
            value = json.loads((root / 'execution.json').read_text())
            self.assertEqual('completed', value['status'])
            self.assertEqual(0, value['host_cleanup']['active_job_processes'])
            text = (root / 'client1-launch.log').read_text()
            self.assertTrue(text.startswith(self.normal))
            self.assertIn('"event": "setup-ready"', text)
            self.kernel.TerminateJobObject.assert_called_once()
            self.kernel.QueryInformationJobObject.assert_called_once()
            self.assertEqual([call.args[0] for call in self.kernel.CloseHandle.call_args_list], [42, 41])
        with patch.object(windows.provenance, 'seal_execution', side_effect=seal) as sealed:
            self.run_fake(self.normal)
        sealed.assert_called_once_with(self.root.resolve())

    def test_missing_setup_tick_times_out_before_scenario_and_preserves_owned_cleanup(self):
        self.selection['options']['fixture_setup_timeout_seconds'] = 2
        self.runtime['fixture']['preflight']['setup_timeout_seconds'] = 2
        self.selection['timeout_seconds'] = 90
        for name, value in (('selection.json', self.selection), ('runtime.json', self.runtime)):
            (self.root / name).write_text(json.dumps(value))
        now = [0]
        def advance(seconds):
            now[0] += seconds
        def capture(root, runtime, processes, execution):
            self.assertIs(processes['client1'], self.process)
            self.process.wait.assert_not_called()
        with patch.object(windows.time, 'monotonic', side_effect=lambda: now[0]), \
                patch.object(windows.setup_diagnostics, 'capture', side_effect=capture) as diagnosed:
            result, adapter = self.run_fake(self.normal, setup_ready=False, advance=advance)
        self.assertEqual('failed', result['status'])
        self.assertEqual('fixture-setup', result['setup_failure']['kind'])
        self.assertEqual(2, result['setup_failure']['evidence']['elapsed_seconds'])
        self.assertFalse((self.cache / 'Lua/queue-preflight-release.txt').exists())
        self.assertEqual(2, now[0])
        adapter.complete.assert_not_called()
        diagnosed.assert_called_once()

    def test_foreign_require_warning_does_not_preempt_completion(self):
        warning = 'WARN : Lua at Lua((MOD:Foreign)).Foreign.lua> require("Missing") failed\n'
        result, adapter = self.run_fake(self.normal + warning)
        self.assertEqual(result['status'], 'completed')
        self.assertNotIn('fixture_load_error', result)
        adapter.complete.assert_called_once()

    def test_preflight_failure_preempts_completion_and_cleans_owned_job(self):
        receipt = '[QUEUE_PREFLIGHT] ' + json.dumps({'event': 'failed', 'token': self.token, 'role': 'client1',
                                                     'phase': 'preflight', 'reason': 'viewport mismatch'}) + '\n'
        result, adapter = self.run_fake(self.normal + receipt)
        self.assertEqual(result['status'], 'failed')
        self.assertEqual(result['setup_failure']['kind'], 'client-preflight')
        self.assertEqual(result['setup_failure']['role'], 'client1')
        self.assertEqual(result['setup_failure']['reason'], 'viewport mismatch')
        self.assertFalse((self.cache / 'Lua/queue-preflight-setup.txt').exists())
        adapter.complete.assert_not_called()


if __name__ == '__main__':
    unittest.main()
