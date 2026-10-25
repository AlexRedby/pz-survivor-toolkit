"""Falsify ownership and real movement/transaction evidence; no gameplay pass."""
import copy
import unittest
from test_queue_fitness_adapter import clinical
import test_queue_fitness_adapter as base
from queue_checks.adapters.fitness_negative import _topology
from queue_checks.adapters.fitness_negative import verify_negative


class FitnessNegativeAdapterTests(unittest.TestCase):
    def evidence(self,case='storage-walk-away',mp=False,managed=True):
        ids=dict(front=1,tail=2,bag=3,hammer=4,screwdriver=5,dumbbell=6)
        spec=dict(origin=dict(x=10,y=20,z=0),bag=dict(id=3,kind='Base.Bag_Schoolbag',favorite=True),
                  content=dict(id=1,kind='Base.BookCarpentry1',favorite=False),prop=dict(id=6,kind='Base.DumbBell',favorite=True))
        inventory=dict(items=[dict(id=i,kind=k,container=c)for i,k,c in [(1,'Base.BookCarpentry1',3),(2,'Base.BookFirstAid1','root'),
            (3,'Base.Bag_Schoolbag','root'),(4,'Base.Hammer','root'),(5,'Base.Screwdriver','root'),(6,'Base.DumbBell',3)]],
            primary=4,secondary=5,worn=[dict(id=3,location='base:back')])
        def snapshot(endpoint='world',partial=False,prepared=False,far=False):
            owner={'world':'world','client1-root':'client1','client2-root':'client2'}[endpoint];rows=[]
            for name,parent,who in [('bag',endpoint,owner),('content',3,owner),('prop',3 if prepared else 'client1-root','client1')]:
                if partial and name!='prop':continue
                entry=dict(spec[name],container=parent,owner=who)
                if name=='bag'and endpoint=='world':entry['world']=dict(**spec['origin'],linked=True)
                rows.append(entry)
            rows.sort(key=lambda r:(r['id'],r['owner']))
            return dict(resources=rows,position=dict(x=14.5 if far else 10.5,y=20.5,z=0,onlineID=0 if mp else -1),
                        peerPosition=dict(x=11.5,y=20.5,z=0,onlineID=4)if mp else False,primary=4,secondary=5,worn=[])
        prep=dict(case=case,items=ids,negativeStorage=spec,inventory=inventory,before=clinical(),negativeBefore=snapshot('client1-root',prepared=True),peerOnlineID=4)
        final=copy.deepcopy(inventory);final['items']=[dict(item,container='root')if item['id']==6 else item for item in final['items']if item['id']not in (1,3)];final['worn']=[]
        walk=case=='storage-walk-away';endpoint='world'if walk else 'client2-root'
        after=snapshot(endpoint,far=walk)
        record=dict(exercise='bicepscurl',minutes=10,maxTime=5000000,previousStopSettled=True,currentExerciseCleared=True,
                    serverStopReturned=True,stopMethod='serverStop'if mp else 'observed-native-removal',reps=2,
                    before=clinical(),lastRep=clinical(2,.95,.1,.1),after=clinical(2,.95,.1,.1),minEndurance=.95,
                    startMS=1000,durationStartMS=0,durationStopMS=60000 if walk else 600001,durationStopFrameGameMS=1000,
                    negativeStorage=snapshot('world'))
        body=copy.deepcopy(final);body.update(primary=6,secondary=False);record['startEquipment']=body
        if mp:record['stopCallbacks']=dict(serverStop=1)
        command=dict(menuDispatched=True,nativeDurations=True,minutes=10,frontMinutes=0,activeObserved=True,queueDrained=True,
                     clientCurrentExerciseCleared=True,pendingCancelled=False,reordered=False,activeCancelled=False,closedUI=False,
                     startedOrder=['bicepscurl'],nativeStopCalls=1,nativeStopReturns=1,clientInventory=copy.deepcopy(final),
                     negativeFinal=snapshot(endpoint,partial=not walk,far=walk),negativeBeforeTail=snapshot(endpoint,partial=not walk,far=walk),
                     negativeStop=dict(callback='ISFitnessAction.stop',state=dict(type='ISFitnessAction',exercise='bicepscurl',minutes=10,started=True)),
                     progressSamples=[dict(total=10,elapsed=1,fraction=.1)]if managed else [],
                     activeAcks=['native0'],terminalAcks=[dict(token='native0',state='canceled')])
        receipt=dict(case=case,inventory=final,negativeStorage=after,tailRead=True,frontRead=False,removed=False,currentExerciseCleared=True,
                     serverStopSettled=True,peerConnected=True,before=copy.deepcopy(prep['before']),clinical=clinical(2,.95,.1,.1),violations=[],serverSettleMilliseconds=2100,records=[record],placements=[dict(callback='ISDropWorldItemAction.complete',succeeded=True,nativeClock=500,
                      storage=dict(id=3,kind='Base.Bag_Schoolbag',favorite=True,endpoint='world',occurrences=1,contents=[dict(id=1,kind='Base.BookCarpentry1',container=3)],world=dict(**spec['origin'],linked=True)))])
        if walk:
            command['afterWalk']=copy.deepcopy(after);command['walkAway']=dict(producer='ISWalkToCursor.create',maxTime=-1,nativeStarted=True,
                oldTailCancelled=True,nativeBegin=True,nativeCompleted=True,nativeResult='Succeeded',nativePerformCalls=1,tailId=2,tailPages=99,tailTotal=100,completedAt=100,maxDisplacement=4,before=dict(x=10.5,y=20.5,z=0),after=dict(x=14.5,y=20.5,z=0),destination=dict(x=14,y=20,z=0))
            command['freshReader']=dict(callback='ISInventoryPaneContextMenu.onLiteratureItems',snapshot=copy.deepcopy(after),pages=99,total=100,timestampMS=110,
                begin=dict(callback='ISBaseTimedAction.begin',id=2,kind='Base.BookFirstAid1',snapshot=copy.deepcopy(after),timestampMS=111))
        else:
            proof=dict(phase='picked',id=3,kind='Base.Bag_Schoolbag',favorite=True,contents=[dict(id=1,kind='Base.BookCarpentry1',container=3)],
                callbacks=1,queueDrained=True,origin=spec['origin'],walkRequired=True,walkStarted=True,walkMoved=True,walkFinished=True,
                position=dict(x=11.5,y=20.5,z=0),snapshot=dict(position=dict(x=11.5,y=20.5,z=0,onlineID=4)),
                pickupStart=dict(callback='ISBaseTimedAction.begin',id=3,kind='Base.Bag_Schoolbag',source='world',destination='peer-root',origin=spec['origin'],position=dict(x=11.5,y=20.5,z=0),timestampMS=110),
                transaction=dict(callback='ISInventoryTransferAction.perform',completed=True,rejected=False,id=3,kind='Base.Bag_Schoolbag',source='world',destination='peer-root',transactionId=7,timestampMS=120))
            receipt.update(peerGrant=dict(reps=1,peerOnlineID=4,snapshot=snapshot('world')),peerPickup=dict(proof=proof,snapshot=copy.deepcopy(after),onlineID=4),
                           tailStart=dict(negativeStorage=copy.deepcopy(after)))
        return case,dict(status='passed',reason=None,command=command),prep,receipt,dict(kind='mp'if mp else'sp',mode='toolkit'if managed else 'native')

    def verify(self,evidence):return verify_negative(*evidence)

    def test_review_observer_and_paid_xp_endpoints_reject_disagreement(self):
        for mutation in ('violations','missing-violations','false-violations','last-rep-xp','stop-xp','final-xp','missing-final-clinical'):
            e=self.evidence();receipt=e[3];record=receipt['records'][0]
            if mutation=='violations':receipt['violations']=['next-workout-before-server-stop']
            elif mutation=='missing-violations':receipt.pop('violations')
            elif mutation=='false-violations':receipt['violations']=False
            elif mutation=='last-rep-xp':record['lastRep']['strengthXP']+=1
            elif mutation=='stop-xp':record['after']['strengthXP']+=1000
            elif mutation=='final-xp':receipt['clinical']['fitnessXP']+=1
            else:receipt.pop('clinical')
            with self.subTest(mutation=mutation):self.assertTrue(self.verify(e))
        e=self.evidence();e[3]['clinical']['endurance']=.4;e[3]['records'][0]['after']['endurance']=.9
        self.assertEqual(self.verify(e),[],'ordinary endurance drift must not invalidate the exact XP boundary')

    def test_review_peer_reach_replica_positions_and_native_callback_order(self):
        for mutation in ('position-far','position-other-z','start-far','grant-far','authority-far','final-authority-far','local-far','same-range-disagreement','wrong-authority-id','wrong-local-id','reversed-time','missing-begin-time','missing-perform-time'):
            e=self.evidence('storage-peer-pickup',True);receipt=e[3];proof=receipt['peerPickup']['proof']
            if mutation=='position-far':proof['position']['x']=100
            elif mutation=='position-other-z':proof['position']['z']=1
            elif mutation=='start-far':proof['pickupStart']['position']['y']=100
            elif mutation=='grant-far':receipt['peerGrant']['snapshot']['peerPosition']['x']=100
            elif mutation=='authority-far':receipt['peerPickup']['snapshot']['peerPosition']['x']=100
            elif mutation=='final-authority-far':receipt['negativeStorage']['peerPosition']['x']=100
            elif mutation=='local-far':proof['snapshot']['position']['x']=100
            elif mutation=='same-range-disagreement':proof['position']['x']=10.5
            elif mutation=='wrong-authority-id':receipt['peerPickup']['snapshot']['peerPosition']['onlineID']=999
            elif mutation=='wrong-local-id':proof['snapshot']['position']['onlineID']=999
            elif mutation=='reversed-time':proof['transaction']['timestampMS']=109
            elif mutation=='missing-begin-time':proof['pickupStart'].pop('timestampMS')
            else:proof['transaction'].pop('timestampMS')
            with self.subTest(mutation=mutation):self.assertTrue(self.verify(e))

    def test_review_walk_exact_original_reader_and_destination_square(self):
        for mutation in ('tail-id','destination-x','destination-y','destination-z','before-z','missing-destination'):
            e=self.evidence();walk=e[1]['command']['walkAway']
            if mutation=='tail-id':walk['tailId']=999
            elif mutation=='destination-x':walk['destination']['x']=100
            elif mutation=='destination-y':walk['destination']['y']=100
            elif mutation=='destination-z':walk['destination']['z']=1
            elif mutation=='before-z':walk['before']['z']=1
            else:walk['destination']={}
            with self.subTest(mutation=mutation):self.assertTrue(self.verify(e))

    def test_resource_ids_are_sorted_by_identity_not_semantic_role(self):
        e=self.evidence();spec=e[2]['negativeStorage'];snapshot=e[3]['negativeStorage']
        snapshot['resources'].sort(key=lambda r:(r['id'],r['owner']))
        self.assertTrue(_topology(snapshot,spec,'world'))
        snapshot['resources'].append(copy.deepcopy(snapshot['resources'][0]))
        self.assertFalse(_topology(snapshot,spec,'world'))

    def test_full_report_retains_missing_peer_payment_as_failed_evidence(self):
        harness=base.FitnessAdapterTests();harness.setUp();self.addCleanup(harness.doCleanups)
        harness.selection.update(cases=['storage-peer-pickup'],kind='mp',mode='toolkit',clients=2,languages=['EN','RU'],options={'mp_host':True})
        evidence=harness.evidence();evidence[0][1]['receipt']['peerPickup']=False
        self.assertTrue(harness.verify(evidence)['issues'])

    def test_native_and_managed_walk_and_two_client_competition(self):
        for case,mp in [('storage-walk-away',False),('storage-walk-away',True),('storage-peer-pickup',True)]:
            for managed in (False,True):
                with self.subTest(case=case,mp=mp,managed=managed):self.assertEqual(self.verify(self.evidence(case,mp,managed)),[])

    def test_walk_requires_real_interruption_motion_conservation_and_fresh_reader(self):
        for change in ('no-start','no-move','old-tail','near-origin','teleport-bag','lost-prop','duplicate','contents','favorite','full-workout','missing-reader','initial-prop-root','no-effects','duplicate-stop','walk-disappeared','fake-displacement','old-reader-position','no-paid-drop','fake-drop','already-read','no-new-begin'):
            e=self.evidence();c=e[1]['command'];r=e[3]
            if change=='no-start':c['walkAway']['nativeStarted']=False
            elif change=='no-move':c['walkAway']['maxDisplacement']=.01
            elif change=='old-tail':c['walkAway']['oldTailCancelled']=False
            elif change=='near-origin':r['negativeStorage']['position']['x']=10.5
            elif change=='teleport-bag':next(v for v in r['negativeStorage']['resources']if v['id']==3)['world']['x']=14
            elif change=='lost-prop':r['negativeStorage']['resources'].pop()
            elif change=='duplicate':r['negativeStorage']['resources'].append(copy.deepcopy(r['negativeStorage']['resources'][0]))
            elif change=='contents':next(v for v in r['negativeStorage']['resources']if v['id']==1)['id']=999
            elif change=='favorite':next(v for v in r['negativeStorage']['resources']if v['id']==3)['favorite']=False
            elif change=='full-workout':r['records'][0]['durationStopMS']=600001
            elif change=='missing-reader':c.pop('freshReader')
            elif change=='initial-prop-root':next(v for v in e[2]['negativeBefore']['resources']if v['id']==6)['container']='client1-root'
            elif change=='no-effects':r['records'][0]['lastRep']=clinical()
            elif change=='walk-disappeared':c['walkAway']['nativeCompleted']=False
            elif change=='fake-displacement':c['walkAway']['before']=copy.deepcopy(c['walkAway']['after'])
            elif change=='old-reader-position':c['negativeBeforeTail']['position']['x']=10.5
            elif change=='no-paid-drop':r['placements']=[]
            elif change=='fake-drop':r['placements'][0]['succeeded']=False;r['placements'][0]['callback']='queue-disappearance'
            elif change=='already-read':c['walkAway']['tailPages']=100
            elif change=='no-new-begin':c['freshReader'].pop('begin')
            else:c['nativeStopCalls']=2
            with self.subTest(change=change):self.assertTrue(self.verify(e))

    def test_explicit_movement_retires_old_ack_namespace_without_losing_stop_proof(self):
        e=self.evidence(mp=True);e[1]['command']['terminalAcks']=[]
        self.assertEqual(self.verify(e),[])
        e[1]['command']['nativeStopReturns']=0
        self.assertTrue(self.verify(e))
        e=self.evidence('storage-peer-pickup',True);e[1]['command']['terminalAcks']=[]
        self.assertTrue(self.verify(e))

    def test_missing_negative_witnesses_fail_without_crashing_the_report(self):
        for case,mp in [('storage-walk-away',False),('storage-peer-pickup',True)]:
            for field in ('negativeStop','walkAway','freshReader','peerGrant','peerPickup','tailStart'):
                if field in ('walkAway','freshReader') and mp:continue
                if field in ('peerGrant','peerPickup','tailStart') and not mp:continue
                e=self.evidence(case,mp);target=e[1]['command'] if field in ('negativeStop','walkAway','freshReader') else e[3]
                target[field]=False
                with self.subTest(case=case,field=field):self.assertTrue(self.verify(e))

    def test_peer_requires_its_own_paid_native_pickup_and_same_original_resources(self):
        for change in ('no-grant','early','not-peer','duplicate','wrong-id','failed','unpaid','wrong-source','wrong-callback','no-walk','different-peer','early-reader','unworn-tool','missing-content'):
            e=self.evidence('storage-peer-pickup',True);r=e[3];p=r['peerPickup']['proof']
            if change=='no-grant':r.pop('peerGrant')
            elif change=='early':r['peerGrant']['reps']=0
            elif change=='not-peer':next(v for v in r['negativeStorage']['resources']if v['id']==3)['container']='client1-root'
            elif change=='duplicate':p['callbacks']=2
            elif change=='wrong-id':p['id']=999
            elif change=='failed':p['transaction']['rejected']=True
            elif change=='unpaid':p['transaction']['transactionId']=0
            elif change=='wrong-source':p['transaction']['source']='other-bag'
            elif change=='wrong-callback':p['transaction']['callback']='queue-disappearance'
            elif change=='no-walk':p['walkMoved']=False
            elif change=='different-peer':r['peerPickup']['onlineID']=5
            elif change=='early-reader':next(v for v in r['tailStart']['negativeStorage']['resources']if v['id']==3)['container']='world'
            elif change=='unworn-tool':r['inventory']['primary']=False
            else:p['contents']=[]
            with self.subTest(change=change):self.assertTrue(self.verify(e))


if __name__=='__main__':unittest.main()
