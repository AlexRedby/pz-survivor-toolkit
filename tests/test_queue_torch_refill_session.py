"""Execute torch native-callback fixture phases with Lua world/transport doubles."""
from pathlib import Path
import os
import sys
import tempfile
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / 'tests/native_queue/torch-refill'
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import torch_refill as adapter

HARNESS = r'''
logs={};print=function(text)logs[#logs+1]=text end
now=0;getTimestampMs=function()return now end
local modules={};package.preload['QueueTestSelection']=function()return selection end
package.preload['QueueHealthEvents']=function()return {encode=function(value)
 local function enc(v)
  if type(v)=='table'then
   local result={}
   if #v>0 then for _,item in ipairs(v)do result[#result+1]=enc(item)end;return '['..table.concat(result,',')..']'end
   for key,item in pairs(v)do result[#result+1]='"'..key..'":'..enc(item)end;return '{'..table.concat(result,',')..'}'
  elseif type(v)=='string'then return '"'..v:gsub('"','\\"')..'"'else return tostring(v)end
 end
 return enc(value)
end}end
package.preload['PZSurvivorToolkit/ItemRetention']=function()return {
 apply=function(item,value)item.retained=value end,isRetained=function(item)return item.retained==true end}end
package.preload['PZSurvivorToolkit/TorchRefillReturn']=function()return {install=function()return true end}end
local function list(values)
 values=values or {};values.size=function(self)return #self end;values.get=function(self,i)return self[i+1]end
 values.contains=function(self,item)for _,v in ipairs(self)do if item==v then return true end end;return false end
 return values
end
nextID=100
function container()
 local c={items=list()}
 function c:getItems()return self.items end
 function c:AddItem(kind)
  nextID=nextID+1
  local item={id=nextID,kind=kind,uses=10,pool=self}
  function item:getID()return self.id end;function item:getFullType()return self.kind end
  function item:getContainer()return self.pool end;function item:getWorldItem()return nil end
  if kind=='Base.Bag'then item.inner=container();function item:getInventory()return self.inner end end
  function item:getCurrentUses()return self.uses end;function item:setCurrentUses(n)self.uses=n;self.fraction=n/10 end
  function item:getMaxUses()return self.kind=='Base.PropaneTank'and 100 or 10 end
  function item:getCurrentUsesFloat()return self.fraction or self.uses/10 end
  self.items[#self.items+1]=item;return item
 end
 function c:Remove(item)
  if cleanupFailure and item.kind=='Base.BlowTorch'and item.output then return end
  for i,v in ipairs(self.items)do if v==item then table.remove(self.items,i);item.pool=nil;return end end
 end
 function c:getItemById(id)for _,item in ipairs(self.items)do if item.id==id then return item end end end
 function c:getItemWithIDRecursiv(id)
  local direct=self:getItemById(id);if direct then return direct end
  for _,item in ipairs(self.items)do if item.inner then local found=item.inner:getItemWithIDRecursiv(id);if found then return found end end end
 end
 function c:contains(item)return self.items:contains(item)end
 function c:setExplored(value)end
 return c
end
vehicles=list();local square={}
function square:isOutside()return true end;function square:isFree()return true end
function square:getMovingObjects()return list()end
function square:getX()return 40 end;function square:getY()return 40 end;function square:getZ()return 0 end
local cell={};function cell:getGridSquare()return square end;function cell:getVehicles()return vehicles end
getCell=function()return cell end
IsoDirections={N=1}
spawnCalls=0
addVehicleDebug=function(...)
 assert(select('#',...)==4,'addVehicleDebug requires exactly four native arguments')
 local script,direction,skin,spot=...
 assert(script=='Base.PickUpVan'and direction==IsoDirections.N and skin==nil and spot==square,'invalid native spawn arguments')
 spawnCalls=spawnCalls+1
 local pool=container();local part={getItemContainer=function()return pool end,getArea=function()return 'TruckBed'end}
 local glove=container();local glovePart={getItemContainer=function()return glove end}
 local vehicle={pool=pool,glove=glove,id=#vehicles+1,parts={part,glovePart}}
 if generatedLoot then
  generatedRefs=generatedRefs or {};local function own(item)generatedRefs[#generatedRefs+1]=item;return item end
  own(pool:AddItem('Base.BlowTorch'));own(pool:AddItem('Base.PropaneTank'))
  local bag=own(glove:AddItem('Base.Bag'));own(bag.inner:AddItem('Base.Apple'))
  local inner=own(bag.inner:AddItem('Base.Bag'));own(inner.inner:AddItem('Base.Nails'))
 end
 function vehicle:getSquare()return square end;function vehicle:getId()return self.id end
 function vehicle:getPartById(name)if name=='TruckBed'then return part end end
 function vehicle:getAreaCenter()return {getX=function()return 40 end,getY=function()return 40 end}end
 function vehicle:getVehicleTowing()return nil end;function vehicle:getVehicleTowedBy()return nil end
 function vehicle:getMaxPassengers()return 2 end;function vehicle:getCharacter()return nil end
 function vehicle:getPartCount()return #self.parts end;function vehicle:getPartByIndex(index)return self.parts[index+1]end
 function vehicle:permanentlyRemove()for i,v in ipairs(vehicles)do if v==self then table.remove(vehicles,i);return end end end
 vehicles[#vehicles+1]=vehicle;return vehicle
end
getVehicleById=function(id)for _,v in ipairs(vehicles)do if v.id==id then return v end end end
instanceof=function(item,kind)return kind=='InventoryItem'and item.id~=nil or kind=='InventoryContainer'and item.inner~=nil or kind=='BaseVehicle'and item.getPartCount~=nil or kind=='DrainableComboItem'and(item.kind=='Base.BlowTorch'or item.kind=='Base.PropaneTank')end
isServer=function()return false end;isClient=function()return false end
player={root=container(),x=10,y=12,z=0}
function player:getInventory()return self.root end;function player:getUsername()return 'Single Player'end
function player:getX()return self.x end;function player:getY()return self.y end;function player:getZ()return self.z end
function player:setX(v)self.x=v end;function player:setY(v)self.y=v end
function player:teleportTo(x,y,z)self.x=x;self.y=y;self.z=z end
function player:setNextX(v)end;function player:setNextY(v)end;function player:setLastX(v)end;function player:setLastY(v)end
function player:getOnlineID()return -1 end;function player:getCurrentSquare()return square end
function player:isTimedActionInstant()return false end;function player:canAccessContainer()return true end
function player:getPrimaryHandItem()return self.primary end;function player:getSecondaryHandItem()return self.secondary end
function player:setPrimaryHandItem(item)self.primary=item end;function player:setSecondaryHandItem(item)self.secondary=item end
function player:removeFromHands(item)if self.primary==item then self.primary=nil end;if self.secondary==item then self.secondary=nil end end
getPlayer=function()return player end
unrelatedTorch=player.root:AddItem('Base.BlowTorch');unrelatedTank=player.root:AddItem('Base.PropaneTank')
unrelatedHat=player.root:AddItem('Base.Hat');player.primary=unrelatedHat
table.wipe=function(value)for key in pairs(value)do value[key]=nil end end
ISMouseDrag={}
PaneMethods={}
function PaneMethods:saveSelection(selected)
 for _,v in pairs(self.selected)do
  if instanceof(v,'InventoryItem')then selected[v]=selected[v]or 'item'
  else selected[v.items[1]]='group'end
 end
 return selected
end
function PaneMethods:restoreSelection(selected)
 local row=1
 for _,v in ipairs(self.itemslist)do
  local item=v.items[1]
  if selected[item]=='group'then self.selected[row]=item end
  row=row+1
  if not self.collapsed[v.name]then
   for index=2,#v.items do
    local item2=v.items[index];if selected[item2]then self.selected[row]=item2 end;row=row+1
   end
  end
 end
end
function PaneMethods:refreshContainer()
 local saved=self:saveSelection({});table.wipe(self.selected)
 self.itemslist={};local groups={}
 for _,item in ipairs(self.inventory.items)do
  local name=item.kind;local group=groups[name]
  if not group then group={name=name,items={item}};groups[name]=group;self.itemslist[#self.itemslist+1]=group end
  group.items[#group.items+1]=item
  if self.collapsed[name]==nil then self.collapsed[name]=true end
 end
 table.sort(self.itemslist,function(a,b)return a.name<b.name end)
 self:restoreSelection(saved)
end
function PaneMethods:getYScroll()return self.scroll end
function PaneMethods:setYScroll(value)self.scroll=value end
function page()
 local pane=setmetatable({inventory=player.root,lastinventory=player.root,selected={},collapsed={['Base.BlowTorch']=false},scroll=-17}, {__index=PaneMethods})
 pane:refreshContainer();pane.selected={[1]=pane.itemslist[1],[2]=unrelatedTorch,[3]=pane.itemslist[2]}
 pane.firstSelect=3;pane.joyselection=1;pane.smoothScrollTargetY=-23
 return {inventoryPane=pane,visible=false,
  refreshBackpacks=function(self)
   self.inventoryPane.inventory=self.forceSelectedContainer or self.inventoryPane.lastinventory
   self.inventoryPane:refreshContainer()
  end,
  setForceSelectedContainer=function(self,c)self.forceSelectedContainer=c;self:refreshBackpacks()end,
  getIsVisible=function(self)return self.visible end,setVisible=function(self,v)self.visible=v end}
end
invPage=page();lootPage=page()
getPlayerInventory=function()return invPage end;getPlayerLoot=function()return lootPage end
Events={};for _,name in ipairs({'OnTick','OnGameStart','OnServerCommand','OnServerStarted','OnClientCommand'})do
 local handlers={};Events[name]={Add=function(fn)handlers[#handlers+1]=fn end,fire=function(...)for _,fn in ipairs(handlers)do fn(...)end end}
end
queue={queue={}};function queue:indexOf(action)for i,v in ipairs(self.queue)do if v==action then return i-1 end end;return -1 end
ISTimedActionQueue={getTimedActionQueue=function()return queue end}
recipe={getScriptObjectFullType=function()return 'Base.RefillBlowTorch'end,getTime=function()return 50 end}
HandcraftLogic={new=function()
 local logic={}
 function logic:findCraftSurface()return nil end;function logic:setIsoObject()end;function logic:setContainers()end
 function logic:setRecipeFromContextClick(recipe,torch)self.torch=torch end
 function logic:canPerformCurrentRecipe()return true end
 function logic:getRecipeData()
  local tank
  for _,item in ipairs(self.torch.pool.items)do if item.kind=='Base.PropaneTank'and item~=unrelatedTank then tank=item end end
  local inputs=list({self.torch,chooseForeignTank and unrelatedTank or tank})
  return {getAllInputItems=function()return inputs end}
 end
 return logic
end}
ISInventoryPaneContextMenu={}
ISInventoryPaneContextMenu.OnNewCraft=function(torch)
 local craft={Type='ISHandcraftAction',craftRecipe=recipe,action={},source=torch,steps=0,
  getDuration=function()return 250 end,isStarted=function()return true end}
 queue.queue={craft};queue.current=craft
end
ISInventoryPaneContextMenu.getContainers=function()
 local pools=list({player.root});for _,v in ipairs(vehicles)do pools[#pools+1]=v.pool end;return pools
end
ISInventoryPaneContextMenu.createMenu=function(_,_,items)
 return {options={{onSelect=ISInventoryPaneContextMenu.OnNewCraft,target=items[1],param1=recipe}},hideAndChildren=function()end}
end
function nativeTick()
 local action=queue.current;if not action then return end
 action.steps=action.steps+1;if action.steps<3 then return end
 local source=action.source;local pool=source.pool;local tank
 for _,item in ipairs(pool.items)do if item.kind=='Base.PropaneTank'and item~=unrelatedTank then tank=item end end
 assert(tank)
 local full=source:getMaxUses()*70;local held=source:getCurrentUsesFloat()*full
 local added=math.min(full-held,tank.uses)
 pool:Remove(source);local output=pool:AddItem('Base.BlowTorch');output.output=true;output.retained=source.retained
 output.fraction=(held+added)/full;output.uses=math.floor(output.fraction*10);tank.uses=math.floor(tank.uses-added+.5)
 queue.queue={};queue.current=nil
end
function step()
 now=now+100
 nativeTick();Events.OnTick.fire()
end
'''


