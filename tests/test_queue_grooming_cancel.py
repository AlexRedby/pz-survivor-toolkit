import copy
import json
import os
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
        selected=case;active=case in g.ACTIVE_CASES;moving=case in g.ALL_MOVE_CASES;case=g.base_case(case)
        native=mode=='native';completed=native or moving;mp=kind=='mp';borrowed=g.BORROWED[case]
        selection=dict(suite='grooming-cancel',cases=[case],mode=mode,kind=kind,clients=1,languages=['EN'],mods=list(g.MODS),options={'mp_host':True} if mp else {})
        names=['bag','content','front','tail','torch','secondary']+([borrowed] if borrowed else [])+(['hat'] if case in ('borrowed-scissors','dye-hair') else [])+(['mask'] if case=='dye-beard' else [])+(['gel'] if case in g.STYLING_COSTS else [])
        types=dict(bag='Base.Bag_Schoolbag',content='Base.Paperclip',front='Base.BookCarpentry1',tail='Base.BookFirstAid1',torch='Base.Torch',secondary='Base.Screwdriver',scissors='Base.Scissors',hat='Base.Hat_BaseballCap',gel='Base.Hairgel',razor='Base.Razor',dye='Base.HairDyeCommon',mask='Base.Hat_DustMask')
        if case in g.STYLING_COSTS:types['gel']=g.STYLING_COSTS[case]['kind']
        items={name:i+1 for i,name in enumerate(names)}
        ids=dict(case=case,actor=1,male=True,items=items,types={name:types[name] for name in names},initialStyle='Fabian',
                 targetStyle='PonyTail' if case=='style-no-tool' else g.STYLING_COSTS[case]['target'] if case in g.STYLING_COSTS else 'CrewCut' if case=='borrowed-scissors' else 'Fabian',
                 duration=g.duration(case),initialLevel=3,targetLevel=3 if case=='style-no-tool' or case not in g.HAIRCUT else 2 if case in ('styled-scissors','sprayed-scissors') else 1,targetAttached=case=='style-no-tool',
                 actionKind=g.BODY[case],producer=g.PRODUCER[g.BODY[case]],borrowed=borrowed,
                 initialBeard='LongScruffy' if case not in g.HAIRCUT else False,targetBeard='Moustache' if case=='beard-trim' else False,
                 beardInitialLevel=3 if case not in g.HAIRCUT else False,beardTargetLevel=1 if case=='beard-trim' else False,
                 frontInitial=97,frontTotal=100,tailInitial=99,tailTotal=100)
        baseline=dict(case=case,male=True,items=[dict(id=value,kind=types[name],container=items['bag'] if name in ('content','scissors','razor','dye') else 'root',favorite=name in ('bag','scissors','razor','dye')) for name,value in items.items()],
                      primary=items['torch'],secondary=items['secondary'],worn=[dict(id=items['bag'],location='base:back')]+([dict(id=items['hat'],location='base:hat')] if 'hat'in items else [])+([dict(id=items['mask'],location='base:mask')] if 'mask'in items else []),
                      torchActive=True,frontPages=97,tailPages=99,appearance=dict(model='Fabian',nonAttached=False,color=dict(r=.2,g=.4,b=.6),beardModel='LongScruffy' if case not in g.HAIRCUT else '',beardColor=dict(r=.3,g=.25,b=.2)),
                      gel=dict(id=items['gel'],uses=g.STYLING_COSTS[case]['initial']) if 'gel'in items else False,dye=dict(id=items['dye'],amount=1,color=dict(r=.1,g=.5,b=.9)) if 'dye'in items else False)
        if selected in g.HELD_MOVES:
            spec=g.HELD_MOVES[selected]
            baseline.update(primary=items[spec['primary']],secondary=items[spec['secondary']],hands=g.expected_hands(dict(ids,case=selected)),
                            torchActive=spec['primary']=='torch' or spec['secondary']=='torch')
            selection['options']['grooming_held_moves']=True
        authority_base=copy.deepcopy(baseline);ids['baseline']=copy.deepcopy(authority_base)
        if mp and borrowed=='dye':baseline['dye']['color']=g.fluid_wire_color(authority_base['dye']['color'])
        def final_state(initial,remote=False):
            value=copy.deepcopy(initial);value.update(frontPages=100 if moving or case=='style-no-tool' else 97,tailPages=100)
            value['appearance']=g.expected_appearance(initial,ids,completed,remote,authority_base)
            if 'gel'in items:value['gel']['uses']=g.STYLING_COSTS[case]['initial']-(g.STYLING_COSTS[case]['uses'] if completed else 0)
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
            moved=not native and selected in g.INDEPENDENT_CASES+g.HELD_CASES
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
            if selected in g.HELD_MOVES and moved:
                before['hands']=g.expected_hands(ids,True)
                for slot,hand in before['hands'].items():before[slot]=hand['id'] if hand else False
            boundary=dict(case=selected,at=10,mode=mode,kind='ISReadABook',item=items['front'],progress=.2,started=True,bodyUnallocated=True,
                          stage='move',startedReceipt=False,tailRetained=True,snapshot=copy.deepcopy(baseline),accepted=moved,
                          reason=False if native or moved else 'dependent',beforeOrder=order,afterOrder=[front['sequence']]+group+[tail['sequence']] if moved else order.copy(),
                          group=group,front=front['sequence'],tail=tail['sequence'],body=body['sequence'])
            if selected in g.HELD_MOVES:
                spec=g.HELD_MOVES[selected];hands=[(spec['primary'],True,spec['primary']==spec['secondary'])]
                for name,primary,two_hands in hands:
                    equip=record('restore','ISEquipWeaponAction',items[name]);equip.update(constructorDuration=50,startedAt=81,
                        finishes=[dict(phase='perform',succeeded=True,at=85)],restoration=dict(primary=primary,twoHands=two_hands,activated=False,begins=1,source='native.ISEquipWeaponAction'))
                    restore=record('restore','P4RestoreAction',items[name]);restore.update(constructorDuration=1,
                        finishes=[dict(phase='perform',succeeded=True,at=86)],restoration=dict(primary=False,twoHands=False,activated=name=='torch',begins=1,source='P4RestoreAction.source'))
                    records.extend((equip,restore))
                for i,value in enumerate(records,1):value['sequence']=i
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
            markers=[(marker,row['command'][key]) for marker,key in [('EDIT' if row['id'] in g.ALL_MOVE_CASES else 'CANCEL','boundary'),('BEFORE_TAIL','beforeTail'),('IDLE','idle')]]
            outcomes=row['command'].get('outcomes',[])
            if outcomes:
                if row['id'] in g.ALL_MOVE_CASES:
                    markers[1:1]=[('OUTCOME',dict(case=row['id'],receipt=value)) for value in outcomes]
                else:markers.insert(2,('OUTCOME',dict(case=row['id'],receipt=outcomes[1])))
            if reverse:markers=markers[::-1]
            lines.extend('[GROOMING_TEST] OUTCOME '+json.dumps(dict(case=row['id'],receipt=value)) for value in ([] if row['id'] in g.ALL_MOVE_CASES else outcomes[:1]))
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
                    native=mode=='native'or case in g.ALL_MOVE_CASES;remote=kind=='mp';base_case=g.base_case(case)
                    state=table(dict(ids=row['ids'],gel=True if base_case in g.STYLING_COSTS else None,dye=True if base_case.startswith('dye-') else None))
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
                    state=dict(ids=row['ids'],gel=base in g.STYLING_COSTS,dye=base.startswith('dye-'))
                    values=[state,row['clientFinal'],row['baseline'],mode=='native' or case in g.ALL_MOVE_CASES,kind=='mp',row['receipt']['baseline']]
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
        self.assertEqual(g.ALL_CASES[:2*len(g.CASES)],g.CASES+g.ACTIVE_CASES)
        self.assertEqual(scenarios.select(definition,'move-independent',None,'mp','toolkit')[0],g.INDEPENDENT_CASES)
        self.assertEqual(g.INDEPENDENT_CASES,g.MOVE_CASES)
        with self.assertRaisesRegex(ValueError,'shared/unknown material conflicts'):
            scenarios.select(definition,'move-dependent',None,'mp','toolkit')
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

    def test_all_moves_share_one_sp_host_on_off_selection_and_report(self):
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
        rows=[self.evidence(case,kind='mp')[1] for case in g.LEGACY_CASES]
        selection,_=self.evidence(kind='mp');selection['cases']=g.LEGACY_CASES.copy()
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
        for case in ('move-styled-scissors','move-sprayed-scissors','move-greased-scissors','move-dye-hair','move-dye-beard'):
            selection,row=self.evidence(case)
            if g.base_case(case) in g.STYLING_COSTS:row['clientFinal']['gel']['uses']=g.STYLING_COSTS[g.base_case(case)]['initial']
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
          for _,baseCase in ipairs(assert(loadfile(shared))().cases)do
           local case='move-'..baseCase
           for _,mode in ipairs({'native','toolkit'})do
            local F=assert(loadfile(shared))()
            local config={mode=mode,cases={case},kind='sp'}
            Events=setmetatable({},{__index=function(t,k)local v={Add=function()end};t[k]=v;return v end})
            local q={queue={}};function q:indexOf(action)for i,v in ipairs(self.queue)do if v==action then return i end end;return -1 end
            local sequence,produced,edited,checkpoint=0,0,0,0
            local item={getID=function()return 7 end};local stylingItem={getID=function()return 8 end};local token={}
            local cost=F.stylingCost(case)
            local selectors={}
            local inventory={getItemFromType=function(_,name)selectors[#selectors+1]=name;if cost and 'Base.'..name==cost.kind then return stylingItem end end}
            local player={isTimedActionInstant=function()return false end,getInventory=function()return inventory end}
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
            local state={player=player,gel=cost and stylingItem or nil,front={getID=function()return 1 end},tail={getID=function()return 2 end}}
            if borrowed then state[kind=='ISDyeHair'and'dye'or(kind=='ISTrimBeard'and'razor'or'scissors')]=item end
            set(client.enqueue,'state',state);set(client.enqueue,'ids',{case=case,baseline={},actionKind=kind,targetStyle=cost and cost.target or 'CrewCut',targetBeard='Moustache',duration=kind=='ISDyeHair'and 120 or(base=='style-no-tool'and 100 or 300)})
            set(client.enqueue,'queue',function()return q end);set(client.enqueue,'snapshot',function()return {}end)
            set(client.enqueue,'register',function(action)
              local actions=get(client.enqueue,'actions');if actions[action]then return actions[action]end
              sequence=sequence+1;actions[action]={sequence=sequence};return actions[action]
            end)
            F.sameSetup=function()return true end
            client.enqueue();assert(produced==1 and q:indexOf(get(client.enqueue,'body'))>2)
            if cost then
              local expected=cost.kind=='Base.Hairspray2'and'Hairgel,Hairspray2'or(base=='greased-scissors'and'Hairgel,Hairgel'or'Hairgel')
              assert(table.concat(selectors,',')==expected,'fixture skipped actual native styling selector path')
            end
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

    def test_expanded_styling_fixture_prepares_exact_native_resources_and_costs(self):
        luajit=shutil.which('luajit')
        if not luajit:self.skipTest('LuaJIT required for actual fixture preparation check')
        fixture=Path(__file__).parent/'native_queue/grooming-cancel/shared/QueueGroomingCancel.lua'
        script=r"""
          function isClient()return false end
          function isServer()return false end
          require=function(name)assert(name=='QueueEnergyPlacement');return function()end end
          local F=assert(loadfile(arg[1]))()
          -- Execute actual preparation/target selection; equipment color/wire setup
          -- has its own source-backed test, so stub only that separate helper.
          for i=1,100 do local name=debug.getupvalue(F.prepare,i);if not name then break end
            if name=='equipment'then debug.setupvalue(F.prepare,i,function()end);break end end
          local function list(values)return {size=function()return #values end,get=function(_,i)return values[i+1]end}end
          local function style(name,level)
            return {getName=function()return name end,getLevel=function()return level end,
              isAttachedHair=function()return false end,isNoChoose=function()return false end,getTrimChoices=function()return list({})end}
          end
          local styles={Fabian=style('Fabian',3),MohawkFan=style('MohawkFan',2),GreasedBack=style('GreasedBack',1)}
          function getHairStylesInstance()return {getAllMaleStyles=function()return list({styles.GreasedBack,styles.Fabian,styles.MohawkFan})end,
            FindMaleStyle=function(_,name)return styles[name]end}end
          local expected={['styled-scissors']={'Base.Hairgel',20,1,'MohawkFan'},
            ['sprayed-scissors']={'Base.Hairspray2',10,1,'MohawkFan'},['greased-scissors']={'Base.Hairgel',20,2,'GreasedBack'}}
          for base,cost in pairs(expected)do
            for _,prefix in ipairs({'','active-','move-'})do
              local serial=0;local root
              local function container()
                local box={items={}}
                function box:AddItem(kind)
                  serial=serial+1;local item={kind=kind,id=serial,container=self}
                  function item:getID()return self.id end
                  function item:getFullType()return self.kind end
                  function item:getContainer()return self.container end
                  function item:setFavorite(value)self.favorite=value end
                  function item:getMaxUses()return self.kind=='Base.Hairspray2'and 10 or 20 end
                  function item:setCurrentUses(value)self.uses=value end
                  function item:getCurrentUses()return self.uses end
                  function item:getNumberOfPages()return 100 end
                  if kind=='Base.Bag_Schoolbag'then local nested=container();function item:getItemContainer()return nested end end
                  self.items[#self.items+1]=item;return item
                end
                return box
              end
              root=container()
              local player={isFemale=function()return false end,getInventory=function()return root end,getOnlineID=function()return 7 end}
              for _,name in ipairs({'setGodMod','setGhostMode','setAutoDrink'})do player[name]=function()end end
              F.snapshot=function(state)return {case=state.ids.case,appearance={model=state.ids.initialStyle,nonAttached=false},
                gel={id=state.gel:getID(),uses=state.gel:getCurrentUses()},dye=false}end
              local state=F.prepare(player,prefix..base)
              assert(state.ids.case==prefix..base and state.ids.actionKind=='ISCutHair'and state.ids.producer=='ISCharacterScreen.onCutHair')
              assert(state.ids.targetStyle==cost[4]and state.ids.duration==300 and state.ids.initialStyle=='Fabian')
              assert(state.ids.borrowed=='scissors'and state.ids.types.gel==cost[1])
              assert(state.gel.kind==cost[1]and state.gel.uses==cost[2]and state.gel.container==root)
              assert(state.scissors.container==state.bag:getItemContainer()and state.scissors.favorite)
              local baseSnapshot=state.ids.baseline
              local final={appearance=F.expectedAppearance(state,baseSnapshot,true),gel={id=baseSnapshot.gel.id,uses=cost[2]-cost[3]}}
              assert(F.effectsMatch(state,final,baseSnapshot,true))
              final.gel.uses=cost[2]-cost[3]+1;assert(not F.effectsMatch(state,final,baseSnapshot,true),'missing styling use accepted')
              assert(F.effectsMatch(state,baseSnapshot,baseSnapshot,false),'canceled preparation consumed styling material')
            end
          end
        """
        result=subprocess.run([luajit,'-',str(fixture)],input=script,text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_expanded_cost_evidence_rejects_corruption_in_each_role(self):
        for case,cost in g.STYLING_COSTS.items():
            for mode in ('native','toolkit'):
                for kind in ('sp','mp'):
                    for prefix in ('','active-','move-'):
                        selected=prefix+case
                        for field in ('clientFinal','authorityFinal','beforeTail'):
                            for bad in (True,1.25,-1,cost['initial']+1):
                                selection,row=self.evidence(selected,mode,kind)
                                value=(row['clientFinal'] if field=='clientFinal' else row['receipt']['final'] if field=='authorityFinal' else row['command']['beforeTail']['snapshot'])
                                value['gel']['uses']=bad
                                with self.subTest(case=selected,mode=mode,kind=kind,field=field,bad=bad),self.assertRaises(AssertionError):self.check(selection,row)
                        for bad_cost in (0,cost['uses']+1):
                            selection,row=self.evidence(selected,mode,kind)
                            completed=mode=='native' or prefix=='move-'
                            row['receipt']['final']['gel']['uses']=cost['initial']-bad_cost if completed else cost['initial']-1
                            with self.subTest(case=selected,mode=mode,kind=kind,cost=bad_cost),self.assertRaises(AssertionError):self.check(selection,row)
                        selection,row=self.evidence(selected,mode,kind)
                        row['command']['beforeTail']['snapshot']['gel']['id']=row['ids']['items']['scissors']
                        with self.assertRaises(AssertionError):self.check(selection,row)
                        selection,row=self.evidence(selected,mode,kind)
                        row['receipt']['baseline']['gel']['uses']=cost['initial']-1
                        with self.assertRaises(AssertionError):self.check(selection,row)

    def test_two_use_host_replication_is_transient_and_final_cost_stays_exact(self):
        for mode in ('native','toolkit'):
            for kind in ('sp','mp'):
                selection,row=self.evidence('move-greased-scissors',mode,kind)
                row['command']['beforeTail']['snapshot']['gel']['uses']=19
                with self.subTest(mode=mode,kind=kind):
                    if kind=='mp' and mode=='toolkit':self.assertTrue(self.check(selection,row)['cleanupVerified'])
                    else:
                        with self.assertRaises(AssertionError):self.check(selection,row)
                selection,row=self.evidence('greased-scissors',mode,kind)
                row['command']['beforeTail']['snapshot']['gel']['uses']=19
                if kind=='mp' and mode=='native':self.assertTrue(self.check(selection,row)['cleanupVerified'])
                else:
                    with self.assertRaises(AssertionError):self.check(selection,row)
                selection,row=self.evidence('move-greased-scissors',mode,kind)
                row['clientFinal']['gel']['uses']=19
                with self.assertRaises(AssertionError):self.check(selection,row)
                selection,row=self.evidence('move-greased-scissors',mode,kind)
                row['receipt']['checkpoint']['gel']['uses']=19
                with self.assertRaises(AssertionError):self.check(selection,row)

    def test_held_bank_is_explicit_and_runs_all_three_cases_in_both_modes_and_roles(self):
        from queue_checks import scenarios
        definition=g.definitions()['grooming-cancel']
        self.assertEqual(scenarios.select(definition,'restore-hands',None,'sp','native')[0],g.HELD_CASES)
        for mode in ('native','toolkit'):
            for kind in ('sp','mp'):
                selection,_=self.evidence(g.HELD_CASES[0],mode,kind);selection['cases']=g.HELD_CASES.copy()
                g.validate(selection)
                rows=[self.evidence(case,mode,kind)[1] for case in g.HELD_CASES]
                with self.subTest(mode=mode,kind=kind):self.assertEqual(self.report(selection,rows)['issues'],[])
                for row in rows:
                    result=self.check(selection,row)
                    self.assertEqual(result['moved'],mode=='toolkit')
                    self.assertTrue(result['cleanupVerified'] and result['tailCompleted'] and result['authoritative'])
                    self.assertEqual(row['clientFinal']['hands'],g.expected_hands(row['ids']))
        selection,_=self.evidence(g.HELD_CASES[0]);selection['cases']=g.HELD_CASES.copy()
        for changes in ({'cases':g.HELD_CASES[::-1]},{'cases':g.MOVE_CASES},{'cases':g.HELD_CASES[:1]},
                        {'cases':g.HELD_CASES+[g.MOVE_CASES[0]]},{'options':{}},{'options':{'grooming_held_moves':False}}):
            with self.subTest(changes=changes),self.assertRaises(ValueError):g.validate(dict(selection,**changes))
        legacy,_=self.evidence('move-styled-scissors');g.validate(legacy)
        with self.assertRaises(ValueError):g.validate(dict(legacy,options={'grooming_held_moves':True}))

    def test_held_admission_and_restoration_reject_stowed_foreign_and_proxy_hand_refs(self):
        def stow(value):value.update(primary=False);value['hands']['primary']=False
        def wrong(value):
            source=next(row for row in value['items'] if row['kind']=='Base.Paperclip')
            value.update(primary=source['id']);value['hands']['primary'].update(id=source['id'],kind=source['kind'])
        changes={'stowed':stow,'foreign-root-member':wrong,
                 'proxy':lambda v:v['hands']['primary'].update(sameReference=False),
                 'lost-owner':lambda v:v['hands']['primary'].update(equipParent=False),
                 'not-root':lambda v:v['hands']['primary'].update(root=False),
                 'nested':lambda v:v['hands']['primary'].update(container=1),
                 'unknown-hand':lambda v:v['hands'].update(third=False),
                 'missing-slot':lambda v:v['hands'].pop('secondary'),
                 'stale-kind':lambda v:v['hands']['primary'].update(kind='Base.Hammer'),
                 'fabricated-ref':lambda v:v['hands']['primary'].update(sameReference=1)}
        for case in g.HELD_CASES:
            for mode in ('native','toolkit'):
                for kind in ('sp','mp'):
                    for place in ('baseline','admission','checkpoint','clientFinal','authorityFinal'):
                        for name,change in changes.items():
                            selection,row=self.evidence(case,mode,kind)
                            value={'baseline':row['baseline'],'admission':row['command']['boundary']['snapshot'],
                                   'checkpoint':row['receipt']['checkpoint'],'clientFinal':row['clientFinal'],'authorityFinal':row['receipt']['final']}[place]
                            change(value)
                            with self.subTest(case=case,mode=mode,kind=kind,place=place,change=name),self.assertRaises((AssertionError,KeyError,TypeError)):self.check(selection,row)
        selection,row=self.evidence('move-held-gel-both');row['command']['boundary']['snapshot']['hands']['secondary']=False
        row['command']['boundary']['snapshot']['secondary']=False
        with self.assertRaises(AssertionError):self.check(selection,row)

    def test_held_costs_topology_appearance_and_reader_effects_cannot_be_waived(self):
        for case in g.HELD_CASES:
            for mode in ('native','toolkit'):
                for kind in ('sp','mp'):
                    changes={
                        'missing-use':lambda r:r['clientFinal']['gel'].update(uses=g.STYLING_COSTS[g.base_case(case)]['initial']),
                        'extra-use':lambda r:r['receipt']['final']['gel'].update(uses=17),
                        'ghost-supply':lambda r:r['clientFinal']['items'].__setitem__(slice(None),[v for v in r['clientFinal']['items'] if v['id']!=r['ids']['items']['gel']]),
                        'nested-supply':lambda r:next(v for v in r['clientFinal']['items'] if v['id']==r['ids']['items']['gel']).update(container=r['ids']['items']['bag']),
                        'foreign-supply-id':lambda r:r['receipt']['final']['gel'].update(id=999),
                        'wrong-cosmetic':lambda r:r['receipt']['final']['appearance'].update(model='Bald'),
                        'lost-tail':lambda r:r['receipt']['final'].update(tailPages=r['ids']['tailInitial']),
                        'lost-front':lambda r:r['clientFinal'].update(frontPages=r['ids']['frontInitial']),
                        'no-scissors-return':lambda r:r['command']['records'].__setitem__(slice(None),[v for v in r['command']['records'] if v['role']!='return']),
                        'unsealed-completion':lambda r:r['command'].update(bodyCompletes=0),
                    }
                    for name,change in changes.items():
                        selection,row=self.evidence(case,mode,kind);change(row)
                        with self.subTest(case=case,mode=mode,kind=kind,change=name),self.assertRaises((AssertionError,KeyError,ValueError)):self.check(selection,row)
        # Only the Host client BEFORE_TAIL may observe the intermediate first use.
        for kind in ('sp','mp'):
            selection,row=self.evidence('move-held-gel-both','toolkit',kind)
            row['command']['beforeTail']['snapshot']['gel']['uses']=19
            if kind=='mp':self.check(selection,row)
            else:
                with self.assertRaises(AssertionError):self.check(selection,row)

    def test_held_p4_restoration_requires_native_source_begin_order_and_single_perform(self):
        changes={
            'missing':lambda rows:rows.pop(),
            'replayed':lambda rows:rows[0]['finishes'].append(copy.deepcopy(rows[0]['finishes'][0])),
            'no-begin':lambda rows:rows[0]['restoration'].update(begins=0),
            'double-begin':lambda rows:rows[0]['restoration'].update(begins=2),
            'foreign-source':lambda rows:rows[0]['restoration'].update(source='foreign.equip'),
            'foreign-item':lambda rows:rows[0].update(item=999),
            'wrong-two-hands':lambda rows:rows[0]['restoration'].update(twoHands=not rows[0]['restoration']['twoHands']),
            'wrong-duration':lambda rows:rows[0].update(constructorDuration=1),
            'early-cleanup':lambda rows:rows[0]['finishes'][0].update(at=10),
            'failed-native':lambda rows:rows[0]['finishes'][0].update(succeeded=False),
            'no-native-equip':lambda rows:rows[0].update(nativeRef=False),
        }
        for case in g.HELD_CASES:
            for mode in ('native','toolkit'):
                for kind in ('sp','mp'):
                    for name,change in changes.items():
                        selection,row=self.evidence(case,mode,kind);restores=[v for v in row['command']['records'] if v['role']=='restore'];change(restores)
                        if name=='missing':row['command']['records']=[v for v in row['command']['records'] if v['role']!='restore']+restores
                        with self.subTest(case=case,mode=mode,kind=kind,change=name),self.assertRaises((AssertionError,KeyError)):self.check(selection,row)
                    selection,row=self.evidence(case,mode,kind)
                    # Native duration-one P4 callbacks can finish between polls.
                    for value in row['command']['records']:
                        if value['kind']=='P4RestoreAction':value.update(started=False,starts=0,nativeRef=False)
                    self.check(selection,row)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_actual_held_resolve_waits_authority_and_never_repairs_equipment_or_visual(self):
        source=Path(__file__).parent/'native_queue/grooming-cancel/shared/QueueGroomingCancel.lua'
        script=r"""
local F=assert(loadfile(arg[1]))()
function isClient()return true end
Perks={Woodwork=1,Doctor=2}
for _,case in ipairs({'move-held-gel-primary','move-held-spray-secondary','move-held-gel-both'})do
 local root={};local player={getInventory=function()return root end,getOnlineID=function()return 7 end};local spec=F.held(case)
 local function item(id,kind)
  local v={getID=function()return id end,getFullType=function()return kind end,getContainer=function()return root end,getEquipParent=function()return player end}
  return v
 end
 local gel=item(1,'Base.Hairgel');local torch=item(2,'Base.Torch');local other=item(3,'Base.Screwdriver')
 local refs={gel=gel,torch=torch,secondary=other};local byID={[1]=gel,[2]=torch,[3]=other}
 function root:getItemById(id)return byID[id]end
 local primary,secondary=refs[spec.primary],refs[spec.secondary]
 function player:getPrimaryHandItem()return primary end
 function player:getSecondaryHandItem()return secondary end
 local ids={case=case,actor=7,items={gel=1,torch=2,secondary=3},frontInitial=97,tailInitial=99,baseline={}}
 local state={player=player,ids=ids};local writes=0
 F.refresh=function(s)
  s.front={setAlreadyReadPages=function(_,v)assert(v==97);writes=writes+1 end,getFullType=function()return 'front'end}
  s.tail={setAlreadyReadPages=function(_,v)assert(v==99);writes=writes+1 end,getFullType=function()return 'tail'end};return true
 end
 F.snapshot=function(s)return {hands=F.hands(s)}end
 ids.baseline=F.snapshot(state)
 function player:setAlreadyReadPages(kind,v)assert(kind=='front'and v==97 or kind=='tail'and v==99);writes=writes+1 end
 function player:setPerkLevelDebug()writes=writes+1 end
 for _,name in ipairs({'setPrimaryHandItem','setSecondaryHandItem','setWornItem','removeWornItem','updateHandEquips','getHumanVisual','resetModel'})do
  player[name]=function()error('client repaired '..name)end
 end
 sendHumanVisual=function()error('client sent visual repair')end;sendEquip=function()error('client sent equip repair')end
 local original=primary;primary=nil
 assert(not F.handsReady(state)and not F.resolve(player,ids)and writes==0,'stowed hand was admitted or repaired')
 primary=item(original:getID(),original:getFullType())
 assert(not F.handsReady(state)and not F.resolve(player,ids)and writes==0,'same-ID proxy was admitted')
 primary=original;local owner=original.getEquipParent;original.getEquipParent=function()return {}end
 assert(not F.handsReady(state)and not F.resolve(player,ids)and writes==0,'foreign equip parent was admitted')
 original.getEquipParent=owner
 assert(F.handsReady(state)and F.resolve(player,ids)and writes==6,'authority exact refs did not release reader-only setup')
 assert(F.resolve(player,ids)and writes==6,'reader setup repeated')
 secondary=nil
 assert(not F.handsReady(state)and not F.resolve(player,ids),'lost secondary was hidden after resolve')
end
"""
        result=subprocess.run([shutil.which('luajit'),'-',str(source)],input=script,text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_grooming_fixture_lua_parses(self):
        root=Path(__file__).parent/'native_queue/grooming-cancel'
        for source in root.rglob('*.lua'):
            result=subprocess.run([shutil.which('luajit'),'-',str(source)],input='assert(loadfile(arg[1]))',text=True,capture_output=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_actual_move_controller_rejects_hands_stowed_after_native_enqueue(self):
        root=Path(__file__).parent/'native_queue/grooming-cancel'
        script=r"""
local function set(fn,key,value)
 for i=1,100 do local name=debug.getupvalue(fn,i);if not name then break end;if name==key then debug.setupvalue(fn,i,value);return end end
 error('missing fixture upvalue '..key)
end
local function get(fn,key)
 for i=1,100 do local name,value=debug.getupvalue(fn,i);if not name then break end;if name==key then return value end end
 error('missing fixture upvalue '..key)
end
for _,case in ipairs({'move-held-gel-primary','move-held-spray-secondary','move-held-gel-both'})do
 for _,mode in ipairs({'native','toolkit'})do for _,scenario in ipairs({'actual','stowed','proxy','foreign-owner'})do
  local F=assert(loadfile(arg[2]))();local cost=F.stylingCost(case);local spec=F.held(case)
  local config={mode=mode,cases={case},kind='sp',options={grooming_held_moves=true}}
  Events=setmetatable({},{__index=function(t,k)local v={Add=function()end};t[k]=v;return v end})
  local q={queue={}};function q:indexOf(action)for i,v in ipairs(self.queue)do if v==action then return i end end;return -1 end
  local edited,checkpoint,serial=0,0,0;local token={};local inventory={};local player={}
  local function item(id,kind)return {getID=function()return id end,getFullType=function()return kind end,
   getContainer=function()return inventory end,getEquipParent=function()return player end}end
  local gel,torch,other,scissors=item(8,cost.kind),item(20,'Base.Torch'),item(21,'Base.Screwdriver'),item(7,'Base.Scissors')
  local refs={gel=gel,torch=torch,secondary=other};local primary,secondary=refs[spec.primary],refs[spec.secondary]
  inventory.getItemById=function(_,id)return ({[8]=gel,[20]=torch,[21]=other,[7]=scissors})[id]end
  inventory.getItemFromType=function(_,name)if 'Base.'..name==cost.kind then return gel end end
  player.getInventory=function()return inventory end;player.isTimedActionInstant=function()return false end
  player.getPrimaryHandItem=function()return primary end;player.getSecondaryHandItem=function()return secondary end
  function getDebug()return false end;function getPlayer()return player end;function getTimestampMs()return 10 end
  ISReadABook={new=function(_,actor,book)return {Type='ISReadABook',character=actor,item=book,maxTime=100,isStarted=function()return true end,getJobDelta=function()return .2 end}end}
  ISTimedActionQueue={add=function(action)q.queue[#q.queue+1]=action;if #q.queue==1 then action.action={};q.current=action end end}
  local function produce(actor,target,time)
   assert(#q.queue==2 and F.handsReady({player=player,ids={case=case,items={gel=8,torch=20,secondary=21}}}))
   ISTimedActionQueue.add({Type='ISInventoryTransferAction',character=player,item=scissors,toolkitQueueOperation=token})
   local body={Type='ISCutHair',character=player,item=scissors,maxTime=time,maxTimeInit=time,toolkitQueueOperation=token}
   setmetatable(body,ISCutHair);ISTimedActionQueue.add(body)
  end
  ISCutHair={};ISTrimBeard={};ISDyeHair={};ISCharacterScreen={onCutHair=produce};ISInventoryPaneContextMenu={}
  PZSurvivorToolkit={ActionQueuePolicy={inspect=function()return {knownInputs=true},'native.ISCutHair'end},
   ActionQueueOperations={run=function(fn)fn()end},ActionQueue={move=function(actual,body,tail,after)
    edited=edited+1;assert(mode=='toolkit'and actual==q and tail==q.queue[2]and after==false)
    q.queue={q.queue[1],q.queue[3],q.queue[4],tail};return true
   end}}
  local json={encode=function()return '{}'end};local proof={closure=function()return true end}
  require=function(name)if name=='QueueGroomingCancel'then return F elseif name=='QueueTestSelection'then return config
   elseif name=='QueueHealthEvents'then return json elseif name=='PZSurvivorToolkit/SourceProof'then return proof end end
  local file=assert(io.open(arg[1]));local source=file:read('*a');file:close()
  local client=assert(loadstring(source..'\nreturn {enqueue=enqueue,move=moveAtBoundary}'))()
  local ids={case=case,baseline={},actionKind='ISCutHair',targetStyle=cost.target,duration=300,items={gel=8,torch=20,secondary=21}}
  local state={player=player,ids=ids,gel=gel,scissors=scissors,front=item(1,'front'),tail=item(2,'tail')}
  set(client.enqueue,'state',state);set(client.enqueue,'ids',ids);set(client.enqueue,'queue',function()return q end)
  set(client.enqueue,'snapshot',function()return {hands=F.hands(state)}end)
  set(client.enqueue,'register',function(action)local actions=get(client.enqueue,'actions');if actions[action]then return actions[action]end
   serial=serial+1;actions[action]={sequence=serial};return actions[action]end)
  F.sameSetup=function()return true end
  client.enqueue();assert(q:indexOf(get(client.enqueue,'body'))==4,'producer did not preserve pending scissors group')
  if scenario=='stowed'then primary=nil
  elseif scenario=='proxy'then primary=item(primary:getID(),primary:getFullType())
  elseif scenario=='foreign-owner'then primary.getEquipParent=function()return {}end end
  set(client.move,'nativeEpisodes',{[q.current]=q.current.action})
  set(client.move,'request',function(name)assert(name=='Checkpoint');checkpoint=checkpoint+1 end)
  set(client.move,'raw',function(marker,row)
   assert(marker=='EDIT'and F.same(row.snapshot.hands,F.hands(state)))
   assert(row.snapshot.hands.primary.sameReference and row.snapshot.hands.secondary.sameReference)
  end)
  local okay=pcall(client.move)
  assert(okay==(scenario=='actual'),'stowed/proxy/foreign-owner hand passed actual move controller')
  assert(edited==(scenario=='actual'and mode=='toolkit'and 1 or 0)and checkpoint==(scenario=='actual'and 1 or 0))
 end end
end
"""
        result=subprocess.run([shutil.which('luajit'),'-',str(root/'client/ZZGroomingCancel.lua'),str(root/'shared/QueueGroomingCancel.lua')],input=script,text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_selected_p4_only_restores_changed_native_hand_refs_with_duration_one(self):
        selected=os.environ.get('PZ_TEST_P4_SOURCE')
        if not selected:self.skipTest('Set PZ_TEST_P4_SOURCE to the locked selected P4 source')
        from cart_blender import game_default
        game=Path(os.environ['PZ_GAME_DIR']) if os.environ.get('PZ_GAME_DIR') else game_default()
        source=Path(selected);version=source/'42.20' if (source/'42.20').is_dir() else source
        project=Path(__file__).resolve().parents[1]
        script=r"""
local version,game,project=arg[1],arg[2],arg[3]
local function text(path)local f=assert(io.open(path));local s=f:read('*a');f:close();return s end
local function reader(path)
 local f=io.open(path);if not f then return end
 return {readLine=function()local line=f:read('*l');return line and line:gsub('\r$','')end,close=function()f:close()end}
end
getGameFilesInput=function(path)return reader(game..'/'..path)end
getModFileReader=function(mod,path)assert(mod=='P4TidyUpMeister');return reader(version..'/'..path)end
getFilenameOfClosure=function(fn)return debug.getinfo(fn,'S').source:gsub('^@','')end
local Proof=assert(loadfile(project..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'))()
assert(Proof.matches('media/lua/client/P4TidyUpMeister.lua',389269229,'P4TidyUpMeister',true),'selected P4 source pin differs')
assert(Proof.matches('media/lua/shared/TimedActions/P4RestoreAction.lua',1645293368,'P4TidyUpMeister',true),'selected P4 restore pin differs')
assert(loadfile(game..'/media/lua/shared/ISBaseObject.lua'))()
package.preload.ISBaseObject=function()return ISBaseObject end
package.preload['TimedActions/ISBaseTimedAction']=function()assert(loadfile(game..'/media/lua/shared/TimedActions/ISBaseTimedAction.lua'))();return ISBaseTimedAction end
assert(loadfile(game..'/media/lua/shared/TimedActions/ISEquipWeaponAction.lua'))()
assert(loadfile(game..'/media/lua/shared/TimedActions/ISCutHair.lua'))()
assert(loadfile(version..'/media/lua/shared/TimedActions/P4RestoreAction.lua'))()
local p4=text(version..'/media/lua/client/P4TidyUpMeister.lua')
local function method(name,nextName)
 local first=assert(p4:find('P4TidyUpMeister.'..name..' = function',1,true))
 local last=assert(p4:find('\nP4TidyUpMeister.'..nextName..' = function',first,true))
 assert(loadstring(p4:sub(first,last-1),'@P4TidyUpMeister.lua'))()
end
local function list(items)return {size=function()return #items end,get=function(_,i)return items[i+1]end}end
P4TidyUpMeister={sessions={},restoring={},restoreFloor={},nextSessionId=1,
 debugLog=function()end,debugHalo=function()end,itemLabel=function()return 'item'end,
 findReplacementItems=function()return {}end,queueTransferRestores=function()end}
method('captureSession','actionTypeOf');method('shouldObserveCharacter','prepareQueueAdd')
method('prepareQueueAdd','observeQueuedAction');method('queueRestore','forceRestoreHands')
local characterScreen=text(game..'/media/lua/client/XpSystem/ISUI/ISCharacterScreen.lua')
local worldMenu=text(game..'/media/lua/client/ISUI/ISWorldObjectContextMenu.lua')
ISCharacterScreen={};ISWorldObjectContextMenu={}
local first=assert(characterScreen:find('ISCharacterScreen.onCutHair = function',1,true))
local last=assert(characterScreen:find('\nISCharacterScreen.setDisplayedTraits',first,true))
assert(loadstring(characterScreen:sub(first,last-1),'@ISCharacterScreen.lua'))()
first=assert(worldMenu:find('ISWorldObjectContextMenu.equip = function',1,true));last=assert(worldMenu:find('\nISWorldObjectContextMenu.equip2',first,true))
assert(loadstring(worldMenu:sub(first,last-1),'@ISWorldObjectContextMenu.lua'))()
local F=assert(loadfile(project..'/tests/native_queue/grooming-cancel/shared/QueueGroomingCancel.lua'))()
isServer=function()return false end;getPlayerHotbar=function()return nil end
ItemTag={LIGHTER='Lighter'}
getPlayerInventory=function()return {refreshBackpacks=function()end}end
getText=function(key)return key end;getDebug=function()return false end
getHairStylesInstance=function()return {FindMaleStyle=function(_,name)return {getName=function()return name end,isAttachedHair=function()return false end}end}end
predicateScissors={};predicateRazor={}
for _,case in ipairs({'move-held-gel-primary','move-held-spray-secondary','move-held-gel-both'})do
 local spec=F.held(case);local player,root={},{};local primary,secondary;local queued={}
 local function item(id,kind,active)
  local value={id=id,kind=kind,active=active or false}
  function value:getID()return self.id end;function value:getFullType()return self.kind end
  function value:getContainer()return root end;function value:getEquipParent()return player end
  function value:canBeActivated()return self.kind=='Base.Torch'end
  function value:isActivated()return self.active end;function value:setActivated(v)self.active=v end
  function value:isRequiresEquippedBothHands()return false end;function value:getName()return self.kind end
  function value:getCurrentUsesFloat()return 20 end;function value:hasTag()return false end
  function value:playActivateSound()end
  return value
 end
 local gel=item(8,F.stylingCost(case).kind);local torch=item(20,'Base.Torch',true);local other=item(21,'Base.Screwdriver');local scissors=item(7,'Base.Scissors')
 local refs={gel=gel,torch=torch,secondary=other};primary,secondary=refs[spec.primary],refs[spec.secondary]
 local initialPrimary,initialSecondary=primary,secondary
 function root:getItems()return list({gel,torch,other,scissors})end
 function root:getItemById(id)return ({[8]=gel,[20]=torch,[21]=other,[7]=scissors})[id]end
 function root:getFirstEvalRecurse(predicate)if predicate==predicateScissors then return scissors end end
 function player:getPrimaryHandItem()return primary end;function player:getSecondaryHandItem()return secondary end
 function player:setPrimaryHandItem(v)primary=v end;function player:setSecondaryHandItem(v)secondary=v end
 function player:getInventory()return root end;function player:getWornItems()return list({})end
 function player:getModData()return {}end;function player:isLocalPlayer()return true end
 function player:isFemale()return false end;function player:getClothingItem_Head()return nil end
 function player:getVisual()return {getNonAttachedHair=function()return nil end}end
 function player:getPlayerNum()return 0 end;function player:isTimedActionInstant()return false end
 function player:getClothingItem_Back()return nil end;function player:isEquippedClothing()return false end
 function player:getCurrentSquare()return nil end
 instanceof=function(object,kind)return object==player and kind=='IsoPlayer'or object==scissors and kind=='InventoryItem'end
 local queue={queue={}}
 ISTimedActionQueue={getTimedActionQueue=function()return queue end,add=function(action)queued[#queued+1]=action end}
 local session=P4TidyUpMeister.prepareQueueAdd({Type='ISReadABook',character=player})
 assert(session.primaryItem==initialPrimary and session.secondaryItem==initialSecondary)
 assert(primary==initialPrimary and secondary==initialSecondary,'P4 enqueue stowed actual held supply')
 ISWorldObjectContextMenu.transferIfNeeded=function(actor,item)
  assert(actor==player and item==scissors);queued[#queued+1]={Type='ISInventoryTransferAction',item=item}
 end
 ISCharacterScreen.onCutHair(player,F.stylingCost(case).target,300)
 assert(#queued==3 and queued[1].Type=='ISInventoryTransferAction'and queued[2].Type=='ISEquipWeaponAction'and queued[3].Type=='ISCutHair')
 assert(primary==initialPrimary and secondary==initialSecondary,'native producer stowed held input before move admission')
 assert(F.handsReady({player=player,ids={case=case,items={gel=8,torch=20,secondary=21}}}))
 assert(queued[2]:complete(),'native scissors equip did not complete')
 local expectedSecondary=initialSecondary;if spec.primary==spec.secondary then expectedSecondary=nil end
 assert(primary==scissors and secondary==expectedSecondary,'native scissors preparation hand transition differs')
 session.restoreHands=true;queued={};P4TidyUpMeister.queueRestore(session)
 assert(#queued==2,'selected P4 manufactured restoration for unchanged secondary')
 assert(queued[1].Type=='ISEquipWeaponAction'and queued[1].item==initialPrimary and queued[1].primary and queued[1].twoHands==(spec.primary==spec.secondary)and queued[1].maxTime==50)
 assert(queued[2].Type=='P4RestoreAction'and queued[2].item==initialPrimary and queued[2].maxTime==1)
 assert(queued[1]:complete()and queued[2]:complete())
 assert(primary==initialPrimary and secondary==initialSecondary,'native P4 hand restoration changed captured refs')
 queued={};P4TidyUpMeister.queueRestore(session)
 assert(#queued==0,'selected P4 re-equipped already restored hands')
end
"""
        result=subprocess.run([shutil.which('luajit'),'-',str(version),str(game),str(project)],input=script,text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_actual_equipment_setup_activates_only_the_held_bank_torch(self):
        fixture=Path(__file__).parent/'native_queue/grooming-cancel/shared/QueueGroomingCancel.lua'
        script=r"""
local F=assert(loadfile(arg[1]))()
local file=assert(io.open(arg[1]));local source=file:read('*a');file:close()
local body=assert(source:match('(local function equipment.-)\nfunction F%.prepare'))
local equipment=assert(loadstring('return function(F,clearHead,Perks)\n'..body..'\nreturn equipment end'))()(F,function()end,{Woodwork=1,Doctor=2})
ImmutableColor={new=function(...)return {...}end}
local visual={};for _,name in ipairs({'setHairModel','setNonAttachedHair','setHairColor','setBeardColor','setBeardModel'})do visual[name]=function()end end
for _,case in ipairs({'move-held-gel-primary','move-held-spray-secondary','move-held-gel-both','move-styled-scissors'})do
 local player={getHumanVisual=function()return visual end};local primary,secondary,activation
 function player:setPrimaryHandItem(value)primary=value end;function player:setSecondaryHandItem(value)secondary=value end
 for _,name in ipairs({'setWornItem','resetModel','setAlreadyReadPages','setPerkLevelDebug'})do player[name]=function()end end
 local function item(id)
  return {getID=function()return id end,canBeEquipped=function()return 'back'end,setUsedDelta=function()end,
   setActivated=function(_,value)activation=value end,getFullType=function()return 'book'end,setAlreadyReadPages=function()end}
 end
 local state={player=player,gel=item(1),torch=item(2),secondary=item(3),bag=item(4),front=item(5),tail=item(6),
  ids={case=case,initialStyle='Fabian',frontInitial=217,tailInitial=219}}
 local spec=F.held(case);local expected=not spec or spec.primary=='torch'or spec.secondary=='torch'
 equipment(state)
 assert(activation==expected,'unstable active unheld Torch seeded by actual equipment helper')
 assert(primary==(spec and state[spec.primary]or state.torch)and secondary==(spec and state[spec.secondary]or state.secondary))
 local base={items={},worn={},primary=primary:getID(),secondary=secondary:getID(),torchActive=expected,hands={primary=primary:getID(),secondary=secondary:getID()}}
 state.ids.baseline=base
 assert(F.restored(state,base),'settled native Torch baseline was not restorable')
 local altered={};for key,value in pairs(base)do altered[key]=value end;altered.torchActive=not expected
 assert(not F.restored(state,altered),'opposite final Torch state was waived')
end
"""
        result=subprocess.run([shutil.which('luajit'),'-',str(fixture)],input=script,text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_held_torch_activation_is_spec_pinned_and_restored_in_each_role(self):
        for case in g.HELD_CASES:
            for mode in ('native','toolkit'):
                for kind in ('sp','mp'):
                    selection,row=self.evidence(case,mode,kind);spec=g.HELD_MOVES[case]
                    expected=spec['primary']=='torch' or spec['secondary']=='torch'
                    self.assertIs(row['baseline']['torchActive'],expected)
                    self.check(selection,row)
                    for place in ('baseline','clientFinal','authorityFinal'):
                        selection,row=self.evidence(case,mode,kind)
                        value={'baseline':row['baseline'],'clientFinal':row['clientFinal'],'authorityFinal':row['receipt']['final']}[place]
                        value['torchActive']=not expected
                        with self.subTest(case=case,mode=mode,kind=kind,place=place),self.assertRaises(AssertionError):self.check(selection,row)
                    selection,row=self.evidence(case,mode,kind)
                    # Matching forged baseline/final booleans cannot define a new bank contract.
                    for value in (row['ids']['baseline'],row['baseline'],row['receipt']['baseline'],row['receipt']['checkpoint'],
                                  row['receipt']['final'],row['clientFinal'],row['command']['boundary']['snapshot'],row['command']['idle']['snapshot']):
                        value['torchActive']=not expected
                    with self.assertRaises(AssertionError):self.check(selection,row)

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT unavailable')
    def test_pre_enqueue_mismatch_records_actual_state_without_normalizing_it(self):
        fixture=Path(__file__).parent/'native_queue/grooming-cancel/client/ZZGroomingCancel.lua'
        script=r"""
local file=assert(io.open(arg[1]));local source=file:read('*a');file:close()
local first=assert(source:find('local function enqueue()',1,true));local last=assert(source:find(' baseline=actual;',first,true))
local prefix=source:sub(first,last+#' baseline=actual;'-1)
local F={sameSetup=function(a,b)return a.torchActive==b.torchActive end}
local actual={torchActive=false,hands={primary={id=1,sameReference=true}},appearance={model='Fabian'}}
local expected={torchActive=true,hands=actual.hands,appearance=actual.appearance}
local publications={};local baseline
local enqueue=assert(loadstring('return function(F,snapshot,ids,case,now,raw)\n'..prefix..'\nend\nreturn enqueue end'))()(F,
 function()return actual end,{baseline=expected},function()return 'move-held-gel-primary'end,function()return 3 end,
 function(marker,row)publications[#publications+1]={marker,row}end)
assert(not pcall(enqueue),'baseline mismatch proceeded to native enqueue')
assert(#publications==1 and publications[1][1]=='BASELINE_MISMATCH')
local row=publications[1][2]
assert(row.actual==actual and row.expected==expected and row.at==3 and row.actual.torchActive==false and row.expected.torchActive==true)
assert(actual.hands.primary.sameReference and actual.appearance.model=='Fabian','diagnostic changed physical witness')
"""
        result=subprocess.run([shutil.which('luajit'),'-',str(fixture)],input=script,text=True,capture_output=True)
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
