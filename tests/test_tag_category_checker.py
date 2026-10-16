import sys
import subprocess
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from check_tag_categories import category_keys, inspect_lua, uncovered


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
