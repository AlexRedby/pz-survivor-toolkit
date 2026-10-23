"""Radio settings logs must prove exact pending edits and native Host effects."""
import copy
import itertools
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import report
from queue_checks.adapters import radio_settings as adapter


class RadioSettingsAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def selection(self, case, kind='sp', mode='toolkit'):
        return dict(suite='radio-settings', cases=[case], kind=kind, mode=mode,
                    clients=1, languages=['EN'], mods=list(adapter.MODS),
                    options={'mp_host': True} if kind == 'mp' else {})

    def evidence(self, case, kind='sp', mode='toolkit'):
        ids = dict(case=case, mode=mode, a=dict(x=11, y=20, z=0, index=2),
                   b=dict(x=9, y=20, z=0, index=1))

        def snapshot(initial=False, server=False):
            devices = {}
            for name in ('a', 'b'):
                volume = (.5 if initial else .25 if name == 'b' else 0 if case == 'barrier'
                          else .25 if mode == 'toolkit' else .75)
                channel = 90000 if initial else 96000 if name == 'b' else 95000
                muted = (not initial and not server and name == 'a' and case != 'barrier'
                         and (case != 'cancel' or mode == 'native'))
                devices[name] = dict(ids[name], volume=volume, channel=channel,
                                     micMuted=muted, on=True, powered=True)
            return dict(case=case, devices=devices)

        specs = [('anchor', 'SetVolume', 'b', .25), ('firstVolume', 'SetVolume', 'a', .25)]
        if case == 'barrier':
            specs += [('channel', 'SetChannel', 'a', 95000), ('powerOff', 'ToggleOnOff', 'a', None),
                      ('powerOn', 'ToggleOnOff', 'a', None), ('legacyMute', 'MuteVolume', 'a', True)]
        else:
            specs += [('channel', 'SetChannel', 'a', 95000), ('lastVolume', 'SetVolume', 'a', .75),
                      ('mic', 'MuteMicrophone', 'a', True)]
        specs += [('tail', 'SetChannel', 'b', 96000)]
        cancelled = ['lastVolume', 'mic'] if case == 'cancel' and mode == 'toolkit' else []
        initial = [name for name, _, _, _ in specs]
        expected = (['anchor', 'lastVolume', 'firstVolume', 'mic', 'channel', 'tail']
                    if case == 'reorder' and mode == 'toolkit'
                    else [name for name in initial if name not in cancelled])
        commands = []
        for name, action, target, value in specs:
            removed = name in cancelled
            command = dict(name=name, mode=action, target=target, value=value, duration=30,
                           producer='native RWM callback', started=not removed,
                           progress=not removed, cancelled=removed)
            if not removed:
                command.update(effectiveDuration=30, nativeDurationExpected=30,
                               startedAt=1000 + expected.index(name) * 100)
            commands.append(command)
        before = snapshot(initial=True)
        client = snapshot()
        authority = snapshot(server=kind == 'mp')
        row = dict(suite='radio-settings', event='case', id=case, kind=kind, mode=mode,
                   actor='client1', status='passed', ids=copy.deepcopy(ids), commands=commands,
                   initialQueue=initial, editedQueue=list(expected), order=list(expected),
                   edit=dict(reordered=case == 'reorder' and mode == 'toolkit', cancelled=cancelled,
                             denied=case == 'barrier' and mode == 'toolkit', reason='move_dependent',
                             untouchedBefore=True, nativeDurations=True, before=before),
                   client=client, server=copy.deepcopy(authority), queueIdle=True, settleMilliseconds=2000)
        return row, ids, authority

    def verify(self, selection, evidence, *, prepared=True, verified=True, malformed_raw=None,
               completion='[RADIO_SETTINGS] COMPLETE'):
        row, ids, receipt = evidence
        # Use timestamped records just as the live launcher does.
        stamp = 'LOG : General > '
        client = stamp + '[QUEUE_CHECK] ' + json.dumps(row) + '\n' + completion + '\n'
        client += ''.join('[QUEUE_TEST] ' + marker + '\n' for marker in
                          ('VOICE_DISABLED', 'DISPLAY_READY', 'PREFLIGHT_COMPLETE',
                           'NATIVE_CONNECTED' if selection['kind'] == 'mp' else 'TRUE_SP'))
        raw = []
        if prepared:
            raw.append('[RADIO_SETTINGS] PREPARED ' + json.dumps(ids))
        if verified:
            raw.append('[RADIO_SETTINGS] VERIFIED ' + json.dumps(receipt))
        if malformed_raw is not None:
            marker, value = malformed_raw
            raw = [line for line in raw if not line.startswith('[RADIO_SETTINGS] ' + marker)]
            raw.append('[RADIO_SETTINGS] ' + marker + ' ' + value)
        authority = '\n'.join(stamp + line for line in raw) + '\n'
        if selection['kind'] == 'mp':
            (self.root / 'server-launch.log').write_text(authority)
        else:
            client += authority
        (self.root / 'client1-launch.log').write_text(client)
        return adapter.verify(self.root, selection, {})

    def matrix(self):
        return itertools.product(adapter.CASES, ('sp', 'mp'), ('native', 'toolkit'))

    def test_valid_evidence_for_all_cases_modes_and_sp_host(self):
        for case, kind, mode in self.matrix():
            with self.subTest(case=case, kind=kind, mode=mode):
                selection = self.selection(case, kind, mode)
                adapter.validate(selection)
                result = self.verify(selection, self.evidence(case, kind, mode))
                self.assertEqual(result['issues'], [])
                self.assertEqual([row['status'] for row in result['outcomes']], ['passed'])

    def test_verified_outcomes_nest_scenario_flags_for_report_consumers(self):
        for case, kind, mode in self.matrix():
            with self.subTest(case=case, kind=kind, mode=mode):
                result = self.verify(self.selection(case, kind, mode), self.evidence(case, kind, mode))
                self.assertEqual(result['issues'], [])
                self.assertEqual(result['outcomes'][0].get('outcome'), {
                    'effectsVerified': True, 'pendingRequestsVerified': True,
                    'pendingEditsVerified': mode == 'toolkit', 'serverAuthorityVerified': True,
                })

    def test_verified_radio_evidence_maps_to_scenarios_and_native_edit_is_inapplicable(self):
        catalog = {'suites': adapter.definitions()}
        mapped = {'reorder': 'move-independent', 'cancel': 'cancel-waiting', 'barrier': 'move-dependent'}
        for case, kind, mode in self.matrix():
            with self.subTest(case=case, kind=kind, mode=mode):
                selection = self.selection(case, kind, mode)
                self.assertEqual(self.verify(selection, self.evidence(case, kind, mode))['issues'], [])
                functional, coverage = report.functional(self.root, selection, catalog)
                self.assertEqual(functional['issues'], [])
                processes = {'client1': {'pid': 123, 'exit_code': 0}}
                execution = {'status': 'completed', 'processes': processes}
                if kind == 'mp':
                    processes['server'] = {'pid': 124, 'parent_role': 'client1',
                                           'cache': str(self.root / 'client1')}
                    execution['host_cleanup'] = {'remaining_pids': []}
                recorded = dict(run=str(self.root), status='passed', selection=selection,
                                functional=functional, coverage=coverage, execution=execution,
                                provenance={'verified': True})
                scenario = next(row for row in report.matrix(catalog, [recorded])['scenarios']
                                if row['suite'] == 'radio-settings' and row['action'] == 'world-radio-settings'
                                and row['scenario'] == mapped[case] and row['kind'] == kind and row['mode'] == mode)
                self.assertEqual(scenario['status'], 'not-applicable' if mode == 'native' else 'passed')

    def test_exact_device_identity_is_required_even_for_matching_receipts(self):
        for case, kind, mode in self.matrix():
            for field in ('x', 'y', 'z', 'index'):
                with self.subTest(case=case, kind=kind, mode=mode, field=field):
                    evidence = self.evidence(case, kind, mode)
                    row, _, receipt = evidence
                    # Matching client/server claims cannot replace the prepared object.
                    for changed in (row['client'], row['server'], receipt):
                        changed['devices']['a'][field] += 1
                    self.assertTrue(self.verify(self.selection(case, kind, mode), evidence)['issues'])

    def test_dispatch_edit_and_observed_order_are_independently_required(self):
        for case, kind, mode in self.matrix():
            for field in ('initialQueue', 'editedQueue', 'order'):
                with self.subTest(case=case, kind=kind, mode=mode, field=field):
                    evidence = self.evidence(case, kind, mode)
                    evidence[0][field][-2:] = reversed(evidence[0][field][-2:])
                    self.assertTrue(self.verify(self.selection(case, kind, mode), evidence)['issues'])

    def test_cancelled_native_actions_cannot_have_started_or_made_progress(self):
        for kind, name, field in itertools.product(('sp', 'mp'), ('lastVolume', 'mic'), ('started', 'progress')):
            with self.subTest(kind=kind, name=name, field=field):
                evidence = self.evidence('cancel', kind)
                command = next(row for row in evidence[0]['commands'] if row['name'] == name)
                command[field] = True
                self.assertTrue(self.verify(self.selection('cancel', kind), evidence)['issues'])

    def test_native_adjustment_is_accepted_but_retiming_is_rejected(self):
        for case, kind, mode in self.matrix():
            for effective, accepted in ((30.02, True), (31.02, False)):
                with self.subTest(case=case, kind=kind, mode=mode, effective=effective):
                    evidence = self.evidence(case, kind, mode)
                    for command in evidence[0]['commands']:
                        if not command['cancelled']:
                            command['nativeDurationExpected'] = 30.02
                            command['effectiveDuration'] = effective
                    result = self.verify(self.selection(case, kind, mode), evidence)
                    if accepted:
                        self.assertEqual(result['issues'], [])
                    else:
                        self.assertTrue(result['issues'])

    def test_host_cannot_fabricate_native_microphone_replication(self):
        for case, mode in itertools.product(adapter.CASES, ('native', 'toolkit')):
            with self.subTest(case=case, mode=mode):
                evidence = self.evidence(case, 'mp', mode)
                evidence[0]['server']['devices']['a']['micMuted'] = True
                evidence[2]['devices']['a']['micMuted'] = True
                self.assertTrue(self.verify(self.selection(case, 'mp', mode), evidence)['issues'])

    def test_receipt_and_authoritative_markers_cannot_be_omitted(self):
        for case, kind, mode in self.matrix():
            selection = self.selection(case, kind, mode)
            for field in ('client', 'server'):
                with self.subTest(case=case, kind=kind, mode=mode, field=field):
                    evidence = self.evidence(case, kind, mode)
                    del evidence[0][field]
                    self.assertTrue(self.verify(selection, evidence)['issues'])
            for marker in ('prepared', 'verified'):
                with self.subTest(case=case, kind=kind, mode=mode, marker=marker):
                    self.assertTrue(self.verify(selection, self.evidence(case, kind, mode), **{marker: False})['issues'])

    def test_malformed_receipts_are_rejected_without_crashing_verifier(self):
        malformed = (None, [], 'receipt', {}, {'case': 'reorder', 'devices': None},
                     {'case': 'reorder', 'devices': 'ab'}, {'case': 'reorder', 'devices': ['a', 'b']},
                     {'case': 'reorder', 'devices': {'a': None, 'b': None}})
        for kind, field, value in itertools.product(('sp', 'mp'), ('client', 'server'), malformed):
            with self.subTest(kind=kind, field=field, value=value):
                evidence = self.evidence('reorder', kind)
                evidence[0][field] = copy.deepcopy(value)
                if field == 'server':
                    evidence = (evidence[0], evidence[1], copy.deepcopy(value))
                self.assertTrue(self.verify(self.selection('reorder', kind), evidence)['issues'])

    def test_malformed_authority_json_is_rejected_without_crashing_verifier(self):
        for kind, marker, value in itertools.product(('sp', 'mp'), ('PREPARED', 'VERIFIED'),
                                                     ('null', '[]', '"receipt"', '{invalid')):
            with self.subTest(kind=kind, marker=marker, value=value):
                result = self.verify(self.selection('reorder', kind), self.evidence('reorder', kind),
                                     malformed_raw=(marker, value))
                self.assertTrue(result['issues'])

    def test_missing_or_duplicate_completion_does_not_pass(self):
        for marker in ('', '[RADIO_SETTINGS] COMPLETE_PENDING',
                       '[RADIO_SETTINGS] COMPLETE\n[RADIO_SETTINGS] COMPLETE'):
            with self.subTest(marker=marker):
                self.assertTrue(self.verify(self.selection('reorder'), self.evidence('reorder'),
                                            completion=marker)['issues'])


if __name__ == '__main__':
    unittest.main()
