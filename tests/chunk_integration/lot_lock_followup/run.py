#!/usr/bin/env python3
"""Bounded follow-up to the original IsoLot single-reader wall-time outlier."""
import argparse
import hashlib
import importlib.util
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
ORIGINAL = SOURCE.parent / "lot_lock"
spec = importlib.util.spec_from_file_location("preserved_lot_lock", ORIGINAL / "run.py")
original_runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(original_runner)
sha = lambda data: hashlib.sha256(data).hexdigest()


def run(command, cwd, log, timeout=180):
    log.with_suffix(".command.json").write_text(json.dumps(list(map(str, command)), indent=2) + "\n")
    try:
        result = subprocess.run(list(map(str, command)), cwd=cwd, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        output = error.stdout or b""
        log.write_text(output.decode(errors="replace") if isinstance(output, bytes) else output)
        raise RuntimeError("Bounded subprocess timed out; retained " + str(log)) from error
    log.write_text(result.stdout)
    if result.returncode:
        raise RuntimeError(f"Process exited {result.returncode}; retained {log}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("game", "jdk", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--measure", action="store_true", help="Acquire exclusive admission and run; default only prepares")
    parser.add_argument("--forks", type=int, default=5)
    parser.add_argument("--iterations", type=int, default=100000)
    parser.add_argument("--rounds", type=int, default=5)
    parser.add_argument("--warmup", type=int, default=20)
    parser.add_argument("--resource-wait", type=int, default=60)
    args = parser.parse_args()
    if not (1 <= args.forks <= 10 and 1 <= args.iterations <= 1000000
            and 1 <= args.rounds <= 20 and 1 <= args.warmup <= 30 and 0 <= args.resource_wait <= 900):
        parser.error("Bounded parameters exceeded")
    game, jdk, out = (getattr(args, name).resolve() for name in ("game", "jdk", "output"))
    if out.exists() or out == game or game in out.parents:
        parser.error("Output must be new and outside installed game")
    native, buddy = game / "projectzomboid.jar", game / "ZombieBuddy.jar"
    for path in (native, buddy, jdk / "bin/java", jdk / "bin/javac"):
        if not path.is_file():
            parser.error("Missing explicit input: " + str(path))
    with zipfile.ZipFile(native) as archive:
        for name, digest in original_runner.GUARDS.items():
            if sha(archive.read(name)) != digest:
                parser.error("Native guard mismatch: " + name)
        native_lot = archive.read("zombie/iso/IsoLot.class")
    out.mkdir(parents=True)
    for name in ("classes", "source", "work", "home", "client1"):
        (out / name).mkdir()
    result = dict(format=1, status="preparing", diagnostic_only=True, timing_qualified=False,
                  parameters={key: value for key, value in vars(args).items() if key not in ("game", "jdk", "output")},
                  measurements=[], workers=[], relevant_jit_overlap=[])

    def save():
        (out / "result.json").write_text(json.dumps(result, indent=2) + "\n")

    try:
        sources = {}
        for parent, names in ((ORIGINAL, ("LotLockCandidate.java", "LotLockCheck.java")),
                              (SOURCE, ("LotIoCounters.java", "LotLockFollowup.java", "run.py"))):
            for name in names:
                data = (parent / name).read_bytes()
                (out / "source" / name).write_bytes(data)
                sources[name] = sha(data)
        cp = os.pathsep.join(map(str, (native, buddy)))
        classes, work = out / "classes", out / "work"
        run([jdk / "bin/javac", "--release", "25", "-cp", cp, "-d", classes,
             *sorted((out / "source").glob("*.java"))], work, out / "compile.log")
        basic = [jdk / "bin/java", "-cp", os.pathsep.join((str(classes), cp))]
        run([*basic, "LotLockCandidate", native, out / "candidate"], work, out / "candidate.log")
        run([*basic, "LotIoCounters", native, out / "telemetry"], work, out / "telemetry.log")
        candidate = (out / "candidate/zombie/iso/IsoLot.class").read_bytes()
        changes = [i for i, pair in enumerate(zip(native_lot, candidate)) if pair[0] != pair[1]]
        if len(candidate) != len(native_lot) or len(changes) != 2 or any(
                native_lot[i] & 0x20 == 0 or candidate[i] != native_lot[i] & ~0x20 for i in changes):
            raise RuntimeError("Candidate exceeds original two cleared synchronized bits")
        receipt = dict(sources=sources, native_guards=original_runner.GUARDS,
                       game_jar_sha256=sha(native.read_bytes()), buddy_jar_sha256=sha(buddy.read_bytes()),
                       candidate_sha256=sha(candidate), changed_byte_offsets=changes,
                       telemetry_sha256=sha((out / "telemetry/zombie/util/BufferedRandomAccessFile.class").read_bytes()),
                       java_version=run([jdk / "bin/java", "-version"], work, out / "java-version.log").strip())
        (out / "input-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        result.update(status="prepared", receipt=receipt)
        save()
        if not args.measure:
            print("LOT_LOCK_FOLLOWUP_PREPARED " + str(out / "result.json"))
            return
        sys.path.insert(0, str(ROOT / "tools"))
        from queue_checks import admission
        selection = {"kind": "sp", "clients": 1, "suite": "lot-lock-followup",
                     "resources": {"heap_mib": 256, "native_mib": 256,
                                   "cpu_per_instance": 2.0, "exclusive": True}}
        runtime = {"roles": {"client1": {"cache": str(out / "client1")}}}
        fixtures = None
        with admission.acquire(out, selection, runtime, args.resource_wait) as admitted:
            (out / "admission.json").write_text(json.dumps(admitted, indent=2) + "\n")
            result["status"] = "measuring"
            save()
            for fork in range(args.forks):
                for mode in (("stock", "candidate") if fork % 2 == 0 else ("candidate", "stock")):
                    tag = f"{fork}-{mode}"
                    classpath = [classes, out / "telemetry"] + ([out / "candidate"] if mode == "candidate" else []) + [native, buddy]
                    command = [jdk / "bin/java", "-Xms256m", "-Xmx256m", "-Xbatch", "-Djava.awt.headless=true",
                               "-Duser.home=" + str(out / "home"), "-Dpz.test.cache=" + str(out / "client1" / tag),
                               "-Dlot.iterations=" + str(args.iterations), "-Dlot.rounds=" + str(args.rounds),
                               "-Dlot.warmup=" + str(args.warmup),
                               "-Xlog:jit+compilation=debug:file=" + str(out / (tag + "-jit.log")),
                               "-Xlog:gc,safepoint:file=" + str(out / (tag + "-gc-safepoint.log")),
                               "-cp", os.pathsep.join(map(str, classpath)), "LotLockFollowup", mode]
                    log = run(command, work, out / (tag + ".log"))
                    if "LOT_LOCK_FOLLOWUP_OK" not in log:
                        raise RuntimeError("Missing completion: " + tag)
                    current = [line for line in log.splitlines() if line.startswith("FIXTURE ")]
                    if len(current) != 3 or fixtures is not None and current != fixtures:
                        raise RuntimeError("Fixture outputs differ: " + tag)
                    fixtures = current
                    windows, count = [], 0
                    for line in log.splitlines():
                        parts = line.split()
                        if line.startswith("ROW "):
                            names = ("round", "operations", "wall_ns", "cpu_ns", "allocated_bytes", "opens", "refills", "read_bytes", "eof", "checksum")
                            row = dict(mode=parts[1], label=parts[2], fork=fork,
                                       **dict(zip(names, map(int, parts[3:]), strict=True)))
                            if row["mode"] != mode:
                                raise RuntimeError("Wrong mode in row")
                            result["measurements"].append(row)
                            count += 1
                        elif line.startswith("WORKER "):
                            names = ("round", "worker", "wall_ns", "cpu_ns", "allocated_bytes", "opens", "refills", "read_bytes", "eof", "checksum")
                            result["workers"].append(dict(mode=mode, fork=fork, label=parts[1],
                                **dict(zip(names, map(int, parts[2:]), strict=True))))
                        elif line.startswith("WINDOW "):
                            windows.append((parts[1], int(parts[2]), int(parts[3]), int(parts[4])))
                    if count != args.rounds * 3 or len(windows) != count:
                        raise RuntimeError("Incomplete retained rows: " + tag)
                    for line in (out / (tag + "-jit.log")).read_text().splitlines():
                        at = re.match(r"\[([0-9.]+)s\]", line)
                        if at and any(name in line for name in ("IsoLot::", "BufferedRandomAccessFile::", "ObjectPool::", "LotLockFollowup::", "LotIoCounters::")):
                            for label, round_, begin, end in windows:
                                if begin <= float(at[1]) * 1000 <= end:
                                    result["relevant_jit_overlap"].append(dict(run=tag, label=label, round=round_, line=line))
                    save()
                    print("RETAINED " + tag, flush=True)
        rows = result["measurements"]
        paired = []
        for label in ("fixed-single", "mixed-single", "mixed-two"):
            for metric in ("wall_ns", "cpu_ns", "allocated_bytes", "opens", "refills", "read_bytes"):
                medians = {mode: [statistics.median(row[metric] / row["operations"] for row in rows
                           if row["mode"] == mode and row["fork"] == fork and row["label"] == label)
                          for fork in range(args.forks)] for mode in ("stock", "candidate")}
                paired.append(dict(label=label, metric_per_operation=metric, medians=medians,
                    percent_deltas=[100 * (b / a - 1) if a else None for a, b in zip(medians["stock"], medians["candidate"]) ]))
        fixed_io = {(row["opens"], row["refills"], row["read_bytes"], row["eof"])
                    for row in rows if row["label"] == "fixed-single"}
        outputs = {label: {row["checksum"] for row in rows if row["label"] == label}
                   for label in ("fixed-single", "mixed-single", "mixed-two")}
        qualified = not result["relevant_jit_overlap"] and len(fixed_io) == 1 and all(len(sums) == 1 for sums in outputs.values())
        result.update(status="measured", timing_qualified=qualified, paired=paired,
                      fixed_io_equivalent=len(fixed_io) == 1, fixture_vectors=fixtures,
                      output_checksums={key: sorted(value) for key, value in outputs.items()})
        save()
        print("LOT_LOCK_FOLLOWUP_RETAINED qualified=" + str(qualified) + " " + str(out / "result.json"))
        if not qualified:
            raise RuntimeError("Diagnostic qualification failed; every row remains retained")
    except Exception as error:
        result.update(status="blocked-before-timing" if result["status"] == "prepared" and args.measure else "failed",
                      error=str(error))
        save()
        raise


if __name__ == "__main__":
    main()
