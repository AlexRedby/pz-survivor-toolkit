"""Exact accepted world-loss retirement, genuine cancellation and fresh receipt joins."""
import copy
import json
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'tests/native_queue/contributions/wooden_cart_multiplayer/analyze-action-invalidation.py'
API = runpy.run_path(str(SOURCE))
SERVER = '00000000-0000-4000-8000-000000000001'
MARKER, NATIVE = API['MARKER'], API['NATIVE']


def fixture():
    selection = dict(suite='wooden_cart_multiplayer', kind='mp', mode='toolkit',
        cases=['owner_observer_motion'], options=dict(cart_action_invalidation=True, mp_host=True,
                                                     cart_timeline=True, cart_fast_motion=True))
    logs = {role: [] for role in API['ROLES']}
    specs = dict(variant='wooden-wheelbarrow', cartType='SaucedWheelbarrow.WheelbarrowWood',
                 id=42, cargoCount=1, cargoID=43, cargoWeight=7.5)
    logs['server'].append(('[CART_MP] CART_SPEC ', specs))
    native = {}
    for phase in (1, 2, 3):
        wall = 126000+phase*2000
        kind = API['KINDS'][phase]
        token = '10000000-0000-4000-8000-'+str(phase).zfill(12)
        record = dict(protocol=1, process=SERVER, sourceSession=SERVER+':21:99999', owner=7,
            actorEpoch=11, connectionEpoch=21, startGeneration=phase*10, actionEpoch=100+phase,
            tableEpoch=200+phase, token=None, transaction=phase, kind=kind, cart=42,
            itemEpoch=301, worldEpoch=400+phase if phase>1 else 0, stage='pending',
            reason='native-request-start', nativeState='Request', nativeBindingValid=True,
            admittedBindingValid=False, accepted=False, sourceValidated=True, tokenObserved=False,
            ingressGeneration=500+phase, parseGeneration=600+phase, packetType=166,
            monoNs=wall*1000000, wallMs=wall)
        pending = dict(record, event='pending')
        accepted = dict(record, event='accepted', stage='accepted', reason='native-accepted',
            nativeState='Accept', admittedBindingValid=True, accepted=True, tokenObserved=True,
            token=token, monoNs=(wall+1)*1000000, wallMs=wall+1)
        retired = dict(accepted, event='retired', stage='terminal', nativeBindingValid=False,
            reason='item-invalid' if phase==2 else 'completed', nativeState='Accept' if phase==2 else 'Done',
            monoNs=(wall+500)*1000000, wallMs=wall+500)
        native[phase] = dict(pending=pending, accepted=accepted, retired=retired)

    def emit(role, event, phase, wall, **fields):
        row = dict(actor=role, event=event, phase=phase, owner=7, cart=42, wall=wall)
        row.update(fields); logs[role].append((MARKER, row)); return row

    def endpoint(role, event, phase, wall, held):
        values = dict(state='held' if held else 'ground', cargoID=43, cargoWeight=7.5,
            primaryID=42 if held else -1, secondaryID=42 if held else -1, handSameItem=held,
            worldAttached=not held, worldCount=0 if held else 1, nativeActions=0, hasPath=False,
            inventoryScope='remote-hand-snapshot' if role=='client2' else 'owner-inventory',
            queueScope={'server':'native-server-only','client1':'owner-local','client2':'remote-native-only'}[role],
            guarded=role=='server')
        if role!='client2': values['inventoryCount'] = 1 if held else 0
        if role=='client1': values['luaActions'] = 0
        return emit(role,event,phase,wall,**values)

    for role in API['ROLES']: endpoint(role,'init',0,126001,True)
    for phase in (1, 2, 3):
        wall = 126000+phase*2000
        for stage in ('pending', 'accepted'):
            logs['server'].append((NATIVE,native[phase][stage]))
        if phase==2:
            values = {key:value for key,value in native[phase]['accepted'].items() if key!='event'}
            emit('server','accepted',2,wall+10,guarded=True,**values)
            emit('server','mutation',2,wall+500,oldWorldEpoch=402,worldReplaced=True,oldWorldRemoved=True,
                 oldX=10,oldY=20,newX=12,newY=20,cargoID=43,cargoWeight=7.5)
        elif phase==3:
            values = {key:value for key,value in native[phase]['accepted'].items() if key!='event'}
            emit('server','fresh-accepted',3,wall+10,guarded=True,**values)
        logs['server'].append((NATIVE,native[phase]['retired']))
        if phase==2:
            values = {key:value for key,value in native[phase]['retired'].items() if key!='event'}
            emit('server','retired',2,wall+501,guarded=True,currentAuthority=False,**values)
        event = {1:'ground',2:'invalid-ground',3:'recovered'}[phase]
        endpoint('server',event,phase,wall+700,phase==3)

        common = dict(kind='release' if phase==1 else 'pickup', actionType=API['KINDS'][phase],
            queuedSource=API['KINDS'][phase], localActionEpoch=700+phase, localSourceEpoch=701,
            operation=900+phase, generation=1 if phase==3 else 0, source='connection@21')
        emit('client1','menu-queued',phase,wall,**common)
        start = dict(common,localNativeEpoch=800+phase,token=native[phase]['accepted']['token'],
                     transaction=phase,state='started',sealed=True)
        emit('client1','menu-start',phase,wall+2,**start)
        if phase==2:
            emit('client1','native-terminal',2,wall+600,protocol=1,player=7,token=start['token'],
                 transaction=2,kind=API['KINDS'][2],state='canceled',guarded=True,sealed=False,currentAuthority=False)
            endpoint('client1',event,phase,wall+700,False)
            emit('client1','invalidated',2,wall+700,token=start['token'],transaction=2,kind=API['KINDS'][2],
                 observation='unavailable',currentAuthority=False,captureUnavailable=True,stateUnavailable=True)
        else:
            if phase==3:
                for duplicate in (1,2):
                    emit('client1','stale-terminal-refused',3,wall+10+duplicate,
                        oldToken=native[2]['accepted']['token'],oldTransaction=2,token=start['token'],
                        transaction=3,kind=API['KINDS'][3],duplicate=duplicate,guarded=True,sealed=True,
                        currentAuthority=True,queueUnchanged=True,oldCaptureUnavailable=True,
                        oldStateUnavailable=True,oldObservation='unavailable')
            final = dict(start,state='completed')
            emit('client1','menu-terminal',phase,wall+600,**final)
            endpoint('client1',event,phase,wall+700,phase==3)
        endpoint('client2',event,phase,wall+800,phase==3)
    for role in API['ROLES']: endpoint(role,'complete',3,133000,True)
    return selection, logs, native


