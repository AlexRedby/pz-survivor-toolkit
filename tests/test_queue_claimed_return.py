"""Fail-closed claimed-return selection, native bridge and evidence checks."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / 'tools'))
from queue_checks import adapters
from queue_checks.adapters import claimed_return as a
from queue_checks.adapters import claimed_return_verifier as v


def placement_proof(target, mode='local'):
    actual = dict(target, x=target['x'] + .5, y=target['y'] + .5,
                  square=dict(target), currentSquare=dict(target))
    if mode == 'local':
        actual.update(queued=0, timed=False, moving=False, hasPath=False, deferredX=0, deferredY=0)
    return dict(mode=mode, target=dict(target), actual=actual, teleports=int(mode == 'local'),
                centered=True, centers=int(mode == 'local'), stableMs=500,
                quietMs=500 if mode == 'local' else 0, elapsedMs=1500)


def selection(kind='mp'):
    return dict(suite='claimed-return', cases=list(a.CASES), kind=kind, mode='toolkit',
                languages=['EN'], clients=1, mods=list(a.MODS),
                options={'mp_host': True} if kind == 'mp' else {})


def evidence(case='claimed-success', kind='mp', offset=0):
    cancelled = case.startswith('claimed-cancel')
    success = case in ('claimed-success', 'claimed-cancel-success')
    origin = dict(x=10, y=20, z=0)
    ids = dict(case=case, placement=origin,
               placementProof=placement_proof(origin, 'replica' if kind == 'mp' else 'local'),
               bag={'id': 90 + offset, 'type': 'Base.Bag_Military'}, items={
                   name: dict(id=100 + offset + index, type=type_name, pages=220, initial=216)
                   for index, (name, type_name) in enumerate(v.TYPES.items())})
    def snapshot(phase):
        initial = phase == 'before'; final = phase == 'final'
        rows = {}
        for name, spec in ids['items'].items():
            root = name != 'borrowed' or not initial and (not final or not success)
            pages = 216 if initial or name == 'previous' or not final and name == 'tail' else 220
            if name == 'borrowed' and cancelled and not initial: pages = 216
            rows[name] = dict(id=spec['id'], type=spec['type'], root=int(root), source=int(not root), pages=pages, total=220)
        previous = initial or phase == 'continuation' or final and success
        return dict(case=case, items=rows, primary=ids['items']['previous' if previous else 'borrowed']['id'], secondary=False,
                    bag=dict(ids['bag'], canonicalRoot=True, worn=True, sourceSame=True))
    ev = dict(claimAccepted=True, originalReturnAllocated=False, originalReturnRef='original-' + case,
              returnAllocated=success, cancelAccepted=cancelled, freshOperation=cancelled,
              stopRequested=not success, queueIdle=True, returnCalls=int(success),
              expandedAt=400, expansionSnapshot=snapshot('expanded'), before=snapshot('before'),
              nativeCallbacksUntouched=True, loanEarnedAtExpansion=True,
              debts=[] if success else [dict(id=1, itemId=ids['items']['borrowed']['id'],
                                            itemType=ids['items']['borrowed']['type'], state='blocked', reason='cleanup-outcome')])
    times = {'pickup': 100, 'preparationEquip': 200, 'body': 300, 'expansion': 400, 'restore': 500,
             'continuation': 650, 'returned': 700, 'tail': 800}
    for name, action_type in v.ACTION_TYPES.items():
        if name == 'returned' and not success: continue
        token = 'tail' if name == 'tail' else 'fresh' if cancelled and name in ('restore', 'expansion', 'continuation', 'returned') else 'original'
        native = name not in ('continuation', 'expansion')
        begun = native or name == 'expansion' or success
        item_name = 'previous' if name == 'restore' else 'tail' if name == 'tail' else 'borrowed'
        action = dict(type=action_type, actionRef=name + '-' + case, allocated=begun,
                      itemId=ids['items'][item_name]['id'] if native else False,
                      duration=-1 if kind == 'mp' and action_type == 'ISInventoryTransferAction' else 50,
                      effectiveDuration=50, started=begun, progress=begun, nativeStarted=begun, events=[])
        if begun:
            action.update(startedAt=times[name], nativeRef='native-' + name + '-' + case, operationRef=token)
        completed = native and not (name == 'body' and cancelled or name == 'restore' and not success)
        if completed:
            for index, phase in enumerate(['perform', 'complete'] if kind == 'sp' else ['perform']):
                action['events'] += [dict(boundary='begin', phase=phase, at=times[name] + 10 + index * 2, nativeRef=action['nativeRef']),
                                     dict(boundary='finish', phase=phase, at=times[name] + 11 + index * 2,
                                          nativeRef=action['nativeRef'], succeeded=True)]
        ev[name] = action
    ev['restore']['ack'] = []
    if kind == 'mp':
        ev['restore']['ack'] = [dict(at=600, state='completed' if success else 'canceled', captured=True, kind='ISEquipWeaponAction',
                                     transaction=1, token='12345678-1234-1234-1234-123456789abc', nativeSame=True,
                                     itemSame=True, actorSame=True, queueSame=True, rootSame=True, operationSame=True,
                                     nativeRef=ev['restore']['nativeRef'], operationRef=ev['restore']['operationRef'])]
    if cancelled: ev['cancelRequestedAt'] = 350
    if success: ev.update(continuationAt=650, continuationSnapshot=snapshot('continuation'), restoreEffectEarned=True)
    else: ev.update(stopRequestedAt=550, beforeStop=snapshot('expanded'))
    final = snapshot('final'); final['authority'] = kind == 'sp'
    authority = copy.deepcopy(final); authority['authority'] = True
    ev['after'] = copy.deepcopy(final)
    tail_snapshot = snapshot('final'); tail_snapshot['items']['tail']['pages'] = 216
    ev['tailBoundary'] = dict(at=800, restoreNativeRemoved=True, restoreAck='completed' if success else 'canceled',
                              restoreRef=ev['restore']['nativeRef'], tailActionRef=ev['tail']['actionRef'],
                              tailRef=ev['tail']['nativeRef'], tailAllocated=True, tailAllocatedAt=800, snapshot=tail_snapshot)
    if kind == 'mp' and case == 'claimed-failure':
        terminal = ev['restore']['ack'][0]
        ev['pendingAfterRemoval'] = dict(at=575, ack='started', currentRestore=True, nativeContained=False,
            continuationAllocated=False, tailAllocated=False, returnCalls=0, snapshot=snapshot('expanded'),
            nativeRef=ev['restore']['nativeRef'], transaction=terminal['transaction'], token=terminal['token'])
    row = dict(suite='claimed-return', event='case', id=case, status='passed', actor='client1', kind=kind, mode='toolkit',
               ids=ids, clientPlacement=placement_proof(origin), client=final, server=authority, evidence=ev)
    return row, copy.deepcopy(ids), copy.deepcopy(authority)


def logs(kind='mp', *, post_removal=True):
    chosen = selection(kind); cases = chosen['cases']
    client = []; server = []
    def emit(target, marker, row): target.append(marker + json.dumps(row))
    emit(client, '[QUEUE_CHECK] ', dict(suite='claimed-return', event='setup', cases=cases, nativeDurations=True, provider='native-returns'))
    for index, case in enumerate(cases):
        row, prepared, verified = evidence(case, kind, index * 100)
        if not post_removal:
            row['evidence'].pop('pendingAfterRemoval', None)
        emit(client, a.PREFIX + 'CLIENT_PLACEMENT ', {'case': case, 'proof': row['clientPlacement']})
        authority = server if kind == 'mp' else client
        emit(authority, a.PREFIX + 'PREPARED ', prepared)
        if 'pendingAfterRemoval' in row['evidence']:
            emit(client, a.PREFIX + 'PENDING_AFTER_REMOVAL ', dict(case=case, observation=row['evidence']['pendingAfterRemoval']))
        for ack in row['evidence']['restore']['ack']:
            emit(client, a.PREFIX + 'ACK ', dict(case=case, actionRef=row['evidence']['restore']['actionRef'], observation=ack))
        emit(authority, a.PREFIX + 'VERIFIED ', verified)
        emit(client, '[QUEUE_CHECK] ', row)
    emit(client, '[QUEUE_CHECK] ', dict(suite='claimed-return', event='complete', cases=cases, performed=len(cases), failed=0, skipped=0))
    emit(client, a.PREFIX + 'COMPLETE ', dict(cases=cases))
    return '\n'.join(client), '\n'.join(server)


class ClaimedReturnAdapterTests(unittest.TestCase):
    def test_supported_native_topologies_and_registered_cases(self):
        for kind in ('sp', 'mp'):
            a.validate(selection(kind))
        self.assertIs(adapters.get('claimed-return'), a)
        spec = a.definitions()['claimed-return']
        self.assertEqual([case['id'] for case in spec['cases']], list(a.CASES))
        self.assertNotIn('P4TidyUpMeister', spec['default_mods'])
        self.assertTrue(all(case['modes'] == ['toolkit'] for case in spec['cases']))

    def test_rejects_incompatible_inputs_before_native_preparation(self):
        for key, value in [('cases', []), ('cases', list(reversed(a.CASES))),
                           ('cases', [a.CASES[0], a.CASES[0]]), ('cases', ['foreign']),
                           ('mode', 'native'), ('clients', True), ('clients', 2),
                           ('mods', [*a.MODS, 'P4TidyUpMeister']), ('languages', ['RU']),
                           ('options', {}), ('options', {'mp_host': True, 'world_template': '/unused'})]:
            with self.subTest(key=key, value=value):
                value_selection = selection(); value_selection[key] = value
                with self.assertRaises(ValueError):
                    a.validate(value_selection)

    def test_bridge_requires_actual_candidate_classes(self):
        with tempfile.TemporaryDirectory() as directory:
            jar = Path(directory) / '42/media/java/PZToolkitJavaPatches.jar'
            jar.parent.mkdir(parents=True)
            names = ['ActionCompletion', 'ActionAcknowledgements', 'ActionAcknowledgementLogic']
            for omitted in [*names, None]:
                with zipfile.ZipFile(jar, 'w') as archive:
                    for name in names:
                        if name != omitted:
                            archive.writestr('net/alexredby/pztoolkitjavapatches/' + name + '.class', b'fixture')
                if omitted:
                    with self.assertRaises(ValueError):
                        a.audit_bridge({'PZToolkitJavaPatches': directory})
                else:
                    a.audit_bridge({'PZToolkitJavaPatches': directory})

    def test_completion_is_exact_and_rejects_ambiguous_json(self):
        text = a.PREFIX + 'COMPLETE ' + json.dumps({'cases': list(a.CASES)})
        self.assertTrue(a.complete(selection(), 'client1', text))
        self.assertFalse(a.complete(selection(), 'server', text))
        self.assertFalse(a.complete(selection(), 'client1', text + '\n' + text))
        self.assertFalse(a.complete(selection(), 'client1', a.PREFIX + 'COMPLETE {"cases":[],"cases":[]}'))

    def test_native_effect_and_stopped_debt_cases(self):
        for kind in ('sp', 'mp'):
            for case in a.CASES:
                with self.subTest(kind=kind, case=case):
                    row, ids, authority = evidence(case, kind)
                    self.assertEqual(v.check_case(row, selection(kind), ids, authority), [])

    def test_causal_corruptions_fail_closed(self):
        mutations = [
            lambda row: row['evidence'].__setitem__('originalReturnAllocated', True),
            lambda row: row['evidence']['restore'].__setitem__('operationRef', 'foreign'),
            lambda row: row['evidence']['tail'].__setitem__('operationRef', 'original'),
            lambda row: row['evidence']['restore']['events'][0].__setitem__('nativeRef', 'foreign'),
            lambda row: row['evidence']['restore']['ack'][0].__setitem__('token', 'foreign'),
            lambda row: row['evidence']['restore']['ack'][0].__setitem__('nativeSame', False),
            lambda row: row['evidence']['continuationSnapshot'].__setitem__('primary', row['ids']['items']['borrowed']['id']),
            lambda row: row['evidence'].__setitem__('continuationAt', 450),
            lambda row: row['client']['items']['borrowed'].__setitem__('root', 1),
            lambda row: row['server']['items']['tail'].__setitem__('pages', 219),
            lambda row: row['evidence']['pickup'].__setitem__('duration', 1),
            lambda row: row['evidence']['tailBoundary'].__setitem__('tailActionRef', 'foreign'),
            lambda row: row['evidence']['tailBoundary'].__setitem__('tailRef', 'foreign'),
            lambda row: row['evidence']['tailBoundary'].__setitem__('tailAllocatedAt', 900),
        ]
        for mutate in mutations:
            row, ids, authority = evidence()
            mutate(row)
            with self.subTest(mutation=mutate):
                self.assertTrue(v.check_case(row, selection(), ids, authority))
        for case in ('claimed-failure', 'claimed-cancel'):
            for mutate in [lambda row: row['evidence']['continuation'].__setitem__('allocated', True),
                           lambda row: row['evidence']['debts'][0].__setitem__('reason', 'cleanup-unresolved'),
                           lambda row: row['evidence'].__setitem__('returnCalls', 1),
                           lambda row: row['evidence'].__setitem__('freshOperation', case != 'claimed-cancel')]:
                row, ids, authority = evidence(case)
                mutate(row)
                with self.subTest(case=case, mutation=mutate):
                    self.assertTrue(v.check_case(row, selection(), ids, authority))

    def test_native_operation_identity_ignores_only_mutable_table_metadata(self):
        row, ids, authority = evidence('claimed-cancel-success')
        for name in ('pickup', 'preparationEquip', 'body'):
            row['evidence'][name]['operationRef'] = 'table 0x123{ old=true }'
        row['evidence']['restore']['operationRef'] = 'table 0x456{ presentation=table 0x111 }'
        row['evidence']['returned']['operationRef'] = 'table 0x456{ presentation=table 0x222 }'
        terminal = row['evidence']['restore']['ack'][0]
        terminal['operationRef'] = 'table 0x456{ presentation=table 0x333 }'
        self.assertEqual(v.check_case(row, selection(), ids, authority), [])
        terminal['operationSame'] = False
        self.assertTrue(v.check_case(row, selection(), ids, authority))
        terminal['operationSame'] = True
        for bad in ('table 0x457{ presentation=table 0x333 }', 'table 0x456 trailing',
                    'table 0x0456{ presentation=table 0x333 }', 'table 0x456{ missing-close',
                    'table 0x2147483648{ presentation=table 0x333 }'):
            terminal['operationRef'] = bad
            with self.subTest(reference=bad):
                self.assertTrue(v.check_case(row, selection(), ids, authority))
        terminal['operationRef'] = 'table 0x456{ presentation=table 0x333 }'
        row['evidence']['tail']['operationRef'] = 'table 0x456{ presentation=table 0x444 }'
        self.assertTrue(v.check_case(row, selection(), ids, authority))
        row, ids, authority = evidence()
        row['evidence']['restore']['ack'][0]['operationRef'] = 'original{ metadata=true }'
        self.assertTrue(v.check_case(row, selection(), ids, authority))

    def test_full_receipt_streams_and_process_order(self):
        for kind in ('sp', 'mp'):
            client, server = logs(kind)
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / 'client1-launch.log').write_text(client)
                if kind == 'mp': (root / 'server-launch.log').write_text(server)
                self.assertEqual(v.verify(root, selection(kind), {})['issues'], [])
                lines = client.splitlines()
                position = next(index for index, line in enumerate(lines) if 'CLIENT_PLACEMENT ' in line)
                lines.append(lines.pop(position))
                (root / 'client1-launch.log').write_text('\n'.join(lines))
                self.assertTrue(v.verify(root, selection(kind), {})['issues'])
        client, server = logs()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'server-launch.log').write_text(server)
            for bad_client in [client + '\n' + next(line for line in client.splitlines() if 'ACK ' in line),
                               client + '\n' + server.splitlines()[0],
                               client + '\n' + a.PREFIX + 'ACK {"case":"foreign"}',
                               client + '\n' + a.PREFIX + 'COMPLETE {"cases":[],"cases":[]}']:
                (root / 'client1-launch.log').write_text(bad_client)
                self.assertTrue(v.verify(root, selection(), {})['issues'])

    def test_pending_authority_before_and_after_native_removal_are_distinct(self):
        row, ids, authority = evidence('claimed-failure')
        before = copy.deepcopy(row['evidence']['pendingAfterRemoval']); before['nativeContained'] = True
        row['evidence']['pendingAuthority'] = before
        self.assertEqual(v.check_case(row, selection(), ids, authority), [])
        row['evidence']['pendingAuthority']['nativeContained'] = False
        self.assertTrue(v.check_case(row, selection(), ids, authority))
        for key, bad in [('nativeContained', True), ('currentRestore', False), ('continuationAllocated', True),
                         ('tailAllocated', True), ('returnCalls', 1), ('returnCalls', False), ('nativeRef', 'foreign'),
                         ('transaction', 2), ('transaction', True), ('token', 'foreign'), ('ack', 'canceled'),
                         ('at', 500), ('at', 700)]:
            row, ids, authority = evidence('claimed-failure')
            row['evidence']['pendingAfterRemoval'][key] = bad
            with self.subTest(field=key, value=bad):
                self.assertTrue(v.check_case(row, selection(), ids, authority))

    def test_host_group_requires_raw_post_removal_pending_window(self):
        client, server = logs(post_removal=False)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'server-launch.log').write_text(server)
            (root / 'client1-launch.log').write_text(client)
            self.assertIn('Host stopped-case group lacks an observed post-removal pending authority window',
                          v.verify(root, selection(), {})['issues'])
            client, server = logs()
            pending = next(line for line in client.splitlines() if 'PENDING_AFTER_REMOVAL ' in line)
            for bad_client in [client.replace(pending + '\n', ''), client + '\n' + pending,
                               client.replace(pending + '\n', '') + '\n' + pending]:
                (root / 'client1-launch.log').write_text(bad_client)
                self.assertTrue(v.verify(root, selection(), {})['issues'])
            (root / 'client1-launch.log').write_text(client)
            (root / 'server-launch.log').write_text(server + '\n' + pending)
            self.assertTrue(v.verify(root, selection(), {})['issues'])


if __name__ == '__main__':
    unittest.main()
