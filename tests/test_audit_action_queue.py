"""Small source-census checks; no installed game or Workshop is required."""
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from tools import audit_action_queue as audit


class ActionQueueAuditTests(unittest.TestCase):
    def write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def test_common_only_mod_uses_declared_id_and_ignores_legacy_root_lua(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            mod = root / 'differently-named-folder'
            self.write(root / 'selected.ini', 'Mods=Selected\n')
            self.write(mod / 'common/mod.info', 'id=Selected\n')
            self.write(mod / 'mod.info', 'id=Legacy\n')
            for layer, action in ((mod, 'LegacyAction'), (mod / 'common', 'CurrentAction')):
                self.write(layer / 'media/lua/action.lua', action + ' = ISBaseTimedAction:derive("' + action + '")')
            roots, mods = audit.source_roots(root, None, None, root / 'selected.ini', (42, 21))
            self.assertEqual([('Selected', mod / 'common/media/lua')], roots)
            self.assertEqual('found', mods[0]['status'])
            self.assertEqual(['CurrentAction'], [row['type'] for row in audit.census(roots)])

    def test_unusable_or_ambiguous_local_sources_are_not_scanned(self):
        cases = [
            ({'Selected/42': 'Other'}, 'missing-or-ambiguous'),
            ({'one/42': 'Selected', 'two/42': 'Selected'}, 'missing-or-ambiguous'),
            ({'one/common': 'Selected', 'one/42': 'Other'}, 'different-mod-id'),
            ({'one/42.13': 'Selected', 'one/42.21': None}, 'different-mod-id'),
            ({'one/common': 'Selected', 'one/43': 'Selected'}, 'missing-compatible-version'),
        ]
        for layers, status in cases:
            with self.subTest(layers=layers), tempfile.TemporaryDirectory() as directory:
                root = Path(directory).resolve()
                self.write(root / 'selected.ini', 'Mods=Selected\n')
                for layer, identifier in layers.items():
                    (root / layer).mkdir(parents=True, exist_ok=True)
                    if identifier:
                        self.write(root / layer / 'mod.info', 'id=' + identifier + '\n')
                roots, mods = audit.source_roots(root, None, None, root / 'selected.ini', (42, 21))
                self.assertEqual([], roots)
                self.assertEqual(status, mods[0]['status'])

    def test_workshop_metadata_is_used_when_local_folder_name_is_misleading(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            self.write(root / 'selected.ini', 'Mods=Selected\nWorkshopItems=123\n')
            self.write(root / 'Selected/42/mod.info', 'id=Other\n')
            mod = root / 'workshop/123/mods/folder/42'
            self.write(mod / 'mod.info', 'id=Selected\n')
            roots, mods = audit.source_roots(root, None, root / 'workshop', root / 'selected.ini', (42, 21))
            self.assertEqual([('Selected', mod / 'media/lua')], roots)
            self.assertEqual('found', mods[0]['status'])

    def test_source_census_inheritance_and_comments(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "actions.lua").write_text('''
ISBaseTimedAction = ISBaseObject:derive("ISBaseTimedAction")
Later = Parent:derive("Later")
Parent = ISBaseTimedAction:derive("Parent")
-- Ignored = Parent:derive("Ignored")
Widget = ISPanel:derive("Widget")
''')
            rows = audit.census([("native", root)])
            self.assertEqual({row["type"] for row in rows}, {"Parent", "Later"})
            self.assertTrue(all(len(row["sha256"]) == 64 for row in rows))

    def test_selected_version_replaces_common_in_same_mod(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for layer in ("common", "42.19", "42.21", "43"):
                target = root / layer / "media/lua"
                target.mkdir(parents=True)
                (target / "action.lua").write_text('ISBaseTimedAction = X:derive("ISBaseTimedAction")\n'
                    + 'Chosen = ISBaseTimedAction:derive("' + layer + '")\n')
            layers = audit.mod_layers(root, (42, 21))
            self.assertEqual([path.name for path in layers], ["common", "42.21"])
            rows = audit.census([("mod", path / "media/lua") for path in layers])
            self.assertEqual([row["type"] for row in rows], ["42.21"])

    def test_missing_game_is_explicit_skip(self):
        try:
            result = audit.audit(ROOT)
        except RuntimeError as error:
            self.skipTest(str(error))
        self.assertTrue(result["native_status"].startswith("SKIP"))
        self.assertEqual(result["errors"], [])
        self.assertGreaterEqual(result["registry_types"], 278)
        self.assertTrue(all(row["game_mp"] == "not-run" for row in result["actions"]))


if __name__ == "__main__":
    unittest.main()
