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
    parser.add_argument("--java", type=Path, required=True, help="Runtime Java binary; use the bundled Zulu runtime for timing")
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
    for name in ("ResolvedCandidate.java", "LootResolvedCheck.java", "run.py"):
        data = (SOURCE / name).read_bytes()
        (sources / name).write_bytes(data)
        fingerprints[name] = sha(data)
    cp = os.pathsep.join(map(str, (native, buddy)))
    run([jdk / "bin/javac", "--release", "25", "-cp", cp, "-d", classes,
         sources / "ResolvedCandidate.java", sources / "LootResolvedCheck.java"], work, out / "compile.log")
    build_cp = os.pathsep.join((str(classes), cp))
    for mode in ("stock", "candidate"):
        patch = run([jdk / "bin/java", "-cp", build_cp, "ResolvedCandidate", native, out / ("overlay-" + mode), mode],
                    work, out / ("splice-" + mode + ".log"))
        if "RESOLVED_SPLICE_READY" not in patch:
            raise RuntimeError("Splice guard check did not finish")
    receipt = {"format": 1, "research_only": True, "native_guards": GUARDS,
               "sources": fingerprints, "game_jar_sha256": sha(native.read_bytes()),
               "buddy_jar_sha256": sha(buddy.read_bytes()),
               "patched_class_sha256": {mode: sha((out / ("overlay-" + mode) / "zombie/inventory/ItemPickerJava.class").read_bytes()) for mode in ("stock", "candidate")},
               "scope": "headless calculation + native no-creation roll paths; not gameplay/SP/Host", "runtime_java_sha256": sha(java.read_bytes()),
               "runtime_selection": "explicit caller-supplied binary; Zulu vendor check does not establish bundled identity",
               "measure": args.measure, "forks": args.forks if args.measure else 1,
               "iterations": args.iterations if args.measure else 0}
    receipt["java_version"] = run([java, "-version"], work, out / "java-version.log").strip()
    if args.measure and "Zulu" not in receipt["java_version"]:
        raise RuntimeError("Timing requires the bundled Zulu runtime")
    (out / "input-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    vectors = None
    consumed = None
    rows = []
    compilation_overlap = []

    def invoke(mode, fork, measure):
        nonlocal vectors, consumed
        tag = f"{fork}-{mode}"
        classpath = [classes, out / ("overlay-" + mode)]
        classpath.extend((native, buddy))
        command = [java, "-Xms256m", "-Xmx256m", "-Xbatch", "-Djava.awt.headless=true",
                   "-Duser.home=" + str(out / "home"), "-Dpz.test.cache=" + str(out / "client1"),
                   "-Dloot.iterations=" + str(args.iterations),
                   "-Xlog:jit+compilation=debug:file=" + str(out / (tag + "-jit.log")),
                   "-cp", os.pathsep.join(map(str, classpath)), "LootResolvedCheck"]
        if measure:
            command.append("--measure")
        log = run(command, work, out / (tag + ".log"))
        actual = [line for line in log.splitlines() if line.startswith("VECTOR ")]
        if len(actual) != 190:
            raise RuntimeError(f"Expected 190 semantic rows, got {len(actual)}: {tag}")
        required = ("VECTOR fulltype-replaced ", "VECTOR existing-empty-original-wins ",
                    "VECTOR live-tag/", "VECTOR precedence-generator-over-medical ",
                    "VECTOR native-doRoll/Base.FluidFixtureEmpty/", "VECTOR native-bagRoll/Base.FluidFixtureEmpty/",
                    "VECTOR exception/null java.lang.NullPointerException")
        if any(not any(line.startswith(prefix) for line in actual) for prefix in required):
            raise RuntimeError("Missing required semantic coverage: " + tag)
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
            gaps = [line.split() for line in log.splitlines() if line.startswith("REPORT_GAP ")]
            if len(gaps) != 1:
                raise RuntimeError("Missing reporting separation receipt: " + tag)
            _, last_end, report_at, waited_ns = gaps[0]
            if int(report_at) - int(last_end) < 10 or int(waited_ns) < 20_000_000:
                raise RuntimeError("Insufficient reporting separation: " + tag)
            windows = []
            for line in log.splitlines():
                if line.startswith("WINDOW "):
                    _, label, round_, began, ended = line.split()
                    windows.append((int(began), int(ended)))
            for line in (out / (tag + "-jit.log")).read_text().splitlines():
                at = re.match(r"\[([0-9.]+)s\]", line)
                # Conservative: retain/reject every logged compilation event, including
                # inlined dependencies, method handles, Java collections and strings.
                # Uptime and JIT timestamps have millisecond boundary uncertainty.
                if at and any(begin - 1 <= float(at[1]) * 1000 <= end + 1 for begin, end in windows):
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
        selection = {"kind": "sp", "clients": 1, "suite": "loot-resolved-headless",
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
                                                    all_compilation_in_measurement=compilation_overlap), indent=2) + "\n")
    if compilation_overlap:
        raise RuntimeError("JIT compilation overlapped timed rounds (+/-1ms boundary); retain result as unqualified")
    print("LOOT_RESOLVED_CHECK_PASS " + str(out / "result.json"))


if __name__ == "__main__":
    main()
