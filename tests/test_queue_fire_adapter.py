"""Exact Fire receipts reject plausible but uncorrelated effect evidence."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import fire


class FireAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.selection = dict(suite='fire', cases=list(fire.FUEL_CASES), kind='sp', mode='toolkit',
                              languages=['EN'], mods=list(fire.MODS), clients=1, options={})

    def evidence(self):
        enabled = self.selection['mode'] == 'toolkit'
        cases = self.selection['cases']
        rows = [dict(event='setup', cases=cases, expected=len(cases), queueEnabled=enabled, nativeDurations=True)]
        prepared, receipts, removals = [], [], []
        for n, case in enumerate(cases):
            missing = case == 'missing-target-after-expansion'
            prep = dict(case=case, log=101+n*10, book=102+n*10, condition=100, fuelAmount=120,
                        x=20, y=30, z=0, objectIndex=2, crateX=20, crateY=30, crateZ=0, crateIndex=1)
            receipt = dict(case=case, logId=prep['log'], bookId=prep['book'], condition=100, fuelAmount=120,
                           consumed=0 if missing else 1, sourceCount=int(missing and enabled),
                           rootCount=int(missing and not enabled), fuel=0 if missing else 120,
                           removed=missing, unspent=missing, tailRead=not missing or enabled)
            result = dict(receipt, event='case', id=case, status='failed' if missing and not enabled else 'passed',
                          reason='native-missing-target' if missing and not enabled else None,
                          expanded=True, pickupProgress=True, fuelProgress=not missing,
                          tailProgress=not missing or enabled, returnProgress=missing and enabled,
                          removedDuringPickup=missing, pickupDuration=50, nativeDuration=100, authorityVerified=True)
            del result['case']
            rows.append(result);prepared.append(prep);receipts.append(receipt)
            if missing:
                removals.append(dict(case=case, logId=prep['log'], fuel=0))
        baseline = not enabled and 'missing-target-after-expansion' in cases
        rows.append(dict(event='complete', cases=cases, expected=len(cases), performed=len(cases),
                         failed=int(baseline), skipped=0))
        rows = [dict(row, suite='fire', kind=self.selection['kind'], mode=self.selection['mode'], actor='client1') for row in rows]
        return rows, prepared, receipts, removals

    def verify(self, evidence=None, extra=''):
        rows, prepared, receipts, removals = evidence or self.evidence()
        authority = '\n'.join(marker + json.dumps(row) for marker, values in (
            ('[FIRE_TEST] PREPARED ', prepared), ('[FIRE_TEST] REMOVED ', removals),
            ('[FIRE_TEST] AUTHORITY ', receipts)) for row in values)
        text = '\n'.join('[QUEUE_CHECK] ' + json.dumps(row) for row in rows) + '\n' + extra
        if self.selection['kind'] == 'mp':
            (self.root / 'server-launch.log').write_text(authority)
        else:
            text += '\n' + authority
        (self.root / 'client1-launch.log').write_text(text)
        return fire.verify(self.root, self.selection, {})

    def test_toolkit_sp_mp_and_native_fuel_success(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.selection.update(kind=kind, mode=mode, cases=['fuel'] if mode == 'native' else list(fire.FUEL_CASES))
                with self.subTest(kind=kind, mode=mode):
                    fire.validate(self.selection)
                    result = self.verify()
                    self.assertEqual(result['issues'], [])
                    self.assertTrue(all(row['status'] == 'passed' for row in result['outcomes']))

    def test_native_terminal_failure_cannot_contaminate_following_ignition(self):
        for cases in (['missing-target-after-expansion'], list(fire.FUEL_CASES),
                      list(fire.ignition.CASES), ['fuel'] + list(fire.ignition.CASES)):
            fire.validate(dict(self.selection, mode='native', cases=cases))
        for case in fire.ignition.CASES:
            with self.subTest(case=case), self.assertRaisesRegex(ValueError, 'terminal'):
                fire.validate(dict(self.selection, mode='native', cases=['missing-target-after-expansion', case]))
        with self.assertRaisesRegex(ValueError, 'terminal'):
            fire.validate(dict(self.selection, mode='native', cases=list(fire.CASES)))
        fire.validate(dict(self.selection, mode='toolkit', cases=list(fire.CASES)))

    def test_native_missing_outcome_is_recorded_but_never_a_runtime_pass(self):
        for kind in ('sp', 'mp'):
            self.selection.update(kind=kind, mode='native')
            result = self.verify(extra='java.lang.RuntimeException: stock ISAddFuelAction.isValid')
            self.assertEqual(len(result['issues']), 1)
            self.assertEqual(result['issues'][0], 'native-missing-target')
            self.assertEqual([(row['case'], row['status']) for row in result['outcomes']],
                             [('fuel', 'passed'), ('missing-target-after-expansion', 'failed')])
            self.assertEqual(result['outcomes'][0]['reason'], '')
            outcome = result['outcomes'][-1]
            self.assertEqual(outcome['status'], 'failed')
            self.assertEqual('native-missing-target', outcome['reason'])
            self.assertEqual(outcome['outcome'], dict(logId=111, consumed=0, sourceCount=0, rootCount=1,
                                                     fuel=0, tailRead=False, returnProgress=False))

    def test_shared_native_evidence_failure_also_fails_fuel(self):
        self.selection['mode'] = 'native'
        evidence = copy.deepcopy(self.evidence())
        evidence[0][0]['mode'] = 'toolkit'
        result = self.verify(evidence)
        self.assertTrue(all(row['status'] == 'failed' for row in result['outcomes']))
        self.assertTrue(all('context differs' in row['reason'] for row in result['outcomes']))

    def test_native_mp_fuel_observes_progress_and_reports_authoritative_tail_loss(self):
        self.selection.update(kind='mp', mode='native')
        for read in (False, True):
            for fuel_progress, tail_progress in ((False, False), (True, False), (True, True)):
                evidence = copy.deepcopy(self.evidence())
                fuel, complete = evidence[0][1], evidence[0][-1]
                fuel.update(tailRead=read, fuelProgress=fuel_progress, tailProgress=tail_progress,
                            status='passed' if read else 'failed',
                            reason=None if read else 'native-independent-tail-not-preserved')
                evidence[2][0]['tailRead'] = read
                complete['failed'] = 1 + int(not read)
                with self.subTest(read=read, fuel_progress=fuel_progress, tail_progress=tail_progress):
                    result = self.verify(evidence)
                    self.assertEqual(result['outcomes'][0]['status'], 'passed' if read else 'failed')
                    self.assertEqual(result['outcomes'][0]['outcome']['tailRead'], read)
                    self.assertEqual(len(result['issues']), 1 if read else 2)
                    if not read:
                        self.assertEqual('native-independent-tail-not-preserved', result['outcomes'][0]['reason'])

    def test_native_mp_fuel_observation_keeps_effects_types_receipt_and_counter_strict(self):
        self.selection.update(kind='mp', mode='native', cases=['fuel'])
        for key, value in (('tailRead', 1), ('fuelProgress', None), ('tailProgress', 0), ('consumed', 0),
                           ('sourceCount', 1), ('fuel', 0), ('logId', 777)):
            evidence = copy.deepcopy(self.evidence())
            evidence[0][1][key] = value
            with self.subTest(key=key):
                self.assertTrue(self.verify(evidence)['issues'])
        for target in ('receipt', 'status', 'counter', 'reason'):
            evidence = copy.deepcopy(self.evidence())
            evidence[0][1].update(tailRead=False, status='failed', reason='native-independent-tail-not-preserved')
            evidence[2][0]['tailRead'] = False
            evidence[0][-1]['failed'] = 1
            if target == 'receipt': evidence[2][0]['tailRead'] = True
            elif target == 'status': evidence[0][1]['status'] = 'passed'
            elif target == 'reason': evidence[0][1]['reason'] = 'native-missing-target'
            else: evidence[0][-1]['failed'] = 0
            with self.subTest(target=target):
                result = self.verify(evidence)
                self.assertTrue(any('evidence differs' in issue or 'effect/progress' in issue or 'authority differs' in issue
                                    for issue in result['issues']))

    def test_toolkit_and_native_sp_do_not_accept_lost_fuel_tail_or_progress(self):
        for kind, mode in (('sp', 'native'), ('sp', 'toolkit'), ('mp', 'toolkit')):
            self.selection.update(kind=kind, mode=mode, cases=['fuel'])
            for key in ('tailRead', 'fuelProgress', 'tailProgress'):
                evidence = copy.deepcopy(self.evidence())
                evidence[0][1][key] = False
                if key == 'tailRead': evidence[2][0]['tailRead'] = False
                with self.subTest(kind=kind, mode=mode, key=key):
                    self.assertIn('Fire exact native effect/progress differs: fuel', self.verify(evidence)['issues'])

    def test_invalid_case_order_duplicates_mode_client_and_world_are_rejected(self):
        for change in ({'cases': []}, {'cases': ['unknown']}, {'cases': ['fuel', 'fuel']},
                       {'cases': list(reversed(fire.CASES))}, {'kind': 'host'}, {'mode': 'other'},
                       {'languages': ['RU']}, {'clients': True}, {'clients': 2}, {'mods': fire.MODS[:-1]},
                       {'options': {'world_template': '/old'}}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                fire.validate(dict(self.selection, **change))
        fire.validate(dict(self.selection, options={'mp_host': True}, kind='mp'))

    def test_missing_duplicated_reordered_unknown_events_and_context_fail(self):
        original = self.evidence()
        rows = original[0]
        for changed in (rows[1:], rows[:-1], rows + [rows[1]], [rows[0], rows[2], rows[1], rows[3]],
                        [rows[0], dict(rows[1], event='error'), *rows[2:]],
                        [rows[0], dict(rows[1], mode='native'), *rows[2:]]):
            with self.subTest(events=[r['event'] for r in changed]):
                self.assertTrue(self.verify((changed, *original[1:]))['issues'])
        with self.assertRaises(ValueError):
            self.verify(extra='[QUEUE_CHECK] []')

    def test_exact_identity_receipts_and_source_location_are_required(self):
        for index, key, value in ((0, 'log', 777), (0, 'condition', True), (0, 'crateIndex', -1),
                                  (0, 'crateX', 21), (0, 'crateIndex', 2),
                                  (0, 'crateX', 20.0), (2, 'logId', 777), (2, 'rootCount', 1),
                                  (2, 'fuel', 121), (3, 'logId', True)):
            evidence = copy.deepcopy(self.evidence())
            table = {0: evidence[1], 2: evidence[2], 3: evidence[3]}[index]
            table[0][key] = value
            with self.subTest(index=index, key=key):
                self.assertTrue(self.verify(evidence)['issues'])
        for table in (1, 2, 3):
            for duplicate in (False, True):
                evidence = copy.deepcopy(self.evidence())
                if duplicate:
                    evidence[table].append(evidence[table][0])
                else:
                    evidence[table].pop()
                with self.subTest(table=table, duplicate=duplicate):
                    self.assertTrue(self.verify(evidence)['issues'])

    def test_exact_progress_unspent_return_and_native_duration_are_required(self):
        for row, key, value in ((1, 'consumed', True), (1, 'fuel', 121), (1, 'nativeDuration', 1),
                                (1, 'pickupDuration', True), (1, 'pickupDuration', 1), (1, 'expanded', False),
                                (2, 'returnProgress', False), (2, 'sourceCount', 0), (2, 'rootCount', 1),
                                (2, 'removedDuringPickup', False), (2, 'tailRead', False),
                                (2, 'unspent', False), (2, 'authorityVerified', False), (2, 'logId', 101.0)):
            evidence = copy.deepcopy(self.evidence())
            evidence[0][row][key] = value
            with self.subTest(row=row, key=key):
                self.assertTrue(self.verify(evidence)['issues'])
        self.assertTrue(self.verify(extra='[QUEUE_TEST] FAIL native fixture')['issues'])

    def test_stage_sources_and_exact_completion_marker(self):
        runtime = {'roles': {role: {'cache': str(self.root / role)} for role in ('server', 'client1')}}
        fire.stage(ROOT, self.root, None, None, self.selection, {}, runtime)
        for role in runtime['roles']:
            lua = self.root / role / 'mods/ActionQueueTest/42/media/lua'
            for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua'), ('shared', 'QueueHealthEvents.lua')]:
                self.assertTrue((lua / side / name).is_file())
        self.assertEqual(runtime['fixture']['sandbox']['MinutesPerPage'], 2.0)
        paths = fire.sources(ROOT, self.selection)
        self.assertTrue(set((ROOT / 'tests/native_queue/fire').rglob('*.lua')) <= set(paths))
        self.assertIn(ROOT / 'tests/native_queue/health/shared/QueueHealthEvents.lua', paths)
        self.assertIn(ROOT / 'tools/queue_checks/adapters/fire_ignition.py', paths)
        self.assertTrue(fire.complete(self.selection, 'client1', '[FIRE_TEST] COMPLETE\n'))
        for text in ('[FIRE_TEST] COMPLETE_PENDING', '[FIRE_TEST] COMPLETE\n[FIRE_TEST] COMPLETE'):
            self.assertFalse(fire.complete(self.selection, 'client1', text))
        self.assertFalse(fire.complete(self.selection, 'server', '[FIRE_TEST] COMPLETE\n'))


if __name__ == '__main__':
    unittest.main()
