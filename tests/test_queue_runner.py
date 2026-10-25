import io
import json
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from queue_checks import runner, admission, coop


class Process:
    def __init__(self, pid):
        self.pid, self.returncode = pid, None

    def poll(self):
        return self.returncode

    def wait(self, timeout=None):
        self.returncode = -15
        return self.returncode

    def terminate(self):
        self.returncode = -15

    def kill(self):
        self.returncode = -9


class NativeRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        for context in (
                patch.object(runner.desktop, 'require_gui_access', return_value={'state': 'awake', 'displays': [{'id': 1, 'asleep': False}]}),
                patch.object(runner.glfw, 'arguments', return_value=['-Dorg.lwjgl.glfw.libname=/owned/native/libglfw.dylib'])):
            context.start()
            self.addCleanup(context.stop)
        disk = patch.object(admission.shutil, 'disk_usage', return_value=SimpleNamespace(free=100 * 1024**3))
        disk.start()
        self.addCleanup(disk.stop)
        self.root = Path(self.temp.name)
        (self.root / "client1").mkdir()
        (self.root / "client1/options.ini").write_text("voiceEnable=false\n")
        self.selection = {"suite": "health", "kind": "sp", "mods": [], "cases": ["nativeStop"], "timeout_seconds": 10}
        self.runtime = {"game": str(self.root), "java": "/fake/java", "glfw": {'compatibility': 'test input'}, "roles": {"client1": {"cache": str(self.root / "client1"), "classes": str(self.root / "classes")}}}
        (self.root / "selection.json").write_text(json.dumps(self.selection))
        (self.root / "runtime.json").write_text(json.dumps(self.runtime))
        self.seal_settings()
        self.desktop = SimpleNamespace(evidence={}, arguments=lambda *args: [], route=lambda *args: None, check=lambda *args: None)
        self.commands = []
        self.processes = []
        self.streams = []
        self.handlers = {}
        self.signal_changes = []
        self.complete = True
        self.sample_error = None
        self.host_save = lambda process, pid, read_text: {'pid': pid, 'exit_code': 0}
        self.manifest_errors = []
        self.snapshot = {'total_memory': 128 * 1024**3, 'available_memory': 100 * 1024**3,
                         'cpu_count': 64, 'processes': []}
        self.content = '[QUEUE_CHECK] {"event":"case","id":"nativeStop"}\n[QUEUE_CHECK] {"event":"complete","failed":0}\n'

    def popen(self, command, **kwargs):
        self.commands.append(command)
        process = Process(100 + len(self.processes))
        self.processes.append(process)
        if "stdout" in kwargs and self.complete:
            self.streams.append(kwargs["stdout"])
            kwargs["stdout"].write(self.content)
            kwargs["stdout"].flush()
        return process

    def signal(self, signum, handler):
        self.handlers[signum] = handler
        self.signal_changes.append((signum, handler))

    def seal_settings(self, add_only=False):
        expected = json.loads((self.root / 'initial-settings.json').read_text()) if add_only else {}
        if self.selection['kind'] == 'mp':
            sandbox = self.root / 'server/Server' / (self.runtime['server_name'] + '_SandboxVars.lua')
            if not sandbox.exists():
                sandbox.write_text('SandboxVars={}\n')
        for role in self.runtime['roles']:
            for path in [self.root / role / 'options.ini', *sorted((self.root / role / 'Server').glob('*'))]:
                if path.is_file():
                    name = path.relative_to(self.root).as_posix()
                    if not add_only or name not in expected:
                        expected[name] = path.read_text()
        (self.root / 'initial-settings.json').write_text(json.dumps(expected))

    def invoke(self, collisions="", sleep=None, settings=True):
        if settings:
            self.seal_settings(add_only=True)
        def kill_group(pid, sig):
            if sig == 0:
                raise ProcessLookupError
        with patch.object(runner.sys, "platform", "darwin"), patch.object(runner, "LOCK", self.root / "lock"), \
             patch.object(runner, "verify_manifest", side_effect=lambda *args: self.manifest_errors), \
             patch.object(admission, "STATE", self.root / "admission-state"), \
             patch.object(admission.host, "sample", side_effect=self.sample_error, return_value=dict(self.snapshot,
                 processes=[{'pid': int(line.split()[0]), 'rss': 0, 'cpu': 0, 'game': True, 'command': line}
                            for line in collisions.splitlines() if line] or self.snapshot['processes'])), \
             patch.object(runner.desktop, "prepare", return_value=self.desktop), \
             patch.object(coop, 'save_host', side_effect=self.host_save), \
             patch.object(runner.subprocess, "Popen", side_effect=self.popen), \
             patch.object(runner.os, "killpg", side_effect=kill_group) as kill, patch.object(runner.signal, "signal", side_effect=self.signal), \
             patch.object(runner.time, "sleep", side_effect=sleep):
            result = runner.run(self.root, resource_wait=0)
            return result, kill.call_args_list

    def test_completed_native_process_gets_novoip_and_only_own_pid_stops(self):
        result, kills = self.invoke()
        self.assertEqual(result["status"], "completed")
        self.assertIn("-novoip", self.commands[1])
        self.assertIn('-Dorg.lwjgl.glfw.libname=/owned/native/libglfw.dylib', self.commands[1])
        self.assertEqual([call.args[0] for call in kills], [101])
        self.assertEqual(result["processes"]["client1"]["exit_code"], -15)

    def test_unavailable_gui_access_does_not_start_caffeinate_or_java(self):
        with patch.object(runner.desktop, 'require_gui_access', side_effect=RuntimeError('GUI access unavailable; outside the sandbox')):
            with self.assertRaisesRegex(RuntimeError, 'outside the sandbox'):
                self.invoke()
        self.assertEqual(self.commands, [])

    def test_unsealed_glfw_input_does_not_start_caffeinate_or_java(self):
        with patch.object(runner.glfw, 'arguments', side_effect=ValueError('prepare a fresh run')):
            with self.assertRaisesRegex(ValueError, 'fresh run'):
                self.invoke()
        self.assertEqual(self.commands, [])

    def test_idle_guard_preserves_display_sleep_and_cleans_up_owned_process(self):
        popen = self.popen
        def launch(command, **kwargs):
            process = popen(command, **kwargs)
            if command[0] == '/usr/bin/caffeinate':
                process.terminate = Mock(wraps=process.terminate)
                process.wait = Mock(wraps=process.wait)
                process.kill = Mock(wraps=process.kill)
            return process
        self.popen = launch
        result, kills = self.invoke()
        self.assertEqual(result['status'], 'completed')
        self.assertEqual(self.commands[0], ['/usr/bin/caffeinate', '-i', '-w', str(runner.os.getpid())])
        guard = self.processes[0]
        guard.terminate.assert_called_once_with()
        guard.wait.assert_called_once_with(timeout=5)
        guard.kill.assert_not_called()
        self.assertEqual(guard.returncode, -15)
        self.assertEqual([call.args[0] for call in kills], [101])

    def test_crash_after_completion_marker_is_failed_after_cleanup(self):
        original_popen = self.popen
        def crash(command, **kwargs):
            process = original_popen(command, **kwargs)
            if 'stdout' in kwargs:
                process.returncode = -11
            return process
        with patch.object(self, 'popen', side_effect=crash):
            result, kills = self.invoke()
        self.assertEqual(result['status'], 'failed')
        self.assertIn('unexpected process exit code -11', result['error'])
        self.assertEqual(result['processes']['client1']['exit_code'], -11)
        self.assertFalse(kills)

    def test_manual_session_waits_for_user_exit_and_releases_without_killing_game(self):
        self.runtime['fixture'] = {'manual': True}
        (self.root / 'runtime.json').write_text(json.dumps(self.runtime))
        self.complete = False
        waits = []
        def user_exit(seconds):
            waits.append(seconds)
            self.processes[1].returncode = 0
        result, kills = self.invoke(sleep=user_exit)
        self.assertEqual(waits, [2])
        self.assertEqual(result['status'], 'completed')
        self.assertTrue(result['manual'])
        self.assertEqual(result['processes']['client1']['exit_code'], 0)
        self.assertFalse(kills)

    def test_manual_crash_is_not_successful_user_exit(self):
        self.runtime['fixture'] = {'manual': True}
        (self.root / 'runtime.json').write_text(json.dumps(self.runtime))
        self.complete = False
        def crash(seconds): self.processes[1].returncode = 1
        result, _ = self.invoke(sleep=crash)
        self.assertEqual(result['status'], 'failed')


    def test_cart_pad_flag_is_typed_and_overrides_inherited_environment(self):
        self.runtime['roles']['client1']['env'] = {'PZ_CART_TEST_PAD': 'false', 'PZ_CART_RUNTIME_FILE': '/owned/runtime.lua'}
        (self.root / 'runtime.json').write_text(json.dumps(self.runtime))
        environments = []
        popen = self.popen
        def capture(command, **kwargs):
            if 'env' in kwargs: environments.append(kwargs['env'])
            return popen(command, **kwargs)
        self.popen = capture
        with patch.dict(runner.os.environ, {'PZ_CART_TEST_PAD': 'true'}):
            result, _ = self.invoke()
        self.assertEqual(result['status'], 'completed')
        self.assertEqual(environments[0]['PZ_CART_TEST_PAD'], 'false')
        self.assertEqual(environments[0]['PZ_CART_RUNTIME_FILE'], '/owned/runtime.lua')

    def test_non_boolean_cart_pad_flag_is_rejected_before_game_launch(self):
        self.runtime['roles']['client1']['env'] = {'PZ_CART_TEST_PAD': '/arbitrary/path'}
        (self.root / 'runtime.json').write_text(json.dumps(self.runtime))
        result, _ = self.invoke()
        self.assertIn('Invalid fixture-owned client environment', result['error'])
        self.assertFalse(result['processes'])

    def test_cart_pad_flag_does_not_admit_unknown_environment_keys(self):
        self.runtime['roles']['client1']['env'] = {'PZ_CART_TEST_PAD': 'true', 'JAVA_TOOL_OPTIONS': '/untrusted'}
        (self.root / 'runtime.json').write_text(json.dumps(self.runtime))
        result, _ = self.invoke()
        self.assertIn('Invalid fixture-owned client environment', result['error'])
        self.assertFalse(result['processes'])

    def test_inherited_inventory_probe_flag_is_stripped_from_actual_sp_launch(self):
        environments = []
        popen = self.popen
        def capture(command, **kwargs):
            if 'env' in kwargs: environments.append(kwargs['env'])
            return popen(command, **kwargs)
        self.popen = capture
        with patch.dict(runner.os.environ, {'PZ_CART_INVENTORY_EQUIP': 'true'}):
            result, _ = self.invoke()
        self.assertEqual('completed', result['status'])
        self.assertTrue(environments)
        self.assertTrue(all('PZ_CART_INVENTORY_EQUIP' not in env for env in environments))

    def test_basement_hall_cache_environment_requires_exact_suite_and_owned_role_cache(self):
        self.selection.update(mode='toolkit', languages=['EN'],
                              mods=['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit'],
                              options={'ffmpeg': sys.executable, 'ffprobe': sys.executable})
        original_popen = self.popen
        environments = []
        def launch(command, **kwargs):
            if 'env' in kwargs:
                environments.append(kwargs['env'])
            return original_popen(command, **kwargs)
        self.popen = launch
        base = self.root
        for index, (suite, target, valid) in enumerate([('basement-hall', 'owned', True), ('health', 'owned', False),
                                                       ('basement-hall', 'other', False),
                                                       ('basement-hall', 'relative', False)]):
            self.root = base / str(index)
            (self.root / 'client1').mkdir(parents=True)
            (self.root / 'client1/options.ini').write_text('voiceEnable=false\n')
            cache = str(self.root / 'client1')
            value = cache if target == 'owned' else 'client1' if target == 'relative' else str(self.root / 'other')
            self.runtime['roles']['client1']['cache'] = cache
            with self.subTest(suite=suite, value=value):
                self.selection.update(suite=suite, cases=['fresh'])
                self.runtime['roles']['client1']['env'] = {'PZ_BASEMENT_HALL_CACHE': value}
                for name, data in [('selection', self.selection), ('runtime', self.runtime)]:
                    (self.root / (name + '.json')).write_text(json.dumps(data))
                self.seal_settings()
                self.content = '[BASEMENT_HALL] COMPLETE case=fresh\n'
                result, _ = self.invoke()
                self.assertEqual('completed' if valid else 'failed', result['status'])
                if valid:
                    self.assertEqual(cache, environments[-1]['PZ_BASEMENT_HALL_CACHE'])
                else:
                    self.assertEqual({}, result['processes'])
                    self.assertIn('Invalid fixture-owned client environment', result['error'])

    def test_vehicle_lights_cache_environment_requires_exact_suite_and_owned_role_cache(self):
        self.selection.update(mode='toolkit', languages=['EN'], clients=1,
                              mods=['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit', 'NepHighBeams', 'ReverseDriveLights'],
                              options={'ffmpeg': sys.executable, 'ffprobe': sys.executable})
        original_popen = self.popen
        environments = []
        def launch(command, **kwargs):
            if 'env' in kwargs:
                environments.append(kwargs['env'])
            return original_popen(command, **kwargs)
        self.popen = launch
        base = self.root
        for index, (suite, target, valid) in enumerate([('vehicle-lights', 'owned', True), ('health', 'owned', False),
                                                       ('vehicle-lights', 'other', False),
                                                       ('vehicle-lights', 'relative', False)]):
            self.root = base / str(index)
            (self.root / 'client1').mkdir(parents=True)
            (self.root / 'client1/options.ini').write_text('voiceEnable=false\n')
            cache = str(self.root / 'client1')
            value = cache if target == 'owned' else 'client1' if target == 'relative' else str(self.root / 'other')
            self.runtime['roles']['client1']['cache'] = cache
            with self.subTest(suite=suite, value=value):
                self.selection.update(suite=suite, cases=['road'])
                self.runtime['roles']['client1']['env'] = {'PZ_LIGHTS_TEST_CACHE': value}
                for name, data in [('selection', self.selection), ('runtime', self.runtime)]:
                    (self.root / (name + '.json')).write_text(json.dumps(data))
                self.seal_settings()
                self.content = '[VEHICLE_LIGHTS] COMPLETE road\n'
                result, _ = self.invoke()
                self.assertEqual('completed' if valid else 'failed', result['status'])
                if valid:
                    self.assertEqual(cache, environments[-1]['PZ_LIGHTS_TEST_CACHE'])
                else:
                    self.assertEqual({}, result['processes'])
                    self.assertIn('Invalid fixture-owned client environment', result['error'])

    def prepare_host(self, proof='[QUEUE_TEST] HOST_CHILD pid=555 parent=101\n'):
        self.selection.update(kind='mp', clients=1, ports=[], mods=['ZombieBuddy'], options={'mp_host': True})
        self.runtime.update(server_name='owned')
        server = self.root / 'server'
        (server / 'Server').mkdir(parents=True)
        (server / 'options.ini').write_text('voiceEnable=false\n')
        (server / 'Server/owned.ini').write_text('VoiceEnable=false\n')
        (server / 'Server/owned_SandboxVars.lua').write_text('SandboxVars={}\n')
        self.runtime['roles']['server'] = {'cache': str(server)}
        coop.stage(self.root, self.runtime)
        for name, value in [('selection', self.selection), ('runtime', self.runtime)]:
            (self.root / (name + '.json')).write_text(json.dumps(value))
        self.content += proof
        (self.root / 'client1/coop-console.txt').write_text('[QUEUE_TEST] SERVER_READY\n')

    def test_host_launches_owner_once_inherits_loader_and_records_native_child(self):
        self.prepare_host()
        environments = []
        popen = self.popen
        def launch(command, **kwargs):
            if 'env' in kwargs:
                environments.append(kwargs['env'])
            return popen(command, **kwargs)
        self.popen = launch
        with patch.dict(runner.os.environ, {'PZ_CART_INVENTORY_EQUIP': 'true'}):
            result, kills = self.invoke()
        self.assertEqual('completed', result['status'])
        self.assertEqual(2, len(self.commands))  # display guard + one real Host owner
        command = self.commands[-1]
        self.assertNotIn('zombie.network.GameServer', command)
        self.assertIn('ToolkitSmokeLauncher', command)
        self.assertIn('-novoip', command)
        self.assertFalse(any(arg.startswith('-javaagent:') for arg in command))
        self.assertEqual(1, environments[0]['JDK_JAVA_OPTIONS'].count('-javaagent:'))
        self.assertIn(str(self.root / 'client1/zombie-buddy'), environments[0]['JDK_JAVA_OPTIONS'])
        self.assertNotIn('PZ_CART_INVENTORY_EQUIP', environments[0])
        self.assertEqual({'pid': 555, 'parent_role': 'client1', 'cache': str((self.root / 'client1').resolve()), 'exit_code': 0}, result['processes']['server'])
        self.assertEqual([101], [call.args[0] for call in kills if call.args[1] != 0])
        self.assertEqual('[QUEUE_TEST] SERVER_READY\n', (self.root / 'server-launch.log').read_text())

    def test_host_save_failure_is_failed_even_after_completed_fixture_and_still_cleans_group(self):
        self.prepare_host()
        def fail(*args): raise RuntimeError('child did not acknowledge native save')
        self.host_save = fail
        result, kills = self.invoke()
        self.assertEqual('failed', result['status'])
        self.assertIn('child did not acknowledge', result['error'])
        self.assertNotIn('host_save', result)
        self.assertEqual([101], [call.args[0] for call in kills if call.args[1] != 0])

    def test_host_rejects_unproven_or_duplicated_child_and_still_stops_only_its_group(self):
        self.prepare_host('[QUEUE_TEST] HOST_CHILD pid=999 parent=666\n')
        result, kills = self.invoke()
        self.assertEqual('failed', result['status'])
        self.assertIn('prove one native child', result['error'])
        self.assertEqual([101], [call.args[0] for call in kills if call.args[1] != 0])

    def test_owned_host_group_is_stopped_even_if_parent_already_exited(self):
        process = Process(456)
        process.returncode = 1
        def kill_group(pid, sig):
            if sig == 0:
                raise ProcessLookupError
        with patch.object(runner.os, 'killpg', side_effect=kill_group) as kill:
            runner.stop(process, owned_host_group=True)
        self.assertEqual([(456, signal.SIGTERM), (456, 0)], [call.args for call in kill.call_args_list])

    def test_host_escalates_only_its_original_group_when_child_outlives_owner(self):
        process = Process(456)
        process.returncode = 1
        with patch.object(runner.os, 'killpg') as kill, patch.object(runner.time, 'monotonic', side_effect=[0, 5]):
            runner.stop(process, owned_host_group=True)
        self.assertEqual([(456, signal.SIGTERM), (456, 0), (456, signal.SIGKILL)],
                         [call.args for call in kill.call_args_list])

    def test_low_disk_or_failed_disk_sampling_never_launches(self):
        for error in (None, OSError('disk sampling failed')):
            with self.subTest(error=error), patch.object(admission.shutil, 'disk_usage',
                    return_value=SimpleNamespace(free=1), side_effect=error):
                with self.assertRaisesRegex((RuntimeError, OSError), 'disk'):
                    self.invoke()
            self.assertEqual(self.commands, [])
            self.assertFalse((self.root / 'execution.json').exists())

    def test_disk_budget_is_recorded_with_execution(self):
        result, _ = self.invoke()
        disk = result['resources']['disk']
        self.assertEqual(disk['runtime_bytes'], admission.DISK_PER_ROLE)
        self.assertEqual(disk['copy_bytes'], 0)
        self.assertEqual(disk['required_bytes'], admission.DISK_PER_ROLE + admission.DISK_MARGIN)

    def test_explicit_font_preload_extends_single_client_agent(self):
        self.selection['mods'] = ['ZombieBuddy', 'PZToolkitJavaPatches']
        self.selection['options'] = {'preload_toolkit_fonts': True}
        (self.root / 'selection.json').write_text(json.dumps(self.selection))
        suffix = ',patches_jar=/owned/snapshot/mod.jar:net.alexredby.pztoolkitbootstrap'
        with patch.object(runner, 'font_preload', return_value=suffix) as preload:
            self.invoke()
        agents = [arg for arg in self.commands[-1] if arg.startswith('-javaagent:')]
        self.assertEqual(len(agents), 1)
        self.assertTrue(agents[0].endswith(suffix))
        preload.assert_called_once_with(self.root / 'client1', self.selection)

    def test_unrelated_game_does_not_block_isolated_profile(self):
        result, kills = self.invoke("77 java ToolkitSmokeLauncher -cachedir=/another-run/client1\n")
        self.assertEqual(result['status'], 'completed')
        self.assertEqual([call.args[0] for call in kills], [101])

    def test_same_profile_game_blocks_before_any_launch(self):
        with self.assertRaisesRegex(RuntimeError, "Existing game"):
            self.invoke("77 java ToolkitSmokeLauncher -cachedir=" + str(self.root / 'client1') + "\n")
        self.assertEqual(self.commands, [])

    def test_exiting_child_race_does_not_interrupt_cleanup(self):
        process = Process(456)
        with patch.object(runner.os, "killpg", side_effect=ProcessLookupError):
            runner.stop(process)
        self.assertIsNotNone(process.returncode)

    def test_same_run_cannot_be_reused(self):
        self.invoke()
        count = len(self.commands)
        with self.assertRaisesRegex(ValueError, "already launched"):
            self.invoke()
        self.assertEqual(len(self.commands), count)

    def test_interruption_writes_failure_and_cleans_only_owned_game(self):
        self.complete = False
        result, kills = self.invoke(sleep=KeyboardInterrupt("test interrupt"))
        self.assertEqual(result["status"], "failed")
        self.assertIn("test interrupt", result["error"])
        self.assertEqual([call.args[0] for call in kills], [101])
        self.assertEqual(json.loads((self.root / "execution.json").read_text())["status"], "failed")

    def assert_interrupted_cleanup(self, result, kills):
        self.assertEqual('failed', result['status'])
        self.assertTrue(result['interrupted'])
        self.assertIn('signal ' + str(signal.SIGINT), result['error'])
        self.assertEqual(result, json.loads((self.root / 'execution.json').read_text()))
        self.assertTrue(all(process.returncode is not None for process in self.processes))
        self.assertTrue(all(stream.closed for stream in self.streams))
        self.assertTrue(all(call.args[0] in [process.pid for process in self.processes[1:]] for call in kills))
        self.assertEqual([(sig, signal.getsignal(sig)) for sig in (signal.SIGINT, signal.SIGTERM)], self.signal_changes[-2:])

    def test_sigint_during_server_graceful_wait_finishes_cleanup_and_report(self):
        self.selection.update(kind='mp', ports=[])
        self.runtime.update(server_name='owned')
        server = self.root / 'server'
        (server / 'Server').mkdir(parents=True)
        (server / 'options.ini').write_text('voiceEnable=false\n')
        (server / 'Server/owned.ini').write_text('VoiceEnable=false\n')
        self.runtime['roles']['server'] = {'cache': str(server)}
        (self.root / 'client2').mkdir()
        (self.root / 'client2/options.ini').write_text('voiceEnable=false\n')
        self.runtime['roles']['client2'] = {'cache': str(self.root / 'client2'), 'classes': str(self.root / 'classes')}
        for name, value in [('selection', self.selection), ('runtime', self.runtime)]:
            (self.root / (name + '.json')).write_text(json.dumps(value))
        self.content += '[QUEUE_TEST] SERVER_READY\n'
        popen = self.popen
        def launch(command, **kwargs):
            process = popen(command, **kwargs)
            if 'zombie.network.GameServer' in command:
                process.stdin = io.StringIO()
                wait = process.wait
                def interrupted_wait(timeout):
                    self.assertEqual(30, timeout)
                    self.handlers[signal.SIGINT](signal.SIGINT, None)
                    return wait(timeout)
                process.wait = interrupted_wait
            return process
        self.popen = launch
        unknown = Process(999999)
        result, kills = self.invoke('999999 java unrelated.application.Main\n')
        self.assert_interrupted_cleanup(result, kills)
        self.assertEqual('Native run interrupted by signal ' + str(signal.SIGINT), result['error'])
        self.assertIsNone(unknown.returncode)
        self.assertEqual('save\nquit\n', self.processes[1].stdin.getvalue())

    def test_sigint_during_probe_cleanup_closes_remaining_probes_and_processes(self):
        (self.root / 'client1/Lua').mkdir()
        specs = [{'classpath': '/owned/classes', 'jar': '/owned/probe' + str(index),
                  'ready': '[QUEUE_CHECK]', 'output': '/owned/output' + str(index)} for index in range(2)]
        self.runtime['fixture'] = {'attach': {'client1': specs}}
        (self.root / 'runtime.json').write_text(json.dumps(self.runtime))
        def attach(command, **kwargs):
            if command[-2:] == [specs[0]['jar'], 'stop']:
                self.handlers[signal.SIGINT](signal.SIGINT, None)
        with patch.object(runner.subprocess, 'run', side_effect=attach) as probes:
            result, kills = self.invoke()
        self.assert_interrupted_cleanup(result, kills)
        self.assertEqual([spec['output'] for spec in specs] + ['stop', 'stop'], [call.args[0][-1] for call in probes.call_args_list])
        self.assertEqual(['101'] * 4, [call.args[0][-3] for call in probes.call_args_list])

    def test_failure_starting_guard_still_restores_handlers_and_writes_report(self):
        def fail(command, **kwargs):
            raise OSError('guard unavailable')
        self.popen = fail
        result, kills = self.invoke()
        self.assertEqual('failed', result['status'])
        self.assertIn('guard unavailable', result['error'])
        self.assertEqual([], kills)
        self.assertEqual(result, json.loads((self.root / 'execution.json').read_text()))
        self.assertEqual([(sig, signal.getsignal(sig)) for sig in (signal.SIGINT, signal.SIGTERM)], self.signal_changes[-2:])

    def test_interrupt_while_installing_handler_is_recorded_before_guard_launch(self):
        install = self.signal
        interrupted = False
        def early_signal(signum, handler):
            nonlocal interrupted
            install(signum, handler)
            if not interrupted:
                interrupted = True
                handler(signum, None)
        self.signal = early_signal
        result, kills = self.invoke()
        self.assertEqual([], self.commands)
        self.assertEqual([], kills)
        self.assertTrue(result['interrupted'])
        self.assertEqual(result, json.loads((self.root / 'execution.json').read_text()))
        self.assertEqual((signal.SIGINT, signal.getsignal(signal.SIGINT)), self.signal_changes[-1])

    def test_unresponsive_display_guard_is_killed_with_bounded_wait(self):
        popen = self.popen
        waits = []
        def launch(command, **kwargs):
            process = popen(command, **kwargs)
            if command[0] == '/usr/bin/caffeinate':
                process.terminate = lambda: None
                def delayed_wait(timeout):
                    waits.append(timeout)
                    if len(waits) == 1:
                        raise subprocess.TimeoutExpired(command, timeout)
                    return process.returncode
                process.wait = delayed_wait
            return process
        self.popen = launch
        result, _ = self.invoke()
        self.assertEqual('completed', result['status'])
        self.assertEqual(-9, self.processes[0].returncode)
        self.assertEqual([5, 5], waits)

    def test_stale_legacy_lock_file_does_not_block_admission(self):
        (self.root / 'lock').write_text('stale owner\n')
        result, _ = self.invoke()
        self.assertEqual('completed', result['status'])
        self.assertEqual('stale owner\n', (self.root / 'lock').read_text())
        self.assertEqual(1, result['resources']['budget']['instances'])

    def test_voice_enabled_rejected_before_game_launch(self):
        (self.root / "client1/options.ini").write_text("voiceEnable=true\n")
        self.seal_settings()  # Isolate the independent VOIP guard with a matching prepared input.
        result, kills = self.invoke()
        self.assertEqual(result["status"], "failed")
        self.assertIn("VOIP", result["error"])
        self.assertEqual(len(self.commands), 1)  # Display guard only.
        self.assertEqual(kills, [])

    def test_prelaunch_live_options_and_mp_server_setting_tamper_start_no_process(self):
        self.selection.update(kind='mp', clients=1, ports=[])
        self.runtime.update(server_name='owned')
        server = self.root / 'server'
        (server / 'Server').mkdir(parents=True)
        (server / 'options.ini').write_text('voiceEnable=false\n')
        (server / 'Server/owned.ini').write_text('VoiceEnable=false\nMap=Muldraugh\n')
        (server / 'Server/owned_SandboxVars.lua').write_text('SandboxVars={MinutesPerPage=0.02}\n')
        self.runtime['roles']['server'] = {'cache': str(server)}
        for name, value in [('selection', self.selection), ('runtime', self.runtime)]:
            (self.root / (name + '.json')).write_text(json.dumps(value))
        self.seal_settings()
        for name in ('client1/options.ini', 'server/options.ini', 'server/Server/owned.ini', 'server/Server/owned_SandboxVars.lua'):
            path = self.root / name
            original = path.read_bytes()
            path.write_bytes(original + b'changed=true\n')
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'settings changed before launch'):
                self.invoke(settings=False)
            path.write_bytes(original)
            self.assertEqual([], self.commands)
        for name in ('server/Server/owned.ini', 'server/Server/owned_SandboxVars.lua'):
            expected = json.loads((self.root / 'initial-settings.json').read_text())
            missing = dict(expected)
            del missing[name]
            (self.root / 'initial-settings.json').write_text(json.dumps(missing))
            with self.subTest(missing=name), self.assertRaisesRegex(ValueError, 'settings are missing'):
                self.invoke(settings=False)
            (self.root / 'initial-settings.json').write_text(json.dumps(expected))
        self.assertEqual([], self.commands)
        self.assertFalse((self.root / 'execution.json').exists())

    def test_prelaunch_initial_settings_reject_malformed_escape_and_symlink(self):
        manifest = self.root / 'initial-settings.json'
        expected = json.loads(manifest.read_text())
        for malformed in (None, [], {}, {'client1/options.ini': False}, dict(expected, **{'../options.ini': 'outside'}),
                          dict(expected, **{str(self.root / 'outside.ini'): 'absolute'}),
                          dict(expected, **{'client2/options.ini': 'unowned'})):
            manifest.write_text(json.dumps(malformed))
            with self.subTest(malformed=malformed), self.assertRaises(ValueError):
                self.invoke(settings=False)
        manifest.write_text(json.dumps(expected))
        backup = self.root / 'sealed-initial.json'
        manifest.rename(backup)
        manifest.symlink_to(backup)
        with self.assertRaisesRegex(ValueError, 'symlink'):
            self.invoke(settings=False)
        manifest.unlink()
        backup.rename(manifest)
        options = self.root / 'client1/options.ini'
        actual = self.root / 'owned-options.ini'
        options.rename(actual)
        options.symlink_to(actual)
        with self.assertRaisesRegex(ValueError, 'symlink'):
            self.invoke(settings=False)
        options.unlink()
        actual.rename(options)
        cache = self.root / 'client1'
        actual = self.root / 'owned-client'
        cache.rename(actual)
        cache.symlink_to(actual, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'symlink'):
            self.invoke(settings=False)
        self.assertEqual([], self.commands)

    def test_settings_rewritten_after_game_launch_remain_allowed(self):
        popen = self.popen
        def launch(command, **kwargs):
            process = popen(command, **kwargs)
            if 'ToolkitSmokeLauncher' in command:
                (self.root / 'client1/options.ini').write_text('voiceEnable=false\nwidth=1280\n')
            return process
        self.popen = launch
        result, _ = self.invoke()
        self.assertEqual('completed', result['status'])
        self.assertNotEqual(json.loads((self.root / 'initial-settings.json').read_text())['client1/options.ini'],
                            (self.root / 'client1/options.ini').read_text())

    def test_restored_world_drift_blocks_resume_before_any_process(self):
        self.selection['options'] = {'world_template': '/owned/world'}
        (self.root / 'selection.json').write_text(json.dumps(self.selection))
        with patch.object(runner.worlds, 'validate', return_value=(Path('/owned/world'), {'files': {'client1/Saves/map.bin': 'original'}})), \
             patch.object(runner.worlds, '_state', return_value={'client1/Saves/map.bin': 'changed'}):
            with self.assertRaisesRegex(ValueError, 'Restored world changed'):
                self.invoke()
        self.assertEqual(self.commands, [])

    def test_locked_pack_is_revalidated_on_resume_before_any_process(self):
        self.selection['options'] = {'pack_lock': '/owned/pack.json'}
        self.runtime['project'] = '/owned/project'
        (self.root / 'selection.json').write_text(json.dumps(self.selection))
        (self.root / 'runtime.json').write_text(json.dumps(self.runtime))
        with patch.object(runner.pack, 'validate', side_effect=ValueError('Missing or changed locked mod')) as verify:
            with self.assertRaisesRegex(ValueError, 'locked mod'):
                self.invoke()
        verify.assert_called_once_with('/owned/pack.json', '/owned/project', str(self.root), [])
        self.assertEqual(self.commands, [])

    def test_adapter_dependencies_are_revalidated_on_resume_before_any_process(self):
        with patch.object(runner.adapters, 'get') as adapter:
            adapter.return_value.validate.side_effect = ValueError('SP cart analyzers require working NumPy')
            with self.assertRaisesRegex(ValueError, 'NumPy'):
                self.invoke()
        adapter.return_value.validate.assert_called_once_with(self.selection)
        self.assertEqual(self.commands, [])
        self.assertFalse((self.root / 'execution.json').exists())

    def test_heap_budget_controls_jvm_and_is_recorded(self):
        self.selection['resources'] = {'heap_mib': 512, 'native_mib': 512, 'cpu_per_instance': 0.5}
        (self.root / 'selection.json').write_text(json.dumps(self.selection))
        result, _ = self.invoke()
        self.assertIn('-Xmx512m', self.commands[1])
        self.assertEqual(result['resources']['budget']['memory'], 1024**3)
        self.assertEqual(result['resources']['budget']['cpu'], 0.5)

    def test_insufficient_resources_and_failed_sampling_never_launch(self):
        self.snapshot['available_memory'] = 1024**2
        with self.assertRaisesRegex(RuntimeError, 'Insufficient resources'):
            self.invoke()
        self.sample_error = RuntimeError('Cannot sample host resources')
        with self.assertRaisesRegex(RuntimeError, 'Cannot sample host'):
            self.invoke()
        self.assertEqual(self.commands, [])
        self.assertFalse((self.root / 'execution.json').exists())

    def test_sigterm_during_server_cleanup_retains_report_and_stops_owned_clients(self):
        self.selection.update(kind='mp', clients=1, ports=[17343, 17344])
        server = self.root / 'server'
        (server / 'Server').mkdir(parents=True)
        (server / 'options.ini').write_text('voiceEnable=false\n')
        (server / 'Server/queue-smoke.ini').write_text('VoiceEnable=false\n')
        self.runtime.update(server_name='queue-smoke')
        self.runtime['roles']['server'] = {'cache': str(server)}
        (self.root / 'selection.json').write_text(json.dumps(self.selection))
        (self.root / 'runtime.json').write_text(json.dumps(self.runtime))
        self.content = '[QUEUE_TEST] SERVER_READY\n' + self.content
        original = self.popen
        def popen(command, **kwargs):
            process = original(command, **kwargs)
            if 'zombie.network.GameServer' in command:
                process.stdin = io.StringIO()
                def wait(timeout):
                    self.handlers[signal.SIGTERM](signal.SIGTERM, None)
                    process.returncode = 0
                    return 0
                process.wait = wait
            return process
        self.popen = popen
        with patch.object(admission.socket, 'socket'):
            result, kills = self.invoke()
        self.assertEqual(result['status'], 'failed')
        self.assertTrue(result['interrupted'])
        self.assertEqual([call.args[0] for call in kills], [102])
        self.assertTrue(json.loads((self.root / 'execution.json').read_text())['interrupted'])

    def test_changed_inputs_after_admission_never_launch(self):
        def sample():
            self.manifest_errors = ['Changed input during wait']
            return self.snapshot
        self.sample_error = sample
        with self.assertRaisesRegex(ValueError, 'Inputs changed while waiting'):
            self.invoke()
        self.assertEqual(self.commands, [])

    def test_live_settings_changed_during_admission_never_launch(self):
        def sample():
            (self.root / 'client1/options.ini').write_text('voiceEnable=false\nwidth=1280\n')
            return self.snapshot
        self.sample_error = sample
        with self.assertRaisesRegex(ValueError, 'settings changed before launch'):
            self.invoke()
        self.assertEqual([], self.commands)
        self.assertFalse((self.root / 'execution.json').exists())

    def test_pack_changed_during_admission_never_launch(self):
        self.selection['options'] = {'pack_lock': '/owned/pack.json'}
        self.runtime['project'] = '/owned/project'
        (self.root / 'selection.json').write_text(json.dumps(self.selection))
        (self.root / 'runtime.json').write_text(json.dumps(self.runtime))
        with patch.object(runner.pack, 'validate', side_effect=[None, ValueError('changed locked mod after admission')]) as verify:
            with self.assertRaisesRegex(ValueError, 'changed locked mod after admission'):
                self.invoke()
        self.assertEqual(2, verify.call_count)
        self.assertEqual([], self.commands)

    def test_restored_world_changed_during_admission_never_launch(self):
        self.selection['options'] = {'world_template': '/owned/world'}
        (self.root / 'selection.json').write_text(json.dumps(self.selection))
        original = {'client1/Saves/map.bin': 'original'}
        with patch.object(runner.worlds, 'validate', return_value=(Path('/owned/world'), {'files': original})), \
             patch.object(runner.worlds, '_state', side_effect=[original, {'client1/Saves/map.bin': 'changed'}]) as verify:
            with self.assertRaisesRegex(ValueError, 'Restored world changed'):
                self.invoke()
        self.assertEqual(2, verify.call_count)
        self.assertEqual([], self.commands)

    def test_signal_during_execution_write_keeps_failure_report(self):
        original = runner.write_json
        def write(path, value):
            if path.name == 'execution.json':
                self.handlers[signal.SIGTERM](signal.SIGTERM, None)
            original(path, value)
        with patch.object(runner, 'write_json', side_effect=write):
            result, _ = self.invoke()
        self.assertEqual(result['status'], 'failed')
        self.assertTrue(json.loads((self.root / 'execution.json').read_text())['interrupted'])

    def test_partial_final_json_does_not_abort_polling(self):
        self.content = '[QUEUE_CHECK] {"event":"case"'
        def finish(_):
            (self.root / "client1-launch.log").write_text('[QUEUE_CHECK] {"event":"case","id":"nativeStop"}\n[QUEUE_CHECK] {"event":"complete","failed":0}\n')
        result, _ = self.invoke(sleep=finish)
        self.assertEqual(result["status"], "completed")


