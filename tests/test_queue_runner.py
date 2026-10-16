import json
from pathlib import Path
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
        self.content = '[QUEUE_CHECK] {"event":"case","id":"nativeStop"}\n[QUEUE_CHECK] {"event":"complete","failed":0}\n'

    def popen(self, command, **kwargs):
        self.commands.append(command)
        process = Process(100 + len(self.processes))
        self.processes.append(process)
        if "stdout" in kwargs and self.complete:
            kwargs["stdout"].write(self.content)
            kwargs["stdout"].flush()
        return process

    def invoke(self, collisions="", sleep=None):
        with patch.object(runner.sys, "platform", "darwin"), patch.object(runner, "LOCK", self.root / "lock"), \
             patch.object(runner, "verify_manifest", return_value=[]), \
             patch.object(runner.subprocess, "check_output", return_value=collisions), \
             patch.object(runner.subprocess, "Popen", side_effect=self.popen), \
             patch.object(runner.os, "killpg") as kill, patch.object(runner.signal, "signal"), \
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

    def test_voice_enabled_rejected_before_game_launch(self):
        (self.root / "client1/options.ini").write_text("voiceEnable=true\n")
        result, kills = self.invoke()
        self.assertEqual(result["status"], "failed")
        self.assertIn("VOIP", result["error"])
        self.assertEqual(len(self.commands), 1)  # Display guard only.
        self.assertEqual(kills, [])

    def test_partial_final_json_does_not_abort_polling(self):
        self.content = '[QUEUE_CHECK] {"event":"case"'
        def finish(_):
            (self.root / "client1-launch.log").write_text('[QUEUE_CHECK] {"event":"case","id":"nativeStop"}\n[QUEUE_CHECK] {"event":"complete","failed":0}\n')
        result, _ = self.invoke(sleep=finish)
        self.assertEqual(result["status"], "completed")


if __name__ == "__main__":
    unittest.main()
