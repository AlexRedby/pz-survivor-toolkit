"""Synthetic hidden-affinity receipts validate the checker, never a native game pass."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import adapters
from queue_checks.adapters import warehouse_workload as A
from queue_checks.adapters import warehouse_affinity_verify as V
from tests.test_queue_warehouse_workload import fixture as peer_fixture, find


def selection(case='hidden-affinity'):
    return dict(suite=A.SUITE, cases=[case], kind='mp', mode='toolkit', clients=2,
                languages=['EN', 'RU'], mods=list(A.MODS), options={'mp_host': True})


def fixture(outcomes=None, case='hidden-affinity'):
    """Produce internally consistent, independent copies of the declared receipts."""
    physical = case == 'physical-affinity'
    kinds = ('type', 'category') * (2 if physical else 1)
    outcomes = outcomes or (('fresh',)*4 if physical else ('blocked',)*2)
    assert len(outcomes) == len(kinds)
    peer = peer_fixture()
    setup = copy.deepcopy(find(peer, 'server', 'SETUP'))
    descriptors, token = setup['ids'], setup['ids']['token']
    originals = descriptors['originalRootIds']
    rows = {role: [] for role in ('server', 'client1', 'client2')}

    def emit(role, event, data):
        row = copy.deepcopy(data)
        row.update(suite=A.SUITE, case=case, kind='mp', mode='toolkit', role=role, token=token)
        rows[role].append((event, row))
        return copy.deepcopy(row)

    def snapshot(phase, places, role, step=None):
        meta = {item['id']: item for item in phase['items']} if phase else {}
        visible = {key: where for key, where in places.items()
                   if role == 'server' or where == role or where.startswith('crate')}
        roots = ('client1', 'client2') if role == 'server' else (role,)
        row = dict(token=token, index=phase['index'] if phase else 0,
                   phaseToken=phase['phaseToken'] if phase else None,
                   visibility='both-roots' if role == 'server' else role,
                   items=[dict(id=key, ft=meta[key]['ft'], name=meta[key]['name'], customName=meta[key]['name'] is not None,
                               endpoint=where, count=1,
                               **({'key': meta[key]['key'], 'cat': meta[key]['cat']} if role == 'server'
                                  else {'rawCategory': meta[key]['cat']})) for key, where in visible.items()],
                   rootIds={who: originals[who] + [key for key, where in places.items() if where == who] for who in roots},
                   crates=[dict(slot=slot, id=desc['id'], capacity=100, effectiveCapacity=100,
                                weight=.05 * sum(where == f'crate{slot}' for where in places.values()),
                                itemIds=[key for key, where in places.items() if where == f'crate{slot}'])
                           for slot, desc in enumerate(descriptors['crates'], 1)])
        if phase:
            row.update(step=step, outputIds=[])
        if role != 'server':
            row['projection'] = 'native-identity'
            if phase and phase['affinityKind'] == 'category' and outcomes[phase['index']-1] == 'blocked' and step != 'initial':
                for item in row['items']:
                    if item['id'] == phase['replacementId']:
                        item['rawCategory'] = 'ToolWeapon'
        if step == 'personal-quick':
            row.update(affinityOutcome=phase['affinityOutcome'], oldDestination=phase['oldDestination'])
        return row

    def aggregate(places):
        stock = sorted(key for key, where in places.items() if where.startswith('crate'))
        meta = {item['id']: item for item in phase['items']}
        return dict(nativeAggregate=True, actualIds=stock, expectedIds=stock,
                    discoveredSlots=list(range(1, 13)), fresh=True,
                    items=[dict(id=key, ft=meta[key]['ft'], rawCategory=meta[key]['cat']) for key in stock])

    emit('server', 'SETUP', setup)
    baselines = {}
    for role in ('client1', 'client2'):
        baselines[role] = copy.deepcopy(find(peer, role, 'BASELINE'))
        baselines[role]['affinityOptions'] = dict(transferMethod=2, transferButtonLayout=1)
        emit(role, 'BASELINE', baselines[role])
        emit(role, 'SETUP', dict(ids=descriptors))
    for index, kind in enumerate(kinds, 1):
        outcome = outcomes[index-1]
        offset = 100 * index
        items = []
        for n in range(1, 16):
            ft = 'Base.Bandage' if n in (3, 14) else 'Base.Screwdriver' if n in (13, 15) else 'Base.HotdogPack' if n == 4 else 'Base.Nails'
            category = 'FirstAid' if n in (3, 14) else 'Tool' if n in (13, 15) else 'Food' if n == 4 else 'Material'
            name = 'Warehouse old bandage' if n == 3 else None
            items.append(dict(id=offset+n, ft=ft, name=name, key=f'{ft}:{name}:{category}', cat=category,
                              initialEndpoint=f'crate{n}' if n <= 12 else 'client2' if n == 13 else 'client1'))
        phase = dict(token=token, index=index, mode='clean', phaseToken=f'{token}:{index}', items=items, outputIds=[],
                     affinityKind=kind, oldCategory='FirstAid', newCategory='Tool', transferId=offset+1,
                     replacementSourceId=offset+3, replacementId=offset+13, oldCandidateId=offset+14,
                     newCandidateId=offset+15, craftInputId=offset+4, quickId=offset+5)
        if physical:
            phase['transferMethod'] = '1' if index <= 2 else '2'
        context = dict(index=index, paneMode='clean', phaseToken=phase['phaseToken'])
        places = {item['id']: item['initialEndpoint'] for item in items}
        template_index = (index-1) % 2 + 1
        readiness = copy.deepcopy(find(peer, 'server', 'SEED', index=template_index)['readiness'])
        emit('server', 'SEED', dict(context, phase=phase, readiness=readiness,
                                  snapshot=snapshot(phase, places, 'server', 'initial')))
        for role in ('client1', 'client2'):
            emit(role, 'MODE', dict(context, placement=find(peer, role, 'MODE', index=template_index)['placement']))
        replacement_aggregate = None
        for step in V.STEPS:
            current = dict(context, step=step)
            before = aggregate(places)
            if step == 'peer-replace':
                places[offset+3] = 'client2'
                places[offset+13] = 'crate3'
                replacement_aggregate = aggregate(places)
                if outcome in ('stale', 'blocked'):
                    replacement_aggregate['actualIds'] = [offset+3 if key == offset+13 else key
                                                         for key in replacement_aggregate['actualIds']]
                    meta = {item['id']: item for item in items}
                    replacement_aggregate['items'] = [dict(id=key, ft=meta[key]['ft'], rawCategory=meta[key]['cat'])
                                                      for key in replacement_aggregate['actualIds']]
                    replacement_aggregate['fresh'] = False
            elif step == 'personal-quick':
                before = copy.deepcopy(replacement_aggregate)
                if outcome != 'blocked':
                    places[offset+15 if outcome == 'fresh' else offset+14] = 'crate3' if outcome == 'fresh' else 'crate1'
                phase.update(affinityOutcome=outcome, oldDestination='crate1' if outcome == 'stale' else 'client1')
            authority = snapshot(phase, places, 'server', step)
            if step != 'initial':
                actor = 'client1' if step == 'personal-quick' else 'client2'
                emit('server', 'GO', dict(current, actor=actor))
                emit('server', 'AUTHORITY', dict(current, phase=phase, snapshot=authority))
                batch = ([] if outcome == 'blocked' else [(offset+15 if outcome == 'fresh' else offset+14, 'client1',
                          'crate3' if outcome == 'fresh' else 'crate1')]) if step == 'personal-quick' else [
                    (offset+3, 'crate3', 'client2'), (offset+13, 'client2', 'crate3')]
                records = [dict(type='ISInventoryTransferAction', step=step, id=key, source=source,
                                destination=destination, duration=-1, progressSamples=0, sourceMethodsUnchanged=True)
                           for key, source, destination in batch]
                extra = {}
                if step == 'personal-quick':
                    extra['quick'] = dict(dispatched=True, installedButton=True, callback='onTransferByNameClick' if kind == 'type' else 'onTransferByCategoryClick',
                                          kind=kind, source='client1', selectedId=offset+15 if outcome == 'fresh' else offset+14,
                                          oldCandidateId=offset+14, newCandidateId=offset+15,
                                          oldEligible=outcome != 'blocked', newEligible=outcome != 'blocked',
                                          targetOldAllowed=outcome != 'blocked', targetNewAllowed=outcome != 'blocked',
                                          physicalOldAllowed=True, physicalNewAllowed=True, physicalOldEligible=True, physicalNewEligible=True,
                                          oldFavorite=False, newFavorite=False, oldEquipped=False, newEquipped=False,
                                          oldHotbar=False, newHotbar=False, targetType='proximityInv', targetOnlyAcceptCategory='none', targetCapacity=0,
                                          physicalOldAffinity=0, physicalNewAffinity=0 if outcome == 'blocked' and kind == 'category' else 1,
                                          completionFrames=3, completionMs=500,
                                          physicalOld=0, physicalNew=1, oldCategory='FirstAid', newCategory='Tool', personalVisible=True,
                                          hiddenBefore=True, hiddenAfter=True, transferMethod='1', buttonLayout='2',
                                          before=copy.deepcopy(before), after=copy.deepcopy(before))
                    if outcome == 'blocked':
                        extra['quick'].pop('selectedId')
                    if physical:
                        extra['quick'].update(targetMode='physical', targetType='crate', targetCapacity=100,
                                              completionTicks=3,
                                              targetOnlyAcceptCategory=None, transferMethod=phase['transferMethod'],
                                              oldEligible=True, newEligible=True, targetOldAllowed=True, targetNewAllowed=True,
                                              physicalNewAffinity=1 if kind == 'type' else 0,
                                              physicalBefore=[dict(id=offset+13, ft='Base.Screwdriver', rawCategory='ToolWeapon')],
                                              physicalAfter=[dict(id=offset+13, ft='Base.Screwdriver',
                                                                  rawCategory='Tool' if outcome == 'fresh' else 'ToolWeapon')])
                emit(actor, 'ACTIONS', dict(current, records=records, **extra))
            observed_aggregate = copy.deepcopy(replacement_aggregate) if step == 'peer-replace' or (step == 'personal-quick' and outcome == 'blocked') else aggregate(places)
            for role in ('client1', 'client2'):
                hidden = dict(visible=False, rowsPending=True, countPending=True, tooltipsPending=True,
                              nativeBuilds=2, rawAggregateIds=observed_aggregate['actualIds'])
                emit(role, 'HIDDEN', dict(current, before=copy.deepcopy(hidden), after=hidden, samples=5, elapsedMs=600))
                proof = dict(kind=kind, personalVisible=True, lootHidden=True, naturalFrames=3, settledMs=500,
                             oldCategory='FirstAid', newCategory='Tool', forcedRefresh=False,
                             aggregate=observed_aggregate,
                             samples=[dict(frame=n, elapsedMs=t, actualIds=(replacement_aggregate or observed_aggregate)['actualIds'],
                                           expectedIds=(replacement_aggregate or observed_aggregate)['expectedIds'],
                                           fresh=(replacement_aggregate or observed_aggregate)['fresh'],
                                           items=copy.deepcopy((replacement_aggregate or observed_aggregate)['items']))
                                      for n, t in ((0, 0), (1, 150), (2, 300), (3, 500))])
                emit(role, 'SNAPSHOT', dict(current, native=snapshot(phase, places, role, step),
                                           authority=authority if step != 'initial' else None,
                                           affinity=proof, aggregateBefore={key: value for key, value in observed_aggregate.items() if key != 'items'}))
                emit('server', 'SEEN', dict(current, observer=role))
        cleanup = dict(context, removedIds=sorted(places), consumedIds=[], affinityOutcome=outcome,
                       oldDestination='crate1' if outcome == 'stale' else 'client1',
                       ownedRemaining=0, originalRootIds=originals, snapshot=snapshot(None, {}, 'server'),
                       cleanupJournal=dict(removedIds=sorted(places), removalCalls=15, noticeAttempts=15, recoveries=[]))
        released = emit('server', 'RELEASE', cleanup)
        for role in ('client1', 'client2'):
            emit(role, 'RELEASE', dict(context, step='personal-quick', absent=True, receipt=released,
                                      original=baselines[role]['original']))
    restored = emit('server', 'RESTORED', dict(index=len(kinds), removedCrates=12, ownedAbsent=True, ownedRemaining=0,
                                              originalRootIds=originals, crates=[dict(d, afterIndex=-1) for d in descriptors['crates']],
                                              snapshot=snapshot(None, {}, 'server')))
    emit('server', 'COMPLETE', dict(phases=len(kinds), restored=True))
    for role in ('client1', 'client2'):
        final = copy.deepcopy(find(peer, role, 'RESTORED'))
        final.update(authority=restored, affinityOptions={name: dict(expected=value, actual=value)
                                                        for name, value in baselines[role]['affinityOptions'].items()})
        emit(role, 'RESTORED', final)
        emit(role, 'COMPLETE', dict(phases=len(kinds), restored=True))
    # The shared template supplied setup/geometry/options, never effect receipts.
    return rows


class WarehousePhysicalAffinityTests(unittest.TestCase):
    """Synthetic physical receipts test validation, never establish a game pass."""

    def result(self, rows):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for role, values in rows.items():
                (root / f'{role}-launch.log').write_text('\n'.join(A.MARKER + event + ' ' + json.dumps(row) for event, row in values))
            try:
                return V.verify(root, 'physical-affinity'), None
            except (KeyError, TypeError, ValueError) as error:
                return None, str(error)

    def assert_rejected(self, mutation):
        rows = fixture(case='physical-affinity')
        mutation(rows)
        self.assertIsNotNone(self.result(rows)[1])

    def test_four_phase_fresh_effect_and_callback_preparation_brackets(self):
        result, issue = self.result(fixture(case='physical-affinity'))
        self.assertIsNone(issue)
        self.assertEqual(result['phases'], 4)
        self.assertEqual(result['outcomes'], ['fresh']*4)
        rows = fixture(case='physical-affinity')
        for index in range(1, 5):
            quick = find(rows, 'client1', 'ACTIONS', 'personal-quick', index=index)['quick']
            quick.pop('targetOnlyAcceptCategory')
            quick['physicalAfter'].append(dict(id=index*100+15, ft='Base.Screwdriver', rawCategory='Tool'))
        self.assertIsNone(self.result(rows)[1])

    def test_coherent_baseline_and_stale_effect_audited_before_final_failure(self):
        for outcomes in (('fresh', 'blocked', 'fresh', 'blocked'), ('stale', 'fresh', 'fresh', 'fresh')):
            with self.subTest(outcomes=outcomes):
                result, issue = self.result(fixture(outcomes, case='physical-affinity'))
                self.assertIsNone(result)
                self.assertIn('native personal quick affinity outcomes:', issue)

    def test_active_physical_callback_allows_explicit_hidden_destination_refresh(self):
        rows = fixture(case='physical-affinity')
        for role in ('client1', 'client2'):
            for index in range(1, 5):
                hidden = find(rows, role, 'HIDDEN', 'personal-quick', index=index)
                hidden['after'].update(nativeBuilds=hidden['before']['nativeBuilds']+1, rowsPending=False)
        self.assertIsNone(self.result(rows)[1])
        changes = [
            lambda r: find(r, 'client1', 'HIDDEN', 'personal-quick')['before'].update(visible=True),
            lambda r: find(r, 'client2', 'HIDDEN', 'personal-quick')['after'].update(visible=True),
            lambda r: find(r, 'client1', 'HIDDEN', 'personal-quick')['after'].update(nativeBuilds=1),
            lambda r: find(r, 'client1', 'HIDDEN', 'personal-quick')['after'].update(nativeBuilds='3'),
            lambda r: find(r, 'client1', 'HIDDEN', 'personal-quick')['after'].update(rowsPending='false'),
            lambda r: find(r, 'client1', 'HIDDEN', 'peer-replace')['after'].update(nativeBuilds=3),
            lambda r: find(r, 'client1', 'HIDDEN', 'initial')['after'].update(rowsPending=False),
        ]
        for change in changes:
            with self.subTest(change=change):
                self.assert_rejected(change)

    def test_binding_modes_options_eligibility_and_completion_guards(self):
        changes = [
            lambda q: q.pop('installedButton'), lambda q: q.update(installedButton=False),
            lambda q: q.pop('callback'), lambda q: q.update(callback='onTransferByCategoryClick'),
            lambda q: q.update(targetMode='aggregate'), lambda q: q.pop('targetMode'),
            lambda q: q.update(targetType='proximityInv'), lambda q: q.update(targetCapacity=0),
            lambda q: q.update(targetOnlyAcceptCategory='Tool'), lambda q: q.update(transferMethod='2'),
            lambda q: q.update(buttonLayout='1'), lambda q: q.update(oldEligible=False),
            lambda q: q.update(newEligible=False), lambda q: q.update(targetOldAllowed=False),
            lambda q: q.update(targetNewAllowed=False), lambda q: q.update(physicalNewEligible=False),
            lambda q: q.update(physicalOldAllowed=False), lambda q: q.update(oldFavorite=True),
            lambda q: q.update(newEquipped=True), lambda q: q.update(newHotbar=True),
            lambda q: q.update(completionFrames=2), lambda q: q.update(completionMs=499),
            lambda q: q.pop('completionTicks'), lambda q: q.update(completionTicks=2),
            lambda q: q.update(hiddenBefore=False), lambda q: q.update(personalVisible=False),
            lambda q: q.update(selectedId=114), lambda q: q.update(source='client2'),
        ]
        for change in changes:
            with self.subTest(change=change):
                self.assert_rejected(lambda r: change(find(r, 'client1', 'ACTIONS', 'personal-quick')['quick']))
        self.assert_rejected(lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick', index=3)['quick'].update(transferMethod='1'))

    def test_physical_stock_and_affinity_are_separate_from_aggregate(self):
        changes = [
            lambda q: q.pop('physicalBefore'), lambda q: q.pop('physicalAfter'),
            lambda q: q.update(physicalBefore=[]), lambda q: q.update(physicalAfter=[]),
            lambda q: q['physicalBefore'][0].update(id=999),
            lambda q: q['physicalAfter'][0].update(id=114),
            lambda q: q['physicalBefore'][0].update(ft='Base.Bandage'),
            lambda q: q['physicalAfter'][0].update(rawCategory=None),
            lambda q: q.update(physicalNewAffinity=0),
        ]
        for change in changes:
            with self.subTest(change=change):
                self.assert_rejected(lambda r: change(find(r, 'client1', 'ACTIONS', 'personal-quick')['quick']))
        rows = fixture(case='physical-affinity')
        quick = find(rows, 'client1', 'ACTIONS', 'personal-quick', index=2)['quick']
        for bracket in ('physicalBefore', 'physicalAfter'):
            quick[bracket][0]['rawCategory'] = 'ForeignCategory'
        self.assertIn('physical affinity bracket', self.result(rows)[1])
        # Aggregate stock may still be stale while the selected physical crate
        # supplies the callback's fresh admission evidence.
        rows = fixture(case='physical-affinity')
        quick = find(rows, 'client1', 'ACTIONS', 'personal-quick')['quick']
        for bracket in ('before', 'after'):
            aggregate = quick[bracket]
            aggregate['actualIds'] = [103 if key == 113 else key for key in aggregate['actualIds']]
            for item in aggregate['items']:
                if item['id'] == 113:
                    item.update(id=103, ft='Base.Bandage', rawCategory='FirstAid')
            aggregate['fresh'] = False
        self.assertIsNone(self.result(rows)[1])

    def test_exact_actions_identity_metadata_lifecycle_and_cleanup(self):
        changes = [
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['records'][0].update(id=114),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['records'][0].update(destination='crate1'),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['records'][0].update(sourceMethodsUnchanged=False),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['records'].append(dict(
                type='ISInventoryTransferAction', step='peer-replace', id=114, source='client1', destination='crate1',
                duration=-1, progressSamples=0, sourceMethodsUnchanged=True)),
            lambda r: find(r, 'server', 'AUTHORITY', 'personal-quick')['snapshot']['items'][0].update(cat='Changed'),
            lambda r: find(r, 'client1', 'SNAPSHOT', 'initial')['native']['items'][0].update(rawCategory=None),
            lambda r: find(r, 'client1', 'SNAPSHOT', 'peer-replace')['native']['items'][0].update(ft='Base.Pencil'),
            lambda r: find(r, 'client1', 'SNAPSHOT', 'personal-quick')['native']['rootIds']['client1'].append(999),
            lambda r: find(r, 'server', 'RELEASE', index=4)['removedIds'].pop(),
            lambda r: find(r, 'server', 'RELEASE')['cleanupJournal'].update(removalCalls=14),
            lambda r: find(r, 'server', 'RESTORED').update(removedCrates=11),
            lambda r: find(r, 'client2', 'RESTORED')['affinityOptions']['transferMethod'].update(actual=1),
            lambda r: find(r, 'server', 'COMPLETE').update(phases=2),
            lambda r: find(r, 'client2', 'COMPLETE').update(phases=2),
            lambda r: r['client2'].append(copy.deepcopy(r['client2'][-1])),
        ]
        for change in changes:
            with self.subTest(change=change):
                self.assert_rejected(change)

    def test_blocked_controls_keep_both_candidates_and_queue_no_actions(self):
        changes = [
            lambda q: q.update(selectedId=215), lambda q: q.update(targetNewAllowed=False),
            lambda q: q.update(newEligible=False), lambda q: q.update(completionMs=499),
            lambda q: q.pop('completionTicks'), lambda q: q.update(completionTicks=2),
            lambda q: q['physicalAfter'][0].update(rawCategory='Tool'),
        ]
        for change in changes:
            rows = fixture(('fresh', 'blocked', 'fresh', 'blocked'), case='physical-affinity')
            change(find(rows, 'client1', 'ACTIONS', 'personal-quick', index=2)['quick'])
            issue = self.result(rows)[1]
            self.assertIsNotNone(issue)
            self.assertNotIn('native personal quick affinity outcomes:', issue)
        rows = fixture(('fresh', 'blocked', 'fresh', 'blocked'), case='physical-affinity')
        find(rows, 'client1', 'ACTIONS', 'personal-quick', index=2)['records'].append(dict(
            type='ISWalkToTimedAction', step='personal-quick', duration=100, progressSamples=0, sourceMethodsUnchanged=True))
        self.assertNotIn('native personal quick affinity outcomes:', self.result(rows)[1])


class WarehouseAffinityTests(unittest.TestCase):
    def result(self, rows, case='hidden-affinity'):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for role, values in rows.items():
                (root / f'{role}-launch.log').write_text('\n'.join(A.MARKER + event + ' ' + json.dumps(row) for event, row in values))
            return A.verify(root, selection(case), {})

    def assert_rejected(self, mutation):
        rows = fixture()
        mutation(rows)
        self.assertTrue(self.result(rows)['issues'])

    def test_complete_synthetic_two_phase_baseline(self):
        result = self.result(fixture())
        self.assertEqual(result['issues'], [])
        self.assertEqual(result['evidence']['outcomes'], ['blocked', 'blocked'])
        self.assertTrue(all(row['status'] == 'passed' and row['case'] == 'hidden-affinity' for row in result['outcomes']))

    def test_wrong_candidate_stale_result_and_exact_endpoints(self):
        changes = [
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick'].update(selectedId=114),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['records'].append(dict(type='ISInventoryTransferAction', step='personal-quick', id=114,
                                                                                       source='client1', destination='crate1', duration=-1, progressSamples=0, sourceMethodsUnchanged=True)),
            lambda r: find(r, 'server', 'AUTHORITY', 'personal-quick')['phase'].update(affinityOutcome='stale', oldDestination='crate1'),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick'].update(source='client2'),
            lambda r: find(r, 'server', 'AUTHORITY', 'personal-quick')['phase'].update(oldDestination='crate1'),
            lambda r: find(r, 'client2', 'ACTIONS', 'peer-replace')['records'][0].update(id=999),
            lambda r: find(r, 'server', 'AUTHORITY', 'personal-quick')['snapshot']['items'][0].update(endpoint='crate9'),
        ]
        for change in changes:
            with self.subTest(change=change):
                self.assert_rejected(change)

    def test_complete_accepting_effect_is_audited_then_fails_current_contract(self):
        # This deliberately synthetic old-cache control includes the actual old
        # candidate at its declared owned crate and a complete cleanup cohort.
        for outcomes in (('stale', 'blocked'), ('blocked', 'fresh'), ('fresh', 'stale'), ('fresh', 'fresh')):
            with self.subTest(outcomes=outcomes):
                issues = self.result(fixture(outcomes))['issues']
                self.assertEqual(len(issues), 1)
                self.assertIn('native personal quick affinity outcomes:', issues[0])

    def test_required_visibility_options_binding_and_settle(self):
        changes = [
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick'].update(installedButton=False),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick'].pop('callback'),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick'].update(callback='onTransferByCategoryClick'),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick'].update(transferMethod='2'),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick'].update(buttonLayout='1'),
            lambda r: find(r, 'client1', 'SNAPSHOT', 'peer-replace')['affinity'].update(forcedRefresh=True),
            lambda r: find(r, 'client1', 'SNAPSHOT', 'peer-replace')['affinity'].update(naturalFrames=2),
            lambda r: find(r, 'client1', 'SNAPSHOT', 'peer-replace')['affinity'].update(settledMs=499),
            lambda r: find(r, 'client2', 'SNAPSHOT', 'personal-quick')['affinity'].update(personalVisible=False),
            lambda r: find(r, 'client1', 'HIDDEN', 'peer-replace')['after'].update(nativeBuilds=3),
            lambda r: find(r, 'client1', 'RESTORED')['affinityOptions']['transferMethod'].update(actual=1),
        ]
        for change in changes:
            with self.subTest(change=change):
                self.assert_rejected(change)

    def test_original_foreign_cleanup_and_metadata_guards(self):
        changes = [
            lambda r: find(r, 'client1', 'SNAPSHOT', 'personal-quick')['native']['rootIds']['client1'].remove(77),
            lambda r: find(r, 'client1', 'SNAPSHOT', 'personal-quick')['native']['rootIds']['client1'].append(999),
            lambda r: find(r, 'server', 'AUTHORITY', 'peer-replace')['snapshot']['items'][0].update(cat='Changed'),
            lambda r: find(r, 'server', 'RELEASE')['removedIds'].pop(),
            lambda r: find(r, 'server', 'RELEASE')['cleanupJournal'].update(recoveries=[dict(id=101)]),
            lambda r: find(r, 'client2', 'RELEASE')['original'].update(payload=False),
            lambda r: find(r, 'server', 'RESTORED')['crates'][0].update(afterIndex=1),
        ]
        for change in changes:
            with self.subTest(change=change):
                self.assert_rejected(change)

    def test_missing_peer_phase_replay_and_envelope(self):
        changes = [
            lambda r: r.pop('client2'),
            lambda r: r['server'].__setitem__(slice(None), [(e, v) for e, v in r['server'] if v.get('index') != 2]),
            lambda r: r['client1'].append(copy.deepcopy(r['client1'][-1])),
            lambda r: find(r, 'server', 'SEEN').update(observer='client2'),
            lambda r: find(r, 'server', 'SEED')['readiness'].pop('client2'),
            lambda r: find(r, 'client2', 'SNAPSHOT', 'peer-replace').update(role='client1'),
        ]
        for change in changes:
            with self.subTest(change=change):
                self.assert_rejected(change)

    def test_raw_aggregate_observations_and_samples_are_required(self):
        changes = [
            lambda r: find(r, 'client1', 'SNAPSHOT', 'peer-replace')['affinity'].pop('aggregate'),
            lambda r: find(r, 'client2', 'SNAPSHOT', 'personal-quick')['affinity'].pop('samples'),
            lambda r: find(r, 'client1', 'SNAPSHOT', 'peer-replace')['affinity'].update(samples=[]),
            lambda r: find(r, 'client1', 'SNAPSHOT', 'peer-replace')['affinity']['samples'][0].update(actualIds=[999]),
            lambda r: find(r, 'client1', 'SNAPSHOT', 'personal-quick')['affinity']['samples'][0].update(expectedIds=[]),
            lambda r: find(r, 'client1', 'SNAPSHOT', 'peer-replace')['affinity']['aggregate']['discoveredSlots'].remove(3),
            lambda r: find(r, 'client1', 'SNAPSHOT', 'peer-replace').pop('aggregateBefore'),
            lambda r: find(r, 'client1', 'SNAPSHOT', 'peer-replace')['aggregateBefore'].update(fresh=True),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick'].pop('before'),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick']['after'].update(expectedIds=[]),
            lambda r: find(r, 'client1', 'SNAPSHOT', 'peer-replace')['affinity']['aggregate'].pop('items'),
            lambda r: find(r, 'client1', 'SNAPSHOT', 'peer-replace')['affinity']['samples'][0].pop('items'),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick']['before']['items'].pop(),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick']['before']['items'][0].update(ft='Base.Pencil'),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick']['after']['items'][0].update(rawCategory=None),
        ]
        for change in changes:
            with self.subTest(change=change):
                self.assert_rejected(change)

    def test_client_native_identity_does_not_claim_prepared_semantics(self):
        rows = fixture()
        for role in ('client1', 'client2'):
            for event, row in rows[role]:
                if event == 'SNAPSHOT':
                    for item in row['native']['items']:
                        item['rawCategory'] = 'UnpreparedClientCategory'
        self.assertEqual(self.result(rows)['issues'], [], 'read-only raw category drift was treated as prepared metadata')
        changes = [
            lambda r: find(r, 'client1', 'SNAPSHOT', 'initial')['native'].update(projection='semantic-metadata'),
            lambda r: find(r, 'client1', 'SNAPSHOT', 'initial')['native']['items'][0].update(key='invented-model-key'),
            lambda r: find(r, 'client1', 'SNAPSHOT', 'initial')['native']['items'][0].update(cat='invented-model-category'),
            lambda r: find(r, 'client1', 'SNAPSHOT', 'initial')['native']['items'][2].update(customName=False),
            lambda r: find(r, 'client1', 'SNAPSHOT', 'initial')['native']['items'][2].update(name='Foreign custom label'),
            lambda r: find(r, 'client2', 'SNAPSHOT', 'initial')['native']['items'][0].update(rawCategory=True),
        ]
        for change in changes:
            with self.subTest(change=change):
                self.assert_rejected(change)

    def test_raw_category_affinity_matches_one_callback_bracket(self):
        rows = fixture(('blocked', 'fresh'))
        quick = find(rows, 'client1', 'ACTIONS', 'personal-quick', index=2)['quick']
        # A legitimate consumer can refresh the aggregate inside the callback.
        # The bracket records permit that source-freshened result without an
        # unsupported claim about the exact internal admission read instant.
        quick['before']['actualIds'] = [203 if key == 213 else key for key in quick['before']['actualIds']]
        for item in quick['before']['items']:
            if item['id'] == 213:
                item.update(id=203, ft='Base.Bandage', rawCategory='FirstAid')
        quick['before']['fresh'] = False
        issues = self.result(rows)['issues']
        self.assertEqual(len(issues), 1)
        self.assertIn('native personal quick affinity outcomes:', issues[0])

        def no_match(rows):
            quick = find(rows, 'client1', 'ACTIONS', 'personal-quick', index=2)['quick']
            for bracket in ('before', 'after'):
                for item in quick[bracket]['items']:
                    item['rawCategory'] = 'UnpreparedNativeCategory'

        def both_candidates_match(rows):
            quick = find(rows, 'client1', 'ACTIONS', 'personal-quick', index=2)['quick']
            for bracket in ('before', 'after'):
                quick[bracket]['items'][0]['rawCategory'] = 'FirstAid'

        for change in (no_match, both_candidates_match,
                       lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick', index=2)['quick'].update(oldEligible=False),
                       lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick', index=2)['quick'].update(newEligible=False)):
            with self.subTest(change=change):
                changed = fixture(('blocked', 'fresh')); change(changed)
                issues = self.result(changed)['issues']
                self.assertTrue(issues)
                self.assertNotIn('native personal quick affinity outcomes:', issues[0], 'unsupported final outcome masked a missing raw admission guard')

    def test_blocked_callback_requires_eligibility_controls_and_completion(self):
        changes = [
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick'].pop('targetOldAllowed'),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick'].pop('physicalNewEligible'),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick'].update(targetNewAllowed=True),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick'].update(physicalOldAllowed=False),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick'].update(oldFavorite=True),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick'].update(newEquipped=True),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick'].update(oldHotbar=True),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick'].update(targetOnlyAcceptCategory=None),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick'].update(targetCapacity=100),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick'].update(dispatched=False),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick'].update(completionFrames=2),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick'].update(completionMs=499),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['quick'].update(physicalNewAffinity=-1),
            lambda r: find(r, 'client1', 'ACTIONS', 'personal-quick')['records'].append(dict(
                type='ISWalkToTimedAction', step='personal-quick', duration=100, progressSamples=0, sourceMethodsUnchanged=True)),
        ]
        for change in changes:
            with self.subTest(change=change):
                self.assert_rejected(change)
        rows = fixture()
        for index in (1, 2):
            quick = find(rows, 'client1', 'ACTIONS', 'personal-quick', index=index)['quick']
            quick['selectedId'] = None
            # An ineligible virtual target may contain either affinity key,
            # neither key, or both; there is still no admissible transfer.
            for bracket in ('before', 'after'):
                for item in quick[bracket]['items']:
                    item['rawCategory'] = 'Other'
        self.assertEqual(self.result(rows)['issues'], [])

    def test_original_options_envelopes_and_categories_are_anchored(self):
        def replace_declared_category(rows):
            def visit(value):
                if isinstance(value, dict):
                    for key, child in value.items():
                        if key == 'newCategory':
                            value[key] = 'InventedCategory'
                        else:
                            visit(child)
                elif isinstance(value, list):
                    for child in value:
                        visit(child)
            for values in rows.values():
                for _, row in values:
                    visit(row)

        def omit_original_root(rows):
            # Keep all repeated original proofs in agreement. Their omitted ID
            # must still be detected against the independent setup descriptors.
            find(rows, 'client1', 'BASELINE')['original']['ids'] = []
            for event, row in rows['client1']:
                if event in ('RELEASE', 'RESTORED'):
                    row['original']['ids'] = []
                    if event == 'RESTORED':
                        row['actual']['ids'] = []

        changes = [
            lambda r: find(r, 'server', 'GO', 'peer-replace').update(phaseToken='foreign'),
            lambda r: find(r, 'client2', 'SNAPSHOT', 'peer-replace').update(phaseToken='foreign'),
            lambda r: find(r, 'client1', 'RESTORED')['affinityOptions']['transferMethod'].update(expected=None, actual=None),
            lambda r: find(r, 'client1', 'RESTORED')['affinityOptions']['transferMethod'].update(expected=1, actual=1),
            lambda r: find(r, 'client1', 'BASELINE')['affinityOptions'].update(transferMethod=None),
            lambda r: find(r, 'client1', 'BASELINE')['original'].pop('ids'),
            replace_declared_category,
            omit_original_root,
        ]
        for change in changes:
            with self.subTest(change=change):
                self.assert_rejected(change)

    def test_adapter_selection_complete_staging_and_fingerprint_inputs(self):
        self.assertIs(adapters.get(A.SUITE), A)
        self.assertIn('hidden-affinity', [case['id'] for case in A.definitions()[A.SUITE]['cases']])
        A.validate(selection())
        for patch in ({'clients': True}, {'kind': 'sp'}, {'cases': ['hidden-affinity', 'peer-edits']},
                      {'options': {'mp_host': True, 'seed_run': 'old-world'}}, {'mods': A.MODS[:-1]}):
            with self.subTest(patch=patch), self.assertRaises(ValueError):
                A.validate(dict(selection(), **patch))
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            runtime = {'roles': {role: {'cache': str(root / role)} for role in ('server', 'client1', 'client2')}}
            A.stage(ROOT, root, None, None, selection(), {}, runtime)
            for role in runtime['roles']:
                lua = root / role / 'mods/ActionQueueTest/42/media/lua'
                self.assertTrue((lua / 'shared/QueueFixtureItemCleanup.lua').is_file())
                self.assertTrue((lua / 'client/ZZStartup.lua').is_file())
            sources = A.sources(ROOT, selection())
            self.assertIn(Path(V.__file__), sources)
            self.assertIn(ROOT / 'tests/native_queue/warehouse-workload/client/WarehouseWorkloadAffinity.lua', sources)
        complete = dict(suite=A.SUITE, case='hidden-affinity', kind='mp', mode='toolkit', role='client1', phases=2, restored=True)
        text = A.MARKER + 'COMPLETE ' + json.dumps(complete)
        self.assertTrue(A.complete(selection(), 'client1', text))
        complete['case'] = 'peer-edits'
        self.assertFalse(A.complete(selection(), 'client1', A.MARKER + 'COMPLETE ' + json.dumps(complete)))


if __name__ == '__main__':
    unittest.main()
