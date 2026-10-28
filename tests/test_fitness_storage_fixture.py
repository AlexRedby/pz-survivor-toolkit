"""Run the multi-storage observer against Lua doubles; no gameplay is simulated as proof."""
from pathlib import Path
import os
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "tests/native_queue/fitness/shared/QueueFitnessStorage.lua"

HARNESS = r"""
local nextID=100
function list(values)return{size=function()return #values end,get=function(_,i)return values[i+1]end,contains=function(_,v)for _,item in ipairs(values)do if item==v then return true end end;return false end}end
function instanceof(value,kind)return value and value.class==kind end
server=false;sent={};clothes={};equips=0
world={frame=100,getFrameNo=function(self)return self.frame end};function getWorld()return world end
GameTime={getServerTimeMills=function()return 1000 end}
function isServer()return server end
function sendAddItemToContainer(container,item)sent[#sent+1]={container=container,item=item}end
function sendRemoveItemFromContainer()end
function sendClothing(player,slot,item)clothes[#clothes+1]={slot=slot,item=item}end
function sendEquip()equips=equips+1 end
function getGameTime()return{getTimeOfDay=function()return 8 end,getNightsSurvived=function()return 0 end}end
local slots={['Base.Bag_Schoolbag']='base:back',['Base.Bag_Satchel']='base:satchel',['Base.Bag_FannyPackFront']='base:fannypackfront'}
function container(kind)
 local c={items={},kind=kind or 'bag'}
 function c:getItems()return list(self.items)end
 function c:getType()return self.kind end
 function c:getItemById(id)
  for _,item in ipairs(self.items)do
   if item.id==id then return item end
   if item.inner then local value=item.inner:getItemById(id);if value then return value end end
  end
 end
 function c:Remove(item)for i,value in ipairs(self.items)do if value==item then table.remove(self.items,i);item.source=nil;return end end end
 function c:AddItem(value)
  local item=value
  if type(value)=='string'then
   nextID=nextID+1;item={id=nextID,kind=value,favorite=false,class=slots[value]and 'InventoryContainer'or 'InventoryItem'}
   function item:getWeight()return .5 end
   function item:getID()return self.id end
   function item:getFullType()return self.kind end
   function item:getContainer()return self.source end
   function item:getItemContainer()return self.inner end
   function item:canBeEquipped()return slots[self.kind]end
   function item:isFavorite()return self.favorite end
   function item:setFavorite(value)self.favorite=value end
   function item:getWorldItem()return self.world end
   if item.class=='InventoryContainer'then item.inner=container()end
  end
  if item.source then item.source:Remove(item)end
  self.items[#self.items+1]=item;item.source=self;return item
 end
 return c
end
square={objects={}}
function square:getX()return 10 end;function square:getY()return 20 end;function square:getZ()return 0 end
function square:getWorldObjects()return list(self.objects)end
function getCell()return{getGridSquare=function()return square end}end
floor=container('floor')
function playerNew()
 local p={inventory=container('inventory'),worn={}}
 function p:getInventory()return self.inventory end
 function p:getPrimaryHandItem()return self.primary end;function p:getSecondaryHandItem()return self.secondary end
 function p:setPrimaryHandItem(item)self.primary=item end;function p:setSecondaryHandItem(item)self.secondary=item end
 function p:getCurrentSquare()return square end
 function p:setWornItem(slot,item)self.worn[slot]=item end;function p:getWornItem(slot)return self.worn[slot]end
 function p:removeWornItem(item)for slot,value in pairs(self.worn)do if value==item then self.worn[slot]=nil end end end
 function p:isEquipped(item)
  if self.primary==item or self.secondary==item then return true end
  for _,value in pairs(self.worn)do if value==item then return true end end;return false
 end
 function p:getWornItems()
  local rows={};for slot,item in pairs(self.worn)do rows[#rows+1]={getLocation=function()return slot end,getItem=function()return item end}end
  return list(rows)
 end
 return p
end
ISInventoryTransferAction={};ISInventoryTransferAction.__index=ISInventoryTransferAction;ISDropWorldItemAction={}
function action(class,item,source,destination)
 return setmetatable({Type=class==ISInventoryTransferAction and 'ISInventoryTransferAction'or 'ISDropWorldItemAction',
  character=state.player,item=item,srcContainer=source,destContainer=destination,isPlaceItem=true,queueList={{items={item},time=100,type=item:getFullType()}}},class)
end
function prepare()
 square.objects={};floor.items={};sent={};clothes={};equips=0
 local p=playerNew();state={case='multi-storage',player=p,items={},ids={items={}}}
 for name,kind in pairs({bag='Base.Bag_Schoolbag',hammer='Base.Bag_Satchel',screwdriver='Base.Screwdriver'})do
  state.items[name]=p.inventory:AddItem(kind);state.ids.items[name]=state.items[name].id
 end
 state.items.dumbbell=state.items.hammer.inner:AddItem('Base.DumbBell');state.ids.items.dumbbell=state.items.dumbbell.id
 S.prepare(state);spec=state.ids.multiStorage;return state
end
function place(item)
 local p=state.player;p:removeWornItem(item)
 if p.primary==item then p.primary=nil end;if p.secondary==item then p.secondary=nil end
 floor:AddItem(item)
 local world={class='IsoWorldInventoryObject',item=item}
 function world:getItem()return self.item end;function world:getSquare()return square end
 item.world=world;square.objects[#square.objects+1]=world;return world
end
function recover(item)
 for i,world in ipairs(square.objects)do if world.item==item then table.remove(square.objects,i);break end end
 item.world=nil;state.player.inventory:AddItem(item)
end
"""


