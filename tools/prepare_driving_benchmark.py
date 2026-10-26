#!/usr/bin/env python3
"""Prepare the portable Windows driving benchmark without reading a game profile."""

from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "PZDrivingBench"
LAUNCHER_FILES = ("Start-driving.cmd", "Start-vanilla.cmd", "Launch.ps1",
                  "Record-JFR.cmd", "Record-JFR.ps1", "README.md")
OWNER = ".pz-driving-bench-package"
OWNER_TEXT = "PZDrivingBench distributable v1\n"
HOST_INI = """# Isolated new test world only. Choose PZDrivingBench in the Host menu.
Mods=PZDrivingBench
WorkshopItems=
Map=Muldraugh, KY
SpawnPoint=10818,10118,0
Public=false
UPnP=false
PVP=false
DoLuaChecksum=true
PauseEmpty=true
"""


def _regular_tree(path: Path) -> None:
    if path.is_symlink() or any(parent.is_symlink() for parent in path.parents):
        raise ValueError(f"Linked package path is not supported: {path}")
    if not path.exists():
        raise ValueError(f"Missing package source: {path}")
    for entry in path.rglob("*") if path.is_dir() else ():
        if entry.is_symlink() or not (entry.is_dir() or entry.is_file()):
            raise ValueError(f"Non-regular package source: {entry}")


def prepare(root: Path = ROOT) -> tuple[Path, Path]:
    root = root.resolve()
    source = root / "tests/driving_benchmark"
    mod = source / "mods" / PACKAGE
    for path in [*(source / name for name in LAUNCHER_FILES), mod]:
        _regular_tree(path)
    info = mod / "42/mod.info"
    if not info.is_file() or "id=PZDrivingBench" not in info.read_text(encoding="utf-8-sig").splitlines():
        raise ValueError("Fixture must declare id=PZDrivingBench in 42/mod.info")

    dist = root / "dist"
    output = dist / PACKAGE
    archive = dist / f"{PACKAGE}.zip"
    for path in (dist, output, archive):
        if path.is_symlink():
            raise ValueError(f"Refusing linked output: {path}")
    if output.exists():
        owner = output / OWNER
        if not output.is_dir() or not owner.is_file() or owner.is_symlink() or owner.read_text() != OWNER_TEXT:
            raise ValueError(f"Refusing to replace foreign output: {output}")
        _regular_tree(output)
        if any((output / name).exists() for name in ("Profiles", "JFR")):
            raise ValueError(f"Keep existing benchmark profiles and recordings; move this used package before rebuilding: {output}")
    if archive.exists() and not archive.is_file():
        raise ValueError(f"Archive output is not a regular file: {archive}")

    dist.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".driving-bench-", dir=dist) as temporary:
        temporary = Path(temporary)
        staging = temporary / PACKAGE
        staging.mkdir()
        for name in LAUNCHER_FILES:
            shutil.copy2(source / name, staging / name)
        shutil.copytree(mod, staging / "mods" / PACKAGE)
        (staging / "Server").mkdir()
        (staging / "Server/PZDrivingBench.ini").write_text(HOST_INI, encoding="utf-8")
        (staging / OWNER).write_text(OWNER_TEXT, encoding="utf-8")
        packed = temporary / archive.name
        with zipfile.ZipFile(packed, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
            for path in sorted(staging.rglob("*")):
                bundle.write(path, (Path(PACKAGE) / path.relative_to(staging)).as_posix())
        previous = temporary / "previous"
        if output.exists():
            output.rename(previous)
        try:
            staging.rename(output)
            packed.replace(archive)
        except OSError:
            if output.exists():
                shutil.rmtree(output)
            if previous.exists():
                previous.rename(output)
            raise
    return output, archive


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    try:
        output, archive = prepare()
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"Ready: {output}\nArchive: {archive}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