class AcceptedActionInvalidationEvidence(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.profile = Path(self.temp.name)
        self.selection, self.logs, self.native = fixture()

    def rows(self,role,event,phase=None):
        return [row for marker,row in self.logs[role] if marker==MARKER and row.get('event')==event
                and (phase is None or row.get('phase')==phase)]

    def row(self,role,event,phase=None):
        return self.rows(role,event,phase)[0]

    def write(self):
        (self.profile/'selection.json').write_text(json.dumps(self.selection))
        for role, rows in self.logs.items():
            lines = ['[CART_MP] START epoch=100000']
            if role=='client1':
                lines.append('[CART_MP_STATE] '+json.dumps(dict(id=7,user='client1',wall=100001,primary=42,secondary=42)))
            lines += [marker+json.dumps(row) for marker,row in rows]
            (self.profile/(role+'-launch.log')).write_text('\n'.join(lines)+'\n')

    def analyze(self):
        self.write();return API['analyze'](self.profile)

    def reset(self):
        self.selection,self.logs,self.native = fixture()

    def test_exact_world_loss_cancellation_and_fresh_receipt_pass(self):
        result = self.analyze()
        self.assertTrue(result['evidenceComplete'])
        self.assertEqual(result['nativeLifetimes'],3)
        self.assertEqual(result['invalidatedAcceptedActions'],1)
        self.assertEqual(result['historicalTerminalReplaysRefused'],2)
        self.assertEqual(result['completedNativeActions'],2)
        self.assertEqual(result['phases'][1]['nativeRetirementReason'],'item-invalid')
        self.assertEqual(result['phases'][1]['nativeTerminalState'],'Accept')
        self.assertEqual(result['phases'][1]['ownerNativeReceiptOutcome'],'canceled')
        self.assertIsNone(result['phases'][1]['ownerSealedOutcome'])
        self.assertIn('explicitly stopped',result['qualification'])
        self.assertIn('No spontaneous native Reject',result['qualification'])

    def test_selection_is_explicit_and_separate_from_legacy_banks(self):
        for flag in ('cart_action_invalidation','mp_host','cart_timeline','cart_fast_motion'):
            for value in (False,1,'true',None):
                self.reset();self.selection['options'][flag]=value
                with self.subTest(flag=flag,value=value),self.assertRaises(ValueError):self.analyze()
        for flag in ('cart_actions','cart_action_admission','cart_lease_control','cart_lease_lifetimes',
                     'cart_lease_menu','cart_lease_inventory','cart_inventory_equip','cart_time_alignment',
                     'cart_hotkey_setdown','cart_observer_association'):
            self.reset();self.selection['options'][flag]=True
            with self.subTest(flag=flag),self.assertRaises(ValueError):self.analyze()

    def test_native_lifecycle_cannot_omit_duplicate_or_resurrect_after_retirement(self):
        for event in ('pending','accepted','retired'):
            for duplicate in (False,True):
                self.reset();entry=(NATIVE,self.native[2][event])
                if duplicate:self.logs['server'].append(copy.deepcopy(entry))
                else:self.logs['server'].remove(entry)
                with self.subTest(event=event,duplicate=duplicate),self.assertRaises(ValueError):self.analyze()
        self.reset();extra=copy.deepcopy(self.native[2]['accepted']);extra['event']='accepted'
        self.logs['server'].append((NATIVE,extra))
        with self.assertRaisesRegex(ValueError,'Duplicate native'):self.analyze()

    def test_native_identity_source_and_parse_binding_are_frozen(self):
        for field,value in (('owner',8),('cart',99),('actorEpoch',99),('connectionEpoch',99),('itemEpoch',99),
                            ('worldEpoch',99),('actionEpoch',99),('tableEpoch',99),('startGeneration',99),
                            ('parseGeneration',99),('ingressGeneration',99),('packetType',99),('transaction',99)):
            self.reset();self.native[2]['retired'][field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()

    def test_missing_or_foreign_fixture_and_native_stages_fail(self):
        for role in API['ROLES']:
            for marker,row in fixture()[1][role]:
                if marker!=MARKER:continue
                self.reset();target=next(entry for entry in self.logs[role]
                    if entry[0]==MARKER and entry[1]['event']==row['event'] and entry[1]['phase']==row['phase'])
                self.logs[role].remove(target)
                with self.subTest(role=role,event=row['event']),self.assertRaises(ValueError):self.analyze()
        self.reset();self.logs['client2'].append((NATIVE,copy.deepcopy(self.native[2]['accepted'])))
        with self.assertRaisesRegex(ValueError,'foreign endpoint'):self.analyze()
        self.reset();self.row('client1','menu-start',2)['actor']='client2'
        with self.assertRaisesRegex(ValueError,'foreign/unknown'):self.analyze()

    def test_world_loss_requires_exact_world_object_real_move_and_same_cargo(self):
        for field,value in (('oldWorldEpoch',999),('worldReplaced',False),('oldWorldRemoved',False),
                            ('newX',10),('cargoID',44),('cargoWeight',8.5),('oldX',True),('newY',float('inf'))):
            self.reset();self.row('server','mutation',2)[field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()

    def test_phase2_never_claims_completion_and_retires_for_exact_world_loss(self):
        for field,value in (('reason','completed'),('nativeState','Done'),('reason','native-remove'),
                            ('nativeBindingValid',True),('accepted',False),('admittedBindingValid',False)):
            self.reset();self.native[2]['retired'][field]=value;self.row('server','retired',2)[field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()
        self.reset();extra=copy.deepcopy(self.row('client1','menu-terminal',3));extra['phase']=2
        self.logs['client1'].append((MARKER,extra))
        with self.assertRaises(ValueError):self.analyze()

    def test_genuine_owner_cancellation_is_distinct_from_retired_admission(self):
        for field,value in (('state','completed'),('state','rejected'),('token',self.native[1]['accepted']['token']),
                            ('transaction',3),('player',8),('protocol',True),('guarded',False),
                            ('sealed',True),('currentAuthority',True)):
            self.reset();self.row('client1','native-terminal',2)[field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()

    def test_old_receipt_capture_state_and_observation_cannot_heal(self):
        for event in ('invalidated','stale-terminal-refused'):
            fields = ('captureUnavailable','stateUnavailable') if event=='invalidated' else ('oldCaptureUnavailable','oldStateUnavailable')
            for field in fields:
                self.reset();self.row('client1',event)[field]=False
                with self.subTest(event=event,field=field),self.assertRaises(ValueError):self.analyze()
            for observation in ('started','completed',True,None):
                self.reset();self.row('client1',event)['observation' if event=='invalidated' else 'oldObservation']=observation
                with self.subTest(event=event,observation=observation),self.assertRaises(ValueError):self.analyze()

    def test_fresh_action_cannot_reuse_native_local_table_world_or_token_identity(self):
        for field in ('actionEpoch','tableEpoch','worldEpoch','token'):
            self.reset();value=self.native[2]['accepted'][field]
            for row in self.native[3].values():
                if field!='token' or row['tokenObserved']:row[field]=value
            self.row('server','fresh-accepted',3)[field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()
        for field in ('localActionEpoch','localNativeEpoch','operation'):
            self.reset();value=self.row('client1','menu-start',2)[field]
            for event in ('menu-queued','menu-start','menu-terminal'):
                if field in self.row('client1',event,3):self.row('client1',event,3)[field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()

    def test_replays_bind_exact_old_and_fresh_receipts_during_fresh_start(self):
        for field,value in (('oldToken',self.native[1]['accepted']['token']),('oldTransaction',3),
                            ('token',self.native[2]['accepted']['token']),('transaction',2),
                            ('guarded',False),('queueUnchanged',False),('sealed',False),('currentAuthority',False),
                            ('duplicate',True),('duplicate',3)):
            self.reset();self.row('client1','stale-terminal-refused')[field]=value
            with self.subTest(field=field,value=value),self.assertRaises(ValueError):self.analyze()
        self.reset();entry=next(value for value in self.logs['client1'] if value[1].get('event')=='stale-terminal-refused')
        self.logs['client1'].remove(entry);self.logs['client1'].append(entry)
        with self.assertRaises(ValueError):self.analyze()

    def test_endpoint_cargo_duplicates_queues_and_observer_authority_fail_closed(self):
        for role in API['ROLES']:
            for field,value in (('cargoID',99),('cargoWeight',8),('primaryID',99),('handSameItem',False),
                                ('worldCount',1),('worldAttached',True),('nativeActions',1),('hasPath',True)):
                self.reset();self.row(role,'recovered',3)[field]=value
                with self.subTest(role=role,field=field),self.assertRaises(ValueError):self.analyze()
        for field,value in (('inventoryCount',1),('luaActions',0),('inventoryScope','owner-inventory'),('queueScope','owner-local')):
            self.reset();self.row('client2','recovered',3)[field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()
        self.reset();self.row('server','recovered',3)['guarded']=False
        with self.assertRaises(ValueError):self.analyze()

    def test_native_and_owner_guards_use_actual_json_boolean_integer_types(self):
        for field in ('accepted','sourceValidated','nativeBindingValid','admittedBindingValid','tokenObserved'):
            self.reset();self.native[2]['accepted'][field]=1
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()
        for role,event,field in (('server','mutation','oldWorldEpoch'),('client1','menu-start','transaction'),
                                ('client1','menu-start','localNativeEpoch'),('client2','recovered','worldCount')):
            for value in (True,1.0):
                self.reset();self.row(role,event)[field]=value
                with self.subTest(field=field,value=value),self.assertRaises(ValueError):self.analyze()

    def test_post_motion_and_native_mutation_order_are_required(self):
        self.row('client1','init',0)['wall']=125999
        with self.assertRaisesRegex(ValueError,'precedes motion'):self.analyze()
        self.reset();accepted=self.row('server','accepted',2);mutation=self.row('server','mutation',2)
        a=self.logs['server'].index((MARKER,accepted));b=self.logs['server'].index((MARKER,mutation))
        accepted['wall']=mutation['wall'];self.logs['server'][a],self.logs['server'][b]=self.logs['server'][b],self.logs['server'][a]
        with self.assertRaisesRegex(ValueError,'barrier reordered'):self.analyze()

    def test_signed_transaction_byte_is_not_a_unique_lifecycle_identity(self):
        for rows in self.logs.values():
            for _,row in rows:
                if 'transaction' in row:row['transaction']=-128
                if 'oldTransaction' in row:row['oldTransaction']=-128
        self.assertTrue(self.analyze()['evidenceComplete'])
        self.assertEqual({row['transaction'] for row in self.analyze()['phases']},{-128})

    def test_cli_and_duplicate_nonfinite_json_fail_closed(self):
        self.write()
        result=subprocess.run([sys.executable,str(SOURCE),'--profile',str(self.profile)],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertTrue(json.loads(result.stdout)['evidenceComplete'])
        file=self.profile/'client1-launch.log'
        file.write_text(file.read_text().replace('"actor": "client1"','"actor": "client1", "actor": "client1"',1))
        with self.assertRaisesRegex(ValueError,'Duplicate JSON key'):API['analyze'](self.profile)
        self.write();file.write_text(file.read_text().replace('7.5','NaN',1))
        with self.assertRaisesRegex(ValueError,'Nonfinite JSON'):API['analyze'](self.profile)


if __name__=='__main__':unittest.main()
