"""A verifier correction can reuse observations; changed native evidence cannot."""
import importlib.util
import io
import os
import subprocess
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from tests import test_queue_report as fixtures

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import provenance, reanalysis, report, runner, native

spec = importlib.util.spec_from_file_location('reanalysis_cli', ROOT / 'tools/check_action_queue.py')
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)


class ReanalysisTests(unittest.TestCase):
    def setUp(self):
        self.fixtures = fixtures.QueueReportTests()
        self.fixtures.setUp()
        self.addCleanup(self.fixtures.doCleanups)
        self.base, self.catalog = self.fixtures.base, self.fixtures.catalog
        self.verifier, self.verifier_test = self.base / 'verify.py', self.base / 'test_verify.py'
        self.verifier.write_text('# original verifier\n')
        self.verifier_test.write_text('# original verifier tests\n')
        # The health fixture supplies real structured effects/readiness/authority
        # evidence. Opt it into the same source-role contract as a split adapter.
        declaration = patch.object(provenance, 'verifier_sources',
                                   return_value=[self.verifier, self.verifier_test])
        declaration.start()
        self.declaration = declaration
        self.addCleanup(declaration.stop)

    def capture(self, name='run', mode='toolkit', seal=True):
        root = self.fixtures.fixture(name, mode=mode)
        original = report.read_json(root / 'source-manifest.json')
        original.update({str(path): provenance.digest(path) for path in (self.verifier, self.verifier_test)})
        report.write_json(root / 'source-manifest.json', original)
        selection = report.read_json(root / 'selection.json')
        report.write_json(root / provenance.SOURCE_ROLES, provenance.source_roles(self.base, selection, original))
        self.fixtures.freeze(root)
        frozen = report.read_json(root / 'snapshot-hashes.json')
        frozen[provenance.SOURCE_ROLES] = provenance.digest(root / provenance.SOURCE_ROLES)
        report.write_json(root / 'snapshot-hashes.json', frozen)
        if seal:
            provenance.seal_execution(root)
        return root

    @staticmethod
    def bytes_in(root):
        return {path.relative_to(root).as_posix(): path.read_bytes() for path in root.rglob('*') if path.is_file()}

    def test_verifier_and_test_corrections_reanalyze_without_changing_original_run(self):
        root = self.capture()
        report.write_json(root / 'report.json', report.build_report(root, self.catalog))
        original = self.bytes_in(root)
        self.verifier.write_text('# corrected verifier\n')
        self.verifier_test.write_text('# regression for correction\n')
        self.assertEqual('failed', report.build_report(root, self.catalog)['status'])
        value = reanalysis.write(root, self.base / 'new-analysis', self.catalog)
        self.assertEqual('passed', value['status'])
        evidence = value['provenance']['reanalysis']
        self.assertNotEqual(evidence['original_verifier'], evidence['current_verifier'])
        self.assertEqual(provenance.digest(root / provenance.EXECUTION_SEAL), evidence['execution_seal_sha256'])
        self.assertEqual(original, self.bytes_in(root))
        self.assertTrue((self.base / 'new-analysis/coverage.json').is_file())

    def test_fixing_only_the_verifier_can_correct_a_failed_report_on_the_same_observations(self):
        def source(status):
            return ("def verify(root, selection, catalog):\n"
                    "    return dict(issues=" + ("['incorrect assertion']" if status == 'failed' else '[]') +
                    ", outcomes=[dict(actor='client1', case='bandageApply', status='" + status + "')])\n")
        self.verifier.write_text(source('failed'))
        root = self.capture()
        original_seal = (root / provenance.EXECUTION_SEAL).read_bytes()
        adapter = SimpleNamespace(verify=lambda *args: provenance.run_verifier(
            self.verifier, 'isolated_fixture', *args))
        with patch.object(report.adapters, 'get', return_value=adapter):
            original = report.build_report(root, self.catalog)
            self.assertEqual('failed', original['status'])
            self.assertEqual('completed', original['execution']['status'])
            report.write_json(root / 'report.json', original)
            self.verifier.write_text(source('passed'))
            corrected = reanalysis.write(root, self.base / 'corrected-analysis', self.catalog)
        self.assertEqual('passed', corrected['status'])
        self.assertEqual(original_seal, (root / provenance.EXECUTION_SEAL).read_bytes())
        self.assertEqual('failed', report.read_json(root / 'report.json')['status'])

    def test_runtime_fixture_metadata_and_observation_drift_refuse_reanalysis(self):
        mutations = [
            ('source', lambda root: self.fixtures.source.write_text('changed runtime')),
            ('fixture', lambda root: (root / 'client1/mods/input').write_text('changed fixture')),
            ('class', lambda root: (root / 'client1/classes/input').write_text('changed bytecode')),
            ('added-class', lambda root: (root / 'client1/classes/new.class').write_bytes(b'new')),
            ('selection', lambda root: (root / 'selection.json').write_text('{}')),
            ('roles', lambda root: (root / provenance.SOURCE_ROLES).write_text('{}')),
            ('execution', lambda root: (root / 'execution.json').write_text('{}')),
            ('log-content', lambda root: (root / 'client1-launch.log').write_text('forged PASS')),
            ('deleted-log', lambda root: (root / 'client1-launch.log').unlink()),
            ('added-log', lambda root: (root / 'extra-launch.log').write_text('new error')),
            ('added-console', lambda root: (root / 'client1/console.txt').write_text('new error')),
            ('seal', lambda root: (root / provenance.EXECUTION_SEAL).write_text('{}')),
        ]
        for name, mutate in mutations:
            with self.subTest(name=name):
                self.fixtures.source.write_text('real source')
                root = self.capture(name)
                mutate(root)
                output = self.base / (name + '-analysis')
                with self.assertRaises((ValueError, KeyError)):
                    reanalysis.write(root, output, self.catalog)
                self.assertFalse(output.exists())

    def test_changed_native_game_tree_refuses_reanalysis(self):
        root = self.capture()
        path = self.base / 'game/media/lua/new.lua'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('return true')
        with self.assertRaisesRegex(ValueError, 'Added native game input'):
            reanalysis.write(root, self.base / 'analysis', self.catalog)

    def test_debug_and_probe_log_membership_and_symlinks_are_guarded(self):
        for name in ('client1-probes.log', 'client1/console.txt', 'client1/Logs/game_DebugLog.txt'):
            with self.subTest(name=name):
                root = self.capture(name.replace('/', '-'), seal=False)
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('original observation')
                provenance.seal_execution(root)
                self.assertFalse(provenance.observation_issues(root))
                content = path.read_text()
                path.unlink()
                self.assertTrue(provenance.observation_issues(root))
                external = self.base / 'external-observation'
                external.write_text(content)
                path.symlink_to(external)
                self.assertTrue(provenance.observation_issues(root))

    def test_legacy_unsupported_and_unsealed_runs_are_not_backfilled(self):
        legacy = self.fixtures.fixture('legacy')
        self.assertEqual('passed', report.build_report(legacy, self.catalog)['status'])
        with self.assertRaisesRegex(ValueError, 'Cannot reanalyze'):
            reanalysis.write(legacy, self.base / 'legacy-analysis', self.catalog)
        self.assertFalse((legacy / provenance.EXECUTION_SEAL).exists())
        root = self.capture('unsealed', seal=False)
        self.assertEqual('failed', report.build_report(root, self.catalog)['status'])
        with self.assertRaisesRegex(ValueError, 'execution observations'):
            reanalysis.write(root, self.base / 'unsealed-analysis', self.catalog)
        with patch.object(provenance, 'verifier_sources', return_value=[]):
            root = self.capture('unsupported')
            with self.assertRaisesRegex(ValueError, 'no separated verifier'):
                reanalysis.write(root, self.base / 'unsupported-analysis', self.catalog)

    @unittest.skipUnless(hasattr(os, 'mkfifo'), 'FIFO inputs are POSIX-specific')
    def test_special_observation_files_are_rejected_without_opening_a_blocking_stream(self):
        root = self.capture()
        os.mkfifo(root / 'extra-probes.log')
        with self.assertRaisesRegex(ValueError, 'regular file'):
            reanalysis.write(root, self.base / 'analysis', self.catalog)

    @unittest.skipUnless(hasattr(os, 'mkfifo'), 'FIFO inputs are POSIX-specific')
    def test_special_metadata_is_refused_before_any_blocking_json_read(self):
        for name in ('selection.json', 'runtime.json', 'game-inputs.json'):
            with self.subTest(name=name):
                root = self.capture('fifo-' + name)
                path = root / name
                path.unlink()
                os.mkfifo(path)
                # A bounded child proves refusal without risking a stuck test runner.
                script = ('import sys;sys.path.insert(0,sys.argv[1]);'
                          'from queue_checks import provenance;'
                          'provenance.reanalysis_provenance(sys.argv[2])')
                result = subprocess.run([sys.executable, '-c', script, str(ROOT / 'tools'), str(root)],
                                        capture_output=True, text=True, timeout=3)
                self.assertNotEqual(0, result.returncode)
                self.assertIn('regular file', result.stderr)
                if name == 'selection.json':
                    result = subprocess.run([sys.executable, str(ROOT / 'tools/check_action_queue.py'),
                                             'reanalyze', str(root), str(self.base / 'fifo-analysis')],
                                            capture_output=True, text=True, timeout=3)
                    self.assertEqual(1, result.returncode)
                    self.assertIn('regular file', result.stderr)

    def test_changed_verifier_dependencies_require_a_fresh_snapshot(self):
        root = self.capture()
        with patch.object(provenance, 'verifier_sources', return_value=[self.verifier]):
            with self.assertRaisesRegex(ValueError, 'dependency set changed'):
                reanalysis.write(root, self.base / 'analysis', self.catalog)

    def test_verifier_source_revision_executes_even_with_unchanged_timestamp_and_size(self):
        path = self.base / 'cached_verifier.py'
        path.write_text("def verify(*args): return 'old'\n")
        spec = importlib.util.spec_from_file_location('cached_verifier', path)
        cached = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cached)
        self.assertEqual('old', cached.verify())
        original = path.stat()
        path.write_text("def verify(*args): return 'new'\n")
        os.utime(path, ns=(original.st_atime_ns, original.st_mtime_ns))
        self.assertEqual(original.st_size, path.stat().st_size)
        self.assertEqual('new', provenance.run_verifier(path, 'isolated_fixture', None, {}, {}))

    def test_drift_at_cleanup_cannot_be_hidden_by_restoring_the_live_source(self):
        root = self.capture(seal=False)
        self.fixtures.source.write_text('runtime changed while the game was running')
        provenance.seal_execution(root)
        self.fixtures.source.write_text('real source')
        with self.assertRaisesRegex(ValueError, 'Invalid execution observation seal'):
            reanalysis.write(root, self.base / 'analysis', self.catalog)
        with self.assertRaises(FileExistsError):
            provenance.seal_execution(root)

    def test_failed_execution_stays_failed_under_a_corrected_verifier(self):
        root = self.capture(seal=False)
        value = report.read_json(root / 'execution.json')
        value.update(status='failed', error='native cleanup failed')
        report.write_json(root / 'execution.json', value)
        provenance.seal_execution(root)
        self.verifier.write_text('# corrected verifier')
        result = reanalysis.write(root, self.base / 'analysis', self.catalog)
        self.assertEqual('failed', result['status'])
        self.assertTrue(result['execution_issues'])

    def test_mid_analysis_observation_or_verifier_change_cannot_publish_a_pass(self):
        for reanalyze, change in ((True, 'log'), (True, 'verifier'), (False, 'log')):
            with self.subTest(reanalyze=reanalyze, change=change):
                root = self.capture(str(reanalyze) + change)
                original = report.functional
                def functional(*args):
                    value = original(*args)
                    path = root / 'client1-launch.log' if change == 'log' else self.verifier
                    path.write_text(path.read_text() + '\nchanged during verification\n')
                    return value
                with patch.object(report, 'functional', side_effect=functional):
                    if reanalyze:
                        with self.assertRaises(ValueError):
                            reanalysis.write(root, self.base / (root.name + '-analysis'), self.catalog)
                    else:
                        self.assertEqual('failed', report.build_report(root, self.catalog)['status'])

    def test_native_control_is_reanalyzed_with_its_own_original_seals(self):
        control = self.capture('control', mode='native')
        self.verifier.write_text('# next verifier revision')
        candidate = self.capture('candidate')
        self.verifier.write_text('# corrected shared verifier')
        value = reanalysis.write(candidate, self.base / 'analysis', self.catalog, control)
        self.assertEqual('passed', value['status'])
        self.assertTrue(value['comparison']['compatible'])
        self.assertNotEqual(value['provenance']['reanalysis']['original_verifier'],
                            value['comparison']['control_reanalysis']['original_verifier'])
        self.assertEqual(value['provenance']['reanalysis']['current_verifier'],
                         value['comparison']['control_reanalysis']['current_verifier'])
        (control / 'client1-launch.log').write_text('changed control')
        with self.assertRaisesRegex(ValueError, 'observations changed'):
            reanalysis.write(candidate, self.base / 'bad-control-analysis', self.catalog, control)

    def test_cli_reanalysis_never_prepares_or_launches_and_requires_fresh_external_output(self):
        root = self.capture()
        output = self.base / 'cli-analysis'
        self.verifier_test.write_text('# added regression')
        with patch.object(cli, 'load_catalog', return_value=self.catalog), \
                patch.object(native, 'prepare') as prepare, patch.object(runner, 'run') as run, \
                patch('sys.stdout', io.StringIO()), patch('sys.stderr', io.StringIO()):
            self.assertEqual(0, cli.main(['reanalyze', str(root), str(output)]))
            self.assertEqual(1, cli.main(['reanalyze', str(root), str(output)]))
            self.assertEqual(1, cli.main(['reanalyze', str(root), str(root / 'analysis')]))
        prepare.assert_not_called()
        run.assert_not_called()
        self.assertFalse((root / 'analysis').exists())

    def test_separated_book_verifier_consumes_its_original_native_bank_receipts(self):
        from tests import test_queue_book_controls as book_fixtures
        from queue_checks.adapters import book_controls
        self.declaration.stop()
        root = self.fixtures.fixture('book-bank')
        selection, text, _ = book_fixtures.BookControlTests().log_bank('sp', 'toolkit')
        markers = ''.join('[QUEUE_TEST] ' + marker + '\n' for marker in
                          ('VOICE_DISABLED', 'DISPLAY_READY', 'PREFLIGHT_COMPLETE', 'TRUE_SP'))
        (root / 'client1-launch.log').write_text(markers + text)
        report.write_json(root / 'selection.json', selection)
        verifier_paths = provenance.verifier_sources(ROOT, selection)
        original = {str(path): provenance.digest(path) for path in
                    (self.fixtures.source, Path(book_controls.__file__), *verifier_paths)}
        report.write_json(root / 'source-manifest.json', original)
        report.write_json(root / provenance.SOURCE_ROLES, provenance.source_roles(ROOT, selection, original))
        self.fixtures.freeze(root)
        frozen = report.read_json(root / 'snapshot-hashes.json')
        frozen[provenance.SOURCE_ROLES] = provenance.digest(root / provenance.SOURCE_ROLES)
        report.write_json(root / 'snapshot-hashes.json', frozen)
        provenance.seal_execution(root)
        value = reanalysis.write(root, self.base / 'book-analysis', {'suites': book_controls.definitions()})
        self.assertEqual('passed', value['status'])
        self.assertEqual(len(selection['cases']), len(value['coverage']))
        self.assertIn(str(Path(book_controls.__file__).with_name('book_controls_verifier.py')),
                      value['provenance']['reanalysis']['current_verifier'])


if __name__ == '__main__':
    unittest.main()
