"""No-game intake validation; registration counts are not native pass results."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent


def main():
    manifest = json.loads((HERE / "manifest.json").read_text())
    assert manifest["status"] == "intake-only" and manifest["native_kinds"] == ["mp"]
    assert manifest["historical_checks_per_client"] == {"full": 33, "standalone": 26, "reload": 5, "visual": 11}
    source = HERE / "prepare.py"
    module = {"__file__": str(source), "__name__": "wishlist_prepare"}
    exec(compile(source.read_text(), str(source), "exec"), module)
    with tempfile.TemporaryDirectory() as directory:
        cache = Path(directory)
        config = module["prepare"](cache, "client1", "standalone", "configured-host", 12345, "ephemeral-check-value", ["PZSurvivorWishlist"])
        assert config.read_text().splitlines()[:4] == ["client1", "standalone", "configured-host", "12345"]
        assert config.stat().st_mode & 0o077 == 0
        assert sorted(p.name for p in (cache / "mods/WishlistTest/42/media/lua/client").iterdir()) == ["ZZWishlist.lua"]
        try:
            module["prepare"](cache, "client1", "standalone", "configured-host", 12345, "ephemeral-check-value", ["PZSurvivorWishlist"])
        except ValueError:
            pass
        else:
            raise AssertionError("Prepared cache was overwritten")
        for host, port, password, mods in [("host\nextra", 12345, "value", ["PZSurvivorWishlist"]), ("host", 65535, "value", ["PZSurvivorWishlist"]), ("host", 12345, "", ["PZSurvivorWishlist"]), ("host", 12345, "value", ["bad/id"])]:
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
    subprocess.run([lua, str(HERE / "protocol.lua"), str(HERE), str(HERE.parents[3])], check=True)
    print("PASS helper preparation, collision protection and runtime parameter validation")
    print("NOT RUN: PZ, SP/MP, rendered UI, network or restart persistence")


if __name__ == "__main__":
    main()
