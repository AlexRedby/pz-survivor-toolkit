"""Offline contracts for the full integration session; no native coverage claim."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from tests.lua_fixture_events import OFFLINE_FIXTURE_EVENTS
from tests.test_queue_craft_wishlist_adapters import ROOT, CRAFT_WORLD_MODEL, adapter, selection, session_log


class WishlistFullSessionTests(unittest.TestCase):
    def value(self):
        return dict(selection('shared-wishlist', 'visual'), cases=['visual', 'full'],
                    mods=[*adapter.FULL_MODS, 'ZombieBuddy', 'PZToolkitJavaPatches'],
                    options={'mp_host': True, 'preload_toolkit_fonts': True})

    def test_full_group_admission_staging_and_joint_cleanup_receipts(self):
        value = self.value()
        adapter.validate(value)
        adapter.validate(dict(value, cases=['full', 'visual']))
        self.assertEqual(['visual', 'full'], adapter.ordered_cases(value))
        for cases in (['visual'], ['standalone'], ['reload'], ['visual', 'standalone'],
                      ['visual', 'full', 'standalone'], ['standalone', 'full']):
            with self.subTest(cases=cases), self.assertRaises(ValueError):
                adapter.validate(dict(value, cases=cases))
        for mod in adapter.FULL_MODS:
            with self.subTest(missing=mod), self.assertRaises(ValueError):
                adapter.validate(dict(value, mods=[name for name in value['mods'] if name != mod]))
        with self.assertRaises(ValueError):
            adapter.validate(dict(value, options={**value['options'], 'native_startup_fixes': True}))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            locations = root / 'integrations'
            (locations / 'BetterContainers').mkdir(parents=True)
            (locations / 'BetterContainers/Proximity.lua').write_text('-- selected implementation\n')
            runtime = {'roles': {role: {} for role in ('server', 'client1', 'client2')}}
            with self.assertRaisesRegex(ValueError, 'Proximity'):
                adapter.stage(ROOT, root / 'missing', None, None, value, {}, runtime)
            for role in runtime['roles']:
                (root / role / 'mods/ActionQueueTest/42/media/lua/client').mkdir(parents=True)
            adapter.stage(ROOT, root, None, None, value, {'EURY_CONTAINERS': locations}, runtime)
            self.assertEqual(['visual', 'full'], runtime['fixture']['session_cases'])
            lua = shutil.which('luajit') or shutil.which('lua5.1') or shutil.which('lua')
            for role in runtime['roles']:
                config = root / role / 'Lua/wishlist-fixture.txt'
                self.assertEqual([role, 'visual,full'], config.read_text().splitlines()[:2])
                self.assertEqual(';'.join(value['mods']), config.read_text().splitlines()[-1])
                self.assertEqual(0, config.stat().st_mode & 0o077)
                for side in ('client', 'server'):
                    source = root / role / 'mods/WishlistTest/42/media/lua' / side / (
                        'ZZWishlist.lua' if side == 'client' else 'ZZWishlist_Server.lua')
                    text = source.read_text()
                    self.assertIn("factories['visual']", text)
                    self.assertIn("factories['full']", text)
                    compiled = subprocess.run([lua, '-', str(source)], input='assert(loadfile(arg[1]))',
                                              text=True, capture_output=True)
                    self.assertEqual(0, compiled.returncode, compiled.stdout + compiled.stderr)
                (root / (role + '-launch.log')).write_text(session_log(value, role))
            verified = adapter.verify(root, value, {'suites': adapter.definitions()})
            self.assertEqual([], verified['issues'])
            for role in runtime['roles']:
                path = root / (role + '-launch.log')
                text = path.read_text()
                path.write_text(text.replace(
                    '[QUEUE_SESSION] JOINT_CLEAN case=full epoch=2 actor=' + role + ' ok=true', ''))
                self.assertTrue(adapter.verify(root, value, {'suites': adapter.definitions()})['issues'])
                path.write_text(text)

    def test_real_lua_full_group_restores_rebuilt_pages_and_native_cook_window(self):
        lua = shutil.which('luajit') or shutil.which('lua5.1') or shutil.which('lua')
        code = CRAFT_WORLD_MODEL + r'''
local m=model()
local classes={clean={},native={}};local paneClasses={clean={},native={}}
local current,mode,baseline,registry,ui,cookCloses,restored,bc,bcBaseline
local pendingRemovals,lingering,unownedWindow,pageRefreshes
local bcFields={'isForceSelected','forceSelectedType','_ForceSwitchIntent','_BrowseElapsedMs','_LastTransfer','_TransferRunning','_HasNearbyCorpses'}
package.preload['BetterContainers/Proximity']=function()return bc end
local function geometry(object,seed)
 for _,name in ipairs({'X','Y','Width','Height','MaxDrawHeight'})do
  object[name]=seed;seed=seed+1
  object['get'..name]=function(self)return self[name]end
  object['set'..name]=function(self,value)self[name]=value end
 end
end
local function page(kind,index,seed)
 local pane=setmetatable({inventory='container'..index,lastinventory='last'..index,mode='details',
  collapsed={stack=true},selected={token='item'},firstSelect=3,joyselection=2,equippedCollapsed=true,
  doController=false,mouseOverOption=7,scroll=-4,smoothScrollY=-3,smoothScrollTargetY=-2},paneClasses[kind])
 geometry(pane,seed)
 pane.getYScroll=function(self)return self.scroll end;pane.setYScroll=function(self,value)self.scroll=value end
 pane.refreshContainer=function(self)self.firstSelect=999;self.joyselection=998 end
 pane.saveSelection=function(self,target)for key,value in pairs(self.selected)do target[key]=value end end
 pane.restoreSelection=function(self,target)for key,value in pairs(target)do self.selected[key]=value end end
 local p=setmetatable({inventory='page-container'..index,inventoryPane=pane,title='title'..index,capacity=80,
  visible=false,pin=false,isCollapsed=true,collapseCounter=6,forceSelectedContainer='force'..index,
  forceSelectedContainerTime=55,tempForceSelectUnlock=true,backpackChoice=2,selectedContainerForSound='sound'},classes[kind]);geometry(p,seed+10)
 p.getIsVisible=function(self)return self.visible end;p.setVisible=function(self,value)self.visible=value end
 p.setPinned=function(self)self.pin=true end;p.collapse=function(self)self.pin=false end
 p.backpacks={{inventory=pane.inventory}};p.selectedButton=p.backpacks[1]
 p.refreshBackpacks=function(self)
  pageRefreshes=pageRefreshes+1
  self.backpacks={{inventory=self.inventoryPane.inventory}};self.selectedButton=self.backpacks[1]
  bc._ForceSwitchIntent[0]='fixture-auto';bc._BrowseElapsedMs[0]=999
  self.inventoryPane:refreshContainer()
 end
 return p
end
local function rebuild(value)
 mode=value;local kind=value and 'clean'or'native';current={page(kind,1,900),page(kind,2,950)}
end
getPlayerInventory=function()return current[1]end;getPlayerLoot=function()return current[2]end
getPlayer=function()return{hasTimedActions=function()return false end}end
getCore=function()return{isDoingTextEntry=function()return false end,TakeFullScreenshot=function()end}end
ISTimedActionQueue={getTimedActionQueue=function()return{queue={}}end}
CleanUI_isCleanInventoryUIEnabled=function()return mode end
CleanUI_setCleanInventoryUIEnabled=function(value)rebuild(value)end
ISEntityUI={GetWindowInstance=function(_,key)return registry[key]end}
-- Native RemoveElement queues removal until the next UIManager update.
local function removeElement(object)pendingRemovals[object]=true end
UIManager={getUI=function()return{contains=function(_,object)return ui[object]==true end}end,
 update=function()
  for object in pairs(pendingRemovals)do
   if not lingering[object]then ui[object]=nil;pendingRemovals[object]=nil end
  end
 end}
local option={value=true,getValue=function(self)return self.value end,setValue=function(self,value)self.value=value end}
PZAPI={ModOptions={getOptions=function()return{getOption=function()return option end}end}}
PZSurvivorWishlist={Client={state=function()return{queue={},lists={}}end},UI={windows={}},
 Crafting={openMenu=function()return{options={1,2},hideAndChildren=function()end}end}}
local function newCook()
 local panel={pzswButton={getX=function()return 1 end,getY=function()return 1 end,
  getBottom=function()return 10 end,prerender=function()end},getHeight=function()return 100 end}
 local window={javaObject={},switchToPanel=function()end,createHandCraftPanel=function()end,
  HandCraftPanel={setVisible=function()end},getChildren=function()return{panel}end,setVisible=function()end}
 window.onCloseClick=function(self)cookCloses=cookCloses+1;registry.CookingWindow=nil;removeElement(self.javaObject)end
 -- Project Cook's actual ISPanel-derived window exposes onCloseClick, not close.
 registry.CookingWindow=window;ui[window.javaObject]=true
end
PJCK_CookingUI={GetWindowInstance=function()return registry.CookingWindow end,OnOpenPanel=newCook}
ScriptManager={instance={getAllBuildableRecipes=function()return{get=function()return'recipe'end}end}}
local infoShown=0
ISEntityUI.OpenHandcraftWindow=function()
 local root={javaObject={},setVisible=function()end}
 root.close=function(self)removeElement(self.javaObject);registry.HandcraftWindow=nil end
 registry.HandcraftWindow=root;ui[root.javaObject]=true
end
ISEntityUI.OpenBuildWindow=function()
 local panel={javaObject={},pzswButton={getX=function()return 1 end,getY=function()return 1 end,
  getBottom=function()return 10 end,getWidth=function()return 70 end},getHeight=function()return 100 end,
  setVisible=function()end}
 panel.close=function(self)removeElement(self.javaObject)end
 local root={javaObject={},logic={getRecipe=function()end,setRecipe=function()end},getChildren=function()return{}end,setVisible=function()end}
 root.showBuildingInfoPanel=function(self)infoShown=infoShown+1;self.BuildingInfoPanel=panel;ui[panel.javaObject]=true end
 root.close=function(self)panel:close();removeElement(self.javaObject);registry.BuildWindow=nil end
 registry.BuildWindow=root;ui[root.javaObject]=true
end
local events=setmetatable({},{__index=function(owner,key)local event={Add=function()end};owner[key]=event;return event end})
local function loadFixture(initialMode,case,preexisting)
 registry={};ui={};cookCloses=0;restored=0;mode=initialMode
 pendingRemovals={};lingering={};unownedWindow={};ui[unownedWindow]=true;pageRefreshes=0
 registry.HandcraftWindow=preexisting
 bc={};bcBaseline={};package.loaded['BetterContainers/Proximity']=nil
 for index,key in ipairs(bcFields)do
  local value=index;if index==1 then value=false end
  bc[key]={[0]=value,[1]='other-actor'};bcBaseline[key]=value
 end
 local kind=mode and'clean'or'native';current={page(kind,1,10),page(kind,2,20)};baseline=current
 local lines={'client1','visual,full','host','12345','password','PZSurvivorToolkit;CleanUI'}
 getFileReader=function()local i=0;return{readLine=function()i=i+1;return lines[i]end,close=function()end}end
 QueueWishlistSession={case=case or'full',epoch=2,events=events,restoreClient=function()restored=restored+1 end,
  verifyOwned=function()return true end}
 dofile(arg[2]);return QueueWishlistSession
end
for _,initialMode in ipairs({false,true})do
 local ctx=loadFixture(initialMode)
 assert(mode==true,'full case must exercise CleanUI even if originally disabled')
 for _,stage in ipairs(WishlistTestFixture.stages)do
  if stage[1]=='Project Cook lazy recipe panel integrates wishlist'then stage[2]()end
 end
 assert(registry.CookingWindow and cookCloses==0,'real Cook stage must own its native window')
 local cook=registry.CookingWindow
 -- Model CleanUI replacing both active page objects during off/on stages.
 rebuild(false);rebuild(true)
 for _,p in ipairs(current)do p.inventory='fixture-page';p.inventoryPane.inventory='combined-loot';p.pin=true;p.visible=true end
 local world,neighbor=m.object(true),m.object(true);m.item(123,world);m.item(124,neighbor);ctx.ownWorld(world)
 assert(ctx.cleanup()==true and restored==1 and cookCloses==1 and not registry.CookingWindow)
 assert(mode==initialMode,'original optional UI mode must restore before peer verification')
 assert(ui[cook.javaObject]and pendingRemovals[cook.javaObject],
  'native close must retain its exact window until UIManager update')
 current[1].X=1234;bc._BrowseElapsedMs[0]=733
 local ready,reason=ctx.clean({})
 assert(ready==false and reason=='owned integration window remains in UIManager',
  'pending native removal must defer clean completion')
 assert(current[1].X==1234 and bc._BrowseElapsedMs[0]==733 and pageRefreshes==0,
  'inventory and proximity restoration must wait for owned window absence')
 UIManager.update()
 assert(not ui[cook.javaObject]and ui[unownedWindow],
  'UIManager update must remove only queued windows')
 ctx.verifyOwned=function()return false,'peer object remains'end
 assert(ctx.clean({})==false,'missing peer absence must block clean completion')
 assert(current[1].X==1234 and bc._BrowseElapsedMs[0]==733 and pageRefreshes==0,
  'peer absence must gate inventory and proximity restoration')
 ctx.verifyOwned=function()return true end
 assert(ctx.clean({})==true)
 for i,p in ipairs(current)do local saved=baseline[i]
  assert(p~=saved,'restoration must resolve the live replacement pages')
  assert(getmetatable(p)==getmetatable(saved)and getmetatable(p.inventoryPane)==getmetatable(saved.inventoryPane))
  for _,key in ipairs({'inventory','title','capacity','pin','visible','isCollapsed','collapseCounter','forceSelectedContainer','forceSelectedContainerTime','tempForceSelectUnlock','backpackChoice','selectedContainerForSound'})do
   assert(p[key]==saved[key],key)
  end
  for _,key in ipairs({'inventory','lastinventory','mode','firstSelect','joyselection','equippedCollapsed','doController','mouseOverOption','scroll','smoothScrollY','smoothScrollTargetY'})do
   assert(p.inventoryPane[key]==saved.inventoryPane[key],key)
  end
  assert(p.inventoryPane.collapsed.stack and p.inventoryPane.selected.token=='item')
  assert(p.selectedButton.inventory==saved.selectedButton.inventory and p.selectedButton~=saved.selectedButton,
   'selected button must bind the active page and original container')
  for _,name in ipairs({'X','Y','Width','Height','MaxDrawHeight'})do
   assert(p[name]==saved[name]and p.inventoryPane[name]==saved.inventoryPane[name],name)
  end
 end
 for _,key in ipairs(bcFields)do assert(bc[key][0]==bcBaseline[key]and bc[key][1]=='other-actor',key)end
 assert(m.square:getWorldObjects():contains(neighbor)and not m.square:getWorldObjects():contains(world),
  'cleanup must preserve unowned ground objects')
end
local ctx=loadFixture(true,'visual')
for _,stage in ipairs(WishlistTestFixture.stages)do
 if stage[1]=='native handcraft window opens'or stage[1]=='native building window opens'or stage[1]=='native building final rendered layout'then stage[2]()end
end
assert(infoShown==1,'full-group visual case must target the separate Neat Building info panel')
local handcraft,building=registry.HandcraftWindow,registry.BuildWindow
local infoPanel=building.BuildingInfoPanel
assert(ctx.cleanup(),'native visual closers must allow deferred UIManager removal')
assert(ui[handcraft.javaObject]and ui[building.javaObject]and ui[infoPanel.javaObject])
assert(ctx.clean({})==false and pageRefreshes==0,'separate Neat Building panel must gate restoration')
UIManager.update()
assert(ctx.clean({}),'separate Neat Building panel must be owned and removed')
assert(not ui[handcraft.javaObject]and not ui[building.javaObject]and not ui[infoPanel.javaObject]and ui[unownedWindow])
ctx=loadFixture(true)
newCook();local stuckCook=registry.CookingWindow
ctx.ownWindow(stuckCook,function(window)window:onCloseClick()end);lingering[stuckCook.javaObject]=true
local now,commands=0,{}
getTimestampMs=function()return now end
local create=dofile(arg[3])
local session=create({user='client1',cases={'full'},actors={'client1'},
 transport=function(_,command)commands[#commands+1]=command end},
 {full=function(context)
  context.readyToClean=ctx.readyToClean;context.cleanup=ctx.cleanup;context.clean=ctx.clean
 end},false)
local envelope={fixtureCase='full',fixtureEpoch=1,fixtureActor='client1'}
session.prepare();session.receive('Start',nil,envelope);session.current().finish(true,false);session.tick()
assert(session.phase=='finish'and commands[#commands]=='Finish',
 'a native closer may succeed while its UIManager removal remains pending')
session.receive('Clean',nil,envelope)
current[1].X=1234;bc._BrowseElapsedMs[0]=733
for update=1,3 do
 UIManager.update()
 local ready,reason=ctx.clean({})
 assert(ready==false and reason=='owned integration window remains in UIManager'and ui[stuckCook.javaObject],
  'a permanently lingering owned window must never become clean')
 assert(current[1].X==1234 and bc._BrowseElapsedMs[0]==733 and pageRefreshes==0,
  'repeated pending checks must not restore inventory or proximity state')
 session.tick();assert(session.phase=='clean','pending removal must remain in the common cleanup poll')
end
now=15001;session.tick()
assert(session.phase=='quarantined'and session.reason=='replicated cleanup deadline owned integration window remains in UIManager',
 'a permanently lingering owned window must hit the common cleanup deadline')
for _,command in ipairs(commands)do assert(command~='Cleaned','lingering window must never acknowledge clean completion')end
assert(commands[#commands]=='Quarantine'and current[1].X==1234 and bc._BrowseElapsedMs[0]==733 and pageRefreshes==0,
 'deadline quarantine must preserve unrestored state')
assert(not pcall(loadFixture,true,'full',{}),'preexisting integration window must stay outside fixture ownership')
local ctx=loadFixture(false);CleanUI_setCleanInventoryUIEnabled=function()end
assert(not pcall(ctx.cleanup),'failed optional-mode restoration must quarantine')
ctx=loadFixture(true);ctx.cleanup();setmetatable(current[1],{})
assert(not pcall(ctx.clean,{}),'changed UI owner/class must quarantine')
ctx=loadFixture(true);ctx.cleanup();current[1].X=1234;bc._ForceSwitchIntent={}
assert(not pcall(ctx.clean,{})and current[1].X==1234,'changed BC state owner must fail before UI restoration')
ctx=loadFixture(true);bc._BrowseElapsedMs[0]={}
assert(not pcall(ctx.cleanup),'unexpected mutable BC selection state must quarantine')
print('PASS full integration native Cook close, mode/class/page restoration and peer-absence gates')
'''
        result = subprocess.run([lua, '-', str(ROOT / 'tests/native_queue/support/QueueCraftSession.lua'),
                                 str(ROOT / 'tests/native_queue/contributions/shared-wishlist/client/ZZWishlist.lua'),
                                 str(ROOT / 'tests/native_queue/support/QueueFixtureSession.lua')],
                                input=OFFLINE_FIXTURE_EVENTS + code, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
