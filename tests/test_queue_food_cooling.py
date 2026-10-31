"""Adversarial receipt and staging checks for live food-cooling evidence."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import adapters
from queue_checks.adapters import food_cooling as cooling


def selection(kind='sp', case='appliances'):
    return {'suite': 'food-cooling', 'kind': kind, 'mode': 'native', 'cases': [case],
            'languages': ['EN'], 'clients': 1, 'options': {'mp_host': kind == 'mp'}}


def snapshot(world, powered, endpoint, chilled, frozen, thaw=False):
    return {'world': world, 'minutesPerDay': 5, 'sandbox': {'DaysForRottenFoodRemoval': -1},
            'generator': {'active': powered, 'connected': True, 'fuel': 90, 'condition': 100},
            'appliance': {'nickLoaded': True, 'unplugged': False, 'auto': False},
            'containers': {
                'fridge': {'type': 'fridge', 'powered': powered, 'temperature': .2 if powered else 1,
                           'customTemperature': 0, 'x': 100, 'y': 100, 'z': 0},
                'freezer': {'type': 'freezer', 'powered': powered, 'temperature': .2 if powered else 1,
                            'customTemperature': 0, 'x': 101, 'y': 100, 'z': 0},
                'ambient': {'type': 'crate', 'powered': False, 'temperature': 1,
                            'customTemperature': 0, 'x': 102, 'y': 100, 'z': 0}},
            'foods': {
                'chilled': {'id': 101, 'type': 'Base.Cabbage', 'count': 1, 'endpoint': endpoint,
                            'age': world * (0.1 if powered else 1), 'lastAged': world,
                            'heat': chilled, 'freezingTime': 0, 'frozen': False, 'isFreezing': False, 'isThawing': False},
                'frozen': {'id': 102, 'type': 'Base.Cabbage', 'count': 1, 'endpoint': 'freezer',
                           'age': world * .1, 'lastAged': world, 'heat': .2 if powered else 1,
                           'freezingTime': 100 if powered and world > 100 else 0,
                           'frozen': powered and world > 100, 'isFreezing': powered and world < 100,
                           'isThawing': thaw},
                'control': {'id': 103, 'type': 'Base.Cabbage', 'count': 1, 'endpoint': 'ambient',
                            'age': world, 'lastAged': world, 'heat': 1, 'freezingTime': 0,
                            'frozen': False, 'isFreezing': False, 'isThawing': False}}}


def raw_receipts(kind='sp', role=None, case='appliances'):
    role = role or ('sp' if kind == 'sp' else 'client')
    env = {'suite': 'food-cooling', 'case': case, 'kind': kind, 'mode': 'native', 'role': role}
    ids = {'chilled': 101, 'frozen': 102, 'control': 103}
    original = {'minutesPerDay': 60, 'sandbox': {'Zombies': 6, 'DaysForRottenFoodRemoval': -1}}
    origin = {'x': 100, 'y': 100, 'z': 0}
    events = [('SETUP', {**env, 'ids': {'foods': ids, 'origin': origin}, 'limits': {'observationAgeWrites': 0,
              'forcedAgeUpdates': 0, 'nativeDurations': True, 'physicalInput': False},
              'original': original, 'originalItemCount': 4, 'snapshot': snapshot(99, False, 'fridge', 1, 0)})]
    phases = []
    ranges = ((100, 101), (101.1, 102.1), (102.2, 103.2), (103.3, 105.3))
    for index, (name, (start, end)) in enumerate(zip(cooling.PHASES, ranges), 1):
        if index == 1:
            before, after = snapshot(start, True, 'fridge', 1, 0), snapshot(end, True, 'fridge', .2, 0)
        elif index == 2:
            before, after = snapshot(start, True, 'root', .2, 100), snapshot(end, True, 'root', .8, 100)
        elif index == 3:
            before, after = snapshot(start, True, 'fridge', .8, 100), snapshot(end, True, 'fridge', .2, 100)
        else:
            before = snapshot(start, False, 'fridge', .2, 0, thaw=True)
            before['foods']['frozen'].update(freezingTime=100, frozen=True, isThawing=True)
            after = snapshot(end, False, 'fridge', 1, 0, thaw=True)
        phases.append((name, start, end, before, after))
    commands = {
        1: {**env, 'index': 0, 'type': 'ISActivateGenerator', 'nativeDuration': True,
            'duration': 15, 'started': True, 'completed': True,
            'before': snapshot(99, False, 'fridge', 1, 0), 'after': snapshot(100, True, 'fridge', 1, 0)},
        2: {**env, 'index': 2, 'type': 'ISInventoryTransferAction', 'nativeDuration': True,
            'duration': 15, 'started': True, 'completed': True, 'itemId': 101,
            'source': 'fridge', 'destination': 'root',
            'before': snapshot(101, True, 'fridge', .2, 100), 'after': snapshot(101.1, True, 'root', .2, 100)},
        3: {**env, 'index': 3, 'type': 'ISInventoryTransferAction', 'nativeDuration': True,
            'duration': 15, 'started': True, 'completed': True, 'itemId': 101,
            'source': 'root', 'destination': 'fridge',
            'before': snapshot(102.1, True, 'root', .8, 100), 'after': snapshot(102.2, True, 'fridge', .8, 100)},
        4: {**env, 'index': 4, 'type': 'ISActivateGenerator', 'nativeDuration': True,
            'duration': 15, 'started': True, 'completed': True,
            'before': snapshot(103.2, True, 'fridge', .2, 100),
            'after': snapshot(103.3, False, 'fridge', .2, 100)},
    }
    for index, (name, start, end, before, after) in enumerate(phases, 1):
        if role != 'server' and index in commands: events.append(('COMMAND', commands[index]))
        settled = {'index': index, 'sequence': index, 'purpose': 'before-begin', 'origin': origin,
                   'actor': {'squareX': 100, 'squareY': 100, 'squareZ': 0, 'moving': False,
                             'hasPath': False, 'timedActions': False}, 'stableMs': 1000, 'ready': True}
        authority = copy.deepcopy(settled)
        if role != 'server':
            settled.update(queue={'size': 0, 'idle': True}, authority=authority)
        events.append(('SETTLED', {**env, **settled}))
        events.append(('BEGIN', {**env, 'index': index, 'name': name, 'snapshot': copy.deepcopy(before)}))
        if role != 'server':
            events.append(('RENDERED', {**env, 'index': index, 'foods': {
                name: {'id': item_id, 'endpoint': 'root' if index == 2 and name == 'chilled' else
                       {'chilled': 'fridge', 'frozen': 'freezer', 'control': 'ambient'}[name],
                       'passes': 2, 'rowTop': 25, 'rowBottom': 45, 'header': 20, 'height': 150,
                       'pageVisible': True, 'paneVisible': True, 'primary': True,
                       'pinned': True, 'unclipped': True, 'selected': True, 'screenBounds': True, 'world': (start + end) / 2}
                for name, item_id in ids.items()}}))
        events.append(('PHASE', {**env, 'index': index, 'name': name, 'before': before, 'after': after,
                                 'elapsedWorldHours': end-start}))
    events.extend([
        ('CLEANUP', {**env, 'objectsRemoved': True, 'ownedIdsAbsent': True, 'originalItemsPreserved': True,
                     'queueIdle': True, 'originalItemCount': 4, 'remainingOriginalCount': 4,
                     'minutesPerDayAfter': 60, 'sandboxBefore': original['sandbox'], 'sandboxAfter': original['sandbox']}),
        ('COMPLETE', {**env, 'phases': 4, 'restored': True}),
    ])
    if case == 'collapsed-stacks':
        members = {'chilled': list(range(1000, 1198)) + [101],
                   'frozen': list(range(2000, 2199)) + [102], 'control': [103]}
        def add_capacity(value):
            if isinstance(value, dict):
                if 'containers' in value:
                    value['containers']['fridge'].update(capacity=40, contentsWeight=39.6 if value['foods']['chilled']['endpoint']=='root' else 39.8)
                    value['containers']['freezer'].update(capacity=40, contentsWeight=40)
                for child in value.values(): add_capacity(child)
            elif isinstance(value, list):
                for child in value: add_capacity(child)
        for event, row in events:
            add_capacity(row)
            if event == 'SETUP':
                row['ids']['stackMembers'] = members
                row['ids']['capacities'] = {'fridge': {'original': 40, 'configured': 40, 'fullWeight': 39.8},
                                            'freezer': {'original': 20, 'configured': 40, 'fullWeight': 40}}
                row['limits'].update(stackFoodProcessing='active-cookable', rootTransfer='singleton')
            if event == 'CLEANUP': row['ownedItemCount'] = 400
            if event == 'RENDERED':
                row['helper'] = {}
                for name, proof in row['foods'].items():
                    count = 1 if name == 'chilled' and row['index'] == 2 else cooling.STACK_COUNTS[name]
                    header = members[name][0] if count > 1 else ids[name]
                    proof['stack'] = {'vanilla': True, 'collapsed': True, 'actualCount': count,
                                      'actualIndex': count, 'headerId': header, 'tailId': ids[name]}
                    if count > 1:
                        row['helper'][name] = {'id': ids[name], 'tailId': ids[name], 'headerId': header,
                            'actualCount': count, 'actualIndex': count, 'endpoint': proof['endpoint'],
                            'admitted': True, 'delegated': True, 'protocol': 1,
                            'enhancedSourceSha256': cooling.ENHANCED_SOURCE_SHA256,
                            'intervalBefore': 1000, 'intervalAfter': 2000,
                            'beforeLastAged': proof['world'] - .01, 'afterLastAged': proof['world'], 'world': proof['world']}
        if role != 'server':
            events.insert(0, ('UI_BASELINE', {**env, 'cleanMode': True, 'samples': 3, 'sampleTimesMs': [0,120,240], 'stableSpanMs': 240,
                'pages': [{'x': 0, 'y': 0, 'width': 500, 'height': 500, 'paneX': 0, 'paneY': 30, 'paneWidth': 480, 'paneHeight': 400, 'inventoryBound': True} for _ in range(2)]}))
            position = next(i for i,(event,row) in enumerate(events) if event=='CLEANUP')
            events.insert(position, ('POSITION_RESTORED', {**env,
                'original': {'x': 100.25, 'y': 100.75, 'z': 0, 'squareX': 100, 'squareY': 100, 'squareZ': 0},
                'actual': {'x': 100.25, 'y': 100.75, 'z': 0, 'squareX': 100, 'squareY': 100, 'squareZ': 0,
                           'currentSquareX': 100, 'currentSquareY': 100, 'currentSquareZ': 0, 'moving': False, 'hasPath': False},
                'elapsedMs': 120, 'minimumWaitMs': 100, 'deadlineMs': 10000}))
            position += 1
            events.insert(position, ('UI_RESTORED', {**env, 'cleanMode': True, 'activePages': True, 'geometry': True, 'bindings': True, 'states': True, 'selection': True, 'anchors': True, 'equipped': True}))
    return events

def log(events, duplicate=False, nonfinite=False):
    lines = []
    for event, row in events:
        payload = json.dumps(row, separators=(',', ':'))
        if duplicate and event == 'SETUP': payload = payload[:-1] + ',"case":"appliances"}'
        if nonfinite and event == 'SETUP': payload = payload[:-1] + ',"bad":NaN}'
        lines.append(cooling.MARKER + event + ' ' + payload)
    return '\n'.join(lines) + '\n'


class FoodCoolingTests(unittest.TestCase):
    def test_registration_selection_and_staging(self):
        self.assertIs(adapters.get('food-cooling'), cooling)
        self.assertEqual(cooling.definitions()['food-cooling']['cases'][0]['kinds'], ['sp', 'mp'])
        for kind in ('sp', 'mp'):
            selected = selection(kind)
            cooling.validate(selected)
            with tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp); cache = root / 'client'; cache.mkdir()
                runtime = {'roles': {'client1': {'cache': str(cache)}}}
                if kind == 'mp': runtime['roles']['server'] = {'cache': str(root / 'server')}
                cooling.stage(ROOT, root, root/'game', root/'jdk', selected, {}, runtime)
                self.assertEqual(runtime['fixture']['server_ready'], '[STARTUP_TEST] SERVER_READY')
                self.assertTrue({ROOT/'tests/native_queue/food-cooling/client/ZZFoodCooling.lua', ROOT/'tests/native_queue/food-cooling/shared/QueueFoodCoolingFixture.lua'} <= set(cooling.sources(ROOT, selected)))
                for role in runtime['roles'].values():
                    lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
                    self.assertTrue((lua/'client/ZZStartup.lua').is_file())
                    self.assertTrue((lua/'shared/QueueHealthEvents.lua').is_file())

        for bad in (dict(selection(), clients=2), dict(selection(), languages=['RU']),
                    dict(selection(), cases=['other']), dict(selection(), options={'world_template':'x'}),
                    dict(selection('mp'), options={})):
            with self.subTest(bad=bad), self.assertRaises(ValueError): cooling.validate(bad)

    def test_collapsed_stack_case_staging_and_receipts(self):
        self.assertEqual([case['id'] for case in cooling.definitions()['food-cooling']['cases']],
                         ['appliances', 'collapsed-stacks'])
        for kind in ('sp', 'mp'):
            selected = selection(kind, 'collapsed-stacks')
            cooling.validate(selected)
            with tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                for role in (['sp'] if kind == 'sp' else ['client', 'server']):
                    name = 'server-launch.log' if role == 'server' else 'client1-launch.log'
                    (root / name).write_text(log(raw_receipts(kind, role, 'collapsed-stacks')))
                self.assertFalse(cooling.verify(root, selected, {})['issues'])
        with self.assertRaises(ValueError):
            cooling.validate(dict(selection(), cases=['appliances', 'collapsed-stacks']))

    def test_collapsed_stack_evidence_mutations_fail(self):
        def setup(rows): return next(row for event, row in rows if event == 'SETUP')
        def rendered(rows, index=1): return next(row for event, row in rows if event == 'RENDERED' and row['index'] == index)
        mutations = [
            lambda rows: setup(rows)['ids'].pop('stackMembers'),
            lambda rows: setup(rows)['ids']['capacities']['fridge'].update(configured=1000),
            lambda rows: setup(rows)['ids']['capacities']['freezer'].update(configured=20),
            lambda rows: next(row for event,row in rows if event=='PHASE')['after']['containers']['freezer'].update(contentsWeight=41),
            lambda rows: rows.remove(next(item for item in rows if item[0]=='UI_RESTORED')),
            lambda rows: rows.remove(next(item for item in rows if item[0]=='POSITION_RESTORED')),
            lambda rows: next(row for event,row in rows if event=='POSITION_RESTORED')['actual'].update(x=100),
            lambda rows: next(row for event,row in rows if event=='POSITION_RESTORED')['actual'].update(currentSquareX=101),
            lambda rows: next(row for event,row in rows if event=='POSITION_RESTORED').update(elapsedMs=99),
            lambda rows: next(row for event,row in rows if event=='UI_RESTORED').update(geometry=False),
            lambda rows: next(row for event,row in rows if event=='UI_RESTORED').update(selection=False),
            lambda rows: next(row for event,row in rows if event=='UI_RESTORED').update(anchors=False),
            lambda rows: next(row for event,row in rows if event=='UI_RESTORED').update(equipped=False),
            lambda rows: next(row for event,row in rows if event=='UI_BASELINE')['pages'][0].update(paneWidth=501),
            lambda rows: next(row for event,row in rows if event=='UI_BASELINE').update(stableSpanMs=0),
            lambda rows: setup(rows)['limits'].update(stackFoodProcessing='inert'),
            lambda rows: setup(rows)['limits'].update(rootTransfer='collapsed'),
            lambda rows: setup(rows)['ids']['stackMembers']['chilled'].pop(),
            lambda rows: setup(rows)['ids']['stackMembers']['frozen'].__setitem__(0, 101),
            lambda rows: next(row for event, row in rows if event == 'CLEANUP').update(ownedItemCount=3),
            lambda rows: rendered(rows)['foods']['chilled']['stack'].update(vanilla=False),
            lambda rows: rendered(rows)['foods']['frozen']['stack'].update(collapsed=False),
            lambda rows: rendered(rows)['foods']['chilled']['stack'].update(actualCount=198),
            lambda rows: rendered(rows)['foods']['frozen']['stack'].update(actualIndex=199),
            lambda rows: rendered(rows)['foods']['chilled']['stack'].update(headerId=101),
            lambda rows: rendered(rows)['foods']['chilled']['stack'].update(headerId=9999),
            lambda rows: rendered(rows, 2)['foods']['chilled']['stack'].update(actualCount=199),
            lambda rows: rendered(rows, 3)['foods']['chilled']['stack'].update(actualCount=198),
            lambda rows: rendered(rows)['helper'].pop('frozen'),
            lambda rows: rendered(rows)['helper']['chilled'].update(actualCount=198),
            lambda rows: rendered(rows)['helper']['chilled'].update(tailId=102),
            lambda rows: rendered(rows)['helper']['chilled'].update(admitted=False),
            lambda rows: rendered(rows)['helper']['chilled'].update(delegated=False),
            lambda rows: rendered(rows)['helper']['chilled'].update(protocol=2),
            lambda rows: rendered(rows)['helper']['chilled'].update(enhancedSourceSha256='unknown'),
            lambda rows: rendered(rows)['helper']['chilled'].update(intervalAfter=1000),
            lambda rows: rendered(rows)['helper']['chilled'].update(afterLastAged=0),
            lambda rows: rendered(rows)['helper']['chilled'].update(world=99),
        ]
        for mutate in mutations:
            rows = raw_receipts(case='collapsed-stacks'); mutate(rows)
            with self.subTest(mutation=mutate), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp); (root / 'client1-launch.log').write_text(log(rows))
                self.assertTrue(cooling.verify(root, selection(case='collapsed-stacks'), {})['issues'])

    def test_collapsed_ui_baseline_and_recreated_owner_restore(self):
        from lupa.lua51 import LuaRuntime
        source = (ROOT / 'tests/native_queue/food-cooling/client/ZZFoodCooling.lua').read_text()
        capture = source[source.index('local function copyUIState('):source.index('local function restoreObservers()')]
        restore = source[source.index('local function geometry('):source.index('local function restoreUI()')]
        for original_mode in ('true', 'false'):
            lua = LuaRuntime()
            lua.execute("""
                local now=0;local baselineSample;local ui;local position
                local events={};local F={collapsedStacks=true,emit=function(event,row)events[#events+1]={event=event,row=row}end}
                local cleanMode=""" + original_mode + """
                local containers={{},{}};local pages={};local restoring=false;local drift=false
                local relocated=false;local discoveryCalls=0
                local actor={x=112.5,y=100.5,z=0,squareX=112,squareY=100,currentX=112,currentY=100,moving=false}
                local function square(x,y)return{getX=function()return x end,getY=function()return y end,getZ=function()return 0 end}end
                function actor:getX()return self.x end;function actor:getY()return self.y end;function actor:getZ()return self.z end
                function actor:getSquare()return square(self.squareX,self.squareY)end
                function actor:getCurrentSquare()return square(self.currentX,self.currentY)end
                function actor:isPlayerMoving()return self.moving end;function actor:getPath2()return nil end
                function actor:teleportTo(x,y,z)self.x=math.floor(x);self.y=math.floor(y);self.z=z end
                function actor:setForceX(x)self.x=x end;function actor:setForceY(y)self.y=y end;function actor:setZ(z)self.z=z end
                function getPlayer()return actor end
                local methods={}
                for _,name in ipairs({'X','Y','Width','Height','MaxDrawHeight'})do
                    local key=string.lower(string.sub(name,1,1))..string.sub(name,2)
                    methods['get'..name]=function(self)return self[key]end
                    methods['set'..name]=function(self,value)self[key]=value end
                end
                methods.setX=function(self,value)self.x=math.min(value,200-self.width)end
                methods.setY=function(self,value)self.y=math.min(value,200-self.height)end
                methods.getIsVisible=function(self)return self.visible end
                methods.setVisible=function(self,value)self.visible=value end
                methods.setMode=function(self,value)self.mode=value end
                methods.saveSelection=function(self,result)
                    for item,kind in pairs(self.selectionState or {})do result[item]=kind end
                    return result
                end
                methods.restoreSelection=function(self,value)self.selectionState=value end
                methods.getYScroll=function(self)return self.scroll end
                methods.setYScroll=function(self,value)self.scroll=value end
                methods.setPinned=function(self)self.pin=true;self.isCollapsed=false end
                methods.collapse=function(self)self.pin=false;self.isCollapsed=true end
                methods.refreshBackpacks=function(self)
                    discoveryCalls=discoveryCalls+1
                    self.backpacks=(not relocated or actor.squareX==100 and actor.squareY==100)and{{inventory=containers[1]},{inventory=containers[2]}}or{}
                end
                methods.setNewContainer=function(self,value)self.inventory=value;self.inventoryPane.inventory=value end
                methods.cleanUIApplyScaleSettings=function(self)
                    if restoring then assert(pages[1].inventory==containers[1]and pages[2].inventory==containers[2],'peer binding missing before native layout')end
                    self.inventoryPane.x=5;self.inventoryPane.y=15
                    self.inventoryPane.width=drift and 70 or self.width-20;self.inventoryPane.height=self.height-40
                end
                local pageClasses={setmetatable({},{__index=methods}),setmetatable({},{__index=methods})}
                local paneClasses={setmetatable({},{__index=methods}),setmetatable({},{__index=methods})}
                local function newPages(mode,fixture)
                    local out={};local key=mode and 1 or 2
                    for i=1,2 do
                        local pane=setmetatable({x=5,y=15,width=fixture and 180 or 120,height=60,inventory=fixture and{}or containers[i],
                            visible=true,maxDrawHeight=-1,mode='details',scroll=0,collapsed={old=true},selected={},equippedCollapsed=not fixture}, {__index=paneClasses[key]})
                        -- Native instances use the class itself as their metatable.
                        setmetatable(pane,paneClasses[key]);paneClasses[key].__index=paneClasses[key]
                        local page=setmetatable({x=30,y=20,width=fixture and 190 or 100,height=fixture and 190 or 100,inventory=pane.inventory,
                            inventoryPane=pane,visible=true,maxDrawHeight=-1,pin=true,isCollapsed=false},pageClasses[key])
                        pageClasses[key].__index=pageClasses[key];page:refreshBackpacks();out[i]=page
                    end
                    return out
                end
                pages=newPages(cleanMode,false)
                function getPlayerInventory()return pages[1]end
                function getPlayerLoot()return pages[2]end
                function getTimestampMs()return now end
                function CleanUI_isCleanInventoryUIEnabled()return cleanMode end
                function CleanUI_setCleanInventoryUIEnabled(value)cleanMode=value;pages=newPages(value,true);restoring=true end
                local core={getOptionPauseOnFocusloss=function()return true end,setOptionPauseOnFocusloss=function()end}
                function getCore()return core end
            """ + capture + restore + """
                assert(not settledUIBaseline());now=119;assert(not settledUIBaseline())
                now=120;assert(not settledUIBaseline());now=240;assert(settledUIBaseline())
                assert(events[1].event=='UI_BASELINE'and events[1].row.stableSpanMs==240)
                ui=saveUI();assert(type(ui.cleanMode)=='boolean')
                local old1,old2=pages[1],pages[2];pages=newPages(not cleanMode,true)
                restoreCollapsedUI()
                assert(pages[1]~=old1 and pages[2]~=old2 and pages[1].inventory==containers[1]and pages[2].inventory==containers[2])
                assert(pages[1].x==30 and pages[1].width==100 and pages[1].inventoryPane.width==80)
                assert(pages[1].inventoryPane.equippedCollapsed==true and pages[2].inventoryPane.equippedCollapsed==true)
                assert(events[#events].event=='UI_RESTORED')
                -- Original loot is twelve tiles from the fixture and cannot be rediscovered there.
                relocated=true;position={x=100.25,y=100.75,z=0,squareX=100,squareY=100,squareZ=0}
                local discoveries=discoveryCalls
                assert(not pcall(restoreCollapsedUI)and discoveryCalls==discoveries)
                beginPositionReturn();assert(phase=='return-position'and actor.x==100.25 and actor.y==100.75)
                now=now+99;assert(not pollPositionReturn())
                now=now+1;actor.squareX=100;actor.squareY=100
                assert(not pollPositionReturn(),'current square still belongs to fixture')
                actor.currentX=100;actor.currentY=100;actor.moving=true;assert(not pollPositionReturn())
                actor.moving=false;local returned=assert(pollPositionReturn());assert(returned.actual.currentSquareX==100 and returned.elapsedMs==100)
                position=nil;restoreCollapsedUI()
                assert(discoveryCalls>discoveries and pages[2].inventory==containers[2])
                drift=true
                local ok=pcall(restoreCollapsedUI)
                assert(not ok and events[#events].event=='DIAGNOSTIC'and events[#events].row.quarantined==true)
            """)

    def test_cooling_ui_selection_and_anchors_follow_native_identities(self):
        from lupa.lua51 import LuaRuntime
        source = (ROOT / 'tests/native_queue/food-cooling/client/ZZFoodCooling.lua').read_text()
        helpers = source[source.index('local function copyUIState('):source.index('local function settledUIBaseline()')]
        lua = LuaRuntime()
        lua.execute(helpers + """
            local a,b,c,hidden={},{},{},{}
            local old={collapsed={food=true,tools=false},selected={},itemslist={
                {name='food',items={a,a,b}}, {name='tools',items={c,c}}, {name='equipped',items={hidden,hidden},equipped=true}},
                equippedCollapsed=true,firstSelect=1,joyselection=2}
            old.selected[1]=old.itemslist[1];old.selected[3]=c
            function old:saveSelection(result)result[a]='group';result[c]='item';return result end
            local saved=saveUISelection(old)
            assert(saved._cleanUISelectedGroups.food and saved[c]=='item'and not saved[a])
            local first=captureUIAnchor(old,old.firstSelect);local joy=captureUIAnchor(old,old.joyselection+1)
            local current={collapsed={food=true,tools=false},selected={},itemslist={
                {name='tools',items={c,c}}, {name='food',items={b,b,a}}, {name='equipped',items={hidden,hidden},equipped=true}},equippedCollapsed=true}
            function current:restoreSelection(input)
                assert(input[b]=='group'and input[c]=='item')
                self.selected[2]=c;self.selected[3]=self.itemslist[2]
            end
            function current:saveSelection(result)result[b]='group';result[c]='item';return result end
            restoreUISelection(current,saved)
            assert(restoreUIAnchor(current,first)==3 and restoreUIAnchor(current,joy)==2)
            verifyUIAnchor(current,3,first);verifyUIAnchor(current,2,joy)
            assert(not pcall(verifyUIAnchor,current,2,first),'wrong native anchor identity accepted')
            assert(saved._cleanUISelectedGroups.food and not saved[b],'native restore mutated saved aliases')
            -- Item/header loss must reject restoration instead of claiming UI_RESTORED.
            current.itemslist={};assert(not pcall(restoreUIAnchor,current,first))
            current.itemslist={{name='tools',items={c,c}},{name='food',items={b,b,a}}}
            function current:saveSelection(result)result[b]='group';return result end
            assert(not pcall(restoreUISelection,current,saved),'missing native selected item was accepted')
        """)

    def test_ui_quarantine_preserves_unrelated_focus_cleanup(self):
        from lupa.lua51 import LuaRuntime
        source = (ROOT / 'tests/native_queue/food-cooling/client/ZZFoodCooling.lua').read_text()
        restore = source[source.index('local function restoreUI()'):source.index('local function endpoint(container)')]
        lua = LuaRuntime()
        lua.execute("""
            local F={collapsedStacks=true};local ui={focusLoss=true};local focus=false
            local expected={reason='foreign observer replacement'}
            local function restoreObservers()error(expected,0)end
            function getCore()return{setOptionPauseOnFocusloss=function(_,value)focus=value end}end
        """ + restore + """
            local ok,problem=pcall(restoreUI)
            assert(not ok and problem==expected and focus==true)
        """)

    def test_public_helper_observer_delegates_passively_and_restores(self):
        from lupa.lua51 import LuaRuntime
        source = (ROOT / 'tests/native_queue/food-cooling/client/ZZFoodCooling.lua').read_text()
        observer = source[source.index('local function observeHelper()'):source.index('local function observePage(page)')]
        restore = source[source.index('local function restoreObservers()'):source.index('local function restoreUI()')]
        for forbidden in (':updateAge(', ':setAge(', ':setLastAged(', ':setHeat(', ':setFreezingTime('):
            self.assertNotIn(forbidden, observer)
        lua = LuaRuntime()
        lua.execute("""
            phase='observe'
            local clock=10
            item={getID=function()return 101 end,getLastAged=function()return clock end}
            local head={getID=function()return 100 end}
            group={items={head,head,item}}
            local F={collapsedStacks=true,find=function(_,id)if id==101 then return item,'fridge' end end}
            local state={};local ids={foods={chilled=101,frozen=102},stackMembers={chilled={100,101},frozen={102}}}
            local helperObserver;local observers={};local helperProof={}
            local function pack(...)return{n=select('#',...),...}end
            function getGameTime()return{getWorldAgeHours=function()return clock end}end
            local native=function(g,admitted,...)
                if Failure then error(Failure,0)end
                assert(g==group and admitted==true)
                clock=clock+1;g._cleanUILastFoodAgeUpdateMs=clock*1000
                return nil,17,false,...
            end
            CleanUI_ToolkitFoodAge={protocol=1,enhancedSourceSha256='""" + cooling.ENHANCED_SOURCE_SHA256 + """',updateCollapsedStack=native}
        """ + observer + restore + """
            for _,bad in ipairs({{}, {protocol=2}, {protocol=1,enhancedSourceSha256='unknown'}})do
                local saved=CleanUI_ToolkitFoodAge;CleanUI_ToolkitFoodAge=bad
                assert(not pcall(observeHelper));CleanUI_ToolkitFoodAge=saved
            end
            observeHelper()
            local wrapped=CleanUI_ToolkitFoodAge.updateCollapsedStack
            local result=pack(wrapped(group,true,'extra'))
            assert(result.n==4 and result[1]==nil and result[2]==17 and result[3]==false and result[4]=='extra')
            local proof=assert(helperProof.chilled)
            assert(proof.id==101 and proof.tailId==101 and proof.actualCount==2 and proof.actualIndex==2)
            assert(proof.beforeLastAged==10 and proof.afterLastAged==11 and proof.intervalBefore==0 and proof.intervalAfter==11000)
            Failure={reason='native exception'}
            local ok,problem=pcall(wrapped,group,true)
            assert(not ok and problem==Failure and helperProof.chilled==proof)
            Failure=nil
            local foreign=function()end
            CleanUI_ToolkitFoodAge.updateCollapsedStack=foreign
            assert(not pcall(restoreObservers)and CleanUI_ToolkitFoodAge.updateCollapsedStack==foreign)
            CleanUI_ToolkitFoodAge.updateCollapsedStack=wrapped
            local owned=CleanUI_ToolkitFoodAge;CleanUI_ToolkitFoodAge={}
            assert(not pcall(restoreObservers))
            CleanUI_ToolkitFoodAge=owned
            restoreObservers();assert(CleanUI_ToolkitFoodAge.updateCollapsedStack==native)
        """)

    def test_native_fixture_lua_syntax(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime()
        for source in cooling.sources(ROOT, selection()):
            if source.suffix == '.lua':
                with self.subTest(source=source.name):
                    lua.execute('assert(loadstring(...))', source.read_text())

    def test_authority_rejects_early_end_and_completes_once_after_thaw(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime()
        lua.execute('''
            package.preload.QueueTestSelection=function()return{kind='mp',mode='toolkit'}end
            package.preload.QueueHealthEvents=function()return{encode=function()return'{}'end}end
        ''')
        source = ROOT / 'tests/native_queue/food-cooling/shared/QueueFoodCoolingFixture.lua'
        lua.globals().F = lua.execute(source.read_text())
        lua.execute('''
            local function sample(world,fraction,frozen)
                return {world=world,foods={chilled={heat=1},frozen={freezingTime=fraction,frozen=frozen}}}
            end
            local before=sample(0,100,true)
            local current=sample(1.7,1.9281368255615234,true)
            F.snapshot=function()return current end
            F.originStatus=function()return{ready=true}end
            local emitted={}
            F.emit=function(event,row)emitted[#emitted+1]={event=event,row=row}end
            local state={phaseIndex=4,before=before}
            -- Client readiness cannot replace the independent server snapshot.
            assert(not F.phaseReadiness(state,4,7).ready)
            assert(not pcall(F.finish,state,4))
            assert(state.before==before and #emitted==0)
            -- A later native snapshot releases the same phase exactly once.
            current=sample(1.8,0,false)
            local ready=F.phaseReadiness(state,4,7)
            assert(ready.ready and ready.sequence==7)
            local receipt=F.finish(state,4)
            assert(receipt.after.foods.frozen.freezingTime==0 and not receipt.after.foods.frozen.frozen)
            assert(state.before==nil and #emitted==2)
            assert(emitted[1].event=='PHASE_READY'and emitted[2].event=='PHASE')
            assert(not pcall(F.finish,state,4)and #emitted==2)
        ''')

    def test_valid_sp_and_host_receipts(self):
        for kind in ('sp', 'mp'):
            with tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                for role in (['sp'] if kind == 'sp' else ['client', 'server']):
                    fname = 'server-launch.log' if role == 'server' else 'client1-launch.log'
                    (root/fname).write_text(log(raw_receipts(kind, role)))
                result = cooling.verify(root, selection(kind), {})
                self.assertFalse(result['issues'], result['issues'])

    def test_evidence_mutations_fail(self):
        def phase(rows, index):
            return next(row for event, row in rows if event == 'PHASE' and row['index'] == index)
        def command(rows, index):
            return next(row for event, row in rows if event == 'COMMAND' and row['index'] == index)
        def setup(rows):
            return next(row for event, row in rows if event == 'SETUP')
        def rendered(rows):
            return next(row for event, row in rows if event == 'RENDERED')
        def settled(rows):
            return next(row for event, row in rows if event == 'SETTLED')
        def reorder_phases(rows):
            indexes = [i for i, item in enumerate(rows) if item[0] == 'PHASE']
            rows[indexes[1]], rows[indexes[2]] = rows[indexes[2]], rows[indexes[1]]
        def late(rows, event):
            item = next(item for item in rows if item[0] == event)
            rows.remove(item); rows.append(item)
        mutations = [
            lambda r: late(r, 'SETTLED'),
            lambda r: late(r, 'BEGIN'),
            lambda r: late(r, 'RENDERED'),
            lambda r: r.remove(next(item for item in r if item[0] == 'BEGIN')),
            lambda r: rendered(r)['foods']['chilled'].update(screenBounds=False),
            lambda r: rendered(r)['foods']['chilled'].update(world=99),
            lambda r: rendered(r)['foods']['chilled'].update(world=102),
            lambda r: command(r, 2)['before'].update(world=1000),
            lambda r: command(r, 2)['before']['foods']['chilled'].update(heat=1),
            lambda r: settled(r)['actor'].update(squareX=101),
            lambda r: settled(r)['actor'].update(moving=True),
            lambda r: settled(r)['actor'].update(hasPath=True),
            lambda r: settled(r)['queue'].update(size=1),
            lambda r: settled(r)['authority'].update(ready=False),
            lambda r: settled(r).update(stableMs=999),
            lambda r: r.remove(next(item for item in r if item[0] == 'SETTLED')),
            lambda r: phase(r, 1)['after']['sandbox'].update(DaysForRottenFoodRemoval=0),
            lambda r: setup(r).update(controls={'DaysForRottenFoodRemoval': -1}),
            lambda r: rendered(r)['foods']['chilled'].update(passes=0),
            lambda r: rendered(r)['foods']['chilled'].update(rowTop=151, rowBottom=171),
            lambda r: rendered(r)['foods']['chilled'].update(pageVisible=False),
            lambda r: rendered(r)['foods']['chilled'].update(unclipped=False),
            lambda r: rendered(r)['foods']['chilled'].update(selected=False),
            lambda r: rendered(r)['foods']['chilled'].update(id=102),
            lambda r: rendered(r)['foods']['chilled'].update(endpoint='root'),
            lambda r: r.remove(next(item for item in r if item[0] == 'RENDERED')),
            lambda r: phase(r, 1)['after']['containers']['fridge'].update(temperature=1),
            lambda r: phase(r, 1)['after']['foods']['chilled'].update(heat=1),
            lambda r: phase(r, 1)['after']['foods']['frozen'].update(frozen=False, freezingTime=0),
            lambda r: phase(r, 4)['after']['foods']['frozen'].update(frozen=True, freezingTime=100),
            lambda r: phase(r, 2)['after']['foods']['chilled'].update(heat=phase(r, 2)['before']['foods']['chilled']['heat']),
            lambda r: command(r, 2).update(source='freezer'),
            lambda r: command(r, 2).update(destination='freezer'),
            lambda r: phase(r, 1)['after']['foods']['chilled'].update(id=102),
            lambda r: phase(r, 1)['after']['foods']['chilled'].update(endpoint='ambient'),
            lambda r: setup(r)['ids']['foods'].update(chilled=102),
            lambda r: setup(r)['ids']['foods'].update(chilled=102, frozen=101),
            lambda r: command(r, 2).update(itemId=102),
            lambda r: phase(r, 1).update(name='wrong'),
            lambda r: r.remove(next(item for item in r if item[0] == 'PHASE' and item[1]['index'] == 2)),
            lambda r: r.append(copy.deepcopy(next(item for item in r if item[0] == 'PHASE' and item[1]['index'] == 2))),
            reorder_phases,
            lambda r: setup(r)['limits'].update(forcedAgeUpdates=1),
            lambda r: setup(r)['limits'].update(nativeDurations=False),
            lambda r: next(row for event, row in r if event == 'CLEANUP').update(objectsRemoved=False),
            lambda r: command(r, 0).update(duration=0),
            lambda r: command(r, 0).update(started=False),
            lambda r: command(r, 0).update(completed=False),
            lambda r: command(r, 0).update(nativeDuration=False),
            lambda r: r.remove(next(item for item in r if item[0] == 'COMMAND' and item[1]['index'] == 0)),
            lambda r: phase(r, 1).update(role='server'),
            lambda r: phase(r, 2)['before'].update(world=100),
            lambda r: phase(r, 2)['before']['foods']['chilled'].update(age=0),
            lambda r: command(r, 2)['after']['foods']['chilled'].update(endpoint='fridge'),
            lambda r: command(r, 0)['after']['generator'].update(active=False),
            lambda r: command(r, 4)['after'].update(world=command(r, 4)['before']['world']),
            lambda r: command(r, 4)['after']['generator'].update(active=True),
            lambda r: r.insert(next(i for i,item in enumerate(r) if item[0]=='PHASE' and item[1]['index']==1), copy.deepcopy(next(item for item in r if item[0]=='COMMAND' and item[1]['index']==2))),
        ]
        for mutate in mutations:
            data = raw_receipts(); mutate(data)
            with self.subTest(mutation=mutate), tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp); (root/'client1-launch.log').write_text(log(data))
                self.assertTrue(cooling.verify(root, selection(), {})['issues'])

    def test_thermal_changes_during_native_settlement_remain_valid(self):
        # Each native transition can finish before walking/Host admission ends.
        # A late observation baseline must not erase its real pre-action proof.
        for kind in ('sp', 'mp'):
            with tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                for role in (['sp'] if kind == 'sp' else ['client', 'server']):
                    data = raw_receipts(kind, role)
                    for event, row in data:
                        if event == 'PHASE':
                            for name in ('chilled', 'frozen'):
                                for field in ('heat', 'freezingTime', 'frozen'):
                                    row['before']['foods'][name][field] = row['after']['foods'][name][field]
                            begin = next(value for event, value in data if event == 'BEGIN' and value['index'] == row['index'])
                            begin['snapshot'] = copy.deepcopy(row['before'])
                    filename = 'server-launch.log' if role == 'server' else 'client1-launch.log'
                    (root / filename).write_text(log(data))
                result = cooling.verify(root, selection(kind), {})
                self.assertFalse(result['issues'], result['issues'])

    def test_strict_json_and_role_identity_rejected(self):
        for kwargs in ({'duplicate':True}, {'nonfinite':True}):
            with tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp); (root/'client1-launch.log').write_text(log(raw_receipts(), **kwargs))
                self.assertTrue(cooling.verify(root, selection(), {})['issues'])
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            (root/'client1-launch.log').write_text(log(raw_receipts('mp','client')))
            (root/'server-launch.log').write_text(log(raw_receipts('mp','server')))
            self.assertFalse(cooling.verify(root, selection('mp'), {})['issues'])
            data=raw_receipts('mp','server'); data[0][1]['ids']['foods']['chilled']=999
            (root/'server-launch.log').write_text(log(data))
            self.assertTrue(cooling.verify(root, selection('mp'), {})['issues'])

    def test_client_thaw_does_not_qualify_unfinished_server_thaw(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'client1-launch.log').write_text(log(raw_receipts('mp', 'client')))
            server = raw_receipts('mp', 'server')
            phase = next(row for event, row in server if event == 'PHASE' and row['index'] == 4)
            phase['after']['foods']['frozen']['freezingTime'] = 1.93
            (root / 'server-launch.log').write_text(log(server))
            result = cooling.verify(root, selection('mp'), {})
            self.assertIn('Real generator power loss did not thaw freezer food', result['issues'])


if __name__ == '__main__':
    unittest.main()
