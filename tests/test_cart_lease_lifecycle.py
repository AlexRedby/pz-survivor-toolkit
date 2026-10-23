"""Strict lifecycle analyzer regressions using synthetic logs, not native-game evidence."""
import copy
import json
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
ANALYZER=Path('tests/native_queue/contributions/wooden_cart_multiplayer/analyze-lease-lifecycle.py')
if not (ROOT/ANALYZER).is_file():ROOT=Path.cwd()
API=runpy.run_path(str(ROOT/ANALYZER))
ROLES=('server','client1','client2')
MARKER='[CART_LIFECYCLE] ';NATIVE='[CART_EQUIPMENT] '


def fixture():
    """Three native processes, three incarnations, six exact owner/observer chains."""
    selection=dict(suite='wooden_cart_multiplayer',kind='mp',mode='toolkit',cases=['lease_lifecycle'],
                   disposable=True,options=dict(mp_host=True,cart_variant='wooden-wheelbarrow'))
    rows={role:[] for role in ROLES}
    def conn(role,phase):return 201 if role=='client1' else (101 if role=='server' else 301)+(phase==3)
    def lifetime(role,phase):return f'1|native-{role}|{10+phase}|{conn(role,phase)}|1'
    def ident(phase):return dict(session='fixture-session',grant=phase,lease=phase,cart=400+phase)
    def emit(role,event,phase,**fields):
        row=dict(actor=role,event=event,phase=phase,wall=1000+len(rows[role])*10);row.update(fields)
        rows[role].append((MARKER,row));return row
    def native(role,event,phase,reason,**fields):
        row=dict(process='native-'+role,event=event,monoNs=(len(rows[role])+1)*1000000,
                 ownerID=6+phase,actorEpoch=10+phase,connectionEpoch=conn(role,phase),revision=1,
                 depth=0,mutationSerial=0,hardRevision=1,parseSerial=0,ingressGeneration=0,
                 oldPrimaryEpoch=100+phase,oldSecondaryEpoch=100+phase,primaryEpoch=100+phase,
                 secondaryEpoch=100+phase,primaryID=400+phase,secondaryID=400+phase,
                 success=True,poisoned=False,retired=False,reason=reason)
        row.update(fields);rows[role].append((NATIVE,row));return row
    for role in ROLES:emit(role,'setup',0,nativeMenuHost=True)
    for phase in (1,2,3):
        owner=6+phase;cart=400+phase;cargo=500+phase
        for role in ROLES:
            native(role,'baseline',phase,'admitted-current')
            if phase>1:
                emit(role,'transition',phase,before=lifetime(role,phase-1),after=lifetime(role,phase),actorChanged=True,
                     newNativeActor=True,sameTransport=phase==2 or role=='client1',
                     transportScope='owner-transport' if role=='server' else 'local-client-ingress',ownerID=owner,oldOwnerID=owner-1,cart=cart)
        emit('server','cart-setup',phase,ownerID=owner,cart=cart,cargoID=cargo,cargoWeight=30,
             reusedNativeCart=False,sameCartPreservationClaim=False)
        if phase>1:
            emit('server','native-connection',phase,ownerID=owner,oldOwnerID=owner-1,
                 oldConnectionActive=phase==2,sameTransport=phase==2,guarded=True)
            emit('server','fresh-replay',phase,ownerID=owner-1,lifetime=lifetime('server',phase-1),
                 stalePayloadAccepted=False,cachedActor=True,cachedConnection=True,guarded=True,**ident(phase-1))
        for role in ROLES[1:]:
            nonce=f'{role}-phase-{phase}-fresh';pending=f'{role}-phase-{phase}-pending'
            emit(role,'phase-setup',phase,ownerID=owner,cart=cart,cargoID=cargo,reusedNativeCart=False)
            emit(role,'native-binding',phase,ownerID=owner,cart=cart,cargoID=cargo,cargoWeight=30,
                 lifetime=lifetime(role,phase),localOwner=role=='client2')
            emit(role,'request',phase,ownerID=owner,cart=cart,lifetime=lifetime(role,phase),attempt=1,nonce=nonce)
            emit('server','bind',phase,ownerID=owner,requester=role,lifetime=lifetime('server',phase),
                 attempt=1,nonce=nonce,guarded=True,**ident(phase))
            emit(role,'bound',phase,ownerID=owner,lifetime=lifetime(role,phase),attempt=1,nonce=nonce,
                 seq=1,guarded=True,**ident(phase))
            emit('server','echo',phase,ownerID=owner,requester=role,lifetime=lifetime('server',phase),
                 attempt=1,nonce=nonce,seq=1,guarded=True,accepted=role=='client2',**ident(phase))
            emit(role,'receipt',phase,ownerID=owner,lifetime=lifetime(role,phase),attempt=1,nonce=nonce,
                 seq=1,guarded=True,accepted=role=='client2',**ident(phase))
            if phase>1:
                emit(role,'fresh-nonce-replay',phase,ownerID=owner,lifetime=lifetime(role,phase),guarded=True,
                     staleReplyAccepted=False,stalePayloadAccepted=False,staleNonce=f'{role}-phase-{phase-1}-pending',
                     freshNonce=nonce,**ident(phase-1))
                emit(role,'fresh-replay',phase,ownerID=owner,lifetime=lifetime(role,phase),guarded=True,
                     staleReplyAccepted=False,stalePayloadAccepted=False,**ident(phase-1))
            if phase<3:
                emit(role,'prepare',phase,ownerID=owner,cart=cart,lifetime=lifetime(role,phase),attempt=1,nonce=pending)
                emit('server','prepared',phase,ownerID=owner,requester=role,lifetime=lifetime('server',phase),
                     attempt=1,nonce=pending,guarded=True,**ident(phase))
            else:emit(role,'done',phase,ownerID=owner,cart=cart,lifetime=lifetime(role,phase))
        if phase<3:
            for role in ROLES:
                emit(role,'transition-start',phase,ownerID=owner,cart=cart,lifetime=lifetime(role,phase),
                     reason='programmatic-native-kill' if phase==1 else 'native-menu-exit')
                if phase==1:
                    if role=='client2':emit(role,'native-kill',phase,ownerID=owner,cart=cart,lifetime=lifetime(role,phase),programmaticNativeKill=True)
                    native(role,'retire',phase,'actor-death',revision=2,hardRevision=2,retired=True)
                    emit(role,'native-death',phase,ownerID=owner,lifetime=lifetime(role,phase),nativeLifetimeAbsent=True,
                         eventSource='OnCharacterDeath',programmaticNativeKill=True)
                native(role,'retire',phase,'actor-remove',revision=3 if phase==1 else 2,retired=True)
                if phase==2 and role!='client1':native(role,'retire',phase,'connection-remove',revision=3,retired=True)
                emit(role,'native-removed',phase,ownerID=owner,lifetime=lifetime(role,phase),nativeCorpse=phase==1,nativeRemovalWitness='new-native-corpse' if phase==1 else None,
                     corpseCount=1 if phase==1 else 0,hasSquare=False,onlineList=False,oldActorDead=phase==1)
                emit(role,'unavailable-replay',phase,ownerID=owner,lifetime=lifetime(role,phase),stalePayloadAccepted=False,
                     staleReplyAccepted=False,guarded=True,nativeLifetimeAbsent=True,**ident(phase))
                emit(role,'cart-disposition',phase,ownerID=owner,cart=cart,lifetime=lifetime(role,phase),cargoID=cargo,
                     cargoWeight=30,cartLocation='corpse-container' if phase==1 else 'native-container',sameCartPreservationClaim=False)
            if phase==1:
                for panel in ('post-death','profession','character'):emit('client2','respawn-ui',phase,panel=panel,nativeCallback=True)
                emit('client2','native-create',phase,ownerID=owner+1,index=0,eventSource='OnCreatePlayer',newNativeActor=True)
            else:
                emit('client2','native-exit',phase,ownerID=owner,lifetime=lifetime('client2',phase),nativeExitToMenu=True)
                emit('client2','native-reconnect',3,nativeConnectToServer=True,checkpoint='pending')
                emit('client2','native-rejoin',3,nativeConnected=True,checkpoint='pending')
    for role in ROLES[1:]:
        emit(role,'final-ack',3,ownerID=9,cart=403,lifetime=lifetime(role,3),guarded=True)
        emit('server','final-ack',3,ownerID=9,requester=role,lifetime=lifetime(role,3),guarded=True)
    for role in ROLES:
        emit(role,'complete',3,ownerID=9,cart=403,lifetime=lifetime(role,3),ok=True)
        rows[role].append(('',f'[CART_LIFECYCLE] COMPLETE actor={role}'))
    return selection,rows