class InventoryEquipEnvironmentTests(unittest.TestCase):
    def selection(self):
        return dict(suite='wooden_cart_multiplayer', kind='mp', cases=['owner_observer_motion'],
                    options=dict(mp_host=True, cart_inventory_equip=True, cart_variant='wooden-wheelbarrow'))

    def test_explicit_exact_true_reaches_both_selected_host_clients(self):
        for role in ('client1', 'client2'):
            with self.subTest(role=role), patch.dict(runner.os.environ, {'PZ_CART_INVENTORY_EQUIP': 'inherited-unsafe'}):
                env = runner._fixture_environment(self.selection(), role, Path('/owned/cache'),
                    {'PZ_CART_INVENTORY_EQUIP': 'true', 'PZ_CART_RUNTIME_FILE': '/owned/runtime.lua'})
                self.assertEqual(env['PZ_CART_INVENTORY_EQUIP'], 'true')
                self.assertEqual(env['PZ_CART_RUNTIME_FILE'], '/owned/runtime.lua')

    def test_probe_flag_accepts_only_string_true(self):
        for value in ('false', 'TRUE', '1', '', '/absolute/path', True, False, 1, None):
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, 'fixture-owned'):
                runner._fixture_environment(self.selection(), 'client1', Path('/owned/cache'), {'PZ_CART_INVENTORY_EQUIP': value})

    def test_probe_flag_rejects_other_suite_kind_case_role_host_or_selection(self):
        changes = [('suite', 'wooden_cart_motion'), ('kind', 'sp'), ('cases', ['motion']),
                   ('mp_host', False), ('mp_host', 'true'), ('cart_inventory_equip', False),
                   ('cart_inventory_equip', 'true'), ('cart_variant', 'shopping-cart')]
        for name, value in changes:
            selected = self.selection()
            (selected['options'] if name in selected['options'] else selected)[name] = value
            with self.subTest(name=name, value=value), self.assertRaisesRegex(ValueError, 'fixture-owned'):
                runner._fixture_environment(selected, 'client1', Path('/owned/cache'), {'PZ_CART_INVENTORY_EQUIP': 'true'})
        for role in ('server', 'client3'):
            with self.subTest(role=role), self.assertRaisesRegex(ValueError, 'fixture-owned'):
                runner._fixture_environment(self.selection(), role, Path('/owned/cache'), {'PZ_CART_INVENTORY_EQUIP': 'true'})

    def test_inherited_probe_flag_never_enables_default_mp_or_unstaged_selected_probe(self):
        for selected in (self.selection(), dict(suite='wooden_cart_multiplayer', kind='mp', cases=['owner_observer_motion'], options={'mp_host': True})):
            for role in ('server', 'client1', 'client2'):
                with self.subTest(selected=selected, role=role), patch.dict(runner.os.environ, {'PZ_CART_INVENTORY_EQUIP': 'true'}):
                    env = runner._fixture_environment(selected, role, Path('/owned/cache'), {})
                    self.assertNotIn('PZ_CART_INVENTORY_EQUIP', env)

    def test_probe_flag_does_not_weaken_unknown_and_absolute_path_guards(self):
        for extra in ({'UNKNOWN_PROBE_ENV': '/owned/path'}, {'JAVA_TOOL_OPTIONS': '/owned/path'},
                      {'PZ_CART_RUNTIME_FILE': 'relative.lua'}, {'PZ_CART_COMMAND_FILE': True}):
            with self.subTest(extra=extra), self.assertRaisesRegex(ValueError, 'fixture-owned'):
                runner._fixture_environment(self.selection(), 'client1', Path('/owned/cache'), dict(extra, PZ_CART_INVENTORY_EQUIP='true'))


