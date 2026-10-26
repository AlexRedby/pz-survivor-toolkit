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

# Only these nested scripts are standalone offline checks. Native scenario fixtures
# under tests/native_queue must never be discovered as runnable Lua unit tests.
NATIVE_TAG_TESTS = (
    "native_tags/check_reconnect.lua",
    "native_tags/check_sort_receipts.lua",
    "native_tags/check_barrier.lua",
    "native_tags/check_transfer_source.lua",
    "native_tags/check_placement.lua",
)

# An explicit request must not silently skip its required source checks. Other
# source-dependent tests retain their own optional-input SKIP/fallback behavior.
REQUIRED_INPUTS = {
    "test_kahlua_own_fields.lua": ("native_action_root", "--game or --native-action-root"),
    "test_wash_water_rule.lua": ("native_action_root", "--game or --native-action-root, and --wishlist-workshop-root"),
    "test_wash_makeup_sync.lua": ("native_action_root", "--game or --native-action-root"),
    "test_torch_refill.lua": ("native_action_root", "--game or --native-action-root"),
    "test_action_queue_fridge_compat.lua": ("fridge_source", "--fridge-source"),
    "test_quartermaster_craft_ui.lua": ("native_action_root", "--game or --native-action-root"),
    "test_quartermaster_deposit.lua": ("native_action_root", "--game or --native-action-root"),
    "native_tags/check_transfer_source.lua": ("native_action_root", "--game or --native-action-root"),
    "native_tags/check_placement.lua": ("native_action_root", "--game or --native-action-root"),
}
DEFAULT_NATIVE_ONLY = {
    "test_torch_refill.lua",
    "test_quartermaster_craft_ui.lua",
    "native_tags/check_transfer_source.lua",
    "native_tags/check_placement.lua",
}


def discover_tests(root):
    """Top-level test_*.lua files are runnable without a second registration."""
    return sorted({path.name for path in (root / "tests").glob("test_*.lua") if path.is_file()}
                  | set(NATIVE_TAG_TESTS))


def configure_game_sources(args):
    if not args.game:
        return
    game = args.game.resolve()
    if not (game / 'projectzomboid.jar').is_file():
        raise ValueError('--game must contain projectzomboid.jar: ' + str(game))
    for option, relative in mod_integrations.GAME_SOURCES.items():
        if getattr(args, option) is None:
            setattr(args, option, game / relative)


def configure_test_sources(lua, name, args):
    """Give every isolated runtime the same paths; read only this test's inputs."""
    mod_integrations.bind_sources(lua, name, args)
    lua.globals().ProjectRoot = str(ROOT)
    lua.globals().NativeQuartermasterLuaRoot = str(ROOT / "PZSurvivorToolkit/42/media/lua")
    for option, variable in (
        ("native_action_root", "NativeActionRoot"),
        ("wishlist_game_root", "NativeWishlistGameRoot"),
        ("wishlist_workshop_root", "NativeWishlistWorkshopRoot"),
        ("saucedcarts_source", "SaucedCartsSource"),
    ):
        value = getattr(args, option)
        if value is not None:
            lua.globals()[variable] = str(value)
    if name == "test_tag_filter_presets_menu.lua" and args.native_action_root:
        lua.globals().NativeTextBoxSource = (args.native_action_root / "client/ISUI/ISTextBox.lua").read_text(encoding="utf-8")
        lua.globals().NativeModalDialogSource = (args.native_action_root / "client/ISUI/ISModalDialog.lua").read_text(encoding="utf-8")
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
    if name in ("test_quartermaster_craft_ui.lua", "native_tags/check_transfer_source.lua", "native_tags/check_placement.lua"):
        lua.globals().NativePZLuaRoot = str(args.native_action_root)
    if name == 'test_container_appearance_controls.lua' and args.native_action_root:
        lua.globals().NativeColorPickerSource = (args.native_action_root / 'client/ISUI/ISColorPickerHSB.lua').read_text(encoding='utf-8')
    if name in ('test_container_configuration_menus.lua', 'test_smart_deposit.lua', 'test_inventory_refresh.lua'):
        if args.native_action_root:
            lua.globals().NativeInventoryPageSource = (args.native_action_root / 'client/ISUI/ISInventoryPage.lua').read_text(encoding='utf-8')
    if name in ("test_highlighter.lua", "test_item_details.lua") and args.native_mod_options:
        lua.globals().NativeModOptionsSource = args.native_mod_options.read_text(encoding="utf-8")
    if name == "test_highlighter.lua" and args.native_action_root:
        lua.globals().NativeMainOptionsSource = (args.native_action_root / "client/OptionScreens/MainOptions.lua").read_text(encoding="utf-8")
    if name == "test_cart_spawns.lua" and args.wheelbarrow_source:
        lua.globals().WheelbarrowSource = str(args.wheelbarrow_source)
    if name == "test_clothing_repair_menu.lua" and args.native_inventory_context_menu:
        lua.globals().NativeGarmentSource = (args.native_inventory_context_menu.parent / "ISGarmentUI.lua").read_text(encoding="utf-8")
    if name == "test_clothing_inspection.lua" and args.native_inventory_context_menu and args.native_action_root:
        lua.globals().NativeInventoryContextMenuSource = args.native_inventory_context_menu.read_text(encoding="utf-8")
        lua.globals().NativeGarmentSource = (args.native_inventory_context_menu.parent / "ISGarmentUI.lua").read_text(encoding="utf-8")
        lua.globals().NativeTransferSource = (args.native_action_root / "client/TimedActions/ISInventoryTransferAction.lua").read_text(encoding="utf-8")
    if name == "test_tv_controls.lua":
        if args.native_radio_root:
            lua.globals().NativeMediaSource = (args.native_radio_root / "RadioCom/RadioWindowModules/RWMMedia.lua").read_text(encoding="utf-8")
            lua.globals().NativeDropBoxSource = (args.native_radio_root / "RadioCom/ISUIRadio/ISItemDropBox.lua").read_text(encoding="utf-8")
    if name == "test_vehicle_ground.lua":
        if args.native_uninstall:
            lua.globals().NativeUninstallSource = args.native_uninstall.read_text(encoding="utf-8")
        if args.native_vehicles:
            lua.globals().NativeVehicleItemsSource = args.native_vehicles.read_text(encoding="utf-8")
    if name == "test_action_queue_fridge_compat.lua" and args.fridge_source:
        lua.globals().FridgeSource = str(args.fridge_source.resolve())
    if name == "test_vva_compat.lua" and args.vva_source:
        lua.globals().NativeVVASourceRoot = str(args.vva_source.resolve())
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
    if name == "test_quantity_transfers.lua" and args.oc_stick_source:
        lua.globals().OCItemStickSource = args.oc_stick_source.read_text(encoding="utf-8")
    if name == "test_inventory_filter.lua" and args.oc_display_source:
        lua.globals().OCDisplayOverrideSource = args.oc_display_source.read_text(encoding="utf-8")
    if name in ("test_action_queue_operations.lua", "test_quantity_transfers.lua", "test_item_retention.lua") and args.native_inventory_context_menu:
        lua.globals().NativeInventoryContextMenuSource = args.native_inventory_context_menu.read_text(encoding="utf-8")
        if name == "test_quantity_transfers.lua":
            lua.globals().NativeTextBoxSource = (args.native_inventory_context_menu.parent / "ISTextBox.lua").read_text(encoding="utf-8")
    if name in ("test_inventory_tags.lua", "test_inventory_filter.lua", "test_inventory_layout.lua", "test_inventory_interaction.lua") and args.native_inventory_pane:
        lua.globals().NativeInventoryPaneSource = args.native_inventory_pane.read_text(encoding="utf-8")


