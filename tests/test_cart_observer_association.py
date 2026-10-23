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
        self.params=[]

    def events(self,role,event):
        return [row for row in self.rows[role] if row['event']==event]

    def write(self):
        (self.root/'selection.json').write_text(json.dumps(self.selection))
        for role in API['ROLES']:
            lines = self.base[role][:]
            for group in (('native','query') if role=='server' else ('owner',) if role=='client1' else ()):
                lines += [PRIOR['MARKERS'][group]+json.dumps(row) for row in self.admission[group]]
            lines += [MARKER+json.dumps(row) for row in sorted(self.rows[role],key=lambda row:row['monoNs'])]
            if role == 'client2':
                lines += [API['PARAMS_MARKER']+json.dumps(row) for row in sorted(self.params,key=lambda row:row['monoNs'])]
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

    def new_schema(self):
        for values in self.rows.values():
            for row in values:
                row.update(associationKind='packet-apply' if row['proxyEpoch'] else 'unavailable',
                           actionEpoch=row['proxyEpoch'],consumeGeneration=0,paramsMapEpoch=0,paramsRevision=0)
        for row in self.timeline:
            row.update(observerVersion=2,observerAssociationKind='packet-apply',observerConsumeGeneration=0,
                       observerParamsMapEpoch=0,observerParamsRevision=0)

    def test_new_packet_apply_schema_remains_exact_without_retained_claim(self):
        self.new_schema()
        result=self.analyze()
        self.assertTrue(result['evidenceComplete'])

    def test_partial_or_mixed_association_schema_is_rejected(self):
        original=copy.deepcopy(self.rows)
        for missing in API['ASSOCIATION_FIELDS']:
            self.rows=copy.deepcopy(original);self.new_schema()
            del self.events('client2','proxy-associate')[0][missing]
            with self.subTest(missing=missing),self.assertRaises(ValueError):self.analyze()

    def test_new_frozen_fields_are_immutable_across_body_cart_and_pose_keys(self):
        self.new_schema();original=copy.deepcopy(self.timeline)
        for field in API['SNAP_PARAMS']:
            self.timeline=copy.deepcopy(original)
            row=next(row for row in self.timeline if row['part']=='cart')
            row[field]=1 if type(row[field]) is int else 'retained-params'
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()

    def retained_schema(self):
        self.new_schema()
        for index, original in enumerate(self.events('client2','proxy-associate')[:],1):
            apply=next(row for row in self.events('client2','state-apply') if row['applyGeneration']==original['applyGeneration'])
            at=apply['monoNs'];top=900000+index*10;nested=top+1;generation=top+2
            common=dict(protocol=1,process=OBSERVER,actorEpoch=original['actorEpoch'],mapKind='params',mapEpoch=top,
                        revision=7,variablesEpoch=top+3,variablesMapEpoch=nested,variablesRevision=0,
                        packetEpoch=original['packetEpoch'],applyGeneration=original['applyGeneration'],
                        consumeGeneration=0,stateTag=original['stateTag'],sourceLife=original['sourceLife'],
                        actionEpoch=0,success=True,bound=False,reason='test-native-boundary',
                        loadedParamMask=127,nativeDefaultMask=0,defaultConsumerGeneration=0)
            def emit(event,offset,**changes):
                row=dict(common,event=event,monoNs=at+offset);row.update(changes);self.params.append(row);return row
            emit('params-birth',-5000,revision=0)
            emit('params-birth',-4500,mapKind='variables',actorEpoch=0,mapEpoch=nested,revision=0)
            emit('params-invalidate',-4000)
            emit('params-load',-1000,bound=True)
            emit('params-consume-begin',1000,bound=False,consumeGeneration=generation)
            action=top+4
            emit('params-consume',2000,bound=True,consumeGeneration=generation,actionEpoch=action)
            oldstop=next(row for row in self.events('client2','proxy-stop') if row['proxyEpoch']==original['proxyEpoch'])
            self.rows['client2'].remove(oldstop)
            self.rows['client2'].append(dict(oldstop,event='proxy-replaced',proxyState='replaced',proxyCurrent=False,
                                             reason='native-replacement',monoNs=at+1500))
            new=dict(original,proxyEpoch=top+5,actionEpoch=action,consumeGeneration=generation,paramsMapEpoch=top,
                     paramsRevision=7,associationKind='retained-params',associationValid=True,
                     reason='exact-retained-params-consumer',monoNs=at+3000)
            self.rows['client2'].append(new)
            self.rows['client2'].append(dict(new,event='proxy-stop',proxyState='stopped',associationValid=False,
                                             reason='native-stop',monoNs=oldstop['monoNs']))
            for row in self.timeline:
                if row['captureId']==index:
                    row.update(observerProxyEpoch=new['proxyEpoch'],observerAssociationKind='retained-params',
                               observerConsumeGeneration=generation,observerParamsMapEpoch=top,observerParamsRevision=7)

    def param_events(self,event):
        return [row for row in self.params if row['event']==event]

    def test_six_retained_consumers_share_original_applies_and_cover_active_draws(self):
        self.retained_schema();result=self.analyze()
        self.assertTrue(result['evidenceComplete'])
        self.assertTrue(result['retainedParamsEvidenceAvailable'])
        self.assertEqual(result['retainedParamsConsumerAssociations'],6)
        self.assertEqual(result['proxyAssociations'],12)
        self.assertEqual(result['activeFrozenPhaseCount'],6)
        self.assertEqual([phase['stateRevisions'] for phase in result['phases']],[1]*6)
        self.assertEqual(len(self.events('client2','state-apply')),6)

    def test_legacy_logs_explicitly_have_no_retained_parameter_proof(self):
        result=self.analyze()
        self.assertFalse(result['retainedParamsEvidenceAvailable'])
        self.assertEqual(result['retainedParamsConsumerAssociations'],0)

    def test_retained_load_requires_both_map_births_and_exact_native_packet_apply(self):
        self.retained_schema();original=copy.deepcopy(self.params)
        for missing in ('params','variables'):
            self.params=copy.deepcopy(original)
            birth=next(row for row in self.param_events('params-birth') if row['mapKind']==missing)
            self.params.remove(birth)
            with self.subTest(missing=missing),self.assertRaises(ValueError):self.analyze()
        for field,value in (('actorEpoch',999),('packetEpoch',999),('applyGeneration',999),
                            ('variablesEpoch',999),('variablesMapEpoch',999),('variablesRevision',999),
                            ('process',OWNER),('stateTag','other'),('sourceLife','other')):
            self.params=copy.deepcopy(original);self.param_events('params-load')[0][field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()

    def test_overwrite_unmarked_load_or_alias_escape_forbids_retained_binding(self):
        self.retained_schema();original=copy.deepcopy(self.params)
        for event,nested in (('params-invalidate',False),('params-invalidate',True),('params-load',False),
                             ('params-escape',False),('params-escape',True)):
            self.params=copy.deepcopy(original);load=self.param_events('params-load')[0]
            changed=dict(load,event=event,bound=False,revision=load['revision']+1,monoNs=load['monoNs']+1)
            if nested:changed.update(mapKind='variables',actorEpoch=0,mapEpoch=load['variablesMapEpoch'],revision=1)
            self.params.append(changed)
            with self.subTest(event=event,nested=nested),self.assertRaises(ValueError):self.analyze()

    def test_escape_is_permanent_even_after_a_later_exact_tagged_reload(self):
        self.retained_schema();load=self.param_events('params-load')[0]
        self.params.append(dict(load,event='params-escape',bound=False,revision=8,monoNs=load['monoNs']-2))
        self.params.append(dict(load,event='params-load',bound=True,revision=8,monoNs=load['monoNs']-1))
        with self.assertRaisesRegex(ValueError,'unescaped'):self.analyze()

    def test_unknown_prebirth_alias_and_revision_rollback_cannot_be_healed(self):
        self.retained_schema();original=copy.deepcopy(self.params)
        birth=self.param_events('params-birth')[0]
        self.params.remove(birth)
        self.params.append(dict(birth,event='params-escape',revision=1,monoNs=birth['monoNs']))
        with self.assertRaises(ValueError):self.analyze()
        self.params=copy.deepcopy(original)
        self.param_events('params-invalidate')[0]['revision']=0
        with self.assertRaisesRegex(ValueError,'advance'):self.analyze()

    def test_consume_requires_successful_unique_begin_exit_and_exact_action(self):
        self.retained_schema();original=copy.deepcopy(self.params)
        for event in ('params-consume-begin','params-consume'):
            for duplicate in (False,True):
                self.params=copy.deepcopy(original);row=self.param_events(event)[0]
                if duplicate:self.params.append(copy.deepcopy(row))
                else:self.params.remove(row)
                with self.subTest(event=event,duplicate=duplicate),self.assertRaises(ValueError):self.analyze()
        for field,value in (('actionEpoch',999),('success',False),('bound',False),('consumeGeneration',999),
                            ('revision',8),('actorEpoch',999),('variablesRevision',1)):
            self.params=copy.deepcopy(original);self.param_events('params-consume')[0][field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()

    def test_retained_proxy_cannot_precede_consumer_or_reuse_its_generation(self):
        self.retained_schema();retained=[row for row in self.events('client2','proxy-associate') if row['associationKind']=='retained-params']
        original=copy.deepcopy(self.rows)
        retained[0]['monoNs']=self.param_events('params-consume')[0]['monoNs']-1
        with self.assertRaisesRegex(ValueError,'consumer'):self.analyze()
        self.rows=copy.deepcopy(original)
        first=next(row for row in self.events('client2','proxy-associate') if row['associationKind']=='retained-params')
        self.rows['client2'].append(dict(first,proxyEpoch=999999,actionEpoch=999998))
        with self.assertRaisesRegex(ValueError,'unique'):self.analyze()

    def test_retained_retirement_and_missing_draws_stay_strict(self):
        self.retained_schema();original=copy.deepcopy(self.timeline)
        self.timeline=[row for row in self.timeline if row['captureId']!=2]
        result=self.analyze();self.assertFalse(result['evidenceComplete']);self.assertEqual(result['activeFrozenPhaseCount'],5)
        self.timeline=original
        stop=next(row for row in self.events('client2','proxy-stop') if row['associationKind']=='retained-params')
        for row in self.timeline:
            if row['captureId']==1:row.update(nativeMonoNs=stop['monoNs']+10,monoNs=stop['monoNs']+20)
        with self.assertRaisesRegex(ValueError,'revived'):self.analyze()

    def test_distinct_later_consumers_can_reuse_one_unchanged_loaded_revision(self):
        self.retained_schema()
        first=next(row for row in self.events('client2','proxy-associate') if row['associationKind']=='retained-params')
        consume=self.param_events('params-consume')[0]
        captured=[row for row in self.timeline if row['captureId']==1]
        at=captured[0]['nativeMonoNs']+1000;generation=consume['consumeGeneration']+100
        self.params.append(dict(consume,event='params-consume-begin',bound=False,actionEpoch=0,
                                consumeGeneration=generation,monoNs=at))
        self.params.append(dict(consume,consumeGeneration=generation,actionEpoch=consume['actionEpoch']+100,monoNs=at+10))
        new=dict(first,consumeGeneration=generation,actionEpoch=consume['actionEpoch']+100,
                 proxyEpoch=first['proxyEpoch']+100,monoNs=at+20)
        self.rows['client2'].append(new)
        stop=next(row for row in self.events('client2','proxy-stop') if row['proxyEpoch']==first['proxyEpoch'])
        self.rows['client2'].remove(stop)
        self.rows['client2'].append(dict(stop,event='proxy-replaced',proxyState='replaced',proxyCurrent=False,
                                        reason='native-replacement',monoNs=at+5))
        self.rows['client2'].append(dict(new,event='proxy-stop',proxyState='stopped',associationValid=False,
                                        reason='native-stop',monoNs=stop['monoNs']))
        for row in copy.deepcopy(captured):
            row.update(captureId=7,observerConsumeGeneration=generation,observerProxyEpoch=new['proxyEpoch'],
                       nativeMonoNs=at+30,monoNs=at+31+{'both':0,'body':1,'cart':2}[row['part']])
            self.timeline.append(row)
        result=self.analyze()
        self.assertEqual(result['retainedParamsConsumerAssociations'],7)
        self.assertEqual(result['phases'][0]['activeFrozenBodyCartPairs'],2)
        self.assertEqual(len(self.events('client2','state-apply')),6)

    def test_native_action_epoch_cannot_be_reused_by_another_proxy(self):
        self.retained_schema()
        first=next(row for row in self.events('client2','proxy-associate') if row['associationKind']=='retained-params')
        self.rows['client2'].append(dict(first,proxyEpoch=999999))
        with self.assertRaisesRegex(ValueError,'Native action reused'):self.analyze()

    def test_unbound_consume_failure_remains_diagnostic_even_when_its_revision_changed(self):
        self.retained_schema();base=self.param_events('params-consume')[-1];at=base['monoNs']+1000
        begin=dict(base,event='params-consume-begin',bound=False,actionEpoch=0,consumeGeneration=999999,monoNs=at)
        self.params.append(begin)
        self.params.append(dict(begin,event='params-consume',success=False,revision=base['revision']+1,
                                mapEpoch=0,mapKind='none',monoNs=at+1))
        result=self.analyze();self.assertTrue(result['evidenceComplete'])
        self.assertEqual(result['retainedParamsConsumerAssociations'],6)

    def test_retained_metadata_guards_do_not_accept_numeric_truthiness(self):
        self.retained_schema();original=copy.deepcopy(self.params)
        for field in ('success','bound'):
            self.params=copy.deepcopy(original);self.param_events('params-consume')[0][field]=1
            with self.subTest(field=field),self.assertRaisesRegex(ValueError,'booleans'):self.analyze()

    def deferred_defaults(self, mask=8):
        self.retained_schema()
        for load in self.param_events('params-load')[:]:
            apply=next(row for row in self.events('client2','state-apply') if row['applyGeneration']==load['applyGeneration'])
            at=apply['monoNs'];generation=load['mapEpoch']+8
            related=[row for row in self.params if row['mapEpoch']==load['mapEpoch']]
            birth=next(row for row in related if row['event']=='params-birth')
            birth['monoNs']=at-3_000_000
            nested=next(row for row in self.param_events('params-birth') if row['mapEpoch']==load['variablesMapEpoch'])
            nested['monoNs']=at-2_999_000
            mutation=next(row for row in related if row['event']=='params-invalidate')
            mutation.update(monoNs=at-1_800_000,revision=6)
            self.params.append(dict(load,bound=False,revision=6,loadedParamMask=127^mask,nativeDefaultMask=0,
                                    defaultConsumerGeneration=0,reason='pending-native-default',monoNs=at-1_700_000))
            self.params.append(dict(load,event='params-consume-begin',bound=False,actionEpoch=0,revision=6,
                                    consumeGeneration=generation,loadedParamMask=0,nativeDefaultMask=0,
                                    defaultConsumerGeneration=0,monoNs=at-1_500_000))
            self.params.append(dict(load,event='params-invalidate',bound=False,consumeGeneration=generation,
                                    loadedParamMask=0,nativeDefaultMask=0,defaultConsumerGeneration=0,
                                    reason='Param.get-default:secondary',monoNs=at-1_400_000))
            for row in self.params:
                if row['mapEpoch']==load['mapEpoch'] and row['event'] in ('params-consume','params-consume-begin') and row['consumeGeneration']!=generation:
                    row.update(loadedParamMask=127^mask,nativeDefaultMask=mask,defaultConsumerGeneration=generation)
            load.update(loadedParamMask=127^mask,nativeDefaultMask=mask,defaultConsumerGeneration=generation)
            self.params.append(dict(load,event='params-consume',bound=False,consumeGeneration=generation,
                                    actionEpoch=apply['actionEpoch'],reason='non-retained-apply',monoNs=at-2000))

    def test_omitted_native_hand_slots_bind_only_after_original_default_consumer(self):
        for mask in (4,8,12):
            self.params=[];self.selection,self.base,self.admission,self.rows,self.timeline=fixture()
            self.deferred_defaults(mask)
            with self.subTest(mask=mask):
                report=self.analyze()
                self.assertTrue(report['evidenceComplete'])
                self.assertEqual(report['retainedParamsConsumerAssociations'],6)
                self.assertEqual(report['originalNativeDefaultCommits'],6)
                self.assertEqual(report['activeFrozenPhaseCount'],6)

    def test_native_default_origin_masks_are_complete_disjoint_and_supported(self):
        self.deferred_defaults();original=copy.deepcopy(self.params)
        for field,value in (('loadedParamMask',127),('loadedParamMask',0),('nativeDefaultMask',16),
                            ('nativeDefaultMask',True),('defaultConsumerGeneration',0),
                            ('defaultConsumerGeneration',999999),('loadedParamMask',128)):
            self.params=copy.deepcopy(original)
            load=next(row for row in self.param_events('params-load') if row['bound'])
            load[field]=value
            with self.subTest(field=field,value=value),self.assertRaises(ValueError):self.analyze()

    def test_deferred_default_proof_requires_successful_original_action_and_exact_revision(self):
        self.deferred_defaults();original=copy.deepcopy(self.params)
        for field,value in (('actionEpoch',999999),('success',False),('reason','consumer-unbound'),
                            ('revision',99),('variablesRevision',99),('actorEpoch',999999),
                            ('packetEpoch',999999),('loadedParamMask',127),('defaultConsumerGeneration',999999)):
            self.params=copy.deepcopy(original)
            consume=next(row for row in self.param_events('params-consume') if row['reason']=='non-retained-apply')
            consume[field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.analyze()

    def test_deferred_default_generation_cannot_reference_retained_or_future_consumer(self):
        self.deferred_defaults()
        load=next(row for row in self.param_events('params-load') if row['bound'])
        retained=next(row for row in self.param_events('params-consume') if row['bound'])
        generation=retained['consumeGeneration']
        for row in self.params:
            if row['mapEpoch']==load['mapEpoch'] and row.get('defaultConsumerGeneration'):
                row['defaultConsumerGeneration']=generation
        with self.assertRaisesRegex(ValueError,'original packet-apply'):self.analyze()

    def test_custom_supplier_or_unknown_default_does_not_supply_a_committed_load(self):
        self.deferred_defaults();original=copy.deepcopy(self.params)
        for reason in ('custom-default-supplier','unknown-default-origin','foreign-default-context'):
            self.params=copy.deepcopy(original)
            load=next(row for row in self.param_events('params-load') if row['bound'])
            load.update(bound=False,reason=reason)
            with self.subTest(reason=reason),self.assertRaisesRegex(ValueError,'overwrite/unmarked load/unknown alias'):self.analyze()

    def test_deferred_default_cannot_commit_after_apply_or_before_original_consumer_finishes(self):
        self.deferred_defaults();original=copy.deepcopy(self.params)
        for change in ('after-apply','before-consume'):
            self.params=copy.deepcopy(original)
            load=next(row for row in self.param_events('params-load') if row['bound'])
            apply=next(row for row in self.events('client2','state-apply') if row['applyGeneration']==load['applyGeneration'])
            original_consume=next(row for row in self.param_events('params-consume') if row['consumeGeneration']==load['defaultConsumerGeneration'])
            load['monoNs']=apply['monoNs']+1 if change=='after-apply' else original_consume['monoNs']-1
            with self.subTest(change=change),self.assertRaises(ValueError):self.analyze()

    def test_unmarked_load_or_escape_after_native_default_commit_still_revokes_binding(self):
        self.deferred_defaults();original=copy.deepcopy(self.params)
        for event in ('params-load','params-invalidate','params-escape'):
            self.params=copy.deepcopy(original)
            load=next(row for row in self.param_events('params-load') if row['bound'])
            self.params.append(dict(load,event=event,bound=False,revision=8,monoNs=load['monoNs']+1))
            with self.subTest(event=event),self.assertRaises(ValueError):self.analyze()

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
