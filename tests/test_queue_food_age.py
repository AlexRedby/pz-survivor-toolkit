"""Natural-age receipts require real visibility, identity, authority and cleanup."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import auxiliary
INTAKE = ROOT / 'tests/native_queue/contributions/storage-profile'
V = auxiliary._load(INTAKE / 'food_age_verify.py')


def selection(kind='sp'):
    return dict(suite='storage-profile', kind=kind, mode='toolkit', cases=['inventory-food-age'],
                languages=['EN'], clients=1, mods=list(auxiliary.INVENTORY_MODS),
                options={'mp_host': True} if kind == 'mp' else {})


def receipts(kind='sp', role='sp'):
    env = V.envelope(selection(kind), role)
    clock = dict(minutesPerDay=90, foodRotSpeed=3, foodRemoval=-1)
    food, off, maximum = ('Base.Apple', 5, 8) if kind == 'sp' else ('Base.Cabbage', 2, 4)
    result = [('AGE_SETUP', dict(env, foodType=food, phases=12, naturalAgeing=True,
                               ageControl='phase-setup-only', physicalInput=False, clockUnchanged=True,
                               forcedAgeUpdates=0, observationAgeWrites=0, fillersPerPhase=60, minutesPerDay=90,
                               clock=clock, periodicAgeReplication=False, initialStateReplication=kind=='mp'))]
    if role != 'server':
        result[0][1].update(
            uiBaseline=dict(stable=True, samples=3, intervalMs=120, deadlineMs=10000, elapsedMs=300,
                            stableSpanMs=240, sampleTimesMs=[60,180,300], pages=[
                                dict(page=i, inventoryBound=True, owner=dict(x=0,y=0,width=427,height=300),
                                     pane=dict(x=0,y=45,width=389,height=255)) for i in (1,2)]),
            uiPreflight=dict(modeChanged=True, resized=True, relocated=True, restored=True, originalMode=True,
                             temporaryMode=False, deadlineMs=10000, elapsedMs=10, pages=[
                                 dict(page=i, original=dict(x=0,y=0,width=427,height=300),
                                      temporary=dict(x=30,y=50,width=1000,height=460), restored=dict(x=0,y=0,width=427,height=300))
                                 for i in (1,2)]))
    for index, (size, mode, exposure) in enumerate(V.SPECS, 1):
        world = 100 + index
        ids = list(range(index * 1000, index * 1000 + size))
        row = dict(env, index=index, size=size, paneMode=mode, exposure=exposure, foodType=food,
                   headId=ids[0], tailId=ids[-1], foodIds=ids,
                   ageBefore=off-.004, ageAfter=off+.005, offAge=off, offAgeMax=maximum,
                   worldBefore=world, worldAfter=world+.4, eventWorld=world+.21,
                   events=0 if role=='server' else 1, headFresh=True, tailFresh=False,
                   identities=True, endpoint='root' if kind=='sp' else 'ambient', minutesPerDay=90,
                   naturalAgeing=True, observationAgeWrites=0, forcedAgeUpdates=0, clock=clock)
        if role=='server':row.update(serverOwned=True,clientPhaseComplete=True)
        if kind=='mp' and role=='client':
            row['authority']=dict(index=index,headId=ids[0],tailId=ids[-1],foodType=food,endpoint='ambient',
                                  count=size,identities=True,headFresh=True,tailFresh=False,
                                  tailAge=off+.005,world=world+.4,clock=clock)
        if role != 'server':
            row.update(paneClass='CleanUI_' + ('Clean' if mode=='clean' else 'Vanilla') + '_ISInventoryPane',
                       optimized=mode=='clean' and size==200, headGroup=size-1, tailGroup=1,
                       separatePublishedRows=True, tailBeyond50=True, primaryPasses=100)
            start = dict(world=world+.01, age=off-.003, events=0, primaryPasses=10,
                         pageVisible=exposure!='hidden', paneVisible=True, rowTop=-60 if exposure=='clipped' else 25,
                         rowBottom=-40 if exposure=='clipped' else 45, header=20, height=150,
                         rowVisible=exposure=='visible', scroll=-100 if exposure=='clipped' else 0,
                         minScroll=-100, scrollAreaHeight=150, scrollHeight=250, fillerVisibleRows=5)
            finish = dict(start, world=world+.2, age=off-.003 if exposure!='visible' else off+.005,
                          primaryPasses=10 if exposure=='hidden' else 40)
            row['exposureProof'] = dict(start=start, finish=finish, potentialThresholdWorld=world+.096,
                                       concealedWorldHours=.19, foodVisiblePasses=30 if exposure=='visible' else 0)
            row['cycles'] = [dict(cycle=i, expandedActualCount=size, collapsedActualCount=size,
                                 headGroup=size-1, tailGroup=1, identities=True, expandedPublishedRows=52)
                             for i in range(1,4)]
        result.append(('AGE_PHASE', row))
    restored = dict(env, ownedRemoved=2394, fillerRemoved=720, objectsRemoved=12 if kind=='mp' else 0,
                    originalItems=5, items=True, settings=True, phases=12, minutesPerDay=90, clock=clock)
    if role!='server': restored.update(observers=True, ui=True)
    if kind=='mp' and role=='client':
        position=dict(x=10.25,y=20.75,z=0,squareX=10,squareY=20,squareZ=0)
        restored.update(positionRestored=True,positionProof=dict(original=position,
                        actual=dict(position,currentSquareX=10,currentSquareY=20,currentSquareZ=0,moving=False,hasPath=False),
                        elapsedMs=200,deadlineMs=10000,minimumWaitMs=100))
    result.extend([('AGE_RESTORED',restored),('AGE_COMPLETE',dict(env,phases=12,restored=True))])
    return result


def log(rows):
    return '\n'.join('[STORAGE_PROFILE] '+event+' '+json.dumps(row) for event,row in rows)+'\n'


def phase(rows, exposure='hidden'):
    return next(row for event,row in rows if event=='AGE_PHASE' and row['exposure']==exposure)


class NativeFoodAgeQueueTests(unittest.TestCase):
    def verify(self, data, kind='sp', server=None):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            if server is not None: (root/'server-launch.log').write_text(log(server))
            return V.verify(root,log(data),selection(kind))

    def test_complete_sp_and_host_natural_expiry_evidence(self):
        for kind in ('sp','mp'):
            result=self.verify(receipts(kind,'sp' if kind=='sp' else 'client'),kind,
                               receipts('mp','server') if kind=='mp' else None)
            self.assertEqual(len(result['food_age']['sp' if kind=='sp' else 'client']['phases']),12)

    def test_native_numeric_id_can_recur_after_a_completed_phase_release(self):
        # Native factory IDs are random; a new phase can receive a retired ID.
        for kind in ('sp','mp'):
            client=receipts(kind,'sp' if kind=='sp' else 'client')
            server=receipts('mp','server') if kind=='mp' else None
            for rows in (client,server):
                if rows is not None:
                    rows[9][1]['foodIds'][1]=rows[1][1]['foodIds'][1]
            result=self.verify(client,kind,server)
            self.assertEqual(len(result['food_age']['sp' if kind=='sp' else 'client']['phases']),12)

    def test_reused_id_still_requires_unique_live_members_and_matching_replicas(self):
        client,server=receipts('mp','client'),receipts('mp','server')
        client[9][1]['foodIds'][1]=client[1][1]['foodIds'][1]
        with self.assertRaisesRegex(ValueError,'Client/server item replicas differ'):
            self.verify(client,'mp',server)
        server[9][1]['foodIds'][1]=server[1][1]['foodIds'][1]
        for rows in (client,server):
            rows[9][1]['foodIds'][2]=rows[9][1]['foodIds'][1]
        with self.assertRaisesRegex(ValueError,'Owned food identities'):
            self.verify(client,'mp',server)

    def test_ui_baseline_and_preflight_are_required(self):
        mutations = [
            lambda row: row.pop('uiBaseline'),
            lambda row: row.update(uiBaseline=[]),
            lambda row: row.update(uiPreflight=None),
            lambda row: row['uiBaseline']['pages'][0].update(pane=None),
            lambda row: row['uiBaseline'].update(samples=1),
            lambda row: row['uiBaseline'].update(sampleTimesMs=[0,1,2]),
            lambda row: row['uiBaseline'].update(stableSpanMs=241),
            lambda row: row['uiBaseline'].update(elapsedMs=10000),
            lambda row: row['uiBaseline']['pages'][0]['pane'].update(y=68,height=281),
            lambda row: row['uiBaseline']['pages'][0].update(inventoryBound=False),
            lambda row: row['uiPreflight'].update(temporaryMode=True),
            lambda row: row['uiPreflight'].update(relocated=False),
            lambda row: row['uiPreflight']['pages'][0]['temporary'].update(x=0),
            lambda row: row['uiPreflight']['pages'][0]['restored'].update(x=1),
            lambda row: row['uiPreflight']['pages'][0]['temporary'].update(width=427),
            lambda row: row['uiPreflight']['pages'][0]['restored'].update(height=299),
        ]
        for mutate in mutations:
            data=receipts();mutate(data[0][1])
            with self.assertRaises(ValueError):self.verify(data)

    def test_concealment_regrouping_and_ownership_fail_closed(self):
        mutations=[
            lambda r:r[0][1].update(forcedAgeUpdates=1),
            lambda r:r[0][1].update(clockUnchanged=False),
            lambda r:phase(r).update(events=0),
            lambda r:phase(r).update(events=2),
            lambda r:phase(r).update(ageAfter=4.999),
            lambda r:phase(r).update(headFresh=False),
            lambda r:phase(r).update(tailFresh=True),
            lambda r:phase(r).update(tailBeyond50=False),
            lambda r:phase(r).update(separatePublishedRows=False),
            lambda r:phase(r).update(headGroup=199),
            lambda r:phase(r).update(minutesPerDay=5),
            lambda r:phase(r).update(eventWorld=0),
            lambda r:phase(r)['foodIds'].__setitem__(1,phase(r)['foodIds'][0]),
            lambda r:phase(r)['exposureProof'].update(foodVisiblePasses=1),
            lambda r:phase(r)['exposureProof'].update(potentialThresholdWorld=999),
            lambda r:phase(r)['exposureProof'].update(concealedWorldHours=0),
            lambda r:phase(r)['exposureProof']['start'].update(age=5),
            lambda r:phase(r)['exposureProof']['start'].update(rowVisible=True),
            lambda r:phase(r,'clipped')['exposureProof']['finish'].update(pageVisible=False),
            lambda r:phase(r,'clipped')['exposureProof']['finish'].update(rowTop=25,rowBottom=45),
            lambda r:phase(r,'clipped')['exposureProof']['finish'].update(primaryPasses=10),
            lambda r:phase(r,'clipped')['exposureProof']['finish'].update(scroll=-1000000),
            lambda r:phase(r,'clipped')['exposureProof']['finish'].update(fillerVisibleRows=0),
            lambda r:phase(r)['cycles'].pop(),
            lambda r:phase(r)['cycles'][1].update(identities=False),
            lambda r:phase(r)['cycles'][1].update(expandedPublishedRows=2),
            lambda r:r[-2][1].update(ownedRemoved=2393),
            lambda r:r[-2][1].update(ui=False),
            lambda r:r[-2][1].update(minutesPerDay=5),
        ]
        for mutate in mutations:
            changed=receipts();mutate(changed)
            with self.subTest(mutation=mutate),self.assertRaises(ValueError):self.verify(changed)
        good=receipts()
        for changed in (good[1:],good[:-1],good+[good[-1]],good[:1]+list(reversed(good[1:]))):
            with self.assertRaises(ValueError):self.verify(changed)

    def test_host_requires_independent_natural_authority(self):
        client=receipts('mp','client')
        for mutation in (lambda r:phase(r).update(ageAfter=1.999),
                         lambda r:phase(r).update(events=1),
                         lambda r:phase(r)['foodIds'].__setitem__(1,999999),
                         lambda r:phase(r).update(tailId=phase(r)['headId']),
                         lambda r:r[-2][1].update(objectsRemoved=0)):
            server=receipts('mp','server');mutation(server)
            with self.assertRaises(ValueError):self.verify(client,'mp',server)
        for mutation in (lambda r:r[-2][1]['positionProof']['actual'].update(currentSquareX=9),
                         lambda r:r[-2][1]['positionProof']['actual'].update(x=10),
                         lambda r:r[-2][1]['positionProof']['actual'].update(moving=True),
                         lambda r:r[-2][1]['positionProof'].update(elapsedMs=10),
                         lambda r:r[-2][1]['positionProof'].update(elapsedMs=10000)):
            changed=receipts('mp','client');mutation(changed)
            with self.assertRaises(ValueError):self.verify(changed,'mp',receipts('mp','server'))

    def test_malformed_receipts_cannot_hide_behind_logger_prefix(self):
        good='\n'.join('LOG : Lua > '+line for line in log(receipts()).splitlines())
        self.assertEqual(len(V.verify(ROOT,good,selection())['food_age']['sp']['phases']),12)
        for extra in ('AGE_UNKNOWN {}','AGE_PHASE','AGE_PHASE null','AGE_PHASE []','AGE_PHASE {broken}',
                      'AGE_PHASE {"index":1,"index":2}','AGE_PHASE {"ageAfter":NaN}',
                      'AGE_PHASE '+' '*32768+'{}','FAIL {}'):
            with self.subTest(extra=extra[:60]),self.assertRaises(ValueError):
                V.verify(ROOT,good+'\nLOG : Lua > [STORAGE_PROFILE] '+extra,selection())

    def test_selection_and_staging(self):
        case=next(row for row in auxiliary.definitions()['storage-profile']['cases'] if row['id']=='inventory-food-age')
        self.assertEqual(case['capability'],'effect');self.assertEqual(case['kinds'],['sp','mp'])
        for kind in ('sp','mp'):
            selected=selection(kind);auxiliary.validate(selected)
            with tempfile.TemporaryDirectory() as directory:
                root=Path(directory);runtime={'roles':{'client1':{'cache':str(root/'client1')}}}
                if kind=='mp':runtime['roles']['server']={'cache':str(root/'server')}
                auxiliary.stage(ROOT,root,root/'game',root/'jdk',selected,
                                {'PZSurvivorToolkit':ROOT/'PZSurvivorToolkit'},runtime)
                for role in runtime['roles'].values():
                    lua=Path(role['cache'])/'mods/StorageProfileNative/42/media/lua'
                    for side,name in (('client','ZZFoodAgeNative.lua'),('shared','QueueFoodAgeFixture.lua'),('server','ZZFoodAgeServer.lua')):
                        self.assertEqual((lua/side/name).read_bytes(),(INTAKE/name).read_bytes())
                    self.assertTrue((lua/'client/ZZStartup.lua').exists())
                    self.assertTrue((lua/'shared/QueueHealthEvents.lua').exists())
                self.assertEqual(runtime['fixture']['server_ready'],'[STARTUP_TEST] SERVER_READY')
                (root/'client1/console.txt').write_text(log(receipts(kind,'sp' if kind=='sp' else 'client')))
                if kind=='mp':(root/'server-launch.log').write_text(log(receipts('mp','server')))
                self.assertFalse(auxiliary.verify(root,selected,{})['issues'])
        for bad in (dict(selection('mp'),options={}),dict(selection(),clients=2),
                    dict(selection(),options={'world_template':'saved'}),dict(selection(),languages=['RU'])):
            with self.assertRaises(ValueError):auxiliary.validate(bad)
        for case in ('walk','inventory-work','inventory-freshness'):
            with self.assertRaises(ValueError):auxiliary.validate(dict(selection('mp'),cases=[case]))

    def test_lua_fixture_syntax_and_no_observer_age_updates(self):
        from lupa.lua51 import LuaRuntime
        lua=LuaRuntime()
        sources=[INTAKE/name for name in ('ZZFoodAgeNative.lua','QueueFoodAgeFixture.lua','ZZFoodAgeServer.lua')]
        for path in sources:
            source=path.read_text();lua.execute('assert(loadstring(...))',source)
            self.assertNotIn(':updateAge(',source)
        self.assertEqual(sum(path.read_text().count(':setAge(') for path in sources),1)


    def test_passive_observer_and_live_ui_reconstruction(self):
        from lupa.lua51 import LuaRuntime
        SOURCE=(INTAKE / 'ZZFoodAgeNative.lua').read_text()
        def base():
         lua=LuaRuntime()
         lua.execute('''
         fixtureDiagnostics={}
         require=function()return {cases={'inventory-food-age'},module='StorageFoodAgeTest',emit=function(event,row)
          fixtureDiagnostics[#fixtureDiagnostics+1]={event=event,row=row}
         end}end
         Events={};for _,name in ipairs({'OnServerCommand','OnGameStart','OnTick','OnContainerUpdate'})do
          Events[name]={Add=function(callback)Events[name].callback=callback end,Remove=function()end}
         end
         getGameTime=function()return {getWorldAgeHours=function()return 100 end}end
         fixtureTime=0;getTimestampMs=function()return fixtureTime end
         testAdvance=function(ms)fixtureTime=fixtureTime+ms end
         ''')
         return lua

        lua=base()
        f=lua.execute(SOURCE+'''
        return {observe=observe,restore=restoreObserver,rows=rows,bounds=bounds,
         seed=function(testPane,testPage,testFoods,testFillers)
          pane=testPane;page=testPage;foods=testFoods;head=foods[1];tail=foods[#foods];foodSet={};fillerSet={}
          for _,item in ipairs(foods)do foodSet[item]=true end;for _,item in ipairs(testFillers)do fillerSet[item]=true end
          passes=0;published=nil;observerFailure=nil;events=0;concealing=false;current={spec={exposure='visible'}}
         end,failed=function()return observerFailure end,
         concealCount=function(on)concealing=on;foodVisiblePasses=0 end,count=function()return foodVisiblePasses end}
        ''')
        lua.execute('''
         local f=...
         local head,tail={getAge=function()return .1 end},{getAge=function()return 4.996 end};local filler={}
         local rows={{name='Fresh',items={head,head,tail}}}
         local fault,calls={},0
         local pane={items={},headerHgt=20,itemHgt=20,scroll=0,getYScroll=function(self)return self.scroll end,
          getHeight=function()return 200 end,getMaxDrawHeight=function()return -1 end,
          getScrollHeight=function()return 1000 end,getScrollAreaHeight=function()return 200 end,
          getIsVisible=function()return true end,isReallyVisible=function()return true end,
          renderdetails=function(self,dragged)
           calls=calls+1;if calls==1 then error(fault,0)end
           if not dragged then self.items=rows end;return 'native',nil,'tail'
          end}
         local page={getIsVisible=function(self)return self.visible end,isReallyVisible=function(self)return self.visible end,visible=true}
         local original=pane.renderdetails;f.seed(pane,page,{head,tail},{filler});f.observe();assert(f.rows()==nil)
         local ok,err=pcall(pane.renderdetails,pane,false);assert(not ok and err==fault and f.failed()==fault)
         pane:renderdetails(true);assert(f.rows()==nil)
         local a,b,c=pane:renderdetails(false);assert(a=='native'and b==nil and c=='tail')
         local info=f.rows();assert(info.count==2 and info.headRow==info.tailRow and info.tailGroup==2)
         rows={{name='fresh',items={head,head}},{name='stale',items={tail,tail}}}
         pane:renderdetails(false);info=f.rows();assert(info.tailGroup==1 and info.headGroup==1 and info.tailRow~=info.headRow)
         rows={rows[1],head,rows[2],tail};pane:renderdetails(false)
         info=f.rows();assert(info.count==2 and info.expandedRows==2 and info.renderedFoodCount==2)
         f.concealCount(true);pane.scroll=-800;pane:renderdetails(false);assert(f.count()==0 and not f.bounds(1).rowVisible)
         pane.scroll=0;pane:renderdetails(false);assert(f.count()==1 and f.bounds(1).rowVisible)
         rows[5]={items={filler,filler}};pane:renderdetails(false);assert(f.rows().fillerVisibleRows==1)
         page.visible=false;pane:renderdetails(false);assert(f.count()==2 and not f.bounds(1).pageVisible)
         rows[3].items={tail,tail,tail};assert(not pcall(f.rows),'duplicate owned native member accepted')
         f.restore();assert(pane.renderdetails==original)
         f.observe();local foreign=function()end;pane.renderdetails=foreign;assert(not pcall(f.restore)and pane.renderdetails==foreign)
        ''',f)

        lua=base()
        lua.execute('''
         ISInventoryPane={MAX_ITEMS_IN_STACK_TO_RENDER=50}
         local mode=true;local option={value=true,getValue=function(self)return self.value end,setValue=function(self,v)self.value=v end}
         PZAPI={ModOptions={getOptions=function()return {getOption=function()return option end}end}}
         local player={god=false,ghost=false,isGodMod=function(self)return self.god end,isGhostMode=function(self)return self.ghost end,
          setGodMod=function(self,v)self.god=v end,setGhostMode=function(self,v)self.ghost=v end}
         getPlayer=function()return player end
         local core={focus=true,getOptionPauseOnFocusloss=function(self)return self.focus end,setOptionPauseOnFocusloss=function(self,v)self.focus=v end,
          getScreenWidth=function()return 1280 end,getScreenHeight=function()return 720 end}
         getCore=function()return core end
         local head,tail={},{};local root={head=head,tail=tail};local loot={head={},tail={}}
         local generation=0;local pages;local nativeLayout='owner'
         testNativeLayout=function(value)nativeLayout=value end
         local function pageFactory(container,n)
          local width=generation>0 and 900 or 600
          local page={valid=true,pin=false,isCollapsed=true,collapseCounter=7,forceSelectedContainer=container,forceSelectedContainerTime=99,
           x=n==1 and 213 or n==2 and 640 or 30,y=20+n,width=width,height=350,visible=true,maxDrawHeight=-1,controlsWidth=width}
          local pane={valid=true,inventory=container,mode='icons',x=2,y=40,width=width-20,height=310,visible=true,maxDrawHeight=-1,
           collapsed={old=false},selected={[1]=true,[3]=true},scroll=-10,firstSelect=3,joyselection=0,mouseOverOption=17,smoothScrollY=-11,smoothScrollTargetY=-12}
          page.inventoryPane=pane;page.inventory=container
          local function alive(self)assert(self.valid,'obsolete page/pane touched after mode rebuild')end
          local props={X='x',Y='y',Width='width',Height='height',MaxDrawHeight='maxDrawHeight',IsVisible='visible',YScroll='scroll'}
          for suffix,key in pairs(props)do
           for _,obj in ipairs({page,pane})do
            obj['get'..suffix]=function(self)alive(self);return self[key]end
            obj['set'..(suffix=='IsVisible'and 'Visible'or suffix)]=function(self,v)
             alive(self)
             if self.inventoryPane and (key=='x'or key=='y')then
              v=math.max(0,math.min(v,(key=='x'and 1280 or 720)-(key=='x'and self.width or self.height)))
             end
             self[key]=v
             if self.inventoryPane and (key=='width'or key=='height')then self:setX(self.x);self:setY(self.y)end
            end
           end
          end
          pane.setMode=function(self,v)alive(self);self.mode=v end
          pane.refreshContainer=function(self)alive(self);self.itemslist={{name='old',items={self.inventory.head,self.inventory.head,self.inventory.tail}}}end
          pane.saveSelection=function(self,out)
           alive(self);out._cleanUISelectedGroups={}
           if self.selected[1]then out[self.inventory.head]='group'end
           if self.selected[3]then out[self.inventory.tail]='item'end;return out
          end
          pane.restoreSelection=function(self,input)
           alive(self);self.selected={}
           if input[self.inventory.head]=='group'then self.selected[1]=true end
           if input[self.inventory.tail]=='item'then self.selected[3]=true end
          end
          page.arrangeControls=function(self)
           alive(self)
           -- Native arrange uses the previous control width and the other page's binding.
           self.controlsHeight=(self.controlsWidth<700 and 20 or 10)+(pages and pages[2].inventory~=loot and 20 or 0)
           self.controlsWidth=self.width
          end
          page.refreshBackpacks=function(self)
           alive(self);self.backpacks={{inventory=root},{inventory=loot}};self:arrangeControls()
           -- Native refresh calculates height before updating the pane's Y position.
           pane:setHeight(self.height-pane.y);pane:setY(20+self.controlsHeight)
          end
          page.cleanUIApplyScaleSettings=function(self,force)
           alive(self);assert(force);self:arrangeControls()
           pane:setX(2);pane:setWidth(self.width-20);pane:setY(20+self.controlsHeight);pane:setHeight(self.height-pane.y)
           if nativeLayout=='nonconverging'then pane:setHeight(pane.height+1)end
          end
          if nativeLayout=='fallback'then page.cleanUIApplyScaleSettings=nil end
          page.setNewContainer=function(self,v)alive(self);self.inventory=v;self.inventoryPane.inventory=v;self.inventoryPane:refreshContainer()end
          page.setPinned=function(self)alive(self);self.pin=true end
          page.collapse=function(self)alive(self);self.pin=false;self.isCollapsed=true end
          pane:refreshContainer();page:refreshBackpacks();return page
         end
         pages={pageFactory(root,1),pageFactory(loot,2)}
         getPlayerInventory=function()return pages[1]end;getPlayerLoot=function()return pages[2]end
         CleanUI_isCleanInventoryUIEnabled=function()return mode end
         CleanUI_setCleanInventoryUIEnabled=function(value)
          if mode==value then return end;mode=value;generation=generation+1
          for _,p in ipairs(pages)do p.valid=false;p.inventoryPane.valid=false end
          pages={pageFactory(root,10+generation),pageFactory(loot,20+generation)}
         end
         testAlter=function()
          CleanUI_setCleanInventoryUIEnabled(false);option:setValue(false);player.god=true;player.ghost=true;core.focus=false
          pages[1]:setVisible(false);pages[2]:setWidth(1000);pages[2]:setHeight(460)
          pages[2]:setX(30);pages[2]:setY(50);pages[2]:setNewContainer(root)
         end
         testTransient=function()pages[1].inventoryPane.y=68;pages[1].inventoryPane.height=381 end
         testOwnerWidth=function(width)pages[1]:setWidth(width)end
         testAssert=function()
          assert(mode and option.value and not player.god and not player.ghost and core.focus)
          assert(pages[1].x==213 and pages[2].x==640 and pages[1].width==600 and pages[2].width==600)
          for _,p in ipairs(pages)do local q=p.inventoryPane
           assert(p.visible and not p.pin and p.isCollapsed and q.selected[1]and q.selected[3]and q.firstSelect==3 and q.joyselection==0)
           assert(q.scroll==-10 and q.smoothScrollY==-11 and q.smoothScrollTargetY==-12 and q.mouseOverOption==17)
           assert(q.x==2 and q.y==40 and q.width==580 and q.height==310,'dependent native pane layout was not restored')
          end
         end
        ''')
        f=lua.execute(SOURCE+'''
        return {capture=function()ui=saveUI();return ui end,restore=restoreUI,lifecycle=uiLifecycle}
        ''')
        f.capture();lua.eval('testAlter')();f.restore();lua.eval('testAssert')()
        lua.eval('testNativeLayout')('fallback')
        f.capture();lua.eval('testAlter')();f.restore();lua.eval('testAssert')()
        lua.eval('testTransient')()
        baseline=f.lifecycle.beginBaseline()
        self.assertIsNone(f.lifecycle.sampleBaseline(baseline))
        lua.eval('testAdvance')(100)
        self.assertIsNone(f.lifecycle.sampleBaseline(baseline))
        lua.eval('testAdvance')(20);lua.eval('testOwnerWidth')(610)
        self.assertIsNone(f.lifecycle.sampleBaseline(baseline))
        lua.eval('testAdvance')(120);lua.eval('testOwnerWidth')(600)
        self.assertIsNone(f.lifecycle.sampleBaseline(baseline))
        lua.eval('testAdvance')(120)
        self.assertIsNone(f.lifecycle.sampleBaseline(baseline))
        lua.eval('testAdvance')(120)
        proof=f.lifecycle.sampleBaseline(baseline)
        self.assertEqual(proof.samples,3);self.assertEqual(proof.stableSpanMs,240)
        self.assertEqual(proof.pages[1].pane.y,40);self.assertEqual(proof.pages[1].pane.height,310)
        missing=f.lifecycle.beginBaseline();self.assertIsNone(f.lifecycle.sampleBaseline(missing))
        lua.execute('originalLoot=getPlayerLoot;getPlayerLoot=function()return nil end')
        lua.eval('testAdvance')(1);self.assertIsNone(f.lifecycle.sampleBaseline(missing))
        self.assertEqual(missing.samples,0)
        lua.execute('getPlayerLoot=originalLoot')
        lua.eval('testAdvance')(1);self.assertIsNone(f.lifecycle.sampleBaseline(missing))
        self.assertEqual(missing.samples,1)
        lua.eval('testNativeLayout')('owner')
        preflight=f.lifecycle.preflight(f.capture())
        self.assertTrue(preflight.restored);self.assertTrue(preflight.modeChanged);self.assertTrue(preflight.resized)
        lua.eval('testAssert')()
        expired=f.lifecycle.beginBaseline();lua.eval('testAdvance')(10000)
        with self.assertRaisesRegex(Exception,'initial native UI layout did not settle'):
            f.lifecycle.sampleBaseline(expired)
        lua.eval('testNativeLayout')('nonconverging')
        f.capture();lua.eval('testAlter')()
        with self.assertRaisesRegex(Exception, 'bounded native owner layout'):
            f.restore()
        lua.execute('''
         local proof=fixtureDiagnostics[#fixtureDiagnostics]
         assert(proof.event=='DIAGNOSTIC'and proof.row.stage=='restore-ui-layout'and proof.row.attempts==4)
         assert(proof.row.pages[1].expected.pane.height==310 and proof.row.pages[1].actual.pane.height==311)
        ''')


    def test_host_authority_requires_ordered_owned_phase_completion(self):
        from lupa.lua51 import LuaRuntime
        SOURCE=(INTAKE / 'ZZFoodAgeServer.lua').read_text()
        SETUP='''
         local fresh=true
         local head={isFresh=function()return true end};local tail={getID=function()return 22 end}
         local player={getUsername=function()return 'client1'end,getSquare=function()return {getX=function()return 10 end,getY=function()return 20 end,getZ=function()return 0 end}end}
         fixturePlayer=player;fixtureReplies={};fixtureEmits={};fixtureCounts={release=0}
         local F={module='StorageFoodAgeTest',phases={1,2}}
         F.newSession=function(p)return {player=p,token='owned-session',index=0}end
         F.setup=function()end
         F.preparePhase=function(s,index)assert(not s.phase and index==s.index+1);s.index=index;s.phase={index=index,head=head,tail=tail,owned={[11]=head},beforeWorld=99};return {token=s.token,index=index,tailId=22}end
         F.snapshot=function(s,p)return {index=p.index,headId=11,tailId=22,tailFresh=fresh,headFresh=true,world=100}end
         F.receipt=function(s,p)return {index=p.index}end
         F.emit=function(event,row)table.insert(fixtureEmits,{event=event,row=row})end
         F.release=function(s)fixtureCounts.release=fixtureCounts.release+1;s.phase=nil;return {index=s.index}end
         F.restored=function(s,row)assert(s.index==2);return {restored=true}end
         fixtureFresh=function(v)fresh=v end
         require=function()return F end
         isServer=function()return true end
         instanceof=function(item,kind)return kind=='Food'and item==head end
         Events={};for _,name in ipairs({'OnClientCommand','OnContainerUpdate','OnTick'})do Events[name]={Add=function(fn)Events[name].callback=fn end}end
         sendServerCommand=function(p,module,name,result)fixtureReplies[name]=result end
         getTimestampMs=function()return 100 end
         send=function(command,args)args=args or {};args.case='inventory-food-age';Events.OnClientCommand.callback('StorageFoodAgeTest',command,fixturePlayer,args)end
        '''
        def run(script):
         lua=LuaRuntime();lua.execute(SETUP);lua.execute(SOURCE);lua.execute(script)
        run('''
         send('Prepare',{index=1,spawn={x=10,y=20,z=0}});assert(fixtureReplies.Prepared.token=='owned-session')
         send('Ready',{token='owned-session',index=1,tailId=22});assert(fixtureReplies.Readyd.tailFresh)
         fixtureFresh(false);send('Status',{token='owned-session',index=1});assert(fixtureReplies.Statusd.ready)
         send('Finish',{token='owned-session',index=1,headId=11});assert(fixtureReplies.Finishd and fixtureEmits[1].event=='AGE_PHASE'and fixtureEmits[1].row.events==0)
         assert(fixtureCounts.release==0,'authority items removed before client can emit its receipt')
         send('Release',{token='owned-session',index=1});assert(fixtureCounts.release==1)
         fixtureFresh(true);send('Prepare',{token='owned-session',index=2});assert(fixtureReplies.Prepared.index==2)
         send('Ready',{token='owned-session',index=2,tailId=22});fixtureFresh(false)
         send('Finish',{token='owned-session',index=2,headId=11});send('Release',{token='owned-session',index=2})
         send('Cleanup',{token='owned-session',index=2});assert(fixtureReplies.Cleanupd.restored and not fixtureReplies.Failed)
         local released,emitted=fixtureCounts.release,#fixtureEmits
         send('Abort',{token='owned-session',index=2});assert(fixtureReplies.Abortd.alreadyCompleted)
         assert(fixtureCounts.release==released and #fixtureEmits==emitted,'completed abort repeated cleanup or receipts')
         fixtureReplies.Abortd=nil
         send('Abort',{token='foreign-session',index=2});assert(fixtureReplies.Failed and not fixtureReplies.Abortd)
        ''')
        for command,args,prepare in [
         ('Release',"{token='owned-session',index=1}",''),
         ('Finish',"{token='owned-session',index=1,headId=11}",''),
         ('Finish',"{token='owned-session',index=1,headId=999}","send('Ready',{token='owned-session',index=1,tailId=22});fixtureFresh(false)"),
         ('Ready',"{token='foreign-session',index=1,tailId=22}",''),
        ]:
         run("send('Prepare',{index=1,spawn={x=10,y=20,z=0}});"+prepare+
             "send('"+command+"',"+args+");assert(fixtureReplies.Failed and not fixtureReplies."+command+"d);"+
             "assert(fixtureCounts.release==1 and fixtureEmits[#fixtureEmits].event=='FAIL')")


    def test_host_position_return_waits_for_native_square_and_keeps_fractions(self):
        from lupa.lua51 import LuaRuntime
        source=(INTAKE / 'ZZFoodAgeNative.lua').read_text()
        lua=LuaRuntime()
        lua.execute('''
         require=function()return {cases={'inventory-food-age'},module='StorageFoodAgeTest'}end
         Events={};for _,name in ipairs({'OnServerCommand','OnGameStart','OnTick','OnContainerUpdate'})do
          Events[name]={Add=function(callback)Events[name].callback=callback end,Remove=function()end}
         end
         fixtureTime=0;getTimestampMs=function()return fixtureTime end;isClient=function()return true end
         local function square(x,y,z)return {getX=function()return x end,getY=function()return y end,getZ=function()return z end}end
         fixtureOrigin={x=10.25,y=20.75,z=0,squareX=10,squareY=20,squareZ=0}
         fixtureSquare=square(99,99,0);fixtureCurrentSquare=fixtureSquare
         fixturePlayer={x=99.5,y=99.5,z=0,moving=false,path=nil,
          getX=function(self)return self.x end,getY=function(self)return self.y end,getZ=function(self)return self.z end,
          getSquare=function()return fixtureSquare end,getCurrentSquare=function()return fixtureCurrentSquare end,
          isPlayerMoving=function(self)return self.moving end,getPath2=function(self)return self.path end,
          teleportTo=function(self,x,y,z)self.x=math.floor(x);self.y=math.floor(y);self.z=z;self.teleports=(self.teleports or 0)+1 end,
          setForceX=function(self,x)self.x=x;self.nextX=x;self.lastX=x end,
          setForceY=function(self,y)self.y=y;self.nextY=y;self.lastY=y end,setZ=function(self,z)self.z=z end}
         getPlayer=function()return fixturePlayer end
         fixtureSetSquares=function(a,b)
          fixtureSquare=a and square(10,20,0)or nil;fixtureCurrentSquare=b and square(10,20,0)or square(99,99,0)
         end
        ''')
        f=lua.execute(source+'''
        return {seed=function(original)position=original end,begin=returnPosition.begin,poll=returnPosition.poll,stage=function()return stage end}
        ''')
        lua.execute('''
         local f=...;f.seed(fixtureOrigin);f.begin()
         assert(f.stage()=='return-position'and fixturePlayer.teleports==1)
         assert(fixturePlayer.x==10.25 and fixturePlayer.y==20.75 and fixturePlayer.nextX==10.25 and fixturePlayer.lastX==10.25
          and fixturePlayer.nextY==20.75 and fixturePlayer.lastY==20.75,'fractional original/next/last positions not restored')
         assert(f.poll()==nil,'same-tick return accepted')
         fixtureTime=200;assert(f.poll()==nil,'stale current square accepted')
         fixtureSetSquares(true,false);assert(f.poll()==nil,'one stale square API accepted')
         fixtureSetSquares(true,true);fixturePlayer.moving=true;assert(f.poll()==nil,'moving return accepted')
         fixturePlayer.moving=false;fixturePlayer.path={};assert(f.poll()==nil,'pathing return accepted')
         fixturePlayer.path=nil;fixturePlayer.x=10.5;assert(f.poll()==nil,'wrong fractional coordinate accepted')
         fixturePlayer.x=10.25;fixtureTime=700;local proof=f.poll()
         assert(proof.original.x==10.25 and proof.original.y==20.75 and proof.actual.x==10.25 and proof.actual.y==20.75)
         assert(proof.actual.squareX==10 and proof.actual.squareY==20 and proof.actual.currentSquareX==10 and proof.actual.currentSquareY==20)
         assert(not proof.actual.moving and not proof.actual.hasPath and proof.elapsedMs==700 and proof.deadlineMs==10000 and proof.minimumWaitMs==100)
         fixtureSetSquares(false,false);assert(f.poll()==nil,'missing square accepted')
         fixtureTime=10000;assert(not pcall(f.poll),'ten-second restoration deadline not enforced')
         assert(fixturePlayer.teleports==1,'poll repeated teleport instead of waiting normal updates')
        ''',f)


if __name__=='__main__':unittest.main()
