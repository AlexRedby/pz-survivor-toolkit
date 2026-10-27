"""Copy a complete dependency and apply one reviewed active-source change."""

from __future__ import annotations

import hashlib
from pathlib import Path
import shutil
from typing import Callable

try:
    from .package_mod import validate_no_symlinks
    from .queue_checks.mod_selection import VERSION, metadata, mod_info, selected_mod_version
except ImportError:
    from package_mod import validate_no_symlinks
    from queue_checks.mod_selection import VERSION, metadata, mod_info, selected_mod_version


def _hashes(root: Path) -> dict[str, str]:
    errors = validate_no_symlinks(root)
    if errors:
        raise ValueError("; ".join(errors))
    return {path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(root.rglob("*")) if path.is_file()}


def prepare_source_patch(source_root: Path, destination: Path, *, mod_id: str,
                         target: Path, original_sha256: str, patched_sha256: str,
                         patch_id: str, transform: Callable[[bytes], bytes],
                         game_version: str = "42.21") -> dict:
    """Reject unknown or changing sources and return portable input/output hashes."""
    source_root, destination = Path(source_root), Path(destination)
    if source_root.is_symlink() or not source_root.is_dir():
        raise ValueError(f"{mod_id} source must be a regular mod directory")
    if destination.exists() or destination.is_symlink():
        raise ValueError(f"{mod_id} destination must not exist")
    source_root, destination = source_root.resolve(), destination.resolve()
    if destination.is_relative_to(source_root) or source_root.is_relative_to(destination):
        raise ValueError(f"{mod_id} source and destination must not overlap")
    if not isinstance(game_version, str) or not VERSION.fullmatch(game_version):
        raise ValueError(f"{mod_id} game version must be a numeric B42 version")
    version = tuple(map(int, game_version.split(".")))
    if version[0] != 42:
        raise ValueError(f"{mod_id} source preparation supports B42 only")
    if target.is_absolute() or ".." in target.parts:
        raise ValueError("Dependency patch target must stay inside the selected layer")

    source_files = _hashes(source_root)
    selected = selected_mod_version(source_root, version)
    info = mod_info(source_root, version)
    if selected is None or info is None or metadata(info).get("id") != mod_id:
        raise ValueError(f"{mod_id} source must expose the {mod_id} Mod ID in its active B42 layer")
    active_target = selected / target
    if not active_target.is_file():
        raise ValueError(f"{mod_id} active version is missing {target.as_posix()}")
    relative = active_target.relative_to(source_root).as_posix()
    before = active_target.read_bytes()
    digest = hashlib.sha256(before).hexdigest()
    if source_files.get(relative) != digest:
        raise ValueError(f"{mod_id} source changed during preparation")
    already_patched = digest == patched_sha256
    if digest == original_sha256:
        after = transform(before)
    elif already_patched:
        after = before
    else:
        raise ValueError(f"Unknown {mod_id} source; review the new source before preparation")
    if hashlib.sha256(after).hexdigest() != patched_sha256:
        raise ValueError(f"Patched {mod_id} source differs from reviewed result")
    expected = dict(source_files)
    expected[relative] = patched_sha256

    try:
        shutil.copytree(source_root, destination)
        (destination / relative).write_bytes(after)
        prepared_files = _hashes(destination)
        if prepared_files != expected or _hashes(source_root) != source_files:
            raise ValueError(f"{mod_id} source or prepared copy changed during preparation")
    except BaseException:
        if destination.is_dir() and not destination.is_symlink():
            shutil.rmtree(destination)
        raise
    return {"schema_version": 1, "patch_id": patch_id, "game_version": game_version,
            "selected_layer": selected.relative_to(source_root).as_posix(), "target": relative,
            "input_sha256": digest, "output_sha256": patched_sha256,
            "already_patched": already_patched, "source_files": source_files,
            "prepared_files": prepared_files}
