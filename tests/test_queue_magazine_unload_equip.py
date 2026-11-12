"""Equip group selection, sealed lifecycle/identity evidence, and denial controls."""
import copy
import json
import tempfile
from pathlib import Path
import sys
import unittest

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / 'tools'))
from queue_checks.adapters import magazine_unload as adapter
from queue_checks.adapters import magazine_unload_equip_verifier as verifier
from tests.test_queue_wring_clothing import placement_proof


def evidence(segment='reorder-two', kind='sp', mode='toolkit'):
    selection = dict(kind=kind, mode=mode)
    editing = kind == 'sp' and mode == 'toolkit'
    types = dict(front='Base.BookCarpentry1', tail='Base.BookFirstAid1', a='Base.Hammer' if segment == 'component-guard' else 'Base.Nails', b='Base.Screwdriver', c='Base.Scissors', bag='Base.Bag_Schoolbag', marker='Base.Nails')
    if segment in ('dependent', 'capacity'): types['nested'] = 'Base.Plank' if segment == 'capacity' else 'Base.Pencil'
    if segment == 'capacity': types['heldBag'] = 'Base.Bag_Schoolbag'
    items = {}
    for index, (name, full_type) in enumerate(types.items(), 10):
        class_name = 'Literature' if name in ('front', 'tail') else 'InventoryContainer' if name in ('bag', 'heldBag') else 'HandWeapon' if name in ('b', 'c', 'nested') or name == 'a' and segment == 'component-guard' else 'ComboItem'
        items[name] = dict(id=index, type=full_type, **{'class': class_name})
        if name in ('front', 'tail'): items[name]['pages'] = 100
    inventory = []
    for name, spec in items.items():
        path = [items['bag']['id']] if name == 'marker' or name == 'nested' and segment == 'dependent' else [items['heldBag']['id']] if name == 'nested' else []
        inventory.append(dict(id=spec['id'], type=spec['type'], path=path, condition=10, count=5 if spec['type'] == 'Base.Nails' else 1, uses=1, **{'class': spec['class']}))
    origin = dict(x=11, y=20, z=0)
    ids = dict(case='equip-edit', segment=segment, mode=mode, kind=kind, origin=origin, items=items,
               placementProof=placement_proof(origin, 'replica' if kind == 'mp' else 'local'), inventory=inventory)
    def snapshot(final=False):
        rows = copy.deepcopy(inventory)
        books = {name: dict(id=items[name]['id'], present=True, root=True, total=100, pages=100 if final else 99, characterPages=100 if final else 99) for name in ('front', 'tail')}
        return dict(case='equip-edit', segment=segment, inventory=rows, books=books, backpack=True,
                    hands=verifier.expected_hands(ids, editing) if final else dict(primary=False, secondary=False))
    source = ['front', 'equip-a', 'equip-b'] + (['equip-c'] if segment in ('reorder-three', 'cancel') else []) + ['tail']
    if segment == 'dependent': source = ['front', 'transfer', 'equip-nested', 'tail']
    if segment == 'capacity': source = ['front', 'equip-bag', 'transfer', 'tail']
    order = list(source)
    if editing and segment == 'reorder-two': order = ['front', 'equip-b', 'equip-a', 'tail']
    elif editing and segment == 'reorder-three': order = ['front', 'equip-c', 'equip-a', 'equip-b', 'tail']
    elif editing and segment == 'cancel': order.remove('equip-c')
    commands = []
    for name in source:
        item_name = name.removeprefix('equip-')
        if name == 'transfer': item_name = 'nested'
        if name == 'equip-bag': item_name = 'heldBag'
        row = dict(name=name, type='ISEquipWeaponAction' if name.startswith('equip-') else 'ISInventoryTransferAction' if name == 'transfer' else 'ISReadABook',
                   item=items[item_name]['id'], duration=50 if name.startswith('equip-') else 100, callbacksUntouched=True,
                   lifecycle=[], started=name in order, progress=name in order)
        if name.startswith('equip-'):
            row.update(primary=not (segment == 'reorder-three' and name in ('equip-a', 'equip-c') or segment == 'cancel' and name == 'equip-b'), twoHands=False, maxTimeInit=50)
        if name not in order: row.update(cancelled=True, started=False, progress=False)
        commands.append(row)
    serial = 0; hands = dict(primary=False, secondary=False); transferred = False
    for episode, name in enumerate(order, 1):
        command = next(value for value in commands if value['name'] == name)
        events = [('admission', False), ('begin', 'perform'), ('finish', 'perform')]
        if kind == 'sp': events += [('begin', 'complete'), ('finish', 'complete')]
        for event, phase in events:
            serial += 1
            if command['type'] == 'ISInventoryTransferAction' and event == 'finish' and phase == 'complete': transferred = True
            if command['type'] == 'ISEquipWeaponAction' and event == 'finish' and phase == 'complete': hands['primary' if command['primary'] else 'secondary'] = command['item']
            item_name = name.removeprefix('equip-')
            if name == 'transfer': item_name = 'nested'
            if name == 'equip-bag': item_name = 'heldBag'
            nested = item_name == 'nested' and not transferred
            location = dict(root=not nested, containerPresent=True, owner=items['bag' if segment == 'dependent' else 'heldBag']['id'] if nested else False)
            command['lifecycle'].append(dict(sequence=serial, event=event, phase=phase, succeeded=event == 'finish',
                nativeEpisode=episode, nativeClass='LuaTimedActionNew', hands=copy.deepcopy(hands), itemLocation=location))
    edits = []
    if mode == 'toolkit':
        names = ['reorder'] if segment.startswith('reorder-') else ['cancel'] if segment == 'cancel' else ['unavailable-input', 'dependent-transfer'] if segment == 'dependent' else ['component-reorder', 'component-cancel'] if segment == 'component-guard' else ['capacity-transfer', 'capacity-cancel']
        for name in names:
            allowed = editing and segment in ('reorder-two', 'reorder-three', 'cancel')
            edits.append(dict(name=name, allowed=allowed, reason=False if allowed else 'unavailable', queueBefore=source, queueAfter=order if allowed else source))
    final = snapshot(True)
    row = dict(segment=segment, ids=copy.deepcopy(ids), input=snapshot(), clientPlacement=placement_proof(origin),
               client=copy.deepcopy(final), server=copy.deepcopy(final), commands=commands, edits=edits,
               componentGuard=dict(item=items['a']['id'], size=2, quiet=False, components=[dict(index=0, type='Attributes', **{'class': 'Attributes'}), dict(index=1, type='Script', **{'class': 'EntityScriptInfo'})]) if segment == 'component-guard' else False,
               pendingBefore=snapshot(), pendingAfter=snapshot(), pendingOrder=order, queueIdle=True, tidyQuiescent=True,
               tidyObservation=dict(sourceVerified=True, integrationInstalled=True, idlePlayerUpdates=6, observer='ActionQueueSettlement.operationState', retainedOperations=0, observedBorrowings=0, outstandingBorrowings=0, activeBlockedReturn=False, privateTablesObserved=False), settleMilliseconds=1000, frameCadence=dict(count=2, totalMilliseconds=33, maxMilliseconds=17))
    return row, selection, ids, final


