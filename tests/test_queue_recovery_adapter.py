"""Causal negative mutations for native queue-remainder recovery receipts."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from queue_checks.adapters import queue_recovery as a


class RecoveryAdapterTests(unittest.TestCase):
    def selection(self,kind='mp',mode='toolkit'):
        return dict(suite='queue-recovery',cases=list(a.CASES),kind=kind,mode=mode,clients=1,languages=['EN'],mods=list(a.MODS),options={'mp_host':True}if kind=='mp'else{})

    def evidence(self,case='movement-cancel',kind='mp',mode='toolkit'):
        spec=dict(case=case,mode=mode,tv=dict(x=9,y=20,z=0,index=1),origin=dict(x=10,y=20,z=0),
                  front=dict(id=101,type='Base.BookCarpentry1',pages=220,initial=217),tail=dict(id=102,type='Base.BookCooking1',pages=220,initial=218))
        def snapshot(phase):
            return dict(case=case,tv=copy.deepcopy(spec['tv']),rootIds=[101,102],carriedIds=[101,102],
                        device=dict(on=True,power=1,powerable=True,volume=.5 if phase=='input'else .25 if phase=='final'and mode=='toolkit'else .4,channel=90000,hasMedia=False),
                        books={name:dict(id=s['id'],type=s['type'],root=True,count=1,total=220,
                                         pages=220 if phase=='final'and mode=='toolkit'else 217 if name=='front'and phase=='input'else 218,
                                         characterPages=220 if phase=='final'and mode=='toolkit'else 217 if name=='front'and phase=='input'else 218)
                               for name,s in ((n,spec[n])for n in ('front','tail'))})
        names=['prefix','front','volume','tail']+(a.STARTS[2:]if mode=='toolkit'else[])
        commands=[];acks=[]
        for i,name in enumerate(names):
            book=name in ('front','tail','restoredFront','restoredTail');start=name in (a.STARTS if mode=='toolkit'else a.STARTS[:2])
            row=dict(name=name,type='ISReadABook'if book else'ISRadioAction',mode=''if book else'SetVolume',duration=79200 if book else 30,
                     producer='native ISReadABook constructor'if book else'recovery native ISRadioAction constructor'if name=='restoredVolume'else'native RWM callback',cancelled=name in a.ORIGINAL,
                     started=start,progress=start,token=i+1,itemId=101 if name in ('front','restoredFront')else 102 if book else False,
                     initialPages=217 if name=='front'else 218 if book else False)
            if start:row.update(effectiveDuration=row['duration'],nativeDurationBefore=row['duration'],nativeDurationAfter=row['duration'],durationSampleBefore=10,durationSampleAfter=20,allocatedAt=20,startedAt=30,durationSamples=2)
            if kind=='mp'and not book and start:
                ack=dict(kind='ISRadioAction',transaction=i+1,token=f'{i+1:08x}-1234-1234-1234-123456789abc',state='completed');row['ack']=ack
                acks.extend(dict(case=case,name=name,**{k:ack[k]for k in ('kind','transaction','token')},state=state)for state in ('started','completed'))
            commands.append(row)
        def physical_steps(tokens,restored=False):
            names=['front','approach','volume','tail'] if mode=='toolkit' else ['front','volume','tail']
            return [dict(name=name,
                         type='ISQueueActionsAction' if name=='approach' or restored and name in ('front','tail') else 'ISRadioAction' if name=='volume' else 'ISReadABook',
                         token=tokens[0 if name=='front' else 2 if name=='tail' else 1],
                         approach=dict(owned=True,helper='walkAdj',target=dict(x=9,y=20,z=0)) if name=='approach' else False)
                    for name in names]
        def projection_ui(tokens):
            def sample(expanded):
                specs=[(1,False,1,1,1,1),(2,True,2,3,2,3)]
                if expanded:specs.extend([(2,False,2,2,2,3),(3,False,3,3,2,3)])
                specs.append((4,False,4,4,4,4))
                return dict(currentIndex=1,stableRows=True,rows=[dict(actionIndex=index,header=header,first=first,last=last,
                    groupFirst=group_first,groupLast=group_last,token=tokens[0 if index==1 else 2 if index==4 else 1])
                    for index,header,first,last,group_first,group_last in specs])
            return dict(nativeUI=True,nativeSnapshot=True,stableReuse=True,actionsUnchanged=True,expansionRestored=True,
                        hiddenCleared=True,reopened=True,visibilityRestored=True,queueCount=4,groups=3,
                        operation=tokens[1],collapsed=sample(False),expanded=sample(True),reopenedView=sample(False))
        baseline,final=snapshot('baseline'),snapshot('final')
        recovery=dict(available=mode=='toolkit',restored=mode=='toolkit',historyAbsent=True,duplicateRejected=True)
        if mode=='toolkit':recovery.update(id=1,count=3,skipped=0,tokens=[5,6,7],steps=physical_steps([5,6,7],True),previewPure=True,
            previewWorkload=dict(elapsedMs=1700,previews=6,plans=0,nativeUI=True),projectionUI=projection_ui([5,6,7]))
        idle=dict(elapsedMs=1700,draws=30,carriedCalls=0,rowClears=0,selectorClears=0)
        wishlist=dict(empty=copy.deepcopy(idle),collapsed=copy.deepcopy(idle),
                      expanded=dict(amount=7,carried=1,firstDrawFresh=True),reopened=True,removed=True,restored=True)
        row=dict(suite='queue-recovery',event='case',id=case,actor='client1',kind=kind,mode=mode,status='passed',ids=copy.deepcopy(spec),
                 input=snapshot('input'),baseline=copy.deepcopy(baseline),authorityBaseline=copy.deepcopy(baseline),client=copy.deepcopy(final),server=copy.deepcopy(final),
                 commands=commands,order=list(a.STARTS if mode=='toolkit'else a.STARTS[:2]),
                 cancellation=dict(entrypoint='IsoGameCharacter.StopAllActionQueueWalking'if case=='movement-cancel'else'ISTimedActionQueue.clear',before=copy.deepcopy(baseline),initialQueue=['front','approach','volume','tail']if mode=='toolkit'else list(a.ORIGINAL),steps=physical_steps([2,3,4]),drained=True,movementStopped=True,nativeCount=1,oldTokens=[dict(id=i,cancelled=True)for i in (2,3,4)]),
                 recovery=recovery,wishlist=wishlist,restoredQueue=['front','approach','volume','tail']if mode=='toolkit'else[],queueIdle=True,settleMilliseconds=1000)
        if mode=='toolkit':row['cancellation']['projectionUI']=projection_ui([2,3,4])
        return row,spec,baseline,final,acks

    def check(self,evidence,selection=None):
        row,spec,baseline,final,acks=evidence
        return a.check_case(row,row['id'],selection or self.selection(),spec,baseline,final,acks)

    def test_all_four_modes_two_cases(self):
        for kind in ('sp','mp'):
            for mode in ('native','toolkit'):
                selection=self.selection(kind,mode);a.validate(selection)
                for case in a.CASES:
                    with self.subTest(kind=kind,mode=mode,case=case):self.assertEqual(self.check(self.evidence(case,kind,mode),selection),[])

    def test_causal_receipt_mutations_fail(self):
        changes={
            'wrong world identity':lambda r:r['client']['tv'].update(index=8),
            'wrong authoritative item':lambda r:r['authorityBaseline']['books']['front'].update(id=999),
            'front did not progress':lambda r:r['baseline']['books']['front'].update(pages=217,characterPages=217),
            'already complete captured':lambda r:r['baseline']['books']['front'].update(pages=220,characterPages=220),
            'tail started before cancellation':lambda r:r['baseline']['books']['tail'].update(pages=219,characterPages=219),
            'old token still live':lambda r:r['cancellation']['oldTokens'][0].update(cancelled=False),
            'old token reused':lambda r:r['recovery'].update(tokens=[2,6,7]),
            'prefix token reused':lambda r:r['recovery'].update(tokens=[1,6,7]),
            'duplicate new token':lambda r:r['recovery'].update(tokens=[5,5,7]),
            'wrong pending order':lambda r:r.update(restoredQueue=['front','tail','volume']),
            'original preparation missing':lambda r:r['cancellation']['steps'].pop(1),
            'original preparation reordered':lambda r:r['cancellation']['steps'].reverse(),
            'original preparation foreign helper':lambda r:r['cancellation']['steps'][1]['approach'].update(helper='walkToObject'),
            'original preparation foreign target':lambda r:r['cancellation']['steps'][1]['approach']['target'].update(x=8),
            'original preparation unowned':lambda r:r['cancellation']['steps'][1]['approach'].update(owned=False),
            'original preparation wrong token':lambda r:r['cancellation']['steps'][1].update(token=2),
            'restored preparation missing':lambda r:r['recovery']['steps'].pop(1),
            'restored preparation reordered':lambda r:r['recovery']['steps'].reverse(),
            'restored preparation wrong token':lambda r:r['recovery']['steps'][1].update(token=5),
            'restored volume split token':lambda r:r['recovery']['steps'][2].update(token=7),
            'restored hidden command':lambda r:r['recovery']['steps'].insert(2,copy.deepcopy(r['recovery']['steps'][1])),
            'restored token coerced':lambda r:r['recovery']['steps'][1].update(token=6.0),
            'restored ownership coerced':lambda r:r['recovery']['steps'][1]['approach'].update(owned=1),
            'restored native read bypassed':lambda r:r['recovery']['steps'][0].update(type='ISReadABook'),
            'new native action old token':lambda r:r['commands'][4].update(token=2),
            'prefix replayed':lambda r:r['order'].insert(2,'prefix'),
            'missing restored tail':lambda r:r['commands'].pop(),
            'false constructor source':lambda r:r['commands'][4].update(producer='manual effects'),
            'restored progress lost':lambda r:r['commands'][4].update(initialPages=217),
            'wrong read object':lambda r:r['commands'][4].update(itemId=102),
            'instant reader':lambda r:r['commands'][4].update(effectiveDuration=0),
            'stale duration bracket':lambda r:r['commands'][4].update(durationSampleBefore=999),
            'wide native bracket':lambda r:r['commands'][4].update(nativeDurationAfter=79300),
            'restore repeated':lambda r:r['recovery'].update(duplicateRejected=False),
            'history retained':lambda r:r['recovery'].update(historyAbsent=False),
            'preview changed state':lambda r:r['recovery'].update(previewPure=False),
            'preview still plans':lambda r:r['recovery']['previewWorkload'].update(plans=1),
            'preview not observed':lambda r:r['recovery']['previewWorkload'].update(previews=0),
            'empty wishlist scans':lambda r:r['wishlist']['empty'].update(carriedCalls=1),
            'collapsed wishlist rebuilds':lambda r:r['wishlist']['collapsed'].update(rowClears=1),
            'collapsed selector rebuilds':lambda r:r['wishlist']['collapsed'].update(selectorClears=1),
            'wishlist stale expansion':lambda r:r['wishlist']['expanded'].update(firstDrawFresh=False),
            'wishlist request missing':lambda r:r['wishlist']['expanded'].update(amount=1),
            'wishlist cleanup missing':lambda r:r['wishlist'].update(restored=False),
            'old java not drained':lambda r:r['cancellation'].update(drained=False),
            'movement ongoing':lambda r:r['cancellation'].update(movementStopped=False),
            'no active native':lambda r:r['cancellation'].update(nativeCount=0),
            'wrong entrypoint':lambda r:r['cancellation'].update(entrypoint='synthetic forceStop'),
            'front final not committed':lambda r:r['server']['books']['front'].update(characterPages=218),
            'volume effect missing':lambda r:r['server']['device'].update(volume=.4),
            'unrelated item lost':lambda r:r['client'].update(rootIds=[101],carriedIds=[101]),
            'foreign item added':lambda r:r['server']['carriedIds'].append(999),
            'duplicate item':lambda r:r['client']['books']['tail'].update(count=2),
            'nested tail':lambda r:r['client']['books']['tail'].update(root=False),
            'tail never started':lambda r:r['order'].pop(),
        }
        for label,change in changes.items():
            with self.subTest(label=label):
                evidence=self.evidence();change(evidence[0]);self.assertTrue(self.check(evidence),label)

    def test_native_controls_retain_cancellation(self):
        for change in (lambda r:r['client']['device'].update(volume=.25),lambda r:r['recovery'].update(historyAbsent=False),
                       lambda r:r['client']['books']['tail'].update(pages=220,characterPages=220),lambda r:r['order'].append('restoredTail')):
            evidence=self.evidence(mode='native');change(evidence[0]);self.assertTrue(self.check(evidence,self.selection(mode='native')))

    def test_production_projection_receipts_are_required_and_exact(self):
        for phase in ('cancellation','recovery'):
            changes={
                'missing receipt':lambda r:r.pop('projectionUI'),
                'false receipt':lambda r:r.update(projectionUI=False),
                'missing native panel':lambda r:r['projectionUI'].update(nativeUI=False),
                'Lua fallback':lambda r:r['projectionUI'].update(nativeSnapshot=False),
                'snapshot not reused':lambda r:r['projectionUI'].update(stableReuse=False),
                'queue mutated':lambda r:r['projectionUI'].update(actionsUnchanged=False),
                'expansion retained':lambda r:r['projectionUI'].update(expansionRestored=False),
                'hidden projection recreated':lambda r:r['projectionUI'].update(hiddenCleared=False),
                'missing hidden check':lambda r:r['projectionUI'].pop('hiddenCleared'),
                'reopen failed':lambda r:r['projectionUI'].update(reopened=False),
                'missing reopen check':lambda r:r['projectionUI'].pop('reopened'),
                'visibility retained':lambda r:r['projectionUI'].update(visibilityRestored=False),
                'reopened rows missing':lambda r:r['projectionUI'].pop('reopenedView'),
                'reopened current stale':lambda r:r['projectionUI']['reopenedView'].update(currentIndex=2),
                'wrong operation':lambda r:r['projectionUI'].update(operation=999),
                'stale current':lambda r:r['projectionUI']['collapsed'].update(currentIndex=2),
                'false stable rows':lambda r:r['projectionUI']['expanded'].update(stableRows=False),
                'missing child':lambda r:r['projectionUI']['expanded']['rows'].pop(2),
                'split volume token':lambda r:r['projectionUI']['expanded']['rows'][3].update(token=999),
                'stale bounds':lambda r:r['projectionUI']['collapsed']['rows'][1].update(last=2),
                'coerced header':lambda r:r['projectionUI']['expanded']['rows'][1].update(header=1),
                'coerced current':lambda r:r['projectionUI']['expanded'].update(currentIndex=True),
            }
            for label,change in changes.items():
                with self.subTest(phase=phase,label=label):
                    evidence=self.evidence();change(evidence[0][phase]);self.assertTrue(self.check(evidence),label)
        # Queue-off controls intentionally have no production projection receipt.
        self.assertEqual(self.check(self.evidence(mode='native'),self.selection(mode='native')),[])

    def test_wire_receipts_are_exact_and_ordered(self):
        for mutation in ('missing','duplicate','reverse','foreign','terminal'):
            evidence=self.evidence();acks=evidence[-1]
            if mutation=='missing':acks.pop()
            elif mutation=='duplicate':acks.append(copy.deepcopy(acks[-1]))
            elif mutation=='reverse':acks.reverse()
            elif mutation=='foreign':acks[-1]['token']='deadbeef-1234-1234-1234-123456789abc'
            else:acks[-1]['state']='cancelled'
            self.assertTrue(self.check(evidence),mutation)

    def test_complete_log_authority_order_and_duplicates(self):
        selection=self.selection()
        with tempfile.TemporaryDirectory()as temp:
            root=Path(temp);client=['[QUEUE_CHECK] '+json.dumps(dict(suite='queue-recovery',event='setup',cases=list(a.CASES),queueEnabled=True,nativeDurations=True))];server=[]
            for case in a.CASES:
                row,spec,baseline,final,acks=self.evidence(case)
                client.append('[QUEUE_CHECK] '+json.dumps(row));client.extend(a.PREFIX+'ACK '+json.dumps(v)for v in acks)
                server.extend(a.PREFIX+marker+' '+json.dumps(value)for marker,value in [('PREPARED',spec),('BASELINE',baseline),('VERIFIED',final)])
            client.extend(['[QUEUE_CHECK] '+json.dumps(dict(suite='queue-recovery',event='complete',cases=list(a.CASES),performed=2,failed=0,skipped=0)),a.PREFIX+'COMPLETE '+json.dumps(dict(cases=list(a.CASES)))])
            (root/'client1-launch.log').write_text('\n'.join(client));(root/'server-launch.log').write_text('\n'.join(server))
            self.assertEqual(a.verify(root,selection,{})['issues'],[])
            for bad in (server[::-1],server+[server[-1]],server[:-1]):
                (root/'server-launch.log').write_text('\n'.join(bad));self.assertTrue(a.verify(root,selection,{})['issues'])

    def test_registration_full_pack_selection_and_staging(self):
        from queue_checks import adapters
        self.assertIs(adapters.get('queue-recovery'),a)
        self.assertEqual(a.definitions()['queue-recovery'],json.loads((ROOT/'tests/native_queue/catalog.json').read_text())['suites']['queue-recovery'])
        self.assertTrue(all(p.is_file()for p in a.sources(ROOT,self.selection())))
        for key,value in [('cases',[a.CASES[0]]),('cases',list(reversed(a.CASES))),('mods',[]),('clients',2),('options',{})]:
            selection=self.selection();selection[key]=value
            with self.assertRaises(ValueError):a.validate(selection)
        with tempfile.TemporaryDirectory()as temp:
            lua=Path(temp)/'mods/ActionQueueTest/42/media/lua'
            for side in ('client','server','shared'):(lua/side).mkdir(parents=True)
            runtime={'roles':{'client1':{'cache':temp}}};a.stage(ROOT,None,None,None,self.selection(),None,runtime)
            self.assertTrue((lua/'client/ZZStartup.lua').is_file());self.assertEqual(runtime['fixture']['sandbox']['MinutesPerPage'],2.0)

    def test_native_ui_checks_declared_duration_after_allocation(self):
        from lupa.lua51 import LuaRuntime
        lua=LuaRuntime()
        source=(ROOT/'tests/native_queue/queue-recovery/client/ZZQueueRecovery.lua').read_text()
        volume='local function volume'+source.split('local function volume',1)[1].split('local function read',1)[0]
        check=lua.execute("""
            local commands,tracks={},{}
            local state={data={}}
            local action={Type='ISRadioAction',mode='SetVolume',maxTime=30.000028610229492,deviceData=state.data}
            local panel={volumeBar={getVolumeSteps=function()return 10 end}}
            panel.volumeBar.onVolumeChange=function(_,value)
                assert(value==4);local row={duration=30};commands[#commands+1]=row;tracks[action]=row
            end
        """+volume+"""
            return function()
                assert(volume(.4)==action)
                -- The declaration stays strict; an altered constructor must fail.
                panel.volumeBar.onVolumeChange=function()local row={duration=29};commands[#commands+1]=row;tracks[action]=row end
                assert(not pcall(volume,.4))
            end
        """)
        check()

    def test_projection_ui_gate_checks_native_rows_and_restores_expansion(self):
        from lupa.lua51 import LuaRuntime
        lua=LuaRuntime();lua.globals().NativeSnapshot=object()
        gate=lua.execute((ROOT/'tests/native_queue/queue-recovery/client/QueueProjectionUI.lua').read_text())
        check=lua.eval('''function(Gate,mode,expanded)
            local tokens={{},{},{}}
            local values={{toolkitQueueOperation=tokens[1]},{toolkitQueueOperation=tokens[2]},
                {toolkitQueueOperation=tokens[2]},{toolkitQueueOperation=tokens[3]}}
            local queue={queue=values,current=values[1]}
            local Panel={refresh=function()end}
            PZSurvivorToolkit={ActionQueuePanel=Panel}
            toolkitQueueViewCurrentIndex=function()return 1 end
            local view=setmetatable({queue=queue,visible=true,expanded={[tokens[2]]=expanded,[tokens[1]]=false},list={items={}}},Panel)
            view.getIsVisible=function(self)return self.visible end
            view.setVisible=function(self,value)self.visible=value end
            view.clearSnapshots=function(self)
                if mode=='clear-failed'then return end
                self.projection,self.projectedRows,self.projectedRowCount,self.currentIndex=nil,nil,nil,nil
                self.expanded,self.list.items,self.opened={},{},nil
            end
            view.update=function(self)
                if not self.visible and mode~='hidden-recreated'then return end
                local opened=not not self.expanded[tokens[2]]
                local previous=self.projection
                self.projection=previous or {native=NativeSnapshot,groups={{},{},{}}}
                self.projection.stable=previous~=nil
                self.currentIndex=mode=='stale-current'and 2 or 1
                if mode=='fallback'then self.projection.native=nil end
                if self.opened~=opened then
                    local specs={{1,false,1,1,1,1},{2,true,2,3,2,3}}
                    if opened then specs[#specs+1]={2,false,2,2,2,3};specs[#specs+1]={3,false,3,3,2,3}end
                    specs[#specs+1]={4,false,4,4,4,4}
                    self.list.items={}
                    for index,s in ipairs(specs)do
                        self.list.items[index]={item=values[s[1]],header=s[2],first=s[3],last=s[4],
                            groupFirst=s[5],groupLast=s[6],index=index,operation=values[s[1]].toolkitQueueOperation}
                    end
                    self.opened=opened
                end
                if mode=='bad-bounds'then self.list.items[2].last=2 end
                if mode=='mutated-action'then values[1].action={}end
            end
            local windows={size=function()return mode=='missing-panel'and 0 or 1 end,
                get=function()return {getTable=function()return view end}end}
            UIManager={getUI=function()return windows end}
            local ok,result=pcall(Gate.capture,queue,tokens,function(token)
                for index,value in ipairs(tokens)do if value==token then return index end end
            end)
            assert(view.expanded[tokens[2]]==expanded,'failed gate left expansion changed')
            assert(view.expanded[tokens[1]]==false and view.visible,'failed gate left presentation state changed')
            if mode=='ok'then
                assert(ok,result)
                assert(result.nativeSnapshot and result.stableReuse and result.expansionRestored
                    and result.hiddenCleared and result.reopened and result.visibilityRestored
                    and #result.collapsed.rows==3 and #result.expanded.rows==5 and #result.reopenedView.rows==3)
            else assert(not ok,'invalid projection gate accepted '..mode)end
        end''')
        for expanded in (None,False,True):
            for mode in ('ok','missing-panel','fallback','stale-current','bad-bounds','mutated-action','clear-failed','hidden-recreated'):
                with self.subTest(expanded=expanded,mode=mode):check(gate,mode,expanded)

    def test_fixture_syntax_native_duration_and_frozen_sources(self):
        from lupa.lua51 import LuaRuntime
        lua=LuaRuntime();compile_chunk=lua.eval('function(source,name)return assert(loadstring(source,name))end')
        for path in (ROOT/'tests/native_queue/queue-recovery').rglob('*.lua'):compile_chunk(path.read_text(),str(path))
        source=(ROOT/'tests/native_queue/queue-recovery/client/ZZQueueRecovery.lua').read_text()
        self.assertIn('getPlayer():StopAllActionQueueWalking()',source);self.assertIn('ISTimedActionQueue.clear(getPlayer())',source)
        self.assertIn("action.item:getID()==ids.front.id",source)
        for forbidden in ('setJobDelta','setCurrentTime','setMultiplier','forceComplete(','ISReadABook.new=','ISReadABook.update=','ISReadABook.perform=','getGameTime():set'):
            self.assertNotIn(forbidden,source)
        self.assertNotRegex(source,r'action\.maxTime\s*=(?!=)')
        self.assertNotRegex(source,r'[.:]\s*forceComplete\s*\(')
        helper='local function finite'+source.split('local function finite',1)[1].split('-- Observe admission',1)[0]
        capture=lua.execute('local now=function()return 100 end\n'+helper+'\nreturn captureDuration')
        lua.eval('''function(capture)
            local action={action={},maxTime=79252.305,adjustMaxTime=function()return 79252.438 end}
            local row={name='reader',duration=79200,nativeDurationBefore=79252.2,durationSampleBefore=90,durationSamples=2}
            capture(action,row);assert(action.maxTime==79252.305 and row.effectiveDuration==79252.305)
            action.maxTime=79252.4;assert(not pcall(capture,action,row))
        end''')(capture)

if __name__=='__main__':unittest.main()
