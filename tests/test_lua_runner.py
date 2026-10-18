"""Focused selection must retain each test's setup and variants."""

from contextlib import redirect_stderr, redirect_stdout
import io
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools import run_tests


class LuaRunner(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.names = set(run_tests.TAG_TESTS) | set(run_tests.ACTION_TESTS) | set(run_tests.EXTRA_TESTS)
        self.names.add("test_wishlist_model.lua")
        for name in self.names:
            path = self.root / "tests" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(name)
        (self.root / "PZSurvivorToolkit").mkdir()
        (self.root / "PZSurvivorToolkit" / "module.lua").write_text("return {}")
        (self.root / "PZSurvivorWishlist").mkdir()
        (self.root / "PZSurvivorWishlist" / "module.lua").write_text("return {}")
        for language in ("EN", "RU"):
            path = self.root / "PZSurvivorToolkit/42/media/lua/shared/Translate" / language
            path.mkdir(parents=True)
            (path / "UI.json").write_text("{}")
        self.executions = []
        self.output = io.StringIO()

    def invoke(self, *arguments):
        executions = self.executions

        class Runtime:
            def __init__(self, **kwargs):
                self.variables = SimpleNamespace()

            def globals(self):
                return self.variables

            def execute(self, source, *args):
                executions.append((source, vars(self.variables).copy()))

            def table_from(self, value, **kwargs):
                return value

        with patch.object(run_tests, "ROOT", self.root), \
                patch.object(sys, "argv", ["run_tests.py", *arguments]), \
                patch.dict(sys.modules, {"lupa.lua51": SimpleNamespace(LuaRuntime=Runtime)}), \
                redirect_stdout(self.output), redirect_stderr(self.output):
            run_tests.main()

    def test_selection_skips_unrelated_sources_and_full_syntax_scan(self):
        self.invoke("--test", "test_tv_controls", "--test", "test_wishlist_model.lua",
                    "--cci-source", "/nonexistent/unrelated-source.lua")
        self.assertEqual([name for name, _ in self.executions],
                         ["test_tv_controls.lua", "test_wishlist_model.lua"])

    def test_default_keeps_all_groups_and_reconnect_variants(self):
        self.invoke()
        names = [name for name, _ in self.executions]
        conditional = {"test_quartermaster_craft_ui.lua", "native_tags/check_transfer_source.lua",
                       "native_tags/check_placement.lua"}
        self.assertEqual(set(names) - {"assert(loadstring(...))"}, self.names - conditional)
        self.assertEqual(names.count("assert(loadstring(...))"), 1)
        self.assertEqual(names.count("native_tags/check_reconnect.lua"), 4)

    def test_selection_retains_tv_sources_without_reading_other_test_inputs(self):
        source = self.root / "tv/RadioWindowModules/RWMMergedTV.lua"
        source.parent.mkdir(parents=True)
        source.write_text("upstream TV")
        (source.parent.parent / "ISRadioWindow.lua").write_text("native window")
        self.invoke("--test", "test_tv_controls", "--tv-source", str(source),
                    "--native-mod-options", "/nonexistent/unrelated-options.lua")
        self.assertEqual(self.executions, [("test_tv_controls.lua",
                         {"ProjectRoot": str(self.root), "TVSource": "upstream TV",
                          "NativeTVWindowSource": "native window"})])

    def test_selection_retains_reconnect_variants_and_native_setup(self):
        self.invoke("--test", "native_tags/check_reconnect")
        self.assertEqual(len(self.executions), 4)
        self.assertTrue(self.executions[1][1]["BaselineTagReconnect"])
        self.assertTrue(self.executions[2][1]["RestartTagReconnect"])
        self.assertTrue(self.executions[3][1]["PlantingTagReconnect"])
        self.executions.clear()
        self.invoke("--test", "test_quartermaster_craft_ui", "--quartermaster-source", "/mod",
                    "--native-action-root", "/native")
        self.assertEqual(self.executions, [("test_quartermaster_craft_ui.lua",
                         {"ProjectRoot": str(self.root), "NativePZLuaRoot": "/native",
                          "NativeQuartermasterLuaRoot": "/mod"})])

    def test_invalid_or_unconfigured_selection_fails_before_execution(self):
        for arguments in (("--test", "test_tv_controls", "--test", "missing"),
                          ("--test", "native_tags/check_placement"),
                          ("--test", "test_quartermaster_craft_ui")):
            with self.subTest(arguments=arguments), self.assertRaises(SystemExit) as failure:
                self.invoke(*arguments)
            self.assertEqual(failure.exception.code, 2)
        self.assertEqual(self.executions, [])

    def test_list_is_available_without_running_checks(self):
        self.invoke("--list")
        self.assertEqual(set(self.output.getvalue().splitlines()), self.names)
        self.assertEqual(self.executions, [])


if __name__ == "__main__":
    unittest.main()
