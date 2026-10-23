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
        baseline,final=snapshot('baseline'),snapshot('final')
        recovery=dict(available=mode=='toolkit',restored=mode=='toolkit',historyAbsent=True,duplicateRejected=True)
        if mode=='toolkit':recovery.update(id=1,count=3,skipped=0,tokens=[5,6,7],previewPure=True)
        row=dict(suite='queue-recovery',event='case',id=case,actor='client1',kind=kind,mode=mode,status='passed',ids=copy.deepcopy(spec),
                 input=snapshot('input'),baseline=copy.deepcopy(baseline),authorityBaseline=copy.deepcopy(baseline),client=copy.deepcopy(final),server=copy.deepcopy(final),
                 commands=commands,order=list(a.STARTS if mode=='toolkit'else a.STARTS[:2]),
                 cancellation=dict(entrypoint='IsoGameCharacter.StopAllActionQueueWalking'if case=='movement-cancel'else'ISTimedActionQueue.clear',before=copy.deepcopy(baseline),initialQueue=list(a.ORIGINAL),drained=True,movementStopped=True,nativeCount=1,oldTokens=[dict(id=i,cancelled=True)for i in (2,3,4)]),
                 recovery=recovery,restoredQueue=list(a.ORIGINAL)if mode=='toolkit'else[],queueIdle=True,settleMilliseconds=1000)
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
