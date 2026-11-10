"""Quartermaster store provenance and exact native distribution evidence."""
import json
import copy
import builtins
import importlib
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
from queue_checks import mod_inputs


def transfer_evidence():
    target = dict(x=12, y=34, z=0)
    phases = ('success', 'partial', 'rejected', 'withdraw', 'custom')
    outcomes = ('PHASE success moved=2 remaining=0 tailRead=true queueObserved=true',
                'PHASE partial moved=1 remaining=1 tailRead=true queueObserved=true',
                'PHASE rejected moved=0 remaining=2 tailRead=false queueObserved=false',
                'PHASE withdraw moved=1 remaining=1 tailRead=true queueObserved=true',
                'CUSTOM protected=3 queueUnchanged=true')
    rows = []
    for index, phase in enumerate(phases, 1):
        common = dict(case='manifest', phase=phase, index=index, token='round-' + str(index), target=target)
        actual = dict(x=12.5, y=34.5, z=0, square=dict(target), currentSquare=dict(target),
                      queued=0, timed=False, moving=False, hasPath=False, deferredX=0, deferredY=0)
        proof = dict(mode='local', target=dict(target), actual=actual, centered=True, centers=1, teleports=1,
                     stableMs=500, quietMs=500, elapsedMs=1001)
        boxes = [dict(target, x=13), dict(target, y=35)]
        for event, extra in [('LAYOUT', dict(boxes=boxes)), ('LOCAL', dict(proof=proof)),
                             ('PREPARED', dict(boxes=boxes)), ('ADMITTED', {})]:
            rows.append('[QM_TRANSFER_PLACEMENT] ' + event + ' ' + json.dumps(dict(common, **extra)))
        rows.append('[QM_TRANSFER] ' + outcomes[index - 1])
    rows.append('[QM_TRANSFER] COMPLETE case=manifest')
    return rows


