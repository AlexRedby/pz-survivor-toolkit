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
from tools.queue_checks import pack


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

        class Globals(SimpleNamespace):
            def __setitem__(self, key, value):
                setattr(self, key, value)

        class Runtime:
            def __init__(self, **kwargs):
                self.variables = Globals()

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

    def test_unrelated_source_paths_do_not_block_any_test_group(self):
        options = ("--medicine-framework-source", "--mpff-source", "--bc-filter-source",
                   "--native-inventory-context-menu", "--navigator-source", "--cleanui-inventory-pane",
                   "--native-inventory-pane", "--native-action-root")
        arguments = [value for option in options for value in (option, "/nonexistent/unrelated")]
        for name in ("test_ui_style", "test_item_tags", "test_tv_controls", "test_wishlist_model"):
            self.executions.clear()
            with self.subTest(name=name):
                self.invoke("--test", name, *arguments)
                self.assertEqual([source for source, _ in self.executions], [name + ".lua"])

    def test_source_consumers_keep_their_inputs_and_missing_inputs_fail(self):
        source = self.root / "source"
        inputs = {
            "pane.lua": "inventory pane", "clean.lua": "CleanUI pane", "context.lua": "native transfers",
            "ISTextBox.lua": "text box", "client/ISUI/ISTextBox.lua": "native text box",
            "client/ISUI/ISModalDialog.lua": "native modal", "medicine.lua": "moodles", "bc.lua": "BC filters",
            "shared/MPFastForward_Config.lua": "MPFF config", "server/MPFastForward_Server.lua": "MPFF server",
            "MonitorConfig.lua": "navigator config", "MonitorRender.lua": "navigator render",
            "NavigatorMonitorDrag.lua": "navigator drag",
        }
        for name, value in inputs.items():
            path = source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(value)
        cases = [
            (("test_inventory_tags", "test_inventory_filter", "test_inventory_layout", "test_inventory_interaction"),
             "--native-inventory-pane", source / "pane.lua", {"NativeInventoryPaneSource": "inventory pane"}),
            (("test_inventory_tags", "test_inventory_filter", "test_inventory_layout", "test_inventory_interaction"),
             "--cleanui-inventory-pane", source / "clean.lua", {"CleanUIInventoryPaneSource": "CleanUI pane"}),
            (("test_action_queue_operations",), "--native-inventory-context-menu", source / "context.lua",
             {"NativeInventoryContextMenuSource": "native transfers"}),
            (("test_quantity_transfers",), "--native-inventory-context-menu", source / "context.lua",
             {"NativeInventoryContextMenuSource": "native transfers", "NativeTextBoxSource": "text box"}),
            (("test_tag_filter_presets_menu",), "--native-action-root", source,
             {"NativeTextBoxSource": "native text box", "NativeModalDialogSource": "native modal"}),
            (("test_medicine_moodles",), "--medicine-framework-source", source / "medicine.lua", {"NativeMedicineFrameworkSource": "moodles"}),
            (("test_bc_filter_compat",), "--bc-filter-source", source / "bc.lua", {"NativeBCFilterSource": "BC filters"}),
            (("test_mpff_compat",), "--mpff-source", source,
             {"NativeMPFFConfigSource": "MPFF config", "NativeMPFFServerSource": "MPFF server"}),
            (("test_navigator",), "--navigator-source", source,
             {"NativeNavigatorConfig": "navigator config", "NativeNavigatorRender": "navigator render", "NativeNavigatorDrag": "navigator drag"}),
        ]
        for names, option, path, expected in cases:
            for name in names:
                self.executions.clear()
                with self.subTest(name=name, option=option):
                    self.invoke("--test", name, option, str(path))
                    variables = self.executions[0][1]
                    self.assertEqual({key: variables.get(key) for key in expected}, expected)
                    self.executions.clear()
                    with self.assertRaises(FileNotFoundError):
                        self.invoke("--test", name, option, "/nonexistent/required")
                    self.assertEqual(self.executions, [])

        (source / "ISTextBox.lua").unlink()
        self.invoke("--test", "test_action_queue_operations", "--native-inventory-context-menu", str(source / "context.lua"))

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
                          ("--test", "test_quartermaster_craft_ui"),
                          ('--integration', 'Navigator'),
                          ('--test', 'test_tv_videos', '--pack-lock', '/missing/pack.json')):
            with self.subTest(arguments=arguments), self.assertRaises(SystemExit) as failure:
                self.invoke(*arguments)
            self.assertEqual(failure.exception.code, 2)
        self.assertEqual(self.executions, [])

    def test_list_is_available_without_running_checks(self):
        self.invoke("--list")
        self.assertEqual(set(self.output.getvalue().splitlines()), self.names)

    def test_locked_integration_runs_only_real_navigator_source_branch(self):
        game = self.root / 'game'
        game.mkdir()
        (game / 'projectzomboid.jar').write_bytes(b'game')
        (self.root / 'SurvivorQoL-selected.ini').write_text('Mods=Navigator\n')
        layer = self.root / 'Navigator/42'
        layer.mkdir(parents=True)
        (layer / 'mod.info').write_text('id=Navigator\n')
        source = layer / 'media/lua/client/NavigatorRadio'
        source.mkdir(parents=True)
        for name in ('MonitorConfig.lua', 'MonitorRender.lua', 'NavigatorMonitorDrag.lua'):
            (source / name).write_text(name)
        lock = (self.root / 'pack.json').resolve()
        pack.create(self.root.resolve(), lock, game)
        self.invoke('--integration', 'Navigator', '--pack-lock', str(lock), '--game', str(game))
        self.assertEqual([name for name, _ in self.executions], ['test_navigator.lua'])
        variables = self.executions[0][1]
        self.assertEqual('MonitorConfig.lua', variables['NativeNavigatorConfig'])
        self.assertEqual('MonitorRender.lua', variables['NativeNavigatorRender'])
        self.assertEqual('NavigatorMonitorDrag.lua', variables['NativeNavigatorDrag'])

    def test_profile_listing_needs_no_lua_execution(self):
        self.invoke('--list-integrations')
        self.assertIn('QuartermasterTags.lua', self.output.getvalue())
        self.assertEqual([], self.executions)
        self.assertEqual(self.executions, [])


if __name__ == "__main__":
    unittest.main()
