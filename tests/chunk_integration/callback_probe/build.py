#!/usr/bin/env python3
"""Build/check a standalone native callback fixture; never install it into the game."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid
import zipfile

ROOT = Path(__file__).resolve().parent
NATIVE_HASHES = {
    "zombie/Lua/Event.class": "cf4b0ba953b8f965fbcacb73ebb5d1a173dc3ed140656e15b90ad932eff0e952",
    "se/krka/kahlua/integration/LuaCaller.class": "0443930027e8f312ae9cb192c628f4b6c10743204597c508f8693cfd7bd79d0b",
}
MOD_ID = "PZChunkCallbackProbe"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("game", "jdk", "output", "cache"):
        parser.add_argument("--" + name, required=True, type=Path)
    parser.add_argument("--check", action="store_true", help="Run headless real-ZombieBuddy weaving/Kahlua checks")
    args = parser.parse_args()
    for name in ("game", "jdk", "output", "cache"):
        setattr(args, name, getattr(args, name).resolve())
    if args.output.exists():
        parser.error("Output must be a new directory")
    if args.output == args.game or args.game in args.output.parents:
        parser.error("Fixture output cannot be inside the game installation")
    marker = args.cache / "smoke-user.txt"
    if marker.is_symlink() or not marker.is_file() or not 0 < marker.stat().st_size <= 1024:
        parser.error("--cache must already contain a regular, nonempty owned-test smoke-user.txt marker")
    opt_in = args.cache / "chunk-callback-probe.opt-in"
    if opt_in.exists() or opt_in.is_symlink():
        parser.error("Cache already has a probe opt-in; use a fresh owned cache")
    game_jar, buddy = args.game / "projectzomboid.jar", args.game / "ZombieBuddy.jar"
    if not buddy.is_file():
        parser.error("ZombieBuddy.jar is required beside projectzomboid.jar")
    with zipfile.ZipFile(game_jar) as native:
        for name, expected in NATIVE_HASHES.items():
            if hashlib.sha256(native.read(name)).hexdigest() != expected:
                parser.error("Unsupported native bytes: " + name)
    names = ("Main.java", "ProbeChecks.java", "mod.info.template", "ZZChunkCallbackProbe.lua", "build.py")
    sources = {name: (ROOT / name).read_bytes() for name in names}
    fingerprints = {name: hashlib.sha256(data).hexdigest() for name, data in sources.items()}
    token = uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix="pz-callback-probe-build-") as temp:
        staging = Path(temp)
        source = staging / "source"
        source.mkdir()
        for name, data in sources.items():
            (source / name).write_bytes(data)
        classes, checks = staging / "classes", staging / "checks"
        classes.mkdir(); checks.mkdir()
        classpath = os.pathsep.join(map(str, (game_jar, buddy)))
        javac, java = args.jdk / "bin/javac", args.jdk / "bin/java"
        subprocess.run([str(javac), "--release", "25", "-cp", classpath, "-d", str(classes),
                        str(source / "Main.java")], check=True)
        resource = classes / "toolkit/chunkprobe/probe-opt-in.txt"
        resource.write_text(token + "\n", encoding="ascii")
        check_output = None
        if args.check:
            checkpath = os.pathsep.join((str(classes), classpath))
            subprocess.run([str(javac), "--release", "25", "-cp", checkpath, "-d", str(checks),
                            str(source / "ProbeChecks.java")], check=True)
            agent_cache = staging / "agent-config"
            agent_cache.mkdir()
            result = subprocess.run([str(java), "-javaagent:" + str(buddy) + "=config_dir=" + str(agent_cache)
                                     + ",policy=deny-new,verbosity=1", "-Djava.awt.headless=true",
                                     "-Duser.home=" + str(staging / "home"), "-Dzomboid.steam=0", "-cp",
                                     os.pathsep.join((str(checks), checkpath)), "toolkit.chunkprobe.ProbeChecks"],
                                    cwd=staging, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
            check_output = result.stdout
            if result.returncode or "CHUNK_CALLBACK_PROBE_CHECK_PASS" not in check_output or "Error during transformation" in check_output:
                print(check_output)
                raise SystemExit("Native weave checks failed; no fixture or opt-in written")
        fixture = staging / MOD_ID
        version = fixture / "42"
        (version / "media/java").mkdir(parents=True)
        (version / "media/lua/client").mkdir(parents=True)
        (version / "mod.info").write_bytes(sources["mod.info.template"])
        (version / "media/lua/client/ZZChunkCallbackProbe.lua").write_bytes(sources["ZZChunkCallbackProbe.lua"])
        receipt = {"format": 1, "test_only": True, "native_hashes": NATIVE_HASHES, "sources": fingerprints,
                   "checked": bool(args.check), "telemetry": "inclusive-per-handler-calls-sum-max",
                   "bounds": {"threads": 16, "handlers_per_thread": 128, "event_depth": 64}}
        with zipfile.ZipFile(version / "media/java/PZChunkCallbackProbe.jar", "w", zipfile.ZIP_DEFLATED) as archive:
            for file in sorted(classes.rglob("*")):
                if file.is_file():
                    archive.writestr(file.relative_to(classes).as_posix(), file.read_bytes())
            archive.writestr("META-INF/chunk-callback-probe-inputs.json", json.dumps(receipt, sort_keys=True) + "\n")
        args.output.mkdir(parents=True)
        shutil.copytree(fixture, args.output / MOD_ID)
        (args.output / "build-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        if check_output is not None:
            (args.output / "weave-check.log").write_text(check_output)
        # The opt-in is created only after a successful build/check; it belongs solely to this fixture.
        with opt_in.open("x", encoding="ascii") as stream:
            stream.write(token + "\n")
    print("Fixture: " + str(args.output / MOD_ID))
    print("Owned cache opt-in written; no game installation performed")
    if args.check:
        print("CHUNK_CALLBACK_PROBE_CHECK_PASS")


if __name__ == "__main__":
    main()
