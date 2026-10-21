#!/usr/bin/env python3
"""Run Lua 5.1 behavioural checks with Lupa (a development dependency only)."""

import argparse
import json
import locale
from pathlib import Path

try:
    from . import mod_integrations
except ImportError:
    import mod_integrations

ROOT = Path(__file__).resolve().parent.parent

TAG_TESTS = ("test_item_tags.lua", "test_tag_visuals.lua", "test_inventory_tags.lua", "test_quartermaster_tags.lua", "test_tag_rule_picker.lua", "test_quartermaster_tag_rules.lua", "test_quartermaster_sync.lua", "test_quartermaster_preset_codec.lua", "test_quartermaster_preset_storage.lua", "test_quartermaster_preset_transactions.lua", "test_quartermaster_item_routing.lua", "test_tag_filter_presets.lua", "test_tag_filter_presets_menu.lua", "native_tags/check_reconnect.lua", "native_tags/check_sort_receipts.lua", "native_tags/check_barrier.lua")
ACTION_TESTS = ("test_vehicle_light_dashboard.lua", "test_vehicle_lighting.lua", "test_source_proof.lua", "test_drink_fluid.lua", "test_animal_info.lua", "test_action_queue_animals.lua", "test_ui_style.lua", "test_ui_text_fit.lua", "test_sidebar_tools.lua", "test_inventory_classes.lua", "test_inventory_filter.lua", "test_inventory_layout.lua", "test_inventory_interaction.lua", "test_bulk_dismantle.lua", "test_bulk_food.lua", "test_packaged_food.lua", "test_food_cart_compat.lua", "test_bulk_firearms.lua", "test_medicine_moodles.lua", "test_navigator.lua", "test_quantity_transfers.lua", "test_action_queue.lua", "test_action_queue_lifecycle.lua", "test_queue_equipment_floor.lua", "test_queue_equipment_bulk.lua", "test_queue_craft_fixture.lua", "test_queue_craft_ui_fixture.lua", "test_queue_engine_fixture.lua", "test_queue_fire_fixture.lua", "test_queue_fire_tidy.lua", "test_queue_equipment_authority.lua", "test_queue_equipment_slots.lua", "test_queue_equipment_postprocess.lua", "test_action_queue_acknowledgements.lua", "test_action_queue_operations.lua", "test_action_queue_world.lua", "test_action_queue_dismantle.lua", "test_action_queue_targets.lua", "test_action_queue_labels.lua", "test_action_queue_craft.lua", "test_action_queue_batches.lua", "test_action_queue_batch_controller.lua", "test_action_queue_appliances.lua", "test_action_queue_fuel.lua", "test_action_queue_wreck.lua", "test_action_queue_repair.lua", "test_action_queue_policy.lua", "test_action_queue_hygiene.lua", "test_action_queue_compat.lua", "test_action_queue_grab_compat.lua", "test_action_queue_tidy_intent.lua", "test_action_queue_manifest.lua", "test_action_queue_health.lua", "test_action_queue_dispatch.lua", "test_action_queue_generators.lua", "test_action_queue_generator_overlay.lua", "test_action_queue_carts.lua", "test_action_queue_fire.lua", "test_action_queue_priority.lua", "test_set_stove_state.lua", "test_craft_planner.lua", "test_craft_chain_recipes.lua", "test_craft_chains.lua", "test_mpff_compat.lua", "test_bc_filter_compat.lua", "test_context_menu_rules.lua", "test_context_menus.lua", "test_context_menu_profile.lua", "test_context_menu_profile_storage.lua", "test_context_menu_profile_failures.lua", "test_context_menu_editor.lua")
ACTION_TESTS += ("test_action_queue_media.lua", "test_device_media_native_order.lua", "test_bc_pins.lua", "test_action_queue_fitness.lua", "test_crafting_controls.lua")
ACTION_TESTS += ("test_action_queue_edit_model.lua", "test_action_queue_edit_adapters.lua", "test_action_queue_edit_policy.lua")
ACTION_TESTS += ("test_action_queue_item_edit_adapters.lua", "test_food_eatsmart_compat.lua", "test_food_goal_labels.lua")
ACTION_TESTS += ("test_inventory_search.lua", "test_inventory_transfer_operations.lua")
ACTION_TESTS += ("test_vva_compat.lua",)
ACTION_TESTS += ("test_manifest_text_fit.lua",)
EXTRA_TESTS = (
    'test_quartermaster_rpc.lua',
    'test_container_tag_icons.lua',
    'test_container_appearance_controls.lua',
    'test_quartermaster_container_config.lua',
    'test_container_configuration_menus.lua',
    'test_quartermaster_craft_ui.lua',
    'test_quartermaster_craft_sources.lua',
    'test_highlighter.lua',
    'test_saucedcarts_compat.lua',
    'test_cart_spawns.lua',
    'test_cart_hands.lua',
    'test_cart_motion.lua',
    'test_cart_transitions.lua',
    'test_cart_impact_release.lua',
    'test_cart_scene_selection.lua',
    'test_cart_test_area.lua',
    'test_cart_obstacles.lua',
    'test_auto_drink.lua',
    'test_inventory_presentation.lua',
    'test_inventory_research.lua',
    'test_inventory_planting.lua',
    'test_inventory_indicators.lua',
    'test_inventory_tooltips.lua',
    'test_clothing_tooltip.lua',
    'test_smart_deposit.lua',
    'test_item_details.lua',
    'test_clothing_repair_menu.lua',
    'test_clothing_inspection.lua',
    'test_tv_videos.lua',
    'test_vhs_ownership.lua',
    'test_vehicle_ground.lua',
    'test_vehicle_doors.lua',
    'test_vehicle_door_dashboard.lua',
    'test_tv_controls.lua',
    'native_tags/check_transfer_source.lua',
    'native_tags/check_placement.lua',
)


