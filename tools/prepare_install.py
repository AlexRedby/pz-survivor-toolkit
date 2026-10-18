#!/usr/bin/env python3
"""Build and prepare the complete local mod set for the server and all clients."""

from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

try:
    from .package_mod import ROOT, validate
except ImportError:
    from package_mod import ROOT, validate


MOD_IDS = ("PZSurvivorToolkit", "PZToolkitJavaPatches")
INI_NAME = "SurvivorQoL-selected.ini"


def metadata(path: Path) -> dict[str, str]:
    return {key.strip(): value.strip()
            for line in path.read_text(encoding="utf-8").splitlines()
            if "=" in line and not line.lstrip().startswith("#")
            for key, value in [line.split("=", 1)]}


def prepare(root: Path = ROOT, game: Path | None = None, jdk: Path | None = None,
            check: bool = False) -> Path:
    dist = root / "dist"
    output = dist / "SurvivorQoL"
    if dist.is_symlink() or output.is_symlink() or (output.exists() and not output.is_dir()):
        raise ValueError(f"Prepared output must be a regular directory: {output}")

    for name in MOD_IDS[:1]:
        errors = validate(root / name)
        if errors:
            raise ValueError("; ".join(errors))
    ini = metadata(root / INI_NAME)
    selected = {name.strip() for name in ini.get("Mods", "").split(";")}
    missing = set(MOD_IDS) - selected
    if missing:
        raise ValueError("INI is missing required local mod IDs: " + ", ".join(sorted(missing)))
    workshop = ini.get("WorkshopItems", "").split(";")
    if any(item and (not item.isascii() or not item.isdigit()) for item in workshop):
        raise ValueError("WorkshopItems must contain only numeric Workshop IDs; local mods have none")

    command = [sys.executable, str(root / "JavaPatches/build.py")]
    for option, value in (("--game", game), ("--jdk", jdk)):
        if value is not None:
            command.extend((option, str(value)))
    if check:
        command.append("--check")
    subprocess.run(command, cwd=root, check=True)

    patch = root / "JavaPatches/build" / MOD_IDS[1]
    info = metadata(patch / "42/mod.info")
    if info.get("id") != MOD_IDS[1] or not (patch / "common").is_dir():
        raise ValueError("Generated Java patch mod has an invalid ID or missing common directory")
    jar_name = info.get("javaJarFile", "")
    jar = patch / "42" / jar_name
    if not jar_name or not jar.is_file() or not jar.resolve().is_relative_to((patch / "42").resolve()):
        raise ValueError("Generated Java patch mod javaJarFile is missing or outside the mod")

    dist.mkdir(exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=".SurvivorQoL-", dir=dist))
    previous = temporary / "previous"
    promoted = False
    try:
        staging = temporary / "prepared"
        for name in MOD_IDS:
            source = patch if name == MOD_IDS[1] else root / name
            shutil.copytree(source, staging / "mods" / name)
        (staging / "Server").mkdir()
        shutil.copy2(root / INI_NAME, staging / "Server" / INI_NAME)
        for launcher in ("start-host.ps1", "start-host.command"):
            shutil.copy2(root / "JavaPatches" / launcher, staging / launcher)
        guide = (root / "MOD_INSTALL.md").read_text(encoding="utf-8")
        guide = guide.replace("](" + INI_NAME + ")", "](Server/" + INI_NAME + ")")
        guide = guide.replace("](README.md", "](https://github.com/AlexRedby/pz-survivor-toolkit/blob/main/README.md")
        guide = guide.replace("](docs/", "](https://github.com/AlexRedby/pz-survivor-toolkit/blob/main/docs/")
        (staging / "MOD_INSTALL.md").write_text(guide, encoding="utf-8")
        (staging / "JavaPatches").mkdir()
        java_guide = (root / "JavaPatches/README.md").read_text(encoding="utf-8")
        for folder in ("docs", "tests"):
            java_guide = java_guide.replace("](../" + folder + "/", "](https://github.com/AlexRedby/pz-survivor-toolkit/blob/main/" + folder + "/")
        (staging / "JavaPatches/README.md").write_text(java_guide, encoding="utf-8")

        if output.exists():
            output.rename(previous)
        try:
            staging.rename(output)
        except OSError:
            if previous.exists():
                try:
                    previous.rename(output)
                except OSError as error:
                    raise OSError(f"Previous prepared set is preserved at {previous}; restore failed") from error
            raise
        promoted = True
    finally:
        if promoted or not previous.exists():
            shutil.rmtree(temporary)
    return output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, help="game Java folder; defaults are provided by JavaPatches/build.py")
    parser.add_argument("--jdk", type=Path, help="JDK 25+ folder; defaults are provided by JavaPatches/build.py")
    parser.add_argument("--check", action="store_true", help="also run the Java native regression checks")
    args = parser.parse_args()
    try:
        output = prepare(game=args.game, jdk=args.jdk, check=args.check)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"Ready: {output}")
    print("Copy the contents of mods/ into Zomboid/mods on the server and every client.")
    print("For a new server profile, copy Server/SurvivorQoL-selected.ini into Zomboid/Server.")
    print("For an existing profile, copy only Mods= and WorkshopItems= into its INI; keep its other settings.")
    print("Clients use this same prepared copy and do not need Python or a JDK.")
    print("Complete ZombieBuddy loader setup and JAR approvals on each machine; see the prepared MOD_INSTALL.md.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
