"""Cold restart inputs must come from an unchanged, fully stopped seed."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.report import game_inputs

spec = importlib.util.spec_from_file_location('tag_restart', ROOT / 'tests/native_tags/run.py')
tags = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tags)


def state(actor):
    return dict(actor=actor, setup=dict(x=1, y=2, z=0, index=0, owner=actor, battery=11, apple=12,
                beans=13, steak=14, source=15, revision=3, manualCategory='Food'),
                start=dict(x=1, y=2, z=0), original=[], manual=dict(priority=0, LSBox={}, LSBoxItems={}, LSBoxPresets={}))


def restart_log(actor='client1'):
    result = []
    value = state(actor)
    for phase in ('enabled', 'disabled', 'enabled'):
        ids = {}
        for key in ('battery', 'apple', 'beans', 'steak'):
            destination = key == 'battery' or key == 'apple' and phase == 'enabled'
            ids[str(value['setup'][key])] = dict(item=key, source=int(not destination), destination=int(destination))
        result.append('[TAG_RECEIPT] ' + json.dumps(dict(actor=actor, phase=phase, ids=ids, exact=True,
                      originalInventoryUnchanged=True, reconnected=True)))
    for phase in ('restart-before', 'restart-after'):
        result.append('[TAG_RESTART_VERIFIED] ' + json.dumps(dict(actor=actor, phase=phase, revision=3,
                      setup=value['setup'], rule=dict(mode='all', include=['food', 'perishable'], exclude=['meat']))))
    return '\n'.join(result)


class RestartReceipts(unittest.TestCase):
    def test_exact_three_receipts_and_actual_rules(self):
        tags.validate_restart_receipts(restart_log(), 'client1', state('client1'))

    def test_identical_consecutive_receipts_and_rule_retries_allowed(self):
        lines = restart_log().splitlines()
        repeated = [line for line in lines for _ in range(3)]
        tags.validate_restart_receipts('\n'.join(repeated), 'client1', state('client1'))

    def test_differing_consecutive_receipt_or_rule_retry_rejected(self):
        lines = restart_log().splitlines()
        for index, before, after in ((0, '"exact": true', '"exact": false'),
                                     (3, '"revision": 3', '"revision": 4')):
            changed = [*lines[:index + 1], lines[index].replace(before, after), *lines[index + 1:]]
            with self.subTest(index=index), self.assertRaises(AssertionError):
                tags.validate_restart_receipts('\n'.join(changed), 'client1', state('client1'))

    def test_box_object_index_may_relocate_but_other_setup_fields_cannot(self):
        lines = restart_log().splitlines()
        moved = [line.replace('"index": 0', '"index": 5') for line in lines]
        tags.validate_restart_receipts('\n'.join(moved), 'client1', state('client1'))
        for before, after in (('"index": 0', '"index": -1'), ('"index": 0', '"index": 1.5'),
                              ('"index": 0', '"index": true'), ('"x": 1', '"x": 2'),
                              ('"manualCategory": "Food"', '"manualCategory": "Other"')):
            changed = [line.replace(before, after) for line in lines]
            with self.subTest(after=after), self.assertRaises(AssertionError):
                tags.validate_restart_receipts('\n'.join(changed), 'client1', state('client1'))

    def test_missing_reused_or_mutated_receipts_rejected(self):
        valid = restart_log()
        lines = valid.splitlines()
        invalid = [lines[1:], lines[:-1], [lines[0], lines[0], *lines[2:]],
                   [line.replace('"revision": 3', '"revision": 4') for line in lines],
                   [line.replace('"12":', '"99":') for line in lines],
                   [line.replace('"food"', '"electrical"') for line in lines]]
        for candidate in invalid:
            with self.subTest(candidate=candidate), self.assertRaises((AssertionError, KeyError)):
                tags.validate_restart_receipts('\n'.join(candidate), 'client1', state('client1'))


class RestartSeed(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.output = self.root / 'seed'
        self.run = self.output / 'run'
        self.run.mkdir(parents=True)
        for role in tags.ROLES:
            for sub in ('Saves', 'db', 'Server', 'Lua', 'mods'):
                (self.run / role / sub).mkdir(parents=True)
            for sub in ('Saves', 'db', 'Server'):
                (self.run / role / sub / 'owned.txt').write_text('persisted')
            (self.run / role / 'Lua/prepared.txt').write_text('initial')
            (self.run / role / 'mods/product.lua').write_text('product')
            if role != 'server':
                (self.run / role / 'Lua/PZSurvivorToolkit_TagFilters_a.txt').write_text('preset')
                (self.run / role / 'Lua/tag-reconnect.txt').write_text('must not copy')
        selection = dict(schema_version=1, suite='tags', kind='mp', mode='toolkit', tagRestartSeed=True,
                         tagRules=True, cases=tags.CASES, mods=['PZSurvivorToolkit'], ports=[17493,17494], languages=['EN','RU'])
        (self.run/'server/Server/queue-smoke.ini').write_text('DefaultPort=17493\nUDPPort=17494\nMods=PZSurvivorToolkit;ActionQueueTest\n')
        tags.write_json(self.run / 'selection.json', selection)
        game = self.root / 'game'; game.mkdir()
        tags.write_json(self.run / 'runtime.json', dict(server_name='queue-smoke', game=str(game)))
        tags.write_json(self.run / 'game-inputs.json', game_inputs(game))
        tags.write_json(self.run / 'manifest.json', [dict(id='PZSurvivorToolkit', files={'product.lua':'hash'})])
        source = self.output / 'source/product.lua'
        source.parent.mkdir(parents=True);source.write_text('source')
        tags.write_json(self.run / 'source-manifest.json', {str(source):tags.digest(source)})
        tags.write_json(self.run / 'initial-settings.json', {})
        tags.write_json(self.run / 'settings-fingerprint.json', dict(inputs=dict(settings={}),sha256='initial'))
        tags.write_json(self.run / 'execution.json', dict(status='completed', processes={role:dict(exit_code=0) for role in tags.ROLES}))
        tags.write_json(self.output / 'result.json', dict(functional='passed', cases_per_client=16, provenance_verified=True))
        text = 'Saving finish\nShutdown handling finished\n' + '\n'.join('[TAG_RESTART_SEED] '+json.dumps(state(role)) for role in ('client1','client2'))
        (self.run / 'server-launch.log').write_text(text)
        for role in ('client1','client2'):
            (self.run / (role+'-launch.log')).write_text('complete')
        self.seal()

    def tearDown(self):
        self.temp.cleanup()

    def seal(self):
        frozen={p.relative_to(self.run).as_posix():tags.digest(p) for p in self.run.glob('*.json') if p.name!='snapshot-hashes.json'}
        for role in tags.ROLES:
            for sub in ('mods','Lua'):
                frozen.update({p.relative_to(self.run).as_posix():tags.digest(p) for p in (self.run/role/sub).rglob('*') if p.is_file() and p.name!='tag-reconnect.txt'})
        tags.write_json(self.run/'snapshot-hashes.json',frozen)
        tags.seal_seed(self.output)

    def test_accepts_complete_sealed_seed(self):
        seed=tags.validate_seed(self.output)
        self.assertEqual(set(seed['states']),{'client1','client2'})
        self.assertFalse(any('reconnect' in name for name in seed['files']))

    def test_accepts_canonical_parent_alias_but_rejects_seed_symlink(self):
        alias = self.root / 'parent-alias'
        alias.symlink_to(self.root, target_is_directory=True)
        self.assertEqual(tags.validate_seed(alias / 'seed')['output'], self.output)
        direct = self.root / 'seed-alias'
        direct.symlink_to(self.output, target_is_directory=True)
        with self.assertRaisesRegex(AssertionError, 'Symlink'):
            tags.validate_seed(direct)

    def test_rejects_missing_mutated_symlink_and_incomplete_seed(self):
        mutations = [lambda: (self.run/'server/Saves/owned.txt').write_text('changed'),
                     lambda: (self.run/'client1/Lua/PZSurvivorToolkit_TagFilters_a.txt').unlink(),
                     lambda: tags.write_json(self.run/'execution.json',dict(status='running',processes={})),
                     lambda: (self.run/'server-launch.log').write_text('Saving finish'),
                     lambda: (self.run/'server/Saves/link').symlink_to(self.output/'source/product.lua'),
                     lambda: (self.output/'source/product.lua').write_text('changed')]
        for mutate in mutations:
            with self.subTest(mutation=mutate):
                # Fresh state for each independent rejection.
                self.tearDown();self.setUp();mutate()
                with self.assertRaises((AssertionError,FileNotFoundError,KeyError)):
                    tags.validate_seed(self.output)

    def test_restore_copies_owned_inputs_and_reseals_lua(self):
        from queue_checks.report import verify_manifest
        seed=tags.validate_seed(self.output)
        fresh=self.root/'fresh'
        import shutil
        shutil.copytree(self.run,fresh)
        for name in ('execution.json','server-launch.log','client1-launch.log','client2-launch.log','restart-inputs.json'):
            (fresh/name).unlink()
        for role in tags.ROLES:
            for directory in ('Saves','db','Server'):
                shutil.rmtree(fresh/role/directory)
            for path in (fresh/role/'Lua').glob('PZSurvivorToolkit_TagFilters_*.txt'):
                path.unlink()
            reconnect=fresh/role/'Lua/tag-reconnect.txt'
            reconnect.unlink(missing_ok=True)
        frozen=json.loads((fresh/'snapshot-hashes.json').read_text())
        frozen.pop('execution.json',None)
        tags.write_json(fresh/'snapshot-hashes.json',frozen)
        tags.restore_seed(seed,fresh)
        record=json.loads((fresh/'restart-inputs.json').read_text())
        self.assertEqual(record['files'],seed['files'])
        self.assertEqual((fresh/'client1/Lua/PZSurvivorToolkit_TagFilters_a.txt').read_text(),'preset')
        self.assertFalse((fresh/'client1/Lua/tag-reconnect.txt').exists())
        self.assertEqual(verify_manifest(fresh,'snapshot-hashes.json'),[])

    def test_saved_endpoint_and_mod_mismatch(self):
        selection=json.loads((self.run/'selection.json').read_text())
        runtime=dict(server_name='queue-smoke')
        for config in ('DefaultPort=18000\nUDPPort=17494\nMods=PZSurvivorToolkit;ActionQueueTest\n',
                       'DefaultPort=17493\nUDPPort=17494\nMods=Other;ActionQueueTest\n'):
            (self.run/'server/Server/queue-smoke.ini').write_text(config)
            with self.assertRaises(AssertionError):
                tags.validate_saved_endpoint(self.run,selection,runtime)

    def test_restore_rejects_endpoint_or_product_changes(self):
        seed=tags.validate_seed(self.output)
        fresh=self.root/'fresh'
        fresh.mkdir()
        for name in ('selection.json','runtime.json','manifest.json'):
            (fresh/name).write_bytes((self.run/name).read_bytes())
        selection=json.loads((fresh/'selection.json').read_text());selection['ports']=[18000,18001]
        tags.write_json(fresh/'selection.json',selection)
        with self.assertRaisesRegex(AssertionError,'endpoints'):
            tags.restore_seed(seed,fresh)
        selection['ports']=seed['selection']['ports'];tags.write_json(fresh/'selection.json',selection)
        tags.write_json(fresh/'manifest.json',[dict(id='PZSurvivorToolkit',files={'product.lua':'changed'})])
        with self.assertRaisesRegex(AssertionError,'product'):
            tags.restore_seed(seed,fresh)


if __name__=='__main__':
    unittest.main()
