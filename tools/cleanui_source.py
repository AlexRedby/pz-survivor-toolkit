"""Prepare a source-locked CleanUI copy without changing its Workshop source."""

from __future__ import annotations

import hashlib
from pathlib import Path
import shutil

try:
    from .package_mod import validate_no_symlinks
    from .queue_checks.mod_selection import VERSION, metadata, mod_info, mod_layers, selected_mod_version
except ImportError:
    from package_mod import validate_no_symlinks
    from queue_checks.mod_selection import VERSION, metadata, mod_info, mod_layers, selected_mod_version


PATCH_ID = "cleanui-collapsed-food-age-v1"
ORIGINAL_SOURCE_SHA256 = "f5992aaebc4f629fd6ebb7b049be86a3e0995ea82276b23f22cf921a18bb7cc0"
PATCHED_SOURCE_SHA256 = "2b9401f5cfc32c79b834cbd9e874fa406018bf978e2009a92bcf88a8b4d966d8"
TARGET = Path("media/lua/client/ISUI/ISInventoryPane.lua")

_EDITS = (
    (b"local CLEANUI_COLLAPSED_FOOD_AGE_UPDATE_LIMIT = 50\n", b""),
    (
        b"    -- Large collapsed food stacks used to update dozens of items every render, even off-screen.\n"
        b"    -- Keep the extra freshness update visible-only and throttled; the first displayed item still\n"
        b"    -- follows the normal vanilla render path every frame.\n",
        b"    -- Refresh every member so older food beyond the displayed header can change freshness.\n"
        b"    -- Keep this visible-only and throttled; the first displayed item still follows the\n"
        b"    -- normal vanilla render path every frame.\n",
    ),
    (
        b"    if now ~= 0 and lastUpdate ~= 0 and (now - lastUpdate) < CLEANUI_COLLAPSED_FOOD_AGE_UPDATE_INTERVAL_MS then return end\n",
        b"    if now ~= 0 and lastUpdate ~= 0 and now >= lastUpdate and (now - lastUpdate) < CLEANUI_COLLAPSED_FOOD_AGE_UPDATE_INTERVAL_MS then return end\n",
    ),
    (
        b"    if itemGroup.cleanUILargeStackOptimized and maxIndex - startIndex + 1 > CLEANUI_COLLAPSED_FOOD_AGE_UPDATE_LIMIT then\n"
        b"        maxIndex = math.min(maxIndex, startIndex + CLEANUI_COLLAPSED_FOOD_AGE_UPDATE_LIMIT - 1)\n"
        b"    end\n",
        b"",
    ),
)


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _hashes(root: Path) -> dict[str, str]:
    errors = validate_no_symlinks(root)
    if errors:
        raise ValueError("; ".join(errors))
    return {path.relative_to(root).as_posix(): _sha256(path.read_bytes())
            for path in sorted(root.rglob("*")) if path.is_file()}


def _patched(source: bytes) -> bytes:
    for before, after in _EDITS:
        if source.count(before) != 1:
            raise ValueError("Reviewed CleanUI food-age source boundary changed")
        source = source.replace(before, after, 1)
    if _sha256(source) != PATCHED_SOURCE_SHA256:
        raise ValueError("Patched CleanUI food-age source differs from reviewed result")
    return source


def prepare_cleanui(source_root: Path, destination: Path, game_version: str = "42.21") -> dict:
    """Copy a known CleanUI source into an absent staging path and return provenance.

    Only the active renderer source changes. The returned manifests use paths
    relative to the mod root and contain no machine-specific source locations.
    The caller may store this record alongside its prepared mods, outside CleanUI.
    """
    source_root, destination = Path(source_root), Path(destination)
    if source_root.is_symlink() or not source_root.is_dir():
        raise ValueError("CleanUI source must be a regular mod directory")
    if destination.exists() or destination.is_symlink():
        raise ValueError("CleanUI destination must not exist")
    source_root, destination = source_root.resolve(), destination.resolve()
    if destination.is_relative_to(source_root) or source_root.is_relative_to(destination):
        raise ValueError("CleanUI source and destination must not overlap")
    if not isinstance(game_version, str) or not VERSION.fullmatch(game_version):
        raise ValueError("CleanUI game version must be a numeric B42 version")
    version = tuple(map(int, game_version.split(".")))
    if version[0] != 42:
        raise ValueError("CleanUI food-age preparation supports B42 only")

    source_files = _hashes(source_root)
    layers = mod_layers(source_root, version)
    selected = selected_mod_version(source_root, version)
    info = mod_info(source_root, version)
    if not layers or info is None or metadata(info).get("id") != "CleanUI":
        raise ValueError("CleanUI source must expose the CleanUI Mod ID in its active B42 layer")
    # The reviewed renderer belongs to the selected version, not a legacy root
    # or a dormant version that the engine will never load.
    target = selected / TARGET
    if not target.is_file():
        raise ValueError("CleanUI active version is missing its inventory renderer")
    relative = target.relative_to(source_root).as_posix()
    before = target.read_bytes()
    digest = _sha256(before)
    if source_files.get(relative) != digest:
        raise ValueError("CleanUI source changed during preparation")
    already_patched = digest == PATCHED_SOURCE_SHA256
    if digest == ORIGINAL_SOURCE_SHA256:
        after = _patched(before)
    elif already_patched:
        after = before
    else:
        raise ValueError("Unknown CleanUI inventory source; review the new source before preparation")
    expected = dict(source_files)
    expected[relative] = PATCHED_SOURCE_SHA256

    try:
        shutil.copytree(source_root, destination)
        (destination / relative).write_bytes(after)
        prepared_files = _hashes(destination)
        if prepared_files != expected or _hashes(source_root) != source_files:
            raise ValueError("CleanUI source or prepared copy changed during preparation")
    except BaseException:
        if destination.is_dir() and not destination.is_symlink():
            shutil.rmtree(destination)
        raise
    return {
        "schema_version": 1,
        "patch_id": PATCH_ID,
        "game_version": game_version,
        "selected_layer": selected.relative_to(source_root).as_posix(),
        "target": relative,
        "input_sha256": digest,
        "output_sha256": PATCHED_SOURCE_SHA256,
        "already_patched": already_patched,
        "source_files": source_files,
        "prepared_files": prepared_files,
    }