class LeaseLifecycleEvidenceTests(unittest.TestCase):
    def setUp(self):
        temp=tempfile.TemporaryDirectory();self.addCleanup(temp.cleanup);self.root=Path(temp.name)
        self.selection,self.rows=fixture();self.checkpoint='verified'
    def selected(self,role,event,phase=None,marker=MARKER):
        return [r for m,r in self.rows[role] if m==marker and r['event']==event and (phase is None or r.get('phase')==phase)]
    def row(self,role,event,phase=None,marker=MARKER):return self.selected(role,event,phase,marker)[0]
    def remove(self,role,event,phase=None,marker=MARKER):
        self.rows[role]=[(m,r) for m,r in self.rows[role] if not (m==marker and r['event']==event and (phase is None or r.get('phase')==phase))]
    def analyze(self):
        (self.root/'selection.json').write_text(json.dumps(self.selection))
        for role,rows in self.rows.items():
            (self.root/(role+'-launch.log')).write_text('\n'.join(m+json.dumps(r) if m else r for m,r in rows)+'\n')
        path=self.root/'client2/Lua/cart-lease-lifecycle-rejoin.txt';path.parent.mkdir(parents=True,exist_ok=True)
        if self.checkpoint is not None:path.write_text(self.checkpoint)
        elif path.exists():path.unlink()
        return API['analyze'](self.root)
    @unittest.skipUnless(shutil.which('luajit'),'LuaJIT required for actual lifecycle controller')
    def test_actual_controller_continues_host_absence_polling_and_preserves_nonce(self):
        base=ROOT/ANALYZER.parent
        result=subprocess.run([shutil.which('luajit'),str(base/'LeaseLifecycleBankCheck.lua'),str(base)],capture_output=True,text=True,timeout=15)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('hostPulseAfterDeathOneSecond=true noncePreserved=true',result.stdout)
    @unittest.skipUnless(shutil.which('luajit'),'LuaJIT required for actual lifecycle controller')
    def test_actual_controller_requires_certified_resnapshot_and_fresh_receipt(self):
        base=ROOT/ANALYZER.parent
        command=[shutil.which('luajit'),str(base/'LeaseLifecycleBankCheck.lua'),str(base),'resnapshot']
        good=subprocess.run(command,capture_output=True,text=True,timeout=15)
        self.assertEqual(good.returncode,0,good.stdout+good.stderr)
        bad=subprocess.run(command+['uncertified'],capture_output=True,text=True,timeout=15)
        self.assertNotEqual(bad.returncode,0)
        self.assertIn('Uncertified equipment transition',bad.stdout+bad.stderr)
    @unittest.skipUnless(shutil.which('luajit'),'LuaJIT required for actual lifecycle controller')
    def test_actual_controller_closes_on_authority_before_delayed_native_death(self):
        base=ROOT/ANALYZER.parent
        for mode in ('normal','resnapshot'):
            result=subprocess.run([shutil.which('luajit'),str(base/'LeaseLifecycleBankCheck.lua'),str(base),mode,'certified','delayed-death'],capture_output=True,text=True,timeout=15)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertIn('delayedHostDeath=true',result.stdout)

    def test_early_authority_close_does_not_claim_local_native_death(self):
        row=self.row('client1','unavailable-replay',1)
        row.update(nativeLifetimeAbsent=False,authoritativeAbsence=True,guarded=True)
        self.assertTrue(self.analyze()['evidenceComplete'])
        row['authoritativeAbsence']=False
        with self.assertRaises(ValueError):self.analyze()

    def test_complete_synthetic_contract_keeps_diagnostic_scope(self):
        result=self.analyze()
        self.assertTrue(result['evidenceComplete']);self.assertTrue(result['diagnosticOnly'])
        self.assertTrue(result['nativeLifecycleVerified']);self.assertFalse(result['animationEquivalencePass'])
        self.assertEqual(result['settledNativeChains'],6)
        epochs=result['nativeEpochs'];self.assertEqual(len({ts[0][0] for ts in epochs.values()}),3)
        for role,ts in epochs.items():
            self.assertEqual(len({t[1] for t in ts}),3);self.assertEqual(ts[0][2],ts[1][2])
            self.assertEqual(ts[1][2]==ts[2][2],role=='client1')
        self.assertIn('No natural-damage',result['scope'])
    def test_online_id_reuse_still_requires_distinct_native_actor_epochs(self):
        for rows in self.rows.values():
            for marker,row in rows:
                if marker:
                    for field in ('ownerID','oldOwnerID','corpseOnlineID'):
                        if field in row:row[field]=7
        self.assertTrue(self.analyze()['evidenceComplete'])
    def test_uncertified_release_parse_is_not_a_native_observer_error(self):
        rows=self.rows['client1']
        pos=next(i for i,(m,r) in enumerate(rows) if m==NATIVE and r['event']=='retire')
        sample=copy.deepcopy(rows[pos][1]);sample.update(event='resnapshot',reason='remote-equip-resnapshot',success=False,certified=False,retired=False)
        rows.insert(pos,(NATIVE,sample))
        self.assertTrue(self.analyze()['evidenceComplete'])
        sample['poisoned']=True
        with self.assertRaises(ValueError):self.analyze()
    def test_guest_reset_can_drop_only_optional_old_lua_replays(self):
        self.remove('client2','unavailable-replay',2);self.remove('client2','fresh-replay',3)
        self.assertEqual(self.analyze()['settledNativeChains'],6)
        for role in ('server','client1'):
            selection,rows=fixture();self.selection,self.rows=selection,rows
            self.remove(role,'unavailable-replay',2)
            with self.subTest(role=role),self.assertRaises(ValueError):self.analyze()
    def test_wait_retry_and_rejoin_ui_are_realistic_auxiliary_events(self):
        # A Wait is settled before the next fresh attempt and never also acquires a grant.
        role='client1';rows=self.rows[role]
        for r in self.selected(role,'request',1)+self.selected(role,'bound',1)+self.selected(role,'receipt',1)+self.selected(role,'prepare',1):r['attempt']=2
        for event in ('bind','echo','prepared'):
            next(r for r in self.selected('server',event,1) if r['requester']==role)['attempt']=2
        pos=next(i for i,(m,r) in enumerate(rows) if m==MARKER and r['event']=='request' and r['phase']==1)
        request=dict(actor=role,event='request',phase=1,wall=1,ownerID=7,cart=401,lifetime='1|native-client1|11|201|1',attempt=1,nonce='wait-before-fresh')
        wait=dict(actor=role,event='bind-wait',phase=1,wall=1,ownerID=7,attempt=1,serverEquipmentPending=True)
        rows[pos:pos]=[(MARKER,request),(MARKER,wait)]
        guest=self.rows['client2'];pos=next(i for i,(m,r) in enumerate(guest) if m==MARKER and r['event']=='native-rejoin')
        guest.insert(pos,(MARKER,dict(actor='client2',event='rejoin-ui',phase=3,wall=1,nativeCallback=True)))
        for rows in self.rows.values():
            for i,(m,r) in enumerate(rows):
                if m==MARKER:r['wall']=1000+i*10
        self.assertEqual(self.analyze()['settledNativeChains'],6)
    def test_native_roles_cannot_alias_process_identity(self):
        for m,r in self.rows['client2']:
            if m:
                for key,value in r.items():
                    if isinstance(value,str):r[key]=value.replace('native-client2','native-client1')
        with self.assertRaisesRegex(ValueError,'processes alias'):self.analyze()
    def test_retire_fences_must_target_exact_connection_and_owner(self):
        original=copy.deepcopy(self.rows)
        for role in ROLES:
            for field in ('connectionEpoch','ownerID'):
                self.rows=copy.deepcopy(original);self.row(role,'retire',marker=NATIVE)[field]=999
                with self.subTest(role=role,field=field),self.assertRaises(ValueError):self.analyze()
    def test_transition_tokens_and_native_flags_cannot_be_substituted(self):
        original=copy.deepcopy(self.rows)
        for role in ROLES[1:]:
            for field,value in (('before','1|native-'+role+'|999|999|1'),('after','1|native-'+role+'|999|999|1'),
                    ('actorChanged',False),('sameTransport',False)):
                self.rows=copy.deepcopy(original);self.row(role,'transition',2)[field]=value
                with self.subTest(role=role,field=field),self.assertRaises(ValueError):self.analyze()
    def test_unknown_or_wrong_old_transport_activity_cannot_pass(self):
        original=copy.deepcopy(self.rows)
        for phase,value in ((2,None),(2,1),(2,'true'),(2,False),(3,None),(3,0),(3,True)):
            self.rows=copy.deepcopy(original);self.row('server','native-connection',phase)['oldConnectionActive']=value
            with self.subTest(phase=phase,value=value),self.assertRaises(ValueError):self.analyze()
    def test_transport_object_and_epoch_fences_match_each_role(self):
        original=copy.deepcopy(self.rows)
        for phase in (2,3):
            self.rows=copy.deepcopy(original);r=self.row('server','native-connection',phase);r['sameTransport']=not r['sameTransport']
            with self.subTest(field='object',phase=phase),self.assertRaises(ValueError):self.analyze()
        for role in ROLES:
            self.rows=copy.deepcopy(original)
            for m,r in self.rows[role]:
                if m==NATIVE and r['actorEpoch']==13:r['connectionEpoch']=999
            with self.subTest(field='epoch',role=role),self.assertRaises(ValueError):self.analyze()
    def test_stale_acceptance_is_always_rejected(self):
        original=copy.deepcopy(self.rows)
        for role in ROLES:
            for event in ('unavailable-replay','fresh-replay'):
                for field in ('stalePayloadAccepted',) if role=='server' else ('stalePayloadAccepted','staleReplyAccepted'):
                    self.rows=copy.deepcopy(original);self.row(role,event)[field]=True
                    with self.subTest(role=role,event=event,field=field),self.assertRaises(ValueError):self.analyze()
        for role in ROLES[1:]:
            for field in ('staleReplyAccepted','stalePayloadAccepted'):
                self.rows=copy.deepcopy(original);self.row(role,'fresh-nonce-replay',2)[field]=True
                with self.subTest(role=role,event='fresh-nonce-replay',field=field),self.assertRaises(ValueError):self.analyze()
    def test_original_native_death_and_actor_removal_hooks_are_required(self):
        original=copy.deepcopy(self.rows)
        for role in ROLES:
            for phase,reason in ((1,'actor-death'),(1,'actor-remove'),(2,'actor-remove')):
                self.rows=copy.deepcopy(original)
                self.rows[role]=[(m,r) for m,r in self.rows[role] if not (m==NATIVE and r['event']=='retire' and r['actorEpoch']==10+phase and r['reason']==reason)]
                with self.subTest(role=role,phase=phase,reason=reason),self.assertRaises(ValueError):self.analyze()
    def test_guest_and_server_connection_removal_hooks_are_required(self):
        original=copy.deepcopy(self.rows)
        for role in ('server','client2'):
            self.rows=copy.deepcopy(original)
            self.rows[role]=[(m,r) for m,r in self.rows[role] if not (m==NATIVE and r['event']=='retire' and r['reason']=='connection-remove')]
            with self.subTest(role=role),self.assertRaises(ValueError):self.analyze()
    def test_exact_native_held_actor_connection_and_reference_back_tokens(self):
        original=copy.deepcopy(self.rows)
        for role in ROLES:
            for field,value in (('actorEpoch',999),('connectionEpoch',999),('ownerID',999),('primaryEpoch',999),('retired',True),('poisoned',True),('success',False)):
                self.rows=copy.deepcopy(original);self.row(role,'baseline',marker=NATIVE)[field]=value
                with self.subTest(role=role,field=field),self.assertRaises(ValueError):self.analyze()
    def test_guarded_chain_nonce_identity_sequence_and_authority_are_exact(self):
        original=copy.deepcopy(self.rows)
        for role,event,field,value in (('server','bind','nonce','foreign'),('client1','bound','session','foreign'),
                ('server','echo','lease',999),('client2','receipt','grant',999),('client2','bound','seq',99),
                ('server','echo','guarded',False),('client1','receipt','accepted',True),('client2','receipt','accepted',False)):
            self.rows=copy.deepcopy(original);self.row(role,event,1)[field]=value
            with self.subTest(role=role,event=event,field=field),self.assertRaises(ValueError):self.analyze()
    def test_prepared_stale_nonce_and_identity_cannot_be_replaced(self):
        original=copy.deepcopy(self.rows)
        for role in ROLES[1:]:
            for field,value in (('staleNonce','foreign'),('freshNonce','foreign'),('session','foreign'),('guarded',False)):
                self.rows=copy.deepcopy(original);self.row(role,'fresh-nonce-replay',2)[field]=value
                with self.subTest(role=role,field=field),self.assertRaises(ValueError):self.analyze()
            self.rows=copy.deepcopy(original);self.remove(role,'fresh-nonce-replay',2)
            with self.subTest(role=role,field='missing-replay'),self.assertRaises(ValueError):self.analyze()
    def test_corpse_and_exact_native_death_callback_are_required(self):
        original=copy.deepcopy(self.rows)
        for role in ROLES:
            for event,field,value in (('native-removed','nativeCorpse',False),('native-removed','corpseCount',0),
                    ('native-death','nativeLifetimeAbsent',False),('native-death','eventSource','synthetic')):
                self.rows=copy.deepcopy(original);self.row(role,event,1)[field]=value
                with self.subTest(role=role,event=event,field=field),self.assertRaises(ValueError):self.analyze()
    def test_native_create_menu_respawn_callbacks_and_final_ack_are_required(self):
        original=copy.deepcopy(self.rows)
        for event,phase in (('native-create',1),('native-kill',1),('native-exit',2),('native-reconnect',3),('native-rejoin',3)):
            self.rows=copy.deepcopy(original);self.remove('client2',event,phase)
            with self.subTest(event=event),self.assertRaises(ValueError):self.analyze()
        for panel in ('post-death','profession','character'):
            self.rows=copy.deepcopy(original)
            next(r for r in self.selected('client2','respawn-ui',1) if r['panel']==panel)['nativeCallback']=False
            with self.subTest(panel=panel),self.assertRaises(ValueError):self.analyze()
        for role in ROLES:
            self.rows=copy.deepcopy(original);self.remove(role,'final-ack',3)
            with self.subTest(role=role,event='final-ack'),self.assertRaises(ValueError):self.analyze()
    def test_server_final_ack_requires_original_guarded_ingress(self):
        self.row('server','final-ack',3)['guarded']=False
        with self.assertRaises(ValueError):self.analyze()
    def test_native_death_removal_requires_a_new_matching_corpse(self):
        self.row('client1','native-removed',1)['nativeRemovalWitness']='online-list-absence'
        with self.assertRaises(ValueError):self.analyze()
    def test_native_menu_flags_cannot_be_synthetic(self):
        original=copy.deepcopy(self.rows)
        for event,phase,field in (('native-kill',1,'programmaticNativeKill'),('native-create',1,'newNativeActor'),
                ('native-exit',2,'nativeExitToMenu'),('native-reconnect',3,'nativeConnectToServer'),('native-rejoin',3,'nativeConnected')):
            self.rows=copy.deepcopy(original);self.row('client2',event,phase)[field]=False
            with self.subTest(event=event),self.assertRaises(ValueError):self.analyze()
    def test_rejoin_checkpoint_and_all_completion_records_are_required(self):
        original=copy.deepcopy(self.rows)
        for value in ('pending','verified\n',None):
            self.rows=copy.deepcopy(original);self.checkpoint=value
            with self.subTest(checkpoint=value),self.assertRaises((ValueError,FileNotFoundError)):self.analyze()
        self.checkpoint='verified'
        for role in ROLES:
            self.rows=copy.deepcopy(original);self.row(role,'complete',3)['ok']=False
            with self.subTest(role=role),self.assertRaises(ValueError):self.analyze()
    def test_mixed_selection_and_unknown_fixture_events_are_rejected(self):
        for option in ('cart_timeline','cart_lease_control','cart_lease_lifetimes','cart_observer_association'):
            self.selection['options'][option]=True
            with self.subTest(option=option),self.assertRaises(ValueError):self.analyze()
            del self.selection['options'][option]
        self.row('client2','setup')['event']='unrecognized'
        with self.assertRaises(ValueError):self.analyze()
    def test_duplicate_json_keys_and_nonfinite_values_are_rejected(self):
        original=copy.deepcopy(self.rows)
        for marker in (MARKER,NATIVE):
            for raw in ('{"event":"baseline","event":"retire"}', '{"unrelated":NaN}', '{"nested":{"value":Infinity}}', '{"value":1e999}'):
                self.rows=copy.deepcopy(original);self.rows['client1'].append(('',marker+raw))
                with self.subTest(marker=marker,raw=raw),self.assertRaises(ValueError):self.analyze()
    def test_native_and_fixture_clocks_cannot_regress(self):
        original=copy.deepcopy(self.rows)
        for role in ROLES:
            for marker,event,field in ((NATIVE,'retire','monoNs'),(MARKER,'complete','wall')):
                self.rows=copy.deepcopy(original);self.row(role,event,marker=marker)[field]=1
                with self.subTest(role=role,marker=marker),self.assertRaises(ValueError):self.analyze()

    def receipt_resnapshot_fixture(self):
        """Host Bound races with real, exactly certified same-ID remote Equip parsing."""
        role='client1';old='1|native-client1|11|201|1';new='1|native-client1|11|201|3'
        rows=self.rows[role];baseline=copy.deepcopy(self.row(role,'baseline',marker=NATIVE))
        def native(event,revision,depth,serial,reason='primary',**fields):
            row=copy.deepcopy(baseline);row.update(event=event,revision=revision,depth=depth,mutationSerial=serial,
                reason=reason,parseSerial=1,ingressGeneration=1,hardRevision=1);row.update(fields);return (NATIVE,row)
        mutations=[
            native('mutation-enter',2,1,1),
            native('mutation-exit',2,0,1,primaryEpoch=1001),
            native('mutation-enter',3,1,2,'secondary',oldPrimaryEpoch=1001,primaryEpoch=1001),
            native('mutation-exit',3,0,2,'secondary',oldPrimaryEpoch=1001,primaryEpoch=1001,secondaryEpoch=1001),
            native('resnapshot',3,0,0,'remote-equip-resnapshot',primaryEpoch=1001,secondaryEpoch=1001,
                   beforeRevision=1,afterRevision=3,directCalls=2,genericCalls=0,certified=True),
        ]
        receipt=self.row(role,'receipt',1);receipt.update(event='receipt-resnapshot',before=old,after=new,
            lifetime=new,nativeCertified=True,freshNativeProof=False)
        at=next(i for i,(m,r) in enumerate(rows) if m==MARKER and r is receipt);rows[at:at]=mutations
        fresh=[]
        for event in ('request','bound','receipt'):
            source=receipt if event=='receipt' else self.row(role,event,1)
            row=copy.deepcopy(source);row.update(event=event,attempt=2,nonce='client1-phase-1-retry',lifetime=new)
            if event in ('bound','receipt'):row['seq']=2
            for field in ('before','after','nativeCertified','freshNativeProof'):row.pop(field,None)
            fresh.append((MARKER,row))
        at=next(i for i,(m,r) in enumerate(rows) if m==MARKER and r is receipt);rows[at+1:at+1]=fresh
        for event in ('bind','echo'):
            source=next(r for r in self.selected('server',event,1) if r['requester']==role)
            row=copy.deepcopy(source);row.update(attempt=2,nonce='client1-phase-1-retry')
            if event=='echo':row['seq']=2
            server=self.rows['server'];at=next(i for i,(m,r) in enumerate(server) if m==MARKER and r['event']=='prepared' and r['phase']==1 and r['requester']==role)
            server.insert(at,(MARKER,row))
        self.row(role,'prepare',1).update(attempt=2,lifetime=new)
        next(r for r in self.selected('server','prepared',1) if r['requester']==role)['attempt']=2
        for event in ('transition-start','native-death','native-removed','unavailable-replay','cart-disposition'):
            for row in self.selected(role,event,1):row['lifetime']=new
        self.row(role,'transition',2)['before']=new
        for role_rows in self.rows.values():
            for i,(marker,row) in enumerate(role_rows):
                if marker==MARKER:row['wall']=1000+i*10
                if marker==NATIVE:row['monoNs']=(i+1)*1000000
        return old,new
    def test_receipt_resnapshot_settles_old_echo_then_requires_fresh_native_retry(self):
        self.receipt_resnapshot_fixture();result=self.analyze()
        self.assertTrue(result['evidenceComplete'])
        self.assertEqual(result['settledNativeChains'],6,'Resnapshot receipt must not count as a fresh native proof')
    def test_receipt_resnapshot_without_fresh_retry_does_not_complete_phase(self):
        self.receipt_resnapshot_fixture()
        for role,events in (('client1',('request','bound','receipt')),('server',('bind','echo'))):
            self.rows[role]=[(m,r) for m,r in self.rows[role] if not (m==MARKER and r['event'] in events and r['phase']==1 and r.get('attempt')==2 and (role=='client1' or r.get('requester')=='client1'))]
        with self.assertRaises(ValueError):self.analyze()
    def test_receipt_resnapshot_requires_exact_raw_parse_certificate(self):
        self.receipt_resnapshot_fixture();original=copy.deepcopy(self.rows)
        for field,value in (('certified',False),('beforeRevision',2),('afterRevision',4),('directCalls',1),('genericCalls',1),('ingressGeneration',0)):
            self.rows=copy.deepcopy(original);self.row('client1','resnapshot',marker=NATIVE)[field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()
        self.rows=copy.deepcopy(original);self.remove('client1','resnapshot',marker=NATIVE)
        with self.subTest(field='missing-certificate'),self.assertRaises(ValueError):self.analyze()
    def test_receipt_resnapshot_shape_cannot_certify_old_or_wrong_native_state(self):
        self.receipt_resnapshot_fixture();original=copy.deepcopy(self.rows)
        for field,value in (('nativeCertified',False),('guarded',False),('freshNativeProof',True),
                ('before','1|native-client1|11|201|2'),('after','1|native-client1|11|201|4'),
                ('lifetime','1|native-client1|11|201|1')):
            self.rows=copy.deepcopy(original);self.row('client1','receipt-resnapshot',1)[field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()
    def test_stale_normal_receipt_cannot_count_as_new_native_proof(self):
        old,_=self.receipt_resnapshot_fixture();receipt=self.row('client1','receipt-resnapshot',1)
        receipt.update(event='receipt',lifetime=old)
        for field in ('before','after','nativeCertified','freshNativeProof'):receipt.pop(field,None)
        with self.assertRaises(ValueError):self.analyze()



if __name__=='__main__':unittest.main()
