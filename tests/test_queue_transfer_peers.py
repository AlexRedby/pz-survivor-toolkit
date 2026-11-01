"""Strict two-client physical/advisory evidence and causal mutation checks."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import queue_transfer_peers as a


class QueueTransferPeersTests(unittest.TestCase):
    def selection(self, mode='toolkit', cases=None):
        return dict(suite='queue-transfer-peers', cases=list(a.CASES if cases is None else cases), kind='mp',
                    mode=mode, clients=2, languages=['EN', 'RU'], mods=list(a.MODS), options={'mp_host': True})

    def fixture(self, case='disjoint-returns', mode='toolkit', index=1):
        enabled = mode == 'toolkit'; token = 'case-token-' + case
        actors = [dict(role=role, onlineId=i + 10,
                       front=dict(id=100 if case == 'contested-pickup' else 100 + i, ft='Base.BookCarpentry1', total=220, initial=219),
                       tail=dict(id=200 + i, ft='Base.BookCooking1', total=220, initial=219)) for i, role in enumerate(a.ROLES)]
        items = {}
        for actor in actors:
            for name in ('front', 'tail'):
                book = actor[name]
                endpoint = actor['role'] + '-root' if name == 'tail' else ('source1' if case in ('shared-capacity', 'contested-pickup') else 'source' + actor['role'][-1])
                items[book['id']] = dict(id=book['id'], ft=book['ft'], initialEndpoint=endpoint)
        seed = dict(case=case, token=token, index=index, actors=actors, items=list(items.values()),
                    originalRootIds={'client1': [301], 'client2': [302]},
                    stores=[dict(key='source1', x=1, y=2, z=0, index=0, capacity=10),
                            dict(key='source2', x=2, y=2, z=0, index=0, capacity=10)])
        clients = {}
        for actor in actors:
            role = actor['role']; loser = role == 'client2' and case in ('shared-capacity', 'contested-pickup')
            lost = role == 'client1' and case == 'lost-done'
            records = []
            for seq, kind in enumerate(('pickup', 'front', 'return', 'tail'), 1):
                book = actor['tail' if kind == 'tail' else 'front']
                unstarted = loser and case == 'contested-pickup' and kind in ('front', 'return') or kind == 'tail' and (lost or loser and not enabled)
                failed = loser and kind == ('pickup' if case == 'contested-pickup' else 'return')
                waiting = lost and kind == 'return'
                tx = 20 + seq if kind in ('pickup', 'return') and not unstarted else False
                record = dict(sequence=seq, role=kind, item=book['id'], actionRef=role + '-' + case + '-' + kind,
                    nativeRef=False if unstarted else 'native-' + role + '-' + case + '-' + kind,
                    token=(42 if kind != 'tail' else 43) if enabled else False,
                    started=not unstarted, progress=not unstarted, duration=79200 if kind in ('front', 'tail') else -1,
                    transaction=tx, finishes=[], samples=[])
                if not unstarted:
                    record['samples'] = [dict(point='started', at=seq * 100, transaction=tx, done=False, rejected=False, observation=False)]
                    if not failed and not waiting:
                        record['samples'].append(dict(point='perform-begin', at=seq * 100 + 50, transaction=tx,
                            done=kind in ('pickup', 'return'), rejected=False, observation=False))
                        record['finishes'] = [dict(phase='perform', at=seq * 100 + 60, succeeded=True)]
                if failed or waiting:
                    record['nativeStopEntry'] = dict(actor=actor['onlineId'], item=actor['front']['id'], transaction=tx,
                        nativeRef=record['nativeRef'], at=seq * 100 + 50, done=False, rejected=failed,
                        current=True, endpointsExact=True, observation=False)
                    record['nativeStopReturned'] = dict(transaction=0 if enabled and failed else tx,
                        at=seq * 100 + 60, sameNative=True, returned=True)
                    record['finishes'] = [dict(phase='stop', at=seq * 100 + 60, succeeded=True)]
                elif enabled and kind == 'return' and not unstarted:
                    observation = dict(phase='submitted', boundary='start', sourceExact=True, paired=False,
                        currentHandle=True, nativeHandle=True, wireAmbiguous=False, ambiguous=False,
                        transaction=tx, id=book['id'], fullType=book['ft'])
                    for sample in record['samples']: sample['observation'] = copy.deepcopy(observation)
                    record['samples'].append(dict(point='perform-finish', at=seq * 100 + 60, transaction=0,
                        done=True, rejected=True, observation=dict(observation, paired=True, currentHandle=False)))
                if enabled and failed and kind == 'pickup':
                    record['nativeStopEntry']['refusal'] = dict(phase='submitted', sourceExact=True, currentHandle=True,
                        nativeHandle=True, wireAmbiguous=False, ambiguous=False, refused=False, transaction=tx,
                        id=book['id'], fullType=book['ft'])
                records.append(record)
            tail_pages = actor['tail']['initial'] if lost or loser and not enabled else actor['tail']['total']
            clients[role] = dict(case=case, token=token, index=index, role=role, onlineId=actor['onlineId'], mode=mode,
                queueEnabled=enabled, sourceBound=True, records=records, tailPages=tail_pages, tailInitial=actor['tail']['initial'],
                tailTotal=actor['tail']['total'], frontPages=actor['front']['initial'] if loser and case == 'contested-pickup' else actor['front']['total'],
                blocked=[dict(id=1, itemId=actor['front']['id'], state='blocked', reason='capacity')] if loser and case == 'shared-capacity' and enabled else [],
                keptIds=[actor['front']['id']] if loser and case == 'shared-capacity' and enabled else [], queueIdle=True, unknown=False)
            if lost:
                probe = dict(sourceExact=True, historyFromConnectionStart=True, armed=True, bound=True, used=True,
                    droppedDone=1, droppedAccept=0, droppedReject=0, passedAccept=1, passedReject=0, attempts=1,
                    requestCount=1, reused=0, nativePresent=True, pendingExact=True, nativeState='Accept',
                    transaction=records[2]['transaction'], item=actor['front']['id'], actor=actor['onlineId'], failure='',
                    closed='', fault='drop-only-native-Done-no-replay')
                private = dict(phase='submitted', boundary='start', sourceExact=True, currentHandle=True, nativeHandle=True,
                    paired=False, wireAmbiguous=False, ambiguous=False, transaction=probe['transaction'], id=actor['front']['id'], fullType=actor['front']['ft']) if enabled else False
                clients[role]['unknown'] = dict(probe=probe, done=False, rejected=False, privateState=private, cleared=True,
                    recovery=dict(count=0, skipped=1, reason='unknown-native-outcome') if enabled else False,
                    afterProbe=dict(probe, armed=False, nativePresent=False, pendingExact=False, closed='native-transaction-retired-or-ambiguous'))
        final = {}
        for actor in actors:
            role = actor['role']
            loser = role == 'client2' and case == 'shared-capacity'
            endpoint = role + '-root' if loser else 'source1' if case in ('shared-capacity', 'contested-pickup') else 'source' + role[-1]
            final[actor['front']['id']] = dict(id=actor['front']['id'], ft=actor['front']['ft'], endpoint=endpoint, count=1, pages=actor['front']['total'])
            final[actor['tail']['id']] = dict(id=actor['tail']['id'], ft=actor['tail']['ft'], endpoint=role + '-root', count=1, pages=clients[role]['tailPages'])
        result = dict(case=case, token=token, index=index, items=list(final.values()), originalsPreserved=True,
            capacity={key: dict(weight=1 if key == 'source1' else 0, capacity=1 if case == 'shared-capacity' and key == 'source1' else 10)
                      for key in ('source1', 'source2')}, clients=clients)
        release = dict(case=case, token=token, index=index)
        capacity = dict(release, capacity=1, roomBefore=True, combinedFits=False, items=[actor['front']['id'] for actor in actors]) if case == 'shared-capacity' else None
        applied = dict(release, items=copy.deepcopy(result['items'])) if case == 'lost-done' else None
        return dict(seed=seed, result=result, clients=clients, release=release, capacity=capacity, applied=applied,
                    selection=self.selection(mode, [case]), case=case, index=index)

    def check(self, evidence):
        return a.check_case(**evidence)

    def logs(self, selection):
        result = {'server': ['[STARTUP_TEST] SERVER_READY']}
        for role in a.ROLES:
            result[role] = ['[QUEUE_TEST] PREFLIGHT_COMPLETE mods=' + str(len(a.MODS)) + ' mode=' + selection['mode'], '[QUEUE_TEST] NATIVE_CONNECTED']
        for index, case in enumerate(selection['cases'], 1):
            data = self.fixture(case, selection['mode'], index)
            for event, key in [('SEED', 'seed'), ('RELEASE', 'release'), ('CAPACITY', 'capacity'), ('APPLIED', 'applied'), ('RESULT', 'result')]:
                if data[key] is not None:
                    result['server'].append(a.PREFIX + event + ' ' + json.dumps(data[key]))
            for role in a.ROLES:
                result[role].append(a.PREFIX + 'CASE ' + json.dumps(data['clients'][role]))
        for lines in result.values():
            lines.append(a.PREFIX + 'COMPLETE ' + json.dumps(a._finish(selection)))
        return {role: '\n'.join(lines) for role, lines in result.items()}

    def verify(self, logs, selection=None):
        with tempfile.TemporaryDirectory() as directory:
            for role, text in logs.items():
                (Path(directory) / (role + '-launch.log')).write_text(text)
            return a.verify(directory, selection or self.selection(), {})

    def test_all_modes_and_cases(self):
        for mode in ('native', 'toolkit'):
            a.validate(self.selection(mode))
            for case in a.CASES:
                with self.subTest(mode=mode, case=case):
                    self.assertEqual(self.check(self.fixture(case, mode)), [])
            audit = self.verify(self.logs(self.selection(mode)), self.selection(mode))
            self.assertEqual(audit['issues'], [])
            self.assertEqual([(o['actor'], o['case']) for o in audit['outcomes']], [(r, c) for r in a.ROLES for c in a.CASES])
            self.assertTrue(all(o['status'] == 'passed' for o in audit['outcomes']))

    def test_selection_canonical_subsets_and_host_pack(self):
        for cases in ([a.CASES[0]], [a.CASES[1], a.CASES[3]], list(a.CASES)):
            selection = self.selection(cases=cases); a.validate(selection)
            self.assertFalse(self.verify(self.logs(selection), selection)['issues'])
        mutations = [lambda s: s.update(cases=[]), lambda s: s.update(cases=['lost-done', 'shared-capacity']),
            lambda s: s.update(cases=['lost-done', 'lost-done']), lambda s: s.update(cases=['unknown']),
            lambda s: s.update(kind='sp'), lambda s: s.update(clients=True), lambda s: s.update(clients=1),
            lambda s: s.update(languages=['RU', 'EN']), lambda s: s['options'].update(mp_host=False),
            lambda s: s['options'].update(world_template='reuse'), lambda s: s['mods'].pop()]
        for mutate in mutations:
            selection = self.selection(); mutate(selection)
            with self.assertRaises(ValueError): a.validate(selection)

    def test_mp_transfer_pending_duration_is_exact_native_minus_one(self):
        for mode in ('native', 'toolkit'):
            self.assertEqual(self.check(self.fixture(mode=mode)), [])
            for index, wrong in ((0, -2), (2, -2), (0, 100), (2, 0), (1, -1), (3, -1)):
                data = self.fixture(mode=mode); data['clients']['client1']['records'][index]['duration'] = wrong
                with self.subTest(mode=mode, index=index, wrong=wrong): self.assertTrue(self.check(data))

    def test_actor_item_and_native_receipt_mutations(self):
        changes = {
            'aliased native actors': lambda e: e['seed']['actors'][1].update(onlineId=10),
            'wrong client actor': lambda e: e['clients']['client1'].update(onlineId=11),
            'foreign action item': lambda e: e['clients']['client1']['records'][2].update(item=999),
            'duplicate action': lambda e: e['clients']['client1']['records'][2].update(actionRef=e['clients']['client1']['records'][1]['actionRef']),
            'foreign native episode': lambda e: e['clients']['client1']['records'][2].update(nativeRef=e['clients']['client1']['records'][1]['nativeRef']),
            'foreign operation': lambda e: e['clients']['client1']['records'][2].update(token=999),
            'zero native ID': lambda e: e['clients']['client1']['records'][2].update(transaction=0),
            'vacuous Done and Reject': lambda e: e['clients']['client1']['records'][2]['samples'][1].update(rejected=True),
            'no real finish': lambda e: e['clients']['client1']['records'][2].update(finishes=[]),
            'reader no progress': lambda e: e['clients']['client1']['records'][1].update(progress=False),
            'tail unread': lambda e: e['clients']['client1'].update(tailPages=219),
            'physical duplicate': lambda e: e['result']['items'][0].update(count=2),
            'wrong physical owner': lambda e: e['result']['items'][0].update(endpoint='client2-root'),
            'original item lost': lambda e: e['result'].update(originalsPreserved=False),
            'overfull container': lambda e: e['result']['capacity']['source1'].update(weight=99),
            'wrong release': lambda e: e['release'].update(token='foreign'),
        }
        for name, change in changes.items():
            with self.subTest(name=name):
                data = self.fixture(); change(data); self.assertTrue(self.check(data), name)
        for field, value in [('id', 999), ('fullType', 'Base.Pen'), ('transaction', 2), ('sourceExact', False), ('wireAmbiguous', True)]:
            data = self.fixture(); record = data['clients']['client1']['records'][2]; sample = record['samples'][1]
            observation = dict(phase='submitted', boundary='start', sourceExact=True, paired=False, currentHandle=True,
                nativeHandle=True, wireAmbiguous=False, ambiguous=False, transaction=sample['transaction'], id=record['item'], fullType='Base.BookCarpentry1')
            observation[field] = value; sample['observation'] = observation
            with self.subTest(field=field): self.assertTrue(self.check(data), field)

    def test_advisory_pairing_requires_earlier_exact_attempt_and_allows_retired_cursor(self):
        data = self.fixture()
        record = data['clients']['client1']['records'][2]
        self.assertEqual(record['samples'][-1]['transaction'], 0)
        self.assertEqual(self.check(data), [])
        record['samples'][1]['observation']['paired'] = True
        self.assertTrue(self.check(data))
        data = self.fixture(); record = data['clients']['client1']['records'][2]
        for sample in record['samples'][:2]: sample['observation'] = False
        self.assertTrue(self.check(data))
        data = self.fixture(); record = data['clients']['client1']['records'][2]
        record['samples'][-1]['observation']['paired'] = False
        self.assertTrue(self.check(data))
        data = self.fixture(); record = data['clients']['client1']['records'][2]
        before = dict(record['samples'][0]['observation'], phase='before', currentHandle=False, nativeHandle=False,
                      wireAmbiguous=True)
        before.pop('transaction'); before.pop('ambiguous')
        record['samples'].insert(0, dict(point='pending', at=200, transaction=0, done=True, rejected=True, observation=before))
        self.assertEqual(self.check(data), [])

    def test_shared_capacity_and_rejected_pickup_do_not_borrow_authority(self):
        for case in ('shared-capacity', 'contested-pickup'):
            mutations = [lambda e: e['clients']['client2']['records'][0 if case == 'contested-pickup' else 2]['nativeStopEntry'].update(rejected=False),
                lambda e: e['clients']['client2']['records'][0 if case == 'contested-pickup' else 2]['nativeStopEntry'].update(done=True),
                lambda e: e['clients']['client2']['records'][0 if case == 'contested-pickup' else 2]['nativeStopEntry'].update(actor=10),
                lambda e: e['clients']['client2']['records'][0 if case == 'contested-pickup' else 2]['nativeStopReturned'].update(sameNative=False)]
            for mutate in mutations:
                data = self.fixture(case); mutate(data); self.assertTrue(self.check(data))
        for mutate in (lambda e: e['capacity'].update(combinedFits=True), lambda e: e['capacity'].update(items=[100, 100]),
                       lambda e: e['clients']['client2'].update(keptIds=[]),
                       lambda e: e['clients']['client2']['blocked'][0].update(itemId=100)):
            data = self.fixture('shared-capacity'); mutate(data); self.assertTrue(self.check(data))
        data = self.fixture('contested-pickup')
        data['clients']['client2']['records'][2]['samples'] = [dict(point='pending', at=400, transaction=False, done=False, rejected=False, observation={})]
        self.assertTrue(self.check(data))

    def test_rejected_pickup_requires_neutral_fresh_proof_and_preserved_tail(self):
        for field, value in (('sourceExact', False), ('currentHandle', False), ('nativeHandle', False),
                             ('wireAmbiguous', True), ('ambiguous', True), ('transaction', -7),
                             ('refused', True), ('id', 999), ('phase', 'failed')):
            data = self.fixture('contested-pickup')
            data['clients']['client2']['records'][0]['nativeStopEntry']['refusal'][field] = value
            self.assertTrue(self.check(data), field)
        data = self.fixture('contested-pickup')
        data['clients']['client2']['tailPages'] = 219
        self.assertTrue(self.check(data), 'old tail loss must fail the repaired contract')

    def test_guarded_rejected_pickup_and_return_reset_only_their_exact_cursor(self):
        pickup = self.fixture('contested-pickup')
        rejected_pickup = pickup['clients']['client2']['records'][0]
        self.assertEqual(rejected_pickup['nativeStopReturned']['transaction'], 0)
        self.assertEqual(self.check(pickup), [])
        rejected_pickup['nativeStopReturned']['transaction'] = rejected_pickup['transaction']
        self.assertTrue(self.check(pickup))
        returning = self.fixture('shared-capacity')
        rejected_return = returning['clients']['client2']['records'][2]
        self.assertEqual(rejected_return['nativeStopReturned']['transaction'], 0)
        self.assertEqual(self.check(returning), [])
        rejected_return['nativeStopReturned']['transaction'] = rejected_return['transaction']
        self.assertTrue(self.check(returning))

    def test_native_operation_tokens_and_zero_time_supplemental_callback_are_diagnostic(self):
        data = self.fixture('shared-capacity', 'native')
        for row in data['clients'].values():
            for record in row['records']: record['token'] = 73
        self.assertEqual(self.check(data), [])
        record = dict(sequence=5, role='return', item=101, actionRef='instant-return', nativeRef='instant-native',
            token=74, started=False, progress=False, duration=0, transaction=0,
            finishes=[dict(phase='perform', at=560, succeeded=True)], samples=[
                dict(point=point, at=at, transaction=0, done=True, rejected=True, observation=False)
                for point, at in [('perform-begin', 550), ('perform-finish', 560)]])
        data['clients']['client2']['records'].append(record)
        self.assertEqual(self.check(data), [])
        record['samples'].pop()
        self.assertTrue(self.check(data))

    def test_supplemental_real_native_returns_keep_independent_rejection_identity(self):
        data = self.fixture('shared-capacity', 'native')
        record = copy.deepcopy(data['clients']['client2']['records'][2])
        record.update(sequence=5, actionRef='supplemental-return', nativeRef='supplemental-native', transaction=-17)
        record['nativeStopEntry'].update(transaction=-17, nativeRef='supplemental-native')
        record['nativeStopReturned'].update(transaction=-17)
        for sample in record['samples']: sample['transaction'] = -17
        data['clients']['client2']['records'].append(record)
        self.assertEqual(self.check(data), [])
        record['nativeStopEntry']['transaction'] = 23
        self.assertTrue(self.check(data))

    def test_unknown_pending_and_no_replay_are_separate_from_physical_return(self):
        changes = {
            'no independent applied evidence': lambda e: e.update(applied=None),
            'physical not returned before clear': lambda e: e['applied']['items'][0].update(endpoint='client1-root'),
            'raw Done true': lambda e: e['clients']['client1']['unknown'].update(done=True),
            'raw Reject true': lambda e: e['clients']['client1']['unknown'].update(rejected=True),
            'not cleared': lambda e: e['clients']['client1']['unknown'].update(cleared=False),
            'absent tx treated pending': lambda e: e['clients']['client1']['unknown']['probe'].update(nativePresent=False),
            'byte-only correlation': lambda e: e['clients']['client1']['unknown']['probe'].update(pendingExact=False),
            'reused byte': lambda e: e['clients']['client1']['unknown']['probe'].update(reused=1),
            'foreign actor probe': lambda e: e['clients']['client1']['unknown']['probe'].update(actor=11),
            'no actual drop': lambda e: e['clients']['client1']['unknown']['probe'].update(droppedDone=0),
            'accepted ack dropped': lambda e: e['clients']['client1']['unknown']['probe'].update(droppedAccept=1),
            'fake success pair': lambda e: e['clients']['client1']['unknown']['privateState'].update(paired=True),
            'foreign receipt': lambda e: e['clients']['client1']['unknown']['privateState'].update(id=101),
            'missing live handle': lambda e: e['clients']['client1']['unknown']['privateState'].update(currentHandle=False),
            'replayed native request': lambda e: e['clients']['client1']['unknown']['afterProbe'].update(attempts=2),
            'unsafe recovery retained': lambda e: e['clients']['client1']['unknown']['recovery'].update(skipped=0),
            'false successful return': lambda e: e['clients']['client1']['records'][2]['finishes'].append(dict(phase='perform', at=390, succeeded=True)),
            'published Keep': lambda e: e['clients']['client1'].update(keptIds=[100]),
        }
        for name, mutate in changes.items():
            data = self.fixture('lost-done'); mutate(data)
            with self.subTest(name=name): self.assertTrue(self.check(data), name)
        data = self.fixture('lost-done', 'native'); data['clients']['client1']['unknown']['privateState'] = {}
        self.assertTrue(self.check(data))

    def test_strict_raw_json_completion_and_lifecycle(self):
        selection = self.selection(); logs = self.logs(selection)
        changes = {
            'server missing': lambda d: d.pop('server'),
            'missing result': lambda d: d.update(server='\n'.join(l for l in d['server'].splitlines() if a.PREFIX + 'RESULT ' not in l)),
            'missing seed': lambda d: d.update(server='\n'.join(l for l in d['server'].splitlines() if a.PREFIX + 'SEED ' not in l)),
            'missing applied': lambda d: d.update(server='\n'.join(l for l in d['server'].splitlines() if a.PREFIX + 'APPLIED ' not in l)),
            'duplicate client': lambda d: d.update(client1=d['client1'] + '\n' + next(l for l in d['client1'].splitlines() if a.PREFIX + 'CASE ' in l)),
            'cleanup missing': lambda d: d.update(server='\n'.join(l for l in d['server'].splitlines() if a.PREFIX + 'COMPLETE ' not in l)),
            'wrong restore': lambda d: d.update(client1=d['client1'].replace('"restored": true', '"restored": false')),
            'duplicate JSON key': lambda d: d.update(server=d['server'].replace('"originalsPreserved": true', '"originalsPreserved": true, "originalsPreserved": true')),
            'nonfinite receipt': lambda d: d.update(server=d['server'].replace('"weight": 1', '"weight": NaN')),
            'client/server mismatch': lambda d: d.update(client2=d['client2'].replace('"onlineId": 11', '"onlineId": 99')),
        }
        for name, mutate in changes.items():
            data = copy.deepcopy(logs); mutate(data)
            with self.subTest(name=name): self.assertTrue(self.verify(data)['issues'], name)
        lines = logs['server'].splitlines(); release = next(i for i, line in enumerate(lines) if a.PREFIX + 'RELEASE ' in line)
        lines[release], lines[release - 1] = lines[release - 1], lines[release]
        self.assertTrue(self.verify(dict(logs, server='\n'.join(lines)))['issues'])
        for role in ('server', *a.ROLES):
            self.assertTrue(a.complete(selection, role, logs[role]))
            self.assertFalse(a.complete(selection, role, logs[role] + '\n' + logs[role].splitlines()[-1]))

    def test_stage_ships_two_disposable_probes_without_book_control_lua(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory); probe = base / 'probe.jar'; probe.write_bytes(b'probe')
            stop = base / 'stop.jar'; stop.write_bytes(b'stop')
            runtime = {'roles': {role: {'cache': str(base / role)} for role in ('server', *a.ROLES)}}
            with mock.patch.object(a, '_probe', return_value=probe), mock.patch.object(a, '_stop_probe', return_value=stop):
                a.stage(ROOT, base / 'output', base / 'game', base / 'jdk', self.selection(), {}, runtime)
            self.assertEqual(runtime['fixture']['mods'], ['QueuePeersProbe', 'BookControlsStopProbe'])
            self.assertEqual(runtime['fixture']['sandbox']['MinutesPerPage'], 2.0)
            for role in runtime['roles'].values():
                cache = Path(role['cache'])
                self.assertTrue((cache / 'mods/QueuePeersProbe/42/media/java/QueuePeersProbe.jar').is_file())
                self.assertIn('net.alexredby.queuepeersprobe', (cache / 'mods/QueuePeersProbe/42/mod.info').read_text())
                lua = cache / 'mods/ActionQueueTest/42/media/lua'
                self.assertTrue((lua / 'client/ZZStartup.lua').is_file())
                self.assertTrue((lua / 'server/ZZStartupServer.lua').is_file())
                self.assertTrue((lua / 'shared/QueueHealthEvents.lua').is_file())
                self.assertTrue((lua / 'shared/QueueEnergyPlacement.lua').is_file())
                self.assertFalse(list(lua.rglob('*BookControls*.lua')))


if __name__ == '__main__':
    unittest.main()