class QuartermasterTransferPlacement(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.selection = dict(suite=adapter.TRANSFER_SUITE, cases=['manifest'], kind='sp', clients=1)

    def verify(self, rows=None, selection=None):
        rows = transfer_evidence() if rows is None else rows
        (self.root / 'client1-launch.log').write_text('\n'.join(rows) + '\n')
        return adapter.verify(self.root, selection or self.selection, {})['issues']

    def mutate(self, index, change):
        rows = transfer_evidence()
        prefix, raw = rows[index].split(' ', 2)[1:]
        value = json.loads(raw)
        change(value)
        rows[index] = '[QM_TRANSFER_PLACEMENT] ' + prefix + ' ' + json.dumps(value)
        return rows

    def test_requires_every_event_once_in_raw_native_round_order(self):
        rows = transfer_evidence()
        self.assertEqual(self.verify(rows), [])
        for index in range(len(rows)):
            for changed in (rows[:index] + rows[index + 1:], rows[:index] + [rows[index]] + rows[index:]):
                with self.subTest(index=index, changed=changed):
                    self.assertTrue(self.verify(changed))
        for index in range(len(rows) - 1):
            changed = rows.copy()
            changed[index:index + 2] = changed[index:index + 2][::-1]
            with self.subTest(swap=index):
                self.assertTrue(self.verify(changed))
        # Correct independent streams cannot hide a setup, admission or outcome
        # that happened before the corresponding fresh placement.
        grouped = [row for row in rows if row.startswith('[QM_TRANSFER_PLACEMENT]')]
        grouped += [row for row in rows if row.startswith('[QM_TRANSFER]')]
        self.assertTrue(self.verify(grouped))
        self.assertTrue(self.verify([row for row in rows if row.startswith('[QM_TRANSFER]')]))

    def test_strict_epoch_identity_schema_and_target_stability(self):
        changes = [lambda row: row.update(case='other'), lambda row: row.update(phase='other'),
                   lambda row: row.update(index=True), lambda row: row.update(index=1.0),
                   lambda row: row.update(index=0), lambda row: row.update(token=''),
                   lambda row: row.update(token='old epoch'), lambda row: row.update(token=True),
                   lambda row: row.update(extra=True), lambda row: row.pop('token'),
                   lambda row: row['target'].update(x=True), lambda row: row['target'].update(x=12.0),
                   lambda row: row['target'].update(z=1000000), lambda row: row['target'].update(extra=0),
                   lambda row: row.update(target=[])]
        for index in (0, 1, 2, 3):
            for change in changes:
                with self.subTest(index=index, change=change):
                    self.assertTrue(self.verify(self.mutate(index, change)))
        self.assertTrue(self.verify(self.mutate(5, lambda row: row.update(token='round-1'))))
        for index in (1, 2, 3):
            self.assertTrue(self.verify(self.mutate(index, lambda row: row.update(token='different'))))
        # Entire later rounds agreeing with each other still cannot drift from
        # the fixture's original standing tile.
        rows = transfer_evidence()
        for index in range(5, 9):
            prefix, raw = rows[index].split(' ', 2)[1:]
            row = json.loads(raw)
            row['target']['x'] += 1
            rows[index] = '[QM_TRANSFER_PLACEMENT] ' + prefix + ' ' + json.dumps(row)
        self.assertTrue(self.verify(rows))

    def test_boxes_are_exact_physical_east_south_integer_tiles(self):
        changes = [lambda row: row.update(boxes=[]), lambda row: row.update(boxes={}),
                   lambda row: row['boxes'].reverse(), lambda row: row['boxes'].pop(),
                   lambda row: row['boxes'].append(dict(x=13, y=34, z=0)),
                   lambda row: row['boxes'][0].update(x=12), lambda row: row['boxes'][1].update(y=34),
                   lambda row: row['boxes'][0].update(z=1), lambda row: row['boxes'][1].update(z=False),
                   lambda row: row['boxes'][0].update(x=13.0), lambda row: row['boxes'][1].update(extra=0),
                   lambda row: row['boxes'].__setitem__(0, 'east')]
        for index in (0, 2, 20, 22):
            for change in changes:
                with self.subTest(index=index, change=change):
                    self.assertTrue(self.verify(self.mutate(index, change)))

    def test_centered_proof_requires_native_settling_and_local_role(self):
        changes = [lambda p: p.update(mode='replica'), lambda p: p.update(mode='authority'),
                   lambda p: p.update(teleports=0), lambda p: p.update(teleports=2),
                   lambda p: p.update(centers=0), lambda p: p.update(centers=True),
                   lambda p: p.update(centered=False), lambda p: p.pop('centered'),
                   lambda p: p.update(stableMs=499), lambda p: p.update(quietMs=499),
                   lambda p: p.update(elapsedMs=999), lambda p: p.update(elapsedMs=30000),
                   lambda p: p.update(stableMs=True), lambda p: p.update(stableMs=float('nan')),
                   lambda p: p.update(extra=True), lambda p: p['target'].update(x=13),
                   lambda p: p['actual'].update(x=12), lambda p: p['actual'].update(y=34),
                   lambda p: p['actual'].update(z=.5), lambda p: p['actual'].update(x=float('inf')),
                   lambda p: p['actual']['square'].update(y=35),
                   lambda p: p['actual']['currentSquare'].update(x=13),
                   lambda p: p['actual'].update(queued=1), lambda p: p['actual'].update(timed=True),
                   lambda p: p['actual'].update(moving=True), lambda p: p['actual'].update(hasPath=True),
                   lambda p: p['actual'].update(deferredX=.01), lambda p: p['actual'].pop('deferredY')]
        for change in changes:
            with self.subTest(change=change):
                self.assertTrue(self.verify(self.mutate(1, lambda row: change(row['proof']))))
        # A round's elapsed duration is independent of the preceding round's
        # clock. The verifier uses raw chronology instead of comparing clocks.
        self.assertEqual(self.verify(self.mutate(6, lambda row: row['proof'].update(elapsedMs=1000))), [])

    def test_rejects_malformed_unknown_extra_and_foreign_role_evidence(self):
        rows = transfer_evidence()
        for value in ('{}', '[]', 'null', '{"case":"manifest","case":"manifest"}', '{broken'):
            changed = rows.copy()
            changed[0] = '[QM_TRANSFER_PLACEMENT] LAYOUT ' + value
            with self.subTest(value=value):
                self.assertTrue(self.verify(changed))
        for extra in ('[QM_TRANSFER_PLACEMENT] AUTHORITY {}', '[QM_TRANSFER_PLACEMENT] FAIL {}',
                      '[QM_TRANSFER_PLACEMENT]LOCAL {}', '[QM_TRANSFER] FAIL old outcome'):
            self.assertTrue(self.verify(rows + [extra]))
        for change in ({'kind': 'mp'}, {'cases': ['other']}, {'clients': True}, {'clients': 2}):
            self.assertTrue(self.verify(selection=dict(self.selection, **change)))
        for role in ('server', 'client2'):
            log = self.root / (role + '-launch.log')
            for foreign in (rows[0], rows[4], '[QM_TRANSFER_PLACEMENT] AUTHORITY {}'):
                log.write_text(foreign + '\n')
                with self.subTest(role=role, foreign=foreign):
                    self.assertTrue(self.verify())
            log.unlink()


def group_evidence(root):
    """Native receipt fixture; mutations below must fail even with matching client claims."""
    packet = dict(ids=[31, 32, 33, 34, 35], types=['Base.BookCooking1', 'Base.BookCooking1',
                  'Base.BookCooking2', 'Base.BookCooking2', 'Base.BookCooking1'], names=['Cooking I', 'Cooking II'],
                  creator='client1', member=dict(x=18, y=10, z=0, index=1))
    created = dict(cats=[], items={'Cooking I': True, 'Cooking II': True}, presets=[], priority=6, noDuplicates=False,
                   appearance=dict(name='PZST cooking group', icon=dict(kind='item', value='Base.BookCooking1'),
                                   color=dict(r=.25, g=.5, b=.75, a=1)))
    updated = copy.deepcopy(created)
    updated.update(priority=11, appearance=dict(name='PZST shared cooking', icon=dict(kind='item', value='Base.BookCooking2'),
                                              color=dict(r=.75, g=.25, b=.5, a=1)))
    detached = copy.deepcopy(updated)
    detached.update(items={'Cooking I': True}, priority=4,
                    appearance=dict(name='PZST local cooking', icon=dict(kind='item', value='Base.BookCooking2'),
                                    color=dict(r=.5, g=.75, b=.25, a=1)))
    unique = copy.deepcopy(updated)
    unique.update(priority=9, noDuplicates=True)
    blank = dict(cats=[], items=[], presets=[], priority=0, noDuplicates=False, appearance=[])
    first_rule = dict(mode='all', include=['readable'], exclude=['writeable'])
    updated_rule = dict(mode='all', include=['experience', 'readable'], exclude=['writeable'])
    stages = [dict(stage=stage, groupId='group-7', revision=revision, creator='client1', links=['group-7', link],
                   configurations=configs, rules=rules)
              for stage, revision, link, configs, rules in [
                  ('created', 1, False, [created, blank], [first_rule, dict(mode='all', include=[], exclude=[])]),
                  ('joined', 1, 'group-7', [created, created], [first_rule, first_rule]),
                  ('updated', 2, 'group-7', [updated, updated], [updated_rule, updated_rule]),
                  ('detached', 2, False, [updated, detached], [updated_rule, updated_rule]),
                  ('rejoined', 2, 'group-7', [updated, updated], [updated_rule, updated_rule]),
                  ('unique', 3, 'group-7', [unique, unique], [updated_rule, updated_rule])]]
    result = dict(ids=packet['ids'], items=[dict(id=value, fullType=kind, container=dest)
                  for value, kind, dest in zip(packet['ids'], packet['types'], [2, 2, 4, 2, 3])],
                  groupId='group-7', groupRevision=3, memberCount=2, noDuplicates=True, priorities=[9, 5],
                  existingGroupCopy=True, sameBatch=True, differentVolume=True, moved=4, conserved=5)
    def row(event, value):
        return '[QM_DISTRIBUTION] GROUP_' + event + ' ' + json.dumps(value) + '\n'
    client = row('PREPARED', packet) + ''.join(row('LOCAL', stage) for stage in stages)
    client += row('SHOT', dict(name='quartermaster-group-editor', width=520, height=850))
    client += row('TRANSFERS_LOCAL', result) + row('COMPLETE', dict(stages=6, members=2, localDetached=True, groupDuplicates=True))
    server = row('PREPARED_AUTHORITY', packet) + ''.join(row('AUTHORITY', stage) for stage in stages)
    server += row('TRANSFERS_AUTHORITY', result)
    screenshot = root / 'client1/Screenshots/quartermaster-group-editor.png'
    screenshot.parent.mkdir(parents=True, exist_ok=True)
    screenshot.write_bytes(b'\x89PNG\r\n\x1a\n\0\0\0\rIHDR' + (1600).to_bytes(4, 'big')
                           + (900).to_bytes(4, 'big') + b'\0' * 9)
    return client, server


class QuartermasterGroupReceipts(unittest.TestCase):
    def test_group_receipts_require_authority_scope_and_exact_book_effects(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            client, authority = group_evidence(root)
            selection = dict(kind='mp')
            self.assertEqual(len(distribution._groups(root, selection, client, authority, [11, 12])['stages']), 6)
            invalid = []
            rows = authority.splitlines(keepends=True)
            invalid.extend(authority.replace(row, '') for row in rows)
            invalid.extend(authority + row for row in rows)
            invalid += [authority.replace('"revision": 2', '"revision": 1'),
                        authority.replace('"creator": "client1"', '"creator": "client2"'),
                        authority.replace('"links": ["group-7", false]', '"links": ["group-7", "group-7"]'),
                        authority.replace('"name": "PZST shared cooking"', '"name": "old name"'),
                        authority.replace('"priority": 11', '"priority": 6'),
                        authority.replace('"noDuplicates": false', '"noDuplicates": true'),
                        authority.replace('"include": ["experience", "readable"]', '"include": ["readable"]'),
                        authority.replace('"container": 4', '"container": 2'),
                        authority.replace('"conserved": 5', '"conserved": 4')]
            for wrong in invalid:
                with self.subTest(authority=wrong), self.assertRaises((ValueError, KeyError)):
                    distribution._groups(root, selection, client, wrong, [11, 12])
            # A matching client/server claim must still meet the contract.
            for original, replacement in [('"noDuplicates": false', '"noDuplicates": true'),
                                           ('"priority": 11', '"priority": 6'),
                                           ('"container": 4', '"container": 2'),
                                           ('"ids": [31, 32, 33, 34, 35]', '"ids": [31, 32, 33, 34, 34]')]:
                with self.subTest(replacement=replacement), self.assertRaises(ValueError):
                    distribution._groups(root, selection, client.replace(original, replacement),
                                         authority.replace(original, replacement), [11, 12])
            screenshot = root / 'client1/Screenshots/quartermaster-group-editor.png'
            screenshot.unlink()
            with self.assertRaises(OSError):
                distribution._groups(root, selection, client, authority, [11, 12])


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
        self.mod_sources = {name: self.root / 'mods' / name for name in adapter.MODS}
        for name, path in self.mod_sources.items():
            (path / '42').mkdir(parents=True)
            (path / '42/mod.info').write_text('id=' + name + '\n')
        self.write('manifest.json', [{'id': name, 'input_policy': mod_inputs.POLICY,
                                     'files': mod_inputs.hashes(path)} for name, path in self.mod_sources.items()])
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
        self.assertFalse((self.cache / 'mods/ActionQueueTest/42/media/lua/shared/QueueHealthEvents.lua').exists())

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
        self.write('manifest.json', [{'id': name, 'input_policy': mod_inputs.POLICY,
                                     'files': {'unexpected.lua': 'a' * 64}} for name in adapter.MODS])
        with self.assertRaisesRegex(ValueError, 'different mod contents'):
            self.stage()

    def test_reload_ignores_only_git_drift_and_refuses_legacy_manifest_policy(self):
        root = self.mod_sources[adapter.MODS[0]]
        (root / '.git').mkdir()
        (root / '.git/config').write_text('new Git metadata after seed')
        self.stage()
        original = adapter.report.read_json(self.seed / 'manifest.json')
        for policy in (None, 'whole-tree-v1'):
            changed = copy.deepcopy(original)
            changed[0]['input_policy'] = policy
            self.write('manifest.json', changed)
            with self.subTest(policy=policy), self.assertRaisesRegex(ValueError, 'policy differs.*fresh snapshot'):
                self.stage()
        self.write('manifest.json', original)
        (root / '.gitignore').write_text('new retained build configuration')
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
        for relative in ('tests/native_queue/health/shared/QueueHealthEvents.lua',
                         'tests/native_queue/support/QueueEnergyPlacement.lua',
                         'tools/queue_checks/placement.py', 'tools/queue_checks/adapters/quartermaster_placement.py',
                         'tests/test_queue_quartermaster.py', 'tests/test_queue_placement.py'):
            self.assertIn(ROOT / relative, sources)
        self.assertFalse(any(path.is_relative_to(self.seed) for path in sources))
        self.stage()
        self.assertEqual(self.runtime['fixture']['failure_markers'], ['[QM_TRANSFER] FAIL '])
        self.assertEqual((self.cache / 'mods/ActionQueueTest/42/media/lua/shared/QueueHealthEvents.lua').read_bytes(),
                         (ROOT / 'tests/native_queue/health/shared/QueueHealthEvents.lua').read_bytes())

    def test_preset_inputs_do_not_import_the_transfer_only_verifier(self):
        native_import = builtins.__import__

        def scoped_import(name, globals=None, locals=None, fromlist=(), level=0):
            if 'quartermaster_placement' in (fromlist or ()):
                raise AssertionError('preset path imported an undeclared transfer verifier')
            return native_import(name, globals, locals, fromlist, level)

        with patch('builtins.__import__', side_effect=scoped_import):
            importlib.reload(adapter)
            paths = adapter.sources(ROOT, dict(suite=adapter.SUITE, cases=['seed']))
        self.assertFalse(any(path.name == 'quartermaster_placement.py' for path in paths))

    def test_transfer_verifier_requires_ordered_exact_outcomes_and_custom_denial(self):
        self.selection.update(suite=adapter.TRANSFER_SUITE, cases=['manifest'], options={})
        records = transfer_evidence()
        log = self.output / 'client1-launch.log'
        def write(rows): log.write_text('\n'.join(rows) + '\n')
        write(records)
        self.assertEqual(adapter.verify(self.output, self.selection, {})['issues'], [])
        for rows in (records[1:], records + records, records[::-1], records[:3] + records[4:],
                     records[:9] + [records[9].replace('moved=1', 'moved=2')] + records[10:],
                     records[:24] + [records[24].replace('protected=3', 'protected=2')] + records[25:],
                     records + ['[QM_TRANSFER] FAIL source identity changed']):
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
                          ('barricaded-door', ['sp', 'mp'])])
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
        books = dict(ids=[21, 22, 23, 24, 25], types=['Base.BookCarpentry1', 'Base.BookCarpentry1',
                     'Base.BookCarpentry2', 'Base.BookCarpentry2', 'Base.BookCarpentry1'])
        book_result = dict(ids=books['ids'], items=[dict(id=value, fullType=kind, container=dest)
                           for value, kind, dest in zip(books['ids'], books['types'], [2, 2, 3, 2, 3])],
                           noDuplicates=True, fallbackNoDuplicates=False, priorities=[7, 5],
                           existingCopy=True, sameBatch=True, differentVolume=True, moved=4, conserved=5)
        group_client, group_server = group_evidence(self.root)
        text = ('[QM_DISTRIBUTION] PREPARED ' + json.dumps(prepared) + '\n'
                '[QM_DISTRIBUTION] LOCAL ' + json.dumps(result) + '\n'
                '[QM_DISTRIBUTION] AUTHORITY ' + json.dumps(result) + '\n'
                '[QM_DISTRIBUTION] BOOKS_PREPARED ' + json.dumps(books) + '\n'
                '[QM_DISTRIBUTION] BOOKS_LOCAL ' + json.dumps(book_result) + '\n'
                '[QM_DISTRIBUTION] BOOKS_AUTHORITY ' + json.dumps(book_result) + '\n'
                + group_client + group_server +
                '[QM_DISTRIBUTION] COMPLETE moved=2 retained=2 walking=true pickup=true destinations=2 favorite=true\n')
        (self.root / 'client1-launch.log').write_text(text)
        self.assertEqual(distribution.verify(self.root, selection, {})['issues'], [])
        self.assertTrue(distribution.complete(selection, 'client1', text))
        self.assertFalse(distribution.complete(self.selection, 'client1', text))
        server = ('[QM_DISTRIBUTION] AUTHORITY ' + json.dumps(result) + '\n'
                  '[QM_DISTRIBUTION] BOOKS_PREPARED_AUTHORITY ' + json.dumps(books) + '\n'
                  '[QM_DISTRIBUTION] BOOKS_AUTHORITY ' + json.dumps(book_result) + '\n' + group_server)
        (self.root / 'server-launch.log').write_text(server)
        host = dict(selection, kind='mp')
        self.assertEqual(distribution.verify(self.root, host, {})['issues'], [])
        for invalid in (server.replace('"noDuplicates": true', '"noDuplicates": false'),
                        server.replace('"priorities": [7, 5]', '"priorities": [5, 7]'),
                        server.replace('"container": 3', '"container": 2'),
                        server.replace('Base.BookCarpentry2', 'Base.BookCarpentry1'),
                        server.replace('BOOKS_AUTHORITY ', 'BOOKS_MISSING '),
                        server + '[QM_DISTRIBUTION] BOOKS_AUTHORITY ' + json.dumps(book_result) + '\n'):
            with self.subTest(server=invalid):
                (self.root / 'server-launch.log').write_text(invalid)
                self.assertTrue(distribution.verify(self.root, host, {})['issues'])


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
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.selection = dict(suite=distribution.SUITE, cases=['barricaded-door'], kind='sp', mode='toolkit',
                              clients=1, languages=['EN'], mods=distribution.MODS, options={})
        self.prepared = {'ids': [501, 502]}
        self.authority = dict(self.prepared, moved=2, normalDoorOpened=True, barricadedDoorClosed=True,
                              barricadeIntact=True, conserved=True)
        self.result = dict(self.authority, nativeWalking=True, detour=True)

    def record(self, event, value):
        return '[QM_DOOR] ' + event + ' ' + json.dumps(value) + '\n'

    def write(self, kind='sp'):
        events = [('PREPARED', self.prepared), ('RESULT', self.result)]
        if kind == 'sp':
            events.append(('AUTHORITY', self.authority))
        events += [('CLEANUP', {'objects': 15, 'localRemoved': True, 'registryCleared': True}),
                   ('COMPLETE', {'case': 'barricaded-door'})]
        client = ''.join(self.record(*row) for row in events)
        server = self.record('PREPARED', self.prepared) + self.record('AUTHORITY', self.authority) + self.record('CLEANUP', {'objects': 15})
        (self.root / 'client1-launch.log').write_text(client)
        (self.root / 'server-launch.log').write_text(server)
        return client, server

    def test_requires_menu_host_and_keeps_supported_sp(self):
        distribution.validate(self.selection)
        with self.assertRaises(ValueError):
            distribution.validate(dict(self.selection, kind='mp'))
        distribution.validate(dict(self.selection, kind='mp', options={'mp_host': True}))

    def test_requires_detour_intact_barricade_and_exact_item_effects(self):
        self.write()
        self.assertEqual(distribution.verify(self.root, self.selection, {})['issues'], [])
        for key in self.result:
            original = self.result[key]
            self.result[key] = [501, 599] if key == 'ids' else 1 if key == 'moved' else False
            with self.subTest(key=key):
                self.write()
                self.assertTrue(distribution.verify(self.root, self.selection, {})['issues'])
            self.result[key] = original
        client, _ = self.write()
        lines = client.splitlines(keepends=True)
        for bad in ([client.replace(line, '') for line in lines] + [client + line for line in lines]
                    + [''.join(reversed(lines)), client + '[QM_DOOR] FAIL changed door\n']):
            (self.root / 'client1-launch.log').write_text(bad)
            self.assertTrue(distribution.verify(self.root, self.selection, {})['issues'])

    def test_host_requires_independent_matching_authority_and_cleanup(self):
        selection = dict(self.selection, kind='mp', options={'mp_host': True})
        client, server = self.write('mp')
        self.assertEqual(distribution.verify(self.root, selection, {})['issues'], [])
        for key in self.authority:
            wrong = dict(self.authority)
            wrong[key] = [501, 599] if key == 'ids' else 1 if key == 'moved' else False
            (self.root / 'server-launch.log').write_text(
                self.record('PREPARED', self.prepared) + self.record('AUTHORITY', wrong) + self.record('CLEANUP', {'objects': 15}))
            with self.subTest(key=key):
                self.assertTrue(distribution.verify(self.root, selection, {})['issues'])
        for bad in ('', server + server, ''.join(reversed(server.splitlines(keepends=True))),
                    server.replace('"objects": 15', '"objects": 14'), server.splitlines(keepends=True)[0]):
            (self.root / 'server-launch.log').write_text(bad)
            self.assertTrue(distribution.verify(self.root, selection, {})['issues'])
        self.write('mp')
        (self.root / 'client1-launch.log').write_text(client.replace(self.record('CLEANUP', {'objects': 15, 'localRemoved': True, 'registryCleared': True}), ''))
        self.assertTrue(distribution.verify(self.root, selection, {})['issues'])
        for field in ('localRemoved', 'registryCleared'):
            self.write('mp')
            (self.root / 'client1-launch.log').write_text(client.replace('"' + field + '": true', '"' + field + '": false'))
            self.assertTrue(distribution.verify(self.root, selection, {})['issues'])


if __name__ == '__main__':
    unittest.main()
