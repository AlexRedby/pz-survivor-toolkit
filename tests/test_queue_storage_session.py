"""Storage sessions retain per-case evidence and restore a native UI baseline."""
from pathlib import Path
import os
import sys
import tempfile
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import auxiliary as adapter

INTAKE = ROOT / 'tests/native_queue/contributions/storage-profile'


class StorageSessionTests(unittest.TestCase):
    def selection(self):
        return dict(suite='storage-profile', cases=['inventory-work', 'inventory-freshness'],
                    kind='sp', clients=1, languages=['EN'], mode='toolkit',
                    mods=list(adapter.INVENTORY_MODS), options={})

    def runtime(self, fault=None, pane_methods=None, pane_setup=None):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().fault = fault
        lua.execute(r'''
logs={};print=function(message)logs[#logs+1]=message end
table.wipe=function(value)for key in pairs(value)do value[key]=nil end end
now=0;getTimestampMs=function()return now end
isClient=function()return false end;isServer=function()return false end
queue={queue={}};ISTimedActionQueue={getTimedActionQueue=function()return queue end}
package.preload['TimedActions/ISTimedActionQueue']=function()return ISTimedActionQueue end
local items={};items.size=function(self)return #self end;items.get=function(self,index)return self[index+1]end
inventory={getItems=function()return items end,getCapacityWeight=function()return #items end}
unrelated={getID=function()return 1 end,getContainer=function()return inventory end};items[1]=unrelated
player={god=false,ghost=false,getInventory=function()return inventory end,
 getX=function()return 1 end,getY=function()return 2 end,getZ=function()return 0 end,
 getPrimaryHandItem=function()return unrelated end,getSecondaryHandItem=function()end,
 isGodMod=function(self)return self.god end,isGhostMode=function(self)return self.ghost end,
 setGodMod=function(self,v)self.god=v end,setGhostMode=function(self,v)self.ghost=v end,
 getCurrentSquare=function()return {}end,hasTimedActions=function()return #queue.queue>0 end}
getPlayer=function()return player end
local function element()
 local e={x=17,y=29,width=500,height=260,visible=false,scroll=-7,mode='icons',pin=false,maxDrawHeight=77}
 for _,field in ipairs({'x','y','width','height','maxDrawHeight'})do
  local name=field:sub(1,1):upper()..field:sub(2)
  e['get'..name]=function(self)return self[field]end;e['set'..name]=function(self,v)self[field]=v end
 end
 e.getIsVisible=function(self)return self.visible end;e.setVisible=function(self,v)self.visible=v end
 e.setMode=function(self,v)self.mode=v end;e.getYScroll=function(self)return self.scroll end
 e.setYScroll=function(self,v)self.scroll=v end
 return e
end
function makePage()
 local page,pane=element(),element();page.inventoryPane=pane
 pane.inventory=inventory;pane.lastinventory=inventory;pane.collapsed={Apple=false}
 pane.selected={[unrelated]='item'};pane.firstSelect=2;pane.joyselection=1;pane.mouseOverOption=3
 pane.saveSelection=function(self,target)for k,v in pairs(self.selected)do target[k]=v end;return target end
 pane.restoreSelection=function(self,value)for k,v in pairs(value)do self.selected[k]=v end end
 pane.refreshContainer=function(self)self.selected={}end
 page.backpacks={{inventory=inventory}}
 page.setNewContainer=function(self,value)
  self.inventoryPane.inventory=value;self.inventory=value;self.inventoryPane.lastinventory=value
  self.inventoryPane:refreshContainer()
 end
 page.refreshBackpacks=function()end;page.setPinned=function(self)self.pin=true end
 page.collapse=function(self)self.pin=false end
 return page
end
mode=false;invPage=makePage();lootPage=makePage()
getPlayerInventory=function()return invPage end;getPlayerLoot=function()return lootPage end
CleanUI_isCleanInventoryUIEnabled=function()return mode end
CleanUI_setCleanInventoryUIEnabled=function(value)
 if mode~=value then mode=value;invPage=makePage();lootPage=makePage()end
end
contexts={};oldTickCalls=0;phaseTicks=0
local function factory()
 local context=require('StorageProfileSession').context();contexts[#contexts+1]=context
 context.events.OnGameStart.Add(function()
  assert(not player.god and not player.ghost and not invPage.visible and invPage.width==500,'previous phase state leaked')
  player.god=true;player.ghost=true;CleanUI_setCleanInventoryUIEnabled(true)
  invPage.width=1000;invPage.visible=true;invPage.pin=true;invPage.inventoryPane.mode='details'
  invPage.inventoryPane.collapsed.Apple=true;invPage.inventoryPane.selected={}
 end)
 local ran=false
 context.events.OnTick.Add(function()
  phaseTicks=phaseTicks+1
  if ran then oldTickCalls=oldTickCalls+1;return end
  ran=true
  print('[STORAGE_PROFILE] COMPLETE')
  if fault=='inventory' then items[2]={getID=function()return 2 end}end
  if fault=='queue' then queue.queue={true}end
  context.finish(true)
 end)
end
package.preload['ZZInventoryWorkProfile']=function()return factory end
package.preload['ZZInventoryFreshness']=function()return factory end
''')
        if pane_methods:
            lua.execute('''
ISInventoryPane={};ISMouseDrag={}
instanceof=function(value,kind)return kind=='InventoryItem'and value==unrelated end
''')
            lua.execute(pane_methods)
            lua.execute('''
local original=makePage
makePage=function()
 local page=original();local pane=page.inventoryPane
 pane.saveSelection=ISInventoryPane.saveSelection;pane.restoreSelection=ISInventoryPane.restoreSelection
 pane.refreshContainer=function(self)
  self.itemslist={{name='Apple',items={unrelated,unrelated}}};self.selected={}
 end
 pane:refreshContainer();pane.firstSelect=1;pane.joyselection=0
 return page
end
invPage=makePage();lootPage=makePage()
''')
        if pane_setup:
            lua.execute("package.preload['PZSurvivorToolkit/InventoryRows']=function()\n" + (ROOT / 'PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/InventoryRows.lua').read_text() + '\nend')
            lua.execute(pane_setup)
        for name, path in [('QueueFixtureSession', ROOT / 'tests/native_queue/support/QueueFixtureSession.lua'),
                           ('StorageProfileSession', INTAKE / 'StorageProfileSession.lua')]:
            lua.execute("package.preload[%r]=function()\n%s\nend" % (name, path.read_text()))
        lua.execute("tick=require('StorageProfileSession').run({cases={'inventory-work','inventory-freshness'}})")
        return lua

    def ticks(self, lua, count=200):
        lua.execute('for i=1,%d do now=now+100;tick()end' % count)
        return '\n'.join(lua.globals().logs.values())

    def test_real_local_transport_restores_ui_player_and_removes_phase_observers(self):
        lua = self.runtime()
        text = self.ticks(lua)
        self.assertNotIn('QUARANTINE', text, text)
        self.assertTrue(adapter.complete(self.selection(), 'client1', text), text)
        self.assertEqual(text.count('[STORAGE_SESSION] RESTORED '), 2)
        lua.execute('''
assert(#contexts==2 and phaseTicks==2 and oldTickCalls==0)
for _,context in ipairs(contexts)do for _,handlers in pairs(context.handlers)do assert(#handlers==0)end end
assert(not player.god and not player.ghost and not mode)
assert(invPage.width==500 and invPage.x==17 and invPage.height==260 and not invPage.visible and not invPage.pin)
assert(invPage.maxDrawHeight==77 and invPage.inventoryPane.mode=='icons'and invPage.inventoryPane.scroll==-7)
assert(invPage.inventoryPane.selected[unrelated]and invPage.inventoryPane.collapsed.Apple==false)
assert(inventory:getItems():size()==1 and inventory:getItems():get(0)==unrelated)
''')

    def test_unknown_inventory_and_pending_queue_quarantine_without_next_phase(self):
        for fault in ('inventory', 'queue'):
            lua = self.runtime(fault)
            text = self.ticks(lua)
            self.assertIn('[QUEUE_SESSION] QUARANTINE ', text, text)
            self.assertNotIn('[STORAGE_SESSION] BEGIN case=inventory-freshness', text)
            self.assertFalse(adapter.complete(self.selection(), 'client1', text))
            lua.execute('assert(#contexts==1 and inventory:getItems():get(0)==unrelated)')

    def test_cleanui_empty_selection_metadata_is_logically_restored(self):
        lua = self.runtime(pane_methods='''
function ISInventoryPane:saveSelection(selected)
 selected._cleanUISelectedGroups={};return selected
end
function ISInventoryPane:restoreSelection(selected)end
''')
        text = self.ticks(lua)
        self.assertNotIn('QUARANTINE', text, text)
        self.assertTrue(adapter.complete(self.selection(), 'client1', text), text)

    @unittest.skipUnless(os.environ.get('PZ_CLEANUI_SOURCE'), 'PZ_CLEANUI_SOURCE selects actual prepared CleanUI methods')
    def test_actual_cleanui_empty_selection_metadata_survives_two_phases(self):
        lua = self.runtime(pane_methods=self.actual_cleanui_methods())
        text = self.ticks(lua)
        self.assertNotIn('QUARANTINE', text, text)
        self.assertTrue(adapter.complete(self.selection(), 'client1', text), text)

    def actual_cleanui_methods(self, vanilla=False):
        path = Path(os.environ['PZ_CLEANUI_SOURCE']) / '42.19/media/lua/client/ISUI/ISInventoryPane.lua'
        if vanilla:
            path = path.parent.parent / 'CleanUI/Vanilla/CleanUI_Vanilla_ISInventoryPane.lua'
        source = path.read_text()
        if vanilla:
            return 'function ISInventoryPane:saveSelection(selected)' + source.split('function CleanUI_Vanilla_ISInventoryPane:saveSelection(selected)', 1)[1].split('local function CleanUI_Vanilla_captureSelectionAnchor', 1)[0].replace('function CleanUI_Vanilla_ISInventoryPane:', 'function ISInventoryPane:')
        helpers = source.split('local function CleanUI_getStackDisplayItem', 1)[1].split('local function CleanUI_getStackFirstActualItem', 1)[0]
        methods = source.split('function ISInventoryPane:saveSelection(selected)', 1)[1].split('local function CleanUI_captureSelectionAnchor', 1)[0]
        return 'local function CleanUI_getStackDisplayItem' + helpers + 'function ISInventoryPane:saveSelection(selected)' + methods

    @unittest.skipUnless(os.environ.get('PZ_CLEANUI_SOURCE'), 'PZ_CLEANUI_SOURCE selects actual prepared CleanUI methods')
    def test_actual_cleanui_group_aliases_separators_capped_children_and_anchors(self):
        setup = r'''
local items=inventory:getItems()
for id=2,10 do
 local identity=id;items[#items+1]={getID=function()return identity end,getContainer=function()return inventory end}
end
instanceof=function(value,kind)return kind=='InventoryItem'and type(value)=='table'and value.getID~=nil end
local Rows=require 'PZSurvivorToolkit/InventoryRows'
local native=ISInventoryPane.restoreSelection
ISInventoryPane.restoreSelection=function(self,saved)
 native(self,saved);Rows.restoreSelection(self,saved)
 if fault=='selection-extra'then self.selected[2]=items[1]end
 if fault=='selection-missing'then self.selected[3]=nil end
end
local original=makePage
makePage=function()
 local page=original();local pane=page.inventoryPane
 pane.mode='details';pane.equippedCollapsed=true;pane.MAX_ITEMS_IN_STACK_TO_RENDER=2
 pane.collapsed={wear=true,virtual=false,['.']=true,tail=true}
 pane.refreshContainer=function(self)
  local virtual={name='virtual',items={},cleanUIDisplayItem={},cleanUIFirstActualIndex=1,cleanUILargeStackOptimized=true}
  for index=1,8 do virtual.items[index]=items[index]end
  self.itemslist={{name='wear',items={items[9],items[9]},equipped=true},virtual,
   {name='.',type='separator',items={}},{name='tail',items={items[10],items[10]}}}
  self.items={virtual,items[1],items[2],self.itemslist[3],self.itemslist[4]}
  self.selected={}
 end
 pane:refreshContainer()
 pane.selected={[1]=pane.itemslist[2],[3]=items[2],[4]=pane.itemslist[3]}
 pane.firstSelect=5;pane.joyselection=2
 return page
end
invPage=makePage();lootPage=makePage()
'''
        lua = self.runtime(pane_methods=self.actual_cleanui_methods(), pane_setup=setup)
        text = self.ticks(lua)
        self.assertNotIn('QUARANTINE', text, text)
        self.assertTrue(adapter.complete(self.selection(), 'client1', text), text)
        lua.execute('''
local pane=invPage.inventoryPane
assert(pane.equippedCollapsed and pane.firstSelect==5 and pane.joyselection==2)
assert(pane.selected[1].name=='virtual'and pane.selected[3]==inventory:getItems():get(1))
assert(pane.selected[4].name=='.'and pane.selected[2]==nil and pane.selected[5]==nil)
''')
        for fault in ('selection-extra', 'selection-missing'):
            lua = self.runtime(fault=fault, pane_methods=self.actual_cleanui_methods(), pane_setup=setup)
            text = self.ticks(lua)
            self.assertIn('QUARANTINE', text, text)
            self.assertFalse(adapter.complete(self.selection(), 'client1', text))

    @unittest.skipUnless(os.environ.get('PZ_CLEANUI_SOURCE'), 'PZ_CLEANUI_SOURCE selects actual prepared CleanUI methods')
    def test_actual_vanilla_class_metadata_survives_two_phases(self):
        lua = self.runtime(pane_methods=self.actual_cleanui_methods(vanilla=True))
        text = self.ticks(lua)
        self.assertNotIn('QUARANTINE', text, text)
        self.assertTrue(adapter.complete(self.selection(), 'client1', text), text)

    @unittest.skipUnless(os.environ.get('PZ_CLEANUI_SOURCE'), 'PZ_CLEANUI_SOURCE selects actual prepared CleanUI page binding')
    def test_second_phase_geometry_refresh_rebinds_exact_root_or_nonroot_container(self):
        source = (Path(os.environ['PZ_CLEANUI_SOURCE']) / '42.19/media/lua/client/ISUI/ISInventoryPage.lua').read_text()
        binding = source.split('function ISInventoryPage:setNewContainer(inventory)', 1)[1].split('function ISInventoryPage:selectButtonForContainer', 1)[0]
        setup = 'NativePage={}\nfunction NativePage:setNewContainer(inventory)' + binding + r'''
inventory.getEffectiveCapacity=function()return 100 end
getSpecificPlayer=getPlayer
bag={getEffectiveCapacity=function()return 75 end}
local original=makePage
binds,geometryInvalidations=0,0
makePage=function()
 local page=original();local pane=page.inventoryPane
 local target=nonroot and bag or inventory
 pane.inventory=target;pane.lastinventory=inventory;pane.selected={}
 page.inventory=target
 function page:refreshBackpacks()
  -- The actual native refresh owns this cache, then rebuilds buttons before
  -- setNewContainer binds the selected target and its title/capacity.
  self.inventoryPane.lastinventory=self.inventoryPane.inventory
  self.backpacks={{inventory=inventory,name='root',capacity=100}}
  if fault~='missing-target'then self.backpacks[#self.backpacks+1]={inventory=bag,name='bag',capacity=75}end
  self.inventory=self.inventoryPane.inventory
  self.inventoryPane:refreshContainer()
 end
 page.playContainerOpenCloseSounds=function()end
 page.setNewContainer=function(self,target)
  binds=binds+1;NativePage.setNewContainer(self,target)
  if fault=='lazy-cache'then self.inventoryPane.lastinventory=nil end
  if fault=='wrong-active'then self.inventoryPane.inventory={}end
 end
 local height=page.setHeight
 page.setHeight=function(self,value)
  height(self,value)
  if #contexts>=2 then self.inventoryPane.lastinventory=nil;geometryInvalidations=geometryInvalidations+1 end
 end
 page:refreshBackpacks()
 return page
end
invPage=makePage();lootPage=makePage()
'''
        for nonroot in (False, True):
            with self.subTest(nonroot=nonroot):
                lua = self.runtime(pane_setup=('nonroot=' + str(nonroot).lower() + '\n' + setup))
                text = self.ticks(lua)
                self.assertNotIn('QUARANTINE', text, text)
                self.assertTrue(adapter.complete(self.selection(), 'client1', text), text)
                lua.execute('''
local target=nonroot and bag or inventory
assert(binds==4 and geometryInvalidations==2)
assert(invPage.inventory==target and invPage.inventoryPane.inventory==target and invPage.inventoryPane.lastinventory==target)
assert(invPage.capacity==(nonroot and 75 or 100)and invPage.title==(nonroot and 'bag'or'root'))
''')
        lua = self.runtime(fault='lazy-cache', pane_setup='nonroot=true\n' + setup)
        text = self.ticks(lua)
        self.assertNotIn('QUARANTINE', text, text)
        lua.execute('assert(invPage.inventory==bag and invPage.inventoryPane.inventory==bag and invPage.inventoryPane.lastinventory==nil)')
        for fault in ('wrong-active', 'missing-target'):
            lua = self.runtime(fault=fault, pane_setup='nonroot=true\n' + setup)
            text = self.ticks(lua)
            self.assertIn('QUARANTINE', text, text)
            self.assertFalse(adapter.complete(self.selection(), 'client1', text))
            self.assertIn(' target=', text)
            self.assertIn(' pane=', text)
            self.assertIn(' page=', text)
            self.assertIn(' cache=', text)
            self.assertTrue(all(len(line) < 900 for line in text.splitlines() if 'QUARANTINE' in line))

    def test_registration_staging_and_restrictions(self):
        selection = self.selection()
        self.assertTrue(adapter.definitions()['storage-profile']['shared_session'])
        adapter.validate(selection)
        for cases in (list(reversed(selection['cases'])), ['walk', 'inventory-freshness'],
                      ['inventory-food-age', 'inventory-freshness'], ['inventory-work', 'walk']):
            with self.subTest(cases=cases), self.assertRaises(ValueError):
                adapter.validate(dict(selection, cases=cases))
        for options in ({'world_template': '/owned/template'}, {'seed_run': '/owned/seed'}, {'mp_host': True}):
            with self.assertRaises(ValueError): adapter.validate(dict(selection, options=options))
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); cache = root / 'client1';cache.mkdir()
            runtime = {'roles': {'client1': {'cache': str(cache)}}}
            adapter.stage(ROOT, root, root, root, selection, {'PZSurvivorToolkit': ROOT / 'PZSurvivorToolkit'}, runtime)
            lua = cache / 'mods/StorageProfileNative/42/media/lua'
            self.assertEqual({p.name for p in (lua / 'client').iterdir()}, {'ZZStorageSession.lua'})
            self.assertIn('[QUEUE_SESSION] QUARANTINE ', runtime['fixture']['failure_markers'])
            for name in ('ZZInventoryWorkProfile.lua', 'ZZInventoryFreshness.lua'):
                self.assertEqual((lua / 'shared' / name).read_bytes(), b'return function()\n' + (INTAKE / name).read_bytes() + b'\nend\n')
                # Eager native shared-script loading only exports the factory.
                check = LuaRuntime()
                factory = check.execute((lua / 'shared' / name).read_text())
                self.assertTrue(callable(factory))
                check.execute('''
context={case=... ,events={}}
for _,name in ipairs({'OnTick','OnGameStart','OnMainMenuEnter','OnPreUIDraw'})do
 context.events[name]={Add=function(fn)context.events[name].callback=fn end}
end
require=function(name)
 if name=='QueueTestSelection'then return {cases={'inventory-work','inventory-freshness'}}end
 if name=='StorageProfileSession'then return {context=function()return context end}end
 return {}
end
''', 'inventory-work' if 'Work' in name else 'inventory-freshness')
                factory()
                check.execute("assert(context.events.OnTick.callback and context.events.OnGameStart.callback)")
            self.assertIn(ROOT / 'tests/native_queue/support/QueueFixtureSession.lua', adapter.sources(ROOT, selection))

    def test_verifier_keeps_existing_assertions_and_case_epoch_boundaries(self):
        work = adapter._load(ROOT / 'tests/test_queue_inventory_work_profile.py')
        fresh = adapter._load(ROOT / 'tests/test_queue_inventory_freshness.py')
        text = self.ticks(self.runtime())
        # The lifecycle double performs no renderer calls. Substitute independently
        # tested full case receipts, retaining its real shared-session transport.
        first = text.index('[STORAGE_PROFILE] COMPLETE')
        text = text[:first] + work.log(work.receipts()).strip() + text[first+len('[STORAGE_PROFILE] COMPLETE'):]
        last = text.index('[STORAGE_PROFILE] COMPLETE', first+len(work.log(work.receipts()).strip()))
        text = text[:last] + fresh.log(fresh.receipts()).strip() + text[last+len('[STORAGE_PROFILE] COMPLETE'):]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary);(root / 'client1').mkdir();log = root / 'client1/console.txt'
            log.write_text(text)
            result = adapter.verify(root, self.selection(), {})
            self.assertFalse(result['issues'], result)
            self.assertEqual([row['status'] for row in result['outcomes']], ['captured', 'passed'])
            begin = '[QUEUE_SESSION] BEGIN case=inventory-freshness epoch=2 actor=server'
            joint = '[QUEUE_SESSION] JOINT_CLEAN case=inventory-work epoch=1 actor=client1 ok=true'
            self.assertIn(begin + '\n' + joint, text)
            interleaved = text.replace(begin + '\n' + joint, joint + '\n' + begin)
            for bad in (text.replace('weight=true', 'weight=false', 1), text + '\n[QUEUE_SESSION] QUARANTINE test',
                        text.replace('epoch=2 actor=client1', 'epoch=1 actor=client1', 1),
                        text.replace('"ownedRemoved": 51', '"ownedRemoved": 50'),
                        text.replace('[QUEUE_SESSION] JOINT_CLEAN case=inventory-work epoch=1 actor=client1 ok=true', ''),
                        text + '\n[QUEUE_SESSION] MALFORMED',
                        text + '\n[STORAGE_SESSION] UNKNOWN',
                        interleaved,
                        text + '\n[STORAGE_SESSION] RESTORED unknown'):
                log.write_text(bad)
                self.assertTrue(adapter.verify(root, self.selection(), {})['issues'])


if __name__ == '__main__':
    unittest.main()
