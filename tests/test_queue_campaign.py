"""Campaign accounting must keep missing acceptance and partial selections visible."""
import argparse
import copy
import importlib.util
import io
import json
from pathlib import Path
import re
import os
import subprocess
import sys
import tempfile
import time
import types
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import campaign
from JavaPatches.tests.test_build_kotlin import KotlinBuild
spec = importlib.util.spec_from_file_location('campaign_cli', ROOT / 'tools/check_action_queue.py')
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)


class CampaignTests(unittest.TestCase):
    def setUp(self):
        self.admission_root = tempfile.TemporaryDirectory()
        self.addCleanup(self.admission_root.cleanup)
        directory = Path(self.admission_root.name)
        for context in (
                patch.object(cli.admission, 'STATE', directory / 'state'),
                patch.object(cli.admission, 'LEGACY_LOCK', directory / 'legacy.lock'),
                patch.object(cli.admission.host, 'sample', return_value={
                    'processes': [], 'total_memory': 16 * 1024**3, 'available_memory': 12 * 1024**3, 'cpu_count': 8})):
            context.start()
            self.addCleanup(context.stop)
        self.jobs = [dict(id='first', suite='startup', kind='sp', boundary='Fresh startup.'),
                     dict(id='second', suite='startup', kind='mp', boundary='Separate multiplayer topology.')]
        self.plan = dict(game='/game', jdk='/jdk', jobs=self.jobs, campaign=[
            dict(id='startup', title='Startup', todo='TODO.md#startup', jobs=['first', 'second'], gates=[])])

    def test_full_pass_requires_every_job_and_no_manual_or_missing_fixture_gate(self):
        passed = [dict(id=job['id'], status='passed') for job in self.jobs]
        self.assertEqual(campaign.build(self.plan, self.jobs, passed)['status'], 'passed')
        self.assertEqual(campaign.build(self.plan, self.jobs[:1], passed[:1])['status'], 'pending')
        self.plan['campaign'][0]['gates'] = ['Inspect the actual second-player view.']
        value = campaign.build(self.plan, self.jobs, passed)
        self.assertEqual(value['status'], 'pending')
        self.assertEqual(value['remaining_gates'], 1)
        self.assertEqual(value['blocks'][0]['gates'], self.plan['campaign'][0]['gates'])

    def test_dry_run_and_capture_never_become_acceptance(self):
        value = campaign.build(self.plan, self.jobs[:1], planned=True)
        self.assertEqual([row['status'] for row in value['blocks'][0]['jobs']], ['planned', 'not-selected'])
        for status in ('captured', 'needs-review', 'failed', 'blocked'):
            value = campaign.build(self.plan, self.jobs, [dict(id='first', status='passed'), dict(id='second', status=status)])
            self.assertEqual(value['blocks'][0]['status'], 'failed' if status in ('failed','blocked') else 'needs-review')
            self.assertNotEqual(value['status'], 'passed')

    def test_unknown_omitted_or_duplicate_work_is_rejected(self):
        edits = [lambda p:p['campaign'][0]['jobs'].append('unknown'),
                 lambda p:p['campaign'][0]['jobs'].pop(),
                 lambda p:p['campaign'][0]['jobs'].append('first'),
                 lambda p:p['campaign'].append(copy.deepcopy(p['campaign'][0])),
                 lambda p:p['jobs'][0].pop('boundary'),
                 lambda p:p['campaign'][0].update(jobs=[], gates=[])]
        for edit in edits:
            plan = copy.deepcopy(self.plan); edit(plan)
            with self.subTest(plan=plan), self.assertRaises(ValueError): campaign.validate(plan)

    def test_late_invalid_environment_stops_campaign_before_first_preparation(self):
        self.jobs[1].update(suite='torch-refill', case='root-retained', kind='mp', language='RU')
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); plan=root/'plan.json'; plan.write_text(json.dumps(self.plan))
            args=argparse.Namespace(plan=plan, output=root/'run')
            with patch.object(cli.native,'source_inputs',side_effect=lambda project,game,jdk,selection,*a,**kw: cli.adapters.get(selection['suite']).validate(selection)), patch.object(cli.native,'prepare') as prepare, self.assertRaises(ValueError):
                cli.batch(args,cli.load_catalog())
            prepare.assert_not_called(); self.assertFalse(args.output.exists())

    def test_late_invalid_viewport_is_rejected_before_first_profile(self):
        self.jobs[1]['options']={'window_size':[1,1]}
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);path=root/'plan.json';path.write_text(json.dumps(self.plan))
            args=argparse.Namespace(plan=path,output=root/'run',dry_run=True)
            with patch.object(cli.native,'source_inputs'), patch.object(cli.native,'prepare') as prepare, self.assertRaisesRegex(ValueError,'window_size'):
                cli.batch(args,cli.load_catalog())
            prepare.assert_not_called();self.assertFalse(args.output.exists())

    def test_campaign_preflight_inherits_resource_wait_and_applies_job_override(self):
        self.plan['resource_wait'] = 11
        self.jobs[1]['resource_wait'] = 23
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            path = root / 'plan.json'
            path.write_text(json.dumps(self.plan))
            args = argparse.Namespace(plan=path, output=root / 'run', dry_run=True)
            with patch.object(cli.native, 'source_inputs', side_effect=lambda *args, **kwargs: print('WAIT preparation')) as sources, \
                    patch.object(cli.native, 'prepare') as prepare, \
                    patch('sys.stdout', io.StringIO()) as output, patch('sys.stderr', io.StringIO()) as errors:
                self.assertEqual(cli.batch(args, cli.load_catalog()), 0)
            self.assertEqual(json.loads(output.getvalue())['status'], 'planned')
            self.assertEqual(errors.getvalue(), 'WAIT preparation\nWAIT preparation\n')
            self.assertEqual([call.kwargs['resource_wait'] for call in sources.call_args_list], [11, 23])
            prepare.assert_not_called()
            self.assertFalse(args.output.exists())

    def test_failed_or_unreviewed_control_blocks_candidate_but_not_independent_job(self):
        for status in ('failed', 'needs-review'):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as folder:
                root=Path(folder); plan=copy.deepcopy(self.plan)
                plan['jobs'][1]['control_job']='first'
                plan['jobs'].append(dict(id='independent',suite='startup',boundary='Independent fixture.'))
                plan['campaign'][0]['jobs'].append('independent')
                path=root/'plan.json';path.write_text(json.dumps(plan))
                args=argparse.Namespace(plan=path,output=root/'run')
                prepared=[]
                def prepare(project,output,*args,**kwargs):
                    output.mkdir();prepared.append(output.name)
                    (output/'snapshot-hashes.json').write_text('{}')
                def run(output,**kwargs):
                    (output/'execution.json').write_text('{}');return {}
                def report(output,*args):
                    value=dict(status=status if output.name=='first' else 'passed',functional={'status':'passed'},runtime={'status':'clean'})
                    (output/'report.json').write_text(json.dumps(value));return value
                with patch.object(cli.native,'source_inputs'), patch.object(cli.native,'prepare',side_effect=prepare), patch.object(cli.runner,'run',side_effect=run), patch.object(cli,'save_report',side_effect=report), patch.object(cli.report,'summary',return_value='checked'), patch.object(cli.report,'matrix',return_value={}), patch('sys.stdout',io.StringIO()):
                    self.assertEqual(cli.batch(args,cli.load_catalog()),1)
                self.assertEqual(prepared,['first','independent'])
                value=json.loads((args.output/'batch-report.json').read_text())
                self.assertEqual(value['jobs'][1]['status'],'blocked')
                self.assertIn('passed report with clean runtime',value['jobs'][1]['error'])
                self.assertEqual(value['campaign']['status'],'failed')

    def test_late_source_override_is_checked_without_preparing_any_profile(self):
        from tests.test_queue_native_snapshot import NativeSnapshotTests
        fixture=NativeSnapshotTests();fixture.setUp();self.addCleanup(fixture.doCleanups)
        self.plan.update(game=str(fixture.game),jdk=str(fixture.jdk))
        self.plan['jobs'][1]['options']={'mod_sources':{'PZSurvivorToolkit':str(fixture.root/'missing')}}
        path=fixture.root/'plan.json';path.write_text(json.dumps(self.plan))
        args=argparse.Namespace(plan=path,output=fixture.root/'run')
        with patch.object(cli,'ROOT',fixture.project), patch.object(cli.native,'prepare') as prepare, self.assertRaisesRegex(ValueError,'Mod ID must resolve exactly once'):
            cli.batch(args,cli.load_catalog())
        prepare.assert_not_called();fixture.compile_mock.assert_not_called();self.assertFalse(args.output.exists())

    def test_same_pack_hashes_once_in_preflight_but_preparation_rechecks(self):
        from tests.test_queue_native_snapshot import NativeSnapshotTests
        fixture=NativeSnapshotTests();fixture.setUp();self.addCleanup(fixture.doCleanups)
        selection=dict(fixture.selection,options={'pack_lock':str(fixture.root/'pack.json')})
        pinned={'PZSurvivorToolkit':str(fixture.project/'Toolkit')}
        fixture.write(fixture.root/'pack.json','{}')
        fixture.write(fixture.project/'SurvivorQoL-selected.ini','Mods=PZSurvivorToolkit\n')
        cache={}
        with patch.object(cli.native.pack,'validate',return_value=pinned) as validate:
            for _ in range(3): cli.native.source_inputs(fixture.project,fixture.game,fixture.jdk,selection,pack_cache=cache)
            self.assertEqual(validate.call_count,1)
            fixture.prepare(options=selection['options'])
            self.assertGreater(validate.call_count,1)
        self.assertTrue((fixture.root/'run').is_dir())

    def test_example_covers_every_outstanding_todo_block_without_erasing_gates(self):
        plan=json.loads((ROOT/'tests/native_queue/plans/in-game-campaign.example.json').read_text())
        campaign.validate(plan)
        todo=(ROOT/'TODO.md').read_text().split('# Batch action-queue audit')[0]
        expected={line[4:] for line in todo.splitlines() if line.startswith('### ')
                  and line!='### Remaining campaign migration'}
        self.assertLessEqual(expected,{item['title'] for item in plan['campaign']})
        items={item['title']:item for item in plan['campaign']}
        for title in ('Vehicle ownership desync','Medical visual packet reproduction',
                      'Item catalogue test world','Legacy Host launchers','New Music selection'):
            self.assertTrue(items[title]['gates'],title)
        self.assertEqual(next(job for job in plan['jobs'] if job['id']=='wishlist-host')['control_job'],'wishlist-host-control')
        for identifier in ('wishlist-host-control', 'wishlist-host'):
            self.assertEqual(next(job for job in plan['jobs'] if job['id']==identifier)['case'], 'visual,full')
        smart = next(job for job in plan['jobs'] if job['id']=='smart-deposit-host')
        self.assertEqual((smart['kind'], smart['case'], smart['options']), ('mp', 'partial', {'mp_host': True}))
        self.assertIn('smart-deposit-host', plan['sets']['inventory'])
        self.assertIn('smart-deposit-host', plan['sets']['host'])
        self.assertNotIn('smart-deposit-host', plan['sets']['sp'])
        peer = next(job for job in plan['jobs'] if job['id']=='warehouse-peer-host')
        self.assertEqual((peer['suite'], peer['case'], peer['kind'], peer['options']),
                         ('warehouse-workload', 'peer-edits', 'mp', {'mp_host': True}))
        for name in ('inventory', 'qualification', 'host', 'full'):
            self.assertIn('warehouse-peer-host', plan['sets'][name])
        self.assertNotIn('warehouse-peer-host', plan['sets']['sp'])
        self.assertIn('warehouse-peer-host', items['Warehouse client workload']['jobs'])
        self.assertTrue(items['Warehouse client workload']['gates'])

    def test_full_example_preflights_and_keeps_subset_report_without_launching(self):
        plan=json.loads((ROOT/'tests/native_queue/plans/in-game-campaign.example.json').read_text())
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); tool=root/'input'; tool.write_text('fixture input'); tool.chmod(0o700)
            options=plan['options']
            options['kotlin_home']=str(KotlinBuild(methodName='runTest').distribution(root/'kotlin'))
            options.update(patch_jar=str(tool),ffmpeg=str(tool),ffprobe=str(tool))
            options['mod_sources']={key:str(root) for key in options['mod_sources']}
            for job in plan['jobs']:
                opt=job.get('options',{})
                if 'mesh_fbx' in opt: opt['mesh_fbx']=str(tool)
                if 'cart_mesh_fbx' in opt: opt['cart_mesh_fbx']={key:str(tool) for key in opt['cart_mesh_fbx']}
            path=root/'plan.json';path.write_text(json.dumps(plan))
            args=argparse.Namespace(plan=path,output=root/'run',dry_run=True,sets=['full'])
            # Planner-only inputs; native cart analyzers are deliberately not executed.
            with patch.dict(sys.modules, {'numpy': types.ModuleType('numpy')}), patch.object(cli.native,'source_inputs',side_effect=lambda project,game,jdk,selection,*a,**kw: cli.adapters.get(selection['suite']).validate(selection)), patch.object(cli.native,'prepare') as prepare, patch.object(cli.runner,'run') as run, patch('sys.stdout',io.StringIO()) as out:
                self.assertEqual(cli.batch(args,cli.load_catalog()),0)
            prepare.assert_not_called();run.assert_not_called();self.assertFalse(args.output.exists())
            value=json.loads(out.getvalue())
            self.assertLess(value['launches'],len(plan['jobs']))
            self.assertEqual(value['campaign']['status'],'pending')
            self.assertEqual(len(value['campaign']['blocks']),len(plan['campaign']))
            self.assertTrue(all(row['boundary'] for row in value['sessions'] if len(row['jobs'])==1))
            args.sets=['qualification']
            with patch.object(cli.native,'source_inputs',side_effect=lambda project,game,jdk,selection,*a,**kw: cli.adapters.get(selection['suite']).validate(selection)), patch('sys.stdout',io.StringIO()) as out: self.assertEqual(cli.batch(args,cli.load_catalog()),0)
            value=json.loads(out.getvalue())
            self.assertEqual(value['jobs_without_reuse'],len(plan['sets']['qualification']))
            self.assertTrue(any(job['status']=='not-selected' for item in value['campaign']['blocks'] for job in item['jobs']))


