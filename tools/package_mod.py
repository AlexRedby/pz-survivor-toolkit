#!/usr/bin/env python3
"""Check a repository mod; optionally generate a local archive."""

from __future__ import annotations

import argparse
from pathlib import Path
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parent.parent
MOD_ROOT = ROOT / "PZSurvivorToolkit"
MOD_NAMES = {"PZSurvivorToolkit": "PZ Survivor Toolkit"}


def validate_no_symlinks(mod_root: Path) -> list[str]:
    if mod_root.is_symlink():
        return [f"symbolic link in mod source: {mod_root}"]
    return [f"symbolic link in mod source: {path}" for path in sorted(mod_root.rglob("*"))
            if path.is_symlink()]


def validate(mod_root: Path = MOD_ROOT) -> list[str]:
    mod_info = mod_root / "42/mod.info"
    bootstrap = mod_root / "42/media/lua/shared" / (mod_root.name + ".lua")
    errors = validate_no_symlinks(mod_root)
    if errors:
        return errors
    if not mod_root.is_dir():
        return [f"missing mod directory: {mod_root}"]
    required_directories = [mod_root / layer / "media" / name
                            for layer in ("common", "42") for name in ("AnimSets", "actiongroups")]
    for required in (mod_root / "common", mod_root / "42", *required_directories):
        if not required.is_dir():
            errors.append(f"required directory is missing or not a directory: {required.relative_to(ROOT)}")
    for required in (mod_info, bootstrap):
        if not required.is_file():
            errors.append(f"required file is missing or not a file: {required.relative_to(ROOT)}")

    if mod_info.is_file():
        metadata: dict[str, str] = {}
        for line in mod_info.read_text(encoding="utf-8").splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                metadata[key.strip()] = value.strip()
        if metadata.get("name") != MOD_NAMES[mod_root.name]:
            errors.append(f"mod.info must declare name={MOD_NAMES[mod_root.name]}")
        if metadata.get("id") != mod_root.name:
            errors.append(f"mod.info must declare id={mod_root.name}")
        for key in ("icon", "poster"):
            name = metadata.get(key, "")
            candidates = [mod_root / folder / name for folder in ("42", "common")]
            if not name or not any(path.is_file() and path.resolve().is_relative_to(mod_root.resolve())
                                   for path in candidates):
                errors.append(f"mod.info {key} must reference a file inside 42/ or common/")

    if bootstrap.is_file():
        source = bootstrap.read_text(encoding="utf-8")
        if not source.strip():
            errors.append("bootstrap file must not be empty")
    return errors


def package(output: Path, mod_root: Path = MOD_ROOT) -> None:
    errors = validate(mod_root)
    if errors:
        raise ValueError("; ".join(errors))
    if output.is_symlink() or (output.exists() and not output.is_file()):
        raise ValueError(f"archive output must be a regular file: {output}")
    if output.resolve().is_relative_to(mod_root.resolve()):
        raise ValueError(f"archive output must be outside the mod source: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f".{output.name}-", dir=output.parent) as staging:
        temporary = Path(staging) / output.name
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(mod_root.rglob("*")):
                if path.name == ".gitkeep":
                    continue
                archive_name = Path(mod_root.name) / path.relative_to(mod_root)
                if path.is_dir():
                    archive.writestr(archive_name.as_posix() + "/", b"")
                elif path.is_file():
                    archive.write(path, archive_name.as_posix())
        temporary.replace(output)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="validate the mod structure")
    parser.add_argument("--mod", choices=MOD_NAMES, default=MOD_ROOT.name, help="mod folder to check/package")
    parser.add_argument(
        "--output",
        type=Path,
        help="ZIP output path (default: ROOT/dist/<mod>.zip)",
    )
    args = parser.parse_args()
    mod_root = ROOT / args.mod
    errors = validate(mod_root)
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print("OK: mod structure is valid")
    if not args.check:
        output = args.output or ROOT / "dist" / (args.mod + ".zip")
        try:
            package(output, mod_root)
        except (OSError, ValueError) as error:
            print(f"ERROR: {error}")
            return 1
        print(f"OK: wrote {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