class FitnessStorageFixtureTests(unittest.TestCase):
    def setUp(self):
        try:
            from lupa.lua51 import LuaRuntime
        except ImportError:
            self.skipTest("Lua 5.1 Lupa runtime unavailable")
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(HARNESS)
        self.lua.globals().S = self.lua.execute(MODULE.read_text())
        self.lua.execute("prepare()")

    def check(self, code):
        self.lua.execute(code)

    def test_native_configuration_and_parent_only_serialization(self):
        self.check("""
assert(S.matches('multi-storage')and S.matches('multi-storage-closed')and not S.matches('empty-restore'))
assert(S.coreType('multi-storage','hammer','Base.Hammer')=='Base.Bag_Satchel')
assert(S.coreType('empty-restore','hammer','Base.Hammer')=='Base.Hammer')
assert(S.propContainer(state)==state.items.hammer.inner and S.resolveReady(state))
assert(#spec.bags==3 and #spec.markers==3 and spec.prop.bag==state.items.hammer.id)
server=true;prepare();assert(#sent==1 and sent[1].item==state.items.fanny and #clothes==1)
assert(sent[1].item.inner:getItems():size()==1 and state.items.hammer.inner:getItems():size()==2)
assert(S.resolveReady(state))
""")

    def test_snapshot_keeps_world_contents_favorites_and_duplicate_occurrences(self):
        self.check("""
local original=S.snapshot(state.player,spec)
local prop=state.items.dumbbell;state.player.inventory:AddItem(prop)
local world=place(state.items.hammer)
local snap=S.snapshot(state.player,spec)
assert(snap.bags[2].endpoint=='world'and snap.bags[2].world.linked and snap.bags[2].occurrences==1)
assert(#snap.bags[2].contents==1 and snap.prop.endpoint=='root'and snap.prop.favorite)
assert(original.bags[2].endpoint=='root'and #original.bags[2].contents==2)
local clone=state.player.inventory:AddItem('Base.Bag_Satchel');clone.id=state.items.hammer.id
assert(S.snapshot(state.player,spec).bags[2].occurrences==2)
state.player.inventory:Remove(clone);world.item=clone;assert(not S.snapshot(state.player,spec).bags[2].world.linked)
""")

    def test_ready_rejects_type_substitution_contents_and_favorites(self):
        for mutation in (
            "state.items.hammer.kind='Base.Bag_Schoolbag'",
            "state.items.hammer.favorite=false",
            "state.items.dumbbell.favorite=false",
            "state.player.inventory:AddItem(state.items.multiMarker2)",
            "state.player.inventory:AddItem(state.items.dumbbell)",
            "state.player.worn['base:fannypackfront']=nil",
            "state.items.fanny.id=9999",
        ):
            with self.subTest(mutation=mutation):
                self.check("prepare();" + mutation + ";assert(not S.resolveReady(state))")

    def test_exact_real_start_witnesses_and_completion_snapshot(self):
        self.check("""
local bag=state.items.hammer;local drop=action(ISDropWorldItemAction,bag)
local begin=S.observeStart(state,drop)
assert(begin.phase=='placement'and begin.snapshot.bags[2].endpoint=='root'and begin.succeeded==nil)
assert(not S.observeStart(state,drop))
state.player.inventory:AddItem(state.items.dumbbell);place(bag)
local paid=S.placement(state,drop,'ISDropWorldItemAction.complete',true)
assert(paid.succeeded and paid.snapshot.bags[2].endpoint=='world'and paid.snapshot.bags[2].world.linked)
local pickup=action(ISInventoryTransferAction,bag,floor,state.player.inventory)
local witness=S.observeStart(state,pickup);assert(witness.phase=='recovery'and witness.id==bag.id)
assert(not S.observeStart(state,pickup));recover(bag)
local prop=state.items.dumbbell;local returning=action(ISInventoryTransferAction,prop,state.player.inventory,bag.inner)
assert(S.observeStart(state,returning).phase=='return')
bag.inner:AddItem(prop);assert(not S.observeStart(state,action(ISInventoryTransferAction,prop,state.player.inventory,bag.inner)))
""")

    def test_forged_and_wrong_endpoint_actions_never_earn_witness(self):
        self.check("""
local bag=state.items.hammer;local fake=action(ISDropWorldItemAction,bag);setmetatable(fake,{})
assert(not S.observeStart(state,fake))
fake=action(ISDropWorldItemAction,bag);fake.character=playerNew();assert(not S.observeStart(state,fake))
fake=action(ISDropWorldItemAction,bag);fake.isPlaceItem=false;assert(not S.observeStart(state,fake))
local prop=state.items.dumbbell;state.player.inventory:AddItem(prop)
assert(not S.observeStart(state,action(ISInventoryTransferAction,prop,state.player.inventory,state.items.bag.inner)))
local clone=state.player.inventory:AddItem('Base.DumbBell')
assert(not S.observeStart(state,action(ISInventoryTransferAction,clone,state.player.inventory,bag.inner)))
place(bag)
clone=floor:AddItem('Base.Bag_Satchel');clone.id=bag.id
assert(not S.observeStart(state,action(ISInventoryTransferAction,clone,floor,state.player.inventory)))
local world=bag.world;clone.world=world
assert(not S.observeStart(state,action(ISInventoryTransferAction,clone,floor,state.player.inventory)))
-- A fully linked fresh Host replica with the original ID/type is valid.
world.item=clone;bag.world=nil;floor:Remove(bag)
assert(S.observeStart(state,action(ISInventoryTransferAction,clone,floor,state.player.inventory)).phase=='recovery')
""")

    def test_actual_native_queue_merge_extends_one_observed_begin(self):
        game=os.environ.get('PZ_GAME')
        if not game:self.skipTest('PZ_GAME required for native queueList source check')
        source=(Path(game)/'media/lua/client/TimedActions/ISInventoryTransferAction.lua').read_text()
        start=source.index('function ISInventoryTransferAction:canMergeAction(action)')
        end=source.index('function ISInventoryTransferAction:setAllowMissingItems',start)
        self.lua.execute(source[start:end])
        self.check("""
state.player.inventory:AddItem(state.items.dumbbell)
local actions={}
for _,ref in ipairs(spec.bags)do
 local bag=state.player.inventory:getItemById(ref.id);place(bag)
 actions[#actions+1]=action(ISInventoryTransferAction,bag,floor,state.player.inventory)
end
local first,second,third=actions[1],actions[2],actions[3]
queue={queue={first,second,third,{Type='independent'}}}
function queue:indexOf(value)for i,item in ipairs(self.queue)do if item==value then return i end end;return -1 end
ISTimedActionQueue={getTimedActionQueue=function(player)assert(player==state.player);return queue end}
function round(value)return value end
function table.wipe(value)for key in pairs(value)do value[key]=nil end end
local witness=S.observeStart(state,first)
assert(#witness.members==1 and witness.membersCallback=='ISBaseTimedAction.begin')
first:checkQueueList() -- Exact source: merges then wipes the two child actions.
assert(#queue.queue==2 and not next(second)and not next(third))
assert(S.observeStart(state,first,'ISInventoryTransferAction.checkQueueList')==nil)
assert(#witness.members==3 and not witness.membersError and witness.callback=='ISBaseTimedAction.begin')
assert(witness.membersCallback=='ISInventoryTransferAction.checkQueueList')
assert(witness.members[1].id==spec.bags[1].id and witness.members[3].id==spec.bags[3].id)
local oldSnapshot=witness.membersSnapshot
recover(first.item);table.remove(first.queueList,1)
S.observeStart(state,first,'ISInventoryTransferAction.checkQueueList')
assert(#witness.members==3 and witness.membersSnapshot==oldSnapshot and not witness.membersError)
first.queueList={};S.observeStart(state,first,'ISInventoryTransferAction.checkQueueList')
assert(#witness.members==3 and not witness.membersError)
""")

    def test_native_group_update_rejects_forged_members_and_endpoint_changes(self):
        for mutation in ("first.queueList[1].type='Base.Screwdriver'",
                         "first.queueList[3]={items={first.item},type=first.item:getFullType()}",
                         "first.queueList[1].items[3]=first.item",
                         "first.queueList[2]={items={first.item},type=first.item:getFullType()}", "first.queueList[2]={items={state.items.screwdriver}}",
                         "first.destContainer=state.items.hammer.inner"):
            with self.subTest(mutation=mutation):
                self.check("""
prepare();state.player.inventory:AddItem(state.items.dumbbell)
local bag=state.items.bag;place(bag)
first=action(ISInventoryTransferAction,bag,floor,state.player.inventory)
witness=S.observeStart(state,first);assert(#witness.members==1 and not witness.membersError)
"""+mutation+"""
S.observeStart(state,first,'ISInventoryTransferAction.checkQueueList')
assert(witness.membersError and #witness.members==1,'invalid members granted batch coverage')
""")

    def test_late_group_merge_keeps_each_members_original_world_boundary(self):
        self.check("""
state.player.inventory:AddItem(state.items.dumbbell)
local actions={}
for _,ref in ipairs(spec.bags)do
 local bag=state.player.inventory:getItemById(ref.id);place(bag)
 actions[#actions+1]=action(ISInventoryTransferAction,bag,floor,state.player.inventory)
end
local first=actions[1];local witness=S.observeStart(state,first)
assert(#witness.memberCaptures==1 and #witness.memberCaptures[1].members==1)
recover(first.item)
first.queueList={actions[2].queueList[1],actions[3].queueList[1]}
assert(S.observeStart(state,first,'ISInventoryTransferAction.checkQueueList')==nil)
assert(not witness.membersError and #witness.members==3 and #witness.memberCaptures==2)
assert(witness.memberCaptures[1].snapshot.bags[1].endpoint=='world')
assert(witness.memberCaptures[2].snapshot.bags[1].endpoint=='root')
assert(#witness.memberCaptures[2].members==2 and witness.memberCaptures[2].callback=='ISInventoryTransferAction.checkQueueList')
""")

    def test_real_server_drop_constructor_omits_client_only_placement_flag(self):
        game = os.environ.get('PZ_GAME')
        if not game:
            self.skipTest('PZ_GAME required for native drop constructor/completion source check')
        source = (Path(game) / 'media/lua/shared/TimedActions/ISDropWorldItemAction.lua').read_text()
        constructor = source[source.index('function ISDropWorldItemAction:new('):]
        self.assertNotIn('isPlaceItem', constructor.splitlines()[0])
        complete_start = source.index('function ISDropWorldItemAction:complete()')
        complete_end = source.index('function ISDropWorldItemAction:perform()', complete_start)
        self.check("""
ISDropWorldItemAction.__index=ISDropWorldItemAction;ISDropWorldItemAction.Type='ISDropWorldItemAction'
ISBaseTimedAction={new=function(class,player)return setmetatable({character=player},class)end}
ISDropWorldItemAction.getDuration=function()return 50 end
function square:AddWorldInventoryItem(item)
 local world=place(item)
 function world:setIgnoreRemoveSandbox()end
 function world:setExtendedPlacement()end
 function world:transmitCompleteItemToClients()end
 function item:setWorldZRotation(value)self.worldRotation=value end
 return item
end
""")
        self.lua.execute(constructor)
        self.lua.execute(source[complete_start:complete_end])
        self.check("""
server=true
local item=state.items.bag
function item:getType()return self.kind:match('[^.]+$')end
local clientAction=ISDropWorldItemAction:new(state.player,item,square,0.5,0.5,0,0,false)
clientAction.isPlaceItem=true -- Actual client-only post-constructor assignment.
-- NetTimedAction sends constructor parameters, then the server calls new afresh.
local copied=ISDropWorldItemAction:new(clientAction.character,clientAction.item,clientAction.sq,
 clientAction.xoffset,clientAction.yoffset,clientAction.zoffset,clientAction.rotation,clientAction.isMultiple)
assert(getmetatable(copied)==ISDropWorldItemAction and copied.Type=='ISDropWorldItemAction')
assert(copied.isPlaceItem==nil and copied.isMultiple==false)
assert(not S.placement(state,copied,'ISDropWorldItemAction.complete',true),'unpaid server placement was accepted')
local originalComplete=ISDropWorldItemAction.complete;local completeCalls=0
local function observedComplete(action)
 completeCalls=completeCalls+1
 local result=originalComplete(action)
 return result,S.placement(state,action,'ISDropWorldItemAction.complete',result==true)
end
local result,witness=observedComplete(copied)
assert(result==true and completeCalls==1 and witness and witness.succeeded)
assert(witness.snapshot.bags[1].endpoint=='world'and witness.snapshot.bags[1].world.linked)
assert(witness.id==item:getID()and witness.kind=='Base.Bag_Schoolbag')
assert(copied.isPlaceItem==nil,'observer fabricated a missing wire field')
local failed=S.placement(state,copied,'ISDropWorldItemAction.complete',false)
assert(not failed or failed.succeeded==false,'failed callback claimed paid placement')
assert(not S.placement(state,copied,'foreign-completion',true),'foreign callback claimed native completion')
local meta=getmetatable(copied);setmetatable(copied,{Type='ISDropWorldItemAction'})
assert(not S.placement(state,copied,'ISDropWorldItemAction.complete',true));setmetatable(copied,meta)
local originalID=item.id;item.id=99999
assert(not S.placement(state,copied,'ISDropWorldItemAction.complete',true));item.id=originalID
local originalSquare=copied.sq;copied.sq={}
assert(not S.placement(state,copied,'ISDropWorldItemAction.complete',true));copied.sq=originalSquare
server=false
assert(not S.placement(state,copied,'ISDropWorldItemAction.complete',true),'client placement lost its isPlaceItem guard')
""")

    def test_cleanup_requires_verified_exact_items_and_releases_added_equipment(self):
        self.check("""
assert(not pcall(S.removePrevious,state))
state.verified=true;assert(not pcall(S.removePrevious,state))
server=true;S.release(state)
assert(state.player.primary==nil and state.player.secondary==nil and not next(state.player.worn)and equips==1)
S.removePrevious(state)
assert(not state.player.inventory:getItemById(spec.bags[3].id))
for _,ref in ipairs(spec.markers)do assert(not state.player.inventory:getItemById(ref.id))end
assert(state.player.inventory:getItemById(spec.bags[1].id)and state.player.inventory:getItemById(spec.bags[2].id))
""")


if __name__ == "__main__":
    unittest.main()
