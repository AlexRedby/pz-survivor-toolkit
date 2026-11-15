"""Detached-source fixtures preserve contents without granting stale-handle authority."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

SHARED=Path(__file__).resolve().parent/'native_queue/wring-clothing/shared'


class WringSourceFixtureTests(unittest.TestCase):
    def runtime(self):
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.execute("package.loaded.QueueEnergyPlacement={atCentered=function()return true end}")
        lua.globals().F=lua.execute((SHARED/'QueueWringClothing.lua').read_text())
        lua.execute("package.loaded.QueueWringClothing=F")
        lua.globals().C=lua.execute((SHARED/'QueueWringReturnControls.lua').read_text())
        lua.execute('''
function isClient()return false end
function isServer()return false end
function getTimestampMs()return 123 end
function instanceof(value,kind)return value.class==kind end
function getClassSimpleName()return 'ItemBodyLocation'end
local location=setmetatable({},{__tostring=function()return 'base:socks'end})
local function container()
 local c={values={}}
 function c:getItems()return{size=function()return #self.values end,get=function(_,index)return self.values[index+1]end}end
 function c:getItemById(id)for _,value in ipairs(self.values)do if value:getID()==id then return value end end end
 function c:Remove(item)for index,value in ipairs(self.values)do if value==item then table.remove(self.values,index);item.owner=nil;return end end;error('duplicate or foreign removal')end
 return c
end
root=container();source=container();bag={class='InventoryContainer',owner=root,getID=function()return 20 end,getFullType=function()return 'Base.Bag_Military'end,
 getContainer=function(self)return self.owner end,getItemContainer=function()return source end,canBeEquipped=function()return 'Back'end}
root.values={bag};local worn=bag
player={getInventory=function()return root end,getWornItems=function()return{contains=function(_,item)return worn==item end,getItemById=function(_,id)return worn and worn:getID()==id and worn or nil end}end,
 removeWornItem=function(_,item)if worn==item then worn=nil end end,getWornItem=function()return worn end}
state={player=player,source=source,bag=bag,items={},ids={case='worn-bag-unavailable',mode='toolkit',restoration=true,returnControl='unavailable',origin={},source={kind='worn-bag',bag=20,world=false},items={}}}
for index,name in ipairs(F.names)do
 local owner=name=='cancelled'and source or root
 local item={class='Clothing',id=index,owner=owner,wetness=name=='cancelled'and 100 or name=='target'and 99 or 10}
 function item:getID()return self.id end
 function item:getFullType()return 'Base.Socks_Ankle'end
 function item:getContainer()return self.owner end
 function item:getWetness()return self.wetness end
 function item:getActualWeight()return .1 end
 function item:getBodyLocation()return location end
 function item:getWeight()return .1+self.wetness*.00025 end
 function item:getUnequippedWeight()return .1 end
 state.items[name]=item;owner.values[#owner.values+1]=item
 state.ids.items[name]={id=index,type=item:getFullType(),cap=10,nativeShoe=false,bodyLocation='base:socks',bodyLocationClass='ItemBodyLocation',initial=100,weight=.1}
end
''')
        return lua

    def test_authority_detach_preserves_exact_contents_and_paid_root_items(self):
        lua=self.runtime()
        lua.execute('''
local before=F.snapshot(state);assert(not before.sourceDetached and before.items.cancelled.counts.actor==1)
local value=F.sourceLost(state)
assert(value.bagRootBefore and value.bagWornBefore and not value.bagRootAfter and not value.bagWornAfter)
assert(value.scope=='detached-retained-fixture-bag'and value.root and value.authority)
assert(#value.contentsBefore==1 and #value.contentsAfter==1 and value.contentsAfter[1].id==state.items.cancelled:getID())
local after=F.snapshot(state)
assert(after.sourceDetached and after.items.target.counts.root==1 and after.items.cancelled.counts.actor==0 and after.items.cancelled.counts.source==1)
state.items.target.wetness=10
assert(F.verify(state),'real final observer rejected conserved detached-source outcome')
F.dispose(state)
assert(#root.values==0 and #source.values==0,'cleanup lost track of detached or retained root items')
''')

    def test_unequipping_or_forging_detached_flag_does_not_establish_source_loss(self):
        lua=self.runtime()
        lua.execute('''
player:removeWornItem(bag,false);state.detachedSource=true
assert(root:getItemById(20)==bag)
assert(not pcall(F.snapshot,state),'unworn but still carried bag became unavailable')
''')

    def test_duplicate_root_identity_in_detached_contents_remains_rejected(self):
        lua=self.runtime()
        lua.execute('''
F.sourceLost(state)
local original=state.items.target;local copy={class='Clothing',getID=original.getID,getFullType=original.getFullType,getContainer=function()return source end,id=original.id}
source.values[#source.values+1]=copy
assert(not pcall(F.snapshot,state),'stale detached duplicate silently replaced canonical root garment')
''')

    def test_replica_waits_for_native_removal_without_mutating_client_inventory(self):
        lua=self.runtime()
        lua.execute('''
function isClient()return true end
profile={controlEvidence={kind='unavailable'}}
local receipt={case=state.ids.case,itemId=state.ids.items.target.id,itemType='Base.Socks_Ankle',bagId=20,bagType='Base.Bag_Military',
 bagRootBefore=true,bagWornBefore=true,bagRootAfter=false,bagWornAfter=false,root=true,authority=true,scope='detached-retained-fixture-bag'}
C.sourceAccepted(profile,state,receipt)
assert(root:getItemById(20)==bag and not state.detachedSource and not C.poll(profile,state),'receipt pretended removal or changed client inventory')
player:removeWornItem(bag,false)
assert(not C.poll(profile,state),'partial worn update was treated as full source loss')
root:Remove(bag)
assert(C.poll(profile,state)and profile.controlEvidence.detachedConfirmed and state.detachedSource)
local proof=profile.controlEvidence.replica
assert(proof.bagAbsentRoot and proof.bagAbsentWorn and proof.rootTarget and proof.sourceRetained)
''')

    def test_client_and_duplicate_authority_cannot_manufacture_source_loss(self):
        lua=self.runtime()
        lua.execute('''
function isClient()return true end
assert(not pcall(F.sourceLost,state))
assert(root:getItemById(20)==bag)
function isClient()return false end
F.sourceLost(state)
assert(not pcall(F.sourceLost,state))
''')


if __name__=='__main__':unittest.main()
