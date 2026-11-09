"""Causal negative mutations for deferred native cursor approach receipts."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import approach_queue as a
from queue_checks.mod_selection import metadata, mod_ids


class ApproachAdapterTests(unittest.TestCase):
    def selection(self, kind='mp', mode='toolkit'):
        return dict(suite='approach-queue', cases=list(a.CASES), kind=kind, mode=mode, clients=1,
                    languages=['EN'], mods=list(a.MODS), options={'mp_host': True} if kind == 'mp' else {})

    def evidence(self, case='bush', kind='mp', mode='toolkit'):
        enabled = mode == 'toolkit'; native_host = kind == 'mp' and not enabled
        spec = dict(case=case, mode=mode, origin=dict(x=100, y=200, z=0),
                    targets={n: dict(x=100 + dx, y=200, z=0, index=1, sprite='stock_' + case,
                                     marker=case + '-' + n) for n, dx in (('first', 7), ('second', -1))},
                    tool=dict(id=101, type='Base.HuntingKnife'),
                    book=dict(id=102, type='Base.BookCarpentry1', pages=220, initial=219))
        spec['placement'] = copy.deepcopy(spec['origin'])
        root = [dict(id=101, type='Base.HuntingKnife'), dict(id=102, type='Base.BookCarpentry1')]
        def snapshot(final):
            value = dict(case=case, targets={}, root=copy.deepcopy(root), ground={},
                         order=(['first', 'second'] if enabled else ['second']) if final else [], effects=[],
                         book=dict(id=102, type='Base.BookCarpentry1', pages=220 if final else 219,
                                   characterPages=220 if final else 219, root=True))
            for i, name in enumerate(('first', 'second')):
                removed = final and (enabled or name == 'second')
                target = spec['targets'][name]
                value['targets'][name] = dict(identity=copy.deepcopy(target), objects=[] if removed else [
                    {k: target[k] for k in ('marker', 'index', 'sprite')}])
                value['ground'][name] = [dict(id=200 + i, type='Base.Twigs')] if removed and case == 'bush' else []
                if removed and case == 'manual-grass':
                    value['root'].extend(dict(id=200 + i * 2 + j, type='Base.GrassTuft') for j in range(2))
            if final:
                previous_root = copy.deepcopy(root); previous_ground = {'first': [], 'second': []}
                for name in value['order']:
                    previous_ground[name] = copy.deepcopy(value['ground'][name])
                    if case == 'manual-grass':
                        offset = 0 if name == 'first' else 2
                        previous_root.extend(dict(id=200 + offset + j, type='Base.GrassTuft') for j in range(2))
                    value['effects'].append(dict(name=name, root=copy.deepcopy(previous_root), ground=copy.deepcopy(previous_ground)))
            return value
        baseline, final = snapshot(False), snapshot(True)
        origin = dict(x=100.5, y=200.5, z=0)
        firstpos = dict(x=106.5, y=200.5, z=0)
        secondpos = dict(x=99.5, y=200.5, z=0)
        commands = []
        for i, name in enumerate(('first', 'second', 'tail')):
            tail = name == 'tail'; started = enabled or name != 'first'; duration = 79200 if tail else 100 if case == 'bush' else 50
            command = dict(name=name, type='ISReadABook' if tail else 'ISRemoveBush' if case == 'bush' else 'ISRemoveGrass',
                           producer='native ISReadABook constructor' if tail else 'native ISRemovePlantCursor.tryBuild',
                           admittedAt=i * 10 + 1, duration=duration, started=started, progress=started, cancelled=not enabled and name == 'first',
                           itemId=102 if tail else False, target=False if tail else copy.deepcopy(spec['targets'][name]), token=i + 1)
            if started:
                command.update(effectiveDuration=duration, nativeDurationBefore=duration, nativeDurationAfter=duration,
                               durationSampleBefore=10, durationSampleAfter=20, allocatedAt=20, startedAt=30 + i * 100,
                               durationSamples=2, endedAt=80 + i * 100,
                               startPosition=copy.deepcopy(secondpos if name != 'first' else firstpos))
            commands.append(command)
        walks = [dict(type='ISWalkToTimedAction', duration=-1, destination=copy.deepcopy(firstpos),
                      admittedAt=1, started=True, progress=enabled, cancelled=not enabled, startedAt=25,
                      endedAt=29, startPosition=copy.deepcopy(origin), endPosition=copy.deepcopy(firstpos if enabled else origin), token=1)]
        if enabled:
            walks.append(dict(type='ISWalkToTimedAction', duration=-1, destination=copy.deepcopy(secondpos),
                              admittedAt=90, started=True, progress=True, cancelled=False, startedAt=100,
                              endedAt=120, startPosition=copy.deepcopy(firstpos), endPosition=copy.deepcopy(secondpos), token=2))
        row = dict(suite='approach-queue', event='case', id=case, actor='client1', kind=kind, mode=mode,
                   status='passed', ids=copy.deepcopy(spec), input=copy.deepcopy(baseline), authorityBaseline=copy.deepcopy(baseline),
                   client=copy.deepcopy(final), server=copy.deepcopy(final), commands=commands, walks=walks,
                   order=['first', 'second', 'tail'] if enabled else ['second', 'tail'],
                   secondIssue=dict(firstWalking=True, position=origin, firstStartedAt=25, issuedAt=26,
                                    firstRetainedAfterIssue=enabled, firstJavaRetainedAfterIssue=enabled),
                   queueIdle=True, settleMilliseconds=1000, lifecycleUnchanged=True)
        if native_host:
            states = [dict(case=case, observedAt=at, player=17, transaction=5,
                           kind='ISRemoveBush' if case == 'bush' else 'ISRemoveGrass',
                           token='deadbeef-1234-1234-1234-123456789abc', state=status, matched=True,
                           name='second', type='ISRemoveBush' if case == 'bush' else 'ISRemoveGrass',
                           actionRef='second action', nativeRef='second native', currentActionRef='second action', referenceStable=True)
                      for at, status in ((40, 'started'), (175, 'completed'))]
            row['commands'][1]['nativeStates'] = states
            row['commands'][2]['nativeStates'] = [dict(case=case, observedAt=at, player=17, transaction=6,
                kind='ISReadABook', token='aeadbeef-1234-1234-1234-123456789abc', state=status, matched=True,
                name='tail', type='ISReadABook', actionRef='tail action', nativeRef='tail native',
                currentActionRef='tail action', referenceStable=True) for at, status in ((240, 'started'), (275, 'completed'))]
            row['clientIdle'] = dict(case=case, phase='running', observedAt=281, client=copy.deepcopy(final),
                                    queue=dict(current=False, currentType=False, pending=[], hasTimedActions=False, nativeCount=0,
                                               pressedMovement=False, pressedCancel=False, manualInputSeen=False, position=secondpos))
            row['serverIdle'] = copy.deepcopy(final); row['manualInputSeen'] = False
        return row, spec, baseline, final

    def check(self, evidence, selection=None):
        row, spec, baseline, final = evidence
        return a.check_case(row, row['id'], selection or self.selection(), spec, baseline, final,
                            [v for c in row['commands'] for v in c.get('nativeStates', [])], row.get('clientIdle'), row.get('serverIdle'))

    def proof(self, target, mode):
        actual = dict(x=target['x'] + .5, y=target['y'] + .5, z=target['z'],
                      square=copy.deepcopy(target), currentSquare=copy.deepcopy(target))
        if mode == 'local':
            actual.update(queued=0, timed=False, moving=False, hasPath=False, deferredX=0, deferredY=0)
        return dict(mode=mode, target=copy.deepcopy(target), actual=actual,
                    teleports=int(mode == 'local'), stableMs=500, quietMs=500 if mode == 'local' else 0,
                    elapsedMs=1100, centered=True, centers=int(mode == 'local'))

    def logs(self, kind='mp', mode='toolkit'):
        client = ['[QUEUE_CHECK] ' + json.dumps(dict(suite='approach-queue', event='setup',
            cases=list(a.CASES), queueEnabled=mode == 'toolkit', nativeDurations=True))]
        server = []
        def raw(marker, value):
            return a.PREFIX + marker + ' ' + json.dumps(value)
        for i, case in enumerate(a.CASES):
            evidence = self.evidence(case, kind, mode)
            # The next native case starts after real walking, so its corridor can move.
            def shift(value):
                if isinstance(value, dict):
                    if 'x' in value: value['x'] += i * 20
                    for child in value.values(): shift(child)
                elif isinstance(value, (list, tuple)):
                    for child in value: shift(child)
            shift(evidence)
            row, spec, baseline, final = evidence
            target = spec['placement']
            local = dict(case=case, actor='client1', target=copy.deepcopy(target), proof=self.proof(target, 'local'))
            remote = dict(case=case, actor='client1', target=copy.deepcopy(target),
                          proof=self.proof(target, 'replica')) if kind == 'mp' else copy.deepcopy(local)
            authority = server if kind == 'mp' else client
            authority.append(raw('LAYOUT', dict(case=case, actor='client1', target=copy.deepcopy(target))))
            client.append(raw('CLIENT_PLACEMENT', local))
            authority.extend(raw(marker, value) for marker, value in (
                ('AUTHORITY_PLACEMENT', remote), ('PREPARED', spec), ('BASELINE', baseline)))
            client.append(raw('ADMITTED', dict(case=case, actor='client1')))
            if kind == 'mp' and mode == 'native':
                client.extend(raw('NATIVE_STATE', value) for command in row['commands'] for value in command.get('nativeStates', []))
                client.extend(raw(marker, value) for marker, value in (
                    ('CLIENT_IDLE', row['clientIdle']), ('SERVER_SNAPSHOT', row['serverIdle'])))
                authority.append(raw('SNAPSHOT', row['serverIdle']))
            authority.append(raw('VERIFIED', final))
            client.append('[QUEUE_CHECK] ' + json.dumps(row))
        client.extend(['[QUEUE_CHECK] ' + json.dumps(dict(suite='approach-queue', event='complete',
            cases=list(a.CASES), performed=2, failed=0, skipped=0)), raw('COMPLETE', dict(cases=list(a.CASES)))])
        return client, server

    def verify_logs(self, client, server, selection=None):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'client1-launch.log').write_text('\n'.join(client))
            (root / 'server-launch.log').write_text('\n'.join(server))
            return a.verify(root, selection or self.selection(), {})

    def test_both_cases_four_modes(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                selection = self.selection(kind, mode); a.validate(selection)
                for case in a.CASES:
                    with self.subTest(kind=kind, mode=mode, case=case):
                        self.assertEqual(self.check(self.evidence(case, kind, mode), selection), [])

    def test_causal_negative_mutations(self):
        mutations = {
            'wrong target marker': lambda r: r['ids']['targets']['first'].update(marker='fake'),
            'same target twice': lambda r: r['ids']['targets'].update(second=r['ids']['targets']['first']),
            'first remains': lambda r: r['client']['targets']['first']['objects'].append(dict(marker='bush-first', index=1, sprite='stock_bush')),
            'wrong exact authority': lambda r: r['server']['targets']['first']['identity'].update(index=9),
            'client only success': lambda r: r['server']['targets']['second']['objects'].append({}),
            'removed in reverse': lambda r: r['server'].update(order=['second', 'first']),
            'changed old item': lambda r: r['client']['root'][0].update(type='Base.KitchenKnife'),
            'lost old item': lambda r: r['server']['root'].pop(0),
            'foreign root loot': lambda r: r['client']['root'].append(dict(id=999, type='Base.Twigs')),
            'missing bush loot': lambda r: r['server']['ground']['second'].clear(),
            'duplicate bush loot': lambda r: r['client']['ground']['first'].append(dict(id=999, type='Base.Twigs')),
            'foreign loot': lambda r: r['client']['ground']['second'].append(dict(id=999, type='Base.Axe')),
            'ground root duplicate': lambda r: r['client']['ground']['first'][0].update(id=101),
            'per-target loot removed': lambda r: r['server']['effects'][0]['ground']['first'].clear(),
            'effects skipped': lambda r: r['client']['effects'].pop(),
            'effects reordered': lambda r: r['server']['effects'].reverse(),
            'first not walking': lambda r: r['secondIssue'].update(firstWalking=False),
            'late second submission': lambda r: r['secondIssue'].update(position=dict(x=107, y=200, z=0)),
            'no active walk': lambda r: r['secondIssue'].update(firstStartedAt=27),
            'first queue cancelled': lambda r: r['secondIssue'].update(firstRetainedAfterIssue=False),
            'first Java cancelled': lambda r: r['secondIssue'].update(firstJavaRetainedAfterIssue=False),
            'removal order': lambda r: r.update(order=['second', 'first', 'tail']),
            'no tail': lambda r: r['commands'].pop(),
            'tail skipped': lambda r: r['commands'][-1].update(started=False),
            'fake producer': lambda r: r['commands'][0].update(producer='direct doRemovePlant'),
            'zero duration': lambda r: r['commands'][0].update(effectiveDuration=0),
            'declared duration changed': lambda r: r['commands'][0].update(duration=1),
            'duration bracket wide': lambda r: r['commands'][0].update(nativeDurationAfter=101),
            'stale bracket': lambda r: r['commands'][0].update(durationSampleBefore=100),
            'no real progress': lambda r: r['commands'][0].update(progress=False),
            'remote native remove': lambda r: r['commands'][0].update(startPosition=dict(x=100, y=200, z=0)),
            'shared independent token': lambda r: r['commands'][-1].update(token=1),
            'changed native lifecycle': lambda r: r.update(lifecycleUnchanged=False),
            'no second walk': lambda r: r['walks'].pop(),
            'second route captured early': lambda r: r['walks'][-1].update(admittedAt=1),
            'second from original position': lambda r: r['walks'][-1].update(startPosition=dict(x=100.5, y=200.5, z=0)),
            'second ends elsewhere': lambda r: r['walks'][-1].update(endPosition=dict(x=107, y=200, z=0)),
            'walk no native progress': lambda r: r['walks'][0].update(progress=False),
            'walk wrong operation': lambda r: r['walks'][-1].update(token=1),
            'instant walk': lambda r: r['walks'][0].update(duration=1),
            'walk reordered': lambda r: r['walks'].reverse(),
            'not settled': lambda r: r.update(settleMilliseconds=999),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name):
                evidence = self.evidence(); mutate(evidence[0]); self.assertTrue(self.check(evidence), name)

    def test_grass_stock_loot_bounds_and_exact_ids(self):
        for mutate in (lambda r: r['client']['root'].pop(),
                       lambda r: r['server']['root'][-1].update(id=101),
                       lambda r: r['server']['root'][-1].update(type='Base.Twigs')):
            evidence = self.evidence('manual-grass'); mutate(evidence[0]); self.assertTrue(self.check(evidence))

    def test_native_controls_cannot_claim_queue_fix(self):
        selection = self.selection(mode='native')
        for mutate in (lambda r: r['secondIssue'].update(firstRetainedAfterIssue=True),
                       lambda r: r['walks'][0].update(cancelled=False),
                       lambda r: r.update(order=['first', 'second', 'tail']),
                       lambda r: r['client']['targets']['first'].update(objects=[])):
            evidence = self.evidence(mode='native'); mutate(evidence[0]); self.assertTrue(self.check(evidence, selection))

    def test_native_host_control_rejects_arbitrary_cancellation_and_progress(self):
        selection = self.selection(mode='native')
        changes = {
            'second canceled receipt': lambda r: r['commands'][1]['nativeStates'][-1].update(state='canceled'),
            'second rejected receipt': lambda r: r['commands'][1]['nativeStates'][-1].update(state='rejected'),
            'wrong UUID': lambda r: r['commands'][1]['nativeStates'][-1].update(token='12345678-1234-1234-1234-123456789abc'),
            'wrong actor': lambda r: r['commands'][1]['nativeStates'][-1].update(player=18),
            'wrong transaction': lambda r: r['commands'][1]['nativeStates'][-1].update(transaction=6),
            'wrong native ref': lambda r: r['commands'][1]['nativeStates'][-1].update(nativeRef='other action'),
            'unmatched completion': lambda r: r['commands'][1]['nativeStates'][-1].update(matched=False),
            'not current completed action': lambda r: r['commands'][1]['nativeStates'][-1].update(currentActionRef=False),
            'completion before start': lambda r: r['commands'][1]['nativeStates'].reverse(),
            'missing completion': lambda r: r['commands'][1]['nativeStates'].pop(),
            'tail initial pages': lambda r: r['server']['book'].update(pages=219, characterPages=219),
            'tail unchanged at idle': lambda r: r['clientIdle']['client']['book'].update(pages=219, characterPages=219),
            'tail was not allocated': lambda r: r['commands'][-1].pop('allocatedAt'),
            'tail had native receipt': lambda r: r['commands'][-1].update(nativeStates=[{}]),
            'tail not started': lambda r: r['commands'][-1].update(started=False, progress=False),
            'tail partial progress': lambda r: r['commands'][-1].update(progress=False),
            'tail missing ACK': lambda r: r['commands'][-1]['nativeStates'].pop(),
            'tail rejected': lambda r: r['commands'][-1]['nativeStates'][-1].update(state='rejected'),
            'tail token canceled': lambda r: r['commands'][-1].update(cancelled=True),
            'second token canceled': lambda r: r['commands'][1].update(cancelled=True),
            'tail canceled': lambda r: r['commands'][-1]['nativeStates'][-1].update(state='canceled'),
            'tail current pointer changed': lambda r: r['commands'][-1]['nativeStates'][-1].update(currentActionRef='second action'),
            'tail foreign actor': lambda r: r['commands'][-1]['nativeStates'][-1].update(player=18),
            'tail no native reference': lambda r: r['commands'][-1]['nativeStates'][-1].update(nativeRef=False),
            'tail stale native reference': lambda r: r['commands'][-1]['nativeStates'][-1].update(referenceStable=False),
            'tail no native progress': lambda r: r['commands'][-1].update(effectiveDuration=0),
            'tail early native completion': lambda r: r['commands'][-1]['nativeStates'][-1].update(observedAt=235),
            'tail ACK before removal completed': lambda r: r['commands'][-1]['nativeStates'][0].update(observedAt=170),
            'idle before tail completion': lambda r: r['clientIdle'].update(observedAt=181),
            'first Java walk retained': lambda r: r['secondIssue'].update(firstJavaRetainedAfterIssue=True),
            'tail shared token': lambda r: r['commands'][-1].update(token=2),
            'unexplained manual input': lambda r: r.update(manualInputSeen=True),
            'manual movement at idle': lambda r: r['clientIdle']['queue'].update(pressedMovement=True),
            'cancel input at idle': lambda r: r['clientIdle']['queue'].update(pressedCancel=True),
            'Java work retained': lambda r: r['clientIdle']['queue'].update(nativeCount=1),
            'late unrelated cancellation': lambda r: r['clientIdle'].update(observedAt=5000),
            'tail admitted after completion': lambda r: r['commands'][-1].update(admittedAt=200),
            'server idle first removed': lambda r: r['serverIdle']['targets']['first'].update(objects=[]),
        }
        for name, change in changes.items():
            with self.subTest(name=name):
                evidence = self.evidence(mode='native'); change(evidence[0]); self.assertTrue(self.check(evidence, selection), name)
        row, spec, baseline, final = self.evidence(mode='native')
        for states in ([], row['commands'][1]['nativeStates'][::-1], row['commands'][1]['nativeStates'] * 2):
            self.assertTrue(a.check_case(row, 'bush', selection, spec, baseline, final, states, row['clientIdle'], row['serverIdle']))

    def test_native_host_receipts_order_callbacks_without_ordering_tick_samples(self):
        evidence = self.evidence(mode='native'); row = evidence[0]
        # observe() visits tracks via pairs() and reads wall-clock milliseconds
        # separately. It may sample the new reader before the old removal's absence.
        row['commands'][-1]['startedAt'] = row['commands'][1]['endedAt'] - 1
        self.assertEqual(self.check(evidence, self.selection(mode='native')), [])
        row['commands'][-1]['nativeStates'][0]['observedAt'] = row['commands'][1]['nativeStates'][-1]['observedAt'] - 1
        self.assertTrue(self.check(evidence, self.selection(mode='native')))

    def test_native_host_reader_requires_distinct_completed_receipts(self):
        selection = self.selection(mode='native')
        for field in ('token', 'transaction', 'actionRef', 'nativeRef'):
            evidence = self.evidence(mode='native'); row = evidence[0]
            for receipt in row['commands'][-1]['nativeStates']:
                receipt[field] = row['commands'][1]['nativeStates'][0][field]
                if field == 'actionRef': receipt['currentActionRef'] = receipt[field]
            self.assertTrue(self.check(evidence, selection), field)
        # This was the historical pre-fix native Host control. A paid removal
        # followed by an untouched reader now loses the completed-reader contract.
        evidence = self.evidence(mode='native'); row = evidence[0]
        row['order'] = ['second']; row['commands'][-1].update(started=False, progress=False)
        row['commands'][-1].pop('nativeStates')
        for key in ('client', 'server', 'serverIdle'):
            row[key]['book'].update(pages=219, characterPages=219)
        row['clientIdle']['client']['book'].update(pages=219, characterPages=219)
        row['clientIdle']['observedAt'] = 181
        self.assertTrue(self.check(evidence, selection))
        client, server = self.logs(mode='native')
        receipts = [i for i, line in enumerate(client) if 'NATIVE_STATE ' in line]
        client[receipts[1]], client[receipts[2]] = client[receipts[2]], client[receipts[1]]
        self.assertTrue(self.verify_logs(client, server, selection)['issues'])

    def test_complete_log_authority_order_and_duplicates(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                with self.subTest(kind=kind, mode=mode):
                    client, server = self.logs(kind, mode)
                    self.assertEqual(self.verify_logs(client, server, self.selection(kind, mode))['issues'], [])
        client, server = self.logs()
        for bad in (server[::-1], server + [server[-1]], server[:-1]):
            self.assertTrue(self.verify_logs(client, bad)['issues'])

    def test_native_host_raw_receipts_and_idle_authority_are_independent(self):
        selection = self.selection(mode='native')
        client, server = self.logs(mode='native')
        good = self.verify_logs(client, server, selection)
        self.assertEqual(good['issues'], [])
        self.assertTrue(all(r['outcome']['effectsVerified'] and r['outcome']['tailCompleted'] for r in good['outcomes']))
        receipts = [v for v in client if a.PREFIX + 'NATIVE_STATE ' in v]
        for bad in ([v for v in client if v != receipts[1]], client + [receipts[0]],
                    client + [receipts[0].replace('"case": "bush"', '"case": "foreign"')]):
            self.assertTrue(self.verify_logs(bad, server, selection)['issues'])
        for authority in ([v for v in server if a.PREFIX + 'SNAPSHOT ' not in v], server[::-1], server + [server[3]]):
            self.assertTrue(self.verify_logs(client, authority, selection)['issues'])

    def test_centered_placement_proof_negatives(self):
        changes = {
            'actor': lambda v: v.update(actor='client2'),
            'case': lambda v: v.update(case='foreign'),
            'foreign field': lambda v: v.update(extra=True),
            'role': lambda v: v['proof'].update(mode='replica'),
            'target': lambda v: v['proof']['target'].update(x=101),
            'corner': lambda v: v['proof']['actual'].update(x=100),
            'near edge': lambda v: v['proof']['actual'].update(x=100.7),
            'current square': lambda v: v['proof']['actual']['currentSquare'].update(x=101),
            'missing centered mode': lambda v: v['proof'].pop('centered'),
            'missing centered count': lambda v: v['proof'].pop('centers'),
            'not centered': lambda v: v['proof'].update(centered=False),
            'no centering': lambda v: v['proof'].update(centers=0),
            'repeated centering': lambda v: v['proof'].update(centers=2),
            'boolean centering count': lambda v: v['proof'].update(centers=True),
            'extra teleport': lambda v: v['proof'].update(teleports=2),
            'unstable': lambda v: v['proof'].update(stableMs=499),
            'not quiet': lambda v: v['proof'].update(quietMs=499),
            'native queue': lambda v: v['proof']['actual'].update(queued=1),
            'moving': lambda v: v['proof']['actual'].update(moving=True),
        }
        for name, change in changes.items():
            with self.subTest(name=name):
                client, server = self.logs()
                i = next(i for i, line in enumerate(client) if 'CLIENT_PLACEMENT ' in line)
                value = json.loads(client[i].split('CLIENT_PLACEMENT ', 1)[1]); change(value)
                client[i] = a.PREFIX + 'CLIENT_PLACEMENT ' + json.dumps(value)
                self.assertTrue(self.verify_logs(client, server)['issues'])
        for name, change in {
            'server local role': lambda v: v['proof'].update(mode='local'),
            'server teleport': lambda v: v['proof'].update(teleports=1),
            'server center': lambda v: v['proof'].update(centers=1),
            'server corner': lambda v: v['proof']['actual'].update(y=200),
            'different target': lambda v: v['target'].update(x=101),
        }.items():
            with self.subTest(name=name):
                client, server = self.logs()
                value = json.loads(server[1].split('AUTHORITY_PLACEMENT ', 1)[1]); change(value)
                server[1] = a.PREFIX + 'AUTHORITY_PLACEMENT ' + json.dumps(value)
                self.assertTrue(self.verify_logs(client, server)['issues'])

    def test_placement_publication_identity_process_and_order(self):
        for kind in ('sp', 'mp'):
            selection = self.selection(kind)
            for marker in ('LAYOUT', 'CLIENT_PLACEMENT', 'AUTHORITY_PLACEMENT', 'ADMITTED'):
                for operation in ('missing', 'duplicate', 'late', 'foreign'):
                    with self.subTest(kind=kind, marker=marker, operation=operation):
                        client, server = self.logs(kind)
                        stream = server if kind == 'mp' and marker in ('LAYOUT', 'AUTHORITY_PLACEMENT') else client
                        i = next(i for i, line in enumerate(stream) if marker + ' ' in line)
                        line = stream[i]
                        if operation == 'missing': stream.pop(i)
                        elif operation == 'duplicate': stream.insert(i, line)
                        elif operation == 'late': stream.append(stream.pop(i))
                        else: stream[i] = line.replace('"case": "bush"', '"case": "foreign"')
                        self.assertTrue(self.verify_logs(client, server, selection)['issues'])
        for marker in ('LAYOUT', 'CLIENT_PLACEMENT', 'ADMITTED', 'AUTHORITY_PLACEMENT'):
            client, server = self.logs()
            source, dest = (server, client) if marker in ('LAYOUT', 'AUTHORITY_PLACEMENT') else (client, server)
            line = next(line for line in source if marker + ' ' in line)
            dest.append(line)
            self.assertTrue(self.verify_logs(client, server)['issues'])
        client, server = self.logs('sp')
        i = next(i for i, line in enumerate(client) if 'AUTHORITY_PLACEMENT ' in line)
        value = json.loads(client[i].split('AUTHORITY_PLACEMENT ', 1)[1]); value['proof']['elapsedMs'] += 1
        client[i] = a.PREFIX + 'AUTHORITY_PLACEMENT ' + json.dumps(value)
        self.assertTrue(self.verify_logs(client, server, self.selection('sp'))['issues'])
        for marker in ('PREPARED', '[QUEUE_CHECK]'):
            client, server = self.logs()
            stream = server if marker == 'PREPARED' else client
            i = next(i for i, line in enumerate(stream) if marker + ' ' in line and ('"origin"' in line))
            stream[i] = stream[i].replace('"placement": {"x": 100', '"placement": {"x": 101')
            self.assertTrue(self.verify_logs(client, server)['issues'])
        client, server = self.logs(mode='native')
        witness = next(line for line in client if 'NATIVE_STATE ' in line)
        client.remove(witness); client.insert(1, witness)
        self.assertTrue(self.verify_logs(client, server, self.selection(mode='native'))['issues'])

    def test_layout_and_admission_exact_fields_and_authority_boundary(self):
        for marker, mutations in (
            ('LAYOUT', (lambda v: v.update(actor='client2'), lambda v: v.update(extra=True),
                        lambda v: v['target'].update(z=False), lambda v: v['target'].update(x=101))),
            ('ADMITTED', (lambda v: v.update(actor='client2'), lambda v: v.update(extra=True))),
        ):
            for mutate in mutations:
                client, server = self.logs()
                stream = server if marker == 'LAYOUT' else client
                i = next(i for i, line in enumerate(stream) if marker + ' ' in line)
                value = json.loads(stream[i].split(marker + ' ', 1)[1]); mutate(value)
                stream[i] = a.PREFIX + marker + ' ' + json.dumps(value)
                self.assertTrue(self.verify_logs(client, server)['issues'])
        for marker in ('PREPARED', 'BASELINE'):
            client, server = self.logs()
            proof = next(i for i, line in enumerate(server) if 'AUTHORITY_PLACEMENT ' in line)
            witness = next(i for i, line in enumerate(server) if marker + ' ' in line)
            server[proof], server[witness] = server[witness], server[proof]
            self.assertTrue(self.verify_logs(client, server)['issues'])
        for field in ('origin', 'placement'):
            evidence = self.evidence()
            evidence[0]['ids'][field]['z'] = False
            self.assertTrue(self.check(evidence))
        client, server = self.logs()
        i = next(i for i, line in enumerate(server) if 'PREPARED ' in line)
        value = json.loads(server[i].split('PREPARED ', 1)[1]); value['origin']['x'] += 1
        server[i] = a.PREFIX + 'PREPARED ' + json.dumps(value)
        self.assertTrue(self.verify_logs(client, server)['issues'])

    def test_registration_selected_pack_and_staging(self):
        from queue_checks import adapters
        self.assertIs(adapters.get('approach-queue'), a)
        expected = json.loads((ROOT / 'tests/native_queue/catalog.json').read_text())['suites']['approach-queue']
        # The JSON records structure; runtime full-pack lists follow the selected INI.
        self.assertIsInstance(expected['default_mods'], list)
        self.assertIsInstance(expected['scenario_actions']['native-cursor-approach']['mods'], list)
        mods = mod_ids(metadata(ROOT / 'SurvivorQoL-selected.ini')['Mods'])
        expected['default_mods'] = mods
        expected['scenario_actions']['native-cursor-approach']['mods'] = mods
        self.assertEqual(a.definitions()['approach-queue'], expected)
        self.assertTrue(all(p.is_file() for p in a.sources(ROOT, self.selection())))
        self.assertIn(ROOT / 'tools/queue_checks/placement.py', a.sources(ROOT, self.selection()))
        for key, value in [('cases', [a.CASES[0]]), ('cases', list(reversed(a.CASES))), ('mods', []), ('clients', 2), ('options', {})]:
            selection = self.selection(); selection[key] = value
            with self.assertRaises(ValueError): a.validate(selection)
        with tempfile.TemporaryDirectory() as temp:
            lua = Path(temp) / 'mods/ActionQueueTest/42/media/lua'
            for side in ('client', 'server', 'shared'): (lua / side).mkdir(parents=True)
            from queue_checks.native import _lua
            generated = dict(self.selection(), port=16261, resources={'exclusive': True})
            (lua / 'shared/QueueTestSelection.lua').write_text('QueueTestSelection=' + _lua(generated) + '\nreturn QueueTestSelection\n')
            game = Path(temp) / 'game'; (game / 'media').mkdir(parents=True)
            (game / 'media/tiledefinitions_erosion.tiles.txt').write_text('\n'.join(
                '// ' + name + '\ntile\n{\nxy = 0,0\n' + flag + ' =\n}\n' for name, flag in a.NATIVE_SPRITES.values()))
            runtime = {'roles': {'client1': {'cache': temp}}}; a.stage(ROOT, None, game, None, self.selection(), None, runtime)
            self.assertTrue((lua / 'client/ZZStartup.lua').is_file())
            from lupa.lua51 import LuaRuntime
            staged = LuaRuntime().execute((lua / 'shared/QueueTestSelection.lua').read_text())
            self.assertTrue(staged['disposable'])
            self.assertEqual(staged['suite'], 'approach-queue'); self.assertEqual(staged['port'], 16261)
            self.assertTrue(staged['resources']['exclusive'])

    def test_exact_native_sprite_definitions_and_runtime_flags(self):
        from lupa.lua51 import LuaRuntime
        with tempfile.TemporaryDirectory() as temp:
            game = Path(temp); (game / 'media').mkdir()
            source = game / 'media/tiledefinitions_erosion.tiles.txt'
            good = '\n'.join('// ' + name + '\ntile\n{\nxy = 0,0\n' + flag + ' =\n}\n'
                             for name, flag in a.NATIVE_SPRITES.values())
            source.write_text(good)
            self.assertEqual([r['sprite'] for r in a.native_sprite_proof(game)], ['f_bushes_1_0', 'e_newgrass_1_0'])
            for bad in (good.replace('canBeCut', 'canBeRemoved'), good.replace('canBeRemoved', 'canBeCut'),
                        good.replace('f_bushes_1_0', 'vegetation_foliage_01_0'), good + good):
                source.write_text(bad)
                with self.assertRaises(ValueError): a.native_sprite_proof(game)
        source = (ROOT / 'tests/native_queue/approach-queue/shared/QueueApproach.lua').read_text()
        helper = 'local function stockSprite' + source.split('local function stockSprite', 1)[1].split('local function square', 1)[0]
        lua = LuaRuntime()
        check = lua.execute("""
            local expected={f_bushes_1_0='canBeCut',e_newgrass_1_0='canBeRemoved'}
            getSprite=function(name)return{getName=function()return name end,getProperties=function()
                return{has=function(_,flag)return expected[name]==flag end}
            end}end
        """ + helper + """
            return function()
                assert(stockSprite('f_bushes_1_0','canBeCut'))
                assert(stockSprite('e_newgrass_1_0','canBeRemoved'))
                assert(not pcall(stockSprite,'f_bushes_1_0','canBeRemoved'))
                assert(not pcall(stockSprite,'vegetation_foliage_01_0','canBeCut'))
            end
        """)
        check()
        self.assertLess(source.index("stockSprite('e_newgrass_1_0'"), source.index(' corridor(origin)', source.index('function F.prepare')))
        self.assertNotIn(':Set(', source)

    def test_layout_is_read_only_and_preparation_clears_loaded_disposable_strip(self):
        from lupa.lua51 import LuaRuntime
        source = (ROOT / 'tests/native_queue/approach-queue/shared/QueueApproach.lua').read_text()
        geometry = 'local function footprint' + source.split('local function footprint', 1)[1].split('function F.prepare', 1)[0]
        check = LuaRuntime().execute("""
            return function(disposable, missing, vehicle, client)
                local writes,recalcs=0,0;local F={}
                local P={choose=function()return{x=0,y=0,z=0}end,target=function(value)return value end}
                local grid={}
                for x=-2,8 do for y=-1,1 do
                    local floor={floor=true};local entries={floor,{decoration=true},{collision=true}}
                    local list={size=function()return #entries end,get=function(_,i)return entries[i+1]end}
                    local square={getFloor=function()return floor end,TreatAsSolidFloor=function()return true end,
                        getRoom=function()return nil end,isVehicleIntersecting=function()return vehicle and x==7 and y==0 end,
                        getObjects=function()return list end,isFree=function()return x==0 and y==0 or #entries==1 end}
                    square.transmitRemoveItemFromSquare=function(_,object)
                        assert(object~=floor);writes=writes+1
                        for i,value in ipairs(entries)do if value==object then table.remove(entries,i);return end end
                        error('removed an unowned scene object')
                    end
                    square.RecalcAllWithNeighbours=function(_,native)assert(native and #entries==1);recalcs=recalcs+1 end
                    grid[x..','..y]=square
                end end
                getCell=function()return{getGridSquare=function(_,x,y,z)
                    if missing and x==8 and y==1 then return nil end
                    return z==0 and grid[x..','..y]or nil
                end}end
                isClient=function()return client end
                require=function(name)assert(name=='QueueTestSelection');return{disposable=disposable}end
                local player=setmetatable({},{__index=function(_,key)error('layout touched player '..key)end})
        """ + geometry + """
                local ok,result=pcall(F.plan,player,'bush')
                assert(writes==0 and recalcs==0,'planning changed the scene')
                if ok then corridor(result.target)end
                return ok,writes,recalcs,result
            end
        """)
        ok, writes, recalcs, result = check(True, False, False, False)
        self.assertTrue(ok); self.assertEqual((writes, recalcs), (66, 33))
        self.assertEqual((result['target']['x'], result['target']['y'], result['target']['z']), (0, 0, 0))
        for flags in ((False, False, False, False), (True, True, False, False),
                      (True, False, True, False), (True, False, False, True)):
            with self.subTest(flags=flags):
                ok, writes, recalcs, result = check(*flags)
                self.assertFalse(ok); self.assertEqual((writes, recalcs), (0, 0))
        for forbidden in ('setX(', 'setY(', 'setZ(', 'setNext', 'setLast', 'teleportTo(', 'setMovingSquareNow('):
            self.assertNotIn(forbidden, source)

    def test_resolve_waits_for_center_without_position_mutation(self):
        from lupa.lua51 import LuaRuntime
        source = (ROOT / 'tests/native_queue/approach-queue/shared/QueueApproach.lua').read_text()
        resolve = 'function F.resolve' + source.split('function F.resolve', 1)[1].split('function F.snapshot', 1)[0]
        check = LuaRuntime().execute("""
            local F={};local target={marker='bush-first',sprite='f_bushes_1_0',index=1}
            local function square()return target end
            local function objects(id)return{id}end
            local spec={case='bush',origin={x=100,y=200,z=0},placement={x=100,y=200,z=0},targets={first=target},
                book={id=1,type='Base.BookCarpentry1',initial=219},tool={id=2}}
            local gearWrites=0
            local book={setAlreadyReadPages=function()gearWrites=gearWrites+1 end};local tool={}
            local root={getItemById=function(_,id)return id==1 and book or tool end}
            local player={x=100,y=200,z=0,getInventory=function()return root end,
                setPrimaryHandItem=function()gearWrites=gearWrites+1 end,setAlreadyReadPages=function()gearWrites=gearWrites+1 end}
            for _,axis in ipairs({'X','Y','Z'})do local key=axis:lower()
                player['get'..axis]=function(self)return self[key]end
            end
            local P={target=function(value)return value end,atCentered=function(p,t)
                return math.abs(p.x-t.x-.5)<=.1 and math.abs(p.y-t.y-.5)<=.1 and p.z==t.z
            end}
        """ + resolve + """
            return function()
                local state,waiting=F.resolve(player,spec)
                assert(not state and waiting.reason=='centered placement differs')
                assert(waiting.actual.x==100 and player.x==100 and player.y==200 and gearWrites==0)
                player.x=100.5;player.y=200.5
                assert(F.resolve(player,spec),'settled local placement was rejected')
                assert(gearWrites==3)
                root.getItemById=function()return nil end
                local missing,detail=F.resolve(player,spec)
                assert(not missing and detail.reason=='items not replicated'and detail.book==false and detail.tool==false)
                assert(gearWrites==3)
            end
        """)
        check()
        client = (ROOT / 'tests/native_queue/approach-queue/client/ZZQueueApproach.lua').read_text()
        self.assertIn("raw('RESOLVE_WAIT'", client)
        self.assertIn('resolveWait=lastResolveWait', client)

    def test_diagnostics_bind_receipts_and_snapshot_without_success(self):
        from lupa.lua51 import LuaRuntime
        source = (ROOT / 'tests/native_queue/approach-queue/client/ZZQueueApproach.lua').read_text()
        observer = 'local function observeNative' + source.split('local function observeNative', 1)[1].split('Events.OnServerCommand.Add', 1)[0]
        check = LuaRuntime().execute("""
            local rows,wireBindings,tracks={}, {}, {}
            local function now()return 100 end
            local player={getOnlineID=function()return 17 end}
            local native={};local action={character=player,toolkitNativeTransaction=5,toolkitNativeKind='ISRemoveBush',action=native,rendered=0}
            setmetatable(action,{__tostring=function(value)return'ISRemoveBush 0x123{rendered='..value.rendered..'}'end})
            local row={name='second',type='ISRemoveBush'};tracks[action]=row
            local q={current=action}
            local function queue()return q end
            local function case()return 'bush'end
            local function raw(marker,value)assert(marker=='NATIVE_STATE');rows[#rows+1]=value end
            getPlayer=function()return player end;isClient=function()return true end
        """ + observer + """
            return function()
                local args={protocol=1,player=17,transaction=5,kind='ISRemoveBush',token='deadbeef-1234-1234-1234-123456789abc',state='started'}
                observeNative('PZSurvivorToolkitActions','State',args)
                assert(#rows==1 and rows[1].matched and rows[1].name=='second'and rows[1].referenceStable)
                action.rendered=1;args.state='completed'
                observeNative('PZSurvivorToolkitActions','State',args)
                assert(#rows==2 and rows[2].matched and rows[2].actionRef==rows[1].actionRef and #row.nativeStates==2)
                assert(rows[2].currentActionRef==rows[2].actionRef,'mutable table rendering changed current action identity')
                q.current={};observeNative('PZSurvivorToolkitActions','State',args)
                assert(#rows==3 and rows[3].currentActionRef~=rows[3].actionRef and rows[3].referenceStable)
                action.action={};observeNative('PZSurvivorToolkitActions','State',args)
                assert(#rows==4 and not rows[4].referenceStable,'replaced native pointer retained its binding')
                action.action=native
                assert(action.action==native and action.toolkitNativeTransaction==5)
                args.player=18;observeNative('PZSurvivorToolkitActions','State',args);assert(#rows==4)
                args.player=17;args.token='invalid';observeNative('PZSurvivorToolkitActions','State',args);assert(#rows==4)
                args.token='12345678-1234-1234-1234-123456789abc';args.kind='ISReadABook';args.state='rejected'
                observeNative('PZSurvivorToolkitActions','State',args)
                assert(#rows==5 and rows[5].matched==false and #row.nativeStates==4)
            end
        """)
        check()
        server = (ROOT / 'tests/native_queue/approach-queue/server/ZZQueueApproachServer.lua').read_text()
        check = LuaRuntime().execute("""
            local handler,tick;local sent,snapshots={},0
            local F={plan=function(_,case)return{case=case,target={x=0,y=0,z=0}}end,prepare=function(player)return{player=player,ids={case='bush'}}end,
                snapshot=function()snapshots=snapshots+1;return{case='bush',book={pages=219},targets={first=true,second=true}}end,
                verify=function()error('Snapshot invoked success verification')end}
            isServer=function()return true end
            require=function(name) if name=='QueuePreflight' then return {onGameStart=function(events,fn)events.OnGameStart.Add(fn)end,onTick=function(events,fn)events.OnTick.Add(fn)end,removeTick=function(events,fn)events.OnTick.Remove(fn)end}end;
                if name=='QueueApproach'then return F elseif name=='QueueTestSelection'then return{cases={'bush'},mode='native'}
                elseif name=='QueueEnergyPlacement'then return{target=function(v)return v end,observeCentered=function()return{}end,
                    poll=function()return{mode='replica',target={x=0,y=0,z=0},centered=true,centers=0,teleports=0}end,atCentered=function()return true end}end
                return{encode=function()return '{}'end}
            end
            Events={OnClientCommand={Add=function(value)handler=value end},OnTick={Add=function(value)tick=value end}}
            print=function()end
            sendServerCommand=function(_,module,command,args)sent[#sent+1]={command=command,args=args}end
            local player={getUsername=function()return 'client1'end,getCurrentSquare=function()return{}end}
        """ + server + """
            return function()
                handler('QueueApproachTest','Layout',player,{case='bush'})
                handler('QueueApproachTest','Prepare',player,{case='bush',target={x=0,y=0,z=0},
                    clientPlacement={mode='local',target={x=0,y=0,z=0},centered=true,centers=1,teleports=1}})
                tick()
                handler('QueueApproachTest','Snapshot',player,{case='bush'})
                assert(snapshots==1 and #sent==3 and sent[3].command=='Snapshot'and sent[3].args.book.pages==219)
            end
        """)
        check()
        self.assertIn("phase=='running'and #queue().queue==0 and not idleCaptured", source)
        self.assertIn('clientSnapshot=snapshotDiagnostic()', source)
        self.assertIn('lastServerSnapshot=lastServerSnapshot or false', source)
        self.assertIn('queueCurrent=queueDiagnostic()', source)

    def test_fixture_syntax_and_no_lifecycle_or_duration_mutation(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(); compile_chunk = lua.eval('function(source,name)return assert(loadstring(source,name))end')
        for path in (ROOT / 'tests/native_queue/approach-queue').rglob('*.lua'):
            compile_chunk(path.read_text(), str(path))
        source = (ROOT / 'tests/native_queue/approach-queue/client/ZZQueueApproach.lua').read_text()
        self.assertIn('c:tryBuild(id.x,id.y,id.z)', source)
        self.assertNotIn('doRemovePlant(', source); self.assertNotIn('doRemoveGrass(', source)
        for forbidden in ('setCurrentTime', 'setJobDelta', 'setMultiplier', 'forceComplete(', 'getGameTime():set'):
            self.assertNotIn(forbidden, source)
        self.assertNotRegex(source, r'action\.maxTime\s*=(?!=)')
        self.assertNotRegex(source, r'IS(RemoveBush|RemoveGrass|WalkToTimedAction|ReadABook)\.(new|start|stop|update|perform|complete)\s*=')


if __name__ == '__main__': unittest.main()
