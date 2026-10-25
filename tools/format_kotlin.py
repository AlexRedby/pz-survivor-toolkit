#!/usr/bin/env python3
"""Format handwritten Kotlin with pinned ktfmt; generated tables stay generator-owned."""

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
FORMATTER_VERSION = "0.65"
FORMATTER_SHA256 = "aba9753b6ab387926179ab7318ba8e0c33dad483ebc72f633e79522265b15214"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--formatter-jar", type=Path, default=os.environ.get("KTFMT_JAR"),
                        help="ktfmt 0.65 with-dependencies JAR; also accepts KTFMT_JAR")
    parser.add_argument("--jdk", type=Path, help="JDK directory; otherwise use java on PATH")
    parser.add_argument("--check", action="store_true", help="Report formatting drift without writing")
    args = parser.parse_args()
    if args.formatter_jar is None:
        parser.error("Pass --formatter-jar or set KTFMT_JAR; this command downloads nothing")
    jar = args.formatter_jar.resolve()
    if not jar.is_file() or hashlib.sha256(jar.read_bytes()).hexdigest() != FORMATTER_SHA256:
        parser.error(f"Expected the official ktfmt {FORMATTER_VERSION} with-dependencies JAR")
    if args.jdk:
        java = args.jdk.resolve() / "bin" / ("java.exe" if os.name == "nt" else "java")
    else:
        java = shutil.which("java")
    if java is None or not Path(java).is_file():
        parser.error("Pass --jdk or put java on PATH")
    sources = []
    for directory in (ROOT / "JavaPatches/src", ROOT / "JavaPatches/tests",
                      ROOT / "tests/native_queue/contributions/wooden_cart_motion",
                      ROOT / "tests/native_queue/contributions/wooden_cart_multiplayer"):
        for path in directory.rglob("*.kt"):
            if any(line.startswith("/** Generated ") for line in path.read_text().splitlines()[:5]):
                continue
            sources.append(path.relative_to(ROOT))
    command = [str(java), "-jar", str(jar), "--kotlinlang-style", "--enable-editorconfig"]
    if args.check:
        command += ["--dry-run", "--set-exit-if-changed"]
    command += list(map(str, sorted(sources)))
    return subprocess.run(command, cwd=ROOT).returncode


if __name__ == "__main__":
    raise SystemExit(main())
