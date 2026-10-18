import hashlib
import json
import sys
import subprocess
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from check_tag_categories import category_keys, inspect_lua, uncovered, load_baseline


class TagCategoryCheckerTest(unittest.TestCase):
    def test_multiline_constants_and_dynamic_categories(self):
        source = '''
-- TweakItem("Base.Fake", "DisplayCategory", "CommentOnly")
--[[
TweakItem("Base.Fake", "DisplayCategory", "LongCommentOnly")
]]
local knownCategory = "weaponFirearm_P308"
globalCategory = "weaponBlunt"
TweakItem(
    "Base.Item",
    "DisplayCategory",
    knownCategory
)
TweakItem("Base.Other", "DisplayCategory", "weaponAxe")
TweakItem("Base.Global", "DisplayCategory", globalCategory)
TweakItem("Base.Runtime", "DisplayCategory", selectedCategory)
item:setDisplayCategory("weaponBlade")
item:setDisplayCategory(dynamicCategory)
'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "categories.lua"
            path.write_text(source)
            values, dynamic = inspect_lua(path)
        self.assertEqual(values, {"weaponFirearm_P308", "weaponAxe", "weaponBlunt", "weaponBlade"})
        self.assertEqual(dynamic, {"selectedCategory", "dynamicCategory"})

    def test_schema_parser_and_negative_coverage(self):
        schema = '''