class InventoryLifetimeEnvironmentTests(unittest.TestCase):
    def selection(self):
        return dict(suite='wooden_cart_multiplayer',kind='mp',cases=['owner_observer_motion'],
                    options=dict.fromkeys(('mp_host','cart_lease_inventory','cart_lease_menu','cart_lease_lifetimes',
                                           'cart_lease_control','cart_timeline','cart_fast_motion'),True))

    def test_only_exact_initial_inventory_chain_admits_client_probe(self):
        for role in ('client1','client2'):
            self.assertEqual(runner._fixture_environment(self.selection(),role,Path('/owned/cache'),
                {'PZ_CART_INVENTORY_EQUIP':'true'})['PZ_CART_INVENTORY_EQUIP'],'true')
        for role in ('server','client3'):
            with self.subTest(role=role),self.assertRaises(ValueError):
                runner._fixture_environment(self.selection(),role,Path('/owned/cache'),{'PZ_CART_INVENTORY_EQUIP':'true'})
        for flag in self.selection()['options']:
            for value in (False,'true',1,None):
                selected=self.selection();selected['options'][flag]=value
                with self.subTest(flag=flag,value=value),self.assertRaises(ValueError):
                    runner._fixture_environment(selected,'client1',Path('/owned/cache'),{'PZ_CART_INVENTORY_EQUIP':'true'})
        for flag,value in [('cart_inventory_equip',True),('cart_actions',True),('cart_time_alignment',True),
                           ('cart_wall_exit','front'),('cart_variant','shopping-cart')]:
            selected=self.selection();selected['options'][flag]=value
            with self.subTest(flag=flag),self.assertRaises(ValueError):
                runner._fixture_environment(selected,'client1',Path('/owned/cache'),{'PZ_CART_INVENTORY_EQUIP':'true'})

    def test_inherited_inventory_probe_is_stripped_even_for_selected_entry(self):
        with patch.dict(runner.os.environ,{'PZ_CART_INVENTORY_EQUIP':'true'}):
            for role in ('server','client1','client2'):
                self.assertNotIn('PZ_CART_INVENTORY_EQUIP',runner._fixture_environment(self.selection(),role,Path('/owned/cache'),{}))


