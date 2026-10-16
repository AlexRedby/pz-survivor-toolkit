import hashlib
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import native, report, worlds


class WorldTemplateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.run = self.root / 'run'
        self.run.mkdir()
        self.game = self.root / 'game'
        self.game.mkdir()
        (self.game / 'projectzomboid.jar').write_bytes(b'owned game build')
        self.template = self.root / 'template'
        self.selection = {'suite': 'health', 'cases': ['nativeStop'], 'kind': 'sp',
                          'mods': ['PZSurvivorToolkit', 'OtherMod'], 'ports': [17343, 17344]}
        self.runtime = {'game': str(self.game), 'server_name': 'queue-smoke',
                        'roles': {'client1': {'cache': str(self.run / 'client1')}}}
        for directory in ('mods', 'Lua'):
            path = self.run / 'client1' / directory
            path.mkdir(parents=True)
            (path / 'frozen.txt').write_text('frozen fixture')
        for name, value in [('selection', self.selection), ('runtime', self.runtime),
                            ('settings-fingerprint', {}), ('source-manifest', {str(self.game / 'projectzomboid.jar'): native.sha256(self.game / 'projectzomboid.jar')}),
                            ('manifest', {}), ('initial-settings', {})]:
            report.write_json(self.run / (name + '.json'), value)
        report.write_json(self.run / 'snapshot-hashes.json', native.hashes(self.run))
        self.execution = {'status': 'completed', 'processes': {'client1': {'pid': 999999, 'exit_code': -15}}}
        report.write_json(self.run / 'execution.json', self.execution)
        for name in ('Saves/Sandbox/owned/map.bin', 'db/players.db'):
            path = self.run / 'client1' / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(('original ' + name).encode())

    def export(self, output=None):
        with patch.object(worlds.os, 'kill', side_effect=ProcessLookupError):
            return worlds.export(self.run, output or self.template)

    def mp_source(self):
        self.selection.update(kind='mp', clients=1, suite='crafting-plans')
        server = self.run / 'server'
        for directory in ('mods', 'Lua', 'Server', 'Saves/Multiplayer/queue-smoke'):
            (server / directory).mkdir(parents=True)
        for directory in ('mods', 'Lua'):
            (server / directory / 'frozen.txt').write_text('frozen server fixture')
        sandbox = server / 'Server/queue-smoke_SandboxVars.lua'
        sandbox.write_text('SandboxVars={VERSION=6,MinutesPerPage=0.02}\n')
        settings = server / 'Server/queue-smoke.ini'
        settings.write_text('Map=Muldraugh\nPVP=false\nDoLuaChecksum=true\nSleepAllowed=true\nSleepNeeded=false\nPublic=false\n')
        (server / 'Saves/Multiplayer/queue-smoke/map.bin').write_bytes(b'owned saved server state')
        self.runtime['roles']['server'] = {'cache': str(server)}
        self.execution['processes']['server'] = {'pid': 999998, 'exit_code': 0}
        report.write_json(self.run / 'selection.json', self.selection)
        report.write_json(self.run / 'runtime.json', self.runtime)
        report.write_json(self.run / 'execution.json', self.execution)
        report.write_json(self.run / 'initial-settings.json', {path.relative_to(self.run).as_posix(): path.read_text() for path in (sandbox, settings)})
        self.refreeze('selection.json', 'runtime.json', 'initial-settings.json',
                      *[path.relative_to(self.run).as_posix() for directory in ('mods', 'Lua', 'Server') for path in (server / directory).rglob('*') if path.is_file()])
        return sandbox

    def refreeze(self, *names):
        frozen = report.read_json(self.run / 'snapshot-hashes.json')
        frozen.update({name: native.sha256(self.run / name) for name in names})
        report.write_json(self.run / 'snapshot-hashes.json', frozen)

    def test_export_restore_copies_only_owned_state_and_preserves_template_and_source(self):
        initial = native.hashes(self.run)
        value = self.export()
        template, value = worlds.validate(self.template, self.selection, self.game)
        sealed = native.hashes(template)
        output = self.root / 'fresh'
        output.mkdir()
        runtime = {'server_name': 'queue-smoke'}
        worlds.restore(template, value, output, runtime)
        self.assertEqual(2, runtime['world_template']['files'])
        self.assertEqual(set(value['files']), set(native.hashes(output)) - {'world-template.json'})
        restored = output / 'client1/Saves/Sandbox/owned/map.bin'
        restored.write_bytes(b'new run progress')
        self.assertEqual(initial, native.hashes(self.run))
        self.assertEqual(sealed, native.hashes(template))
        self.assertEqual(self.selection['mods'], value['mods'])
        self.assertIsNone(value['sandbox_sha256'])
        self.assertIsNone(value['server_settings'])
        worlds.verify_settings(value, output, runtime)

    def test_sp_template_requires_same_suite_and_allows_selected_case_subset(self):
        self.selection['cases'] = ['nativeStop', 'bandageApply']
        report.write_json(self.run / 'selection.json', self.selection)
        self.refreeze('selection.json')
        self.export()
        selected = dict(self.selection, cases=['bandageApply'])
        worlds.validate(self.template, selected, self.game)
        with self.assertRaisesRegex(ValueError, 'different suite'):
            worlds.validate(self.template, dict(selected, suite='item-tags', cases=['scenes']), self.game)

    def test_mp_requires_authoritative_server_world_at_export_and_restore(self):
        self.mp_source()
        server_saves = self.run / 'server/Saves'
        shutil.rmtree(server_saves)
        with self.assertRaisesRegex(ValueError, 'authoritative world'):
            self.export()
        self.assertFalse(self.template.exists())
        wrong = server_saves / 'Multiplayer/another-server/map.bin'
        wrong.parent.mkdir(parents=True)
        wrong.write_bytes(b'other server world')
        with self.assertRaisesRegex(ValueError, 'authoritative world'):
            self.export()
        owned = server_saves / 'Multiplayer/queue-smoke/map.bin'
        owned.parent.mkdir(parents=True)
        owned.write_bytes(b'owned server world')
        value = self.export()
        value['files'] = {name: digest for name, digest in value['files'].items() if not name.startswith('server/Saves/')}
        for operation in (lambda: worlds.restore(self.template, value, self.root / 'output', self.runtime),
                          lambda: worlds._manifest(value)):
            with self.assertRaisesRegex(ValueError, 'authoritative world'):
                operation()

    def test_mp_cross_suite_reuse_requires_effective_sandbox_bytes_to_match(self):
        sandbox = self.mp_source()
        value = self.export()
        self.assertEqual(native.sha256(sandbox), value['sandbox_sha256'])
        selected = dict(self.selection, suite='animal-trailer', cases=['timer-shared'])
        worlds.validate(self.template, selected, self.game)
        before = native.hashes(self.run), native.hashes(self.template)
        output = self.root / 'fresh-mp'
        target = output / 'server/Server/queue-smoke_SandboxVars.lua'
        target.parent.mkdir(parents=True)
        target.write_bytes(sandbox.read_bytes())
        (target.parent / 'queue-smoke.ini').write_bytes((sandbox.parent / 'queue-smoke.ini').read_bytes())
        worlds.verify_settings(value, output, self.runtime)
        for text in ('SandboxVars={VERSION=6,MinutesPerPage=2.0}\n',
                     'SandboxVars={VERSION=6,MinutesPerPage=0.020}\n'):
            target.write_text(text)
            with self.subTest(text=text), self.assertRaisesRegex(ValueError, 'sandbox settings differ'):
                worlds.verify_settings(value, output, self.runtime)
        target.unlink()
        with self.assertRaisesRegex(ValueError, 'sandbox settings differ'):
            worlds.verify_settings(value, output, self.runtime)
        self.assertEqual(before, (native.hashes(self.run), native.hashes(self.template)))

    def test_mp_template_requires_matching_effective_map_pvp_checksum_and_sleep_flags(self):
        sandbox = self.mp_source()
        value = self.export()
        self.assertEqual({'Map': 'Muldraugh', 'PVP': 'false', 'DoLuaChecksum': 'true',
                          'SleepAllowed': 'true', 'SleepNeeded': 'false'}, value['server_settings'])
        output = self.root / 'fresh-mp'
        target = output / 'server/Server/queue-smoke.ini'
        target.parent.mkdir(parents=True)
        (target.parent / sandbox.name).write_bytes(sandbox.read_bytes())
        original = (sandbox.parent / target.name).read_text()
        target.write_text(original)
        worlds.verify_settings(value, output, self.runtime)
        for before, after in (('Map=Muldraugh', 'Map=Rosewood'), ('PVP=false', 'PVP=true'),
                              ('DoLuaChecksum=true', 'DoLuaChecksum=false'), ('SleepAllowed=true', 'SleepAllowed=false'),
                              ('SleepNeeded=false', 'SleepNeeded=true')):
            target.write_text(original.replace(before, after))
            with self.subTest(setting=before), self.assertRaisesRegex(ValueError, 'server settings differ'):
                worlds.verify_settings(value, output, self.runtime)
        target.write_text(original.replace('Public=false', 'Public=true'))
        worlds.verify_settings(value, output, self.runtime)
        for broken in (original.replace('SleepNeeded=false\n', ''), original + 'Map=Rosewood\n',
                       original.replace('SleepNeeded=false', 'SleepNeeded=1')):
            target.write_text(broken)
            with self.subTest(broken=broken), self.assertRaisesRegex(ValueError, 'server settings'):
                worlds.verify_settings(value, output, self.runtime)

    def test_mp_export_requires_pinned_original_server_ini(self):
        self.mp_source()
        path = 'server/Server/queue-smoke.ini'
        original = report.read_json(self.run / 'initial-settings.json')
        for settings in ({name: text for name, text in original.items() if name != path},):
            report.write_json(self.run / 'initial-settings.json', settings)
            self.refreeze('initial-settings.json')
            with self.subTest(settings=settings), self.assertRaisesRegex(ValueError, 'initial server settings'):
                self.export()
            self.assertFalse(self.template.exists())

    def test_mp_export_requires_original_pinned_sandbox_settings(self):
        sandbox = self.mp_source()
        initial = self.run / 'initial-settings.json'
        for settings in ({},):
            report.write_json(initial, settings)
            self.refreeze('initial-settings.json')
            with self.subTest(settings=settings), self.assertRaisesRegex(ValueError, 'initial sandbox settings'):
                self.export()
            self.assertFalse(self.template.exists())

    def test_mp_export_uses_sealed_initial_settings_after_engine_rewrites(self):
        sandbox = self.mp_source()
        initial = self.run / 'initial-settings.json'
        expected = report.read_json(initial)
        # Server files are mutable outputs, as in native.prepare, not frozen inputs.
        frozen = report.read_json(self.run / 'snapshot-hashes.json')
        for path in expected:
            frozen.pop(path, None)
            (self.run / path).write_text('engine rewritten settings\n')
        report.write_json(self.run / 'snapshot-hashes.json', frozen)
        value = self.export()
        self.assertEqual(value['sandbox_sha256'], hashlib.sha256(expected[sandbox.relative_to(self.run).as_posix()].encode()).hexdigest())
        self.assertEqual(value['server_settings']['SleepAllowed'], 'true')

    def test_template_requires_explicit_sandbox_metadata(self):
        value = self.export()
        for key in ('sandbox_sha256', 'server_settings'):
            altered = dict(value)
            del altered[key]
            report.write_json(self.template / 'world.json', altered)
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'sandbox hash|server settings'):
                worlds.validate(self.template, self.selection, self.game)

    def test_export_refuses_game_updated_since_the_source_run(self):
        before = native.hashes(self.run)
        (self.game / 'projectzomboid.jar').write_bytes(b'updated installed game build')
        with self.assertRaisesRegex(ValueError, 'game build differs from its prepared snapshot'):
            self.export()
        self.assertFalse(self.template.exists())
        self.assertEqual(before, native.hashes(self.run))

    def test_modified_extra_and_removed_template_files_are_rejected(self):
        value = self.export()
        name = next(iter(value['files']))
        path = self.template / 'state' / name
        original = path.read_bytes()
        path.write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'changed'):
            worlds.validate(self.template, self.selection, self.game)
        path.write_bytes(original)
        extra = path.parent / 'unexpected.bin'
        extra.write_bytes(b'extra')
        with self.assertRaisesRegex(ValueError, 'unexpected'):
            worlds.validate(self.template, self.selection, self.game)
        extra.unlink()
        path.unlink()
        with self.assertRaisesRegex(ValueError, 'changed'):
            worlds.validate(self.template, self.selection, self.game)

    def test_ordered_mods_ports_game_and_roles_must_match(self):
        self.export()
        variants = [dict(self.selection, mods=list(reversed(self.selection['mods']))),
                    dict(self.selection, ports=list(reversed(self.selection['ports']))),
                    dict(self.selection, kind='mp', clients=1),
                    dict(self.selection, kind='mp', clients=2)]
        for selected in variants:
            with self.subTest(selection=selected), self.assertRaises(ValueError):
                worlds.validate(self.template, selected, self.game)
        (self.game / 'projectzomboid.jar').write_bytes(b'other build')
        with self.assertRaisesRegex(ValueError, 'game build'):
            worlds.validate(self.template, self.selection, self.game)

    def test_manifest_traversal_absolute_wrong_role_and_invalid_hash_are_rejected(self):
        value = self.export()
        digest = next(iter(value['files'].values()))
        for name in ('../outside.bin', '/tmp/outside.bin', 'client1/Saves/../../../outside.bin',
                     'client2/Saves/map.bin', 'client1/mods/file', 'client1/Saves/./map.bin'):
            altered = dict(value, files={name: digest})
            report.write_json(self.template / 'world.json', altered)
            with self.subTest(name=name), self.assertRaises(ValueError):
                worlds.validate(self.template, self.selection, self.game)
        for files in ({'client1/Saves/map.bin': None}, {'client1/Saves/map.bin': 'not-a-hash'}):
            report.write_json(self.template / 'world.json', dict(value, files=files))
            with self.subTest(files=files), self.assertRaises(ValueError):
                worlds.validate(self.template, self.selection, self.game)
        self.assertFalse((self.root / 'outside.bin').exists())

    def test_malformed_manifest_and_source_metadata_raise_value_error(self):
        value = self.export()
        for altered in ([], None, {}, dict(value, roles='client1'), dict(value, source_cases=[{}]),
                        dict(value, ports=[[], 17344]), dict(value, source_run=None),
                        dict(value, server_name=[]), dict(value, files=[]), dict(value, schema_version=True)):
            report.write_json(self.template / 'world.json', altered)
            with self.subTest(manifest=altered), self.assertRaises(ValueError):
                worlds.validate(self.template, self.selection, self.game)
        for filename in ('selection', 'runtime', 'execution'):
            path = self.run / (filename + '.json')
            original = path.read_bytes()
            for malformed in ([], None, {}):
                report.write_json(path, malformed)
                with self.subTest(source=filename, malformed=malformed), self.assertRaises(ValueError):
                    self.export(self.root / ('bad-' + filename))
            path.write_bytes(original)

    def test_live_pid_unstopped_run_and_external_cache_are_refused(self):
        self.execution['processes']['client1']['pid'] = os.getpid()
        report.write_json(self.run / 'execution.json', self.execution)
        with self.assertRaisesRegex(ValueError, 'still alive'):
            worlds.export(self.run, self.template)
        self.execution['processes']['client1']['exit_code'] = None
        report.write_json(self.run / 'execution.json', self.execution)
        with self.assertRaisesRegex(ValueError, 'unstopped'):
            self.export()
        report.write_json(self.run / 'execution.json', {'status': 'failed'})
        with self.assertRaisesRegex(ValueError, 'completed'):
            self.export()
        self.runtime['roles']['client1']['cache'] = str(self.root / 'player-save')
        report.write_json(self.run / 'runtime.json', self.runtime)
        with self.assertRaisesRegex(ValueError, 'disposable'):
            self.export()

    def test_export_requires_unchanged_frozen_inputs_and_fresh_external_output(self):
        with self.assertRaisesRegex(ValueError, 'fresh directory'):
            self.export(self.run / 'nested-template')
        output = self.root / 'already-exists'
        output.mkdir()
        with self.assertRaisesRegex(ValueError, 'fresh directory'):
            self.export(output)
        (self.run / 'client1/mods/frozen.txt').write_text('modified fixture')
        with self.assertRaisesRegex(ValueError, 'snapshot changed'):
            self.export()
        self.assertFalse(self.template.exists())

    def test_source_root_and_save_directory_symlinks_are_refused(self):
        linked = self.root / 'linked-run'
        linked.symlink_to(self.run, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'symlink'):
            worlds.export(linked, self.template)
        saves = self.run / 'client1/Saves'
        actual = self.root / 'actual-saves'
        saves.rename(actual)
        saves.symlink_to(actual, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'symlink'):
            self.export()

    def test_template_root_state_and_nested_symlinks_are_refused(self):
        value = self.export()
        linked = self.root / 'linked-template'
        linked.symlink_to(self.template, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'symlink'):
            worlds.validate(linked, self.selection, self.game)
        state = self.template / 'state'
        actual = self.root / 'actual-state'
        state.rename(actual)
        state.symlink_to(actual, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'symlink'):
            worlds.validate(self.template, self.selection, self.game)
        state.unlink()
        actual.rename(state)
        path = state / next(iter(value['files']))
        path.unlink()
        path.symlink_to(self.game / 'projectzomboid.jar')
        with self.assertRaisesRegex(ValueError, 'symlink'):
            worlds.validate(self.template, self.selection, self.game)

    def test_export_detects_added_removed_and_modified_source_files_while_copying(self):
        copyfile = shutil.copyfile
        source = self.run / 'client1/Saves/Sandbox/owned/map.bin'
        original = source.read_bytes()
        extra = source.parent / 'late.bin'
        for change in ('added', 'removed', 'modified'):
            changed = False
            def copy_and_change(src, dst):
                nonlocal changed
                result = copyfile(src, dst)
                if Path(src) == source and not changed:
                    changed = True
                    if change == 'added':
                        extra.write_bytes(b'late save')
                    elif change == 'removed':
                        source.unlink()
                    else:
                        source.write_bytes(b'modified save')
                return result
            output = self.root / ('raced-' + change)
            with self.subTest(change=change), patch.object(worlds.shutil, 'copyfile', side_effect=copy_and_change), self.assertRaisesRegex(ValueError, 'changed during export'):
                self.export(output)
            self.assertFalse((output / 'world.json').exists())
            source.write_bytes(original)
            extra.unlink(missing_ok=True)

    def test_restore_refuses_existing_state_wrong_server_and_symlink_destination(self):
        value = self.export()
        output = self.root / 'fresh'
        output.mkdir()
        with self.assertRaisesRegex(ValueError, 'server name'):
            worlds.restore(self.template, value, output, {'server_name': 'other'})
        (output / 'client1').symlink_to(self.run / 'client1', target_is_directory=True)
        before = native.hashes(self.run)
        with self.assertRaisesRegex(ValueError, 'overwrite'):
            worlds.restore(self.template, value, output, self.runtime)
        self.assertEqual(before, native.hashes(self.run))
        (output / 'client1').unlink()
        worlds.restore(self.template, value, output, self.runtime)
        with self.assertRaisesRegex(ValueError, 'overwrite'):
            worlds.restore(self.template, value, output, self.runtime)

    def test_restore_rechecks_template_file_set_after_copy(self):
        value = self.export()
        output = self.root / 'fresh'
        output.mkdir()
        sealed = native.hashes(self.template)
        copyfile = shutil.copyfile
        extra = self.template / 'state/client1/Saves/late.bin'
        def copy_and_change(src, dst):
            result = copyfile(src, dst)
            extra.write_bytes(b'late')
            return result
        with patch.object(worlds.shutil, 'copyfile', side_effect=copy_and_change), self.assertRaisesRegex(ValueError, 'changed while copying'):
            worlds.restore(self.template, value, output, self.runtime)
        self.assertFalse((output / 'world-template.json').exists())
        self.assertNotIn('world_template', self.runtime)
        extra.unlink()
        self.assertEqual(sealed, native.hashes(self.template))


if __name__ == '__main__':
    unittest.main()
