"""Magazine native receipts: exact input/output units, immutable callbacks and pending edits."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zlib

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / 'tools'))
from queue_checks.adapters import magazine_unload as a
from tests.test_queue_wring_clothing import placement_proof


def ammo(identifier, kind=a.AMMO, uses=1, path=None):
    path = [] if path is None else path
    return dict(id=identifier, type=kind, uses=uses, class_='ComboItem', factoryCount=5 if kind == a.AMMO else 6,
                root=not path, path=path)


def ammo_record(identifier, kind=a.AMMO, uses=1, path=None):
    value = ammo(identifier, kind, uses, path); value['class'] = value.pop('class_'); return value


def gun_spec(identifier, name):
    return dict(id=identifier, type='Base.Shotgun', loaded=1, maxAmmo=5, ammoType=a.OTHER, factoryCount=1, condition=10,
                magazineType=False, containsClip=False, haveChamber=True, roundChambered=name == 'gun-a',
                spentRoundChambered=False, spentRoundCount=0, **{'class': 'HandWeapon'})


def totals(value):
    value['looseUnits'] = sum(item['uses'] for item in value['ammo'])
    value['loadedUnits'] = sum(item['loaded'] for item in value['magazines'].values()) + sum(item['loaded'] for item in value['firearms'].values())
    value['totalUnits'] = value['looseUnits'] + value['loadedUnits']
    value['units'] = {a.AMMO: sum(item['loaded'] for item in value['magazines'].values()), a.OTHER: sum(item['loaded'] for item in value['firearms'].values())}
    for item in value['ammo']: value['units'][item['type']] += item['uses']


def evidence(kind='mp', mode='toolkit', case='direct', lifecycle_mode=None):
    editing = mode == 'toolkit'; serialized = (mode if lifecycle_mode is None else lifecycle_mode) == 'toolkit'; origin = dict(x=11, y=20, z=0)
    specs = {name: dict(id=10 + index, type='Base.9mmClip', loaded=a.LOADS[name], maxAmmo=15, ammoType=a.AMMO,
                       factoryCount=1, condition=10, **{'class': 'ComboItem'}) for index, name in enumerate(a.NAMES)}
    guns = {name: gun_spec(40 + index, name) for index, name in enumerate(('gun-a', 'gun-b'))}
    initial = [ammo_record(20), ammo_record(21), ammo_record(22, a.OTHER)]
    hands = dict(primary=False, secondary=False)
    ids = dict(case=case, mode=mode, origin=origin, placementProof=placement_proof(origin, 'replica' if kind == 'mp' else 'local'),
               magazines=specs, firearms=guns, hands=hands, seedAmmo=[20, 21], otherAmmo=22, initialAmmo=initial, ammoUnit='currentUses')
    def snapshot(phase):
        magazines = {}
        for name, spec in specs.items():
            loaded = spec['loaded']
            if phase == 'final' and name != 'unrelated' and not (editing and name == 'cancelled'): loaded = 0
            if phase == 'pending' and name == 'front': loaded = 4
            magazines[name] = dict(spec, present=True, actorCount=1, rootCount=1, equipped=False, favorite=False, loaded=loaded)
        decrement = sum(a.LOADS[name] - item['loaded'] for name, item in magazines.items())
        firearms = {name: dict(spec, loaded=0 if phase == 'final' else 1, present=True, actorCount=1, rootCount=1, favorite=False, jobDelta=0) for name, spec in guns.items()}
        ammo = copy.deepcopy(initial) + [ammo_record(100 + index) for index in range(decrement)]
        if phase == 'final': ammo += [ammo_record(200 + index, a.OTHER) for index in range(2)]
        value = dict(case=case, magazines=magazines, firearms=firearms, hands=copy.deepcopy(hands), ammo=ammo)
        totals(value); return value
    final = snapshot('final'); pending = snapshot('pending'); commands = []; preparations = []
    gun_names = ['gun-a', 'gun-b', 'gun-repeat-a', 'gun-repeat-b']
    names = ['front', 'repeat-first', 'repeat-second', 'target', 'cancelled', 'tail', *gun_names, 'gun-tail']
    order = ['front', 'repeat-first', 'repeat-second'] + (['tail', 'target'] if editing else ['target', 'cancelled', 'tail']) + [stage for name in gun_names for stage in ('equip-' + name, name)] + ['gun-tail']
    for name in names:
        gun = name in gun_names; repeat = name.startswith('repeat-') or name.startswith('gun-repeat-')
        source = name.replace('gun-repeat-', 'gun-') if gun else 'front' if repeat else name
        spec = guns[source] if gun else specs[source]; cancelled = editing and name == 'cancelled'
        command = dict(name=name, type='ISUnloadBulletsFromFirearm' if gun else 'ISUnloadBulletsFromMagazine', item=spec['id'],
                       producer='native ISInventoryPaneContextMenu.onUnloadBulletsFromFirearm' if gun and case == 'direct' else a.PRODUCERS[case],
                       duration=-1, constructorAmmo=1 if gun else 4 if repeat else a.LOADS[source], constructorStartUnset=True,
                       callbacksUntouched=True, ownedBulkGuard=case == 'bulk', started=not cancelled and (gun or not repeat),
                       progress=not cancelled and not repeat and not gun, partialCounts=[] if cancelled or repeat or gun else [a.LOADS[source] - 1], lifecycle=[])
        if cancelled: command['cancelled'] = True
        elif command['started']: command['startedAt'] = 100 + order.index(name) * 100
        commands.append(command)
        if gun:
            preparations.append(dict(name='equip-' + name, target=name, preparation=True, type='ISEquipWeaponAction', item=spec['id'],
                duration=50, primary=True, twoHands=True, constructorHands=copy.deepcopy(hands), callbacksUntouched=True, ownedBulkGuard=case == 'bulk', lifecycle=[]))
    serial = 0; previous_gun = False
    for name in order:
        command = next(item for item in commands + preparations if item['name'] == name)
        equip = command.get('preparation', False); target = command['target'] if equip else name
        gun = target in gun_names; repeat = not equip and (target.startswith('repeat-') or target.startswith('gun-repeat-'))
        source = target.replace('gun-repeat-', 'gun-') if gun else 'front' if repeat else target
        observed = copy.deepcopy(initial) + [ammo_record(100 + index) for index in range((10 if editing else 14) if gun else 5)] if repeat else False
        if gun and repeat: observed += [ammo_record(200 + index, a.OTHER) for index in range(2)]
        for event, phase in [('admission', False), ('begin', 'perform'), ('finish', 'perform')] + ([('begin', 'complete'), ('finish', 'complete')] if kind == 'sp' else []):
            serial += 1; loaded = (0 if target.startswith('gun-repeat-') else 1) if equip else 0 if repeat or event != 'admission' else 1 if gun else a.LOADS[source]
            firearm = False
            if gun:
                held = previous_gun if equip and event == 'admission' else guns[source]['id']
                firearm = dict(guns[source], loaded=loaded, hands=dict(primary=held, secondary=held),
                    jobDelta='nan' if repeat and event == 'begin' and phase == 'perform' else 0)
            command['lifecycle'].append(dict(sequence=serial, event=event, phase=phase, succeeded=event == 'finish',
                nativeEpisode=False if event == 'admission' else order.index(name) + 1,
                nativeClass=False if event == 'admission' else 'LuaTimedActionNew', loaded=loaded, firearm=firearm,
                startAmmo=False if event == 'admission' or equip else 0 if repeat else 1 if gun else a.LOADS[source], ammo=copy.deepcopy(observed)))
        if gun: previous_gun = guns[source]['id']
    # Disabled controls nest admission in equip.perform; enabled Lifecycle drains it
    # after complete (SP) or client perform/native removal (Host).
    for index, target in enumerate(gun_names):
        old = False if index == 0 else guns['gun-b' if target.endswith('a') else 'gun-a']['id']
        equip = next(item for item in preparations if item['target'] == target)
        unload = next(item for item in commands if item['name'] == target)
        for event in equip['lifecycle']:
            held = guns[target.replace('gun-repeat-', 'gun-')]['id'] if event['event'] == 'finish' and event['phase'] == 'complete' else old
            event['firearm']['hands'] = dict(primary=held, secondary=held)
        held = guns[target.replace('gun-repeat-', 'gun-')]['id'] if serialized and kind == 'sp' else old
        unload['lifecycle'][0]['firearm']['hands'] = dict(primary=held, secondary=held)
    serial = 0
    for name in order:
        if name in gun_names: continue
        command = next(item for item in commands + preparations if item['name'] == name)
        for event in command['lifecycle']:
            serial += 1; event['sequence'] = serial
            if command.get('preparation') and event['event'] == 'begin' and event['phase'] == 'perform' and not serialized:
                unload = next(item for item in commands if item['name'] == command['target'])
                serial += 1; unload['lifecycle'][0]['sequence'] = serial
        if command.get('preparation'):
            unload = next(item for item in commands if item['name'] == command['target'])
            if serialized:
                serial += 1; unload['lifecycle'][0]['sequence'] = serial
            for event in unload['lifecycle'][1:]:
                serial += 1; event['sequence'] = serial
    calls = ([dict(names=[name], entries=1, queued=1) for name in names] if case == 'direct' else
             [dict(names=[name], entries=1, queued=1) for name in names[:3]] + [dict(names=['target', 'cancelled', 'tail'], entries=3, queued=3), dict(names=gun_names[:2], entries=2, queued=2), dict(names=gun_names[2:], entries=2, queued=2), dict(names=['gun-tail'], entries=1, queued=1)])
    row = dict(ids=copy.deepcopy(ids), input=snapshot('input'), client=copy.deepcopy(final), server=copy.deepcopy(final),
               clientPlacement=placement_proof(origin), commands=commands, preparations=preparations, producerCalls=calls, pendingOrder=order,
               pendingBefore=copy.deepcopy(pending), pendingAfter=copy.deepcopy(pending), status='passed', queueIdle=True, settleMilliseconds=1000,
               edit=dict(cancelled=editing, reordered=editing, untouched=True))
    return row, dict(kind=kind, mode=mode), ids, final


class MagazineUnloadTests(unittest.TestCase):
    def test_grouped_full_pack_and_sp_menu_host_modes(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                selection = dict(suite='magazine-unload', cases=list(a.CASES), kind=kind, mode=mode, clients=1,
                                 languages=['EN'], mods=a.MODS, options={'mp_host': True} if kind == 'mp' else {})
                a.validate(selection)
                for case in a.CASES: self.assertEqual([], a.check_case(*evidence(kind, mode, case)))
        selection['options'] = {}
        with self.assertRaises(ValueError): a.validate(selection)
        selection['options'] = {'mp_host': True, 'world_template': 'old-world'}
        with self.assertRaises(ValueError): a.validate(selection)

    def test_missing_or_forged_magazine_consumption_is_rejected(self):
        for name in a.NAMES:
            result = evidence(); result[0]['client']['magazines'][name]['loaded'] += 1
            self.assertTrue(a.check_case(*result), name)
        for field, value in [('id', 999), ('type', 'Base.M14Clip'), ('class', 'HandWeapon'), ('rootCount', 0),
                             ('actorCount', 2), ('equipped', True), ('favorite', True), ('present', False)]:
            result = evidence(); result[0]['client']['magazines']['target'][field] = value
            self.assertTrue(a.check_case(*result), field)

    def test_round_outputs_must_be_new_unique_exact_root_actionable_units(self):
        for change in ('missing', 'duplicate', 'alias', 'wrong-type', 'wrong-units', 'nested', 'replayed'):
            result = evidence(); value = result[0]['client']
            if change == 'missing': value['ammo'].pop()
            if change == 'duplicate': value['ammo'].append(copy.deepcopy(value['ammo'][-1]))
            if change == 'alias': value['ammo'][-1]['id'] = result[2]['magazines']['target']['id']
            if change == 'wrong-type': value['ammo'][-1].update(type=a.AMMO, factoryCount=5)
            if change == 'wrong-units': value['ammo'][-1]['uses'] = 5
            if change == 'nested': value['ammo'][-1].update(root=False, path=[99])
            if change == 'replayed': value['ammo'].append(ammo_record(900))
            totals(value); self.assertTrue(a.check_case(*result), change)

    def test_initial_ammo_and_unrelated_inputs_cannot_be_lost_or_credited(self):
        for identifier in (20, 21, 22):
            result = evidence(); value = result[0]['client']; value['ammo'] = [item for item in value['ammo'] if item['id'] != identifier]
            totals(value); self.assertTrue(a.check_case(*result))
        result = evidence(); result[0]['client']['magazines']['unrelated']['loaded'] = 0
        self.assertTrue(a.check_case(*result))
        result = evidence(); result[0]['client']['ammo'][0]['uses'] = 2
        self.assertTrue(a.check_case(*result))
        result = evidence(); result[0]['client']['looseUnits'] *= 5
        self.assertTrue(a.check_case(*result), 'factory count must never inflate physical round credit')

    def test_preexisting_actionable_uses_are_preserved_without_factory_count_multiplication(self):
        result = evidence(); extra = ammo_record(90, uses=3, path=[99])
        result[2]['initialAmmo'].append(copy.deepcopy(extra)); result[0]['ids'] = copy.deepcopy(result[2])
        for phase in ('input', 'client', 'server', 'pendingBefore', 'pendingAfter'):
            result[0][phase]['ammo'].append(copy.deepcopy(extra)); result[0][phase]['ammo'].sort(key=lambda item: item['id']); totals(result[0][phase])
        for command in result[0]['commands']:
            for event in command['lifecycle']:
                if type(event['ammo']) is list:
                    event['ammo'].append(copy.deepcopy(extra)); event['ammo'].sort(key=lambda item: item['id'])
        result[3].update(copy.deepcopy(result[0]['server']))
        self.assertEqual([], a.check_case(*result))

    def test_real_partial_progress_callbacks_and_duration_are_required(self):
        changes = [('duration', 1), ('callbacksUntouched', False), ('ownedBulkGuard', True), ('started', False),
                   ('progress', False), ('constructorAmmo', 0), ('partialCounts', []), ('partialCounts', [5]),
                   ('partialCounts', [3, 4]), ('partialCounts', [3, 3]), ('type', 'ISUnloadBulletsFromFirearm')]
        for field, value in changes:
            result = evidence(); result[0]['commands'][0][field] = value
            self.assertTrue(a.check_case(*result), field)
        result = evidence(case='bulk'); result[0]['commands'][0]['ownedBulkGuard'] = False
        self.assertTrue(a.check_case(*result))

    def test_pending_cancel_reorder_and_tail_must_have_real_effects(self):
        for change in ('cancel-started', 'cancel-empty', 'unchanged-order', 'missing-tail', 'fake-edit', 'physical-edit', 'public-bulk-call'):
            result = evidence(case='bulk'); row = result[0]
            if change == 'cancel-started': next(item for item in row['commands'] if item['name'] == 'cancelled')['started'] = True
            if change == 'cancel-empty': row['client']['magazines']['cancelled']['loaded'] = 0
            if change == 'unchanged-order': row['commands'][3]['lifecycle'], row['commands'][5]['lifecycle'] = row['commands'][5]['lifecycle'], row['commands'][3]['lifecycle']
            if change == 'missing-tail': row['commands'].pop()
            if change == 'fake-edit': row['edit']['reordered'] = False
            if change == 'physical-edit': row['pendingAfter']['magazines']['target']['loaded'] = 0
            if change == 'public-bulk-call': row['producerCalls'][3]['entries'] = 1
            self.assertTrue(a.check_case(*result), change)

    def test_repeat_empty_starts_require_native_witness_not_final_zero_or_polling(self):
        for change in ('constructor-zero', 'constructor-drift', 'constructor-started', 'wrong-input', 'admission-positive',
                       'start-positive', 'no-allocation', 'episode-reused', 'no-perform', 'failed-perform', 'missing-sp-complete',
                       'duplicate-sequence', 'missing-admission', 'repeat-output', 'forged-output', 'invented-partial', 'wrong-source'):
            result = evidence(kind='sp', case='bulk'); row = result[0]; command = row['commands'][1]
            if change == 'constructor-zero': command['constructorAmmo'] = 0
            if change == 'constructor-drift': command['constructorAmmo'] = 3
            if change == 'constructor-started': command['constructorStartUnset'] = False
            if change == 'wrong-input': command['item'] = row['ids']['magazines']['target']['id']
            if change == 'admission-positive': command['lifecycle'][0]['loaded'] = 1
            if change == 'start-positive': command['lifecycle'][1]['startAmmo'] = 1
            if change == 'no-allocation': command['lifecycle'][1]['nativeEpisode'] = False
            if change == 'episode-reused':
                for event in command['lifecycle'][1:]: event['nativeEpisode'] = 1
            if change == 'no-perform': command['lifecycle'] = [event for event in command['lifecycle'] if event['phase'] != 'perform']
            if change == 'failed-perform': command['lifecycle'][2]['succeeded'] = False
            if change == 'missing-sp-complete': command['lifecycle'] = command['lifecycle'][:3]
            if change == 'duplicate-sequence': command['lifecycle'][1]['sequence'] = command['lifecycle'][0]['sequence']
            if change == 'missing-admission': command['lifecycle'].pop(0)
            if change == 'repeat-output': command['lifecycle'][2]['ammo'].append(ammo_record(900))
            if change == 'forged-output': command['lifecycle'][0]['ammo'][-1]['id'] = 900
            if change == 'invented-partial': command['partialCounts'] = [1]
            if change == 'wrong-source': command['producer'] = a.PRODUCERS['direct']
            self.assertTrue(a.check_case(*result), change)
        result = evidence()
        for command in result[0]['commands'][1:3]: command.update(started=True, startedAt=100)
        self.assertEqual([], a.check_case(*result), 'instant repeats may finish between polls and share timestamps')
        result = evidence(); result[0]['commands'][1]['lifecycle'] += copy.deepcopy(result[0]['commands'][1]['lifecycle'][1:])
        self.assertTrue(a.check_case(*result), 'repeat callback replay must fail')

    def test_integral_empty_starts_preserve_native_hands_chamber_spent_delta_and_tail(self):
        changes = ('positive-start', 'missing-perform', 'callback', 'owned-guard', 'wrong-gun', 'live-chamber-lost', 'spent-created',
                   'inserted-magazine', 'held-wrong-gun', 'held-before-own-equip', 'missing-own-equip', 'equip-hands',
                   'final-delta-nan', 'perform-not-reset', 'infinite-delta', 'invented-fraction', 'output-replay', 'tail-missing', 'queue-forged')
        for change in changes:
            result = evidence(case='bulk', kind='sp'); row = result[0]
            command = next(item for item in row['commands'] if item['name'] == 'gun-repeat-a')
            event = command['lifecycle'][1]
            if change == 'positive-start': event['startAmmo'] = 1
            if change == 'missing-perform': command['lifecycle'] = [item for item in command['lifecycle'] if item['phase'] != 'perform']
            if change == 'callback': command['callbacksUntouched'] = False
            if change == 'owned-guard': command['ownedBulkGuard'] = False
            if change == 'wrong-gun': command['item'] = row['ids']['firearms']['gun-b']['id']
            if change == 'live-chamber-lost': row['client']['firearms']['gun-a']['roundChambered'] = False
            if change == 'spent-created': event['firearm']['spentRoundCount'] = 1
            if change == 'inserted-magazine': event['firearm']['containsClip'] = True
            if change == 'held-wrong-gun': event['firearm']['hands']['primary'] = row['ids']['firearms']['gun-b']['id']
            if change == 'held-before-own-equip': row['preparations'][2]['lifecycle'][0]['firearm']['hands'] = dict(primary=40, secondary=40)
            if change == 'missing-own-equip': row['preparations'].pop(2)
            if change == 'equip-hands': row['preparations'][2]['twoHands'] = False
            if change == 'final-delta-nan': row['client']['firearms']['gun-a']['jobDelta'] = 'nan'
            if change == 'perform-not-reset': command['lifecycle'][2]['firearm']['jobDelta'] = 'nan'
            if change == 'infinite-delta': event['firearm']['jobDelta'] = 'positive-infinity'
            if change == 'invented-fraction': event['firearm']['jobDelta'] = 0.5
            if change == 'output-replay': command['lifecycle'][2]['ammo'].append(ammo_record(900, a.OTHER))
            if change == 'tail-missing': row['commands'].pop()
            if change == 'queue-forged': row['pendingOrder'][-1] = 'gun-repeat-b'
            self.assertTrue(a.check_case(*result), change)
        result = evidence()
        self.assertEqual([], a.check_case(*result), 'vanilla temporary NaN must remain observable and reset natively')

    def test_native_sp_equip_perform_precedes_complete_and_nested_unload_admission(self):
        result = evidence(kind='sp', mode='native'); row = result[0]
        equip = row['preparations'][0]; unload = next(item for item in row['commands'] if item['name'] == 'gun-a')
        self.assertEqual([('admission', False), ('begin', 'perform'), ('finish', 'perform'),
                          ('begin', 'complete'), ('finish', 'complete')],
                         [(event['event'], event['phase']) for event in equip['lifecycle']])
        self.assertLess(equip['lifecycle'][1]['sequence'], unload['lifecycle'][0]['sequence'])
        self.assertLess(unload['lifecycle'][0]['sequence'], equip['lifecycle'][2]['sequence'])
        self.assertEqual(dict(primary=False, secondary=False), unload['lifecycle'][0]['firearm']['hands'])
        self.assertEqual([], a.check_case(*result))
        for change in ('premature-handoff', 'complete-missing-handoff', 'wrong-previous', 'not-nested', 'unload-wrong-hands'):
            result = evidence(kind='sp', mode='native'); row = result[0]; equip = row['preparations'][0]
            unload = next(item for item in row['commands'] if item['name'] == 'gun-a')
            if change == 'premature-handoff': equip['lifecycle'][2]['firearm']['hands'] = dict(primary=40, secondary=40)
            if change == 'complete-missing-handoff': equip['lifecycle'][-1]['firearm']['hands'] = dict(primary=False, secondary=False)
            if change == 'wrong-previous': unload['lifecycle'][0]['firearm']['hands'] = dict(primary=41, secondary=41)
            if change == 'not-nested': unload['lifecycle'][0]['sequence'] = equip['lifecycle'][-1]['sequence'] + 1
            if change == 'unload-wrong-hands': unload['lifecycle'][1]['firearm']['hands'] = dict(primary=False, secondary=False)
            self.assertTrue(a.check_case(*result), change)
        result = evidence(kind='mp', mode='native'); equip = result[0]['preparations'][0]
        equip['lifecycle'][2]['firearm']['hands'] = dict(primary=40, secondary=40)
        # The hand packet can arrive during client perform; the nested admission must not observe a reversion.
        next(item for item in result[0]['commands'] if item['name'] == 'gun-a')['lifecycle'][0]['firearm']['hands'] = dict(primary=40, secondary=40)
        self.assertEqual([], a.check_case(*result))
        equip['lifecycle'][2]['firearm']['hands'] = dict(primary=False, secondary=False)
        self.assertTrue(a.check_case(*result), 'Host hand state may not revert after observed handoff')

    def test_mode_specific_completion_barrier_rejects_cross_mode_admission_profiles(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                for case in a.CASES:
                    result = evidence(kind=kind, mode=mode, case=case)
                    self.assertEqual([], a.check_case(*result), (kind, mode, case))
                    wrong = 'toolkit' if mode == 'native' else 'native'
                    self.assertTrue(a.check_case(*evidence(kind=kind, mode=mode, case=case, lifecycle_mode=wrong)), (kind, mode, case))
        for change in ('admission-before-complete', 'admission-still-old', 'premature-equip', 'late-equip', 'effect-still-old'):
            result = evidence(kind='sp', mode='toolkit'); row = result[0]; equip = row['preparations'][0]
            unload = next(item for item in row['commands'] if item['name'] == 'gun-a')
            if change == 'admission-before-complete':
                equip['lifecycle'][-1]['sequence'], unload['lifecycle'][0]['sequence'] = unload['lifecycle'][0]['sequence'], equip['lifecycle'][-1]['sequence']
            if change == 'admission-still-old': unload['lifecycle'][0]['firearm']['hands'] = dict(primary=False, secondary=False)
            if change == 'premature-equip': equip['lifecycle'][2]['firearm']['hands'] = dict(primary=40, secondary=40)
            if change == 'late-equip': equip['lifecycle'][-1]['firearm']['hands'] = dict(primary=False, secondary=False)
            if change == 'effect-still-old': unload['lifecycle'][1]['firearm']['hands'] = dict(primary=False, secondary=False)
            self.assertTrue(a.check_case(*result), change)

    def test_host_hand_packet_timing_preserves_real_effect_handoff_without_local_complete(self):
        for mode in ('native', 'toolkit'):
            for arrival in ('perform-begin', 'perform-finish', 'admission', 'effect'):
                result = evidence(kind='mp', mode=mode); row = result[0]; equip = row['preparations'][0]
                unload = next(item for item in row['commands'] if item['name'] == 'gun-a')
                entries = sorted(equip['lifecycle'] + unload['lifecycle'], key=lambda event: event['sequence'])
                if arrival == 'perform-begin': start = equip['lifecycle'][1]['sequence']
                elif arrival == 'perform-finish': start = equip['lifecycle'][2]['sequence']
                elif arrival == 'admission': start = unload['lifecycle'][0]['sequence']
                else: start = unload['lifecycle'][1]['sequence']
                for event in entries:
                    event['firearm']['hands'] = dict(primary=40, secondary=40) if event['sequence'] >= start else dict(primary=False, secondary=False)
                self.assertFalse(any(event['phase'] == 'complete' for event in equip['lifecycle']))
                self.assertEqual([], a.check_case(*result), (mode, arrival))
                unload['lifecycle'][1]['firearm']['hands'] = dict(primary=False, secondary=False)
                self.assertTrue(a.check_case(*result), (mode, arrival, 'real effect cannot precede handoff'))
        result = evidence(kind='mp', mode='toolkit'); row = result[0]; equip = row['preparations'][0]
        unload = next(item for item in row['commands'] if item['name'] == 'gun-a')
        equip['lifecycle'][2]['sequence'], unload['lifecycle'][0]['sequence'] = unload['lifecycle'][0]['sequence'], equip['lifecycle'][2]['sequence']
        self.assertTrue(a.check_case(*result), 'Host enabled admission cannot precede client perform finish')

    def test_grouped_authority_readiness_and_complete_receipts(self):
        for kind in ('sp', 'mp'):
            selection = dict(kind=kind, mode='toolkit'); cases = list(a.CASES)
            client = ['[QUEUE_TEST] ' + marker for marker in ('VOICE_DISABLED', 'DISPLAY_READY', 'PREFLIGHT_COMPLETE', 'NATIVE_CONNECTED' if kind == 'mp' else 'TRUE_SP')]
            client += ['[QUEUE_CHECK] ' + json.dumps(dict(suite='magazine-unload', event='setup', cases=cases, queueEnabled=True, nativeDurations=True, adapterInstalled=True))]
            server = ['[STARTUP_TEST] SERVER_READY']
            for case in cases:
                row, _, ids, final = evidence(kind=kind, case=case)
                row.update(suite='magazine-unload', event='case', id=case, actor='client1', kind=kind, mode='toolkit')
                client += [a.PREFIX + 'CLIENT_PLACEMENT ' + json.dumps(dict(case=case, proof=row['clientPlacement'])), '[QUEUE_CHECK] ' + json.dumps(row)]
                server += [a.PREFIX + 'PREPARED ' + json.dumps(ids), a.PREFIX + 'VERIFIED ' + json.dumps(final)]
            if kind == 'sp': client += server
            client += ['[QUEUE_CHECK] ' + json.dumps(dict(suite='magazine-unload', event='complete', cases=cases, performed=len(cases), failed=0, skipped=0)),
                       a.PREFIX + 'COMPLETE ' + json.dumps(dict(cases=cases))]
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary); (root / 'client1-launch.log').write_text('\n'.join(client)); (root / 'server-launch.log').write_text('\n'.join(server))
                self.assertEqual([], a.verify(root, selection, {})['issues'])
                (root / 'client1-launch.log').write_text('\n'.join(client[1:]))
                self.assertTrue(a.verify(root, selection, {})['issues'])
                (root / 'client1-launch.log').write_text('\n'.join(client[:-1]))
                self.assertTrue(a.verify(root, selection, {})['issues'])
                if kind == 'mp':
                    (root / 'client1-launch.log').write_text('\n'.join(client)); (root / 'server-launch.log').write_text('\n'.join(server[:-1]))
                    self.assertTrue(a.verify(root, selection, {})['issues'])

    def test_native_source_audit_refuses_changes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); data = b'current native fixture source'; expected = {name: zlib.crc32(data) for name in a.NATIVE_CRC}
            for relative in expected:
                path = root / relative; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
            with patch.object(a, 'NATIVE_CRC', expected):
                self.assertEqual(expected, a.audit_native(root))
                (root / next(iter(expected))).write_bytes(b'modified callback')
                with self.assertRaises(ValueError): a.audit_native(root)

    def test_report_verifier_is_declared_from_first_capture(self):
        from queue_checks import provenance
        selection = dict(suite='magazine-unload')
        with patch.object(provenance.adapters, 'get', return_value=a):
            declared = {path.resolve() for path in provenance.verifier_sources(PROJECT, selection)}
            inputs = {path.resolve() for path in a.sources(PROJECT, selection)} | declared | {Path(a.__file__).resolve()}
            roles = provenance.source_roles(PROJECT, selection, {str(path): provenance.digest(path) for path in inputs})
        verifier = Path(a.__file__).with_name('magazine_unload_verifier.py').resolve()
        self.assertIn(str(verifier), roles['verifier']); self.assertIn(str(Path(__file__).resolve()), roles['verifier'])
        self.assertIn(str(Path(a.__file__).resolve()), roles['runtime'])
        self.assertIn(str(PROJECT / 'tests/native_queue/magazine-unload/client/ZZMagazineUnload.lua'), roles['runtime'])

    def test_fixture_compiles_and_never_accelerates_or_injects_native_events(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True); compile_ = lua.eval('function(source)local f,e=loadstring(source);assert(f,e)end')
        root = PROJECT / 'tests/native_queue/magazine-unload'
        for file in root.rglob('*.lua'):
            text = file.read_text(); compile_(text)
            self.assertNotRegex(text, r'\.(?:maxTime|animEvent|serverStart|complete|perform)\s*=(?!=)')
            self.assertNotIn('emulateAnimEvent(', text)
            self.assertNotIn(':animEvent(', text)
        client = (root / 'client/ZZMagazineUnload.lua').read_text()
        self.assertIn('ISInventoryPaneContextMenu.onUnloadBulletsFromMagazine(player,item)', client)
        self.assertIn('BulkFirearms.unloadEntries(player,rows)', client)
        self.assertIn('BulkFirearms.queueUnload(player,entries)', client)
        self.assertIn('ActionQueue.cancelOperation(', client); self.assertIn('ActionQueue.move(', client)

    def test_shared_fixture_conservation_and_cleanup_execute_with_realistic_ammo_metadata(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().fixture = str(PROJECT / 'tests/native_queue/magazine-unload/shared/QueueMagazineUnload.lua')
        lua.execute(r'''
package.loaded.QueueEnergyPlacement={}
function instanceof(value,kind)return value.class==kind end
function getClassSimpleName(value)return value.class end
function isServer()return false end
local F=dofile(fixture)
for _,mode in ipairs({'native','toolkit'})do
 local values={};local root={}
 local function item(id,kind,loaded,uses)
  local value={class='ComboItem',id=id,kind=kind,loaded=loaded or 0,uses=uses or 1}
  function value:getID()return self.id end
  function value:getFullType()return self.kind end
  function value:getContainer()return root end
  function value:getCurrentAmmoCount()return self.loaded end
  function value:getMaxAmmo()return self.kind=='Base.9mmClip'and 15 or 0 end
  function value:getAmmoType()return self.kind=='Base.9mmClip'and{getItemKey=function()return 'Base.Bullets9mm'end}or nil end
  function value:getCount()return self.kind=='Base.9mmClip'and 1 or self.kind=='Base.Bullets9mm'and 5 or 6 end
  function value:getCurrentUses()return self.uses end
  function value:getCondition()return 10 end
  function value:isFavorite()return false end
  values[#values+1]=value;return value
 end
 function root:getItems()return{size=function()return #values end,get=function(_,i)return values[i+1]end}end
 function root:getItemById(id)for _,value in ipairs(values)do if value.id==id then return value end end end
 function root:Remove(item)for i,value in ipairs(values)do if value==item then table.remove(values,i);return end end end
 local player={getInventory=function()return root end,isEquipped=function()return false end,getPrimaryHandItem=function()end,getSecondaryHandItem=function()end}
 local ids={case='direct',mode=mode,magazines={},seedAmmo={20,21},otherAmmo=22,hands={primary=false,secondary=false},firearms={}}
 local state={player=player,ids=ids,items={}}
 for index,name in ipairs(F.names)do
  local value=item(index,'Base.9mmClip',F.loads[name]);state.items[name]=value
  ids.magazines[name]={id=index,type=value.kind,class='ComboItem',loaded=value.loaded,maxAmmo=15,ammoType='Base.Bullets9mm',factoryCount=1,condition=10}
 end
 for index,name in ipairs({'gun-a','gun-b'})do
  local value=item(40+index,'Base.Shotgun',1);value.class='HandWeapon';state.items[name]=value
  function value:getMaxAmmo()return 5 end
  function value:getAmmoType()return{getItemKey=function()return 'Base.ShotgunShells'end}end
  function value:getCount()return 1 end
  function value:getMagazineType()end
  function value:isContainsClip()return false end
  function value:haveChamber()return true end
  function value:isRoundChambered()return name=='gun-a'end
  function value:isSpentRoundChambered()return false end
  function value:getSpentRoundCount()return 0 end
  function value:getJobDelta()return 0 end
  local spec=F.gunFacts(player,value);spec.hands=nil;spec.jobDelta=nil;ids.firearms[name]=spec
 end
 item(20,'Base.Bullets9mm');item(21,'Base.Bullets9mm');item(22,'Base.ShotgunShells');local untouched=item(99,'Base.Bullets9mm',0,3)
 state.input=F.snapshot(state);ids.initialAmmo=state.input.ammo;assert(F.baseline(state))
 local nextID=100
 for _,name in ipairs({'front','target','cancelled','tail','gun-tail'})do
  if mode=='native'or name~='cancelled'then
   local magazine=state.items[name]
   while magazine.loaded>0 do magazine.loaded=magazine.loaded-1;item(nextID,'Base.Bullets9mm');nextID=nextID+1 end
  end
 end
 for _,name in ipairs({'gun-a','gun-b'})do state.items[name].loaded=0;item(nextID,'Base.ShotgunShells');nextID=nextID+1 end
 assert(F.verify(state),'native-shaped output conservation failed')
 local output=values[#values];output.uses=5;assert(not F.verify(state),'factoryCount confused with actionable round uses');output.uses=1
 local missing=table.remove(values);assert(not F.verify(state),'missing round accepted');values[#values+1]=missing
 state.items.unrelated.loaded=0;assert(not F.verify(state),'unrelated magazine was allowed to unload');state.items.unrelated.loaded=6
 assert(F.verify(state));F.dispose(state)
 assert(#values==1 and values[1]==untouched and untouched.uses==3,'cleanup touched preexisting ammo')
end
''')

    def test_installed_kahlua_native_constructor_uses_exact_fixture_owned_guard_read(self):
        game, jdk = os.environ.get('PZ_GAME'), os.environ.get('PZ_JDK')
        if not game or not jdk: self.skipTest('PZ_GAME and PZ_JDK required for installed Kahlua own-slot regression')
        a.audit_native(game)
        client = (PROJECT / 'tests/native_queue/magazine-unload/client/ZZMagazineUnload.lua').read_text()
        self.assertIn('local guard=F.ownStartGuard(action)', client)
        self.assertNotRegex(client, r"rawget\s*\(action\s*,\s*['\"]isValidStart")
        java_source = r'''
import java.nio.file.*;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.*;
public final class MagazineOwnGuardChecks {
 static final J2SEPlatform platform=J2SEPlatform.getInstance();
 static KahluaTable env;
 static KahluaThread thread;
 static void filenames(Prototype p,String name){p.filename=name;for(Prototype child:p.prototypes)filenames(child,name);}
 static Object run(String source,String name)throws Exception{
  LuaClosure chunk=LuaCompiler.loadstring(source,name,env);filenames(chunk.prototype,name);
  return thread.call(chunk,new Object[0]);
 }
 static Object load(Path path)throws Exception{return run(Files.readString(path),path.getFileName().toString());}
 static void source(Object value,String method,String file){
  if(!(value instanceof KahluaTable table)||!(table.rawget(method) instanceof LuaClosure closure)
   ||!file.equals(closure.prototype.filename))throw new AssertionError("native/fixture source capture differs: "+method);
 }
 public static void main(String[] args)throws Exception{
  Path game=Path.of(args[0]),project=Path.of(args[1]);env=platform.newTable();env.rawset("_G",env);env.rawset("_VERSION","Kahlua");
  se.krka.kahlua.stdlib.BaseLib.register(env);se.krka.kahlua.j2se.MathLib.register(platform,env);
  se.krka.kahlua.stdlib.RandomLib.register(platform,env);se.krka.kahlua.stdlib.StringLib.register(platform,env);
  se.krka.kahlua.stdlib.CoroutineLib.register(platform,env);se.krka.kahlua.stdlib.OsLib.register(platform,env);
  se.krka.kahlua.stdlib.TableLib.register(platform,env);LuaCompiler.register(env);
  thread=new KahluaThread(System.out,platform,env);thread.debugOwnerThread=Thread.currentThread();
  try(var stream=Files.newInputStream(game.resolve("stdlib.lbc"))){thread.call(Prototype.loadByteCode(stream,env),new Object[0]);}
  run("require=function()return{}end","bootstrap");
  load(game.resolve("media/lua/shared/ISBaseObject.lua"));
  load(game.resolve("media/lua/shared/TimedActions/ISBaseTimedAction.lua"));
  load(game.resolve("media/lua/shared/TimedActions/ISUnloadBulletsFromMagazine.lua"));
  load(game.resolve("media/lua/shared/TimedActions/ISUnloadBulletsFromFirearm.lua"));
  Object fixture=load(project.resolve("tests/native_queue/magazine-unload/shared/QueueMagazineUnload.lua"));env.rawset("Fixture",fixture);
  source(env.rawget("ISUnloadBulletsFromMagazine"),"new","ISUnloadBulletsFromMagazine.lua");
  source(env.rawget("ISBaseTimedAction"),"isValidStart","ISBaseTimedAction.lua");
  source(fixture,"ownStartGuard","QueueMagazineUnload.lua");
  run("local actor,magazine={},{};local action=ISUnloadBulletsFromMagazine:new(actor,magazine);"
   +"assert(action.character==actor and action.magazine==magazine and action.maxTime==-1 and action.Type=='ISUnloadBulletsFromMagazine');"
   +"assert(type(action.isValidStart)=='function' and rawget(action,'isValidStart')==ISBaseTimedAction.isValidStart,'installed rawget no longer demonstrates inherited native guard');"
   +"local direct=Fixture.ownStartGuard(action);assert(direct==nil,'direct native action falsely owns inherited guard');"
   +"local guard=function()error('own-slot observation executed guard')end;action.isValidStart=guard;"
   +"assert(Fixture.ownStartGuard(action)==guard,'owned start callback was not returned exactly');"
   +"assert(ISBaseTimedAction.isValidStart~=guard and action.maxTime==-1,'guard read mutated native constructor/base');",
   "fixture-own-guard-regression");
  run("""