class TorchRefillSessionTests(unittest.TestCase):
    def runtime(self, cases=None, kind='sp', native_pane_source=None):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().selection = lua.table_from(dict(suite='torch-refill', kind=kind, cases=lua.table_from(cases or ['trunk-retained', 'root-retained', 'trunk-unmarked'])))
        lua.execute(HARNESS)
        if native_pane_source:
            methods = native_pane_source.split('function ISInventoryPane:saveSelection(selected)', 1)[1].split('function ISInventoryPane:refreshContainer()', 1)[0]
            lua.execute('ISInventoryPane=PaneMethods\nfunction ISInventoryPane:saveSelection(selected)' + methods)
        paths = [ROOT / 'tests/native_queue/support/QueueFixtureSession.lua', *sorted((FIXTURE / 'shared').glob('*.lua'))]
        for path in paths:
            lua.execute("package.preload[%r]=function(...)\n%s\nend" % (path.stem, path.read_text()))
        if kind == 'mp':
            lua.execute(r"""
            authoritySide=false;isServer=function()return authoritySide end;isClient=function()return true end
            player.getUsername=function()return 'client1'end;player.getOnlineID=function()return 0 end
            player.secondary=unrelatedTorch
            serverHands={primary=player.primary,secondary=player.secondary}
            player.getPrimaryHandItem=function(self)return authoritySide and serverHands.primary or(not authoritySide and self.primary or nil)end
            player.getSecondaryHandItem=function(self)return authoritySide and serverHands.secondary or(not authoritySide and self.secondary or nil)end
            player.setPrimaryHandItem=function(self,item)if authoritySide then serverHands.primary=item else self.primary=item end end
            player.setSecondaryHandItem=function(self,item)if authoritySide then serverHands.secondary=item else self.secondary=item end end
            equipPackets={};equipSent=0
            player.updateHandEquips=function(self)
             assert(not authoritySide,'fixture restore should send client equipment')
             equipSent=equipSent+1
             equipPackets[#equipPackets+1]={primary=self.primary,secondary=self.secondary}
            end
            network={}
            sendClientCommand=function(module,command,args)network[#network+1]={module=module,command=command,args=args}end
            sendServerCommand=function(player,module,command,args)network[#network+1]={module=module,command=command,args=args,authority=true}end
            replicatedRemovals={};containerSnapshots={}
            sendItemsInContainer=function(vehicle,pool)containerSnapshots[#containerSnapshots+1]={vehicle=vehicle,pool=pool}end
            sendAddItemToContainer=function()end
            sendRemoveItemFromContainer=function(pool,item)replicatedRemovals[item.id]={pool=pool,item=item}end
            Events.OnTick.Add(function()
             if not holdEquip then
              for _,packet in ipairs(equipPackets)do serverHands.primary=packet.primary;serverHands.secondary=packet.secondary end
              equipPackets={}
             end
             local messages=network;network={}
             for _,entry in ipairs(messages)do
              if entry.authority then Events.OnServerCommand.fire(entry.module,entry.command,entry.args)
              else authoritySide=true;Events.OnClientCommand.fire(entry.module,entry.command,player,entry.args);authoritySide=false end
             end
            end)
            nativeAuthorityTick=Events.OnTick.Add
            Events.OnTick.Add=function(fn)nativeAuthorityTick(function()authoritySide=true;fn();authoritySide=false end)end
            authoritySide=true
            """)
            lua.execute((FIXTURE / 'server/ZZTorchRefillServer.lua').read_text())
            lua.execute(r"""
            Events.OnTick.Add=nativeAuthorityTick;Events.OnServerStarted.fire();authoritySide=false
            local original=nativeTick
            nativeTick=function()
             local action=queue.current
             if action and action.steps==0 then
              player.primary=nil;player.secondary=nil;serverHands.primary=nil;serverHands.secondary=nil
             end
             original()
             if action and not queue.current then
              local sourceID=action.source.id
              local pool=vehicles[1]and vehicles[1].pool or player.root
              local output
              for _,item in ipairs(pool.items)do if item.output then output=item end end
              Events.OnServerCommand.fire('PZSurvivorToolkitTorchRefill','Refilled',{sourceID=sourceID,outputID=output.id})
             end
            end
            """)
        lua.execute((FIXTURE / 'client/ZZTorchRefill.lua').read_text())
        lua.execute('Events.OnGameStart.fire()')
        return lua

    def run_ticks(self, lua, count=650):
        lua.execute('for i=1,%d do step()end' % count)
        return '\n'.join(lua.globals().logs.values())

    def test_three_native_callbacks_restore_exact_baseline_between_phases(self):
        lua = self.runtime()
        logs = self.run_ticks(lua)
        self.assertNotIn('[TORCH_REFILL] FAIL', logs, logs)
        self.assertEqual(logs.count('[TORCH_REFILL] COMPLETE '), 3)
        self.assertEqual(logs.count('[TORCH_REFILL] NATIVE '), 3)
        self.assertEqual(logs.count('[TORCH_REFILL] AUTHORITY '), 3)
        self.assertEqual(logs.count('[TORCH_REFILL] REMOVED '), 3)
        lua.execute("assert(#player.root.items==3 and player.root:contains(unrelatedTorch)and player.root:contains(unrelatedTank));assert(player.primary==unrelatedHat and player.x==10 and player.y==12);assert(#vehicles==0);local selected=invPage.inventoryPane:saveSelection({});assert(selected[unrelatedTorch]and selected[unrelatedHat]and not selected[unrelatedTank]);assert(not lootPage.visible and not lootPage.forceSelectedContainer)")

    def test_host_transport_runs_three_cases_with_product_rpc_and_authority_ack(self):
        lua = self.runtime(kind='mp')
        logs = self.run_ticks(lua)
        self.assertNotIn('[TORCH_REFILL] FAIL', logs, logs)
        self.assertEqual(logs.count('[TORCH_REFILL] COMPLETE '), 3)
        self.assertEqual(logs.count('[TORCH_REFILL] REFILLED '), 3)
        self.assertEqual(logs.count('[TORCH_REFILL] REMOVED '), 3)
        lua.execute('assert(#vehicles==0 and #player.root.items==3 and player.primary==unrelatedHat)')

    def test_host_equipment_restore_waits_for_delayed_native_equip_packet(self):
        lua = self.runtime(kind='mp')
        lua.execute('holdEquip=true')
        pending = self.run_ticks(lua, 75)
        self.assertIn('[TORCH_REFILL] AUTHORITY ', pending)
        self.assertNotIn('[TORCH_REFILL] REMOVED ', pending)
        lua.execute('assert(player.primary==unrelatedHat and player.secondary==unrelatedTorch);assert(serverHands.primary==nil and serverHands.secondary==nil and #equipPackets==1)')
        lua.execute('holdEquip=false')
        logs = self.run_ticks(lua)
        self.assertNotIn('[TORCH_REFILL] FAIL', logs, logs)
        self.assertEqual(logs.count('[TORCH_REFILL] COMPLETE '), 3)
        lua.execute('assert(serverHands.primary==unrelatedHat and serverHands.secondary==unrelatedTorch and equipSent>=3)')

    def test_host_missing_native_equip_packet_quarantines_before_cleanup(self):
        lua = self.runtime(kind='mp')
        lua.execute('holdEquip=true')
        logs = self.run_ticks(lua)
        self.assertIn('authority baseline restoration timeout', logs)
        self.assertNotIn('[TORCH_REFILL] REMOVED ', logs)
        self.assertEqual(logs.count('[TORCH_REFILL] PREPARED '), 1)
        lua.execute('assert(player.primary==unrelatedHat and player.secondary==unrelatedTorch);assert(serverHands.primary==nil and serverHands.secondary==nil)')

    def test_native_spawn_uses_exact_four_argument_overload(self):
        lua = self.runtime()
        logs = self.run_ticks(lua)
        self.assertNotIn('[TORCH_REFILL] FAIL', logs, logs)
        lua.execute("""
        assert(spawnCalls==2)
        local ok,reason=pcall(function()
         addVehicleDebug('Base.PickUpVan',IsoDirections.N,nil,assert(getCell():getGridSquare(1,1,0),'no clear truck spawn square'))
        end)
        assert(not ok and tostring(reason):find('exactly four native arguments',1,true))
        assert(spawnCalls==2)
        """)

    def test_generated_vehicle_loot_is_exactly_owned_and_removed_for_sp_and_host(self):
        for kind in ('sp', 'mp'):
            with self.subTest(kind=kind):
                lua = self.runtime(kind=kind)
                lua.execute('generatedLoot=true')
                logs = self.run_ticks(lua)
                self.assertNotIn('[TORCH_REFILL] FAIL', logs, logs)
                self.assertEqual(logs.count('[TORCH_REFILL] COMPLETE '), 3)
                lua.execute("""
                assert(#generatedRefs==12 and #vehicles==0 and #player.root.items==3)
                for _,item in ipairs(generatedRefs)do assert(item:getContainer()==nil)end
                assert(player.root:contains(unrelatedTorch)and player.root:contains(unrelatedTank))
                """)
                if kind == 'mp':
                    lua.execute("""
                    for _,item in ipairs(generatedRefs)do assert(replicatedRemovals[item.id].item==item)end
                    assert(#containerSnapshots==4)
                    """)

    def test_client_waits_for_generated_nested_loot_removal_replication(self):
        lua = self.runtime()
        lua.execute("""
        generatedLoot=true
        local F=require 'TorchRefillFixture'
        local baseline=F.baseline(player)
        local state=F.prepare(player,'trunk-retained',1)
        assert(#state.generatedIDs==6)
        assert(F.resolve(state.packet,player,baseline,state))
        local bag=generatedRefs[3];local child=generatedRefs[4]
        state.vehicle.glove.items[#state.vehicle.glove.items+1]=bag;bag.pool=state.vehicle.glove
        bag.inner.items[#bag.inner.items+1]=child;child.pool=bag.inner
        assert(not F.resolve(state.packet,player,baseline,state))
        bag.inner:Remove(child);state.vehicle.glove:Remove(bag)
        assert(F.resolve(state.packet,player,baseline,state))
        """)

    def test_missing_baseline_acknowledgement_stops_before_removal(self):
        lua = self.runtime()
        lua.execute("""
        local session=require 'TorchRefillSession';local original=step
        step=function()
         for _,entry in ipairs(session.messages)do
          if entry.command=='BaselineRestored'then entry.args.fixtureEpoch=0 end
         end
         original()
        end
        """)
        logs = self.run_ticks(lua)
        self.assertIn('authority baseline acknowledgement timeout', logs)
        self.assertEqual(logs.count('[TORCH_REFILL] PREPARED '), 1)
        self.assertNotIn('[TORCH_REFILL] REMOVED ', logs)

    def test_actual_phase_records_verify_for_sp_and_host(self):
        for kind in ('sp', 'mp'):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                lua = self.runtime(kind=kind)
                logs = self.run_ticks(lua)
                root = Path(directory)
                (root / 'client1-launch.log').write_text(logs)
                (root / 'server-launch.log').write_text(logs)
                selection = dict(kind=kind, cases=list(adapter.CASES))
                result = adapter.verify(root, selection, {})
                self.assertEqual(result['issues'], [])
                self.assertEqual([row['status'] for row in result['outcomes']], ['passed'] * 3)

    def test_logical_ui_selection_survives_native_style_wipe_rebuild(self):
        lua = self.runtime()
        lua.execute('initialSelectionTable=lootPage.inventoryPane.selected')
        logs = self.run_ticks(lua)
        self.assertNotIn('[TORCH_REFILL] FAIL', logs, logs)
        self.assertEqual(logs.count('[TORCH_REFILL] COMPLETE '), 3)
        lua.execute("""
        assert(next(initialSelectionTable)==nil,'native refresh must wipe the aliased baseline table')
        for _,page in ipairs({invPage,lootPage})do
         local pane=page.inventoryPane;local selected=pane:saveSelection({})
         assert(selected[unrelatedTorch]and selected[unrelatedHat]and not selected[unrelatedTank])
         assert(pane.selected[1]and pane.selected[2]and pane.selected[3])
         assert(pane.firstSelect==3 and pane.joyselection==1)
         assert(pane.collapsed['Base.BlowTorch']==false and pane.collapsed['Base.Hat']==true)
         assert(pane:getYScroll()==-17 and pane.smoothScrollTargetY==-23)
         assert(pane.inventory==player.root and pane.lastinventory==player.root)
        end
        """)

    def test_ui_selection_with_installed_native_save_restore(self):
        game = os.environ.get('PZ_GAME')
        if not game:
            self.skipTest('PZ_GAME with current native Lua sources is required')
        source = (Path(game) / 'media/lua/client/ISUI/ISInventoryPane.lua').read_text()
        self.assertIn('local selected = self:saveSelection({})\n\ttable.wipe(self.selected)', source)
        lua = self.runtime(native_pane_source=source)
        logs = self.run_ticks(lua)
        self.assertNotIn('[TORCH_REFILL] FAIL', logs, logs)
        self.assertEqual(logs.count('[TORCH_REFILL] COMPLETE '), 3)
        lua.execute("""
        for _,page in ipairs({invPage,lootPage})do
         local pane=page.inventoryPane;local selected=pane:saveSelection({})
         assert(selected[unrelatedTorch]and selected[unrelatedHat]and not selected[unrelatedTank])
         assert(pane.firstSelect==3 and pane.joyselection==1 and pane:getYScroll()==-17)
        end
        """)

    def test_native_selector_foreign_fuel_is_rejected_before_callback(self):
        lua = self.runtime()
        lua.execute('chooseForeignTank=true')
        logs = self.run_ticks(lua)
        self.assertIn('native selector would borrow unrelated/repeated input', logs)
        self.assertNotIn('[TORCH_REFILL] ENQUEUED ', logs)
        lua.execute('assert(unrelatedTank.uses==10 and unrelatedTorch.uses==10 and #queue.queue==0)')

    def test_subset_in_reverse_order(self):
        lua = self.runtime(['root-retained', 'trunk-retained'])
        logs = self.run_ticks(lua)
        self.assertNotIn('[TORCH_REFILL] FAIL', logs, logs)
        self.assertEqual(logs.count('[TORCH_REFILL] COMPLETE '), 2)

    def test_cleanup_failure_quarantines_without_next_phase(self):
        lua = self.runtime()
        lua.execute('cleanupFailure=true')
        logs = self.run_ticks(lua)
        self.assertIn('owned item removal failed', logs)
        self.assertEqual(logs.count('[TORCH_REFILL] PREPARED '), 1)
        self.assertNotIn('[TORCH_REFILL] COMPLETE ', logs)
        lua.execute('assert(player.root:contains(unrelatedHat)and player.root:contains(unrelatedTorch))')

    def test_missing_authority_and_stale_payload_never_advance(self):
        lua = self.runtime()
        lua.execute("""
        local session=require 'TorchRefillSession'
        originalStep=step
        step=function()
         for _,entry in ipairs(session.messages)do
          if entry.command=='Verified'then entry.args.fixtureEpoch=0 end
         end
         originalStep()
        end
        """)
        logs = self.run_ticks(lua)
        self.assertIn('authority timeout', logs)
        self.assertIn('[QUEUE_SESSION] REJECT case=trunk-retained epoch=1 actor=client1 command=Verified', logs)
        self.assertEqual(logs.count('[TORCH_REFILL] PREPARED '), 1)
        self.assertNotIn('[TORCH_REFILL] REMOVED ', logs)

    def test_foreign_truck_content_stops_cleanup_without_erasing_it(self):
        lua = self.runtime()
        lua.execute('for i=1,20 do step()end;foreign=vehicles[1].pool:AddItem(\'Base.Apple\')')
        logs = self.run_ticks(lua)
        self.assertIn('foreign item in fixture truck', logs)
        self.assertEqual(logs.count('[TORCH_REFILL] PREPARED '), 1)
        lua.execute('assert(vehicles[1].pool:contains(foreign))')


if __name__ == '__main__':
    unittest.main()
