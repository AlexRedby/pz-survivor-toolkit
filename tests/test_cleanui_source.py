"""Source preparation delivers the reviewed fix without mutating dependencies."""

import hashlib
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools import cleanui_source, dependency_source


ORIGINAL = b"""local CLEANUI_LARGE_STACK_OPTIMIZATION_THRESHOLD = 200
local CLEANUI_COLLAPSED_FOOD_AGE_UPDATE_LIMIT = 50
local CLEANUI_COLLAPSED_FOOD_AGE_UPDATE_INTERVAL_MS = 1000
local function CleanUI_updateCollapsedFoodStackAge(itemGroup, rowVisible)
    -- Large collapsed food stacks used to update dozens of items every render, even off-screen.
    -- Keep the extra freshness update visible-only and throttled; the first displayed item still
    -- follows the normal vanilla render path every frame.
    if rowVisible ~= true or not itemGroup or not itemGroup.items then return end
    local now = CleanUI_getCachedTimestampMs()
    local lastUpdate = tonumber(itemGroup._cleanUILastFoodAgeUpdateMs) or 0
    if now ~= 0 and lastUpdate ~= 0 and (now - lastUpdate) < CLEANUI_COLLAPSED_FOOD_AGE_UPDATE_INTERVAL_MS then return end
    itemGroup._cleanUILastFoodAgeUpdateMs = now
    local startIndex = CleanUI_getStackActualStartIndex(itemGroup)
    local maxIndex = #itemGroup.items
    if itemGroup.cleanUILargeStackOptimized and maxIndex - startIndex + 1 > CLEANUI_COLLAPSED_FOOD_AGE_UPDATE_LIMIT then
        maxIndex = math.min(maxIndex, startIndex + CLEANUI_COLLAPSED_FOOD_AGE_UPDATE_LIMIT - 1)
    end
    for i = startIndex, maxIndex do
        local foodItem = itemGroup.items[i]
        if foodItem and type(foodItem.updateAge) == "function" then foodItem:updateAge() end
    end
end
"""
EXPECTED = b"""local CLEANUI_LARGE_STACK_OPTIMIZATION_THRESHOLD = 200
local CLEANUI_COLLAPSED_FOOD_AGE_UPDATE_INTERVAL_MS = 1000
local function CleanUI_updateCollapsedFoodStackAge(itemGroup, rowVisible)
    -- Refresh every member so older food beyond the displayed header can change freshness.
    -- Keep this visible-only and throttled; the first displayed item still follows the
    -- normal vanilla render path every frame.
    if rowVisible ~= true or not itemGroup or not itemGroup.items then return end
    local now = CleanUI_getCachedTimestampMs()
    local lastUpdate = tonumber(itemGroup._cleanUILastFoodAgeUpdateMs) or 0
    if now ~= 0 and lastUpdate ~= 0 and now >= lastUpdate and (now - lastUpdate) < CLEANUI_COLLAPSED_FOOD_AGE_UPDATE_INTERVAL_MS then return end
    itemGroup._cleanUILastFoodAgeUpdateMs = now
    local startIndex = CleanUI_getStackActualStartIndex(itemGroup)
    local maxIndex = #itemGroup.items
    for i = startIndex, maxIndex do
        local foodItem = itemGroup.items[i]
        if foodItem and type(foodItem.updateAge) == "function" then foodItem:updateAge() end
    end
end
"""


def digest(value):
    return hashlib.sha256(value).hexdigest()


def files(root):
    return {p.relative_to(root).as_posix(): p.read_bytes() for p in root.rglob("*") if p.is_file()}


