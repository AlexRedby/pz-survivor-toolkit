"""Exact native start/token/owner receipt evidence joins, with adversarial trace edits."""
import copy
import json
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'tests/native_queue/contributions/wooden_cart_multiplayer/analyze-action-admission.py'
API = runpy.run_path(str(SOURCE))
SERVER = '00000000-0000-4000-8000-000000000001'
OWNER = '00000000-0000-4000-8000-000000000002'
PHASES = API['PHASES']
MARKERS = dict(native='[CART_ADMISSION] ',owner='[CART_ADMISSION_OWNER] ',query='[CART_ADMISSION_QUERY] ')


def fixture():
    selection = dict(suite='wooden_cart_multiplayer',kind='mp',mode='toolkit',cases=['owner_observer_motion'],
                     options=dict(mp_host=True,cart_actions=True,cart_action_admission=True))
    base = {role:['[CART_MP] START epoch=100000'] for role in ('server','client1','client2')}
    base['client1'].append('[CART_MP_STATE] '+json.dumps(dict(id=7,user='client1',wall=100000,primary=42,secondary=42)))
    groups = dict(native=[],owner=[],query=[])
    for index,phase in enumerate(PHASES,1):
        cancel = index in (3,5)
        kind = 'ToolkitWoodCartPickup' if phase.startswith('pickup') else 'ToolkitWoodCartSetdown'
        token = '10000000-0000-4000-8000-'+str(index).zfill(12)
        wall = 116000+index*2000
        base['client1'].append('[CART_MP_ACTION] BEGIN '+json.dumps(dict(index=index,phase=phase,id=42,
            actor='client1',cancel=cancel,wall=wall)))
        record = dict(protocol=1,process=SERVER,sourceSession=SERVER+':21:99999',owner=7,
            actorEpoch=11,connectionEpoch=21,startGeneration=index*10,actionEpoch=100+index,tableEpoch=200+index,
            token=None,transaction=index,kind=kind,cart=42,itemEpoch=301,worldEpoch=400+index if kind.endswith('Pickup') else 0,
            stage='pending',reason='native-request-start',nativeState='Request',nativeBindingValid=True,
            admittedBindingValid=False,accepted=False,sourceValidated=True,tokenObserved=False,
            ingressGeneration=500+index,parseGeneration=600+index,packetType=166,monoNs=wall*1000000,wallMs=wall)
        pending = dict(record,event='pending')
        accepted = dict(record,event='accepted',stage='accepted',reason='native-accepted',nativeState='Accept',
                        admittedBindingValid=True,accepted=True,tokenObserved=True,token=token,
                        monoNs=(wall+1)*1000000,wallMs=wall+1)
        retired = dict(accepted,event='retired',stage='terminal',nativeState='Accept' if cancel else 'Done',
            reason='native-remove' if cancel else 'completed',nativeBindingValid=cancel,
            monoNs=(wall+1000)*1000000,wallMs=wall+1000)
        groups['native'] += [pending,accepted,retired]
        owner = dict(actor='client1',ownerProcess=OWNER,owner=7,index=index,phase=phase,cart=42,
                     localActionEpoch=700+index,wallMs=wall)
        track = dict(owner,event='track')
        capture = dict(owner,event='capture',localNativeEpoch=800+index,token=token,transaction=index,
                       kind=kind,state='started',sealed=True,wallMs=wall+2)
        nonce = OWNER+':action:'+str(index)
        query = dict(capture,event='query',nonce=nonce,guarded=True,wallMs=wall+3)
        query.pop('state');query.pop('sealed')
        server_query = dict(accepted,event='query',actor='server',index=index,phase=phase,nonce=nonce,guarded=True,
                            monoNs=(wall+4)*1000000,wallMs=wall+4)
        reply = dict(query,**{key:value for key,value in server_query.items() if key not in ('actor','event')})
        reply.update(event='reply',actor='client1',sealed=True,guarded=True,wallMs=wall+5)
        terminal = dict(capture,event='terminal',state='canceled' if cancel else 'completed',wallMs=wall+1001)
        groups['query'].append(server_query)
        groups['owner'] += [track,capture,query,reply,terminal]
    return selection,base,groups


