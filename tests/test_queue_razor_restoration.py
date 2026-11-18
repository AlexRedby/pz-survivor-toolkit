"""Fail-closed selection and absent/invalid live razor evidence checks."""
import copy
from pathlib import Path
import sys
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / 'tools'))
from queue_checks import adapters
from queue_checks.adapters import razor_restoration as a
from queue_checks.adapters import razor_restoration_verifier as v


def selection(kind='mp'):
    return dict(suite='razor-restoration', cases=list(a.CASES), kind=kind, mode='toolkit',
                languages=['EN'], clients=1, mods=list(a.MODS), options={'mp_host': True} if kind == 'mp' else {})


def control_observation(case):
    # Receipt sub-schemas only; these never constitute a passing native run.
    ids = dict(case=case, initialBeard='LongScruffy', targetBeard='Moustache', bag=dict(id=42, type='Base.Bag_Military'),
               items={name: dict(id=index, type=kind) for index, (name, kind) in enumerate(v.TYPES.items(), 73)})
    ids['items']['tail'].update(initial=8, total=10)
    ids['baseline'] = dict(case=case, appearance=dict(beard='LongScruffy'), primary=74, secondary=False,
        items=[dict(id=42, type='Base.Bag_Military', container='root'),
               *[dict(id=item['id'], type=item['type'], container=42 if name == 'razor' else 'root') for name, item in ids['items'].items()]],
        origin=dict(id=42, type='Base.Bag_Military', container='root', worn=True, sourceCount=1), worn=[dict(id=42, location='Back')],
        tail=dict(id=76, type='Base.BookCarpentry1', pages=8, characterPages=8, total=10))
    roles = {'trim': [dict(actionRef='trim', nativeRef='native', operationRef='episode', startedAt=1)],
             'tail': [dict(actionRef='tail', operationRef='independent', startedAt=10)],
             'command': [dict(actionRef='command')], 'restore': [dict(admittedAt=9)]}
    control = dict(source='authority.ChangeOrigin', input='authority-command', at=2, requestedAt=2, acceptedAt=3,
                   trimRef='trim', trimNative='native', trimDelta=0.4, before=v.borrowed_snapshot(ids), accepted=True)
    changed = copy.deepcopy(control['before'])
    if case == 'unavailable-origin':
        changed['origin'].update(container='unavailable', worn=False); changed['items'][0]['container']='unavailable'; changed['worn']=[]
    origin = dict(case=case, kind='unavailable' if case == 'unavailable-origin' else 'full', authority=True,
                  requestedAt=2, at=3, bagId=42, itemId=73, itemType='Base.Razor', capacityBefore=28, roomBefore=True,
                  capacityAfter=28 if case == 'unavailable-origin' else 0, roomAfter=case == 'unavailable-origin',
                  before=copy.deepcopy(control['before']), after=changed)
    debts = [dict(id=9, itemId=73, itemType='Base.Razor', reason='cleanup-return' if case == 'unavailable-origin' else 'admission', state='blocked')]
    snapshot = v.expected(ids, False); snapshot.pop('authority'); snapshot['tail'].update(pages=8, characterPages=8)
    blocked = dict(at=11, debts=debts, snapshot=snapshot, tailRef='tail', tailStarted=True, tailProgress=False,
                   ui=dict(source='ActionQueuePanel.KeepReturn', visible=True, id=9, itemId=73))
    ev = dict(control=control, origin=origin, blocked=blocked, debts=copy.deepcopy(debts))
    if case == 'keep-return':
        ev['debts']=[]
        ev['keep']=dict(source='ActionQueuePanel.KeepReturn', input='programmatic-press-callback', at=12, id=9, itemId=73,
            before=copy.deepcopy(snapshot), after=copy.deepcopy(snapshot), tailRef='tail',
            **{key: True for key in ('visible', 'tailStarted', 'tailProgress', 'queueActive', 'pressCaptured', 'cleared', 'sameSnapshot', 'accepted')})
    return ids, roles, ev


