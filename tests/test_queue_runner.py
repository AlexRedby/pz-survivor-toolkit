import json
import io
import signal
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from queue_checks import runner, admission


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
        self.commands = []
        self.processes = []
        self.complete = True
        self.handlers = {}
        self.sample_error = None
        self.manifest_errors = []
        self.snapshot = {'total_memory': 128 * 1024**3, 'available_memory': 100 * 1024**3,
                         'cpu_count': 64, 'processes': []}
        self.content = '[QUEUE_CHECK] {"event":"case","id":"nativeStop"}\n[QUEUE_CHECK] {"event":"complete","failed":0}\n'

    def popen(self, command, **kwargs):
        self.commands.append(command)
        process = Process(100 + len(self.processes))
        self.processes.append(process)
        if "stdout" in kwargs and self.complete:
            kwargs["stdout"].write(self.content)
            kwargs["stdout"].flush()
        return process

    def handle_signal(self, signum, handler):
        previous = self.handlers.get(signum)
        self.handlers[signum] = handler
        return previous

    def invoke(self, collisions="", sleep=None):
        with patch.object(runner.sys, "platform", "darwin"), patch.object(runner, "LOCK", self.root / "lock"), \
             patch.object(runner, "verify_manifest", side_effect=lambda *args: self.manifest_errors), \
             patch.object(admission, "STATE", self.root / "admission-state"), \
             patch.object(admission.host, "sample", side_effect=self.sample_error, return_value=dict(self.snapshot,
                 processes=[{'pid': int(line.split()[0]), 'rss': 0, 'cpu': 0, 'game': True, 'command': line}
                            for line in collisions.splitlines() if line] or self.snapshot['processes'])), \
             patch.object(runner.subprocess, "Popen", side_effect=self.popen), \
             patch.object(runner.os, "killpg") as kill, patch.object(runner.signal, "signal", side_effect=self.handle_signal), \
             patch.object(runner.time, "sleep", side_effect=sleep):
            result = runner.run(self.root, resource_wait=0)
            return result, kill.call_args_list

    def test_completed_native_process_gets_novoip_and_only_own_pid_stops(self):
        result, kills = self.invoke()
        self.assertEqual(result["status"], "completed")
        self.assertIn("-novoip", self.commands[1])
        self.assertEqual([call.args[0] for call in kills], [101])
        self.assertEqual(result["processes"]["client1"]["exit_code"], -15)

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

    def test_voice_enabled_rejected_before_game_launch(self):
        (self.root / "client1/options.ini").write_text("voiceEnable=true\n")
        result, kills = self.invoke()
        self.assertEqual(result["status"], "failed")
        self.assertIn("VOIP", result["error"])
        self.assertEqual(len(self.commands), 1)  # Display guard only.
        self.assertEqual(kills, [])

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


if __name__ == "__main__":
    unittest.main()
