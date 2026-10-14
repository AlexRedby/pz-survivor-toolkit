#!/usr/bin/env python3
"""Run Lua 5.1 behavioural checks with Lupa (a development dependency only)."""

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-mod-options", type=Path,
                        help="test against an extracted vanilla PZAPI/ModOptions.lua")
    parser.add_argument("--cci-source", type=Path, help="test against ContainerCapacityIndicator.lua")
    parser.add_argument("--item-details-source", type=Path, help="Item Details media/lua/client directory")
    parser.add_argument("--cleanui-inventory-pane", type=Path, help="test against CleanUI ISInventoryPane.lua")
    parser.add_argument("--native-inventory-pane", type=Path, help="test against vanilla ISInventoryPane.lua")
    parser.add_argument("--proximity-source", type=Path, help="test against ProximityInventory.lua and sibling ISInventoryPage.lua")
    parser.add_argument("--tv-source", type=Path, help="test VHS controls against TVRadio Reinvented RWMMergedTV.lua")
    parser.add_argument("--native-radio-root", type=Path, help="vanilla media/lua/client directory for RWMMedia and ISItemDropBox checks")
    parser.add_argument("--navigator-source", type=Path, help="NavigatorRadio source directory for upstream render/input checks")
    parser.add_argument("--native-uninstall", type=Path, help="vanilla ISUninstallVehiclePart.lua for ground-placement checks")
    parser.add_argument("--native-vehicles", type=Path, help="vanilla Vehicles.lua for mechanics item-collection checks")
    parser.add_argument("--medicine-framework-source", type=Path, help="installed MF_ISMoodle.lua")
    parser.add_argument("--mpff-source", type=Path, help="MP Fast Forward media/lua directory")
    parser.add_argument("--bc-filter-source", type=Path, help="Better Containers CategoryFilters.lua")
    parser.add_argument("--native-inventory-context-menu", type=Path, help="vanilla inventory transfer callbacks")
    parser.add_argument("--native-action-root", type=Path, help="vanilla media/lua for queue/base/read contracts")
    parser.add_argument("--wishlist-game-root", type=Path, help="game Java directory for native wishlist menu callbacks")
    parser.add_argument("--wishlist-workshop-root", type=Path, help="Workshop content/108600 for wishlist UI source checks")
    parser.add_argument("--project-cook-picker", type=Path, help="Project Cook ItemPicker.lua for queued stove controls")
    parser.add_argument("--saucedcarts-source", type=Path, help="SaucedCarts shared module directory for server hook checks")
    args = parser.parse_args()
    try:
        from lupa.lua51 import LuaRuntime
    except ImportError as error:
        raise SystemExit("Install the test dependency with: python3 -m pip install lupa") from error
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().ProjectRoot = str(ROOT)
    if args.native_mod_options:
        lua.globals().NativeModOptionsSource = args.native_mod_options.read_text(encoding="utf-8")
    for path in sorted((ROOT / "PZSurvivorToolkit").rglob("*.lua")):
        lua.execute("assert(loadstring(...))", path.read_text(encoding="utf-8"))
    for path in sorted((ROOT / "PZSurvivorWishlist").rglob("*.lua")):
        lua.execute("assert(loadstring(...))", path.read_text(encoding="utf-8"))
    print("All mod files compile as Lua 5.1.", flush=True)
    lua.execute((ROOT / "tests/test_highlighter.lua").read_text(encoding="utf-8"))

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().ProjectRoot = str(ROOT)
    if args.saucedcarts_source:
        lua.globals().SaucedCartsSource = str(args.saucedcarts_source)
    lua.execute((ROOT / "tests/test_saucedcarts_compat.lua").read_text(encoding="utf-8"))

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().ProjectRoot = str(ROOT)
    lua.execute((ROOT / "tests/test_cart_hands.lua").read_text(encoding="utf-8"))

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().ProjectRoot = str(ROOT)
    lua.execute((ROOT / "tests/test_auto_drink.lua").read_text(encoding="utf-8"))

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().ProjectRoot = str(ROOT)
    if args.cci_source:
        lua.globals().CCISource = args.cci_source.read_text(encoding="utf-8")
    lua.execute((ROOT / "tests/test_cci_compat.lua").read_text(encoding="utf-8"))

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().ProjectRoot = str(ROOT)
    if args.item_details_source:
        for name, filename in (("ItemDetailsSource", "BravoItemDetails.lua"),
                               ("ItemDetailsConfigSource", "BravoItemDetailsConfig.lua"),
                               ("ItemDetailsSorterSource", "BravoItemDetailsSorter.lua")):
            lua.globals()[name] = (args.item_details_source / filename).read_text(encoding="utf-8")
    lua.execute((ROOT / "tests/test_item_details.lua").read_text(encoding="utf-8"))

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().ProjectRoot = str(ROOT)
    if args.tv_source:
        lua.globals().TVSource = args.tv_source.read_text(encoding="utf-8")
    lua.execute((ROOT / "tests/test_tv_videos.lua").read_text(encoding="utf-8"))

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().ProjectRoot = str(ROOT)
    lua.execute((ROOT / "tests/test_vhs_ownership.lua").read_text(encoding="utf-8"))

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().ProjectRoot = str(ROOT)
    if args.native_uninstall:
        lua.globals().NativeUninstallSource = args.native_uninstall.read_text(encoding="utf-8")
    if args.native_vehicles:
        lua.globals().NativeVehicleItemsSource = args.native_vehicles.read_text(encoding="utf-8")
    lua.execute((ROOT / "tests/test_vehicle_ground.lua").read_text(encoding="utf-8"))

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().ProjectRoot = str(ROOT)
    if args.tv_source:
        lua.globals().TVSource = args.tv_source.read_text(encoding="utf-8")
        lua.globals().NativeTVWindowSource = (args.tv_source.parent.parent / "ISRadioWindow.lua").read_text(encoding="utf-8")
    if args.native_radio_root:
        lua.globals().NativeMediaSource = (args.native_radio_root / "RadioCom/RadioWindowModules/RWMMedia.lua").read_text(encoding="utf-8")
        lua.globals().NativeDropBoxSource = (args.native_radio_root / "RadioCom/ISUIRadio/ISItemDropBox.lua").read_text(encoding="utf-8")
    lua.execute((ROOT / "tests/test_tv_controls.lua").read_text(encoding="utf-8"))

    for name in ("test_ui_style.lua", "test_sidebar_tools.lua", "test_inventory_filter.lua", "test_inventory_layout.lua", "test_manage_containers.lua", "test_inventory_interaction.lua", "test_proximity_selection.lua", "test_bulk_dismantle.lua", "test_bulk_firearms.lua", "test_medicine_moodles.lua", "test_navigator.lua", "test_quantity_transfers.lua", "test_action_queue.lua", "test_action_queue_operations.lua", "test_action_queue_world.lua", "test_action_queue_dismantle.lua", "test_action_queue_targets.lua", "test_action_queue_labels.lua", "test_action_queue_craft.lua", "test_action_queue_batches.lua", "test_action_queue_batch_controller.lua", "test_action_queue_appliances.lua", "test_action_queue_fuel.lua", "test_action_queue_wreck.lua", "test_action_queue_repair.lua", "test_action_queue_policy.lua", "test_action_queue_compat.lua", "test_action_queue_health.lua", "test_action_queue_dispatch.lua", "test_action_queue_generators.lua", "test_action_queue_fire.lua", "test_action_queue_priority.lua", "test_set_stove_state.lua", "test_craft_planner.lua", "test_craft_chain_recipes.lua", "test_craft_chains.lua", "test_mpff_compat.lua", "test_bc_filter_compat.lua", "test_context_menu_rules.lua", "test_context_menus.lua"):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().ProjectRoot = str(ROOT)
        if args.native_action_root:
            lua.globals().NativeActionRoot = str(args.native_action_root)
        if name in ("test_action_queue_craft.lua", "test_action_queue_batches.lua", "test_action_queue_batch_controller.lua", "test_action_queue_appliances.lua", "test_action_queue_dispatch.lua", "test_action_queue_compat.lua", "test_action_queue_fire.lua", "test_action_queue_generators.lua") and args.wishlist_workshop_root:
            lua.globals().NativeWishlistWorkshopRoot = str(args.wishlist_workshop_root)
        if args.project_cook_picker:
            lua.globals().ProjectCookPickerSourcePath = str(args.project_cook_picker)
        if name == "test_action_queue_labels.lua":
            translations = {}
            for language in ("EN", "RU"):
                values = {}
                if args.native_action_root:
                    for path in sorted((args.native_action_root / "shared/Translate" / language).glob("*.json")):
                        values.update(json.loads(path.read_text(encoding="utf-8")))
                values.update(json.loads((ROOT / "PZSurvivorToolkit/42/media/lua/shared/Translate" / language / "UI.json").read_text(encoding="utf-8")))
                translations[language] = values
            lua.globals().ActionQueueTranslations = lua.table_from(translations, recursive=True)
        if args.medicine_framework_source:
            lua.globals().NativeMedicineFrameworkSource = args.medicine_framework_source.read_text(encoding="utf-8")
        if args.mpff_source:
            lua.globals().NativeMPFFConfigSource = (args.mpff_source / "shared/MPFastForward_Config.lua").read_text(encoding="utf-8")
            lua.globals().NativeMPFFServerSource = (args.mpff_source / "server/MPFastForward_Server.lua").read_text(encoding="utf-8")
        if args.bc_filter_source:
            lua.globals().NativeBCFilterSource = args.bc_filter_source.read_text(encoding="utf-8")
        if args.native_inventory_context_menu:
            lua.globals().NativeInventoryContextMenuSource = args.native_inventory_context_menu.read_text(encoding="utf-8")
            lua.globals().NativeTextBoxSource = (args.native_inventory_context_menu.parent / "ISTextBox.lua").read_text(encoding="utf-8")
        if args.navigator_source:
            for suffix in ("Config", "Render", "Drag"):
                source_name = "NavigatorMonitorDrag" if suffix == "Drag" else "Monitor" + suffix
                lua.globals()["NativeNavigator" + suffix] = (args.navigator_source / (source_name + ".lua")).read_text(encoding="utf-8")
        if args.cleanui_inventory_pane:
            lua.globals().CleanUIInventoryPaneSource = args.cleanui_inventory_pane.read_text(encoding="utf-8")
        if args.native_inventory_pane:
            lua.globals().NativeInventoryPaneSource = args.native_inventory_pane.read_text(encoding="utf-8")
        if args.proximity_source:
            lua.globals().ProximityInventorySource = args.proximity_source.read_text(encoding="utf-8")
            lua.globals().ProximityInventoryPageSource = (args.proximity_source.parent / "ISInventoryPage.lua").read_text(encoding="utf-8")
        lua.execute((ROOT / "tests" / name).read_text(encoding="utf-8"))
        if name == "test_action_queue_fire.lua" and args.native_action_root and args.wishlist_workshop_root:
            for scenario in ("FireTestBCPreinstalled", "FireTestBCForeignPredecessor"):
                variant = LuaRuntime(unpack_returned_tuples=True)
                variant.globals().ProjectRoot = str(ROOT)
                variant.globals().NativeActionRoot = str(args.native_action_root)
                variant.globals().NativeWishlistWorkshopRoot = str(args.wishlist_workshop_root)
                variant.globals()[scenario] = True
                variant.execute((ROOT / "tests" / name).read_text(encoding="utf-8"))

    for path in sorted((ROOT / "tests").glob("test_wishlist_*.lua")):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().ProjectRoot = str(ROOT)
        if args.wishlist_game_root:
            lua.globals().NativeWishlistGameRoot = str(args.wishlist_game_root)
        if args.wishlist_workshop_root:
            lua.globals().NativeWishlistWorkshopRoot = str(args.wishlist_workshop_root)
        lua.execute(path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    main()
