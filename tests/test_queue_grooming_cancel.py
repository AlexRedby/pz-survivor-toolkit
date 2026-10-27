import copy
import json
import shutil
import subprocess
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from queue_checks.adapters import grooming_cancel as g


class GroomingCancellationTests(unittest.TestCase):
    def evidence(self,case='borrowed-scissors',mode='toolkit',kind='sp'):
        selected=case;active=case in g.ACTIVE_CASES;moving=case in g.MOVE_CASES;case=g.base_case(case)
        native=mode=='native';completed=native or moving;mp=kind=='mp';borrowed=g.BORROWED[case]
        selection=dict(suite='grooming-cancel',cases=[case],mode=mode,kind=kind,clients=1,languages=['EN'],mods=list(g.MODS),options={'mp_host':True} if mp else {})
        names=['bag','content','front','tail','torch','secondary']+([borrowed] if borrowed else [])+(['hat'] if case in ('borrowed-scissors','dye-hair') else [])+(['mask'] if case=='dye-beard' else [])+(['gel'] if case=='styled-scissors' else [])
        types=dict(bag='Base.Bag_Schoolbag',content='Base.Paperclip',front='Base.BookCarpentry1',tail='Base.BookFirstAid1',torch='Base.Torch',secondary='Base.Screwdriver',scissors='Base.Scissors',hat='Base.Hat_BaseballCap',gel='Base.Hairgel',razor='Base.Razor',dye='Base.HairDyeCommon',mask='Base.Hat_DustMask')
        items={name:i+1 for i,name in enumerate(names)}
        ids=dict(case=case,actor=1,male=True,items=items,types={name:types[name] for name in names},initialStyle='Fabian',
                 targetStyle='PonyTail' if case=='style-no-tool' else 'MohawkFan' if case=='styled-scissors' else 'CrewCut' if case=='borrowed-scissors' else 'Fabian',
                 duration=g.duration(case),initialLevel=3,targetLevel=3 if case=='style-no-tool' or case not in g.HAIRCUT else 2 if case=='styled-scissors' else 1,targetAttached=case=='style-no-tool',
                 actionKind=g.BODY[case],producer=g.PRODUCER[g.BODY[case]],borrowed=borrowed,
                 initialBeard='LongScruffy' if case not in g.HAIRCUT else False,targetBeard='Moustache' if case=='beard-trim' else False,
                 beardInitialLevel=3 if case not in g.HAIRCUT else False,beardTargetLevel=1 if case=='beard-trim' else False,
                 frontInitial=97,frontTotal=100,tailInitial=99,tailTotal=100)
        baseline=dict(case=case,male=True,items=[dict(id=value,kind=types[name],container=items['bag'] if name in ('content','scissors','razor','dye') else 'root',favorite=name in ('bag','scissors','razor','dye')) for name,value in items.items()],
                      primary=items['torch'],secondary=items['secondary'],worn=[dict(id=items['bag'],location='base:back')]+([dict(id=items['hat'],location='base:hat')] if 'hat'in items else [])+([dict(id=items['mask'],location='base:mask')] if 'mask'in items else []),
                      torchActive=True,frontPages=97,tailPages=99,appearance=dict(model='Fabian',nonAttached=False,color=dict(r=.2,g=.4,b=.6),beardModel='LongScruffy' if case not in g.HAIRCUT else '',beardColor=dict(r=.3,g=.25,b=.2)),
                      gel=dict(id=items['gel'],uses=20) if 'gel'in items else False,dye=dict(id=items['dye'],amount=1,color=dict(r=.1,g=.5,b=.9)) if 'dye'in items else False)
        authority_base=copy.deepcopy(baseline);ids['baseline']=copy.deepcopy(authority_base)
        if mp and borrowed=='dye':baseline['dye']['color']=g.fluid_wire_color(authority_base['dye']['color'])
        def final_state(initial,remote=False):
            value=copy.deepcopy(initial);value.update(frontPages=100 if moving or case=='style-no-tool' else 97,tailPages=100)
            value['appearance']=g.expected_appearance(initial,ids,completed,remote,authority_base)
            if 'gel'in items:value['gel']['uses']=19 if completed else 20
            if 'dye'in items:value['dye']['amount']=.5 if completed else 1
            return value
        final=final_state(baseline,mp);authority_final=final_state(authority_base)
        before=copy.deepcopy(final);before['tailPages']=99
        if not native or not mp:
            before['appearance']=copy.deepcopy(baseline['appearance']);before['gel']=copy.deepcopy(baseline['gel']);before['dye']=copy.deepcopy(baseline['dye'])
        if native and borrowed:next(item for item in before['items'] if item['id']==items[borrowed])['container']='root'
        def record(role,kind,item,started=True):
            return dict(sequence=0,role=role,kind=kind,item=item,constructorDuration=ids['duration'] if role=='body' else 10,
                        started=started,starts=1 if started else 0,finishes=[],nativeRef=role+'-native' if started else False,
                        transaction=False,token=False,terminal=False)
        prep=record('front' if case=='style-no-tool' else 'prepare','ISReadABook' if case=='style-no-tool' else 'ISInventoryTransferAction',items['front' if case=='style-no-tool' else borrowed])
        body=record('body',g.BODY[case],items.get(borrowed,False),native)
        if native:
            body['startedAt']=20;body['finishes']=[dict(phase='perform',succeeded=True,at=51)]
            if not mp:body['finishes'].append(dict(phase='complete',succeeded=True,at=52))
            else:body.update(transaction=3,token='00000000-0000-0000-0000-000000000001',terminal='completed')
        records=[prep,body,record('tail','ISReadABook',items['tail'])]
        if borrowed:
            restore=record('return','ISInventoryTransferAction',items[borrowed]);restore['finishes']=[dict(phase='perform',succeeded=True,at=80 if native else 40)];records.append(restore)
        for i,record_row in enumerate(records,1):record_row['sequence']=i
        boundary=dict(case=case,at=10,mode=mode,kind=prep['kind'],item=prep['item'],progress=.2,started=True,bodyUnallocated=True,tailRetained=True,snapshot=copy.deepcopy(baseline),accepted=not native,reason=False)
        command=dict(producer=ids['producer'],duration=ids['duration'],cancelled=not native,boundary=boundary,
                     beforeTail=dict(case=case,at=50,callback='ISBaseTimedAction.begin',snapshot=before),records=records,bodyStarts=int(native),bodyCompletes=int(native),
                     idle=dict(case=case,since=90,at=2091,empty=True,snapshot=copy.deepcopy(final)),frontQueued=case=='style-no-tool',
                     completeCountProof='sealed-native-transaction' if mp else 'shared-native-complete')
        receipt=dict(baseline=authority_base,checkpoint=copy.deepcopy(authority_base),final=authority_final,
                     bodyCompletes=False if mp else int(native),bodyRecords=[] if mp else records,
                     completeCountProof='unavailable-remote-callback' if mp else 'shared-native-complete')
        if mp:receipt['completeCountLimit']='remote callback count unavailable without replacing native effects'
        if active:
            def selected_ids(value):
                if isinstance(value,dict):
                    if value.get('case')==case:value['case']=selected
                    for child in value.values():selected_ids(child)
                elif isinstance(value,list):
                    for child in value:selected_ids(child)
            selected_ids(ids);selected_ids(baseline);selected_ids(boundary);selected_ids(command);selected_ids(receipt);selected_ids(final)
            selection['cases']=[selected]
            body.update(started=True,starts=1,nativeRef='body-native',startedAt=5)
            if not native:body.update(finishes=[],stoppedRemoval=dict(at=12,nativeRef='body-native',queueAbsent=True,nativeAbsent=True,finished=False,forceComplete=False))
            command['bodyStarts']=1
            boundary.update(stage='active',bodyUnallocated=False,kind=g.BODY[case],item=items.get(borrowed,False),startedReceipt=False)
            command['outcomes']=[]
            if mp:
                body.update(transaction=3,token='00000000-0000-0000-0000-000000000001',terminal='completed' if native else 'canceled')
                started=dict(transaction=body['transaction'],kind=g.BODY[case],token=body['token'],state='started')
                boundary['startedReceipt']=started
                command['outcomes']=[dict(protocol=1,player=ids['actor'],**started),dict(protocol=1,player=ids['actor'],**dict(started,state=body['terminal']))]
        if moving:
            moved=not native and selected in g.INDEPENDENT_CASES
            def rename(value):
                if isinstance(value,dict):
                    if value.get('case')==case:value['case']=selected
                    for child in value.values():rename(child)
                elif isinstance(value,list):
                    for child in value:rename(child)
            for value in (ids,baseline,authority_base,authority_final,final,before,receipt,command):rename(value)
            selection['cases']=[selected]
            front=record('front','ISReadABook',items['front']);front.update(startedAt=1,finishes=[dict(phase='perform',succeeded=True,at=15)])
            tail=record('tail','ISReadABook',items['tail']);tail.update(startedAt=50,finishes=[dict(phase='perform',succeeded=True,at=55)])
            members=[]
            if borrowed:
                pickup=record('prepare','ISInventoryTransferAction',items[borrowed]);pickup.update(startedAt=16 if moved else 56,finishes=[dict(phase='perform',succeeded=True,at=19 if moved else 59)])
                members.append(pickup)
            body=record('body',g.BODY[case],items.get(borrowed,False));body.update(startedAt=20 if moved else 60,finishes=[dict(phase='perform',succeeded=True,at=49 if moved else 70)])
            if mp:body.update(transaction=3,token='00000000-0000-0000-0000-000000000001',terminal='completed')
            else:body['finishes'].append(dict(phase='complete',succeeded=True,at=50 if moved else 71))
            members.append(body);records=[front,tail]+members
            if borrowed:
                restore=record('return','ISInventoryTransferAction',items[borrowed]);restore.update(startedAt=79,finishes=[dict(phase='perform',succeeded=True,at=80)]);records.append(restore)
            for i,value in enumerate(records,1):value['sequence']=i
            group=[value['sequence'] for value in members];order=[front['sequence'],tail['sequence']]+group
            before=copy.deepcopy(final);before['tailPages']=99
            before['appearance']=copy.deepcopy(baseline['appearance']);before['gel']=copy.deepcopy(baseline['gel']);before['dye']=copy.deepcopy(baseline['dye'])
            if moved and borrowed:next(item for item in before['items'] if item['id']==items[borrowed])['container']='root'
            boundary=dict(case=selected,at=10,mode=mode,kind='ISReadABook',item=items['front'],progress=.2,started=True,bodyUnallocated=True,
                          stage='move',startedReceipt=False,tailRetained=True,snapshot=copy.deepcopy(baseline),accepted=moved,
                          reason=False if native or moved else 'dependent',beforeOrder=order,afterOrder=[front['sequence']]+group+[tail['sequence']] if moved else order.copy(),
                          group=group,front=front['sequence'],tail=tail['sequence'],body=body['sequence'])
            trace=[]
            if mp:
                identity=dict(transaction=body['transaction'],kind=ids['actionKind'],token=body['token'])
                trace=[dict(protocol=1,player=ids['actor'],**identity,state=state) for state in ('started','completed')]
            command.update(cancelled=False,boundary=boundary,beforeTail=dict(case=selected,at=50,callback='ISBaseTimedAction.begin',snapshot=before),
                           records=records,bodyStarts=1,bodyCompletes=1,frontQueued=True,outcomes=trace)
            receipt.update(bodyCompletes=False if mp else 1,bodyRecords=[] if mp else records)
        row=dict(event='case',id=selected,status='passed',ids=ids,baseline=baseline,command=command,receipt=receipt,clientFinal=final,nativeMethodsUnchanged=True)
        return selection,row

    def check(self,selection,row):return g.check_case(row,selection,copy.deepcopy(row['ids']),copy.deepcopy(row['receipt']))

    def test_source_consistent_native_and_cancelled_effects(self):
        for case in g.CASES:
            for mode in ('native','toolkit'):
                for kind in ('sp','mp'):
                    selection,row=self.evidence(case,mode,kind);g.validate(selection)
                    with self.subTest(case=case,mode=mode,kind=kind):self.assertTrue(self.check(selection,row)['cleanupVerified'])

    def test_rejects_resource_loss_and_fabricated_waiting_deletion(self):
        changes={
            'nativebody':lambda r:r['command'].update(bodyStarts=1),
            'boolcount':lambda r:r['command'].update(bodyCompletes=False),
            'losttail':lambda r:r['clientFinal'].update(tailPages=99),
            'lostitem':lambda r:r['clientFinal']['items'].pop(),
            'duplicateditem':lambda r:r['clientFinal']['items'].append(r['clientFinal']['items'][0]),
            'hairchanged':lambda r:r['clientFinal']['appearance'].update(model='CrewCut'),
            'favoritechanged':lambda r:r['clientFinal']['items'][0].update(favorite=False),
            'noreturn':lambda r:r['command'].update(records=r['command']['records'][:-1]),
            'returnlate':lambda r:r['command']['records'][-1]['finishes'][0].update(at=51),
            'methods':lambda r:r.update(nativeMethodsUnchanged=False),
            'allocated':lambda r:r['command']['boundary'].update(bodyUnallocated=False),
            'nocurrent':lambda r:r['command']['records'][0].update(started=False),
            'foreignid':lambda r:r['ids']['types'].update(scissors='Base.Knife'),
            'cycle':lambda r:r['baseline']['items'][0].update(container=r['ids']['items']['content']),
        }
        for label,change in changes.items():
            selection,row=self.evidence();change(row)
            with self.subTest(change=label),self.assertRaises((AssertionError,KeyError)):self.check(selection,row)

    def test_native_controls_keep_real_costs_and_remote_limit(self):
        for kind in ('sp','mp'):
            selection,row=self.evidence('styled-scissors','native',kind)
            row['receipt']['final']['gel']['uses']=18
            with self.subTest(kind=kind),self.assertRaises(AssertionError):self.check(selection,row)
        selection,row=self.evidence('styled-scissors','native','sp')
        row['command']['beforeTail']['snapshot']['gel']['uses']=19
        with self.assertRaises(AssertionError):self.check(selection,row)
        selection,row=self.evidence('styled-scissors','toolkit','mp');row['receipt']['bodyCompletes']=0
        with self.assertRaises(AssertionError):self.check(selection,row)
        selection,row=self.evidence('style-no-tool','native','mp');row['receipt'].pop('completeCountLimit')
        with self.assertRaises(KeyError):self.check(selection,row)

    def report(self,selection,row,reverse=False):
        rows=row if isinstance(row,list) else [row]
        context=dict(suite='grooming-cancel',kind=selection['kind'],mode=selection['mode'],actor='client1')
        lines=['[QUEUE_CHECK] '+json.dumps(dict(event='setup',cases=selection['cases'],nativeDurations=True,queueEnabled=selection['mode']=='toolkit',**context))]
        authority=[]
        for row in rows:
            authority.extend('[GROOMING_TEST] '+marker+' '+json.dumps(value) for marker,value in [('PREPARED',row['ids']),('BASELINED',row['receipt']['baseline']),('VERIFIED',row['receipt'])])
            markers=[(marker,row['command'][key]) for marker,key in [('EDIT' if row['id'] in g.MOVE_CASES else 'CANCEL','boundary'),('BEFORE_TAIL','beforeTail'),('IDLE','idle')]]
            outcomes=row['command'].get('outcomes',[])
            if outcomes:
                if row['id'] in g.MOVE_CASES:
                    markers[1:1]=[('OUTCOME',dict(case=row['id'],receipt=value)) for value in outcomes]
                else:markers.insert(2,('OUTCOME',dict(case=row['id'],receipt=outcomes[1])))
            if reverse:markers=markers[::-1]
            lines.extend('[GROOMING_TEST] OUTCOME '+json.dumps(dict(case=row['id'],receipt=value)) for value in ([] if row['id'] in g.MOVE_CASES else outcomes[:1]))
            lines.extend('[GROOMING_TEST] '+marker+' '+json.dumps(value) for marker,value in markers)
            lines.append('[QUEUE_CHECK] '+json.dumps(dict(row,**context)))
        lines.append('[QUEUE_CHECK] '+json.dumps(dict(event='complete',cases=selection['cases'],performed=len(rows),skipped=0,failed=0,**context)))
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);(root/'client1-launch.log').write_text('\n'.join(lines+(authority if selection['kind']=='sp' else [])))
            if selection['kind']=='mp':(root/'server-launch.log').write_text('\n'.join(authority))
            return g.verify(root,selection,{})

    def test_complete_report_rejects_raw_order_and_retains_per_role_baselines(self):
        for mode in ('native','toolkit'):
            for kind in ('sp','mp'):
                selection,row=self.evidence(mode=mode,kind=kind)
                self.assertEqual(self.report(selection,row)['issues'],[])
                self.assertTrue(self.report(selection,row,True)['issues'])
        selection,row=self.evidence(kind='mp');row['receipt']['baseline']['appearance']['color']['r']=.21;row['receipt']['checkpoint']['appearance']['color']['r']=.21;row['receipt']['final']['appearance']['color']['r']=.21
        self.assertEqual(self.report(selection,row)['issues'],[])

    def test_beard_and_dye_controls_are_exact_and_cancellation_preserves_both_cosmetics(self):
        changes={
            'wrongbeard':lambda r:r['clientFinal']['appearance'].update(beardModel='Full'),
            'wronghair':lambda r:r['clientFinal']['appearance'].update(model='CrewCut'),
            'nativeallocation':lambda r:r['command'].update(bodyStarts=1),
            'borrowlost':lambda r:r['command'].update(records=r['command']['records'][:-1]),
            'gender':lambda r:r['baseline'].update(male=False),
            'wrongduration':lambda r:r['command'].update(duration=1),
        }
        for case in ('beard-trim','dye-hair','dye-beard'):
            for name,change in changes.items():
                selection,row=self.evidence(case);change(row)
                with self.subTest(case=case,change=name),self.assertRaises(AssertionError):self.check(selection,row)
        for case in ('dye-hair','dye-beard'):
            for kind in ('sp','mp'):
                for mode in ('native','toolkit'):
                    for amount in (0,1.5,.75):
                        selection,row=self.evidence(case,mode,kind);row['receipt']['final']['dye']['amount']=amount
                        with self.subTest(case=case,kind=kind,mode=mode,amount=amount),self.assertRaises(AssertionError):self.check(selection,row)
                    selection,row=self.evidence(case,mode,kind);row['receipt']['final']['dye']['color']['r']+=.03
                    with self.assertRaises(AssertionError):self.check(selection,row)
                    selection,row=self.evidence(case,mode,kind);row['clientFinal']['appearance']['color' if case=='dye-hair' else 'beardColor']['r']+=.01
                    with self.assertRaises(AssertionError):self.check(selection,row)

    def test_native_visual_and_fluid_byte_protocols_remain_distinct(self):
        color=dict(r=.1,g=.5,b=.9)
        visual=g.wire_color(color);fluid=g.fluid_wire_color(color)
        self.assertAlmostEqual(visual['r'],25/255,places=7)
        self.assertAlmostEqual(fluid['r'],26/255,places=7)
        self.assertAlmostEqual(visual['g'],127/255,places=7)
        self.assertAlmostEqual(fluid['g'],128/255,places=7)
        for case in ('dye-hair','dye-beard'):
            selection,row=self.evidence(case,'native','mp')
            key='color' if case=='dye-hair' else 'beardColor'
            row['clientFinal']['appearance'][key]=copy.deepcopy(row['baseline']['dye']['color'])
            with self.assertRaises(AssertionError):self.check(selection,row)
            selection,row=self.evidence(case,'toolkit','mp')
            row['baseline']['dye']['color']=copy.deepcopy(row['receipt']['baseline']['dye']['color'])
            with self.assertRaises(AssertionError):self.check(selection,row)

    def test_setup_appearance_survives_native_wire_roundtrips(self):
        fixture=Path(__file__).parent/'native_queue/grooming-cancel/shared/QueueGroomingCancel.lua'
        script="""
          local F=assert(loadfile(FixturePath))()
          function isClient()return false end
          local file=assert(io.open(FixturePath));local source=file:read('*a');file:close()
          local body=assert(source:match('(local function equipment.-)\\nfunction F%.prepare'))
          local equipment=assert(loadstring('return function(F,clearHead,Perks)\\n'..body..'\\nreturn equipment end'))()(F,function()end,{Woodwork=1,Doctor=2})
          local v={hair=ImmutableColor.new(.74,.35,.13,1),beard=ImmutableColor.new(.4,.26,.09,1)}
          function v:setHairModel(value)self.model=value end
          function v:setNonAttachedHair(value)self.attached=value end
          function v:setBeardModel(value)self.beardModel=value end
          function v:setHairColor(value)self.hair=value end
          function v:setBeardColor(value)self.beard=value end
          function v:getHairModel()return self.model end
          function v:getNonAttachedHair()return self.attached end
          function v:getBeardModel()return self.beardModel end
          function v:getHairColor()return self.hair end
          function v:getBeardColor()return self.beard end
          local p={getHumanVisual=function()return v end}
          for _,key in ipairs({'setWornItem','setPrimaryHandItem','setSecondaryHandItem','resetModel','setAlreadyReadPages','setPerkLevelDebug'})do p[key]=function()end end
          local item={canBeEquipped=function()return 'back'end,setUsedDelta=function()end,setActivated=function()end,getFullType=function()return 'book'end,setAlreadyReadPages=function()end}
          local state={player=p,bag=item,torch=item,secondary=item,front=item,tail=item,ids={initialStyle='Fabian',initialBeard='LongScruffy',frontInitial=217,tailInitial=219}}
          local function wire(c)return ImmutableColor.new(c:getRedInt()/255,c:getGreenInt()/255,c:getBlueInt()/255,1)end
          equipment(state)
          local before=F.appearance(p)
          for i=1,100 do
            v.hair,v.beard=wire(v.hair),wire(v.beard)
            assert(F.same(F.appearance(p),before),'setup color changed under native wire rounding')
          end
          v.hair=ImmutableColor.new(.74,.35,.13,1);v.beard=ImmutableColor.new(.4,.26,.09,1)
          v.model='PonyTail';v.attached='Fabian';v.beardModel='Moustache'
          equipment(state)
          assert(F.same(F.appearance(p),before),'previous dye/tie/trim leaked into next case setup')
          v.hair=ImmutableColor.new(.21,.4,.6,1)
          assert(not F.sameSetup({appearance=F.appearance(p)},{appearance=before}),'fixture hid an actual setup color mismatch')
        """
        numeric="""
          ImmutableColor={new=function(r,g,b)
            local c={r=f32(r),g=f32(g),b=f32(b)}
            function c:getRedInt()return math.floor(f32(self.r*255))end
            function c:getGreenInt()return math.floor(f32(self.g*255))end
            function c:getBlueInt()return math.floor(f32(self.b*255))end
            function c:getRedFloat()return self.r end
            function c:getGreenFloat()return self.g end
            function c:getBlueFloat()return self.b end
            return c
          end}
        """
        luajit=shutil.which('luajit')
        if luajit:
            value="local ffi=require('ffi');local function f32(v)return tonumber(ffi.new('float[1]',v)[0])end\n"+numeric+"\nlocal FixturePath="+json.dumps(str(fixture))+"\n"+script
            result=subprocess.run([luajit,'-'],input=value,text=True,capture_output=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        else:
            try:
                from lupa.lua51 import LuaRuntime
            except ImportError:
                self.skipTest('Lupa or LuaJIT required for fixture setup check')
            lua=LuaRuntime(unpack_returned_tuples=True)
            lua.globals().f32=lambda value:g.struct.unpack('f',g.struct.pack('f',value))[0]
            lua.globals().FixturePath=str(fixture)
            lua.execute(numeric+script)

    def test_actual_shared_fixture_preserves_unpaid_effects_and_native_protocol(self):
        # Execute the shipped fixture helpers; mock only native numeric value objects.
        try:
            from lupa.lua51 import LuaRuntime
        except ImportError:
            return self.check_shared_fixture_luajit()
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.globals().f32=lambda value:g.struct.unpack('f',g.struct.pack('f',value))[0]
        lua.execute("""
          Color={new=function()return {set=function(self,r)self.r=f32(r)end,getR=function(self)return self.r end}end}
          ImmutableColor={new=function(r,g,b)
            local c={r=f32(r),g=f32(g),b=f32(b)}
            function c:getRedInt()return math.floor(f32(self.r*255))end
            function c:getGreenInt()return math.floor(f32(self.g*255))end
            function c:getBlueInt()return math.floor(f32(self.b*255))end
            function c:getRedFloat()return self.r end
            function c:getGreenFloat()return self.g end
            function c:getBlueFloat()return self.b end
            return c
          end}
          function isClient()return true end
        """)
        fixture=Path(__file__).parent/'native_queue/grooming-cancel/shared/QueueGroomingCancel.lua'
        shared=lua.execute(fixture.read_text())
        table=lambda value:lua.table_from(copy.deepcopy(value),recursive=True)
        for case in g.ALL_CASES:
            for mode in ('native','toolkit'):
                for kind in ('sp','mp'):
                    selection,row=self.evidence(case,mode,kind)
                    native=mode=='native'or case in g.MOVE_CASES;remote=kind=='mp';base_case=g.base_case(case)
                    state=table(dict(ids=row['ids'],gel=True if base_case=='styled-scissors' else None,dye=True if base_case.startswith('dye-') else None))
                    base,final,authority=table(row['baseline']),table(row['clientFinal']),table(row['receipt']['baseline'])
                    with self.subTest(case=case,mode=mode,kind=kind):
                        self.assertTrue(shared.effectsMatch(state,final,base,native,remote,authority))
                        altered=copy.deepcopy(row['clientFinal']);altered['appearance']['beardModel']='unexpected'
                        self.assertFalse(shared.effectsMatch(state,table(altered),base,native,remote,authority))
                        if base_case.startswith('dye-'):
                            altered=copy.deepcopy(row['clientFinal']);altered['dye']['amount']=.75
                            self.assertFalse(shared.effectsMatch(state,table(altered),base,native,remote,authority))
                            if remote:
                                self.assertTrue(shared.sameSetup(base,table(row['ids']['baseline'])))
                                altered=copy.deepcopy(row['baseline']);altered['dye']['color']['r']+=.01
                                self.assertFalse(shared.sameSetup(table(altered),table(row['ids']['baseline'])))

    def check_shared_fixture_luajit(self):
        luajit=shutil.which('luajit')
        if not luajit:self.skipTest('Lupa or LuaJIT required for shared fixture effects check')
        def literal(value):
            if value is None:return 'nil'
            if isinstance(value,bool):return 'true' if value else 'false'
            if isinstance(value,(int,float)):return repr(value)
            if isinstance(value,str):return json.dumps(value)
            if isinstance(value,list):return '{'+','.join(literal(v) for v in value)+'}'
            return '{'+','.join('['+literal(k)+']='+literal(v) for k,v in value.items())+'}'
        script=[r"""
          local ffi=require('ffi')
          local function f32(value)return tonumber(ffi.new('float[1]',value)[0])end
          Color={new=function()return {set=function(self,r)self.r=f32(r)end,getR=function(self)return self.r end}end}
          ImmutableColor={new=function(r,g,b)
            local c={r=f32(r),g=f32(g),b=f32(b)}
            function c:getRedInt()return math.floor(f32(self.r*255))end
            function c:getGreenInt()return math.floor(f32(self.g*255))end
            function c:getBlueInt()return math.floor(f32(self.b*255))end
            function c:getRedFloat()return self.r end
            function c:getGreenFloat()return self.g end
            function c:getBlueFloat()return self.b end
            return c
          end}
          function isClient()return true end
          local F=assert(loadfile(arg[1]))()
        """]
        for case in g.ALL_CASES:
            for mode in ('native','toolkit'):
                for kind in ('sp','mp'):
                    _,row=self.evidence(case,mode,kind);base=g.base_case(case)
                    state=dict(ids=row['ids'],gel=base=='styled-scissors',dye=base.startswith('dye-'))
                    values=[state,row['clientFinal'],row['baseline'],mode=='native' or case in g.MOVE_CASES,kind=='mp',row['receipt']['baseline']]
                    script.append('assert(F.effectsMatch('+','.join(literal(v) for v in values)+'),'+literal(case+'/'+mode+'/'+kind)+')')
                    changed=copy.deepcopy(row['clientFinal']);changed['appearance']['beardModel']='unexpected';values[1]=changed
                    script.append('assert(not F.effectsMatch('+','.join(literal(v) for v in values)+'))')
        fixture=Path(__file__).parent/'native_queue/grooming-cancel/shared/QueueGroomingCancel.lua'
        result=subprocess.run([luajit,'-',str(fixture)],input='\n'.join(script),text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_active_case_family_and_registration_are_distinct_from_waiting(self):
        from queue_checks import scenarios
        definition=g.definitions()['grooming-cancel']
        self.assertEqual(scenarios.select(definition,'cancel-active',None,'mp','toolkit')[0],g.ACTIVE_CASES)
        self.assertEqual(scenarios.select(definition,'cancel-waiting',None,'mp','toolkit')[0],g.CASES)
        for case in g.ACTIVE_CASES:
            for mode in ('native','toolkit'):
                for kind in ('sp','mp'):
                    selection,row=self.evidence(case,mode,kind);g.validate(selection)
                    with self.subTest(case=case,mode=mode,kind=kind):
                        self.assertEqual(self.check(selection,row)['activeCancelVerified'],mode=='toolkit')
                        self.assertEqual(self.report(selection,row)['issues'],[])

    def test_active_rejects_unstarted_effect_replay_or_unsealed_host_outcome(self):
        changes={
            'waiting-stage':lambda r:r['command']['boundary'].update(stage='waiting'),
            'unallocated':lambda r:r['command']['boundary'].update(bodyUnallocated=True),
            'zero-progress':lambda r:r['command']['boundary'].update(progress=0),
            'never-started':lambda r:r['command'].update(bodyStarts=0),
            'native-still-present':lambda r:r['command']['records'][1]['stoppedRemoval'].update(nativeAbsent=False),
            'foreign-native':lambda r:r['command']['records'][1]['stoppedRemoval'].update(nativeRef='foreign'),
            'finished-native':lambda r:r['command']['records'][1]['stoppedRemoval'].update(finished=True),
            'completed-effect':lambda r:r['command']['records'][1]['finishes'].append(dict(phase='complete',succeeded=True,at=12)),
            'late-start':lambda r:r['command']['records'][1].update(startedAt=12),
            'wrong-terminal':lambda r:r['command']['records'][1].update(terminal='completed'),
            'wrong-token':lambda r:r['command']['boundary']['startedReceipt'].update(token='foreign'),
            'completed-receipt':lambda r:r['command']['outcomes'][1].update(state='completed'),
            'replayed-receipt':lambda r:r['command']['outcomes'].append(r['command']['outcomes'][1]),
            'unsealed-start':lambda r:r['command']['boundary'].update(startedReceipt=False),
            'effects':lambda r:r['receipt']['final']['appearance'].update(model='CrewCut'),
        }
        for case in g.ACTIVE_CASES:
            for label,change in changes.items():
                selection,row=self.evidence(case,kind='mp');change(row)
                with self.subTest(case=case,change=label),self.assertRaises((AssertionError,KeyError,TypeError)):self.check(selection,row)

    def test_move_scenarios_preserve_all_cancel_ids_and_complete_original_effects(self):
        from queue_checks import scenarios
        definition=g.definitions()['grooming-cancel']
        self.assertEqual(g.ALL_CASES[:12],g.CASES+g.ACTIVE_CASES)
        self.assertEqual(scenarios.select(definition,'move-independent',None,'mp','toolkit')[0],g.INDEPENDENT_CASES)
        self.assertEqual(scenarios.select(definition,'move-dependent',None,'mp','toolkit')[0],g.DEPENDENT_CASES)
        for case in g.MOVE_CASES:
            for mode in ('native','toolkit'):
                for kind in ('sp','mp'):
                    selection,row=self.evidence(case,mode,kind);g.validate(selection)
                    with self.subTest(case=case,mode=mode,kind=kind):
                        result=self.check(selection,row)
                        self.assertTrue(result['moveVerified']);self.assertFalse(result['cancelled'])
                        self.assertEqual(result['moved'],mode=='toolkit' and case in g.INDEPENDENT_CASES)
                        self.assertEqual(self.report(selection,row)['issues'],[])
                        self.assertTrue(self.report(selection,row,True)['issues'])

    def test_all_six_moves_share_one_sp_host_on_off_selection_and_report(self):
        for mode in ('native','toolkit'):
            for kind in ('sp','mp'):
                rows=[self.evidence(case,mode,kind)[1] for case in g.MOVE_CASES]
                selection,_=self.evidence(g.MOVE_CASES[0],mode,kind);selection['cases']=g.MOVE_CASES.copy()
                g.validate(selection)
                with self.subTest(mode=mode,kind=kind):self.assertEqual(self.report(selection,rows)['issues'],[])
        # Native perform can publish its finish after it has begun the next reader.
        selection,row=self.evidence('move-borrowed-scissors','native','mp')
        row['command']['records'][0]['finishes'][0]['at']=51
        self.assertEqual(self.report(selection,row)['issues'],[])
        rows=[self.evidence(case,kind='mp')[1] for case in g.ALL_CASES]
        selection,_=self.evidence(kind='mp');selection['cases']=g.ALL_CASES.copy()
        self.assertEqual(self.report(selection,rows)['issues'],[])

    def test_move_rejects_detached_preparation_fabricated_success_and_missing_costs(self):
        changes={
            'wrong-operation-order':lambda r:r['command']['boundary']['afterOrder'].reverse(),
            'dropped-member':lambda r:r['command']['boundary']['group'].pop(0),
            'duplicate-member':lambda r:r['command']['boundary']['group'].append(r['command']['boundary']['body']),
            'tail-in-group':lambda r:r['command']['boundary']['group'].insert(0,r['command']['boundary']['tail']),
            'missing-front':lambda r:r['command']['boundary']['beforeOrder'].pop(0),
            'claimed-cancel':lambda r:r['command'].update(cancelled=True),
            'allocated-body':lambda r:r['command']['boundary'].update(bodyUnallocated=False),
            'wrong-permission':lambda r:r['command']['boundary'].update(accepted=not r['command']['boundary']['accepted']),
            'zero-progress':lambda r:r['command']['boundary'].update(progress=0),
            'missing-complete':lambda r:r['command'].update(bodyCompletes=0),
            'front-not-complete':lambda r:r['clientFinal'].update(frontPages=97),
            'wrong-execution-order':lambda r:next(v for v in r['command']['records'] if v['role']=='body').update(startedAt=99 if r['command']['boundary']['accepted'] else 20),
            'preparation-replay':lambda r:next(v for v in r['command']['records'] if v['role']=='body').update(starts=2),
            'unsealed-host':lambda r:r['command']['outcomes'].pop(),
            'early-return':lambda r:r['command']['records'][-1]['finishes'][0].update(at=40),
        }
        for case in ('move-borrowed-scissors','move-styled-scissors','move-dye-hair','move-beard-trim'):
            for label,change in changes.items():
                selection,row=self.evidence(case,kind='mp');change(row)
                with self.subTest(case=case,change=label),self.assertRaises((AssertionError,KeyError,TypeError)):self.check(selection,row)
        for case in ('move-styled-scissors','move-dye-hair','move-dye-beard'):
            selection,row=self.evidence(case)
            if case=='move-styled-scissors':row['clientFinal']['gel']['uses']=20
            else:row['clientFinal']['dye']['amount']=1
            with self.subTest(case=case),self.assertRaises(AssertionError):self.check(selection,row)

    def test_actual_client_move_fixture_calls_native_producer_after_both_readers(self):
        luajit=shutil.which('luajit')
        if not luajit:self.skipTest('LuaJIT required for actual client fixture regression')
        root=Path(__file__).resolve().parent/'native_queue/grooming-cancel'
        script=r"""
          local source,shared=arg[1],arg[2]
          local function set(fn,key,value)
            for i=1,100 do local name=debug.getupvalue(fn,i);if not name then break end
              if name==key then debug.setupvalue(fn,i,value);return end end
            error('missing fixture upvalue '..key)
          end
          local function get(fn,key)
            for i=1,100 do local name,value=debug.getupvalue(fn,i);if not name then break end
              if name==key then return value end end
            error('missing fixture upvalue '..key)
          end
          for _,case in ipairs({'move-borrowed-scissors','move-style-no-tool','move-styled-scissors','move-beard-trim','move-dye-hair','move-dye-beard'})do
           for _,mode in ipairs({'native','toolkit'})do
            local F=assert(loadfile(shared))()
            local config={mode=mode,cases={case},kind='sp'}
            Events=setmetatable({},{__index=function(t,k)local v={Add=function()end};t[k]=v;return v end})
            local q={queue={}};function q:indexOf(action)for i,v in ipairs(self.queue)do if v==action then return i end end;return -1 end
            local sequence,produced,edited,checkpoint=0,0,0,0
            local player={isTimedActionInstant=function()return false end,getInventory=function()return {getItemFromType=function()return nil end}end}
            local item={getID=function()return 7 end};local token={}
            local base=F.baseCase(case);local kind=base=='beard-trim'and'ISTrimBeard'or(base:find('dye-',1,true)and'ISDyeHair'or'ISCutHair')
            local borrowed=base~='style-no-tool'
            function getDebug()return false end
            function getPlayer()return player end
            function getTimestampMs()return 10 end
            ISReadABook={new=function(_,actor,book)return {Type='ISReadABook',character=actor,item=book,maxTime=100,isStarted=function()return true end,getJobDelta=function()return .2 end}end}
            ISTimedActionQueue={add=function(action)
              q.queue[#q.queue+1]=action
              if #q.queue==1 then action.action={};q.current=action end
            end}
            local function produce(actor,target,time)
              produced=produced+1
              assert(#q.queue==2 and q.queue[1].Type=='ISReadABook'and q.queue[2].Type=='ISReadABook','producer preceded independent readers')
              if borrowed then ISTimedActionQueue.add({Type='ISInventoryTransferAction',character=player,item=item,toolkitQueueOperation=token})end
              local body={Type=kind,character=player,maxTime=kind=='ISDyeHair'and 120 or(base=='style-no-tool'and 100 or 300),toolkitQueueOperation=token}
              if kind=='ISDyeHair'then body.hairDye=item else body.item=borrowed and item or nil end
              body.maxTimeInit=body.maxTime;setmetatable(body,_G[kind]);ISTimedActionQueue.add(body)
            end
            ISCharacterScreen={onCutHair=produce,onTrimBeard=produce};ISInventoryPaneContextMenu={onDyeHair=produce}
            ISCutHair={};ISTrimBeard={};ISDyeHair={}
            PZSurvivorToolkit={ActionQueuePolicy={inspect=function()return {knownInputs=F.moveAllowed(case)},'native.'..kind end},ActionQueueOperations={run=function(fn)fn()end},ActionQueue={move=function(actual,body,tail,after)
              edited=edited+1;assert(mode=='toolkit'and actual==q and tail==q.queue[2]and after==false and body==q.queue[#q.queue])
              if not F.moveAllowed(case)then return false,'dependent'end
              local moved={q.queue[1]};for i=3,#q.queue do moved[#moved+1]=q.queue[i]end;moved[#moved+1]=tail;q.queue=moved;return true
            end}}
            local proof={closure=function()return true end}
            require=function(name)if name=='QueueGroomingCancel'then return F elseif name=='QueueHealthEvents'then return {encode=function()return '{}'end}
              elseif name=='QueueTestSelection'then return config elseif name=='PZSurvivorToolkit/SourceProof'then return proof end end
            local file=assert(io.open(source));local contents=file:read('*a');file:close()
            local client=assert(loadstring(contents..'\nreturn {enqueue=enqueue,move=moveAtBoundary}'))()
            local state={player=player,front={getID=function()return 1 end},tail={getID=function()return 2 end}}
            if borrowed then state[kind=='ISDyeHair'and'dye'or(kind=='ISTrimBeard'and'razor'or'scissors')]=item end
            set(client.enqueue,'state',state);set(client.enqueue,'ids',{baseline={},actionKind=kind,targetStyle='CrewCut',targetBeard='Moustache',duration=kind=='ISDyeHair'and 120 or(base=='style-no-tool'and 100 or 300)})
            set(client.enqueue,'queue',function()return q end);set(client.enqueue,'snapshot',function()return {}end)
            set(client.enqueue,'register',function(action)
              local actions=get(client.enqueue,'actions');if actions[action]then return actions[action]end
              sequence=sequence+1;actions[action]={sequence=sequence};return actions[action]
            end)
            F.sameSetup=function()return true end
            client.enqueue();assert(produced==1 and q:indexOf(get(client.enqueue,'body'))>2)
            set(client.move,'nativeEpisodes',{[q.current]=q.current.action})
            set(client.move,'request',function(name)assert(name=='Checkpoint');checkpoint=checkpoint+1 end)
            set(client.move,'raw',function(marker,boundary)
              assert(marker=='EDIT'and boundary.stage=='move'and boundary.bodyUnallocated and boundary.tailRetained)
              assert(boundary.accepted==(mode=='toolkit'and F.moveAllowed(case)))
            end)
            client.move();assert(edited==(mode=='toolkit'and 1 or 0)and checkpoint==1)
           end
          end
        """
        result=subprocess.run([luajit,'-',str(root/'client/ZZGroomingCancel.lua'),str(root/'shared/QueueGroomingCancel.lua')],input=script,text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_requires_exact_full_pack_and_fresh_single_actor_host(self):
        for changes in ({'mods':g.MODS[:-1]},{'clients':True},{'options':{'world_template':'saved-world'}},{'kind':'mp','options':{}}):
            selection,_=self.evidence();selection.update(changes)
            with self.subTest(changes=changes),self.assertRaises(ValueError):g.validate(selection)




class GroomingRequestedOrderTests(unittest.TestCase):
    def test_unique_cases_may_run_in_requested_order_without_weakening_identity(self):
        selection=dict(suite='grooming-cancel',cases=['move-borrowed-scissors','borrowed-scissors','active-beard-trim'],
                       kind='sp',mode='native',clients=1,languages=['EN'],mods=list(g.MODS),options={})
        g.validate(selection)
        for cases in (['borrowed-scissors','borrowed-scissors'],['move-unknown'],[{}]):
            with self.subTest(cases=cases),self.assertRaises(ValueError):g.validate(dict(selection,cases=cases))

if __name__=='__main__':unittest.main()
