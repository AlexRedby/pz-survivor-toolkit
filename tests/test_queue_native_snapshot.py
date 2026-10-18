"""Snapshot preparation checks without Steam, Java compilation, or a game launch."""
import sys
import json
import os
from pathlib import Path
import shutil
import tempfile
from types import SimpleNamespace
import unittest
import zipfile
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import native, worlds, pack, runner, admission, report


class NativeSnapshotTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        disk = patch.object(admission.shutil, 'disk_usage', return_value=SimpleNamespace(free=100 * 1024**3))
        disk.start()
        self.addCleanup(disk.stop)
        self.root = Path(self.directory.name).resolve()
        state = patch.object(admission, 'STATE', self.root / 'admission-state')
        state.start()
        self.addCleanup(state.stop)
        sample = patch.object(admission.host, 'sample', return_value={'processes': []})
        sample.start()
        self.addCleanup(sample.stop)
        self.project, self.game, self.jdk = [self.root / name for name in ("project", "game", "jdk")]
        for relative in ("projectzomboid.jar", "media/lua/shared/native.lua", "media/scripts/items.txt",
                         "media/lua/shared/Translate/EN/Fixture_EN.txt"):
            self.write(self.game / relative, "native input")
        for name in ('java', 'javac'):
            executable = native.jdk_binary(self.jdk, name)
            self.write(executable, "fake Java executable")
            executable.chmod(0o755)
        if sys.platform == 'win32':
            self.write(self.game / 'jre64/bin/java.exe', 'fake bundled game runtime')
        shutil.copytree(ROOT / "tests/native_queue/support", self.project / "tests/native_queue/support")
        self.write(self.project / "tools/check_action_queue.py", "# queue CLI\n")
        self.write(self.project / "tools/queue_checks/report.py", "# report framework\n")
        self.write(self.project / "tests/native_queue/catalog.json", '{}\n')
        for side in ("client", "server", "shared"):
            self.write(self.project / "tests/native_queue/health" / side / "suite.lua", "return {}\n")
        self.mod(self.project / "Toolkit", "PZSurvivorToolkit")
        self.selection = {"schema_version": 1, "suite": "health", "kind": "sp", "mode": "toolkit",
                          "cases": ["bandageApply"], "mods": ["PZSurvivorToolkit"], "languages": ["EN"],
                          "timeout_seconds": 60, "ports": [17343, 17344], "expected_checks": 3}
        self.compiler = patch.object(native.subprocess, "run", side_effect=self.compile)
        self.compile_mock = self.compiler.start()
        self.addCleanup(self.compiler.stop)

    @staticmethod
    def write(path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def mod(self, path, identifier, layer="42"):
        self.write(path / layer / "mod.info", "name=Test\nid = " + identifier + "\n")
        self.write(path / layer / "media/lua/shared/test.lua", "return 'unchanged mod source'\n")
        return path

    @staticmethod
    def compile(command, **kwargs):
        Path(command[-1]).with_suffix(".class").write_bytes(b"fake class")

    def prepare(self, name="run", **changes):
        selection = dict(self.selection, **changes)
        return native.prepare(self.project, self.root / name, self.game, self.jdk, selection)

    def test_disk_shortage_refuses_before_profile_copy_compile_or_port_reservation(self):
        with patch.object(admission.shutil, 'disk_usage', return_value=SimpleNamespace(free=1)), \
             patch.object(native.shutil, 'copytree') as copy, patch.object(admission, 'allocate_ports') as ports:
            with self.assertRaisesRegex(RuntimeError, 'Insufficient disk space'):
                self.prepare(ports_auto=True)
        self.assertFalse((self.root / 'run').exists())
        copy.assert_not_called()
        ports.assert_not_called()
        self.compile_mock.assert_not_called()

    def test_source_links_fail_before_snapshot_copy_and_compilation(self):
        outside = self.root / 'external'
        self.write(outside / 'linked.lua', 'external source')
        for target in (outside, outside / 'linked.lua', outside / 'missing'):
            with self.subTest(target=target):
                link = self.project / 'Toolkit/42/linked'
                link.symlink_to(target, target_is_directory=target == outside)
                try:
                    with patch.object(native.shutil, 'copytree') as copy:
                        with self.assertRaisesRegex(ValueError, 'symlinks are unsupported'):
                            self.prepare()
                    copy.assert_not_called()
                    self.compile_mock.assert_not_called()
                    self.assertFalse((self.root / 'run').exists())
                finally:
                    link.unlink()
        root_link = self.root / 'linked-mod'
        root_link.symlink_to(self.project / 'Toolkit', target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'symlinks are unsupported'):
            native.hashes(root_link)
        self.assertEqual((outside / 'linked.lua').read_text(), 'external source')

    def test_host_prepares_and_seals_the_actual_shared_server_settings(self):
        shutil.copytree(ROOT / 'tests/native_queue/startup', self.project / 'tests/native_queue/startup')
        root = self.prepare(suite='startup', kind='mp', clients=1, cases=['loaded'], options={'mp_host': True})
        selected = report.read_json(root / 'selection.json')
        runtime = report.read_json(root / 'runtime.json')
        initial = report.read_json(root / 'initial-settings.json')
        self.assertEqual((root / 'server/options.ini').read_bytes().decode('utf-8'), initial['server/options.ini'])
        self.assertEqual(str(root / 'client1'), runtime['host_cache'])
        for name in ('queue-smoke.ini', 'queue-smoke_SandboxVars.lua'):
            self.assertEqual((root / 'server/Server' / name).read_bytes(), (root / 'client1/Server' / name).read_bytes())
        runner._verify_initial_settings(root, selected, runtime)
        actual = root / 'client1/Server/queue-smoke.ini'
        actual.write_text(actual.read_text().replace('VoiceEnable=false', 'VoiceEnable=true'))
        with self.assertRaisesRegex(ValueError, 'changed before launch'):
            runner._verify_initial_settings(root, selected, runtime)

    def test_host_rejects_suites_without_the_common_coop_bootstrap(self):
        with self.assertRaisesRegex(ValueError, 'common startup bootstrap'):
            self.prepare(kind='mp', clients=2, languages=['EN', 'RU'], options={'mp_host': True})

    def test_health_host_seals_common_startup_for_both_peers_and_keeps_legacy_startup_separate(self):
        bootstrap = self.project / 'tests/native_queue/startup/client/ZZStartup.lua'
        self.write(bootstrap, (ROOT / 'tests/native_queue/startup/client/ZZStartup.lua').read_text())
        for hosted in (False, True):
            root = self.prepare('host' if hosted else 'dedicated', kind='mp', clients=2,
                                languages=['EN', 'RU'], options={'mp_host': hosted})
            sources = report.read_json(root / 'source-manifest.json')
            self.assertEqual(str(bootstrap) in sources, hosted)
            runtime = report.read_json(root / 'runtime.json')
            self.assertEqual('host_cache' in runtime, hosted)
            for role in ('server', 'client1', 'client2'):
                lua = root / role / 'mods/ActionQueueTest/42/media/lua'
                copied = lua / 'client/ZZStartup.lua'
                self.assertEqual(copied.exists(), hosted)
                if hosted:
                    self.assertEqual(copied.read_bytes(), bootstrap.read_bytes())
                self.assertTrue((lua / 'client/suite.lua').is_file())
                self.assertTrue((lua / 'server/suite.lua').is_file())
            shared = 'mods/ActionQueueTest/42/media/lua/shared/QueueTestSelection.lua'
            self.assertEqual((root / 'client1' / shared).read_bytes(), (root / 'client2' / shared).read_bytes())
        self.write(bootstrap, '-- changed after snapshot\n')
        self.assertTrue(report.verify_manifest(root, 'source-manifest.json', absolute=True))

    def test_health_host_rejects_patient_disconnect_before_preparing_profiles(self):
        for mode in ('toolkit', 'native'):
            with self.subTest(mode=mode):
                selection = dict(self.selection, kind='mp', clients=2, languages=['EN', 'RU'],
                                 mode=mode, cases=['remoteRemoved'], options={'mp_host': True})
                with self.assertRaisesRegex(ValueError, 'remoteRemoved stops the Host owner'):
                    native.prepare(self.project, self.root / 'run', self.game, self.jdk, selection)
                self.assertFalse((self.root / 'run').exists())
                self.compile_mock.assert_not_called()
                native._validate(dict(selection, options={'mp_host': False}))

    def test_disk_estimate_counts_each_role_and_sparse_file_logical_size(self):
        large = self.project / 'Toolkit/42/sparse.dat'
        with large.open('wb') as stream:
            stream.truncate(8 * 1024**2)
        with patch.object(admission, 'require_disk', wraps=admission.require_disk) as check, \
             patch.object(admission.shutil, 'disk_usage', return_value=SimpleNamespace(free=1)):
            with self.assertRaisesRegex(RuntimeError, 'Insufficient disk space'):
                self.prepare(kind='mp', clients=2, languages=['EN', 'RU'])
        args = check.call_args_list[0].args
        self.assertEqual(args[1], 3)
        self.assertGreater(args[2], 3 * 8 * 1024**2)
        self.assertFalse((self.root / 'run').exists())

    def test_disk_is_rechecked_before_next_role(self):
        with patch.object(admission.shutil, 'disk_usage', side_effect=[SimpleNamespace(free=100 * 1024**3),
                 SimpleNamespace(free=100 * 1024**3), SimpleNamespace(free=1)]):
            with self.assertRaisesRegex(RuntimeError, 'Insufficient disk space'):
                self.prepare(kind='mp', clients=2, languages=['EN', 'RU'])
        self.assertTrue((self.root / 'run/server').is_dir())
        self.assertFalse((self.root / 'run/client1').exists())
        self.compile_mock.assert_not_called()

    def test_disk_is_rechecked_after_fixture_staging(self):
        def stage(project, output, game, jdk, selection, locations, runtime):
            admission.shutil.disk_usage.return_value = SimpleNamespace(free=1)
        adapter = SimpleNamespace(__file__=__file__, validate=lambda _: None, sources=lambda *_: [],
                                  definitions=lambda: {'health': {}}, stage=stage)
        with patch.object(native.adapters, 'get', return_value=adapter):
            with self.assertRaisesRegex(RuntimeError, 'Insufficient disk space'):
                self.prepare()
        self.assertEqual(self.compile_mock.call_count, 1)
        self.assertFalse((self.root / 'run/selection.json').exists())

    def test_font_preload_is_explicit_and_uses_only_selected_snapshot_jar(self):
        cache = self.root / 'owned client'
        selection = dict(self.selection, mods=['ZombieBuddy', 'PZToolkitJavaPatches'],
                         options={'preload_toolkit_fonts': True})
        layer = cache / 'mods/PZToolkitJavaPatches/42'
        metadata = ('id=PZToolkitJavaPatches\njavaPkgName=net.alexredby.pztoolkitjavapatches\n'
                    'javaJarFile=media/java/PZToolkitJavaPatches.jar\n')
        self.write(layer / 'mod.info', metadata)
        jar = layer / 'media/bootstrap/PZToolkitFonts.jar'
        jar.parent.mkdir(parents=True)
        with zipfile.ZipFile(jar, 'w') as archive:
            archive.writestr('META-INF/MANIFEST.MF', 'Manifest-Version: 1.0\r\nZB-Preload: true\r\n\r\n')
        game_argument = self.game if os.name == 'nt' else None
        jar_argument = os.path.relpath(jar, self.game) if game_argument is not None else str(jar)
        self.assertEqual(native.font_preload(cache, selection, game_argument),
                         ',patches_jar=' + jar_argument + ':net.alexredby.pztoolkitbootstrap')
        relative = os.path.relpath(jar, self.game)
        expected = ',patches_jar=' + relative + ':net.alexredby.pztoolkitbootstrap'
        self.assertEqual(native.font_preload(cache, selection, self.game), expected)
        from queue_checks import windows, coop
        agent = windows.loader_agent(self.game, cache, selection)
        self.assertTrue(agent.endswith(expected))
        self.assertEqual(agent.count('-javaagent:'), 1)
        self.assertEqual(agent.split(',patches_jar=')[1].split(':'),
                         [relative, 'net.alexredby.pztoolkitbootstrap'])
        self.assertIn('"' + agent + '"', coop.loader_options(agent))
        self.assertNotIn('patches_jar=', windows.loader_agent(self.game, cache, dict(selection, options={})))
        with patch.object(native.os.path, 'relpath', side_effect=ValueError('different drives')):
            with self.assertRaisesRegex(ValueError, 'same drive'):
                native.font_preload(cache, selection, self.game)
        self.write(layer / 'media/java/PZToolkitJavaPatches.jar', 'ordinary mod jar')
        approvals = native._approvals(cache, ['PZToolkitJavaPatches'])
        self.assertEqual([row['jar_hash'] for row in approvals], [native.sha256(layer / 'media/java/PZToolkitJavaPatches.jar')])
        self.assertEqual(native.font_preload(cache, dict(selection, options={})), '')
        for value in ('true', 1, None):
            with self.assertRaisesRegex(ValueError, 'boolean'):
                native.font_preload(cache, dict(selection, options={'preload_toolkit_fonts': value}))
        with self.assertRaisesRegex(ValueError, 'requires selected'):
            native.font_preload(cache, dict(selection, mods=['ZombieBuddy']))
        self.write(layer / 'mod.info', metadata.replace('pztoolkitjavapatches', 'wrongpackage'))
        with self.assertRaisesRegex(ValueError, 'metadata'):
            native.font_preload(cache, selection, game_argument)
        self.write(layer / 'mod.info', metadata)
        with zipfile.ZipFile(jar, 'w') as archive:
            archive.writestr('META-INF/MANIFEST.MF', 'Manifest-Version: 1.0\n')
        with self.assertRaisesRegex(ValueError, 'manifest'):
            native.font_preload(cache, selection, game_argument)

    def test_fresh_snapshot_pins_sources_configs_mods_and_compiler_output(self):
        output = self.prepare()
        self.assertEqual(self.compile_mock.call_args.args[0][0], str(self.jdk / "bin/javac"))
        source = json.loads((output / "source-manifest.json").read_text())
        original = self.project / "Toolkit/42/media/lua/shared/test.lua"
        self.assertEqual(source[str(original)], native.sha256(original))
        self.assertIn(str(self.game / "media/lua/shared/native.lua"), source)
        self.assertIn(str(self.game / 'media/scripts/items.txt'), source)
        self.assertIn(str(self.game / 'media/lua/shared/Translate/EN/Fixture_EN.txt'), source)
        self.assertIn(str(self.project / "tools/queue_checks/report.py"), source)
        self.assertIn(str(self.project / "tools/check_action_queue.py"), source)
        self.assertIn(str(self.project / "tests/native_queue/catalog.json"), source)
        snapshot = json.loads((output / "snapshot-hashes.json").read_text())
        for relative in ("selection.json", "runtime.json", "initial-settings.json", "game-inputs.json", "client1/classes/ToolkitSmokeLauncher.class",
                         "client1/Lua/queue-expected-mods.txt", "client1/mods/ActionQueueTest/42/media/lua/shared/QueueTestSelection.lua"):
            self.assertEqual(snapshot[relative], native.sha256(output / relative))
        copied = output / "client1/mods/PZSurvivorToolkit/42/media/lua/shared/test.lua"
        self.assertEqual(copied.read_bytes(), original.read_bytes())
        self.assertIn("voiceEnable=false", (output / "client1/options.ini").read_text())
        self.assertNotIn("client1/options.ini", snapshot)
        settings = json.loads((output / "initial-settings.json").read_text())
        self.assertEqual(settings["client1/options.ini"], (output / "client1/options.ini").read_text())
        self.write(original, "changed after preparation")
        self.assertNotEqual(source[str(original)], native.sha256(original))
        self.assertNotEqual(copied.read_bytes(), original.read_bytes())

    def test_live_game_tree_membership_and_contents_are_checked(self):
        output = self.prepare()
        self.assertEqual([], report.verify_manifest(output, 'source-manifest.json', True))
        self.assertEqual([], report.verify_manifest(output, 'snapshot-hashes.json'))
        added = self.game / 'media/lua/shared/added.lua'
        script = self.game / 'media/scripts/items.txt'
        original = script.read_bytes()
        for change, expected in (('add', 'Added native game input'), ('change', 'Changed native game input'),
                                 ('remove', 'Missing native game input')):
            if change == 'add': added.write_text('return true\n')
            elif change == 'change': script.write_text('changed recipe\n')
            else: script.unlink()
            with self.subTest(change=change):
                self.assertTrue(any(expected in issue for issue in
                                    report.verify_manifest(output, 'source-manifest.json', True)))
                with patch.object(runner.sys, 'platform', 'darwin'), patch.object(runner.subprocess, 'Popen') as launch:
                    with self.assertRaisesRegex(ValueError, expected):
                        runner.run(output, resource_wait=0)
                    launch.assert_not_called()
            if added.exists(): added.unlink()
            script.write_bytes(original)
        self.assertEqual([], report.verify_manifest(output, 'source-manifest.json', True))

    def test_native_input_drift_during_prepare_prevents_sealing(self):
        script = self.game / 'media/scripts/items.txt'
        original = script.read_bytes()
        for change in ('add', 'change', 'remove'):
            def drift(command, **kwargs):
                self.compile(command, **kwargs)
                if change == 'add': self.write(self.game / 'media/lua/shared/added.lua', 'return true\n')
                elif change == 'change': script.write_text('changed recipe\n')
                else: script.unlink()
            self.compile_mock.side_effect = drift
            with self.subTest(change=change), self.assertRaisesRegex(RuntimeError, 'Native Lua/script inputs changed'):
                self.prepare(change)
            self.assertFalse((self.root / change / 'snapshot-hashes.json').exists())
            added = self.game / 'media/lua/shared/added.lua'
            if added.exists(): added.unlink()
            script.write_bytes(original)

    def test_native_input_directory_symlinks_are_rejected(self):
        outside = self.root / 'outside'; outside.mkdir()
        self.write(outside / 'script.lua', 'return true\n')
        (self.game / 'media/lua/linked').symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'input symlinks are unsupported'):
            self.prepare()
        self.assertFalse((self.root / 'run').exists())

    def test_source_overrides_reject_invalid_types_and_relative_paths(self):
        for sources in ([], False, {'PZSurvivorToolkit': None}, {'PZSurvivorToolkit': []},
                        {'PZSurvivorToolkit': 1}, {'PZSurvivorToolkit': 'relative/path'}):
            with self.subTest(sources=sources), self.assertRaises(ValueError):
                native._locations(self.project, [], ['PZSurvivorToolkit'], sources)

    def test_empty_common_layer_has_native_animation_directories_only_in_snapshot(self):
        source = self.project / "Toolkit/common"
        self.write(source / ".gitkeep", "")
        output = self.prepare(kind="mp", languages=["EN", "RU"])
        self.assertFalse((source / "media").exists())
        for role in ("server", "client1", "client2"):
            for layer in ("common", "42"):
                for sub in ("AnimSets", "actiongroups"):
                    self.assertTrue((output / role / "mods/PZSurvivorToolkit" / layer / "media" / sub).is_dir())

    def test_missing_common_layer_is_created_only_in_owned_snapshot(self):
        original = self.project / 'Toolkit/common'
        self.assertFalse(original.exists())
        output = self.prepare()
        self.assertFalse(original.exists())
        for sub in ('AnimSets', 'actiongroups'):
            self.assertTrue((output / 'client1/mods/PZSurvivorToolkit/common/media' / sub).is_dir())

    def test_common_only_b42_metadata_and_empty_fallback_leave_b41_files_untouched(self):
        source = self.project / 'Toolkit'
        shutil.rmtree(source / '42')
        self.mod(source, 'PZSurvivorToolkit', layer='common')
        self.write(source / 'mod.info', 'id=LegacyB41Toolkit\nversion=1.0.5\n')
        self.write(source / 'media/lua/client/legacy.lua', 'return "B41 only"\n')
        initial = native.hashes(source)
        output = self.prepare(kind='mp', languages=['EN', 'RU'])
        self.assertEqual(initial, native.hashes(source))
        self.assertFalse((source / '42.0').exists())
        for role in ('server', 'client1', 'client2'):
            target = output / role / 'mods/PZSurvivorToolkit'
            self.assertEqual(initial, native.hashes(target), 'Only empty directories may be added')
            self.assertEqual('LegacyB41Toolkit', native._metadata(target / 'mod.info')['id'])
            for sub in ('AnimSets', 'actiongroups'):
                self.assertTrue((target / '42.0/media' / sub).is_dir())
            self.assertEqual({}, native.hashes(target / '42.0'), 'No mod.info or B41 Lua may shadow common')

    def test_numeric_42_layer_never_gets_a_competing_42_0_fallback(self):
        source = self.project / 'Toolkit'
        self.write(source / 'common/mod.info', 'id=OlderCommonToolkit\n')
        output = self.prepare(kind='mp', languages=['EN', 'RU'])
        for role in ('server', 'client1', 'client2'):
            target = output / role / 'mods/PZSurvivorToolkit'
            self.assertFalse((target / '42.0').exists())
            self.assertEqual('PZSurvivorToolkit', native._metadata(target / '42/mod.info')['id'])

    def test_saved_world_is_copied_into_fresh_profile_with_silent_settings_and_pinned_source(self):
        seed = self.prepare('seed')
        self.write(seed / 'client1/Saves/Sandbox/QueueHealthSP/map.bin', 'prepared world')
        self.write(seed / 'execution.json', json.dumps({'status': 'completed', 'processes': {'client1': {'pid': 999999, 'exit_code': 0}}}))
        template = self.root / 'world'
        with patch.object(worlds.os, 'kill', side_effect=ProcessLookupError):
            worlds.export(seed, template)
        before = native.hashes(template)
        output = self.prepare('from-world', options={'world_template': str(template)})
        restored = output / 'client1/Saves/Sandbox/QueueHealthSP/map.bin'
        self.assertEqual('prepared world', restored.read_text())
        restored.write_text('new run progress')
        with self.assertRaisesRegex(ValueError, 'Restored world changed'):
            runner.run(output)
        self.assertEqual(before, native.hashes(template))
        sources = json.loads((output / 'source-manifest.json').read_text())
        self.assertIn(str(template / 'state/client1/Saves/Sandbox/QueueHealthSP/map.bin'), sources)
        self.assertIn('world-template.json', json.loads((output / 'snapshot-hashes.json').read_text()))
        settings = (output / 'client1/options.ini').read_text()
        for key in ('soundVolume', 'musicVolume', 'jumpScareVolume', 'vehicleEngineVolume'):
            self.assertIn(key + '=0\n', settings)
        self.assertIn('voiceEnable=false\n', settings)

    def test_new_file_in_locked_mod_blocks_prepared_resume(self):
        self.write(self.project / 'SurvivorQoL-selected.ini', 'Mods=PZSurvivorToolkit\nWorkshopItems=\n')
        lock = self.root / 'selected.lock.json'
        pack.create(self.project, lock, self.game)
        output = self.prepare(options={'pack_lock': str(lock)})
        self.write(self.project / 'Toolkit/42/media/lua/shared/unexpected.lua', 'return true\n')
        with self.assertRaisesRegex(ValueError, 'changed locked mod'):
            runner.run(output)

    def locked_pack(self):
        self.write(self.project / 'SurvivorQoL-selected.ini',
                   'Mods=PZSurvivorToolkit\nWorkshopItems=\nMap=Riverside, KY\nPVP=true\n'
                   'DoLuaChecksum=true\nSleepAllowed=true\nSleepNeeded=true\n'
                   'Public=true\nUPnP=true\nVoiceEnable=true\n')
        lock = self.root / 'selected.lock.json'
        pack.create(self.project, lock, self.game)
        return lock

    def stopped_mp_template(self, lock, ports=None):
        seed = self.prepare('mp-seed', kind='mp', languages=['EN', 'RU'], options={'pack_lock': str(lock)}, ports=ports or [17343, 17344])
        self.write(seed / 'server/Saves/Multiplayer/queue-smoke/map.bin', 'saved multiplayer world')
        for role in ('client1', 'client2'):
            self.write(seed / role / 'db/players.db', 'saved ' + role)
        self.write(seed / 'execution.json', json.dumps({'status': 'completed', 'processes': {
            role: {'pid': 999990 + index, 'exit_code': 0}
            for index, role in enumerate(('server', 'client1', 'client2'))}}))
        template = self.root / 'mp-world'
        with patch.object(worlds.os, 'kill', side_effect=ProcessLookupError):
            worlds.export(seed, template)
        return template

    def fixture_adapter(self, stage):
        return SimpleNamespace(__file__=str(self.project / 'tools/queue_checks/report.py'),
                               validate=lambda selection: None, sources=lambda project, selection: [],
                               definitions=lambda: {'health': {}}, stage=stage)

    def test_locked_pack_preserves_critical_mp_settings_and_forces_private_silent_profiles(self):
        lock = self.locked_pack()
        output = self.prepare(kind='mp', languages=['EN', 'RU'], options={'pack_lock': str(lock)})
        server = native._metadata(output / 'server/Server/queue-smoke.ini')
        expected = {'Map': 'Riverside, KY', 'PVP': 'true', 'DoLuaChecksum': 'true',
                    'SleepAllowed': 'true', 'SleepNeeded': 'true',
                    'Public': 'false', 'UPnP': 'false', 'VoiceEnable': 'false'}
        self.assertEqual(expected, {key: server[key] for key in expected})
        initial = json.loads((output / 'initial-settings.json').read_text())
        self.assertEqual(initial['server/Server/queue-smoke.ini'], (output / 'server/Server/queue-smoke.ini').read_text())
        for role in ('server', 'client1', 'client2'):
            settings = native._metadata(output / role / 'options.ini')
            self.assertEqual('false', settings['voiceEnable'])
            for key in ('soundVolume', 'musicVolume', 'jumpScareVolume', 'vehicleEngineVolume'):
                self.assertEqual('0', settings[key])

    def test_native_prepared_mp_world_exports_and_reprepares_after_matching_adapter_sandbox(self):
        lock = self.locked_pack()
        template = self.stopped_mp_template(lock)
        initial = native.hashes(template)

        def stage(project, output, game, jdk, selection, locations, runtime):
            runtime['fixture']['sandbox'] = {'MinutesPerPage': 2.0}

        with patch.object(native.adapters, 'get', return_value=self.fixture_adapter(stage)):
            output = self.prepare('mp-from-world', kind='mp', languages=['EN', 'RU'],
                                  options={'pack_lock': str(lock), 'world_template': str(template)})
        self.assertEqual('saved multiplayer world', (output / 'server/Saves/Multiplayer/queue-smoke/map.bin').read_text())
        for role in ('client1', 'client2'):
            self.assertEqual('saved ' + role, (output / role / 'db/players.db').read_text())
        runtime = json.loads((output / 'runtime.json').read_text())
        worlds.verify_settings(json.loads((template / 'world.json').read_text()), output, runtime)
        self.assertEqual(initial, native.hashes(template))
        self.assertTrue((output / 'snapshot-hashes.json').is_file())

    def test_world_template_keeps_saved_endpoint_when_cli_ports_are_automatic(self):
        lock = self.locked_pack()
        template = self.stopped_mp_template(lock, ports=[17521, 17522])
        with patch.object(admission, 'allocate_ports') as allocate:
            output = self.prepare('auto-world', kind='mp', languages=['EN', 'RU'], ports_auto=True,
                                  options={'pack_lock': str(lock), 'world_template': str(template)})
        allocate.assert_not_called()
        selection = report.read_json(output / 'selection.json')
        self.assertEqual([17521, 17522], selection['ports'])
        self.assertFalse(selection['ports_auto'])
        self.assertEqual('saved client1', (output / 'client1/db/players.db').read_text())

    def test_mp_world_rejects_effective_adapter_sandbox_mismatch_before_sealing(self):
        lock = self.locked_pack()
        template = self.stopped_mp_template(lock)
        initial = native.hashes(template)

        def stage(project, output, game, jdk, selection, locations, runtime):
            runtime['fixture']['sandbox'] = {'MinutesPerPage': 0.02}

        with patch.object(native.adapters, 'get', return_value=self.fixture_adapter(stage)):
            with self.assertRaisesRegex(ValueError, 'sandbox settings differ'):
                self.prepare('mp-wrong-sandbox', kind='mp', languages=['EN', 'RU'],
                             options={'pack_lock': str(lock), 'world_template': str(template)})
        self.assertFalse((self.root / 'mp-wrong-sandbox/snapshot-hashes.json').exists())
        self.assertEqual(initial, native.hashes(template))

    def test_mp_world_rejects_effective_adapter_server_critical_mismatch_before_sealing(self):
        lock = self.locked_pack()
        template = self.stopped_mp_template(lock)
        initial = native.hashes(template)

        def stage(project, output, game, jdk, selection, locations, runtime):
            path = output / 'server/Server/queue-smoke.ini'
            self.assertIn('PVP=true\n', path.read_text())
            path.write_text(path.read_text().replace('PVP=true\n', 'PVP=false\n'))

        with patch.object(native.adapters, 'get', return_value=self.fixture_adapter(stage)):
            with self.assertRaisesRegex(ValueError, 'server settings differ'):
                self.prepare('mp-wrong-server', kind='mp', languages=['EN', 'RU'],
                             options={'pack_lock': str(lock), 'world_template': str(template)})
        self.assertFalse((self.root / 'mp-wrong-server/snapshot-hashes.json').exists())
        self.assertEqual(initial, native.hashes(template))

    def test_refuses_existing_output_without_changing_it(self):
        output = self.prepare()
        self.write(output / "evidence.log", "keep evidence")
        with self.assertRaisesRegex(FileExistsError, "Fresh"):
            self.prepare()
        self.assertEqual((output / "evidence.log").read_text(), "keep evidence")
        self.assertEqual(self.compile_mock.call_count, 1)

    def test_fingerprint_compares_native_and_toolkit_but_detects_settings_and_source_changes(self):
        def fingerprint(path):
            return json.loads((path / "settings-fingerprint.json").read_text())["sha256"]
        baseline = fingerprint(self.prepare("toolkit"))
        self.assertEqual(baseline, fingerprint(self.prepare("native", mode="native")))
        self.assertNotEqual(baseline, fingerprint(self.prepare("ru", languages=["RU"])))
        self.write(self.project / "Toolkit/42/media/lua/shared/test.lua", "changed source")
        self.assertNotEqual(baseline, fingerprint(self.prepare("changed")))

    def test_mp_has_concurrent_roles_languages_ports_and_no_voice(self):
        output = self.prepare(kind="mp", languages=["EN", "RU"], ports=[17501, 17502])
        runtime = json.loads((output / "runtime.json").read_text())
        self.assertEqual(set(runtime["roles"]), {"server", "client1", "client2"})
        self.assertEqual(runtime["roles"]["client2"]["language"], "RU")
        self.assertIn("language=RU", (output / "client2/options.ini").read_text())
        server = (output / "server/Server/queue-smoke.ini").read_text()
        self.assertIn("VoiceEnable=false", server)
        self.assertIn("DefaultPort=17501\nUDPPort=17502", server)
        config = (output / "client2/mods/ActionQueueTest/42/media/lua/shared/QueueTestSelection.lua").read_text()
        self.assertIn('["port"]=17501', config)
        self.assertIn("return QueueTestSelection", config)
        for role in ("server", "client1"):
            self.assertEqual(config, (output / role / "mods/ActionQueueTest/42/media/lua/shared/QueueTestSelection.lua").read_text(), "Shared MP Lua must keep native checksums identical")
        self.assertEqual(self.compile_mock.call_count, 2)

    def test_automatic_ports_are_unique_frozen_and_do_not_change_control_fingerprint(self):
        with patch.object(admission, 'STATE', self.root / 'leases'):
            first = self.prepare('auto-native', ports_auto=True, kind='mp', languages=['EN', 'RU'], mode='native')
            second = self.prepare('auto-toolkit', ports_auto=True, kind='mp', languages=['EN', 'RU'])
        selections = [report.read_json(run / 'selection.json') for run in (first, second)]
        self.assertFalse(set(selections[0]['ports']).intersection(selections[1]['ports']))
        self.assertEqual(report.read_json(first / 'settings-fingerprint.json')['sha256'],
                         report.read_json(second / 'settings-fingerprint.json')['sha256'])
        for run, selected in zip((first, second), selections):
            self.assertEqual([], report.verify_manifest(run, 'snapshot-hashes.json'))
            self.assertIn('DefaultPort=' + str(selected['ports'][0]), (run / 'server/Server/queue-smoke.ini').read_text())
            self.assertIn('pauseOnFocusLoss=false', (run / 'client1/options.ini').read_text())

    def test_resource_budget_is_validated_before_output(self):
        for resources in ({'heap_mib': 0}, {'native_mib': -1}, {'cpu_per_instance': float('nan')},
                          {'exclusive': 1}, {'unknown': 1}, []):
            with self.subTest(resources=resources), self.assertRaises(ValueError):
                self.prepare(resources=resources)
            self.assertFalse((self.root / 'run').exists())

    def test_output_inside_source_mod_and_ambiguous_runtime_paths_fail(self):
        for output in (self.project / "Toolkit" / "run", self.root / "bad,path"):
            with self.subTest(output=output), self.assertRaises(ValueError):
                native.prepare(self.project, output, self.game, self.jdk, self.selection)
            self.assertFalse(output.exists())
        with self.assertRaises(ValueError):
            self.prepare(kind="mp", languages=["EN"])

    def test_workshop_requires_exact_unambiguous_id_across_all_roots(self):
        self.selection["mods"].append("External")
        first, second = self.root / "workshop1", self.root / "workshop2"
        first.mkdir()
        second.mkdir()
        with self.assertRaisesRegex(ValueError, "External"):
            native.prepare(self.project, self.root / "missing", self.game, self.jdk, self.selection, [first])
        self.mod(first / "123/mods/External", "external")
        with self.assertRaisesRegex(ValueError, "External"):
            native.prepare(self.project, self.root / "wrongcase", self.game, self.jdk, self.selection, [first])
        self.mod(first / "124/mods/External", "External")
        self.mod(second / "124/mods/External", "External")
        with self.assertRaisesRegex(ValueError, "exactly once"):
            native.prepare(self.project, self.root / "ambiguous", self.game, self.jdk, self.selection, [first, second])
        output = native.prepare(self.project, self.root / "good", self.game, self.jdk, self.selection, [first, first])
        self.assertTrue((output / "client1/mods/External/42/mod.info").is_file())

    def test_local_source_wins_over_workshop_copy_and_repeated_jars_keep_exact_hashes(self):
        workshop = self.root / "workshop"
        self.mod(workshop / "1/mods/OldToolkit", "PZSurvivorToolkit")
        for relative in ("42/media/java/one.jar", "42/media/java/two.jar"):
            self.write(self.project / "Toolkit" / relative, "same jar bytes")
        output = native.prepare(self.project, self.root / "run", self.game, self.jdk, self.selection, [workshop])
        mods = json.loads((output / "manifest.json").read_text())
        self.assertEqual(mods[0]["source"], str(self.project / "Toolkit"))
        approvals = json.loads((output / "client1/zombie-buddy/mod_approvals.json").read_text())["mods"]
        self.assertEqual(len(approvals), 2)
        self.assertEqual(approvals[0]["jar_hash"], approvals[1]["jar_hash"])

    def test_invalid_inputs_do_not_create_output(self):
        for changes in ({"cases": []}, {"mods": ["PZSurvivorToolkit"] * 2}, {"mods": ['..']}, {"cases": ['.']}, {"expected_checks": 7},
                        {"ports": [17343, 17343]}, {"kind": "invalid"}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.prepare(**changes)
            self.assertFalse((self.root / "run").exists())
        (self.jdk / "bin/javac").unlink()
        with self.assertRaisesRegex(ValueError, "Missing game/JDK"):
            self.prepare()
        self.assertFalse((self.root / "run").exists())

    def test_incompatible_layer_and_duplicate_local_ids_fail(self):
        self.mod(self.project / "Duplicate", "PZSurvivorToolkit")
        with self.assertRaisesRegex(ValueError, "exactly once"):
            self.prepare()
        shutil.rmtree(self.project / "Duplicate")
        (self.project / "Toolkit/42").rename(self.project / "Toolkit/43")
        with self.assertRaisesRegex(ValueError, "compatible 42.21"):
            self.prepare()

    def test_selected_layer_cannot_hide_a_different_mod_id(self):
        self.write(self.project / "Toolkit/common/mod.info", "id=PZSurvivorToolkit\n")
        self.write(self.project / "Toolkit/42/mod.info", "id=OtherToolkit\n")
        with self.assertRaisesRegex(ValueError, "different Mod ID"):
            self.prepare()

    def test_source_changes_during_preparation_are_rejected(self):
        def change_source(command, **kwargs):
            self.compile(command, **kwargs)
            self.write(self.project / "tests/native_queue/shared.lua", "unrelated file")
            self.write(self.project / "Toolkit/42/media/lua/shared/test.lua", "changed during compile")
        self.compile_mock.side_effect = change_source
        with self.assertRaisesRegex(RuntimeError, "Source changed"):
            self.prepare()
        self.assertFalse((self.root / "run/snapshot-hashes.json").exists())

    def test_common_builder_accepts_another_fixture_suite(self):
        shutil.copytree(self.project / "tests/native_queue/health", self.project / "tests/native_queue/crafting")
        output = self.prepare(suite="crafting")
        selection = json.loads((output / "selection.json").read_text())
        self.assertEqual(selection["suite"], "crafting")


if __name__ == "__main__":
    unittest.main()
