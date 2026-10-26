import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from queue_checks.adapters import grooming_cancel as g


class GroomingCancellationTests(unittest.TestCase):
    def evidence(self,case='borrowed-scissors',mode='toolkit',kind='sp'):
        native=mode=='native';mp=kind=='mp';borrowed=g.BORROWED[case]
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
            value=copy.deepcopy(initial);value.update(frontPages=100 if case=='style-no-tool' else 97,tailPages=100)
            value['appearance']=g.expected_appearance(initial,ids,native,remote,authority_base)
            if 'gel'in items:value['gel']['uses']=19 if native else 20
            if 'dye'in items:value['dye']['amount']=.5 if native else 1
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
        row=dict(event='case',id=case,status='passed',ids=ids,baseline=baseline,command=command,receipt=receipt,clientFinal=final,nativeMethodsUnchanged=True)
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
        context=dict(suite='grooming-cancel',kind=selection['kind'],mode=selection['mode'],actor='client1')
        lines=['[QUEUE_CHECK] '+json.dumps(dict(event='setup',cases=selection['cases'],nativeDurations=True,queueEnabled=selection['mode']=='toolkit',**context))]
        authority=['[GROOMING_TEST] '+marker+' '+json.dumps(value) for marker,value in [('PREPARED',row['ids']),('BASELINED',row['receipt']['baseline']),('VERIFIED',row['receipt'])]]
        markers=[(marker,row['command'][key]) for marker,key in [('CANCEL','boundary'),('BEFORE_TAIL','beforeTail'),('IDLE','idle')]]
        if reverse:markers=markers[::-1]
        lines.extend('[GROOMING_TEST] '+marker+' '+json.dumps(value) for marker,value in markers)
        lines.append('[QUEUE_CHECK] '+json.dumps(dict(row,**context)))
        lines.append('[QUEUE_CHECK] '+json.dumps(dict(event='complete',cases=selection['cases'],performed=1,skipped=0,failed=0,**context)))
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

    def test_actual_shared_fixture_preserves_unpaid_effects_and_native_protocol(self):
        # Execute the shipped fixture helpers; mock only native numeric value objects.
        from lupa.lua51 import LuaRuntime
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
        for case in g.CASES:
            for mode in ('native','toolkit'):
                for kind in ('sp','mp'):
                    selection,row=self.evidence(case,mode,kind)
                    native=mode=='native';remote=kind=='mp'
                    state=table(dict(ids=row['ids'],gel=True if case=='styled-scissors' else None,dye=True if case.startswith('dye-') else None))
                    base,final,authority=table(row['baseline']),table(row['clientFinal']),table(row['receipt']['baseline'])
                    with self.subTest(case=case,mode=mode,kind=kind):
                        self.assertTrue(shared.effectsMatch(state,final,base,native,remote,authority))
                        altered=copy.deepcopy(row['clientFinal']);altered['appearance']['beardModel']='unexpected'
                        self.assertFalse(shared.effectsMatch(state,table(altered),base,native,remote,authority))
                        if case.startswith('dye-'):
                            altered=copy.deepcopy(row['clientFinal']);altered['dye']['amount']=.75
                            self.assertFalse(shared.effectsMatch(state,table(altered),base,native,remote,authority))
                            if remote:
                                self.assertTrue(shared.sameSetup(base,table(row['ids']['baseline'])))
                                altered=copy.deepcopy(row['baseline']);altered['dye']['color']['r']+=.01
                                self.assertFalse(shared.sameSetup(table(altered),table(row['ids']['baseline'])))

    def test_requires_exact_full_pack_and_fresh_single_actor_host(self):
        for changes in ({'mods':g.MODS[:-1]},{'clients':True},{'cases':g.CASES[::-1]},{'options':{'world_template':'saved-world'}},{'kind':'mp','options':{}}):
            selection,_=self.evidence();selection.update(changes)
            with self.subTest(changes=changes),self.assertRaises(ValueError):g.validate(selection)


if __name__=='__main__':unittest.main()
