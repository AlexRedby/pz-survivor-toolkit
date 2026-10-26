#!/usr/bin/env python3
"""Compare a test-only lookup splice against the same external native classes and inputs."""
import argparse
from contextlib import nullcontext
import hashlib
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys
import zipfile

SOURCE = Path(__file__).resolve().parent
ROOT = SOURCE.parents[2]
GUARDS = {
    "zombie/inventory/ItemPickerJava.class": "5c8cf626e46a52cdbd9d73e9de10766dece3388ee3e4f4d8d071df5e44d68522",
    "zombie/scripting/ScriptManager.class": "8aee81a03fb7c09a9e9844ba9388a943aef9b313ea00017b8f2a33f16f4f0f99",
    "zombie/scripting/objects/Item.class": "9e6a2f7fe48cc66843fea06b4821063d7cc6a73eaba0de8ee51d0a15c373202e",
    "zombie/SandboxOptions.class": "d90458506ab559c7d9b84588a1a62a78ceb7b4c6303bb2127d823fc21c4e7297",
    "zombie/scripting/ScriptBucketCollection.class": "61ba45ea197992413af259c3736820d1669a5678f577f661956d0c3e8fbf9781",
    "zombie/scripting/ScriptBucket.class": "dc7a234f0d1fb162ef6b6ce316f16d13d87a52a93d863016abc7a7b9ba41d4dc",
    "zombie/scripting/objects/ScriptModule.class": "10606317c7d84eb1b5c0df06a27687803aaefbc13e7d7148e99c6d9074442856",
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def run(args, cwd, log):
    result = subprocess.run(list(map(str, args)), cwd=cwd, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
    log.write_text(result.stdout)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}); see {log}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("game", "jdk", "output"):
        parser.add_argument("--" + key, type=Path, required=True)
    parser.add_argument("--measure", action="store_true", help="Reserve the common exclusive test slot before timing")
    parser.add_argument("--forks", type=int, default=5)
    parser.add_argument("--iterations", type=int, default=200000)
    parser.add_argument("--resource-wait", type=int, default=900)
    args = parser.parse_args()
    if args.forks < 1 or args.iterations < 1 or args.resource_wait < 0:
        parser.error("forks/iterations must be positive and resource-wait nonnegative")
    game, jdk, out = (getattr(args, key).resolve() for key in ("game", "jdk", "output"))
    if out.exists() or out == game or game in out.parents:
        parser.error("Output must be a new directory outside the game installation")
    native, buddy = game / "projectzomboid.jar", game / "ZombieBuddy.jar"
    if not buddy.is_file():
        parser.error("ZombieBuddy.jar is required only as the build-time ASM dependency")
    with zipfile.ZipFile(native) as archive:
        for name, digest in GUARDS.items():
            if sha(archive.read(name)) != digest:
                parser.error("Native input guard mismatch: " + name)
    out.mkdir(parents=True)
    classes, sources, work = out / "classes", out / "source", out / "work"
    for folder in (classes, sources, work, out / "client1", out / "home"):
        folder.mkdir()
    fingerprints = {}
    for name in ("LookupCandidate.java", "LootLookupCheck.java", "run.py"):
        data = (SOURCE / name).read_bytes()
        (sources / name).write_bytes(data)
        fingerprints[name] = sha(data)
    cp = os.pathsep.join(map(str, (native, buddy)))
    run([jdk / "bin/javac", "--release", "25", "-cp", cp, "-d", classes,
         sources / "LookupCandidate.java", sources / "LootLookupCheck.java"], work, out / "compile.log")
    build_cp = os.pathsep.join((str(classes), cp))
    patch = run([jdk / "bin/java", "-cp", build_cp, "LookupCandidate", native, out / "overlay"],
                work, out / "splice.log")
    if "LOOKUP_SPLICE_READY" not in patch:
        raise RuntimeError("Splice guard check did not finish")
    receipt = {"format": 1, "research_only": True, "native_guards": GUARDS,
               "sources": fingerprints, "game_jar_sha256": sha(native.read_bytes()),
               "buddy_jar_sha256": sha(buddy.read_bytes()),
               "patched_class_sha256": sha((out / "overlay/zombie/inventory/ItemPickerJava.class").read_bytes()),
               "measure": args.measure, "forks": args.forks if args.measure else 1,
               "iterations": args.iterations if args.measure else 0}
    receipt["java_version"] = run([jdk / "bin/java", "-version"], work, out / "java-version.log").strip()
    (out / "input-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    vectors = None
    consumed = None
    rows = []
    compilation_overlap = []

    def invoke(mode, fork, measure):
        nonlocal vectors, consumed
        tag = f"{fork}-{mode}"
        classpath = [classes]
        if mode == "candidate":
            classpath.append(out / "overlay")
        classpath.extend((native, buddy))
        command = [jdk / "bin/java", "-Xms256m", "-Xmx256m", "-Xbatch", "-Djava.awt.headless=true",
                   "-Duser.home=" + str(out / "home"), "-Dpz.test.cache=" + str(out / "client1"),
                   "-Dloot.iterations=" + str(args.iterations),
                   "-Xlog:jit+compilation=debug:file=" + str(out / (tag + "-jit.log")),
                   "-cp", os.pathsep.join(map(str, classpath)), "LootLookupCheck"]
        if measure:
            command.append("--measure")
        log = run(command, work, out / (tag + ".log"))
        actual = [line for line in log.splitlines() if line.startswith("VECTOR ")]
        if not actual:
            raise RuntimeError("No actual-source vectors: " + tag)
        if vectors is None:
            vectors = actual
        if vectors != actual:
            raise RuntimeError("Native/candidate result mismatch: " + tag)
        sums = [line for line in log.splitlines() if line.startswith("CONSUMED ")]
        if measure:
            if len(sums) != 4:
                raise RuntimeError("Missing consumed benchmark outputs: " + tag)
            if consumed is None:
                consumed = sums
            if consumed != sums:
                raise RuntimeError("Benchmark result mismatch: " + tag)
            windows = []
            for line in log.splitlines():
                if line.startswith("WINDOW "):
                    _, label, round_, began, ended = line.split()
                    windows.append((int(began), int(ended)))
            for line in (out / (tag + "-jit.log")).read_text().splitlines():
                at = re.match(r"\[([0-9.]+)s\]", line)
                relevant = any(name in line for name in ("ItemPickerJava::", "ScriptManager::", "ScriptBucket::",
                                                        "ScriptModule::", "LootLookupCheck::loop", "LootLookupCheck$Vector::"))
                if at and relevant and any(begin <= float(at[1]) * 1000 <= end for begin, end in windows):
                    compilation_overlap.append(dict(run=tag, line=line))
        for line in log.splitlines():
            if line.startswith("MEASURE "):
                _, label, round_, count, wall, cpu, allocation = line.split()
                rows.append(dict(mode=mode, fork=fork, label=label, round=int(round_),
                                 iterations=int(count), wall_ns=int(wall), cpu_ns=int(cpu),
                                 allocated_bytes=int(allocation)))
        if measure and not any(row['mode'] == mode and row['fork'] == fork for row in rows):
            raise RuntimeError("No timing rows: " + tag)
        print("PASS " + tag + " vectors=" + str(len(actual)), flush=True)

    # Validate cold actual-source behavior before acquiring a potentially contended timing slot.
    for mode in ("stock", "candidate"):
        invoke(mode, "check", False)
    context = nullcontext(None)
    if args.measure:
        sys.path.insert(0, str(ROOT / "tools"))
        from queue_checks import admission
        selection = {"kind": "sp", "clients": 1, "suite": "loot-lookup-headless",
                     "resources": {"heap_mib": 256, "native_mib": 256,
                                   "cpu_per_instance": 1.0, "exclusive": True}}
        runtime = {"roles": {"client1": {"cache": str(out / "client1")}}}
        context = admission.acquire(out, selection, runtime, args.resource_wait)
    with context as resources:
        if args.measure:
            (out / "admission.json").write_text(json.dumps(resources, indent=2) + "\n")
            for fork in range(args.forks):
                for mode in (("stock", "candidate") if fork % 2 == 0 else ("candidate", "stock")):
                    invoke(mode, fork, True)
    summary = []
    paired = []
    for label in sorted({row['label'] for row in rows}):
        for mode in ("stock", "candidate"):
            selected = [row for row in rows if row['label'] == label and row['mode'] == mode]
            forks = []
            for fork in range(args.forks):
                subset = [row for row in selected if row['fork'] == fork]
                if not subset:
                    raise RuntimeError("Missing paired fork: " + label)
                forks.append({key: statistics.median(row[key] / row['iterations'] for row in subset)
                              for key in ("wall_ns", "cpu_ns", "allocated_bytes")})
            summary.append(dict(label=label, mode=mode, fork_medians=forks,
                                median={key: statistics.median(row[key] for row in forks)
                                        for key in forks[0]}))
        stock, candidate = [row for row in summary if row['label'] == label]
        deltas = [{key: after[key] - before[key] for key in before}
                  for before, after in zip(stock['fork_medians'], candidate['fork_medians'])]
        paired.append(dict(label=label, candidate_minus_stock= deltas,
                           median_delta={key: statistics.median(row[key] for row in deltas) for key in deltas[0]}))
    (out / "result.json").write_text(json.dumps(dict(receipt=receipt, vectors=vectors, consumed=consumed,
                                                    measurements=rows, summary=summary, paired=paired,
                                                    relevant_compilation_in_measurement=compilation_overlap), indent=2) + "\n")
    if compilation_overlap:
        raise RuntimeError("Relevant JIT compilation overlapped timed rounds; retain result as unqualified")
    print("LOOT_LOOKUP_CHECK_PASS " + str(out / "result.json"))


if __name__ == "__main__":
    main()
