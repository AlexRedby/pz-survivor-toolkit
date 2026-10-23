"""Synthetic exact log-shape regressions for the native setter lifetime bank; no game."""
import copy
import json
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'tests/native_queue/contributions/wooden_cart_multiplayer/analyze-lease-lifetimes.py'
API=runpy.run_path(str(SOURCE))
CONTROL=runpy.run_path(str(ROOT/'tests/test_cart_lease_control.py'))
ROLES=('server','client1','client2')
MARKER='[CART_LEASE_LIFETIME] '
NATIVE='[CART_EQUIPMENT] '


def fixture(cart=42):
    selection, prefixes, held = CONTROL['fixture']()
    selection['options']['cart_lease_lifetimes']=True
    logs={role:prefixes[role]+['[CART_LEASE] '+json.dumps(row) for row in held[role]] for role in ROLES}
    rows={role:[] for role in ROLES}
    processes={role:'native-'+role for role in ROLES}
    original=1001
    def tok(role,revision): return '1|'+processes[role]+'|101|201|'+str(revision)
    def native(role,event,revision,depth,serial,reason,primary,secondary,old_primary=None,old_secondary=None):
        row=dict(event=event,process=processes[role],ownerID=7,actorEpoch=101,connectionEpoch=201,revision=revision,
                 depth=depth,mutationSerial=serial,reason=reason,oldPrimaryEpoch=primary if old_primary is None else old_primary,
                 oldSecondaryEpoch=secondary if old_secondary is None else old_secondary,primaryEpoch=primary,secondaryEpoch=secondary,
                 primaryID=cart if primary else None,secondaryID=cart if secondary else None,success=True,poisoned=False,retired=False,
                 monoNs=len(rows[role])+100)
        rows[role].append((NATIVE,row))
    def lua(role,event,phase,**values):
        rows[role].append((MARKER,dict(actor=role,event=event,phase=phase,owner=7,wall=127000+len(rows[role]),**values)))
    def bind(phase): return dict(session='equipment-session',grant=1,lease=phase,cart=cart)
    def cycle(role,phase):
        rev=1+(phase-2)*4
        state=(original,original)
        middle=0 if phase==2 else 5001
        for n, (reason,new) in enumerate((('primary',(middle,original)),('secondary',(middle,middle)),
                                          ('primary',(original,middle)),('secondary',(original,original)))):
            native(role,'mutation-enter',rev+n+1,1,(phase-2)*4+n+1,reason,*state)
            native(role,'mutation-exit',rev+n+1,0,(phase-2)*4+n+1,reason,*new,*state)
            state=new
        values=dict(name=API['PHASES'][phase-1],cart=cart,before=tok(role,rev),after=tok(role,rev+4),
                    cargoID=313,cargoWeight=30,sameItem=True)
        if role!='server': values.update(staleReplyAccepted=False,stalePayloadAccepted=False,staleNonce=f'{role}-pending-{phase-1}')
        lua(role,'cycle',phase,**values)
    for role in ROLES:
        native(role,'baseline',1,0,0,'admitted-current',original,original)
    for role in ('client1','client2'):
        lua('server','ready',0,requester=role,guarded=True)
        lua(role,'ready',0)
    for role in ROLES: lua(role,'begin',1)
    for phase in (1,2,3):
        if phase>1:
            for role in ROLES: cycle(role,phase)
        for role in ('client1','client2'):
            nonce=f'{role}-fresh-{phase}'
            client_life=tok(role,1+(phase-1)*4); server_life=tok('server',1+(phase-1)*4)
            if phase>1: lua('server','stale',phase,requester=role,guarded=True,accepted=False,**bind(phase-1))
            lua(role,'request',phase,nonce=nonce,lifetime=client_life)
            lua('server','bind',phase,requester=role,nonce=nonce,lifetime=server_life,guarded=True,**bind(phase))
            lua(role,'bound',phase,nonce=nonce,lifetime=client_life,guarded=True,**bind(phase))
            lua('server','echo',phase,requester=role,nonce=nonce,seq=1,accepted=role=='client1',guarded=True,**bind(phase))
            lua(role,'receipt',phase,nonce=nonce,seq=1,accepted=role=='client1',guarded=True,**bind(phase))
            if phase<3:
                pending=f'{role}-pending-{phase}'
                lua(role,'prepare',phase,nonce=pending,lifetime=client_life)
                lua('server','prepare',phase,requester=role,nonce=pending,lifetime=server_life,guarded=True,**bind(phase))
            else:
                lua(role,'done',phase)
                lua('server','done',phase,requester=role,guarded=True)
    for role in ROLES: lua(role,'complete',3)
    return selection,logs,rows


class EquipmentLifetimeEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.profile=Path(self.temp.name)
        self.selection,self.logs,self.rows=fixture()
    def write(self):
        (self.profile/'selection.json').write_text(json.dumps(self.selection))
        for role in ROLES:
            lines=self.logs[role]+['LOG : General > '+marker+json.dumps(row) for marker,row in self.rows[role]]
            (self.profile/(role+'-launch.log')).write_text('\n'.join(lines)+'\n')
    def analyze(self): self.write(); return API['analyze'](self.profile)
    def find(self,role,event,phase=None,marker=MARKER):
        return [row for prefix,row in self.rows[role] if prefix==marker and row['event']==event and (phase is None or row.get('phase')==phase)]
    def assert_mutations_fail(self,mutations):
        original=copy.deepcopy(self.rows)
        for role,event,phase,changes,marker in mutations:
            self.rows=copy.deepcopy(original)
            self.find(role,event,phase,marker)[0].update(changes)
            with self.subTest(role=role,event=event,changes=changes),self.assertRaises(ValueError): self.analyze()
    def test_complete_six_native_cycles_and_guarded_chains_are_narrowly_reported(self):
        result=self.analyze()
        self.assertTrue(result['evidenceComplete']); self.assertTrue(result['diagnosticOnly'])
        self.assertEqual(result['completedNativeCycles'],6); self.assertEqual(result['completeChains'],6)
        self.assertEqual(result['heldLeaseControl']['roundsPerClient'],3)
        self.assertEqual([cycle['completedSetterWrites'] for cycle in result['cycles']],[4]*6)
        self.assertEqual(result['staleServerPayloadsRefused'],4)
        self.assertEqual(result['stalePreparedRepliesRefused'],4)
        self.assertEqual(result['staleClientPayloadsRefused'],4)
        self.assertIn('Native setter fixture only',result['qualification'])
        self.assertIn('No normal menu release, complete reconnect',result['qualification'])
        self.assertNotIn('runtimePass',result)
    def test_explicit_flags_and_real_held_three_round_control_are_prerequisites(self):
        original=copy.deepcopy(self.selection)
        for key in ('cart_lease_lifetimes','cart_lease_control'):
            for value in (None,False,1,'true'):
                self.selection=copy.deepcopy(original); self.selection['options'][key]=value
                with self.subTest(key=key,value=value),self.assertRaises(ValueError): self.analyze()
        self.selection=original
        self.logs['server']=[line for line in self.logs['server'] if '"event": "echo"' not in line]
        with self.assertRaises(ValueError): self.analyze()
    def test_missing_duplicate_foreign_and_error_records_fail(self):
        original=copy.deepcopy(self.rows)
        for role,event,marker in (('client1','cycle',MARKER),('server','stale',MARKER),('client2','prepare',MARKER),
                                  ('server','mutation-enter',NATIVE),('client1','mutation-exit',NATIVE),('client2','baseline',NATIVE)):
            for action in ('remove','duplicate'):
                self.rows=copy.deepcopy(original)
                entry=next(entry for entry in self.rows[role] if entry[0]==marker and entry[1]['event']==event)
                pos=self.rows[role].index(entry)
                if action=='remove': self.rows[role].pop(pos)
                else: self.rows[role].insert(pos,copy.deepcopy(entry))
                with self.subTest(role=role,event=event,action=action),self.assertRaises(ValueError): self.analyze()
        self.rows=copy.deepcopy(original)
        self.rows['client1'].insert(2,(NATIVE,dict(event='error',reason='native failure')))
        with self.assertRaisesRegex(ValueError,'trace error'): self.analyze()
    def test_exact_phase_chain_identity_nonce_and_guard_must_match(self):
        mutations=[]
        for role,event in (('server','bind'),('server','echo'),('client1','bound'),('client2','receipt')):
            for changes in (dict(session='foreign'),dict(grant=2),dict(lease=8),dict(cart=43),dict(owner=8),dict(nonce='foreign'),
                            dict(guarded=1),dict(guarded=False),dict(guarded='true')):
                mutations.append((role,event,1,changes,MARKER))
        mutations.extend([('client1','receipt',2,dict(accepted=False),MARKER),('client2','receipt',3,dict(accepted=True),MARKER),
                          ('server','echo',2,dict(seq=2),MARKER),('client1','request',1,dict(actor='client2'),MARKER)])
        self.assert_mutations_fail(mutations)
    def test_stale_prepared_reply_and_payload_denial_is_exact_and_boolean(self):
        mutations=[]
        for phase in (2,3):
            for field in ('staleReplyAccepted','stalePayloadAccepted'):
                for value in (True,0,'false',None): mutations.append(('client1','cycle',phase,{field:value},MARKER))
            mutations.extend([('client2','cycle',phase,dict(staleNonce='wrong-pending-reply'),MARKER),
                              ('server','stale',phase,dict(accepted=True),MARKER),
                              ('server','stale',phase,dict(lease=99),MARKER),
                              ('client1','prepare',phase-1,dict(nonce='foreign'),MARKER)])
        self.assert_mutations_fail(mutations)
    def test_default_stale_foreign_process_actor_connection_and_revision_tokens_fail(self):
        original=copy.deepcopy(self.rows)
        for value in ('','0','1|native-client1|0|201|1','1|native-client1|101|0|1',
                      '1|native-client1|101|201|0','1|native-client1|101|201|9007199254740992',
                      '1|other-process|101|201|1','1|native-client1|102|201|1','1|native-client1|101|202|1',
                      '1|native-client1|101|201|2','1|native-client1|101|201|5'):
            self.rows=copy.deepcopy(original)
            for row in self.find('client1','request',1)+self.find('client1','bound',1)+self.find('client1','prepare',1): row['lifetime']=value
            with self.subTest(value=value),self.assertRaises(ValueError): self.analyze()
    def test_cycle_before_after_original_cart_cargo_and_stale_lease_cannot_be_fabricated(self):
        mutations=[]
        for role in ROLES:
            for phase in (2,3):
                for changes in (dict(before='1|other|101|201|1'),dict(after='1|native-'+role+'|101|201|8'),
                                dict(sameItem=False),dict(cart=43),dict(cargoID=314),dict(cargoWeight=3),dict(name='reconnect')):
                    mutations.append((role,'cycle',phase,changes,MARKER))
        self.assert_mutations_fail(mutations)
    def test_completed_exit_not_entry_claim_proves_both_empty_and_replacement(self):
        original=copy.deepcopy(self.rows)
        for phase,revision in ((2,3),(3,7)):
            self.rows=copy.deepcopy(original)
            for prefix,row in self.rows['client1']:
                if prefix==NATIVE and row['revision']==revision and row['event']=='mutation-exit':
                    row.update(primaryEpoch=1001,secondaryEpoch=1001,primaryID=42,secondaryID=42)
            with self.subTest(phase=phase),self.assertRaises(ValueError): self.analyze()
        self.rows=copy.deepcopy(original)
        for prefix,row in self.rows['client1']:
            if prefix==NATIVE and row['event']=='mutation-exit' and row['revision']==9: row['primaryEpoch']=9001
        with self.assertRaises(ValueError): self.analyze()
    def test_same_numeric_id_aliasing_original_reference_is_not_replacement(self):
        for prefix,row in self.rows['client1']:
            if prefix==NATIVE:
                for field in ('primaryEpoch','secondaryEpoch','oldPrimaryEpoch','oldSecondaryEpoch'):
                    if row[field]==5001: row[field]=1001
        with self.assertRaisesRegex(ValueError,'different-reference'): self.analyze()
    def test_unknown_interleaving_load_and_identity_mutations_do_not_pass_as_setters(self):
        original=copy.deepcopy(self.rows)
        for reason in ('item-id','world-item','player-load','character-load','online-id','unrecognized'):
            self.rows=copy.deepcopy(original)
            for row in self.find('server','mutation-enter',marker=NATIVE)+self.find('server','mutation-exit',marker=NATIVE):
                if row['revision']==2: row['reason']=reason
            with self.subTest(reason=reason),self.assertRaisesRegex(ValueError,'interleaving'): self.analyze()
    def test_native_serial_stack_revision_monotonic_and_old_refs_are_checked(self):
        self.assert_mutations_fail([
            ('client1','mutation-enter',None,dict(depth=2),NATIVE),
            ('client1','mutation-enter',None,dict(revision=3),NATIVE),
            ('client1','mutation-exit',None,dict(mutationSerial=99),NATIVE),
            ('client1','mutation-exit',None,dict(oldPrimaryEpoch=999),NATIVE),
            ('client1','mutation-exit',None,dict(depth=1),NATIVE),
            ('client1','mutation-enter',None,dict(monoNs=0),NATIVE),
            ('client1','mutation-enter',None,dict(primaryEpoch=9000),NATIVE),
            ('client1','baseline',None,dict(primaryID=None),NATIVE),
            ('client1','baseline',None,dict(connectionEpoch=0),NATIVE),
            ('client1','baseline',None,dict(revision=True),NATIVE)])
    def test_poison_failed_retired_unknown_death_or_rebaseline_cannot_heal(self):
        self.assert_mutations_fail([
            ('client1','mutation-exit',None,dict(success=False),NATIVE),
            ('client1','mutation-exit',None,dict(poisoned=True),NATIVE),
            ('client1','mutation-exit',None,dict(retired=True),NATIVE),
            ('client1','mutation-exit',None,dict(event='retire'),NATIVE),
            ('client1','mutation-exit',None,dict(event='death'),NATIVE),
            ('client1','mutation-exit',None,dict(event='baseline',depth=0,mutationSerial=0,reason='admitted-current'),NATIVE)])
    def test_balanced_nested_same_actor_scopes_are_paired_by_serial_and_depth(self):
        rows=self.rows['client1']; pos=next(i for i,(p,r) in enumerate(rows) if p==NATIVE and r['event']=='mutation-enter')
        outer=rows[pos][1]
        nested=copy.deepcopy(outer); nested.update(depth=2,revision=3,mutationSerial=2)
        nested_exit=copy.deepcopy(nested); nested_exit.update(event='mutation-exit',depth=1,primaryEpoch=7001)
        for prefix,row in rows[pos+1:]:
            if prefix==NATIVE:
                row['revision']+=1
                if row['mutationSerial']>1: row['mutationSerial']+=1
            elif prefix==MARKER:
                for field in ('lifetime','before','after'):
                    if field in row:
                        pieces=row[field].split('|')
                        if int(pieces[-1])>=2: pieces[-1]=str(int(pieces[-1])+1); row[field]='|'.join(pieces)
        rows[pos+1:pos+1]=[(NATIVE,nested),(NATIVE,nested_exit)]
        for i,(prefix,row) in enumerate(rows):
            if prefix==NATIVE: row['monoNs']=100+i
        self.assertTrue(self.analyze()['evidenceComplete'])
        nested_exit['mutationSerial']=3
        with self.assertRaisesRegex(ValueError,'scope mismatch'): self.analyze()
    def test_nested_callback_can_replace_a_later_noop_top_level_setter(self):
        rows=self.rows['client1']
        pos=next(i for i,(p,r) in enumerate(rows) if p==NATIVE and r['event']=='mutation-enter')
        primary_enter,primary_exit,secondary_enter,secondary_exit=[copy.deepcopy(rows[pos+i]) for i in range(4)]
        secondary_enter[1]['depth']=2
        secondary_exit[1]['depth']=1
        primary_exit[1].update(revision=3,primaryEpoch=0,secondaryEpoch=0,primaryID=None,secondaryID=None)
        rows[pos:pos+4]=[primary_enter,secondary_enter,secondary_exit,primary_exit]
        for i,(marker,row) in enumerate(rows):
            if marker==NATIVE: row['monoNs']=100+i
        result=self.analyze()
        cycle=next(c for c in result['cycles'] if c['actor']=='client1' and c['phase']==2)
        self.assertEqual(cycle['completedSetterWrites'],4)
    def test_trailing_shutdown_retire_is_outside_completed_fixture(self):
        row=copy.deepcopy(self.find('client1','baseline',marker=NATIVE)[0])
        row.update(event='retire',retired=True,reason='connection-remove')
        self.rows['client1'].append((NATIVE,row))
        self.assertTrue(self.analyze()['evidenceComplete'])
    def test_order_clock_deadline_and_completion_are_required(self):
        original=copy.deepcopy(self.rows)
        for role,changes in (('client1',dict(wall=1)),('server',dict(wall=999999)),('client2',dict(phase=2))):
            self.rows=copy.deepcopy(original); self.find(role,'complete')[0].update(changes)
            with self.subTest(role=role,changes=changes),self.assertRaises(ValueError): self.analyze()
        self.rows=copy.deepcopy(original)
        rows=self.rows['client1']; request=next(i for i,(p,r) in enumerate(rows) if p==MARKER and r['event']=='request')
        bound=request+1; rows[request][1]['wall']=rows[bound][1]['wall']; rows[request],rows[bound]=rows[bound],rows[request]
        with self.assertRaises(ValueError): self.analyze()
    def test_signed_and_zero_cart_ids_are_valid_native_ids(self):
        for cart in (-2147483648,0,2147483647):
            self.selection,self.logs,self.rows=fixture(cart)
            self.logs={role:[line.replace('"primary": 42','"primary": '+str(cart)).replace('"secondary": 42','"secondary": '+str(cart)).replace('"cart": 42','"cart": '+str(cart)).replace('"id": 42','"id": '+str(cart)) for line in lines] for role,lines in self.logs.items()}
            with self.subTest(cart=cart): self.assertEqual(self.analyze()['cartID'],cart)
    def test_strict_json_duplicate_nonfinite_trailing_and_nonobject_fail(self):
        self.write(); path=self.profile/'client1-launch.log'; initial=path.read_text()
        raw=json.dumps(self.find('client1','cycle',2)[0])
        for replacement in (raw[:-1]+',"sameItem":true}',raw.replace('"cargoWeight": 30','"cargoWeight": NaN'),raw+' trailing','[]'):
            path.write_text(initial.replace(raw,replacement,1))
            with self.subTest(replacement=replacement),self.assertRaises(ValueError): API['analyze'](self.profile)
    def test_unlinked_final_native_mutation_cannot_hide_before_completion(self):
        rows=self.rows['client1']; baseline=self.find('client1','baseline',marker=NATIVE)[0]
        enter=copy.deepcopy(baseline)
        enter.update(event='mutation-enter',revision=10,depth=1,mutationSerial=9,reason='player-load',monoNs=999)
        exit_=dict(enter,event='mutation-exit',depth=0,monoNs=1000)
        rows[-1:-1]=[(NATIVE,enter),(NATIVE,exit_)]
        with self.assertRaisesRegex(ValueError,'Unlinked native mutation'): self.analyze()
    def test_consistent_grant_or_lease_rewrite_and_early_done_do_not_pass(self):
        original=copy.deepcopy(self.rows)
        for field in ('grant','lease'):
            self.rows=copy.deepcopy(original)
            for rows in self.rows.values():
                for marker,row in rows:
                    if marker==MARKER and field in row: row[field]+=5
            with self.subTest(field=field),self.assertRaises(ValueError): self.analyze()
        self.rows=copy.deepcopy(original)
        rows=self.rows['client1']
        receipt=next(i for i,(p,r) in enumerate(rows) if p==MARKER and r['event']=='receipt' and r['phase']==3)
        done=receipt+1
        rows[receipt][1]['wall']=rows[done][1]['wall']
        rows[receipt],rows[done]=rows[done],rows[receipt]
        with self.assertRaisesRegex(ValueError,'completion preceded receipt'): self.analyze()
    def test_cli_reports_json_and_preserves_all_original_capture_files(self):
        self.write(); (self.profile/'existing-result.json').write_text('keep')
        before={path.name:path.read_bytes() for path in self.profile.iterdir()}
        expected=API['analyze'](self.profile)
        cli=subprocess.run([sys.executable,str(SOURCE),'--profile',str(self.profile)],capture_output=True,text=True,timeout=15)
        self.assertEqual(cli.returncode,0,cli.stderr); self.assertEqual(json.loads(cli.stdout),expected)
        self.assertEqual(before,{path.name:path.read_bytes() for path in self.profile.iterdir()})


if __name__=='__main__': unittest.main()
