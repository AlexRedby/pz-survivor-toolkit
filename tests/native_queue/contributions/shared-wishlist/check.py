"""No-game intake validation; registration counts are not native pass results."""
import importlib.util
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
    spec = importlib.util.spec_from_file_location("wishlist_prepare", HERE / "prepare.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    with tempfile.TemporaryDirectory() as directory:
        cache = Path(directory)
        config = module.prepare(cache, "client1", "standalone", "configured-host", 12345, "ephemeral-check-value", ["PZSurvivorWishlist"])
        assert config.read_text().splitlines()[:4] == ["client1", "standalone", "configured-host", "12345"]
        assert config.stat().st_mode & 0o077 == 0
        assert sorted(p.name for p in (cache / "mods/WishlistTest/42/media/lua/client").iterdir()) == ["ZZWishlist.lua"]
        try:
            module.prepare(cache, "client1", "standalone", "configured-host", 12345, "ephemeral-check-value", ["PZSurvivorWishlist"])
        except ValueError:
            pass
        else:
            raise AssertionError("Prepared cache was overwritten")
        for host, port, password, mods in [("host\nextra", 12345, "value", ["PZSurvivorWishlist"]), ("host", 65535, "value", ["PZSurvivorWishlist"]), ("host", 12345, "", ["PZSurvivorWishlist"]), ("host", 12345, "value", ["bad/id"])]:
            try:
                module.prepare(cache / "invalid", "client1", "standalone", host, port, password, mods)
            except ValueError:
                pass
            else:
                raise AssertionError("Unsafe runtime configuration accepted")
        assert not (cache / "invalid").exists()
    lua = shutil.which("luajit") or shutil.which("lua5.1") or shutil.which("lua")
    if not lua:
        raise SystemExit("No Lua interpreter on PATH; native fixture syntax/registration remains unchecked")
    subprocess.run([lua, str(HERE / "check.lua"), str(HERE)], check=True)
    print("PASS helper preparation, collision protection and runtime parameter validation")
    print("NOT RUN: PZ, SP/MP, rendered UI, network or restart persistence")


if __name__ == "__main__":
    main()