class EquipEditTests(unittest.TestCase):
    def test_ordered_subset_and_independent_equip_group_selection(self):
        selection = dict(kind='sp', mode='toolkit', clients=1, languages=['EN'], mods=adapter.MODS, options={})
        for cases in (['direct'], ['bulk'], ['direct', 'bulk'], ['equip-edit']):
            adapter.validate(dict(selection, cases=cases))
        for cases in ([], ['bulk', 'direct'], ['direct', 'direct'], ['equip-edit', 'direct'], ['missing']):
            with self.assertRaises(ValueError): adapter.validate(dict(selection, cases=cases))
        self.assertIn('equip-edit', [row['id'] for row in adapter.definitions()['magazine-unload']['cases']])

    def test_matching_native_and_sp_toolkit_and_host_denial_evidence(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                for segment in verifier.SEGMENTS:
                    self.assertEqual([], verifier.check_segment(*evidence(segment, kind, mode)), (segment, kind, mode))

    def test_inventory_loss_alias_nested_drift_and_final_hands_are_rejected(self):
        for change in ('missing', 'duplicate', 'wrong-hands', 'backpack', 'contents', 'authority', 'pending-physical'):
            values = evidence('dependent'); row = values[0]
            if change == 'missing': row['client']['inventory'].pop()
            elif change == 'duplicate': row['client']['inventory'].append(copy.deepcopy(row['client']['inventory'][-1]))
            elif change == 'wrong-hands': row['client']['hands']['primary'] = row['ids']['items']['a']['id']
            elif change == 'backpack': row['client']['backpack'] = False
            elif change == 'contents': next(value for value in row['client']['inventory'] if value['id'] == row['ids']['items']['nested']['id'])['path'] = []
            elif change == 'authority': row['server']['books']['tail']['pages'] -= 1
            else: row['pendingAfter']['inventory'].pop()
            self.assertTrue(verifier.check_segment(*values), change)

    def test_host_cannot_inherit_sp_rights_and_denials_cannot_reorder(self):
        values = evidence(kind='mp'); values[0]['edits'][0]['allowed'] = True
        self.assertTrue(verifier.check_segment(*values))
        values = evidence(kind='mp'); values[0]['edits'][0]['reason'] = 'bogus-denial'
        self.assertTrue(verifier.check_segment(*values))
        for segment, reason in (('reorder-two', 'move_dependent'), ('cancel', 'operation_dependent')):
            values = evidence(segment, kind='mp'); values[0]['edits'][0]['reason'] = reason
            self.assertEqual([], verifier.check_segment(*values))
        values = evidence('capacity'); values[0]['edits'][0]['queueAfter'] = list(reversed(values[0]['edits'][0]['queueBefore']))
        self.assertTrue(verifier.check_segment(*values))

    def test_native_callbacks_paid_lifecycle_and_independent_tail_required(self):
        for change in ('duration', 'callback', 'perform', 'episode', 'progress', 'tail', 'cancel-ran', 'p4-busy'):
            values = evidence('cancel'); row = values[0]; command = row['commands'][1]
            if change == 'duration': command['duration'] = 1
            elif change == 'callback': command['callbacksUntouched'] = False
            elif change == 'perform': command['lifecycle'] = [event for event in command['lifecycle'] if event['phase'] != 'perform']
            elif change == 'episode': command['lifecycle'][2]['nativeEpisode'] = False
            elif change == 'progress': row['commands'][0]['progress'] = False
            elif change == 'tail': row['commands'].pop()
            elif change == 'cancel-ran': row['commands'][3]['started'] = True
            else: row['tidyQuiescent'] = False
            self.assertTrue(verifier.check_segment(*values), change)

    def test_native_transfer_and_equip_effects_precede_original_p4_restoration(self):
        for segment in ('dependent', 'capacity'):
            values = evidence(segment)
            self.assertEqual(dict(primary=False, secondary=False), values[0]['client']['hands'])
            self.assertEqual(values[2]['inventory'], values[0]['client']['inventory'])
            for change in ('transfer-effect', 'equip-effect', 'invented-retention'):
                changed = copy.deepcopy(values); row = changed[0]
                if change == 'invented-retention': row['client']['hands']['primary'] = row['ids']['items']['nested' if segment == 'dependent' else 'heldBag']['id']
                else:
                    command = next(value for value in row['commands'] if value['name'] == ('transfer' if change == 'transfer-effect' else 'equip-nested' if segment == 'dependent' else 'equip-bag'))
                    event = next(value for value in command['lifecycle'] if value['event'] == 'finish' and value['phase'] == 'complete')
                    if change == 'transfer-effect': event['itemLocation'] = dict(root=False, containerPresent=True, owner=row['ids']['items']['bag' if segment == 'dependent' else 'heldBag']['id'])
                    else: event['hands'] = dict(primary=False, secondary=False)
                self.assertTrue(verifier.check_segment(*changed), (segment, change))

    def test_quiescence_observes_real_idle_updates_and_retained_loans_without_private_maps(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().helper_path = str(PROJECT / 'tests/native_queue/magazine-unload/client/QueueEquipEditQuiescence.lua')
        # Explicit source-metadata and private-loan observer doubles; no P4 map is exposed.
        lua.execute('''
local helper=assert(loadfile(helper_path))()
local idle,valid,blocked=true,true,false
local updates,states={},{}
P4TidyUpMeister={registerActionPolicy=function()end,registerWornItemReplacement=function()end}
local compat={isInstalled=function()return true end,verifySources=function()return true end}
local settlement={operationState=function(action)return states[action]end,hasActiveBlockedReturn=function()return blocked end}
local proof={closure=function(value)return type(value)=='function'end,captureBindings=function()return function()return valid end end}
local events={OnPlayerUpdate={Add=function(callback)updates[#updates+1]=callback end}}
local player,other,action={},{},{}
local tracks={[action]={}}
local observer=helper.new({ActionQueueCompat=compat,ActionQueueSettlement=settlement},player,function()return idle end,proof,events)
local function tick(who)for _,callback in ipairs(updates)do callback(who or player)end end
for i=1,8 do tick(other)end
assert(observer.read(tracks)==nil,'foreign player updates became quiescence')
for i=1,5 do tick()end
assert(observer.read(tracks)==nil,'P4 idle boundary completed too early')
tick();local receipt=assert(observer.read(tracks));assert(receipt.idlePlayerUpdates==6 and receipt.privateTablesObserved==false and receipt.retainedOperations==0)
states[action]={borrowings={{state='prepare'}}};assert(observer.read(tracks)==nil,'outstanding borrowing was ignored')
local diagnostic=observer.diagnose(tracks);assert(diagnostic.privateTablesObserved==false and diagnostic.operations[1].state.borrowings[1].state=='prepare','failure diagnosis lost original retained-loan state')
states[action].borrowings[1].state='completed';receipt=assert(observer.read(tracks));assert(receipt.retainedOperations==1 and receipt.observedBorrowings==1)
blocked=true;assert(observer.read(tracks)==nil,'blocked return was ignored');blocked=false
idle=false;tick();idle=true;assert(observer.read(tracks)==nil,'native work did not reset idle boundary')
for i=1,6 do tick()end
valid=false;assert(observer.read(tracks)==nil,'changed source bindings retained authority');valid=true
assert(observer.read(tracks));observer.reset();assert(observer.read(tracks)==nil,'segment reset retained idle history')
''')

    def test_quiescence_receipt_cannot_claim_private_maps_or_outstanding_loans(self):
        for field, value in (('idlePlayerUpdates', 5), ('outstandingBorrowings', 1), ('activeBlockedReturn', True),
                             ('privateTablesObserved', True), ('sourceVerified', False), ('integrationInstalled', False)):
            values = evidence(); values[0]['tidyObservation'][field] = value
            self.assertTrue(verifier.check_segment(*values), field)

    def test_frame_cadence_is_structural_evidence_without_arbitrary_performance_gate(self):
        for total, maximum in ((0, 0), (33, 17), (100000, 90000)):
            values = evidence(); values[0]['frameCadence'] = dict(count=2, totalMilliseconds=total, maxMilliseconds=maximum)
            self.assertEqual([], verifier.check_segment(*values))
        for cadence in (dict(count=0, totalMilliseconds=0, maxMilliseconds=0),
                        dict(count=2, totalMilliseconds=20, maxMilliseconds=21),
                        dict(count=2, totalMilliseconds=50, maxMilliseconds=20),
                        dict(count=2, totalMilliseconds=float('inf'), maxMilliseconds=20)):
            values = evidence(); values[0]['frameCadence'] = cadence
            self.assertTrue(verifier.check_segment(*values))

    def test_component_guard_requires_actual_hammer_components_and_denied_edits(self):
        for change in ('quiet', 'missing', 'wrong-type', 'index', 'allowed', 'reordered', 'substituted'):
            values = evidence('component-guard'); row = values[0]
            if change == 'quiet': row['componentGuard']['quiet'] = True
            elif change == 'missing': row['componentGuard']['components'].pop()
            elif change == 'wrong-type': row['componentGuard']['components'][1]['type'] = 'FluidContainer'
            elif change == 'index': row['componentGuard']['components'][1]['index'] = 8
            elif change == 'allowed': row['edits'][0]['allowed'] = True
            elif change == 'reordered': row['edits'][0]['queueAfter'] = list(reversed(row['edits'][0]['queueBefore']))
            else: row['ids']['items']['a']['type'] = 'Base.Pencil'
            self.assertTrue(verifier.check_segment(*values), change)

    def test_grouped_verifier_requires_all_ordered_authority_checkpoints(self):
        for kind in ('sp', 'mp'):
            selection = dict(kind=kind, mode='toolkit', cases=['equip-edit'])
            client = ['[QUEUE_TEST] ' + marker for marker in ('VOICE_DISABLED', 'DISPLAY_READY', 'PREFLIGHT_COMPLETE', 'NATIVE_CONNECTED' if kind == 'mp' else 'TRUE_SP')]
            authority = ['[STARTUP_TEST] SERVER_READY']
            group = []
            for segment in verifier.SEGMENTS:
                row, _, ids, final = evidence(segment, kind)
                group.append(row)
                client.append(verifier.PREFIX + 'CLIENT_PLACEMENT ' + json.dumps(dict(case='equip-edit', segment=segment, proof=row['clientPlacement'])))
                authority.extend([verifier.PREFIX + 'PREPARED ' + json.dumps(ids), verifier.PREFIX + 'VERIFIED ' + json.dumps(final)])
            client.extend(['[QUEUE_CHECK] ' + json.dumps(dict(suite='magazine-unload', event='setup', cases=['equip-edit'], segments=verifier.SEGMENTS, queueEnabled=True, nativeDurations=True)),
                           '[QUEUE_CHECK] ' + json.dumps(dict(suite='magazine-unload', event='case', id='equip-edit', status='passed', actor='client1', kind=kind, mode='toolkit', segments=group, queueIdle=True, tidyQuiescent=True)),
                           '[QUEUE_CHECK] ' + json.dumps(dict(suite='magazine-unload', event='complete', cases=['equip-edit'], performed=1, failed=0, skipped=0)),
                           adapter.PREFIX + 'COMPLETE ' + json.dumps(dict(cases=['equip-edit']))])
            if kind == 'sp': client += authority
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary); (root / 'client1-launch.log').write_text('\n'.join(client)); (root / 'server-launch.log').write_text('\n'.join(authority))
                result = adapter.verify(root, selection, {})
                self.assertEqual([], result['issues'])
                outcome = result['outcomes'][0]['outcome']
                self.assertIs(outcome['pendingEditsVerified'], kind == 'sp')
                self.assertIs(outcome['pendingProtectionVerified'], True)
                # Drive the real scenario matrix using the verifier's current
                # outcome fields. A clean Host denial cannot become positive
                # cancellation/reorder coverage.
                from queue_checks import scenarios
                suite = adapter.definitions()['magazine-unload']
                coverage = dict(result['outcomes'][0], suite='magazine-unload', kind=kind, mode='toolkit')
                reports = [dict(status='passed', selection=dict(mods=adapter.MODS), coverage=[coverage])]
                def case_matrix(catalog, matching):
                    return dict(rows=[dict(suite='magazine-unload', case='equip-edit', kind=kind, mode='toolkit', status='passed', evidence=[coverage])])
                matrix = scenarios.matrix(dict(suites={'magazine-unload': suite}), reports, case_matrix)
                mapped = {value['scenario']: value for value in matrix if value['action'] == 'native-equip-edit' and value['kind'] == kind and value['mode'] == 'toolkit'}
                for positive in ('cancel-waiting', 'move-independent'):
                    self.assertEqual('passed' if kind == 'sp' else 'missing-evidence', mapped[positive]['status'])
                self.assertEqual('passed', mapped['move-dependent']['status'])

                if kind == 'sp': (root / 'client1-launch.log').write_text('\n'.join(client[:-1]))
                else: (root / 'server-launch.log').write_text('\n'.join(authority[:-1]))
                self.assertTrue(adapter.verify(root, selection, {})['issues'])

    def test_source_audit_adds_native_read_transfer_and_equip_without_weaker_unload_pins(self):
        self.assertEqual(3528902511, adapter.EQUIP_NATIVE_CRC['media/lua/shared/TimedActions/ISEquipWeaponAction.lua'])
        self.assertIn('media/lua/shared/TimedActions/ISUnloadBulletsFromMagazine.lua', adapter.NATIVE_CRC)
        declared = adapter.verifier_sources(PROJECT, dict(cases=['equip-edit']))
        self.assertIn(Path(verifier.__file__), declared)
        self.assertIn(Path(__file__), declared)


if __name__ == '__main__': unittest.main()
