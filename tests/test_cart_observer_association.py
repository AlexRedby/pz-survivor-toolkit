"""Diagnostic wire evidence regressions; synthetic traces never claim a native run."""
import copy
import json
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'tests/native_queue/contributions/wooden_cart_multiplayer/analyze-observer.py'
API = runpy.run_path(str(SOURCE))
PRIOR = runpy.run_path(str(ROOT/'tests/test_cart_action_admission.py'))
OWNER, SERVER = PRIOR['OWNER'], PRIOR['SERVER']
OBSERVER = '00000000-0000-4000-8000-000000000003'
MARKER = API['MARKER']


def fixture():
    selection, base, admission = PRIOR['fixture']()
    selection['options'].update(cart_observer_association=True, cart_timeline=True)
    rows = {role: [] for role in API['ROLES']}; timeline = []
    for index in range(1, 7):
        wall = 116000+index*2000
        begin = index*10000
        source = f'1|{OWNER}|111|121|{100+index}|{200+index}|{begin}'
        tag = source+'|'+str(begin+10)
        for group in ('owner', 'query'):
            for row in admission[group]:
                if row['index'] == index and row['event'] != 'track': row['observerSource'] = source
        common = dict(protocol=1, diagnosticWire=True, owner=7, sourceLife=source, stateTag=tag,
            sourceProcess=OWNER, sourceActorEpoch=111, sourceConnectionEpoch=121,
            sourceNativeEpoch=100+index, sourceTableEpoch=200+index, sourceBeginGeneration=begin,
            stateGeneration=begin+10, peerRole='unavailable', stage='Enter', reason='native-process',
            packetEpoch=begin+11, ingressGeneration=0, receiveGeneration=0, sendGeneration=0,
            parentReceiveGeneration=0, proxyEpoch=0, applyGeneration=0, proxyState='unavailable',
            proxyCurrent=False, associationValid=False, transportValidated=False, sourceValidated=True,
            bodyBegin=0, bodyEnd=0, packetBytes=0, success=True, wallMs=wall)
        def emit(role, event, offset, **changes):
            process = {'client1':OWNER,'server':SERVER,'client2':OBSERVER}[role]
            clock = {'client1':0,'server':-100_000_000_000,'client2':5_000_000_000}[role]
            actor = {'client1':111,'server':11,'client2':211}[role]
            conn = {'client1':0,'server':21,'client2':221}[role]
            row = dict(common, role=role, event=event, process=process, actorEpoch=actor,
                       connectionEpoch=conn, monoNs=int((wall+offset)*1_000_000+clock))
            row.update(changes); rows[role].append(row); return row
        empty = dict(stateTag='',stateGeneration=0,packetEpoch=0,stage='unavailable',connectionEpoch=121,peerRole='server')
        emit('client1','source-begin',0,**empty,reason='native-start-enter')
        emit('client1','source-capture',2,**empty,reason='exact-current-native',wallMs=wall+2)
        emit('client1','source-end',1000,**empty,reason='native-stop' if index in (3,5) else 'native-perform')
        emit('client1','state-set',1,reason='native-set-data')
        write = emit('client1','state-write',3,reason='native-source',connectionEpoch=121,peerRole='server',
                     sendGeneration=begin+12,bodyBegin=3,bodyEnd=203,packetBytes=200,transportValidated=True)
        submit = dict(write,event='state-submit',reason='native-submit',monoNs=write['monoNs']+1)
        rows['client1'].append(submit)
        receipt = dict(packetEpoch=begin+20,ingressGeneration=begin+21,receiveGeneration=begin+22,
                       peerRole='client1',transportValidated=True,sourceValidated=False)
        emit('server','state-parse',4,**receipt,reason='native-parse',bodyBegin=0,bodyEnd=200,packetBytes=200)
        receipt['sourceValidated']=True
        emit('server','state-process-server',6,**receipt,parentReceiveGeneration=begin+22)
        relay = dict(receipt,connectionEpoch=31,peerRole='client2',parentReceiveGeneration=begin+22,
                     sendGeneration=begin+23,bodyBegin=3,bodyEnd=203,packetBytes=200)
        emit('server','state-write',5,**relay,reason='native-relay')
        emit('server','state-submit',5.001,**relay,reason='native-submit')
        recv = dict(packetEpoch=begin+30,ingressGeneration=begin+31,receiveGeneration=begin+32,
                    peerRole='server',transportValidated=True,sourceValidated=False)
        emit('client2','state-parse',7,**recv,reason='native-parse',bodyBegin=0,bodyEnd=200,packetBytes=200)
        proxy = dict(recv,proxyEpoch=begin+34,applyGeneration=begin+33,proxyState='active',proxyCurrent=True)
        association = emit('client2','proxy-associate',8,**proxy,reason='exact-apply-set-action')
        emit('client2','state-apply',9,**proxy,associationValid=True,reason='native-apply')
        emit('client2','state-process-client',10,**recv,applyGeneration=begin+33)
        emit('client2','proxy-stop',1000,**dict(proxy,proxyState='stopped'),reason='native-stop')
        snapshot = dict(observerVersion=1,observerDiagnosticWire=True,observerProcess=OBSERVER,
                        observerSourceLife=source,observerStateTag=tag,observerStateGeneration=begin+10,
                        observerPacketEpoch=begin+30,observerIngressGeneration=begin+31,observerReceiveGeneration=begin+32,
                        observerApplyGeneration=begin+33,observerProxyEpoch=begin+34,observerProxyState='active',
                        observerProxyCurrent=True,observerAssociationValid=True,observerReason='state-apply')
        native_at = (wall+12)*1_000_000+5_000_000_000
        for key in ('ToolkitCartPose','ToolkitCartActionPose'):
            for event,part,offset in (('capture-prepared','both',1),('draw-consumed','body',2),('draw-consumed','cart',3)):
                timeline.append(dict(snapshot,schema=1,event=event,actor='client2',seq=0,
                    monoNs=native_at+offset,serverNs=0,wallMs=wall+12,clockReady=False,ownerID=7,
                    captureId=index,slotToken=44,key=key,raw=None,clear=True,part=part,
                    preparedPrimary=42,preparedSecondary=42,nativeMonoNs=native_at,nativeServerNs=0,nativeClockReady=False))
    return selection,base,admission,rows,timeline


