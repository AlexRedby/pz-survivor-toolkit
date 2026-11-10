#!/usr/bin/env python3
"""Run the focused Wishlist model/server checks against the game's Lua runtime."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
MARKERS = (
    "WISHLIST_MODEL_NATIVE_PASS",
    "WISHLIST_MODEL_RETAINED_CONTROL_REJECTED",
    "WISHLIST_MODEL_NATIVE_WITNESS_PASS",
)
SCOPE = "Focused headless Wishlist model/server checks; no gameplay."


def fingerprint(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return {"sha256": digest.hexdigest(), "size": path.stat().st_size}


def source_paths():
    lua = ROOT / "PZSurvivorToolkit/42/media/lua"
    return sorted([ROOT / "tools/check_wishlist_model_native.py",
                   ROOT / "tests/native_wishlist_model/WishlistModelChecks.java",
                   ROOT / "tests/test_wishlist_model.lua",
                   *lua.glob("shared/PZSurvivorWishlist.lua"),
                   *lua.glob("shared/PZSurvivorWishlist/**/*.lua"),
                   *lua.glob("server/PZSurvivorWishlist/**/*.lua")])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, required=True)
    parser.add_argument("--jdk", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    game, jdk = args.game.resolve(), args.jdk.resolve()
    output = args.output.absolute()
    inputs = {"game_jar": game / "projectzomboid.jar", "stdlib": game / "stdlib.lbc",
              "java": jdk / "bin/java", "javac": jdk / "bin/javac"}
    sources = source_paths()
    if output.exists() or output.is_symlink():
        parser.error(f"output already exists: {output}")
    missing = [str(p) for p in [*inputs.values(), *sources] if not p.is_file()]
    if missing:
        parser.error("missing input files: " + ", ".join(missing))
    if not any(p.name == "Model.lua" for p in sources) or not any(p.name == "Server.lua" for p in sources):
        parser.error("Wishlist production sources are missing")

    output.mkdir(parents=True, exist_ok=False)
    classes = output / "classes"
    classes.mkdir()
    report = {"scope": SCOPE, "status": "failed", "inputs": {}, "sources": {},
              "compile_exit": None, "run_exit": None, "markers": {m: 0 for m in MARKERS}}
    try:
        report["inputs"] = {name: {"path": str(path), **fingerprint(path)} for name, path in inputs.items()}
        report["sources"] = {str(path.relative_to(ROOT)): fingerprint(path) for path in sources}
        compile_result = subprocess.run([str(inputs["javac"]), "-cp", str(inputs["game_jar"]),
                                         "-d", str(classes), str(sources[[p.name for p in sources].index("WishlistModelChecks.java")])],
                                        capture_output=True, text=True, check=False, timeout=60)
        report["compile_exit"] = compile_result.returncode
        (output / "compile.log").write_text(compile_result.stdout + compile_result.stderr)
        if compile_result.returncode == 0:
            run_result = subprocess.run([str(inputs["java"]), "-Djava.awt.headless=true", "-cp",
                                         f"{classes}{os.pathsep}{inputs['game_jar']}",
                                         "WishlistModelChecks", str(ROOT), str(game)],
                                        capture_output=True, text=True, check=False, timeout=60)
            report["run_exit"] = run_result.returncode
            (output / "run.log").write_text(run_result.stdout + run_result.stderr)
            lines = run_result.stdout.splitlines()
            report["markers"] = {marker: lines.count(marker) for marker in MARKERS}
            if run_result.returncode == 0 and all(count == 1 for count in report["markers"].values()):
                report["status"] = "passed"
    except (OSError, subprocess.SubprocessError) as exc:
        report["error"] = str(exc)
    finally:
        # Retain the initial fingerprints as the record of intended inputs, and
        # refuse success if any input or the declared source set changed meanwhile.
        issues = []
        current_sources = source_paths()
        initial_names = set(report["sources"])
        current_names = {str(path.relative_to(ROOT)) for path in current_sources}
        for name in sorted(initial_names ^ current_names):
            issues.append(f"source membership changed: {name}")
        for name, previous in report["sources"].items():
            try:
                if fingerprint(ROOT / name) != previous:
                    issues.append(f"source changed: {name}")
            except OSError:
                issues.append(f"source missing or unreadable: {name}")
        for name, previous in report["inputs"].items():
            try:
                if fingerprint(inputs[name]) != {k: previous[k] for k in ("sha256", "size")}:
                    issues.append(f"input changed: {name}")
            except OSError:
                issues.append(f"input missing or unreadable: {name}")
        report["input_issues"] = issues
        if issues:
            report["status"] = "failed"
        (output / "compile.log").touch(exist_ok=True)
        (output / "run.log").touch(exist_ok=True)
        (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"{report['status']}: {output / 'report.json'}")
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())
