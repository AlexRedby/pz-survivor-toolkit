#!/usr/bin/env python3
"""Exercise a flags-only native IsoLot candidate; never modifies the game installation."""
import argparse
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
    "zombie/iso/IsoLot.class": "c7dd6226fec81d27e761e661fcedc93164bf95fe07c59c3b2b0475c160d37b05",
    "zombie/iso/MapFiles.class": "74cf373fa30d02c3fea7dcbea3d04d3b078808fbc075d015a0a72c76e4f8298c",
    "zombie/iso/LotHeader.class": "4e7408f54917e55187d68065f0a0f7313f5eedacec6167979a2f64a33297fcd9",
    "zombie/popman/ObjectPool.class": "38c883df7d01b8d168510c0aaebf0fd02ad0ecd13630dd4adf2d35dcd6bd641e",
    "zombie/util/BufferedRandomAccessFile.class": "cfd4b73296db2dc5e1f2cf8f5b679af88caac9b642b507ee85674759ebd5c76c",
    "zombie/ChunkMapFilenames.class": "dda963873623685bbee6973248b390f3cf7e0f1963eaed0eb88a88b2340b5f75",
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def run(command, cwd, log):
    result = subprocess.run(list(map(str, command)), cwd=cwd, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
    log.write_text(result.stdout)
    if result.returncode:
        raise RuntimeError(f"Process failed ({result.returncode}); see {log.name}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("game", "jdk", "output"):
        parser.add_argument("--" + key, type=Path, required=True)
    parser.add_argument("--measure", action="store_true")
    parser.add_argument("--forks", type=int, default=3)
    parser.add_argument("--iterations", type=int, default=20000)
    parser.add_argument("--resource-wait", type=int, default=60)
    args = parser.parse_args()
    if not 1 <= args.iterations <= 1000000 or not 1 <= args.forks <= 10 or args.resource_wait < 0:
        parser.error("Invalid bounded measurement parameters")
    game, jdk, out = (getattr(args, key).resolve() for key in ("game", "jdk", "output"))
    if out.exists() or out == game or game in out.parents:
        parser.error("Output must be new and outside the installed game")
    native, buddy = game / "projectzomboid.jar", game / "ZombieBuddy.jar"
    for file in (native, buddy, jdk / "bin/java", jdk / "bin/javac"):
        if not file.is_file():
            parser.error("Missing explicit input: " + str(file))
    with zipfile.ZipFile(native) as archive:
        for name, digest in GUARDS.items():
            if sha(archive.read(name)) != digest:
                parser.error("Native guard mismatch: " + name)
        original = archive.read("zombie/iso/IsoLot.class")
    out.mkdir(parents=True)
    for name in ("classes", "source", "work", "home", "client1"):
        (out / name).mkdir()
    classes, work = out / "classes", out / "work"
    fingerprints = {}
    for name in ("LotLockCandidate.java", "LotLockCheck.java", "run.py"):
        data = (SOURCE / name).read_bytes()
        (out / "source" / name).write_bytes(data)
        fingerprints[name] = sha(data)
    cp = os.pathsep.join(map(str, (native, buddy)))
    run([jdk / "bin/javac", "--release", "25", "-cp", cp, "-d", classes,
         out / "source/LotLockCandidate.java", out / "source/LotLockCheck.java"], work, out / "compile.log")
    run([jdk / "bin/java", "-cp", os.pathsep.join((str(classes), cp)), "LotLockCandidate",
         native, out / "overlay"], work, out / "candidate.log")
    candidate = (out / "overlay/zombie/iso/IsoLot.class").read_bytes()
    changes = [i for i, pair in enumerate(zip(original, candidate)) if pair[0] != pair[1]]
    if len(original) != len(candidate) or len(changes) != 2 or any(
            original[i] & 0x20 == 0 or candidate[i] != original[i] & ~0x20 for i in changes):
        raise RuntimeError("Candidate changes more than two synchronized access bits")
    receipt = dict(format=1, research_only=True, native_guards=GUARDS, sources=fingerprints,
                   game_jar_sha256=sha(native.read_bytes()), buddy_jar_sha256=sha(buddy.read_bytes()),
                   candidate_sha256=sha(candidate), changed_byte_offsets=changes,
                   java_version=run([jdk / "bin/java", "-version"], work, out / "java-version.log").strip())
    (out / "input-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    vectors, consumed, rows, overlap = None, None, [], []
    result = dict(receipt=receipt, status="checking", timing_qualified=False, measurements=rows)

    def save():
        (out / "result.json").write_text(json.dumps(result, indent=2) + "\n")

    def invoke(mode, fork, measure=False):
        nonlocal vectors, consumed
        tag = f"{fork}-{mode}"
        classpath = [classes] + ([out / "overlay"] if mode == "candidate" else []) + [native, buddy]
        command = [jdk / "bin/java", "-Xms256m", "-Xmx256m", "-Xbatch", "-Djava.awt.headless=true",
                   "-Duser.home=" + str(out / "home"), "-Dpz.test.cache=" + str(out / "client1" / tag),
                   "-Dlot.iterations=" + str(args.iterations),
                   "-Xlog:jit+compilation=debug:file=" + str(out / (tag + "-jit.log")),
                   "-cp", os.pathsep.join(map(str, classpath)), "LotLockCheck", mode]
        if measure:
            command.append("--measure")
        log = run(command, work, out / (tag + ".log"))
        current = [line for line in log.splitlines() if line.startswith("VECTOR ")]
        scheduling = ("independent-load-completed" if mode == "candidate" else "class-monitor-blocked")
        if len(current) != 18 or "LOT_LOCK_CHECK_OK" not in log or (
                "SCHEDULING synthetic-block " + scheduling) not in log:
            raise RuntimeError("Incomplete correctness or lock regression: " + tag)
        if vectors is None:
            vectors = current
        if current != vectors:
            raise RuntimeError("Native/candidate output mismatch: " + tag)
        if measure:
            sums = [line for line in log.splitlines() if line.startswith("CONSUMED ")]
            if len(sums) != 6:
                raise RuntimeError("Missing consumed outputs: " + tag)
            if consumed is None:
                consumed = sums
            if sums != consumed:
                raise RuntimeError("Measured output mismatch: " + tag)
            windows = []
            for line in log.splitlines():
                if line.startswith("MEASURE "):
                    _, label, round_, count, elapsed = line.split()
                    rows.append(dict(mode=mode, fork=fork, label=label, round=int(round_),
                                     operations=int(count), wall_ns=int(elapsed)))
                if line.startswith("WINDOW "):
                    _, label, round_, begin, end = line.split()
                    windows.append((int(begin), int(end)))
            if len(windows) != 6 or len([r for r in rows if r['mode'] == mode and r['fork'] == fork]) != 6:
                raise RuntimeError("Incomplete timed rounds: " + tag)
            for line in (out / (tag + "-jit.log")).read_text().splitlines():
                at = re.match(r"\[([0-9.]+)s\]", line)
                if at and any(name in line for name in ("IsoLot::", "BufferedRandomAccessFile::", "ObjectPool::", "LotLockCheck::")):
                    if any(begin <= float(at[1]) * 1000 <= end for begin, end in windows):
                        overlap.append(dict(run=tag, line=line))
        print("PASS " + tag + " vectors=" + str(len(current)), flush=True)

    try:
        for mode in ("stock", "candidate"):
            invoke(mode, "check")
        result.update(status="correctness-passed", vectors=vectors)
        save()
        if args.measure:
            sys.path.insert(0, str(ROOT / "tools"))
            from queue_checks import admission
            selection = {"kind": "sp", "clients": 1, "suite": "lot-lock-headless",
                         "resources": {"heap_mib": 256, "native_mib": 256,
                                       "cpu_per_instance": 2.0, "exclusive": True}}
            runtime = {"roles": {"client1": {"cache": str(out / "client1")}}}
            with admission.acquire(out, selection, runtime, args.resource_wait) as resources:
                (out / "admission.json").write_text(json.dumps(resources, indent=2) + "\n")
                for fork in range(args.forks):
                    for mode in (("stock", "candidate") if fork % 2 == 0 else ("candidate", "stock")):
                        invoke(mode, fork, True)
            paired = []
            for label in ("warm-file-single", "warm-file-two"):
                medians = {mode: [statistics.median(r['wall_ns'] / r['operations'] for r in rows
                               if r['mode'] == mode and r['label'] == label and r['fork'] == fork)
                              for fork in range(args.forks)] for mode in ("stock", "candidate")}
                deltas = [after - before for before, after in zip(medians['stock'], medians['candidate'])]
                paired.append(dict(label=label, ns_per_operation=medians, candidate_minus_stock=deltas,
                                   median_delta=statistics.median(deltas)))
            result.update(status="measured", consumed=consumed, paired=paired,
                          relevant_jit_overlap=overlap, timing_qualified=not overlap)
            if overlap:
                raise RuntimeError("Relevant JIT compilation overlapped timed rounds; results unqualified")
        save()
    except Exception as error:
        result.update(status="blocked-before-timing" if result['status'] == "correctness-passed" and args.measure and not rows else "failed",
                      error=str(error), completed_timed_runs=len(rows) // 6, relevant_jit_overlap=overlap)
        save()
        raise
    print("LOT_LOCK_EXPERIMENT_PASS " + str(out / "result.json"))


if __name__ == "__main__":
    main()
