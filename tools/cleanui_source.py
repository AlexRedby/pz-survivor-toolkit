"""Prepare a source-locked CleanUI copy without changing its Workshop source."""

from __future__ import annotations

import hashlib
from pathlib import Path

try:
    from .dependency_source import prepare_source_patch
except ImportError:
    from dependency_source import prepare_source_patch


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


def _patched(source: bytes) -> bytes:
    for before, after in _EDITS:
        if source.count(before) != 1:
            raise ValueError("Reviewed CleanUI food-age source boundary changed")
        source = source.replace(before, after, 1)
    if _sha256(source) != PATCHED_SOURCE_SHA256:
        raise ValueError("Patched CleanUI food-age source differs from reviewed result")
    return source


def prepare_cleanui(source_root: Path, destination: Path, game_version: str = "42.21") -> dict:
    """Copy the complete dependency and change only its reviewed active renderer."""
    return prepare_source_patch(source_root, destination, mod_id="CleanUI", target=TARGET,
                                original_sha256=ORIGINAL_SOURCE_SHA256,
                                patched_sha256=PATCHED_SOURCE_SHA256, patch_id=PATCH_ID,
                                transform=_patched, game_version=game_version)
