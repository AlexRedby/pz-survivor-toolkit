"""Contribution-local checks only. Never prepares a profile or launches the game."""
from pathlib import Path
import argparse
import json
import os
import re
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent


def check_manifest():
    manifest = json.loads((HERE / "manifest.json").read_text())
    assert manifest["schema_version"] == 1
    assert manifest["id"] == "wooden_cart_motion"
    assert manifest["status"] == "intake_only" and manifest["runner_adapter"] is None
    assert manifest["live_after_parameterization"] == "not_run"
    assert manifest["exclusive_native_process"] is True
    assert manifest["sources"] == {
        "java": "Main.java", "test_area": "test-area.lua",
        "bootstrap": "bootstrap.lua", "scenario": "scenario-clips.lua", "evidence": "evidence/README.md",
    }
    for name in manifest["sources"].values():
        assert (HERE / name).is_file(), name
    assert manifest["dependencies"]["compile_jdk_minimum"] == 25
    assert manifest["dependencies"]["compile_release"] == 17
    assert manifest["dependencies"]["required_project_versions"]["PZSurvivorToolkit"] == ">=0.1.57"
    assert manifest["dependencies"]["required_project_versions"]["PZToolkitJavaPatches"] == ">=0.1.14"
    assert manifest["required_environment"] == ["PZ_CART_RUNTIME_FILE", "PZ_CART_COMMAND_FILE"]
    assert manifest["required_lua_fields"] == ["disposable", "videoRoot", "ffmpeg", "area"]
    assert manifest["runtime_contract"]["world_name"] == "CartTestArea"
    assert manifest["runtime_contract"]["fresh_owned_profile"] is True
    assert manifest["scenario"]["case_count"] == 16
    axes = manifest["scenario"]["axes"]
    assert len(axes["sex"]) * len(axes["cargo"]) * len(axes["spec"]) == 16
    assert set(manifest["criteria"]) == {"completion", "grip", "geometry", "native_pose", "floor", "gait", "diagnostics"}
    allowed = {"Main.java", "test-area.lua", "bootstrap.lua", "scenario-clips.lua", "manifest.json", "README.md", "self_check.py"}
    assert {p.name for p in HERE.iterdir() if p.is_file()} == allowed
    for path in HERE.rglob("*"):
        if path.is_file():
            assert path.suffix not in {".jar", ".class", ".zip", ".mp4", ".png", ".bin", ".log"}, path
    for name in manifest["sources"].values():
        text = (HERE / name).read_text()
        assert not re.search(r"/(?:Users|home|private/tmp|opt/homebrew)/", text), name
        assert all(line.rstrip() == line for line in text.splitlines()), name
    for name in ("test-area.lua", "bootstrap.lua", "scenario-clips.lua"):
        first = next(line for line in (HERE / name).read_text().splitlines() if line.strip() and not line.startswith("--"))
        assert first.startswith("local config=assert(CartMotionConfig,"), name
    return manifest


def check_lua(executable):
    if not executable:
        return "SKIPPED (supply --lua or install Lua/LuaJIT)"
    for name in ("test-area.lua", "bootstrap.lua", "scenario-clips.lua"):
        path = json.dumps(str(HERE / name), ensure_ascii=False)
        # loadfile parses without executing game APIs; missing config must fail first.
        code = f"assert(loadfile({path})); local ok,err=pcall(dofile,{path}); assert(not ok and tostring(err):find('CartMotionConfig',1,true),tostring(err))"
        subprocess.run([executable, "-e", code], check=True, cwd=HERE)
    area = json.dumps(str(HERE / "test-area.lua"), ensure_ascii=False)
    code = "CartMotionConfig={disposable=true,area={x=10825.5,y=10142.5,z=7,minX=10777,minY=10094,size=96,margin=2,floorSprite='carpentry_02_57'}}; "
    code += f"local a=dofile({area}); assert(a.size==96 and a.contains(a.x,a.y,a.z) and not a.contains(a.minX,a.minY,a.z)); "
    code += "getWorld=function() return {getWorld=function() return 'PlayerSave' end} end; local ok,err=pcall(a.prepare); assert(not ok and tostring(err):find('non-test save',1,true),tostring(err))"
    subprocess.run([executable, "-e", code], check=True, cwd=HERE)
    return "PASS (syntax, missing config, area bounds and non-test-save refusal)"


def check_java(game, jdk):
    if game is None and jdk is None:
        return "SKIPPED (supply --game-java-dir and --jdk)"
    assert game is not None and jdk is not None, "Supply both Java dependency paths"
    compiler = jdk / "bin" / ("javac.exe" if os.name == "nt" else "javac")
    version = subprocess.run([str(compiler), "-version"], check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT).stdout
    match = re.search(r"javac (\d+)", version)
    assert match and int(match[1]) >= 25, version
    jars = [game / name for name in ("projectzomboid.jar", "ZombieBuddy.jar")]
    assert all(path.is_file() for path in jars), "Local game/ZombieBuddy JARs required"
    with tempfile.TemporaryDirectory(prefix="wooden-cart-compile-") as output:
        subprocess.run([str(compiler), "--release", "17", "-cp", os.pathsep.join(map(str, jars)), "-d", output, str(HERE / "Main.java")], check=True)
        assert (Path(output) / "net/alexredby/cartlab/Main.class").is_file()
    return "PASS (compile only; fixture/game not launched)"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-java-dir", type=Path)
    parser.add_argument("--jdk", type=Path)
    parser.add_argument("--lua", default=shutil.which("luajit") or shutil.which("lua"))
    args = parser.parse_args()
    check_manifest()
    lua = check_lua(args.lua)
    java = check_java(args.game_java_dir, args.jdk)
    print(f"WOODEN_CART_FIXTURE_CHECK: schema/files=PASS; Lua={lua}; Java={java}; live=NOT_RUN")


if __name__ == "__main__":
    main()
