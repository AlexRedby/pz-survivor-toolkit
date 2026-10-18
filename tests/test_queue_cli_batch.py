"""Batch sequencing and failure reporting without native processes."""
import argparse
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

    def test_misspelled_cases_never_silently_runs_only_the_default_case(self):
        self.write_plan([{'id': 'typo', 'suite': 'engine', 'cases': ['repair', 'cancel']},
                         {'id': 'selected', 'suite': 'engine', 'case': 'missing-target,late-continuation'}])
        self.assertEqual(self.invoke(), 1)
        self.assertEqual([name for name, _ in self.calls], ['selected'])
        self.assertEqual(self.calls[0][1]['cases'], ['missing-target', 'late-continuation'])
        result = json.loads((self.args.output / 'batch-report.json').read_text())
        self.assertIn("use 'case'", result['jobs'][0]['error'])

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

    def test_missing_dependency_blocks_before_preparation_and_propagates_to_dependents(self):
        self.write_plan([{'id': 'blocked', 'suite': 'startup'},
                         {'id': 'candidate', 'suite': 'startup', 'control_job': 'blocked'},
                         {'id': 'reload', 'suite': 'startup', 'seed_job': 'candidate'},
                         {'id': 'independent', 'suite': 'startup'}])
        self.assertEqual(1, self.invoke())
        self.assertEqual(['blocked', 'independent'], [name for name, _ in self.calls])
        result = json.loads((self.args.output / 'batch-report.json').read_text())
        self.assertEqual(['blocked', 'blocked', 'blocked', 'passed'], [row['status'] for row in result['jobs']])
        for row, dependency in zip(result['jobs'][1:3], ('blocked', 'candidate')):
            self.assertIn('Dependency has no completed report: ' + dependency, row['error'])
            self.assertFalse(Path(row['run']).exists())
        self.assertEqual([], result['remaining'])

    def test_existing_failed_or_review_control_remains_available_for_comparison(self):
        self.write_plan([{'id': 'control', 'suite': 'startup'},
                         {'id': 'candidate', 'suite': 'startup', 'control_job': 'control'}])
        for status in ('failed', 'needs-review'):
            with self.subTest(status=status):
                self.args.output = self.root / status
                controls = []
                def save(output, catalog, control=None):
                    controls.append(control)
                    return {'status': status if output.name == 'control' else 'passed',
                            'functional': {'status': 'passed'}, 'runtime': {'status': 'clean'}}
                self.report = save
                self.assertEqual(1 if status == 'failed' else 2, self.invoke())
                self.assertEqual([None, (self.args.output / 'control').resolve()], controls)

    def test_interruption_preserves_unrun_jobs_and_stops_batch(self):
        self.write_plan([{'id': name, 'suite': 'video-recording'} for name in ('interrupt', 'not-run')])
        self.assertEqual(self.invoke(), 130)
        result = json.loads((self.args.output / 'batch-report.json').read_text())
        self.assertEqual(result['remaining'], ['not-run'])
        self.assertEqual(len(self.calls), 1)

    def test_interrupt_during_prepare_admission_or_report_keeps_batch_state(self):
        self.write_plan([{'id': 'current', 'suite': 'startup'}, {'id': 'not-run', 'suite': 'startup'}])
        original_prepare, original_run, original_report = self.prepare, self.run_job, self.report
        for stage in ('prepare', 'run_job', 'report'):
            with self.subTest(stage=stage):
                self.args.output = self.root / stage
                self.calls = []
                self.prepare, self.run_job, self.report = original_prepare, original_run, original_report
                def interrupt(*args, **kwargs):
                    raise KeyboardInterrupt()
                setattr(self, stage, interrupt)
                self.assertEqual(130, self.invoke())
                result = json.loads((self.args.output / 'batch-report.json').read_text())
                self.assertEqual('failed', result['status'])
                self.assertEqual(['not-run'], result['remaining'])
                self.assertEqual(1, len(result['jobs']))
                self.assertEqual('failed' if stage == 'report' else 'blocked', result['jobs'][0]['status'])
                self.assertEqual('Batch job interrupted', result['jobs'][0]['error'])
                self.assertFalse((self.args.output / 'not-run').exists())

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

    def test_cart_scene_flag_is_pinned_and_rejected_for_other_suites(self):
        command=['prepare',str(self.root/'cart'),'--game','/game','--jdk','/jdk',
                 '--suite','wooden_cart_motion','--cases','path','--cart-scene','male-full-corner',
                 '--cart-scene','female-empty-straight']
        with patch.object(cli.native,'prepare') as prepare:
            self.assertEqual(cli.main(command),0)
            selected=prepare.call_args.args[4]
            self.assertEqual(selected['options']['cart_scenes'],['male-full-corner','female-empty-straight'])
            prepare.reset_mock()
            command[command.index('wooden_cart_motion')]='video-recording'
            command[command.index('path')]='captures'
            self.assertEqual(cli.main(command),1)
            prepare.assert_not_called()

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

    def test_batch_vanilla_and_empty_mods_do_not_fall_back_to_suite_defaults(self):
        self.write_plan([{'id': 'vanilla', 'suite': 'startup', 'mode': 'native', 'mods': 'vanilla'},
                         {'id': 'empty', 'suite': 'startup', 'mode': 'native', 'mods': []},
                         {'id': 'wrong-suite', 'suite': 'video-recording', 'mode': 'native', 'mods': 'vanilla'}])
        self.assertEqual(1, self.invoke())
        self.assertEqual(['vanilla'], [name for name, _ in self.calls])
        self.assertEqual([], self.calls[0][1]['mods'])
        cli.native._validate(self.calls[0][1])

    def test_invalid_job_inputs_preserve_batch_report_and_later_jobs(self):
        jobs = [{'id': 'bad-options-' + str(i), 'suite': 'startup', 'options': value}
                for i, value in enumerate((None, [], 'bad'))]
        jobs += [{'id': 'bad-case-' + str(i), 'suite': 'startup', 'case': value}
                 for i, value in enumerate(([], ['loaded'], False, 0, ''))]
        jobs += [{'id': 'bad-sources-' + str(i), 'suite': 'startup', 'options': {'mod_sources': value}}
                 for i, value in enumerate((None, [], 'bad'))]
        self.write_plan(jobs + [{'id': 'valid', 'suite': 'startup'}])
        self.assertEqual(1, self.invoke())
        self.assertEqual(['valid'], [name for name, _ in self.calls])
        result = json.loads((self.args.output / 'batch-report.json').read_text())
        self.assertEqual(['blocked'] * len(jobs) + ['passed'], [job['status'] for job in result['jobs']])
        self.assertEqual([], result['remaining'])

    def test_job_source_overrides_merge_by_mod_id_without_mutating_plan(self):
        plan = {'game': '/game', 'jdk': '/jdk',
                'options': {'mod_sources': {'PZSurvivorToolkit': '/frozen/toolkit-a',
                                            'PZToolkitJavaPatches': '/frozen/java-a'},
                            'ffmpeg': '/tools/plan-ffmpeg', 'retained': True},
                'jobs': [{'id': 'toolkit', 'suite': 'startup',
                          'options': {'mod_sources': {'PZSurvivorToolkit': '/frozen/toolkit-b'},
                                      'ffmpeg': '/tools/job-ffmpeg'}},
                         {'id': 'java', 'suite': 'startup',
                          'options': {'mod_sources': {'PZToolkitJavaPatches': '/frozen/java-b'}}}]}
        original = json.dumps(plan, sort_keys=True)
        with patch.object(cli.report, 'read_json', return_value=plan):
            self.assertEqual(0, self.invoke())
        toolkit, java = [selection['options'] for _, selection in self.calls]
        self.assertEqual(toolkit['mod_sources'], {'PZSurvivorToolkit': '/frozen/toolkit-b',
                                                  'PZToolkitJavaPatches': '/frozen/java-a'})
        self.assertEqual(java['mod_sources'], {'PZSurvivorToolkit': '/frozen/toolkit-a',
                                               'PZToolkitJavaPatches': '/frozen/java-b'})
        self.assertEqual(toolkit['ffmpeg'], '/tools/job-ffmpeg')
        self.assertEqual(java['ffmpeg'], '/tools/plan-ffmpeg')
        self.assertTrue(toolkit['retained'] and java['retained'])
        self.assertEqual(json.dumps(plan, sort_keys=True), original)

    def test_job_source_map_cannot_hide_invalid_plan_map_or_stop_later_reports(self):
        for index, invalid in enumerate((None, [], 'bad')):
            with self.subTest(plan_sources=invalid):
                self.args.output = self.root / ('invalid-sources-' + str(index))
                self.plan.write_text(json.dumps({'game': '/game', 'jdk': '/jdk',
                    'options': {'mod_sources': invalid},
                    'jobs': [{'id': 'first', 'suite': 'startup',
                              'options': {'mod_sources': {'PZSurvivorToolkit': '/frozen/toolkit'}}},
                             {'id': 'clear', 'suite': 'startup', 'options': {'mod_sources': {}}},
                             {'id': 'later', 'suite': 'startup'}]}))
                self.assertEqual(1, self.invoke())
                self.assertEqual([], self.calls)
                result = json.loads((self.args.output / 'batch-report.json').read_text())
                self.assertEqual(['blocked'] * 3, [job['status'] for job in result['jobs']])
                self.assertTrue(all('mod_sources' in job['error'] for job in result['jobs']))
                self.assertEqual([], result['remaining'])

    def test_explicit_empty_job_sources_clear_plan_pins_for_native_vanilla(self):
        self.plan.write_text(json.dumps({'game': '/game', 'jdk': '/jdk',
            'options': {'mod_sources': {'PZSurvivorToolkit': '/frozen/toolkit'}, 'retained': True},
            'jobs': [{'id': 'vanilla', 'suite': 'startup', 'mode': 'native', 'mods': 'vanilla',
                      'options': {'mod_sources': {}}}]}))
        self.assertEqual(0, self.invoke())
        selected = self.calls[0][1]
        self.assertEqual([], selected['mods'])
        self.assertEqual({}, selected['options']['mod_sources'])
        self.assertTrue(selected['options']['retained'])
        cli.native._validate(selected)

    def test_invalid_plan_options_are_reported_for_every_unrun_job(self):
        for index, value in enumerate((None, [], 'bad')):
            with self.subTest(value=value):
                self.write_plan([{'id': 'first', 'suite': 'startup'}, {'id': 'second', 'suite': 'startup'}])
                plan = json.loads(self.plan.read_text())
                plan['options'] = value
                self.plan.write_text(json.dumps(plan))
                self.args.output = self.root / ('bad-plan-' + str(index))
                self.assertEqual(1, self.invoke())
                self.assertEqual([], self.calls)
                result = json.loads((self.args.output / 'batch-report.json').read_text())
                self.assertEqual(['blocked', 'blocked'], [job['status'] for job in result['jobs']])
                self.assertEqual([], result['remaining'])

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

    def test_dry_run_matches_execution_selection_without_preparing_or_writing(self):
        self.plan.write_text(json.dumps({'game': '/game', 'jdk': '/jdk',
            'resources': {'heap_mib': 1024}, 'resource_wait': 15,
            'options': {'mod_sources': {'PZSurvivorToolkit': '/candidate', 'PZToolkitJavaPatches': '/java'}},
            'sets': {'wishlist': ['reload']},
            'jobs': [{'id': 'control', 'suite': 'shared-wishlist', 'mode': 'native'},
                     {'id': 'seed', 'suite': 'shared-wishlist', 'case': 'standalone', 'control_job': 'control'},
                     {'id': 'reload', 'suite': 'shared-wishlist', 'case': 'reload', 'seed_job': 'seed',
                      'options': {'mod_sources': {'PZSurvivorToolkit': '/updated'}},
                      'resources': {'native_mib': 512}},
                     {'id': 'unrelated', 'suite': 'startup'}]}))
        original = self.plan.read_bytes()
        output = io.StringIO()
        with patch.object(cli.native, 'prepare') as prepare, patch.object(cli.runner, 'run') as run, \
                patch.object(cli.report, 'write_json') as write, patch('sys.stdout', output):
            self.assertEqual(0, cli.main(['batch', str(self.plan), str(self.args.output),
                                         '--set', 'wishlist', '--dry-run']))
        prepare.assert_not_called()
        run.assert_not_called()
        write.assert_not_called()
        self.assertFalse(self.args.output.exists())
        self.assertEqual(self.plan.read_bytes(), original)
        preview = json.loads(output.getvalue())
        self.assertEqual(preview['status'], 'planned')
        self.assertEqual([job['id'] for job in preview['jobs']], ['control', 'seed', 'reload'])
        self.assertEqual(preview['jobs'][1]['control'], str((self.args.output / 'control').resolve()))
        self.assertEqual(preview['jobs'][2]['selection']['options']['mod_sources'],
                         {'PZSurvivorToolkit': '/updated', 'PZToolkitJavaPatches': '/java'})
        self.assertEqual(preview['jobs'][2]['resource_wait'], 15)
        self.args.sets = ['wishlist']
        self.assertEqual(0, self.invoke())
        self.assertEqual([job['selection'] for job in preview['jobs']], [value for _, value in self.calls])

    def test_dry_run_rejects_bad_cases_before_any_output_or_launch(self):
        self.write_plan([{'id': 'bad-case', 'suite': 'startup', 'case': 'nonexistent'}])
        with patch.object(cli.native, 'prepare') as prepare, patch.object(cli.runner, 'run') as run, \
                patch('sys.stderr', io.StringIO()):
            self.assertEqual(1, cli.main(['batch', str(self.plan), str(self.args.output), '--dry-run']))
        prepare.assert_not_called()
        run.assert_not_called()
        self.assertFalse(self.args.output.exists())

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