def test_variants(name, args):
    """Each flag selects an independent execution, never a reused Lua state."""
    flags = [None]
    if name == "native_tags/check_reconnect.lua":
        flags += ["BaselineTagReconnect", "RestartTagReconnect", "PlantingTagReconnect"]
    if name == "test_action_queue_fire.lua" and args.native_action_root and args.wishlist_workshop_root:
        flags += ["FireTestBCPreinstalled", "FireTestBCForeignPredecessor", "FireTestQMBeforeBC",
                  "FireTestQMPreloaded", "FireTestQMForeignPredecessor", "FireTestQMForeignGather"]
    return flags


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
    parser.add_argument("--fridge-source", type=Path, help="Nick's Turn Off Fridges active media/lua directory")
    parser.add_argument("--vva-source", type=Path, help="Vanilla Vehicles Animated effective content root containing media/")
    parser.add_argument("--vro-source", type=Path, help="Vehicle Repair Overhaul effective content root containing media/")
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
    available = discover_tests(ROOT)
    requested = {name if name.endswith(".lua") else name + ".lua" for name in args.test}

    def validate_selection():
        unknown = requested - set(available)
        if unknown:
            parser.error("unknown tests: " + ", ".join(sorted(unknown)) + "; see --list")

    validate_selection()
    if args.list:
        print("\n".join(available))
        return
    if args.list_integrations:
        print(json.dumps(mod_integrations.describe(), indent=2))
        return
    if args.integration or args.pack_lock:
        try:
            mod_integrations.configure(args, ROOT, requested)
        except (OSError, ValueError, KeyError) as error:
            parser.error(str(error))
        validate_selection()
    try:
        configure_game_sources(args)
    except ValueError as error:
        parser.error(str(error))
    for name in sorted(requested):
        if name in REQUIRED_INPUTS:
            option, help_text = REQUIRED_INPUTS[name]
            if not getattr(args, option):
                parser.error(name.removesuffix(".lua") + " requires " + help_text)

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
    for name in available:
        if requested and name not in requested:
            continue
        if name in DEFAULT_NATIVE_ONLY and not args.native_action_root:
            continue
        for flag in test_variants(name, args):
            lua = LuaRuntime(unpack_returned_tuples=True)
            configure_test_sources(lua, name, args)
            if flag:
                lua.globals()[flag] = True
            lua.execute((ROOT / "tests" / name).read_text(encoding="utf-8"))


if __name__ == "__main__":
    main()