class ActionInvalidationEnvironmentTests(unittest.TestCase):
    def selection(self):
        return dict(suite='wooden_cart_multiplayer',kind='mp',cases=['owner_observer_motion'],
                    options=dict(cart_action_invalidation=True,mp_host=True,cart_timeline=True,cart_fast_motion=True))

    def test_new_fixture_flag_requires_exact_sealed_selection_and_owned_role(self):
        flags=dict(PZ_CART_ACTION_INVALIDATION='true',PZ_CART_ACTION_ADMISSION='true',PZ_CART_LEASE_CONTROL='true')
        for role in ('server','client1','client2'):
            env=runner._fixture_environment(self.selection(),role,Path('/owned/cache'),flags)
            self.assertEqual(env['PZ_CART_ACTION_INVALIDATION'],'true')
        for key in self.selection()['options']:
            for value in (False,1,'true',None):
                selection=self.selection();selection['options'][key]=value
                with self.subTest(key=key,value=value),self.assertRaises(ValueError):
                    runner._fixture_environment(selection,'client1',Path('/owned/cache'),flags)
        for key,value in [('cart_actions',True),('cart_action_admission',True),('cart_lease_control',True),
                          ('cart_lease_lifetimes',True),('cart_lease_inventory',True),('cart_inventory_equip',True),
                          ('cart_time_alignment',True),('cart_wall_exit','front'),('cart_variant','shopping-cart')]:
            selection=self.selection();selection['options'][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):
                runner._fixture_environment(selection,'client1',Path('/owned/cache'),flags)
        with self.assertRaises(ValueError):runner._fixture_environment(self.selection(),'client3',Path('/owned/cache'),flags)
        for value in ('false',True,1,None):
            with self.subTest(value=value),self.assertRaises(ValueError):
                runner._fixture_environment(self.selection(),'client1',Path('/owned/cache'),dict(flags,PZ_CART_ACTION_INVALIDATION=value))

    def test_inherited_mutating_fixture_flag_is_stripped_from_all_roles(self):
        with patch.dict(runner.os.environ,{'PZ_CART_ACTION_INVALIDATION':'true'}):
            for role in ('server','client1','client2'):
                self.assertNotIn('PZ_CART_ACTION_INVALIDATION',runner._fixture_environment(self.selection(),role,Path('/owned/cache'),{}))


