#!/usr/bin/env python3
"""Build the diagnostic-only B42.21 visual synchronization fixture."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

SOURCE = Path(__file__).resolve().parent


def run(command, **kwargs):
    return subprocess.run(list(map(str, command)), check=True, text=True, **kwargs)


def check(jdk, game, output, classpath):
    classes = output / "checkclasses"
    classes.mkdir()
    run([jdk / "bin/javac", "--release", "25", "-cp", classpath, "-d", classes, SOURCE / "NativeChecks.java"])
    command = [jdk / "bin/java", f"-javaagent:{game / 'ZombieBuddy.jar'}=config_dir={output / 'check-cache'},policy=deny-new,verbosity=1",
               "-Djava.awt.headless=true", "-Dzomboid.steam=0", "-Djava.library.path=.", "-cp",
               os.pathsep.join([str(classes), classpath]), "NativeChecks"]
    result = subprocess.run(list(map(str, command)), cwd=game, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (output / "native-check.log").write_text(result.stdout)
    result.check_returncode()
    markers = re.findall(r"NATIVE_CASES_PASS phase=(\w+) bytes=(\d+) count=(\d+) sha256=(\w+)", result.stdout)
    if len(markers) != 2 or [x[0] for x in markers] != ["original", "woven"] or markers[0][1:] != markers[1][1:]:
        raise RuntimeError("Original and woven native cases did not produce identical bytes/count/digest")
    trace = [json.loads(line.split("[SYNC_VISUALS_TRACE] ", 1)[1]) for line in result.stdout.splitlines() if "[SYNC_VISUALS_TRACE] " in line]
    exits = [row for row in trace if row["kind"] == "visual.parse.exit"]
    size = int(markers[0][1])
    if [(len(row["packetVisuals"]), row["consumed"]) for row in exits] != [(7, 4), (8, size), (8, size)]:
        raise RuntimeError("Trace changed native parser results or omitted events")
    wires = [row["wire"] for row in trace if "wire" in row and row.get("error") is None]
    if not wires or any(row["sha256"] != markers[0][3] for row in wires):
        raise RuntimeError("Trace write/read wire digests differ")
    if len([row for row in trace if row.get("error", "") and "NullPointerException" in row["error"]]) != 1 or "NATIVE_FAILURE_PRESERVED_PASS" not in result.stdout:
        raise RuntimeError("Native failure was changed or was not traced")
    quoted = [json.loads(line.split("JSON_CHECK ", 1)[1]) for line in result.stdout.splitlines() if line.startswith("JSON_CHECK ")]
    if len(quoted) != 1 or quoted[0]["wire"]["bytes"] != 5 or quoted[0]["quoted"] != 'quote"\\\n\t':
        raise RuntimeError("JSON escaping or nonmutating buffer self-check failed")
    (output / "native-check.json").write_text(json.dumps({"checks": "PASS", "markers": markers, "trace": trace}, indent=2) + "\n")
    print(f"CHECK_PASS bytes={size} count={markers[0][2]} sha256={markers[0][3]} (mismatch, valid, swapped identities, native failure, JSON, unchanged buffer)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, required=True, help="Java directory containing projectzomboid.jar and ZombieBuddy.jar")
    parser.add_argument("--jdk", type=Path, required=True, help="JDK 25+ home")
    parser.add_argument("--output", type=Path, required=True, help="Fresh output directory outside the repository")
    parser.add_argument("--check", action="store_true", help="Run headless native parser and woven diagnostic checks")
    args = parser.parse_args()
    game, jdk, output = args.game.resolve(), args.jdk.resolve(), args.output.resolve()
    if output.is_relative_to(SOURCE.parents[3]):
        parser.error("--output must be outside the repository")
    if output.exists():
        parser.error("--output already exists; choose a fresh directory")
    for file in [game / "projectzomboid.jar", game / "ZombieBuddy.jar", jdk / "bin/javac", jdk / "bin/jar", jdk / "bin/java"]:
        if not file.is_file():
            parser.error(f"Missing required file: {file}")
    version = run([jdk / "bin/javac", "-version"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT).stdout
    match = re.search(r"javac (\d+)", version)
    if not match or int(match[1]) < 25:
        parser.error(f"JDK 25+ is required to read B42.21 game classes; found {version.strip()}")
    output.mkdir(parents=True)
    classes = output / "classes"
    classes.mkdir()
    classpath = os.pathsep.join(str(game / name) for name in ["projectzomboid.jar", "ZombieBuddy.jar"])
    run([jdk / "bin/javac", "--release", "25", "-cp", classpath, "-d", classes, SOURCE / "src/net/alexredby/visualtrace/Main.java"])
    mod = output / "SyncVisualsTraceFixture"
    jar = mod / "42/media/java/SyncVisualsTraceFixture.jar"
    jar.parent.mkdir(parents=True)
    (mod / "common").mkdir()
    (mod / "42/mod.info").write_text("name=Sync Visuals Trace Fixture\nid=SyncVisualsTraceFixture\nversion=0.0.1\nauthor=AlexRedby\nversionMin=42.21\nversionMax=42.21\nrequire=\\ZombieBuddy\njavaJarFile=media/java/SyncVisualsTraceFixture.jar\njavaPkgName=net.alexredby.visualtrace\nZBVersionMin=2.3.4\ndescription=Temporary diagnostic-only clothing packet and native bandage lifecycle trace.\n")
    run([jdk / "bin/jar", "--create", "--file", jar, "-C", classes, "net/alexredby/visualtrace"])
    if args.check:
        check(jdk, game, output, os.pathsep.join([str(jar), classpath]))
    print(json.dumps({"modroot": str(mod), "jar": str(jar), "sha256": hashlib.sha256(jar.read_bytes()).hexdigest()}))


if __name__ == "__main__":
    main()
