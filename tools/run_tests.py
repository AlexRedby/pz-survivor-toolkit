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
    lua.execute((ROOT / "tests/test_tv_videos.lua").read_text(encoding="utf-8"))

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().ProjectRoot = str(ROOT)
    lua.execute((ROOT / "tests/test_vhs_ownership.lua").read_text(encoding="utf-8"))

    for name in ("test_inventory_filter.lua", "test_inventory_layout.lua", "test_manage_containers.lua", "test_inventory_interaction.lua", "test_proximity_selection.lua"):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().ProjectRoot = str(ROOT)
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