class CartTimelineEnvironmentTests(unittest.TestCase):
    def selected(self):
        return dict(suite='wooden_cart_multiplayer',kind='mp',cases=['owner_observer_motion'],options=dict(cart_timeline=True))

    def test_selected_trace_reaches_exact_roles_for_host_or_ordinary_mp(self):
        for host in (False,True):
            selection=self.selected();selection['options']['mp_host']=host
            for role in ('server','client1','client2'):
                env=runner._fixture_environment(selection,role,Path('/owned/cache'),{'PZ_CART_TIMELINE':'true'})
                self.assertEqual(env['PZ_CART_TIMELINE'],'true')

    def test_unselected_inherited_flag_is_removed(self):
        for selected in (self.selected(),dict(suite='health',kind='sp',options={})):
            with patch.dict(runner.os.environ,{'PZ_CART_TIMELINE':'true'}):
                self.assertNotIn('PZ_CART_TIMELINE',runner._fixture_environment(selected,'client1',Path('/owned/cache'),{}))

    def test_exact_true_flag_and_selected_context_are_required(self):
        for value in ('false','TRUE','1','',True,False,1,None,'/owned/cache'):
            with self.subTest(value=value),self.assertRaisesRegex(ValueError,'fixture-owned'):
                runner._fixture_environment(self.selected(),'client1',Path('/owned/cache'),{'PZ_CART_TIMELINE':value})
        for field,value in (('suite','wooden_cart_motion'),('kind','sp'),('cases',['other']),('cart_timeline',False),('cart_timeline','true')):
            selection=self.selected();(selection['options'] if field=='cart_timeline' else selection)[field]=value
            with self.subTest(field=field,value=value),self.assertRaisesRegex(ValueError,'fixture-owned'):
                runner._fixture_environment(selection,'client1',Path('/owned/cache'),{'PZ_CART_TIMELINE':'true'})
        with self.assertRaisesRegex(ValueError,'fixture-owned'):
            runner._fixture_environment(self.selected(),'client3',Path('/owned/cache'),{'PZ_CART_TIMELINE':'true'})