class ObserverAssociationEvidence(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.selection,self.base,self.admission,self.rows,self.timeline = fixture()

    def events(self,role,event):
        return [row for row in self.rows[role] if row['event']==event]

    def write(self):
        (self.root/'selection.json').write_text(json.dumps(self.selection))
        for role in API['ROLES']:
            lines = self.base[role][:]
            for group in (('native','query') if role=='server' else ('owner',) if role=='client1' else ()):
                lines += [PRIOR['MARKERS'][group]+json.dumps(row) for row in self.admission[group]]
            lines += [MARKER+json.dumps(row) for row in sorted(self.rows[role],key=lambda row:row['monoNs'])]
            (self.root/(role+'-launch.log')).write_text('\n'.join(lines)+'\n')
        path=self.root/'client2';path.mkdir(exist_ok=True)
        rows=sorted(self.timeline,key=lambda row:row['monoNs'])
        rows=rows+[dict(schema=1,event='trace-end',actor='client2',seq=0,monoNs=rows[-1]['monoNs']+1,
                        serverNs=0,clockReady=False,wallMs=0,ownerID=7,failed=False)]
        for index,row in enumerate(rows,1):row['seq']=index
        (path/'cart-timeline.jsonl').write_text('\n'.join(json.dumps(row) for row in rows)+'\n')

    def analyze(self):
        self.write();return API['analyze'](self.root)

    def test_six_exact_source_proxy_and_frozen_pairs_with_unsynchronized_clocks(self):
        result=self.analyze()
        self.assertTrue(result['evidenceComplete']);self.assertTrue(result['alteredDiagnosticWire'])
        self.assertEqual(result['exactSealedSourceAssociations'],6)
        self.assertEqual(result['proxyAssociations'],6)
        self.assertEqual(result['logicalQueryMessages'],dict(total=12,clientToServer=6,serverToClient=6))
        self.assertEqual([row['activeFrozenBodyCartPairs'] for row in result['phases']],[1]*6)
        self.assertIn('not a lease grant',result['qualification'])
        self.assertIn('whole-image/source-age',result['qualification'])
        self.assertNotIn('latencyMs',str(result))
        self.assertNotIn('functionalPass',result)

    def test_existing_admission_prerequisite_is_not_replaced_by_marker(self):
        self.admission['native']=[row for row in self.admission['native'] if row['event']!='accepted']
        with self.assertRaises(ValueError):self.analyze()

    def test_actual_native_source_capture_not_just_owner_provided_echo_is_required(self):
        self.rows['client1'].remove(self.events('client1','source-capture')[0])
        with self.assertRaisesRegex(ValueError,'source capture'):self.analyze()

    def test_sealed_flags_and_selection_are_actual_booleans(self):
        original=copy.deepcopy(self.selection)
        for key in ('cart_observer_association','cart_timeline'):
            for value in (False,1,'true',None):
                self.selection=copy.deepcopy(original);self.selection['options'][key]=value
                with self.subTest(key=key,value=value),self.assertRaises(ValueError):self.analyze()

    def test_owner_query_reply_server_echo_cannot_change_frozen_source(self):
        original=copy.deepcopy(self.admission)
        for group,event in (('owner','query'),('owner','reply'),('query','query')):
            self.admission=copy.deepcopy(original)
            next(row for row in self.admission[group] if row['event']==event)['observerSource']=self.events('client1','source-begin')[1]['sourceLife']
            with self.subTest(group=group,event=event),self.assertRaises(ValueError):self.analyze()

    def test_source_epoch_begin_or_canonical_encoding_cannot_be_substituted(self):
        original=copy.deepcopy(self.rows)
        for field,value in (('sourceActorEpoch',999),('sourceNativeEpoch',999),('sourceBeginGeneration',999),
                            ('sourceLife','1|'+OWNER+'|0111|121|101|201|10000'),('process',SERVER)):
            self.rows=copy.deepcopy(original);self.events('client1','source-capture')[0][field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()

    def test_same_source_cannot_be_reused_for_distinct_sealed_tokens(self):
        source=self.events('client1','source-begin')[0]['sourceLife']
        for group in ('owner','query'):
            for row in self.admission[group]:
                if row['index']==2 and row['event']!='track':row['observerSource']=source
        with self.assertRaisesRegex(ValueError,'reused'):self.analyze()

    def test_repeated_source_state_writes_remain_same_revision_not_unique_delivery(self):
        for role in ('client1','server'):
            for event in ('state-write','state-submit'):
                duplicate=copy.deepcopy(self.events(role,event)[0]);duplicate['sendGeneration']+=100
                duplicate['monoNs']+=100;self.rows[role].append(duplicate)
        result=self.analyze()
        self.assertEqual(result['repeatedSubmissionCandidateSets'],2)
        self.assertEqual(result['successfulDirectedSubmissions'],14)
        self.assertEqual(result['phases'][0]['stateRevisions'],1)

    def test_repeated_enter_creates_multiple_concrete_proxies_without_collapsing_revision(self):
        original=self.events('client2','proxy-associate')[0]
        prior_stop=self.events('client2','proxy-stop')[0];self.rows['client2'].remove(prior_stop)
        replacement=dict(prior_stop,event='proxy-replaced',reason='native-replacement',proxyState='replaced',
                         proxyCurrent=False,monoNs=original['monoNs']+10_000_000)
        self.rows['client2'].append(replacement)
        new=dict(original,proxyEpoch=original['proxyEpoch']+100,applyGeneration=original['applyGeneration']+100,
                 monoNs=replacement['monoNs']+1)
        self.rows['client2'].append(new)
        self.rows['client2'].append(dict(new,event='state-apply',reason='native-apply',associationValid=True,monoNs=new['monoNs']+1))
        stopped=dict(new,event='proxy-stop',reason='native-stop',proxyState='stopped',associationValid=False,
                     monoNs=prior_stop['monoNs'])
        self.rows['client2'].append(stopped)
        extra=copy.deepcopy([row for row in self.timeline if row['captureId']==1])
        for row in extra:
            row.update(captureId=7,observerProxyEpoch=new['proxyEpoch'],observerApplyGeneration=new['applyGeneration'],
                       nativeMonoNs=new['monoNs']+10,monoNs=new['monoNs']+20)
        self.timeline+=extra
        result=self.analyze()
        self.assertEqual(result['phases'][0]['proxyAssociations'],2)
        self.assertEqual(result['phases'][0]['stateRevisions'],1)
        self.assertEqual(result['phases'][0]['activeFrozenBodyCartPairs'],2)

    def test_marker_cannot_change_native_state_stage_across_wire(self):
        for role in ('server','client2'):
            for row in self.rows[role]:
                if row['sourceBeginGeneration']==10000:row['stage']='Enter'
        self.events('client1','state-set')[0]['stage']='Execute'
        self.events('client1','state-write')[0]['stage']='Execute'
        self.events('client1','state-submit')[0]['stage']='Execute'
        with self.assertRaisesRegex(ValueError,'actor/stage'):self.analyze()

    def test_consistent_foreign_server_actor_cannot_match_same_online_id(self):
        for row in self.rows['server']:row['actorEpoch']=999
        with self.assertRaisesRegex(ValueError,'admitted native incarnation'):self.analyze()

    def test_canceled_source_or_relay_write_is_not_successful_transport(self):
        original=copy.deepcopy(self.rows)
        for role in ('client1','server'):
            self.rows=copy.deepcopy(original);self.events(role,'state-submit')[0]['event']='state-cancel'
            with self.subTest(role=role),self.assertRaisesRegex(ValueError,'submission'):self.analyze()

    def test_missing_duplicate_or_orphan_submission_is_rejected(self):
        original=copy.deepcopy(self.rows)
        for event in ('state-write','state-submit'):
            for duplicate in (False,True):
                self.rows=copy.deepcopy(original);row=self.events('server',event)[0]
                if duplicate:self.rows['server'].append(copy.deepcopy(row))
                else:self.rows['server'].remove(row)
                with self.subTest(event=event,duplicate=duplicate),self.assertRaises(ValueError):self.analyze()

    def test_body_span_and_submit_native_identity_must_stay_exact(self):
        original=copy.deepcopy(self.rows)
        for field,value in (('packetBytes',199),('bodyBegin',2),('bodyEnd',2053),('packetEpoch',999),('sendGeneration',999)):
            self.rows=copy.deepcopy(original);self.events('server','state-submit')[0][field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()

    def test_wrong_directed_role_and_server_parent_receive_cannot_match(self):
        original=copy.deepcopy(self.rows)
        for role,event,field,value in (('client1','state-submit','peerRole','client2'),
            ('server','state-write','parentReceiveGeneration',999),('server','state-parse','peerRole','client2'),
            ('client2','state-parse','peerRole','client1')):
            self.rows=copy.deepcopy(original);self.events(role,event)[0][field]=value
            with self.subTest(role=role,event=event),self.assertRaises(ValueError):self.analyze()

    def test_original_ingress_receive_process_and_proxy_guards_are_required(self):
        original=copy.deepcopy(self.rows)
        for role,event,field,value in (('server','state-process-server','sourceValidated',False),
            ('client2','state-parse','ingressGeneration',0),('client2','state-parse','transportValidated',False),
            ('client2','state-apply','success',False),('client2','proxy-associate','proxyCurrent',False),
            ('client2','state-apply','associationValid',False),('client2','state-apply','proxyEpoch',999)):
            self.rows=copy.deepcopy(original);self.events(role,event)[0][field]=value
            with self.subTest(role=role,event=event,field=field),self.assertRaises(ValueError):self.analyze()

    def test_numeric_truthiness_cannot_replace_native_guard(self):
        original=copy.deepcopy(self.rows)
        for field in API['BOOLS']:
            self.rows=copy.deepcopy(original);self.events('client2','state-apply')[0][field]=1
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()

    def test_unobserved_pending_discard_must_not_claim_applied_proxy(self):
        discarded=copy.deepcopy(self.events('client2','state-parse')[0])
        discarded.update(event='state-discard',reason='pending-replaced',monoNs=discarded['monoNs']+1)
        self.rows['client2'].append(discarded)
        with self.assertRaisesRegex(ValueError,'Discarded'):self.analyze()

    def test_every_selected_phase_needs_proxy_and_active_body_cart_draws(self):
        original=copy.deepcopy(self.timeline)
        for missing in ('body','cart','both'):
            self.timeline=[row for row in original if not (row['captureId']==2 and (missing=='both' or row['part']==missing))]
            with self.subTest(missing=missing):
                report=self.analyze()
                self.assertFalse(report['evidenceComplete']);self.assertFalse(report['sampledDrawCoverageComplete'])
                self.assertTrue(report['proxyCoverageComplete']);self.assertEqual(report['activeFrozenPhaseCount'],5)
                self.assertEqual(len(report['failures']),1)

    def test_frozen_body_or_cart_cannot_advance_any_association_field(self):
        original=copy.deepcopy(self.timeline)
        for field in API['SNAPSHOT']:
            self.timeline=copy.deepcopy(original)
            row=next(row for row in self.timeline if row['part']=='cart')
            value=row[field];row[field]=False if value is True else value+1 if type(value) is int else 'changed'
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()

    def test_two_pose_key_views_of_one_slot_cannot_disagree(self):
        for row in self.timeline:
            if row['captureId']==1 and row['key']=='ToolkitCartPose':row['observerReason']='other'
        with self.assertRaisesRegex(ValueError,'Pose-key'):self.analyze()

    def test_correctly_frozen_stopped_retained_pointer_is_diagnostic_not_active(self):
        stopped=copy.deepcopy([row for row in self.timeline if row['captureId']==1])
        stop=self.events('client2','proxy-stop')[0]
        for row in stopped:
            row.update(captureId=7,nativeMonoNs=stop['monoNs']+10,monoNs=stop['monoNs']+20,
                       observerProxyState='stopped',observerProxyCurrent=True,observerAssociationValid=False,observerReason='native-stop')
        self.timeline+=stopped
        result=self.analyze()
        self.assertEqual(result['diagnostics']['inactive-selected-source-pairs'],1)
        self.assertEqual(result['diagnostics']['stopped-retained-current-pairs'],1)
        self.assertEqual(result['phases'][0]['activeFrozenBodyCartPairs'],1)

    def test_stopped_proxy_cannot_be_forged_active_by_reusing_old_exact_marker(self):
        stop=self.events('client2','proxy-stop')[0]
        for row in self.timeline:
            if row['captureId']==1:row.update(nativeMonoNs=stop['monoNs']+10,monoNs=stop['monoNs']+20)
        with self.assertRaisesRegex(ValueError,'revived'):self.analyze()

    def test_frozen_draw_after_native_stop_is_preserved_as_carryover(self):
        carry=copy.deepcopy([row for row in self.timeline if row['captureId']==1])
        stop=self.events('client2','proxy-stop')[0]
        for row in carry:
            row['captureId']=7
            if row['event']=='draw-consumed':row['monoNs']=stop['monoNs']+10
        self.timeline+=carry
        result=self.analyze()
        self.assertEqual(result['phases'][0]['frozenCarryoverBodyCartPairs'],1)
        self.assertEqual(result['phases'][0]['activeFrozenBodyCartPairs'],1)

    def test_local_actor_or_connection_epoch_ambiguity_is_not_nearest_matched(self):
        for row in self.rows['client2']:
            if row['sourceBeginGeneration']==10000:row['actorEpoch']=999
        with self.assertRaisesRegex(ValueError,'incarnations'):self.analyze()

    def test_proxy_must_use_enter_and_exact_successful_apply(self):
        original=copy.deepcopy(self.rows)
        for field,value in (('stage','Execute'),('applyGeneration',999),('receiveGeneration',999),('proxyEpoch',0)):
            self.rows=copy.deepcopy(original);self.events('client2','proxy-associate')[0][field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()

    def test_missing_trace_close_sequence_gap_duplicate_json_and_nonfinite_rejected(self):
        self.write();path=self.root/'client2/cart-timeline.jsonl';original=path.read_text()
        for changed in ('\n'.join(original.splitlines()[:-1]),original.replace('"seq": 1,','"seq": 99,',1),
                        original.replace('"observerVersion": 1','"observerVersion": 1,"observerVersion": 1',1),
                        original.replace('"nativeMonoNs": '+str(self.timeline[0]['nativeMonoNs']),'"nativeMonoNs": NaN',1)):
            path.write_text(changed)
            with self.subTest(changed=changed[:30]),self.assertRaises(ValueError):API['analyze'](self.root)
        path.write_text(original)

    def test_cli_is_read_only_and_preserves_original_trace_outputs(self):
        self.write();files={path:path.read_bytes() for path in self.root.rglob('*') if path.is_file()}
        result=subprocess.run([sys.executable,str(SOURCE),'--profile',str(self.root)],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertTrue(json.loads(result.stdout)['evidenceComplete'])
        self.assertEqual(files,{path:path.read_bytes() for path in self.root.rglob('*') if path.is_file()})


if __name__=='__main__':unittest.main()
