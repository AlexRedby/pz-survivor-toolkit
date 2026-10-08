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


if __name__ == "__main__":
    main()
