"""Stopped-run compaction preserves native evidence, dependencies and recovery."""
from pathlib import Path
import os
import io
import json
from contextlib import redirect_stdout
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import admission, native, report, snapshot_storage as storage, snapshot_store, worlds, pack


@unittest.skipUnless(os.name == 'posix', 'Native snapshot maintenance requires POSIX admission locks')
class SnapshotStorageTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name).resolve()
        self.run = self.base / 'runs' / 'example'
        self.run.mkdir(parents=True)
        self.store = self.base / 'store'
        self.game = self.base / 'game'
        self.game.mkdir()
        (self.game / 'projectzomboid.jar').write_bytes(b'game')
        self.mod = self.run / 'client1/mods/Example'
        (self.mod / '42/media/lua').mkdir(parents=True)
        (self.mod / '42/media/lua/Test.lua').write_text('return true\n')
        (self.mod / '42/media/empty').mkdir()
        (self.mod / '42/mod.info').write_text('id=Example\nname=Example\n')
        for directory in ('Lua', 'classes'):
            path = self.run / 'client1' / directory
            path.mkdir()
            (path / 'input').write_text('input')
        (self.run / 'client1/mods/default.txt').write_text('Example')
        self.selection = {'kind': 'sp', 'clients': 1, 'suite': 'health', 'cases': ['nativeStop'], 'mods': ['Example'], 'ports': [17343, 17344]}
        self.write('selection.json', self.selection)
        self.write('runtime.json', {'game': str(self.game), 'server_name': 'queue-smoke',
                                  'roles': {'client1': {'cache': str(self.run / 'client1')}}})
        self.write('manifest.json', [{'id': 'Example', 'source': str(self.base / 'original'),
                                     'input_policy': 'mod-artifacts-no-git-v1', 'files': native.hashes(self.mod)}])
        self.write('source-manifest.json', {str(self.game / 'projectzomboid.jar'): native.sha256(self.game / 'projectzomboid.jar')})
        self.write('settings-fingerprint.json', {})
        self.write('initial-settings.json', {})
        self.write('game-inputs.json', report.game_inputs(self.game))
        self.write('snapshot-hashes.json', native.hashes(self.run))
        self.write('execution.json', {'status': 'completed', 'processes': {'client1': {'pid': 999999, 'exit_code': 0}}})
        self.write('report.json', {'original': 'retained'})
        saved = self.run / 'client1/Saves/Sandbox/world/map.bin'
        saved.parent.mkdir(parents=True)
        saved.write_bytes(b'unchanged world')
        self.saved = saved
        self.seal = (self.run / 'snapshot-hashes.json').read_bytes()
        self.startPatch(patch.object(admission, 'STATE', self.base / 'admission'))
        self.startPatch(patch.object(admission, 'LEGACY_LOCK', self.base / 'legacy.lock'))
        self.startPatch(patch.object(admission.host, 'sample', return_value={'processes': []}))
        self.startPatch(patch.object(storage.os, 'kill', side_effect=ProcessLookupError))

    def startPatch(self, item):
        item.start()
        self.addCleanup(item.stop)

    def write(self, name, value):
        report.write_json(self.run / name, value)

    def compact(self, **kwargs):
        return storage.compact(self.run, self.store, dependency_roots=[self.base / 'runs'], **kwargs)

    def test_preview_does_not_publish_or_remove_and_roundtrip_preserves_evidence(self):
        preview = self.compact()
        self.assertEqual(['client1/mods/Example'], preview['eligible'])
        self.assertFalse(self.store.exists())
        self.assertTrue(self.mod.is_dir())
        self.assertFalse((self.run / storage.MARKER).exists())
        before = native.hashes(self.mod)
        self.compact(apply=True)
        self.assertFalse(self.mod.exists())
        storage.verify(self.run)
        self.assertEqual(self.seal, (self.run / 'snapshot-hashes.json').read_bytes())
        self.assertEqual(b'unchanged world', self.saved.read_bytes())
        self.assertEqual({'original': 'retained'}, report.read_json(self.run / 'report.json'))
        storage.restore(self.run)
        self.assertEqual(before, native.hashes(self.mod))
        self.assertTrue((self.mod / '42/media/empty').is_dir())
        self.assertEqual([], report.verify_manifest(self.run, 'snapshot-hashes.json'))

    def test_source_references_protect_original_paths(self):
        other = self.base / 'runs/consumer'
        other.mkdir()
        report.write_json(other / 'source-manifest.json', {str(self.mod / '42/mod.info'): 'x'})
        preview = self.compact()
        self.assertEqual(['client1/mods/Example'], preview['protected_sources'])
        self.assertEqual([], preview['eligible'])
        result = self.compact(apply=True)
        self.assertEqual('unchanged', result['status'])
        self.assertTrue(self.mod.is_dir())

    def test_dependency_scan_keeps_arbitrary_pack_names_and_native_run_directories(self):
        for relative, value in (
            ('native/consumer/source-manifest.json', {str(self.mod / '42/mod.info'): 'x'}),
            ('locks/selected-pack.json', {'mods': [{'id': 'Example', 'source': str(self.mod)}]}),
        ):
            path = self.base / 'runs' / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            report.write_json(path, value)
            with self.subTest(path=relative):
                self.assertEqual(['client1/mods/Example'], self.compact()['protected_sources'])
            path.unlink()

    def test_first_compaction_is_blocked_by_unarchived_source_pin_and_alias(self):
        alias = self.run / '..' / self.run.name / 'client1/mods/Example'
        for source in (self.mod, alias):
            with self.subTest(source=str(source)), storage.source_inputs([source]):
                with self.assertRaisesRegex(RuntimeError, 'pins'):
                    self.compact(apply=True)
                self.assertTrue(self.mod.is_dir())
        self.compact(apply=True)
        with storage.source_inputs([alias]):
            with self.assertRaisesRegex(RuntimeError, 'pins'):
                self.compact(apply=True)
            self.assertTrue(self.mod.is_dir())

    def test_seed_metadata_and_recursive_workshop_roots_discover_their_owner(self):
        self.compact(apply=True)
        for source in (self.run / 'selection.json', self.run / 'client1'):
            with self.subTest(source=str(source)), storage.source_inputs([source]):
                self.assertTrue(self.mod.is_dir())
                with self.assertRaisesRegex(RuntimeError, 'pins'):
                    self.compact(apply=True)
            self.compact(apply=True)

    def test_source_pin_spans_restoration_and_preparation_admission(self):
        from contextlib import nullcontext
        from types import SimpleNamespace
        self.compact(apply=True)
        selected = dict(self.selection, options={'mod_sources': {'Example': str(self.mod)}})
        def check_pin(*args, **kwargs):
            self.assertTrue(self.mod.is_dir())
            lease_path = admission.STATE / (admission._key(self.run) + '.lease')
            with lease_path.open('a+') as stream:
                with self.assertRaises(BlockingIOError):
                    admission.fcntl.flock(stream, admission.fcntl.LOCK_EX | admission.fcntl.LOCK_NB)
            with self.assertRaisesRegex(RuntimeError, 'pins'):
                self.compact(apply=True)
            return nullcontext()
        with patch.object(native.adapters, 'get', return_value=SimpleNamespace()), \
             patch.object(admission, 'preparing', side_effect=check_pin), \
             patch.object(native, '_prepare', side_effect=lambda *a: check_pin()):
            native.prepare(self.base, self.base / 'new-run', self.game, self.base / 'jdk', selected)
        lease_path = admission.STATE / (admission._key(self.run) + '.lease')
        with lease_path.open('a+') as stream:
            admission.fcntl.flock(stream, admission.fcntl.LOCK_EX | admission.fcntl.LOCK_NB)

    def test_linked_worktree_source_consumers_are_included_by_default(self):
        from types import SimpleNamespace
        (self.base / '.git').write_text('gitdir: owned-test-gitdir\n')
        other = self.base / 'other-worktree'
        consumer = other / '.codex/investigations/consumer'
        consumer.mkdir(parents=True)
        report.write_json(consumer / 'source-manifest.json', {str(self.mod / '42/mod.info'): 'x'})
        result = SimpleNamespace(stdout=os.fsencode('worktree ' + str(other) + '\0HEAD example\0\0'))
        with patch.object(storage.subprocess, 'run', return_value=result):
            preview = self.compact()
        self.assertEqual(['client1/mods/Example'], preview['protected_sources'])

    def test_dependency_scan_handles_escaped_pack_keys_and_options_sources(self):
        consumer = self.base / 'runs/consumer'
        consumer.mkdir()
        path = consumer / 'arbitrary-name.json'
        value = {'mods': [{'id': 'Example', 'source': str(self.mod)}]}
        path.write_text(json.dumps(value).replace('"mods"', '"mo\\u0064s"'))
        self.assertEqual(['client1/mods/Example'], self.compact()['protected_sources'])
        report.write_json(path, {'options': {'mod_sources': {'Example': str(self.mod)}}})
        self.assertEqual(['client1/mods/Example'], self.compact()['protected_sources'])

    def test_dependency_scan_resolves_parent_and_file_aliases(self):
        consumer = self.base / 'runs/consumer'
        consumer.mkdir()
        alias = self.base / 'source-alias'
        alias.symlink_to(self.mod, target_is_directory=True)
        file_alias = self.base / 'source-file.lua'
        file_alias.symlink_to(self.mod / '42/media/lua/Test.lua')
        for source in (alias / '42/mod.info', file_alias, self.mod / '42/..'):
            report.write_json(consumer / 'source-manifest.json', {str(source): 'x'})
            with self.subTest(source=str(source)):
                self.assertEqual(['client1/mods/Example'], self.compact()['protected_sources'])

    def test_archive_source_can_be_restored_without_rewriting_original_lock(self):
        self.compact(apply=True)
        source = str(self.mod / '42/media/lua/Test.lua')
        storage.restore_sources([source])
        self.assertTrue(Path(source).is_file())
        self.assertEqual(self.seal, (self.run / 'snapshot-hashes.json').read_bytes())

    def test_physical_consumers_temporarily_restore_and_recompact(self):
        self.compact(apply=True)
        with storage.available(self.run):
            self.assertTrue(self.mod.is_dir())
            self.assertEqual([], report.verify_manifest(self.run, 'snapshot-hashes.json'))
            with storage.available(self.run):
                self.assertTrue(self.mod.is_dir())
            self.assertTrue(self.mod.is_dir())
        self.assertFalse(self.mod.exists())
        with self.assertRaisesRegex(RuntimeError, 'consumer failure'):
            with storage.available(self.run):
                raise RuntimeError('consumer failure')
        self.assertFalse(self.mod.exists())

    def test_mutating_consumer_is_rejected_and_changed_tree_is_retained(self):
        self.compact(apply=True)
        with self.assertRaisesRegex(ValueError, 'differs'):
            with storage.available(self.run):
                (self.mod / '42/mod.info').write_text('changed')
        self.assertEqual('changed', (self.mod / '42/mod.info').read_text())

    def test_cli_preview_apply_verify_restore_needs_no_scenario_catalog(self):
        from tests.test_queue_reanalysis import cli
        for command, extra in (
            ('snapshot-compact', ['--store', str(self.store)]),
            ('snapshot-compact', ['--store', str(self.store), '--apply']),
            ('snapshot-verify', []),
            ('snapshot-restore', []),
        ):
            output = io.StringIO()
            with patch.object(cli, 'load_catalog') as catalog, redirect_stdout(output):
                self.assertEqual(0, cli.main([command, str(self.run), *extra]))
            catalog.assert_not_called()
            self.assertIn('status', json.loads(output.getvalue()))
        self.assertTrue(self.mod.is_dir())

    def test_opt_in_lifecycle_runs_only_after_report_publication(self):
        from tests.test_queue_reanalysis import cli
        value = {'status': 'passed', 'original_verdict': True}
        with patch.object(cli.report, 'build_report', return_value=value), \
             patch.object(cli.report, 'matrix', return_value={}), \
             patch.object(cli.report, 'summary', return_value='original report'), \
             redirect_stdout(io.StringIO()):
            self.assertEqual(value, cli.save_report(self.run, {}, snapshot_store=self.store))
        self.assertEqual(value, report.read_json(self.run / 'report.json'))
        self.assertFalse(self.mod.exists())
        self.assertEqual('compacted', report.read_json(self.run / 'storage-maintenance.json')['status'])

    def test_world_export_restores_inputs_only_during_export(self):
        self.compact(apply=True)
        value = worlds.export(self.run, self.base / 'world-template')
        self.assertIn('client1/Saves/Sandbox/world/map.bin', value['files'])
        self.assertFalse(self.mod.exists())
        self.assertEqual(b'unchanged world', self.saved.read_bytes())

    def test_changed_directory_or_mode_is_retained_after_consumer(self):
        self.compact(apply=True)
        with self.assertRaises(ValueError):
            with storage.available(self.run):
                (self.mod / 'new-empty').mkdir()
        self.assertTrue((self.mod / 'new-empty').is_dir())

    def test_linked_role_cannot_be_compacted(self):
        role = self.run / 'client1'
        role.rename(self.run / 'actual-cache')
        role.symlink_to(self.run / 'actual-cache', target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'Linked'):
            self.compact(apply=True)
        self.assertTrue(self.mod.is_dir())
        self.assertFalse(self.store.exists())

    def test_pack_lock_can_reuse_archived_source_without_changing_its_path(self):
        project = self.base / 'project'
        project.mkdir()
        (project / 'SurvivorQoL-selected.ini').write_text('Mods=Example\nWorkshopItems=\n')
        lock = self.base / 'pack.json'
        pack.create(project, lock, self.game, overrides={'Example': str(self.mod)})
        original = lock.read_bytes()
        self.compact(apply=True)
        self.assertFalse(self.mod.exists())
        self.assertEqual({'Example': str(self.mod)}, pack.validate(lock, project, self.game, ['Example']))
        self.assertTrue(self.mod.is_dir())
        self.assertEqual(original, lock.read_bytes())

    def test_lifecycle_hook_keeps_report_and_raw_inputs_when_compaction_is_refused(self):
        with patch.object(storage, 'compact', side_effect=RuntimeError('busy lease')):
            result = storage.after_report(self.run, self.store)
        self.assertEqual('deferred', result['status'])
        self.assertEqual('busy lease', result['reason'])
        self.assertTrue(self.mod.is_dir())
        self.assertEqual({'original': 'retained'}, report.read_json(self.run / 'report.json'))
        self.assertEqual(result, report.read_json(self.run / 'storage-maintenance.json'))

    def test_interrupted_restore_staging_cannot_pollute_sealed_mod_membership(self):
        self.compact(apply=True)
        def interrupt(store, object_id, destination):
            residue = destination.parent / '.Example.snapshot-interrupted'
            residue.mkdir()
            (residue / 'partial').write_bytes(b'partial')
            raise KeyboardInterrupt()
        with patch.object(snapshot_store, 'materialize', side_effect=interrupt):
            with self.assertRaises(KeyboardInterrupt):
                storage.restore(self.run)
        storage.verify(self.run)
        self.assertFalse(self.mod.exists())
        storage.restore(self.run)
        self.assertTrue(self.mod.is_dir())
        self.assertEqual([], report.verify_manifest(self.run, 'snapshot-hashes.json'))
        self.assertTrue((self.run / '.snapshot-restoring/client1/mods/.Example.snapshot-interrupted/partial').is_file())

    def test_corrupt_archive_refuses_restore_without_publishing_any_tree(self):
        self.compact(apply=True)
        payload = next((self.store / 'payloads').glob('*.tar.gz'))
        payload.write_bytes(b'corrupt')
        with self.assertRaises(ValueError):
            storage.restore(self.run)
        self.assertFalse(self.mod.exists())
        self.assertTrue(self.saved.exists())

    def test_changed_snapshot_or_added_file_cannot_be_compacted(self):
        (self.mod / 'new').write_text('unsealed')
        with self.assertRaisesRegex(ValueError, 'changed snapshot'):
            self.compact(apply=True)
        self.assertTrue(self.mod.is_dir())
        self.assertFalse(self.store.exists())

    def test_live_pid_prepared_waiting_and_owned_processes_are_protected(self):
        with patch.object(storage.os, 'kill', return_value=None):
            with self.assertRaisesRegex(ValueError, 'still alive'):
                self.compact(apply=True)
        for name in ('_records', '_preparations', '_waiters'):
            with self.subTest(registry=name), patch.object(admission, name, return_value=[{'root': str(self.run)}]):
                with self.assertRaisesRegex(RuntimeError, 'reservation'):
                    self.compact(apply=True)
        with patch.object(admission, 'owned', return_value=[{'pid': 5}]):
            with self.assertRaisesRegex(RuntimeError, 'owned native'):
                self.compact(apply=True)
        self.assertTrue(self.mod.is_dir())

    def test_dead_admission_owner_is_reconciled_before_storage_claims_its_lease(self):
        admission._directory()
        record = {'root': str(self.run), 'ports': [17343, 17344], 'phase': 'running',
                  'caches': [str(self.run / 'client1')], 'budget': admission.budget(self.selection)}
        path = admission.STATE / (admission._key(self.run) + '.json')
        report.write_json(path, record)
        self.compact(apply=True)
        self.assertFalse(path.exists())
        self.assertFalse(self.mod.exists())

    def test_busy_profile_or_global_lease_refuses_storage(self):
        admission._directory()
        for path in (admission.STATE / (admission._key(self.run) + '.lease'), admission.LEGACY_LOCK):
            with path.open('a+') as stream:
                admission.fcntl.flock(stream, admission.fcntl.LOCK_EX | admission.fcntl.LOCK_NB)
                with self.assertRaisesRegex(RuntimeError, 'owns a lease'):
                    self.compact(apply=True)
        self.assertTrue(self.mod.is_dir())

    def test_interrupted_retirement_recovers_without_rewriting_seal(self):
        original = Path.rename
        def fail_after_move(path, target):
            result = original(path, target)
            if path == self.mod:
                raise OSError('interrupted retirement')
            return result
        with patch.object(Path, 'rename', fail_after_move):
            with self.assertRaisesRegex(OSError, 'interrupted retirement'):
                self.compact(apply=True)
        self.assertFalse(self.mod.exists())
        storage.verify(self.run)
        storage.restore(self.run)
        self.assertTrue(self.mod.is_dir())
        self.compact(apply=True)
        self.assertEqual(self.seal, (self.run / 'snapshot-hashes.json').read_bytes())
        self.assertFalse((self.run / '.snapshot-retiring').exists())

    def test_repeat_restore_rejects_linked_staging_without_touching_outside_directories(self):
        self.compact(apply=True)
        storage.restore(self.run)
        outside = self.base / 'outside'
        (outside / 'client1/mods').mkdir(parents=True)
        (self.run / '.snapshot-restoring').symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'Linked'):
            storage.restore(self.run)
        self.assertTrue((outside / 'client1/mods').is_dir())
        self.assertTrue(self.mod.is_dir())

    def test_unknown_journal_special_files_are_never_swept(self):
        self.compact(apply=True)
        retired = self.run / '.snapshot-retiring'
        retired.mkdir()
        fifo = retired / 'unexpected-fifo'
        os.mkfifo(fifo)
        with self.assertRaisesRegex(ValueError, 'Unexpected retirement'):
            self.compact(apply=True)
        self.assertTrue(fifo.exists())

    def test_dangling_marker_is_preserved_instead_of_replaced(self):
        marker = self.run / storage.MARKER
        marker.symlink_to(self.base / 'missing-metadata')
        with self.assertRaisesRegex(ValueError, 'regular file'):
            self.compact(apply=True)
        self.assertTrue(marker.is_symlink())
        self.assertTrue(self.mod.is_dir())
        self.assertFalse(self.store.exists())

    def test_marker_cannot_redirect_retirement_or_change_sealed_bytes(self):
        self.compact(apply=True)
        marker = report.read_json(self.run / storage.MARKER)
        marker['trees']['client1/mods/../../Saves'] = next(iter(marker['trees'].values()))
        self.write(storage.MARKER, marker)
        with self.assertRaisesRegex(ValueError, 'identity'):
            storage.restore(self.run)
        self.assertTrue(self.saved.exists())

