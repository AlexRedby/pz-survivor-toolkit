"""Install only this helper and its runtime parameters; never launch or copy PZ."""
import argparse
import os
from pathlib import Path
import re
import shutil

HERE = Path(__file__).resolve().parent


def prepare(cache, user, mode, host, port, password, mods):
    if user not in ("client1", "client2", "server") or mode not in ("full", "standalone", "reload", "visual"):
        raise ValueError("Unsupported fixture actor or mode")
    if not 1 <= port <= 65534:
        raise ValueError("Port must leave room for the server's adjacent UDP port")
    if not mods or len(mods) != len(set(mods)) or "PZSurvivorWishlist" not in mods:
        raise ValueError("Supply unique product mod IDs including PZSurvivorWishlist")
    if any(not re.fullmatch(r"[A-Za-z0-9_.-]+", mod) for mod in mods):
        raise ValueError("Invalid mod ID")
    if mode in ("standalone", "visual") and mods != ["PZSurvivorWishlist"]:
        raise ValueError("Standalone/visual modes require only PZSurvivorWishlist")
    if mode == "full" and "PZSurvivorToolkit" not in mods:
        raise ValueError("Full mode requires PZSurvivorToolkit plus the declared integrations")
    values = [user, mode, host, str(port), password, ";".join(mods)]
    if any(not value or any(c in value for c in "\r\n\0") for value in values):
        raise ValueError("Runtime parameters must be nonempty single lines")
    helper = cache / "mods/WishlistTest"
    config = cache / "Lua/wishlist-fixture.txt"
    if helper.exists() or config.exists():
        raise ValueError("Fixture already exists; do not overwrite a prepared cache")
    helper.mkdir(parents=True)
    (helper / "common").mkdir()
    lua = helper / "42/media/lua"
    for side in ("client", "server"):
        shutil.copytree(HERE / side, lua / side)
    (helper / "42/mod.info").write_text("name=Isolated wishlist fixture\nid=WishlistTest\nversionMin=42.21\n", encoding="utf-8")
    config.parent.mkdir(parents=True, exist_ok=True)
    # This disposable runtime file contains the supplied test password.
    with open(config, "x", encoding="utf-8", opener=lambda path, flags: os.open(path, flags, 0o600)) as output:
        output.write("\n".join(values) + "\n")
    return config


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cache", type=Path)
    parser.add_argument("--user", choices=("server", "client1", "client2"), required=True)
    parser.add_argument("--mode", choices=("full", "standalone", "reload", "visual"), required=True)
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--password-env", required=True, help="Name of an environment variable; never pass the password in argv")
    parser.add_argument("--mods", nargs="+", default=["PZSurvivorWishlist"])
    args = parser.parse_args()
    if args.password_env not in os.environ:
        parser.error("Password environment variable is missing")
    try:
        prepare(args.cache, args.user, args.mode, args.host, args.port, os.environ[args.password_env], args.mods)
    except ValueError as error:
        parser.error(str(error))
    print("Prepared helper only; no game, launcher, mods, world or server was started.")


if __name__ == "__main__":
    main()
