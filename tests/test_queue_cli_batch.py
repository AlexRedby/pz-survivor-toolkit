"""Batch sequencing and failure reporting without native processes."""
import argparse
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
spec = importlib.util.spec_from_file_location('native_stand_cli', ROOT / 'tools/check_action_queue.py')
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)


class BatchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.catalog = {'suites': cli.adapters.definitions()}
        self.plan = self.root / 'plan.json'
        self.args = argparse.Namespace(plan=self.plan, output=self.root / 'batch')
        self.calls = []

    def write_plan(self, jobs):
        self.plan.write_text(json.dumps({'game': '/game', 'jdk': '/jdk', 'jobs': jobs}))

    def prepare(self, project, output, game, jdk, selection, workshop):
        output.mkdir()
        self.calls.append((output.name, selection))
        if output.name == 'blocked':
            raise ValueError('Missing declared dependency')

    def run_job(self, output, resource_wait=300):
        result = {'status': 'failed' if output.name == 'interrupt' else 'completed',
                  'interrupted': output.name == 'interrupt'}
        (output / 'execution.json').write_text(json.dumps(result))
        return result

    def report(self, output, catalog, control=None):
        return {'status': 'failed' if output.name == 'interrupt' else 'passed',
                'functional': {'status': 'passed'}, 'runtime': {'status': 'clean'}}

    def invoke(self):
        with patch.object(cli.native, 'prepare', side_effect=self.prepare), \
             patch.object(cli.runner, 'run', side_effect=self.run_job), \
             patch.object(cli, 'save_report', side_effect=self.report), \
             patch.object(cli.report, 'matrix', return_value={'rows': []}), \
             patch.object(cli.report, 'summary', return_value='checked'):
            return cli.batch(self.args, self.catalog)

    def test_one_client_mp_and_ru_suite_defaults(self):
        self.write_plan([{'id': 'animal', 'suite': 'animal-trailer'}, {'id': 'tags', 'suite': 'item-tags'}])
        self.assertEqual(self.invoke(), 0)
        animal, tags = [selection for _, selection in self.calls]
        self.assertEqual((animal['kind'], animal['clients'], animal['languages']), ('mp', 1, ['EN']))
        self.assertEqual(tags['languages'], ['RU'])
        self.assertEqual(tags['cases'], ['scenes'])

    def test_blocked_job_does_not_hide_remaining_jobs(self):
        self.write_plan([{'id': name, 'suite': 'video-recording'} for name in ('blocked', 'next')])
        self.assertEqual(self.invoke(), 1)
        result = json.loads((self.args.output / 'batch-report.json').read_text())
        self.assertEqual([row['status'] for row in result['jobs']], ['blocked', 'passed'])
        self.assertEqual(result['remaining'], [])

    def test_reload_seed_resolves_only_completed_prior_job(self):
        self.write_plan([{'id': 'seed', 'suite': 'shared-wishlist', 'case': 'standalone'},
                         {'id': 'reload', 'suite': 'shared-wishlist', 'case': 'reload', 'seed_job': 'seed'}])
        self.assertEqual(self.invoke(), 0)
        self.assertEqual(self.calls[1][1]['options']['seed_run'], str((self.args.output / 'seed').resolve()))

    def test_interruption_preserves_unrun_jobs_and_stops_batch(self):
        self.write_plan([{'id': name, 'suite': 'video-recording'} for name in ('interrupt', 'not-run')])
        self.assertEqual(self.invoke(), 130)
        result = json.loads((self.args.output / 'batch-report.json').read_text())
        self.assertEqual(result['remaining'], ['not-run'])
        self.assertEqual(len(self.calls), 1)

    def test_budget_and_wait_are_passed_per_job_and_ports_default_to_auto(self):
        self.plan.write_text(json.dumps({'game': '/game', 'jdk': '/jdk',
            'resources': {'heap_mib': 1024, 'cpu_per_instance': 0.5}, 'resource_wait': 15,
            'jobs': [{'id': 'custom', 'suite': 'video-recording', 'resources': {'native_mib': 512}}]}))
        waits = []
        original = self.run_job
        def run_job(output, resource_wait=300):
            waits.append(resource_wait)
            return original(output, resource_wait)
        self.run_job = run_job
        self.assertEqual(self.invoke(), 0)
        resources = self.calls[0][1]['resources']
        self.assertEqual((resources['heap_mib'], resources['native_mib'], resources['cpu_per_instance']), (1024, 512, 0.5))
        self.assertTrue(self.calls[0][1]['ports_auto'])
        self.assertEqual(waits, [15])

    def test_prepare_cli_parses_budget_and_exclusive_without_launching(self):
        with patch.object(cli.native, 'prepare') as prepare:
            result = cli.main(['prepare', str(self.root / 'fresh'), '--game', '/game', '--jdk', '/jdk',
                              '--suite', 'video-recording', '--heap-mib', '1536', '--native-mib', '768',
                              '--cpu-per-instance', '0.75', '--exclusive'])
        self.assertEqual(result, 0)
        selection = prepare.call_args.args[4]
        self.assertEqual(selection['resources'], {'heap_mib': 1536, 'native_mib': 768, 'cpu_per_instance': 0.75, 'exclusive': True})
        self.assertTrue(selection['ports_auto'])

    def test_duplicate_or_escaping_ids_fail_before_any_preparation(self):
        for names in [('same', 'same'), ('../escape', 'next')]:
            self.write_plan([{'id': name, 'suite': 'video-recording'} for name in names])
            with self.assertRaises(ValueError):
                self.invoke()
            self.assertFalse(self.args.output.exists())

    def test_explicit_empty_cases_never_broadens_to_the_suite_default(self):
        output = self.root / 'empty-cases'
        with patch.object(cli.native, 'prepare') as prepare:
            result = cli.main(['prepare', str(output), '--game', '/game', '--jdk', '/jdk', '--cases', ''])
        self.assertEqual(1, result)
        prepare.assert_not_called()
        self.assertFalse(output.exists())

    def test_vanilla_selection_is_explicit_and_only_for_native_startup(self):
        command = ['prepare', str(self.root / 'vanilla'), '--game', '/game', '--jdk', '/jdk',
                   '--suite', 'startup', '--mode', 'native', '--mods', 'vanilla']
        with patch.object(cli.native, 'prepare') as prepare:
            self.assertEqual(0, cli.main(command))
        selected = prepare.call_args.args[4]
        self.assertEqual([], selected['mods'])
        cli.native._validate(selected)
        for changes in ({'mode': 'toolkit'}, {'suite': 'health'}, {'mods': None}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                cli.native._validate(dict(selected, **changes))
        with patch.object(cli.native, 'prepare') as prepare:
            self.assertEqual(1, cli.main(command + ['--mode', 'toolkit']))
        prepare.assert_not_called()

    def test_explicit_empty_jobs_never_broadens_to_the_full_plan(self):
        self.write_plan([{'id': 'wanted', 'suite': 'item-tags'}, {'id': 'unrelated', 'suite': 'video-recording'}])
        self.args.jobs = ''
        with self.assertRaisesRegex(ValueError, '--jobs requires'):
            self.invoke()
        self.assertEqual([], self.calls)
        self.assertFalse(self.args.output.exists())

    def test_selected_set_includes_only_its_control_and_seed_dependencies(self):
        jobs = [{'id': 'control', 'suite': 'shared-wishlist'},
                {'id': 'seed', 'suite': 'shared-wishlist', 'control_job': 'control'},
                {'id': 'reload', 'suite': 'shared-wishlist', 'seed_job': 'seed'},
                {'id': 'unrelated', 'suite': 'video-recording'}]
        self.write_plan(jobs)
        plan = json.loads(self.plan.read_text())
        plan['sets'] = {'wishlist': ['reload']}
        self.plan.write_text(json.dumps(plan))
        self.args.sets = ['wishlist']
        self.assertEqual(self.invoke(), 0)
        self.assertEqual([name for name, _ in self.calls], ['control', 'seed', 'reload'])

    def test_disabled_dependency_unknown_selection_and_cycle_fail_before_preparation(self):
        plan = {'jobs': [{'id': 'control'}, {'id': 'candidate', 'control_job': 'control'}]}
        for kwargs in ({'only': 'unknown'}, {'only': 'candidate', 'skip': 'control'}, {'sets': ['unknown']}):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                cli.selected_jobs(plan, **kwargs)
        with self.assertRaisesRegex(ValueError, 'Cyclic'):
            cli.selected_jobs({'jobs': [{'id': 'a', 'seed_job': 'b'}, {'id': 'b', 'seed_job': 'a'}]}, only='a')
        with self.assertRaisesRegex(ValueError, 'precede'):
            cli.selected_jobs({'jobs': [{'id': 'candidate', 'control_job': 'control'}, {'id': 'control'}]})

    def test_plan_world_options_are_kept_while_unselected_jobs_do_not_prepare(self):
        self.write_plan([{'id': 'tags', 'suite': 'item-tags'}, {'id': 'unrelated', 'suite': 'video-recording'}])
        plan = json.loads(self.plan.read_text())
        plan['options'] = {'world_template': '/frozen/world'}
        self.plan.write_text(json.dumps(plan))
        self.args.jobs = 'tags'
        self.assertEqual(self.invoke(), 0)
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.calls[0][1]['options']['world_template'], '/frozen/world')

    def test_shipped_pack_plan_targeted_sets_resolve_only_their_dependencies(self):
        plan = json.loads((ROOT / 'tests/native_queue/plans/pack-regression.example.json').read_text())
        self.assertEqual(['craft'], [job['id'] for job in cli.selected_jobs(plan, sets=['craft'])])
        self.assertEqual(['wishlist-control', 'wishlist'], [job['id'] for job in cli.selected_jobs(plan, sets=['wishlist'])])
        self.assertEqual(['tags-control', 'tags', 'video-control', 'video'],
                         [job['id'] for job in cli.selected_jobs(plan, sets=['tags', 'video'])])


if __name__ == '__main__':
    unittest.main()
