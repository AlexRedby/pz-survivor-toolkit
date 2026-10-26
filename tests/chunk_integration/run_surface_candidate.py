#!/usr/bin/env python3
"""Qualify one official propertySurfaceNoAlloc flag using external pinned runtime inputs."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import statistics
import subprocess
import tempfile
import zipfile

RELEASE_SHA256 = "2bcd0e01a3ac66856fae137ff1dbda66c8397375da781e7a6ed67fe2b9d6590d"
SELECTED_HASHES_SHA256 = "f1a338611ecccc7c7224e8e19d7a8344fbd53d983a4a11ca77f7e63b90dff7c7"
PROFILE_PROPERTIES_SHA256 = "bffa49378a70d23afcef451d8b8e13b5a27a3fd691697adf782c4e1af84bf1c5"
MANIFEST_SHA256 = "ba1bb752ad3577bcc014ba6d43901f80395db1364d6afcae92ec7d41f2b1544c"


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, required=True, help="Directory containing projectzomboid.jar")
    parser.add_argument("--jdk", type=Path, required=True)
    parser.add_argument("--release", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--forks", type=int, default=3)
    parser.add_argument("--batch-compilation", action="store_true", help="Synchronize compilation to check warmed tiered behavior")
    parser.add_argument("--correctness-only", action="store_true", help="Run false/true/native vectors once, without warmup or measurements")
    args = parser.parse_args()
    if args.correctness_only and args.batch_compilation:
        parser.error("--correctness-only and --batch-compilation are separate workflows")
    for name in ("game", "jdk", "release", "manifest", "output"):
        setattr(args, name, getattr(args, name).resolve())
    manifest = json.loads(args.manifest.read_text())
    if digest(manifest) != MANIFEST_SHA256:
        raise SystemExit("Pinned complete manifest mismatch")
    release_hash = hashlib.sha256(args.release.read_bytes()).hexdigest()
    if release_hash != RELEASE_SHA256 or release_hash != manifest["release_sha256"]:
        raise SystemExit("Official release digest mismatch")
    if digest(manifest["selected_files"]) != SELECTED_HASHES_SHA256:
        raise SystemExit("Pinned selected resource map mismatch")
    if digest(manifest["profile"]["properties"]) != PROFILE_PROPERTIES_SHA256:
        raise SystemExit("Pinned baseline profile properties mismatch")
    source = Path(__file__).with_name("SurfaceCandidateCheck.java")
    source_bytes = source.read_bytes()
    if args.forks < 1:
        raise SystemExit("At least one fork is required")
    with zipfile.ZipFile(args.game / "projectzomboid.jar") as native, zipfile.ZipFile(args.release) as release:
        for name, expected in manifest["native_guards"].items():
            if hashlib.sha256(native.read(name)).hexdigest() != expected:
                raise SystemExit("Native guard mismatch: " + name)
        for name, expected in manifest["lifecycle_guards"].items():
            resolved = release if name in manifest["selected_files"] else native
            if hashlib.sha256(resolved.read(name)).hexdigest() != expected:
                raise SystemExit("Resolved lifecycle guard mismatch: " + name)
        if any(name in native.namelist() for name in manifest["native_absences"]):
            raise SystemExit("A pinned absent native entry is now present")
    args.output.mkdir(parents=True, exist_ok=True)
    java = args.jdk / "bin/java"
    javac = args.jdk / "bin/javac"
    rows = []
    with tempfile.TemporaryDirectory(prefix="pz-surface-check-") as temp:
        root = Path(temp)
        overlay = root / "overlay"
        overlay.mkdir()
        with zipfile.ZipFile(args.release) as archive:
            for name, expected in manifest["selected_files"].items():
                path = PurePosixPath(name)
                if path.is_absolute() or ".." in path.parts or "\\" in name or ":" in name:
                    raise SystemExit("Unsafe selected resource path")
                data = archive.read(name)
                if hashlib.sha256(data).hexdigest() != expected:
                    raise SystemExit("Selected resource digest mismatch: " + name)
                target = overlay / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
        props = manifest["profile"]["properties"]
        (root / "pzopt.properties").write_text("".join(f"{k}={v}\n" for k, v in sorted(props.items())))
        native_cp = str(args.game.resolve() / "projectzomboid.jar")
        compiled = root / "compiled"
        compiled.mkdir()
        snapshot = root / source.name
        snapshot.write_bytes(source_bytes)
        subprocess.run([str(javac), "-cp", native_cp, "-d", str(compiled), str(snapshot)], check=True)
        common_vectors = None
        official_vectors = None
        modes = (("correctness", []),) if args.correctness_only else (("tiered", []), ("c1", ["-XX:TieredStopAtLevel=1"]))
        for mode, flags in modes:
            for fork in range(1 if args.correctness_only else args.forks):
                for candidate in ((False, True) if fork % 2 == 0 else (True, False)):
                    tag = f"{mode}-{fork}-{str(candidate).lower()}"
                    cp = os.pathsep.join((str(compiled), str(overlay), native_cp))
                    command = [str(java), "-Xms256m", "-Xmx256m", *flags,
                               *(["-Xbatch"] if args.batch_compilation else []),
                               "-Xlog:jit+compilation=debug:file=" + str(args.output / (tag + "-jit.log")),
                               f"-Dpzopt.propertySurfaceNoAlloc={str(candidate).lower()}",
                               "-Duser.home=" + str(root / "home"), "-cp", cp, "SurfaceCandidateCheck", "false"]
                    if args.correctness_only:
                        command.append("--correctness-only")
                    result = subprocess.run(command, cwd=root, text=True, capture_output=True)
                    (args.output / (tag + ".log")).write_text(result.stdout + result.stderr)
                    if result.returncode:
                        raise SystemExit(f"JVM failed ({tag}); see output log")
                    vectors = [line for line in result.stdout.splitlines() if line.startswith("VECTOR ")]
                    if official_vectors is None:
                        official_vectors = vectors
                        common_vectors = [line for line in vectors if not line.startswith(("VECTOR invalid-", "VECTOR hole-"))]
                    if vectors != official_vectors:
                        raise SystemExit("False/true correctness transcript mismatch")
                    for line in result.stdout.splitlines():
                        if line.startswith("MEASURE "):
                            _, kind, access, round_, ns, allocated = line.split()
                            rows.append(dict(mode=mode, fork=fork, candidate=candidate, kind=kind, access=access,
                                             round=int(round_), ns=float(ns), allocated=float(allocated)))
                    if args.correctness_only and rows:
                        raise SystemExit("Correctness-only run unexpectedly produced measurements")
        # Native baseline validates normal values and public mutation/cache outcomes independently.
        cp = os.pathsep.join((str(compiled), native_cp))
        result = subprocess.run([str(java), "-Duser.home=" + str(root / "home"), "-cp", cp,
                                 "SurfaceCandidateCheck", "true"], cwd=root, text=True, capture_output=True)
        (args.output / "native.log").write_text(result.stdout + result.stderr)
        native_vectors = [line for line in result.stdout.splitlines() if line.startswith("VECTOR ")]
        if result.returncode or native_vectors != common_vectors:
            raise SystemExit("Native correctness baseline mismatch; see native.log")
    summary = []
    for mode in (() if args.correctness_only else ("tiered", "c1")):
        for kind in ("empty", "surface", "mixed", "irrelevant64"):
            for access in ("cold", "set", "cached"):
                entry = dict(mode=mode, kind=kind, access=access)
                for candidate in (False, True):
                    selected = [r for r in rows if (r["mode"], r["kind"], r["access"], r["candidate"]) == (mode, kind, access, candidate)]
                    entry[str(candidate).lower()] = {"ns_median": statistics.median(r["ns"] for r in selected),
                                                    "bytes_median": statistics.median(r["allocated"] for r in selected),
                                                    "fork_ns_medians": [statistics.median(r["ns"] for r in selected if r["fork"] == f) for f in range(args.forks)]}
                summary.append(entry)
    output = dict(release_sha256=release_hash, selected_file_count=len(manifest["selected_files"]),
                  manifest_sha256=digest(manifest), harness_source_sha256=hashlib.sha256(source_bytes).hexdigest(),
                  selected_hashes_sha256=digest(manifest["selected_files"]),
                  baseline_properties_sha256=digest(manifest["profile"]["properties"]),
                  profile_id=manifest["profile"]["id"], property_delta={"propertySurfaceNoAlloc": ["false", "true"]},
                  batch_compilation=args.batch_compilation,
                  correctness_only=args.correctness_only,
                  correctness_vectors=len(official_vectors), native_vectors=len(common_vectors),
                  java_version=subprocess.run([str(java), "-version"], text=True, capture_output=True).stderr,
                  platform=__import__("platform").platform(), rows=rows, summary=summary)
    (args.output / "result.json").write_text(json.dumps(output, indent=2) + "\n")
    print(json.dumps({k: v for k, v in output.items() if k not in ("rows", "summary")}, indent=2))
    for row in summary:
        print(f"{row['mode']:6} {row['kind']:12} {row['access']:6} false={row['false']} true={row['true']}")


if __name__ == "__main__":
    main()
