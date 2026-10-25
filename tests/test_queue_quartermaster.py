"""Quartermaster store provenance and exact native distribution evidence."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import quartermaster as adapter
from queue_checks.adapters import quartermaster_distribution as distribution
from queue_checks.adapters import quartermaster_crafting as crafting


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
        self.text = ('[QM_PRESET] RULE index=1 gen=123 rev=2 creator=s00410042 mode=all resolved=true\n'
                     '[QM_PRESET] RULE index=2 gen=456 rev=2 creator=nil mode=any resolved=true\n')
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

    def test_owned_toolkit_provides_quartermaster_without_external_mod(self):
        self.assertEqual(adapter.MODS, ['PZSurvivorToolkit'])
        for owner in (distribution, crafting):
            self.assertNotIn('organizedCategories_core', owner.MODS)
        backpack = (ROOT / 'tests/native_queue/quartermaster-distribution/client/ZZQuartermasterBackpack.lua').read_text()
        self.assertIn("require 'PZSurvivorToolkit/ItemRetentionUI'", backpack)
        self.assertIn('Retention.setRetained(0,{items[5]},true)', backpack)
        self.assertIn('Retention.isRetained(items[5])', backpack)
        self.assertNotIn('OrganizedCategories', backpack)

    def test_reload_seals_and_copies_only_known_global_store_files(self):
        adapter.validate(self.selection)
        (self.seed / 'client1/Lua/unrelated.txt').write_text('unrelated user data')
        for name in adapter.LEGACY_STORES:
            (self.seed / 'client1/Lua' / name).write_text('untouched legacy ' + name)
        sources = adapter.sources(ROOT, self.selection)
        for name in adapter.STORES + adapter.LEGACY_STORES:
            self.assertIn(self.seed / 'client1/Lua' / name, sources)
        self.assertNotIn(self.seed / 'client1/Lua/unrelated.txt', sources)
        self.stage()
        self.assertEqual(sorted(path.name for path in (self.cache / 'Lua').iterdir()),
                         sorted(adapter.STORES + adapter.LEGACY_STORES))
        for name in adapter.STORES + adapter.LEGACY_STORES:
            self.assertEqual((self.cache / 'Lua' / name).read_bytes(), (self.seed / 'client1/Lua' / name).read_bytes())
        self.assertEqual((self.cache / 'mods/ActionQueueTest/42/media/lua/client/ZZStartup.lua').read_bytes(),
                         (ROOT / 'tests/native_queue/startup/client/ZZStartup.lua').read_bytes())

    def test_reload_accepts_either_single_snapshot_slot_and_optional_legacy(self):
        for slot in adapter.STORES:
            for name in adapter.STORES:
                (self.seed / 'client1/Lua' / name).unlink(missing_ok=True)
            (self.seed / 'client1/Lua' / slot).write_text('one valid slot')
            for name in adapter.LEGACY_STORES:
                (self.seed / 'client1/Lua' / name).write_text('untouched legacy')
            with self.subTest(slot=slot):
                sources = adapter.sources(ROOT, self.selection)
                self.assertIn(self.seed / 'client1/Lua' / slot, sources)
                absent = next(name for name in adapter.STORES if name != slot)
                self.assertNotIn(self.seed / 'client1/Lua' / absent, sources)
                self.stage()
                self.assertEqual((self.cache / 'Lua' / slot).read_text(), 'one valid slot')
                (self.output / 'client1-launch.log').write_text(self.text + '[QM_PRESET] COMPLETE case=reload\n')
                self.assertEqual(adapter.verify(self.output, self.selection, {})['issues'], [])
                for path in (self.cache / 'Lua').iterdir():
                    path.unlink()

    def test_reload_refuses_legacy_only_seed(self):
        for name in adapter.STORES:
            (self.seed / 'client1/Lua' / name).unlink()
        for name in adapter.LEGACY_STORES:
            (self.seed / 'client1/Lua' / name).write_text('old native store')
        with self.assertRaisesRegex(ValueError, 'at least one snapshot'):
            adapter.sources(ROOT, self.selection)

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
        store.unlink()
        legacy = self.seed / 'client1/Lua' / adapter.LEGACY_STORES[0]
        legacy.symlink_to(self.seed / 'missing')
        with self.assertRaisesRegex(ValueError, 'regular global store'):
            adapter._seed(self.selection)

    def test_reload_refuses_mismatched_mod_contents(self):
        self.write('manifest.json', [{'id': name, 'files': {'unexpected.lua': 'changed'}} for name in adapter.MODS])
        with self.assertRaisesRegex(ValueError, 'different mod contents'):
            self.stage()

    def test_verify_requires_both_rules_same_generations_revisions_creators_and_unchanged_files(self):
        self.stage()
        log = self.output / 'client1-launch.log'
        log.write_text(self.text + '[QM_PRESET] COMPLETE case=reload\n')
        self.assertEqual(adapter.verify(self.output, self.selection, {})['issues'], [])
        for wrong in (self.text.replace('gen=123', 'gen=789'), self.text.replace('rev=2', 'rev=3'),
                      self.text.replace('creator=s00410042', 'creator=s00410043'),
                      self.text.replace('creator=nil', 'creator=s'),
                      self.text.replace('creator=s00410042', 'creator=s041'),
                      self.text.splitlines()[0] + '\n', self.text + self.text):
            with self.subTest(wrong=wrong):
                log.write_text(wrong + '[QM_PRESET] COMPLETE case=reload\n')
                self.assertTrue(adapter.verify(self.output, self.selection, {})['issues'])
        log.write_text(self.text + '[QM_PRESET] COMPLETE case=reload\n')
        (self.cache / 'Lua' / adapter.STORES[1]).write_text('rewritten instead of loaded')
        self.assertIn('changed the persisted', adapter.verify(self.output, self.selection, {})['issues'][0])

    def test_verify_rejects_new_stores_or_legacy_rewrites(self):
        legacy = self.seed / 'client1/Lua' / adapter.LEGACY_STORES[0]
        legacy.write_text('untouched legacy')
        self.stage()
        (self.output / 'client1-launch.log').write_text(self.text + '[QM_PRESET] COMPLETE case=reload\n')
        copied = self.cache / 'Lua' / legacy.name
        copied.write_text('rewritten legacy')
        self.assertIn('changed the persisted', adapter.verify(self.output, self.selection, {})['issues'][0])
        copied.write_bytes(legacy.read_bytes())
        (self.cache / 'Lua' / adapter.LEGACY_STORES[1]).write_text('unexpected legacy')
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

    def test_transfer_modes_use_their_own_fixture_and_failure_marker(self):
        self.selection.update(suite=adapter.TRANSFER_SUITE, cases=['manifest'], options={})
        for mode in ('native', 'toolkit'):
            adapter.validate(dict(self.selection, mode=mode))
        sources = adapter.sources(ROOT, self.selection)
        self.assertIn(ROOT / 'tests/native_queue/quartermaster-transfers/client/ZZQuartermasterTransfers.lua', sources)
        self.assertFalse(any(path.is_relative_to(self.seed) for path in sources))
        self.stage()
        self.assertEqual(self.runtime['fixture']['failure_markers'], ['[QM_TRANSFER] FAIL '])

    def test_transfer_verifier_requires_ordered_exact_outcomes_and_custom_denial(self):
        self.selection.update(suite=adapter.TRANSFER_SUITE, cases=['manifest'], options={})
        records = ['PHASE success moved=2 remaining=0 tailRead=true queueObserved=true',
                   'PHASE partial moved=1 remaining=1 tailRead=true queueObserved=true',
                   'PHASE rejected moved=0 remaining=2 tailRead=false queueObserved=false',
                   'PHASE withdraw moved=1 remaining=1 tailRead=true queueObserved=true',
                    'CUSTOM protected=3 queueUnchanged=true', 'COMPLETE case=manifest']
        log = self.output / 'client1-launch.log'
        def write(rows): log.write_text(''.join('[QM_TRANSFER] ' + row + '\n' for row in rows))
        write(records)
        self.assertEqual(adapter.verify(self.output, self.selection, {})['issues'], [])
        for rows in (records[1:], records + records, records[::-1], records[:3] + records[4:],
                     [records[0], records[1].replace('moved=1', 'moved=2'), *records[2:]],
                     records + ['FAIL source identity changed']):
            with self.subTest(rows=rows):
                write(rows)
                self.assertTrue(adapter.verify(self.output, self.selection, {})['issues'])


class QuartermasterCrafting(unittest.TestCase):
    def test_shared_fixture_dependencies_are_sealed_and_staged_for_each_role(self):
        selection = dict(suite=crafting.SUITE, cases=['vanilla', 'neat'], kind='mp', mode='toolkit',
                         clients=1, languages=['EN'], mods=crafting.MODS, options={})
        sources = crafting.sources(ROOT, selection)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            runtime = {'roles': {role: {'cache': str(output / role)} for role in ('client1', 'server')}}
            crafting.stage(ROOT, output, None, None, selection, {}, runtime)
            for name in ('QueueCraftUIFixture.lua', 'QueueCookEvolvedFixture.lua'):
                source = ROOT / 'tests/native_queue/craft-ui/shared' / name
                with self.subTest(module=name):
                    self.assertIn(source, sources, 'shared fixture dependency is missing from the sealed inputs')
                    for role in runtime['roles']:
                        staged = output / role / 'mods/ActionQueueTest/42/media/lua/shared' / name
                        self.assertTrue(staged.is_file(), 'shared fixture dependency is missing for ' + role)
                        self.assertEqual(source.read_bytes(), staged.read_bytes())


class QuartermasterSupplyUnits(unittest.TestCase):
    def test_standalone_case_requires_exact_native_uses_and_authority(self):
        selection = dict(suite=crafting.SUITE, cases=['uses'], kind='mp', mode='toolkit',
                         clients=1, languages=['EN'], mods=crafting.MODS, options={'mp_host': True})
        crafting.validate(selection)
        for change in ({'cases': ['vanilla', 'uses']}, {'options': {}}):
            with self.assertRaises(ValueError):
                crafting.validate(dict(selection, **change))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            client, server = '', ''
            for index, case in enumerate(('full', 'carried', 'partial'), 1):
                ids = list(range(index*10, index*10 + (3 if case == 'partial' else 2)))
                prep = dict(index=index, case=case, ids=ids, source=dict(x=1, y=2, z=0, index=1))
                expected = [(0, 0), (0, 0), (2, 4)] if case == 'partial' else [(2 if case == 'full' else 1, 2), (2, 4)]
                receipt = dict(index=index, case=case, items=[dict(id=item, container=loc, uses=uses)
                               for item, (loc, uses) in zip(ids, expected)], outputIds=[index*10+5], outputs=1, consumedUses=2)
                for event, value in [('PREPARED', prep), ('VERIFIED', receipt)]:
                    server += '[QM_USES] ' + event + ' ' + json.dumps(value) + '\n'
                client += '[QM_USES] RESULT ' + json.dumps(dict(index=index, case=case, walked=case!='carried',
                           picked=case!='carried', crafted=True, returned=case=='full', receipt=receipt)) + '\n'
            server += '[QM_USES] CLEANUP\n'
            client += '[QM_USES] COMPLETE\n'
            (root / 'client1-launch.log').write_text(client)
            authority = root / 'server-launch.log'
            authority.write_text(server)
            report = crafting.verify(root, selection, {})
            self.assertEqual(report['issues'], [])
            self.assertIsInstance(report['outcomes'][0]['outcome'], dict)
            for invalid in (server.replace('"uses": 2', '"uses": 1'), server.replace('"consumedUses": 2', '"consumedUses": 1'),
                            server + server, server.replace('[QM_USES] CLEANUP', '[QM_OTHER] CLEANUP')):
                authority.write_text(invalid)
                self.assertTrue(crafting.verify(root, selection, {})['issues'])


class QuartermasterBackpack(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.selection = dict(suite=distribution.SUITE, cases=['backpack'], kind='sp', mode='toolkit',
                              clients=1, languages=['EN'], mods=distribution.MODS, options={})
        self.prepared = {'ids': [101, 102, 103, 104, 105, 106]}
        self.result = dict(self.prepared, moved=1, retained=4, backpackWorn=True, stuckRetained=True, menuDispatched=True,
                           toolbarVisible=True, sourceBag=True, transfer=True, rejectedDestinationSkipped=True)

    def write(self, prepared=None, result=None, complete='[QM_BACKPACK] COMPLETE\n'):
        text = ('[QM_BACKPACK] PREPARED ' + json.dumps(self.prepared if prepared is None else prepared) + '\n'
                '[QM_BACKPACK] RESULT ' + json.dumps(self.result if result is None else result) + '\n' + complete)
        (self.root / 'client1-launch.log').write_text(text)
        return text

    def test_backpack_case_is_separate_fresh_sp_with_existing_required_mods(self):
        cases = distribution.definitions()[distribution.SUITE]['cases']
        self.assertEqual([(case['id'], case['kinds']) for case in cases],
                         [('sort', ['sp', 'mp']), ('backpack', ['sp']), ('deposit', ['sp', 'mp']), ('batch', ['mp']),
                          ('barricaded-door', ['sp'])])
        distribution.validate(self.selection)
        for changes in ({'kind': 'mp'}, {'cases': ['sort', 'backpack']}, {'mode': 'native'},
                        {'languages': ['RU']}, {'clients': 2}, {'mods': distribution.MODS[:-1]},
                        {'options': {'world_template': 'existing'}}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                distribution.validate(dict(self.selection, **changes))
        for kind in ('sp', 'mp'):
            distribution.validate(dict(self.selection, cases=['sort'], kind=kind))
            distribution.validate(dict(self.selection, cases=['deposit'], kind=kind, options={'mp_host': kind == 'mp'}))
        with self.assertRaises(ValueError):
            distribution.validate(dict(self.selection, cases=['deposit'], kind='mp'))
        distribution.validate(dict(self.selection, cases=['batch'], kind='mp', options={'mp_host': True}))
        with self.assertRaises(ValueError):
            distribution.validate(dict(self.selection, cases=['batch'], kind='sp', options={'mp_host': True}))

    def test_backpack_requires_exact_result_and_case_specific_completion(self):
        text = self.write()
        report = distribution.verify(self.root, self.selection, {})
        self.assertEqual(report['issues'], [])
        self.assertEqual(report['evidence']['receipt'], self.result)
        self.assertEqual(report['outcomes'][0]['case'], 'backpack')
        self.assertTrue(distribution.complete(self.selection, 'client1', text))
        self.assertFalse(distribution.complete(self.selection, 'server', text))
        self.assertFalse(distribution.complete(dict(self.selection, cases=['sort']), 'client1', text))
        for key in self.result:
            wrong = dict(self.result)
            wrong[key] = [101, 102, 103, 104, 105, 999] if key == 'ids' else 2 if key == 'moved' else 5 if key == 'retained' else False
            with self.subTest(key=key):
                self.write(result=wrong)
                self.assertTrue(distribution.verify(self.root, self.selection, {})['issues'])
        for wrong in (dict(self.result, moved=True), dict(self.result, transfer=1),
                      dict(self.result, ids=[True, 102, 103, 104, 105, 106]), dict(self.result, extra=True)):
            self.write(result=wrong)
            self.assertTrue(distribution.verify(self.root, self.selection, {})['issues'])

    def test_backpack_rejects_invalid_identities_duplicate_records_and_missing_gate(self):
        for ids in ([101, 102, 103, 104, 105], [101, 102, 103, 104, 105, 105], [True, 102, 103, 104, 105, 106],
                    [101.0, 102, 103, 104, 105, 106], '101,102,103,104,105,106'):
            with self.subTest(ids=ids):
                self.write(prepared={'ids': ids}, result=dict(self.result, ids=ids))
                self.assertIn('six unique integers', distribution.verify(self.root, self.selection, {})['issues'][0])
        original = self.write()
        rows = original.splitlines(keepends=True)
        invalid = [original.replace(row, '') for row in rows]
        invalid += [original + row for row in rows]
        invalid += [''.join(reversed(rows)), original.replace('[QM_BACKPACK] COMPLETE', '[QM_DISTRIBUTION] COMPLETE'),
                    original.replace('[QM_BACKPACK] COMPLETE', '[QM_BACKPACK] COMPLETE extra'),
                    original + '[QM_BACKPACK] FAIL observed mismatch\n']
        for text in invalid:
            with self.subTest(text=text):
                (self.root / 'client1-launch.log').write_text(text)
                self.assertTrue(distribution.verify(self.root, self.selection, {})['issues'])

    def test_backpack_requires_explicit_native_rejected_destination_gate(self):
        missing = dict(self.result)
        del missing['rejectedDestinationSkipped']
        for result in (missing, dict(self.result, rejectedDestinationSkipped=False),
                       dict(self.result, rejectedDestinationSkipped=1)):
            with self.subTest(result=result):
                self.write(result=result)
                self.assertTrue(distribution.verify(self.root, self.selection, {})['issues'])

    def test_sort_receipt_and_completion_remain_unchanged(self):
        selection = dict(self.selection, cases=['sort'])
        prepared = {'ids': [11, 12, 13, 14]}
        result = {'items': [{'id': value, 'container': dest} for value, dest in zip(prepared['ids'], [2, 3, 1, 1])],
                  'moved': 2, 'retained': 2, 'favorite': True}
        text = ('[QM_DISTRIBUTION] PREPARED ' + json.dumps(prepared) + '\n'
                '[QM_DISTRIBUTION] LOCAL ' + json.dumps(result) + '\n'
                '[QM_DISTRIBUTION] AUTHORITY ' + json.dumps(result) + '\n'
                '[QM_DISTRIBUTION] COMPLETE moved=2 retained=2 walking=true pickup=true destinations=2 favorite=true\n')
        (self.root / 'client1-launch.log').write_text(text)
        self.assertEqual(distribution.verify(self.root, selection, {})['issues'], [])
        self.assertTrue(distribution.complete(selection, 'client1', text))
        self.assertFalse(distribution.complete(self.selection, 'client1', text))


class QuartermasterBatch(unittest.TestCase):
    def test_whole_rejection_then_native_acceptance_requires_matching_authority(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            selection = dict(cases=['batch'], kind='mp')
            packet = dict(kind='batch', ids=[1, 2, 3, 4], ballastId=5,
                          boxes=[dict(x=x, y=y, z=0, index=1) for x, y in [(10, 10), (12, 10), (11, 11)]])
            effects = [dict(kind='batch', stage=stage, ids=packet['ids'], ballastId=5,
                            destinations=destinations, sourceCount=count, limitedCapacity=1,
                            limitedWeight=weight, tailWeight=.0625, conserved=5)
                       for stage, destinations, count, weight in [('rejected', [1, 1, 1, 3], 3, .875),
                                                                  ('accepted', [2, 2, 1, 3], 1, 1)]]
            def record(event, value):
                return '[QM_BATCH] ' + event + ' ' + json.dumps(value) + '\n'
            client = record('PREPARED', packet)
            server = '[PZToolkitJavaPatches] itemBatchAdmission=true,\n' + record('PREPARED', packet)
            for index, effect in enumerate(effects, 1):
                client += record(effect['stage'].upper(), dict(result=effect, merged=True, transactionId=index))
                server += record(effect['stage'].upper(), effect)
            client += record('CLEANUP', dict(objects=3)) + record('COMPLETE',
                       dict(case='batch', rejected=True, accepted=True, manual=True, continued=True))
            server += record('CLEANUP', dict(objects=3))
            (root / 'client1-launch.log').write_text(client)
            (root / 'server-launch.log').write_text(server)
            self.assertEqual(distribution.verify(root, selection, {})['issues'], [])
            for invalid in [server.replace('true,', 'false,'), server.replace('"limitedWeight": 1', '"limitedWeight": 1.0625'),
                            server.replace('"destinations": [1, 1, 1, 3]', '"destinations": [2, 1, 1, 3]')]:
                (root / 'server-launch.log').write_text(invalid)
                self.assertTrue(distribution.verify(root, selection, {})['issues'])


class QuartermasterBarricadedDoor(unittest.TestCase):
    def test_requires_detour_intact_barricade_and_exact_item_effects(self):
        selection = dict(suite=distribution.SUITE, cases=['barricaded-door'], kind='sp', mode='toolkit',
                         clients=1, languages=['EN'], mods=distribution.MODS, options={})
        distribution.validate(selection)
        with self.assertRaises(ValueError):
            distribution.validate(dict(selection, kind='mp'))
        prepared = {'ids': [501, 502]}
        result = dict(prepared, moved=2, nativeWalking=True, detour=True, normalDoorOpened=True,
                      barricadedDoorClosed=True, barricadeIntact=True, conserved=True)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def verify(value, suffix='[QM_DOOR] COMPLETE\n'):
                text = ('[QM_DOOR] PREPARED ' + json.dumps(prepared) + '\n'
                        '[QM_DOOR] RESULT ' + json.dumps(value) + '\n' + suffix)
                (root / 'client1-launch.log').write_text(text)
                return distribution.verify(root, selection, {})
            self.assertEqual(verify(result)['issues'], [])
            for key in result:
                wrong = dict(result)
                wrong[key] = [501, 599] if key == 'ids' else 1 if key == 'moved' else False
                with self.subTest(key=key):
                    self.assertTrue(verify(wrong)['issues'])
            for suffix in ('', '[QM_DOOR] COMPLETE\n[QM_DOOR] COMPLETE\n',
                           '[QM_BACKPACK] COMPLETE\n', '[QM_DOOR] COMPLETE extra\n',
                           '[QM_DOOR] COMPLETE\n[QM_DOOR] FAIL changed door\n'):
                with self.subTest(suffix=suffix):
                    self.assertTrue(verify(result, suffix)['issues'])


if __name__ == '__main__':
    unittest.main()