class StatusTests(unittest.TestCase):
    def setUp(self):
        self.value = {'schema_version': 1,
            'running': [{'root': '/old/run', 'pid': 10, 'owner_alive': False, 'budget': {'exclusive': False},
                         'processes': [{'pid': 11}]}],
            'waiting': [{'root': '/new/run', 'pid': 12, 'position': 1, 'wait_seconds': 5,
                         'exclusive': True, 'reason': 'Legacy or exclusive native run is using the desktop'}],
            'prepared': [{'root': '/prepared', 'ports': [24000, 24001]}],
            'legacy_lock': {'path': '/lock', 'busy': True, 'exclusive': False},
            'limits': ['FIFO applies to updated runners only.']}

    def invoke(self, arguments):
        output = io.StringIO()
        with patch.object(cli.admission, 'status', return_value=self.value) as status, \
             patch.object(cli.report, 'read_json', side_effect=AssertionError('Status must not read catalog')), \
             patch.object(cli.runner, 'run', side_effect=AssertionError('Status must not launch')), \
             patch('sys.stdout', output):
            result = cli.main(arguments)
        status.assert_called_once_with(legacy_lock=cli.runner.LOCK)
        self.assertEqual(result, 0)
        return output.getvalue()

    def test_json_status_preserves_machine_readable_snapshot_without_launching(self):
        self.assertEqual(json.loads(self.invoke(['status', '--json'])), self.value)

    def test_text_status_shows_owners_fifo_position_reason_and_legacy_limits(self):
        value = self.invoke(['status'])
        for expected in ('Running: 1', '/old/run | PID 10 (owner exited)', 'game PIDs 11', 'Waiting: 1',
                         '#1 /new/run | PID 12', '5s | exclusive', self.value['waiting'][0]['reason'],
                         'Prepared port reservations: 1', 'Legacy lock: shared/busy', self.value['limits'][0]):
            self.assertIn(expected, value)

    def test_empty_status_and_legacy_exclusive_status(self):
        self.value.update(running=[], waiting=[], prepared=[])
        self.value['legacy_lock'].update(busy=False, exclusive=False)
        self.assertIn('Legacy lock: free', self.invoke(['status']))
        self.value['legacy_lock'].update(busy=True, exclusive=True)
        self.assertIn('Legacy lock: exclusive', self.invoke(['status']))

    def test_status_error_is_clear_and_does_not_claim_free_stand(self):
        error = io.StringIO()
        with patch.object(cli.admission, 'status', side_effect=RuntimeError('Cannot sample host resources')), \
             patch('sys.stderr', error):
            self.assertEqual(cli.main(['status', '--json']), 1)
        self.assertIn('ERROR: Cannot sample host resources', error.getvalue())


if __name__ == '__main__':
    unittest.main()
