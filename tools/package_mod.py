#!/usr/bin/env python3
"""Check and package the PZ Survivor Toolkit mod."""

from __future__ import annotations

import argparse
from pathlib import Path
import zipfile


ROOT = Path(__file__).resolve().parent.parent
MOD_ROOT = ROOT / "PZSurvivorToolkit"
MOD_INFO = MOD_ROOT / "42" / "mod.info"
BOOTSTRAP = MOD_ROOT / "42" / "media" / "lua" / "shared" / "PZSurvivorToolkit.lua"


def validate() -> list[str]:
    errors: list[str] = []
    if not MOD_ROOT.is_dir():
        return [f"missing mod directory: {MOD_ROOT}"]
    for required in (MOD_ROOT / "common", MOD_ROOT / "42"):
        if not required.is_dir():
            errors.append(f"required directory is missing or not a directory: {required.relative_to(ROOT)}")
    for required in (MOD_INFO, BOOTSTRAP):
        if not required.is_file():
            errors.append(f"required file is missing or not a file: {required.relative_to(ROOT)}")

    if MOD_INFO.is_file():
        metadata: dict[str, str] = {}
        for line in MOD_INFO.read_text(encoding="utf-8").splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                metadata[key.strip()] = value.strip()
        if metadata.get("name") != "PZ Survivor Toolkit":
            errors.append("mod.info must declare name=PZ Survivor Toolkit")
        if metadata.get("id") != "PZSurvivorToolkit":
            errors.append("mod.info must declare id=PZSurvivorToolkit")

    if BOOTSTRAP.is_file():
        source = BOOTSTRAP.read_text(encoding="utf-8")
        if not source.strip():
            errors.append("bootstrap file must not be empty")
    return errors


def package(output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(f"{MOD_ROOT.name}/common/", b"")
        for path in sorted(MOD_ROOT.rglob("*")):
            if not path.is_file() or path.name == ".gitkeep":
                continue
            archive_name = Path(MOD_ROOT.name) / path.relative_to(MOD_ROOT)
            archive.write(path, archive_name.as_posix())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="validate the mod structure")
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "dist/PZSurvivorToolkit.zip",
        help="ZIP output path (default: ROOT/dist/PZSurvivorToolkit.zip)",
    )
    args = parser.parse_args()
    errors = validate()
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print("OK: mod structure is valid")
    if not args.check:
        package(args.output)
        print(f"OK: wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
