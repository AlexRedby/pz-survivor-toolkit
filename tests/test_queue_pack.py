import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import pack


class PackLockTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.game = self.root / 'game'
        self.game.mkdir()
        (self.game / 'projectzomboid.jar').write_bytes(b'game build')
        self.ini = self.root / 'SurvivorQoL-selected.ini'
        self.ini.write_text('Mods=First;Second\nWorkshopItems=1;2\n')
        for id in ('First', 'Second'):
            path = self.root / id / '42'
            path.mkdir(parents=True)
            (path / 'mod.info').write_text('id=' + id + '\nversion=1.2.3\n')
            (path / 'source.lua').write_text('return true\n')
        self.output = self.root / 'pack.json'

    def create(self):
        return pack.create(self.root, self.output, self.game)

    def validate(self, mods=None):
        return pack.validate(self.output, self.root, self.game, mods or ['First', 'Second'])

    def test_lock_preserves_actual_order_versions_settings_and_exact_sources(self):
        value = self.create()
        self.assertEqual(['First', 'Second'], [row['id'] for row in value['mods']])
        self.assertEqual(['1', '2'], value['workshop_ids'])
        self.assertEqual(['1.2.3', '1.2.3'], [row['version'] for row in value['mods']])
        self.assertEqual(str(self.root / 'First'), self.validate()['First'])
        with self.assertRaises(FileExistsError):
            self.create()

    def test_missing_mod_blocks_lock_without_output(self):
        self.ini.write_text('Mods=Missing\n')
        with self.assertRaisesRegex(ValueError, 'Missing'):
            self.create()
        self.assertFalse(self.output.exists())

    def test_lock_output_cannot_mutate_its_selected_source(self):
        alias = self.root / 'source-alias'
        alias.symlink_to(self.root / 'First', target_is_directory=True)
        for destination in (self.root / 'First/pack.json', alias / 'nested/pack.json'):
            with self.subTest(destination=destination):
                self.output = destination
                with self.assertRaisesRegex(ValueError, 'outside selected mod sources'):
                    self.create()
                self.assertFalse(destination.exists())
                self.assertFalse((self.root / 'First/nested').exists())
        self.assertEqual((self.root / 'First/42/source.lua').read_text(), 'return true\n')

    def test_linked_inputs_are_rejected_when_creating_and_validating_locks(self):
        outside = self.root / 'external'
        outside.mkdir()
        (outside / 'source.lua').write_text('external content')
        self.create()
        for target in (outside, outside / 'source.lua', outside / 'missing'):
            with self.subTest(target=target):
                link = self.root / 'First/42/linked'
                link.symlink_to(target, target_is_directory=target == outside)
                try:
                    with self.assertRaisesRegex(ValueError, 'symlinks are unsupported'):
                        self.validate()
                    fresh = self.root / 'fresh-lock.json'
                    with self.assertRaisesRegex(ValueError, 'symlinks are unsupported'):
                        pack.create(self.root, fresh, self.game)
                    self.assertFalse(fresh.exists())
                finally:
                    link.unlink()
        self.assertEqual((outside / 'source.lua').read_text(), 'external content')
        self.validate()

    def test_common_only_b42_metadata_precedes_root_b41_id_and_version(self):
        root = self.root / 'First'
        shutil.rmtree(root / '42')
        (root / 'common').mkdir()
        (root / 'common/mod.info').write_text('id=First\nmodversion=1.1.5\n')
        (root / 'mod.info').write_text('id=LegacyFirst\nversion=1.0.5\n')
        value = self.create()
        self.assertEqual('First', value['mods'][0]['id'])
        self.assertEqual('1.1.5', value['mods'][0]['version'])
        self.assertEqual(str(root), self.validate()['First'])
        self.assertFalse((root / '42.0').exists())

    def test_numeric_layer_metadata_keeps_precedence_over_common_and_root(self):
        root = self.root / 'First'
        (root / 'common').mkdir()
        (root / 'common/mod.info').write_text('id=OlderCommonFirst\nversion=0.5\n')
        (root / 'mod.info').write_text('id=LegacyFirst\nversion=0.1\n')
        value = self.create()
        self.assertEqual('1.2.3', value['mods'][0]['version'])

    def test_added_removed_and_changed_mod_files_invalidate_lock(self):
        self.create()
        path = self.root / 'First/42/source.lua'
        for change in ('add', 'remove', 'modify'):
            original = path.read_bytes()
            extra = path.parent / 'extra.lua'
            if change == 'add': extra.write_text('extra')
            elif change == 'remove': path.unlink()
            else: path.write_text('changed')
            with self.subTest(change=change), self.assertRaisesRegex(ValueError, 'First'):
                self.validate()
            if extra.exists(): extra.unlink()
            path.write_bytes(original)

    def test_mod_order_selected_settings_and_game_drift_are_rejected(self):
        self.create()
        with self.assertRaisesRegex(ValueError, 'ordered'):
            self.validate(['Second', 'First'])
        original = self.ini.read_bytes()
        self.ini.write_text('Mods=Second;First\n')
        with self.assertRaisesRegex(ValueError, 'INI'):
            self.validate()
        self.ini.write_bytes(original)
        (self.game / 'projectzomboid.jar').write_bytes(b'new engine')
        with self.assertRaisesRegex(ValueError, 'Game build'):
            self.validate()

    def test_malformed_lock_is_rejected(self):
        for value in ([], {}, {'schema_version': 1, 'mods': [{'id': '../escape'}]}):
            self.output.write_text(json.dumps(value))
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.validate()

    def test_lock_cannot_claim_a_different_pack_under_the_same_ini_hash(self):
        value = self.create()
        value['selected_settings']['Mods'] = 'First'
        value['mods'] = value['mods'][:1]
        self.output.write_text(json.dumps(value))
        with self.assertRaisesRegex(ValueError, 'actual selected INI'):
            self.validate(['First'])
