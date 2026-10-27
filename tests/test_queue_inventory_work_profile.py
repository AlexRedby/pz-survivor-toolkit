"""Inventory cost evidence must retain controls, visibility, identities and cleanup."""
import copy
import itertools
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from queue_checks.adapters import auxiliary
INTAKE=ROOT/'tests/native_queue/contributions/storage-profile'
V=auxiliary._load(INTAKE/'inventory_work_verify.py')


def receipts():
    rows=[('WORK_SETUP',dict(native=True,clock='getTimestampMs',resolutionMs=1,spacers=60,foodType='Base.Apple',
                            lookupType='Base.Nails',phases=14,physicalInput=False,fpsMeasurement=False))]
    for case,requested in [('missing',-2147483648),('first-present',1),('last-nested',4802),('empty-control',-2147483648)]:
        rows.append(('WORK_LOOKUP',dict(case=case,native=True,clock='getTimestampMs',resolutionMs=1,nestedObjects=4800,
            rootObjects=2,recursiveObjects=4802,emptyObjects=0,batchCalls=512,warmupBatches=2,measuredBatches=9,
            measuredCalls=4608,matchedCalls=4608,objectsPreserved=True,fpsMeasurement=False,receiptLatencyMeasurement=False,
            missingId=-2147483648,firstId=1,lastId=4802,requestedId=requested,elapsedMs=[4]*9,totalElapsedMs=36,
            minBatchMs=4,medianBatchMs=4,p95BatchMs=4,maxBatchMs=4,zeroMsBatches=0,meanMsPerCall=36/4608)))
    specs=[(*spec,True)for spec in itertools.product((100,10000),('clean','vanilla'),
                                              ('collapsed-visible','collapsed-clipped','expanded-clipped'))]
    specs += [(10000,'clean',view,False)for view in ('collapsed-visible','collapsed-clipped')]
    for index,(size,mode,view,freshness) in enumerate(specs,1):
        rows.append(('WORK_FOOD',dict(index=index,size=size,mode=mode,view=view,native=True,elapsedMs=3010,warmupMs=1500,
            clockResolutionMs=1,paneClass='CleanUI_Clean_ISInventoryPane' if mode=='clean' else 'CleanUI_Vanilla_ISInventoryPane',
            rendererMatchesClass=True,freshnessBar=freshness,freshnessPercentage=freshness,
            foodIcons=180 if view=='collapsed-visible'else 0,groups=65,rawItems=size+65,refresh=dict(calls=0,totalMs=0),
            primary=dict(calls=180,totalMs=240,meanMs=240/180,p50=1,p95=2,maxMs=2,zeroMsCalls=0),dragged={'calls':0},
            scrollY=0 if view=='collapsed-visible'else -2000,width=960,height=350,groupObjects=size)))
    for mode in ('clean','vanilla'):
        rows.append(('WORK_FRESHNESS',dict(mode=mode,
            paneClass='CleanUI_Clean_ISInventoryPane' if mode=='clean' else 'CleanUI_Vanilla_ISInventoryPane',
            rendererMatchesClass=True,tailId=10000,objects=10000,tailGroup=1,unique=True,ageBefore=0,ageAfter=99)))
    rows.append(('WORK_RESTORED',dict(ownedRemoved=10060,foodRemoved=10000,originalItems=5,observers=True,
                                     mode=True,freshnessOptions=True,phases=14,lookupObjectsPreserved=True)))
    return rows


def log(rows):return '\n'.join('[STORAGE_PROFILE] '+kind+' '+json.dumps(row)for kind,row in rows)+'\n[STORAGE_PROFILE] COMPLETE\n'


