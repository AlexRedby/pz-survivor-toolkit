"""Quartermaster restart cases retain strict provenance and immutable store input."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import quartermaster as adapter


class QuartermasterPresets(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.seed = self.root / 'seed'
        self.output = self.root / 'reload'
        self.selection = dict(suite=adapter.SUITE, cases=['reload'], kind='sp', mode='toolkit',
                              clients=1, languages=['EN'], mods=adapter.MODS, options={'seed_run': str(self.seed)})
        self.cache = self.output / 'client1'
        (self.cache / 'mods/ActionQueueTest/42/media/lua/client').mkdir(parents=True)
        (self.cache / 'Lua').mkdir()
        (self.seed / 'client1/Lua').mkdir(parents=True)
        self.runtime = {'roles': {'client1': {'cache': str(self.cache)}}}
        self.game = self.root / 'game'
        self.initial = dict(self.selection, cases=['seed'], options={})
        self.write('selection.json', self.initial)
        self.write('runtime.json', {'game': str(self.game), 'roles': {'client1': {'cache': str(self.seed / 'client1')}}})
        self.write('manifest.json', [{'id': name, 'files': {}} for name in adapter.MODS])
        self.text = ('[QM_PRESET] RULE index=1 gen=123 mode=all resolved=true\n'
                     '[QM_PRESET] RULE index=2 gen=456 mode=any resolved=true\n')
        (self.seed / 'client1-launch.log').write_text(self.text + '[QM_PRESET] COMPLETE case=seed\n')
        for name in adapter.STORES:
            (self.seed / 'client1/Lua' / name).write_text('native serialized ' + name)
        self.report = {'status': 'passed', 'runtime': {'status': 'clean'},
                       'execution': {'processes': {'client1': {'exit_code': 0, 'pid': 99999999}}}}
        self.audit = patch.object(adapter.report, 'build_report', return_value=self.report).start()
        patch.object(adapter.os, 'kill', side_effect=ProcessLookupError).start()
        self.addCleanup(patch.stopall)

    def write(self, name, value):
        (self.seed / name).write_text(json.dumps(value))

    def stage(self):
        locations = {name: self.root / 'mods' / name for name in adapter.MODS}
        for path in locations.values():
            path.mkdir(parents=True, exist_ok=True)
        adapter.stage(ROOT, self.output, self.game, self.root / 'jdk', self.selection, locations, self.runtime)

    def test_reload_seals_and_copies_only_two_native_global_store_files(self):
        adapter.validate(self.selection)
        (self.seed / 'client1/Lua/unrelated.txt').write_text('unrelated user data')
        sources = adapter.sources(ROOT, self.selection)
        self.assertIn(self.seed / 'client1/Lua' / adapter.STORES[0], sources)
        self.assertNotIn(self.seed / 'client1/Lua/unrelated.txt', sources)
        self.stage()
        self.assertEqual(sorted(path.name for path in (self.cache / 'Lua').iterdir()), sorted(adapter.STORES))
        for name in adapter.STORES:
            self.assertEqual((self.cache / 'Lua' / name).read_bytes(), (self.seed / 'client1/Lua' / name).read_bytes())
        self.assertEqual((self.cache / 'mods/ActionQueueTest/42/media/lua/client/ZZStartup.lua').read_bytes(),
                         (ROOT / 'tests/native_queue/startup/client/ZZStartup.lua').read_bytes())

    def test_reload_refuses_unsafe_or_still_running_seed(self):
        for status, runtime in [('failed', 'clean'), ('needs-review', 'unclassified-errors')]:
            with self.subTest(status=status):
                self.report.update(status=status, runtime={'status': runtime})
                with self.assertRaisesRegex(ValueError, 'fresh successful'):
                    adapter._seed(self.selection)
        self.report.update(status='passed', runtime={'status': 'clean'})
        with patch.object(adapter.os, 'kill', return_value=None):
            with self.assertRaisesRegex(ValueError, 'still alive'):
                adapter._seed(self.selection)
        store = self.seed / 'client1/Lua' / adapter.STORES[0]
        store.unlink()
        store.symlink_to(self.seed / 'selection.json')
        with self.assertRaisesRegex(ValueError, 'regular global store'):
            adapter._seed(self.selection)

    def test_reload_refuses_mismatched_mod_contents(self):
        self.write('manifest.json', [{'id': name, 'files': {'unexpected.lua': 'changed'}} for name in adapter.MODS])
        with self.assertRaisesRegex(ValueError, 'different mod contents'):
            self.stage()

    def test_verify_requires_both_rules_same_generations_and_unchanged_files(self):
        self.stage()
        log = self.output / 'client1-launch.log'
        log.write_text(self.text + '[QM_PRESET] COMPLETE case=reload\n')
        self.assertEqual(adapter.verify(self.output, self.selection, {})['issues'], [])
        for wrong in (self.text.replace('gen=123', 'gen=789'), self.text.splitlines()[0] + '\n', self.text + self.text):
            with self.subTest(wrong=wrong):
                log.write_text(wrong + '[QM_PRESET] COMPLETE case=reload\n')
                self.assertTrue(adapter.verify(self.output, self.selection, {})['issues'])
        log.write_text(self.text + '[QM_PRESET] COMPLETE case=reload\n')
        (self.cache / 'Lua' / adapter.STORES[1]).write_text('rewritten instead of loaded')
        self.assertIn('changed the persisted', adapter.verify(self.output, self.selection, {})['issues'][0])

    def test_validation_requires_two_separate_sp_lifecycles(self):
        for changes in ({'cases': ['seed', 'reload']}, {'kind': 'mp'}, {'mode': 'native'}, {'clients': True}):
            with self.subTest(changes=changes):
                with self.assertRaises(ValueError):
                    adapter.validate(dict(self.selection, **changes))
        for case, options in [('seed', {'seed_run': str(self.seed)}), ('reload', {}), ('reload', {'world_template': 'unused'})]:
            with self.subTest(case=case, options=options):
                with self.assertRaises(ValueError):
                    adapter.validate(dict(self.selection, cases=[case], options=options))


if __name__ == '__main__':
    unittest.main()