@unittest.skipUnless(os.name == 'posix', 'Archived native report inputs require qualified POSIX restoration')
class ArchivedReportTests(unittest.TestCase):
    def setUp(self):
        from tests.test_queue_reanalysis import ReanalysisTests
        self.fixture = ReanalysisTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.base = self.fixture.base
        self.store = self.base / 'archive'
        for item in (
            patch.object(admission, 'STATE', self.base / 'admission'),
            patch.object(admission, 'LEGACY_LOCK', self.base / 'legacy.lock'),
            patch.object(admission.host, 'sample', return_value={'processes': []}),
            patch.object(storage.os, 'kill', side_effect=ProcessLookupError),
        ):
            item.start()
            self.addCleanup(item.stop)

    def capture(self, name, mode='toolkit'):
        from queue_checks import provenance
        root = self.fixture.capture(name, mode, seal=False)
        path = root / 'client1/mods/GeneratedFixture'
        path.mkdir()
        (path / 'input.lua').write_text('return true\n')
        self.fixture.fixtures.freeze(root)
        frozen = report.read_json(root / 'snapshot-hashes.json')
        frozen[provenance.SOURCE_ROLES] = provenance.digest(root / provenance.SOURCE_ROLES)
        report.write_json(root / 'snapshot-hashes.json', frozen)
        provenance.seal_execution(root)
        return root

    def test_report_and_control_reanalysis_keep_original_verdict_and_seals(self):
        from queue_checks import reanalysis
        control = self.capture('control', 'native')
        root = self.capture('candidate')
        before_control = report.build_report(control, self.fixture.catalog)
        before = report.build_report(root, self.fixture.catalog, before_control)
        self.assertEqual('passed', before['status'])
        seals = {p: (p / 'snapshot-hashes.json').read_bytes() for p in (root, control)}
        for p in (root, control):
            storage.compact(p, self.store, apply=True)
            self.assertFalse((p / 'client1/mods/GeneratedFixture').exists())
        after_control = report.build_report(control, self.fixture.catalog)
        after = report.build_report(root, self.fixture.catalog, after_control)
        self.assertEqual(before, after)
        self.fixture.verifier.write_text('# corrected verifier\n')
        value = reanalysis.write(root, self.base / 'reanalysis', self.fixture.catalog, control)
        self.assertEqual('passed', value['status'])
        for p in (root, control):
            self.assertEqual(seals[p], (p / 'snapshot-hashes.json').read_bytes())
            self.assertFalse((p / 'client1/mods/GeneratedFixture').exists())


class UnsupportedPlatformStorageTests(unittest.TestCase):
    def test_plain_sources_keep_working_without_posix_but_archived_sources_fail_explicitly(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            for name in ('selection.json', 'runtime.json', 'snapshot-hashes.json'):
                (root / name).write_text('{}')
            source = root / 'client1/mods/Example'
            with patch.object(admission, 'fcntl', None):
                with storage.source_inputs([source]):
                    pass
                (root / storage.MARKER).write_text('{}')
                with self.assertRaisesRegex(ValueError, 'qualified POSIX'):
                    with storage.source_inputs([source]):
                        self.fail('unsupported archived source was accepted')


if __name__ == '__main__':
    unittest.main()