-- Headless regression only: drive real native callbacks through the fixture observer, no live game/events.
function isClient()return false end
function getText(key)return key end
function getClassSimpleName(value)return 'LuaTimedActionNew'end
function instanceof()return false end
local root={getItems=function()return{size=function()return 0 end}end}
local actor={getInventory=function()return root end,setIsFarming=function()end}
local completed=0
ISTimedActionQueue={getTimedActionQueue=function()return{onCompleted=function()completed=completed+1 end}end}
ISLogSystem={logAction=function()end}
local tracks={};local callbacks={start=ISUnloadBulletsFromMagazine.start,perform=ISUnloadBulletsFromMagazine.perform,complete=ISUnloadBulletsFromMagazine.complete}
local observer=Fixture.lifecycleObserver(function()return tracks end,callbacks)
local previous=0
for _,name in ipairs({'repeat-first','repeat-second'})do
 local loaded=4
 local magazine={getCurrentAmmoCount=function()return loaded end,setJobType=function()end,setJobDelta=function()end}
 local action=ISUnloadBulletsFromMagazine:new(actor,magazine)
 assert(action.ammoCountStart==nil and action.maxTime==-1)
 local row={name=name,lifecycle={},callbacksUntouched=true};tracks[action]=row
 loaded=0
 assert(observer.started(action)==nil and action.ammoCountStart==nil)
 local forced=0;action.action={forceComplete=function()forced=forced+1 end}
 action:start();assert(forced==1 and action.ammoCountStart==0)
 for _,phase in ipairs({'perform','complete'})do
  assert(observer.begin(action,phase)==true)
  local result=action[phase](action);assert(phase~='complete'or result==true)
  assert(observer.finish(action,phase,true)==nil)
 end
 assert(#row.lifecycle==5 and row.callbacksUntouched and completed==(name=='repeat-first'and 1 or 2))
 local episode
 for i,event in ipairs(row.lifecycle)do
  assert(event.sequence>previous);previous=event.sequence
  assert(event.loaded==0 and #event.ammo==0)
  if i==1 then assert(event.startAmmo==false and event.nativeEpisode==false)
  else
   assert(event.startAmmo==0 and event.nativeEpisode and event.nativeClass=='LuaTimedActionNew')
   episode=episode or event.nativeEpisode;assert(episode==event.nativeEpisode)
  end
 end
 assert(action.start==callbacks.start and action.perform==callbacks.perform and action.complete==callbacks.complete)
end
assert(observer.begin({},'perform')==nil,'untracked observer granted a scope')
""", "fixture-native-empty-start-observer-regression");
  run("""
-- Real native zero-count firearm start/update/events/perform, executed only in this headless regression.
CharacterActionAnims={Reload='Reload'};Metabolics={LightDomestic='LightDomestic'}
ISReloadWeaponAction={setReloadSpeed=function()end}
function isServer()return false end
local values={};local root={getItems=function()return{size=function()return #values end,get=function(_,i)return values[i+1]end}end}
local gun,delta;local actor={getInventory=function()return root end,setIsFarming=function()end,clearVariable=function()end,setMetabolicTarget=function()end}
function actor:getPrimaryHandItem()return gun end
function actor:getSecondaryHandItem()return gun end
function getClassSimpleName(value)return value==gun and'HandWeapon'or'LuaTimedActionNew'end
local completed=0;ISTimedActionQueue={getTimedActionQueue=function()return{onCompleted=function()completed=completed+1 end}end}
local callbacks={};for _,name in ipairs({'start','update','complete','perform','animEvent','initVars'})do callbacks[name]=ISUnloadBulletsFromFirearm[name]end
for _,name in ipairs({'gun-repeat-a','gun-repeat-b'})do
 delta=0
 gun={getID=function()return 99 end,getFullType=function()return 'Base.Shotgun'end,getCurrentAmmoCount=function()return 0 end,
  getMaxAmmo=function()return 5 end,getAmmoType=function()return{getItemKey=function()return 'Base.ShotgunShells'end}end,
  getCount=function()return 1 end,getCondition=function()return 10 end,getMagazineType=function()end,isContainsClip=function()return false end,
  haveChamber=function()return true end,isRoundChambered=function()return true end,isSpentRoundChambered=function()return false end,
  getSpentRoundCount=function()return 0 end,getJobDelta=function()return delta end,setJobDelta=function(_,value)delta=value end,
  setJobType=function()end,getWeaponReloadType=function()return 'shotgun'end,getEjectAmmoStopSound=function()end}
 local action=ISUnloadBulletsFromFirearm:new(actor,gun)
 local row={name=name,lifecycle={},callbacksUntouched=true};local tracks={[action]=row}
 local observer=Fixture.lifecycleObserver(function()return tracks end,callbacks)
 assert(action.ammoCountStart==nil and action.maxTime==-1 and observer.started(action)==nil)
 local forced=0;action.action={forceComplete=function()forced=forced+1 end,setActionAnim=function()end,setAnimVariable=function()end,setOverrideHandModelsObject=function()end}
 action:start();assert(action.ammoCountStart==0 and delta==0 and forced==0,'firearm empty start must stay native and animated')
 action:animEvent('playReloadSound');assert(#values==0)
 action:animEvent('unloadFinished');assert(action.unloadFinished)
 -- Native update's zero/zero is retained; only native perform resets the field.
 gun.setCurrentAmmoCount=function(_,value)assert(value==0)end
 action:update();assert(delta~=delta and forced==1 and Fixture.jobDelta(gun)=='nan')
 assert(observer.begin(action,'perform')==true);action:perform();observer.finish(action,'perform',true)
 assert(delta==0 and completed>0 and #values==0)
 assert(observer.begin(action,'complete')==true and action:complete());observer.finish(action,'complete',true)
 assert(row.callbacksUntouched and row.lifecycle[2].firearm.jobDelta=='nan'and row.lifecycle[3].firearm.jobDelta==0)
 for _,event in ipairs(row.lifecycle)do
  assert(event.loaded==0 and #event.ammo==0 and event.firearm.roundChambered and not event.firearm.spentRoundChambered and event.firearm.spentRoundCount==0)
  assert(event.firearm.magazineType==false and not event.firearm.containsClip and event.firearm.hands.primary==99 and event.firearm.hands.secondary==99)
 end
end
assert(completed==2)
""", "fixture-native-integral-empty-regression");
  System.out.println("KAHLUA_NATIVE_OWN_GUARD_OK");
 }
}
'''
        with tempfile.TemporaryDirectory(prefix='pz-magazine-kahlua-own-') as temporary:
            root = Path(temporary); source = root / 'MagazineOwnGuardChecks.java'; source.write_text(java_source)
            jar = Path(game) / 'projectzomboid.jar'
            environment = {key: value for key, value in os.environ.items() if key not in ('JDK_JAVA_OPTIONS', 'JAVA_TOOL_OPTIONS', '_JAVA_OPTIONS')}
            compiled = subprocess.run([str(Path(jdk) / 'bin/javac'), '--release', '25', '-cp', str(jar), '-d', str(root), str(source)],
                                      capture_output=True, text=True, timeout=30, env=environment)
            self.assertEqual(0, compiled.returncode, compiled.stdout + compiled.stderr)
            checked = subprocess.run([str(Path(jdk) / 'bin/java'), '-cp', str(root) + os.pathsep + str(jar),
                                      'MagazineOwnGuardChecks', str(game), str(PROJECT)], capture_output=True, text=True, timeout=20, env=environment)
            self.assertEqual(0, checked.returncode, checked.stdout + checked.stderr)
            self.assertIn('KAHLUA_NATIVE_OWN_GUARD_OK', checked.stdout)

    def test_installed_native_remove_bullet_uses_one_output_per_decrement_complete_is_empty(self):
        game = os.environ.get('PZ_GAME')
        if not game: self.skipTest('PZ_GAME required for installed native unload source regression')
        source = Path(game) / 'media/lua/shared/TimedActions/ISUnloadBulletsFromMagazine.lua'
        self.assertEqual(a.NATIVE_CRC[str(source.relative_to(game))], zlib.crc32(source.read_bytes()))
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True); lua.globals().source = str(source)
        lua.execute(r'''
require=function()end
ISBaseTimedAction={derive=function(_,name)local c={Type=name};c.__index=c;return c end}
function isServer()return true end
function isClient()return false end
function isMultiplayer()return true end
local created,loaded=0,3
function instanceItem(kind)assert(kind=='Base.Bullets9mm');created=created+1;return{getCurrentUses=function()return 1 end,getCount=function()return 5 end}end
function sendAddItemToContainer()end
function syncItemFields()end
dofile(source)
local inventory={AddItem=function(_,item)assert(item:getCurrentUses()==1 and item:getCount()==5)end}
local magazine={getCurrentAmmoCount=function()return loaded end,setCurrentAmmoCount=function(_,n)loaded=n end,
 getAmmoType=function()return{getItemKey=function()return 'Base.Bullets9mm'end}end}
local action=setmetatable({magazine=magazine,character={getInventory=function()return inventory end}},ISUnloadBulletsFromMagazine)
assert(action:getDuration()==-1 and action:complete()and loaded==3 and created==0)
-- Offline callback unit test only; the native fixture never injects animation events.
action:animEvent('RemoveBullet',nil);assert(loaded==2 and created==1)
assert(action:complete()and loaded==2 and created==1)
action:animEvent('RemoveBullet',nil);action:animEvent('RemoveBullet',nil);assert(loaded==0 and created==3)
action:animEvent('RemoveBullet',nil);assert(loaded==0 and created==3)
''')


if __name__ == '__main__':
    unittest.main()