class CleanUISource(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.source = self.root / "source"
        self.output = self.root / "prepared"
        self.target = self.source / "42.19" / cleanui_source.TARGET
        self.target.parent.mkdir(parents=True)
        self.target.write_bytes(ORIGINAL)
        (self.source / "42.19/mod.info").write_text("id=CleanUI\nversion=fixture\n")
        (self.source / "common").mkdir()
        (self.source / "common/texture.bin").write_bytes(b"\x00unchanged\xff")
        (self.source / "42.30").mkdir()
        (self.source / "42.30/mod.info").write_text("id=FutureCleanUI\n")
        (self.source / "42.30/unused.lua").write_bytes(b"future version is untouched\r\n")
        (self.source / "legacy.lua").write_bytes(b"legacy source is untouched\r\n")
        self.addCleanup(patch.stopall)
        patch.object(cleanui_source, "ORIGINAL_SOURCE_SHA256", digest(ORIGINAL)).start()
        patch.object(cleanui_source, "PATCHED_SOURCE_SHA256", digest(EXPECTED)).start()

    def test_reviewed_patch_preserves_all_other_bytes_and_source(self):
        before = files(self.source)
        record = cleanui_source.prepare_cleanui(self.source, self.output)
        self.assertEqual(files(self.source), before)
        expected = dict(before)
        expected["42.19/" + cleanui_source.TARGET.as_posix()] = EXPECTED
        self.assertEqual(files(self.output), expected)
        self.assertEqual(record["input_sha256"], digest(ORIGINAL))
        self.assertEqual(record["output_sha256"], digest(EXPECTED))
        self.assertEqual(record["source_files"], {p: digest(v) for p, v in before.items()})
        self.assertEqual(record["prepared_files"], {p: digest(v) for p, v in expected.items()})
        self.assertEqual(record["selected_layer"], "42.19")
        self.assertEqual(record["target"], "42.19/" + cleanui_source.TARGET.as_posix())
        self.assertEqual(record["patch_id"], "cleanui-collapsed-food-age-v1")
        self.assertFalse(record["already_patched"])
        self.assertNotIn(str(self.root), str(record))

    def test_known_already_fixed_source_is_copied_without_additional_changes(self):
        self.target.write_bytes(EXPECTED)
        before = files(self.source)
        record = cleanui_source.prepare_cleanui(self.source, self.output)
        self.assertEqual(files(self.output), before)
        self.assertEqual(files(self.source), before)
        self.assertTrue(record["already_patched"])
        self.assertEqual(record["source_files"], record["prepared_files"])

    def test_unknown_source_fails_without_creating_output(self):
        self.target.write_bytes(ORIGINAL + b"-- upstream update\n")
        before = files(self.source)
        with self.assertRaisesRegex(ValueError, "Unknown CleanUI"):
            cleanui_source.prepare_cleanui(self.source, self.output)
        self.assertFalse(self.output.exists())
        self.assertEqual(files(self.source), before)

    def test_wrong_active_mod_id_and_missing_version_renderer_are_rejected(self):
        info = self.source / "42.19/mod.info"
        info.write_text("id=DifferentMod\n")
        with self.assertRaisesRegex(ValueError, "CleanUI Mod ID"):
            cleanui_source.prepare_cleanui(self.source, self.output)
        info.write_text("id=CleanUI\n")
        self.target.rename(self.source / "legacy-renderer.lua")
        with self.assertRaisesRegex(ValueError, "active version is missing"):
            cleanui_source.prepare_cleanui(self.source, self.output)
        self.assertFalse(self.output.exists())

    def test_existing_destination_and_overlapping_paths_are_rejected(self):
        self.output.mkdir()
        sentinel = self.output / "keep.txt"
        sentinel.write_text("keep")
        with self.assertRaisesRegex(ValueError, "must not exist"):
            cleanui_source.prepare_cleanui(self.source, self.output)
        self.assertEqual(sentinel.read_text(), "keep")
        with self.assertRaisesRegex(ValueError, "must not overlap"):
            cleanui_source.prepare_cleanui(self.source, self.source / "nested-output")

    def test_symlink_sources_and_destination_are_rejected(self):
        link = self.root / "source-link"
        link.symlink_to(self.source, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "regular mod directory"):
            cleanui_source.prepare_cleanui(link, self.output)
        nested = self.source / "linked.lua"
        nested.symlink_to(self.target)
        with self.assertRaisesRegex(ValueError, "symbolic link"):
            cleanui_source.prepare_cleanui(self.source, self.output)
        nested.unlink()
        self.output.symlink_to(self.root / "absent")
        with self.assertRaisesRegex(ValueError, "must not exist"):
            cleanui_source.prepare_cleanui(self.source, self.output)

    def test_unsupported_game_version_is_rejected(self):
        for version in ("41.78", "unknown", "42.bad", None):
            with self.subTest(version=version), self.assertRaisesRegex(ValueError, "B42"):
                cleanui_source.prepare_cleanui(self.source, self.output, version)
        self.assertFalse(self.output.exists())

    def test_changed_source_while_copying_rejects_and_removes_partial_copy(self):
        copytree = shutil.copytree

        def changed(source, destination, *args, **kwargs):
            result = copytree(source, destination, *args, **kwargs)
            if Path(source) == self.source:
                (self.source / "common/texture.bin").write_bytes(b"changed by another process")
            return result

        with patch.object(dependency_source.shutil, "copytree", side_effect=changed):
            with self.assertRaisesRegex(ValueError, "changed during preparation"):
                cleanui_source.prepare_cleanui(self.source, self.output)
        self.assertFalse(self.output.exists())

    def test_unexpected_patch_result_fails_before_copy(self):
        with patch.object(cleanui_source, "PATCHED_SOURCE_SHA256", "0" * 64):
            with self.assertRaisesRegex(ValueError, "differs from reviewed result"):
                cleanui_source.prepare_cleanui(self.source, self.output)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
