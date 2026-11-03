"""Native bank qualification and causal mutations; fixture controls remain real widgets."""
import argparse
import copy
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from tests.lua_fixture_events import OFFLINE_FIXTURE_EVENTS
import zipfile
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import book_controls as adapter, book_controls_verifier as a
from queue_checks import adapters, native
import check_action_queue as cli


class BookControlTests(unittest.TestCase):
    def test_native_binding_evidence_requires_compiled_sources_and_supported_environment(self):
        value = dict(compatFactories=2, cartFactories=1, canonicalPairs=True, plainEnvironment=True,
                     debugDisabled=True, readOnly=True, scope='source-owned-upvalues-no-guard-calls')
        self.assertEqual(a.native_binding_errors(value), [])
        for key in value:
            changed = dict(value); changed.pop(key)
            self.assertTrue(a.native_binding_errors(changed), key)
        for key in ('canonicalPairs', 'plainEnvironment', 'debugDisabled', 'readOnly'):
            changed = dict(value); changed[key] = False
            self.assertTrue(a.native_binding_errors(changed), key)
        for key, wrong in [('compatFactories', 1), ('cartFactories', 0), ('compatFactories', True), ('scope', 'guard-called')]:
            changed = dict(value); changed[key] = wrong
            self.assertTrue(a.native_binding_errors(changed), key)
        changed = dict(value, error='native observation unavailable')
        self.assertTrue(a.native_binding_errors(changed))
        self.assertTrue(a.native_binding_errors(None))

    def test_extended_binding_evidence_requires_policy_sites_and_canonical_helpers(self):
        value = dict(compatFactories=2, cartFactories=1, canonicalPairs=True, plainEnvironment=True,
                     debugDisabled=True, readOnly=True, scope='source-owned-upvalues-no-guard-calls',
                     policyFactories=2, radioFactories=1, canonicalIpairs=True, canonicalGetmetatable=True)
        self.assertEqual(a.native_binding_errors(value, extended=True), [])
        for key in ('policyFactories', 'radioFactories', 'canonicalIpairs', 'canonicalGetmetatable'):
            changed = dict(value); changed.pop(key)
            self.assertTrue(a.native_binding_errors(changed, extended=True), key)
            changed[key] = False
            self.assertTrue(a.native_binding_errors(changed, extended=True), key)
        selection = self.selection()
        selection['options']['require_extended_native_bindings'] = True
        with self.assertRaises(ValueError): adapter.validate(selection)
        selection['options']['require_native_bindings'] = True
        adapter.validate(selection)
        selection['options']['require_extended_native_bindings'] = 1
        with self.assertRaises(ValueError): adapter.validate(selection)

    def selection(self, kind='mp', mode='toolkit'):
        return dict(suite='book-controls', cases=list(adapter.CASES), kind=kind, mode=mode, clients=1,
                    languages=['EN'], mods=list(adapter.MODS), options=dict(book_controls=True, **({'mp_host': True} if kind == 'mp' else {})))

    def evidence(self, case='worn-bag.move-equip', kind='mp', mode='toolkit'):
        source, original_control = case.split('.', 1); control = a.base_control(original_control); lost = a.capacity_case(original_control); favorite_unmoved = a.favorite_case(original_control) and kind == 'sp'
        device = a.device_only(original_control)
        demote = control == 'demote-reader'
        enabled = mode == 'toolkit'; moving = enabled and (control.startswith('move-') or demote); keep = enabled and control == 'return-child-cancel'
        spec = dict(case=case, source=source, control=original_control, actor=0, targetVolume=.25, initialVolume=.5,
                    front=dict(id=101, type='Base.BookCarpentry1', total=220, initial=218),
                    tail=dict(id=102, type='Base.BookCooking1', total=220, initial=219), pen=dict(id=103, type='Base.Pen'),
                    bag=dict(id=104, type='Base.Bag_Military', location='base:back') if source == 'worn-bag' else False)
        where = 104 if source == 'worn-bag' else source
        items = [dict(id=spec[n]['id'], type=spec[n]['type'], container=where if n == 'front' else 'root', condition=10, favorite=n != 'front' or source != 'world' or a.favorite_case(original_control), count=1) for n in ('front', 'tail', 'pen')]
        if source == 'worn-bag': items.append(dict(id=104, type=spec['bag']['type'], container='root', condition=10, favorite=False, count=1))
        seed = dict(case=case, items=items, worn=[dict(id=104, location='base:back')] if source == 'worn-bag' else [], hands=dict(primary=False, secondary=False),
                    appearance=dict(hair='Long', beard='Scruffy', hairColor=dict(r=.2, g=.4, b=.6), beardColor=dict(r=.6, g=.4, b=.2)),
                    books={n: dict(id=spec[n]['id'], type=spec[n]['type'], pages=spec[n]['initial'], characterPages=spec[n]['initial'], total=220, container=source if n == 'front' else 'root', favorite=n != 'front' or source != 'world' or a.favorite_case(original_control)) for n in ('front', 'tail')},
                    volume=.5, powered=True, bagWorn=source == 'worn-bag')
        spec['baseline'] = copy.deepcopy(seed)
        before = copy.deepcopy(seed); before['books']['front'].update(pages=219, characterPages=219)
        before['books']['front']['container'] = 'root'
        b = dict(case=case, at=10, before=before, reader='reader:1', native='java:1', token=10 if enabled else False,
                 delta=.995, tailRetained=True, volumePending=True, equipPending=True, requested=enabled, drained=True, drainedAt=11)
        acks = []; records = []
        def record(seq, role, item, token, started=True, performed=True):
            typ = {'front': 'ISReadABook', 'tail': 'ISReadABook', 'volume': 'ISRadioAction', 'equip': 'ISEquipWeaponAction', 'pickup': 'ISInventoryTransferAction', 'return': 'ISInventoryTransferAction', 'preparation':'ISQueueActionsAction'}[role]
            r = dict(sequence=seq, role=role, item=item, token=token if enabled else False, type=typ, mode='SetVolume' if role == 'volume' else False,
                     actionRef='reader:1' if seq == 1 else 'lua:' + str(seq), duration=30 if role == 'volume' else 100, nativeSource=True,
                     started=started, progress=started, finishes=[], receipts=[])
            if started:
                r.update(nativeRef='java:' + str(seq), startedAt=seq + 10, allocatedAt=seq + 9,
                         effectiveDuration=r['duration'], durationBefore=r['duration'], durationAfter=r['duration'])
                if performed:
                    r['performedAt'] = seq + 12
                    r['finishes'] = [dict(phase=p, succeeded=True, at=seq + 12) for p in (['perform'] if kind == 'mp' else ['perform', 'complete'])]
                else: r['finishes'] = []
                if kind == 'mp' and role in ('volume', 'equip'):
                    for state in ('started', 'completed'):
                        ack = dict(case=case, sequence=seq, kind=typ, transaction=seq, token='12345678-1234-1234-1234-' + str(seq).zfill(12), state=state, player=0, at=seq + 11)
                        r['receipts'].append(ack); acks.append(ack)
                if role in ('pickup', 'return'):
                    r.update(transaction=seq, transactionDone=True, transactionRejected=False)
            records.append(r);return r
        original = record(1, 'front', 101, 10, performed=not enabled or keep)
        original['startedAt'] = 9
        b['nativeCheckpoint'] = dict(finished=False, forceComplete=False)
        if enabled and not keep:
            original['stopReturned'] = dict(case=case,actionRef=b['reader'],nativeRef=b['native'],item=101,at=11,returned=True,
                queueOwned=True,nativePresent=True,bridgeStopped=True,nativeSource=True,finished=False,forceComplete=False,pages=219)
            original['stoppedRemoval'] = dict(at=11,actionRef=b['reader'],nativeRef=b['native'],sameNative=True,item=101,pages=219,
                queueAbsent=True,nativeAbsent=True,finished=False,forceComplete=False)
        equip = record(2, 'equip', 103, 20, started=enabled or not lost) if not device else None
        volume = record(3, 'volume', False, 30, started=enabled or not lost)
        tail = record(4, 'tail', 102, 40, started=enabled or not lost)
        approach=record(8,'preparation',False,30,started=False,performed=False) if device and enabled else None
        if approach: approach.update(duration=-1,approach=dict(declared=True,owned=True,nativeConstructor=True,nativeResolver=True,ownedStart=True,actor='IsoPlayer@live',targetSquare='IsoGridSquare@tv'))
        if moving:
            resumed = record(5, 'front', 101, 10)
            resume = dict(oldAction=original['actionRef'], newAction=resumed['actionRef'], oldNative=original['nativeRef'], newNative=resumed['nativeRef'],
                          item=101, token=10, startPage=219, pages=219, oldNativeAbsent=True, at=15)
        else: resume = False
        admission = [dict(sequence=r['sequence'], role=r['role'], type=r['type'], token=r['token'], actionRef=r['actionRef'], nativeRef=False, current=r is original, **({'approach':copy.deepcopy(r['approach'])} if 'approach' in r else {})) for r in (original, equip, approach, volume, tail) if r is not None]
        if source != 'root':
            pickup = record(6, 'pickup', 101, 10); returned = record(7, 'return', 101, 10, started=not keep and not lost)
            if lost and kind == 'mp':
                returned.update(started=True,progress=True,nativeRef='java:7',startedAt=17,allocatedAt=16,transaction=7,transactionDone=False,transactionRejected=True,finishes=[dict(phase='stop',at=19)])
                returned['nativeStopEntry'] = dict(case=case, sequence=7, actor=spec['actor'], item=spec['front']['id'], itemType=spec['front']['type'],
                    actionRef=returned['actionRef'], nativeRef=returned['nativeRef'], transaction=7, at=18, point='entry',
                    current=True, nativePresent=True, endpointsExact=True, nativeSource=True, guarded=enabled, done=False, rejected=True, observation=False)
                returned['nativeStopReturned'] = dict(case=case, sequence=7, actor=spec['actor'], item=spec['front']['id'], itemType=spec['front']['type'],
                    actionRef=returned['actionRef'], nativeRef=returned['nativeRef'], transaction=0 if enabled else 7, at=19, point='returned', returned=True, sameNative=True)
            admission.insert(0, dict(sequence=6, role='pickup', type=pickup['type'], token=pickup['token']))
            admission.insert(2, dict(sequence=7, role='return', type=returned['type'], token=returned['token']))
            if device and enabled: admission[2].update(actionRef=returned['actionRef'],nativeRef=False,current=False)
        starts = [1, 2, 5, 3, 4] if moving and control == 'move-equip' else [1, 3, 5, 2, 4] if moving else [1] if lost and not enabled else [1, 2, 3, 4]
        if device: starts = [sequence for sequence in starts if sequence != 2]; b['equipPending'] = False
        b['queue'] = copy.deepcopy([r for r in admission if not (device and enabled and r['role']=='pickup')])
        b['ui'] = dict(source='ActionQueuePanel.List', input='programmatic-drag' if moving else 'programmatic-press-release',
                       header=device and demote or not demote and source != 'root' and control not in ('reader-child-cancel', 'return-child-cancel'), singleton=source == 'root', target=returned['actionRef'] if keep else volume['actionRef'] if demote else original['actionRef'], operation=30 if demote else 10,
                       at=10, acceptedAt=10, hitTested=True, pressCaptured=True, gestureCleared=True, accepted=True, feedback=False,
                       bodyContinues=True, returnAbsent=True, bookRoot=True, operationCancelled=False,
                       decision=dict(reason=False, source=source), dragging=True, movingAction=(original if demote else equip if control == 'move-equip' else volume)['actionRef'],
                       movingAnchor=(original if demote else equip if control == 'move-equip' else volume)['actionRef'], movingToken=10 if demote else 20 if control == 'move-equip' else 30) if enabled else False
        if device and enabled:
            b['ui'].update(commonActiveEdit=False,dropAfter=demote,targetAction=volume['actionRef'] if demote else original['actionRef'],
                target=approach['actionRef'] if demote else original['actionRef'],movingAnchor=original['actionRef'] if demote else approach['actionRef'])
        if keep:
            carried = dict(ref='Literature@carried', id=101, type=spec['front']['type'], container='root')
            identity = dict(requested=copy.deepcopy(carried), carried=copy.deepcopy(carried), rootMatches=1,
                            directRootMatches=1, destinationMatches=0, sameReference=True)
            b['ui']['waiverIdentity'] = dict(schema=1, case=case, actor=0, source=source,
                actionRef=returned['actionRef'], token=returned['token'], beforeAt=9, previewCheckedAt=10, afterAt=10, groupUnchangedAfterCommit=True,
                before=copy.deepcopy(identity), after=copy.deepcopy(identity), previewUnchanged=True, actualReplicaReplacement=False)
        final = a.expected(spec, enabled, b, kind)
        row = dict(event='case', suite='book-controls', kind=kind, mode=mode, actor='client1', id=case, status='passed', reason=False, ids=spec,
                   baseline=copy.deepcopy(seed), authorityBaseline=copy.deepcopy(seed), boundary=b, records=records, starts=starts,
                   resume=resume, tailSnapshot=copy.deepcopy(final), volumeSnapshot=copy.deepcopy(before), equipSnapshot=False if device else copy.deepcopy(before),
                   client=copy.deepcopy(final), server=copy.deepcopy(final), nativeMethodsUnchanged=True, finishedAt=99, reset=False,replicaGaps=[],capacity=False,blockedReturn=False,failureUI=False)
        if lost:
            row['returnSucceeded'] = False
            row['capacity'] = dict(case=case, actor=0, source=source, itemId=101, itemType=spec['front']['type'], before=40,roomBefore=True,frontFavorite=source != 'world', after=0, roomAfter=False, bookRoot=True, requestedAt=11, acceptedAt=10 if enabled else False, at=12, authority=True)
            if enabled:
                row['blockedReturn'] = dict(id=501, itemId=101, itemType=spec['front']['type'], title='Carpentry', reason='server' if kind == 'mp' else 'admission', state='blocked')
                row['failureUI'] = dict(case=case, source='ActionQueuePanel.KeepReturn',input='programmatic-press-callback', id=501,itemId=101,revision=1,count=1,visible=True,idle=True,bookRoot=True,at=20,pressCaptured=True,cleared=True,bookRetained=True)
            else: row['tailSnapshot'] = False; row['nativeDebtAbsent'] = True
        if favorite_unmoved:
            row['returnSucceeded'] = False
            if enabled:
                row['blockedReturn'] = dict(id=501,itemId=101,itemType=spec['front']['type'],title='Carpentry',reason='unmoved',state='blocked')
                row['failureUI'] = dict(case=case,source='ActionQueuePanel.KeepReturn',input='programmatic-press-callback',id=501,itemId=101,revision=1,count=1,visible=True,idle=True,bookRoot=True,at=20,pressCaptured=True,cleared=True,bookRetained=True)
            else: row['nativeDebtAbsent'] = True
        row['performance'] = dict(case=case,timer='getTimestampMs',units='ms',coarse=True,readOnly=True,queueEnabled=enabled,queueCount=len(b['queue']),warmup=3,samples=20,
                                  limits='Tiny fixture, coarse timer; no end-to-end, regression or Host contention qualification.',metrics=[])
        for index,name in enumerate(('evaluateMove','evaluateCancel','previewMove','previewCancel','panelUpdate')):
            row['performance']['metrics'].append(dict(name=name,kind='authoritative' if index<2 else 'advisory',firstUseMs=25,rawMs=[0]*20,
                p95Ms=0,p99Ms=0,p95BudgetMs=2 if index<2 else 1,p99BudgetMs=4 if index<2 else 2,passed=True))
        for index,metric in enumerate(row['performance']['metrics']):
            metric.update(decisionSamples=24 if index<4 else 0,decisionStable=True,decisionClass=('allowed' if enabled else 'denied') if index<4 else 'not-decision')
            observation=dict(allowed=enabled,reason=False if enabled else 'unavailable',mode=False)
            metric['firstDecision']=copy.deepcopy(observation) if index<4 else False
            metric['lastDecision']=copy.deepcopy(observation) if index<4 else False
        row['performance'].update(pathClass='toolkit-observed-decisions' if enabled else 'nativeoff-denial-baseline',authorityAllowed=enabled,positiveTimingClaim=enabled)
        probe = copy.deepcopy(row['performance']);probe.update(queueCount=32,originalQueueCount=len(b['queue']),source='fixture-temporary-native-constructors',
            constructor='ISRadioAction.new',nativeDuration=30,nativeConstructorProof=True,restored=True,queueIdentityUnchanged=True,originalStateUnchanged=True)
        probe['temporary'] = [dict(actionRef='temporary:' + str(i),type='ISRadioAction',mode='SetVolume',duration=30,nativeRef=False,started=False,unexecuted=True,intentPublished=False) for i in range(32-len(b['queue']))]
        row['performance']['probe32'] = probe
        row['tickSpacingMs'] = [16,17,16]
        admitted = dict(case=case, producer='ISInventoryPaneContextMenu.onLiteratureItems/readItem', volumeProducer='RWMVolume.onVolumeChange',
                        equipProducer=False if device else 'ISInventoryPaneContextMenu.equipWeapon', sourceBound=True, queue=admission)
        raw_b = copy.deepcopy(b); raw_b['drained'] = False; raw_b.pop('drainedAt')
        drain = dict(case=case, reader=b['reader'], native=b['native'], at=b['drainedAt'], oldNativeAbsent=True)
        return row, spec, copy.deepcopy(seed), copy.deepcopy(final), [admitted], [raw_b], [drain], acks

    def check(self, evidence, kind='mp', mode='toolkit'):
        row, spec, baseline, final, admissions, boundaries, drains, acks = evidence
        return a.check_case(row, row['id'], self.selection(kind, mode), spec, baseline, final, admissions, boundaries, drains, acks, row.get('capacity') if row.get('capacity') is not False else None,
                            [r['stopReturned'] for r in row['records'] if 'stopReturned' in r])

    def test_all_sources_controls_and_native_controls_qualify(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                for case in adapter.CASES:
                    with self.subTest(kind=kind, mode=mode, case=case):
                        self.assertEqual(self.check(self.evidence(case, kind, mode), kind, mode), [])

    def test_causal_mutations_fail_qualification(self):
        mutations = {
            'pen hand intent lost': lambda r: r['client']['hands'].update(primary=False),
            'unrelated inventory item lost': lambda r: r['client']['items'].pop(),
            'book source not conserved': lambda r: r['server']['books']['front'].update(container='root'),
            'old native not drained': lambda r: r['boundary'].update(drained=False),
            'wrong paid page': lambda r: r['boundary']['before']['books']['front'].update(pages=218),
            'fresh action reused': lambda r: r['resume'].update(newAction=r['resume']['oldAction']),
            'fresh Java reused': lambda r: r['resume'].update(newNative=r['resume']['oldNative']),
            'fresh reader skipped saved page': lambda r: r['resume'].update(startPage=218),
            'wrong fresh item': lambda r: r['resume'].update(item=999),
            'native body reused': lambda r: r['resume'].update(oldNativeAbsent=False),
            'equipment order not promoted': lambda r: r.update(starts=[1, 5, 2, 3, 4]),
            'shortened constructor': lambda r: r['records'][1].update(duration=1),
            'shortened allocation': lambda r: r['records'][1].update(effectiveDuration=1),
            'replaced native callbacks': lambda r: r.update(nativeMethodsUnchanged=False),
            'missing exact outcome': lambda r: r['records'][1]['receipts'].pop(),
            'forged outcome token': lambda r: r['records'][1]['receipts'][1].update(token='bad'),
            'missing perform callback': lambda r: r['records'][1].update(finishes=[]),
            'wrong equip item': lambda r: r['records'][1].update(item=999),
            'UI cross accepted only by API': lambda r: r['boundary']['ui'].update(hitTested=False),
            'UI declined operation': lambda r: r['boundary']['ui'].update(accepted=False),
            'missing real drag anchor': lambda r: r['boundary']['ui'].update(movingAnchor=False),
            'wrong native source': lambda r: r['records'][1].update(nativeSource=False),
            'tail started too soon': lambda r: r.update(starts=[1, 4, 2, 5, 3]),
            'tail pen missing': lambda r: r['tailSnapshot']['hands'].update(primary=False),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name):
                evidence = self.evidence(); mutate(evidence[0]); self.assertTrue(self.check(evidence), name)

    def test_missing_raw_source_chain_and_drains_are_rejected(self):
        for member in (4, 5, 6, 7):
            evidence = self.evidence()
            evidence[member].clear()
            self.assertTrue(self.check(evidence))
        evidence = self.evidence(); evidence[4][0]['queue'].pop(0)
        self.assertTrue(self.check(evidence))
        evidence = self.evidence(); evidence[4][0]['queue'][0]['token'] = 999
        self.assertTrue(self.check(evidence))

    def test_cancellation_and_natural_branch_cannot_swap(self):
        for case in ('root.header-cancel', 'worn-bag.reader-child-cancel', 'world.header-cancel'):
            evidence = self.evidence(case)
            evidence[0]['records'][0]['performedAt'] = 99
            self.assertTrue(self.check(evidence))
        evidence = self.evidence('root.header-cancel', mode='native')
        evidence[0]['boundary']['ui'] = dict(accepted=True)
        self.assertTrue(self.check(evidence, mode='native'))

    def test_exact_native_stop_and_dual_removal_are_required(self):
        mutations = {
            'missing stop': lambda r: r['records'][0].pop('stopReturned'),
            'wrong old action': lambda r: r['records'][0]['stopReturned'].update(actionRef='unrelated'),
            'wrong old native': lambda r: r['records'][0]['stopReturned'].update(nativeRef='unrelated'),
            'wrong item': lambda r: r['records'][0]['stopReturned'].update(item=999),
            'bridge not reached': lambda r: r['records'][0]['stopReturned'].update(bridgeStopped=False),
            'stop returned failure': lambda r: r['records'][0]['stopReturned'].update(returned=False),
            'source replaced': lambda r: r['records'][0]['stopReturned'].update(nativeSource=False),
            'outside queue owner': lambda r: r['records'][0]['stopReturned'].update(queueOwned=False),
            'native already absent at stop': lambda r: r['records'][0]['stopReturned'].update(nativePresent=False),
            'checkpoint completed': lambda r: r['boundary']['nativeCheckpoint'].update(finished=True),
            'checkpoint force completed': lambda r: r['boundary']['nativeCheckpoint'].update(forceComplete=True),
            'stop completed': lambda r: r['records'][0]['stopReturned'].update(finished=True),
            'stop force completed': lambda r: r['records'][0]['stopReturned'].update(forceComplete=True),
            'stop before press': lambda r: r['records'][0]['stopReturned'].update(at=9),
            'page advanced at stop': lambda r: r['records'][0]['stopReturned'].update(pages=220),
            'no dual removal': lambda r: r['records'][0].pop('stoppedRemoval'),
            'Lua queue retained': lambda r: r['records'][0]['stoppedRemoval'].update(queueAbsent=False),
            'native queue retained': lambda r: r['records'][0]['stoppedRemoval'].update(nativeAbsent=False),
            'native replaced': lambda r: r['records'][0]['stoppedRemoval'].update(sameNative=False),
            'removal wrong item': lambda r: r['records'][0]['stoppedRemoval'].update(item=999),
            'removal page advanced': lambda r: r['records'][0]['stoppedRemoval'].update(pages=220),
            'removal future': lambda r: r['records'][0]['stoppedRemoval'].update(at=100),
            'removal completed': lambda r: r['records'][0]['stoppedRemoval'].update(finished=True),
            'removal force completed': lambda r: r['records'][0]['stoppedRemoval'].update(forceComplete=True),
            'perform observed': lambda r: r['records'][0].update(performedAt=11),
            'complete observed': lambda r: r['records'][0].update(finishes=[dict(phase='complete',succeeded=True,at=11)]),
        }
        for case in ('root.header-cancel', 'worn-bag.reader-child-cancel', 'world.move-equip'):
            for kind in ('sp', 'mp'):
                for name, mutate in mutations.items():
                    with self.subTest(case=case, kind=kind, mutation=name):
                        evidence=self.evidence(case,kind);mutate(evidence[0])
                        self.assertTrue(self.check(evidence,kind),name)
        evidence=self.evidence('root.header-cancel')
        row,*_=evidence
        args=[row,row['id'],self.selection(),evidence[1],evidence[2],evidence[3],*evidence[4:8]]
        self.assertTrue(any('stop return/bridge' in e for e in a.check_case(*args,stops=[])))

    def test_failed_fixture_status_does_not_claim_source_mismatch(self):
        evidence=self.evidence('root.header-cancel')
        evidence[0].update(status='failed',reason='frozen timing budget exceeded')
        errors=self.check(evidence)
        self.assertTrue(any('Fixture case failed: frozen timing' in e for e in errors))
        self.assertFalse(any('Exact source, seeded IDs' in e for e in errors))

    def test_optional_return_cross_keeps_reader_and_retires_only_its_exact_return(self):
        for source in ('worn-bag', 'world'):
            case = source + '.return-child-cancel'
            mutations = {
                'reader stopped': lambda r: r['boundary']['ui'].update(bodyContinues=False),
                'return retained': lambda r: r['boundary']['ui'].update(returnAbsent=False),
                'operation cancelled': lambda r: r['boundary']['ui'].update(operationCancelled=True),
                'reader did not finish': lambda r: r['records'][0].pop('performedAt'),
                'retired return ran': lambda r: next(v for v in r['records'] if v['role'] == 'return').update(started=True),
                'return callback ran': lambda r: next(v for v in r['records'] if v['role'] == 'return').update(finishes=[dict(phase='perform', succeeded=True, at=20)]),
                'cross targets reader': lambda r: r['boundary']['ui'].update(target=r['boundary']['reader']),
                'late return resurrected': lambda r: r['client']['books']['front'].update(container=source),
            }
            for name, mutate in mutations.items():
                with self.subTest(source=source, mutation=name):
                    evidence = self.evidence(case); mutate(evidence[0]); self.assertTrue(self.check(evidence))
        self.assertNotIn('root.return-child-cancel', adapter.CASES)

    def test_capacity_loss_requires_exact_retained_debt_and_real_idle_keep(self):
        mutations = {
            'capacity not lost': lambda r: r['capacity'].update(after=40),
            'change before accepted UI': lambda r: r['capacity'].update(requestedAt=9),
            'wrong authority': lambda r: r['capacity'].update(authority=False),
            'wrong exact item': lambda r: r['blockedReturn'].update(itemId=999),
            'revoked obligation': lambda r: r['blockedReturn'].update(state='revoked'),
            'failure silently hidden': lambda r: r['failureUI'].update(visible=False),
            'queue not drained': lambda r: r['failureUI'].update(idle=False),
            'keep not exact': lambda r: r['failureUI'].update(id=999),
            'debt discarded': lambda r: r.update(blockedReturn=False),
            'failed return claimed success': lambda r: r.update(returnSucceeded=True),
            'item lost after keep': lambda r: r['failureUI'].update(bookRetained=False),
            'independent tail discarded': lambda r: r['client']['books']['tail'].update(pages=219),
        }
        for case in adapter.CAPACITY_CASES:
            for name, mutate in mutations.items():
                with self.subTest(case=case, mutation=name):
                    evidence = self.evidence(case); mutate(evidence[0]); self.assertTrue(self.check(evidence))
            native = self.evidence(case, mode='native')
            self.assertEqual(native[0]['starts'], [1]); self.assertIs(native[0]['blockedReturn'], False)
            self.assertEqual(native[0]['client']['books']['tail']['pages'], native[1]['tail']['initial'])

    def test_historical_timing_integrity_is_separate_from_design_acceptance(self):
        self.assertEqual(self.check(self.evidence()), [])  # Slow first-use is separate from warmed samples.
        mutations = {
            'no evidence': lambda r: r.update(performance=False),
            'not read only': lambda r: r['performance'].update(readOnly=False),
            'wrong timer': lambda r: r['performance'].update(timer='fabricated'),
            'wrong warmup': lambda r: r['performance'].update(warmup=0),
            'missing sample': lambda r: r['performance']['metrics'][0]['rawMs'].pop(),
            'nonfinite sample': lambda r: r['performance']['metrics'][0]['rawMs'].__setitem__(0,float('nan')),
            'negative sample': lambda r: r['performance']['metrics'][0]['rawMs'].__setitem__(0,-1),
            'changed frozen budget': lambda r: r['performance']['metrics'][0].update(p99BudgetMs=99),
            'wrong quantile': lambda r: r['performance']['metrics'][0].update(p95Ms=1),
            'false pass claim': lambda r: r['performance']['metrics'][0]['rawMs'].__setitem__(19,5),
            'no tick observations': lambda r: r.update(tickSpacingMs=[]),
        }
        for name,mutate in mutations.items():
            with self.subTest(name=name):
                evidence=self.evidence();mutate(evidence[0]);self.assertTrue(self.check(evidence))
        evidence=self.evidence();metric=evidence[0]['performance']['metrics'][0]
        metric['rawMs'][-1]=5;metric.update(p99Ms=5,passed=False)
        evidence[0]['performance']['positiveTimingClaim']=False
        self.assertEqual(self.check(evidence), [])
        evidence[0].update(status='failed',reason='frozen timing budget exceeded')
        self.assertTrue(any('Fixture case failed' in e for e in self.check(evidence)))

    def test_actual_cli_catalog_selection_and_native_preflight_accept_safe_case_ids(self):
        catalog = cli.load_catalog(['book-controls'])
        self.assertEqual([case['id'] for case in catalog['suites']['book-controls']['cases']], list(adapter.DECLARED_CASES))
        self.assertTrue(all('/' not in case for case in adapter.CASES))
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                with self.subTest(kind=kind, mode=mode):
                    args = argparse.Namespace(suite='book-controls',cases=','.join(adapter.CASES),kind=kind,mode=mode,
                                              mods='selected',language='EN',config=None,mod_source=[],timeout=1800,ports=None)
                    options = dict(book_controls=True, **({'mp_host': True} if kind == 'mp' else {}))
                    selected = cli.selection(args, catalog, options=options)
                    native._validate(selected)
                    adapter.validate(selected)
                    self.assertEqual(selected['cases'], list(adapter.CASES))
                    bad = copy.deepcopy(selected);bad['cases'] = [case.replace('.', '/', 1) for case in bad['cases']]
                    with self.assertRaisesRegex(ValueError, 'Expected nonempty IDs in cases'): native._validate(bad)
                    args.cases = ','.join(bad['cases'])
                    with self.assertRaisesRegex(ValueError, 'Select known unique case IDs'): cli.selection(args, catalog, options=options)

    def test_actual_fixture_accepts_dot_case_parser_before_authority_writes(self):
        lua = shutil.which('luajit')
        if not lua: self.skipTest('LuaJIT not installed')
        source = r"""
isClient=function()return false end
local F=assert(loadfile(arg[1]))()
local player={setPrimaryHandItem=function()error('PASSED_ID_PARSING')end}
for case in arg[2]:gmatch('[^,]+')do
 local ok,problem=pcall(F.prepare,player,case)
 assert(not ok and tostring(problem):find('PASSED_ID_PARSING',1,true),'fixture rejected CLI case '..case..': '..tostring(problem))
 local invalid=case:gsub('%.','/',1)
 ok,problem=pcall(F.prepare,player,invalid)
 assert(not ok and not tostring(problem):find('PASSED_ID_PARSING',1,true),'legacy slash ID reached authority writes')
end
for _,invalid in ipairs({'world.header-cancel-favorite-capacity-lost','world.header-cancel-capacity-lost-favorite','root.header-cancel-favorite','world.reader-child-cancel-favorite','root.header-cancel-capacity-lost'})do
 local ok,problem=pcall(F.prepare,player,invalid);assert(not ok and not tostring(problem):find('PASSED_ID_PARSING',1,true),'invalid suffix reached authority writes')
end
os.exit(0)
"""
        subprocess.run([lua, '-e', OFFLINE_FIXTURE_EVENTS + source, '--', 'unused', str(ROOT / 'tests/native_queue/book-controls/shared/QueueBookControls.lua'), ','.join(adapter.CASES)], check=True)

    def test_32_probe_evidence_and_frozen_budgets_cannot_be_fabricated(self):
        mutations = {
            'missing probe': lambda r: r['performance'].pop('probe32'),
            'wrong size': lambda r: r['performance']['probe32'].update(queueCount=31),
            'wrong original size': lambda r: r['performance']['probe32'].update(originalQueueCount=32),
            'not restored': lambda r: r['performance']['probe32'].update(restored=False),
            'native executed': lambda r: r['performance']['probe32']['temporary'][0].update(nativeRef='java:forbidden'),
            'intent published': lambda r: r['performance']['probe32']['temporary'][0].update(intentPublished=True),
            'shortened native duration': lambda r: r['performance']['probe32']['temporary'][0].update(duration=1),
            'missing constructor': lambda r: r['performance']['probe32']['temporary'].pop(),
            'budget raised': lambda r: r['performance']['probe32']['metrics'][0].update(p99BudgetMs=99),
            'sample changed without updating quantile': lambda r: r['performance']['probe32']['metrics'][0]['rawMs'].__setitem__(-1,5),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name):
                evidence=self.evidence();mutate(evidence[0]);self.assertTrue(self.check(evidence))

    def test_actual_32_probe_restores_same_queue_on_success_and_callback_failure(self):
        lua=shutil.which('luajit')
        if not lua:self.skipTest('LuaJIT not installed')
        source=r"""
local file=assert(io.open(arg[1]));local text=file:read('*a');file:close()
local first=assert(text:find('local function performanceAtBoundary()',1,true))
local last=assert(text:find('\nlocal function atBoundary()',first,true))
local body=text:sub(first,last-1)..'\nreturn performanceAtBoundary'
config={options={}}
local constructed,removed,calls,fail={},{},0,false
local unstable,probeCalls=false,0
local actor,tv,data={},{},{}
state={player=setmetatable({getPlayerNum=function()return 0 end},{__index=actor}),tv=tv,data=data}
local original={};for i=1,5 do original[i]={toolkitQueueOperation={},action=i==1 and{}or nil}end
local list={};for i,a in ipairs(original)do list[i]=a end
local q={queue=list,current=original[1],toolkitOperationGeneration=17}
front,equip,volume=original[1],original[3],original[4];ids={source='worn-bag'}
queue=function()return q end;control=function()return'move-volume'end;case=function()return'worn-bag.move-volume'end
now=function()return 1000 end;timingNow=now;ref=function(value)return tostring(value)end;raw=function()end
F={snapshot=function()return{itemId=101,pages=219,container='root',volume=.5}end,same=function(a,b)for k,v in pairs(a)do if b[k]~=v then return false end end;return true end}
local ctor=function(_,mode,player,device,value)
 local action={Type='ISRadioAction',character=player,device=device,deviceData=data,mode=mode,secondaryItem=value,maxTime=30}
 constructed[#constructed+1]=action;return action
end
ISRadioAction={new=ctor};Proof={closure=function(callback,path)return callback==ctor and path=='ISRadioAction.lua'end}
local function policy()
 calls=calls+1
 if fail and #q.queue==32 then error('deliberate read-only inspection failure')end
 if #q.queue==32 then probeCalls=probeCalls+1;if unstable and probeCalls==5 then return{allowed=false,reason='transient'}end end
 return{allowed=true,mode='move'}
end
local Panel={new=function()
 return{initialise=function()end,addToUIManager=function()end,removeFromUIManager=function(self)removed[#removed+1]=self end,update=policy}
end}
T={ActionQueuePanel=Panel,ActionQueuePolicy={evaluateMove=policy,evaluateCancel=policy,previewMove=policy,previewCancel=policy}}
ISTimedActionQueue={add=function()error('probe may not enqueue')end}
T.ActionQueueOperations={run=function()error('probe may not stamp intent')end}
local run=assert(loadstring(body,'@actual-performance-probe'))()
for _,scenario in ipairs({'success','failure','unstable','absent-options','false-profile','top-level-ignored'})do
 config=scenario=='absent-options'and{}or{options={}}
 if scenario=='false-profile'then config.options.profileCounts=false end
 if scenario=='top-level-ignored'then config.profileCounts=true end
 local fails=scenario=='failure';fail=fails;unstable=scenario=='unstable';probeCalls=0;constructed={};local oldRemoved=#removed
 local ok,problem=pcall(run)
 assert(ok~=fails,'probe failure propagation changed: '..tostring(problem))
 assert(q.queue==list and #list==5 and q.current==original[1]and q.toolkitOperationGeneration==17,'queue/list ownership not restored')
 for i,a in ipairs(original)do assert(list[i]==a,'original prefix identity changed')end
 assert(#constructed==27 and #removed==oldRemoved+1,'private suffix or UI cleanup incomplete')
 for _,action in ipairs(constructed)do assert(not action.action and not action.started,'temporary constructor executed')end
 if ok then
  assert(performance.probe32.restored and performance.probe32.readOnly and #performance.probe32.temporary==27)
  assert(not performance.diagnosticProfile and not performance.probe32.diagnosticProfile,'absent/false/nonnested option enabled profiling')
  local metric=performance.probe32.metrics[1]
  if unstable then assert(not metric.decisionStable and metric.decisionClass=='unstable'and metric.firstDecision.allowed and metric.lastDecision.allowed and not performance.probe32.positiveTimingClaim,'intermediate denial hidden by equal first/last samples')
  else assert(metric.decisionStable and metric.decisionClass=='allowed'and not performance.probe32.positiveTimingClaim)end
 end
end
-- Explicit nested opt-in must fail before touching the queue if the private
-- source profiler was not staged. The default harness config stays ordinary.
config={options={profileCounts=true}};PZSurvivorToolkitBookProfile=nil
fail=false;unstable=false;probeCalls=0;constructed={};local beforeMissing=#removed
local ok,problem=pcall(run)
assert(not ok and tostring(problem):find('diagnostic source profiler not loaded',1,true),'missing opted-in profiler was silently accepted')
assert(#constructed==0 and #removed==beforeMissing and q.queue==list and #list==5,'missing-profiler check changed scene/queue')
-- The profiler double records only diagnostic boundaries; actual production
-- entrypoints, permission samples,32 constructor probe and cleanup stay real.
local profileStarts,profileStops=0,0
local profile={active=false}
profile.start=function(label)
 assert(PZSurvivorToolkitBookProfileEnabled==true and not profile.active,'profile start ignored explicit opt-in or leaked scope')
 profile.active=true;profile.label=label;profileStarts=profileStarts+1;return true
end
profile.stop=function()
 assert(profile.active,'unpaired diagnostic stop');profile.active=false;profileStops=profileStops+1
 return{label=profile.label,mode='count-only',diagnostic=true,counts={}}
end
PZSurvivorToolkitBookProfile=profile;PZSurvivorToolkitBookProfileEnabled=false
constructed={};probeCalls=0;local oldRemoved=#removed
assert(pcall(run),'explicit diagnostic probe failed')
assert(profileStarts==10 and profileStops==10 and not profile.active,'metrics did not own separate diagnostic scopes')
assert(#constructed==27 and #removed==oldRemoved+1 and q.queue==list and #list==5,'diagnostic option changed32-probe cleanup')
for _,result in ipairs({performance,performance.probe32})do
 assert(result.diagnosticProfile and result.positiveTimingClaim==false and result.authorityAllowed,'diagnostic acquired final timing qualification or changed authority')
 for _,metric in ipairs(result.metrics)do
  assert(metric.sourceProfile and metric.sourceProfile.entrypointCalls==24 and metric.sourceProfile.label==tostring(result.queueCount)..'/'..metric.name)
  assert(metric.sourceProfile.scope==(result.queueCount==32 and'probe32'or'natural'),'diagnostic queue scope mislabeled')
 end
end
fail=true;constructed={};probeCalls=0;oldRemoved=#removed
ok,problem=pcall(run)
assert(not ok and tostring(problem):find('deliberate read-only inspection failure',1,true),'diagnostic hid original callback failure')
assert(not profile.active and #constructed==27 and #removed==oldRemoved+1 and q.queue==list and #list==5,'failed diagnostic leaked active scope or suffix')
assert(calls>0,'actual entrypoints were not exercised')
-- Fractional-clock diagnostics keep the same source/queue guards and scopes.
preciseTiming=true;config={options={precise_timing=true}};fail=false;unstable=false
performanceClockInfo={schema=1,timer='System.nanoTime',units='ms',monotonic=true,relativeOrigin=true,source='disposable-jvm-probe',
 functionClass='net.alexredby.bookcontrolsprobe.Main$MonotonicClock',nativeClock=true}
local precise=0;timingNow=function()precise=precise+.03125;return precise end
assert(pcall(run),'precise diagnostic probe failed')
for _,result in ipairs({performance,performance.probe32})do
 assert(result.timer=='System.nanoTime'and result.coarse==false and result.clockEvidence==performanceClockInfo)
 assert(result.measurementScope=='isolated-entrypoint-bank'and result.completeEditMeasured==false and result.frameLoadMeasured==false)
 assert(result.assessmentPolicy=='correctness-work-complexity-and-impact'and result.performanceAssessment=='not-assessed')
 assert(result.budgetBasis==nil and not result.positiveTimingClaim and result.tailEstimate=='20-samples-p95-order19-p99-sample-maximum')
 for _,metric in ipairs(result.metrics)do assert(metric.passed==nil and metric.p95BudgetMs==nil and metric.p99BudgetMs==nil)end
 for _,metric in ipairs(result.metrics)do assert(metric.rawMs[1]==.03125 and metric.p95Ms==.03125 and metric.p99Ms==.03125)end
end
os.exit(0)
"""
        subprocess.run([lua,'-e',OFFLINE_FIXTURE_EVENTS + source,'--','unused',str(ROOT/'tests/native_queue/book-controls/client/ZZBookControls.lua')],check=True)

    @staticmethod
    def current_measurements(evidence):
        # Legacy fixtures above remain useful for auditing old captured reports.
        row=evidence[0]
        for value in (row['performance'],row['performance']['probe32']):
            value.update(positiveTimingClaim=False,**a.ASSESSMENT_POLICY,**a.PERFORMANCE_SCOPE)
            for index,metric in enumerate(value['metrics']):
                metric['workScope']='policy-decision-call'if index<2 else 'policy-preview-call'if index<4 else 'panel-update-only'
                for key in ('p95BudgetMs','p99BudgetMs','passed'):metric.pop(key,None)
        return evidence

    def precise_evidence(self, case='worn-bag.move-equip', kind='mp', mode='toolkit', requests=False):
        evidence=self.current_measurements((self.request_evidence if requests else self.evidence)(case,kind,mode));row=evidence[0]
        for value in (row['performance'],row['performance']['probe32']):
            value.update(timer='System.nanoTime',coarse=False,clockEvidence=copy.deepcopy(a.CLOCK_INFO),**a.PERFORMANCE_SCOPE)
            for index,metric in enumerate(value['metrics']):
                metric['workScope']='policy-decision-call'if index<2 else 'policy-preview-call'if index<4 else 'panel-update-only'
        if mode=='toolkit':
            row['boundary']['ui']['handlerTiming']=dict(timer='System.nanoTime',units='ms',scope='actual-list-handler-work',samples=1,
                pressMs=.125,releaseMs=.75,handlerWorkMs=.875,pressStartedMs=10,pressFinishedMs=10.125,releaseStartedMs=10.5,releaseFinishedMs=11.25,replayed=False,includesHumanPause=False,includesRender=False,
                includesAsyncSettlement=False,warmState='after-readonly-bank-and-diagnostic-decision',completeEditQualified=False,timerOverhead='included-not-subtracted')
            for boundary in evidence[5]:boundary['ui']=copy.deepcopy(row['boundary']['ui'])
        return evidence

    def test_current_observations_preserve_correctness_without_numerical_acceptance(self):
        for kind in ('sp','mp'):
            for mode in ('native','toolkit'):
                for case in adapter.CASES:
                    with self.subTest(kind=kind,mode=mode,case=case):
                        evidence=self.current_measurements(self.evidence(case,kind,mode))
                        for bank in (evidence[0]['performance'],evidence[0]['performance']['probe32']):
                            for metric in bank['metrics']:
                                metric.update(rawMs=[50]*20,p95Ms=50,p99Ms=50)
                        self.assertEqual(self.check(evidence,kind,mode),[])
                        evidence[0]['performance']['metrics'][0]['decisionStable']=False
                        self.assertTrue(self.check(evidence,kind,mode))
        for mutate in (lambda r:r.update(performanceAssessment='accepted'),
                       lambda r:r.update(performanceAssessment='rejected'),
                       lambda r:r.update(positiveTimingClaim=True),
                       lambda r:r.pop('assessmentPolicy'),
                       lambda r:r.pop('measurementScope'),
                       lambda r:r['metrics'][0].pop('workScope'),
                       lambda r:r['metrics'][0].update(passed=True),
                       lambda r:r['metrics'][0].update(p95BudgetMs=1)):
            row=self.current_measurements(self.evidence())[0];mutate(row['performance'])
            self.assertTrue(a.performance_errors(row['performance'],row['id'],True))
        evidence=self.current_measurements(self.evidence())
        evidence[0]['client']['books']['tail']['pages']-=1
        self.assertTrue(self.check(evidence))  # Removing timing gates cannot hide a wrong physical outcome.

    def test_legacy_reference_provenance_and_malformed_summary_are_not_reinterpreted(self):
        row=self.evidence()[0];bank=row['performance']
        for value in (bank,bank['probe32']):
            value.update(timer='System.nanoTime',coarse=False,clockEvidence=copy.deepcopy(a.CLOCK_INFO),
                         budgetBasis='initial-engineering-targets',**a.PERFORMANCE_SCOPE)
            for index,metric in enumerate(value['metrics']):
                metric['workScope']='policy-decision-call'if index<2 else 'policy-preview-call'if index<4 else 'panel-update-only'
        self.assertEqual(a.performance_errors(bank,row['id'],True,precise=True),[])
        bank['budgetBasis']='fabricated-empirical-baseline'
        self.assertTrue(a.performance_errors(bank,row['id'],True,precise=True))
        with tempfile.TemporaryDirectory()as directory:
            root=Path(directory)
            for field in ('rawMs','firstUseMs'):
                row=self.current_measurements(self.evidence())[0]
                row['performance']['metrics'][0][field]=[10**309]if field=='rawMs'else 10**309
                self.assertTrue(a.performance_errors(row['performance'],row['id'],True))
                (root/'client1-launch.log').write_text('[QUEUE_CHECK] '+json.dumps(row))
                (root/'server-launch.log').write_text('')
                result=a.verify(root,self.selection(),{})
                self.assertTrue(result['issues'])
                self.assertEqual(result['evidence']['performance']['performanceAssessment'],'not-assessed')

    def test_actual_fixture_completion_rejects_instability_without_timing_gate(self):
        lua=shutil.which('luajit')
        if not lua:self.skipTest('LuaJIT not installed')
        text=(ROOT/'tests/native_queue/book-controls/client/ZZBookControls.lua').read_text()
        first=text.index(' if not failure and performance then')
        body=text[first:text.index(' if not failure then\n  local expected=',first)]
        source="""
local check=assert(loadstring('return function(performance) local failure; '..arg[1]..' return failure end'))()
local metric={name='previewMove',p95Ms=50,p99Ms=50,passed=false,decisionStable=true}
local bank={queueCount=32,metrics={metric}};bank.probe32={queueCount=32,metrics={metric}}
assert(check(bank)==nil,'duration alone became a functional failure')
metric.decisionStable=false
assert(check(bank):find('unstable read-only decision',1,true),'unstable decisions silently accepted')
os.exit(0)
"""
        subprocess.run([lua,'-e',OFFLINE_FIXTURE_EVENTS + source,'--','unused',body],check=True)

    def test_current_full_bank_reports_cost_unassessed_and_preserves_raw_integrity(self):
        with tempfile.TemporaryDirectory()as directory:
            root=Path(directory)
            for mode in ('toolkit','native'):
                selection,client,server=self.log_bank(mode=mode,current=True,sample_ms=50)
                (root/'client1-launch.log').write_text(client);(root/'server-launch.log').write_text(server)
                result=a.verify(root,selection,{})
                self.assertEqual(result['issues'],[])
                cost=result['evidence']['performance']
                self.assertEqual(cost['performanceAssessment'],'not-assessed')
                self.assertEqual(cost['runtimeImpact'],'not-established')
                self.assertEqual(len(cost['observations']),len(adapter.CASES)*10)
                self.assertTrue(all(r['p95Ms']==50 and r['maxMs']==50 for r in cost['observations']))
                changed=client.replace('"p95Ms": 50','"p95Ms": 0',1)
                (root/'client1-launch.log').write_text(changed)
                self.assertTrue(a.verify(root,selection,{})['issues'])
        with tempfile.TemporaryDirectory()as directory:
            result=a.verify(Path(directory),self.selection(),{})
            self.assertTrue(result['issues'])
            self.assertEqual(result['evidence']['performance']['performanceAssessment'],'not-assessed')
        self.assertEqual(a.performance_observations([None,dict(performance={},boundary=None)])['handlers'],[])
        row=self.current_measurements(self.evidence())[0]
        row['performance']['metrics'][0]['rawMs']=list(range(20))
        self.assertEqual(a.performance_observations([row])['observations'][0]['medianMs'],9.5)

    def test_precise_scope_and_clock_do_not_qualify_complete_input_latency(self):
        for mode in ('toolkit','native'):
            row=self.precise_evidence(mode=mode)[0]
            self.assertEqual(a.performance_errors(row['performance'],row['id'],mode=='toolkit',precise=True),[])
            self.assertEqual(a.handler_timing_errors(row['boundary']['ui'],True,mode=='toolkit'),[])
        row=self.precise_evidence()[0]
        mutations=[lambda r:r.update(coarse=True),lambda r:r.update(timer='getTimestampMs'),
            lambda r:r.update(completeEditMeasured=True),lambda r:r.update(frameLoadMeasured=True),
            lambda r:r.update(completeEditQualified=True),lambda r:r.update(budgetBasis='baseline-measured'),
            lambda r:r['clockEvidence'].update(schema=True),lambda r:r['clockEvidence'].update(nativeClock=False),
            lambda r:r['clockEvidence'].update(extra={'object':'bad'}),lambda r:r['metrics'][0].update(workScope='complete-edit'),
            lambda r:r['metrics'][0].update(p95BudgetMs=99),lambda r:r['probe32'].update(completeEditMeasured=True)]
        for i,mutate in enumerate(mutations):
            value=copy.deepcopy(row['performance']);mutate(value)
            self.assertTrue(a.performance_errors(value,row['id'],True,precise=True),i)
        timing=row['boundary']['ui']['handlerTiming']
        for key,value in [('samples',True),('replayed',True),('includesRender',True),('includesHumanPause',True),
                ('includesAsyncSettlement',True),('completeEditQualified',True),('handlerWorkMs',9),('pressMs',float('nan')),
                ('releaseMs',-1),('releaseStartedMs',0),('pressFinishedMs',11),('scope','end-to-end-click'),('warmState','cold-process')]:
            changed=copy.deepcopy(timing);changed[key]=value
            self.assertTrue(a.handler_timing_errors({'handlerTiming':changed},True,True),key)
        self.assertTrue(a.handler_timing_errors({'handlerTiming':timing},False,True))
        self.assertTrue(a.handler_timing_errors({'handlerTiming':timing},True,False))
        selection=self.selection();selection['options']['precise_timing']=1
        with self.assertRaises(ValueError):adapter.validate(selection)

    def test_timing_quantiles_and_budgets_cannot_alias_boolean_values(self):
        for precise in (False,True):
            row=(self.precise_evidence if precise else self.evidence)()[0]
            for key,index,value in [('p95Ms',0,False),('p99Ms',0,False),('p95BudgetMs',2,True)]:
                bank=copy.deepcopy(row['performance']);bank['metrics'][index][key]=value
                self.assertTrue(a.performance_errors(bank,row['id'],True,precise=precise),(key,precise))

    def test_precise_timing_full_bank_needs_setup_and_actual_handler_evidence(self):
        with tempfile.TemporaryDirectory()as directory:
            root=Path(directory)
            for mode in ('toolkit','native'):
                selection,client,server=self.log_bank(mode=mode,requests=True,precise=True)
                (root/'client1-launch.log').write_text(client);(root/'server-launch.log').write_text(server)
                self.assertEqual(a.verify(root,selection,{})['issues'],[],mode)
                # Corrupt only the source-bound setup row; samples stay intact.
                changed=client.replace('"nativeClock": true','"nativeClock": false',1)
                (root/'client1-launch.log').write_text(changed)
                self.assertTrue(a.verify(root,selection,{})['issues'])
                (root/'client1-launch.log').write_text(client)
                selection['options'].pop('precise_timing')
                self.assertTrue(a.verify(root,selection,{})['issues'])

    def test_actual_fixture_times_one_mutating_handler_pair_without_replay(self):
        lua=shutil.which('luajit')
        if not lua:self.skipTest('LuaJIT not installed')
        source=r"""
local file=assert(io.open(arg[1]));local text=file:read('*a');file:close()
local first=assert(text:find('local function timedHandler(',1,true))
local last=assert(text:find('\nlocal function resetFailure(',first,true))
local run,handler=assert(loadstring(text:sub(first,last-1)..'\nreturn realGesture,timedHandler'))()
preciseTiming=true;local clock=0
-- Clock double isolates the fixture's wiring, not native time accuracy.
timingNow=function()clock=clock+.125;return clock end
now=function()return 100 end
local down,up,removed=0,0,0
for _,moving in ipairs({false,true})do
 local token={};oldNative={};front={toolkitQueueOperation=token,action=oldNative}
 equip={toolkitQueueOperation={}};volume={toolkitQueueOperation={}}
 state={player={getPlayerNum=function()return 0 end}};ids={source='root'}
 local q={current=front,queue={front,equip,volume}}
 queue=function()return q end;control=function()return moving and'move-equip'or'reader-child-cancel'end
 deviceOnly=function()return false end
 diagnostic=function()return{reason=false}end;ref=tostring;tokenID=function()return 1 end
 local rows={{item=front,operation=token,header=false,index=1,height=40},
  {item=equip,operation=equip.toolkitQueueOperation,header=false,index=2,height=40}}
 local list={items=rows,setYScroll=function()end,isVScrollBarVisible=function()return false end,
  cancelX=function()return 400 end,topOfItem=function(_,i)return(i-1)*40 end,
  rowUnderMouse=function(_,x,y)return rows[math.floor(y/40)+1]end}
 list.onMouseDown=function(self,x,y)
  down=down+1;if moving then self.dragAction=equip else self.pressedCancel=front end
 end
 list.onMouseUp=function(self,x,y)
  up=up+1;q.toolkitCancel=front;self.dragAction=nil;self.dragging=nil;self.pressedCancel=nil
 end
 local panel={list=list,initialise=function()end,addToUIManager=function()end,update=function()end,
  removeFromUIManager=function()removed=removed+1 end}
 T={ActionQueuePanel={new=function()return panel end},ActionQueuePolicy={evaluateCancel=function()return{}end,evaluateMove=function()return{}end}}
 local oldDown,oldUp=down,up;local ui=run()
 assert(down==oldDown+1 and up==oldUp+1 and removed==(moving and 2 or 1),'handler was replayed or not called')
 assert(ui.accepted and ui.handlerTiming.pressMs==.125 and ui.handlerTiming.releaseMs==.125 and ui.handlerTiming.handlerWorkMs==.25)
 assert(ui.handlerTiming.samples==1 and ui.handlerTiming.replayed==false and ui.handlerTiming.completeEditQualified==false)
 assert(ui.handlerTiming.pressStartedMs<=ui.handlerTiming.pressFinishedMs and ui.handlerTiming.pressFinishedMs<=ui.handlerTiming.releaseStartedMs and ui.handlerTiming.releaseStartedMs<=ui.handlerTiming.releaseFinishedMs)
 assert(list.onMouseDown~=nil and list.onMouseUp~=nil,'callback binding was replaced')
end
local effects,payload=0,{}
local list={onMouseUp=function()effects=effects+1;error(payload,0)end}
local original=list.onMouseUp
local ok,reason=pcall(handler,list,'onMouseUp',0,0)
assert(not ok and reason==payload and effects==1 and list.onMouseUp==original,'timing swallowed an error, replayed mutation or replaced callback')
os.exit(0)
"""
        subprocess.run([lua,'-e',OFFLINE_FIXTURE_EVENTS + source,'--','unused',str(ROOT/'tests/native_queue/book-controls/client/ZZBookControls.lua')],check=True)

    def test_scalar_decisions_classify_allowed_denied_and_block_false32_claims(self):
        self.assertEqual(self.check(self.evidence()), [])
        self.assertEqual(self.check(self.evidence(mode='native'), mode='native'), [])
        mutations = {
            'no observations': lambda r: r['performance']['metrics'][0].pop('firstDecision'),
            'unstable observation': lambda r: r['performance']['probe32']['metrics'][0].update(decisionStable=False),
            'authority snapshot leaked': lambda r: r['performance']['metrics'][0]['firstDecision'].update(snapshot={}),
            'first last differ': lambda r: r['performance']['probe32']['metrics'][1]['lastDecision'].update(reason='different'),
            'wrong observation count': lambda r: r['performance']['metrics'][0].update(decisionSamples=20),
            'false allowed classification': lambda r: r['performance']['probe32']['metrics'][0].update(decisionClass='denied'),
            'false positive timing claim': lambda r: r['performance']['probe32'].update(positiveTimingClaim=False),
        }
        for name,mutate in mutations.items():
            with self.subTest(name=name):
                evidence=self.evidence();mutate(evidence[0]);self.assertTrue(self.check(evidence))
        evidence=self.evidence();probe=evidence[0]['performance']['probe32'];metric=probe['metrics'][0]
        metric.update(firstDecision=dict(allowed=False,reason='protected',mode=False),lastDecision=dict(allowed=False,reason='protected',mode=False),decisionClass='denied')
        probe.update(authorityAllowed=False,positiveTimingClaim=False)
        self.assertTrue(any('Intended Toolkit32 authority edit denied' in reason for reason in self.check(evidence)))

    def test_world_nonfavorite_and_mode_specific_favorite_outcomes(self):
        self.assertEqual(len(adapter.CASES), 20)
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                for case in ('world.header-cancel', 'world.header-cancel-capacity-lost', *adapter.FAVORITE_CASES):
                    evidence = self.evidence(case, kind, mode)
                    self.assertEqual(self.check(evidence, kind, mode), [])
                    self.assertIs(evidence[1]['baseline']['books']['front']['favorite'], a.favorite_case(case))
                    if case in adapter.FAVORITE_CASES:
                        self.assertEqual(evidence[0]['client']['books']['front']['container'], 'root' if kind == 'sp' else 'world')
                        self.assertIsInstance(evidence[0]['blockedReturn'], dict if kind == 'sp' and mode == 'toolkit' else bool)
        for case in ('world.header-cancel', 'world.header-cancel-capacity-lost'):
            evidence=self.evidence(case);evidence[1]['baseline']['books']['front']['favorite']=True
            self.assertTrue(self.check(evidence))
        evidence=self.evidence('world.header-cancel-favorite','sp');evidence[0]['blockedReturn']['reason']='admission'
        self.assertTrue(self.check(evidence,'sp'))
        evidence=self.evidence('world.move-volume-favorite','sp')
        for record in evidence[0]['records']:
            if record['role']=='return':record.pop('performedAt',None);record['finishes']=[]
        self.assertTrue(self.check(evidence,'sp'))
        evidence=self.evidence('world.header-cancel-favorite');evidence[0]['capacity']={}
        self.assertTrue(self.check(evidence))

    def test_actual_refresh_and_bounded_replica_barrier_fail_closed(self):
        lua=shutil.which('luajit')
        if not lua:self.skipTest('LuaJIT not installed')
        source=r"""
local F=assert(loadfile(arg[1]))()
local function copy(v)if type(v)~='table'then return v end;local r={};for k,x in pairs(v)do r[k]=copy(x)end;return r end
local state={ids={case='world.move-volume',actor=5,source='world',front={id=101,type='Book'}}}
local diagnostic={case=state.ids.case,actor=5,missing={front=true,tv=false,shelf=false,tail=false,pen=false},mismatch={},counts={front={root=0,world=0}}}
local episode={case=state.ids.case,actor=5,itemId=101,itemType='Book',source='world',role='return',from='root',to='world',sequence=7,transaction=14,actionRef='lua:7',nativeRef='java:7',positive=true,live=true,observedAt=100}
local status,gap=F.replicaBarrier(state,diagnostic,episode,100);assert(status=='wait'and state.replicaGap==gap)
status,gap=F.replicaBarrier(state,nil,episode,101);assert(status=='resolved'and gap.resolvedAt==101 and not state.replicaGap)
for _,mutate in ipairs({
 function(d,e)d.missing.tv=true end,function(d,e)d.mismatch.shelf=true end,
 function(d,e)d.missing.tail=true end,function(d,e)d.missing.bag=true end,function(d,e)d.mismatch.front=true end,
 function(d,e)d.counts.front.root=1 end,function(d,e)e.actor=99 end,function(d,e)e.itemId=999 end,
 function(d,e)e.itemType='Other'end,function(d,e)e.source='unknown'end,function(d,e)e.transaction=0 end,
 function(d,e)e.observedAt=-2001 end,function(d,e)e.positive=false end,function(d,e)e.rejected=true end,
 function(d,e)e.live=false end,function(d,e)e.from='unknown'end,function(d,e)e.nativeRef=nil end,
})do
 local d,e=copy(diagnostic),copy(episode);mutate(d,e);state.replicaGap=nil
 assert(F.replicaBarrier(state,d,e,100)==nil,'unsafe gap admitted')
end
state.replicaGap=nil;assert(F.replicaBarrier(state,diagnostic,nil,100)==nil,'unobserved start fabricated')
state.replicaGap=nil;assert(F.replicaBarrier(state,diagnostic,episode,100)=='wait')
local e=copy(episode);e.observedAt=2101;assert(F.replicaBarrier(state,diagnostic,e,2101)==nil,'live transaction bypassed absolute deadline')
state.replicaGap=nil;assert(F.replicaBarrier(state,diagnostic,episode,100)=='wait')
e=copy(episode);e.transaction=15;assert(F.replicaBarrier(state,nil,e,101)==nil,'stale transaction resolved gap')
state.replicaGap=nil;assert(F.replicaBarrier(state,diagnostic,episode,100)=='wait')
e=copy(episode);e.live=false;e.terminalAt=101;e.observedAt=101;assert(F.replicaBarrier(state,nil,e,102)=='resolved','just-after terminal convergence rejected')
-- Actual refresh: absence is diagnosed without overwriting the earned exact object.
local function list(v)return{size=function()return #v end,get=function(_,i)return v[i+1]end}end
local square={getX=function()return 1 end,getY=function()return 2 end,getZ=function()return 0 end}
local function item(id,kind)return{getID=function()return id end,getFullType=function()return kind end}end
local front,tail,pen=item(101,'Book'),item(102,'Tail'),item(103,'Pen');local rootItems={front,tail,pen};local worldItems={}
local root={getItems=function()return list(rootItems)end};local world={getItems=function()return list(worldItems)end}
local tv={kind='IsoTelevision',getSquare=function()return square end,getObjectIndex=function()return 1 end,getDeviceData=function()return{}end}
local shelf={kind='IsoThumpable',getSquare=function()return square end,getObjectIndex=function()return 2 end,getContainer=function()return world end}
local objects={tv,shelf};square.getObjects=function()return list(objects)end
getCell=function()return{getGridSquare=function()return square end}end
instanceof=function(v,kind)return v.kind==kind end
local s={player={getInventory=function()return root end,getOnlineID=function()return 5 end},ids={case='x',actor=5,source='world',bag=false,tv={x=1,y=2,z=0,index=1},shelf={x=1,y=2,z=0,index=2},front={id=101,type='Book'},tail={id=102,type='Tail'},pen={id=103,type='Pen'}}}
assert(F.refresh(s)and s.front==front)
table.remove(rootItems,1);local ok,d=F.refresh(s);assert(not ok and d.missing.front and s.front==front,'refresh destroyed last earned identity')
worldItems[1]=front;assert(F.refresh(s)and s.front==front)
rootItems[#rootItems+1]=front;ok,d=F.refresh(s);assert(not ok and d.mismatch.front,'duplicate exact ownership admitted');table.remove(rootItems)
objects[1]={kind='IsoTelevision',getObjectIndex=function()return 1 end};ok,d=F.refresh(s);assert(not ok and d.mismatch.tv,'scene index reuse silently rebound')
for _,case in ipairs({'header-cancel-favorite','move-volume-favorite'})do local base,lost,favorite=F.parseControl(case);assert(not lost and favorite and base:find('favorite')==nil)end
os.exit(0)
"""
        subprocess.run([lua,'-e',OFFLINE_FIXTURE_EVENTS + source,'--','unused',str(ROOT/'tests/native_queue/book-controls/shared/QueueBookControls.lua')],check=True)
        client=(ROOT/'tests/native_queue/book-controls/client/ZZBookControls.lua').read_text()
        self.assertIn('if not observe()then return end',client)
        wait=client.split("if status=='wait'then",1)[1].split("if status=='resolved'",1)[0]
        self.assertIn('return false',wait)
        for forbidden in ('F.snapshot','resetFailure','request(',':forceStop',':forceComplete'):
            self.assertNotIn(forbidden,wait)

    def test_actual_observer_waits_without_snapshot_or_phase_edits_and_refuses_missed_start(self):
        lua=shutil.which('luajit')
        if not lua:self.skipTest('LuaJIT not installed')
        source=r"""
local F=assert(loadfile(arg[1]))();_G.F=F
local source=assert(io.open(arg[2])):read('*a');source=source:match('(local function observe%(%).-)%s*local function lifecycleBegin');assert(source)
source=source:gsub('local function observe','function observe',1)
state={ids={case='world.move-volume',actor=5,source='world',front={id=101,type='Book'}}}
local d={case=state.ids.case,actor=5,missing={front=true},mismatch={},counts={front={root=0,world=0}}}
F.refresh=function()return false,d end
F.snapshot=function()error('snapshot during gap')end
local action={};tracks={[action]={role='return',sequence=7}};replicaGaps={}
transferEpisode={case=state.ids.case,actor=5,itemId=101,itemType='Book',source='world',role='return',from='root',to='world',sequence=7,transaction=14,actionRef='lua:7',nativeRef='java:7',positive=true,live=true,observedAt=100,action=action}
now=function()return 100 end;case=function()return state.ids.case end;updateTransferEpisode=function()end
raw=function(marker)assert(marker=='REPLICA_GAP')end
queue=function()error('native queue or phase inspected during gap')end
assert(loadstring(source))();assert(observe()==false and state.replicaGap)
tracks[{}]={role='equip',started=false,performedAt=100}
local ok,problem=pcall(observe);assert(not ok and tostring(problem):find('native start crossed replica gap',1,true),'missed native timing fabricated')
os.exit(0)
"""
        subprocess.run([lua,'-e',OFFLINE_FIXTURE_EVENTS + source,'--','unused',str(ROOT/'tests/native_queue/book-controls/shared/QueueBookControls.lua'),str(ROOT/'tests/native_queue/book-controls/client/ZZBookControls.lua')],check=True)

    def test_exact_replica_gap_requires_terminal_transaction_and_raw_pair(self):
        evidence=self.evidence();row=evidence[0];without_gap=copy.deepcopy(row);record=next(r for r in row['records'] if r['role']=='return')
        gap=dict(case=row['id'],actor=0,itemId=101,itemType='Base.BookCarpentry1',source='worn-bag',sequence=record['sequence'],transaction=record['transaction'],actionRef=record['actionRef'],nativeRef=record['nativeRef'],role='return',startedAt=20,deadlineAt=2020,resolvedAt=21,resolved=True,diagnostic=dict(case=row['id'],actor=0,missing=dict(front=True,tv=False,tail=False),mismatch={},counts=dict(front=dict(root=0,world=0))))
        row['replicaGaps']=[gap];self.assertEqual(self.check(evidence),[])
        for key,value in [('itemId',999),('transaction',999),('resolved',False),('resolvedAt',2021),('nativeRef','other')]:
            changed=copy.deepcopy(evidence);changed[0]['replicaGaps'][0][key]=value;self.assertTrue(self.check(changed))
        changed=copy.deepcopy(evidence);changed[0]['replicaGaps'][0]['diagnostic']['missing']['tv']=True;self.assertTrue(self.check(changed))
        changed=copy.deepcopy(evidence);next(r for r in changed[0]['records'] if r['role']=='return')['transactionDone']=False;self.assertTrue(self.check(changed))
        selection,client,server=self.log_bank()
        client=client.replace('[QUEUE_CHECK] '+json.dumps(without_gap),'[QUEUE_CHECK] '+json.dumps(row))
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'server-launch.log').write_text(server)
            (root/'client1-launch.log').write_text(client);self.assertTrue(a.verify(root,selection,{})['issues'])
            opened=dict({k:v for k,v in gap.items() if k not in ('resolved','resolvedAt')},emitted=True)
            client+='\n'+adapter.PREFIX+'REPLICA_GAP '+json.dumps(opened)+'\n'+adapter.PREFIX+'REPLICA_CONVERGED '+json.dumps(gap)
            (root/'client1-launch.log').write_text(client);self.assertEqual(a.verify(root,selection,{})['issues'],[])
            (root/'client1-launch.log').write_text(client.replace(adapter.PREFIX+'REPLICA_CONVERGED '+json.dumps(gap),adapter.PREFIX+'REPLICA_CONVERGED '+json.dumps(dict(gap,transaction=999))))
            self.assertTrue(a.verify(root,selection,{})['issues'])


    def test_real_kahlua_dump_keeps_identity_while_reader_fields_change(self):
        raw = json.loads((ROOT / 'tests/fixtures/book_controls_action_refs.json').read_text())
        self.assertNotEqual(raw['registered'], raw['boundary'])
        evidence = self.evidence('root.header-cancel', 'sp', 'native')
        row = evidence[0]; original = next(record for record in row['records'] if record['role'] == 'front')
        original['actionRef'] = raw['registered']; original['nativeRef'] = raw['native']
        row['boundary']['reader'] = raw['boundary']; row['boundary']['native'] = raw['native']
        evidence[6][0]['native'] = raw['native']; evidence[6][0]['reader'] = raw['boundary']
        evidence[5][0]['reader'] = raw['boundary']; evidence[5][0]['native'] = raw['native']
        self.assertEqual(self.check(evidence, 'sp', 'native'), [])
        for field, value in [('reader', raw['boundary'].replace('ISReadABook 0x', 'ISReadABook 0xf', 1)), ('reader', raw['boundary'].replace('ISReadABook', 'OtherAction', 1)), ('native', 'java:wrong')]:
            with self.subTest(field=field, value=value[:40]):
                changed = copy.deepcopy(evidence); changed[0]['boundary'][field] = value
                self.assertTrue(self.check(changed, 'sp', 'native'))
        self.assertFalse(a._same_action(None, None))
        self.assertFalse(a._same_action('ISReadABook 0x123{truncated', 'ISReadABook 0x123{truncated'))
        self.assertFalse(a._same_action('ISReadABook 0x123{pages=1}extra', 'ISReadABook 0x123{pages=2}'))

    def test_cross_snapshot_refs_and_fresh_reader_use_stable_table_identity(self):
        evidence = self.evidence(); row = evidence[0]
        original, resumed = [record for record in row['records'] if record['role'] == 'front']
        original['actionRef'] = 'ISReadABook 0x111{pageTimer=0}'
        row['boundary']['reader'] = 'ISReadABook 0x111{pageTimer=15, action=java:1}'
        row['resume']['oldAction'] = 'ISReadABook 0x111{pageTimer=99}'
        original['stopReturned']['actionRef'] = 'ISReadABook 0x111{pageTimer=15}'
        original['stoppedRemoval']['actionRef'] = 'ISReadABook 0x111{pageTimer=16}'
        resumed['actionRef'] = 'ISReadABook 0x222{pageTimer=0}'
        row['resume']['newAction'] = 'ISReadABook 0x222{pageTimer=12}'
        equip = next(record for record in row['records'] if record['role'] == 'equip')
        equip['actionRef'] = 'ISEquipWeaponAction 0x333{maxTime=50}'
        row['boundary']['ui']['movingAction'] = 'ISEquipWeaponAction 0x333{maxTime=50, action=java:2}'
        evidence[5][0] = dict({k:v for k,v in row['boundary'].items() if k not in ('drained', 'drainedAt')}, drained=False)
        evidence[6][0]['reader'] = row['boundary']['reader']
        self.assertEqual(self.check(evidence), [])
        changed = copy.deepcopy(evidence)
        fresh = next(record for record in changed[0]['records'] if record['role'] == 'front' and record is not changed[0]['records'][0])
        fresh['actionRef'] = 'ISReadABook 0x111{pageTimer=0, action=java:new}'
        changed[0]['resume']['newAction'] = 'ISReadABook 0x111{pageTimer=12}'
        self.assertTrue(self.check(changed), 'same Lua table must not pass as a fresh reader when fields change')
        kept = self.evidence('worn-bag.return-child-cancel')
        returned = next(record for record in kept[0]['records'] if record['role'] == 'return')
        returned['actionRef'] = 'ISInventoryTransferAction 0x444{started=false}'
        kept[0]['boundary']['ui']['target'] = 'ISInventoryTransferAction 0x444{started=false, queueList={}}'
        kept[0]['boundary']['ui']['waiverIdentity']['actionRef'] = 'ISInventoryTransferAction 0x444{started=false, queueList={}}'
        kept[5][0] = dict({k:v for k,v in kept[0]['boundary'].items() if k not in ('drained', 'drainedAt')}, drained=False)
        self.assertEqual(self.check(kept), [])

    def test_shared_codec_encodes_nonfinite_numbers_without_finite_substitution(self):
        lua=shutil.which('luajit')
        if not lua:self.skipTest('LuaJIT not installed')
        source=r"""
local J=assert(loadfile(arg[1]))()
print(J.encode({nan=0/0,pos=math.huge,neg=-math.huge,finite=1.25,flag=false,text='nan'}))
local ok=pcall(J.encode,function()end);assert(not ok,'unknown Lua value accepted')
ok=pcall(J.encode,{[1]='mixed',unknown=true});assert(not ok,'malformed mixed table accepted')
os.exit(0)
"""
        value=json.loads(subprocess.check_output([lua,'-e',OFFLINE_FIXTURE_EVENTS + source,'--','unused',str(ROOT/'tests/native_queue/health/shared/QueueHealthEvents.lua')],text=True))
        self.assertEqual(value,dict(nan={'__queueNonfiniteNumber':'nan'},pos={'__queueNonfiniteNumber':'+inf'},neg={'__queueNonfiniteNumber':'-inf'},finite=1.25,flag=False,text='nan'))

    def test_actual_case15_unstarted_nan_is_diagnostic_only_with_exact_admission_evidence(self):
        saved=json.loads((ROOT/'tests/fixtures/book_controls_nonfinite_return.json').read_text())
        record,row,ids=saved['record'],saved['row'],saved['ids']
        self.assertTrue(a._unstarted_admission_diagnostic(record,row,ids,True))
        row=copy.deepcopy(row);row['records']=[record]
        self.assertEqual(a._nonfinite_case_errors(row,ids,True),[])
        for mutate in (
            lambda r:r.update(started=True), lambda r:r.update(progress=True),
            lambda r:r.update(item=999), lambda r:r.update(role='pickup'),lambda r:r.update(type='ISReadABook'),
            lambda r:r.update(performedAt=1),lambda r:r.update(startedAt=1),lambda r:r.update(transaction=1),
            lambda r:r.update(finishes=[dict(phase='perform',succeeded=True)]),lambda r:r.update(receipts=[{}]),
            lambda r:r.update(duration={'__queueNonfiniteNumber':'unknown'}),
            lambda r:r.update(duration={'__queueNonfiniteNumber':'nan','other':True}),
            lambda r:r.update(duration='nan'),lambda r:r.update(duration=None),
        ):
            changed=copy.deepcopy(row);mutate(changed['records'][0]);self.assertTrue(a._nonfinite_case_errors(changed,ids,True))
        for field,value in [('reason','server'),('itemId',999),('state','revoked')]:
            changed=copy.deepcopy(row);changed['blockedReturn'][field]=value;self.assertTrue(a._nonfinite_case_errors(changed,ids,True))
        changed=copy.deepcopy(row);changed['failureUI']['cleared']=False;self.assertTrue(a._nonfinite_case_errors(changed,ids,True))
        changed=copy.deepcopy(row);changed['starts'].append(record['sequence']);self.assertTrue(a._nonfinite_case_errors(changed,ids,True))
        self.assertTrue(a._nonfinite_case_errors(row,ids,False),'queue-off cannot acquire diagnostic admission authority')
        changed=copy.deepcopy(row);changed['records'][0]['allocatedAt']=changed['capacity']['at']-1;self.assertTrue(a._nonfinite_case_errors(changed,ids,True))
        changed=copy.deepcopy(row);changed['boundary']['queue'].append({'sequence':record['sequence']});self.assertTrue(a._nonfinite_case_errors(changed,ids,True))
        changed=copy.deepcopy(row);changed['records'][0]['token']=changed['boundary']['token'];self.assertTrue(a._nonfinite_case_errors(changed,ids,True))
        for field in ('startedAt','transactionDuration'):
            changed=copy.deepcopy(row);changed['records'][0][field]={'__queueNonfiniteNumber':'nan'};self.assertTrue(a._nonfinite_case_errors(changed,ids,True))
        changed=copy.deepcopy(row);changed['unrelatedCritical']={'__queueNonfiniteNumber':'nan'};self.assertTrue(a._nonfinite_case_errors(changed,ids,True))
        for token in ('nan','+inf','-inf'):
            changed=copy.deepcopy(row)
            for field in ('duration','durationAfter','effectiveDuration'):changed['records'][0][field]={'__queueNonfiniteNumber':token}
            self.assertEqual(a._nonfinite_case_errors(changed,ids,True),[])

    def test_tagged_duration_never_qualifies_started_transfer_or_performance(self):
        evidence=self.evidence('worn-bag.header-cancel-capacity-lost','sp')
        row=evidence[0];returned=copy.deepcopy(next(record for record in row['records']if record['role']=='return'))
        returned.update(sequence=800,token=60,actionRef='ISInventoryTransferAction 0x800{maxTime=nan}',nativeRef='java:800',allocatedAt=row['capacity']['at']+1)
        row['records'].append(returned)
        returned.update(duration={'__queueNonfiniteNumber':'nan'},durationAfter={'__queueNonfiniteNumber':'nan'},effectiveDuration={'__queueNonfiniteNumber':'nan'})
        self.assertEqual(self.check(evidence,'sp'),[])
        for field in ('started','progress'):
            changed=copy.deepcopy(evidence);next(record for record in changed[0]['records']if record['sequence']==800)[field]=True
            self.assertTrue(self.check(changed,'sp'))
        changed=copy.deepcopy(evidence);changed[0]['performance']['metrics'][0]['rawMs'][0]={'__queueNonfiniteNumber':'nan'}
        self.assertTrue(self.check(changed,'sp'))
        changed=copy.deepcopy(evidence);changed[0]['boundary']['at']={'__queueNonfiniteNumber':'nan'}
        self.assertTrue(self.check(changed,'sp'))

    def test_selection_is_opt_in_ordered_nonempty_subset(self):
        adapter.validate(self.selection())
        self.assertEqual(adapters.get('book-controls'), adapter)
        for field, value in [('cases', list(reversed(adapter.CASES))), ('cases', []), ('cases', [adapter.CASES[0], adapter.CASES[0]]), ('cases', ['unknown.case']), ('mods', adapter.MODS[:-1]), ('languages', ['RU']), ('clients', True), ('options', dict(mp_host=True))]:
            selection = self.selection(); selection[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError): adapter.validate(selection)
        selection = self.selection(); selection['options']['world_template'] = 'fixture'
        with self.assertRaises(ValueError): adapter.validate(selection)

    def test_passive_waiver_scan_uses_real_locations_without_rebinding(self):
        lua = shutil.which('luajit')
        if not lua: self.skipTest('LuaJIT not installed')
        source = r"""
local F=assert(loadfile(arg[1]))()
instanceof=function(item,kind)return kind=='InventoryContainer'and item.nested~=nil end
local function container()
 local c={values={}}
 function c:getItems()local list=self.values;return{size=function()return #list end,get=function(_,i)return list[i+1]end}end
 return c
end
local root,dest=container(),container()
local function item(label,id,owner,kind)
 local value={label=label,id=id,owner=owner,kind=kind or'Base.BookCarpentry1'}
 function value:getID()return self.id end
 function value:getFullType()return self.kind end
 function value:getContainer()return self.owner end
 function value:getItemContainer()return self.nested end
 return setmetatable(value,{__tostring=function(v)return v.label end})
end
local old=item('old',101,dest);local carried=item('carried',101,root)
root.values={carried};local action={item=old}
local s={player={getInventory=function()return root end},source=dest,ids={front={id=101},source='world'}}
action.queueList={{items={old},time=123,type='Base.BookCarpentry1'}}
local original=F.captureReturnPreview(action)
assert(F.returnPreviewUnchanged(action,original))
action.item=carried;assert(not F.returnPreviewUnchanged(action,original)and F.returnGroupUnchanged(action,original));action.item=old
local group=action.queueList[1];group.items={old};assert(not F.returnGroupUnchanged(action,original));group.items=original.items
group.items[1]=carried;assert(not F.returnGroupUnchanged(action,original));group.items[1]=old
action.queueList={{items=group.items,time=group.time,type=group.type}};assert(not F.returnGroupUnchanged(action,original));action.queueList=original.groups
assert(F.returnPreviewUnchanged(action,original))
local v=F.waiverIdentity(s,action)
assert(action.item==old and root.values[1]==carried and #dest.values==0,'passive scan mutated state')
assert(v.requested.ref=='old'and v.requested.container=='world'and v.carried.ref=='carried'and v.carried.container=='root')
assert(not v.sameReference and v.rootMatches==1 and v.directRootMatches==1 and v.destinationMatches==0)
action.item=carried;assert(F.waiverIdentity(s,action).sameReference)
local bag=item('bag',201,root,'Base.Bag_Military');bag.nested=container();bag.nested.values={carried};carried.owner=bag.nested;root.values={bag}
v=F.waiverIdentity(s,action);assert(v.rootMatches==1 and v.directRootMatches==0 and v.carried.container=='other')
root.values={carried};carried.owner=root;dest.values={old}
v=F.waiverIdentity(s,action);assert(v.destinationMatches==1)
root.values={carried,item('duplicate',101,root,'Base.Pen')};v=F.waiverIdentity(s,action)
assert(v.rootMatches==2 and v.directRootMatches==2 and v.carried.type=='Base.Pen')
assert(action.item==carried,'passive diagnostic rebound the requested action')
os.exit(0)
"""
        subprocess.run([lua, '-e', OFFLINE_FIXTURE_EVENTS + source, '--', 'unused', str(ROOT / 'tests/native_queue/book-controls/shared/QueueBookControls.lua')], check=True)

    def test_optional_return_waiver_passively_qualifies_same_or_replaced_replica(self):
        for source in ('world', 'worn-bag'):
            for kind in ('sp', 'mp'):
                evidence = self.evidence(source + '.return-child-cancel', kind)
                self.assertEqual(self.check(evidence, kind), [])
                identity = evidence[0]['boundary']['ui']['waiverIdentity']
                identity['before']['requested'].update(ref='Literature@pre-pickup', container=source)
                identity['before']['sameReference'] = False
                identity['actualReplicaReplacement'] = True
                evidence[5][0]['ui']['waiverIdentity'] = copy.deepcopy(identity)
                self.assertEqual(self.check(evidence, kind), [])
                # Object.toString diagnostic identity hashes can collide. The
                # actual Lua reference equality remains the observed authority.
                identity['before']['requested']['ref'] = identity['before']['carried']['ref']
                evidence[5][0]['ui']['waiverIdentity'] = copy.deepcopy(identity)
                self.assertEqual(self.check(evidence, kind), [])

    def test_optional_return_waiver_rejects_inexact_or_mutated_identity(self):
        mutations = {
            'no evidence': lambda v: v.clear(),
            'wrong actor': lambda v: v.update(actor=99),
            'wrong case': lambda v: v.update(case='root.header-cancel'),
            'wrong source': lambda v: v.update(source='root'),
            'wrong action': lambda v: v.update(actionRef='foreign'),
            'wrong token': lambda v: v.update(token=99),
            'wrong requested ID': lambda v: v['before']['requested'].update(id=999),
            'wrong requested type': lambda v: v['before']['requested'].update(type='Base.Pen'),
            'wrong carried ID': lambda v: v['before']['carried'].update(id=999),
            'wrong carried type': lambda v: v['after']['carried'].update(type='Base.Pen'),
            'nested carried book': lambda v: v['before']['carried'].update(container='other'),
            'not direct root': lambda v: v['before'].update(directRootMatches=0),
            'duplicate carried': lambda v: v['before'].update(rootMatches=2),
            'destination duplicate': lambda v: v['after'].update(destinationMatches=1),
            'boolean root count': lambda v: v['before'].update(rootMatches=True),
            'preview mutated item': lambda v: v.update(previewUnchanged=False),
            'invented replacement': lambda v: v.update(actualReplicaReplacement=True),
            'nonscalar replacement': lambda v: v.update(actualReplicaReplacement=1),
            'reference contradiction': lambda v: v['before']['requested'].update(ref='Literature@foreign'),
            'wrong after binding': lambda v: v['after']['requested'].update(ref='Literature@foreign'),
            'changed carried object': lambda v: v['after']['carried'].update(ref='Literature@foreign'),
            'initial capture after boundary': lambda v: v.update(beforeAt=11),
            'preview check before boundary': lambda v: v.update(previewCheckedAt=9),
            'native group changed at commit': lambda v: v.update(groupUnchangedAfterCommit=False),
            'observation after gesture': lambda v: v.update(afterAt=11),
        }
        for name, mutate in mutations.items():
            evidence = self.evidence('world.return-child-cancel')
            identity = evidence[0]['boundary']['ui']['waiverIdentity']; mutate(identity)
            # Keep the raw boundary aligned, so failure comes from the typed identity proof.
            evidence[5][0]['ui']['waiverIdentity'] = copy.deepcopy(identity)
            with self.subTest(name=name):
                self.assertTrue(any('waiver' in error.lower() or 'replica' in error.lower() for error in self.check(evidence)))
        evidence = self.evidence('world.header-cancel')
        evidence[0]['boundary']['ui']['waiverIdentity'] = {}
        self.assertTrue(self.check(evidence))
        evidence = self.evidence('world.return-child-cancel')
        duplicate = copy.deepcopy(next(record for record in evidence[0]['records'] if record['role'] == 'return'))
        duplicate.update(sequence=900, token=900, actionRef='unexpected-return')
        evidence[0]['records'].append(duplicate)
        self.assertTrue(self.check(evidence), 'an unrelated-token extra return must not escape the zero-transfer gate')

    def test_targeted_ordered_bank_has_complete_selected_raw_evidence(self):
        cases = ['root.header-cancel', 'worn-bag.return-child-cancel', 'world.return-child-cancel']
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                with self.subTest(kind=kind, mode=mode), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory); selection, client, server = self.log_bank(kind, mode, cases=cases)
                    (root / 'client1-launch.log').write_text(client); (root / 'server-launch.log').write_text(server)
                    self.assertEqual(a.verify(root, selection, {})['issues'], [])
                    self.assertEqual(adapter.selected_cases(selection), cases)
                    self.assertTrue(adapter.complete(selection, 'client1', client))
                    line = next(line for line in client.splitlines() if adapter.PREFIX + 'ADMISSION ' in line)
                    for changed in (client + '\n' + line, client.replace(line, '', 1),
                                    client + '\n' + line.replace('root.header-cancel', 'world.header-cancel')):
                        (root / 'client1-launch.log').write_text(changed)
                        self.assertTrue(a.verify(root, selection, {})['issues'])
        selection = self.selection(); selection['cases'] = list(reversed(cases))
        with self.assertRaises(ValueError): adapter.validate(selection)
        selection['cases'] = [cases[0], cases[0]]
        with self.assertRaises(ValueError): adapter.validate(selection)
        selection['cases'] = ['foreign.case']
        with self.assertRaises(ValueError): adapter.validate(selection)

    def request_evidence(self, case='worn-bag.move-equip', kind='mp', mode='toolkit'):
        evidence = self.evidence(case, kind, mode)
        row, ids = evidence[:2]
        source, name = case.split('.', 1)
        negative = mode == 'native' or kind != 'mp' or source == 'root' or a.base_control(name) == 'return-child-cancel' or a.capacity_case(name)
        targets = [r for r in row['records'] if r['role'] == ('front' if source == 'root' else 'return')]
        for record in targets:
            def sample(point, at, observation=False, current=False, transaction=0, allocated=False):
                return dict(case=case,sequence=record['sequence'],actor=ids['actor'],item=ids['front']['id'],itemType=ids['front']['type'],
                    token=record['token'],actionRef=record['actionRef'],nativeRef=record.get('nativeRef',False) if allocated else False,
                    point=point,at=at,current=current,transaction=transaction,observation=copy.deepcopy(observation),watchPending=observation is not False)
            record['requestStates'] = [sample('pending',1)]
            if not negative:
                tx=record['transaction']
                state=dict(phase='submitted',boundary='start',sourceExact=True,ambiguous=False,paired=False,
                    nativeHandle=True,currentHandle=True,wireAmbiguous=False,transaction=tx,id=ids['front']['id'],fullType=ids['front']['type'])
                record['requestStates'].append(sample('started',2,state,True,tx,True))
                record['requestStates'].append(sample('perform-begin',3,state,True,tx,True))
                state['paired']=True
                record['requestStates'].append(sample('perform-finish',4,state,False,0,True))
            record['requestStates'].append(sample('terminal',5))
        if kind=='mp' and a.capacity_case(name):
            record=next(r for r in row['records'] if r['role']=='return')
            if mode=='native':
                record.update(started=True,startedAt=17,allocatedAt=16,nativeRef='java:7',transaction=7,transactionDone=False,transactionRejected=True)
            entry=dict(case=case,sequence=record['sequence'],actor=ids['actor'],item=ids['front']['id'],itemType=ids['front']['type'],
                actionRef=record['actionRef'],nativeRef=record['nativeRef'],transaction=record['transaction'],at=18,point='entry',
                current=True,nativePresent=True,endpointsExact=True,nativeSource=True,guarded=mode=='toolkit',done=False,rejected=True,observation=False)
            if mode=='toolkit':
                entry['observation']=dict(phase='submitted',boundary='start',sourceExact=True,ambiguous=False,paired=False,
                    nativeHandle=True,currentHandle=True,wireAmbiguous=False,transaction=record['transaction'],id=ids['front']['id'],fullType=ids['front']['type'])
            record['nativeStopEntry']=entry
            record['nativeStopReturned']=dict(case=case,sequence=record['sequence'],actor=ids['actor'],item=ids['front']['id'],itemType=ids['front']['type'],
                actionRef=record['actionRef'],nativeRef=record['nativeRef'],transaction=0 if mode=='toolkit' else record['transaction'],at=19,point='returned',returned=True,sameNative=True)
        return evidence

    def test_native_requests_require_exact_capture_and_explicit_absence_controls(self):
        for kind,mode,case in [('mp','toolkit','worn-bag.move-equip'),('mp','toolkit','world.header-cancel'),
                ('mp','toolkit','root.move-volume'),('mp','native','worn-bag.move-equip'),
                ('sp','toolkit','world.header-cancel'),('mp','toolkit','worn-bag.return-child-cancel'),
                ('mp','toolkit','world.header-cancel-capacity-lost')]:
            evidence=self.request_evidence(case,kind,mode);selection=self.selection(kind,mode)
            selection['options']['require_native_requests']=True
            self.assertEqual(a.native_request_errors(evidence[0],case,selection,evidence[1]),[],(kind,mode,case))
        selection=self.selection();selection['options']['require_native_requests']=1
        with self.assertRaises(ValueError):adapter.validate(selection)

    def test_native_request_pairing_can_describe_a_rejected_stop_without_success(self):
        evidence=self.request_evidence('worn-bag.header-cancel-capacity-lost');row,ids=evidence[:2]
        record=next(r for r in row['records']if r['role']=='return'and r['started'])
        state=dict(phase='submitted',boundary='start',sourceExact=True,ambiguous=False,paired=False,
            nativeHandle=True,currentHandle=True,wireAmbiguous=False,transaction=record['transaction'],id=ids['front']['id'],fullType=ids['front']['type'])
        first=copy.deepcopy(record['requestStates'][0]);first.update(point='started',at=2,current=True,
            nativeRef=record['nativeRef'],transaction=record['transaction'],observation=copy.deepcopy(state))
        state['paired']=True
        terminal=copy.deepcopy(first);terminal.update(point='terminal',at=3,current=False,observation=state)
        record['requestStates']=[record['requestStates'][0],first,terminal]
        record['finishes']=[];record.pop('performedAt',None)
        selection=self.selection();selection['options']['require_native_requests']=True
        self.assertEqual(a.native_request_errors(row,row['id'],selection,ids),[])
        for mutate in [lambda r:r.update(returnSucceeded=True),lambda r:r.update(blockedReturn=False),
                lambda r:r['blockedReturn'].update(reason='unmoved'),lambda r:r['server']['books']['front'].update(container='world')]:
            changed=copy.deepcopy(row);mutate(changed)
            self.assertTrue(a.native_request_errors(changed,changed['id'],selection,ids))

    def test_native_transfer_rejection_requires_live_paired_stop_evidence(self):
        for mode in ('toolkit','native'):
            selection=self.selection(mode=mode);selection['options']['require_native_requests']=True
            for case in adapter.CAPACITY_CASES:
                row,ids=self.request_evidence(case,mode=mode)[:2]
                self.assertEqual(a.native_transfer_stop_errors(row,case,selection,ids),[])
                mutations=[lambda r:r.pop('nativeStopEntry'),lambda r:r.pop('nativeStopReturned'),
                    lambda r:r['nativeStopEntry'].update(done=True),lambda r:r['nativeStopEntry'].update(rejected=False),
                    lambda r:r['nativeStopEntry'].update(current=False),lambda r:r['nativeStopEntry'].update(nativePresent=False),
                    lambda r:r['nativeStopEntry'].update(guarded=1),lambda r:r['nativeStopEntry'].update(endpointsExact=False),lambda r:r['nativeStopEntry'].update(nativeSource=False),
                    lambda r:r['nativeStopEntry'].update(sequence=True),lambda r:r['nativeStopEntry'].update(actor=True),
                    lambda r:r['nativeStopEntry'].update(item=True),lambda r:r['nativeStopEntry'].update(transaction=True),
                    lambda r:r['nativeStopEntry'].update(nativeRef='foreign'),lambda r:r['nativeStopEntry'].update(actionRef='foreign'),
                    lambda r:r['nativeStopEntry'].update(case='root.header-cancel'),lambda r:r['nativeStopEntry'].update(at=float('nan')),
                    lambda r:r['nativeStopEntry'].update(extra={'unbounded':'object'}),lambda r:r['nativeStopReturned'].update(transaction=99),
                    lambda r:r['nativeStopReturned'].update(at=1),lambda r:r['nativeStopReturned'].update(returned=False),
                    lambda r:r['nativeStopReturned'].update(sameNative=False)]
                if mode=='toolkit':
                    mutations += [lambda r:r['nativeStopEntry']['observation'].update(currentHandle=False),
                        lambda r:r['nativeStopEntry']['observation'].update(wireAmbiguous=True),
                        lambda r:r['nativeStopEntry']['observation'].update(paired=True),
                        lambda r:r['nativeStopEntry']['observation'].update(id=True),
                        lambda r:r['nativeStopEntry']['observation'].update(transaction=True),
                        lambda r:r['nativeStopEntry'].update(observation=False)]
                else: mutations += [lambda r:r['nativeStopEntry'].update(observation={'sourceExact':True}),
                    lambda r:(r['nativeStopEntry'].update(guarded=True),r['nativeStopReturned'].update(transaction=0))]
                for index,mutate in enumerate(mutations):
                    changed=copy.deepcopy(row);record=next(r for r in changed['records']if r['role']=='return');mutate(record)
                    self.assertTrue(a.native_transfer_stop_errors(changed,case,selection,ids),(case,mode,index))
        selection=self.selection(kind='sp');selection['options']['require_native_requests']=True
        row,ids=self.request_evidence(adapter.CAPACITY_CASES[0],kind='sp')[:2]
        self.assertEqual(a.native_transfer_stop_errors(row,row['id'],selection,ids),[])

    def test_native_transfer_rejection_stays_strict_without_request_diagnostics(self):
        for mode in ('native', 'toolkit'):
            selection = self.selection(mode=mode)
            for case in adapter.CAPACITY_CASES:
                row, ids = self.evidence(case, mode=mode)[:2]
                self.assertEqual(a.native_transfer_stop_errors(row, case, selection, ids), [])
                for key in ('nativeStopEntry', 'nativeStopReturned'):
                    changed = copy.deepcopy(row)
                    next(record for record in changed['records'] if record['role'] == 'return').pop(key)
                    self.assertTrue(a.native_transfer_stop_errors(changed, case, selection, ids))
                changed = copy.deepcopy(row)
                returned = next(record for record in changed['records'] if record['role'] == 'return')
                returned['nativeStopEntry']['rejected'] = False
                self.assertTrue(a.native_transfer_stop_errors(changed, case, selection, ids),
                                'server debt and a historical rejected flag cannot substitute for a live native Reject')
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory); selection, client, server = self.log_bank(mode=mode, cases=['world.move-volume-capacity-lost'])
                (root / 'server-launch.log').write_text(server); (root / 'client1-launch.log').write_text(client)
                self.assertEqual(a.verify(root, selection, {})['issues'], [])
                for marker in ('TRANSFER_STOP_ENTRY ', 'TRANSFER_STOP_RETURNED '):
                    line = next(line for line in client.splitlines() if marker in line)
                    for changed in (client.replace(line, '', 1), client + '\n' + line,
                                    client + '\n' + line.replace('world.move-volume-capacity-lost', 'foreign.case')):
                        (root / 'client1-launch.log').write_text(changed)
                        self.assertTrue(a.verify(root, selection, {})['issues'])

    def test_actual_native_stop_capture_precedes_removal_with_request_diagnostics_off(self):
        lua = shutil.which('luajit')
        if not lua: self.skipTest('LuaJIT not installed')
        source = r"""
local file=assert(io.open(arg[1]));local text=file:read('*a');file:close()
local first=assert(text:find('function bookControlsNativeTransferStop(',1,true))
local last=assert(text:find('\nlocal function observeStoppedRemoval()',first,true))
assert(loadstring(text:sub(first,last-1)))()
local pollFirst=assert(text:find("  if row.type=='ISInventoryTransferAction'and not row.nativeStopEntry",1,true))
local pollLast=assert(text:find('\n end\n for action,row',pollFirst,true))
local poll=assert(loadstring('return function(row,action)'..text:sub(pollFirst,pollLast-1)..' end'))()
requestsEnabled=false
isClient=function()return true end
nativeRequestState=function()error('disabled request diagnostic was called')end
intact=function()end
now=function()return 100 end
ref=function(value)return tostring(value)end
case=function()return 'world.move-volume-capacity-lost'end
ids={actor=0,source='world',front={id=101,type='Base.BookCarpentry1'}}
local root,source,episode={},{},{}
local book={getID=function()return 101 end,getFullType=function()return 'Base.BookCarpentry1'end}
local player={getInventory=function()return root end,getCharacterActions=function()return{contains=function(_,value)return value==episode end}end}
state={player=player,source=source}
for _,guarded in ipairs({false,true})do
 local live=true;local calls=0
 isItemTransactionDone=function()assert(live,'queried removed transaction');calls=calls+1;return false end
 isItemTransactionRejected=function()assert(live,'queried removed transaction');calls=calls+1;return true end
 local stop=function()end
 local action={item=book,character=player,srcContainer=root,destContainer=source,transactionId=7,action=episode,stop=stop}
 if guarded then action.toolkitTransferGuard={stop=stop}end
 local row={type='ISInventoryTransferAction',role='return',sequence=28,nativeRef=ref(episode),actionRef=ref(action),transaction=7,transactionDone=false,transactionRejected=false}
 tracks={[action]=row};queue=function()return{current=action,queue={action}}end
 nativeStopMatcher=function(value)assert(value==action);return true end
 transferEpisode={action=action,transaction=7,live=true}
 local emitted={};raw=function(marker,value)emitted[#emitted+1]={marker,value}end
 bookControlsNativeTransferStop(action,episode,'entry',true)
 assert(row.nativeStopEntry.rejected and not row.nativeStopEntry.done and row.transactionRejected and not row.transactionDone)
 assert(row.nativeStopEntry.observation==false and row.nativeStopEntry.guarded==guarded and calls==2)
 live=false;if guarded then action.transactionId=0 end
 bookControlsNativeTransferStop(action,episode,'returned',true)
 poll(row,action)
 assert(row.transactionRejected and not row.transactionDone and row.transaction==7 and calls==2,
  'later polling overwrote the positively observed pre-removal terminal state')
 assert(#emitted==2 and emitted[1][1]=='TRANSFER_STOP_ENTRY'and emitted[2][1]=='TRANSFER_STOP_RETURNED')
 assert(row.nativeStopReturned.transaction==(guarded and 0 or 7)and row.nativeStopReturned.sameNative)
 assert(not transferEpisode.live and transferEpisode.rejected and not transferEpisode.done)
end
os.exit(0)
"""
        subprocess.run([lua, '-e', OFFLINE_FIXTURE_EVENTS + source, '--', 'unused', str(ROOT / 'tests/native_queue/book-controls/client/ZZBookControls.lua')], check=True)

    def test_actual_callback_captures_instant_native_episode_without_inventing_start(self):
        lua=shutil.which('luajit')
        if not lua:self.skipTest('LuaJIT not installed')
        text=(ROOT/'tests/native_queue/book-controls/client/ZZBookControls.lua').read_text()
        first=text.index('local function lifecycleBegin(action,step)')
        body=text[first:text.index('local function lifecycleFinish(',first)]
        source="""
local run=assert(loadstring(arg[1]..' return lifecycleBegin'))()
local row={type='ISInventoryTransferAction',duration=0,started=false,progress=false}
local action={action={},transactionId=0}
isClient=function()return false end
register=function()return row end;ref=function(value)return value end;now=function()return 25 end
requestsEnabled=true;transferEpisode=nil
requestSample=function(a,r,point)
 assert(point=='perform-begin'and r.nativeRef==a.action and r.allocatedAt==25,'sample lost actual instant episode')
end
assert(run(action,'perform'))
assert(row.nativeRef==action.action and row.allocatedAt==25)
assert(not row.started and not row.progress and row.startedAt==nil and row.effectiveDuration==nil,'callback fabricated native timing')
row.nativeRef={};local ok,err=pcall(run,action,'perform')
assert(not ok and tostring(err):find('native perform episode changed',1,true),'foreign episode accepted')
row.nativeRef=nil;row.allocatedAt=nil;action.action=nil;requestsEnabled=false
assert(run(action,'perform')and row.nativeRef==nil and row.allocatedAt==nil,'missing Java action acquired a native identity')
os.exit(0)
"""
        subprocess.run([lua,'-e',OFFLINE_FIXTURE_EVENTS + source,'--','unused',body],check=True)

    def test_instant_return_request_identity_remains_strict_without_observed_start(self):
        case='world.header-cancel-favorite';evidence=self.request_evidence(case,'sp','native')
        row,ids=evidence[:2];selection=self.selection('sp','native');selection['options']['require_native_requests']=True
        extra=copy.deepcopy(next(r for r in row['records']if r['role']=='return'))
        extra.update(sequence=800,actionRef='ISInventoryTransferAction 0x800',token=77,duration=0,
                     started=False,progress=False,nativeRef='java:800',allocatedAt=2,performedAt=4)
        extra['requestStates']=[]
        for point,at,native,current in [('pending',1,False,True),('perform-begin',2,'java:800',True),
                                        ('perform-finish',4,'java:800',False),('terminal',5,'java:800',False)]:
            extra['requestStates'].append(dict(case=case,sequence=800,actor=ids['actor'],item=ids['front']['id'],
                itemType=ids['front']['type'],token=77,actionRef=extra['actionRef'],nativeRef=native,
                point=point,at=at,current=current,transaction=0,observation=False,watchPending=False))
        row['records'].append(extra)
        self.assertEqual(a.native_request_errors(row,case,selection,ids),[])
        for mutate in (lambda r:r.pop('nativeRef'),lambda r:r.update(nativeRef='foreign'),
                       lambda r:r['requestStates'][2].update(nativeRef='foreign'),
                       lambda r:r['requestStates'][-1].update(observation={'phase':'submitted'})):
            changed=copy.deepcopy(row);mutate(changed['records'][-1])
            self.assertTrue(a.native_request_errors(changed,case,selection,ids))

    def test_native_request_negative_evidence_has_strict_scalar_schema(self):
        selection=self.selection();selection['options']['require_native_requests']=True
        base=self.request_evidence('root.header-cancel')
        changes=[lambda s:s.pop('transaction'),lambda s:s.update(transaction={'object':'bad'}),
            lambda s:s.update(transaction=True),lambda s:s.update(nativeRef='foreign'),
            lambda s:s.update(extra={'unbounded':['object']}),lambda s:s.update(token=True)]
        for mutate in changes:
            changed=copy.deepcopy(base);mutate(changed[0]['records'][0]['requestStates'][0])
            self.assertTrue(a.native_request_errors(changed[0],changed[0]['id'],selection,changed[1]))

    def test_native_request_causal_mutations_reject_false_pairing(self):
        base=self.request_evidence();selection=self.selection();selection['options']['require_native_requests']=True
        mutations={
            'foreign actor':lambda r:r['requestStates'][1].update(actor=999),
            'boolean actor alias':lambda r:r['requestStates'][1].update(actor=False),
            'foreign item':lambda r:r['requestStates'][1].update(item=999),
            'foreign action':lambda r:r['requestStates'][1].update(actionRef='foreign'),
            'foreign native':lambda r:r['requestStates'][1].update(nativeRef='foreign'),
            'missing source':lambda r:r['requestStates'][1]['observation'].update(sourceExact=False),
            'no handle':lambda r:r['requestStates'][1]['observation'].update(nativeHandle=False),
            'byte reuse':lambda r:r['requestStates'][3]['observation'].update(wireAmbiguous=True),
            'ambiguous nested':lambda r:r['requestStates'][3]['observation'].update(ambiguous=True),
            'foreign byte':lambda r:r['requestStates'][3]['observation'].update(transaction=-127),
            'wrong boundary':lambda r:r['requestStates'][3]['observation'].update(boundary='continuation'),
            'early pair':lambda r:r['requestStates'][1]['observation'].update(paired=True),
            'missing final pair':lambda r:r['requestStates'][3]['observation'].update(paired=False),
            'no current anchor':lambda r:[v.update(current=False)for v in r['requestStates']],
            'missing terminal':lambda r:r['requestStates'].pop(),
            'duplicate':lambda r:r['requestStates'].insert(2,copy.deepcopy(r['requestStates'][1])),
            'unbounded':lambda r:r.update(requestStates=r['requestStates']*4),
        }
        for reason,mutate in mutations.items():
            changed=copy.deepcopy(base);record=next(r for r in changed[0]['records']if r['role']=='return');mutate(record)
            self.assertTrue(a.native_request_errors(changed[0],changed[0]['id'],selection,changed[1]),reason)
        state=next(r for r in base[0]['records']if r['role']=='return')['requestStates'][1]['observation']
        negative=self.request_evidence('root.header-cancel');negative[0]['records'][0]['requestStates'][0]['observation']=state
        self.assertTrue(a.native_request_errors(negative[0],negative[0]['id'],selection,negative[1]))

    def test_native_request_raw_and_setup_binding_cannot_be_fabricated(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);selection,client,server=self.log_bank(requests=True)
            (root/'server-launch.log').write_text(server);(root/'client1-launch.log').write_text(client)
            self.assertEqual(a.verify(root,selection,{})['issues'],[])
            lines=client.splitlines();request=next(v for v in lines if 'NATIVE_REQUEST 'in v)
            for changed in [client.replace('"nativeRequestsObserved": true','"nativeRequestsObserved": false'),
                    '\n'.join(v for v in lines if v!=request),client+'\n'+request]:
                (root/'client1-launch.log').write_text(changed)
                self.assertTrue(a.verify(root,selection,{})['issues'])

    def test_native_request_current_anchor_requires_live_object(self):
        row,ids=self.request_evidence()[:2];selection=self.selection();selection['options']['require_native_requests']=True
        for record in row['records']:
            for sample in record.get('requestStates',[]):
                if isinstance(sample['observation'],dict):sample['observation']['currentHandle']=False
        self.assertTrue(a.native_request_errors(row,row['id'],selection,ids))

    def test_native_transfer_finish_preserves_pre_removal_episode_without_query(self):
        lua=shutil.which('luajit')
        if not lua:self.skipTest('LuaJIT not installed')
        source=r"""
local file=assert(io.open(arg[1]));local text=file:read('*a');file:close()
local first=assert(text:find('local function lifecycleFinish(',1,true))
local last=assert(text:find('\nlocal function request(command)',first,true))
local finish=assert(loadstring(text:sub(first,last-1)..'\nreturn lifecycleFinish'))()
local epFirst=assert(text:find('local function updateTransferEpisode(',1,true))
local epLast=assert(text:find('\n-- The disposable Java probe',epFirst,true))
local update=assert(loadstring(text:sub(epFirst,epLast-1)..'\nreturn updateTransferEpisode'))()
isClient=function()return true end
local retained={live=false,done=false,rejected=true,observedAt=10}
transferEpisode=retained
update({}, {type='ISInventoryTransferAction',role='return',nativeStopEntry={}})
assert(transferEpisode==retained and retained.observedAt==10 and retained.rejected==true)
now=function()return 12 end
requestsEnabled=false
isItemTransactionDone=function()error('queried a removed native transaction')end
isItemTransactionRejected=isItemTransactionDone
for _,step in ipairs({'stop','perform'})do
 local action={};local row={finishes={}}
 register=function(value)assert(value==action);return row end
 transferEpisode={action=action,transaction=7,live=true,done=step=='perform',rejected=step=='stop',observedAt=10}
 finish(action,step,true)
 assert(transferEpisode.live==false and transferEpisode.terminalAt==12 and transferEpisode.observedAt==10)
 assert(transferEpisode.done==(step=='perform')and transferEpisode.rejected==(step=='stop'))
 assert(#row.finishes==1 and row.finishes[1].phase==step and row.finishes[1].succeeded==true)
end
os.exit(0)
"""
        subprocess.run([lua,'-e',OFFLINE_FIXTURE_EVENTS + source,'--','unused',str(ROOT/'tests/native_queue/book-controls/client/ZZBookControls.lua')],check=True)

    def test_native_transfer_stop_raw_pair_cannot_be_dropped_or_duplicated(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);selection,client,server=self.log_bank(requests=True)
            (root/'server-launch.log').write_text(server);(root/'client1-launch.log').write_text(client)
            self.assertEqual(a.verify(root,selection,{})['issues'],[])
            for marker in ('TRANSFER_STOP_ENTRY ','TRANSFER_STOP_RETURNED '):
                line=next(value for value in client.splitlines()if marker in value)
                for changed in [client.replace(line,'',1),client+'\n'+line,client+'\n'+line.replace('worn-bag.header-cancel-capacity-lost','foreign.case')]:
                    (root/'client1-launch.log').write_text(changed)
                    self.assertTrue(a.verify(root,selection,{})['issues'])

    def active_edit_receipt(self, row, legacy_allowed=None):
        case, mode, kind = row['id'], row['mode'], row['kind']
        source = case.split('.')[0]; enabled = mode == 'toolkit'; borrowed = enabled and source != 'root'
        device = case in adapter.DEVICE_ONLY_CASES
        if legacy_allowed is None: legacy_allowed = enabled
        item, root, destination = 'Literature@live', 'ItemContainer@root', 'ItemContainer@' + source
        book = row['ids']['front']; bag = row['ids']['bag']
        ledger = dict(status='observed' if enabled else 'unhandled', reason=False if enabled else 'unavailable',
                      borrowings=[], earnedPreparations=int(borrowed))
        if enabled: ledger.update(generation=10, legacyHints=borrowed, providersPresent=False)
        if borrowed:
            ledger['borrowings'] = [dict(id=book['id'], fullType=book['type'], state='active', ambiguous=False,
                source=destination, destination=root, returning=False, plannedReturn=False,
                sourceOwner=dict(id=bag['id'], fullType=bag['type']) if bag else False)]
        projection = dict(status='unhandled', reason='edit_unknown', externalCapacity=borrowed, allowedAbsent=True) if enabled else False
        observer = dict(status='observed' if enabled else 'unhandled', reason=False if enabled else 'unavailable',
                        allowedAbsent=True, projection=projection, returns=int(borrowed), unresolved=0)
        sources = dict(observer='ActionQueuePolicy.lua', cleanup='ActionQueueSettlement.lua', bulk='BulkActions.lua',
                       compat='ActionQueueCompat.lua', carts='ActionQueueCarts.lua',
                       transferConstructor='CartTransferInterceptor.lua', transferPerform='ActionQueueCompat.lua')
        value = dict(schema=1, case=case, kind=kind, mode=mode, queueEnabled=enabled,
            scope='active-edit-native-return-effect-observation', mutationAuthorized=False, permissionsMeasured=False,
            current=row['boundary']['reader'], currentNative=row['boundary']['native'], currentLuaStartedPresent=False,
            currentLuaStarted=False, nativeStarted=True, nativeFinished=False, nativeForceComplete=False,
            liveItem=item, source=source, observer=observer,
            existingDecision=dict(entrypoint='Policy.evaluateCancel', allowed=legacy_allowed, reason=False if legacy_allowed else 'unavailable', whole=True),
            ledgerBefore=ledger, ledgerAfter=copy.deepcopy(ledger), nativeFacts=False, aliasFacts=False, prototype=False, effect=False,
            qualifiedReturn=borrowed, readOnly=True, uiUnchanged=True, passed=True, failure=False, sources=sources)
        if borrowed:
            action = next(r['actionRef'] for r in row['records'] if r['role'] == 'return')
            value['nativeFacts'] = dict(scope='independent-native-value-probe', schema=2, item=item, source=root, destination=destination,
                destinationOwner='InventoryContainer@bag' if bag else False, destinationOwnerFullType=bag['type'] if bag else False,
                primaryKnown=True, primaryFullType=False)
            value['prototype'] = dict(action=action, item=item, member=item, liveItem=item, sameItemReference=True,
                sameMemberReference=True, itemId=book['id'], itemType=book['type'], source=root, destination=destination,
                stopSource='BulkActions.lua', performSource=sources['transferPerform'], constructorSource=sources['transferConstructor'],
                allowMissingItems=True, pending=True)
            value['effect'] = dict(version=1, complete=True, capacity='external', domain='item', id=book['id'], fullType=book['type'],
                item=item, source=root, destination=destination, actionAbsent=True, synthetic=True,
                resources=1, requirements=1, effects=1, field='location')
        else: value['control'] = 'no-loan' if enabled else 'queue-disabled'
        def distribution(samples):
            return dict(samplesMs=samples, samples=3, minMs=min(samples), medianMs=sorted(samples)[1],
                        maxMs=max(samples), meanMs=sum(samples)/3)
        comparable = borrowed and legacy_allowed
        value['performance'] = dict(scope='paired-live-header-return-entrypoints', timer='System.nanoTime', units='ms',
            warmupPairs=1, pairs=3, sameLiveIntent=True, whole=True,
            firstUseScope='first-call-after-untimed-identity-ledger-and-native-facts-diagnostics',
            baseline=distribution([.2,.1,.3]), observer=distribution([.3,.2,.1]), baselineFirstMs=.4, observerFirstMs=.5,
            comparable=comparable, comparisonReason='useful-return-effect-layer-and-existing-cancel-success' if comparable else value.get('control','existing-cancel-denied-or-observer-unknown'),
            observerProjectionStatus=projection['status'] if projection else False, observerProjectionReason=projection['reason'] if projection else False,
            timerOverhead='included-not-subtracted', sameOutputContract=False, completeEditMeasured=False, frameLoadMeasured=False,
            positiveTimingClaim=False, assessment='not-assessed')
        if device:
            if enabled: value.pop('control', None)
            value.update(schema=3 if enabled else 1,scope='active-edit-device-only-deferred-native-phase-observation' if enabled else 'active-edit-device-only-preempt-observation', qualifiedReturn=False, effect=False, nativeFacts=False, aliasFacts=False,
                intent=dict(kind='move', action=row['boundary']['reader'] if a.base_control(row['ids']['control'])=='demote-reader' else next(r['actionRef'] for r in row['records'] if r['role']=='volume'), target=next(r['actionRef'] for r in row['records'] if r['role']=='volume') if a.base_control(row['ids']['control'])=='demote-reader' else row['boundary']['reader'], after=a.base_control(row['ids']['control'])=='demote-reader'))
            value['existingDecision'] = dict(entrypoint='Policy.evaluateMove', allowed=enabled, reason=False if enabled else 'unavailable', whole=False, commonActiveEdit=False)
            if enabled:
                projection.update(status='deferred', reason='edit_native_resolution', externalCapacity=True)
                approach=next(r for r in row['records'] if r['role']=='preparation'and r['type']=='ISQueueActionsAction'and r['token']==30)
                phase=dict(version=1,kind='deferred-spatial',actor=approach['approach']['actor'],targetSquare=approach['approach']['targetSquare'],
                    invalidates='all-resources',routing='native',expansion='native',outcome='native')
                projection.update(blocker=approach['actionRef'],evaluatedPrefix=1,deferred=[dict(action=approach['actionRef'],index=2,descriptor=copy.deepcopy(phase))])
                nodes = [dict(kind='checkpoint', action=row['boundary']['reader'], complete=True, capacity='unchanged'),
                    dict(kind='pending',action=approach['actionRef'],complete=False,capacity=False,deferred=copy.deepcopy(phase)),
                    dict(kind='pending', action=next(r['actionRef'] for r in row['records'] if r['role']=='volume'), complete=True, capacity='unchanged'),
                    dict(kind='resume', action=row['boundary']['reader'], complete=True, capacity='unchanged')]
                for returning in (r for r in row['records'] if r['role']=='return'):
                    effect=dict(version=1,complete=True,capacity='external',domain='item',id=book['id'],fullType=book['type'],item=item,
                        source=root,destination=destination,action=returning['actionRef'],synthetic=False,resources=1,requirements=1,effects=1,field='location')
                    nodes.append(dict(kind='pending',action=returning['actionRef'],complete=True,capacity='external',returnEffect=effect))
                nodes.append(dict(kind='pending', action=next(r['actionRef'] for r in row['records'] if r['role']=='tail'), complete=True, capacity='unchanged'))
                value['plan'] = dict(kind='preempt', nodes=nodes)
                at=next(index for index,r in enumerate(row['boundary']['queue'],1) if r.get('actionRef')==approach['actionRef'])
                value['diagnostics']=dict(contractGaps=[],
                    nodes=[dict(kind=n['kind'],action=n['action'],complete=n['complete'],**({'deferred':copy.deepcopy(n['deferred'])} if 'deferred'in n else {})) for n in nodes],projectionBlockerType='ISQueueActionsAction',gapsTruncated=False,nodesTruncated=False)
            else: value['plan'] = False
            observer['returns'] = 0
            value['performance'].update(scope='paired-live-device-preempt-entrypoints', whole=False, comparable=False,
                comparisonReason='deferred-native-phase-not-full-projection' if enabled else 'queue-disabled',
                observerProjectionStatus='deferred' if enabled else False, observerProjectionReason='edit_native_resolution' if enabled else False)
        return value

    def test_device_only_variants_use_native_device_chain_and_keep_pen_untouched(self):
        self.assertEqual(adapter.PROMOTE_DEVICE_ONLY_CASES, tuple(source+'.move-volume-device-only' for source in adapter.SOURCES))
        self.assertEqual(adapter.DEMOTE_DEVICE_ONLY_CASES, tuple(source+'.demote-reader-device-only' for source in adapter.SOURCES))
        self.assertEqual(len(adapter.CASES), 20, 'existing mixed bank must remain unchanged')
        self.assertEqual(set(adapter.DECLARED_CASES)-set(adapter.CASES), set(adapter.DEVICE_ONLY_CASES))
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                for case in adapter.DEVICE_ONLY_CASES:
                    with self.subTest(kind=kind, mode=mode, case=case):
                        evidence = self.evidence(case, kind, mode)
                        row, ids = evidence[:2]
                        self.assertFalse(any(r['role']=='equip' or r['type']=='ISEquipWeaponAction' for r in row['records']))
                        self.assertFalse(any(r['role']=='equip' for r in evidence[4][0]['queue']))
                        self.assertIs(evidence[4][0]['equipProducer'], False)
                        self.assertIs(row['boundary']['equipPending'], False)
                        self.assertIs(row['equipSnapshot'], False)
                        self.assertEqual(row['client']['hands'], ids['baseline']['hands'])
                        self.assertEqual(next(i for i in row['client']['items'] if i['id']==ids['pen']['id']), next(i for i in ids['baseline']['items'] if i['id']==ids['pen']['id']))
                        self.assertEqual(self.check(evidence, kind, mode), [])
        selection=self.selection();selection['cases']=list(adapter.DEVICE_ONLY_CASES)
        with self.assertRaisesRegex(ValueError, 'active_edit_observation'): adapter.validate(selection)
        selection['options'].update(active_edit_observation=True, precise_timing=True)
        adapter.validate(selection)
        for bad in ('root.move-equip-device-only', 'world.move-volume-device-only-capacity-lost', 'world.move-volume-favorite-device-only'):
            selection['cases']=[bad]
            with self.assertRaises(ValueError): adapter.validate(selection)

    def test_actual_device_only_fixture_omits_equip_producer_and_uses_move_observation(self):
        lua=shutil.which('luajit')
        if not lua: self.skipTest('LuaJIT not installed')
        source=r"""
local file=assert(io.open(arg[1]));local text=file:read('*a');file:close()
local first=assert(text:find('local function enqueue()',1,true))
local last=assert(text:find('\nlocal function diagnostic(',first,true))
local enqueue=assert(loadstring(text:sub(first,last-1)..'\nreturn enqueue'))()
local fixture=assert(loadfile(arg[2]))()
for _,source in ipairs({'root','worn-bag','world'})do
 local base,lost,favorite,only=fixture.parseControl('move-volume-device-only')
 assert(base=='move-volume'and only and not lost and not favorite)
 for _,device in ipairs({false,true})do
  front,tail,volume,equip=nil,nil,nil,nil
  local inv={};state={front={},tail={},pen={},tv={},data={}}
  state.player={getPlayerNum=function()return 0 end,getInventory=function()return inv end,hasTrait=function()return false end,isTimedActionInstant=function()return false end}
  ids={baseline={},pen={id=3},front={id=1},source=source,targetVolume=.25}
  state.front.getID=function()return 1 end
  local q={queue={}};queue=function()return q end
  deviceOnly=function()return device end
  F={snapshot=function()return{}end,same=function()return true end};authorityBaseline={};now=function()return 1 end
  CharacterTrait={DISORGANIZED={},ILLITERATE={}}
  local reads,equips,volumes=0,0,0
  producer=function(items)reads=reads+1;q.queue[#q.queue+1]={role=items[1]==state.front and'front'or'tail',item=items[1]}end
  equipProducer=function(item)equips=equips+1;q.queue[#q.queue+1]={role='equip',item=item,primary=true,twoHands=false};item.getContainer=function()return inv end end
  RWMMergedTV={new=function()return{initialise=function()end,instantiate=function()end,readFromObject=function()return true end,
   volumeBar={getVolumeSteps=function()return 4 end,onVolumeChange=function(window,value)
    volumes=volumes+1;q.queue[#q.queue+1]={role='volume',secondaryItem=value/4,deviceData=state.data,maxTime=30}
   end}}end}
  role=function(action)return action.role end;register=function()end;queueEvidence=function()return{}end;case=function()return source..'.move-volume'end
  raw=function(marker,value)if marker=='ADMISSION'then if device then assert(value.equipProducer==false)else assert(value.equipProducer=='ISInventoryPaneContextMenu.equipWeapon')end end end
  enqueue()
  assert(reads==2 and volumes==1 and equips==(device and 0 or 1))
  assert((equip==nil)==device and front.item==state.front and tail.item==state.tail)
 end
end
local run=assert(loadfile(arg[3]))().run
local item={getID=function()return 1 end,getFullType=function()return'Base.Book'end}
local native={isStarted=function()return true end,finished=function()return false end,isForceComplete=function()return false end}
local front={Type='ISReadABook',item=item,action=native,toolkitQueueOperation={}}
local actor={getInventory=function()return{}end};local target={}
local phase={version=1,kind='deferred-spatial',actor=actor,targetSquare=target,invalidates='all-resources',routing='native',expansion='native',outcome='native'}
local volume,tail={Type='ISRadioAction',toolkitQueueOperation={}},{Type='ISReadABook'}
local approach={Type='ISQueueActionsAction',toolkitQueueApproach=true,toolkitQueueOperation=volume.toolkitQueueOperation}
local q={current=front,queue={front,approach,volume,tail}}
local ui={size=function()return 0 end};UIManager={getUI=function()return ui end}
local off,demoting,unexpected=false,false,false;local observations,moves=0,0
local function observe(queue,intent)
 observations=observations+1;assert(queue==q and intent.kind=='move'and intent.action==(demoting and front or volume)and intent.target==(demoting and volume or front)and intent.after==demoting)
 if off then return{status='unhandled',reason='unavailable'}end
 local edit={complete=true,capacity='unchanged'}
 local result={status='observed',kind='preempt',unresolved={},nodes={{kind='checkpoint',action=front,edit=edit},{kind='pending',action=approach,deferred=phase},
  {kind='pending',action=volume,edit=edit},{kind='resume',action=front,edit=edit},{kind='pending',action=tail,edit=edit}},
  projection={status='deferred',reason='edit_native_resolution',blocker=approach,externalCapacity=true,evaluatedPrefix=1,deferred={{action=approach,index=2,descriptor=phase}}},contractGaps={}}
 if unexpected then
  result.nodes[3].edit=nil;result.contractGaps[1]={index=3,actionType='ISRadioAction',reason='effects_unproven'}
  if unexpected=='bounded'then for index=2,40 do result.nodes[index]=result.nodes[3];result.contractGaps[index]=result.contractGaps[1]end end
 end
 return result
end
local function move(queue,action,target,after)moves=moves+1;assert(queue==q and action==(demoting and front or volume)and target==(demoting and volume or front)and after==demoting);return{allowed=not off,reason=off and'unavailable'or nil}end
local function ledger()return{status=off and'unhandled'or'observed',steps={},borrowings={}}end
local function owned(action)return action==approach end
local toolkit={ActionQueuePolicy={observeActiveEdit=observe,evaluateMove=move},ActionQueueSettlement={editLedger=ledger},ActionQueueApproach={isAction=owned}}
getFilenameOfClosure=function(fn)if fn==observe then return'ActionQueuePolicy.lua'elseif fn==ledger then return'ActionQueueSettlement.lua'elseif fn==owned then return'ActionQueueApproach.lua'end end
ISInventoryTransferAction={}
local tick=0;local context={toolkit=toolkit,queue=q,front=front,state={front=item,player=actor},spatialIdentity={actor=actor,targetSquare=target},
 fixture={snapshot=function()return{}end,same=fixture.same},ids={source='root',front={id=1,type='Base.Book'}},case='root.move-volume-device-only',
 kind='sp',mode='toolkit',native=false,control='move-volume',deviceOnly=true,volume=volume,precise=true,clock=function()tick=tick+1;return tick end}
local receipt=run(context)
assert(receipt.passed and receipt.readOnly and not receipt.existingDecision.commonActiveEdit and receipt.intent.action==tostring(volume))
assert(receipt.schema==3 and receipt.plan.kind=='preempt'and #receipt.plan.nodes==5 and not receipt.plan.nodes[2].complete and receipt.observer.projection.status=='deferred'and receipt.observer.returns==0)
assert(#receipt.diagnostics.contractGaps==0 and receipt.diagnostics.nodes[2].deferred.kind=='deferred-spatial'and receipt.diagnostics.projectionBlockerType=='ISQueueActionsAction'and not receipt.performance.comparable)
assert(moves==5 and observations==5 and q.current==front and front.action==native)
demoting=true;context.control='demote-reader';context.case='root.demote-reader-device-only'
receipt=run(context);assert(receipt.passed and receipt.intent.action==tostring(front)and receipt.intent.target==tostring(volume)and receipt.intent.after==true and #receipt.plan.nodes==5)
for _,change in ipairs({{'invalidates','position'},{'domain','position'},{'actor',{}},{'targetSquare',{}},{'complete',true},{'futureFacts',{}}})do
 local field,value=change[1],change[2];local previous=phase[field];phase[field]=value
 receipt=run(context);assert(not receipt.passed and receipt.readOnly,'raw malformed descriptor escaped native fixture qualification')
 phase[field]=previous
end
unexpected=true;receipt=run(context);assert(not receipt.passed and receipt.readOnly and #receipt.diagnostics.contractGaps==1 and not receipt.diagnostics.nodes[3].complete)
unexpected='bounded';receipt=run(context);assert(not receipt.passed and #receipt.diagnostics.nodes==32 and #receipt.diagnostics.contractGaps==32 and receipt.diagnostics.nodesTruncated and receipt.diagnostics.gapsTruncated)
unexpected=false;off=true;context.native=true;context.mode='native'
receipt=run(context);assert(receipt.passed and receipt.schema==1 and receipt.plan==false and receipt.observer.projection==false and receipt.existingDecision.commonActiveEdit==false)
os.exit(0)
"""
        subprocess.run([lua,'-e',source,'--','unused',str(ROOT/'tests/native_queue/book-controls/client/ZZBookControls.lua'),
            str(ROOT/'tests/native_queue/book-controls/shared/QueueBookControls.lua'),str(ROOT/'tests/native_queue/book-controls/shared/QueueBookEditObservation.lua')],check=True)

    def test_reader_demotion_fixture_uses_actual_panel_drag_handlers_and_exact_return_resource(self):
        lua=shutil.which('luajit')
        if not lua: self.skipTest('LuaJIT not installed')
        source=r"""
local function read(path)local f=assert(io.open(path));local s=f:read('*a');f:close();return s end
local text=read(arg[1]);local first=assert(text:find('local function timedHandler(',1,true));local last=assert(text:find('\nlocal function resetFailure(',first,true))
local gesture=assert(loadstring(text:sub(first,last-1)..'\nreturn realGesture'))()
text=read(arg[2]);first=assert(text:find('function List:onMouseDown(',1,true));last=assert(text:find('\nfunction List:onMouseUpOutside(',first,true))
List={};assert(loadstring(text:sub(first,last-1)))()
ISScrollingListBox={onMouseDown=function()end,onMouseMove=function()end,onMouseUp=function()end}
cancelsOperation=function(row)return row.header==true end
preciseTiming=true;local tick=0;timingNow=function()tick=tick+1;return tick end;now=function()return tick end
ref=tostring;tokenID=function(token)return token.id end;deviceOnly=function()return true end
control=function()return'demote-reader'end
for _,source in ipairs({'root','worn-bag','world'})do
 local readToken,volumeToken={id=10},{id=30};oldNative={};front={toolkitQueueOperation=readToken,action=oldNative};volume={toolkitQueueOperation=volumeToken};equip=nil
 local approach={toolkitQueueOperation=volumeToken};local q={queue={front,approach,volume},current=front};queue=function()return q end
 ids={source=source};state={player={getPlayerNum=function()return 0 end}}
 local rows={{item=front,operation=readToken,header=source~='root',index=1,height=40},{item=approach,operation=volumeToken,header=true,index=2,height=40}}
 local list=setmetatable({items=rows},{__index=List})
 function list:clearGesture()self.dragAction=nil;self.dragging=nil;self.pressedCancel=nil;self.pressedToggle=nil;self.pressedOperation=nil end
 function list:rowUnderMouse(x,y)return self.items[math.floor(y/40)+1]end
 function list:topOfItem(index)return(index-1)*40 end
 function list:cancelX()return 400 end
 function list:setYScroll()end
 function list:isVScrollBarVisible()return false end
 local panel={list=list,expanded={},initialise=function()end,addToUIManager=function()end,update=function()end,removeFromUIManager=function()end}
 list.parent=panel
 local admission,moved=0,0
 Toolkit={ActionQueue={moveReason=function(queue,action,target)
  admission=admission+1;assert(queue==q and action==front and target==nil);return nil
 end,move=function(queue,action,target,after)
  moved=moved+1;assert(queue==q and action==front and target==approach and after==true)
  q.toolkitCancel=front;return true
 end}}
 T={ActionQueuePanel={new=function()return panel end},ActionQueuePolicy={evaluateMove=function(queue,action,target,after)
  assert(queue==q and action==front and target==volume and after==true);return{allowed=true}
 end}}
 diagnostic=function(decision)return{reason=false,source=source}end
 local ui=gesture()
 assert(admission==1 and moved==1 and ui.accepted and ui.pressCaptured and ui.dragging and ui.gestureCleared)
 assert(ui.movingAction==tostring(front)and ui.movingAnchor==tostring(front)and ui.target==tostring(approach)and ui.targetAction==tostring(volume)and ui.operation==30 and ui.movingToken==10)
 assert(ui.dropAfter==true and ui.commonActiveEdit==false and ui.toY>list:topOfItem(2)+20 and list.dragAction==nil)
end
text=read(arg[3]);last=assert(text:find('local function descriptor(',1,true))
local summary=assert(loadstring(text:sub(1,last-1)..'return planSummary'))()
local item,root,dest,action={},{},{},{}
local edit={version=1,complete=true,capacity='external',resources={{domain='item',key=17,facts={item=item,location=root},requires={{field='location',equal=root}},effects={{field='location',set=dest}}}}}
local plan={kind='preempt',nodes={{kind='pending',action=action,edit=edit}}}
local result=summary(plan,action,item,root,dest,17,'Base.Book')
local effect=result.nodes[1].returnEffect
assert(effect.action==tostring(action)and effect.item==tostring(item)and effect.source==tostring(root)and effect.destination==tostring(dest)and effect.synthetic==false)
local resource=edit.resources[1]
for _,change in ipairs({
 function()resource.key=18 end,function()resource.facts.item={}end,function()resource.facts.location=dest end,
 function()resource.requires[1].equal=dest end,function()resource.effects[1].set=root end,
 function()edit.capacity='unchanged'end,function()plan.nodes[1].action={}end,function()plan.nodes[1].kind='return'end,
 function()edit.resources[2]=resource end,function()resource.effects[2]=resource.effects[1]end})do
 resource.key=17;resource.facts.item=item;resource.facts.location=root;resource.requires[1].equal=root;resource.effects[1].set=dest
 edit.capacity='external';plan.nodes[1].action=action;plan.nodes[1].kind='pending';edit.resources[2]=nil;resource.effects[2]=nil
 change();assert(not pcall(summary,plan,action,item,root,dest,17,'Base.Book'),'retained return resource mutation was accepted')
end
os.exit(0)
"""
        subprocess.run([lua,'-e',source,'--','unused',str(ROOT/'tests/native_queue/book-controls/client/ZZBookControls.lua'),
            str(ROOT/'PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueuePanel.lua'),str(ROOT/'tests/native_queue/book-controls/shared/QueueBookEditObservation.lua')],check=True)

    def test_device_action_refs_accept_expanded_dumps_only_for_the_same_class_and_address(self):
        def replace(value, mapping):
            if isinstance(value, dict): return {key: replace(field, mapping) for key, field in value.items()}
            if isinstance(value, list): return [replace(field, mapping) for field in value]
            return mapping.get(value, value) if isinstance(value, str) else value
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                for case in adapter.DEVICE_ONLY_CASES:
                    row=self.precise_evidence(case,kind,mode)[0]
                    receipt=self.active_edit_receipt(row)
                    compact={r['actionRef']: r['type']+' 0x'+format(r['sequence']+256,'x') for r in row['records']}
                    expanded={key: value+'{ mode=SetVolume, maxTime=50, changed=true }' for key,value in compact.items()}
                    row=replace(row,expanded);receipt=replace(receipt,compact)
                    selection=self.selection(kind,mode)
                    self.assertEqual(a.active_edit_errors(receipt,row,case,selection),[],(kind,mode,case))
                    intent=receipt['intent']
                    action_class,address=intent['action'].split(' ',1)
                    wrong_refs=[action_class+' 0xdeadbeef','ForeignAction '+address,
                                intent['action']+'{unterminated',intent['action']+' trailing',True,1,None,{}]
                    for field in ('action','target'):
                        for wrong in wrong_refs:
                            changed=copy.deepcopy(receipt);changed['intent'][field]=wrong
                            self.assertTrue(a.active_edit_errors(changed,row,case,selection),(kind,mode,case,field,wrong))
                    for change in (lambda r:r['intent'].update(extra=True),lambda r:r['intent'].update(after=int(r['intent']['after'])),
                                   lambda r:r['intent'].update(kind=True)):
                        changed=copy.deepcopy(receipt);change(changed)
                        self.assertTrue(a.active_edit_errors(changed,row,case,selection))
                    if mode=='toolkit':
                        for index in range(len(receipt['plan']['nodes'])):
                            for change in (lambda r,i=index:r['plan']['nodes'][i].update(action='ForeignAction 0xdeadbeef'),
                                           lambda r,i=index:r['plan']['nodes'][i].update(extra=True),
                                           lambda r,i=index:r['plan']['nodes'][i].update(complete=int(r['plan']['nodes'][i]['complete']))):
                                changed=copy.deepcopy(receipt);change(changed)
                                self.assertTrue(a.active_edit_errors(changed,row,case,selection))
                        changed=copy.deepcopy(receipt);changed['plan']['extra']=True
                        self.assertTrue(a.active_edit_errors(changed,row,case,selection))
                        changed=copy.deepcopy(receipt);changed['plan']['nodes'][1:3]=reversed(changed['plan']['nodes'][1:3])
                        self.assertTrue(a.active_edit_errors(changed,row,case,selection))
                        if not case.startswith('root.'):
                            for field,wrong in [('action','ISInventoryTransferAction 0xdeadbeef'),('synthetic',0),('extra',True)]:
                                changed=copy.deepcopy(receipt)
                                next(node for node in changed['plan']['nodes'] if 'returnEffect' in node)['returnEffect'][field]=wrong
                                self.assertTrue(a.active_edit_errors(changed,row,case,selection))
                            changed=copy.deepcopy(receipt);changed['prototype']['action']='ForeignAction 0x'+format(7+256,'x')
                            self.assertTrue(a.active_edit_errors(changed,row,case,selection))

    def test_device_only_native_phase_requires_owned_record_and_every_other_effect_complete(self):
        for case in adapter.DEVICE_ONLY_CASES:
            row=self.precise_evidence(case)[0];selection=self.selection()
            receipt=self.active_edit_receipt(row)
            historical=copy.deepcopy(row)
            actual_approach=next(r for r in historical['records'] if r.get('role')=='preparation')
            for token in (10,30):
                completed=copy.deepcopy(actual_approach);completed.update(sequence=900+token,actionRef='ISQueueActionsAction 0x'+format(900+token,'x'),token=token,started=True,performedAt=8)
                historical['records'].insert(0,completed)
            self.assertEqual(a.active_edit_errors(receipt,historical,case,selection),[], 'completed historical preparation cannot become the pending native TV phase')
            for mutate in (lambda r:r['diagnostics']['contractGaps'].append(dict(index=999,actionType='ISQueueActionsAction',reason='effects_unproven')),
                           lambda r:r['observer']['projection']['deferred'][0].update(index=999),
                           lambda r:r['diagnostics']['contractGaps'].append(dict(index=4,actionType='ISRadioAction',reason='effects_unproven')),
                           lambda r:r['diagnostics'].update(projectionBlockerType='ISRadioAction'),
                           lambda r:r['diagnostics'].update(nodesTruncated=True),
                           lambda r:r['plan']['nodes'][2].update(complete=False),
                           lambda r:r['plan']['nodes'][1].update(capacity='unchanged'),
                           lambda r:r['existingDecision'].update(commonActiveEdit=True),
                           lambda r:r['performance'].update(comparable=True)):
                changed=copy.deepcopy(receipt);mutate(changed)
                self.assertTrue(a.active_edit_errors(changed,row,case,selection),(case,changed))
            for mutate in (lambda r:next(x for x in r['records'] if x['role']=='preparation')['approach'].update(owned=False),
                           lambda r:next(x for x in r['records'] if x['role']=='preparation').update(token=999),
                           lambda r:next(x for x in r['boundary']['queue'] if x['role']=='preparation').update(type='ISRadioAction'),
                           lambda r:next(x for x in r['boundary']['queue'] if x['role']=='preparation')['approach'].update(nativeResolver=False),
                           lambda r:r['boundary']['queue'].append(dict(role='preparation',type='ForeignAction',actionRef='foreign',token=999)),
                           lambda r:r['boundary']['ui'].update(movingAnchor='synthetic-anchor'),
                           lambda r:r['boundary']['ui'].update(targetAction='foreign-target')):
                changed=copy.deepcopy(row);mutate(changed)
                if a.active_edit_errors(receipt,changed,case,selection): continue
                evidence=list(self.precise_evidence(case));evidence[0]=changed
                self.assertTrue(self.check(evidence),case)

    def test_device_only_native_phase_descriptor_identity_shape_and_order_are_causal(self):
        for case in adapter.DEVICE_ONLY_CASES:
            row=self.precise_evidence(case)[0];selection=self.selection()
            receipt=self.active_edit_receipt(row)
            self.assertEqual(a.active_edit_errors(receipt,row,case,selection),[])
            for path in ('projection','plan','diagnostics'):
                def phase(value):
                    if path=='projection': return value['observer']['projection']['deferred'][0]['descriptor']
                    return value[path]['nodes'][1]['deferred']
                for field,wrong in [('version',True),('version',2),('kind','native-noop'),('actor','IsoPlayer@foreign'),
                        ('actor',False),('targetSquare','IsoGridSquare@foreign'),('targetSquare',42),
                        ('invalidates','position'),('routing','direct'),('expansion','known'),('outcome','success'),
                        ('complete',True),('resources',[]),('domain','position'),('futureFacts',{}),('position',{})]:
                    changed=copy.deepcopy(receipt);phase(changed)[field]=wrong
                    self.assertTrue(a.active_edit_errors(changed,row,case,selection),(case,path,field,wrong))
                for field in receipt['plan']['nodes'][1]['deferred']:
                    changed=copy.deepcopy(receipt);phase(changed).pop(field)
                    self.assertTrue(a.active_edit_errors(changed,row,case,selection),(case,path,field))
            for field in ('actor','targetSquare'):
                changed=copy.deepcopy(receipt)
                for descriptor in (changed['observer']['projection']['deferred'][0]['descriptor'],
                        changed['plan']['nodes'][1]['deferred'],changed['diagnostics']['nodes'][1]['deferred']):
                    descriptor[field]='foreign@identity'
                self.assertTrue(a.active_edit_errors(changed,row,case,selection),(case,field,'all summaries'))
            for mutate in (lambda r:r['observer']['projection'].update(evaluatedPrefix=True),
                           lambda r:r['observer']['projection'].update(evaluatedPrefix=2),
                           lambda r:r['observer']['projection'].update(blocker='ForeignAction 0xdead'),
                           lambda r:r['observer']['projection']['deferred'].append(copy.deepcopy(r['observer']['projection']['deferred'][0])),
                           lambda r:r['observer']['projection']['deferred'][0].update(index=True),
                           lambda r:r['observer']['projection']['deferred'][0].update(action=r['current']),
                           lambda r:r['observer']['projection']['deferred'][0].update(complete=True),
                           lambda r:r['observer']['projection'].update(futureFacts={}),
                           lambda r:r['plan']['nodes'][1].pop('deferred'),
                           lambda r:r['plan']['nodes'][2].update(deferred=copy.deepcopy(r['plan']['nodes'][1]['deferred'])),
                           lambda r:r['plan']['nodes'].__setitem__(slice(1,3),list(reversed(r['plan']['nodes'][1:3])))):
                changed=copy.deepcopy(receipt);mutate(changed)
                self.assertTrue(a.active_edit_errors(changed,row,case,selection),case)

    def test_device_only_requires_exact_native_phase_and_real_legacy_authority(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                selection, client, server = self.log_bank(kind=kind, mode=mode, precise=True, active=True, cases=adapter.DEVICE_ONLY_CASES)
                with tempfile.TemporaryDirectory() as directory:
                    root=Path(directory);(root/'client1-launch.log').write_text(client);(root/'server-launch.log').write_text(server)
                    result=a.verify(root,selection,{})
                    self.assertEqual(result['issues'], [], (kind,mode,result['issues']))
                for case in adapter.DEVICE_ONLY_CASES:
                    row=self.precise_evidence(case,kind,mode)[0];receipt=self.active_edit_receipt(row)
                    self.assertEqual(a.active_edit_errors(receipt,row,case,selection),[])
                    mutations=[lambda r:r['intent'].update(kind='cancel'),lambda r:r['intent'].update(after=not r['intent']['after']),
                        lambda r:r['intent'].update(action='synthetic-equip'),lambda r:r.update(qualifiedReturn=True),
                        lambda r:r.update(readOnly=False),lambda r:r['existingDecision'].update(commonActiveEdit=True),
                        lambda r:r['performance'].update(positiveTimingClaim=True),lambda r:r['performance'].update(completeEditMeasured=True)]
                    if mode=='toolkit':
                        mutations += [lambda r:r['observer']['projection'].update(status='allowed',reason=False),
                            lambda r:r['observer']['projection'].update(allowed=True),lambda r:r['observer'].update(returns=1),
                            lambda r:r['plan']['nodes'][1].update(complete=True),lambda r:r['plan']['nodes'][1].update(action='native-noop-equip'),
                            lambda r:r['plan']['nodes'][0].update(complete=1),lambda r:r['intent'].update(after=int(r['intent']['after']))]
                    else: mutations += [lambda r:r.update(plan={'kind':'preempt','nodes':[]}),lambda r:r['observer'].update(projection={'status':'allowed'})]
                    if mode=='toolkit' and not case.startswith('root.'):
                        for field, wrong in (('id',999),('fullType','Base.Pen'),('item','different-item'),('source','different-root'),
                                ('destination','different-destination'),('action','synthetic-return'),('synthetic',True),('effects',2),('complete',False)):
                            changed=copy.deepcopy(receipt)
                            next(n for n in changed['plan']['nodes'] if 'returnEffect' in n)['returnEffect'][field]=wrong
                            self.assertTrue(a.active_edit_errors(changed,row,case,selection),(case,field))
                    for mutate in mutations:
                        changed=copy.deepcopy(receipt);mutate(changed)
                        self.assertTrue(a.active_edit_errors(changed,row,case,selection),(case,mode,changed))
        mixed=self.precise_evidence('world.header-cancel')[0];value=self.active_edit_receipt(mixed)
        value['observer']['projection'].update(status='allowed',reason=False)
        value['performance'].update(observerProjectionStatus='allowed',observerProjectionReason=False)
        self.assertTrue(a.active_edit_errors(value,mixed,mixed['id'],self.selection()))
        row=self.evidence('world.move-volume-device-only')[0]
        for mutate in (lambda r:r['records'].append(dict(role='equip',type='ISEquipWeaponAction')),
                       lambda r:r['boundary']['ui'].update(commonActiveEdit=True),lambda r:r.update(equipSnapshot={} ),
                       lambda r:r['client']['hands'].update(primary=r['ids']['pen']['id'])):
            changed=copy.deepcopy(row);mutate(changed);evidence=list(self.evidence(row['id']));evidence[0]=changed
            self.assertTrue(self.check(evidence))

    def test_active_edit_flag_is_strict_and_restricted_to_precise_real_header_cases(self):
        selection = self.selection(); selection['cases'] = list(adapter.ACTIVE_EDIT_CASES)
        for bad in (1, 'true', None, [], {}):
            selection['options']['active_edit_observation'] = bad
            with self.assertRaises(ValueError): adapter.validate(selection)
        selection['options']['active_edit_observation'] = True
        with self.assertRaises(ValueError): adapter.validate(selection)
        selection['options']['precise_timing'] = True
        adapter.validate(selection)
        for case in ('root.reader-child-cancel', 'worn-bag.header-cancel-capacity-lost', 'world.header-cancel-favorite'):
            selection['cases'] = [case]
            with self.assertRaises(ValueError): adapter.validate(selection)
        selection['options']['active_edit_observation'] = False
        adapter.validate(selection)  # Legacy cases retain their previous options/evidence contract.

    def test_active_edit_exact_return_and_controls_keep_overall_unknown_visible(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                for case in adapter.ACTIVE_EDIT_CASES:
                    row = self.precise_evidence(case, kind, mode)[0]
                    selection = self.selection(kind, mode)
                    receipt = self.active_edit_receipt(row)
                    self.assertEqual(a.active_edit_errors(receipt, row, case, selection), [], (kind, mode, case))
                    diagnostic_only = copy.deepcopy(receipt)
                    diagnostic_only.update(currentLuaStartedPresent=True, currentLuaStarted=True)
                    self.assertEqual(a.active_edit_errors(diagnostic_only, row, case, selection), [])
                    if mode == 'toolkit':
                        self.assertEqual(receipt['observer']['projection']['status'], 'unhandled')
                        self.assertEqual(receipt['performance']['observerProjectionReason'], 'edit_unknown')
                    if mode == 'toolkit' and not case.startswith('root.'):
                        self.assertTrue(receipt['performance']['comparable'])
                        denied = self.active_edit_receipt(row, legacy_allowed=False)
                        self.assertFalse(denied['performance']['comparable'])
                        self.assertEqual(a.active_edit_errors(denied, row, case, selection), [])

    def test_active_edit_metadata_hints_stay_native_and_require_fresh_qualified_effect(self):
        for kind in ('sp', 'mp'):
            for case in ('worn-bag.header-cancel', 'world.header-cancel'):
                row = self.precise_evidence(case, kind=kind)[0]; selection = self.selection(kind=kind)
                receipt = self.active_edit_receipt(row)
                before = copy.deepcopy(receipt['ledgerBefore'])
                self.assertIs(before['legacyHints'], True)
                self.assertEqual(receipt['ledgerAfter'], before)
                self.assertEqual(a.active_edit_errors(receipt, row, case, selection), [])
                self.assertEqual(receipt['ledgerBefore'], before)
                self.assertEqual(receipt['ledgerAfter'], before)
                for wrong in (False, None, 1, 'true'):
                    changed = copy.deepcopy(receipt)
                    changed['ledgerBefore']['legacyHints'] = wrong; changed['ledgerAfter']['legacyHints'] = wrong
                    self.assertTrue(a.active_edit_errors(changed, row, case, selection), wrong)
                for field in ('nativeFacts', 'effect'):
                    changed = copy.deepcopy(receipt); changed[field] = False
                    self.assertTrue(a.active_edit_errors(changed, row, case, selection), field)
                changed = copy.deepcopy(receipt); changed['ledgerAfter']['legacyHints'] = False
                self.assertTrue(a.active_edit_errors(changed, row, case, selection))
            row = self.precise_evidence('root.header-cancel', kind=kind)[0]; selection = self.selection(kind=kind)
            receipt = self.active_edit_receipt(row)
            self.assertIs(receipt['ledgerBefore']['legacyHints'], False)
            receipt['ledgerBefore']['legacyHints'] = True; receipt['ledgerAfter']['legacyHints'] = True
            self.assertTrue(a.active_edit_errors(receipt, row, row['id'], selection))

    def test_active_edit_legacy_nil_error_encoding_only_decodes_success(self):
        for mode in ('native', 'toolkit'):
            row = self.precise_evidence('worn-bag.header-cancel', mode=mode)[0]
            selection = self.selection(mode=mode)
            receipt = self.active_edit_receipt(row); receipt['failure'] = 'nil'
            self.assertEqual(a.active_edit_errors(receipt, row, row['id'], selection), [])
            for failed in (None, 'None', '', 'false', 'nil\n', 'real failure', True):
                changed = copy.deepcopy(receipt); changed['failure'] = failed
                self.assertTrue(a.active_edit_errors(changed, row, row['id'], selection), failed)
            for passed in (False, 'true', 1):
                changed = copy.deepcopy(receipt); changed['passed'] = passed
                self.assertTrue(a.active_edit_errors(changed, row, row['id'], selection), passed)
        selection, client, server = self.log_bank(mode='native', precise=True, active=True, cases=adapter.ACTIVE_EDIT_CASES)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root/'server-launch.log').write_text(server)
            (root/'client1-launch.log').write_text(client.replace('"failure": false', '"failure": "nil"'))
            self.assertEqual(a.verify(root, selection, {})['issues'], [])

    def test_active_edit_reviewed_cart_wrapper_pair_still_requires_qualified_return(self):
        for kind in ('sp', 'mp'):
            row = self.precise_evidence('worn-bag.header-cancel', kind=kind)[0]; selection = self.selection(kind=kind)
            receipt = self.active_edit_receipt(row)
            receipt['sources'].update(transferConstructor='TransferRestrictions.lua', transferPerform='VisualUpdateQueue.lua')
            receipt['prototype'].update(constructorSource='TransferRestrictions.lua', performSource='VisualUpdateQueue.lua')
            self.assertEqual(a.active_edit_errors(receipt, row, row['id'], selection), [])
            for constructor, perform in (('TransferRestrictions.lua', 'ISInventoryTransferAction.lua'),
                                         ('ISInventoryTransferAction.lua', 'VisualUpdateQueue.lua'),
                                         ('Foreign.lua', 'VisualUpdateQueue.lua'),
                                         ('TransferRestrictions.lua', 'Foreign.lua')):
                changed = copy.deepcopy(receipt)
                changed['sources'].update(transferConstructor=constructor, transferPerform=perform)
                changed['prototype'].update(constructorSource=constructor, performSource=perform)
                self.assertTrue(a.active_edit_errors(changed, row, row['id'], selection), (constructor, perform))
            for mutate in (lambda r: r['sources'].update(carts='fixture.lua'),
                           lambda r: r.update(nativeFacts=False), lambda r: r.update(effect=False),
                           lambda r: (r['ledgerBefore'].update(earnedPreparations=0), r['ledgerAfter'].update(earnedPreparations=0)),
                           lambda r: r['prototype'].update(performSource='ISInventoryTransferAction.lua')):
                changed = copy.deepcopy(receipt); mutate(changed)
                self.assertTrue(a.active_edit_errors(changed, row, row['id'], selection))

    def test_active_edit_causal_mutations_reject_rebinding_rights_missing_facts_and_timing_claims(self):
        row = self.precise_evidence('worn-bag.header-cancel')[0]; selection = self.selection()
        mutations = {
            'schema': lambda r: r.update(schema=True),
            'case': lambda r: r.update(case='world.header-cancel'),
            'kind': lambda r: r.update(kind='sp'),
            'mode': lambda r: r.update(mode='native'),
            'native current': lambda r: r.update(currentNative='java:foreign'),
            'Lua started inconsistent': lambda r: r.update(currentLuaStartedPresent=False, currentLuaStarted=True),
            'Lua started nonboolean': lambda r: r.update(currentLuaStartedPresent=1),
            'Lua started diagnostic missing': lambda r: r.pop('currentLuaStarted'),
            'not native started': lambda r: r.update(nativeStarted=False),
            'native complete': lambda r: r.update(nativeFinished=True),
            'native force complete': lambda r: r.update(nativeForceComplete=True),
            'mutation': lambda r: r.update(readOnly=False),
            'UI mutation': lambda r: r.update(uiUnchanged=False),
            'rights': lambda r: r.update(mutationAuthorized=True),
            'permission measurement': lambda r: r.update(permissionsMeasured=True),
            'failed assertion': lambda r: r.update(passed=False, failure='detached prototype'),
            'observer authority': lambda r: r['observer'].update(allowedAbsent=False),
            'missing return': lambda r: r['observer'].update(returns=0),
            'lost overall unknown reason': lambda r: r['observer']['projection'].update(reason=False),
            'lost overall projection': lambda r: (r['observer'].update(projection=False), r['performance'].update(observerProjectionStatus=False, observerProjectionReason=False)),
            'projection capacity lost': lambda r: r['observer']['projection'].update(externalCapacity=False),
            'projection authority': lambda r: r['observer']['projection'].update(allowedAbsent=False),
            'hidden projection authority': lambda r: r['observer']['projection'].update(allowed=True),
            'fake wrapper': lambda r: r['sources'].update(carts='fixture.lua'),
            'no probe': lambda r: r.update(nativeFacts=False),
            'old native schema': lambda r: r['nativeFacts'].update(schema=1),
            'native different item': lambda r: r['nativeFacts'].update(item='Literature@detached'),
            'native unknown primary': lambda r: r['nativeFacts'].update(primaryKnown=False),
            'native wrong owner': lambda r: r['nativeFacts'].update(destinationOwnerFullType='Base.OtherBag'),
            'detached prototype': lambda r: r['prototype'].update(sameItemReference=False),
            'detached queue member': lambda r: r['prototype'].update(member='Literature@detached'),
            'prototype wrong action': lambda r: r['prototype'].update(action='lua:foreign'),
            'prototype native allocated': lambda r: r['prototype'].update(pending=False),
            'effect hidden native action': lambda r: r['effect'].update(actionAbsent=False),
            'effect appended executor': lambda r: r['effect'].update(action='lua:executor'),
            'effect capacity': lambda r: r['effect'].update(capacity='admitted'),
            'effect wrong id': lambda r: r['effect'].update(id=999),
            'effect wrong type': lambda r: r['effect'].update(fullType='Base.OtherBook'),
            'effect wrong destination': lambda r: r['effect'].update(destination='ItemContainer@other'),
            'effect two effects': lambda r: r['effect'].update(effects=2),
            'effect incomplete': lambda r: r['effect'].update(complete=False),
            'ledger mutation': lambda r: r['ledgerAfter'].update(earnedPreparations=0),
            'no private borrowing': lambda r: (r['ledgerBefore'].update(borrowings=[]), r['ledgerAfter'].update(borrowings=[])),
            'no real baseline': lambda r: r['existingDecision'].update(entrypoint='fixture.helper'),
            'baseline different intent': lambda r: r['existingDecision'].update(whole=False),
            'false comparability': lambda r: r['existingDecision'].update(allowed=False),
            'timing fake scope': lambda r: r['performance'].update(scope='source-only'),
            'timing warmup': lambda r: r['performance'].update(warmupPairs=0),
            'timing pairs': lambda r: r['performance'].update(pairs=2),
            'timing frame claim': lambda r: r['performance'].update(frameLoadMeasured=True),
            'timing complete edit claim': lambda r: r['performance'].update(completeEditMeasured=True),
            'timing positive claim': lambda r: r['performance'].update(positiveTimingClaim=True),
            'timing acceptance': lambda r: r['performance'].update(assessment='accepted'),
            'timing hidden acceptance': lambda r: r['performance'].update(performanceAssessment='accepted'),
            'timing lost unknown': lambda r: r['performance'].update(observerProjectionStatus='allowed'),
            'timing negative': lambda r: r['performance'].update(observerFirstMs=-1),
            'timing infinity': lambda r: r['performance']['observer']['samplesMs'].__setitem__(0, float('inf')),
            'timing NaN': lambda r: r['performance']['baseline'].update(meanMs=float('nan')),
            'timing bool': lambda r: r['performance']['observer']['samplesMs'].__setitem__(0, True),
            'timing inconsistent mean': lambda r: r['performance']['baseline'].update(meanMs=8),
            'timing missing distribution': lambda r: r['performance'].pop('baseline'),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name):
                receipt = self.active_edit_receipt(row); mutate(receipt)
                self.assertTrue(a.active_edit_errors(receipt, row, row['id'], selection))
        for key, wrong in (('earnedPreparations', 0), ('legacyHints', False), ('providersPresent', True), ('generation', -1)):
            receipt = self.active_edit_receipt(row)
            receipt['ledgerBefore'][key] = wrong; receipt['ledgerAfter'][key] = wrong
            self.assertTrue(a.active_edit_errors(receipt, row, row['id'], selection), key)
        changed = copy.deepcopy(row)
        next(r for r in changed['records'] if r['role'] == 'pickup').pop('performedAt')
        self.assertTrue(a.active_edit_errors(self.active_edit_receipt(row), changed, row['id'], selection))
        for field in ('nativeRef', 'started'):
            changed = copy.deepcopy(row); changed['records'][0].pop(field)
            self.assertTrue(a.active_edit_errors(self.active_edit_receipt(row), changed, row['id'], selection))
        for case, mode in (('root.header-cancel', 'toolkit'), ('world.header-cancel', 'native')):
            control = self.precise_evidence(case, mode=mode)[0]; chosen = self.selection(mode=mode)
            for mutate in (lambda r: r.update(control='no-loan' if mode == 'native' else 'queue-disabled'),
                           lambda r: r.update(qualifiedReturn=True), lambda r: r.update(effect={'complete': True}),
                           lambda r: r['performance'].update(comparable=True)):
                receipt = self.active_edit_receipt(control); mutate(receipt)
                self.assertTrue(a.active_edit_errors(receipt, control, case, chosen))
            if mode == 'native':
                receipt = self.active_edit_receipt(control, legacy_allowed=True)
                self.assertTrue(a.active_edit_errors(receipt, control, case, chosen))

    def test_active_edit_detached_member_needs_native_resolution_and_keeps_admission_external(self):
        row = self.precise_evidence('worn-bag.header-cancel')[0]
        selection = self.selection(); selection['cases'] = [row['id']]
        value = self.active_edit_receipt(row)
        prototype, facts = value['prototype'], value['nativeFacts']
        prototype.update(member='Literature@detached', sameMemberReference=False)
        value['sources']['nativeAlias'] = True
        value['aliasFacts'] = dict(scope='independent-native-alias-probe', schema=2, item=facts['item'],
            source=facts['source'], destination=facts['destination'], aliasMember=prototype['member'], aliasResolution='native-root-id')
        self.assertEqual(a.active_edit_errors(value, row, row['id'], selection), [])
        for key, wrong in [('aliasFacts', False), ('aliasFacts', dict(value['aliasFacts'], aliasResolution='same-id')),
                           ('aliasFacts', dict(value['aliasFacts'], aliasMember=facts['item'])),
                           ('aliasFacts', dict(value['aliasFacts'], destination=facts['source'])),
                           ('sources', dict(value['sources'], nativeAlias=False)),
                           ('prototype', dict(prototype, sameItemReference=False)),
                           ('prototype', dict(prototype, member=facts['item']))]:
            changed=copy.deepcopy(value); changed[key]=wrong
            self.assertTrue(a.active_edit_errors(changed, row, row['id'], selection), key)
        for field in value['aliasFacts']:
            changed=copy.deepcopy(value); changed['aliasFacts'].pop(field)
            self.assertTrue(a.active_edit_errors(changed, row, row['id'], selection), field)
        changed=copy.deepcopy(value); changed['aliasFacts']['allowed']=True
        self.assertTrue(a.active_edit_errors(changed, row, row['id'], selection))
        sp_row=self.precise_evidence('worn-bag.header-cancel',kind='sp')[0]
        sp_value=self.active_edit_receipt(sp_row); sp_value.update(aliasFacts=value['aliasFacts'],prototype=prototype)
        sp_selection=self.selection(kind='sp');sp_selection['cases']=[sp_row['id']]
        self.assertTrue(a.active_edit_errors(sp_value,sp_row,sp_row['id'],sp_selection))
        direct=self.active_edit_receipt(row);direct['aliasFacts']=value['aliasFacts']
        self.assertTrue(a.active_edit_errors(direct,row,row['id'],selection))

    def test_active_edit_raw_setup_case_receipts_are_integrated_and_optional(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                selection, client, server = self.log_bank(kind=kind, mode=mode, precise=True, active=True, cases=adapter.ACTIVE_EDIT_CASES)
                with tempfile.TemporaryDirectory() as directory:
                    root = Path(directory); (root/'server-launch.log').write_text(server)
                    (root/'client1-launch.log').write_text(client)
                    result = a.verify(root, selection, {})
                    self.assertEqual(result['issues'], [], (kind, mode, result['issues']))
                    self.assertEqual(len(result['evidence']['activeEditObservation']), 3)
                    rawline = next(line for line in client.splitlines() if line.startswith(adapter.PREFIX+'ACTIVE_EDIT_OBSERVATION '))
                    for name, changed in (
                        ('missing raw', client.replace(rawline, '', 1)), ('duplicate raw', client+'\n'+rawline),
                        ('foreign raw', client+'\n'+rawline.replace('root.header-cancel', 'foreign.case')),
                        ('setup false', client.replace('"activeEditObserved": true', '"activeEditObserved": false')),
                        ('setup missing', client.replace(', "activeEditObserved": true', '')),
                        ('case mismatch', client.replace('"readOnly": true, "uiUnchanged": true', '"readOnly": false, "uiUnchanged": true', 1)),
                        ('malformed raw', client.replace(rawline, adapter.PREFIX+'ACTIVE_EDIT_OBSERVATION null', 1))):
                        (root/'client1-launch.log').write_text(changed)
                        self.assertTrue(a.verify(root, selection, {})['issues'], (kind, mode, name))
                    selection['options']['active_edit_observation'] = False
                    (root/'client1-launch.log').write_text(client)
                    self.assertTrue(a.verify(root, selection, {})['issues'])
                    old_selection, old_client, old_server = self.log_bank(kind=kind, mode=mode, precise=True, cases=adapter.ACTIVE_EDIT_CASES)
                    (root/'client1-launch.log').write_text(old_client); (root/'server-launch.log').write_text(old_server)
                    self.assertEqual(a.verify(root, old_selection, {})['issues'], [])

    def log_bank(self, kind='mp', mode='toolkit', requests=False, precise=False, current=False, sample_ms=None, cases=None, active=False):
        selection = self.selection(kind, mode); client, server = [], []
        cases = list(adapter.CASES) if cases is None else list(cases); selection['cases'] = cases
        if requests: selection['options']['require_native_requests']=True
        if precise: selection['options']['precise_timing']=True
        if active: selection['options']['active_edit_observation']=True
        def raw(marker, value): return adapter.PREFIX + marker + ' ' + json.dumps(value)
        def event(value): return '[QUEUE_CHECK] ' + json.dumps(value)
        client.append(event(dict(event='setup', suite='book-controls', cases=cases, queueEnabled=mode == 'toolkit', nativeDurations=True, sourceBound=True, authorityEquipment=True,nativeRequestsObserved=requests,timingClock=copy.deepcopy(a.CLOCK_INFO)if precise else False)))
        if active:
            setup=json.loads(client[0].split(' ', 1)[1]);setup['activeEditObserved']=True;client[0]=event(setup)
        for case in cases:
            evidence=self.precise_evidence(case,kind,mode,requests=requests)if precise else(self.request_evidence if requests else self.evidence)(case,kind,mode)
            if current:evidence=self.current_measurements(evidence)
            if sample_ms is not None:
                for bank in (evidence[0]['performance'],evidence[0]['performance']['probe32']):
                    for metric in bank['metrics']:metric.update(rawMs=[sample_ms]*20,p95Ms=sample_ms,p99Ms=sample_ms)
            row, spec, baseline, final, admissions, boundaries, drains, acks = evidence
            authority = server if kind == 'mp' else client
            authority.extend([raw('PREPARED', spec), raw('BASELINE', baseline), raw('VERIFIED', final)])
            if row.get('capacity') is not False: authority.append(raw('CAPACITY_LOST', row['capacity']))
            if row.get('blockedReturn') is not False:
                client.append(raw('BLOCKED_RETURN',dict(case=case,entry=row['blockedReturn'])))
                client.append(raw('FAILURE_UI',row['failureUI']))
            for marker, values in [('ADMISSION', admissions), ('BOUNDARY', boundaries), ('DRAIN', drains), ('ACK', acks)]:
                client.extend(raw(marker, value) for value in values)
            for record in row['records']:
                if 'stopReturned' in record:client.append(raw('STOP_RETURNED',record['stopReturned']))
                for marker,field in [('TRANSFER_STOP_ENTRY','nativeStopEntry'),('TRANSFER_STOP_RETURNED','nativeStopReturned')]:
                    if field in record: client.append(raw(marker,record[field]))
                for sample in record.get('requestStates',[]):client.append(raw('NATIVE_REQUEST',sample))
            client.append(raw('PERFORMANCE',row['performance']))
            if active:
                row['activeEditObservation']=self.active_edit_receipt(row)
                client.append(raw('ACTIVE_EDIT_OBSERVATION',row['activeEditObservation']))
            client.append(event(row))
        client.append(event(dict(event='complete', suite='book-controls', cases=cases, performed=len(cases), skipped=0, failed=0)))
        client.append(raw('COMPLETE', dict(cases=cases, failed=0)))
        return selection, '\n'.join(client), '\n'.join(server)

    def test_whole_bank_raw_evidence_and_completion(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for kind, mode in [('mp', 'toolkit'), ('sp', 'native')]:
                selection, client, server = self.log_bank(kind, mode)
                (root / 'client1-launch.log').write_text(client); (root / 'server-launch.log').write_text(server)
                self.assertEqual(a.verify(root, selection, {})['issues'], [])
                self.assertTrue(adapter.complete(selection, 'client1', client))
                self.assertFalse(adapter.complete(selection, 'server', client))
                for bad in (client.replace('"performed": ' + str(len(adapter.CASES)), '"performed": 0'), client + '\n' + adapter.PREFIX + 'DENIED {}', client + '\n' + adapter.PREFIX + 'RESET {}', client.replace('"authorityEquipment": true', '"authorityEquipment": false')):
                    (root / 'client1-launch.log').write_text(bad)
                    self.assertTrue(a.verify(root, selection, {})['issues'])
            # Diagnostic completion must stop the common runner after the whole
            # failed bank, while qualification still fails all denied features.
            denied = adapter.PREFIX + 'COMPLETE ' + json.dumps(dict(cases=list(adapter.CASES), failed=len(adapter.CASES)))
            self.assertTrue(adapter.complete(self.selection(), 'client1', denied))
            self.assertFalse(adapter.complete(self.selection(), 'client1', denied + '\n' + denied))

    def test_staging_and_source_sealing(self):
        paths = adapter.sources(ROOT, self.selection())
        self.assertTrue(all(path.is_file() for path in paths))
        self.assertIn(Path(adapter.__file__).with_name('tv_controls.py'), paths)
        self.assertNotIn(ROOT / 'tests/test_queue_book_controls.py', paths)
        verifier_paths = adapter.verifier_sources(ROOT, self.selection())
        self.assertEqual(verifier_paths, [Path(a.__file__), ROOT / 'tests/test_queue_book_controls.py'])
        self.assertTrue(all(path.is_file() for path in verifier_paths))
        self.assertFalse(set(paths) & set(verifier_paths))
        probe_source=ROOT / 'tests/native_queue/book-controls/java/Main.java'
        self.assertIn(probe_source,paths)
        self.assertIn('media/lua/shared/TimedActions/ISBaseTimedAction.lua',adapter.GAME_INPUTS)
        self.assertIn('[QUEUE_TEST] FAIL book-controls-stop-observer',probe_source.read_text())
        with tempfile.TemporaryDirectory() as directory:
            runtime = dict(roles={role: dict(cache=str(Path(directory) / role)) for role in ('server', 'client1')})
            probe = Path(directory) / 'probe.jar'
            with zipfile.ZipFile(probe,'w') as jar:
                jar.writestr('net/alexredby/bookcontrolsprobe/Main.class',b'compiled observation fixture')
                jar.writestr('net/alexredby/bookcontrolsprobe/Main$Stopped.class',b'compiled stop advice')
            with mock.patch.object(adapter, '_stop_probe', return_value=probe):
                adapter.stage(ROOT, directory, None, None, self.selection(), {}, runtime)
            self.assertEqual(runtime['fixture']['mods'], ['BookControlsStopProbe'])
            for role in runtime['roles'].values():
                cache=Path(role['cache']);layer=cache/'mods/BookControlsStopProbe/42'
                metadata=native._metadata(layer/'mod.info')
                self.assertEqual({k:metadata[k] for k in ('id','require','javaPkgName','javaJarFile')},
                    dict(id='BookControlsStopProbe',require='\\ZombieBuddy',javaPkgName='net.alexredby.bookcontrolsprobe',javaJarFile='media/java/BookControlsStopProbe.jar'))
                staged=layer/'media/java/BookControlsStopProbe.jar'
                self.assertEqual(staged.read_bytes(),probe.read_bytes())
                self.assertEqual(native._approvals(cache,runtime['fixture']['mods']),
                    [dict(id='BookControlsStopProbe',jar_hash=native.sha256(probe),decision=True,time='2026-01-01T00:00:00Z')])
                with zipfile.ZipFile(staged) as jar:
                    self.assertIn('net/alexredby/bookcontrolsprobe/Main$Stopped.class',jar.namelist())
                lua = cache / 'mods/ActionQueueTest/42/media/lua'
                for path in (ROOT / 'tests/native_queue/book-controls').rglob('*.lua'):
                    self.assertEqual(path.read_bytes(), (lua / path.relative_to(ROOT / 'tests/native_queue/book-controls')).read_bytes())
            self.assertEqual(runtime['fixture']['failure_markers'], ['[QUEUE_TEST] FAIL book-controls'])

    def test_adapter_dispatches_post_run_verification(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            selected, text, authority = self.log_bank()
            (root / 'client1-launch.log').write_text(text)
            (root / 'server-launch.log').write_text(authority)
            with mock.patch.object(a, 'verify', side_effect=AssertionError('cached verifier')) as cached:
                self.assertEqual([], adapter.verify(root, selected, {})['issues'])
            cached.assert_not_called()
        self.assertFalse(hasattr(adapter, 'check_case'))
        self.assertFalse(hasattr(adapter, 'active_edit_errors'))

    def test_failed_return_footer_revision_cache_idle_layout_and_stale_press(self):
        lua = shutil.which('luajit')
        if not lua: self.skipTest('LuaJIT not installed')
        source = r"""
local W={};W.__index=W
function W:derive()local t={};t.__index=t;setmetatable(t,{__index=self});return t end
function W:new(x,y,w,h)local t=setmetatable({x=x,y=y,width=w,height=h,items={},selected=-1,visible=true},self);return t end
function W:initialise()if self.createChildren then self:createChildren()end end
function W:instantiate()end
function W:createChildren()self.closeButton=W:new();self.closeButtonTexture='close'end
function W:addChild(child)child.parent=self end
function W:setVisible(v)self.visible=v end
function W:getIsVisible()return self.visible end
function W:setEnable(v)self.enabled=v end
function W:setTitle(v)self.title=v end
function W:setTooltip(v)self.tooltip=v end
function W:setY(v)self.y=v end
function W:setX(v)self.x=v end
function W:getX()return self.x end
function W:getY()return self.y end
function W:setWidth(v)self.width=v end
function W:setHeight(v)self.height=v end
function W:titleBarHeight()return 16 end
function W:update()end
function W:onResize()end
function W:getYScroll()return 0 end
function W:setYScroll()end
function W:setScrollHeight()end
function W:clear()self.items={}end
function W:onMouseDown()return true end
local windows={}
function W:addToUIManager()windows[#windows+1]=self end
function W:removeFromUIManager()self.removed=true end
ISCollapsableWindow=W;ISScrollingListBox=W;ISButton=W:derive()
function ISButton:new(x,y,w,h,title,target,callback)local t=W.new(self,x,y,w,h);t.title,t.target,t.onclick=title,target,callback;return t end
UIFont={Small=1};getTextManager=function()return{getFontHeight=function()return 14 end}end
getTexture=function(v)return v end;getText=function(key,...)local values={...};for i,v in ipairs(values)do values[i]=tostring(v)end;return key..table.concat(values,'|')end
local player={isDead=function()return false end,getInventory=function()error('UI must not scan inventory')end}
local queue={character=player,queue={}}
ISTimedActionQueue={queues={[player]=queue},getTimedActionQueue=function()return queue end}
getNumActivePlayers=function()return 1 end;getSpecificPlayer=function()return player end
getPlayerScreenLeft=function()return 0 end;getPlayerScreenTop=function()return 0 end;getPlayerScreenHeight=function()return 900 end;getPlayerScreenWidth=function()return 1600 end
getTimestampMs=function()return 1000 end;Events={OnTickEvenPaused={Add=function()end}}
local revision,entries,copies,kept=1,{{id=11,itemId=101,title='Book',state='blocked',reason='admission'}},0,nil
local execution={blockedReturnInfo=function()return{count=#entries,revision=revision}end,blockedReturns=function()copies=copies+1;return entries end,
 keepReturn=function(_,id)kept=id;for index,entry in ipairs(entries)do if entry.id==id then table.remove(entries,index);revision=revision+1;return true end end;return false,'unavailable'end}
PZSurvivorToolkit={Settings={actionQueue=function()return true end},ActionQueueExecution=execution}
require=function(name) if name=='QueuePreflight' then return {onGameStart=function(events,fn)events.OnGameStart.Add(fn)end,onTick=function(events,fn)events.OnTick.Add(fn)end,removeTick=function(events,fn)events.OnTick.Remove(fn)end}end;if name=='PZSurvivorToolkit/ActionQueueProjection'then return{capture=function()return{stable=false}end}end end
assert(loadfile(arg[1]))()
local Panel=PZSurvivorToolkit.ActionQueuePanel;Panel.refresh();local view=windows[#windows];view:update()
assert(view.visible and #view.list.items==0 and view.keepReturnButton.visible and view.keepReturnButton.enabled,'idle failure footer absent')
assert(view.list.height==view.height-view.list.y-42,'one footer layout')
local firstCopies=copies;for i=1,10 do view:update()end;assert(copies==firstCopies,'unchanged revision allocated list copies')
view.keepReturnButton:onMouseDown(1,1)
entries={{id=12,itemId=102,title='Replacement',state='blocked',reason='server'}};revision=revision+1;view:update()
view:keepFailedReturn(view.keepReturnButton);assert(kept==11 and #entries==1,'stale press waived a replacement')
view.keepReturnButton:onMouseDown(1,1);view:keepFailedReturn(view.keepReturnButton);assert(kept==12 and #entries==0,'fresh exact keep did not clear debt')
Panel.refresh();assert(not view.visible,'idle empty window must hide after debt is dismissed')
entries={{id=13,title='One',state='blocked',reason='unmoved'},{id=14,title='Two',state='revoked',reason='server'}};revision=revision+1
Panel.refresh();view:update();assert(view.nextReturnButton.visible);view:nextFailedReturn()
assert(view.keepReturnButton.enabled and view.keepReturnButton.title:find('queue_return_forget',1,true),'revoked notice has no Forget control')
view.keepReturnButton:onMouseDown(1,1);entries[2]={id=15,title='New revoked notice',state='revoked',reason='server'};revision=revision+1;view:update()
view:keepFailedReturn(view.keepReturnButton);assert(kept==14 and #entries==2,'stale revoked press forgot a replacement')
view:nextFailedReturn();view:nextFailedReturn();view.keepReturnButton:onMouseDown(1,1);view:keepFailedReturn(view.keepReturnButton)
assert(kept==15 and #entries==1 and entries[1].id==13,'Forget did not remove only the captured historical notice')
PZSurvivorToolkit.ActionQueueRecovery={info=function()return{id=1,count=1,skipped=0}end,preview=function()return{id=1,available=true}end}
local other=Panel:new(0,0,420,300);other.queue=queue;other:initialise();other:update()
assert(other.list.height==other.height-other.list.y-72,'recovery and failure footer overlap')
assert(other.keepReturnButton.y==other.restoreButton.y-30,'footer rows overlap')
other:setVisible(false);other:clearSnapshots();assert(not other.returnEntries and not other.returnBackend and not other.keepReturnButton.visible,'hidden UI retained debt cache')
PZSurvivorToolkit.ActionQueueExecution=nil;other:setVisible(true);other:update();assert(not other.keepReturnButton.visible,'removed API retained stale controls')
local legacy=Panel:new(0,0,420,300);legacy.queue=queue;legacy:initialise();legacy:update();assert(not legacy.keepReturnButton,'legacy panel acquired execution controls')
os.exit(0)
"""
        subprocess.run([lua, '-e', OFFLINE_FIXTURE_EVENTS + source, '--', 'unused', str(ROOT / 'PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueuePanel.lua')], check=True)

    def test_unsupported_active_edit_is_collected_after_read_only_checks(self):
        lua = shutil.which('luajit')
        if not lua: self.skipTest('LuaJIT not installed')
        source = r"""
local item={getID=function()return 17 end,getFullType=function()return 'Base.Book' end}
local root,destination={},{}
local native={isStarted=function()return true end,finished=function()return false end,isForceComplete=function()return false end}
local operation={};local front={item=item,action=native,started=true,toolkitQueueOperation=operation}
local prototype={Type='ISInventoryTransferAction',item=item,allowMissingItems=true,toolkitQueueOperation=operation,
 queueList={{items={{}}}},srcContainer=root,destContainer=destination}
local queue={queue={front,prototype},current=front}
local ui={size=function()return 0 end};UIManager={getUI=function()return ui end}
local player={getInventory=function()return root end};local state={player=player,front=item,source=destination}
local observeCount,ledgerCount,snapshots=0,0,0
local queueOff,withEffect=false,false
local function observe()observeCount=observeCount+1;if queueOff then return{status='unhandled'}end
 local node={kind='return',action=nil,synthetic=true,item=item,id=17,fullType='Base.Book',source=root,destination=destination}
 if withEffect then node.edit={version=1,complete=true,capacity='external',resources={{domain='item',key=17,facts={item=item,location=root},requires={{field='location',equal=root}},effects={{field='location',set=destination}}}}}end
 return{status='observed',nodes={node}}end
local function evaluate()return{allowed=true}end
local function ledger()ledgerCount=ledgerCount+1;return{status='observed',steps={{phase='prepare',state='earned'}},borrowings={{id=17,fullType='Base.Book',state='active',ambiguous=false,returning=false,source=destination,destination=root}}}end
local toolkit={ActionQueuePolicy={observeActiveEdit=observe,evaluateCancel=evaluate},ActionQueueSettlement={editLedger=ledger}}
function getFilenameOfClosure(fn)if fn==observe then return 'ActionQueuePolicy.lua'elseif fn==ledger then return 'ActionQueueSettlement.lua'end end
ISInventoryTransferAction={}
function toolkitLeafTransferFacts()return{schema=2,item=item,source=root,destination=destination}end
local aliasCalls=0
function toolkitLeafTransferAliasFacts(actor,canonical,source,dest,id,fullType,member)
 aliasCalls=aliasCalls+1;assert(actor==player and canonical==item and source==root and dest==destination and id==17 and fullType=='Base.Book' and member==prototype.queueList[1].items[1])
 return{schema=2,item=item,source=root,destination=destination,aliasMember=member,aliasResolution='native-root-id'}
end
local fixture={snapshot=function()snapshots=snapshots+1;return{stable=true}end,same=function(a,b)
 local function same(x,y)if type(x)~=type(y)then return false end;if type(x)~='table'then return x==y end
 for k,v in pairs(x)do if not same(v,y[k])then return false end end;for k in pairs(y)do if x[k]==nil then return false end end;return true end
 return same(a,b)end}
local tick=0;local function clock()tick=tick+1;return tick end
local run=assert(loadfile(arg[1]))().run
local context={toolkit=toolkit,queue=queue,front=front,state=state,fixture=fixture,
 ids={source='worn-bag',front={id=17,type='Base.Book'}},case='worn-bag.header-cancel',kind='mp',mode='toolkit',native=false,
 control='header-cancel',clock=clock,precise=true,pickupEarned=true}
local result=run(context)
assert(result.passed==false and result.failure=='virtual-return-effect-unavailable' and result.unsupported==result.failure)
assert(result.effect==false and result.qualifiedReturn==false and result.mutationAuthorized==false)
assert(aliasCalls==1 and result.sources.nativeAlias and result.prototype.sameItemReference and not result.prototype.sameMemberReference)
assert(result.aliasFacts.scope=='independent-native-alias-probe' and result.aliasFacts.aliasMember==result.prototype.member and result.aliasFacts.aliasResolution=='native-root-id')
assert(result.readOnly and result.uiUnchanged and result.ledgerAfter and result.performance and not result.performance.comparable)
assert(observeCount==5 and ledgerCount==2 and snapshots==2,'observation did not finish the full read-only bank')
local detached=prototype.queueList[1].items[1];prototype.queueList[1].items[1]=item
local same=run(context);assert(same.aliasFacts==false and same.prototype.sameMemberReference and aliasCalls==1)
prototype.queueList[1].items[1]=detached;queueOff=true;context.native=true;context.mode='native'
local control=run(context);assert(control.passed and control.control=='queue-disabled' and control.aliasFacts==false and aliasCalls==1)
queueOff=false;context.native=false;context.mode='toolkit';withEffect=true
local helper=toolkitLeafTransferAliasFacts
for _,which in ipairs({'absent','nil'})do
 toolkitLeafTransferAliasFacts=which=='absent'and nil or function()return nil end
 -- Lua's and/or idiom cannot represent nil in its middle operand.
 if which=='absent'then toolkitLeafTransferAliasFacts=nil end
 local beforeObserve,beforeLedger,beforeSnapshots=observeCount,ledgerCount,snapshots
 local missing=run(context)
 assert(not missing.passed and missing.failure=='native-alias-facts-unavailable' and missing.aliasFacts==false)
 assert(not missing.qualifiedReturn and missing.effect.complete and missing.readOnly and missing.performance and not missing.performance.comparable)
 assert(observeCount-beforeObserve==5 and ledgerCount-beforeLedger==2 and snapshots-beforeSnapshots==2)
end
toolkitLeafTransferAliasFacts=helper
os.exit(0)
"""
        subprocess.run([lua, '-e', OFFLINE_FIXTURE_EVENTS + source, '--', 'unused', str(ROOT / 'tests/native_queue/book-controls/shared/QueueBookEditObservation.lua')], check=True)

    def test_fixture_compiles_and_does_not_repair_client_equipment(self):
        lua = shutil.which('luajit')
        if not lua: self.skipTest('LuaJIT not installed')
        paths = list((ROOT / 'tests/native_queue/book-controls').rglob('*.lua'))
        subprocess.run([lua, '-e', 'for i=1,#arg do assert(loadfile(arg[i]))end;os.exit()', '--', *map(str, paths)], check=True)
        source = (ROOT / 'tests/native_queue/book-controls/shared/QueueBookControls.lua').read_text()
        resolve = source.split('function F.resolve', 1)[1]
        for mutation in ('setPrimaryHandItem', 'setSecondaryHandItem', 'setWornItem', 'resetModel', 'teleportTo'):
            self.assertNotIn(mutation, resolve)
        client = (ROOT / 'tests/native_queue/book-controls/client/ZZBookControls.lua').read_text()
        self.assertIn('ISTimedActionQueue.clear(state.player)', client)
        self.assertIn("raw('DENIED',ui.decision)", client)
        self.assertIn("phase='reset-drain'", client)
        self.assertIn('list:rowUnderMouse', client)
        self.assertIn('list:onMouseDown', client)
        self.assertIn('list:onMouseUp', client)
        self.assertNotIn('T.ActionQueue.move(', client)
        self.assertNotIn('T.ActionQueue.cancel(', client)
        self.assertNotIn('setMaxTime', client)


if __name__ == '__main__': unittest.main()
