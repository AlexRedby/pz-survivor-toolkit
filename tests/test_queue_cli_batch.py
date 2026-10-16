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


if __name__ == '__main__':
    unittest.main()
