"""Resolve cart build inputs before batch execution or native snapshot mutation."""
import argparse
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from JavaPatches import build
from JavaPatches.tests import test_build_kotlin as kotlin_fixture
from queue_checks import adapters, native, snapshot_copy
from queue_checks.adapters import carts
from tests import test_queue_native_snapshot as snapshot_fixture

spec = importlib.util.spec_from_file_location('kotlin_preflight_cli', ROOT / 'tools/check_action_queue.py')
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)


class QueueKotlinPreflightTests(unittest.TestCase):
    def setUp(self):
        self.fixture = snapshot_fixture.NativeSnapshotTests('runTest')
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.root
        self.home = self.distribution('Kotlin distribution')
        self.options = {'kotlin_home': str(self.home), 'mod_sources': {}}
        for identifier in carts.MODS:
            source = self.fixture.project / ('Toolkit' if identifier == 'PZSurvivorToolkit' else identifier)
            self.fixture.mod(source, identifier)
            if identifier in ('PZSurvivorToolkit', 'PZToolkitJavaPatches'):
                self.options['mod_sources'][identifier] = str(source)
        self.fixture.write(self.fixture.game / 'ZombieBuddy.jar', 'fixture loader')
        for name in ('patch_jar', 'ffmpeg', 'ffprobe'):
            path = self.root / name
            self.fixture.write(path, 'explicit fixture dependency')
            path.chmod(0o755)
            self.options[name] = str(path)
        self.catalog = cli.load_catalog(['startup', carts.SP])

    def distribution(self, name, *, runtime_version=None):
        return kotlin_fixture.KotlinBuild('runTest').distribution(
            self.root / name, runtime_version=runtime_version)

    def invalid_distribution(self, case, name):
        home = self.distribution(name, runtime_version='2.2.0' if case == 'wrong runtime' else None)
        if case == 'missing compiler':
            (home / 'lib/kotlin-compiler.jar').unlink()
        return home

    def plan(self, home, *, campaign=False):
        jobs = [dict(id='startup', suite='startup', boundary='Fresh startup.')]
        jobs.append(dict(id='cart', suite=carts.SP, case='controls', kind='sp', language='RU',
                         boundary='Cart fixture after startup.',
                         options=dict(copy.deepcopy(self.options), kotlin_home=str(home))))
        plan = dict(game=str(self.fixture.game), jdk=str(self.fixture.jdk), jobs=jobs)
        if campaign:
            plan['campaign'] = [dict(id='fixtures', title='Fixture preparation',
                                     todo='TODO.md#fixtures', jobs=[job['id'] for job in jobs], gates=[])]
        return plan

    def arguments(self, plan, name, *, dry_run):
        path = self.root / (name + '.json')
        path.write_text(json.dumps(plan), encoding='utf-8')
        return argparse.Namespace(plan=path, output=self.root / name, dry_run=dry_run)

    def test_late_invalid_cart_stops_batch_and_campaign_before_first_profile(self):
        for campaign in (False, True):
            for dry_run in (False, True):
                for case in ('missing compiler', 'wrong runtime'):
                    with self.subTest(campaign=campaign, dry_run=dry_run, case=case):
                        name = f'batch-{campaign}-{dry_run}-{case}'
                        home = self.invalid_distribution(case, name + '-Kotlin')
                        args = self.arguments(self.plan(home, campaign=campaign), name, dry_run=dry_run)
                        with patch.object(cli, 'ROOT', self.fixture.project), \
                                patch.object(cli.native, 'prepare') as prepare, \
                                patch.object(cli.runner, 'run') as run, \
                                patch.object(carts, '_compile') as compile_cart, \
                                patch.object(native.shutil, 'copytree') as copy_mods, \
                                self.assertRaises(ValueError) as failure:
                            cli.batch(args, self.catalog)
                        message = str(failure.exception)
                        for text in ('Cart Kotlin preflight', build.KOTLIN_VERSION, str(home),
                                     'options.kotlin_home', 'KOTLIN_HOME'):
                            self.assertIn(text, message)
                        prepare.assert_not_called()
                        run.assert_not_called()
                        compile_cart.assert_not_called()
                        copy_mods.assert_not_called()
                        self.fixture.compile_mock.assert_not_called()
                        self.assertFalse(args.output.exists())

    def test_successful_dry_run_reports_resolved_home_without_profiles_or_processes(self):
        # Keep a noncanonical spelling in the plan to exercise the printed selection.
        selected_home = self.home / '..' / self.home.name
        for campaign in (False, True):
            with self.subTest(campaign=campaign):
                args = self.arguments(self.plan(selected_home, campaign=campaign),
                                      f'planned-{campaign}', dry_run=True)
                with patch.object(cli, 'ROOT', self.fixture.project), \
                        patch.object(cli.native, 'prepare') as prepare, \
                        patch.object(cli.runner, 'run') as run, \
                        patch.object(carts, '_compile') as compile_cart, \
                        patch.object(native.shutil, 'copytree') as copy_mods, \
                        patch('sys.stdout', new_callable=io.StringIO) as stdout:
                    self.assertEqual(cli.batch(args, self.catalog), 0)
                value = json.loads(stdout.getvalue())
                self.assertEqual(value['status'], 'planned')
                self.assertEqual([job['id'] for job in value['jobs']], ['startup', 'cart'])
                selected = value['jobs'][1]['selection']
                self.assertEqual(selected['options']['kotlin_home'], str(self.home.resolve()))
                self.assertEqual(value['sessions'][1]['selection']['options']['kotlin_home'],
                                 str(self.home.resolve()))
                self.assertNotIn('kotlin_home', value['jobs'][0]['selection']['options'])
                if campaign:
                    self.assertEqual(value['campaign']['status'], 'pending')
                prepare.assert_not_called()
                run.assert_not_called()
                compile_cart.assert_not_called()
                copy_mods.assert_not_called()
                self.fixture.compile_mock.assert_not_called()
                self.assertFalse(args.output.exists())

    def test_execution_retains_preflight_home_when_environment_changes_after_startup(self):
        for campaign in (False, True):
            with self.subTest(campaign=campaign):
                plan = self.plan(self.home, campaign=campaign)
                del plan['jobs'][1]['options']['kotlin_home']
                args = self.arguments(plan, f'executed-{campaign}', dry_run=False)
                prepared = []

                def prepare(project, output, game, jdk, selected, workshop, *, resource_wait=300):
                    prepared.append(copy.deepcopy(selected))
                    if selected['suite'] == 'startup':
                        os.environ['KOTLIN_HOME'] = str(self.root / 'changed Kotlin')
                    else:
                        self.assertEqual(adapters.preflight(selected), {'kotlin_home': str(self.home)})
                    output.mkdir()
                    (output / 'snapshot-hashes.json').write_text('{}')

                passed = dict(status='passed', functional={'status': 'passed'}, runtime={'status': 'clean'})
                def saved_report(output, *args):
                    (output / 'report.json').write_text(json.dumps(passed))
                    return passed
                with patch.dict(os.environ, {'KOTLIN_HOME': str(self.home)}), \
                        patch.object(cli, 'ROOT', self.fixture.project), \
                        patch.object(cli.native, 'prepare', side_effect=prepare), \
                        patch.object(cli.runner, 'run', return_value={'status': 'completed'}) as run, \
                        patch.object(cli, 'save_report', side_effect=saved_report), \
                        patch.object(cli.report, 'matrix', return_value={}), \
                        patch.object(cli.report, 'summary', return_value='checked'), \
                        patch.object(carts, '_compile') as compile_cart, \
                        patch('sys.stdout', new_callable=io.StringIO):
                    self.assertEqual(cli.batch(args, self.catalog), 0)
                self.assertEqual([selected['suite'] for selected in prepared], ['startup', carts.SP])
                self.assertEqual(prepared[1]['options']['kotlin_home'], str(self.home))
                self.assertEqual(run.call_count, 2)
                compile_cart.assert_not_called()
                self.fixture.compile_mock.assert_not_called()

    def test_native_prepare_rejects_invalid_kotlin_before_mod_or_save_copy(self):
        for case in ('missing compiler', 'wrong runtime'):
            with self.subTest(case=case):
                home = self.invalid_distribution(case, 'native-' + case + '-Kotlin')
                selection = dict(self.fixture.selection, suite=carts.SP, cases=['controls'],
                                 mods=list(carts.MODS), languages=['RU'],
                                 options=dict(copy.deepcopy(self.options), kotlin_home=str(home),
                                              world_template=str(self.root / 'saved-world')))
                output = self.root / ('native-' + case)
                with patch.object(native.shutil, 'copytree') as copy_mods, \
                        patch.object(snapshot_copy, 'copy_file') as copy_file, \
                        patch.object(native.worlds, 'validate') as validate_world, \
                        patch.object(native.worlds, 'restore') as restore_world, \
                        patch.object(carts, '_compile') as compile_cart, \
                        patch.object(native.admission, 'allocate_ports') as ports, \
                        self.assertRaises(ValueError) as failure:
                    native.prepare(self.fixture.project, output, self.fixture.game,
                                   self.fixture.jdk, selection)
                self.assertIn('Cart Kotlin preflight', str(failure.exception))
                self.assertIn(str(home), str(failure.exception))
                copy_mods.assert_not_called()
                copy_file.assert_not_called()
                validate_world.assert_not_called()
                restore_world.assert_not_called()
                compile_cart.assert_not_called()
                ports.assert_not_called()
                self.fixture.compile_mock.assert_not_called()
                self.assertFalse(output.exists())

    def test_noncart_selections_do_not_resolve_kotlin(self):
        plan = dict(game=str(self.fixture.game), jdk=str(self.fixture.jdk),
                    jobs=[dict(id='startup', suite='startup')])
        args = self.arguments(plan, 'noncart', dry_run=True)
        with patch.dict(os.environ, {'KOTLIN_HOME': str(self.root / 'missing Kotlin')}), \
                patch.object(carts, 'resolve_kotlin_home', side_effect=AssertionError('Unexpected Kotlin lookup')) as resolve, \
                patch('sys.stdout', new_callable=io.StringIO):
            self.assertEqual(cli.batch(args, self.catalog), 0)
            self.assertEqual(adapters.preflight(self.fixture.selection), {})
            output = self.fixture.prepare('health-without-Kotlin')
        resolve.assert_not_called()
        self.assertTrue((output / 'selection.json').is_file())
        self.assertFalse(args.output.exists())


if __name__ == '__main__':
    unittest.main()
