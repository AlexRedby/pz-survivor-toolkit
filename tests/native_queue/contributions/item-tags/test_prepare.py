import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location("item_tags_prepare", Path(__file__).with_name("prepare.py"))
prepare = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(prepare)


class PrepareTest(unittest.TestCase):
    def test_helper_contains_only_fixture_and_metadata_and_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            toolkit, output = root / "toolkit", root / "helper"
            visuals = toolkit / prepare.VISUALS
            visuals.parent.mkdir(parents=True)
            source = 'return {"Item_Plate", "Item_Plate", "media/ui/test.png"}'
            visuals.write_text(source)
            self.assertEqual(prepare.prepare(toolkit, output), 2)
            fixture = (output / "42/media/lua/client" / prepare.FIXTURE).read_text()
            self.assertNotIn(prepare.MARKER, fixture)
            self.assertEqual(fixture.count('assert(getTexture("Item_Plate")'), 1)
            self.assertIn('assert(getTexture("media/ui/test.png")', fixture)
            self.assertEqual(visuals.read_text(), source)
            self.assertEqual(sorted(str(p.relative_to(output)) for p in output.rglob("*") if p.is_file()),
                             ["42/media/lua/client/ZZQuartermasterScreens.lua", "42/mod.info", "fixture-manifest.json"])
            manifest = json.loads((output / "fixture-manifest.json").read_text())
            self.assertEqual(manifest["textures"], ["Item_Plate", "media/ui/test.png"])
            with self.assertRaises(FileExistsError):
                prepare.prepare(toolkit, output)
            visuals.write_text("return {}")
            with self.assertRaises(ValueError):
                prepare.prepare(toolkit, root / "invalid")
            self.assertFalse((root / "invalid").exists())


if __name__ == "__main__":
    unittest.main()
