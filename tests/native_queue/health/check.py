"""Portable, offline checks of the shipped medical fixture (Lua 5.1 or LuaJIT)."""
from pathlib import Path
import json
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent


def main():
    executable = shutil.which("luajit") or shutil.which("lua5.1") or shutil.which("lua")
    if executable is None:
        raise SystemExit("Medical fixture self-check needs Lua 5.1 or LuaJIT on PATH")
    sources = sorted(path for side in ("client", "server", "shared") for path in (ROOT / side).glob("*.lua"))
    syntax = "\n".join("assert(loadfile(" + json.dumps(str(path)) + "))" for path in sources)
    subprocess.run([executable, "-e", syntax], check=True)
    result = subprocess.run([executable, str(ROOT / "check.lua"), str(ROOT)], text=True, capture_output=True)
    if result.returncode:
        print(result.stdout)
        print(result.stderr)
        raise SystemExit(result.returncode)
    for line in result.stdout.splitlines():
        if line.startswith("PASS"):
            print(line)
    events = [json.loads(line.removeprefix("EVENT_JSON ")) for line in result.stdout.splitlines() if line.startswith("EVENT_JSON ")]
    assert len(events) == 1 and events[0]["outcome"]["tailCompleted"] is False
    assert events[0]["reason"] == 'quote" slash\\ newline\n'
    assert events[0]["cases"] == ["nativeStop", "remoteRemoved"]
    print("PASS structured events preserve JSON booleans, arrays and escaped reasons")
    catalog = json.loads((ROOT.parent / "catalog.json").read_text())
    assert catalog["schema"] == 1
    cases = catalog["suites"]["health"]["cases"]
    assert len(cases) == len({case["id"] for case in cases}) == 45
    assert cases[0]["id"] == "bandageApply"
    for case in cases:
        assert set(case["modes"]) <= {"native", "toolkit"}
        assert case["producer"] in ("menu", "drop", "mini-menu", "inventory")
    print("PASS Lua syntax and 45-case medical catalog")
    print("NOT RUN: PZ, native durations, SP/MP, real disconnect, or rendered UI")


if __name__ == "__main__":
    main()
