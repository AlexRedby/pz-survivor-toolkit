"""Snapshot preparation checks without Steam, Java compilation, or a game launch."""
import sys
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import native


class NativeSnapshotTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        self.project, self.game, self.jdk = [self.root / name for name in ("project", "game", "jdk")]
        for relative in ("projectzomboid.jar", "media/lua/shared/native.lua"):
            self.write(self.game / relative, "native input")
        for relative in ("bin/java", "bin/javac"):
            self.write(self.jdk / relative, "fake Java executable")
            (self.jdk / relative).chmod(0o755)
        shutil.copytree(ROOT / "tests/native_queue/support", self.project / "tests/native_queue/support")
        self.write(self.project / "tools/check_action_queue.py", "# queue CLI\n")
        self.write(self.project / "tools/queue_checks/report.py", "# report framework\n")
        self.write(self.project / "tests/native_queue/catalog.json", '{}\n')
        for side in ("client", "server", "shared"):
            self.write(self.project / "tests/native_queue/health" / side / "suite.lua", "return {}\n")
        self.mod(self.project / "Toolkit", "PZSurvivorToolkit")
        self.selection = {"schema_version": 1, "suite": "health", "kind": "sp", "mode": "toolkit",
                          "cases": ["bandageApply"], "mods": ["PZSurvivorToolkit"], "languages": ["EN"],
                          "timeout_seconds": 60, "ports": [17343, 17344], "expected_checks": 3}
        self.compiler = patch.object(native.subprocess, "run", side_effect=self.compile)
        self.compile_mock = self.compiler.start()
        self.addCleanup(self.compiler.stop)

    @staticmethod
    def write(path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def mod(self, path, identifier, layer="42"):
        self.write(path / layer / "mod.info", "name=Test\nid = " + identifier + "\n")
        self.write(path / layer / "media/lua/shared/test.lua", "return 'unchanged mod source'\n")
        return path

    @staticmethod
    def compile(command, **kwargs):
        Path(command[-1]).with_suffix(".class").write_bytes(b"fake class")

    def prepare(self, name="run", **changes):
        selection = dict(self.selection, **changes)
        return native.prepare(self.project, self.root / name, self.game, self.jdk, selection)

    def test_fresh_snapshot_pins_sources_configs_mods_and_compiler_output(self):
        output = self.prepare()
        self.assertEqual(self.compile_mock.call_args.args[0][0], str(self.jdk / "bin/javac"))
        source = json.loads((output / "source-manifest.json").read_text())
        original = self.project / "Toolkit/42/media/lua/shared/test.lua"
        self.assertEqual(source[str(original)], native.sha256(original))
        self.assertIn(str(self.game / "media/lua/shared/native.lua"), source)
        self.assertIn(str(self.project / "tools/queue_checks/report.py"), source)
        self.assertIn(str(self.project / "tools/check_action_queue.py"), source)
        self.assertIn(str(self.project / "tests/native_queue/catalog.json"), source)
        snapshot = json.loads((output / "snapshot-hashes.json").read_text())
        for relative in ("selection.json", "runtime.json", "initial-settings.json", "client1/classes/ToolkitSmokeLauncher.class",
                         "client1/Lua/queue-expected-mods.txt", "client1/mods/ActionQueueTest/42/media/lua/shared/QueueTestSelection.lua"):
            self.assertEqual(snapshot[relative], native.sha256(output / relative))
        copied = output / "client1/mods/PZSurvivorToolkit/42/media/lua/shared/test.lua"
        self.assertEqual(copied.read_bytes(), original.read_bytes())
        self.assertIn("voiceEnable=false", (output / "client1/options.ini").read_text())
        self.assertNotIn("client1/options.ini", snapshot)
        settings = json.loads((output / "initial-settings.json").read_text())
        self.assertEqual(settings["client1/options.ini"], (output / "client1/options.ini").read_text())
        self.write(original, "changed after preparation")
        self.assertNotEqual(source[str(original)], native.sha256(original))
        self.assertNotEqual(copied.read_bytes(), original.read_bytes())

    def test_refuses_existing_output_without_changing_it(self):
        output = self.prepare()
        self.write(output / "evidence.log", "keep evidence")
        with self.assertRaisesRegex(FileExistsError, "Fresh"):
            self.prepare()
        self.assertEqual((output / "evidence.log").read_text(), "keep evidence")
        self.assertEqual(self.compile_mock.call_count, 1)

    def test_fingerprint_compares_native_and_toolkit_but_detects_settings_and_source_changes(self):
        def fingerprint(path):
            return json.loads((path / "settings-fingerprint.json").read_text())["sha256"]
        baseline = fingerprint(self.prepare("toolkit"))
        self.assertEqual(baseline, fingerprint(self.prepare("native", mode="native")))
        self.assertNotEqual(baseline, fingerprint(self.prepare("ru", languages=["RU"])))
        self.write(self.project / "Toolkit/42/media/lua/shared/test.lua", "changed source")
        self.assertNotEqual(baseline, fingerprint(self.prepare("changed")))

    def test_mp_has_concurrent_roles_languages_ports_and_no_voice(self):
        output = self.prepare(kind="mp", languages=["EN", "RU"], ports=[17501, 17502])
        runtime = json.loads((output / "runtime.json").read_text())
        self.assertEqual(set(runtime["roles"]), {"server", "client1", "client2"})
        self.assertEqual(runtime["roles"]["client2"]["language"], "RU")
        self.assertIn("language=RU", (output / "client2/options.ini").read_text())
        server = (output / "server/Server/queue-smoke.ini").read_text()
        self.assertIn("VoiceEnable=false", server)
        self.assertIn("DefaultPort=17501\nUDPPort=17502", server)
        config = (output / "client2/mods/ActionQueueTest/42/media/lua/shared/QueueTestSelection.lua").read_text()
        self.assertIn('["port"]=17501', config)
        self.assertIn("return QueueTestSelection", config)
        for role in ("server", "client1"):
            self.assertEqual(config, (output / role / "mods/ActionQueueTest/42/media/lua/shared/QueueTestSelection.lua").read_text(), "Shared MP Lua must keep native checksums identical")
        self.assertEqual(self.compile_mock.call_count, 2)

    def test_output_inside_source_mod_and_ambiguous_runtime_paths_fail(self):
        for output in (self.project / "Toolkit" / "run", self.root / "bad,path"):
            with self.subTest(output=output), self.assertRaises(ValueError):
                native.prepare(self.project, output, self.game, self.jdk, self.selection)
            self.assertFalse(output.exists())
        with self.assertRaises(ValueError):
            self.prepare(kind="mp", languages=["EN"])

    def test_workshop_requires_exact_unambiguous_id_across_all_roots(self):
        self.selection["mods"].append("External")
        first, second = self.root / "workshop1", self.root / "workshop2"
        first.mkdir()
        second.mkdir()
        with self.assertRaisesRegex(ValueError, "External"):
            native.prepare(self.project, self.root / "missing", self.game, self.jdk, self.selection, [first])
        self.mod(first / "123/mods/External", "external")
        with self.assertRaisesRegex(ValueError, "External"):
            native.prepare(self.project, self.root / "wrongcase", self.game, self.jdk, self.selection, [first])
        self.mod(first / "124/mods/External", "External")
        self.mod(second / "124/mods/External", "External")
        with self.assertRaisesRegex(ValueError, "exactly once"):
            native.prepare(self.project, self.root / "ambiguous", self.game, self.jdk, self.selection, [first, second])
        output = native.prepare(self.project, self.root / "good", self.game, self.jdk, self.selection, [first, first])
        self.assertTrue((output / "client1/mods/External/42/mod.info").is_file())

    def test_local_source_wins_over_workshop_copy_and_repeated_jars_keep_exact_hashes(self):
        workshop = self.root / "workshop"
        self.mod(workshop / "1/mods/OldToolkit", "PZSurvivorToolkit")
        for relative in ("42/media/java/one.jar", "42/media/java/two.jar"):
            self.write(self.project / "Toolkit" / relative, "same jar bytes")
        output = native.prepare(self.project, self.root / "run", self.game, self.jdk, self.selection, [workshop])
        mods = json.loads((output / "manifest.json").read_text())
        self.assertEqual(mods[0]["source"], str(self.project / "Toolkit"))
        approvals = json.loads((output / "client1/zombie-buddy/mod_approvals.json").read_text())["mods"]
        self.assertEqual(len(approvals), 2)
        self.assertEqual(approvals[0]["jar_hash"], approvals[1]["jar_hash"])

    def test_invalid_inputs_do_not_create_output(self):
        for changes in ({"cases": []}, {"mods": ["PZSurvivorToolkit"] * 2}, {"expected_checks": 7},
                        {"ports": [17343, 17343]}, {"kind": "invalid"}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.prepare(**changes)
            self.assertFalse((self.root / "run").exists())
        (self.jdk / "bin/javac").unlink()
        with self.assertRaisesRegex(ValueError, "Missing game/JDK"):
            self.prepare()
        self.assertFalse((self.root / "run").exists())

    def test_incompatible_layer_and_duplicate_local_ids_fail(self):
        self.mod(self.project / "Duplicate", "PZSurvivorToolkit")
        with self.assertRaisesRegex(ValueError, "exactly once"):
            self.prepare()
        shutil.rmtree(self.project / "Duplicate")
        (self.project / "Toolkit/42").rename(self.project / "Toolkit/43")
        with self.assertRaisesRegex(ValueError, "compatible 42.21"):
            self.prepare()

    def test_selected_layer_cannot_hide_a_different_mod_id(self):
        self.write(self.project / "Toolkit/common/mod.info", "id=PZSurvivorToolkit\n")
        self.write(self.project / "Toolkit/42/mod.info", "id=OtherToolkit\n")
        with self.assertRaisesRegex(ValueError, "different Mod ID"):
            self.prepare()

    def test_source_changes_during_preparation_are_rejected(self):
        def change_source(command, **kwargs):
            self.compile(command, **kwargs)
            self.write(self.project / "tests/native_queue/shared.lua", "unrelated file")
            self.write(self.project / "Toolkit/42/media/lua/shared/test.lua", "changed during compile")
        self.compile_mock.side_effect = change_source
        with self.assertRaisesRegex(RuntimeError, "Source changed"):
            self.prepare()
        self.assertFalse((self.root / "run/snapshot-hashes.json").exists())

    def test_common_builder_accepts_another_fixture_suite(self):
        shutil.copytree(self.project / "tests/native_queue/health", self.project / "tests/native_queue/crafting")
        output = self.prepare(suite="crafting")
        selection = json.loads((output / "selection.json").read_text())
        self.assertEqual(selection["suite"], "crafting")


if __name__ == "__main__":
    unittest.main()
