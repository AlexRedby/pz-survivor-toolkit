"""Inventory cost evidence must retain controls, visibility, identities and cleanup."""
import copy
import itertools
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock
import zipfile

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from queue_checks.adapters import auxiliary
INTAKE=ROOT/'tests/native_queue/contributions/storage-profile'
V=auxiliary._load(INTAKE/'inventory_work_verify.py')


def receipts(renderer=None):
    modes=(renderer,) if renderer else ('clean','vanilla')
    phases=len(modes)*10
    rows=[('WORK_SETUP',dict(native=True,clock='getTimestampMs',resolutionMs=1,spacers=60,foodType='Base.Apple',
                            lookupType='Base.Nails',phases=phases,physicalInput=False,fpsMeasurement=False,
                            renderClock='System.nanoTime',renderResolutionMs=0.000001,
                            nativeAgeMethod='Food.updateAge()',observer='scoped-entry-counter'))]
    if renderer:rows[0][1]['renderer']=renderer
    for case,requested in [('missing',-2147483648),('first-present',1),('last-nested',4802),('empty-control',-2147483648)]:
        rows.append(('WORK_LOOKUP',dict(case=case,native=True,clock='getTimestampMs',resolutionMs=1,nestedObjects=4800,
            rootObjects=2,recursiveObjects=4802,emptyObjects=0,batchCalls=512,warmupBatches=2,measuredBatches=9,
            measuredCalls=4608,matchedCalls=4608,objectsPreserved=True,fpsMeasurement=False,receiptLatencyMeasurement=False,
            missingId=-2147483648,firstId=1,lastId=4802,requestedId=requested,elapsedMs=[4]*9,totalElapsedMs=36,
            minBatchMs=4,medianBatchMs=4,p95BatchMs=4,maxBatchMs=4,zeroMsBatches=0,meanMsPerCall=36/4608)))
    specs=[(*spec,True)for spec in itertools.product((100,10000),modes,
                                              ('collapsed-visible','collapsed-clipped','expanded-visible','expanded-clipped'))]
    specs += [(10000,mode,view,False)for mode,view in itertools.product(modes,('collapsed-visible','collapsed-clipped'))]
    for index,(size,mode,view,freshness) in enumerate(specs,1):
        rows.append(('WORK_FOOD',dict(index=index,size=size,mode=mode,view=view,native=True,elapsedMs=3010,warmupMs=1500,
            clockResolutionMs=0.000001,clock='System.nanoTime',nativeAgeMethod='Food.updateAge()',observer='scoped-entry-counter',
            paneClass='CleanUI_Clean_ISInventoryPane' if mode=='clean' else 'CleanUI_Vanilla_ISInventoryPane',
            rendererMatchesClass=True,freshnessBar=freshness,freshnessPercentage=freshness,
            foodIcons=180 if view.endswith('-visible')else 0,groups=65,rawItems=size+65,refresh=dict(calls=0,totalMs=0),
            primary=dict(calls=180,totalMs=240,meanMs=240/180,p50=1,p95=2,maxMs=2,zeroMsCalls=0,updateAgeCalls=180,minUpdateAgeCalls=1,maxUpdateAgeCalls=1),dragged={'calls':0},
            scrollY=0 if view.endswith('-visible')else -2000,width=960,height=350,groupObjects=size)))
    for mode in modes:
        rows.append(('WORK_FRESHNESS',dict(mode=mode,
            paneClass='CleanUI_Clean_ISInventoryPane' if mode=='clean' else 'CleanUI_Vanilla_ISInventoryPane',
            rendererMatchesClass=True,tailId=10000,objects=10000,tailGroup=1,unique=True,ageBefore=0,ageAfter=99)))
    rows.append(('WORK_RESTORED',dict(ownedRemoved=10060,foodRemoved=10000,originalItems=5,observers=True,
                                     mode=True,freshnessOptions=True,phases=phases,lookupObjectsPreserved=True)))
    return rows


def log(rows):return '\n'.join('[STORAGE_PROFILE] '+kind+' '+json.dumps(row)for kind,row in rows)+'\n[STORAGE_PROFILE] COMPLETE\n'


