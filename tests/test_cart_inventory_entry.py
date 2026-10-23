"""Initial inventory input must precede fresh native lifetime and later menu fences."""
import copy
import json
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HERE = ROOT/'tests/native_queue/contributions/wooden_cart_multiplayer'
SOURCE = HERE/'analyze-inventory-entry.py'
API = runpy.run_path(str(SOURCE))
LIFETIME = runpy.run_path(str(ROOT/'tests/test_cart_equipment_lifetimes.py'))
EQUIP = runpy.run_path(str(ROOT/'tests/test_cart_mp_inventory_equip.py'))
MARKER = API['MARKER']
TOKEN = '00000000-0000-4000-8000-000000000099'


def fixture():
    selection, logs, rows = LIFETIME['fixture'](menu=True, menu_parses=True, menu_race=True)
    for flag in ('cart_lease_inventory', 'cart_lease_menu', 'cart_lease_lifetimes', 'cart_lease_control',
                 'cart_timeline', 'cart_fast_motion', 'mp_host'):
        selection['options'][flag] = True
    def endpoint(role, event, wall):
        held = event == 'held'
        value = dict(actor=role, event=event, phase=0, owner=7, cart=42, cargoID=313, cargoWeight=30,
                     primaryID=42 if held else -1, secondaryID=42 if held else -1, handSameItem=held,
                     worldAttached=False, worldCount=0, nativeActions=0, hasPath=False,
                     inventoryScope='remote-hand-snapshot' if role == 'client2' else 'owner-inventory',
                     queueScope={'server':'native-server-only', 'client1':'owner-local', 'client2':'remote-native-only'}[role],
                     wall=wall)
        if role != 'client2': value['inventoryCount'] = 1
        if role == 'client1': value['luaActions'] = 0
        if role == 'server': value['guarded'] = True
        return value
    entry = {'server':[endpoint('server', 'unheld', 100), endpoint('server', 'held', 4000)],
             'client1':[endpoint('client1', 'unheld', 150)], 'client2':[endpoint('client2', 'held', 3900)]}
    driver = dict(actor='client1', phase=0, owner=7, cart=42, kind='inventory', actionType='ISCartEquipAction',
                  queuedSource='ISCartEquipAction', localActionEpoch=1, localSourceEpoch=2,
                  source='owned-native-connection', operation=3, generation=0, duration=30, sourceType='inventory')
    for event, wall in (('queued',3100), ('start',3150), ('terminal',3650)):
        row = dict(driver, event=event, wall=wall)
        if event != 'queued': row.update(localNativeEpoch=4, token=TOKEN, transaction=3, nativeMaxTime=30,
                                        luaMaxTime=30.003, state='started' if event == 'start' else 'completed', sealed=True)
        else:row['luaMaxTime']=30
        entry['client1'].append(row)
    entry['client1'].append(endpoint('client1', 'held', 3700))
    for role in ('client1','client2'):
        logs[role].insert(0, '[CART_MP] ARMED '+role+' sprintLevel=10')
    native = EQUIP['fixture']()[1]['client1']
    return selection, logs, rows, entry, native


class InventoryEntryEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.profile = Path(self.temp.name)
        self.selection, self.logs, self.rows, self.entry, self.native = fixture()

    def write(self):
        (self.profile/'selection.json').write_text(json.dumps(self.selection))
        for role in API['ROLES']:
            lines = [MARKER+json.dumps(row) for row in self.entry[role]]+self.logs[role]
            lines += [marker+json.dumps(row) for marker, row in self.rows[role]]
            (self.profile/(role+'-launch.log')).write_text('\n'.join(lines)+'\n')
        path = self.profile/'client1/inventory-equip-native.jsonl'; path.parent.mkdir(exist_ok=True)
        path.write_text('\n'.join(json.dumps(row) for row in self.native)+'\n')

    def analyze(self, life=None):
        self.write(); return API['analyze'](self.profile, life)

    def driver(self, event):
        return next(row for row in self.entry['client1'] if row['event'] == event)

    def test_one_actual_inventory_entry_precedes_all_role_fresh_baselines_and_world_cycles(self):
        result = self.analyze()
        self.assertIs(result['evidenceComplete'], True)
        self.assertIs(result['diagnosticOnly'], True)
        self.assertEqual(result['ownerMenuActions'], 1)
        self.assertEqual(result['completedNativeCycles'], 6)
        self.assertEqual(result['nativeActionID'], 5)
        self.assertEqual(result['nativeTransactionID'], 3)
        self.assertEqual(result['token'], TOKEN)
        self.assertEqual(result['heldEndpointRoles'], ['server','client1','client2'])
        self.assertNotIn('animationEquivalencePass', result)
        for text in ('No repeated inventory return', 'ground Grab', 'native action-admission classifier', 'wire budget'):
            self.assertIn(text, result['qualification'])

    def test_preverified_lifetime_result_has_same_entry_evidence(self):
        expected = self.analyze()
        life = API['LIFE']['analyze'](self.profile)
        self.assertEqual(self.analyze(life), expected)
        for mutation in (dict(evidenceComplete=False), dict(menu=False), dict(completedNativeCycles=5),
                         dict(ownerID=8), dict(cartID=43), dict(cycles=[])):
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                self.analyze(dict(life, **mutation))

    def test_signed_nonzero_native_transaction_is_joined_without_inventing_unsigned_identity(self):
        for row in self.native:
            if row.get('event') == 'lifecycle': row['transactionId'] = -128
        for event in ('start','terminal'): self.driver(event)['transaction'] = -128
        self.assertEqual(self.analyze()['nativeTransactionID'], -128)

    def test_queue_before_native_creation_preserves_real_adjusted_start_duration(self):
        queued = self.driver('queued')
        self.assertNotIn('localNativeEpoch', queued)
        self.assertNotIn('nativeMaxTime', queued)
        self.assertEqual(queued['luaMaxTime'], 30)
        self.assertEqual(self.driver('start')['luaMaxTime'], 30.003)
        self.assertIs(self.analyze()['evidenceComplete'], True)
        queued.update(localNativeEpoch=4, nativeMaxTime=30, luaMaxTime=30.003)
        self.assertIs(self.analyze()['evidenceComplete'], True)

    def test_started_native_duration_and_adjustment_cannot_be_changed_or_borrowed_from_queue(self):
        original = copy.deepcopy(self.entry)
        for event in ('start','terminal'):
            for field,value in (('nativeMaxTime',31), ('luaMaxTime',30), ('luaMaxTime',30.004)):
                self.entry = copy.deepcopy(original);self.driver(event)[field]=value
                with self.subTest(event=event,field=field,value=value),self.assertRaises(ValueError):self.analyze()
        self.entry = copy.deepcopy(original)
        for event in ('start','terminal'):self.driver(event)['luaMaxTime']=30
        with self.assertRaisesRegex(ValueError,'native lifecycle changed adjusted Lua duration'):self.analyze()
        for field in ('localNativeEpoch','nativeMaxTime'):
            self.entry = copy.deepcopy(original);self.driver('queued')[field]=4 if field=='localNativeEpoch' else 30
            with self.subTest(field=field),self.assertRaisesRegex(ValueError,'observed together'):self.analyze()

    def test_selection_requires_exact_initial_entry_bank_and_real_booleans(self):
        original = copy.deepcopy(self.selection)
        for key in ('cart_lease_inventory','cart_lease_menu','cart_lease_lifetimes','cart_lease_control',
                    'cart_timeline','cart_fast_motion','mp_host'):
            for value in (False, 1, 'true', None):
                self.selection = copy.deepcopy(original); self.selection['options'][key] = value
                with self.subTest(key=key,value=value), self.assertRaises(ValueError): self.analyze()
        for key, value in (('cart_inventory_equip',True), ('cart_actions',True), ('cart_hotkey_setdown',True),
                           ('cart_action_admission',True), ('cart_observer_association',True),
                           ('cart_time_alignment',True), ('cart_wall_exit','front'), ('cart_variant','shopping-cart')):
            self.selection = copy.deepcopy(original); self.selection['options'][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): self.analyze()

    def test_missing_duplicate_and_reordered_entry_stages_fail_closed(self):
        original = copy.deepcopy(self.entry)
        for role in API['ROLES']:
            for index in range(len(original[role])):
                for duplicate in (False, True):
                    self.entry = copy.deepcopy(original)
                    if duplicate:self.entry[role].insert(index, copy.deepcopy(self.entry[role][index]))
                    else:self.entry[role].pop(index)
                    with self.subTest(role=role,index=index,duplicate=duplicate), self.assertRaises(ValueError):
                        self.analyze()
        self.entry = copy.deepcopy(original)
        self.entry['client1'][1],self.entry['client1'][2] = self.entry['client1'][2],self.entry['client1'][1]
        with self.assertRaises(ValueError):self.analyze()

    def test_foreign_endpoint_phase_actor_and_unguarded_server_are_refused(self):
        original = copy.deepcopy(self.entry)
        for role in API['ROLES']:
            for field,value in (('actor','foreign'), ('phase',1), ('phase',False), ('owner',8), ('cart',43),
                                ('cargoID',314), ('cargoWeight',29), ('primaryID',-1), ('handSameItem',False),
                                ('worldAttached',True), ('worldCount',1), ('nativeActions',1), ('hasPath',True)):
                self.entry = copy.deepcopy(original); self.entry[role][-1][field] = value
                with self.subTest(role=role,field=field), self.assertRaises(ValueError):self.analyze()
        for event in ('unheld','held'):
            self.entry = copy.deepcopy(original)
            next(row for row in self.entry['server'] if row['event']==event)['guarded'] = False
            with self.subTest(event=event), self.assertRaises(ValueError):self.analyze()

    def test_observer_never_claims_owner_inventory_or_remote_lua_queue(self):
        original = copy.deepcopy(self.entry)
        for field,value in (('inventoryCount',1), ('luaActions',0), ('inventoryScope','owner-inventory'),
                            ('queueScope','owner-local')):
            self.entry = copy.deepcopy(original); self.entry['client2'][0][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):self.analyze()
        for role,field,value in (('server','luaActions',0), ('server','queueScope','owner-local'),
                                 ('client1','luaActions',1), ('client1','inventoryCount',2),
                                 ('server','inventoryCount',0)):
            self.entry = copy.deepcopy(original); self.entry[role][-1][field] = value
            with self.subTest(role=role,field=field), self.assertRaises(ValueError):self.analyze()

    def test_initial_cart_is_unheld_in_inventory_on_both_authoritative_roles(self):
        original = copy.deepcopy(self.entry)
        for role in ('server','client1'):
            for field,value in (('primaryID',42), ('secondaryID',42), ('handSameItem',True),
                                ('inventoryCount',0), ('worldAttached',True)):
                self.entry = copy.deepcopy(original); self.entry[role][0][field] = value
                with self.subTest(role=role,field=field), self.assertRaises(ValueError):self.analyze()

    def test_initial_baseline_cannot_precede_actual_inventory_held_endpoint(self):
        self.write(); life = API['LIFE']['analyze'](self.profile)
        original_rows,original_entry = copy.deepcopy(self.rows),copy.deepcopy(self.entry)
        for role in API['ROLES']:
            self.rows,self.entry = copy.deepcopy(original_rows),copy.deepcopy(original_entry)
            baseline = self.rows[role].pop(0)
            self.write()
            path = self.profile/(role+'-launch.log'); lines = path.read_text().splitlines()
            held = next(i for i,line in enumerate(lines) if MARKER in line and '"event": "held"' in line)
            lines.insert(held, baseline[0]+json.dumps(baseline[1])); path.write_text('\n'.join(lines)+'\n')
            with self.subTest(role=role), self.assertRaisesRegex(ValueError,'baseline.*after actual'):
                API['analyze'](self.profile, life)

    def test_held_endpoint_must_precede_ordinary_motion_start_for_each_role(self):
        original = copy.deepcopy(self.entry)
        for role in API['ROLES']:
            self.entry = copy.deepcopy(original); self.write()
            path = self.profile/(role+'-launch.log'); lines = path.read_text().splitlines()
            held = next(i for i,line in enumerate(lines) if MARKER in line and '"event": "held"' in line)
            row = lines.pop(held); start = next(i for i,line in enumerate(lines) if '[CART_MP] START epoch=' in line)
            lines.insert(start+1,row); path.write_text('\n'.join(lines)+'\n')
            with self.subTest(role=role), self.assertRaisesRegex(ValueError,'precede ordinary motion START'):
                API['analyze'](self.profile)

    def test_client_held_endpoint_must_precede_first_exact_armed_even_before_start(self):
        for role in ('client1','client2'):
            for defect in ('late-held','missing-armed','foreign-armed'):
                self.write()
                path = self.profile/(role+'-launch.log'); lines = path.read_text().splitlines()
                armed = next(i for i,line in enumerate(lines) if '[CART_MP] ARMED ' in line)
                if defect == 'late-held':
                    held = next(i for i,line in enumerate(lines) if MARKER in line and '"event": "held"' in line)
                    row = lines.pop(held)
                    armed = next(i for i,line in enumerate(lines) if '[CART_MP] ARMED ' in line)
                    lines.insert(armed+1,row)
                    start = next(i for i,line in enumerate(lines) if '[CART_MP] START epoch=' in line)
                    self.assertLess(armed+1,start)
                elif defect == 'missing-armed':lines.pop(armed)
                else:lines[armed]=lines[armed].replace('ARMED '+role,'ARMED foreign')
                path.write_text('\n'.join(lines)+'\n')
                with self.subTest(role=role,defect=defect),self.assertRaisesRegex(ValueError,'first exact local ARMED'):
                    API['analyze'](self.profile)

    def test_exact_inventory_action_source_duration_and_operation_are_required(self):
        original = copy.deepcopy(self.entry)
        for event in ('queued','start','terminal'):
            for field,value in (('kind','pickup'), ('actionType','ISGrabItemAction'), ('sourceType','ground'),
                                ('duration',1), ('nativeMaxTime',31), ('luaMaxTime',float('nan')),
                                ('localActionEpoch',True), ('localSourceEpoch',0), ('operation',0), ('source',''),
                                ('owner',8), ('generation',-1)):
                self.entry = copy.deepcopy(original); self.driver(event)[field] = value
                with self.subTest(event=event,field=field), self.assertRaises(ValueError):self.analyze()
        for field,value in (('operation',99), ('generation',1), ('localActionEpoch',99), ('source','other'),
                            ('localSourceEpoch',99), ('luaMaxTime',30.004)):
            self.entry = copy.deepcopy(original); self.driver('terminal')[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):self.analyze()

    def test_start_and_completion_require_same_actual_sealed_uuid_native_transaction(self):
        original = copy.deepcopy(self.entry)
        for event in ('start','terminal'):
            for field,value in (('sealed',False), ('state','canceled'), ('token','not-a-native-uuid'),
                                ('transaction',0), ('transaction',128), ('transaction',True), ('localNativeEpoch',0)):
                self.entry = copy.deepcopy(original); self.driver(event)[field] = value
                with self.subTest(event=event,field=field), self.assertRaises(ValueError):self.analyze()
        for field,value in (('token','00000000-0000-4000-8000-000000000098'), ('transaction',4), ('localNativeEpoch',5)):
            self.entry = copy.deepcopy(original); self.driver('terminal')[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):self.analyze()

    def test_canonical_native_registration_done_and_measured_progress_cannot_be_forged(self):
        original = copy.deepcopy(self.native)
        for field,value in (('id',43), ('ownerID',8), ('actionType','ToolkitWoodCartPickup'), ('sourceType','ground'),
                            ('maxTime',31), ('luaMaxTime',30.004), ('luaCharacterExact',False), ('threw',True),
                            ('forceStop',True), ('networkRejected',True), ('local',False), ('producer','foreign')):
            self.native = copy.deepcopy(original)
            for row in self.native:
                if row.get('event') == 'lifecycle':row[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):self.analyze()
        for method,stage,field,value in (('start','exit','networkActionExact',False),
                                        ('start','exit','networkActionPresent',False),
                                        ('start','exit','networkActionType','ISCartPickupAction'),
                                        ('update','exit','networkDone',False),
                                        ('perform','exit','forceComplete',False),
                                        ('perform','exit','progress',.9)):
            self.native = copy.deepcopy(original)
            next(row for row in self.native if row.get('method')==method and row.get('stage')==stage)[field]=value
            with self.subTest(method=method,field=field), self.assertRaises(ValueError):self.analyze()

    def test_exact_native_transaction_and_single_action_id_join_the_driver(self):
        original = copy.deepcopy(self.native)
        for field,value in (('transactionId',4), ('actionId',6)):
            self.native = copy.deepcopy(original)
            selected = [row for row in self.native if row.get('event')=='lifecycle']
            for row in selected if field=='transactionId' else selected[-1:]:row[field]=value
            with self.subTest(field=field), self.assertRaises(ValueError):self.analyze()
        self.native = copy.deepcopy(original)
        self.native.extend(copy.deepcopy(row) for row in original if row.get('event')=='lifecycle')
        with self.assertRaises(ValueError):self.analyze()

    def test_native_file_errors_and_unknown_boundaries_cannot_hide_behind_valid_action(self):
        original = copy.deepcopy(self.native)
        for event in ('error', 'invented-body'):
            self.native = copy.deepcopy(original)
            self.native.append(dict(producer=API['EQUIP']['NATIVE'], actor='client1', event=event, wall=4000))
            with self.subTest(event=event), self.assertRaises(ValueError):self.analyze()
        for field,value in (('method','invented-callback'), ('stage','invented-stage')):
            self.native = copy.deepcopy(original)
            next(row for row in self.native if row.get('method')=='update')[field]=value
            with self.subTest(field=field), self.assertRaises(ValueError):self.analyze()

    def test_queued_native_epoch_cannot_change_and_boolean_transaction_cannot_alias_one(self):
        self.driver('queued')['nativeMaxTime']=30
        self.driver('queued')['localNativeEpoch']=5
        with self.assertRaisesRegex(ValueError,'queued native action'):self.analyze()
        self.driver('queued')['localNativeEpoch']=4
        for row in self.native:
            if row.get('event')=='lifecycle':row['transactionId']=1
        self.driver('start')['transaction']=1;self.driver('terminal')['transaction']=1
        self.assertIs(self.analyze()['evidenceComplete'],True)
        self.driver('terminal')['transaction']=True
        with self.assertRaises(ValueError):self.analyze()
        self.driver('terminal')['transaction']=1
        next(row for row in self.native if row.get('method')=='update')['transactionId']=True
        with self.assertRaises(ValueError):self.analyze()

    def test_no_early_force_completion_or_canceled_native_path_is_accepted(self):
        original = copy.deepcopy(self.native)
        self.native = copy.deepcopy(original)
        next(row for row in self.native if row.get('method')=='update')['forceComplete']=True
        with self.assertRaisesRegex(ValueError,'forced before'):self.analyze()
        self.native = copy.deepcopy(original)
        for row in self.native:
            if row.get('method')=='update':row['progress']=1
        with self.assertRaisesRegex(ValueError,'measured progress'):self.analyze()
        self.native = copy.deepcopy(original)
        next(row for row in self.native if row.get('method')=='perform')['method']='stop'
        with self.assertRaisesRegex(ValueError,'cancelled'):self.analyze()

    def test_cli_reads_capture_without_rewriting_sources_or_claiming_animation(self):
        self.write();before={p.relative_to(self.profile):p.read_bytes() for p in self.profile.rglob('*') if p.is_file()}
        result = subprocess.run([sys.executable,str(SOURCE),'--profile',str(self.profile)],text=True,capture_output=True,timeout=15)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIs(json.loads(result.stdout)['evidenceComplete'],True)
        self.assertEqual(before,{p.relative_to(self.profile):p.read_bytes() for p in self.profile.rglob('*') if p.is_file()})


if __name__ == '__main__':unittest.main()
