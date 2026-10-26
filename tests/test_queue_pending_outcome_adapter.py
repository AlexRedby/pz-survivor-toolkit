"""Reject packet-order claims without exact real fault and transition evidence."""
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks.adapters import fitness, fitness_pending as pending


class PendingOutcomeAdapterTests(unittest.TestCase):
    def fixture(self, case='active-cancel-restore', mode='toolkit'):
        selection = dict(kind='mp', mode=mode, cases=[case], clients=2, languages=['EN', 'RU'], mods=fitness.MODS,
                         options=dict(mp_host=True, fitness_diagnostics=True, fitness_receipt_delay_ms=1000,
                                      fitness_receipt_duplicate=True, fitness_editor_toggles={case:'off-pending-outcome'}))
        native = mode == 'native'
        packet = dict(protocol=1, player=7, transaction=3, kind=pending.TARGETS[case][0],
                      state=pending.TARGETS[case][1], token='00000000-0000-0000-0000-000000000001')
        rows = []
        for index, phase in enumerate(('retained','pending','released','duplicate'), 1):
            row = dict(packet, case=case, sequence=index, phase=phase, at=(100,150,1100,1120)[index-1], deadline=1100,
                       actionRef='original-action', nativeRef='original-native', packetRef='original-packet',
                       fingerprint='|'.join(str(packet[key]) for key in ('protocol','player','transaction','kind','token','state')), ackBefore=False if native else 'started' if index<=3 else packet['state'],
                       ackAfter=False if native else 'started' if index<=2 else packet['state'],
                       currentMatches=not native, headMatches=not native, nativeAbsent=case=='active-cancel-restore')
            if phase=='pending':row.update(mode=mode,editorEnabled=False,sealedStarted=not native,
                                          tailRetained=not native or case!='active-cancel-restore',tailUnread=True)
            rows.append(row)
        prep = dict(items=dict(tail=10, bag=11, dumbbell=12))
        cancel = dict(case=case,boundary='accepted-cancel',at=50,nativeClock=200,actionRef='earlier-action',currentRef='earlier-action',
                      nativeRef='original-native',kind=packet['kind'],itemId=False if case=='active-cancel-restore' else 11,
                      itemType=False if case=='active-cancel-restore' else 'Base.Bag_Schoolbag',token='operation',generation=5,
                      tailRef='tail',tailId=10,tailRetained=True,requestRetained=True,drainingAction=True,requiredStep=False)
        boundary = dict(cancel,boundary='pending-outcome',at=140,nativeClock=300,actionRef='pending-action',currentRef='pending-action')
        command = dict(receiptFault=rows,receiptFaultTailAt=False if native and case=='active-cancel-restore' else 1200,
                       editorEnabled=False,editorTransitions=[],activeAcks=[packet['token']],
                       terminalAcks=[] if native else [dict(token=packet['token'],state=packet['state'])])
        if not native:
            command.update(editorCancelBoundary=cancel,editorPendingBoundary=boundary,
                           editorTransitions=[dict(boundary,at=145,enabled=False,generationBefore=5,generationAfter=5)])
        return selection, command, prep

    def test_exact_fault_and_pending_transition_in_both_modes(self):
        for case in pending.TARGETS:
            for mode in ('native','toolkit'):
                selection, command, prep = self.fixture(case,mode)
                fitness.validate(selection)
                self.assertEqual(pending.verify_case(case,command,prep,selection),[])
                self.assertEqual(fitness._editor_case(case,command,prep,selection),[])

    def test_fault_requires_actual_hold_release_identity_and_once_only_delivery(self):
        changes = {
            'missing':lambda c:c.pop('receiptFault'),
            'empty':lambda c:c.update(receiptFault=[]),
            'duplicate phase':lambda c:c['receiptFault'].append(c['receiptFault'][-1]),
            'no hold':lambda c:c['receiptFault'][1].update(at=1100),
            'early release':lambda c:c['receiptFault'][2].update(at=1000),
            'reversed replay':lambda c:c['receiptFault'][3].update(at=1050),
            'wrong action':lambda c:c['receiptFault'][1].update(actionRef='foreign'),
            'wrong native':lambda c:c['receiptFault'][2].update(nativeRef='foreign'),
            'different packet':lambda c:c['receiptFault'][3].update(packetRef='copy'),
            'token replaced':lambda c:c['receiptFault'][3].update(token='00000000-0000-0000-0000-000000000002'),
            'foreign transaction':lambda c:c['receiptFault'][2].update(transaction=4),
            'contents replaced':lambda c:c['receiptFault'][0].update(fingerprint='{}'),
            'premature terminal':lambda c:c['receiptFault'][1].update(ackBefore='canceled'),
            'not sealed':lambda c:c['receiptFault'][1].update(sealedStarted=False),
            'native still present':lambda c:c['receiptFault'][1].update(nativeAbsent=False),
            'not head':lambda c:c['receiptFault'][1].update(currentMatches=False,headMatches=False),
            'tail lost':lambda c:c['receiptFault'][1].update(tailRetained=False),
            'tail consumed':lambda c:c['receiptFault'][1].update(tailUnread=False),
            'tail early':lambda c:c.update(receiptFaultTailAt=1099),
            'editor on':lambda c:c['receiptFault'][1].update(editorEnabled=True),
            'release not settled':lambda c:c['receiptFault'][2].update(ackAfter='started'),
            'duplicate rewrites outcome':lambda c:c['receiptFault'][3].update(ackAfter='completed'),
        }
        for name, change in changes.items():
            selection,command,prep=self.fixture();change(command)
            with self.subTest(change=name):self.assertTrue(pending.verify_case(selection['cases'][0],command,prep,selection))

    def test_disable_must_be_inside_genuine_hold_and_same_native_episode(self):
        changes = {
            'before hold':lambda c:c['editorPendingBoundary'].update(at=99),
            'after window':lambda c:c['editorTransitions'][0].update(at=1100),
            'wrong native':lambda c:c['editorPendingBoundary'].update(nativeRef='foreign'),
            'wrong generation':lambda c:c['editorTransitions'][0].update(generationAfter=8),
            'request lost':lambda c:c['editorPendingBoundary'].update(requestRetained=False),
            'wrong boundary':lambda c:c['editorPendingBoundary'].update(boundary='accepted-cancel'),
            'extra transition':lambda c:c['editorTransitions'].append(c['editorTransitions'][0]),
        }
        for name, change in changes.items():
            selection,command,prep=self.fixture();change(command)
            with self.subTest(change=name):self.assertTrue(fitness._editor_case(selection['cases'][0],command,prep,selection))

    def test_raw_fault_order_and_publication_are_required(self):
        selection,command,_=self.fixture(mode='native');case=selection['cases'][0]
        row=dict(event='case',id=case,command=command)
        lines=['[FITNESS_TEST] RECEIPT_FAULT '+json.dumps(entry) for entry in command['receiptFault']]
        complete='[QUEUE_CHECK] '+json.dumps(row)
        self.assertEqual(pending.verify_logs('\n'.join(lines+[complete]),[row],selection),[])
        for changed in ([],lines[1:],lines+lines[-1:],lines[::-1],lines+[complete]+lines[:1]):
            with self.subTest(lines=len(changed)):
                self.assertTrue(pending.verify_logs('\n'.join(changed+[complete]),[row],selection))

    def test_configured_but_unused_legacy_delay_is_not_a_pass(self):
        selection=dict(options=dict(fitness_receipt_delay_ms=1000))
        self.assertTrue(pending.verify_logs('',[],selection))
        first=dict(case='empty-restore',boundary='Receipt.delayed',wallClock=10,action=dict(nativeRef=1),detail=dict(transaction=3))
        last=dict(first,boundary='Receipt.released',wallClock=1010)
        log=lambda rows:'\n'.join('[FITNESS_TEST] NATIVE_TRACE '+json.dumps(row) for row in rows)
        self.assertEqual(pending.verify_logs(log([first,last]),[],selection),[])
        for changed in ([first],[last,first], [first,dict(last,action=dict(nativeRef=2))]):
            # Chronological release order, not file order alone, is authoritative.
            if changed==[last,first]:changed=[first,dict(last,wallClock=9)]
            self.assertTrue(pending.verify_logs(log(changed),[],selection))

    def test_complete_report_preserves_existing_effect_and_cleanup_oracles(self):
        import test_queue_fitness_adapter as baseline
        for mode in ('native', 'toolkit'):
            seed = baseline.FitnessAdapterTests();seed.setUp();self.addCleanup(seed.doCleanups)
            selection, _, _ = self.fixture(mode=mode)
            selection['cases'] = list(pending.TARGETS)
            selection['options']['fitness_editor_toggles'] = {case:'off-pending-outcome' for case in selection['cases']}
            seed.selection = selection
            rows, raw, peers = seed.evidence()
            lines = []
            for row in rows:
                if row.get('event') == 'case':
                    case = row['id'];command = row['command']
                    _, fault, _ = self.fixture(case, mode)
                    command.update(receiptFault=fault['receiptFault'],receiptFaultTailAt=fault['receiptFaultTailAt'])
                    if case == 'active-cancel-restore':
                        command['activeAcks'] = fault['activeAcks']
                        if mode == 'toolkit':command['terminalAcks'] = fault['terminalAcks']
                    if mode == 'toolkit':
                        cancel = command['editorCancelBoundary']
                        for event in command['receiptFault']:event['nativeRef'] = cancel['nativeRef']
                        boundary = dict(cancel,boundary='pending-outcome',at=140,nativeClock=cancel['nativeClock']+100)
                        command['editorPendingBoundary'] = boundary
                        command['editorTransitions'] = [dict(boundary,at=145,enabled=False,generationBefore=5,generationAfter=5)]
                        for i, event in enumerate(command['settledLedgers']):event['at']=2000+i*100
                        lines.extend(['[FITNESS_TEST] EDITOR_CANCEL '+json.dumps(cancel),
                                      '[FITNESS_TEST] RECEIPT_FAULT '+json.dumps(command['receiptFault'][0]),
                                      '[FITNESS_TEST] EDITOR_PENDING '+json.dumps(boundary),
                                      '[FITNESS_TEST] EDITOR_TRANSITION '+json.dumps(command['editorTransitions'][0])])
                        events = command['receiptFault'][1:]
                    else:events = command['receiptFault']
                    lines.extend('[FITNESS_TEST] RECEIPT_FAULT '+json.dumps(event) for event in events)
                    lines.extend('[FITNESS_TEST] SETTLED_LEDGER '+json.dumps(event) for event in command['settledLedgers'])
                lines.append('[QUEUE_CHECK] '+json.dumps(row))
            (seed.root/'client1-launch.log').write_text('\n'.join(lines)+'\n[FITNESS_TEST] COMPLETE\n')
            (seed.root/'server-launch.log').write_text('\n'.join('[FITNESS_TEST] '+marker+' '+json.dumps(value) for marker,value in raw))
            (seed.root/'client2-launch.log').write_text('\n'.join('[QUEUE_CHECK] '+json.dumps(row) for row in peers)+'\n[FITNESS_TEST] COMPLETE\n')
            with self.subTest(mode=mode):self.assertEqual(fitness.verify(seed.root,selection,{})['issues'],[])

    def test_native_receipts_cannot_be_terminal_before_release_or_reopen_started(self):
        for case in pending.TARGETS:
            for index, ack in ((0,pending.TARGETS[case][1]),(1,pending.TARGETS[case][1]),(3,'started')):
                selection,command,prep=self.fixture(case,'native')
                command['receiptFault'][index].update(ackBefore=ack,ackAfter=ack)
                with self.subTest(case=case,index=index):self.assertTrue(pending.verify_case(case,command,prep,selection))

    def test_raw_editor_transition_cannot_be_published_after_receipt_release(self):
        selection,command,_=self.fixture();case=selection['cases'][0]
        row=dict(event='case',id=case,command=command)
        faults=['[FITNESS_TEST] RECEIPT_FAULT '+json.dumps(entry) for entry in command['receiptFault']]
        editors=['[FITNESS_TEST] '+marker+' '+json.dumps(command[key]) for marker,key in
                 [('EDITOR_CANCEL','editorCancelBoundary'),('EDITOR_PENDING','editorPendingBoundary')]]
        editors.append('[FITNESS_TEST] EDITOR_TRANSITION '+json.dumps(command['editorTransitions'][0]))
        complete='[QUEUE_CHECK] '+json.dumps(row)
        good=[editors[0],faults[0],*editors[1:],*faults[1:],complete]
        self.assertEqual(pending.verify_logs('\n'.join(good),[row],selection),[])
        self.assertTrue(pending.verify_logs('\n'.join(faults+editors+[complete]),[row],selection))

    def test_legacy_release_must_follow_interception_in_the_raw_stream(self):
        selection=dict(options=dict(fitness_receipt_delay_ms=1000))
        first=dict(case='empty-restore',boundary='Receipt.delayed',wallClock=10,action=dict(nativeRef=1),detail=dict(transaction=3))
        last=dict(first,boundary='Receipt.released',wallClock=1010)
        text='\n'.join('[FITNESS_TEST] NATIVE_TRACE '+json.dumps(row) for row in [last,first])
        self.assertTrue(pending.verify_logs(text,[],selection))

    def test_cleanup_cannot_be_reported_earned_while_terminal_is_held(self):
        selection,command,prep=self.fixture()
        command['settledLedgers']=[dict(at=1000)]
        self.assertTrue(pending.verify_case(selection['cases'][0],command,prep,selection))

    def test_active_fault_must_match_the_workout_receipt_token(self):
        for mode in ('native','toolkit'):
            selection,command,prep=self.fixture(mode=mode)
            command['activeAcks']=['00000000-0000-0000-0000-000000000002']
            with self.subTest(mode=mode):self.assertTrue(pending.verify_case(selection['cases'][0],command,prep,selection))

    def test_pending_options_are_bounded_and_case_specific(self):
        for key,value in [('fitness_receipt_delay_ms',999),('fitness_receipt_duplicate',False),('fitness_diagnostics',False)]:
            selection,_,_=self.fixture();selection['options'][key]=value
            with self.subTest(option=key),self.assertRaises(ValueError):fitness.validate(selection)
        selection,_,_=self.fixture();selection['cases']=['pickup-cancel-restore'];selection['options']['fitness_editor_toggles']={selection['cases'][0]:'off-pending-outcome'}
        with self.assertRaises(ValueError):fitness.validate(selection)


if __name__=='__main__':unittest.main()
