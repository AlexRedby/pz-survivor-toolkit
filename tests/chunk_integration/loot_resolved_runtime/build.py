#!/usr/bin/env python3
"""Build an explicitly armed, initial-load-only native loot fixture; install nothing."""
import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid
import zipfile

SOURCE = Path(__file__).resolve().parent
MOD_ID = "PZLootResolvedRuntime"
OPT_IN = "loot-resolved-runtime.opt-in"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def load_guards():
    tree = ast.parse((SOURCE.parent / "loot_resolved/run.py").read_text())
    declarations = [node for node in tree.body if isinstance(node, ast.Assign)
                    and any(isinstance(target, ast.Name) and target.id == "GUARDS" for target in node.targets)]
    if len(declarations) != 1:
        raise ValueError("Expected one reviewed native calculation guard declaration")
    guards = ast.literal_eval(declarations[0].value)
    guards.update(json.loads((SOURCE / "success-native-hashes.json").read_text()))
    return guards


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("game", "jdk", "output", "cache"):
        parser.add_argument("--" + name, required=True, type=Path)
    parser.add_argument("--mode", required=True, choices=("control", "candidate"))
    parser.add_argument("--check", action="store_true", help="Headless initial-definition/token/RNG-ownership guards only")
    args = parser.parse_args()
    for name in ("game", "jdk", "output", "cache"):
        setattr(args, name, getattr(args, name).resolve())
    if args.output.exists() or args.output == args.game or args.game in args.output.parents:
        parser.error("Output must be new and outside the game installation")
    marker = args.cache / "Lua/smoke-user.txt"
    if not marker.exists() and not marker.is_symlink(): marker = args.cache / "smoke-user.txt"
    if marker.is_symlink() or not marker.is_file() or not 0 < marker.stat().st_size <= 1024:
        parser.error("--cache must contain a regular, nonempty owned-test smoke-user.txt marker")
    opt_in = args.cache / OPT_IN
    if opt_in.exists() or opt_in.is_symlink():
        parser.error("Use a fresh owned cache without this fixture's opt-in")
    if any(os.environ.get(key) for key in ("JAVA_TOOL_OPTIONS", "JDK_JAVA_OPTIONS", "_JAVA_OPTIONS")):
        parser.error("Unset injected JVM option variables")
    native, buddy = args.game / "projectzomboid.jar", args.game / "ZombieBuddy.jar"
    guards = load_guards()
    with zipfile.ZipFile(native) as archive:
        for name, expected in guards.items():
            if sha(archive.read(name)) != expected:
                parser.error("Unsupported native bytes: " + name)
    sources = {path.name: path.read_bytes() for path in SOURCE.iterdir() if path.is_file()}
    candidate_source = SOURCE.parent / "loot_resolved/ResolvedCandidate.java"
    sources["ResolvedCandidate.java"] = candidate_source.read_bytes()
    fingerprints = {name: sha(data) for name, data in sources.items()}
    fingerprints["../loot_resolved/run.py"] = sha((SOURCE.parent / "loot_resolved/run.py").read_bytes())
    token = uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix="pz-loot-runtime-build-") as directory:
        stage = Path(directory)
        src, classes, checks = stage / "source", stage / "classes", stage / "checks"
        for path in (src, classes, checks): path.mkdir()
        for name, data in sources.items(): (src / name).write_bytes(data)
        (src / "ResolvedCandidate.java").write_text("package toolkit.lootresolved.bootstrap;\n" + sources["ResolvedCandidate.java"].decode())
        cp = os.pathsep.join(map(str, (native, buddy)))
        javac, java = args.jdk / "bin/javac", args.jdk / "bin/java"
        subprocess.run([str(javac), "--release", "25", "-cp", cp, "-d", str(classes),
                        *map(str, (src / name for name in ("ResolvedCandidate.java", "Bootstrap.java", "PreMain.java", "Main.java")))], check=True)
        resource = classes / "toolkit/lootresolved/bootstrap"
        (resource / "token.txt").write_text(token + "\n", encoding="ascii")
        (resource / "mode.txt").write_text(args.mode + "\n", encoding="ascii")
        (resource / "native-hashes.properties").write_text("".join(name.removesuffix(".class") + "=" + digest + "\n" for name,digest in sorted(guards.items())))
        logs = {}
        if args.check:
            check_cp = os.pathsep.join((str(classes),cp))
            subprocess.run([str(javac), "--release", "25", "-cp", check_cp, "-d", str(checks),
                            str(src / "BootstrapChecks.java"), str(src / "RuntimeCleanupChecks.java")],check=True)
            preload_jar = stage / "preload-check.jar"
            with zipfile.ZipFile(preload_jar, "w", zipfile.ZIP_DEFLATED) as archive:
                archive.writestr("META-INF/MANIFEST.MF", "Manifest-Version: 1.0\nZB-Preload: true\n\n")
                for file in sorted(resource.rglob("*")):
                    if file.is_file(): archive.writestr(file.relative_to(classes).as_posix(), file.read_bytes())
            for scenario in ("missing-token", "already-loaded", "initial-definition", "preload"):
                cache = stage / ("cache-" + scenario); cache.mkdir()
                (cache / "smoke-user.txt").write_text("owned-headless-admission-only\n")
                if scenario != "missing-token": (cache / OPT_IN).write_text(token + "\n")
                config = cache / "zombie-buddy"; config.mkdir()
                preload = ",patches_jar=" + str(preload_jar) + ":toolkit.lootresolved.bootstrap" if scenario == "preload" else ""
                command = [str(java), "-javaagent:" + str(buddy) + "=config_dir=" + str(config) + ",policy=deny-new,verbosity=1" + preload,
                           "-Djava.awt.headless=true", "-Duser.home=" + str(stage / "home"), "-Dzomboid.steam=0", "-cp",
                           os.pathsep.join((str(checks),check_cp)), "toolkit.lootresolved.bootstrap.BootstrapChecks", str(cache), scenario]
                result = subprocess.run(command,cwd=stage,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90)
                logs[scenario] = result.stdout
                if result.returncode or "LOOT_RESOLVED_BOOTSTRAP_CHECK_PASS" not in result.stdout or "Error during transformation" in result.stdout:
                    print(result.stdout)
                    raise SystemExit("Admission check failed: " + scenario + "; no fixture/cache opt-in written")
        fixture = stage / MOD_ID / "42"
        for folder in ("media/java", "media/bootstrap", "media/lua/shared"): (fixture / folder).mkdir(parents=True)
        (fixture / "mod.info").write_bytes(sources["mod.info.template"])
        (fixture / "media/lua/shared/ZZLootResolvedRuntime.lua").write_bytes(sources["ZZLootResolvedRuntime.lua"])
        receipt = {"format":1, "test_only":True, "mode":args.mode, "sources":fingerprints,
                   "native_hashes":guards, "headless_checks":list(logs),
                   "success_path_checked":False, "entry_point":"lootResolvedRuntimeRun",
                   "terminal_marker":"[LOOT_RESOLVED_RUNTIME] FINISH status=",
                   "required_preload":"42/media/bootstrap/PZLootResolvedBootstrap.jar"}
        for jar_name, package, preload in (("media/bootstrap/PZLootResolvedBootstrap.jar", "toolkit/lootresolved/bootstrap", True),
                                           ("media/java/PZLootResolvedRuntime.jar", "toolkit/lootresolved/runtime", False)):
            with zipfile.ZipFile(fixture / jar_name,"w",zipfile.ZIP_DEFLATED) as archive:
                if preload: archive.writestr("META-INF/MANIFEST.MF", "Manifest-Version: 1.0\nZB-Preload: true\n\n")
                for file in sorted((classes / package).rglob("*")):
                    if file.is_file(): archive.writestr(file.relative_to(classes).as_posix(),file.read_bytes())
                archive.writestr("META-INF/loot-runtime-inputs.json",json.dumps(receipt,sort_keys=True) + "\n")
        args.output.mkdir(parents=True)
        shutil.copytree(stage / MOD_ID,args.output / MOD_ID)
        (args.output / "build-receipt.json").write_text(json.dumps(receipt,indent=2) + "\n")
        for scenario, text in logs.items(): (args.output / ("check-" + scenario + ".log")).write_text(text)
        with opt_in.open("x",encoding="ascii") as stream: stream.write(token + "\n")
    print("Fixture: " + str(args.output / MOD_ID))
    print("Explicit early preload: " + str(args.output / MOD_ID / "42/media/bootstrap/PZLootResolvedBootstrap.jar"))
    print("No game installation performed; success-path parity remains a native-game check")


if __name__ == "__main__":
    main()
