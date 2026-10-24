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
                regularity=dict(squats=regularity, pushups=regularity, bicepscurl=regularity, burpees=regularity),
                stiffness=dict(legs=stiffness, arms=stiffness, chest=stiffness, abs=stiffness),
                timers=dict(legs=100, arms=100, chest=100, abs=100))


def storage_snapshot(ids, inventory, endpoint='root', fetched=False):
    return dict(id=ids['bag'], kind='Base.Bag_Schoolbag', favorite=True, endpoint=endpoint, occurrences=1,
        contents=[dict(row) for row in inventory['items'] if row['container']==ids['bag'] and (not fetched or row['id']!=ids['dumbbell'])],
        world=dict(x=1,y=2,z=0,linked=True) if endpoint=='world' else False)


def ground_inventory(ids, inventory):
    value=copy.deepcopy(inventory)
    value['items']=[dict(row,container='root') if row['id']==ids['dumbbell'] else row for row in value['items']
        if row['id']!=ids['bag'] and (row['container']!=ids['bag'] or row['id']==ids['dumbbell'])]
    value.update(primary=False,secondary=False,worn=[row for row in value['worn'] if row['id']!=ids['bag']])
    return value


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
            if case in fitness.BORROWED_CASES:
                inventory.update(primary=ids['hammer'], secondary=ids['screwdriver'], worn=[dict(id=ids['bag'], location='Back')])
                next(row for row in inventory['items'] if row['id']==ids['dumbbell'])['container']=ids['bag']
            if case in fitness.RESTORATION_CASES:
                next(row for row in inventory['items'] if row['id']==ids['front'])['container']=ids['bag']
            if case in fitness.BORROWED_CASES:
                types = dict(front='Base.BookCarpentry1', tail='Base.BookFirstAid1', bag='Base.Bag_Schoolbag',
                             hammer='Base.Torch' if case in fitness.RESTORATION_CASES else 'Base.Hammer', screwdriver='Base.Screwdriver', dumbbell='Base.DumbBell')
                for item in inventory['items']:item['kind']=types[next(key for key,value in ids.items() if value==item['id'])]
            prep = dict(case=case, items=ids, inventory=inventory, before=clinical())
            if case in fitness.BORROWED_CASES:
                prep['activation']=[]
                prep['storage']=storage_snapshot(ids,inventory);prep['storage']['favorite']=case in fitness.RESTORATION_CASES
            if case in fitness.RESTORATION_CASES:
                prep['activation']={str(ids['hammer']):True};prep['storage']=storage_snapshot(ids,inventory)
            if mp:
                prep.update(peerBook=1000+n, peerOnlineID=2)
                peers.append(dict(event='case', suite='fitness', kind='mp', mode=mode, actor='client2',
                                  id=case, book=prep['peerBook'], read=True, queueDrained=True))
            final = copy.deepcopy(inventory)
            if case == 'missing-dumbbell':
                final['items'] = [row for row in final['items'] if row['id'] != ids['dumbbell']]
            exercises = fitness._expected_exercises(case, mode)
            minutes = 30 if case == 'burpees-30' else 10
            records = []
            for i, exercise in enumerate(exercises):
                start = i*700000
                end = start + (100000 if case in ('active-cancel', 'active-cancel-restore') else minutes * 60000 + 1)
                records.append(dict(exercise=exercise, minutes=minutes, maxTime=5000000, reps=10,
                    startMS=start, stopMS=end, lastRepMS=start+1000, before=clinical(), after=clinical(10,.9,1,1),
                    minEndurance=.8, lastRep=clinical(10,.8,1,1), currentExerciseCleared=True,
                    serverStopReturned=True, previousStopSettled=True))
            if case in fitness.BORROWED_CASES:
                for record in records:
                    start_inventory=copy.deepcopy(inventory)
                    start_inventory.update(primary=ids['dumbbell'],secondary=False,worn=[])
                    next(row for row in start_inventory['items'] if row['id']==ids['dumbbell'])['container']='root'
                    if case in fitness.RESTORATION_CASES:
                        start_inventory=ground_inventory(ids,inventory);start_inventory.update(primary=ids['dumbbell'])
                        record['startStorage']=storage_snapshot(ids,inventory,'world',True)
                    record['startEquipment']=start_inventory
            receipt = dict(case=case, inventory=final, before=prep['before'], clinical=clinical(10,.9,1,1) if records else clinical(),
                records=records, violations=[], tailRead=True, frontRead=case not in fitness.IMMEDIATE_CASES, currentExerciseCleared=True,
                serverStopSettled=True, peerConnected=True, removed=ids['dumbbell'] if case=='missing-dumbbell' else False,
                serverSettleMilliseconds=2000)
            if mp:
                receipt.update(peerRead=True, peerBook=prep['peerBook'], peerOnlineID=prep['peerOnlineID'])
            command = dict(menuDispatched=True, nativeDurations=True, minutes=minutes, frontMinutes=0 if case in fitness.IMMEDIATE_CASES else 12,
                waitingNoExercise=True, waitingNoClinicalEffects=True, waitMS=720000,
                activeObserved=bool(exercises), activeCancelled=case in ('active-cancel','active-cancel-restore'), pendingCancelled=mode=='toolkit' and case=='pending-cancel',
                reordered=mode=='toolkit' and case=='pending-reorder', closedUI=case=='closed-ui-restore',
                queueDrained=True, clientCurrentExerciseCleared=True, clientInventory=final, startedOrder=exercises,
                activeAcks=['token'+str(i) for i in range(len(exercises))],
                terminalAcks=[dict(token='token'+str(i), state='canceled') for i in range(len(exercises))])
            command['initialClinical']=copy.deepcopy(prep['before'])
            command['progressSamples']=[dict(exercise=exercise,total=minutes,elapsed=2,fraction=2/minutes,
                startMS=i*700000,sampleMS=i*700000+120000,label=f'2.0 / {minutes} minutes') for i,exercise in enumerate(exercises)] if mode=='toolkit' else []
            if case=='burpees-30' and mode=='toolkit':command['durationStopDelayMilliseconds']=0
            if case=='pending-reorder' and mode=='toolkit':command['reorderedTailBeforeStart']=True
            if case in fitness.BORROWED_CASES and mode=='toolkit':
                command.update(borrowedTransferProgress=True,borrowedTool=ids['dumbbell'],borrowedSourceBag=ids['bag'])
            if case in fitness.BORROWED_CASES:
                command.update(beforeTail=dict(inventory=copy.deepcopy(final),activation=copy.deepcopy(prep['activation']),nativeClock=1000000,callback='ISBaseTimedAction.begin'),
                               cancelCallback='ISFitnessUI:CANCEL' if mode=='native' else 'ActionQueue.cancelOperation',
                               clientActivation=copy.deepcopy(prep['activation']),clientStorage=copy.deepcopy(prep['storage']))
                receipt['activation']=copy.deepcopy(prep['activation']);receipt['storage']=copy.deepcopy(prep['storage'])
                command['beforeTail']['storage']=copy.deepcopy(prep['storage'])
                placed=mode=='native' or case!='pickup-cancel-restore'
                receipt['placements']=[dict(callback='ISDropWorldItemAction.complete',succeeded=True,nativeClock=800000,
                    storage=dict(storage_snapshot(ids,inventory,'world',True),favorite=prep['storage']['favorite']),inventory=ground_inventory(ids,inventory))] if placed else []
                if mode=='native':
                    # P4 restores after this reader; native timing and callbacks stay intact.
                    boundary=command['beforeTail']
                    boundary['inventory']=ground_inventory(ids,inventory);boundary['inventory'].update(primary=ids['dumbbell'])
                    boundary['storage']=dict(storage_snapshot(ids,inventory,'world',True),favorite=prep['storage']['favorite'])
                    if case in fitness.RESTORATION_CASES:boundary['activation'][str(ids['hammer'])]=False
                if mode=='toolkit':
                    command.update(confirmedPickup=True,confirmedReturn=True,returnCount=1,propEquipObserved=case=='active-cancel-restore',confirmedPreparation=case=='active-cancel-restore',
                        settlement=dict(phase='cleanup',steps=[dict(phase='prepare',state='earned',started=True,kind='ISDropWorldItemAction',
                            itemId=ids['bag'],itemType='Base.Bag_Schoolbag',observedPreparation=True)] if placed else [],
                            borrowings=[dict(id=ids['dumbbell'],fullType='Base.DumbBell',state='completed')]))
                if mode=='toolkit':
                    command['returnStarts']=[dict(ordinal=1,id=ids['dumbbell'],kind='Base.DumbBell',source='root',
                        destination=ids['bag'],callback='ISBaseTimedAction.begin',nativeClock=900000)]
                if mode=='toolkit':
                    command['recoveryStarts']=[dict(ordinal=1,id=ids['bag'],kind='Base.Bag_Schoolbag',source='world',destination='root',
                        callback='ISBaseTimedAction.begin',nativeClock=850000,storage=dict(storage_snapshot(ids,inventory,'world',True),favorite=prep['storage']['favorite']),
                        inventory=ground_inventory(ids,inventory))] if placed else []
                    command['recoverySettlements']=[dict(steps=[dict(plannedTransfer=True,transferDirection='pickup',kind='ISInventoryTransferAction',
                        itemId=ids['bag'],itemType='Base.Bag_Schoolbag',state='earned',started=True,phase='cleanup')])] if placed else []
                if case=='active-cancel-restore' and mode=='toolkit':
                    command['preparationAtCancel']=dict(steps=[dict(observedPreparation=True,kind=kind,itemId=ids[name],
                        itemType=types[name],state='earned',started=True) for kind,name in (('ISInventoryTransferAction','dumbbell'),('ISUnequipAction','hammer'),
                        ('ISUnequipAction','screwdriver'),('ISUnequipAction','bag'),('ISDropWorldItemAction','bag'),('ISEquipWeaponAction','dumbbell'))])
                if case=='pickup-cancel-restore':
                    command.update(pickupCancelInventory=copy.deepcopy(inventory),pickupCancelStorage=copy.deepcopy(prep['storage']))
                    command.update(pickupCancelled=True,pickupCancel=dict(id=ids['dumbbell'],kind='Base.DumbBell',source=ids['bag'],
                        destination='root',started=True,progress=.25,transaction=5 if mp else 0))
                if case=='placement-cancel-restore':
                    cancel_inventory=copy.deepcopy(inventory)
                    next(row for row in cancel_inventory['items'] if row['id']==ids['dumbbell'])['container']='root'
                    cancel_inventory.update(primary=False,secondary=False,worn=[])
                    command.update(placementCancelled=True,placementCancel=dict(id=ids['bag'],kind='Base.Bag_Schoolbag',started=True,isPlaceItem=True,
                        progress=.25,square=dict(x=1,y=2,z=0),storage=storage_snapshot(ids,inventory,'root',True),inventory=cancel_inventory))
                if mp:
                    receipt['tailStart']=dict(id=ids['tail'],kind='Base.BookFirstAid1',callback='ISReadABook.serverStart',
                        workouts=len(exercises),observerActive=False,inventory=copy.deepcopy(command['beforeTail']['inventory']),
                        activation=copy.deepcopy(command['beforeTail']['activation']),storage=copy.deepcopy(command['beforeTail']['storage']))
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


    def test_borrowed_cancel_requires_native_progress_confirmed_return_and_tail_boundary(self):
        for case in fitness.RESTORATION_CASES:
            self.selection['cases']=[case]
            for change in ('pickup','return','borrowing','return-count','duplicate-return','boundary-hands','boundary-container','activation','cancel-callback'):
                evidence=copy.deepcopy(self.evidence());command=evidence[0][1]['command']
                if change=='pickup':command['confirmedPickup']=False
                elif change=='return':command['confirmedReturn']=False
                elif change=='borrowing':command['settlement']['borrowings'][0]['state']='active'
                elif change=='return-count':command['settlement']['borrowings']*=2
                elif change=='duplicate-return':command['returnCount']=2
                elif change=='boundary-hands':command['beforeTail']['inventory']['primary']=False
                elif change=='boundary-container':command['beforeTail']['inventory']['items'][-1]['container']='root'
                elif change=='activation':command['beforeTail']['activation']={}
                else:command['cancelCallback']='fixture-synthetic-cancel'
                with self.subTest(case=case,change=change):self.assertTrue(self.verify(evidence)['issues'])

    def test_closed_ui_normal_cleanup_requires_shared_return_before_reader(self):
        for kind in ('sp','mp'):
            self.selection.update(kind=kind,clients=2 if kind=='mp' else 1,languages=['EN','RU'] if kind=='mp' else ['EN'],
                options={'mp_host':True} if kind=='mp' else {},cases=['closed-ui-restore'])
            self.assertEqual(self.verify()['issues'],[])
            for change in ('late-prop','late-start','missing-start','duplicate-return','wrong-bag','unconfirmed-return','active-loan',
                           'wrong-content-type','missing-recovery-receipt','wrong-drop','authority-late-prop','authority-content'):
                if change.startswith('authority-') and kind!='mp':continue
                evidence=copy.deepcopy(self.evidence());row=evidence[0][1];command=row['command'];prep=evidence[1][0][1]
                final=copy.deepcopy(row['receipt']['inventory'])
                if change=='late-prop':
                    next(value for value in command['beforeTail']['inventory']['items'] if value['id']==prep['items']['dumbbell'])['container']='root'
                    command['beforeTail']['storage']['contents']=[]
                elif change=='late-start':command['returnStarts'][0]['nativeClock']=command['beforeTail']['nativeClock']+1
                elif change=='missing-start':command['returnStarts']=[]
                elif change=='duplicate-return':command['returnCount']=2;command['returnStarts']*=2
                elif change=='wrong-bag':command['returnStarts'][0]['destination']+=100
                elif change=='unconfirmed-return':command['confirmedReturn']=False
                elif change=='active-loan':command['settlement']['borrowings'][0]['state']='active'
                elif change=='wrong-content-type':command['beforeTail']['storage']['contents'][0]['kind']='Base.Pencil'
                elif change=='missing-recovery-receipt':command['recoverySettlements']=[]
                elif change=='wrong-drop':row['receipt']['placements'][0]['storage']['id']+=100
                elif change=='authority-late-prop':
                    next(value for value in row['receipt']['tailStart']['inventory']['items'] if value['id']==prep['items']['dumbbell'])['container']='root'
                else:row['receipt']['tailStart']['storage']['contents']=[]
                with self.subTest(kind=kind,change=change):
                    self.assertEqual(row['receipt']['inventory'],final,'regression must retain exact late final restoration')
                    self.assertTrue(self.verify(evidence)['issues'])

    def test_closed_ui_native_control_retains_real_pre_reader_differences(self):
        for kind in ('sp','mp'):
            self.selection.update(mode='native',kind=kind,clients=2 if kind=='mp' else 1,languages=['EN','RU'] if kind=='mp' else ['EN'],
                options={'mp_host':True} if kind=='mp' else {},cases=['closed-ui-restore'])
            evidence=self.evidence();self.assertEqual(self.verify(evidence)['issues'],[])
            row=evidence[0][1];prep=evidence[1][0][1]
            self.assertEqual(next(value for value in prep['inventory']['items'] if value['id']==prep['items']['hammer'])['kind'],'Base.Hammer')
            self.assertFalse(prep['storage']['favorite']);self.assertEqual(row['command']['frontMinutes'],12)
            self.assertNotEqual(row['command']['beforeTail']['inventory'],prep['inventory'])
            self.assertEqual(row['receipt']['inventory'],prep['inventory'])
            row['receipt']['records'][0]['stopMS']=row['receipt']['records'][0]['startMS']+1
            self.assertTrue(self.verify(evidence)['issues'],'native constructor/duration failure must remain failed')

    def test_active_borrowed_cancel_requires_all_exact_native_preparation_effects(self):
        self.selection['cases']=['active-cancel-restore']
        for change in ('unearned','missing-step','wrong-id','wrong-type','unstarted','not-observed'):
            evidence=copy.deepcopy(self.evidence());steps=evidence[0][1]['command']['preparationAtCancel']['steps']
            if change=='unearned':steps[0]['state']='pending'
            elif change=='missing-step':steps.pop()
            elif change=='wrong-id':steps[0]['itemId']+=99
            elif change=='wrong-type':steps[0]['itemType']='Base.Hammer'
            elif change=='unstarted':steps[0]['started']=False
            else:steps[0]['observedPreparation']=False
            with self.subTest(change=change):self.assertTrue(self.verify(evidence)['issues'])

    def test_pickup_cancel_rejects_nonstarted_transaction_replayed_workout_and_prop_equip(self):
        self.selection.update(kind='mp',clients=2,languages=['EN','RU'],options={'mp_host':True},cases=['pickup-cancel-restore'])
        for change in ('progress','started','transaction','wrong-id','prop-equip','workout','authority-tail'):
            evidence=copy.deepcopy(self.evidence());command=evidence[0][1]['command']
            if change=='progress':command['pickupCancel']['progress']=0
            elif change=='started':command['pickupCancel']['started']=False
            elif change=='transaction':command['pickupCancel']['transaction']=0
            elif change=='wrong-id':command['pickupCancel']['id']+=1
            elif change=='prop-equip':command['propEquipObserved']=True
            elif change=='workout':command['startedOrder']=['bicepscurl']
            else:evidence[1][-1][1]['tailStart']['inventory']['primary']=False
            with self.subTest(change=change):self.assertTrue(self.verify(evidence)['issues'])

    def test_native_borrowed_controls_restore_after_reader_and_keep_native_boundary_differences(self):
        for kind in ('sp','mp'):
            self.selection.update(mode='native',kind=kind,clients=2 if kind=='mp' else 1,
                languages=['EN','RU'] if kind=='mp' else ['EN'],options={'mp_host':True} if kind=='mp' else {},
                cases=list(fitness.RESTORATION_CASES))
            evidence=self.evidence();result=self.verify(evidence)
            with self.subTest(kind=kind):
                self.assertEqual(result['issues'],[])
                self.assertEqual([len(row['outcome']['receipt']['records']) for row in result['outcomes'][:3]],[1,1,1])
                for row in evidence[0][1:-1]:
                    command=row['command'];prep=next(value for marker,value in evidence[1] if marker=='PREPARED' and value['case']==row['id'])
                    self.assertEqual(command['cancelCallback'],'ISFitnessUI:CANCEL')
                    self.assertEqual(row['receipt']['inventory'],prep['inventory'])
                    self.assertEqual(row['receipt']['activation'],prep['activation'])
                    self.assertNotEqual(command['beforeTail']['inventory'],prep['inventory'])
                    self.assertNotEqual(command['beforeTail']['activation'],prep['activation'])

    def test_native_borrowed_controls_reject_unreturned_final_prop_or_wrong_activation(self):
        for case in fitness.RESTORATION_CASES:
            self.selection.update(mode='native',cases=[case])
            for change in ('prop-root','authority-activation','client-activation'):
                evidence=copy.deepcopy(self.evidence());row=evidence[0][1]
                prep=evidence[1][0][1]
                if change=='prop-root':
                    for inventory in (row['receipt']['inventory'],row['command']['clientInventory']):
                        next(item for item in inventory['items'] if item['id']==prep['items']['dumbbell'])['container']='root'
                elif change=='authority-activation':row['receipt']['activation'][str(prep['items']['hammer'])]=False
                else:row['command']['clientActivation'][str(prep['items']['hammer'])]=False
                with self.subTest(case=case,change=change):
                    issues=self.verify(evidence)['issues']
                    self.assertTrue(any(('exact inventory' if change=='prop-root' else 'settled equipment activation') in issue for issue in issues))

    def test_return_start_witness_rejects_wrong_identity_endpoint_duplicates_and_late_start(self):
        self.selection.update(kind='mp',clients=2,languages=['EN','RU'],options={'mp_host':True},cases=['pickup-cancel-restore'])
        for change in ('absent','duplicate','wrong-id','wrong-type','wrong-source','wrong-bag','wrong-callback','late','nonfinite'):
            evidence=copy.deepcopy(self.evidence());command=evidence[0][1]['command'];starts=command['returnStarts']
            if change=='absent':command.pop('returnStarts')
            elif change=='duplicate':starts.append(dict(starts[0],ordinal=2))
            elif change=='wrong-id':starts[0]['id']+=99
            elif change=='wrong-type':starts[0]['kind']='Base.Hammer'
            elif change=='wrong-source':starts[0]['source']='floor'
            elif change=='wrong-bag':starts[0]['destination']+=99
            elif change=='wrong-callback':starts[0]['callback']='fixture-poll'
            elif change=='late':starts[0]['nativeClock']=command['beforeTail']['nativeClock']+1
            else:starts[0]['nativeClock']=float('nan')
            with self.subTest(change=change):self.assertTrue(self.verify(evidence)['issues'])

    def test_lua_native_return_begin_observes_recreated_host_items_without_polling_or_completing(self):
        try:
            from lupa import LuaRuntime
        except ImportError:
            self.skipTest('Lupa is required for native return begin checks')
        lua=LuaRuntime()
        lua.execute("""
            package.preload['QueueFitnessObservation']=function()return {clock=function()return 900000 end}end
            ISInventoryTransferAction={};root={items={}}
            function root:getItemById(id)return self.items[id]end
            player={getInventory=function()return root end}
            function item(id,kind,container)
             return {getID=function()return id end,getFullType=function()return kind end,getContainer=function()return container end}
            end
            local oldBagContainer={};local liveBagContainer={}
            oldProp=item(10,'Base.DumbBell',root);liveProp=item(10,'Base.DumbBell',root)
            oldBag=item(20,'Base.Bag_Schoolbag',root);oldBag.getItemContainer=function()return oldBagContainer end
            liveBag=item(20,'Base.Bag_Schoolbag',root);liveBag.getItemContainer=function()return liveBagContainer end
            root.items[10]=liveProp;root.items[20]=liveBag
            state={player=player,ids={items={dumbbell=10,bag=20}},items={dumbbell=oldProp,bag=oldBag}}
            function action()
             return setmetatable({Type='ISInventoryTransferAction',character=player,item=item(10,'Base.DumbBell',root),
              srcContainer=root,destContainer=liveBagContainer,isStarted=function()error('must not poll native start')end},ISInventoryTransferAction)
            end
        """)
        lua.globals().fixture=lua.execute((ROOT/'tests/native_queue/fitness/shared/QueueFitnessFixture.lua').read_text())
        lua.execute("""
            local seen={};local first=action();local witness=fixture.observeReturnStart(state,first,seen)
            assert(witness and witness.id==10 and witness.destination==20 and witness.callback=='ISBaseTimedAction.begin')
            assert(first.item~=state.items.dumbbell and root.items[20]~=state.items.bag,'test needs replaced Host replicas')
            -- A native transfer may complete before the next fixture tick. The start
            -- witness remains true; this helper never fabricates its completion.
            root.items[10]=nil
            assert(not fixture.observeReturnStart(state,first,seen))
            assert(seen[first] and witness.nativeClock==900000 and root.items[10]==nil)
            root.items[10]=liveProp
            local second=action();assert(fixture.observeReturnStart(state,second,seen),'distinct second native begin must be observable')
            assert(seen[first] and seen[second],'a duplicate distinct return cannot collapse into one witness')
            for _,change in ipairs({
             function(a)a.character={}end,function(a)a.item=item(11,'Base.DumbBell',root)end,
             function(a)a.item=item(10,'Base.Hammer',root)end,function(a)a.srcContainer={}end,
             function(a)a.destContainer=state.items.bag:getItemContainer()end,function(a)setmetatable(a,{})end
            })do local candidate=action();change(candidate)
             assert(not fixture.observeReturnStart(state,candidate,{}),'wrong actor/identity/type/endpoint/class counted')
            end
        """)

    def test_lua_world_bag_witness_uses_actual_linked_object_contents_and_recreated_recovery_item(self):
        try:
            from lupa import LuaRuntime
        except ImportError:
            self.skipTest('Lupa is required for world-bag recovery checks')
        lua=LuaRuntime()
        lua.execute("""
            package.preload['QueueFitnessObservation']=function()return {clock=function()return 100 end}end
            ISInventoryTransferAction={}
            function list(values)return {values=values,size=function(self)return #self.values end,get=function(self,i)return self.values[i+1]end}end
            function item(id,kind,container)
             return {getID=function()return id end,getFullType=function()return kind end,getContainer=function()return container end}
            end
            instanceof=function(value,kind)return value and value.class==kind end
            root={items=list({})};function root:getItems()return self.items end
            function root:getItemById(id)for _,value in ipairs(self.items.values)do if value:getID()==id then return value end end end
            floor={getType=function()return 'floor'end};bagContainer={items=list({})}
            function bagContainer:getItems()return self.items end
            local bagParent=floor
            bag=item(20,'Base.Bag_Schoolbag',floor);bag.class='InventoryContainer'
            bag.getContainer=function()return bagParent end;bag.getItemContainer=function()return bagContainer end
            bag.isFavorite=function()return true end
            book=item(30,'Base.BookCarpentry1',bagContainer);bagContainer.items.values={book}
            prop=item(10,'Base.DumbBell',root);root.items.values={prop}
            objects=list({});square={getX=function()return 5 end,getY=function()return 6 end,getZ=function()return 0 end,
             getWorldObjects=function()return objects end}
            world={class='IsoWorldInventoryObject',getItem=function()return bag end,getSquare=function()return square end}
            bag.getWorldItem=function()return bagParent==floor and world or nil end;objects.values={world}
            player={getInventory=function()return root end,getCurrentSquare=function()return square end,
             getPrimaryHandItem=function()end,getSecondaryHandItem=function()end,getWornItems=function()return list({})end}
            state={player=player,ids={items={bag=20,dumbbell=10}},items={bag={oldReplica=true}}}
            function recover()
             return setmetatable({Type='ISInventoryTransferAction',character=player,item=item(20,'Base.Bag_Schoolbag',floor),
              srcContainer=floor,destContainer=root,isStarted=function()error('no polling')end},ISInventoryTransferAction)
            end
            function finishPickup()objects.values={};root.items.values={prop,bag};bagParent=root end
        """)
        lua.globals().fixture=lua.execute((ROOT/'tests/native_queue/fitness/shared/QueueFitnessFixture.lua').read_text())
        lua.execute("""
            local snapshot=fixture.storage(player,20)
            assert(snapshot.endpoint=='world' and snapshot.occurrences==1 and snapshot.favorite and snapshot.world.linked)
            assert(#snapshot.contents==1 and snapshot.contents[1].id==30 and snapshot.contents[1].container==20)
            local seen={};local action=recover();local witness=fixture.observeRecoveryStart(state,action,seen)
            assert(witness and witness.id==20 and witness.storage.world.linked and witness.storage.favorite)
            assert(action.item~=bag and #witness.inventory.items==1 and witness.inventory.items[1].id==10)
            world.getSquare=function()return {}end
            assert(not fixture.storage(player,20).world.linked)
            world.getSquare=function()return square end;objects.values={world,world}
            assert(fixture.storage(player,20).occurrences==2 and not fixture.observeRecoveryStart(state,recover(),{}))
            objects.values={};assert(fixture.storage(player,20).occurrences==0)
            objects.values={world};finishPickup()
            assert(not fixture.observeRecoveryStart(state,action,seen),'same action counted twice')
            assert(fixture.storage(player,20).endpoint=='root' and fixture.storage(player,20).favorite)
            assert(#fixture.storage(player,20).contents==1 and fixture.storage(player,20).contents[1].id==30)
        """)

    def test_native_sp_placement_observer_accepts_real_lifecycle_begin_with_queue_disabled(self):
        try:
            from lupa import LuaRuntime
        except ImportError:
            self.skipTest('Lupa is required for queue-disabled placement observation')
        source=(ROOT/'tests/native_queue/fitness/client/ZZFitnessQueue.lua').read_text()
        start=source.index("assert(T.ActionQueueLifecycle.registerObserver('fitness-independent-tail'")
        end=source.index("),'fitness native reader boundary observer unavailable')",start)+len("),'fitness native reader boundary observer unavailable')")
        lua=LuaRuntime()
        lua.execute("""
            package.preload['TimedActions/ISQueueActionsAction']=function()return {}end
            ISQueueActionsAction={start=function()end};ISDropWorldItemAction={}
            queueEnabled=false;PZSurvivorToolkit={Settings={actionQueue=function()return queueEnabled end}}
            ISTimedActionQueue={queues={}};isClient=function()return false end;isServer=function()return false end
            player={};state={player=player,ids={items={bag=20}}};command={};O={placements={}}
            F={borrowedCase=function(id)return id=='placement-cancel-restore'or id=='closed-ui-restore'end,
             placement=function(_,id,callback,succeeded)return {id=id,callback=callback,succeeded=succeeded}end}
            caseID='placement-cancel-restore';case=function()return caseID end
            function action()
             return setmetatable({Type='ISDropWorldItemAction',character=player,item={
              getID=function()return 20 end,getFullType=function()return 'Base.Bag_Schoolbag'end}},ISDropWorldItemAction)
            end
        """)
        lua.globals().T=lua.globals().PZSurvivorToolkit
        lua.execute((ROOT/'PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueLifecycle.lua').read_text())
        lua.execute(source[start:end])
        lua.execute("""
            local lifecycle=T.ActionQueueLifecycle
            for _,id in ipairs({'placement-cancel-restore','closed-ui-restore'})do caseID=id;O.placements={}
            for _,enabled in ipairs({false,true})do
             queueEnabled=enabled;local exact=action();local before=#O.placements
             assert(lifecycle.begin(exact,'perform'),'native perform finish observation must remain active with queue disabled')
             lifecycle.finish(exact,'perform',true);assert(#O.placements==before,'perform is not completed placement')
             assert(lifecycle.begin(exact,'complete'),'native complete finish observation must remain active with queue disabled')
             lifecycle.finish(exact,'complete',true)
            end
            assert(#O.placements==2 and O.placements[1].id==20 and O.placements[1].succeeded)
            queueEnabled=false
            for _,change in ipairs({function(a)a.character={}end,function(a)a.item.getID=function()return 21 end end,
             function(a)a.item.getFullType=function()return 'Base.Pencil'end end,
             function(a)setmetatable(a,{})end,function(a)a.Type='ISUnequipAction'end})do
             local wrong=action();change(wrong);assert(not lifecycle.begin(wrong,'complete'),'unrelated callback accepted')
            end
            assert(not lifecycle.begin(action(),'stop')and not lifecycle.begin(nil,'complete'))
            end
        """)

    def test_world_bag_and_contents_require_exact_native_effect_and_completed_recovery(self):
        self.selection.update(kind='mp',clients=2,languages=['EN','RU'],options={'mp_host':True},cases=['placement-cancel-restore'])
        for change in ('no-placement','failed-callback','unlinked-world','wrong-world-bag','duplicate-bag','lost-content','changed-content-type',
                       'lost-root-prop','favourite-cleared','duplicate-recovery','no-receipt','unearned-recovery','wrong-direction','wrong-recovery-id',
                       'drop-not-earned','early-recovery','prop-equip','replayed-workout'):
            evidence=copy.deepcopy(self.evidence());command=evidence[0][1]['command'];receipt=evidence[0][1]['receipt']
            if change=='no-placement':receipt['placements']=[]
            elif change=='failed-callback':receipt['placements'][0]['succeeded']=False
            elif change=='unlinked-world':receipt['placements'][0]['storage']['world']['linked']=False
            elif change=='wrong-world-bag':receipt['placements'][0]['storage']['id']+=99
            elif change=='duplicate-bag':receipt['placements'][0]['storage']['occurrences']=2
            elif change=='lost-content':receipt['placements'][0]['storage']['contents']=[]
            elif change=='changed-content-type':receipt['placements'][0]['storage']['contents'][0]['kind']='Base.Pencil'
            elif change=='lost-root-prop':receipt['placements'][0]['inventory']['items'].pop()
            elif change=='favourite-cleared':command['beforeTail']['storage']['favorite']=False
            elif change=='duplicate-recovery':command['recoveryStarts']*=2
            elif change=='no-receipt':command['recoverySettlements']=[]
            elif change=='unearned-recovery':command['recoverySettlements'][0]['steps'][0]['state']='pending'
            elif change=='wrong-direction':command['recoverySettlements'][0]['steps'][0]['transferDirection']='return'
            elif change=='wrong-recovery-id':command['recoverySettlements'][0]['steps'][0]['itemId']+=99
            elif change=='drop-not-earned':command['settlement']['steps'][0]['state']='pending'
            elif change=='early-recovery':command['recoveryStarts'][0]['nativeClock']=receipt['placements'][0]['nativeClock']-1
            elif change=='prop-equip':command['propEquipObserved']=True
            else:command['startedOrder']=['bicepscurl']
            with self.subTest(change=change):self.assertTrue(self.verify(evidence)['issues'])

    def test_placement_cancel_requires_actual_positive_native_progress_exact_square_and_favourite(self):
        self.selection['cases']=['placement-cancel-restore']
        for change in ('not-canceled','progress','not-started','not-place','wrong-square','wrong-bag','favourite','missing-source-content'):
            evidence=copy.deepcopy(self.evidence());command=evidence[0][1]['command'];placement=command['placementCancel']
            if change=='not-canceled':command['placementCancelled']=False
            elif change=='progress':placement['progress']=0
            elif change=='not-started':placement['started']=False
            elif change=='not-place':placement['isPlaceItem']=False
            elif change=='wrong-square':placement['square']['x']+=1
            elif change=='wrong-bag':placement['id']+=1
            elif change=='favourite':placement['storage']['favorite']=False
            else:placement['storage']['contents']=[]
            with self.subTest(change=change):self.assertTrue(self.verify(evidence)['issues'])

    def test_pickup_cancel_precedes_hand_removal_and_bag_placement(self):
        self.selection['cases']=['pickup-cancel-restore']
        for change in ('hand','worn','placed','recovery'):
            evidence=copy.deepcopy(self.evidence());command=evidence[0][1]['command']
            if change=='hand':command['pickupCancelInventory']['primary']=False
            elif change=='worn':command['pickupCancelInventory']['worn']=[]
            elif change=='placed':evidence[0][1]['receipt']['placements']=[{}]
            else:command['recoveryStarts']=[{}]
            with self.subTest(change=change):self.assertTrue(self.verify(evidence)['issues'])

    def test_burpees_duration_stop_rejects_missing_or_delayed_native_removal(self):
        self.selection['cases'] = ['burpees-30']
        for delay in (None, -1, 5000, 30000, float('nan')):
            with self.subTest(delay=delay):
                evidence = self.evidence()
                evidence[0][1]['command']['durationStopDelayMilliseconds'] = delay
                self.assertTrue(any('stop remained active' in issue for issue in self.verify(evidence)['issues']))

    def test_original_regularity_receipts_remain_valid_for_existing_cases(self):
        self.selection['cases'] = ['empty']
        evidence = self.evidence()
        def legacy(value):
            if isinstance(value, dict):
                if 'regularity' in value:
                    value['regularity'].pop('burpees', None)
                for child in value.values():legacy(child)
            elif isinstance(value, list):
                for child in value:legacy(child)
        legacy(evidence[0]);legacy(evidence[1])
        self.assertEqual(self.verify(evidence)['issues'], [])

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
        self.assertGreater(source.index('ISReadABook.serverStart='),guard)
        self.assertGreater(source.index('ISDropWorldItemAction.complete='),guard)
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
                ISDropWorldItemAction={complete=function()calls.dropComplete=(calls.dropComplete or 0)+1;return true end};package.preload['TimedActions/ISDropWorldItemAction']=function()return ISDropWorldItemAction end
                ISReadABook={serverStart=function()calls.readStart=(calls.readStart or 0)+1;return 'native-reader-result'end};package.preload['TimedActions/ISReadABook']=function()return ISReadABook end
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
                 observer.tailID=42;observer.inventory=function()return {exact='inventory'}end
                 observer.activation=function()return {exact='activation'}end
                 local book={getID=function()return 42 end,getFullType=function()return 'Base.BookFirstAid1'end}
                 assert(ISReadABook.serverStart({character=player,item=book})=='native-reader-result')
                 assert(calls.readStart==1 and observer.tailStart.id==42 and observer.tailStart.workouts==1
                  and not observer.tailStart.observerActive and observer.tailStart.inventory.exact=='inventory'
                  and observer.tailStart.activation.exact=='activation')
                 observer.captureStorage=true;observer.bagID=55
                 observer.placement=function(_,callback,succeeded)return {callback=callback,succeeded=succeeded}end
                 assert(ISDropWorldItemAction.complete({character=player,item={getID=function()return 55 end}})==true)
                 assert(calls.dropComplete==1 and #observer.placements==1 and observer.placements[1].succeeded
                  and observer.placements[1].callback=='ISDropWorldItemAction.complete')
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
            local player={};local panel={player=player,exeTime={getInternalText=function()return '10'end}}
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

    def isolation_evidence(self, case='closed-ui-restore'):
        self.selection.update(kind='mp', mode='native', cases=[case], clients=2, languages=['EN','RU'], options={'mp_host':True})
        evidence=self.evidence();rows,raw,_=evidence;row=rows[1];prep=raw[0][1];ids=prep['items']
        initial=ground_inventory(ids,prep['inventory']);storage=storage_snapshot(ids,prep['inventory'],'world',True)
        storage['favorite']=prep['storage']['favorite'];activation={str(ids['hammer']):False}
        row.update(status='failed',reason='independent-tail-not-preserved')
        row['command'].update(queueDrained=True,activeObserved=False,startedOrder=[],clientCurrentExerciseCleared=False,clientInventory=initial)
        row['receipt'].update(tailRead=False,records=[],violations=[],inventory=initial,clinical=clinical(),currentExerciseCleared=True,serverStopSettled=True)
        rows[-1]['failed']=1
        context=dict(case=case,actor='client1',mode='native',kind='mp',failedCaseRecorded=True,failedRowUnchanged=True,
                     queueEmpty=True,nativeActions=0,observerActive=False,localRecords=0)
        authority=dict(case=case,phase='before',items=ids,serverIdle=True,currentExerciseCleared=True,records=0,
            observerActive=False,nativeActions=0,failedCaseRecorded=True,inventory=initial,storage=storage,clinical=clinical(),activation=activation)
        start=dict(context,phase='started',exactObjectMatched=True,cleared=True,authority=authority,before=clinical(),after=clinical(),
            inventoryBefore=initial,inventoryAfter=initial,activationBefore=activation,activationAfter=activation,storageBefore=storage,recoveryRequired=True)
        final=copy.deepcopy(prep['inventory']);final.update(primary=False,secondary=ids['screwdriver'],worn=[])
        next(value for value in final['items'] if value['id']==ids['dumbbell'])['container']='root'
        carried=copy.deepcopy(storage);carried.update(endpoint='root',world=False)
        settled_authority=dict(authority,phase='after',inventory=final,storage=carried)
        end=dict(context,phase='settled',currentExerciseCleared=True,nativeBegins=[dict(kind='ISInventoryTransferAction',id=ids['bag'],callback='ISBaseTimedAction.begin')],
            recoveryRequired=True,recoveryCallbacks=1,recoveryCallbackSucceeded=True,recoveryTransaction=17,recoveryAuthorityCompleted=True,
            recoveryStart=dict(id=ids['bag'],kind='Base.Bag_Schoolbag',source='world',destination='root',callback='ISBaseTimedAction.begin',
                storage=storage,inventory=initial,nativeClock=2000),authority=settled_authority,clinical=clinical(),inventory=final,activation=activation,storage=carried)
        return evidence,start,end

    def verify_isolation(self,evidence,start,end,order='normal',ready_order='normal'):
        self.verify(evidence);rows,raw,_=evidence
        marker=lambda key,value:'[FITNESS_TEST] '+key+' '+json.dumps(value)+'\n'
        line=lambda value:'[QUEUE_CHECK] '+json.dumps(value)+'\n'
        started=marker('ISOLATION_STARTED',start);settled=marker('ISOLATION_SETTLED',end)
        middle=started+line(rows[1])+settled if order=='before-failure' else line(rows[1])+started+settled
        if order=='next-overlap':middle=line(rows[1])+started+'[FITNESS_TEST] MENU_READY {}\n'+settled
        if order=='duplicate':middle+=started+settled
        client=line(rows[0])+middle+line(rows[-1])+'[FITNESS_TEST] COMPLETE\n'
        authority=''.join(marker(key,value) for key,value in raw)
        ready=marker('ISOLATION_READY',start['authority'])+marker('ISOLATION_READY',end['authority'])
        authority=ready+authority if ready_order=='early' else authority+ready
        (self.root/'client1-launch.log').write_text(client);(self.root/'server-launch.log').write_text(authority)
        return fitness.verify(self.root,self.selection,{})

    def test_native_isolation_keeps_failed_rows_and_native_equipment_differences(self):
        for case in fitness.BORROWED_CASES:
            with self.subTest(case=case):
                evidence,start,end=self.isolation_evidence(case)
                result=self.verify_isolation(evidence,start,end)
                self.assertEqual([issue for issue in result['issues'] if 'isolation' in issue],[])
                self.assertEqual(len(result['evidence']['isolations']),2)
                self.assertTrue(all(value['status']=='failed' for value in result['outcomes']))
                self.assertEqual(evidence[0][1]['status'],'failed')
                self.assertNotEqual(end['inventory'],evidence[1][0][1]['inventory'])

    def test_native_isolation_rejects_order_live_workouts_loss_and_unconfirmed_recovery(self):
        for change in ('before-failure','next-overlap','duplicate','authority-early','mode','not-failed','workout','local-active','server-active',
                       'wrong-ids','lost','duplicate-item','type','favorite','bag-world','effects','authority-effects','callback','transaction','fake-start','no-start','repeat-start','row-mutated'):
            evidence,start,end=self.isolation_evidence();order='normal';ready_order='normal'
            if change in ('before-failure','next-overlap','duplicate'):order=change
            elif change=='authority-early':ready_order='early'
            elif change=='mode':self.selection['mode']='toolkit'
            elif change=='not-failed':evidence[0][1]['status']='passed'
            elif change=='workout':evidence[0][1]['receipt']['records']=[{}]
            elif change=='local-active':start['observerActive']=True
            elif change=='server-active':end['authority']['nativeActions']=1
            elif change=='wrong-ids':end['authority']['items']=dict(end['authority']['items'],bag=999)
            elif change=='lost':end['inventory']['items'].pop()
            elif change=='duplicate-item':end['inventory']['items'].append(end['inventory']['items'][0])
            elif change=='type':end['inventory']['items'][0]['kind']='Base.Pencil'
            elif change=='favorite':end['storage']['favorite']=not end['storage']['favorite']
            elif change=='bag-world':end['storage'].update(endpoint='world',world=dict(x=1,y=2,z=0,linked=True))
            elif change=='effects':end['clinical']['strengthXP']+=1
            elif change=='authority-effects':end['authority']['clinical']=clinical(xp=1)
            elif change=='callback':end['recoveryCallbackSucceeded']=False
            elif change=='transaction':end['recoveryAuthorityCompleted']=False
            elif change=='fake-start':end['recoveryStart']['callback']='fixture-poll'
            elif change=='no-start':end['nativeBegins']=[]
            elif change=='repeat-start':end['nativeBegins']*=2
            else:end['failedRowUnchanged']=False
            with self.subTest(change=change):
                self.assertTrue(any('isolation' in issue for issue in self.verify_isolation(evidence,start,end,order,ready_order)['issues']))

    def test_lua_native_isolation_exact_object_gates_and_real_disabled_lifecycle_receipt(self):
        try:
            from lupa import LuaRuntime
        except ImportError:
            self.skipTest('Lupa is required for native isolation ownership checks')
        lua=LuaRuntime()
        lua.execute("""
            function copy(value)if type(value)~='table'then return value end local result={}
             for key,entry in pairs(value)do result[key]=copy(entry)end return result end
            selection={mode='native',kind='mp'};observer={records={},clock=function()return 1000 end}
            package.preload['QueueFitnessObservation']=function()return observer end
            package.preload['QueueTestSelection']=function()return selection end
            package.preload['TimedActions/ISQueueActionsAction']=function()return {}end
            ISQueueActionsAction={start=function()end};ISInventoryTransferAction={}
            isClient=function()return true end;isServer=function()return false end;getTimestampMs=function()return 1000 end
            PZSurvivorToolkit={Settings={actionQueue=function()return false end}}
            q={queue={}};ISTimedActionQueue={queues={},getTimedActionQueue=function()return q end}
            nativeCount=0;clearCalls=0;root={};ghost={}
            fit={current=ghost,getCurrentExe=function(self)return self.current end,
             setCurrentExercise=function(self,value)clearCalls=clearCalls+1;self.current=value end}
            player={getFitness=function()return fit end,getInventory=function()return root end,
             hasTimedActions=function()return nativeCount>0 end,getCharacterActions=function()return {isEmpty=function()return nativeCount==0 end}end}
            clinical={fitnessXP=0,strengthXP=0,endurance=1,regularity={bicepscurl=0},stiffness={arms=0}}
            observer.clinical=function()return copy(clinical)end
            original={items={{id=10,kind='Base.BookCarpentry1',container=12},{id=11,kind='Base.BookFirstAid1',container='root'},
             {id=12,kind='Base.Bag_Schoolbag',container='root'},{id=13,kind='Base.Torch',container='root'},
             {id=14,kind='Base.Screwdriver',container='root'},{id=15,kind='Base.DumbBell',container=12}},primary=13,secondary=14,worn={{id=12,location='Back'}}}
            initialStorage={id=12,kind='Base.Bag_Schoolbag',favorite=true,endpoint='root',occurrences=1,
             contents={copy(original.items[1]),copy(original.items[6])},world=false}
            function reset()
             selection.mode='native';selection.kind='mp';nativeCount=0;clearCalls=0;fit.current=ghost
             q.queue={};q.current=nil;observer.records={};observer.active=nil;clinical.fitnessXP=0;clinical.strengthXP=0
             inventory={items={copy(original.items[2]),copy(original.items[4]),copy(original.items[5]),copy(original.items[6])},primary=false,secondary=14,worn={}}
             inventory.items[4].container='root'
             storage=copy(initialStorage);storage.endpoint='world';storage.world={x=1,y=2,z=0,linked=true};storage.contents={copy(original.items[1])}
             state={case='placement-cancel-restore',player=player,requestedCurrent=ghost,strandedCurrent=ghost,failedCaseRecorded=true,
              ids={items={front=10,tail=11,bag=12,hammer=13,screwdriver=14,dumbbell=15},inventory=copy(original),storage=copy(initialStorage)}}
             state.lastReceipt={currentExerciseCleared=true,serverStopSettled=true,records={},violations={}}
             state.failedRow={id=state.case,status='failed',receipt=state.lastReceipt,command={queueDrained=true,clientCurrentExerciseCleared=false,activeObserved=false,startedOrder={}}}
             state.failedRowEncoding=JSON.encode(state.failedRow)
             authority={case=state.case,phase='before',items=state.ids.items,serverIdle=true,currentExerciseCleared=true,records=0,
              observerActive=false,nativeActions=0,failedCaseRecorded=true,inventory=copy(inventory),storage=copy(storage),clinical=copy(clinical)}
            end
        """)
        lua.globals().JSON=lua.execute((ROOT/'tests/native_queue/health/shared/QueueHealthEvents.lua').read_text())
        lua.execute("package.preload['QueueHealthEvents']=function()return JSON end")
        lua.globals().fixture=lua.execute((ROOT/'tests/native_queue/fitness/shared/QueueFitnessFixture.lua').read_text())
        lua.execute("""
            fixture.inventory=function()return copy(inventory)end;fixture.storage=function()return copy(storage)end
            fixture.activation=function()return {['13']=false}end
            local changes={function()selection.mode='toolkit'end,function()selection.kind='sp'end,
             function()state.case='empty'end,function()state.failedCaseRecorded=false end,
             function()state.failedRow.status='passed'end,function()state.failedRow.command.activeObserved=true end,
             function()state.failedRow.command.startedOrder={'bicepscurl'}end,function()state.lastReceipt.records={{}}end,
             function()state.requestedCurrent={}end,function()state.strandedCurrent={}end,
             function()q.queue={{}}end,function()q.current={}end,function()nativeCount=1 end,
             function()observer.active={}end,function()observer.records={{}}end,
             function()authority.records=1 end,function()authority.currentExerciseCleared=false end,
             function()authority.items=copy(authority.items);authority.items.bag=999 end,
             function()authority.case='closed-ui-restore'end,function()storage.favorite=false end,
             function()inventory.items[1].kind='Base.Pencil'end,function()storage.contents={}end}
            for _,change in ipairs(changes)do
             reset();change();local old=fit.current
             assert(not pcall(fixture.beginNativeIsolation,state,authority),'unsafe native isolation accepted')
             assert(clearCalls==0 and fit.current==old,'rejected gate changed live constructor')
            end
            reset();local witness=fixture.beginNativeIsolation(state,authority)
            assert(clearCalls==1 and fit.current==nil and witness.cleared and witness.exactObjectMatched)
            assert(not pcall(fixture.beginNativeIsolation,state,authority)and clearCalls==1,'isolation repeated clear')
            assert(not pcall(fixture.finishNativeIsolation,state,authority),'queue disappearance fabricated cleanup')
            F=fixture;O=observer;T=PZSurvivorToolkit;command={};case=function()return state.case end
        """)
        lua.execute((ROOT/'PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueLifecycle.lua').read_text())
        source=(ROOT/'tests/native_queue/fitness/client/ZZFitnessQueue.lua').read_text()
        start=source.index("assert(T.ActionQueueLifecycle.registerObserver('fitness-independent-tail'")
        end=source.index("),'fitness native reader boundary observer unavailable')",start)+len("),'fitness native reader boundary observer unavailable')")
        lua.execute(source[start:end])
        lua.execute("""
            isItemTransactionDone=function(id)return id==17 end;isItemTransactionRejected=function()return false end
            local action=setmetatable({Type='ISInventoryTransferAction',character=player,transactionId=17,
             srcContainer={getType=function()return 'floor'end},destContainer=root,item={getID=function()return 12 end,
             getFullType=function()return 'Base.Bag_Schoolbag'end}},ISInventoryTransferAction)
            local lifecycle=T.ActionQueueLifecycle;lifecycle.started(action)
            assert(lifecycle.begin(action,'perform'),'queue-disabled recovery did not opt into actual finish observation')
            lifecycle.finish(action,'perform',true)
            assert(state.isolation.callbacks==1 and state.isolation.authority and clearCalls==1)
            -- Emulate separately completed native replication. The observer never moves or equips an item.
            inventory=copy(original);inventory.primary=false;inventory.secondary=14;inventory.worn={};inventory.items[6].container='root'
            storage=copy(initialStorage);storage.contents={copy(original.items[1])}
            local final=copy(authority);final.phase='after';final.inventory=copy(inventory);final.storage=copy(storage)
            local saved=state.failedRowEncoding
            local result=fixture.finishNativeIsolation(state,final)
            assert(result.recoveryCallbacks==1 and result.recoveryTransaction==17 and result.recoveryAuthorityCompleted)
            assert(result.inventory.primary==false and result.activation['13']==false,'native baseline differences were repaired')
            assert(JSON.encode(state.failedRow)==saved and state.failedRow.status=='failed'and clearCalls==1)
            assert(not pcall(fixture.finishNativeIsolation,state,final),'settled isolation was repeated')
        """)

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
                PZSurvivorToolkit={ActionQueue={},ActionQueueOperations={},ActionQueueLifecycle={registerObserver=function()return true end},Settings={actionQueue=function()return true end}}
                PZAPI={ModOptions={getOptions=function()return {getOption=function()return {
                 setValue=function()optionCalls=optionCalls+1 end}end}end}}
                local config={kind=test_kind,mode='toolkit',cases={'empty'}}
                package.preload['QueueTestSelection']=function()return config end
                package.preload['QueueHealthEvents']=function()return {
                 emit=function(row)rows[#rows+1]=row end,encode=function()return '{}'end}end
                for _,name in ipairs({'PZSurvivorToolkit/ActionQueuePanel','ISUI/ISFitnessUI',
                 'Definitions/FitnessExercises','TimedActions/ISFitnessAction','QueueFitnessFixture','QueueFitnessObservation','PZSurvivorToolkit/ActionQueueSettlement'})do
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