class InventoryWorkProfileTests(unittest.TestCase):
    def fixture_runtime(self):
        from lupa.lua51 import LuaRuntime
        lua=LuaRuntime()
        lua.execute('''
            require=function(name)
                if name=='QueueTestSelection' then return {cases={'inventory-work'}} end
                return {}
            end
            Events={}
            for _,name in ipairs({'OnTick','OnMainMenuEnter','OnGameStart','OnPreUIDraw'}) do
                Events[name]={Add=function(callback) Events[name].callback=callback end}
            end
            getTimestampMs=function() return 100 end
            print=function(message) capturedLog=(capturedLog or '')..message..'\\n' end
        ''')
        fixture=lua.execute((INTAKE/'ZZInventoryWorkProfile.lua').read_text()+'''
            return {
                paneClass=paneClass, observe=observe,restorePane=restorePane,
                phaseOptions=phaseOptions,phases=phases,options=freshnessOptions,
                originalOptions=function(bar,percentage)
                    originalFreshnessOptions={bar=bar,percentage=percentage}
                end,
                measure=function(value)active=value end,
                seed=function(testPane,testInventory,testOwned,testActive)
                    pane=testPane;inventory=testInventory;owned=testOwned or {}
                    active=testActive;started=true;originalMode=false
                    iconOriginal=function()end;iconWrapper=function()end
                    ISInventoryItem={renderItemIcon=iconWrapper}
                end,
                failed=function()return rendererFailure and rendererFailure.error end,
                finished=function()return done end,
                iconRestored=function()return ISInventoryItem.renderItemIcon==iconOriginal end
            }
        ''')
        return lua,fixture

    def test_renderer_failure_survives_later_success_and_triggers_cleanup(self):
        for measuring,method in itertools.product((True,False),('renderdetails','refreshContainer')):
            lua,fixture=self.fixture_runtime()
            lua.execute('''
                local fixture,measuring,method=...
                local fault,calls={},0
                local class={refreshContainer=function()end,renderdetails=function()end}
                class[method]=function()
                    calls=calls+1
                    if calls==1 then error(fault,0) end
                    return 'ok',nil,'tail'
                end
                class.__index=class
                local testPane=setmetatable({},class)
                local removed,item=0,{}
                local testInventory={Remove=function(_,value)assert(value==item);removed=removed+1 end}
                item.getContainer=function()return testInventory end
                local active=measuring and {primary={},dragged={},refresh={calls=0,totalMs=0}} or nil
                fixture.seed(testPane,testInventory,{item},active)
                fixture.originalOptions(true,false)
                fixture.options.showFoodFreshnessBar=false;fixture.options.showFoodFreshnessPercentage=true
                fixture.observe()
                local ok,errorValue=pcall(testPane[method],testPane,false)
                assert(not ok and errorValue==fault,'UI must retain the original error object')
                local a,b,c=testPane[method](testPane,false)
                assert(a=='ok' and b==nil and c=='tail','renderer returns changed')
                assert(fixture.failed()==fault,'later success hid the renderer failure')
                local restoredMode
                CleanUI_setCleanInventoryUIEnabled=function(value)restoredMode=value end
                Events.OnTick.callback()
                assert(fixture.finished() and fixture.iconRestored() and removed==1 and restoredMode==false)
                assert(fixture.options.showFoodFreshnessBar==true and fixture.options.showFoodFreshnessPercentage==false)
                assert(rawget(testPane,'renderdetails')==nil,'instance observer was not removed')
                assert(rawget(testPane,'refreshContainer')==nil,'refresh observer was not removed')
                assert(string.find(capturedLog,'[STORAGE_PROFILE] FAIL',1,true))
                assert(not string.find(capturedLog,'[STORAGE_PROFILE] COMPLETE',1,true))
            ''',fixture,measuring,method)

    def test_refresh_observer_excludes_warmup_and_restores_owned_override(self):
        lua,fixture=self.fixture_runtime()
        lua.execute('''
            local fixture=...
            local calls,clock=0,0
            getTimestampMs=function()clock=clock+1;return clock end
            local refresh=function(self,value)calls=calls+1;return value,nil,'tail' end
            local testPane={renderdetails=function()end,refreshContainer=refresh}
            fixture.seed(testPane,{},nil,nil)
            fixture.observe()
            assert(testPane:refreshContainer('warm')=='warm')
            local measured={primary={},dragged={},refresh={calls=0,totalMs=0}}
            fixture.measure(measured)
            local a,b,c=testPane:refreshContainer('measured')
            assert(a=='measured' and b==nil and c=='tail')
            assert(calls==2 and measured.refresh.calls==1 and measured.refresh.totalMs==1)
            fixture.restorePane()
            assert(rawget(testPane,'refreshContainer')==refresh,'own refresh override changed')
            fixture.observe()
            local foreign=function()end
            testPane.refreshContainer=foreign
            assert(not pcall(fixture.restorePane),'foreign refresh observer accepted')
            assert(testPane.refreshContainer==foreign,'foreign refresh callback overwritten')
        ''',fixture)

    def test_feature_controls_require_both_runtime_options(self):
        lua,fixture=self.fixture_runtime()
        lua.execute('''
            local fixture=...
            assert(#fixture.phases==14)
            for index,phase in ipairs(fixture.phases)do
                assert(phase.freshness==(index<=12))
                if index>12 then assert(phase.size==10000 and phase.mode=='clean')end
                fixture.options.showFoodFreshnessBar=phase.freshness
                fixture.options.showFoodFreshnessPercentage=phase.freshness
                fixture.phaseOptions(phase)
                fixture.options.showFoodFreshnessPercentage=not phase.freshness
                assert(not pcall(fixture.phaseOptions,phase),'mismatched feature flags accepted')
            end
            assert(fixture.phases[13].view=='collapsed-visible' and fixture.phases[14].view=='collapsed-clipped')
        ''',fixture)

    def test_actual_pane_class_and_captured_renderer_are_required(self):
        lua,fixture=self.fixture_runtime()
        lua.execute('''
            local fixture=...
            CleanUI_Clean_ISInventoryPane={renderdetails=function()end}
            CleanUI_Vanilla_ISInventoryPane={renderdetails=function()end}
            for _,mode in ipairs({'clean','vanilla'})do
                local name=mode=='clean'and 'CleanUI_Clean_ISInventoryPane'or 'CleanUI_Vanilla_ISInventoryPane'
                local class=_G[name];class.__index=class
                ISInventoryPane=class
                fixture.seed(setmetatable({},class),{},nil,nil)
                assert(fixture.paneClass(mode,class.renderdetails)==name)
                assert(not pcall(fixture.paneClass,mode,function()end),'foreign renderer accepted')
                local other=mode=='clean'and CleanUI_Vanilla_ISInventoryPane or CleanUI_Clean_ISInventoryPane
                other.__index=other
                fixture.seed(setmetatable({},other),{},nil,nil)
                assert(not pcall(fixture.paneClass,mode,class.renderdetails),'stale pane accepted')
            end
        ''',fixture)

    def test_exact_capture_and_mutations(self):
        rows=receipts();result=V.verify(ROOT,log(rows))
        self.assertEqual(len(result['food']),14);self.assertEqual(len(result['lookup']),4)
        for index,key,value in [(1,'recursiveObjects',4801),(1,'matchedCalls',0),(1,'meanMsPerCall',1),
                                 (1,'elapsedMs',[4]*8),(1,'requestedId',1),(5,'foodIcons',0),
                                 (6,'foodIcons',1),(5,'groupObjects',99),(5,'elapsedMs',10),
                                 (5,'paneClass','CleanUI_Vanilla_ISInventoryPane'),(5,'rendererMatchesClass',False),
                                 (5,'freshnessBar',False),(17,'freshnessBar',True),(18,'freshnessPercentage',True),
                                 (5,'refresh',dict(calls=0,totalMs=1)),(5,'refresh',dict(calls=-1,totalMs=0)),
                                 (19,'tailGroup',10000),(20,'mode','clean'),(19,'rendererMatchesClass',False),
                                 (20,'paneClass','CleanUI_Clean_ISInventoryPane'),(21,'observers',False),(21,'freshnessOptions',False)]:
            changed=copy.deepcopy(rows);changed[index][1][key]=value
            with self.subTest(index=index,key=key),self.assertRaises(ValueError):V.verify(ROOT,log(changed))
        with self.assertRaises(ValueError):V.verify(ROOT,log(rows[1:]))
        with self.assertRaises(ValueError):V.verify(ROOT,log(rows)+'[STORAGE_PROFILE] FAIL\n')

    def test_selection_and_isolated_stage(self):
        self.assertEqual([case['capability']for case in auxiliary.definitions()['storage-profile']['cases']],['capture','capture','effect'])
        prepare=auxiliary._load(INTAKE/'prepare.py').prepare
        with tempfile.TemporaryDirectory()as temp:
            target=Path(temp)/'fixture';prepare(ROOT/'PZSurvivorToolkit',target,case='inventory-work')
            names={p.name for p in (target/'42/media/lua/client').iterdir()}
            self.assertEqual(names,{'ZZInventoryWorkProfile.lua','ReceiptLookupNative.lua'})

    def test_lua_syntax(self):
        from lupa.lua51 import LuaRuntime
        lua=LuaRuntime()
        for name in ('ZZInventoryWorkProfile.lua','ReceiptLookupNative.lua'):
            lua.execute('assert(loadstring(...))',(INTAKE/name).read_text())


if __name__=='__main__':unittest.main()
