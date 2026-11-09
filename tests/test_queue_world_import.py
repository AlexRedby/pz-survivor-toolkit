"""Imports publish separately sealed provenance; ordinary template guards stay exact."""
from copy import deepcopy
import importlib.util
import io
import json
from pathlib import Path
import shutil
import sqlite3
import unittest
from unittest.mock import patch

from tests import test_queue_worlds as fixtures
from queue_checks import native, report, world_import, worlds

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('world_import_cli', ROOT / 'tools/check_action_queue.py')
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)


class WorldImportTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.WorldTemplateTests(methodName='runTest')
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.root
        self.template = self.fixture.template
        self.output = self.root / 'imported'

    def create(self, *, removals=('OtherMod',), **options):
        return world_import.create(self.template, self.output, self.fixture.game, removals, **options)

    def host(self):
        self.fixture.host_source()
        base = self.fixture.export()
        source = self.root / 'external-world'
        source.mkdir()
        (source / 'map.bin').write_bytes(b'external world with original object IDs')
        (source / 'global_mod_data.bin').write_bytes(b'opaque original world modData')
        with sqlite3.connect(source / 'players.db') as connection:
            connection.execute('CREATE TABLE networkPlayers (id INTEGER PRIMARY KEY NOT NULL,world TEXT,username TEXT,'
                'playerIndex INTEGER,name STRING,steamid STRING,x FLOAT,y FLOAT,z FLOAT,worldversion INTEGER,'
                'data BLOB,isDead BOOLEAN,splitUsername STRING)')
            connection.execute('INSERT INTO networkPlayers VALUES (7,?,?,?,?,?,?,?,?,?,?,?,?)',
                ('source-world', 'original-player', 0, 'Original', 'steam', 101., 202., 0., 240,
                 b'original opaque inventory and character', 0, 'Original'))
        settings = self.root / 'source.ini'
        settings.write_text('Mods=' + ';'.join(base['mods']) + '\n' + ''.join(k + '=' + v + '\n' for k, v in base['server_settings'].items()))
        sandbox = self.root / 'source_SandboxVars.lua'
        sandbox.write_bytes((self.fixture.run / 'server/Server/queue-smoke_SandboxVars.lua').read_bytes())
        return base, dict(external_world=source, server_settings=settings, sandbox=sandbox, players={'client1': 7})

    def test_explicit_removal_keeps_order_bytes_and_independent_origin(self):
        original = self.fixture.export()
        source_hashes = native.hashes(self.template)
        value = self.create()
        self.assertEqual(2, value['schema_version'])
        self.assertNotIn('source_run', value)
        self.assertEqual(['PZSurvivorToolkit'], value['mods'])
        self.assertEqual(original['files'], value['files'])
        self.assertEqual(['OtherMod'], value['origin']['removed_mods'])
        self.assertEqual(original, value['origin']['base_manifest'])
        self.assertEqual(source_hashes, native.hashes(self.template))
        selection = dict(self.fixture.selection, mods=value['mods'])
        worlds.validate(self.output, selection, self.fixture.game)
        restored = self.root / 'restored'
        runtime = {'server_name': 'queue-smoke'}
        worlds.restore(self.output, value, restored, runtime)
        self.assertEqual(value, {k: v for k, v in report.read_json(restored / 'world-template.json').items() if k != 'template'})
        with self.assertRaisesRegex(ValueError, 'ordered mods'):
            worlds.validate(self.output, self.fixture.selection, self.fixture.game)
        with self.assertRaisesRegex(ValueError, 'imported world provenance'):
            worlds.completed_source_run(value)

    def test_import_remains_usable_after_original_template_is_deleted(self):
        self.fixture.export()
        value = self.create()
        shutil.rmtree(self.template)
        selection = dict(self.fixture.selection, mods=value['mods'])
        worlds.validate(self.output, selection, self.fixture.game)
        worlds.restore(self.output, value, self.root / 'restored', self.fixture.runtime)

    def test_undeclared_reorder_addition_context_and_state_changes_are_rejected(self):
        self.fixture.export()
        value = self.create()
        variants = [dict(value, mods=['OtherMod', 'PZSurvivorToolkit']), dict(value, mods=['AddedMod']),
                    dict(value, ports=[17000, 17001]), dict(value, game_sha256='f' * 64),
                    dict(value, source_run=str(self.fixture.run)), dict(value, source_suite='other')]
        corrupt = deepcopy(value); corrupt['origin']['removed_mods'] = []; variants.append(corrupt)
        corrupt = deepcopy(value); corrupt['origin']['base_manifest']['mods'] = ['PZSurvivorToolkit']; variants.append(corrupt)
        corrupt = deepcopy(value); corrupt['files'][next(iter(corrupt['files']))] = 'f' * 64; variants.append(corrupt)
        for altered in variants:
            with self.subTest(altered=altered), self.assertRaises(ValueError): worlds._manifest(altered)

    def test_duplicate_unknown_and_all_mod_removals_fail_before_copy(self):
        self.fixture.export()
        for removals in (['OtherMod', 'OtherMod'], ['Absent'], ['PZSurvivorToolkit', 'OtherMod']):
            with self.subTest(removals=removals), self.assertRaises(ValueError): self.create(removals=removals)
            self.assertFalse(self.output.exists())

    def test_imports_always_start_from_original_template_and_cannot_claim_seed_provenance(self):
        self.fixture.export()
        self.create()
        with self.assertRaisesRegex(ValueError, 'original exported'):
            world_import.create(self.output, self.root / 'second', self.fixture.game)

    def test_source_template_corruption_and_build_mismatch_remain_fatal(self):
        self.fixture.export()
        source = self.template / 'state' / next(iter(report.read_json(self.template / 'world.json')['files']))
        original = source.read_bytes(); source.write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'changed'): self.create()
        source.write_bytes(original)
        (self.fixture.game / 'projectzomboid.jar').write_bytes(b'new game')
        with self.assertRaisesRegex(ValueError, 'different game build'): self.create()
        self.assertFalse(self.output.exists())

    def test_overlay_preserves_world_rows_blob_auth_and_source_bytes(self):
        base, options = self.host()
        before = native.hashes(options['external_world']); template_before = native.hashes(self.template)
        with patch.object(world_import, 'verify_player_api', return_value=world_import.PLAYER_DB_SHA256):
            value = self.create(**options)
        self.assertEqual(before, native.hashes(options['external_world']))
        self.assertEqual(template_before, native.hashes(self.template))
        prefix = 'client1/Saves/Multiplayer/queue-smoke/'
        state = self.output / 'state'
        self.assertEqual(b'external world with original object IDs', (state / prefix / 'map.bin').read_bytes())
        self.assertEqual(b'opaque original world modData', (state / prefix / 'global_mod_data.bin').read_bytes())
        auth = 'client1/db/queue-smoke.db'
        self.assertEqual(base['files'][auth], native.sha256(state / auth))
        self.assertFalse(any(name.startswith('server/Saves/') for name in value['files']))
        with sqlite3.connect(state / prefix / 'players.db') as connection:
            rows = connection.execute('SELECT id,world,username,playerIndex,data FROM networkPlayers ORDER BY id').fetchall()
        self.assertEqual((7, 'source-world', 'original-player', 0), rows[0][:4])
        self.assertEqual(('queue-smoke', 'client1', 0), rows[1][1:4])
        self.assertEqual(rows[0][4], rows[1][4])
        self.assertFalse(value['origin']['external']['source_game_build_verified'])
        selected = dict(self.fixture.selection, mods=value['mods'])
        worlds.validate(self.output, selected, self.fixture.game)
        worlds.restore(self.output, value, self.root / 'restored', self.fixture.runtime)
        for key in ('mods', 'ports'):
            invalid = dict(selected, **{key: list(reversed(selected[key])) if len(selected[key]) > 1 else ['unselected']})
            with self.assertRaises(ValueError): worlds.validate(self.output, invalid, self.fixture.game)

    def test_overlay_requires_matching_original_mods_and_exact_settings(self):
        base, options = self.host()
        settings = options['server_settings']; original = settings.read_text()
        for text in (original.replace('PZSurvivorToolkit;OtherMod', 'OtherMod;PZSurvivorToolkit'),
                     original.replace('PZSurvivorToolkit;OtherMod', 'PZSurvivorToolkit'),
                     original + 'Mods=PZSurvivorToolkit;OtherMod\n', original.replace('PVP=false', 'PVP=true')):
            settings.write_text(text)
            with self.assertRaises(ValueError): self.create(**options)
            self.assertFalse(self.output.exists())
        settings.write_text(original)
        options['sandbox'].write_bytes(b'different sandbox')
        with self.assertRaisesRegex(ValueError, 'sandbox differs'): self.create(**options)
        self.assertFalse(self.output.exists())

    def test_raw_layout_and_identity_prerequisites_are_explicit(self):
        self.fixture.export()
        with self.assertRaisesRegex(ValueError, 'menu-Host'):
            self.create(external_world=self.root)
        with self.assertRaisesRegex(ValueError, 'require --external-world'):
            self.create(players={'client1': 7})
        base, options = self.host_after_reset()
        for changes in ({'server_settings': None}, {'sandbox': None}, {'players': None}, {'players': {'client2': 7}}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.create(**dict(options, **changes))
            self.assertFalse(self.output.exists())

    def host_after_reset(self):
        # This test already exported its SP source; replace only its test fixture template.
        shutil.rmtree(self.template)
        return self.host()

    def test_path_overlap_symlinks_journal_and_special_files_are_rejected(self):
        base, options = self.host()
        for output in (self.template / 'nested', options['external_world'] / 'nested', self.fixture.game / 'nested'):
            with self.subTest(output=output), self.assertRaises(ValueError):
                world_import.create(self.template, output, self.fixture.game, ['OtherMod'], **options)
            self.assertFalse(output.exists())
        link = self.root / 'linked'; link.symlink_to(options['external_world'], target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'symlink'): self.create(**dict(options, external_world=link))
        journal = options['external_world'] / 'players.db-wal'; journal.write_bytes(b'live SQLite journal')
        with self.assertRaisesRegex(ValueError, 'journal'): self.create(**options)
        journal.unlink()
        (options['external_world'] / 'escape').symlink_to(self.fixture.game / 'projectzomboid.jar')
        with self.assertRaisesRegex(ValueError, 'symlink'): self.create(**options)
        self.assertFalse(self.output.exists())

    def test_mutation_during_copy_never_publishes_usable_manifest(self):
        self.fixture.export()
        copy = world_import.shutil.copyfile
        def changing(source, target):
            result = copy(source, target)
            Path(source).write_bytes(b'concurrent modification')
            return result
        with patch.object(world_import.shutil, 'copyfile', side_effect=changing), self.assertRaisesRegex(ValueError, 'changed'):
            self.create()
        self.assertFalse((self.output / 'world.json').exists())

    def test_external_mutation_and_non_player_corruption_cannot_be_published(self):
        _, options = self.host()
        copy = world_import.shutil.copyfile
        def changing(source, target):
            result = copy(source, target)
            if Path(source).parent == options['external_world']:
                Path(source).write_bytes(b'concurrent modification')
            return result
        with patch.object(world_import, 'verify_player_api', return_value=world_import.PLAYER_DB_SHA256), \
                patch.object(world_import.shutil, 'copyfile', side_effect=changing), self.assertRaises(ValueError):
            self.create(**options)
        self.assertFalse((self.output / 'world.json').exists())


class ImportCommandTests(unittest.TestCase):
    def test_import_command_dispatches_explicit_options_without_loading_catalog_or_game(self):
        with patch.object(cli.world_import, 'create', return_value={'files': {'one': 'hash'}}) as create, \
                patch.object(cli, 'load_catalog', side_effect=AssertionError('Import must not load suites')), \
                patch.object(cli.runner, 'run', side_effect=AssertionError('Import must not launch')), \
                patch('sys.stdout', io.StringIO()):
            result = cli.main(['import-world', '/base', '/output', '--game', '/game', '--remove-mod', 'OldMod',
                '--external-world', '/source', '--server-settings', '/source.ini', '--sandbox', '/sandbox.lua', '--player', 'client1=7'])
        self.assertEqual(0, result)
        create.assert_called_once_with(Path('/base'), Path('/output'), Path('/game'), ['OldMod'],
            external_world=Path('/source'), server_settings=Path('/source.ini'), sandbox=Path('/sandbox.lua'), players={'client1': 7})

    def test_invalid_and_duplicate_player_mappings_never_enter_import(self):
        for arguments in (['client1=0'], ['client3=7'], ['client1=7', 'client1=8'], ['client1=bad'], ['client1=١']):
            with self.subTest(arguments=arguments), patch.object(cli.world_import, 'create') as create, patch('sys.stderr', io.StringIO()):
                args = ['import-world', '/base', '/output', '--game', '/game']
                for item in arguments: args += ['--player', item]
                self.assertEqual(1, cli.main(args))
                create.assert_not_called()


if __name__ == '__main__':
    unittest.main()
