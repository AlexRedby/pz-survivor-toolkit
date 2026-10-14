"""Small source-census checks; no installed game or Workshop is required."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("audit_action_queue", ROOT / "tools/audit_action_queue.py")
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class ActionQueueAuditTests(unittest.TestCase):
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
