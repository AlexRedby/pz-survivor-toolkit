"""No-game intake validation; registration counts are not native pass results."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent


def check_host_adapter():
    project = HERE.parents[3]
    sys.path.insert(0, str(project / "tools"))
    from queue_checks.adapters import craft_wishlist as adapter
    startup = project / "tests/native_queue/startup/client/ZZStartup.lua"
    base = {"suite": "shared-wishlist", "kind": "mp", "mode": "toolkit", "clients": 2,
            "mods": ["PZSurvivorToolkit"], "ports": [18061, 18062], "languages": ["EN", "RU"]}
    for cases in (["standalone"], ["visual", "standalone"]):
        selection = dict(base, cases=cases, options={"mp_host": True})
        adapter.validate(selection)
        assert startup in adapter.sources(project, selection), "Host bootstrap must be frozen input"
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            runtime = {"roles": {role: {} for role in ("server", "client1", "client2")}}
            for role in runtime["roles"]:
                cache = output / role
                lua = cache / "mods/ActionQueueTest/42/media/lua"
                (lua / "client").mkdir(parents=True)
                (lua / "shared").mkdir()
                (lua / "shared/QueueTestSelection.lua").write_text("runner-owned selection\n")
                (cache / "Lua").mkdir()
                (cache / "Lua/smoke-user.txt").write_text(role + "\n")
            adapter.stage(project, output, None, None, selection, {}, runtime)
            for role in runtime["roles"]:
                cache = output / role
                lua = cache / "mods/ActionQueueTest/42/media/lua"
                assert (lua / "client/ZZStartup.lua").read_bytes() == startup.read_bytes()
                assert (lua / "shared/QueueTestSelection.lua").read_text() == "runner-owned selection\n"
                assert (cache / "Lua/smoke-user.txt").read_text() == role + "\n"
    assert startup not in adapter.sources(project, dict(base, cases=["standalone"])), "Legacy route must not gain startup callbacks"
    for changes in ({"cases": ["reload"]}, {"languages": ["RU", "EN"]}):
        try:
            adapter.validate(dict(dict(base, cases=["standalone"], options={"mp_host": True}), **changes))
        except ValueError:
            pass
        else:
            raise AssertionError("Unsupported Host lifecycle or actor languages accepted")
    print("PASS wishlist menu Host: frozen bootstrap, runner-owned role inputs and reload rejection")


def main():
    manifest = json.loads((HERE / "manifest.json").read_text())
    assert manifest["status"] == "intake-only" and manifest["native_kinds"] == ["mp"]
    assert manifest["historical_checks_per_client"] == {"full": 33, "standalone": 26, "reload": 5, "visual": 11}
    source = HERE / "prepare.py"
    module = {"__file__": str(source), "__name__": "wishlist_prepare"}
    exec(compile(source.read_text(), str(source), "exec"), module)
    with tempfile.TemporaryDirectory() as directory:
        cache = Path(directory)
        config = module["prepare"](cache, "client1", "standalone", "configured-host", 12345, "ephemeral-check-value", ["PZSurvivorToolkit"])
        assert config.read_text().splitlines()[:4] == ["client1", "standalone", "configured-host", "12345"]
        assert config.stat().st_mode & 0o077 == 0
        assert sorted(p.name for p in (cache / "mods/WishlistTest/42/media/lua/client").iterdir()) == ["ZZWishlist.lua"]
        try:
            module["prepare"](cache, "client1", "standalone", "configured-host", 12345, "ephemeral-check-value", ["PZSurvivorToolkit"])
        except ValueError:
            pass
        else:
            raise AssertionError("Prepared cache was overwritten")
        for host, port, password, mods in [("host\nextra", 12345, "value", ["PZSurvivorToolkit"]), ("host", 65535, "value", ["PZSurvivorToolkit"]), ("host", 12345, "", ["PZSurvivorToolkit"]), ("host", 12345, "value", ["bad/id"])]:
            try:
                module["prepare"](cache / "invalid", "client1", "standalone", host, port, password, mods)
            except ValueError:
                pass
            else:
                raise AssertionError("Unsafe runtime configuration accepted")
        assert not (cache / "invalid").exists()
    lua = shutil.which("luajit") or shutil.which("lua5.1") or shutil.which("lua")
    if not lua:
        raise SystemExit("No Lua interpreter on PATH; native fixture syntax/registration remains unchecked")
    result = subprocess.run([lua, str(HERE / "check.lua"), str(HERE)], check=True, capture_output=True, text=True)
    names = {}
    for line in result.stdout.splitlines():
        if line.startswith("STAGE\t"):
            _, scenario, name = line.split("\t", 2)
            if scenario != "reload" or name not in names.get(scenario, []):
                names.setdefault(scenario, []).append(name)
        else:
            print(line)
    assert names == json.loads((HERE / "stage-names.json").read_text()), "Preserved stage names changed"
    with tempfile.TemporaryDirectory() as directory:
        session = Path(directory) / "WishlistSession.lua"
        session.write_text(module["session_source"](["visual", "standalone"], "client"))
        subprocess.run([lua, str(HERE / "protocol.lua"), str(HERE), str(HERE.parents[3]), str(session)], check=True)
    check_host_adapter()
    print("PASS helper preparation, collision protection and runtime parameter validation")
    print("NOT RUN: PZ, SP/MP, rendered UI, network or restart persistence")


if __name__ == "__main__":
    main()
