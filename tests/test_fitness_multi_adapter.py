"""Mixed-storage cases reuse the real Fitness reporting protocol."""
import copy
import unittest
import test_queue_fitness_adapter as base
from queue_checks.adapters import fitness
from queue_checks.adapters.fitness_storage import verify_storage


class MultiStorageAdapterTests(unittest.TestCase):
    def setUp(self):
        self.harness=base.FitnessAdapterTests()
        self.harness.setUp();self.addCleanup(self.harness.doCleanups)

    def evidence(self,case='multi-storage',kind='sp',mode='toolkit'):
        h=self.harness
        h.selection.update(cases=[case],kind=kind,mode=mode,clients=2 if kind=='mp' else 1,
                           languages=['EN','RU'] if kind=='mp' else ['EN'],options={'mp_host':True} if kind=='mp' else {})
        rows,raw,peers=h.evidence();row=rows[1];command=row['command'];receipt=row['receipt'];prep=raw[0][1];ids=prep['items']
        kinds=dict(front='Base.BookCarpentry1',tail='Base.BookFirstAid1',bag='Base.Bag_Schoolbag',hammer='Base.Bag_Satchel',screwdriver='Base.Screwdriver',dumbbell='Base.DumbBell')
        inventory=prep['inventory']
        for item in inventory['items']:
            name=next(name for name,identity in ids.items() if identity==item['id']);item['kind']=kinds[name]
            if name=='dumbbell':item['container']=ids['hammer']
        inventory['items'] += [dict(id=106,kind='Base.Bag_FannyPackFront',container='root'),
                              *[dict(id=107+i,kind='Base.Pencil',container=parent) for i,parent in enumerate((ids['bag'],ids['hammer'],106))]]
        inventory.update(primary=ids['hammer'],secondary=ids['screwdriver'],worn=[dict(id=ids['bag'],location='base:back'),dict(id=106,location='base:fannypackfront')])
        spec=dict(bags=[dict(name=name,id=identity,kind=kinds.get(name,'Base.Bag_FannyPackFront'),slot=slot,primary=name=='hammer',secondary=False,favorite=True)
                        for name,identity,slot in [('bag',ids['bag'],'base:back'),('hammer',ids['hammer'],False),('fanny',106,'base:fannypackfront')]],
                  markers=[dict(id=107+i,kind='Base.Pencil',bag=parent) for i,parent in enumerate((ids['bag'],ids['hammer'],106))],
                  prop=dict(id=ids['dumbbell'],kind='Base.DumbBell',bag=ids['hammer'],favorite=True),origin=dict(x=5,y=5,z=0))
        bag_ids={ref['id'] for ref in spec['bags']}
        def snapshot(world=(),outside=False,body=False):
            world=set(world);items=[]
            for item in inventory['items']:
                entry=dict(item,favorite=item['id'] in bag_ids or item['id']==ids['dumbbell'])
                if item['id'] in world:entry['container']='world'
                elif item['id']==ids['dumbbell'] and outside:entry['container']='root'
                items.append(entry)
            bags=[dict(id=ref['id'],kind=ref['kind'],favorite=True,endpoint='world' if ref['id'] in world else 'root',occurrences=1,
                       contents=[entry for entry in items if entry['container']==ref['id']],world=dict(**spec['origin'],linked=True) if ref['id'] in world else False) for ref in spec['bags']]
            return dict(bags=bags,items=items,primary=ids['dumbbell'] if body else inventory['primary'],secondary=False if body else inventory['secondary'],
                        worn=[] if body else inventory['worn'],prop=dict(id=ids['dumbbell'],kind='Base.DumbBell',favorite=True,endpoint='root' if outside else ids['hammer'],occurrences=1))
        before=snapshot();prep.update(multiStorage=spec,multiBefore=before)
        command.update(clientInventory=copy.deepcopy(inventory),closedUI=case=='multi-storage-closed',multiFinal=copy.deepcopy(before),multiStarts=[],
                       multiStopFrame=70,multiBeforeTail=dict(callback='ISBaseTimedAction.begin',nativeClock=700600,frameNo=100,snapshot=copy.deepcopy(before),inventory=copy.deepcopy(inventory)))
        receipt.update(inventory=copy.deepcopy(inventory),multiStorage=copy.deepcopy(before),multiPlacements=[])
        record=receipt['records'][0]
        record.update(startMS=100000,stopMS=700001,durationStartMS=100000,durationStopMS=700001,lastRepMS=101000,
                      multiStorage=snapshot(bag_ids,True,True),startFrameNo=40)
        body_inventory=copy.deepcopy(inventory)
        body_inventory['items']=[dict(item,container='root') if item['id']==ids['dumbbell'] else item for item in inventory['items']
                                 if item['id'] not in bag_ids and (item['container'] not in bag_ids or item['id']==ids['dumbbell'])]
        body_inventory.update(primary=ids['dumbbell'],secondary=False,worn=[]);record['startEquipment']=body_inventory
        command['durationStops'][0].update(startMS=100000,endMS=700000,stopMS=700001)
        if mode=='toolkit':command['progressSamples'][0].update(startMS=100000,sampleMS=220000)
        placed=set()
        for i,ref in enumerate(spec['bags']):
            command['multiStarts'].append(dict(phase='placement',id=ref['id'],kind=ref['kind'],source='root',destination='world',callback='ISBaseTimedAction.begin',nativeClock=10+i*10,frameNo=10+i*10,snapshot=snapshot(placed,True)))
            placed.add(ref['id'])
            receipt['multiPlacements'].append(dict(phase='placement',id=ref['id'],kind=ref['kind'],callback='ISDropWorldItemAction.complete',succeeded=True,nativeClock=11+i*10,frameNo=11+i*10,serverTimeMS=11+i*10,snapshot=snapshot(placed,True)))
        for i,ref in enumerate(spec['bags']):
            command['multiStarts'].append(dict(phase='recovery',id=ref['id'],kind=ref['kind'],source='world',destination='root',callback='ISBaseTimedAction.begin',nativeClock=700100+i*10,frameNo=80+i,snapshot=snapshot(placed,True)))
            placed.remove(ref['id'])
        command['multiStarts'].append(dict(phase='return',id=ids['dumbbell'],kind='Base.DumbBell',source='root',destination=ids['hammer'],callback='ISBaseTimedAction.begin',nativeClock=700500,frameNo=90,snapshot=snapshot((),True)))
        for witness in command['multiStarts']:
            if witness['phase']!='placement':
                witness['members']=[{key:witness[key] for key in ('id','kind','source','destination')}]
                witness.update(membersCallback='ISBaseTimedAction.begin',membersNativeClock=witness['nativeClock'],membersSnapshot=copy.deepcopy(witness['snapshot']))
                witness['memberCaptures']=[dict(members=[witness['id']],callback='ISBaseTimedAction.begin',nativeClock=witness['nativeClock'],frameNo=witness['frameNo'],snapshot=copy.deepcopy(witness['snapshot']))]
        if kind=='mp':record['serverTiming']=dict(source='GameTime.getServerTimeMills:System.nanoTime',startMS=100000,stopMS=700001,elapsedMS=600001,minutesPerDay=90,worldMS=600000,realMS=37500,minScale=16,maxScale=16,samples=376)
        if kind=='mp':receipt['tailStart']=dict(id=ids['tail'],kind='Base.BookFirstAid1',callback='ISReadABook.serverStart',workouts=1,observerActive=False,inventory=copy.deepcopy(inventory),multiStorage=copy.deepcopy(before))
        return rows,raw,peers

    def test_native_and_toolkit_open_closed_cases_use_shared_protocol(self):
        for case in ('multi-storage','multi-storage-closed'):
            for kind in ('sp','mp'):
                for mode in ('native','toolkit'):
                    with self.subTest(case=case,kind=kind,mode=mode):
                        result=self.harness.verify(self.evidence(case,kind,mode))
                        self.assertEqual(result['issues'],[])
                        self.assertTrue(result['outcomes'][0]['outcome']['restoreVerified'])

    def test_storage_verifier_is_sealed_with_fixture_sources(self):
        self.assertIn(base.ROOT / 'tools/queue_checks/adapters/fitness_storage.py',
                      fitness.sources(base.ROOT,self.harness.selection))

    def test_one_native_begin_can_cover_three_original_merged_members(self):
        for kind in ('sp','mp'):
            evidence=self.evidence(kind=kind);command=evidence[0][1]['command'];group=command['multiStarts'][3]
            group['members']=[copy.deepcopy(witness['members'][0]) for witness in command['multiStarts'][3:6]]
            group.update(membersCallback='ISInventoryTransferAction.checkQueueList',membersNativeClock=700120)
            group['memberCaptures'].append(dict(members=[member['id'] for member in group['members'][1:]],callback='ISInventoryTransferAction.checkQueueList',nativeClock=700120,frameNo=82,snapshot=copy.deepcopy(group['snapshot'])))
            command['multiStarts'][3:6]=[group]
            self.assertEqual(self.harness.verify(evidence)['issues'],[])
            for change in ('duplicate','missing','fake-merge','wrong-source','late','foreign','observer-failed'):
                changed=copy.deepcopy(evidence);group=changed[0][1]['command']['multiStarts'][3]
                if change=='duplicate':group['members'][2]=copy.deepcopy(group['members'][0])
                elif change=='missing':group['members'].pop()
                elif change=='fake-merge':group['memberCaptures'][1]['callback']='inferred-pending-actions'
                elif change=='wrong-source':group['members'][1]['source']='root'
                elif change=='late':group['memberCaptures'][1]['frameNo']=101
                elif change=='foreign':group['members'][1]['id']=999
                else:group['membersError']='invalid native group'
                with self.subTest(kind=kind,change=change):self.assertTrue(self.harness.verify(changed)['issues'])

    def test_members_are_validated_at_their_own_native_source_boundary(self):
        evidence=self.evidence(kind='mp');starts=evidence[0][1]['command']['multiStarts']
        first,second,third=starts[3:6]
        first['members']=[copy.deepcopy(row['members'][0]) for row in (first,second,third)]
        first['memberCaptures'].append(dict(members=[second['id'],third['id']],callback='ISInventoryTransferAction.checkQueueList',
            nativeClock=second['nativeClock'],frameNo=second['frameNo'],snapshot=copy.deepcopy(second['snapshot'])))
        starts[3:6]=[first]
        self.assertEqual(self.harness.verify(evidence)['issues'],[])
        for change in ('old-source','duplicate','missing','foreign','early','bad-callback'):
            changed=copy.deepcopy(evidence);captures=changed[0][1]['command']['multiStarts'][3]['memberCaptures']
            if change=='old-source':captures[0]['snapshot']=copy.deepcopy(captures[1]['snapshot'])
            elif change=='duplicate':captures[1]['members'].append(captures[0]['members'][0])
            elif change=='missing':captures.pop()
            elif change=='foreign':captures[1]['members'][0]=999
            elif change=='early':captures[1]['frameNo']=0
            else:captures[1]['callback']='ISBaseTimedAction.begin'
            with self.subTest(change=change):self.assertTrue(self.harness.verify(changed)['issues'])

    def test_each_real_resource_boundary_is_required(self):
        for kind in ('sp','mp'):
            for change in ('favorite','marker','duplicate','body-held','body-bag','late-restore','server-restore','drop-count','drop-effect','wrong-recovery','missing-return','before-stop','completion-before-start','wrong-source'):
                evidence=self.evidence(kind=kind);rows,raw,_=evidence;command=rows[1]['command'];receipt=rows[1]['receipt']
                if change=='favorite':receipt['multiStorage']['bags'][0]['favorite']=False
                elif change=='marker':receipt['multiStorage']['items'].pop()
                elif change=='duplicate':receipt['records'][0]['multiStorage']['bags'][0]['occurrences']=2
                elif change=='body-held':receipt['records'][0]['multiStorage']['primary']=False
                elif change=='body-bag':receipt['records'][0]['multiStorage']['bags'][0]['endpoint']='root'
                elif change=='late-restore':command['multiBeforeTail']['snapshot']['primary']=False
                elif change=='server-restore':
                    if kind!='mp':continue
                    receipt['tailStart']['multiStorage']['bags'][0]['contents']=[]
                elif change=='drop-count':receipt['multiPlacements'].pop()
                elif change=='drop-effect':receipt['multiPlacements'][0]['succeeded']=False
                elif change=='wrong-recovery':command['multiStarts'][3]['id']=999
                elif change=='missing-return':command['multiStarts'].pop()
                elif change=='before-stop':command['multiStarts'][3]['frameNo']=69
                elif change=='completion-before-start':
                    if kind=='mp':receipt['multiPlacements'][0]['serverTimeMS']=100001
                    else:receipt['multiPlacements'][0]['frameNo']=0
                else:command['multiStarts'][-1]['members'][0]['destination']=999
                with self.subTest(kind=kind,change=change):self.assertTrue(self.harness.verify(evidence)['issues'])


if __name__=='__main__':unittest.main()
