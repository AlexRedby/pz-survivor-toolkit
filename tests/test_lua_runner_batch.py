"""Batch reporting and failure isolation for the offline Lua runner."""

from contextlib import redirect_stderr, redirect_stdout
import io
import importlib.util
import json
from pathlib import Path
import sys
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools import run_tests


class LuaRunnerBatch(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.output = io.StringIO()
        (self.root / "tests/native_tags").mkdir(parents=True)
        (self.root / "tests/test_one.lua").write_text("test_one")
        (self.root / "tests/test_two.lua").write_text("test_two")
        (self.root / "tests/native_tags/check_reconnect.lua").write_text("reconnect")
        for name in ("check_sort_receipts.lua", "check_barrier.lua", "check_transfer_source.lua", "check_placement.lua"):
            (self.root / "tests/native_tags" / name).write_text(name)
        (self.root / "tests/test_quartermaster_craft_ui.lua").write_text("optional")
        for name in ("test_action_queue_alpha.lua", "test_action_queue_fridge_compat.lua",
                     "test_wash_water_rule.lua", "test_wash_unrelated_future.lua",
                     "test_empty_fluid_action.lua", "test_source_proof.lua", "test_ui_misc.lua"):
            (self.root / "tests" / name).write_text(name)
        (self.root / "PZSurvivorToolkit").mkdir()
        (self.root / "PZSurvivorToolkit/42/media/lua/shared/Translate/EN").mkdir(parents=True)
        (self.root / "PZSurvivorToolkit/42/media/lua/shared/Translate/RU").mkdir(parents=True)
        for language in ("EN", "RU"):
            (self.root / f"PZSurvivorToolkit/42/media/lua/shared/Translate/{language}/UI.json").write_text("{}")

    def invoke(self, arguments, failures=()):
        executions = []
        failures = set(failures)

        class Globals(dict):
            pass

        class Runtime:
            def __init__(self, **kwargs):
                self.variables = Globals()

            def globals(self):
                return self.variables

            def execute(self, source, *args):
                name = source.strip()
                variant = next((key for key in self.variables if key.startswith("Baseline") or
                                key.startswith("Restart") or key.startswith("Planting")), "default")
                executions.append((name, variant))
                if (name, variant) in failures:
                    raise RuntimeError("failed " + name + "/" + variant)

            def table_from(self, value, **kwargs):
                return value

        with patch.object(run_tests, "ROOT", self.root), \
                patch.object(sys, "argv", ["run_tests.py", *arguments]), \
                patch.dict(sys.modules, {"lupa.lua51": SimpleNamespace(LuaRuntime=Runtime)}), \
                redirect_stdout(self.output), redirect_stderr(self.output):
            try:
                run_tests.main()
            except SystemExit as error:
                return error.code, executions
            except Exception as error:
                return error, executions
        return 0, executions

    def report(self, path):
        return json.loads(path.read_text())

    def test_keep_going_collects_multiple_failures_and_variants_are_isolated(self):
        path = self.root / "report.json"
        code, runs = self.invoke(["--keep-going", "--report", str(path), "--test", "test_one",
                                  "--test", "native_tags/check_reconnect"],
                                 {("reconnect", "BaselineTagReconnect"), ("reconnect", "RestartTagReconnect")})
        report = self.report(path)
        self.assertEqual(code, 1)
        self.assertEqual(len(runs), 5)
        self.assertEqual(len({variant for name, variant in runs if name == "reconnect"}), 4)
        self.assertEqual(report["counts"], {"passed": 3, "partial": 0, "failed": 2, "skipped": 0, "total": 5})
        self.assertEqual([item["status"] for item in report["results"]], ["passed", "failed", "failed", "passed", "passed"])
        self.assertIn("FAILED native_tags/check_reconnect.lua [BaselineTagReconnect]: failed reconnect/BaselineTagReconnect", self.output.getvalue())

    def test_default_stops_at_first_failure(self):
        path = self.root / "report.json"
        code, runs = self.invoke(["--report", str(path), "--test", "test_one", "--test", "native_tags/check_reconnect"],
                                 {("reconnect", "default")})
        report = self.report(path)
        self.assertIsInstance(code, RuntimeError)
        self.assertIn("failed reconnect/default", str(code))
        self.assertEqual(runs, [("reconnect", "default")])
        self.assertEqual(report["counts"]["failed"], 1)
        self.assertEqual(report["status"], "failed")

    def test_optional_native_path_is_reported_as_partial_and_nonzero_if_another_fails(self):
        path = self.root / "report.json"
        code, _ = self.invoke(["--keep-going", "--report", str(path)], {("test_one", "default")})
        report = self.report(path)
        self.assertEqual(code, 1)
        self.assertEqual(report["counts"]["failed"], 1)
        self.assertGreaterEqual(report["counts"]["skipped"], 1)
        self.assertEqual(report["counts"]["partial"], 0)
        self.assertEqual(report["status"], "failed")
        self.assertIn("did not run", report["limitations"][0])
        self.assertEqual(report["results"][1]["status"], "skipped")

    def test_success_has_per_variant_elapsed_time(self):
        path = self.root / "report.json"
        code, _ = self.invoke(["--report", str(path), "--test", "test_two"])
        report = self.report(path)
        self.assertEqual(code, 0)
        self.assertEqual(report["status"], "passed")
        self.assertEqual(report["results"][0]["test"], "test_two.lua")
        self.assertGreaterEqual(report["results"][0]["elapsed_seconds"], 0)

    def test_action_queue_group_discovers_future_tests_and_unions_explicit_selection(self):
        future = self.root / "tests/test_action_queue_new.lua"
        future.write_text("test_action_queue_new.lua")
        _, runs = self.invoke(["--group", "action-queue", "--test", "test_action_queue_alpha",
                               "--test", "test_two", "--native-action-root", "/native",
                               "--wishlist-workshop-root", "/workshop", "--fridge-source", "/fridge"])
        names = [source for source, _ in runs]
        self.assertEqual(set(names), {
            "test_action_queue_alpha.lua", "test_action_queue_fridge_compat.lua",
            "test_action_queue_new.lua", "test_wash_water_rule.lua",
            "test_wash_unrelated_future.lua", "test_empty_fluid_action.lua", "test_source_proof.lua",
            "test_two",
        })
        self.assertEqual(names.count("test_action_queue_alpha.lua"), 1)
        self.assertNotIn("test_ui_misc.lua", names)

    def test_action_queue_group_list_shows_only_group_and_explicit_union(self):
        self.invoke(["--list", "--group", "action-queue", "--test", "test_two"])
        listed = self.output.getvalue().splitlines()
        self.assertIn("test_action_queue_alpha.lua", listed)
        self.assertIn("test_wash_water_rule.lua", listed)
        self.assertIn("test_two.lua", listed)
        self.assertNotIn("test_ui_misc.lua", listed)

    def test_action_queue_group_keeps_required_source_preflight(self):
        code, runs = self.invoke(["--group", "action-queue"])
        self.assertEqual(code, 2)
        self.assertEqual(runs, [])
        self.assertIn("--fridge-source", self.output.getvalue())

    @unittest.skipUnless(importlib.util.find_spec("lupa"), "Lupa is required for the real Lua print regression")
    def test_real_lua_print_skip_and_failure_are_captured_in_subprocess(self):
        for name, source in (("pass", "print('real Lua pass'); print('safe skips'); print('skipped-task'); print('idle rows skip permissions')"),
                             ("skip", "print('real Lua SKIP optional check')"),
                             ("lower_skip", "print('Source checks skipped (pass --game).')"),
                             ("fail", "print('real Lua failure') error('real failure')")):
            (self.root / f"tests/test_{name}.lua").write_text(source)
        script = self.root / "exercise_runner.py"
        script.write_text("""\
import json, sys
from pathlib import Path
from types import SimpleNamespace
from lupa.lua51 import LuaRuntime
from tools import run_tests
run_tests.ROOT = Path(sys.argv[1])
args = SimpleNamespace(keep_going=True, native_action_root=None, wishlist_game_root=None,
    wishlist_workshop_root=None, saucedcarts_source=None, vhs_tooltip_root=None,
    bci_tooltip_root=None, native_mod_options=None, wheelbarrow_source=None,
    native_inventory_context_menu=None, native_radio_root=None, native_uninstall=None,
    native_vehicles=None, fridge_source=None, vva_source=None, project_cook_picker=None,
    native_inventory_pane=None, cleanui_inventory_pane=None, oc_stick_source=None,
    oc_display_source=None)
results = [run_tests._run_variant('test_' + name + '.lua', None, args, LuaRuntime)
           for name in ('pass', 'skip', 'lower_skip', 'fail')]
print('RESULTS=' + json.dumps(results))
""")
        result = subprocess.run([sys.executable, "-c", script.read_text(), str(self.root)], text=True,
                                capture_output=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("real Lua pass", result.stdout)
        self.assertIn("real Lua SKIP optional check", result.stdout)
        self.assertIn("real Lua failure", result.stdout)
        report = json.loads(result.stdout.split("RESULTS=", 1)[1])
        self.assertEqual([item["status"] for item in report], ["passed", "partial", "partial", "failed"])
        self.assertIn("real Lua SKIP optional check", report[1]["partial_reasons"][0])
        self.assertIn("checks skipped", report[2]["partial_reasons"][0])
        self.assertIn("real failure", report[3]["error"])


if __name__ == "__main__":
    unittest.main()
