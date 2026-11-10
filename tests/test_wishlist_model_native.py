import contextlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

from tools import check_wishlist_model_native as runner


class NativeRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / "repo"
        self.game = self.base / "game"
        self.jdk = self.base / "jdk"
        self.output = self.base / "output"
        self.sources = ["tools/check_wishlist_model_native.py", "tests/native_wishlist_model/WishlistModelChecks.java", "tests/test_wishlist_model.lua",
                        "PZSurvivorToolkit/42/media/lua/shared/PZSurvivorWishlist/Model.lua",
                        "PZSurvivorToolkit/42/media/lua/server/PZSurvivorWishlist/Server.lua"]
        for path in [*(self.root / name for name in self.sources), self.game / "projectzomboid.jar",
                     self.game / "stdlib.lbc", self.jdk / "bin/java", self.jdk / "bin/javac"]:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(str(path.name))
        patch = mock.patch.object(runner, "ROOT", self.root)
        patch.start()
        self.addCleanup(patch.stop)
        self.args = ["--game", str(self.game), "--jdk", str(self.jdk), "--output", str(self.output)]

    def run_cli(self, responses):
        with mock.patch.object(runner.subprocess, "run", side_effect=responses) as process, contextlib.redirect_stdout(io.StringIO()):
            code = runner.main(self.args)
        report = json.loads((self.output / "report.json").read_text())
        return code, report, process

    @staticmethod
    def result(code=0, stdout="", stderr=""):
        return subprocess.CompletedProcess([], code, stdout, stderr)

    def test_valid_and_source_fingerprints(self):
        markers = "\n".join(runner.MARKERS) + "\n"
        code, report, process = self.run_cli([self.result(), self.result(stdout=markers)])
        self.assertEqual(code, 0)
        self.assertEqual(report["status"], "passed")
        self.assertEqual(set(report["sources"]), set(self.sources))
        self.assertEqual(set(report["inputs"]), {"game_jar", "stdlib", "java", "javac"})
        self.assertEqual(process.call_count, 2)
        self.assertIn("-Djava.awt.headless=true", process.call_args_list[1].args[0])
        before = report["sources"][self.sources[2]]["sha256"]
        (self.root / self.sources[2]).write_text("changed")
        self.assertNotEqual(before, runner.fingerprint(self.root / self.sources[2])["sha256"])
        self.assertEqual((self.output / "run.log").read_text(), markers)

    def test_input_and_existing_output_rejected_without_mutation(self):
        (self.game / "stdlib.lbc").unlink()
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            runner.main(self.args)
        self.assertFalse(self.output.exists())
        (self.game / "stdlib.lbc").write_text("stdlib")
        self.output.mkdir()
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            runner.main(self.args)
        self.assertEqual(list(self.output.iterdir()), [])

    def test_mutation_and_source_membership_rejected(self):
        markers = "\n".join(runner.MARKERS) + "\n"
        server = self.root / self.sources[-1]
        added = server.parent / "Added.lua"
        for name in ("compiler_mutation", "jvm_mutation", "added", "removed", "input_mutation"):
            with self.subTest(name=name):
                self.output = self.base / name
                self.args[-1] = str(self.output)
                server.write_text("original")
                added.unlink(missing_ok=True)
                (self.game / "stdlib.lbc").write_text("stdlib")
                calls = []
                def invoke(*args, **kwargs):
                    calls.append(args)
                    if (name == "compiler_mutation" and len(calls) == 1) or (name == "jvm_mutation" and len(calls) == 2):
                        server.write_text("changed")
                    if len(calls) == 2:
                        if name == "added":
                            added.write_text("new")
                        elif name == "removed":
                            server.unlink()
                        elif name == "input_mutation":
                            (self.game / "stdlib.lbc").write_text("changed")
                    return self.result(stdout=markers if len(calls) == 2 else "")
                code, report, _ = self.run_cli(invoke)
                self.assertEqual(code, 1)
                self.assertEqual(report["status"], "failed")
                self.assertTrue(report["input_issues"])

    def test_failed_compiler(self):
        code, report, process = self.run_cli([self.result(1, stderr="compile error")])
        self.assertEqual(code, 1)
        self.assertEqual(report["compile_exit"], 1)
        self.assertIsNone(report["run_exit"])
        self.assertEqual(process.call_count, 1)
        self.assertIn("compile error", (self.output / "compile.log").read_text())

    def test_process_timeout_is_a_failed_report(self):
        code, report, _ = self.run_cli([self.result(), subprocess.TimeoutExpired("java", 60)])
        self.assertEqual(code, 1)
        self.assertEqual(report["status"], "failed")
        self.assertIn("timed out", report["error"])

    def test_failed_jvm_and_invalid_markers(self):
        markers = "\n".join(runner.MARKERS) + "\n"
        for name, result in [("jvm", self.result(1, markers)), ("missing", self.result(stdout=markers.replace(runner.MARKERS[0], ""))),
                             ("duplicate", self.result(stdout=markers + runner.MARKERS[0] + "\n"))]:
            with self.subTest(name=name):
                self.output = self.base / name
                self.args[-1] = str(self.output)
                code, report, _ = self.run_cli([self.result(), result])
                self.assertEqual(code, 1)
                self.assertEqual(report["status"], "failed")


if __name__ == "__main__":
    unittest.main()
