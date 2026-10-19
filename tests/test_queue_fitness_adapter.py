"""Falsify native fitness evidence: client completion alone never proves effects."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import fitness


def clinical(xp=0, endurance=1, regularity=0, stiffness=0):
    return dict(fitnessXP=xp, strengthXP=xp, endurance=endurance,
                regularity=dict(squats=regularity, pushups=regularity, bicepscurl=regularity),
                stiffness=dict(legs=stiffness, arms=stiffness, chest=stiffness, abs=stiffness),
                timers=dict(legs=100, arms=100, chest=100, abs=100))


class FitnessAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.selection = dict(suite='fitness', kind='sp', mode='toolkit', cases=list(fitness.CASES),
                              clients=1, languages=['EN'], mods=list(fitness.MODS), options={})

    def evidence(self):
        cases, mode, mp = self.selection['cases'], self.selection['mode'], self.selection['kind']=='mp'
        rows = [dict(event='setup', cases=cases, expected=len(cases), nativeDurations=True, queueEnabled=mode=='toolkit')]
        raw, peers = [], []
        for n, case in enumerate(cases):
            ids = dict(zip(('front', 'tail', 'bag', 'hammer', 'screwdriver', 'dumbbell'), range(100+n*10, 106+n*10)))
            inventory = dict(items=[dict(id=value, kind=key, container='root') for key, value in ids.items()],
                             primary=False, secondary=False, worn=[])
            if case == 'closed-ui-restore':
                inventory.update(primary=ids['hammer'], secondary=ids['screwdriver'], worn=[dict(id=ids['bag'], location='Back')])
                next(row for row in inventory['items'] if row['id']==ids['dumbbell'])['container']=ids['bag']
            prep = dict(case=case, items=ids, inventory=inventory, before=clinical())
            if mp:
                prep.update(peerBook=1000+n, peerOnlineID=2)
                peers.append(dict(event='case', suite='fitness', kind='mp', mode=mode, actor='client2',
                                  id=case, book=prep['peerBook'], read=True, queueDrained=True))
            final = copy.deepcopy(inventory)
            if case == 'missing-dumbbell':
                final['items'] = [row for row in final['items'] if row['id'] != ids['dumbbell']]
            exercises = fitness._expected_exercises(case, mode)
            records = []
            for i, exercise in enumerate(exercises):
                start = i*700000
                end = start + (100000 if case == 'active-cancel' else 600001)
                records.append(dict(exercise=exercise, minutes=10, maxTime=5000000, reps=10,
                    startMS=start, stopMS=end, lastRepMS=start+1000, before=clinical(), after=clinical(10,.9,1,1),
                    minEndurance=.8, lastRep=clinical(10,.8,1,1), currentExerciseCleared=True,
                    serverStopReturned=True, previousStopSettled=True))
            if case=='closed-ui-restore':
                for record in records:
                    start_inventory=copy.deepcopy(inventory)
                    start_inventory.update(primary=ids['dumbbell'],secondary=False,worn=[])
                    next(row for row in start_inventory['items'] if row['id']==ids['dumbbell'])['container']='root'
                    record['startEquipment']=start_inventory
            receipt = dict(case=case, inventory=final, before=prep['before'], clinical=clinical(10,.9,1,1) if records else clinical(),
                records=records, violations=[], tailRead=True, frontRead=case not in ('empty','active-cancel'), currentExerciseCleared=True,
                serverStopSettled=True, peerConnected=True, removed=ids['dumbbell'] if case=='missing-dumbbell' else False,
                serverSettleMilliseconds=2000)
            if mp:
                receipt.update(peerRead=True, peerBook=prep['peerBook'], peerOnlineID=prep['peerOnlineID'])
            command = dict(menuDispatched=True, nativeDurations=True, minutes=10, frontMinutes=0 if case in ('empty','active-cancel') else 12,
                waitingNoExercise=True, waitingNoClinicalEffects=True, waitMS=720000,
                activeObserved=bool(exercises), activeCancelled=case=='active-cancel', pendingCancelled=mode=='toolkit' and case=='pending-cancel',
                reordered=mode=='toolkit' and case=='pending-reorder', closedUI=case=='closed-ui-restore',
                queueDrained=True, clientCurrentExerciseCleared=True, clientInventory=final, startedOrder=exercises,
                activeAcks=['token'+str(i) for i in range(len(exercises))],
                terminalAcks=[dict(token='token'+str(i), state='canceled') for i in range(len(exercises))])
            command['initialClinical']=copy.deepcopy(prep['before'])
            command['progressSamples']=[dict(exercise=exercise,total=10,elapsed=2,fraction=.2,
                startMS=i*700000,sampleMS=i*700000+120000,label='2.0 / 10 minutes') for i,exercise in enumerate(exercises)] if mode=='toolkit' else []
            if case=='pending-reorder' and mode=='toolkit':command['reorderedTailBeforeStart']=True
            if case=='closed-ui-restore' and mode=='toolkit':
                command.update(borrowedTransferProgress=True,borrowedTool=ids['dumbbell'],borrowedSourceBag=ids['bag'])
            raw.append(('PREPARED', prep))
            if case in ('missing-dumbbell', 'exhaustion'):
                mutation = dict(case=case, removed=ids['dumbbell'] if case=='missing-dumbbell' else False,
                                endurance=.01 if case=='exhaustion' else 1)
                command.update(mutationObserved=True, mutation=mutation);raw.append(('MUTATED',mutation))
            raw.append(('VERIFIED',receipt))
            rows.append(dict(event='case', id=case, status='passed', reason=None, command=command, receipt=receipt))
        rows.append(dict(event='complete', cases=cases, expected=len(cases), performed=len(cases), failed=0, skipped=0))
        rows = [dict(row, suite='fitness', actor='client1', kind=self.selection['kind'], mode=mode) for row in rows]
        return rows, raw, peers

    def verify(self, evidence=None):
        rows, raw, peers = evidence or self.evidence()
        authority = '\n'.join('[FITNESS_TEST] '+marker+' '+json.dumps(value) for marker,value in raw)
        client = '\n'.join('[QUEUE_CHECK] '+json.dumps(row) for row in rows)+'\n[FITNESS_TEST] COMPLETE\n'
        if self.selection['kind']=='mp':
            (self.root/'server-launch.log').write_text(authority)
            (self.root/'client2-launch.log').write_text('\n'.join('[QUEUE_CHECK] '+json.dumps(row) for row in peers)+'\n[FITNESS_TEST] COMPLETE\n')
        else:
            client += authority
        (self.root/'client1-launch.log').write_text(client)
        return fitness.verify(self.root, self.selection, {})

    def test_complete_toolkit_sp_and_real_host_evidence(self):
        for kind in ('sp','mp'):
            self.selection.update(kind=kind, clients=2 if kind=='mp' else 1,
                                  languages=['EN','RU'] if kind=='mp' else ['EN'], options={'mp_host':True} if kind=='mp' else {})
            with self.subTest(kind=kind):
                fitness.validate(self.selection)
                result = self.verify()
                self.assertEqual(result['issues'], [])
                self.assertTrue(all(row['status']=='passed' for row in result['outcomes']))
                self.assertEqual([(row['actor'],row['case']) for row in result['outcomes']],
                    [(actor,case) for actor in (('client1','client2') if kind=='mp' else ('client1',)) for case in self.selection['cases']])

    def test_native_control_success_keeps_exact_contract(self):
        self.selection.update(mode='native',cases=['empty','active-cancel'])
        self.assertEqual(self.verify()['issues'], [])

    def test_rejects_non_host_single_client_mp_partial_pack_and_reordered_cases(self):
        for changes in ({'mods':fitness.MODS[:-1]}, {'cases':['queued','empty']}, {'cases':['empty','empty']},
                        {'clients':True}, {'kind':'mp','clients':1,'languages':['EN']},
                        {'options':{'world_template':'/tmp/save'}}, {'kind':'mp','clients':2,'languages':['EN','RU'],'options':{}}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                fitness.validate(dict(self.selection,**changes))

    def test_rejects_fake_real_repetition_and_clinical_proofs(self):
        self.selection['cases']=['empty']
        for field,value in (('reps',0),('reps',True),('minEndurance',1),('lastRepMS',700000),
                            ('lastRep',clinical()),('after',{}),('stopMS',100000),
                            ('previousStopSettled',False),('serverStopReturned',False),('currentExerciseCleared',False)):
            evidence=copy.deepcopy(self.evidence())
            evidence[0][1]['receipt']['records'][0][field]=value
            evidence[1][-1][1]['records'][0][field]=value
            with self.subTest(field=field,value=value):
                self.assertTrue(self.verify(evidence)['issues'])

    def test_rejects_forged_inventory_and_lost_closed_ui_equipment(self):
        self.selection['cases']=['closed-ui-restore']
        for mutate in (
            lambda row: row.update(primary=False),
            lambda row: row.update(worn=[]),
            lambda row: row['items'][0].update(container=102),
            lambda row: row['items'].append(dict(row['items'][0])),
        ):
            evidence=copy.deepcopy(self.evidence())
            mutate(evidence[0][1]['receipt']['inventory']);mutate(evidence[1][-1][1]['inventory'])
            self.assertTrue(self.verify(evidence)['issues'])

    def test_rejects_queue_wait_timer_expiration_and_constructor_side_effect(self):
        self.selection['cases']=['queued']
        for field,value in (('waitMS',599999),('waitingNoExercise',False),('waitingNoClinicalEffects',False),('minutes',1)):
            evidence=copy.deepcopy(self.evidence());evidence[0][1]['command'][field]=value
            with self.subTest(field=field):self.assertTrue(self.verify(evidence)['issues'])

    def test_rejects_sequential_server_overlap_and_absent_second_workout(self):
        self.selection['cases']=['sequential']
        for overlap in (True,False):
            evidence=copy.deepcopy(self.evidence())
            for receipt in (evidence[0][1]['receipt'],evidence[1][-1][1]):
                if overlap:receipt['records'][1]['startMS']=500000
                else:receipt['records'].pop()
            self.assertTrue(self.verify(evidence)['issues'])

    def test_rejects_lost_or_stale_real_peer_receipt_and_terminal_ack(self):
        self.selection.update(kind='mp',clients=2,languages=['EN','RU'],options={'mp_host':True},cases=['empty'])
        for change in ('peer','book','terminal','tail'):
            evidence=copy.deepcopy(self.evidence())
            if change=='peer':evidence[2].clear()
            elif change=='book':evidence[2][0]['book']=9999
            elif change=='terminal':evidence[0][1]['command']['terminalAcks']=[]
            else:
                evidence[0][1]['receipt']['tailRead']=False;evidence[1][-1][1]['tailRead']=False
            with self.subTest(change=change):self.assertTrue(self.verify(evidence)['issues'])

    def test_rejects_missing_item_that_still_awards_exercise_xp(self):
        self.selection['cases']=['missing-dumbbell']
        evidence=copy.deepcopy(self.evidence())
        for receipt in (evidence[0][1]['receipt'],evidence[1][-1][1]):receipt['clinical']=clinical(2,.9,1,1)
        self.assertTrue(self.verify(evidence)['issues'])

    def test_native_failures_are_never_reported_as_toolkit_pass(self):
        self.selection.update(mode='native',cases=['queued'])
        evidence=copy.deepcopy(self.evidence());evidence[0][1]['command']['waitingNoExercise']=False
        result=self.verify(evidence)
        self.assertEqual(result['outcomes'][0]['status'],'failed')
        self.assertFalse(result['outcomes'][0]['outcome']['effectsVerified'])

    def test_source_guards_remain_unmodified_on_sp_and_clients(self):
        source=(ROOT/'tests/native_queue/fitness/shared/QueueFitnessObservation.lua').read_text()
        guard=source.index('if not isServer()then return O end')
        self.assertGreater(source.index('ISFitnessAction[begin]='),guard)
        self.assertGreater(source.index('ISFitnessAction.exeLooped='),guard)
        self.assertGreater(source.index('ISFitnessAction[method]='),guard)
        self.assertNotIn('setGameSpeed(',source)
        self.assertNotIn('AddXP(',source)
        self.assertNotIn(':exerciseRepeat(',source)

    def test_lua_observer_preserves_client_callbacks_and_counts_real_server_calls(self):
        try:
            from lupa import LuaRuntime
        except ImportError:
            self.skipTest('Lupa is required for Lua observer checks')
        source=(ROOT/'tests/native_queue/fitness/shared/QueueFitnessObservation.lua').read_text()
        for server in (False,True):
            lua=LuaRuntime()
            lua.globals().server_mode=server
            lua.execute("""
                isServer=function()return server_mode end;isClient=function()return false end
                local now=0
                function advance()now=now+1000 end
                getGameTime=function()return {getCalender=function()return {getTimeInMillis=function()return now end}end}end
                calls={start=0,loop=0,stop=0,xp=0}
                fit={current=nil,getCurrentExe=function(self)return self.current end}
                player={getFitness=function()return fit end}
                ISFitnessAction={
                 serverStart=function(self)calls.start=calls.start+1;fit.current=self.exeDataType end,
                 exeLooped=function(self)calls.loop=calls.loop+1;calls.xp=calls.xp+5 end,
                 serverStop=function(self)calls.stop=calls.stop+1;fit.current=nil end,
                 complete=function()return true end,
                 start=function()return 'original' end,
                 stop=function()return 'original' end,
                 perform=function()return 'original' end}
                originalStart,originalLoop,originalStop=ISFitnessAction.start,ISFitnessAction.exeLooped,ISFitnessAction.stop
                package.preload['TimedActions/ISFitnessAction']=function()return ISFitnessAction end
            """)
            observation=lua.execute(source)
            lua.globals().observer=observation
            lua.execute("""
                observer.clinical=function()return {fitnessXP=calls.xp,endurance=1-calls.xp/100}end
                observer.reset(player,'probe')
                action={character=player,exeDataType='squats',timeToExe=10,repnb=0,startMS=0,
                 Type='ISFitnessAction',getDuration=function()return 5000000 end,isStarted=function()return true end}
                assert(ISFitnessAction.start==originalStart and ISFitnessAction.stop==originalStop)
                if server_mode then
                 ISFitnessAction.serverStart(action);advance()
                 ISFitnessAction.exeLooped(action);advance();ISFitnessAction.exeLooped(action);advance()
                 ISFitnessAction.serverStop(action)
                 local receipt=observer.receipt(player)
                 assert(calls.start==1 and calls.loop==2 and calls.stop==1 and calls.xp==10)
                 assert(#receipt.records==1 and receipt.records[1].reps==2)
                 assert(receipt.records[1].before.fitnessXP==0 and receipt.records[1].after.fitnessXP==10)
                 assert(receipt.serverStopSettled and receipt.currentExerciseCleared)
                else
                 assert(ISFitnessAction.exeLooped==originalLoop)
                 observer.sample(action);action.repnb=2;calls.xp=10;advance();observer.sample(action)
                 fit.current=nil;advance();observer.sample(nil)
                 local receipt=observer.receipt(player)
                 assert(calls.start==0 and calls.loop==0 and calls.stop==0 and calls.xp==10)
                 assert(#receipt.records==1 and receipt.records[1].reps==2)
                 assert(receipt.serverStopSettled and receipt.currentExerciseCleared)
                end
            """)
        lua=LuaRuntime()
        for path in (ROOT/'tests/native_queue/fitness').rglob('*.lua'):
            lua.compile(path.read_text())

    def test_native_hidden_get_up_action_extraction_is_exact_and_read_only(self):
        try:
            from lupa import LuaRuntime
        except ImportError:
            self.skipTest('Lupa is required for native callback shape checks')
        lua=LuaRuntime()
        lua.execute("""
            package.preload['QueueFitnessObservation']=function()return {}end
            ISTimedActionQueue={add=function()return 'original' end}
        """)
        fixture=lua.execute((ROOT/'tests/native_queue/fitness/shared/QueueFitnessFixture.lua').read_text())
        lua.globals().fixture=fixture
        lua.execute("""
            local player={};local panel={player=player}
            local action={Type='ISFitnessAction',character=player,fitnessUI=panel,exercise='bicepscurl',timeToExe=10}
            local wrapper={Type='ISWaitWhileGettingUp',onCompleteFunc=ISTimedActionQueue.add,onCompleteArgs={p1=action}}
            local found,deferred=fixture.requestedAction(wrapper,panel,true,'bicepscurl')
            assert(found==action and deferred and wrapper.onCompleteFunc==ISTimedActionQueue.add and wrapper.onCompleteArgs.p1==action)
            assert(fixture.requestedAction(wrapper,panel,false,'bicepscurl')==nil)
            assert(fixture.requestedAction(wrapper,panel,true,'squats')==nil)
            wrapper.onCompleteFunc=function()end
            assert(fixture.requestedAction(wrapper,panel,true,'bicepscurl')==nil)
            wrapper.onCompleteFunc=ISTimedActionQueue.add;wrapper.onCompleteArgs={p2=action}
            assert(fixture.requestedAction(wrapper,panel,true,'bicepscurl')==nil)
            wrapper.onCompleteArgs={p1=action};action.timeToExe=1
            assert(fixture.requestedAction(wrapper,panel,true,'bicepscurl')==nil)
        """)

    def test_borrowed_dumbbell_requires_transfer_progress_and_authoritative_start_hand(self):
        self.selection['cases']=['closed-ui-restore']
        for mutation in ('progress','source','start-hand','start-container','bag-worn'):
            evidence=copy.deepcopy(self.evidence())
            command=evidence[0][1]['command']
            if mutation=='progress':command['borrowedTransferProgress']=False
            elif mutation=='source':command['borrowedSourceBag']=99999
            else:
                for receipt in (evidence[0][1]['receipt'],evidence[1][-1][1]):
                    start=receipt['records'][0]['startEquipment']
                    if mutation=='start-hand':start['primary']=False
                    elif mutation=='start-container':start['items'][-1]['container']=102
                    else:start['worn']=[dict(id=102,location='Back')]
            with self.subTest(mutation=mutation):self.assertTrue(self.verify(evidence)['issues'])

    def test_visible_progress_rejects_wrong_total_elapsed_fraction_and_nonfinite_values(self):
        self.selection['cases']=['empty']
        for key,value in (('total',1),('elapsed',0),('elapsed',11),('fraction',0),('fraction',1.1),
                          ('fraction',float('inf')),('elapsed',float('nan')),('sampleMS',1),('label','')):
            evidence=copy.deepcopy(self.evidence());evidence[0][1]['command']['progressSamples'][0][key]=value
            with self.subTest(key=key,value=value):
                self.assertTrue(any('visible progress' in issue for issue in self.verify(evidence)['issues']))

    def exhaustion_passive_evidence(self):
        self.selection['cases']=['exhaustion']
        evidence=copy.deepcopy(self.evidence())
        evidence[0][1]['command']['waitingNoClinicalEffects']=False
        for receipt in (evidence[0][1]['receipt'],evidence[1][-1][1]):receipt['clinical']['fitnessXP']=10
        return evidence

    def test_exhaustion_native_passive_fitness_xp_is_not_an_exercise_replay(self):
        result=self.verify(self.exhaustion_passive_evidence())
        self.assertEqual(result['issues'],[])
        self.assertEqual(result['outcomes'][0]['status'],'passed')
        self.assertFalse(result['outcomes'][0]['outcome']['command']['waitingNoClinicalEffects'])
        self.assertEqual(result['outcomes'][0]['outcome']['receipt']['clinical']['fitnessXP'],10)

    def test_exhaustion_rejects_strength_regularity_stiffness_repetitions_and_xp_decrease(self):
        for mutation in ('strength','regularity','stiffness','records','started-order','fitness-decrease','initial-missing','initial-changed','flag-missing'):
            evidence=self.exhaustion_passive_evidence()
            for receipt in (evidence[0][1]['receipt'],evidence[1][-1][1]):
                if mutation=='strength':receipt['clinical']['strengthXP']=1
                elif mutation=='regularity':receipt['clinical']['regularity']['squats']=.08
                elif mutation=='stiffness':receipt['clinical']['stiffness']['legs']=1
                elif mutation=='records':receipt['records']=[{'exercise':'squats','reps':1}]
                elif mutation=='fitness-decrease':receipt['clinical']['fitnessXP']=-1
            command=evidence[0][1]['command']
            if mutation=='started-order':command['startedOrder']=['squats']
            elif mutation=='initial-missing':command.pop('initialClinical')
            elif mutation=='initial-changed':command['initialClinical']['strengthXP']=1
            elif mutation=='flag-missing':command.pop('waitingNoClinicalEffects')
            with self.subTest(mutation=mutation):self.assertTrue(self.verify(evidence)['issues'])

    def test_missing_dumbbell_and_pending_cancel_still_reject_any_unstarted_xp(self):
        for case in ('pending-cancel','missing-dumbbell'):
            self.selection['cases']=[case]
            evidence=copy.deepcopy(self.evidence())
            for receipt in (evidence[0][1]['receipt'],evidence[1][-1][1]):receipt['clinical']['fitnessXP']=1
            with self.subTest(case=case):
                self.assertTrue(any('rejected workout changed XP' in issue for issue in self.verify(evidence)['issues']))

    def ghost_evidence(self):
        self.selection.update(mode='native',cases=['missing-dumbbell','closed-ui-restore'])
        evidence=copy.deepcopy(self.evidence())
        failed=evidence[0][1]
        failed.update(status='failed',reason='independent-tail-not-preserved')
        failed['receipt'].update(records=[],tailRead=False,currentExerciseCleared=False)
        failed['command'].update(startedOrder=[],activeObserved=False,clientCurrentExerciseCleared=False)
        receipt=next(row for marker,row in evidence[1] if marker=='VERIFIED' and row['case']=='missing-dumbbell')
        receipt.update(records=[],tailRead=False,currentExerciseCleared=False)
        evidence[0][-1]['failed']=1
        recovery=dict(case='missing-dumbbell',mode='native',actor='client1',failedCaseRecorded=True,
            queueEmpty=True,nativeActions=0,observerRecords=0,observerActive=False,exactObjectMatched=True,cleared=True,
            before=clinical(),after=clinical(),inventoryBefore=copy.deepcopy(receipt['inventory']),inventoryAfter=copy.deepcopy(receipt['inventory']))
        insertion=next(i+1 for i,(marker,row) in enumerate(evidence[1]) if marker=='VERIFIED' and row['case']=='missing-dumbbell')
        evidence[1].insert(insertion,('RECOVERY',recovery))
        return evidence

    def test_recorded_native_ghost_stays_failed_but_later_control_is_retained(self):
        result=self.verify(self.ghost_evidence())
        self.assertEqual([row['status'] for row in result['outcomes']],['failed','passed'])
        self.assertEqual(len(result['evidence']['recoveries']),1)
        self.assertFalse(result['outcomes'][0]['outcome']['receipt']['currentExerciseCleared'])
        self.assertFalse(result['outcomes'][0]['outcome']['receipt']['tailRead'])

    def test_recovery_witness_rejects_nonfinite_changed_or_active_state(self):
        for key,value in (('nativeActions',1),('observerRecords',1),('observerActive',True),('queueEmpty',False),
                          ('failedCaseRecorded',False),('exactObjectMatched',False),('cleared',False),
                          ('mode','toolkit'),('before',clinical(float('inf'))),('after',clinical(100))):
            evidence=self.ghost_evidence()
            witness=next(row for marker,row in evidence[1] if marker=='RECOVERY')
            witness[key]=value
            with self.subTest(key=key):
                result=self.verify(evidence)
                self.assertTrue(any('recovery' in issue for issue in result['issues']))
        evidence=self.ghost_evidence()
        witness=next(row for marker,row in evidence[1] if marker=='RECOVERY')
        witness['inventoryAfter']['items'].pop()
        self.assertTrue(any('recovery' in issue for issue in self.verify(evidence)['issues']))

    def test_recovery_must_follow_published_failed_case(self):
        self.verify(self.ghost_evidence())
        path=self.root/'client1-launch.log';text=path.read_text()
        line=next(line for line in text.splitlines() if '[FITNESS_TEST] RECOVERY ' in line)
        path.write_text(line+'\n'+text.replace(line+'\n',''))
        result=fitness.verify(self.root,self.selection,{})
        self.assertTrue(any('recovery preceded' in issue for issue in result['issues']))

    def test_lua_recovery_refuses_live_or_unrecorded_or_unowned_state(self):
        try:
            from lupa import LuaRuntime
        except ImportError:
            self.skipTest('Lupa is required for recovery ownership checks')
        lua=LuaRuntime()
        lua.execute("""
            observer={records={},active=nil,clinical=function()return {xp=0}end}
            selection={mode='native'}
            package.preload['QueueFitnessObservation']=function()return observer end
            package.preload['QueueTestSelection']=function()return selection end
            isServer=function()return false end
            q={queue={},current=nil};ISTimedActionQueue={getTimedActionQueue=function()return q end}
            nativeCount=0;clearCalls=0
            ghost={};fit={current=ghost,getCurrentExe=function(self)return self.current end,
             setCurrentExercise=function(self,value)clearCalls=clearCalls+1;self.current=value end}
            player={getFitness=function()return fit end,hasTimedActions=function()return nativeCount>0 end,
             getCharacterActions=function()return {isEmpty=function()return nativeCount==0 end}end}
        """)
        fixture=lua.execute((ROOT/'tests/native_queue/fitness/shared/QueueFitnessFixture.lua').read_text())
        lua.globals().fixture=fixture
        lua.execute("""
            fixture.inventory=function()return {same='exact identities'}end
            local function reset()
             state={case='missing-dumbbell',player=player,verified=true,failedCaseRecorded=true,
              lastReceipt={currentExerciseCleared=false,records={}},strandedCurrent=ghost}
             fit.current=ghost;clearCalls=0;nativeCount=0;q.queue={};q.current=nil
             observer.active=nil;observer.records={};selection.mode='native'
            end
            local changes={
             function()state.verified=false end,function()state.failedCaseRecorded=false end,
             function()state.lastReceipt.currentExerciseCleared=true end,function()state.lastReceipt.records={{}}end,
             function()state.case='queued'end,function()selection.mode='toolkit'end,
             function()observer.active={}end,function()observer.records={{}}end,
             function()nativeCount=1 end,function()q.queue={{}}end,function()q.current={}end,
             function()fit.current={}end}
            for _,change in ipairs(changes)do
             reset();change();local before=fit.current
             assert(not pcall(fixture.recoverStranded,state),'unsafe recovery was accepted')
             assert(clearCalls==0 and fit.current==before,'rejected recovery changed native state')
            end
            reset();local witness=fixture.recoverStranded(state)
            assert(clearCalls==1 and fit.current==nil and witness.cleared and witness.exactObjectMatched)
            assert(state.lastReceipt.currentExerciseCleared==false and #state.lastReceipt.records==0)
        """)

    def test_host_startup_waits_for_tick_ready_identity_and_times_out_without_passing(self):
        try:
            from lupa import LuaRuntime
        except ImportError:
            self.skipTest('Lupa is required for startup callback checks')
        source=(ROOT/'tests/native_queue/fitness/client/ZZFitnessQueue.lua').read_text()
        for kind,role,timeout in (('mp','client1',False),('mp','client2',False),('sp','client1',False),('mp','client1',True),('mp','client1','peer')):
            lua=LuaRuntime()
            lua.globals().test_kind, lua.globals().test_role=kind,role
            lua.execute("""
                now=0;network=false;ingame=false;squareReady=false;onlineID=-1;username='temporary-name'
                optionCalls=0;usernameReads=0;rows={};logs={};handlers={};sent={};player=nil
                print=function(line)logs[#logs+1]=line end
                Events={}
                for _,name in ipairs({'OnGameStart','OnTick','OnServerCommand'})do
                 local event=name;Events[name]={Add=function(fn)handlers[event]=fn end}
                end
                PZSurvivorToolkit={ActionQueue={},ActionQueueOperations={},Settings={actionQueue=function()return true end}}
                PZAPI={ModOptions={getOptions=function()return {getOption=function()return {
                 setValue=function()optionCalls=optionCalls+1 end}end}end}}
                local config={kind=test_kind,mode='toolkit',cases={'empty'}}
                package.preload['QueueTestSelection']=function()return config end
                package.preload['QueueHealthEvents']=function()return {
                 emit=function(row)rows[#rows+1]=row end,encode=function()return '{}'end}end
                for _,name in ipairs({'PZSurvivorToolkit/ActionQueuePanel','ISUI/ISFitnessUI',
                 'Definitions/FitnessExercises','TimedActions/ISFitnessAction','QueueFitnessFixture','QueueFitnessObservation'})do
                 package.preload[name]=function()return {}end
                end
                getTimestampMs=function()return now end;isClient=function()return network end
                isIngameState=function()return ingame end;getPlayer=function()return player end
                getFileReader=function()return {readLine=function()return test_role end,close=function()end}end
                getCore=function()return {setOptionPauseOnFocusloss=function()end}end
                sendClientCommand=function(module,name,args)sent[#sent+1]={name=name,args=args}end
                local q={queue={}}
                ISTimedActionQueue={getTimedActionQueue=function()return q end}
                function installPlayer()
                 player={getSquare=function()return squareReady and {}or nil end,isDead=function()return false end,
                  getOnlineID=function()return onlineID end,getUsername=function()usernameReads=usernameReads+1;return username end,
                  isTimedActionInstant=function()return false end,setGhostMode=function()end,setAutoDrink=function()end,
                  hasTimedActions=function()return false end,tooDarkToRead=function()return true end}
                end
            """)
            lua.execute(source)
            lua.execute("""
                handlers.OnGameStart()
                assert(usernameReads==0 and #rows==0 and optionCalls==0,'OnGameStart touched incomplete network player')
                now=10;handlers.OnTick();assert(#rows==0 and optionCalls==0)
                installPlayer();now=20;handlers.OnTick();assert(#rows==0 and optionCalls==0)
                ingame=true;squareReady=true
            """)
            if timeout is True:
                lua.execute("""
                    network=true;onlineID=1;now=90001;handlers.OnTick()
                    assert(#rows==1 and rows[1].event=='error' and optionCalls==0)
                    for _,line in ipairs(logs)do assert(not line:find('COMPLETE'),'unready client falsely completed')end
                """)
            else:
                if kind=='mp':
                    lua.execute("""
                        now=30;handlers.OnTick();assert(optionCalls==0)
                        network=true;now=40;handlers.OnTick();assert(optionCalls==0)
                        onlineID=1;now=50;handlers.OnTick();assert(optionCalls==0)
                        username=test_role=='client1'and 'client2'or 'client1';now=60;handlers.OnTick();assert(optionCalls==0)
                        username=test_role
                    """)
                lua.execute("""
                    now=70;handlers.OnTick();assert(optionCalls==1,'ready actor was not initialized')
                    if test_role=='client1'then assert(#rows==1 and rows[1].event=='setup' and rows[1].actor==test_role)
                    else assert(#rows==0)end
                    now=80;handlers.OnTick();assert(optionCalls==1,'setup repeated')
                    for _,row in ipairs(rows)do assert(row.event~='error' and row.event~='complete')end
                    if test_kind=='mp'then
                     assert(#sent==1 and sent[1].name=='Ready' and sent[1].args.actor==test_role and sent[1].args.onlineID==onlineID)
                    end
                """)
                if kind=='mp' and timeout=='peer':
                    lua.execute("""
                        now=90071;handlers.OnTick()
                        assert(rows[#rows].event=='error' and rows[#rows].reason:find('peer readiness deadline'))
                        for _,line in ipairs(logs)do assert(not line:find('COMPLETE'))end
                    """)
                elif kind=='mp':
                    lua.execute("""
                        player.tooDarkToRead=function()return false end
                        for i=1,12 do now=100+i;handlers.OnTick()end
                        assert(#sent==1,'client prepared before server peers-ready acknowledgement')
                        local ids=test_role=='client1'and {client1=onlineID,client2=onlineID+1}or {client1=onlineID+1,client2=onlineID}
                        handlers.OnServerCommand('FitnessQueueTest','PeersReady',ids)
                        for i=1,12 do now=200+i;handlers.OnTick()end
                        if test_role=='client1'then assert(#sent==2 and sent[2].name=='Prepare')
                        else assert(#sent==1)end
                    """)

    def test_menu_readiness_waits_for_cached_moodle_without_changing_stats_or_enabling_button(self):
        try:
            from lupa import LuaRuntime
        except ImportError:
            self.skipTest('Lupa is required for native menu readiness checks')
        lua=LuaRuntime()
        lua.execute("""
            package.preload['QueueFitnessObservation']=function()return {}end
            CharacterStat={ENDURANCE='endurance'}
            MoodleType={ENDURANCE='endurance',HEAVY_LOAD='heavy',PAIN='pain'}
            endurance=1;cachedEndurance=4;cachedHeavy=0;cachedPain=0;updates=0;mutations=0
            local moodles={getMoodleLevel=function(self,kind)
             if kind=='endurance'then return cachedEndurance elseif kind=='heavy'then return cachedHeavy else return cachedPain end end}
            local stats={get=function()return endurance end,set=function()mutations=mutations+1 end}
            player={getMoodles=function()return moodles end,getStats=function()return stats end,
             getVariableBoolean=function()return false end,isSittingOnFurniture=function()return false end,
             getVehicle=function()return nil end,isClimbing=function()return false end,
             getFitness=function()return {getCurrentExe=function()return nil end}end}
            panel={player=player,selectedExe='bicepscurl',ok={enable=false},updateButtons=function(self)
             updates=updates+1;self.ok.enable=cachedEndurance<=2 and cachedHeavy<=2 and cachedPain<=3
             self.ok.tooltip=not self.ok.enable and 'Too exhausted for fitness' or nil
            end}
        """)
        fixture=lua.execute((ROOT/'tests/native_queue/fitness/shared/QueueFitnessFixture.lua').read_text())
        lua.globals().fixture=fixture
        lua.execute("""
            local gate={since=0}
            assert(fixture.menuReady(panel,nil,gate,0)=='waiting' and not panel.ok.enable)
            local blocked=fixture.menuDiagnostic(panel,'closed-ui-restore',0)
            assert(blocked.endurance==1 and blocked.enduranceMoodle==4 and blocked.tooltip=='Too exhausted for fitness'and blocked.status=='waiting')
            assert(fixture.menuReady(panel,nil,gate,100)=='waiting' and not panel.ok.enable)
            cachedEndurance=0
            assert(fixture.menuReady(panel,nil,gate,200)=='waiting' and panel.ok.enable)
            cachedPain=4
            assert(fixture.menuReady(panel,nil,gate,300)=='waiting' and not panel.ok.enable)
            cachedPain=0
            assert(fixture.menuReady(panel,nil,gate,400)=='waiting')
            assert(fixture.menuReady(panel,nil,gate,500)=='ready')
            assert(endurance==1 and mutations==0 and updates==6,'readiness changed clinical state or bypassed native update')
            cachedEndurance=4;gate={since=0}
            assert(fixture.menuReady(panel,nil,gate,15000)=='expired' and not panel.ok.enable)
            assert(endurance==1 and mutations==0)
        """)

    def test_server_waits_for_delayed_ready_peer_before_creating_books_and_diagnoses_peer_timeout(self):
        try:
            from lupa import LuaRuntime
        except ImportError:
            self.skipTest('Lupa is required for server peer readiness checks')
        lua=LuaRuntime()
        lua.execute("""
            now=0;created=0;prepared=0;peerPages=0;packets={};logs={};diagnostics={};handlers={}
            isServer=function()return true end;getTimestampMs=function()return now end
            print=function(line)logs[#logs+1]=line end
            Events={}
            for _,name in ipairs({'OnServerStarted','OnClientCommand','OnTick'})do
             local event=name;Events[name]={Add=function(fn)handlers[event]=fn end}
            end
            observer={records={},active=nil}
            local config={kind='mp',mode='toolkit',cases={'empty'}}
            package.preload['QueueTestSelection']=function()return config end
            package.preload['QueueFitnessObservation']=function()return observer end
            package.preload['QueueHealthEvents']=function()return {encode=function(row)diagnostics[#diagnostics+1]=row;return '{}'end}end
            package.preload['QueueFitnessFixture']=function()return {
             prepare=function(player,id)prepared=prepared+1;return {player=player,case=id,ids={case=id}}end,
             receipt=function(state)return {case=state.case,records={},currentExerciseCleared=true,serverStopSettled=true,tailRead=true}end}end
            Perks={Mechanics={}}
            local book={getID=function()return 123 end,getNumberOfPages=function()return 200 end,
             getFullType=function()return 'Base.BookMechanic1'end,setAlreadyReadPages=function()end}
            local inventory={AddItem=function()created=created+1;return book end}
            local function player(name,id)return {
             getUsername=function()return name end,getOnlineID=function()return id end,
             getCurrentSquare=function()return {}end,isDead=function()return false end,
             getInventory=function()return inventory end,setPerkLevelDebug=function()end,
             setAlreadyReadPages=function(self,kind,value)peerPages=value end,getAlreadyReadPages=function()return peerPages end,
             hasTimedActions=function()return false end,getCharacterActions=function()return {size=function()return 0 end,isEmpty=function()return true end}end,
             getFitness=function()return {getCurrentExe=function()return nil end}end}end
            actor=player('client1',1);peer=player('client2',2)
            getOnlinePlayers=function()return {size=function()return 2 end,get=function(self,i)return i==0 and actor or peer end}end
            sendServerCommand=function(player,module,name,args)packets[#packets+1]={actor=player:getUsername(),name=name,args=args}end
            sendAddItemToContainer=function()end
        """)
        lua.execute((ROOT/'tests/native_queue/fitness/server/ZZFitnessQueueServer.lua').read_text())
        lua.execute("""
            handlers.OnClientCommand('FitnessQueueTest','Ready',actor,{actor='client1',onlineID=1})
            handlers.OnTick();assert(created==0 and prepared==0 and #packets==0)
            handlers.OnClientCommand('FitnessQueueTest','Prepare',actor,{case='empty'})
            assert(created==0 and prepared==0 and packets[#packets].name=='Failed')
            handlers.OnClientCommand('FitnessQueueTest','Ready',peer,{actor='client1',onlineID=2})
            assert(packets[#packets].name=='Failed' and created==0)
            handlers.OnClientCommand('FitnessQueueTest','Ready',peer,{actor='client2',onlineID=3})
            assert(packets[#packets].name=='Failed' and created==0)
            now=400;handlers.OnClientCommand('FitnessQueueTest','Ready',peer,{actor='client2',onlineID=2})
            handlers.OnTick();assert(created==0 and prepared==0)
            assert(packets[#packets].name=='PeersReady' and packets[#packets-1].name=='PeersReady')
            assert(packets[#packets].args.client1==1 and packets[#packets].args.client2==2)
            handlers.OnClientCommand('FitnessQueueTest','Prepare',actor,{case='empty'})
            assert(created==1 and prepared==1 and packets[#packets].name=='Peer' and packets[#packets].actor=='client2')
            now=500;handlers.OnClientCommand('FitnessQueueTest','Verify',actor,{case='empty',clientQuiescent=true})
            now=600;handlers.OnTick();now=2700;handlers.OnTick()
            assert(packets[#packets].name~='Verified','peer reader was bypassed')
            now=30501;handlers.OnTick()
            assert(packets[#packets].name=='Failed')
            local report=diagnostics[#diagnostics]
            assert(report.waitingFor=='peer-reader' and report.peerRead==false and report.peerConnected==true)
            assert(report.hasTimedActions==false and report.characterActions==0 and report.currentExercise==false)
            assert(report.observerActive==false and report.observerRecords==0)
        """)

    def test_stage_freezes_shared_json_and_bootstrap_for_all_roles(self):
        runtime={'roles':{role:{'cache':str(self.root/role)} for role in ('server','client1','client2')}}
        self.selection.update(kind='mp',clients=2,languages=['EN','RU'],options={'mp_host':True})
        fitness.stage(ROOT,self.root,'/unused/game','/unused/jdk',self.selection,{},runtime)
        for role in runtime['roles']:
            lua=self.root/role/'mods/ActionQueueTest/42/media/lua'
            self.assertEqual((lua/'shared/QueueHealthEvents.lua').read_bytes(),(ROOT/'tests/native_queue/health/shared/QueueHealthEvents.lua').read_bytes())
            self.assertTrue((lua/'client/ZZStartup.lua').is_file())
        self.assertEqual(runtime['fixture']['server_ready'],'[FITNESS_TEST] SERVER_READY')


if __name__=='__main__':unittest.main()