return {
    categories = {
        ["Known"] = {"food"},
    },
    labels = {
        ["food"] = "Food",
    },
}
'''
        known = category_keys(schema)
        self.assertEqual(known, {"Known"})
        self.assertEqual(uncovered({"Known", "Missing"}, known), {"Missing"})

    def run_cli(self, schema, *options):
        script = Path(__file__).resolve().parents[1] / "tools" / "check_tag_categories.py"
        return subprocess.run(
            [sys.executable, str(script), "--schema", str(schema), *map(str, options)],
            capture_output=True, text=True,
        )

    def taxonomy_fixture(self, base):
        schema = base / "schema.lua"
        schema.write_text('return { categories = {\n ["Known"] = {"miscellaneous"},\n }, labels = {} }')
        root = base / "organizedCategories_core"
        lua = root / "42" / "media" / "lua"
        translation = lua / "shared" / "Translate" / "EN" / "IG_UI.json"
        translation.parent.mkdir(parents=True)
        translation.write_text('{"IGUI_ItemCat_Known": "Original meaning"}')
        writer = lua / "client" / "categories.lua"
        writer.parent.mkdir()
        writer.write_text('TweakItem("Base.Original", "DisplayCategory", "Known")')
        (writer.parent / "unrelated.lua").write_text("return {}\n")
        baseline = base / "baseline.json"
        baseline.write_text(json.dumps({
            "format": 1,
            "schema_sha256": hashlib.sha256(schema.read_bytes()).hexdigest(),
            "files": {path.relative_to(lua).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                      for path in (translation, writer)},
        }))
        return schema, root, lua, translation, writer, baseline

    def test_cli_checks_unchanged_baseline_with_both_oc_root_forms(self):
        with tempfile.TemporaryDirectory() as directory:
            schema, root, lua, _, _, baseline = self.taxonomy_fixture(Path(directory))
            for path in (root, lua):
                result = self.run_cli(schema, "--oc-root", path, "--oc-baseline", baseline)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("source baseline: unchanged", result.stdout)

    def test_cli_requires_review_for_changed_meaning_or_assignment_with_same_ids(self):
        with tempfile.TemporaryDirectory() as directory:
            schema, root, _, translation, writer, baseline = self.taxonomy_fixture(Path(directory))
            for path, replacement in (
                (translation, '{"IGUI_ItemCat_Known": "Different meaning"}'),
                (writer, 'TweakItem("Base.Different", "DisplayCategory", "Known")'),
                (schema, schema.read_text() + "\n-- reviewed mapping changed\n"),
            ):
                with self.subTest(path=path):
                    original = path.read_text()
                    path.write_text(replacement)
                    result = self.run_cli(schema, "--oc-root", root, "--oc-baseline", baseline)
                    path.write_text(original)
                    self.assertEqual(result.returncode, 1, result.stderr)
                    self.assertIn("source baseline: REVIEW REQUIRED", result.stdout)
                    self.assertIn("uncovered: 0", result.stdout)
                    self.assertIn(path.name, result.stdout)

    def test_cli_requires_review_for_added_removed_or_no_longer_detected_writer(self):
        with tempfile.TemporaryDirectory() as directory:
            schema, root, lua, _, writer, baseline = self.taxonomy_fixture(Path(directory))
            extra = lua / "client" / "new_writer.lua"
            extra.write_text('item:setDisplayCategory("Known")')
            result = self.run_cli(schema, "--oc-root", root, "--oc-baseline", baseline)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("added source: client/new_writer.lua", result.stdout)
            extra.unlink()
            for text in (None, "-- no category writer remains\n"):
                with self.subTest(text=text):
                    if text is None:
                        writer.unlink()
                    else:
                        writer.write_text(text)
                    result = self.run_cli(schema, "--oc-root", root, "--oc-baseline", baseline)
                    self.assertEqual(result.returncode, 1, result.stderr)
                    self.assertIn("removed source: client/categories.lua", result.stdout)

    def test_cli_missing_or_invalid_baseline_cannot_pass_verification(self):
        with tempfile.TemporaryDirectory() as directory:
            schema, root, _, _, _, baseline = self.taxonomy_fixture(Path(directory))
            baseline.unlink()
            result = self.run_cli(schema, "--oc-root", root, "--oc-baseline", baseline)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("baseline.json", result.stderr)
            self.assertNotIn("source baseline: unchanged", result.stdout)
            for value in ([], {"format": 2}, {"format": 1, "files": {}},
                          {"format": 1, "schema_sha256": "a" * 64,
                           "files": {"shared/Translate/EN/IG_UI.json": "not a hash"}}):
                with self.subTest(value=value):
                    baseline.write_text(json.dumps(value))
                    with self.assertRaisesRegex(ValueError, "invalid organizedCategories baseline"):
                        load_baseline(baseline)

    def test_cli_rejects_empty_schema(self):
        with tempfile.TemporaryDirectory() as directory:
            schema = Path(directory) / "schema.lua"
            schema.write_text("return { categories = {}, labels = {} }")
            result = self.run_cli(schema, "--mod-root", directory)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("schema contains no category entries", result.stderr)

    def test_cli_audits_game_or_mod_without_organized_categories(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            schema = base / "schema.lua"
            schema.write_text('return { categories = {\n ["Known"] = {"miscellaneous"},\n }, labels = {} }')
            mods = base / "mods"
            mods.mkdir()
            game = base / "game"
            scripts = game / "media" / "scripts"
            scripts.mkdir(parents=True)
            for option, root, source, text in (
                ("--mod-root", mods, mods / "categories.lua", 'item:setDisplayCategory("{}")'),
                ("--game", game, scripts / "items.txt", 'DisplayCategory = {},'),
            ):
                for category, expected in (("Known", 0), ("Missing", 1)):
                    with self.subTest(option=option, category=category):
                        source.write_text(text.format(category))
                        result = self.run_cli(schema, option, root)
                        self.assertEqual(result.returncode, expected, result.stderr)
                        self.assertIn(f"source category IDs: 1; uncovered: {expected}", result.stdout)
                        self.assertIn("source baseline: not checked (--oc-root not supplied)", result.stdout)

    def test_cli_rejects_invalid_explicit_roots(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            schema = base / "schema.lua"
            schema.write_text('return { categories = { ["Known"] = {"miscellaneous"}, }, labels = {} }')
            missing = base / "missing"
            for option in ("--oc-root", "--mod-root", "--game"):
                with self.subTest(option=option):
                    result = self.run_cli(schema, option, missing)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("existing directory", result.stderr)

    def test_cli_rejects_oc_root_without_taxonomy_translation(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            schema = base / "schema.lua"
            schema.write_text('return { categories = { ["Known"] = {"miscellaneous"}, }, labels = {} }')
            lua = base / "organizedCategories_core" / "42" / "media" / "lua"
            lua.mkdir(parents=True)
            (lua / "categories.lua").write_text('-- source exists\n')
            result = self.run_cli(schema, "--oc-root", lua.parents[2])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing EN translation", result.stderr)

    def test_cli_rejects_empty_or_unstructured_game_and_mod_roots(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            schema = base / "schema.lua"
            schema.write_text('return { categories = { ["Known"] = {"miscellaneous"}, }, labels = {} }')
            empty = base / "empty"
            empty.mkdir()
            result = self.run_cli(schema, "--mod-root", empty)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("no supported source files", result.stderr)
            result = self.run_cli(schema, "--game", empty)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("game root containing media/scripts", result.stderr)


if __name__ == "__main__":
    unittest.main()
