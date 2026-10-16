import io
import json
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from queue_checks import runner


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
        self.root = Path(self.temp.name)
        (self.root / "client1").mkdir()
        (self.root / "client1/options.ini").write_text("voiceEnable=false\n")
        self.selection = {"suite": "health", "kind": "sp", "mods": [], "cases": ["nativeStop"], "timeout_seconds": 10}
        self.runtime = {"game": str(self.root), "java": "/fake/java", "roles": {"client1": {"cache": str(self.root / "client1"), "classes": str(self.root / "classes")}}}
        (self.root / "selection.json").write_text(json.dumps(self.selection))
        (self.root / "runtime.json").write_text(json.dumps(self.runtime))
        self.seal_settings()
        self.commands = []
        self.processes = []
        self.streams = []
        self.handlers = {}
        self.signal_changes = []
        self.complete = True
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
        with patch.object(runner.sys, "platform", "darwin"), patch.object(runner, "LOCK", self.root / "lock"), \
             patch.object(runner, "verify_manifest", return_value=[]), \
             patch.object(runner.subprocess, "check_output", return_value=collisions), \
             patch.object(runner.subprocess, "Popen", side_effect=self.popen), \
             patch.object(runner.os, "killpg") as kill, patch.object(runner.signal, "signal", side_effect=self.signal), \
             patch.object(runner.time, "sleep", side_effect=sleep):
            result = runner.run(self.root)
            return result, kill.call_args_list

    def test_completed_native_process_gets_novoip_and_only_own_pid_stops(self):
        result, kills = self.invoke()
        self.assertEqual(result["status"], "completed")
        self.assertIn("-novoip", self.commands[1])
        self.assertEqual([call.args[0] for call in kills], [101])
        self.assertEqual(result["processes"]["client1"]["exit_code"], -15)

    def test_existing_game_blocks_before_any_launch(self):
        with self.assertRaisesRegex(RuntimeError, "Existing game"):
            self.invoke("77 java ToolkitSmokeLauncher\n")
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

    def test_lock_metadata_describes_owner_and_stale_file_does_not_block(self):
        (self.root / 'lock').write_text('stale owner\n')
        result, _ = self.invoke()
        self.assertEqual('completed', result['status'])
        owner = json.loads((self.root / 'lock').read_text())
        self.assertEqual(str(self.root.resolve()), owner['run'])
        self.assertEqual(self.selection['suite'], owner['suite'])
        self.assertEqual(self.selection['cases'], owner['cases'])
        self.assertTrue(owner['started_utc'].endswith('+00:00'))

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

    def test_partial_final_json_does_not_abort_polling(self):
        self.content = '[QUEUE_CHECK] {"event":"case"'
        def finish(_):
            (self.root / "client1-launch.log").write_text('[QUEUE_CHECK] {"event":"case","id":"nativeStop"}\n[QUEUE_CHECK] {"event":"complete","failed":0}\n')
        result, _ = self.invoke(sleep=finish)
        self.assertEqual(result["status"], "completed")


if __name__ == "__main__":
    unittest.main()