class InventoryWorkProfileTests(unittest.TestCase):
    def fixture_runtime(self, renderer=None):
        from lupa.lua51 import LuaRuntime
        lua=LuaRuntime()
        lua.globals().selectedRenderer=renderer
        lua.execute('''
            require=function(name)
                if name=='QueueTestSelection' then return {cases={'inventory-work'},kind='sp',clients=1,options={inventory_work_renderer=selectedRenderer}} end
                return {}
            end
            Events={}
            for _,name in ipairs({'OnTick','OnMainMenuEnter','OnGameStart','OnPreUIDraw'}) do
                Events[name]={Add=function(callback) Events[name].callback=callback end}
            end
            getTimestampMs=function() return 100 end
            inventoryWorkProbeBegin=function()return getTimestampMs()end
            inventoryWorkProbeClockMs=function()return getTimestampMs()end
            inventoryWorkProbeEnd=function()return 0 end
            print=function(message) capturedLog=(capturedLog or '')..message..'\\n' end
        ''')
        fixture=lua.execute((INTAKE/'ZZInventoryWorkProfile.lua').read_text()+'''
            return {
                paneClass=paneClass, observe=observe,restorePane=restorePane,
                phaseOptions=phaseOptions,phases=phases,options=freshnessOptions,selectMode=selectMode,modes=modes,
                originalOptions=function(bar,percentage)
                    originalFreshnessOptions={bar=bar,percentage=percentage}
                end,
                measure=function(value)active=value end,
                beginFill=beginFill,restoreFillVisibility=restoreFillVisibility,tick=tick,
                fillStatus=function()return fillVisibility end,
                state=function()return stage,active,phaseIndex,since end,
                seedFill=function(testInventory,testFood,index)
                    inventory=testInventory;food=testFood;foodSet={};owned={}
                    for _,item in ipairs(food)do foodSet[item]=true;owned[#owned+1]=item end
                    phaseIndex=index;began=0
                end,
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

    def test_renderer_native_scopes_separate_primary_drag_and_preserve_errors(self):
        lua,fixture=self.fixture_runtime()
        lua.execute('''
            local fixture=...
            local scoped=false;local calls=0;local closes=0;local time=0
            inventoryWorkProbeBegin=function()assert(not scoped);scoped=true;calls=0;return time end
            inventoryWorkProbeClockMs=function()return time end
            inventoryWorkProbeEnd=function()assert(scoped);scoped=false;closes=closes+1;return calls end
            local fault={}
            local testPane={refreshContainer=function()end,renderdetails=function(self,dragged,fail)
                assert(scoped);calls=dragged and 3 or 7;time=time+.125
                if fail then error(fault,0)end
                return 'same',nil,23
            end}
            local measured={primary={},dragged={},refresh={calls=0,totalMs=0}}
            fixture.seed(testPane,{},nil,measured);fixture.observe()
            local a,b,c=testPane:renderdetails(false)
            assert(a=='same'and b==nil and c==23)
            testPane:renderdetails(true)
            assert(measured.primary[1]==.125 and measured.dragged[1]==.125)
            assert(measured.primaryAgeCalls[1]==7 and measured.draggedAgeCalls[1]==3)
            inventoryWorkProbeClockMs=function()error('clock fault')end
            local ok,value=pcall(testPane.renderdetails,testPane,false,true)
            assert(not ok and value==fault,'observer replaced renderer error')
            assert(not scoped and closes==3,'renderer failure leaked native scope')
            fixture.restorePane()
        ''',fixture)

    def test_probe_begin_failure_still_delegates_and_clock_failure_closes(self):
        for boundary in ('begin','clock','end'):
            lua,fixture=self.fixture_runtime()
            lua.execute('''
                local fixture,boundary=...
                local calls,closes=0,0;local fault={}
                inventoryWorkProbeBegin=function()if boundary=='begin'then error(fault,0)end;return 0 end
                inventoryWorkProbeClockMs=function()if boundary=='clock'then error(fault,0)end;return .25 end
                inventoryWorkProbeEnd=function()closes=closes+1;if boundary=='end'then error(fault,0)end;return 0 end
                local testPane={refreshContainer=function()end,renderdetails=function()calls=calls+1 end}
                fixture.seed(testPane,{},nil,{primary={},dragged={},refresh={calls=0,totalMs=0}})
                fixture.observe()
                local ok,value=pcall(testPane.renderdetails,testPane,false)
                assert(not ok and value==fault and calls==1,'observer prevented delegation or replaced error')
                assert(closes==(boundary=='begin'and 0 or 1),'scope close skipped on clock failure')
                assert(fixture.failed()==fault)
                fixture.restorePane()
            ''',fixture,boundary)

    def test_probe_is_packaged_only_in_owned_disposable_mod(self):
        stage=auxiliary._load(INTAKE/'stage_inventory_probe.py').stage
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); cache=root/'cache';runtime={'roles':{'client1':{'cache':str(cache)}},'fixture':{'mods':['StorageProfileNative']}}
            def compile_probe(command,**kwargs):
                self.assertEqual(command[:3],[str(root/'jdk/bin/javac'),'--release','25'])
                self.assertIn('ZombieBuddy.jar',command[4])
                classes=Path(command[6])/'toolkit/inventorywork';classes.mkdir(parents=True)
                for name in ('Main.class','Main$FoodAge.class'):(classes/name).write_bytes(b'fixture')
            with mock.patch.object(auxiliary._load(INTAKE/'stage_inventory_probe.py').subprocess,'run',side_effect=compile_probe):
                stage(root,root/'game',root/'jdk',runtime)
            jar=cache/'mods/InventoryWorkProbe/42/media/java/InventoryWorkProbe.jar'
            with zipfile.ZipFile(jar) as archive:
                self.assertEqual(set(archive.namelist()),{'toolkit/inventorywork/Main.class','toolkit/inventorywork/Main$FoodAge.class'})
            self.assertEqual(runtime['fixture']['mods'],['StorageProfileNative','InventoryWorkProbe'])
            self.assertNotIn('env', runtime['roles']['client1'])
            for layer in ('common','42'):
                for directory in ('AnimSets','actiongroups'):
                    self.assertTrue((jar.parents[3]/layer/'media'/directory).is_dir())
            self.assertIn('require=\\ZombieBuddy',(jar.parents[2]/'mod.info').read_text())

    def test_feature_controls_require_both_runtime_options(self):
        lua,fixture=self.fixture_runtime()
        lua.execute('''
            local fixture=...
            assert(#fixture.phases==20)
            for index,phase in ipairs(fixture.phases)do
                assert(phase.freshness==(index<=16))
                if index>16 then assert(phase.size==10000)end
                fixture.options.showFoodFreshnessBar=phase.freshness
                fixture.options.showFoodFreshnessPercentage=phase.freshness
                fixture.phaseOptions(phase)
                fixture.options.showFoodFreshnessPercentage=not phase.freshness
                assert(not pcall(fixture.phaseOptions,phase),'mismatched feature flags accepted')
            end
            assert(fixture.phases[17].view=='collapsed-visible' and fixture.phases[18].view=='collapsed-clipped'
                and fixture.phases[19].mode=='vanilla' and fixture.phases[20].view=='collapsed-clipped')
        ''',fixture)

    def test_unmeasured_fill_hides_only_its_pane_and_restores_before_full_warmup(self):
        for baseline_visible in (True, False):
            lua,fixture=self.fixture_runtime()
            lua.execute('''
                local fixture,baselineVisible=...
                local clock,draws=100,0
                getTimestampMs=function()return clock end
                local items={}
                local inventory={AddItem=function(self)
                    local item={setAge=function()end};items[#items+1]=item;return item
                end}
                local initial={};for i=1,100 do initial[i]=inventory:AddItem()end
                fixture.seedFill(inventory,initial,9)
                local function render()draws=draws+1 end
                local function pane(class,visible)
                    class.__index=class;class.renderdetails=render
                    local p=setmetatable({visible=visible,inventory=inventory,collapsed={unrelated=false},scroll=-19},class)
                    function p:getIsVisible()return self.visible end;function p:setVisible(v)self.visible=v end
                    function p:setMode(v)self.mode=v end;function p:setYScroll(v)self.scroll=v end
                    function p:refreshContainer()
                        local group={name='food',items={items[1]}}
                        for _,item in ipairs(items)do group.items[#group.items+1]=item end
                        self.itemslist={group}
                        for i=1,60 do self.itemslist[#self.itemslist+1]={name='spacer'..i,items={}}end
                    end
                    return p
                end
                CleanUI_Clean_ISInventoryPane={};CleanUI_Vanilla_ISInventoryPane={}
                local old=pane(CleanUI_Vanilla_ISInventoryPane,baselineVisible)
                local page={inventoryPane=old,visible=false}
                for _,key in ipairs({'X','Y','Width','Height'})do page['set'..key]=function()end end
                function page:setVisible(v)self.visible=v end
                function page:clearMaxDrawHeight()end;function page:setPinned()end
                local loot={visible=true,setVisible=function(self,v)self.visible=v end}
                getPlayerInventory=function()return page end;getPlayerLoot=function()return loot end
                CleanUI_setCleanInventoryUIEnabled=function(clean)
                    assert(old.visible==baselineVisible,'fill failed to restore prior pane visibility before mode/configuration')
                    ISInventoryPane=clean and CleanUI_Clean_ISInventoryPane or CleanUI_Vanilla_ISInventoryPane
                    page.inventoryPane=pane(ISInventoryPane,false)
                end
                fixture.beginFill()
                assert(not old.visible and not page.visible and loot.visible and old.collapsed.unrelated==false)
                assert(fixture.fillStatus().from==100 and fixture.fillStatus().target==10000)
                -- Simulate native draws between all 99 bounded fill ticks.
                for i=1,99 do
                    if old.visible then old:renderdetails(false)end
                    local stage,active=fixture.state();assert(stage=='fill'and active==nil)
                    fixture.tick()
                end
                assert(draws==0 and #items==10000,'construction rendered or changed the target workload')
                assert(fixture.fillStatus()==nil and old.visible==baselineVisible)
                local stage,active,index,since=fixture.state()
                assert(stage=='warm'and active==nil and index==9 and since==100)
                assert(page.visible and page.inventoryPane.visible and page.inventoryPane.mode=='details')
                assert(page.inventoryPane.scroll==0 and page.inventoryPane.collapsed.food==true and not loot.visible)
                assert(fixture.phases[9].size==10000 and fixture.phases[9].mode=='clean'and fixture.phases[9].view=='collapsed-visible')
                clock=1599;fixture.tick();stage,active=fixture.state();assert(stage=='warm'and active==nil)
                clock=1600;fixture.tick();stage,active=fixture.state();assert(stage=='measure'and active.started==1600)
                assert(#active.primary==0 and active.refresh.calls==0,'fill/warmup leaked into measurements')
                assert(select(2,capturedLog:gsub('%[STORAGE_PROFILE%] FILL_BEGIN ',''))==1)
                assert(select(2,capturedLog:gsub('%[STORAGE_PROFILE%] FILL_COMPLETE ',''))==1)
            ''',fixture,baseline_visible)

    def test_aborted_fill_restores_exact_prior_pane_visibility(self):
        lua,fixture=self.fixture_runtime()
        lua.execute('''
            local fixture=...
            local owner={visible=false,getIsVisible=function(self)return self.visible end,setVisible=function(self,v)self.visible=v end}
            getPlayerInventory=function()return {inventoryPane=owner}end
            fixture.seedFill({}, {},1);fixture.beginFill()
            owner.visible=true
            fixture.restoreFillVisibility()
            assert(owner.visible==false and fixture.fillStatus()==nil)
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
        self.assertEqual(len(result['food']),20);self.assertEqual(len(result['lookup']),4)
        for index,key,value in [(1,'recursiveObjects',4801),(1,'matchedCalls',0),(1,'meanMsPerCall',1),
                                 (1,'elapsedMs',[4]*8),(1,'requestedId',1),(5,'foodIcons',0),
                                 (6,'foodIcons',1),(5,'groupObjects',99),(5,'elapsedMs',10),
                                 (5,'paneClass','CleanUI_Vanilla_ISInventoryPane'),(5,'rendererMatchesClass',False),
                                 (5,'freshnessBar',False),(21,'freshnessBar',True),(22,'freshnessPercentage',True),
                                 (5,'refresh',dict(calls=0,totalMs=1)),(5,'refresh',dict(calls=-1,totalMs=0)),
                                 (25,'tailGroup',10000),(26,'mode','clean'),(25,'rendererMatchesClass',False),
                                 (26,'paneClass','CleanUI_Clean_ISInventoryPane'),(27,'observers',False),(27,'freshnessOptions',False)]:
            changed=copy.deepcopy(rows);changed[index][1][key]=value
            with self.subTest(index=index,key=key),self.assertRaises(ValueError):V.verify(ROOT,log(changed))
        with self.assertRaises(ValueError):V.verify(ROOT,log(rows[1:]))
        with self.assertRaises(ValueError):V.verify(ROOT,log(rows)+'[STORAGE_PROFILE] FAIL\n')

    def work_selection(self, renderer):
        return dict(suite='storage-profile',cases=['inventory-work'],kind='sp',clients=1,mode='native',languages=['EN'],
                    mods=auxiliary.definitions()['storage-profile']['default_mods'],options={'inventory_work_renderer':renderer})

    def test_renderer_filter_requires_standalone_fresh_one_client_sp(self):
        for renderer in ('clean','vanilla'):
            auxiliary.validate(self.work_selection(renderer))
        for renderer in (None,False,True,0,'both','Clean',[],{}):
            with self.subTest(renderer=renderer),self.assertRaises(ValueError):
                auxiliary.validate(self.work_selection(renderer))
        base=self.work_selection('clean')
        foreign=[dict(base,suite='inventory-presentation',cases=['scenes']),
                 dict(base,cases=['inventory-work','inventory-freshness']),dict(base,cases=['walk']),
                 dict(base,cases=['inventory-freshness']),dict(base,cases=['inventory-food-age']),
                 dict(base,kind='mp'),dict(base,clients=2),dict(base,clients=True)]
        foreign.extend(dict(base,options={**base['options'],key:'/owned/input'}) for key in
                       ('seed_run','world_template','startup_connection','mp_host'))
        for selected in foreign:
            with self.subTest(selection=selected),self.assertRaises(ValueError):auxiliary.validate(selected)

    def test_renderer_filter_phases_and_dense_mode_changes_are_guarded(self):
        for renderer in ('clean','vanilla'):
            lua,fixture=self.fixture_runtime(renderer)
            lua.execute('''
                local fixture,renderer=...
                assert(#fixture.phases==10 and #fixture.modes==1 and fixture.modes[1]==renderer)
                for index,phase in ipairs(fixture.phases)do
                    assert(phase.mode==renderer and phase.freshness==(index<=8))
                    assert(phase.size==(index<=4 and 100 or 10000))
                end
                local foods={};for i=1,100 do foods[i]={}end
                fixture.seedFill({},foods,1)
                local enabled=renderer~='clean';local calls=0
                CleanUI_isCleanInventoryUIEnabled=function()return enabled end
                CleanUI_setCleanInventoryUIEnabled=function(value)calls=calls+1;enabled=value end
                fixture.selectMode(renderer);assert(calls==1 and enabled==(renderer=='clean'))
                for i=101,10000 do foods[i]={}end
                fixture.seedFill({},foods,5)
                for _,phase in ipairs(fixture.phases)do fixture.selectMode(phase.mode)end
                fixture.selectMode(fixture.modes[1]) -- final native freshness path
                assert(calls==1,'renderer-specific phases/freshness called a dense mode setter')
                enabled=not enabled
                assert(not pcall(fixture.selectMode,renderer),'dense external mode drift allowed recreation')
                assert(calls==1)
                assert(not pcall(fixture.selectMode,renderer=='clean'and'vanilla'or'clean'))
            ''',fixture,renderer)

    def test_renderer_specific_staging_and_exact_receipt_selection(self):
        for renderer in ('clean','vanilla'):
            selected=self.work_selection(renderer)
            rows=receipts(renderer)
            result=V.verify(ROOT,log(rows),selected)
            self.assertEqual(len(result['food']),10)
            self.assertEqual([row['mode'] for row in result['freshness']],[renderer])
            for other in (None,'vanilla' if renderer=='clean'else'clean'):
                with self.assertRaises(ValueError):V.verify(ROOT,log(rows),None if other is None else self.work_selection(other))
            with self.assertRaises(ValueError):V.verify(ROOT,log(receipts()),selected)
            for key,value in (('phases',20),('renderer','both')):
                changed=copy.deepcopy(rows);changed[0][1][key]=value
                with self.assertRaises(ValueError):V.verify(ROOT,log(changed),selected)
            for omitted in (5,13,15):
                with self.assertRaises(ValueError):V.verify(ROOT,log(rows[:omitted]+rows[omitted+1:]),selected)
            with tempfile.TemporaryDirectory()as temp:
                root=Path(temp);cache=root/'client1';cache.mkdir()
                runtime={'roles':{'client1':{'cache':str(cache)}}}
                def compile_probe(command,**kwargs):
                    classes=Path(command[6])/'toolkit/inventorywork';classes.mkdir(parents=True)
                    for name in ('Main.class','Main$FoodAge.class'):(classes/name).write_bytes(b'fixture')
                with mock.patch('subprocess.run',side_effect=compile_probe):
                    auxiliary.stage(ROOT,root,root/'game',root/'jdk',selected,{'PZSurvivorToolkit':ROOT/'PZSurvivorToolkit'},runtime)
                self.assertEqual(runtime['roles']['client1']['env'],{'PZ_INVENTORY_WORK_TEST_CACHE':str(cache)})
                staged=cache/'mods/StorageProfileNative/42/media/lua/client/ZZInventoryWorkProfile.lua'
                self.assertEqual(staged.read_bytes(),(INTAKE/'ZZInventoryWorkProfile.lua').read_bytes())
                (cache/'console.txt').write_text(log(rows))
                outcome=auxiliary.verify(root,selected,{})
                self.assertFalse(outcome['issues'],outcome)
                self.assertEqual(len(outcome['evidence']['food']),10)

    def test_selection_and_isolated_stage(self):
        self.assertEqual([case['capability']for case in auxiliary.definitions()['storage-profile']['cases']],['capture','capture','effect','effect'])
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
