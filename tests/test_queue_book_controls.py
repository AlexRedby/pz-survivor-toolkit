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
import zipfile
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import book_controls as a
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

    def selection(self, kind='mp', mode='toolkit'):
        return dict(suite='book-controls', cases=list(a.CASES), kind=kind, mode=mode, clients=1,
                    languages=['EN'], mods=list(a.MODS), options=dict(book_controls=True, **({'mp_host': True} if kind == 'mp' else {})))

    def evidence(self, case='worn-bag.move-equip', kind='mp', mode='toolkit'):
        source, original_control = case.split('.', 1); control = a.base_control(original_control); lost = a.capacity_case(original_control); favorite_unmoved = a.favorite_case(original_control) and kind == 'sp'
        enabled = mode == 'toolkit'; moving = enabled and control.startswith('move-'); keep = enabled and control == 'return-child-cancel'
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
            typ = {'front': 'ISReadABook', 'tail': 'ISReadABook', 'volume': 'ISRadioAction', 'equip': 'ISEquipWeaponAction', 'pickup': 'ISInventoryTransferAction', 'return': 'ISInventoryTransferAction'}[role]
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
        equip = record(2, 'equip', 103, 20, started=enabled or not lost)
        volume = record(3, 'volume', False, 30, started=enabled or not lost)
        tail = record(4, 'tail', 102, 40, started=enabled or not lost)
        if moving:
            resumed = record(5, 'front', 101, 10)
            resume = dict(oldAction=original['actionRef'], newAction=resumed['actionRef'], oldNative=original['nativeRef'], newNative=resumed['nativeRef'],
                          item=101, token=10, startPage=219, pages=219, oldNativeAbsent=True, at=15)
        else: resume = False
        admission = [dict(sequence=r['sequence'], role=r['role'], type=r['type'], token=r['token'], actionRef=r['actionRef'], nativeRef=False, current=r is original) for r in (original, equip, volume, tail)]
        if source != 'root':
            pickup = record(6, 'pickup', 101, 10); returned = record(7, 'return', 101, 10, started=not keep and not lost)
            if lost and enabled and kind == 'mp':
                returned.update(started=True,progress=True,nativeRef='java:7',startedAt=17,allocatedAt=16,transaction=7,transactionDone=False,transactionRejected=True,finishes=[dict(phase='stop',at=19)])
            admission.insert(0, dict(sequence=6, role='pickup', type=pickup['type'], token=pickup['token']))
            admission.insert(2, dict(sequence=7, role='return', type=returned['type'], token=returned['token']))
        starts = [1, 2, 5, 3, 4] if moving and control == 'move-equip' else [1, 3, 5, 2, 4] if moving else [1] if lost and not enabled else [1, 2, 3, 4]
        b['queue'] = copy.deepcopy(admission)
        b['ui'] = dict(source='ActionQueuePanel.List', input='programmatic-drag' if moving else 'programmatic-press-release',
                       header=source != 'root' and control not in ('reader-child-cancel', 'return-child-cancel'), singleton=source == 'root', target=returned['actionRef'] if keep else original['actionRef'], operation=10,
                       at=10, acceptedAt=10, hitTested=True, pressCaptured=True, gestureCleared=True, accepted=True, feedback=False,
                       bodyContinues=True, returnAbsent=True, bookRoot=True, operationCancelled=False,
                       decision=dict(reason=False, source=source), dragging=True, movingAction=(equip if control == 'move-equip' else volume)['actionRef'],
                       movingAnchor=(equip if control == 'move-equip' else volume)['actionRef'], movingToken=20 if control == 'move-equip' else 30) if enabled else False
        final = a.expected(spec, enabled, b, kind)
        row = dict(event='case', suite='book-controls', kind=kind, mode=mode, actor='client1', id=case, status='passed', reason=False, ids=spec,
                   baseline=copy.deepcopy(seed), authorityBaseline=copy.deepcopy(seed), boundary=b, records=records, starts=starts,
                   resume=resume, tailSnapshot=copy.deepcopy(final), volumeSnapshot=copy.deepcopy(before), equipSnapshot=copy.deepcopy(before),
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
                        equipProducer='ISInventoryPaneContextMenu.equipWeapon', sourceBound=True, queue=admission)
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
                for case in a.CASES:
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
        self.assertNotIn('root.return-child-cancel', a.CASES)

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
        for case in a.CAPACITY_CASES:
            for name, mutate in mutations.items():
                with self.subTest(case=case, mutation=name):
                    evidence = self.evidence(case); mutate(evidence[0]); self.assertTrue(self.check(evidence))
            native = self.evidence(case, mode='native')
            self.assertEqual(native[0]['starts'], [1]); self.assertIs(native[0]['blockedReturn'], False)
            self.assertEqual(native[0]['client']['books']['tail']['pages'], native[1]['tail']['initial'])

    def test_timing_samples_quantiles_and_frozen_design_budgets(self):
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
        self.assertTrue(any('Frozen performance budget exceeded' in e for e in self.check(evidence)))

    def test_actual_cli_catalog_selection_and_native_preflight_accept_safe_case_ids(self):
        catalog = cli.load_catalog(['book-controls'])
        self.assertEqual([case['id'] for case in catalog['suites']['book-controls']['cases']], list(a.CASES))
        self.assertTrue(all('/' not in case for case in a.CASES))
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                with self.subTest(kind=kind, mode=mode):
                    args = argparse.Namespace(suite='book-controls',cases=','.join(a.CASES),kind=kind,mode=mode,
                                              mods='selected',language='EN',config=None,mod_source=[],timeout=1800,ports=None)
                    options = dict(book_controls=True, **({'mp_host': True} if kind == 'mp' else {}))
                    selected = cli.selection(args, catalog, options=options)
                    native._validate(selected)
                    a.validate(selected)
                    self.assertEqual(selected['cases'], list(a.CASES))
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
        subprocess.run([lua, '-e', source, '--', 'unused', str(ROOT / 'tests/native_queue/book-controls/shared/QueueBookControls.lua'), ','.join(a.CASES)], check=True)

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
            'slow32 edit': lambda r: r['performance']['probe32']['metrics'][0]['rawMs'].__setitem__(-1,5),
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
now=function()return 1000 end;ref=function(value)return tostring(value)end;raw=function()end
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
  else assert(metric.decisionStable and metric.decisionClass=='allowed'and performance.probe32.positiveTimingClaim)end
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
os.exit(0)
"""
        subprocess.run([lua,'-e',source,'--','unused',str(ROOT/'tests/native_queue/book-controls/client/ZZBookControls.lua')],check=True)

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
        self.assertEqual(len(a.CASES), 20)
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                for case in ('world.header-cancel', 'world.header-cancel-capacity-lost', *a.FAVORITE_CASES):
                    evidence = self.evidence(case, kind, mode)
                    self.assertEqual(self.check(evidence, kind, mode), [])
                    self.assertIs(evidence[1]['baseline']['books']['front']['favorite'], a.favorite_case(case))
                    if case in a.FAVORITE_CASES:
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
        subprocess.run([lua,'-e',source,'--','unused',str(ROOT/'tests/native_queue/book-controls/shared/QueueBookControls.lua')],check=True)
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
        subprocess.run([lua,'-e',source,'--','unused',str(ROOT/'tests/native_queue/book-controls/shared/QueueBookControls.lua'),str(ROOT/'tests/native_queue/book-controls/client/ZZBookControls.lua')],check=True)

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
            client+='\n'+a.PREFIX+'REPLICA_GAP '+json.dumps(opened)+'\n'+a.PREFIX+'REPLICA_CONVERGED '+json.dumps(gap)
            (root/'client1-launch.log').write_text(client);self.assertEqual(a.verify(root,selection,{})['issues'],[])
            (root/'client1-launch.log').write_text(client.replace(a.PREFIX+'REPLICA_CONVERGED '+json.dumps(gap),a.PREFIX+'REPLICA_CONVERGED '+json.dumps(dict(gap,transaction=999))))
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
        value=json.loads(subprocess.check_output([lua,'-e',source,'--','unused',str(ROOT/'tests/native_queue/health/shared/QueueHealthEvents.lua')],text=True))
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

    def test_selection_is_opt_in_exact_ordered_bank(self):
        a.validate(self.selection())
        self.assertEqual(adapters.get('book-controls'), a)
        for field, value in [('cases', list(reversed(a.CASES))), ('cases', list(a.CASES[:-1])), ('mods', a.MODS[:-1]), ('languages', ['RU']), ('clients', True), ('options', dict(mp_host=True))]:
            selection = self.selection(); selection[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError): a.validate(selection)
        selection = self.selection(); selection['options']['world_template'] = 'fixture'
        with self.assertRaises(ValueError): a.validate(selection)

    def log_bank(self, kind='mp', mode='toolkit'):
        selection = self.selection(kind, mode); client, server = [], []
        def raw(marker, value): return a.PREFIX + marker + ' ' + json.dumps(value)
        def event(value): return '[QUEUE_CHECK] ' + json.dumps(value)
        client.append(event(dict(event='setup', suite='book-controls', cases=list(a.CASES), queueEnabled=mode == 'toolkit', nativeDurations=True, sourceBound=True, authorityEquipment=True)))
        for case in a.CASES:
            row, spec, baseline, final, admissions, boundaries, drains, acks = self.evidence(case, kind, mode)
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
            client.append(raw('PERFORMANCE',row['performance']))
            client.append(event(row))
        client.append(event(dict(event='complete', suite='book-controls', cases=list(a.CASES), performed=len(a.CASES), skipped=0, failed=0)))
        client.append(raw('COMPLETE', dict(cases=list(a.CASES), failed=0)))
        return selection, '\n'.join(client), '\n'.join(server)

    def test_whole_bank_raw_evidence_and_completion(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for kind, mode in [('mp', 'toolkit'), ('sp', 'native')]:
                selection, client, server = self.log_bank(kind, mode)
                (root / 'client1-launch.log').write_text(client); (root / 'server-launch.log').write_text(server)
                self.assertEqual(a.verify(root, selection, {})['issues'], [])
                self.assertTrue(a.complete(selection, 'client1', client))
                self.assertFalse(a.complete(selection, 'server', client))
                for bad in (client.replace('"performed": ' + str(len(a.CASES)), '"performed": 0'), client + '\n' + a.PREFIX + 'DENIED {}', client + '\n' + a.PREFIX + 'RESET {}', client.replace('"authorityEquipment": true', '"authorityEquipment": false')):
                    (root / 'client1-launch.log').write_text(bad)
                    self.assertTrue(a.verify(root, selection, {})['issues'])
            # Diagnostic completion must stop the common runner after the whole
            # failed bank, while qualification still fails all denied features.
            denied = a.PREFIX + 'COMPLETE ' + json.dumps(dict(cases=list(a.CASES), failed=len(a.CASES)))
            self.assertTrue(a.complete(self.selection(), 'client1', denied))
            self.assertFalse(a.complete(self.selection(), 'client1', denied + '\n' + denied))

    def test_staging_and_source_sealing(self):
        paths = a.sources(ROOT, self.selection())
        self.assertTrue(all(path.is_file() for path in paths))
        self.assertIn(Path(a.__file__).with_name('tv_controls.py'), paths)
        self.assertIn(ROOT / 'tests/test_queue_book_controls.py', paths)
        probe_source=ROOT / 'tests/native_queue/book-controls/java/Main.java'
        self.assertIn(probe_source,paths)
        self.assertIn('media/lua/shared/TimedActions/ISBaseTimedAction.lua',a.GAME_INPUTS)
        self.assertIn('[QUEUE_TEST] FAIL book-controls-stop-observer',probe_source.read_text())
        with tempfile.TemporaryDirectory() as directory:
            runtime = dict(roles={role: dict(cache=str(Path(directory) / role)) for role in ('server', 'client1')})
            probe = Path(directory) / 'probe.jar'
            with zipfile.ZipFile(probe,'w') as jar:
                jar.writestr('net/alexredby/bookcontrolsprobe/Main.class',b'compiled observation fixture')
                jar.writestr('net/alexredby/bookcontrolsprobe/Main$Stopped.class',b'compiled stop advice')
            with mock.patch.object(a, '_stop_probe', return_value=probe):
                a.stage(ROOT, directory, None, None, self.selection(), {}, runtime)
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
require=function(name)if name=='PZSurvivorToolkit/ActionQueueProjection'then return{capture=function()return{stable=false}end}end end
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
        subprocess.run([lua, '-e', source, '--', 'unused', str(ROOT / 'PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueuePanel.lua')], check=True)

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