class CartTimingEnvironmentTests(unittest.TestCase):
    def selected(self):
        return dict(suite='wooden_cart_multiplayer',kind='mp',cases=['owner_observer_motion'],
                    options=dict(cart_timeline=True,cart_time_alignment=True,mp_host=True))

    def test_only_explicit_owned_host_clients_may_request_clock_samples(self):
        for role in ('client1','client2'):
            env=runner._fixture_environment(self.selected(),role,Path('/owned/cache'),{'PZ_CART_TIME_ALIGNMENT':'true'})
            self.assertEqual(env['PZ_CART_TIME_ALIGNMENT'],'true')
        for role in ('server','client3'):
            with self.assertRaises(ValueError):runner._fixture_environment(self.selected(),role,Path('/owned/cache'),{'PZ_CART_TIME_ALIGNMENT':'true'})
        for key,value in [('cart_timeline',False),('cart_time_alignment',False),('mp_host',False),('cart_inventory_equip',True),('cart_actions',True),('cart_wall_exit','front')]:
            selected=self.selected();selected['options'][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):
                runner._fixture_environment(selected,'client1',Path('/owned/cache'),{'PZ_CART_TIME_ALIGNMENT':'true'})

    def test_inherited_experiment_flags_never_enable_extra_requests(self):
        with patch.dict(runner.os.environ,{'PZ_CART_TIME_ALIGNMENT':'true'}):
            self.assertNotIn('PZ_CART_TIME_ALIGNMENT',runner._fixture_environment(self.selected(),'client1',Path('/owned/cache'),{}))
        for value in ('false','TRUE','1',True,1,None,'/owned/cache'):
            with self.subTest(value=value),self.assertRaises(ValueError):
                runner._fixture_environment(self.selected(),'client1',Path('/owned/cache'),{'PZ_CART_TIME_ALIGNMENT':value})


