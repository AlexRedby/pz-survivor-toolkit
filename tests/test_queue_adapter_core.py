"""Shared adapter boundaries with synthetic inputs and owned mocked processes only."""
import io
import json
from pathlib import Path
import signal
import subprocess
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tests"))
from queue_checks import adapters, native, report, runner
import test_queue_native_snapshot as snapshot_helpers
import test_queue_report as report_helpers
import test_queue_runner as runner_helpers


class AdapterSnapshotBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.fixture = snapshot_helpers.NativeSnapshotTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)

    def test_adapter_without_suite_directories_keeps_staged_config_and_generated_inputs(self):
        fixture = self.fixture
        suite = "test-adapter"
        self.assertFalse((fixture.project / "tests/native_queue" / suite).exists())

        def stage(project, output, game, jdk, selection, locations, runtime):
            self.assertEqual({"server", "client1"}, set(runtime["roles"]))
            for role in runtime["roles"]:
                lua = output / role / "mods/ActionQueueTest/42/media/lua"
                self.assertTrue(all((lua / side).is_dir() for side in ("client", "shared", "server")))
                config = lua / "shared/QueueTestSelection.lua"
                config.write_text(config.read_text().replace("return QueueTestSelection", 'QueueTestSelection.adapterField="staged"\nreturn QueueTestSelection'))
                fixture.write(output / role / "mods/GeneratedFixture/42/mod.info", "id=GeneratedFixture\n")
                fixture.write(output / role / "mods/GeneratedFixture/42/media/java/probe.jar", "generated probe jar")
            runtime["fixture"] = {"mods": ["GeneratedFixture"], "sandbox": {"MinutesPerPage": 0.02, "AllowMiniMap": False}}

        adapter = SimpleNamespace(__file__=str(Path(__file__).resolve()), validate=Mock(), sources=lambda *_: [],
                                  definitions=lambda: {suite: {}}, stage=stage)
        with patch.object(native.adapters, "get", return_value=adapter):
            output = fixture.prepare(suite=suite, kind="mp", clients=1, languages=["EN"], options={"fraction": 0.25, "optional": None})
        adapter.validate.assert_called_once()
        runtime = report.read_json(output / "runtime.json")
        self.assertEqual({"server", "client1"}, set(runtime["roles"]))
        self.assertEqual("EN", runtime["roles"]["client1"]["language"])
        configs = []
        for role in runtime["roles"]:
            cache = output / role
            config = (cache / "mods/ActionQueueTest/42/media/lua/shared/QueueTestSelection.lua").read_text()
            self.assertIn('adapterField="staged"', config)
            self.assertIn('["fraction"]=0.25', config)
            self.assertIn('["optional"]=nil', config)
            self.assertTrue(config.rstrip().endswith("return QueueTestSelection"))
            configs.append(config)
            for layer in ("common", "42"):
                for directory in ("AnimSets", "actiongroups"):
                    self.assertTrue((cache / "mods/GeneratedFixture" / layer / "media" / directory).is_dir())
            self.assertIn(" mod = GeneratedFixture,", (cache / "mods/default.txt").read_text())
            jar = cache / "mods/GeneratedFixture/42/media/java/probe.jar"
            approvals = report.read_json(cache / "zombie-buddy/mod_approvals.json")["mods"]
            self.assertEqual([{"id": "GeneratedFixture", "jar_hash": native.sha256(jar), "decision": True, "time": "2026-01-01T00:00:00Z"}], approvals)
        self.assertEqual(configs[0], configs[1], "MP shared Lua must remain byte-identical")
        self.assertIn("Mods=PZSurvivorToolkit;ActionQueueTest;GeneratedFixture", (output / "server/Server/queue-smoke.ini").read_text())
        sandbox = (output / "server/Server/queue-smoke_SandboxVars.lua").read_text()
        self.assertIn("MinutesPerPage=0.02", sandbox)
        self.assertIn("AllowMiniMap=false", sandbox)
        self.assertEqual([], report.verify_manifest(output, "snapshot-hashes.json"))

    def test_explicit_mod_source_requires_the_selected_exact_id(self):
        fixture = self.fixture
        candidate = fixture.mod(fixture.root / "candidate", "OtherMod")
        with self.assertRaisesRegex(ValueError, "exactly once.*PZSurvivorToolkit"):
            fixture.prepare("wrong-id", options={"mod_sources": {"PZSurvivorToolkit": str(candidate)}})
        self.assertFalse((fixture.root / "wrong-id").exists())
        fixture.write(candidate / "42/mod.info", "id=PZSurvivorToolkit\n")
        fixture.write(candidate / "42/media/lua/shared/test.lua", "return 'explicit candidate'\n")
        output = fixture.prepare(options={"mod_sources": {"PZSurvivorToolkit": str(candidate)}})
        manifest = report.read_json(output / "manifest.json")
        self.assertEqual(str(candidate), manifest[0]["source"])
        self.assertIn("explicit candidate", (output / "client1/mods/PZSurvivorToolkit/42/media/lua/shared/test.lua").read_text())
        with self.assertRaisesRegex(ValueError, "not selected"):
            fixture.prepare("unselected", options={"mod_sources": {"OtherMod": str(candidate)}})

    def test_equal_config_content_at_different_paths_compares_but_keeps_real_provenance(self):
        fixture = self.fixture
        configs = [fixture.root / name for name in ("one.json", "two.json")]
        for path in configs:
            fixture.write(path, '{"options":{"same":true}}\n')
        runs = [fixture.prepare("run" + str(index), config_source=str(path)) for index, path in enumerate(configs)]
        fingerprints = [report.read_json(root / "settings-fingerprint.json") for root in runs]
        self.assertEqual(fingerprints[0]["sha256"], fingerprints[1]["sha256"])
        for index, root in enumerate(runs):
            provenance = report.read_json(root / "source-manifest.json")
            self.assertIn(str(configs[index]), provenance)
            self.assertNotIn(str(configs[1 - index]), provenance)
            self.assertEqual(str(configs[index]), report.read_json(root / "selection.json")["config_source"])
            self.assertEqual("<suite-config>", fingerprints[index]["inputs"]["selection"]["config_source"])
            self.assertIn("<suite-config>", fingerprints[index]["inputs"]["sources"])


class AdapterReportBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.fixture = report_helpers.QueueReportTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.catalog = {"suites": {"test-adapter": {"status": "ready", "clients": 1, "cases": [
            {"id": "bandageApply", "producer": "preserved-fixture", "capability": "capture", "kinds": ["sp"], "modes": ["toolkit", "native"]}]}}}

    def root(self, name="run"):
        root = self.fixture.fixture(name)
        selection = report.read_json(root / "selection.json")
        selection["suite"] = "test-adapter"
        report.write_json(root / "selection.json", selection)
        self.fixture.freeze(root)
        return root

    @staticmethod
    def outcome(status="passed"):
        return {"actor": "client1", "case": "bandageApply", "status": status, "outcome": {"assertion": "synthetic parser input"}}

    def build(self, root, value=None, error=None):
        verifier = Mock(side_effect=error, return_value=value)
        with patch.object(adapters, "get", return_value=SimpleNamespace(verify=verifier)):
            return report.build_report(root, self.catalog)

    def test_capture_stays_needs_review_and_matrix_never_promotes_it_to_pass(self):
        result = self.build(self.root(), {"issues": [], "outcomes": [self.outcome("captured")]})
        self.assertEqual("captured", result["functional"]["status"])
        self.assertEqual("needs-review", result["status"])
        row = next(row for row in report.matrix(self.catalog, [result])["rows"] if row["mode"] == "toolkit")
        self.assertEqual("captured", row["status"])
        self.assertNotIn("passed", [row["status"] for row in result["coverage"]])
        self.catalog["suites"]["test-adapter"]["cases"][0]["capability"] = "effect"
        result = self.build(self.root("cannot-capture-effect"), {"issues": [], "outcomes": [self.outcome("captured")]})
        self.assertEqual("failed", result["status"])

    def test_missing_duplicate_and_throwing_verifiers_fail_while_full_native_audit_survives(self):
        for index, (value, error) in enumerate((( {"issues": [], "outcomes": []}, None),
                                               ({"issues": [], "outcomes": [self.outcome(), self.outcome()]}, None),
                                               (None, ValueError("malformed authority receipt")),
                                               (None, AssertionError("native assertion failed")),
                                               (None, subprocess.TimeoutExpired("native analyzer", 1)))):
            with self.subTest(index=index):
                root = self.root(str(index))
                with (root / "client1-launch.log").open("a") as stream:
                    stream.write("ERROR : General > java.lang.IllegalStateException: full audit remains visible\n")
                result = self.build(root, value, error)
                self.assertEqual("failed", result["status"])
                self.assertEqual("failed", result["functional"]["status"])
                self.assertTrue(result["provenance"]["verified"])
                self.assertEqual(1, result["runtime"]["roles"]["client1"]["error_count"])
                self.assertIn("full audit remains visible", result["runtime"]["roles"]["client1"]["issues"][0]["message"])
                self.assertTrue(result["functional"]["issues"])

    def test_pending_seed_audit_keeps_functional_success_but_requires_review(self):
        evidence = {"requires_review": True, "seed_native_audit": {"pending": True, "status": "needs-review", "runtime_status": "unclassified-errors"}}
        result = self.build(self.root(), {"issues": [], "outcomes": [self.outcome()], "evidence": evidence})
        self.assertEqual("passed", result["functional"]["status"])
        self.assertEqual("clean", result["runtime"]["status"])
        self.assertEqual("needs-review", result["status"])
        self.assertEqual(evidence, result["functional"]["evidence"])


class AdapterRunnerBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.fixture = runner_helpers.NativeRunnerTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)

    def configure(self, attach=None):
        fixture = self.fixture
        fixture.selection["suite"] = "test-adapter"
        fixture.runtime["fixture"] = {"attach": attach or {}}
        (fixture.root / "client1/Lua").mkdir()
        report.write_json(fixture.root / "selection.json", fixture.selection)
        report.write_json(fixture.root / "runtime.json", fixture.runtime)
        fixture.content = "OWNED_READY\n"
        return SimpleNamespace(validate=lambda selection: None,
                               complete=lambda selection, role, text: "OWNED_READY" in text)

    def spec(self):
        return {"classpath": str(self.fixture.root / "owned-probe-classes"), "class": "AttachProbe",
                "jar": str(self.fixture.root / "owned-probe.jar"), "output": str(self.fixture.root / "probe.tsv"),
                "ready": "OWNED_READY", "pid": 999999}

    def test_unrelated_steam_game_can_coexist_with_isolated_profile(self):
        result, kills = self.fixture.invoke("37 /Steam/steamapps/common/Project Zomboid/Project Zomboid.app/Contents/MacOS/JavaAppLauncher\n")
        self.assertEqual('completed', result['status'])
        self.assertEqual([101], [call.args[0] for call in kills])

    def test_sigkill_disappearance_race_still_reaps_the_owned_process(self):
        process = Mock(pid=9876, returncode=None)
        process.poll.return_value = None
        reaped = []

        def wait(timeout):
            if not reaped:
                reaped.append(False)
                raise subprocess.TimeoutExpired("owned process", timeout)
            reaped.append(True)
            process.returncode = -9
            return -9

        process.wait.side_effect = wait
        with patch.object(runner.os, "killpg", side_effect=[None, ProcessLookupError]) as kill:
            runner.stop(process)
        self.assertEqual([(9876, signal.SIGTERM), (9876, signal.SIGKILL)], [call.args for call in kill.call_args_list])
        self.assertEqual([False, True], reaped)
        self.assertEqual(-9, process.returncode)

    def test_probe_descriptor_uses_only_the_current_owned_popen_pid(self):
        spec = self.spec()
        adapter = self.configure({"client1": [spec]})
        with patch.object(adapters, "get", return_value=adapter), patch.object(runner.subprocess, "run") as attach:
            result, kills = self.fixture.invoke()
        self.assertEqual("completed", result["status"])
        self.assertEqual(2, attach.call_count, "Probe must be attached and closed")
        for call in attach.call_args_list:
            command = call.args[0]
            self.assertEqual("101", command[-3])
            self.assertNotIn("999999", command)
        self.assertEqual([spec["output"], "stop"], [call.args[0][-1] for call in attach.call_args_list])
        self.assertEqual([101], [call.args[0] for call in kills])
        self.assertTrue((self.fixture.root / "client1/Lua/queue-probes-ready.txt").is_file())

    def test_probe_attachment_failure_cleans_the_owned_client(self):
        adapter = self.configure({"client1": [self.spec()]})
        with patch.object(adapters, "get", return_value=adapter), patch.object(runner.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "probe")):
            result, kills = self.fixture.invoke()
        self.assertEqual("failed", result["status"])
        self.assertEqual([101], [call.args[0] for call in kills])
        self.assertEqual(-15, result["processes"]["client1"]["exit_code"])
        self.assertEqual([], result["attachments"])
        self.assertFalse((self.fixture.root / "client1/Lua/queue-probes-ready.txt").exists())

    def test_unowned_probe_role_is_rejected_and_existing_owned_client_is_cleaned(self):
        adapter = self.configure({"client2": [self.spec()]})
        with patch.object(adapters, "get", return_value=adapter), patch.object(runner.subprocess, "run") as attach:
            result, kills = self.fixture.invoke()
        self.assertEqual("failed", result["status"])
        self.assertIn("not an owned client", result["error"])
        attach.assert_not_called()
        self.assertEqual([101], [call.args[0] for call in kills])

    def test_server_saves_and_quits_before_force_stop(self):
        fixture = self.fixture
        adapter = self.configure()
        fixture.selection.update(kind="mp", clients=1, languages=["EN"], ports=[17343, 17344])
        server = fixture.root / "server"
        (server / "Server").mkdir(parents=True)
        (server / "options.ini").write_text("voiceEnable=false\n")
        (server / "Server/queue-smoke.ini").write_text("VoiceEnable=false\n")
        fixture.runtime.update(server_name="queue-smoke")
        fixture.runtime["roles"]["server"] = {"cache": str(server)}
        report.write_json(fixture.root / "selection.json", fixture.selection)
        report.write_json(fixture.root / "runtime.json", fixture.runtime)
        fixture.content = "[QUEUE_TEST] SERVER_READY\nOWNED_READY\n"
        original = fixture.popen
        servers = []

        def popen(command, **kwargs):
            process = original(command, **kwargs)
            if "zombie.network.GameServer" in command:
                process.stdin = io.StringIO()
                servers.append(process)

                def wait(timeout):
                    self.assertEqual(30, timeout)
                    self.assertEqual("save\nquit\n", process.stdin.getvalue())
                    process.returncode = 0
                    return 0

                process.wait = wait
            return process

        fixture.popen = popen
        with patch.object(adapters, "get", return_value=adapter), patch.object(runner.admission.socket, "socket"):
            result, kills = fixture.invoke()
        self.assertEqual("completed", result["status"])
        self.assertEqual(1, len(servers))
        self.assertEqual(0, result["processes"]["server"]["exit_code"])
        self.assertEqual([102], [call.args[0] for call in kills], "Saved server must not need a signal")


if __name__ == "__main__":
    unittest.main()
