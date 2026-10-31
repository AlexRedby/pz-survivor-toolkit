"""Host admission and evidence reject local-only or incomplete Smart Deposit proof."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import auxiliary
INTAKE = ROOT / 'tests/native_queue/contributions/smart-deposit'


def selection(kind='mp'):
    return dict(suite='smart-deposit', cases=['partial'], kind=kind, mode='toolkit',
                languages=['EN'], clients=1, mods=list(auxiliary.INVENTORY_MODS),
                options={'mp_host': True} if kind == 'mp' else {})


class SmartDepositHostAdapterTests(unittest.TestCase):
    def test_host_requires_fresh_one_client_menu_host(self):
        auxiliary.validate(selection())
        auxiliary.validate(selection('sp'))
        for patch in ({'clients': True}, {'clients': 2}, {'options': {}},
                      {'options': {'mp_host': True, 'seed_run': '/seed'}},
                      {'options': {'mp_host': True, 'world_template': '/world'}},
                      {'options': {'mp_host': True, 'startup_connection': 'existing'}}):
            with self.subTest(patch=patch), self.assertRaises(ValueError):
                auxiliary.validate(dict(selection(), **patch))

    def test_host_stage_has_authority_and_bootstrap_without_sp_fixture(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            runtime = {'roles': {role: {'cache': str(root / role)} for role in ('client1', 'server')}}
            auxiliary.stage(ROOT, root, root / 'game', root / 'jdk', selection(),
                            {'PZSurvivorToolkit': ROOT / 'PZSurvivorToolkit'}, runtime)
            for role in runtime['roles']:
                lua = root / role / 'mods/SmartDepositNative/42/media/lua'
                for path in ('client/ZZSmartDepositHost.lua', 'shared/QueueSmartDepositHostFixture.lua',
                             'server/ZZSmartDepositHostServer.lua', 'client/ZZStartup.lua',
                             'server/ZZStartupServer.lua', 'shared/QueueHealthEvents.lua'):
                    self.assertTrue((lua / path).is_file(), path)
                self.assertFalse((lua / 'client/ZZSmartDepositNative.lua').exists())
            self.assertEqual(runtime['fixture']['server_ready'], '[STARTUP_TEST] SERVER_READY')
            self.assertIn('[SMART_DEPOSIT_HOST] FAIL ', runtime['fixture']['failure_markers'])
            sources = auxiliary.sources(ROOT, selection())
            self.assertIn(ROOT / 'tests/native_queue/startup/client/ZZStartup.lua', sources)
            self.assertIn(INTAKE / 'QueueSmartDepositHostFixture.lua', sources)



V = auxiliary._load(INTAKE / 'host_verify.py')


def evidence(role='client'):
    env = dict(V.envelope(selection(), role), token='session')
    original = [77]
    crates = [dict(x=10+i,y=10,z=0,index=1,token='session:'+str(i)) for i in range(1,4)]
    def snap(phase=None, moved=False, extras=()):
        expected = V.phase_expected(phase, moved, extras) if phase else {}
        weights = {key: .1 for key in expected}
        types = {key: 'Base.Nails' for key in expected}
        if phase:
            types[phase['stockIds'][0]] = 'Base.Screws'
            for slot,key in enumerate(phase['fillerIds'],1):
                weights[key] = 9.85 - (.1 if slot != phase['order'][0] else 0)
                types[key] = 'Base.Apple'
        return dict(originalRootIds=original, rootIds=original+[key for key,where in expected.items() if where=='root'],
                    items=[dict(id=key,endpoint=where,count=1,type=types[key],weight=weights[key]) for key,where in expected.items()],
                    crates=[dict(slot=slot,capacity=10,effectiveCapacity=10,weight=sum(weights[key] for key,where in expected.items() if where=='crate'+str(slot)),
                                 itemIds=[key for key,where in expected.items() if where=='crate'+str(slot)]) for slot in (1,2,3)])
    proof=dict(rootIds=original,worn=[],primaryHandId=0,secondaryHandId=0)
    rows=[('SETUP',dict(ids=dict(token='session',crates=crates,origin=dict(x=10,y=10,z=0)),snapshot=snap(),original=proof,
                       uiBaseline=dict(samples=3,stableSpanMs=240)))]
    def add(event,**row): rows.append((event,dict(index=index,paneMode=mode,**row)))
    for index,mode in enumerate(('clean','vanilla'),1):
        start=index*100
        phase=dict(token='session',index=index,mode=mode,order=[1,2,3],sampleIds=list(range(start,start+4)),
                   stockIds=[start+4,start+5],fillerIds=[start+6,start+7,start+8])
        keys=phase['sampleIds'];extras=list(range(start+9,start+12))
        moved=V.phase_expected(phase,True)
        add('SEED',phase=phase,snapshot=snap(phase),originAuthority=dict(token='session',index=index,ready=True,
            x=10.5,y=10.5,z=0,squareX=10,squareY=10,squareZ=0))
        if role=='client':
            add('PREVIEW',items=[dict(id=key,allowed=i<3,cannotDrop=i>=3,destination=moved[key] if i<3 else False) for i,key in enumerate(keys)],
                pane=True,page=True,cannotDropAny=False,snapshot=snap(phase))
            add('SHOT',name='smart-deposit-'+mode+'-partial.png')
            add('QUEUED',nativeActions=3,rejectedQueued=False,items=[dict(id=key,source='root',destination=moved[key],initialDuration=-1,queueTime=-1) for key in keys[:3]])
            for key in keys[:3]:
                add('TIMING',id=key,source='root',destination=moved[key],initialDuration=-1,duration=20,transactionDuration=20,durationSource='native-transaction-duration',transactionId=key,
                    started=True,completed=True,startCalls=1,performCalls=1,stopCalls=0,progressSamples=3,updateCalls=2)
        add('EFFECT',sampleIds=keys,snapshot=snap(phase,True))
        add('EXTRAS',extraIds=extras,snapshot=snap(phase,True,extras))
        add('FULL',snapshot=snap(phase,True,extras),pane=False,page=False,cannotDropAny=True,nativeActions=0,
            items=[dict(id=key,allowed=False,cannotDrop=True,destination=False) for key in [keys[3]]+extras])
        add('RELEASE',removedIds=list(range(start,start+12)),snapshot=snap())
    position=dict(x=10.25,y=20.5,z=0,squareX=10,squareY=20,squareZ=0)
    quiet=dict(position,moving=False,hasPath=False,deferredX=0,deferredY=0)
    layout=dict(owner=dict(x=0,y=0,width=500,height=400),pane=dict(x=0,y=20,width=500,height=380))
    ui=dict(pages=[dict(expected=layout,actual=layout,inventoryBound=True,selectionRestored=True) for _ in range(2)],
            flags=dict(expected={},actual={}),core=dict(expected={},actual={}),cleanMode=dict(expected=True,actual=True),
            options={name:dict(expected=False,actual=False) for name in ('enableProximity','enableCorpseOnly','enableDualMode','enableNestedContainers_Loot','enableAutoLock')})
    rows.extend([('RESTORED',dict(ownedAbsent=True,rootIds=original,removedCrates=3,ownedRemaining=0,
                                 crates=[dict(row,afterIndex=-1) for row in crates],original=proof,actual=proof,
                                 ui=True,uiProof=ui,options=True,flags=True,positionRestored=True,
                                 positionProof=dict(original=position,actual=dict(quiet,currentSquareX=10,currentSquareY=20,currentSquareZ=0),
                                                    minimumWaitMs=100,deadlineMs=10000,elapsedMs=200,lifecycleElapsedMs=700,
                                                    quiescence=dict(first=dict(quiet),last=dict(quiet),stableMs=500,minimumStableMs=500,samples=10)))),
                 ('COMPLETE',dict(phases=2,restored=True,nativeActions=6))])
    return [(event,dict(env,**row)) for event,row in rows]


def render(rows): return '\n'.join(V.MARKER+event+' '+json.dumps(row) for event,row in rows)


def event(rows,name): return next(row for key,row in rows if key==name)


class SmartDepositHostReceiptTests(unittest.TestCase):
    def verify(self,client=None,server=None):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'server-launch.log').write_text(render(server if server is not None else evidence('server')))
            (root/'client1/Screenshots').mkdir(parents=True)
            for mode in ('clean','vanilla'): (root/'client1/Screenshots'/('smart-deposit-'+mode+'-partial.png')).write_bytes(V.PNG)
            return V.verify(root,render(client if client is not None else evidence()),selection())

    def test_two_modes_require_independent_host_endpoints(self):
        self.assertEqual(len(self.verify()['screenshots']),2)
        rows=evidence('server');event(rows,'EFFECT')['snapshot']['items'][0]['endpoint']='root'
        with self.assertRaises(ValueError):self.verify(server=rows)

    def test_rejects_incomplete_duplicate_foreign_and_reordered_proof(self):
        changes=[lambda rows:rows.pop(5),lambda rows:rows.append(rows[-1]),lambda rows:rows.reverse(),
                 lambda rows:event(rows,'EFFECT').update(token='foreign'),
                 lambda rows:event(rows,'SEED')['phase'].update(order=[1,1,3]),
                 lambda rows:event(rows,'RELEASE')['removedIds'].pop(),
                 lambda rows:event(rows,'RESTORED').update(rootIds=[])]
        for change in changes:
            rows=evidence();change(rows)
            with self.subTest(change=change),self.assertRaises(ValueError):self.verify(rows)

    def test_raw_preview_capacity_and_native_timing_are_mandatory(self):
        changes=[lambda rows:event(rows,'PREVIEW')['items'][3].update(cannotDrop=False),
                 lambda rows:event(rows,'QUEUED')['items'][0].update(queueTime=20),
                 lambda rows:event(rows,'TIMING').update(duration=0),
                 lambda rows:event(rows,'TIMING').update(transactionId=0),
                 lambda rows:event(rows,'TIMING').update(stopCalls=1),
                 lambda rows:event(rows,'FULL').update(nativeActions=1),
                 lambda rows:event(rows,'FULL')['snapshot']['crates'][0].update(weight=11),
                 lambda rows:event(rows,'FULL')['snapshot']['crates'][0]['itemIds'].append(999),
                 lambda rows:event(rows,'RESTORED')['positionProof']['actual'].update(x=10),
                 lambda rows:event(rows,'RESTORED')['positionProof']['actual'].update(deferredX=.001),
                 lambda rows:event(rows,'RESTORED')['positionProof']['quiescence'].update(stableMs=400),
                 lambda rows:event(rows,'RESTORED')['positionProof']['quiescence']['last'].update(deferredY=.001),
                 lambda rows:event(rows,'RESTORED')['positionProof']['quiescence']['last'].update(x=10),
                 lambda rows:event(rows,'RESTORED')['positionProof']['actual'].update(currentSquareX=11)]
        for change in changes:
            rows=evidence();change(rows)
            with self.subTest(change=change),self.assertRaises(ValueError):self.verify(rows)

    def test_completion_is_role_bound_and_fail_closed(self):
        rows=evidence()
        self.assertTrue(V.complete(render(rows),selection(),'client1'))
        self.assertFalse(V.complete(render(rows),selection(),'server'))
        self.assertFalse(V.complete(render(rows)+'\n'+V.MARKER+'FAIL {}',selection(),'client1'))
        self.assertFalse(V.complete(render(rows)+ '\n'+V.MARKER+'COMPLETE {"phases":2,"phases":2}',selection(),'client1'))

    def test_origin_requires_matching_authority_before_each_phase(self):
        changes=[lambda row:row.update(ready=False),lambda row:row.update(token='foreign'),
                 lambda row:row.update(index=3),lambda row:row.update(x=11.5),
                 lambda row:row.update(squareX=11)]
        for change in changes:
            rows=evidence();seeds=[row for key,row in rows if key=='SEED'];change(seeds[1]['originAuthority'])
            with self.subTest(change=change),self.assertRaises(ValueError):self.verify(rows)
        rows=evidence('server');event(rows,'SETUP')['ids']['origin']['x']=11
        with self.assertRaises(ValueError):self.verify(server=rows)

    def test_matching_foreign_phase_tokens_do_not_establish_session_ownership(self):
        client,server=evidence(),evidence('server')
        for rows in (client,server):
            for name,row in rows:
                if name=='SEED':row['phase']['token']='foreign-phase-token'
        with self.assertRaises(ValueError):self.verify(client,server)


if __name__ == '__main__':
    unittest.main()