class RazorRestorationTests(unittest.TestCase):
    def test_runner_declares_ordered_real_producer_bank(self):
        self.assertEqual(adapters.get('razor-restoration'), a)
        self.assertEqual([row['id'] for row in a.definitions()['razor-restoration']['cases']], list(a.CASES))
        for kind in ('sp', 'mp'):
            a.validate(selection(kind))

    def test_selection_refuses_wrong_provider_and_dedicated_host(self):
        mutations = [lambda s: s.update(mode='native'), lambda s: s['mods'].append('P4TidyUpMeister'),
                     lambda s: s['options'].pop('mp_host'), lambda s: s.update(cases=list(reversed(a.CASES))),
                     lambda s: s.update(clients=2), lambda s: s['options'].update(world_template='old-save')]
        for mutate in mutations:
            value = copy.deepcopy(selection()); mutate(value)
            with self.assertRaises(ValueError):
                a.validate(value)

    def test_ordered_subsets_preserve_old_and_individual_control_cases(self):
        self.assertEqual(a.CASES, ('restore-success', 'new-primary-intent', 'cancel-active',
                                  'full-origin', 'unavailable-origin', 'keep-return'))
        for kind in ('sp', 'mp'):
            for cases in (list(a.CASES[:2]), *([case] for case in a.CASES), list(a.CASES[2:])):
                value = selection(kind); value['cases'] = cases
                a.validate(value)
        for cases in ([], ['cancel-active', 'cancel-active'], ['foreign'], ['keep-return', 'full-origin']):
            value = selection(); value['cases'] = cases
            with self.assertRaises(ValueError):
                a.validate(value)

    def test_editor_off_reuses_only_existing_restore_success_in_sp_and_host(self):
        for kind in ('sp', 'mp'):
            value = selection(kind)
            value['cases'] = ['restore-success']
            value['options']['queue_editor_enabled'] = False
            a.validate(value)
            for change in (lambda s: s.update(cases=['new-primary-intent']),
                           lambda s: s.update(cases=list(a.CASES)),
                           lambda s: s['mods'].append('P4TidyUpMeister')):
                changed = copy.deepcopy(value); change(changed)
                with self.assertRaises(ValueError):
                    a.validate(changed)
            for invalid in (None, 0, 1, 'false'):
                value['options']['queue_editor_enabled'] = invalid
                with self.assertRaises(ValueError):
                    a.validate(value)
        enabled = selection(); enabled['options']['queue_editor_enabled'] = True
        a.validate(enabled)

    def test_editor_off_receipts_cover_producer_native_admission_and_completion(self):
        # Editor receipt sub-schema only: no fabricated successful native run.
        actions = [dict(role=name, actionRef=name, admittedAt=2 + index, startedAt=3 + index,
                        events=[dict(at=4 + index)])
                   for index, name in enumerate(('pickup', 'preparationEquip', 'trim', 'restore', 'returned', 'tail'))]
        samples = [dict(boundary='before-producer', at=1, ticks=0, actionRef=False, option=False, setting=False)]
        samples.extend(dict(boundary='native-admission', at=action['admittedAt'], ticks=index,
                            actionRef=action['actionRef'], option=False, setting=False)
                       for index, action in enumerate(actions, 1))
        samples.append(dict(boundary='after-completion', at=10, ticks=10, actionRef=False, option=False, setting=False))
        # Host resolves item proxies between queue construction and native admission.
        actions[1]['actionRef'] = 'ISEquipWeaponAction 0x42{ item=menu reference }'
        samples[2]['actionRef'] = 'ISEquipWeaponAction 0x42{ item=native reference }'
        ev = dict(actions=actions, editor=samples)
        for kind in ('sp', 'mp'):
            value = selection(kind); value['cases'] = ['restore-success']; value['options']['queue_editor_enabled'] = False
            self.assertEqual(v.editor_errors(ev, value), [])
            for mutate in (lambda e: e.pop('editor'), lambda e: e['editor'].pop(0),
                           lambda e: e['editor'].pop(2), lambda e: e['editor'][-1].update(at=8),
                           lambda e: e['editor'][1].update(actionRef='foreign'),
                           lambda e: e['editor'][1].update(option=True),
                           lambda e: e['editor'][1].update(setting=True),
                           lambda e: e['editor'][-1].update(ticks=0),
                           lambda e: e['actions'][0].pop('admittedAt'),
                           lambda e: e['actions'][0]['events'][0].update(at=11)):
                changed = copy.deepcopy(ev); mutate(changed)
                self.assertTrue(v.editor_errors(changed, value))
        self.assertEqual(v.editor_errors({}, selection()), [])
        self.assertTrue(v.editor_errors(ev, selection()))

    def test_active_cancel_requires_native_stop_and_exact_canceled_host_ack(self):
        # Lifecycle sub-schema only: no fabricated successful native case/run.
        action = dict(role='trim', type='ISTrimBeard', nativeRef='native', operationRef='episode',
                      events=[])
        action['ack'] = [dict(state='canceled', kind='ISTrimBeard', transaction=7,
                              token='01234567-89ab-cdef-0123-456789abcdef', nativeRef='native', operationRef='episode',
                              **{key: True for key in ('nativeSame', 'actorSame', 'queueSame', 'rootSame', 'itemSame', 'operationSame')})]
        self.assertEqual(v.lifecycle_errors(action, 'mp', canceled=True), [])
        self.assertEqual(v.lifecycle_errors(action, 'sp', canceled=True), [])
        for mutate in (lambda a: a['ack'][0].update(state='completed'),
                       lambda a: a['ack'][0].update(state='rejected'),
                       lambda a: a['ack'][0].update(nativeSame=False),
                       lambda a: a['ack'][0].update(operationRef='foreign'),
                       lambda a: a['ack'].append(copy.deepcopy(a['ack'][0])),
                       lambda a: a['events'].append(dict(boundary='begin', phase='perform', at=1, nativeRef='native'))):
            changed = copy.deepcopy(action); mutate(changed)
            self.assertTrue(v.lifecycle_errors(changed, 'mp', canceled=True))
        self.assertTrue(v.lifecycle_errors(action, 'mp'))

    def test_approach_admission_requires_exact_container_array_and_token(self):
        # This tests a receipt sub-schema, never a successful native case/run.
        names = ('approach', 'pickup', 'preparationEquip', 'trim', 'command')
        roles = {name: [dict(actionRef=name, operationRef='episode', allocated=True)] for name in names}
        roles['pickup'][0]['sourceRef'] = 'canonical-source'
        ids = {'bag': {'id': 42}}
        ev = dict(producerQueue=list(names), producerEntries=[dict(position=index, actionRef=name, role=name,
                  operationRef='episode', sameToken=True, actorSame=True, queueEntrySame=True)
                  for index, name in enumerate(names, 1)],
                  approach=dict(actionRef='approach', position=1, type='ISQueueActionsAction', bagId=42,
                                containerRef='canonical-source', operationRef='episode', sourceBound=True,
                                pickupSourceSame=True, canonicalBag=True, actorSame=True, sameToken=True,
                                queueSame=True, listSame=True, queueEntrySame=True))
        self.assertEqual(v.producer_errors(ev, roles, ids), [])
        for field, value in [('sourceBound', False), ('bagId', 99), ('position', 2), ('containerRef', 'foreign'),
                             ('operationRef', 'foreign'), ('queueEntrySame', False), ('listSame', False), ('actorSame', False)]:
            changed = copy.deepcopy(ev); changed['approach'][field] = value
            self.assertTrue(v.producer_errors(changed, roles, ids), field)
        changed = copy.deepcopy(ev); changed['producerEntries'][1]['position'] = 1
        self.assertTrue(v.producer_errors(changed, roles, ids))
        changed = copy.deepcopy(ev); changed['producerQueue'] = list(reversed(names))
        self.assertTrue(v.producer_errors(changed, roles, ids))
        changed = copy.deepcopy(roles); changed['pickup'][0]['operationRef'] = 'foreign'
        self.assertTrue(v.producer_errors(ev, changed, ids))

    def test_host_transfer_uses_inventory_transaction_and_canonical_identity(self):
        # Sub-schema observations only; these are not native run/pass receipts.
        ids = dict(case='restore-success', bag=dict(id=42), items={'razor': dict(id=73, type='Base.Razor')})
        physical = dict(case=ids['case'], role='pickup', at=10, authority=False, itemId=73, itemType='Base.Razor',
                        source=42, destination='root', sourceCount=0, destinationCount=1, canonical=True, bagCanonical=True)
        sample = dict(at=10, boundary='begin-perform', transaction=7, done=True, rejected=False, duration=30,
                      physical=physical, itemState='canonical-replica', itemExact=True, itemCanonical=True,
                      nativeRef='native', operationRef='episode', nativeSame=True, actorSame=True, operationSame=True,
                      sourceSame=True, destinationSame=True, queueSame=True, rootSame=True)
        action = dict(role='pickup', nativeRef='native', operationRef='episode', ack=[], transfers=[sample])
        self.assertEqual(v.transfer_errors(action, ids, 'mp'), [])
        cleared = copy.deepcopy(sample); cleared.update(boundary='finish-perform', transaction=0, done=False, itemState='nil', itemCanonical=False)
        action['transfers'].append(cleared)
        self.assertEqual(v.transfer_errors(action, ids, 'mp'), [])
        for mutate in (lambda a: a['transfers'][0].update(sourceSame=False),
                       lambda a: a['transfers'][0].update(itemExact=False),
                       lambda a: a['transfers'][0].update(rejected=True),
                       lambda a: a.update(ack=[dict(state='completed', token='invented')]),
                       lambda a: a['transfers'][0]['physical'].update(itemId=99),
                       lambda a: a['transfers'].reverse()):
            changed = copy.deepcopy(action); mutate(changed)
            self.assertTrue(v.transfer_errors(changed, ids, 'mp'))
        authority = copy.deepcopy(physical); authority['authority'] = True
        receipt = dict(transfers=[authority])
        intent_ids = copy.deepcopy(ids); intent_ids['case'] = 'new-primary-intent'; authority['case'] = intent_ids['case']
        self.assertEqual(v.authority_transfer_errors(receipt, intent_ids), [])
        authority['destinationCount'] = 0; authority['sourceCount'] = 1
        self.assertTrue(v.authority_transfer_errors(receipt, intent_ids))

    def test_origin_authority_and_visible_debt_keep_are_exact(self):
        for case in ('full-origin', 'unavailable-origin', 'keep-return'):
            ids, roles, ev = control_observation(case)
            self.assertEqual(v.control_errors(ev, roles, ids), [], case)
            for mutate in (lambda e: e['origin'].update(authority=False),
                           lambda e: e['origin'].update(itemId=99),
                           lambda e: e['origin']['before'].update(primary=99),
                           lambda e: e['control'].update(trimDelta=1),
                           lambda e: e['control'].update(accepted=False),
                           lambda e: e['blocked']['debts'][0].update(itemId=99),
                           lambda e: e['blocked']['snapshot']['items'].pop(),
                           lambda e: e['blocked']['ui'].update(visible=False),
                           lambda e: e['blocked'].update(tailRef='foreign')):
                changed = copy.deepcopy(ev); mutate(changed)
                self.assertTrue(v.control_errors(changed, roles, ids), case)
        ids, roles, ev = control_observation('keep-return')
        for mutate in (lambda e: e['keep'].update(id=99), lambda e: e['keep'].update(tailProgress=False),
                       lambda e: e['keep'].update(queueActive=False), lambda e: e['keep']['after'].update(primary=99),
                       lambda e: e.update(debts=copy.deepcopy(e['blocked']['debts']))):
            changed = copy.deepcopy(ev); mutate(changed)
            self.assertTrue(v.control_errors(changed, roles, ids))

    def test_host_capacity_replica_is_explicit_and_authority_bound(self):
        ids, roles, ev = control_observation('full-origin')
        self.assertTrue(v.control_errors(ev, roles, ids, 'mp'))
        ev['originReplica'] = dict(source='authority-confirmed-capacity', case='full-origin', at=4, authorityAt=3,
            requestedAt=2, bagId=42, itemId=73, capacityBefore=28, roomBefore=True, capacityAfter=0, roomAfter=False,
            trimRef='trim', trimNative='native', trimDelta=0.5, before=copy.deepcopy(ev['control']['before']),
            after=copy.deepcopy(ev['control']['before']), unchanged=True)
        self.assertEqual(v.control_errors(ev, roles, ids, 'mp'), [])
        self.assertTrue(v.control_errors(ev, roles, ids, 'sp'))
        for mutate in (lambda e: e['originReplica'].update(authorityAt=99),
                       lambda e: e['originReplica'].update(trimDelta=1),
                       lambda e: e['originReplica'].update(itemId=99),
                       lambda e: e['originReplica'].update(roomAfter=True),
                       lambda e: e['originReplica']['after'].update(primary=99)):
            changed = copy.deepcopy(ev); mutate(changed)
            self.assertTrue(v.control_errors(changed, roles, ids, 'mp'))

    def test_active_cancel_matches_real_header_members_and_unchanged_grooming(self):
        ids, roles, ev = control_observation('cancel-active')
        control = ev['control']; control.update(source='ActionQueuePanel.List', input='programmatic-press-release',
            after=copy.deepcopy(control['before']), reason=False, targetRef='trim', operationRef='episode',
            members=['trim', 'command'], **{key: True for key in ('header', 'hitTested', 'pressCaptured', 'tailQueued')})
        before = dict(at=2, actionRef='trim', nativeRef='native', member=True, current=True, beard='LongScruffy',
                      **{key: True for key in ('actionSame', 'nativeSame', 'actorSame', 'queueSame', 'rootSame')})
        after = dict(before, at=3, member=False, current=False, boundary='after-release', snapshot=copy.deepcopy(control['before']))
        control['nativeStop'] = dict(before=before, after=after)
        ev = dict(control=control)
        self.assertEqual(v.control_errors(ev, roles, ids), [])
        for mutate in (lambda e: e['control'].update(members=['trim', 'tail']),
                       lambda e: e['control'].update(operationRef='foreign'),
                       lambda e: e['control'].update(pressCaptured=False),
                       lambda e: e['control'].update(trimNative='foreign'),
                       lambda e: e['control']['after']['appearance'].update(beard='Moustache'),
                       lambda e: e['control']['nativeStop']['after'].update(member=True),
                       lambda e: e['control']['nativeStop']['after'].update(nativeRef='foreign'),
                       lambda e: e['control']['nativeStop']['after'].update(at=10)):
            changed = copy.deepcopy(ev); mutate(changed)
            self.assertTrue(v.control_errors(changed, roles, ids))
        self.assertEqual(v.expected(ids, True)['appearance']['beard'], 'LongScruffy')
        self.assertEqual(v.expected(ids, True)['items'][1]['container'], 42)

    def test_mutable_kahlua_diagnostics_keep_only_exact_action_identity(self):
        self.assertEqual(v.action_key('ISTrimBeard 0x123{ item=razor }'),
                         v.action_key('ISTrimBeard 0x123{ item=razor, action=native }'))
        self.assertNotEqual(v.action_key('ISTrimBeard 0x123{}'), v.action_key('ISTrimBeard 0x124{}'))
        self.assertNotEqual(v.action_key('ISTrimBeard 0x123{}'), v.action_key('ISCutHair 0x123{}'))
        self.assertNotEqual(v.action_key('ISTrimBeard 0x123{}'), v.action_key('ISTrimBeard 0x0123{}'))

    def test_only_exact_sp_admission_failure_accepts_native_nan_duration_diagnostic(self):
        nan = {'__queueNonfiniteNumber': 'nan'}
        self.assertTrue(v.denied_duration(nan, 'admission', 'sp'))
        for value, reason, kind in ((nan, 'server', 'mp'), (nan, 'admission', 'mp'), (nan, 'unmoved', 'sp'),
                                    ({'__queueNonfiniteNumber': '+inf'}, 'admission', 'sp'),
                                    (dict(nan, foreign=True), 'admission', 'sp'), (float('nan'), 'admission', 'sp')):
            self.assertFalse(v.denied_duration(value, reason, kind))

    def test_full_origin_native_admission_failure_is_not_successful_transfer(self):
        ids, _, ev = control_observation('full-origin')
        action = dict(role='returned', actionRef='return', itemId=73, operationRef='episode',
                      allocated=False, started=False, progress=False, events=[], ack=[], transfers=[])
        attempt = dict(at=11, actionRef='return', nativeRef='native-return', itemId=73, reason='admission',
                       allocated=True, started=False, progress=False, queued=False,
                       physical=dict(case=ids['case'], role='returned', at=11, authority=False,
                                     itemId=73, itemType='Base.Razor', source='root', destination=42,
                                     sourceCount=1, destinationCount=0, canonical=True, bagCanonical=True))
        ev['blocked']['returnAttempt'] = attempt
        self.assertEqual(v.denied_return_errors(action, ev, ids, 'mp'), [])
        polled = copy.deepcopy(action); polled.update(allocated=True, nativeRef='native-return', effectiveDuration=0)
        polled['transfers'] = [dict(at=10, boundary='poll', transaction=0, done=False, rejected=False, duration=False,
            physical=copy.deepcopy(attempt['physical']), itemState='original', nativeRef='native-return', operationRef='episode',
            **{key: True for key in ('itemExact', 'nativeSame', 'actorSame', 'operationSame', 'sourceSame', 'destinationSame', 'queueSame', 'rootSame')})]
        self.assertEqual(v.denied_return_errors(polled, ev, ids, 'mp'), [])
        for field, value in (('transaction', 1), ('done', True), ('rejected', True), ('sourceSame', False), ('boundary', 'begin-perform')):
            changed = copy.deepcopy(polled); changed['transfers'][0][field] = value
            self.assertTrue(v.denied_return_errors(changed, ev, ids, 'mp'))
        for mutate in (lambda a,e: e['blocked']['returnAttempt'].update(allocated=False),
                       lambda a,e: e['blocked']['returnAttempt'].update(queued=True),
                       lambda a,e: e['blocked']['returnAttempt']['physical'].update(sourceCount=0, destinationCount=1),
                       lambda a,e: a.update(started=True), lambda a,e: a.update(ack=[dict(state='completed')]),
                       lambda a,e: e['blocked']['returnAttempt'].update(reason='server')):
            changed_action, changed_ev = copy.deepcopy(action), copy.deepcopy(ev); mutate(changed_action, changed_ev)
            self.assertTrue(v.denied_return_errors(changed_action, changed_ev, ids, 'mp'))

    def test_host_rejected_return_requires_exact_inventory_transaction_and_native_stop(self):
        ids, _, ev = control_observation('full-origin')
        ev['blocked']['debts'][0]['reason'] = 'server'
        physical = dict(case=ids['case'], role='returned', at=11, authority=False,
                        itemId=73, itemType='Base.Razor', source='root', destination=42,
                        sourceCount=1, destinationCount=0, canonical=True, bagCanonical=True)
        ev['blocked']['returnAttempt'] = dict(at=12, actionRef='return', nativeRef='native-return', itemId=73,
            reason='server', allocated=True, started=True, progress=True, queued=False, physical=physical)
        sample = dict(at=11, nativeRef='native-return', operationRef='episode', boundary='begin-stop',
            transaction=21, rejected=True, done=False, physical=copy.deepcopy(physical), itemState='canonical-replica',
            **{key: True for key in ('itemExact', 'nativeSame', 'actorSame', 'operationSame', 'sourceSame', 'destinationSame', 'queueSame', 'rootSame')})
        action = dict(role='returned', actionRef='return', nativeRef='native-return', itemId=73, operationRef='episode',
            allocated=True, started=True, progress=True, ack=[], transfers=[sample],
            events=[dict(at=11+index, boundary=boundary, phase='stop', nativeRef='native-return', succeeded=True)
                    for index, boundary in enumerate(('begin', 'finish'))])
        self.assertEqual(v.denied_return_errors(action, ev, ids, 'mp'), [])
        for mutate in (lambda a: a['transfers'][0].update(rejected=False),
                       lambda a: a['transfers'][0].update(sourceSame=False),
                       lambda a: a['transfers'][0].update(done=True),
                       lambda a: a['transfers'][0].update(transaction=0),
                       lambda a: a['events'][0].update(phase='perform'),
                       lambda a: a['transfers'][0]['physical'].update(sourceCount=0, destinationCount=1),
                       lambda a: a['transfers'].append(dict(a['transfers'][0], transaction=22))):
            changed = copy.deepcopy(action); mutate(changed)
            self.assertTrue(v.denied_return_errors(changed, ev, ids, 'mp'))
        self.assertTrue(v.denied_return_errors(action, ev, ids, 'sp'))

    def test_missing_live_logs_never_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            result = v.verify(Path(directory), selection(), {})
        self.assertTrue(result['issues'])
        self.assertTrue(all(row['status'] == 'failed' for row in result['outcomes']))

    def test_empty_case_evidence_never_passes(self):
        for kind in ('sp', 'mp'):
            self.assertTrue(v.check_case({}, selection(kind), {}, {}))

    def test_sources_exist_and_exclude_legacy_synthetic_producer(self):
        sources = a.sources(PROJECT, selection())
        self.assertTrue(all(path.is_file() for path in sources))
        self.assertFalse(any('claimed-return/client' in str(path) for path in sources))


if __name__ == '__main__':
    unittest.main()
