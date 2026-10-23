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


def fixture(cart=42,injected=False,receipt_gap=False,menu=False):
    selection,prefixes,held=CONTROL['fixture']()
    selection['options']['cart_lease_lifetimes']=True
    if menu: selection['options']['cart_lease_menu']=True
    logs={role:prefixes[role]+['[CART_LEASE] '+json.dumps(row) for row in held[role]] for role in ROLES}
    if cart!=42:
        logs={role:[line.replace('"primary": 42','"primary": '+str(cart)).replace('"secondary": 42','"secondary": '+str(cart)).replace('"cart": 42','"cart": '+str(cart)).replace('"id": 42','"id": '+str(cart)) for line in lines] for role,lines in logs.items()}
    rows={role:[] for role in ROLES}
    state={role:dict(revision=1,hard=1,serial=0,parse=0,ingress=0,primary=1001,secondary=1001) for role in ROLES}
    attempts={role:0 for role in ROLES}; sequences={}; latest={}
    def tok(role,revision=None): return '1|native-'+role+'|101|201|'+str(state[role]['revision'] if revision is None else revision)
    def native(role,event,reason,depth=0,serial=0,old=None,parse=0,ingress=0,**extra):
        s=state[role]; primary,secondary=s['primary'],s['secondary']; old=old or (primary,secondary)
        row=dict(event=event,process='native-'+role,ownerID=7,actorEpoch=101,connectionEpoch=201,revision=s['revision'],hardRevision=s['hard'],
                 depth=depth,mutationSerial=serial,parseSerial=parse,ingressGeneration=ingress,reason=reason,directCalls=(2 if event=='resnapshot' else 0),genericCalls=0,
                 oldPrimaryEpoch=old[0],oldSecondaryEpoch=old[1],primaryEpoch=primary,secondaryEpoch=secondary,
                 primaryID=cart if primary else None,secondaryID=cart if secondary else None,success=True,poisoned=False,retired=False,monoNs=len(rows[role])+100,**extra)
        rows[role].append((NATIVE,row))
    def setter(role,reason,new,parse=0,ingress=0):
        s=state[role]; old=(s['primary'],s['secondary']); s['revision']+=1; s['serial']+=1
        if parse==0: s['hard']=s['revision']
        native(role,'mutation-enter',reason,1,s['serial'],old,parse,ingress)
        s[reason]=new
        native(role,'mutation-exit',reason,0,s['serial'],old,parse,ingress)
    def lua(role,event,phase,**values):
        rows[role].append((MARKER,dict(actor=role,event=event,phase=phase,owner=7,wall=127000+len(rows[role]),**values)))
    def binding(phase): return dict(session='equipment-session',grant=1,lease=phase,cart=cart)
    def cycle(role,phase):
        before=tok(role); original=state[role]['primary']; middle=0 if phase==2 else 5001
        setter(role,'primary',middle); setter(role,'secondary',middle); setter(role,'primary',original); setter(role,'secondary',original)
        values=dict(name=API['PHASES'][phase-1],cart=cart,before=before,after=tok(role),cargoID=313,cargoWeight=30,sameItem=True)
        if role!='server': values.update(staleReplyAccepted=False,stalePayloadAccepted=False,staleNonce=f'{role}-pending-{phase-1}')
        lua(role,'cycle',phase,**values)
    def menu_action(phase,kind,event):
        code=phase*10+(1 if kind=='release' else 2)
        row=dict(actor='client1',owner=7,phase=phase,cart=cart,kind=kind,event=event,
                 actionType='ToolkitWoodCartSetdown' if kind=='release' else 'ToolkitWoodCartPickup',
                 localActionEpoch=code,operation=code+100,localSourceEpoch=1,source='native-owner-connection',
                 queuedSource='ToolkitWoodCartSetdown' if kind=='release' else 'ToolkitWoodCartPickup',generation=1,
                 wall=127000+len(rows['client1']))
        if event!='queued':row.update(localNativeEpoch=code+200,token=f'00000000-0000-0000-0000-{code:012d}',
                                      transaction=code,state='started' if event=='start' else 'completed',sealed=True)
        rows['client1'].append(('[CART_LEASE_MENU] ',row))
    def menu_cycles(phase):
        before={role:tok(role) for role in ROLES}
        original={role:state[role]['primary'] for role in ROLES}
        menu_action(phase,'release','queued');menu_action(phase,'release','start')
        for role in ROLES:
            setter(role,'primary',0);setter(role,'secondary',0)
            if role=='client1':menu_action(phase,'release','terminal')
            fields=dict(before=before[role],nativeLifetimeAbsent=True)
            if role!='server':fields.update(staleReplyAccepted=False,stalePayloadAccepted=False,staleNonce=f'{role}-pending-{phase-1}')
            lua(role,'absence',phase,**fields)
        for role in ('client1','client2'):
            lua('server','absent-source',phase,requester=role,before=before['server'],nativeLifetimeAbsent=True,
                stalePayloadAccepted=False,guarded=True,seq=2,**binding(phase-1))
        lua('server','menu-resume',phase,nativeLifetimeAbsent=True)
        for role in ('client1','client2'):lua(role,'menu-resume-received',phase,nativeLifetimeAbsent=True)
        menu_action(phase,'pickup','queued');menu_action(phase,'pickup','start')
        for role in ROLES:
            setter(role,'primary',original[role]);setter(role,'secondary',original[role])
            if role=='client1':menu_action(phase,'pickup','terminal')
            fields=dict(name=API['MENU_PHASES'][phase-1],cart=cart,before=before[role],after=tok(role),
                        cargoID=313,cargoWeight=30,sameItem=True,menu=True)
            if role!='server':fields.update(staleReplyAccepted=False,stalePayloadAccepted=False,staleNonce=f'{role}-pending-{phase-1}')
            lua(role,'cycle',phase,**fields)
    def gap(role,phase):
        s=state[role]; before=tok(role); oldrev=s['revision']; old=(s['primary'],s['secondary']); s['parse']+=1;s['ingress']+=3
        new=7000+s['parse']; parse=s['parse']; ingress=s['ingress']
        setter(role,'primary',new,parse,ingress); setter(role,'secondary',new,parse,ingress)
        native(role,'resnapshot','remote-equip-resnapshot',old=old,parse=parse,ingress=ingress,beforeRevision=oldrev,afterRevision=s['revision'],certified=True)
        lua(role,'resnapshot',phase,before=before,after=tok(role),cart=cart,cargoID=313,cargoWeight=30,nativeCertified=True)
    def chain(role,phase,race=False,gap_receipt=False):
        attempts[role]+=1; attempt=attempts[role]; nonce=f'{role}-fresh-{attempt}'; lifetime=tok(role)
        lua(role,'request',phase,attempt=attempt,nonce=nonce,lifetime=lifetime)
        lua('server','bind',phase,requester=role,attempt=attempt,nonce=nonce,lifetime=tok('server'),guarded=True,**binding(phase))
        if race:
            gap(role,phase)
            lua(role,'reply-refused',phase,attempt=attempt,nonce=nonce,before=lifetime,after=tok(role),accepted=False,guarded=True,**binding(phase))
            return
        seq=sequences.get((role,phase),0)+1; sequences[role,phase]=seq
        lua(role,'bound',phase,attempt=attempt,nonce=nonce,lifetime=lifetime,seq=seq,guarded=True,**binding(phase))
        lua('server','echo',phase,requester=role,attempt=attempt,nonce=nonce,seq=seq,accepted=role=='client1',guarded=True,**binding(phase))
        if gap_receipt: gap(role,phase)
        lua(role,'receipt',phase,attempt=attempt,nonce=nonce,lifetime=lifetime,currentLifetime=tok(role),seq=seq,accepted=role=='client1',guarded=True,**binding(phase))
        if menu and phase>1:
            lua(role,'post-bind-stale',phase,attempt=attempt,nonce=f'{role}-pending-{phase-1}',freshLifetime=tok(role),
                staleReplyAccepted=False,stalePayloadAccepted=False,guarded=True,seq=2,**binding(phase-1))
        latest[role]=attempt
    for role in ROLES: native(role,'baseline','admitted-current')
    for role in ('client1','client2'):
        lua('server','ready',0,requester=role,lifetime=tok('server'),guarded=True); lua(role,'ready',0,lifetime=tok(role))
    for role in ROLES: lua(role,'begin',1)
    for phase in (1,2,3):
        if phase>1:
            if injected and phase==3: gap('client2',2)
            if menu: menu_cycles(phase)
            else:
                for role in ROLES: cycle(role,phase)
        for role in ('client1','client2'):
            if phase>1: lua('server','stale',phase,requester=role,attempt=attempts[role]+1,guarded=True,accepted=False,**binding(phase-1))
            if injected and phase==2 and role=='client2': chain(role,phase,race=True)
            chain(role,phase,gap_receipt=receipt_gap and phase==2 and role=='client2')
            if receipt_gap and phase==2 and role=='client2': chain(role,phase)
            if phase<3:
                pending=f'{role}-pending-{phase}'
                lua(role,'prepare',phase,afterAttempt=latest[role],nonce=pending,lifetime=tok(role))
                lua('server','prepare',phase,requester=role,afterAttempt=latest[role],nonce=pending,lifetime=tok('server'),guarded=True,**binding(phase))
            else:
                lua(role,'done',phase,afterAttempt=latest[role]); lua('server','done',phase,requester=role,afterAttempt=latest[role],guarded=True)
    lua('server','complete-offer',3)
    for role in ('client1','client2'):
        if injected and role=='client2': gap(role,3)
        lua(role,'complete-offer',3)
        if injected and role=='client2': chain(role,3)
        lua(role,'complete',3,afterAttempt=latest[role],lifetime=tok(role))
        lua('server','finished',3,requester=role,afterAttempt=latest[role],lifetime=tok(role),guarded=True)
    lua('server','complete',3)
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
    def test_menu_cycles_require_actual_actions_all_role_absence_and_post_bind_refusals(self):
        self.selection,self.logs,self.rows=fixture(menu=True)
        result=self.analyze()
        self.assertTrue(result['evidenceComplete']);self.assertTrue(result['menu'])
        self.assertEqual(len(result['menuEvidence']['ownerMenuActions']),4)
        self.assertEqual(result['logicalCommandMessages']['fixture'],50)
        self.assertEqual(result['logicalCommandMessages']['maximumFixture'],90)
        self.assertEqual(result['menuEvidence']['postBindClientPayloadsRefused'],4)
        self.assertIn('Inventory-menu equip',result['qualification'])

    def test_menu_proof_rejects_missing_barrier_input_or_stale_refusal(self):
        self.selection,self.logs,self.rows=fixture(menu=True)
        self.assert_mutations_fail([
            ('server','absence',2,dict(nativeLifetimeAbsent=False),MARKER),
            ('client1','absence',2,dict(staleReplyAccepted=True),MARKER),
            ('client2','absence',3,dict(staleNonce='other'),MARKER),
            ('server','absent-source',2,dict(guarded=False),MARKER),
            ('client1','post-bind-stale',2,dict(freshLifetime='1|client1|1|1|999'),MARKER),
            ('client2','post-bind-stale',3,dict(stalePayloadAccepted=True),MARKER),
            ('client1','cycle',2,dict(menu=False),MARKER),
            ('client1','queued',2,dict(actionType='ToolkitWoodCartDrop'),'[CART_LEASE_MENU] '),
            ('client1','start',3,dict(source='foreign'),'[CART_LEASE_MENU] '),
            ('client1','terminal',2,dict(state='canceled'),'[CART_LEASE_MENU] '),
        ])
        original=copy.deepcopy(self.rows)
        for role,marker,event in [('server',MARKER,'menu-resume'),('client2',MARKER,'absence'),
                                  ('client1','[CART_LEASE_MENU] ','queued')]:
            self.rows=copy.deepcopy(original)
            self.rows[role]=[(m,r) for m,r in self.rows[role] if not (m==marker and r['event']==event and r['phase']==2)]
            with self.subTest(role=role,event=event),self.assertRaises(ValueError):self.analyze()

    def test_menu_barrier_requires_current_native_absence_not_an_old_empty_snapshot(self):
        self.selection,self.logs,self.rows=fixture(menu=True)
        original=copy.deepcopy(self.rows)
        for role,event in [('server','absence'),('server','menu-resume'),('client1','absence'),('client1','menu-resume-received')]:
            self.rows=copy.deepcopy(original)
            restored=[pair for pair in self.rows[role] if pair[0]==NATIVE and pair[1].get('revision') in (4,5)]
            self.rows[role]=[pair for pair in self.rows[role] if not (pair[0]==NATIVE and pair[1].get('revision') in (4,5))]
            at=next(i for i,(m,r) in enumerate(self.rows[role]) if m==MARKER and r['event']==event and r['phase']==2)
            self.rows[role][at:at]=restored
            with self.subTest(role=role,event=event),self.assertRaisesRegex(ValueError,'barrier'):
                self.analyze()

    def test_menu_receipts_use_native_signed_nonzero_transaction_and_uuid(self):
        self.selection,self.logs,self.rows=fixture(menu=True)
        for marker,row in self.rows['client1']:
            if marker=='[CART_LEASE_MENU] ' and row['event'] in ('start','terminal'):row['transaction']=-128
        self.assertTrue(self.analyze()['evidenceComplete'])
        original=copy.deepcopy(self.rows)
        for key,value in [('transaction',0),('transaction',128),('transaction',-129),('transaction',True),('token','arbitrary-token')]:
            self.rows=copy.deepcopy(original)
            for marker,row in self.rows['client1']:
                if marker=='[CART_LEASE_MENU] ' and row['event'] in ('start','terminal'):row[key]=value
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):self.analyze()

    def test_menu_selection_cannot_relabel_the_setter_bank(self):
        self.selection,self.logs,self.rows=fixture(menu=True)
        for value in (False,'true',1):
            self.selection['options']['cart_lease_menu']=value
            with self.subTest(value=value),self.assertRaises(ValueError):self.analyze()

    def test_complete_six_native_cycles_and_guarded_chains_are_narrowly_reported(self):
        result=self.analyze()
        self.assertTrue(result['evidenceComplete']); self.assertTrue(result['diagnosticOnly'])
        self.assertEqual(result['completedNativeCycles'],6); self.assertEqual(result['completeChains'],6)
        self.assertEqual(result['heldLeaseControl']['roundsPerClient'],3)
        self.assertEqual([cycle['completedSetterWrites'] for cycle in result['cycles']],[4]*6)
        self.assertEqual(result['staleServerPayloadsRefused'],4)
        self.assertEqual(result['stalePreparedRepliesRefused'],4)
        self.assertEqual(result['staleClientPayloadsRefused'],4)
        self.assertIn('Native setter fixture and strictly certified',result['qualification'])
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
        nested=copy.deepcopy(outer); nested.update(depth=2,revision=3,hardRevision=3,mutationSerial=2)
        nested_exit=copy.deepcopy(nested); nested_exit.update(event='mutation-exit',depth=1,primaryEpoch=7001)
        for prefix,row in rows[pos+1:]:
            if prefix==NATIVE:
                row['revision']+=1; row['hardRevision']=row['revision']
                if row['mutationSerial']>1: row['mutationSerial']+=1
            elif prefix==MARKER:
                for field in ('lifetime','currentLifetime','before','after'):
                    if field in row:
                        pieces=row[field].split('|')
                        if int(pieces[-1])>=2: pieces[-1]=str(int(pieces[-1])+1); row[field]='|'.join(pieces)
        rows[pos+1:pos+1]=[(NATIVE,nested),(NATIVE,nested_exit)]
        for i,(prefix,row) in enumerate(rows):
            if prefix==NATIVE: row['monoNs']=100+i
        self.find('server','finished')[0]['lifetime']=self.find('client1','complete')[0]['lifetime']
        self.assertTrue(self.analyze()['evidenceComplete'])
        nested_exit['mutationSerial']=3
        with self.assertRaisesRegex(ValueError,'scope mismatch'): self.analyze()
    def test_nested_callback_can_replace_a_later_noop_top_level_setter(self):
        rows=self.rows['client1']
        pos=next(i for i,(p,r) in enumerate(rows) if p==NATIVE and r['event']=='mutation-enter')
        primary_enter,primary_exit,secondary_enter,secondary_exit=[copy.deepcopy(rows[pos+i]) for i in range(4)]
        secondary_enter[1]['depth']=2
        secondary_exit[1]['depth']=1
        primary_exit[1].update(revision=3,hardRevision=3,primaryEpoch=0,secondaryEpoch=0,primaryID=None,secondaryID=None)
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
        enter.update(event='mutation-enter',revision=10,hardRevision=10,depth=1,mutationSerial=9,reason='player-load',monoNs=999)
        exit_=dict(enter,event='mutation-exit',depth=0,monoNs=1000)
        rows[-1:-1]=[(NATIVE,enter),(NATIVE,exit_)]
        with self.assertRaisesRegex(ValueError,'native revision window|Unlinked native mutation'): self.analyze()
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
        with self.assertRaisesRegex(ValueError,'Done preceded exact receipt'): self.analyze()
    def test_certified_races_precycle_gap_and_post_done_resync_are_separate_proof(self):
        self.selection,self.logs,self.rows=fixture(injected=True)
        result=self.analyze()
        self.assertEqual(result['certifiedResnapshots'],3)
        self.assertEqual(result['refusedRacedReplies'],1)
        self.assertEqual(result['completeChains'],7)
        self.assertEqual(result['completedNativeCycles'],6)
        self.assertEqual(result['logicalCommandMessages'],dict(fixture=48,clientToServer=25,serverToClient=23,includingHeldControl=72,maximumFixture=82))
        self.assertEqual([c['seq'] for c in result['chains'] if c['requester']=='client2' and c['phase']==3],[1,2])
        self.assertEqual([g['parseSerials'] for g in result['resnapshots']],[[1],[2],[3]])
    def test_snapshot_between_bound_and_receipt_requires_a_fresh_same_lease_chain(self):
        self.selection,self.logs,self.rows=fixture(receipt_gap=True)
        result=self.analyze()
        self.assertEqual(result['certifiedResnapshots'],1)
        self.assertEqual(result['refusedRacedReplies'],0)
        self.assertEqual(result['logicalCommandMessages']['fixture'],46)
        self.assertEqual([c['seq'] for c in result['chains'] if c['requester']=='client2' and c['phase']==2],[1,2])
    def test_no_certificate_no_success_even_with_exact_same_numeric_id(self):
        self.selection,self.logs,self.rows=fixture(injected=True)
        original=copy.deepcopy(self.rows)
        for marker,event in ((NATIVE,'resnapshot'),(MARKER,'resnapshot')):
            self.rows=copy.deepcopy(original)
            entry=next(e for e in self.rows['client2'] if e[0]==marker and e[1]['event']==event)
            self.rows['client2'].remove(entry)
            with self.subTest(marker=marker),self.assertRaises(ValueError): self.analyze()
    def test_certificate_schema_ingress_identity_hard_fence_and_call_counts_are_strict(self):
        self.selection,self.logs,self.rows=fixture(injected=True)
        original=copy.deepcopy(self.rows)
        for changes in (dict(certified=False),dict(certified=1),dict(directCalls=1),dict(directCalls=3),dict(directCalls=True),
                        dict(genericCalls=1),dict(genericCalls=False),dict(parseSerial=0),dict(ingressGeneration=0),
                        dict(beforeRevision=999),dict(afterRevision=999),dict(hardRevision=999),dict(oldPrimaryEpoch=9000),
                        dict(process='foreign'),dict(actorEpoch=102),dict(connectionEpoch=202),dict(reason='generic-equip'),
                        dict(success=False),dict(poisoned=True),dict(retired=True)):
            self.rows=copy.deepcopy(original)
            self.find('client2','resnapshot',marker=NATIVE)[0].update(changes)
            with self.subTest(changes=changes),self.assertRaises(ValueError): self.analyze()
    def test_generic_nested_or_mismatched_parser_writes_cannot_use_certificate(self):
        self.selection,self.logs,self.rows=fixture(injected=True)
        original=copy.deepcopy(self.rows)
        for changes in (dict(parseSerial=99),dict(ingressGeneration=99),dict(reason='player-load'),dict(depth=2),dict(hardRevision=7)):
            self.rows=copy.deepcopy(original)
            row=next(r for p,r in self.rows['client2'] if p==NATIVE and r['event']=='mutation-enter' and r['parseSerial']>0)
            row.update(changes)
            with self.subTest(changes=changes),self.assertRaises(ValueError): self.analyze()
    def test_native_certificate_reuse_and_lua_boolean_guard_do_not_admit_gaps(self):
        self.selection,self.logs,self.rows=fixture(injected=True)
        original=copy.deepcopy(self.rows)
        for value in (False,1,'true',None):
            self.rows=copy.deepcopy(original); self.find('client2','resnapshot')[0]['nativeCertified']=value
            with self.subTest(value=value),self.assertRaises(ValueError): self.analyze()
        self.rows=copy.deepcopy(original)
        certs=self.find('client2','resnapshot',marker=NATIVE)
        certs[1]['parseSerial']=certs[0]['parseSerial']
        with self.assertRaises(ValueError): self.analyze()
    def test_certified_remote_parse_is_never_absorbed_into_planned_cycle(self):
        self.selection,self.logs,self.rows=fixture(injected=True)
        gap=self.find('client2','resnapshot',2)[-1]
        self.find('client2','cycle',3)[0]['before']=gap['before']
        entry=next(e for e in self.rows['client2'] if e[0]==MARKER and e[1] is gap)
        self.rows['client2'].remove(entry)
        with self.assertRaisesRegex(ValueError,'interleaving|original references not restored'): self.analyze()
    def test_final_same_lease_rebind_cannot_reset_sequence_or_finish_on_old_ack(self):
        self.selection,self.logs,self.rows=fixture(injected=True)
        original=copy.deepcopy(self.rows)
        for event,role in (('bound','client2'),('receipt','client2'),('echo','server')):
            self.rows=copy.deepcopy(original)
            row=[r for r in self.find(role,event,3) if role!='server' or r['requester']=='client2'][-1]
            row['seq']=1
            with self.subTest(event=event),self.assertRaisesRegex(ValueError,'sequence'): self.analyze()
        self.rows=copy.deepcopy(original)
        self.find('client2','complete',3)[0]['afterAttempt']=4
        with self.assertRaisesRegex(ValueError,'settle'): self.analyze()
    def test_attempt_and_final_certificate_bounds_are_enforced(self):
        self.selection,self.logs,self.rows=fixture(injected=True)
        original=copy.deepcopy(self.rows)
        for changes in (dict(attempt=9),dict(attempt=True),dict(attempt=1),dict(nonce='client2-fresh-1')):
            self.rows=copy.deepcopy(original); self.find('client2','request',3)[-1].update(changes)
            with self.subTest(changes=changes),self.assertRaises(ValueError): self.analyze()
        self.rows=copy.deepcopy(original)
        self.find('client2','complete',3)[0]['lifetime']=self.find('client2','request',3)[0]['lifetime']
        with self.assertRaises(ValueError): self.analyze()

    def test_cli_reports_json_and_preserves_all_original_capture_files(self):
        self.write(); (self.profile/'existing-result.json').write_text('keep')
        before={path.name:path.read_bytes() for path in self.profile.iterdir()}
        expected=API['analyze'](self.profile)
        cli=subprocess.run([sys.executable,str(SOURCE),'--profile',str(self.profile)],capture_output=True,text=True,timeout=15)
        self.assertEqual(cli.returncode,0,cli.stderr); self.assertEqual(json.loads(cli.stdout),expected)
        self.assertEqual(before,{path.name:path.read_bytes() for path in self.profile.iterdir()})


if __name__=='__main__': unittest.main()
