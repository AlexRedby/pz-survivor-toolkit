"""Explicit session grouping saves launches without mixing incompatible lifecycles."""
import argparse
import copy
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
spec = importlib.util.spec_from_file_location('session_batch_cli', ROOT / 'tools/check_action_queue.py')
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)


class BatchSessionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.args = argparse.Namespace(plan=self.root / 'plan.json', output=self.root / 'run')
        self.catalog = {'suites': cli.adapters.definitions()}
        self.jobs = [dict(id='torch-' + case, suite='torch-refill', case=case,
                         session='torch-sp', kind='sp', language='EN', timeout=120)
                     for case in ('trunk-retained', 'root-retained', 'trunk-unmarked')]
        self.plan = dict(game='/game', jdk='/jdk', jobs=self.jobs)
        self.calls, self.runs, self.report_paths = [], [], []
        self.report_status = 'passed'

    def invoke(self):
        self.args.plan.write_text(json.dumps(self.plan))
        def prepare(project, output, game, jdk, selection, workshop):
            output.mkdir()
            self.calls.append(copy.deepcopy(selection))
        def run(output, resource_wait=300):
            self.runs.append(output)
            value = {'status': 'completed', 'processes': {'client1': {'pid': 123}}}
            (output / 'execution.json').write_text(json.dumps(value))
            return value
        def report(output, catalog, control=None):
            self.report_paths.append(output)
            return {'status': self.report_status,
                    'functional': {'status': self.report_status}, 'runtime': {'status': 'clean'}}
        with patch.object(cli.native, 'prepare', side_effect=prepare), \
             patch.object(cli.runner, 'run', side_effect=run), \
             patch.object(cli, 'save_report', side_effect=report), \
             patch.object(cli.report, 'matrix', return_value={'rows': []}), \
             patch.object(cli.report, 'summary', return_value='checked'), \
             patch('sys.stdout', io.StringIO()) as stdout:
            result = cli.batch(self.args, self.catalog)
        return result, stdout.getvalue()

    def test_three_jobs_share_one_native_lifecycle_and_one_full_report(self):
        result, _ = self.invoke()
        self.assertEqual(result, 0)
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.calls[0]['cases'], [job['case'] for job in self.jobs])
        self.assertEqual(self.calls[0]['timeout_seconds'], 360)
        self.assertEqual(len(self.runs), 1)
        self.assertEqual(len(self.report_paths), 1)
        value = json.loads((self.args.output / 'batch-report.json').read_text())
        self.assertEqual([row['id'] for row in value['jobs']], [job['id'] for job in self.jobs])
        self.assertEqual(len({row['run'] for row in value['jobs']}), 1)
        self.assertEqual([row['cases'] for row in value['jobs']], [[job['case']] for job in self.jobs])
        self.assertEqual(value['remaining'], [])
        self.assertEqual(value['launches_planned'], 1)
        self.assertEqual(len(value['sessions']), 1)

    def test_sp_and_host_are_two_explicit_launch_groups(self):
        host = [dict(job, id='host-' + job['id'], session='torch-host', kind='mp', options={'mp_host': True})
                for job in self.jobs]
        self.plan['jobs'] = self.jobs + host
        result, _ = self.invoke()
        self.assertEqual(result, 0)
        self.assertEqual([row['kind'] for row in self.calls], ['sp', 'mp'])
        self.assertEqual([len(row['cases']) for row in self.calls], [3, 3])

    def test_dry_run_shows_combined_selection_without_profiles_or_processes(self):
        self.args.dry_run = True
        result, text = self.invoke()
        value = json.loads(text)
        self.assertEqual(result, 0)
        self.assertEqual(value['launches'], 1)
        self.assertEqual(value['jobs_without_reuse'], 3)
        self.assertEqual(value['sessions'][0]['selection']['cases'], [job['case'] for job in self.jobs])
        self.assertEqual(len({row['run'] for row in value['jobs']}), 1)
        self.assertFalse(self.args.output.exists())
        self.assertEqual(self.calls + self.runs, [])

    def test_incompatible_member_rejected_before_even_an_independent_first_job(self):
        changes = [dict(kind='mp', options={'mp_host': True}), dict(language='RU'),
                   dict(mods=['PZSurvivorToolkit', 'CleanUI']), dict(mode='native'),
                   dict(timeout=121), dict(ports=[20001, 20002]), dict(resource_wait=15),
                   dict(resources={'heap_mib': 4096}),
                   dict(options={'mod_sources': {'PZSurvivorToolkit': '/different/source'}}),
                   dict(options={'desktop_mode': 'aerospace'}), dict(options={'sandbox': {'DayLength': 4}})]
        baseline = copy.deepcopy(self.jobs)
        for change in changes:
            with self.subTest(change=change):
                jobs = copy.deepcopy(baseline)
                jobs[1].update(change)
                self.plan['jobs'] = [dict(id='first', suite='startup')] + jobs
                with self.assertRaises(ValueError):
                    self.invoke()
                self.assertFalse(self.args.output.exists())
                self.assertEqual(self.calls, [])

    def test_cross_suite_and_unsupported_suite_fail_closed(self):
        self.jobs[1].update(suite='plastic-battery', case='native-recipes')
        self.catalog['suites']['plastic-battery']['shared_session'] = True
        with self.assertRaisesRegex(ValueError, 'Incompatible'):
            self.invoke()
        self.plan['jobs'] = [dict(id='not-migrated', suite='startup', session='shared')]
        with self.assertRaisesRegex(ValueError, 'no shared-session contract'):
            self.invoke()
        self.assertEqual(self.calls, [])

    def test_case_overlap_and_noncontiguous_groups_rejected(self):
        self.jobs[1]['case'] = self.jobs[0]['case']
        with self.assertRaisesRegex(ValueError, 'unique'):
            self.invoke()
        self.jobs[1]['case'] = 'root-retained'
        self.plan['jobs'].insert(1, dict(id='gap', suite='startup'))
        with self.assertRaisesRegex(ValueError, 'contiguous'):
            self.invoke()

    def test_group_members_cannot_supply_or_consume_control_or_seed(self):
        base = copy.deepcopy(self.jobs)
        for field in ('control_job', 'seed_job'):
            with self.subTest(field=field, direction='consumer'):
                jobs = copy.deepcopy(base)
                jobs[0][field] = 'seed'
                self.plan['jobs'] = [dict(id='seed', suite='startup')] + jobs
                with self.assertRaisesRegex(ValueError, 'dependencies'):
                    self.invoke()
            with self.subTest(field=field, direction='provider'):
                self.plan['jobs'] = copy.deepcopy(base) + [dict(id='later', suite='startup', **{field: base[0]['id']})]
                with self.assertRaisesRegex(ValueError, 'dependencies'):
                    self.invoke()
        self.assertEqual(self.calls, [])

    def test_templates_and_invalid_session_labels_rejected(self):
        base = copy.deepcopy(self.jobs)
        for key in ('world_template', 'seed_run', 'startup_connection'):
            with self.subTest(key=key):
                self.plan['jobs'] = [dict(job, options={key: '/prior/world'}) for job in base]
                with self.assertRaisesRegex(ValueError, 'fresh lifecycle'):
                    self.invoke()
        for value in (None, '', False, [], '../bad'):
            with self.subTest(label=value):
                self.plan['jobs'] = [dict(base[0], session=value)]
                with self.assertRaisesRegex(ValueError, 'Session IDs'):
                    self.invoke()

    def test_invalid_member_deadlines_cannot_become_valid_when_summed(self):
        base = copy.deepcopy(self.jobs)
        for value in (True, '120', 0, -1, None):
            with self.subTest(timeout=value):
                self.plan['jobs'] = [dict(job, timeout=value) for job in base]
                with self.assertRaises(ValueError):
                    self.invoke()
                self.assertFalse(self.args.output.exists())
        self.assertEqual(self.calls, [])

    def test_bool_numeric_option_difference_is_not_a_matching_setting(self):
        self.jobs[0]['options'] = {'fixture_flag': True}
        self.jobs[1]['options'] = {'fixture_flag': 1}
        with self.assertRaisesRegex(ValueError, 'Incompatible'):
            self.invoke()

    def test_invalid_session_wait_rejected_before_profiles(self):
        for value in (True, '300', -1, float('inf'), float('nan')):
            with self.subTest(wait=value):
                self.plan['resource_wait'] = value
                with self.assertRaises(ValueError):
                    self.invoke()
                self.assertFalse(self.args.output.exists())

    def test_targeted_selection_does_not_run_omitted_session_members(self):
        self.args.jobs = self.jobs[1]['id']
        result, _ = self.invoke()
        self.assertEqual(result, 0)
        self.assertEqual(self.calls[0]['cases'], ['root-retained'])
        value = json.loads((self.args.output / 'batch-report.json').read_text())
        self.assertEqual([row['id'] for row in value['jobs']], [self.jobs[1]['id']])

    def test_shared_run_failure_is_never_reported_as_individual_success(self):
        self.report_status = 'failed'
        result, _ = self.invoke()
        self.assertEqual(result, 1)
        value = json.loads((self.args.output / 'batch-report.json').read_text())
        self.assertEqual([row['status'] for row in value['jobs']], ['failed'] * 3)
        self.assertEqual(len(self.report_paths), 1)


if __name__ == '__main__':
    unittest.main()
