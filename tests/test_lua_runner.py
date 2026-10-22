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
        self.names = set(run_tests.discover_tests(run_tests.ROOT))
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
        self.owned_root = str(self.root / "PZSurvivorToolkit/42/media/lua")
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
                    "--mpff-source", "/nonexistent/unrelated-source")
        self.assertEqual([name for name, _ in self.executions],
                         ["test_tv_controls.lua", "test_wishlist_model.lua"])

    def test_new_top_level_check_is_discovered_and_executed_without_registration(self):
        name = "test_new_extra.lua"
        (self.root / "tests" / name).write_text(name)
        self.invoke("--test", name)
        self.assertEqual(self.executions, [(name, {"ProjectRoot": str(self.root), "NativeQuartermasterLuaRoot": self.owned_root})])

    def test_default_keeps_all_checks_and_reconnect_variants(self):
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
                         {"ProjectRoot": str(self.root), "NativeQuartermasterLuaRoot": self.owned_root,
                          "TVSource": "upstream TV",
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
        self.invoke("--test", "test_quartermaster_craft_ui", "--native-action-root", "/native")
        self.assertEqual(self.executions, [("test_quartermaster_craft_ui.lua",
                         {"ProjectRoot": str(self.root), "NativePZLuaRoot": "/native", "NativeActionRoot": "/native",
                          "NativeQuartermasterLuaRoot": str(self.root / "PZSurvivorToolkit/42/media/lua")})])

    def test_quartermaster_checks_use_owned_sources_without_external_options(self):
        self.invoke("--test", "test_quartermaster_tag_rules", "--test", "test_action_queue_manifest")
        self.assertEqual({source for source, _ in self.executions},
                         {"test_quartermaster_tag_rules.lua", "test_action_queue_manifest.lua"})
        for _, variables in self.executions:
            self.assertEqual(variables["NativeQuartermasterLuaRoot"],
                             str(self.root / "PZSurvivorToolkit/42/media/lua"))
        self.executions.clear()
        with self.assertRaises(SystemExit):
            self.invoke("--quartermaster-source", "/external")
        self.assertEqual(self.executions, [])

    def test_game_supplies_selected_native_sources_and_preserves_explicit_overrides(self):
        game = self.root / 'game'
        native = game / 'media/lua'
        native.mkdir(parents=True)
        (game / 'projectzomboid.jar').write_bytes(b'game')
        sources = {
            'client/ISUI/ISInventoryPane.lua': 'game inventory',
            'shared/Vehicles/TimedActions/ISUninstallVehiclePart.lua': 'game uninstall',
            'server/Vehicles/Vehicles.lua': 'game vehicle items',
            'client/RadioCom/RadioWindowModules/RWMMedia.lua': 'game media',
            'client/RadioCom/ISUIRadio/ISItemDropBox.lua': 'game dropbox',
        }
        for relative, content in sources.items():
            path = native / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        override = self.root / 'candidate-pane.lua'
        override.write_text('candidate inventory')
        self.invoke('--game', str(game), '--native-inventory-pane', str(override),
                    '--test', 'test_inventory_tags', '--test', 'test_vehicle_ground',
                    '--test', 'test_tv_controls', '--test', 'test_wishlist_model',
                    '--test', 'native_tags/check_placement')
        selected = dict(self.executions)
        self.assertEqual(set(selected), {'test_inventory_tags.lua', 'test_vehicle_ground.lua',
                                        'test_tv_controls.lua', 'test_wishlist_model.lua',
                                        'native_tags/check_placement.lua'})
        self.assertEqual(selected['test_inventory_tags.lua']['NativeInventoryPaneSource'], 'candidate inventory')
        self.assertEqual(selected['test_vehicle_ground.lua']['NativeUninstallSource'], 'game uninstall')
        self.assertEqual(selected['test_vehicle_ground.lua']['NativeVehicleItemsSource'], 'game vehicle items')
        self.assertEqual(selected['test_tv_controls.lua']['NativeMediaSource'], 'game media')
        self.assertEqual(selected['test_tv_controls.lua']['NativeDropBoxSource'], 'game dropbox')
        self.assertEqual(selected['test_wishlist_model.lua']['NativeWishlistGameRoot'], str(game.resolve()))
        self.assertEqual(selected['native_tags/check_placement.lua']['NativePZLuaRoot'], str(native.resolve()))

    def test_game_reads_only_selected_inputs_and_missing_required_sources_fail(self):
        game = self.root / 'game'
        game.mkdir()
        with self.assertRaises(SystemExit) as failure:
            self.invoke('--game', str(game), '--test', 'test_ui_style')
        self.assertEqual(failure.exception.code, 2)
        self.assertEqual(self.executions, [])
        (game / 'projectzomboid.jar').write_bytes(b'game')
        self.invoke('--game', str(game), '--test', 'test_ui_style')
        self.assertEqual([source for source, _ in self.executions], ['test_ui_style.lua'])
        self.executions.clear()
        with self.assertRaises(FileNotFoundError):
            self.invoke('--game', str(game), '--test', 'test_inventory_tags')
        self.assertEqual(self.executions, [])

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

    def test_discovery_does_not_admit_nested_native_scenarios_or_helper_files(self):
        for name in ("helper.lua", "native_queue/test_scenario.lua", "native_tags/check_unregistered.lua"):
            path = self.root / "tests" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("must not execute")
        (self.root / "tests/test_directory.lua").mkdir()
        self.invoke("--list")
        self.assertEqual(set(self.output.getvalue().splitlines()), self.names)
        self.assertEqual(self.executions, [])

    def test_fire_variants_are_isolated_and_keep_the_same_source_paths(self):
        self.invoke("--test", "test_action_queue_fire", "--native-action-root", "/native",
                    "--wishlist-workshop-root", "/workshop", "--saucedcarts-source", "/carts")
        flags = ["FireTestBCPreinstalled", "FireTestBCForeignPredecessor", "FireTestQMBeforeBC",
                 "FireTestQMPreloaded", "FireTestQMForeignPredecessor", "FireTestQMForeignGather"]
        self.assertEqual(len(self.executions), 7)
        for index, (name, variables) in enumerate(self.executions):
            with self.subTest(index=index):
                self.assertEqual(name, "test_action_queue_fire.lua")
                self.assertEqual(variables["NativeActionRoot"], "/native")
                self.assertEqual(variables["NativeWishlistWorkshopRoot"], "/workshop")
                self.assertEqual(variables["SaucedCartsSource"], "/carts")
                self.assertEqual(variables["NativeQuartermasterLuaRoot"], self.owned_root)
                self.assertEqual({flag for flag in flags if variables.get(flag)},
                                 set() if index == 0 else {flags[index - 1]})
        self.executions.clear()
        self.invoke("--test", "test_action_queue_fire", "--native-action-root", "/native")
        self.assertEqual(len(self.executions), 1)

    def test_common_source_paths_are_available_to_new_checks_without_new_dispatch(self):
        name = "test_new_paths.lua"
        (self.root / "tests" / name).write_text(name)
        self.invoke("--test", name, "--native-action-root", "/native",
                    "--wishlist-game-root", "/game", "--wishlist-workshop-root", "/workshop",
                    "--saucedcarts-source", "/carts")
        self.assertEqual(self.executions, [(name, {
            "ProjectRoot": str(self.root), "NativeQuartermasterLuaRoot": self.owned_root,
            "NativeActionRoot": "/native", "NativeWishlistGameRoot": "/game",
            "NativeWishlistWorkshopRoot": "/workshop", "SaucedCartsSource": "/carts",
        })])

    def test_profile_listing_needs_no_lua_execution(self):
        self.invoke('--list-integrations')
        self.assertNotIn('Quartermaster', self.output.getvalue())
        self.assertIn('Navigator.lua', self.output.getvalue())
        self.assertEqual([], self.executions)
        self.assertEqual(self.executions, [])


if __name__ == "__main__":
    unittest.main()