def configure_game_sources(args):
    if not args.game:
        return
    game = args.game.resolve()
    if not (game / 'projectzomboid.jar').is_file():
        raise ValueError('--game must contain projectzomboid.jar: ' + str(game))
    for option, relative in {
        'native_mod_options': 'media/lua/client/PZAPI/ModOptions.lua',
        'native_inventory_pane': 'media/lua/client/ISUI/ISInventoryPane.lua',
        'native_inventory_context_menu': 'media/lua/client/ISUI/ISInventoryPaneContextMenu.lua',
        'native_radio_root': 'media/lua/client',
        'native_uninstall': 'media/lua/shared/Vehicles/TimedActions/ISUninstallVehiclePart.lua',
        'native_vehicles': 'media/lua/server/Vehicles/Vehicles.lua',
        'native_action_root': 'media/lua',
        'wishlist_game_root': '.',
    }.items():
        if getattr(args, option) is None:
            setattr(args, option, game / relative)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--test", action="append", default=[], metavar="NAME",
                        help="run only this test relative to tests/ (optional .lua suffix); repeatable")
    parser.add_argument("--list", action="store_true", help="list available test names without running checks")
    parser.add_argument('--integration', action='append', default=[], choices=mod_integrations.INTEGRATIONS,
                        help='run this integration against its locked upstream sources; repeatable')
    parser.add_argument('--list-integrations', action='store_true', help='show upstream inputs, Toolkit owners and focused checks')
    parser.add_argument('--pack-lock', type=Path, help='validated selected-pack lock supplying integration source paths')
    parser.add_argument('--game', type=Path,
                        help='directory containing projectzomboid.jar; supplies native Lua paths, and must match --pack-lock when used')
    parser.add_argument("--native-mod-options", type=Path,
                        help="test against an extracted vanilla PZAPI/ModOptions.lua")
    parser.add_argument("--cleanui-inventory-pane", type=Path, help="test against CleanUI ISInventoryPane.lua")
    parser.add_argument("--native-inventory-pane", type=Path, help="test against vanilla ISInventoryPane.lua")
    parser.add_argument("--tv-source", type=Path, help="test VHS controls against TVRadio Reinvented RWMMergedTV.lua")
    parser.add_argument("--native-radio-root", type=Path, help="vanilla media/lua/client directory for RWMMedia and ISItemDropBox checks")
    parser.add_argument("--navigator-source", type=Path, help="NavigatorRadio source directory for upstream render/input checks")
    parser.add_argument("--native-uninstall", type=Path, help="vanilla ISUninstallVehiclePart.lua for ground-placement checks")
    parser.add_argument("--native-vehicles", type=Path, help="vanilla Vehicles.lua for mechanics item-collection checks")
    parser.add_argument("--medicine-framework-source", type=Path, help="installed MF_ISMoodle.lua")
    parser.add_argument("--mpff-source", type=Path, help="MP Fast Forward media/lua directory")
    parser.add_argument("--vva-source", type=Path, help="Vanilla Vehicles Animated effective content root containing media/")
    parser.add_argument("--bc-filter-source", type=Path, help="Better Containers CategoryFilters.lua")
    parser.add_argument("--oc-stick-source", type=Path, help="organizedCategories_itemStick.lua for Quantity transfer protection checks")
    parser.add_argument("--oc-display-source", type=Path, help="organizedCategories_displayOverride.lua for inventory stack splitting checks")
    parser.add_argument("--vhs-tooltip-root", type=Path, help="active Show VHS Skills in Tooltip media/lua/client directory")
    parser.add_argument("--bci-tooltip-root", type=Path, help="active Better Clothing Info media/lua/client directory")
    parser.add_argument("--native-inventory-context-menu", type=Path, help="vanilla inventory callbacks and sibling garment inspection UI")
    parser.add_argument("--native-action-root", type=Path, help="vanilla media/lua for queue/base/read contracts")
    parser.add_argument("--wishlist-game-root", type=Path, help="game Java directory for native wishlist menu callbacks")
    parser.add_argument("--wishlist-workshop-root", type=Path, help="Workshop content/108600 for wishlist UI source checks")
    parser.add_argument("--project-cook-picker", type=Path, help="Project Cook ItemPicker.lua for queued stove controls")
    parser.add_argument("--saucedcarts-source", type=Path, help="SaucedCarts shared module directory for server hook checks")
    parser.add_argument("--wheelbarrow-source", type=Path, help="SaucedWheelbarrow registration init.lua for spawn checks")
    args = parser.parse_args()
    quartermaster_root = ROOT / "PZSurvivorToolkit/42/media/lua"
    available = set(TAG_TESTS) | set(ACTION_TESTS) | set(EXTRA_TESTS)
    available.update(path.name for path in (ROOT / "tests").glob("test_wishlist_*.lua"))
    requested = {name if name.endswith(".lua") else name + ".lua" for name in args.test}
    unknown = requested - available
    if unknown:
        parser.error("unknown tests: " + ", ".join(sorted(unknown)) + "; see --list")
    if args.list:
        print("\n".join(sorted(available)))
        return
    if args.list_integrations:
        print(json.dumps(mod_integrations.INTEGRATIONS, indent=2))
        return
    if args.integration or args.pack_lock:
        try:
            mod_integrations.configure(args, ROOT, requested)
        except (OSError, ValueError, KeyError) as error:
            parser.error(str(error))
    try:
        configure_game_sources(args)
    except ValueError as error:
        parser.error(str(error))
    if "test_quartermaster_craft_ui.lua" in requested and not args.native_action_root:
        parser.error("test_quartermaster_craft_ui requires --game or --native-action-root")
    if requested.intersection({"native_tags/check_transfer_source.lua", "native_tags/check_placement.lua"}) and not args.native_action_root:
        parser.error("selected native tag checks require --native-action-root")

    def should_run(name):
        return not requested or name in requested

    # Lua 5.1 character classes inspect bytes; host UTF-8 locales can misclassify them.
    locale.setlocale(locale.LC_CTYPE, "C")
    try:
        from lupa.lua51 import LuaRuntime
    except ImportError as error:
        raise SystemExit("Install the test dependency with: python3 -m pip install lupa") from error
    if not requested:
        syntax = LuaRuntime(unpack_returned_tuples=True)
        for path in sorted((ROOT / "PZSurvivorToolkit").rglob("*.lua")):
            syntax.execute("assert(loadstring(...))", path.read_text(encoding="utf-8"))
        print("All mod files compile as Lua 5.1.", flush=True)
    for name in TAG_TESTS:
        if not should_run(name):
            continue
        check = LuaRuntime(unpack_returned_tuples=True)
        check.globals().ProjectRoot = str(ROOT)
        if name == "test_inventory_tags.lua" and args.native_inventory_pane:
            check.globals().NativeInventoryPaneSource = args.native_inventory_pane.read_text(encoding="utf-8")
        if name == "test_inventory_tags.lua" and args.cleanui_inventory_pane:
            check.globals().CleanUIInventoryPaneSource = args.cleanui_inventory_pane.read_text(encoding="utf-8")
        check.globals().NativeQuartermasterLuaRoot = str(quartermaster_root)
        if name == "test_tag_filter_presets_menu.lua" and args.native_action_root:
            check.globals().NativeTextBoxSource = (args.native_action_root / "client/ISUI/ISTextBox.lua").read_text(encoding="utf-8")
            check.globals().NativeModalDialogSource = (args.native_action_root / "client/ISUI/ISModalDialog.lua").read_text(encoding="utf-8")
        check.execute((ROOT / "tests" / name).read_text(encoding="utf-8"))
    if should_run("native_tags/check_reconnect.lua"):
        check = LuaRuntime(unpack_returned_tuples=True)
        check.globals().ProjectRoot = str(ROOT)
        check.globals().BaselineTagReconnect = True
        check.execute((ROOT / "tests/native_tags/check_reconnect.lua").read_text(encoding="utf-8"))
        check = LuaRuntime(unpack_returned_tuples=True)
        check.globals().ProjectRoot = str(ROOT)
        check.globals().RestartTagReconnect = True
        check.execute((ROOT / "tests/native_tags/check_reconnect.lua").read_text(encoding="utf-8"))
        check = LuaRuntime(unpack_returned_tuples=True)
        check.globals().ProjectRoot = str(ROOT)
        check.globals().PlantingTagReconnect = True
        check.execute((ROOT / "tests/native_tags/check_reconnect.lua").read_text(encoding="utf-8"))
    for name in EXTRA_TESTS:
        if not should_run(name):
            continue
        if name == "test_quartermaster_craft_ui.lua" and not args.native_action_root:
            continue
        if name in ("native_tags/check_transfer_source.lua", "native_tags/check_placement.lua") and not args.native_action_root:
            continue
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().ProjectRoot = str(ROOT)
        if name in ("test_inventory_planting.lua", "test_inventory_indicators.lua") and args.native_action_root:
            lua.globals().NativePlantingLuaRoot = str(args.native_action_root)
        if name == "test_inventory_tooltips.lua":
            if args.native_action_root:
                lua.globals().NativeTooltipLuaRoot = str(args.native_action_root)
            if args.vhs_tooltip_root:
                lua.globals().NativeVHSTooltipRoot = str(args.vhs_tooltip_root)
        if name == "test_clothing_tooltip.lua":
            if args.native_action_root:
                lua.globals().NativeTooltipLuaRoot = str(args.native_action_root)
            if args.bci_tooltip_root:
                lua.globals().NativeBCITooltipRoot = str(args.bci_tooltip_root)
        if name == "test_vehicle_doors.lua" and args.native_action_root:
            lua.globals().NativeActionRoot = str(args.native_action_root)
        if name == "test_quartermaster_craft_ui.lua":
            lua.globals().NativePZLuaRoot = str(args.native_action_root)
            lua.globals().NativeQuartermasterLuaRoot = str(quartermaster_root)
        if name in ("native_tags/check_transfer_source.lua", "native_tags/check_placement.lua"):
            lua.globals().NativePZLuaRoot = str(args.native_action_root)
        if name == 'test_container_appearance_controls.lua' and args.native_action_root:
            lua.globals().NativeColorPickerSource = (args.native_action_root / 'client/ISUI/ISColorPickerHSB.lua').read_text(encoding='utf-8')
        if name == 'test_container_configuration_menus.lua':
            if args.native_action_root:
                lua.globals().NativeInventoryPageSource = (args.native_action_root / 'client/ISUI/ISInventoryPage.lua').read_text(encoding='utf-8')
            if args.cleanui_inventory_pane:
                lua.globals().CleanUIInventoryPageSource = (args.cleanui_inventory_pane.parent / 'ISInventoryPage.lua').read_text(encoding='utf-8')
                lua.globals().CleanUIVanillaInventoryPageSource = (args.cleanui_inventory_pane.parent.parent / 'CleanUI/Vanilla/CleanUI_Vanilla_ISInventoryPage.lua').read_text(encoding='utf-8')
            if args.bc_filter_source:
                lua.globals().NativeBCPageCustomizerSource = (args.bc_filter_source.parent.parent / 'Customize/Customize_ISInventoryPage.lua').read_text(encoding='utf-8')
        if name in ("test_highlighter.lua", "test_item_details.lua") and args.native_mod_options:
            lua.globals().NativeModOptionsSource = args.native_mod_options.read_text(encoding="utf-8")
        if name in ("test_saucedcarts_compat.lua", "test_cart_transitions.lua") and args.native_action_root:
            lua.globals().NativeActionRoot = str(args.native_action_root)
        if name in ("test_saucedcarts_compat.lua", "test_cart_spawns.lua", "test_cart_transitions.lua", "test_cart_impact_release.lua") and args.saucedcarts_source:
            lua.globals().SaucedCartsSource = str(args.saucedcarts_source)
        if name == "test_cart_spawns.lua" and args.wheelbarrow_source:
            lua.globals().WheelbarrowSource = str(args.wheelbarrow_source)
        if name == "test_clothing_repair_menu.lua" and args.native_inventory_context_menu:
            lua.globals().NativeGarmentSource = (args.native_inventory_context_menu.parent / "ISGarmentUI.lua").read_text(encoding="utf-8")
        if name == "test_clothing_inspection.lua" and args.native_inventory_context_menu and args.native_action_root:
            lua.globals().NativeInventoryContextMenuSource = args.native_inventory_context_menu.read_text(encoding="utf-8")
            lua.globals().NativeGarmentSource = (args.native_inventory_context_menu.parent / "ISGarmentUI.lua").read_text(encoding="utf-8")
            lua.globals().NativeTransferSource = (args.native_action_root / "client/TimedActions/ISInventoryTransferAction.lua").read_text(encoding="utf-8")
        if name in ("test_tv_videos.lua", "test_tv_controls.lua") and args.tv_source:
            lua.globals().TVSource = args.tv_source.read_text(encoding="utf-8")
        if name == "test_tv_controls.lua":
            if args.tv_source:
                lua.globals().NativeTVWindowSource = (args.tv_source.parent.parent / "ISRadioWindow.lua").read_text(encoding="utf-8")
            if args.native_radio_root:
                lua.globals().NativeMediaSource = (args.native_radio_root / "RadioCom/RadioWindowModules/RWMMedia.lua").read_text(encoding="utf-8")
                lua.globals().NativeDropBoxSource = (args.native_radio_root / "RadioCom/ISUIRadio/ISItemDropBox.lua").read_text(encoding="utf-8")
        if name == "test_vehicle_ground.lua":
            if args.native_uninstall:
                lua.globals().NativeUninstallSource = args.native_uninstall.read_text(encoding="utf-8")
            if args.native_vehicles:
                lua.globals().NativeVehicleItemsSource = args.native_vehicles.read_text(encoding="utf-8")
        lua.execute((ROOT / "tests" / name).read_text(encoding="utf-8"))

    for name in ACTION_TESTS:
        if not should_run(name):
            continue
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().ProjectRoot = str(ROOT)
        if name == "test_vva_compat.lua" and args.vva_source:
            lua.globals().NativeVVASourceRoot = str(args.vva_source.resolve())
        if args.saucedcarts_source:
            lua.globals().SaucedCartsSource = str(args.saucedcarts_source)
        if args.native_action_root:
            lua.globals().NativeActionRoot = str(args.native_action_root)
        if name in ("test_action_queue_craft.lua", "test_action_queue_batches.lua", "test_action_queue_batch_controller.lua", "test_action_queue_appliances.lua", "test_action_queue_dispatch.lua", "test_action_queue_compat.lua", "test_action_queue_grab_compat.lua", "test_action_queue_tidy_intent.lua", "test_action_queue_manifest.lua", "test_action_queue_health.lua", "test_action_queue_fire.lua", "test_action_queue_generators.lua", "test_action_queue_generator_overlay.lua", "test_action_queue_item_edit_adapters.lua", "test_food_eatsmart_compat.lua", "test_food_goal_labels.lua") and args.wishlist_workshop_root:
            lua.globals().NativeWishlistWorkshopRoot = str(args.wishlist_workshop_root)
        if name in ("test_action_queue.lua", "test_action_queue_fire.lua", "test_action_queue_manifest.lua", "test_action_queue_compat.lua"):
            lua.globals().NativeQuartermasterLuaRoot = str(quartermaster_root)
        if name == "test_action_queue_dispatch.lua" and args.project_cook_picker:
            lua.globals().ProjectCookPickerSourcePath = str(args.project_cook_picker)
        if name in ("test_action_queue_labels.lua", "test_food_goal_labels.lua"):
            translations = {}
            for language in ("EN", "RU"):
                values = {}
                if args.native_action_root:
                    for path in sorted((args.native_action_root / "shared/Translate" / language).glob("*.json")):
                        values.update(json.loads(path.read_text(encoding="utf-8")))
                values.update(json.loads((ROOT / "PZSurvivorToolkit/42/media/lua/shared/Translate" / language / "UI.json").read_text(encoding="utf-8")))
                translations[language] = values
            lua.globals().ActionQueueTranslations = lua.table_from(translations, recursive=True)
            if name == "test_food_goal_labels.lua":
                lua.globals().FoodGoalTranslations = lua.table_from(translations, recursive=True)
        if name == "test_medicine_moodles.lua" and args.medicine_framework_source:
            lua.globals().NativeMedicineFrameworkSource = args.medicine_framework_source.read_text(encoding="utf-8")
        if name == "test_mpff_compat.lua" and args.mpff_source:
            lua.globals().NativeMPFFConfigSource = (args.mpff_source / "shared/MPFastForward_Config.lua").read_text(encoding="utf-8")
            lua.globals().NativeMPFFServerSource = (args.mpff_source / "server/MPFastForward_Server.lua").read_text(encoding="utf-8")
        if name == "test_bc_filter_compat.lua" and args.bc_filter_source:
            lua.globals().NativeBCFilterSource = args.bc_filter_source.read_text(encoding="utf-8")
        if name == "test_quantity_transfers.lua" and args.oc_stick_source:
            lua.globals().OCItemStickSource = args.oc_stick_source.read_text(encoding="utf-8")
        if name == "test_inventory_filter.lua" and args.oc_display_source:
            lua.globals().OCDisplayOverrideSource = args.oc_display_source.read_text(encoding="utf-8")
        if name in ("test_action_queue_operations.lua", "test_quantity_transfers.lua") and args.native_inventory_context_menu:
            lua.globals().NativeInventoryContextMenuSource = args.native_inventory_context_menu.read_text(encoding="utf-8")
            if name == "test_quantity_transfers.lua":
                lua.globals().NativeTextBoxSource = (args.native_inventory_context_menu.parent / "ISTextBox.lua").read_text(encoding="utf-8")
        if name == "test_navigator.lua" and args.navigator_source:
            for suffix in ("Config", "Render", "Drag"):
                source_name = "NavigatorMonitorDrag" if suffix == "Drag" else "Monitor" + suffix
                lua.globals()["NativeNavigator" + suffix] = (args.navigator_source / (source_name + ".lua")).read_text(encoding="utf-8")
        if name in ("test_inventory_filter.lua", "test_inventory_search.lua", "test_inventory_layout.lua", "test_inventory_interaction.lua", "test_inventory_transfer_operations.lua") and args.cleanui_inventory_pane:
            lua.globals().CleanUIInventoryPaneSource = args.cleanui_inventory_pane.read_text(encoding="utf-8")
            if name == "test_inventory_filter.lua":
                handler = args.cleanui_inventory_pane.parent / "ISInventoryPageTransferHandler.lua"
                if handler.is_file():
                    lua.globals().CleanUIInventoryTransferHandlerSource = handler.read_text(encoding="utf-8")
            if name == "test_inventory_transfer_operations.lua":
                vanilla = args.cleanui_inventory_pane.parent.parent / "CleanUI/Vanilla/CleanUI_Vanilla_ISInventoryPane.lua"
                lua.globals().CleanUIVanillaInventoryPaneSource = vanilla.read_text(encoding="utf-8")
        if name in ("test_inventory_filter.lua", "test_inventory_layout.lua", "test_inventory_interaction.lua") and args.native_inventory_pane:
            lua.globals().NativeInventoryPaneSource = args.native_inventory_pane.read_text(encoding="utf-8")
        lua.execute((ROOT / "tests" / name).read_text(encoding="utf-8"))
        if name == "test_action_queue_fire.lua" and args.native_action_root and args.wishlist_workshop_root:
            scenarios = ["FireTestBCPreinstalled", "FireTestBCForeignPredecessor"]
            scenarios += ["FireTestQMBeforeBC", "FireTestQMPreloaded", "FireTestQMForeignPredecessor", "FireTestQMForeignGather"]
            for scenario in scenarios:
                variant = LuaRuntime(unpack_returned_tuples=True)
                variant.globals().ProjectRoot = str(ROOT)
                variant.globals().NativeActionRoot = str(args.native_action_root)
                variant.globals().NativeWishlistWorkshopRoot = str(args.wishlist_workshop_root)
                variant.globals().NativeQuartermasterLuaRoot = str(quartermaster_root)
                variant.globals()[scenario] = True
                variant.execute((ROOT / "tests" / name).read_text(encoding="utf-8"))

    for path in sorted((ROOT / "tests").glob("test_wishlist_*.lua")):
        if not should_run(path.name):
            continue
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().ProjectRoot = str(ROOT)
        if args.wishlist_game_root:
            lua.globals().NativeWishlistGameRoot = str(args.wishlist_game_root)
        if args.wishlist_workshop_root:
            lua.globals().NativeWishlistWorkshopRoot = str(args.wishlist_workshop_root)
        lua.execute(path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    main()