class NativeActionAdmissionEvidence(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.profile = Path(self.temp.name)
        self.selection,self.base,self.groups = fixture()

    def records(self,group,event):
        return [row for row in self.groups[group] if row['event']==event]

    def write(self):
        (self.profile/'selection.json').write_text(json.dumps(self.selection))
        for role in ('server','client1','client2'):
            lines = self.base[role][:]
            for group in (('native','query') if role=='server' else ('owner',) if role=='client1' else ()):
                lines += [MARKERS[group]+json.dumps(row) for row in self.groups[group]]
            (self.profile/(role+'-launch.log')).write_text('\n'.join(lines)+'\n')

    def analyze(self):
        self.write();return API['analyze'](self.profile)

    def test_complete_exact_owner_associations_preserve_separate_terminal_facts(self):
        result = self.analyze()
        self.assertTrue(result['evidenceComplete'])
        self.assertEqual(result['exactOwnerAssociations'],6)
        self.assertEqual(result['nativeLifetimes'],6)
        self.assertEqual(result['logicalQueryMessages'],dict(total=12,clientToServer=6,serverToClient=6))
        canceled = [row for row in result['phases'] if row['ownerSealedOutcome']=='canceled']
        self.assertEqual([row['phase'] for row in canceled],['drop-cancel','pickup-cancel'])
        self.assertEqual({row['nativeTerminalState'] for row in canceled},{'Accept'})
        self.assertEqual({row['nativeRetirementReason'] for row in canceled},{'native-remove'})
        self.assertIn('No observer skeleton/proxy binding',result['qualification'])
        self.assertIn('runtime PASS',result['qualification'])
        self.assertNotIn('nativeCancellationSuccess',result)

    def test_query_after_retirement_keeps_frozen_admission_proof(self):
        for index in range(6):
            retired = self.records('native','retired')[index]
            for row in (self.groups['query'][index],self.records('owner','reply')[index]):
                for field in ('stage','reason','nativeState','nativeBindingValid','admittedBindingValid','accepted'):
                    row[field] = retired[field]
                row['monoNs'] = retired['monoNs']+1000
        result = self.analyze()
        self.assertEqual({row['queryObservedStage'] for row in result['phases']},{'terminal'})
        self.assertTrue(result['evidenceComplete'])

    def test_missing_duplicate_and_extra_server_lifecycle_rows_fail_closed(self):
        original = copy.deepcopy(self.groups)
        for event in ('pending','accepted','retired'):
            for duplicate in (False,True):
                self.groups = copy.deepcopy(original)
                row = self.records('native',event)[0]
                if duplicate:self.groups['native'].insert(0,copy.deepcopy(row))
                else:self.groups['native'].remove(row)
                with self.subTest(event=event,duplicate=duplicate),self.assertRaises(ValueError):self.analyze()

    def test_every_owner_stage_and_exact_query_response_is_required_once(self):
        original = copy.deepcopy(self.groups)
        for event in ('track','capture','query','reply','terminal'):
            self.groups = copy.deepcopy(original);self.groups['owner'].remove(self.records('owner',event)[0])
            with self.subTest(event=event),self.assertRaises(ValueError):self.analyze()
        for duplicate in (False,True):
            self.groups = copy.deepcopy(original)
            if duplicate:self.groups['query'].append(copy.deepcopy(self.groups['query'][0]))
            else:self.groups['query'].pop()
            with self.subTest(duplicate=duplicate),self.assertRaises(ValueError):self.analyze()

    def test_native_object_source_start_and_ingress_binding_cannot_change_mid_lifetime(self):
        original = copy.deepcopy(self.groups)
        for field,value in (('actionEpoch',999),('tableEpoch',999),('actorEpoch',999),('connectionEpoch',999),
                            ('itemEpoch',999),('worldEpoch',999),('startGeneration',999),('owner',8),
                            ('parseGeneration',999),('ingressGeneration',999),('transaction',99),('packetType',99)):
            self.groups = copy.deepcopy(original);self.records('native','retired')[0][field] = value
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()

    def test_accepted_flags_are_actual_booleans_and_not_pending_authority(self):
        original = copy.deepcopy(self.groups)
        for field in ('sourceValidated','admittedBindingValid','nativeBindingValid','accepted','tokenObserved'):
            for value in (False,1,'true',None):
                self.groups = copy.deepcopy(original);self.records('native','accepted')[0][field] = value
                with self.subTest(field=field,value=value),self.assertRaises(ValueError):self.analyze()
        self.groups = copy.deepcopy(original);self.records('native','pending')[0]['accepted'] = True
        with self.assertRaisesRegex(ValueError,'Pending start'):self.analyze()

    def test_native_terminal_state_and_reason_cannot_claim_conflicting_outcomes(self):
        original = copy.deepcopy(self.groups)
        for field,value in (('reason','invented-completion'),('nativeState','Canceled'),('nativeState','Reject')):
            self.groups = copy.deepcopy(original);self.records('native','retired')[0][field] = value
            with self.subTest(field=field,value=value),self.assertRaises(ValueError):self.analyze()
        self.groups = copy.deepcopy(original)
        self.records('native','retired')[0].update(reason='native-absent',nativeState='unavailable')
        result = self.analyze()
        self.assertEqual(result['phases'][0]['nativeTerminalState'],'unavailable')
        self.assertEqual(result['phases'][0]['ownerSealedOutcome'],'completed')

    def test_direct_native_done_and_reject_cannot_contradict_same_token_owner_outcome(self):
        original = copy.deepcopy(self.groups)
        for index,state,reason in ((0,'Reject','rejected'),(2,'Done','completed'),(2,'Done','native-remove')):
            self.groups = copy.deepcopy(original)
            self.records('native','retired')[index].update(nativeState=state,reason=reason)
            with self.subTest(index=index,state=state,reason=reason),self.assertRaisesRegex(ValueError,'Direct native terminal state contradicts'):
                self.analyze()

    def test_native_remove_without_direct_terminal_state_keeps_outcome_unknown(self):
        self.records('native','retired')[0].update(nativeState='Accept',reason='native-remove')
        result = self.analyze()
        first = result['phases'][0]
        self.assertTrue(result['evidenceComplete'])
        self.assertEqual(first['ownerSealedOutcome'],'completed')
        self.assertEqual(first['nativeTerminalState'],'Accept')
        self.assertEqual(first['nativeRetirementReason'],'native-remove')
        self.assertIn('native remove does not by itself prove cancellation or success',result['qualification'])

    def test_nonzero_signed_native_transaction_ids_are_not_unique_lifecycle_keys(self):
        for group in self.groups.values():
            for row in group:
                if 'transaction' in row:row['transaction'] = -128
        result = self.analyze()
        self.assertEqual({row['transaction'] for row in result['phases']},{-128})
        self.assertEqual(len({row['token'] for row in result['phases']}),6)
        self.assertEqual(len({row['startGeneration'] for row in result['phases']}),6)
        self.records('owner','capture')[0]['transaction'] = 0
        with self.assertRaisesRegex(ValueError,'Zero native transaction'):self.analyze()

    def test_ack_token_is_required_and_cannot_be_reused_or_nearest_time_matched(self):
        original = copy.deepcopy(self.groups)
        for event in ('accepted','retired'):
            self.groups = copy.deepcopy(original);self.records('native',event)[0]['token'] = None
            with self.subTest(event=event),self.assertRaises(ValueError):self.analyze()
        self.groups = copy.deepcopy(original)
        for event in ('track','capture','query','reply','terminal'):
            self.groups = copy.deepcopy(original)
            row = self.records('owner',event)[0]
            if event=='track':row['localActionEpoch'] += 1
            else:row['token'] = self.records('owner',event)[1]['token']
            with self.subTest(event=event),self.assertRaises(ValueError):self.analyze()
        self.groups = copy.deepcopy(original)
        old_token = self.records('native','accepted')[1]['token']
        reused_token = self.records('native','accepted')[0]['token']
        for row in self.groups['native']:
            if row.get('token') == old_token:
                row['token'] = reused_token
        with self.assertRaisesRegex(ValueError,'token reused'):self.analyze()

    def test_pending_token_may_be_observed_but_must_match_same_admitted_object(self):
        pending=self.records('native','pending')[0];accepted=self.records('native','accepted')[0]
        pending.update(token=accepted['token'],tokenObserved=True)
        self.assertTrue(self.analyze()['evidenceComplete'])
        pending['token']=self.records('native','accepted')[1]['token']
        with self.assertRaisesRegex(ValueError,'Pending start token'):self.analyze()

    def test_native_start_and_owner_callback_order_do_not_use_nearest_timestamps(self):
        original = copy.deepcopy(self.groups)
        for name in ('native','owner'):
            self.groups = copy.deepcopy(original)
            self.groups[name][0],self.groups[name][1] = self.groups[name][1],self.groups[name][0]
            with self.subTest(group=name),self.assertRaisesRegex(ValueError,'reordered'):self.analyze()
        self.groups = copy.deepcopy(original);self.records('native','accepted')[0]['monoNs'] = 1
        with self.assertRaisesRegex(ValueError,'monotonic'):self.analyze()

    def test_fresh_nonce_local_action_native_pointer_and_phase_are_frozen(self):
        original = copy.deepcopy(self.groups)
        for field,value in (('nonce',OWNER+':action:2'),('index',2),('phase','pickup-complete'),
                            ('localActionEpoch',999),('localNativeEpoch',999),('ownerProcess',SERVER)):
            self.groups = copy.deepcopy(original);self.records('owner','reply')[0][field] = value
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()
        self.groups = copy.deepcopy(original);self.groups['query'][0]['nonce'] += '-old'
        with self.assertRaisesRegex(ValueError,'nonce-associated'):self.analyze()

    def test_server_query_must_return_exact_accepted_native_snapshot(self):
        original = copy.deepcopy(self.groups)
        for field,value in (('stage','pending'),('tokenObserved',False),('sourceValidated',False),('guarded',1),
                            ('startGeneration',999),('transaction',99),('nativeState','Request'),('owner',8)):
            self.groups = copy.deepcopy(original);self.groups['query'][0][field] = value
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()
        self.groups = copy.deepcopy(original);self.records('owner','reply')[0]['reason'] = 'native-remove'
        with self.assertRaises(ValueError):self.analyze()

    def test_terminal_query_snapshot_cannot_invent_another_native_outcome(self):
        for row in (self.groups['query'][0],self.records('owner','reply')[0]):
            row.update(stage='terminal',reason='native-remove',nativeState='Accept',nativeBindingValid=True,
                       monoNs=self.records('native','retired')[0]['monoNs']+1000)
        with self.assertRaisesRegex(ValueError,'contradicts exact observed'):
            self.analyze()

    def test_owner_seal_capture_rights_and_selected_cancel_outcomes_are_checked(self):
        original = copy.deepcopy(self.groups)
        for event,field,value in (('capture','sealed',1),('capture','state','completed'),('query','guarded',False),
                                  ('reply','sealed',False),('reply','guarded',None),('terminal','sealed',False),
                                  ('terminal','state','rejected')):
            self.groups = copy.deepcopy(original);self.records('owner',event)[0][field] = value
            with self.subTest(event=event,field=field),self.assertRaises(ValueError):self.analyze()
        self.groups = copy.deepcopy(original);self.records('owner','terminal')[2]['state'] = 'completed'
        with self.assertRaisesRegex(ValueError,'terminal outcome'):self.analyze()

    def test_exact_operation_and_pickup_world_binding_are_required(self):
        original = copy.deepcopy(self.groups)
        for group in self.groups.values():
            for row in group:
                if row.get('index') == 1 and 'kind' in row:row['kind'] = 'ToolkitWoodCartPickup'
        with self.assertRaises(ValueError):self.analyze()
        self.groups = copy.deepcopy(original);self.records('native','pending')[1]['worldEpoch'] = 0
        with self.assertRaises(ValueError):self.analyze()

    def test_foreign_endpoints_errors_and_process_restarts_fail_closed(self):
        original=copy.deepcopy(self.groups)
        self.records('owner','capture')[0]['actor']='client2'
        with self.assertRaisesRegex(ValueError,'Foreign owner'):self.analyze()
        self.groups=copy.deepcopy(original);self.groups['query'][0]['actor']='client2'
        with self.assertRaisesRegex(ValueError,'Server query'):self.analyze()
        self.groups=copy.deepcopy(original);self.groups['owner'].append(dict(actor='client1',event='error',reason='seal invalid'))
        with self.assertRaisesRegex(ValueError,'probe error'):self.analyze()
        self.groups=copy.deepcopy(original)
        self.base['client2'].append(MARKERS['owner']+json.dumps(self.groups['owner'][0]))
        with self.assertRaisesRegex(ValueError,'foreign endpoint'):self.analyze()

    def test_positive_epochs_uuid_and_strict_numeric_bounds(self):
        original=copy.deepcopy(self.groups)
        for field,value in (('protocol',True),('startGeneration',0),('actionEpoch',True),('connectionEpoch',-1),
                            ('transaction',128),('packetType',0),('cart',2147483648),('itemEpoch',0),
                            ('process','not-an-epoch'),('sourceSession','wrong-source'),('token','not-a-token')):
            self.groups=copy.deepcopy(original);self.records('native','accepted')[0][field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()

    def test_native_canonical_owner_cart_and_original_phase_bank_cannot_be_replaced(self):
        baseline=copy.deepcopy(self.base)
        self.base['client1'][1]=self.base['client1'][1].replace('"id": 7','"id": 8')
        with self.assertRaisesRegex(ValueError,'canonical owner/cart'):self.analyze()
        self.base=copy.deepcopy(baseline);self.base['client1'].pop()
        with self.assertRaisesRegex(ValueError,'six-phase'):self.analyze()
        self.base=copy.deepcopy(baseline);self.base['client1'][2]=self.base['client1'][2].replace('"id": 42','"id": 43')
        with self.assertRaisesRegex(ValueError,'cart changed'):self.analyze()

    def test_frozen_explicit_scope_and_actual_option_booleans(self):
        original=copy.deepcopy(self.selection)
        for field,value in (('suite','cart_motion_mp'),('kind','sp'),('mode','baseline'),('cases',[])):
            self.selection=dict(original,**{field:value})
            with self.subTest(field=field),self.assertRaisesRegex(ValueError,'Frozen selection'):self.analyze()
        for field,value in (('cart_action_admission',1),('cart_actions',False),('mp_host',False),
                            ('cart_lease_control',True),('cart_inventory_equip',True),('cart_wall_exit','left')):
            self.selection=copy.deepcopy(original);self.selection['options'][field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()

    def test_strict_json_and_read_only_cli_preserve_source_capture(self):
        self.write();before={path.name:path.read_bytes() for path in self.profile.iterdir()}
        cli=subprocess.run([sys.executable,str(SOURCE),'--profile',str(self.profile)],text=True,capture_output=True,timeout=15)
        self.assertEqual(cli.returncode,0,cli.stderr)
        self.assertEqual(json.loads(cli.stdout),API['analyze'](self.profile))
        self.assertEqual(before,{path.name:path.read_bytes() for path in self.profile.iterdir()})
        path=self.profile/'server-launch.log';original=path.read_text();raw=json.dumps(self.records('native','accepted')[0])
        for malformed in (raw[:-1]+',"accepted":true}',raw.replace('"startGeneration": 10','"startGeneration": NaN'),raw+' junk'):
            path.write_text(original.replace(raw,malformed,1))
            with self.subTest(malformed=malformed),self.assertRaises(ValueError):API['analyze'](self.profile)


if __name__=='__main__':
    unittest.main()
