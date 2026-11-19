"""Fail-closed selection and absent/invalid live razor evidence checks."""
import copy
from pathlib import Path
import sys
import shutil
import subprocess
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
               items={name: dict(id=index, type=kind) for index, (name, kind) in enumerate(v.item_types(case).items(), 73)})
    ids['items']['tail'].update(initial=8, total=10)
    ids['baseline'] = dict(case=case, appearance=dict(beard='LongScruffy'), primary=74, secondary=False,
        items=[dict(id=42, type='Base.Bag_Military', container='root'),
               *[dict(id=item['id'], type=item['type'], container=42 if name == 'razor' else 'root') for name, item in ids['items'].items()]],
        origin=dict(id=42, type='Base.Bag_Military', container='root', worn=True, sourceCount=1), worn=[dict(id=42, location='Back')],
        tail=dict(id=76, type='Base.BookCarpentry1', pages=8, characterPages=8, total=10))
    ids['baseline'].update(v.seed_hands(ids))
    if case == 'cut-hair-scissors':
        ids.update(initialHair='Fabian', targetHair='Bald')
        ids['baseline']['appearance'].update(hair='Fabian', nonAttached=False)
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


def native_equip_observation(role, kind, *, two=False):
    # A focused receipt sub-schema; never a fabricated native gameplay pass.
    row = dict(role=role, type='ISEquipWeaponAction', actionRef=role + '-equip', nativeRef='native-' + role,
        operationRef='episode', startedAt=10, equipPrimary=True, equipTwoHands=two,
        events=[dict(boundary=boundary, phase=phase, at=11 + index, nativeRef='native-' + role, succeeded=True)
                for index, (boundary, phase) in enumerate((('begin', 'perform'), ('finish', 'perform'),
                     ('begin', 'complete'), ('finish', 'complete'))) if kind == 'sp' or phase == 'perform'], ack=[])
    if kind == 'mp':
        row['ack'] = [dict(state='completed', at=14, kind=row['type'], transaction=7,
            token='01234567-89ab-cdef-0123-456789abcdef', nativeRef=row['nativeRef'], operationRef='episode',
            **{key: True for key in ('nativeSame', 'actorSame', 'queueSame', 'rootSame', 'itemSame', 'operationSame')})]
    return row


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
        self.assertEqual(a.CASES, ('restore-success', 'empty-primary', 'new-primary-intent', 'cancel-active',
                                  'full-origin', 'unavailable-origin', 'keep-return', 'trim-scissors', 'cut-hair-scissors',
                                  'two-handed-axe', 'two-handed-axe-new-primary-intent',
                                  'one-handed-axe', 'one-handed-axe-new-primary-intent',
                                  'mandatory-both-stone-wheel', 'mandatory-both-wood-axe-new-primary-intent'))
        for kind in ('sp', 'mp'):
            for cases in (list(a.CASES[:2]), *([case] for case in a.CASES), list(a.CASES[2:])):
                value = selection(kind); value['cases'] = cases
                a.validate(value)
        for cases in ([], ['cancel-active', 'cancel-active'], ['foreign'], ['keep-return', 'full-origin']):
            value = selection(); value['cases'] = cases
            with self.assertRaises(ValueError):
                a.validate(value)

    def test_editor_off_reuses_ordinary_restore_cases_in_sp_and_host(self):
        for kind in ('sp', 'mp'):
            value = selection(kind)
            value['cases'] = ['restore-success']
            value['options']['queue_editor_enabled'] = False
            for cases in (['restore-success'], ['empty-primary'], ['trim-scissors'], ['cut-hair-scissors'],
                          ['restore-success', 'empty-primary', 'trim-scissors', 'cut-hair-scissors']):
                value['cases'] = cases
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

    def test_scissors_cases_keep_exact_borrowed_return_and_independent_appearance(self):
        for case in ('trim-scissors', 'cut-hair-scissors'):
            ids, _, _ = control_observation(case)
            ids['items']['razor']['type'] = 'Base.Scissors'
            ids['baseline']['items'][1]['type'] = 'Base.Scissors'
            ids['baseline']['appearance'].update(hair='Fabian', nonAttached=False)
            if case == 'cut-hair-scissors':
                ids.update(initialHair='Fabian', targetHair='Bald')
            final = v.expected(ids, True)
            self.assertEqual(final['primary'], ids['items']['previous']['id'])
            self.assertEqual(final['items'], ids['baseline']['items'])
            self.assertEqual(final['origin'], ids['baseline']['origin'])
            self.assertEqual(final['tail']['pages'], ids['items']['tail']['total'])
            appearance = copy.deepcopy(ids['baseline']['appearance'])
            appearance['hair' if case == 'cut-hair-scissors' else 'beard'] = 'Bald' if case == 'cut-hair-scissors' else 'Moustache'
            self.assertEqual(final['appearance'], appearance)
            self.assertEqual(v.item_types(case)['razor'], 'Base.Scissors')
            for role in ('pickup', 'returned'):
                pickup = role == 'pickup'
                physical = dict(case=case, role=role, at=10, authority=True, itemId=73, itemType='Base.Scissors',
                    source=42 if pickup else 'root', destination='root' if pickup else 42,
                    sourceCount=0, destinationCount=1, canonical=True, bagCanonical=True)
                self.assertEqual(v.physical_transfer_errors(physical, ids, role, True), [])
                for field, value in (('itemType', 'Base.Razor'), ('itemId', 99), ('bagCanonical', False)):
                    changed = dict(physical, **{field: value})
                    self.assertTrue(v.physical_transfer_errors(changed, ids, role, True))
            receipts = [dict(case=case, role=role, at=10 + index, authority=True, itemId=73, itemType='Base.Scissors',
                source=42 if role == 'pickup' else 'root', destination='root' if role == 'pickup' else 42,
                sourceCount=0, destinationCount=1, canonical=True, bagCanonical=True)
                for index, role in enumerate(('pickup', 'returned'))]
            self.assertEqual(v.authority_transfer_errors(dict(transfers=receipts), ids), [])
            self.assertTrue(v.authority_transfer_errors(dict(transfers=receipts[:1]), ids))

    def test_prepared_scissors_exact_type_and_actual_hair_change_are_required(self):
        for case in ('trim-scissors', 'cut-hair-scissors'):
            ids, _, _ = control_observation(case)
            baseline = ids['baseline']; baseline['male'] = True
            for item in baseline['items']:
                item.update(canonical=True, condition=10, favorite=True, count=1)
            target = dict(x=10, y=10, z=0)
            ids['placement'] = target
            ids['placementProof'] = dict(mode='replica', target=target,
                actual=dict(x=10.5, y=10.5, z=0, square=target, currentSquare=target),
                teleports=0, stableMs=500, quietMs=0, elapsedMs=500, centered=True, centers=0)
            v.validate_prepared(ids, selection())
            for mutate in (lambda i: i['items']['razor'].update(type='Base.Razor'),
                           lambda i: i['baseline']['items'][1].update(container='root')):
                changed = copy.deepcopy(ids); mutate(changed)
                with self.assertRaises(ValueError):
                    v.validate_prepared(changed, selection())
            if case == 'cut-hair-scissors':
                for mutate in (lambda i: i.update(initialHair='Bald'), lambda i: i.update(targetHair='Fabian'),
                               lambda i: i['baseline']['appearance'].update(nonAttached='PonyTail')):
                    changed = copy.deepcopy(ids); mutate(changed)
                    with self.assertRaises(ValueError):
                        v.validate_prepared(changed, selection())

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_native_fixture_expected_scissors_return_and_distinct_grooming_effects(self):
        # Test the shared fixture state model, not a synthetic native pass receipt.
        script = r'''
package.preload.QueueEnergyPlacement=function()return {}end
local F=assert(loadfile(arg[1]))()
for _,case in ipairs({'trim-scissors','cut-hair-scissors'})do
 local ids={case=case,initialBeard='LongScruffy',targetBeard='Moustache',initialHair='Fabian',targetHair='Bald',
  items={razor={id=73},previous={id=74},tail={total=10}},
  baseline={appearance={beard='LongScruffy',hair='Fabian',nonAttached=false},primary=74,
   tail={pages=8,characterPages=8},origin={sourceCount=1},items={{id=73,container=42}}}}
 local final=F.expected(ids)
 assert(F.returnedCase(case)and final.primary==74 and final.items[1].container==42 and final.origin.sourceCount==1)
 assert(final.tail.pages==10 and final.tail.characterPages==10)
 assert(final.appearance.beard==(case=='trim-scissors'and'Moustache'or'LongScruffy'))
 assert(final.appearance.hair==(case=='cut-hair-scissors'and'Bald'or'Fabian'))
 assert(ids.baseline.appearance.beard=='LongScruffy'and ids.baseline.appearance.hair=='Fabian')
end
'''
        result = subprocess.run(['luajit', '-', str(PROJECT / 'tests/native_queue/razor-restoration/shared/QueueRazorRestoration.lua')],
                                input=script, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_empty_primary_exact_secondary_and_borrowed_return_state(self):
        ids, _, _ = control_observation('empty-primary')
        baseline = ids['baseline']; baseline['male'] = True
        for item in baseline['items']:
            item.update(canonical=True, condition=10, favorite=True, count=1)
        target = dict(x=10, y=10, z=0)
        ids['placement'] = target
        ids['placementProof'] = dict(mode='replica', target=target,
            actual=dict(x=10.5, y=10.5, z=0, square=target, currentSquare=target),
            teleports=0, stableMs=500, quietMs=0, elapsedMs=500, centered=True, centers=0)
        v.validate_prepared(ids, selection())
        final = v.expected(ids, True)
        self.assertIs(final['primary'], False)
        self.assertEqual(final['secondary'], ids['items']['previous']['id'])
        self.assertEqual(final['items'][1]['container'], ids['bag']['id'])
        self.assertEqual(final['tail']['pages'], ids['items']['tail']['total'])
        self.assertEqual(v.borrowed_snapshot(ids)['secondary'], final['secondary'])
        for mutate in (lambda i: i['baseline'].update(primary=i['items']['previous']['id']),
                       lambda i: i['baseline'].update(primary=0),
                       lambda i: i['baseline'].update(secondary=False),
                       lambda i: i['baseline'].update(secondary=i['items']['replacement']['id'])):
            changed = copy.deepcopy(ids); mutate(changed)
            with self.assertRaises(ValueError): v.validate_prepared(changed, selection())

    def test_empty_primary_requires_completed_native_unequip_before_exact_return(self):
        # Focused receipt sub-schema checks, never a fabricated native pass.
        ids, _, _ = control_observation('empty-primary')
        for kind in ('sp', 'mp'):
            restore = dict(role='restore', type='ISUnequipAction', actionRef='unequip', nativeRef='native',
                operationRef='episode', startedAt=10,
                events=[dict(boundary=boundary, phase=phase, at=11 + index, nativeRef='native', succeeded=True)
                        for index, (boundary, phase) in enumerate((('begin', 'perform'), ('finish', 'perform'),
                             ('begin', 'complete'), ('finish', 'complete'))) if kind == 'sp' or phase == 'perform'], ack=[])
            if kind == 'mp':
                restore['ack'] = [dict(state='completed', at=14, kind='ISUnequipAction', transaction=7,
                    token='01234567-89ab-cdef-0123-456789abcdef', nativeRef='native', operationRef='episode',
                    **{key: True for key in ('nativeSame', 'actorSame', 'queueSame', 'rootSame', 'itemSame', 'operationSame')})]
            returned = dict(actionRef='return', admittedAt=15, startedAt=16)
            roles = dict(restore=[restore], returned=[returned])
            snapshot = v.expected(ids, kind == 'sp'); snapshot.pop('authority')
            snapshot['origin']['sourceCount'] = 0; snapshot['items'][1]['container'] = 'root'
            snapshot['tail'].update(pages=8, characterPages=8)
            ev = dict(restoreBoundary=dict(at=15, actionRef='unequip', nativeRef='native', returnRef='return', snapshot=snapshot))
            self.assertEqual(v.lifecycle_errors(restore, kind), [])
            self.assertEqual(v.restore_boundary_errors(ev, roles, ids, kind), [])
            for mutate in (lambda e: e.pop('restoreBoundary'),
                           lambda e: e['restoreBoundary'].update(actionRef='foreign'),
                           lambda e: e['restoreBoundary'].update(nativeRef='foreign'),
                           lambda e: e['restoreBoundary'].update(returnRef='foreign'),
                           lambda e: e['restoreBoundary'].update(at=17),
                           lambda e: e['restoreBoundary']['snapshot'].update(primary=73),
                           lambda e: e['restoreBoundary']['snapshot'].update(primary=0),
                           lambda e: e['restoreBoundary']['snapshot'].update(secondary=False),
                           lambda e: e['restoreBoundary']['snapshot']['items'][1].update(container=42),
                           lambda e: e['restoreBoundary']['snapshot']['tail'].update(pages=9)):
                changed = copy.deepcopy(ev); mutate(changed)
                self.assertTrue(v.restore_boundary_errors(changed, roles, ids, kind))
            changed = copy.deepcopy(roles)
            terminal = changed['restore'][0]['events'][-1] if kind == 'sp' else changed['restore'][0]['ack'][0]
            terminal['at'] = 17
            self.assertTrue(v.restore_boundary_errors(ev, changed, ids, kind))
            changed = copy.deepcopy(roles)
            changed['restore'][0]['events' if kind == 'sp' else 'ack'] = []
            self.assertTrue(v.restore_boundary_errors(ev, changed, ids, kind))
            if kind == 'mp':
                for mutate in (lambda a: a['ack'][0].update(state='rejected'),
                               lambda a: a['ack'][0].update(kind='ISEquipWeaponAction'),
                               lambda a: a['ack'][0].update(itemSame=False)):
                    changed = copy.deepcopy(restore); mutate(changed)
                    self.assertTrue(v.lifecycle_errors(changed, kind))
        old_ids, _, _ = control_observation('restore-success')
        self.assertTrue(v.restore_boundary_errors(ev, roles, old_ids, 'sp'))

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_native_fixture_empty_primary_keeps_exact_secondary_and_tool_origin(self):
        script = r'''
package.preload.QueueEnergyPlacement=function()return {}end
local F=assert(loadfile(arg[1]))()
local ids={case='empty-primary',initialBeard='LongScruffy',targetBeard='Moustache',
 items={razor={id=73},previous={id=74},tail={total=10}},
 baseline={appearance={beard='LongScruffy'},primary=false,secondary=74,
  tail={pages=8,characterPages=8},origin={sourceCount=1},items={{id=73,container=42}}}}
local final=F.expected(ids)
assert(F.returnedCase(ids.case)and final.primary==false and final.secondary==74)
assert(final.items[1].container==42 and final.origin.sourceCount==1)
assert(final.tail.pages==10 and final.tail.characterPages==10 and final.appearance.beard=='Moustache')
assert(ids.baseline.primary==false and ids.baseline.secondary==74 and ids.baseline.tail.pages==8)
'''
        result = subprocess.run(['luajit', '-', str(PROJECT / 'tests/native_queue/razor-restoration/shared/QueueRazorRestoration.lua')],
                                input=script, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_haircut_host_completion_uses_native_cut_hair_ack(self):
        action = dict(role='trim', type='ISCutHair', nativeRef='native', operationRef='episode',
            events=[dict(boundary=boundary, phase='perform', at=10, nativeRef='native', succeeded=True)
                    for boundary in ('begin', 'finish')],
            ack=[dict(state='completed', kind='ISCutHair', transaction=7,
                token='01234567-89ab-cdef-0123-456789abcdef', nativeRef='native', operationRef='episode',
                **{key: True for key in ('nativeSame', 'actorSame', 'queueSame', 'rootSame', 'itemSame', 'operationSame')})])
        self.assertEqual(v.grooming('cut-hair-scissors'), ('ISCharacterScreen.onCutHair', 'ISCutHair', 'Bald'))
        self.assertEqual(v.lifecycle_errors(action, 'mp'), [])
        for mutate in (lambda a: a['ack'][0].update(kind='ISTrimBeard'),
                       lambda a: a['ack'][0].update(state='canceled'),
                       lambda a: a['ack'][0].update(itemSame=False)):
            changed = copy.deepcopy(action); mutate(changed)
            self.assertTrue(v.lifecycle_errors(changed, 'mp'))

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

    def test_equipment_cases_batch_in_sp_and_menu_host(self):
        cases = [case for case in a.CASES if case in v.EQUIPMENT_CASES]
        for kind in ('sp', 'mp'):
            value = selection(kind); value['cases'] = cases
            a.validate(value)
        definitions = {row['id']: row for row in a.definitions()['razor-restoration']['cases']}
        for case in cases:
            self.assertEqual(definitions[case]['kinds'], ['sp', 'mp'])

    def test_equipment_seed_and_exact_hands_follow_native_effects(self):
        for case in v.EQUIPMENT_CASES:
            ids, _, _ = control_observation(case)
            baseline = ids['baseline']; baseline['male'] = True
            for item in baseline['items']:
                item.update(canonical=True, condition=10, favorite=True, count=1)
            target = dict(x=10, y=10, z=0)
            ids['placement'] = target
            ids['placementProof'] = dict(mode='replica', target=target,
                actual=dict(x=10.5, y=10.5, z=0, square=target, currentSquare=target),
                teleports=0, stableMs=500, quietMs=0, elapsedMs=500, centered=True, centers=0)
            v.validate_prepared(ids, selection())
            expected_type = {'mandatory-both-stone-wheel': 'Base.StoneWheelSmall',
                             'mandatory-both-wood-axe-new-primary-intent': 'Base.WoodAxe'}.get(case, 'Base.Axe')
            self.assertEqual(ids['items']['previous']['type'], expected_type)
            self.assertEqual(baseline['primary'], ids['items']['previous']['id'])
            held_secondary = ids['items']['secondary']['id'] if case in v.ONE_HANDED_AXE_CASES else baseline['primary']
            borrowed_secondary = held_secondary if case in v.ONE_HANDED_AXE_CASES else False
            self.assertEqual(baseline['secondary'], held_secondary)
            borrowed = v.borrowed_snapshot(ids)
            self.assertEqual(borrowed['primary'], ids['items']['razor']['id'])
            self.assertEqual(borrowed['secondary'], borrowed_secondary)
            final = v.expected(ids, True)
            if case in v.INTENT_CASES:
                self.assertEqual(final['primary'], ids['items']['replacement']['id'])
                self.assertEqual(final['secondary'], borrowed_secondary)
                self.assertEqual(final['items'][1]['container'], 'root')
                self.assertEqual(final['origin']['sourceCount'], 0)
            else:
                self.assertEqual(final['primary'], ids['items']['previous']['id'])
                self.assertEqual(final['secondary'], held_secondary)
                self.assertEqual(final['items'][1]['container'], ids['bag']['id'])
                self.assertEqual(final['origin']['sourceCount'], 1)
            self.assertEqual(final['tail']['pages'], ids['items']['tail']['total'])
            self.assertEqual(final['tail']['characterPages'], ids['items']['tail']['total'])
            if case in v.ONE_HANDED_AXE_CASES:
                self.assertEqual(ids['items']['secondary']['type'], 'Base.Pen')
            for mutate in (lambda i: i['baseline'].update(secondary=False),
                           lambda i: i['baseline'].update(secondary=i['items']['replacement']['id']),
                           lambda i: i['items']['previous'].update(type='Base.Hammer')):
                changed = copy.deepcopy(ids); mutate(changed)
                with self.assertRaises(ValueError): v.validate_prepared(changed, selection())

    def test_equipment_native_restore_completes_exact_hands_before_return(self):
        # Receipt sub-schema checks do not constitute a native gameplay pass.
        for case, kind in ((case, kind) for case in ('two-handed-axe', 'one-handed-axe', 'mandatory-both-stone-wheel') for kind in ('sp', 'mp')):
            ids, _, _ = control_observation(case)
            two = case in v.SHARED_HAND_CASES
            restore = native_equip_observation('restore', kind, two=two)
            roles = dict(restore=[restore], returned=[dict(actionRef='return', admittedAt=15, startedAt=16)])
            snapshot = v.expected(ids, kind == 'sp'); snapshot.pop('authority')
            snapshot['origin']['sourceCount'] = 0; snapshot['items'][1]['container'] = 'root'
            snapshot['tail'].update(pages=8, characterPages=8)
            ev = dict(restoreBoundary=dict(at=15, actionRef=restore['actionRef'], nativeRef=restore['nativeRef'], returnRef='return', snapshot=snapshot))
            self.assertEqual(v.lifecycle_errors(restore, kind), [])
            self.assertEqual(v.restore_boundary_errors(ev, roles, ids, kind), [])
            for slot in ('primary', 'secondary'):
                for invalid in (False, ids['items']['replacement']['id'], ids['items']['razor']['id']):
                    changed = copy.deepcopy(ev); changed['restoreBoundary']['snapshot'][slot] = invalid
                    self.assertTrue(v.restore_boundary_errors(changed, roles, ids, kind))
            for mutate in (lambda r: r['restore'][0].update(equipTwoHands=not two),
                           lambda r: r['restore'][0].update(equipPrimary=False),
                           lambda r: r['restore'][0].update(**{'events' if kind == 'sp' else 'ack': []}),
                           lambda r: r['returned'][0].update(admittedAt=13)):
                changed = copy.deepcopy(roles); mutate(changed)
                self.assertTrue(v.restore_boundary_errors(ev, changed, ids, kind))

    def test_equipment_new_intent_keeps_unpaid_exact_razor_debt(self):
        for case in ('two-handed-axe-new-primary-intent', 'one-handed-axe-new-primary-intent', 'mandatory-both-wood-axe-new-primary-intent'):
            ids, _, _ = control_observation(case)
            roles = dict(trim=[dict(actionRef='trim', nativeRef='native-trim', operationRef='borrow', startedAt=1)],
                         tail=[dict(operationRef='independent', startedAt=10)],
                         explicitEquip=[dict(actionRef='explicit', operationRef='new-intent', startedAt=20)])
            ev = dict(initialRevision=4, debts=[dict(itemId=73, itemType='Base.Razor', state='blocked', reason='cleanup-unresolved')],
                      intent=dict(at=5, before=4, after=5, trimDelta=.4, trimRef='trim', trimNative='native-trim',
                          explicitActionRef='explicit', explicitUnallocated=True, snapshot=v.borrowed_snapshot(ids)))
            self.assertEqual(v.intent_errors(ev, roles, ids), [])
            for mutate in (lambda e: e['intent']['snapshot'].update(secondary=74),
                           lambda e: e['intent']['snapshot'].update(primary=75),
                           lambda e: e['intent'].update(after=4),
                           lambda e: e['intent'].update(explicitUnallocated=False),
                           lambda e: e['intent'].update(trimDelta=0),
                           lambda e: e.update(debts=[]),
                           lambda e: e['debts'][0].update(itemId=75),
                           lambda e: e['debts'][0].update(reason='admission')):
                changed = copy.deepcopy(ev); mutate(changed)
                self.assertTrue(v.intent_errors(changed, roles, ids))
            for operation in ('borrow', 'independent'):
                changed = copy.deepcopy(roles); changed['explicitEquip'][0]['operationRef'] = operation
                self.assertTrue(v.intent_errors(ev, changed, ids))

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_native_fixture_expected_equipment_hands_and_superseding_intent(self):
        source = r"""
package.preload.QueueEnergyPlacement=function()return {}end
local F=dofile(arg[1])
for _,case in ipairs({'two-handed-axe','two-handed-axe-new-primary-intent','one-handed-axe','one-handed-axe-new-primary-intent','mandatory-both-stone-wheel','mandatory-both-wood-axe-new-primary-intent'})do
 local secondary=F.oneHandedCase(case)and 77 or 74
 local ids={case=case,initialBeard='LongScruffy',targetBeard='Moustache',
  items={razor={id=73},previous={id=74},replacement={id=75},tail={id=76,initial=8,total=10}},
  baseline={appearance={beard='LongScruffy'},primary=74,secondary=secondary,
   items={{id=73,container=42}},origin={sourceCount=1},tail={pages=8,characterPages=8}}}
 local final=F.expected(ids)
 local wantedSecondary=secondary
 if F.sharedHandCase(case)and F.intentCase(case)then wantedSecondary=false end
 assert(F.equipmentCase(case)and final.appearance.beard=='Moustache')
 if F.intentCase(case)then
  assert(not F.returnedCase(case)and final.primary==75 and final.secondary==wantedSecondary)
  assert(final.items[1].container=='root'and final.origin.sourceCount==0)
 else
  assert(F.returnedCase(case)and final.primary==74 and final.secondary==wantedSecondary)
  assert(final.items[1].container==42 and final.origin.sourceCount==1)
 end
 assert(final.tail.pages==10 and final.tail.characterPages==10)
 assert(ids.baseline.primary==74 and ids.baseline.secondary==secondary and ids.baseline.tail.pages==8)
end
"""
        result = subprocess.run(['luajit', '-', str(PROJECT / 'tests/native_queue/razor-restoration/shared/QueueRazorRestoration.lua')],
                                input=source, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_new_equipment_native_mode_requires_explicit_flag(self):
        for case in v.ONE_HANDED_AXE_CASES | v.MANDATORY_BOTH_CASES:
            ids, _, _ = control_observation(case)
            for role in ('preparationEquip', 'restore', 'explicitEquip'):
                two = role == 'restore' and case in v.SHARED_HAND_CASES
                action = native_equip_observation(role, 'mp', two=two)
                self.assertEqual(v.equip_mode_errors(action, ids), [])
                for mutate in (lambda a: a.pop('equipTwoHands'), lambda a: a.update(equipTwoHands=not two),
                               lambda a: a.update(equipPrimary=False)):
                    changed = copy.deepcopy(action); mutate(changed)
                    self.assertTrue(v.equip_mode_errors(changed, ids))
        # Previously sealed two-handed preparation had no serialized false flag.
        ids, _, _ = control_observation('two-handed-axe')
        old = native_equip_observation('preparationEquip', 'mp'); old.pop('equipTwoHands')
        self.assertEqual(v.equip_mode_errors(old, ids), [])
        self.assertEqual(v.preparation_boundary_errors({}, {}, ids, 'mp'), [])

    def test_equipment_grooming_progress_keeps_exact_hands_and_host_receipt(self):
        for case, kind in ((case, kind) for case in v.PREPARATION_BOUNDARY_CASES for kind in ('sp', 'mp')):
            ids, _, _ = control_observation(case)
            prepared = native_equip_observation('preparationEquip', kind)
            trim = dict(actionRef='trim', nativeRef='native-trim', admittedAt=15, startedAt=16)
            roles = dict(preparationEquip=[prepared], trim=[trim])
            ev = dict(preparationBoundary=dict(at=17, actionRef=prepared['actionRef'], nativeRef=prepared['nativeRef'],
                groomingRef='trim', groomingNative='native-trim', groomingDelta=.4, snapshot=v.borrowed_snapshot(ids)))
            self.assertEqual(v.preparation_boundary_errors(ev, roles, ids, kind), [])
            for mutate in (lambda e: e.pop('preparationBoundary'),
                           lambda e: e['preparationBoundary']['snapshot'].update(secondary=False if case in v.ONE_HANDED_AXE_CASES else 75),
                           lambda e: e['preparationBoundary']['snapshot'].update(secondary=74),
                           lambda e: e['preparationBoundary'].update(groomingDelta=0),
                           lambda e: e['preparationBoundary'].update(groomingNative='foreign'),
                           lambda e: e['preparationBoundary'].update(nativeRef='foreign')):
                changed = copy.deepcopy(ev); mutate(changed)
                self.assertTrue(v.preparation_boundary_errors(changed, roles, ids, kind))
            changed = copy.deepcopy(roles)
            changed['preparationEquip'][0]['events' if kind == 'sp' else 'ack'] = []
            self.assertTrue(v.preparation_boundary_errors(ev, changed, ids, kind))
            if kind == 'mp':
                late = copy.deepcopy(roles); late['preparationEquip'][0]['ack'][0]['at'] = 18
                self.assertEqual(v.preparation_boundary_errors(ev, late, ids, kind), [])
                for mutate in (lambda a: a['ack'][0].update(state='rejected'),
                               lambda a: a['ack'][0].update(nativeSame=False),
                               lambda a: a['ack'][0].update(token='foreign')):
                    changed = copy.deepcopy(roles); mutate(changed['preparationEquip'][0])
                    self.assertTrue(v.preparation_boundary_errors(ev, changed, ids, kind))

    def test_mandatory_hand_seed_requires_native_type_and_no_force_drop(self):
        for case, previous_type, weapon in (('mandatory-both-stone-wheel', 'Base.StoneWheelSmall', False),
                                           ('mandatory-both-wood-axe-new-primary-intent', 'Base.WoodAxe', True)):
            ids, _, _ = control_observation(case)
            seed = dict(id=ids['items']['previous']['id'], secondary=ids['items']['previous']['id'], type=previous_type,
                        requiresBoth=True, handWeapon=weapon, supportsTwo=weapon, ordinary=True, forceDropHeavy=False)
            self.assertEqual(v.hand_seed_errors(seed, ids), [])
            for mutate in (lambda s: s.update(forceDropHeavy=True), lambda s: s.update(forceDropHeavy=0),
                           lambda s: s.pop('forceDropHeavy'), lambda s: s.update(requiresBoth=False),
                           lambda s: s.update(handWeapon=not weapon), lambda s: s.update(supportsTwo=not weapon),
                           lambda s: s.update(secondary=ids['items']['replacement']['id'])):
                changed = copy.deepcopy(seed); mutate(changed)
                self.assertTrue(v.hand_seed_errors(changed, ids))

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