class CampaignResumeTests(unittest.TestCase):
    """Normal resume refreshes anchored accounting using real strict health reports."""
    def setUp(self):
        from tests.test_queue_report import QueueReportTests
        self.fixtures = QueueReportTests()
        self.fixtures.setUp()
        self.addCleanup(self.fixtures.doCleanups)
        self.root, self.catalog = self.fixtures.base, self.fixtures.catalog
        self.output, self.path = self.root / 'batch', self.root / 'plan.json'
        self.observations, self.launches = {}, []
        self.blocked = {'first'}
        self.plan = dict(game='/game', jdk='/jdk', failure_policy='stop-on-setup-failure',
            jobs=[self.job('first')], campaign=[dict(id='health', title='Health', todo='TODO.md#health',
                                                   jobs=['first'], gates=[])])

    @staticmethod
    def job(identifier, **fields):
        return dict(id=identifier, suite='health', kind='sp', case='bandageApply',
                    boundary='Independent native lifecycle.', **fields)

    def prepare(self, project, output, game, jdk, selection, workshop, **kwargs):
        output = output.resolve()
        capture = self.fixtures.fixture(str(output.relative_to(self.root)), mode=selection['mode'])
        manifest = cli.provenance.read_json(capture / 'source-manifest.json')
        cli.report.write_json(capture / cli.provenance.SOURCE_ROLES,
                              cli.provenance.source_roles(self.root, selection, manifest))
        self.fixtures.freeze(capture)
        frozen = cli.report.read_json(capture / 'snapshot-hashes.json')
        frozen[cli.provenance.SOURCE_ROLES] = cli.provenance.digest(capture / cli.provenance.SOURCE_ROLES)
        cli.report.write_json(capture / 'snapshot-hashes.json', frozen)
        observations = [capture / 'execution.json', *capture.glob('*-launch.log')]
        self.observations[str(capture)] = {path.name: path.read_bytes() for path in observations}
        for path in observations:
            path.unlink()

    def launch(self, output, **kwargs):
        output = output.resolve()
        self.launches.append(output.name)
        if output.name in self.blocked:
            raise RuntimeError('Resource wait expired before native launch')
        for name, content in self.observations[str(output)].items():
            (output / name).write_bytes(content)
        cli.provenance.seal_execution(output)
        return cli.report.read_json(output / 'execution.json')

    def batch(self, *, only=None):
        self.path.write_text(json.dumps(self.plan))
        args = argparse.Namespace(plan=self.path, output=self.output, jobs=only)
        with patch.object(cli.native, 'source_inputs'), patch.object(cli.native, 'prepare', side_effect=self.prepare), \
                patch.object(cli.runner, 'run', side_effect=self.launch), patch('sys.stdout', io.StringIO()):
            return cli.batch(args, self.catalog)

    def resume(self, name='first', control=None):
        command = ['resume', str(self.output / name)]
        if control:
            command += ['--control', str(control)]
        with patch.object(cli, 'load_catalog', return_value=self.catalog), \
                patch.object(cli.runner, 'run', side_effect=self.launch) as run, \
                patch.object(cli.native, 'prepare') as prepare, \
                patch('sys.stdout', io.StringIO()), patch('sys.stderr', io.StringIO()):
            result = cli.main(command)
        prepare.assert_not_called()
        return result, run.call_count

    def accounting(self):
        return cli.report.read_json(self.output / 'batch-report.json')

    def test_successful_sole_job_resume_preserves_blocked_attempt_and_first_stop(self):
        self.assertEqual(1, self.batch())
        original = self.accounting()
        self.assertNotIn('execution.json', {path.name for path in (self.output / 'first').iterdir()})
        self.blocked.clear()
        self.assertEqual((0, 1), self.resume())
        current = self.accounting()
        row = current['jobs'][0]
        self.assertEqual('passed', current['status'])
        self.assertEqual('passed', current['campaign']['status'])
        self.assertEqual(original['jobs'][0], row['attempts'][0])
        self.assertEqual(original['sessions'][0], current['sessions'][0]['attempts'][0])
        self.assertEqual([original['stop_reason']], current['stop_history'])
        self.assertIsNone(current['stop_reason'])
        self.assertEqual(cli.provenance.digest(self.output / 'first/report.json'), row['report_sha256'])
        self.assertEqual(str(self.output / 'first/report.json'), current['campaign']['blocks'][0]['jobs'][0]['report'])
        coverage = cli.report.read_json(self.output / 'coverage.json')
        self.assertTrue(any(row['status'] == 'passed' for row in coverage['rows']))

    def test_resumed_case_setup_failure_replaces_current_reason_and_keeps_blocked_attempt(self):
        self.assertEqual(1, self.batch())
        original = self.accounting()
        finding = dict(kind='fixture-case-setup', phase='fixture-setup', role='client1',
                       case='bandageApply', reason='corridor unavailable')
        observations = self.observations[str((self.output / 'first').resolve())]
        execution = json.loads(observations['execution.json'])
        execution['setup_failure'] = finding
        observations['execution.json'] = json.dumps(execution).encode()
        self.blocked.clear()
        self.assertEqual((1, 1), self.resume())
        value = self.accounting()
        self.assertEqual('failed', value['status'])
        self.assertEqual(finding, value['jobs'][0]['setup_failure'])
        self.assertEqual(finding, value['sessions'][0]['setup_failure'])
        self.assertEqual(dict(finding, job='first'), value['stop_reason'])
        self.assertEqual(original['jobs'][0], value['jobs'][0]['attempts'][0])
        self.assertEqual([original['stop_reason']], value['stop_history'])

    def test_remaining_jobs_gates_and_unselected_jobs_are_never_promoted(self):
        self.plan['jobs'].append(self.job('later', control_job='first'))
        self.plan['campaign'][0]['jobs'].append('later')
        self.plan['campaign'][0]['gates'] = ['Inspect native UI.']
        self.assertEqual(1, self.batch())
        self.blocked.clear()
        self.assertEqual((0, 1), self.resume())
        value = self.accounting()
        self.assertEqual(['later'], value['remaining'])
        self.assertEqual('pending', value['status'])
        self.assertEqual('pending', value['campaign']['status'])
        self.assertEqual(['passed', 'pending'], [row['status'] for row in value['campaign']['blocks'][0]['jobs']])
        self.assertEqual(['first', 'first'], self.launches)
        selected = campaign.refresh(dict(status='pending', remaining_gates=0, blocks=[dict(
            id='other', jobs=[dict(id='first', status='blocked'), dict(id='unselected', status='not-selected')], gates=[])]), value['jobs'])
        self.assertEqual('not-selected', selected['blocks'][0]['jobs'][1]['status'])

    def test_dependency_blocked_rows_remain_blocked_after_control_resume(self):
        self.plan['failure_policy'] = 'continue'
        self.plan['jobs'].append(self.job('candidate', control_job='first'))
        self.plan['campaign'][0]['jobs'].append('candidate')
        self.assertEqual(1, self.batch())
        dependency = self.accounting()['jobs'][1]
        self.blocked.clear()
        self.assertEqual((0, 1), self.resume())
        self.assertEqual(dependency, self.accounting()['jobs'][1])
        self.assertEqual('failed', self.accounting()['campaign']['status'])
        self.assertFalse((self.output / 'candidate').exists())

    def test_stored_control_is_restored_and_wrong_override_refuses_before_launch(self):
        self.blocked = {'candidate'}
        self.plan['jobs'] = [self.job('control', mode='native'), self.job('candidate', control_job='control')]
        self.plan['campaign'][0]['jobs'] = ['control', 'candidate']
        self.assertEqual(1, self.batch())
        original = (self.output / 'batch-report.json').read_bytes()
        self.assertEqual((1, 0), self.resume('candidate', self.root / 'wrong-control'))
        self.assertEqual(original, (self.output / 'batch-report.json').read_bytes())
        self.blocked.clear()
        self.assertEqual((0, 1), self.resume('candidate'))
        value = cli.report.read_json(self.output / 'candidate/report.json')
        self.assertTrue(value['comparison']['compatible'])
        self.assertEqual('passed', self.accounting()['campaign']['status'])

    def test_changed_snapshot_or_control_binding_refuses_before_launch(self):
        self.assertEqual(1, self.batch())
        snapshot = self.output / 'first/snapshot-hashes.json'
        snapshot.write_text(snapshot.read_text() + '\n')
        self.blocked.clear()
        self.assertEqual((1, 0), self.resume())
        self.assertEqual('blocked', self.accounting()['jobs'][0]['status'])

    def test_changed_control_snapshot_refuses_before_launch(self):
        self.blocked = {'candidate'}
        self.plan['jobs'] = [self.job('control', mode='native'), self.job('candidate', control_job='control')]
        self.plan['campaign'][0]['jobs'] = ['control', 'candidate']
        self.assertEqual(1, self.batch())
        snapshot = self.output / 'control/snapshot-hashes.json'
        snapshot.write_text(snapshot.read_text() + '\n')
        self.blocked.clear()
        self.assertEqual((1, 0), self.resume('candidate'))
        self.assertEqual('blocked', self.accounting()['jobs'][1]['status'])

    def test_legacy_and_preprepare_failures_do_not_gain_campaign_bindings(self):
        self.assertEqual(1, self.batch())
        value = self.accounting()
        for row in [*value['jobs'], *value['sessions']]:
            for key in ('snapshot_sha256', 'control_run', 'control_snapshot_sha256'):
                row.pop(key, None)
        cli.report.write_json(self.output / 'batch-report.json', value)
        original = (self.output / 'batch-report.json').read_bytes()
        self.blocked.clear()
        self.assertEqual((0, 1), self.resume())
        self.assertEqual(original, (self.output / 'batch-report.json').read_bytes())
        self.assertEqual((None, None), cli.batch_resume.resolve(self.output / 'unprepared'))

    def test_preprepare_failure_cannot_bind_a_later_unrelated_preparation(self):
        self.path.write_text(json.dumps(self.plan))
        args = argparse.Namespace(plan=self.path, output=self.output)
        def incomplete(project, output, *args, **kwargs):
            output.mkdir()
            raise ValueError('Preparation did not produce a sealed snapshot')
        with patch.object(cli.native, 'source_inputs'), patch.object(cli.native, 'prepare', side_effect=incomplete), \
                patch.object(cli.runner, 'run') as run, patch('sys.stdout', io.StringIO()):
            self.assertEqual(1, cli.batch(args, self.catalog))
        run.assert_not_called()
        original = (self.output / 'batch-report.json').read_bytes()
        self.assertNotIn('snapshot_sha256', self.accounting()['jobs'][0])
        (self.output / 'first').rmdir()
        self.prepare(None, self.output / 'first', None, None, {'suite': 'health', 'mode': 'toolkit'}, [])
        self.blocked.clear()
        self.assertEqual((0, 1), self.resume())
        self.assertEqual(original, (self.output / 'batch-report.json').read_bytes())

    def test_live_runtime_drift_can_never_upgrade_campaign_to_passed(self):
        self.assertEqual(1, self.batch())
        self.fixtures.source.write_text('changed runtime input')
        self.blocked.clear()
        self.assertEqual((1, 1), self.resume())
        value = self.accounting()
        self.assertEqual('failed', value['campaign']['status'])
        self.assertEqual('blocked', value['jobs'][0]['attempts'][0]['status'])

    def test_later_batch_write_keeps_a_resume_recorded_between_units(self):
        self.assertEqual(1, self.batch())
        stale_batch_state = self.accounting()
        self.blocked.clear()
        self.assertEqual((0, 1), self.resume())
        resumed = self.accounting()
        cli.batch_resume.write_accounting(self.output / 'batch-report.json', stale_batch_state, self.catalog)
        current = self.accounting()
        self.assertEqual(resumed['jobs'], current['jobs'])
        self.assertEqual(resumed['sessions'], current['sessions'])
        self.assertEqual(resumed['stop_history'], current['stop_history'])
        self.assertEqual('passed', current['campaign']['status'])

    def test_accounting_lock_survives_owner_death_without_stale_ownership(self):
        self.assertEqual(1, self.batch())
        path = self.output / 'batch-report.json'
        original = path.read_bytes()
        ready = self.root / 'lock-ready'
        script = '''import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from queue_checks.batch_resume import _locked
with _locked(Path(sys.argv[2])):
    Path(sys.argv[3]).write_text('held')
    sys.stdin.buffer.read()
'''
        process = subprocess.Popen([sys.executable, '-c', script, str(ROOT / 'tools'), str(path), str(ready)],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 5
            while not ready.exists() and process.poll() is None and time.monotonic() < deadline:
                time.sleep(.01)
            self.assertTrue(ready.exists(), 'Owned lock holder failed to acquire its accounting lock')
            with self.assertRaisesRegex(RuntimeError, 'busy'):
                cli.batch_resume.write_accounting(path, self.accounting(), self.catalog)
            self.assertEqual(original, path.read_bytes())
            lock = path.with_name('batch-report.resume.lock')
            identity = lock.stat().st_ino
            process.kill()
            process.wait(timeout=5)
            with cli.batch_resume._locked(path):
                self.assertEqual(identity, lock.stat().st_ino)
            cli.batch_resume.write_accounting(path, self.accounting(), self.catalog)
            self.assertEqual('blocked', self.accounting()['jobs'][0]['status'])
        finally:
            if process.poll() is None:
                process.kill()
            process.communicate(timeout=5)

    def test_windows_accounting_lock_uses_nonblocking_byte_lock_and_closes_descriptor(self):
        calls = []
        backend = types.SimpleNamespace(LK_NBLCK=17, locking=lambda *args: calls.append(args))
        path = self.root / 'batch-report.json'
        with patch.object(cli.batch_resume, 'fcntl', None), patch.dict(sys.modules, {'msvcrt': backend}):
            with cli.batch_resume._locked(path):
                self.assertEqual(1, len(calls))
                descriptor, mode, size = calls[0]
                self.assertEqual((17, 1), (mode, size))
                self.assertEqual(0, os.lseek(descriptor, 0, os.SEEK_CUR))
                self.assertEqual(1, os.fstat(descriptor).st_size)
        with self.assertRaises(OSError):
            os.fstat(descriptor)
        self.assertTrue(path.with_name('batch-report.resume.lock').is_file())


if __name__ == '__main__': unittest.main()
