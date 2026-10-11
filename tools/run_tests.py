#!/usr/bin/env python3
"""Run Lua 5.1 behavioural checks with Lupa (a development dependency only)."""

import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-mod-options", type=Path,
                        help="test against an extracted vanilla PZAPI/ModOptions.lua")
    parser.add_argument("--cci-source", type=Path, help="test against ContainerCapacityIndicator.lua")
    parser.add_argument("--cleanui-inventory-pane", type=Path, help="test against CleanUI ISInventoryPane.lua")
    parser.add_argument("--native-inventory-pane", type=Path, help="test against vanilla ISInventoryPane.lua")
    parser.add_argument("--proximity-source", type=Path, help="test against ProximityInventory.lua and sibling ISInventoryPage.lua")
    parser.add_argument("--tv-source", type=Path, help="test VHS controls against TVRadio Reinvented RWMMergedTV.lua")
    parser.add_argument("--native-radio-root", type=Path, help="vanilla media/lua/client directory for RWMMedia and ISItemDropBox checks")
    parser.add_argument("--navigator-source", type=Path, help="NavigatorRadio source directory for upstream render/input checks")
    parser.add_argument("--native-uninstall", type=Path, help="vanilla ISUninstallVehiclePart.lua for ground-placement checks")
    parser.add_argument("--medicine-framework-source", type=Path, help="installed MF_ISMoodle.lua")
    parser.add_argument("--mpff-source", type=Path, help="MP Fast Forward media/lua directory")
    parser.add_argument("--bc-filter-source", type=Path, help="Better Containers CategoryFilters.lua")
    parser.add_argument("--native-inventory-context-menu", type=Path, help="vanilla inventory transfer callbacks")
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
    print("All mod files compile as Lua 5.1.", flush=True)
    lua.execute((ROOT / "tests/test_highlighter.lua").read_text(encoding="utf-8"))
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

    for name in ("test_inventory_filter.lua", "test_inventory_layout.lua", "test_manage_containers.lua", "test_inventory_interaction.lua", "test_proximity_selection.lua", "test_bulk_dismantle.lua", "test_bulk_firearms.lua", "test_medicine_moodles.lua", "test_navigator.lua", "test_quantity_transfers.lua", "test_mpff_compat.lua", "test_bc_filter_compat.lua"):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().ProjectRoot = str(ROOT)
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


if __name__ == "__main__":
    main()
