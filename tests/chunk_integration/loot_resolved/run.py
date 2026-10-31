#!/usr/bin/env python3
"""Compare a test-only resolved-lookup splice against the same external native classes and inputs."""
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
GUARDS = {'org/uncommons/maths/random/CellularAutomatonRNG.class': 'c315f1fcc7c59042db5659fc50fedd2e92c2a4f6522b8dd4218d772fc218e455',
 'zombie/SandboxOptions$Basement.class': 'd312d3bb49f11482a69a655e3e22512fbd6f670067748f323dfb7b09dd65b897',
 'zombie/SandboxOptions$BooleanSandboxOption.class': 'd09e1ab42d27595797cccc0d1a9d3b86b08f53dbafc50a14b4e59d31a7d1145f',
 'zombie/SandboxOptions$DoubleSandboxOption.class': 'bacb8b73dd9501831b50079a0754e1a61ab4ced3fd3646d459f04fbf2111ed09',
 'zombie/SandboxOptions$EnumSandboxOption.class': '20c8bd893b8eb93010f2520ff82483548754adb45f42ad16f5141dcd5dbaee7f',
 'zombie/SandboxOptions$IntegerSandboxOption.class': 'b1ef4dc32b9cea045a3c472cbe723193b087fd606f8985d91e365e117be9f598',
 'zombie/SandboxOptions$Map.class': '1547ee6ced1383e5ff562f54f0be44b6dfe8500411ab2e566a64db643a907a29',
 'zombie/SandboxOptions$MultiplierConfig.class': '38c9db269342527afae3308371f1469fa7e0b498029c36fdab92e0ee00f56f6a',
 'zombie/SandboxOptions$SandboxOption.class': '93ee3b805b73af388e583939d34956d86c8dbdbc2e3ec230a4d359312ce5e1d9',
 'zombie/SandboxOptions$StringSandboxOption.class': 'c727872fc06f21c78f6fd93fc803de6d51e2daabde1e2cc4a85112495f15b6ea',
 'zombie/SandboxOptions$StrongEnumSandboxOption.class': '39324aa9b96697739b6f94ea16dd63217f70bf4a416935d17c63d7a6046b79aa',
 'zombie/SandboxOptions$ZombieConfig.class': 'd1e8ebf85cc6e596dc8c3b68355a627baef2e8ccf403f57b858b0c82983405a6',
 'zombie/SandboxOptions$ZombieLore.class': 'c7b7f8d6622456092805943d768c4b98072b8e9bd1c73228d7b2cfdf314357a4',
 'zombie/SandboxOptions.class': 'd90458506ab559c7d9b84588a1a62a78ceb7b4c6303bb2127d823fc21c4e7297',
 'zombie/config/ArrayConfigOption.class': 'b9e0e212dc4852386d96ff5a86788d06dfd3dd244866d310fa57cbd8fe48282f',
 'zombie/config/BooleanConfigOption.class': 'ffa95151e835f60d98ca7ac65bf8e1daf6f7ab5f4c57d7f08554487ae94fb63e',
 'zombie/config/ConfigFile.class': '8e5969b15302f93bb12609d45bc97b50407c41d4693873c3be43deb73c706e75',
 'zombie/config/ConfigOption$ConfigOptionOnChangeCallback.class': 'd5a38b47b76d88901a7b7967af10ba42a664d3300d85c473bd4523e05a3233db',
 'zombie/config/ConfigOption.class': 'f99932d56c4ce393b21ccb43c2466e23461874df7ccb5f0057f817c7f9bf1b37',
 'zombie/config/DoubleConfigOption.class': 'e2295f43e999a424dec387b35b24b5960b72ceeda3df01f809557a33161452bc',
 'zombie/config/EnumConfigOption.class': '9e073bc8b60cdda0a7802a1abb4759cceb76ceed2c2971166183d77cd8e8686b',
 'zombie/config/IntegerConfigOption.class': '6a4c25274e98d0a8bd43079e662d14880f180b7df214c263c71671234f8fd4e9',
 'zombie/config/StringConfigOption.class': 'b41f433d63103cfd8067cfce8eed9886014e5f06781e341ffde35f1a76236d00',
 'zombie/core/random/PZSeedGenerator.class': '7049629e799a7bfe57f3883c83b3b7b7bff12260107d1ef32db524acebdcdeb0',
 'zombie/core/random/Rand.class': '2f73b6bdfa0d8211de585db15974be2a31d341cd53ff64bdbd3271a90b727326',
 'zombie/core/random/RandAbstract.class': 'f8b8a08585a17b8a9b0ba96dbb6434c904ff84233465c8647cf5e670aaf06a3b',
 'zombie/core/random/RandInterface.class': 'd511151dd7aee4fcbf4469898f4cb02f4edbcd47465a8637dd53bc7f915a7bd3',
 'zombie/core/random/RandLocation.class': '403e0d21983981d7a61567b2a4b714e0569762b8d784894a258a4c481c0d7006',
 'zombie/core/random/RandLua.class': 'bc1b5606bf6a4a21007931dc1adc8eda96f5c92d81a14322ceb0eb16dfd74a4d',
 'zombie/core/random/RandSeeded.class': '87acc846ad48044d93d063f9ae8bfe33db210ea57db3f779d5b2849982c72790',
 'zombie/core/random/RandStandard.class': '9d270d2578a0d3a8f4298cb16d4c0600d51e35ed2fb375f0dc716d16090b2422',
 'zombie/entity/ComponentType.class': '28f3d346c47a0b1804c7258659587c0f415eef3d510d6cd67c50d2ff291ebcda',
 'zombie/inventory/ItemPickerJava.class': '5c8cf626e46a52cdbd9d73e9de10766dece3388ee3e4f4d8d071df5e44d68522',
 'zombie/scripting/ScriptBucket.class': 'dc7a234f0d1fb162ef6b6ce316f16d13d87a52a93d863016abc7a7b9ba41d4dc',
 'zombie/scripting/ScriptBucketCollection.class': '61ba45ea197992413af259c3736820d1669a5678f577f661956d0c3e8fbf9781',
 'zombie/scripting/ScriptManager.class': '8aee81a03fb7c09a9e9844ba9388a943aef9b313ea00017b8f2a33f16f4f0f99',
 'zombie/scripting/entity/GameEntityScript.class': '2863b3af3a0dcef1163268da1469aaba2104a90c2def4f625811e8364cecab29',
 'zombie/scripting/objects/Item.class': '9e6a2f7fe48cc66843fea06b4821063d7cc6a73eaba0de8ee51d0a15c373202e',
 'zombie/scripting/objects/ItemDisplayCategory.class': '592ec2004db2c8c5f2504b804b096777d53f22bfc73e7ffbae8ccc426fd0cda4',
 'zombie/scripting/objects/ItemTag.class': '616d4da81f7ea23f6a4cfafb27a240e21d26f5670506c11372cd56636007c825',
 'zombie/scripting/objects/ItemType.class': 'fbdb595b740af50cb6f157cd162bfac19b682c742c5442f7089826329fe2ef31',
 'zombie/scripting/objects/ScriptModule.class': '10606317c7d84eb1b5c0df06a27687803aaefbc13e7d7148e99c6d9074442856'}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def run(args, cwd, log):
    try:
        result = subprocess.run(list(map(str, args)), cwd=cwd, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
    except subprocess.TimeoutExpired as error:
        partial = error.stdout or ""
        if isinstance(partial, bytes):
            partial = partial.decode(errors="replace")
        log.write_text(partial)
        log.with_name(log.name + ".timeout.json").write_text(json.dumps(
            {"status": "timeout", "timeout_seconds": 180, "partial_stdout_bytes": len(partial.encode()),
             "log": log.name}, indent=2) + "\n")
        raise RuntimeError(f"Command timed out; retained partial stdout and metadata: {log}") from error
    log.write_text(result.stdout)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}); see {log}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("game", "jdk", "output"):
        parser.add_argument("--" + key, type=Path, required=True)
    parser.add_argument("--java", type=Path, required=True, help="Explicit bundled Zulu25 Java binary")
    parser.add_argument("--measure", action="store_true", help="Reserve the exclusive test slot before timing")
    parser.add_argument("--forks", type=int, default=5, help="Independent JVMs, each containing BOTH modes")
    parser.add_argument("--pairs", type=int, default=12, help="Even AB/BA pair count per group inside each JVM")
    parser.add_argument("--iterations", type=int, default=200000)
    parser.add_argument("--resource-wait", type=int, default=900)
    args = parser.parse_args()
    if args.forks < 1 or args.pairs < 2 or args.pairs % 2 or args.iterations < 1 or args.resource_wait < 0:
        parser.error("positive forks/iterations, even pairs >=2, nonnegative resource-wait required")
    if any(os.environ.get(key) for key in ("JAVA_TOOL_OPTIONS", "JDK_JAVA_OPTIONS", "_JAVA_OPTIONS")):
        parser.error("Unset injected JVM option variables so the receipt contains every JVM flag")
    game, jdk, out = (getattr(args, key).resolve() for key in ("game", "jdk", "output"))
    if out.exists() or out == game or game in out.parents:
        parser.error("Output must be a new directory outside the game installation")
    java = args.java.resolve()
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
    for name in ("ResolvedCandidate.java", "LootResolvedCheck.java", "run.py", "README.md"):
        data = (SOURCE / name).read_bytes()
        (sources / name).write_bytes(data)
        fingerprints[name] = sha(data)
    cp = os.pathsep.join(map(str, (native, buddy)))
    # Build the overlay first so javac can bind DIRECT static bridge calls. No timed MH dispatch.
    run([jdk / "bin/javac", "--release", "25", "-cp", cp, "-d", classes,
         sources / "ResolvedCandidate.java"], work, out / "compile-builder.log")
    build_cp = os.pathsep.join((str(classes), cp))
    for mode in ("stock", "candidate"):
        patch = run([jdk / "bin/java", "-cp", build_cp, "ResolvedCandidate", native, out / ("overlay-" + mode), mode],
                    work, out / ("splice-" + mode + ".log"))
        if "RESOLVED_SPLICE_READY" not in patch:
            raise RuntimeError("Splice guard check did not finish")
    compile_cp = os.pathsep.join(map(str, (out / "overlay-candidate", native, buddy)))
    run([jdk / "bin/javac", "--release", "25", "-cp", compile_cp, "-d", classes,
         sources / "LootResolvedCheck.java"], work, out / "compile-harness.log")
    bytecode = run([jdk / "bin/javap", "-c", "-p", "-l", "-cp", str(classes), "LootResolvedCheck"],
                   work, out / "harness-bytecode.txt")
    loop = bytecode.split("private static long pairedLoop(", 1)[1].split("private static void separateReporting(", 1)[0]
    for name in ("pztest$iterationNative", "pztest$iterationResolved"):
        direct = [line for line in loop.splitlines() if "invokestatic" in line and name + ":" in line]
        if len(direct) != 1:
            raise RuntimeError("Expected one direct static bridge call in symmetric pairedLoop: " + name)
    if "MethodHandle" in bytecode or "invokeExact" in bytecode:
        raise RuntimeError("MethodHandle dispatch must not be present in the paired harness")
    run([jdk / "bin/javap", "-c", "-p", "-l", "-cp", str(out / "overlay-candidate"),
         "zombie.inventory.ItemPickerJava"], work, out / "candidate-bytecode.txt")
    common_flags = ["-Xms256m", "-Xmx256m", "-XX:+UseZGC", "-Xbatch", "-Djava.awt.headless=true",
                    "-Duser.home=" + str(out / "home"), "-Dpz.test.cache=" + str(out / "client1"),
                    "-Dloot.iterations=" + str(args.iterations), "-Dloot.pairs=" + str(args.pairs)]
    receipt = {"format": 2, "research_only": True, "native_guards": GUARDS, "sources": fingerprints,
               "game_jar_sha256": sha(native.read_bytes()), "buddy_jar_sha256": sha(buddy.read_bytes()),
               "overlay_sha256": {mode: sha((out / ("overlay-" + mode) / "zombie/inventory/ItemPickerJava.class").read_bytes())
                                  for mode in ("stock", "candidate")},
               "harness_class_sha256": sha((classes / "LootResolvedCheck.class").read_bytes()),
               "runtime_java_sha256": sha(java.read_bytes()),
               "runtime_selection": "explicit binary; Zulu vendor check alone does not establish bundled identity",
               "common_jvm_flags": common_flags, "jvm_invocations": {},
               "scope": "synthetic first resolution + one Rand draw + chance; no creation/gameplay/SP/Host",
               "design": "both direct bridges in candidate overlay; within each JVM alternating AB/BA pairs",
               "warmup_seed_policy": "short timer-wrapper warmup continues RNG; long warmup and measured halves reset native CA seed",
               "input_weighting": "synthetic equal predicate coverage, not observed gameplay frequencies",
               "gc_policy": "ZGC; allocation and GC retained as workload; no FPS extrapolation",
               "measure": args.measure, "forks": args.forks if args.measure else 0,
               "pairs_per_group_per_jvm": args.pairs if args.measure else 0,
               "iterations_per_half": args.iterations if args.measure else 0}
    receipt["java_version"] = run([java, "-version"], work, out / "java-version.log").strip()
    if args.measure and "Zulu" not in receipt["java_version"]:
        raise RuntimeError("Timing requires caller-supplied bundled Zulu runtime")
    vectors = inputs = groups = None
    rows, windows, overlaps, log_receipts = [], [], [], {}

    def invoke(tag, overlay, measure=False, fork=0):
        nonlocal vectors, inputs, groups
        classpath = os.pathsep.join(map(str, (classes, out / ("overlay-" + overlay), native, buddy)))
        flags = common_flags + ["-Dloot.fork=" + str(fork),
            "-Xlog:jit+compilation=debug:file=" + str(out / (tag + "-jit.log")),
            "-Xlog:gc*,safepoint:file=" + str(out / (tag + "-gc-safepoint.log")) + ":uptime,level,tags"]
        main_args = ["--measure"] if measure else []
        receipt["jvm_invocations"][tag] = {"jvm_flags": flags, "classpath": classpath,
                                           "main_class": "LootResolvedCheck", "main_arguments": main_args}
        (out / "input-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        log = run([java, *flags, "-cp", classpath, "LootResolvedCheck", *main_args], work, out / (tag + ".log"))
        actual = [line for line in log.splitlines() if line.startswith("VECTOR ")]
        if len(actual) != 190:
            raise RuntimeError(f"Expected 190 semantic rows, got {len(actual)}: {tag}")
        required = ("VECTOR fulltype-replaced ", "VECTOR existing-empty-original-wins ", "VECTOR live-tag/",
                    "VECTOR precedence-generator-over-medical ", "VECTOR native-doRoll/Base.FluidFixtureEmpty/",
                    "VECTOR native-bagRoll/Base.FluidFixtureEmpty/", "VECTOR exception/null java.lang.NullPointerException")
        if any(not any(line.startswith(prefix) for line in actual) for prefix in required):
            raise RuntimeError("Missing required semantic coverage: " + tag)
        actual_groups = [line for line in log.splitlines() if line.startswith("GROUP ")]
        actual_inputs = [line for line in log.splitlines() if line.startswith("INPUT ")]
        if len(actual_groups) != 5 or len(actual_inputs) != 257:
            raise RuntimeError("Missing varied paired inputs: " + tag)
        if vectors is None:
            vectors, groups, inputs = actual, actual_groups, actual_inputs
        if (vectors, groups, inputs) != (actual, actual_groups, actual_inputs):
            raise RuntimeError("Native/candidate or same-JVM varied semantic/RNG mismatch: " + tag)
        gc_text = (out / (tag + "-gc-safepoint.log")).read_text()
        if "Initializing The Z Garbage Collector" not in gc_text:
            raise RuntimeError("ZGC initialization missing: " + tag)
        for suffix in (".log", "-jit.log", "-gc-safepoint.log"):
            file = out / (tag + suffix)
            log_receipts[file.name] = sha(file.read_bytes())
        if measure:
            local_windows, local_rows = [], []
            for line in log.splitlines():
                if line.startswith("WINDOW "):
                    _, label, pair, order, mode, begin, end = line.split()
                    local_windows.append(dict(run=tag, fork=fork, label=label, pair=int(pair), order=order,
                                              mode=mode, begin_ms=int(begin), end_ms=int(end)))
                elif line.startswith("PAIR "):
                    _, label, pair, order, mode, count, wall, cpu, allocation, checksum, rng = line.split()
                    local_rows.append(dict(run=tag, fork=fork, label=label, pair=int(pair), order=order, mode=mode,
                                           iterations=int(count), wall_ns=int(wall), cpu_ns=int(cpu),
                                           allocated_bytes=int(allocation), checksum=int(checksum), next_rng=int(rng)))
            expected = 5 * args.pairs * 2
            if len(local_rows) != expected or len(local_windows) != expected:
                raise RuntimeError("Incomplete same-JVM pair rows/windows: " + tag)
            for label in sorted({row['label'] for row in local_rows}):
                for pair in range(args.pairs):
                    half = [row for row in local_rows if row['label'] == label and row['pair'] == pair]
                    if len(half) != 2 or {row['mode'] for row in half} != {"native", "candidate"}:
                        raise RuntimeError("Incomplete pair: " + tag)
                    if len({(row['order'], row['iterations'], row['checksum'], row['next_rng']) for row in half}) != 1:
                        raise RuntimeError("Paired count/checksum/RNG mismatch: " + tag)
                orders = [row['order'] for row in local_rows if row['label'] == label and row['mode'] == 'native']
                if orders.count('AB') != args.pairs // 2 or orders.count('BA') != args.pairs // 2:
                    raise RuntimeError("Unbalanced AB/BA order: " + tag)
            gaps = [line.split() for line in log.splitlines() if line.startswith("REPORT_GAP ")]
            if len(gaps) != 1:
                raise RuntimeError("Missing reporting separation: " + tag)
            _, last_end, report_at, waited = gaps[0]
            if int(last_end) != max(w['end_ms'] for w in local_windows):
                raise RuntimeError("Reporting separation does not match final window: " + tag)
            if int(report_at) - int(last_end) < 10 or int(waited) < 20_000_000:
                raise RuntimeError("Insufficient reporting separation: " + tag)
            # Preserve EVERY compilation event, with the same conservative +/-1ms margin.
            for line in (out / (tag + "-jit.log")).read_text().splitlines():
                at = re.match(r"\[([0-9.]+)s\]", line)
                if at:
                    hit = [w for w in local_windows if w['begin_ms'] - 1 <= float(at[1]) * 1000 <= w['end_ms'] + 1]
                    if hit:
                        overlaps.append(dict(run=tag, line=line, windows=hit))
            rows.extend(local_rows)
            windows.extend(local_windows)
        print(f"PASS {tag} vectors={len(actual)} varied_inputs={len(actual_inputs)}", flush=True)

    for mode in ("stock", "candidate"):
        invoke("check-" + mode, mode)
    context = nullcontext(None)
    if args.measure:
        sys.path.insert(0, str(ROOT / "tools"))
        from queue_checks import admission
        selection = {"kind": "sp", "clients": 1, "suite": "loot-resolved-paired-headless",
                     "resources": {"heap_mib": 256, "native_mib": 256, "cpu_per_instance": 1.0, "exclusive": True}}
        runtime = {"roles": {"client1": {"cache": str(out / "client1")}}}
        context = admission.acquire(out, selection, runtime, args.resource_wait)
    with context as resource_receipt:
        if args.measure:
            (out / "admission.json").write_text(json.dumps(resource_receipt, indent=2) + "\n")
            for fork in range(args.forks):
                invoke(f"{fork}-paired", "candidate", True, fork)
    metrics = ("wall_ns", "cpu_ns", "allocated_bytes")
    paired, summary = [], []
    for label in sorted({row['label'] for row in rows}):
        selected = [row for row in rows if row['label'] == label]
        for fork in range(args.forks):
            for pair in range(args.pairs):
                halves = {row['mode']: row for row in selected if row['fork'] == fork and row['pair'] == pair}
                if set(halves) != {"native", "candidate"}:
                    raise RuntimeError("Missing paired result")
                native_row, candidate_row = halves['native'], halves['candidate']
                delta = {key: candidate_row[key] / candidate_row['iterations'] - native_row[key] / native_row['iterations']
                         for key in metrics}
                paired.append(dict(label=label, fork=fork, pair=pair, order=native_row['order'],
                                   candidate_minus_native_per_iteration=delta))
        deltas = [row for row in paired if row['label'] == label]
        fork_rows = []
        for fork in range(args.forks):
            subset = [row for row in deltas if row['fork'] == fork]
            fork_rows.append(dict(fork=fork, median_delta={key: statistics.median(
                row['candidate_minus_native_per_iteration'][key] for row in subset) for key in metrics}))
        modes = {mode: {key: statistics.median(row[key] / row['iterations'] for row in selected if row['mode'] == mode)
                        for key in metrics} for mode in ('native', 'candidate')}
        summary.append(dict(label=label, modes=modes, fork_medians=fork_rows,
                            median_fork_delta={key: statistics.median(f['median_delta'][key] for f in fork_rows) for key in metrics},
                            order_median_delta={order: {key: statistics.median(row['candidate_minus_native_per_iteration'][key]
                                for row in deltas if row['order'] == order) for key in metrics} for order in ('AB', 'BA')},
                            negative_pair_counts={key: sum(row['candidate_minus_native_per_iteration'][key] < 0 for row in deltas)
                                                  for key in metrics}, pair_count=len(deltas)))
    result = dict(receipt=receipt, vectors=vectors, groups=groups, inputs=inputs, measurements=rows,
                  windows=windows, paired=paired, summary=summary, log_sha256=log_receipts,
                  all_compilation_in_measurement=overlaps,
                  qualification=("semantics-only" if not args.measure else
                                 "unqualified-jit-overlap" if overlaps else "synthetic-paired-unit-only"))
    (out / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    if overlaps:
        raise RuntimeError("All-JIT gate rejected timed windows (+/-1ms); retain unqualified result")
    print("LOOT_RESOLVED_CHECK_PASS " + str(out / "result.json"))


if __name__ == "__main__":
    main()