class CartLeaseEnvironmentTests(unittest.TestCase):
    def selected(self):
        return dict(suite='wooden_cart_multiplayer',kind='mp',cases=['owner_observer_motion'],
                    options=dict(cart_timeline=True,cart_lease_control=True,cart_fast_motion=True,mp_host=True))

    def test_control_scope_requires_explicit_owned_host_selection(self):
        for role in ('server','client1','client2'):
            self.assertEqual(runner._fixture_environment(self.selected(),role,Path('/owned/cache'),
                {'PZ_CART_LEASE_CONTROL':'true'})['PZ_CART_LEASE_CONTROL'],'true')
        for key,value in [('cart_timeline',False),('cart_lease_control',False),('cart_fast_motion',False),('mp_host',False),
                          ('cart_inventory_equip',True),('cart_actions',True),('cart_wall_exit','front')]:
            selection=self.selected();selection['options'][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):
                runner._fixture_environment(selection,'client1',Path('/owned/cache'),{'PZ_CART_LEASE_CONTROL':'true'})
        with self.assertRaises(ValueError):
            runner._fixture_environment(self.selected(),'client3',Path('/owned/cache'),{'PZ_CART_LEASE_CONTROL':'true'})

    def test_control_scope_is_never_inherited_or_enabled_by_nontrue_values(self):
        with patch.dict(runner.os.environ,{'PZ_CART_LEASE_CONTROL':'true'}):
            self.assertNotIn('PZ_CART_LEASE_CONTROL',runner._fixture_environment(self.selected(),'client1',Path('/owned/cache'),{}))
        for value in ('false','TRUE','1',True,1,None,'/owned/cache'):
            with self.subTest(value=value),self.assertRaises(ValueError):
                runner._fixture_environment(self.selected(),'client1',Path('/owned/cache'),{'PZ_CART_LEASE_CONTROL':value})


