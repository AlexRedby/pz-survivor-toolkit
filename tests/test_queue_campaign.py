"""Campaign accounting must keep missing acceptance and partial selections visible."""
import argparse
import copy
import importlib.util
import io
import json
from pathlib import Path
import re
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import campaign
spec = importlib.util.spec_from_file_location('campaign_cli', ROOT / 'tools/check_action_queue.py')
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)


class CampaignTests(unittest.TestCase):
    def setUp(self):
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
                def prepare(project,output,*args):
                    output.mkdir();prepared.append(output.name)
                def run(output,**kwargs):
                    (output/'execution.json').write_text('{}');return {}
                def report(output,*args):
                    return dict(status=status if output.name=='first' else 'passed',functional={'status':'passed'},runtime={'status':'clean'})
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


if __name__ == '__main__': unittest.main()