class CartLifecycleEnvironmentTests(unittest.TestCase):
    def selected(self):
        return dict(suite='wooden_cart_multiplayer',kind='mp',cases=['lease_lifecycle'],options=dict(mp_host=True))

    def test_explicit_case_owns_only_control_and_equipment_flags(self):
        flags={'PZ_CART_LEASE_CONTROL':'true','PZ_CART_LEASE_LIFETIME':'true'}
        for role in ('server','client1','client2'):
            env=runner._fixture_environment(self.selected(),role,Path('/owned/cache'),flags)
            for name in flags:self.assertEqual(env[name],'true')
        changes=[('suite','startup'),('kind','sp'),('cases',['owner_observer_motion'])]
        for key,value in changes:
            selection=self.selected();selection[key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):runner._fixture_environment(selection,'client2',Path('/owned/cache'),flags)
        for key,value in [('mp_host',False),('mp_host','true'),('cart_timeline',True),('cart_actions',True),
                          ('cart_inventory_equip',True),('cart_lease_control',True),('cart_variant','shopping-cart'),('cart_wall_exit','front')]:
            selection=self.selected();selection['options'][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):runner._fixture_environment(selection,'client2',Path('/owned/cache'),flags)
        with self.assertRaises(ValueError):runner._fixture_environment(self.selected(),'client3',Path('/owned/cache'),flags)
        for name in flags:
            for value in ('false',True,None,'1'):
                with self.subTest(name=name,value=value),self.assertRaises(ValueError):runner._fixture_environment(self.selected(),'client1',Path('/owned/cache'),{name:value})
        for name in ('PZ_CART_TIMELINE','PZ_CART_ACTION_ADMISSION'):
            with self.assertRaises(ValueError):runner._fixture_environment(self.selected(),'client1',Path('/owned/cache'),dict(flags,**{name:'true'}))
        with patch.dict(runner.os.environ,flags):
            env=runner._fixture_environment(self.selected(),'client2',Path('/owned/cache'),{})
            self.assertTrue(all(name not in env for name in flags))


class CartEquipmentLifetimeEnvironmentTests(CartLeaseEnvironmentTests):
    def selected(self):
        selection=super().selected();selection['options']['cart_lease_lifetimes']=True;return selection

    def test_equipment_scope_requires_isolated_explicit_selection(self):
        name='PZ_CART_LEASE_LIFETIME'
        for role in ('server','client1','client2'):
            self.assertEqual(runner._fixture_environment(self.selected(),role,Path('/owned/cache'),{name:'true'})[name],'true')
        for key,value in [('cart_lease_lifetimes',False),('cart_lease_lifetimes','true'),('cart_lease_control',False),
                          ('cart_timeline',False),('cart_fast_motion',False),('mp_host',False),('cart_actions',True),
                          ('cart_inventory_equip',True),('cart_time_alignment',True),('cart_hotkey_setdown',True)]:
            selection=self.selected();selection['options'][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):
                runner._fixture_environment(selection,'client1',Path('/owned/cache'),{name:'true'})
        with patch.dict(runner.os.environ,{name:'true'}):
            self.assertNotIn(name,runner._fixture_environment(self.selected(),'client1',Path('/owned/cache'),{}))
        for value in ('false','1',True,1,None,'/owned/cache'):
            with self.subTest(value=value),self.assertRaises(ValueError):
                runner._fixture_environment(self.selected(),'client1',Path('/owned/cache'),{name:value})


class CartActionAdmissionEnvironmentTests(unittest.TestCase):
    def selected(self):
        return dict(suite='wooden_cart_multiplayer',kind='mp',cases=['owner_observer_motion'],options=dict(
            cart_timeline=True,cart_fast_motion=True,cart_actions=True,cart_action_admission=True,mp_host=True))

    def test_action_observation_requires_explicit_isolated_host_bank(self):
        for role in ('server','client1','client2'):
            env=runner._fixture_environment(self.selected(),role,Path('/owned/cache'),
                {'PZ_CART_LEASE_CONTROL':'true','PZ_CART_ACTION_ADMISSION':'true'})
            self.assertEqual(env['PZ_CART_ACTION_ADMISSION'],'true')
        for key,value in [('cart_timeline',False),('cart_fast_motion',False),('cart_actions',False),('cart_action_admission',False),
                          ('mp_host',False),('cart_lease_control',True),('cart_time_alignment',True),
                          ('cart_inventory_equip',True),('cart_wall_exit','front')]:
            selection=self.selected();selection['options'][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):
                runner._fixture_environment(selection,'client1',Path('/owned/cache'),{'PZ_CART_ACTION_ADMISSION':'true'})

    def test_action_observation_cannot_be_inherited_or_enabled_by_invalid_value(self):
        with patch.dict(runner.os.environ,{'PZ_CART_ACTION_ADMISSION':'true','PZ_CART_LEASE_CONTROL':'true'}):
            env=runner._fixture_environment(self.selected(),'client1',Path('/owned/cache'),{})
            self.assertNotIn('PZ_CART_ACTION_ADMISSION',env);self.assertNotIn('PZ_CART_LEASE_CONTROL',env)
        for value in ('false','1','TRUE',True,1,None,'/owned/cache'):
            with self.subTest(value=value),self.assertRaises(ValueError):
                runner._fixture_environment(self.selected(),'client1',Path('/owned/cache'),{'PZ_CART_ACTION_ADMISSION':value})


class CartObserverEnvironmentTests(CartActionAdmissionEnvironmentTests):
    def selected(self):
        selection=super().selected()
        selection['options']['cart_observer_association']=True
        return selection

    def test_observer_marker_requires_explicit_owned_action_bank(self):
        name='PZ_CART_OBSERVER_ASSOCIATION'
        for role in ('server','client1','client2'):
            self.assertEqual(runner._fixture_environment(self.selected(),role,Path('/owned/cache'),{name:'true'})[name],'true')
        for key,value in [('cart_observer_association',False),('cart_observer_association','true'),
                          ('cart_action_admission',False),('cart_actions',False),('cart_fast_motion',False),
                          ('cart_timeline',False),('mp_host',False),('cart_time_alignment',True),('cart_lease_control',True)]:
            selection=self.selected();selection['options'][key]=value
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):
                runner._fixture_environment(selection,'client1',Path('/owned/cache'),{name:'true'})
        with self.assertRaises(ValueError):
            runner._fixture_environment(self.selected(),'client3',Path('/owned/cache'),{name:'true'})
        with patch.dict(runner.os.environ,{name:'true'}):
            self.assertNotIn(name,runner._fixture_environment(self.selected(),'client1',Path('/owned/cache'),{}))
        for value in ('false','TRUE',True,1,None,'/owned/cache'):
            with self.subTest(value=value),self.assertRaises(ValueError):
                runner._fixture_environment(self.selected(),'client1',Path('/owned/cache'),{name:value})


if __name__ == "__main__":
    unittest.main()
