"""Persisted identity and exact cleanup gates with the real shared journals."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).parent / 'native_queue'

HARNESS = r'''
next=nil
clock=0;getTimestampMs=function()return clock end
Perks={Mechanics='Mechanics',MetalWelding='MetalWelding'}
isServer=function()return server or false end;isClient=function()return false end
package.preload.QueueHealthEvents=function()return {encode=function()return ''end}end
local function list(values)
 values=values or {};function values:size()return #self end;function values:get(i)return self[i+1]end
 return values
end
local function remove(values,value)
 for i,entry in ipairs(values)do if entry==value then table.remove(values,i);return end end
end
local locations={}
local function bodyLocation(name)
 if not locations[name]then locations[name]=setmetatable({name=name},{__tostring=function(value)return value.name end})end
 return locations[name]
end
ResourceLocation={of=function(name)assert(type(name)=='string');return {name=name}end}
ItemBodyLocation={get=function(resource)assert(type(resource)=='table');return bodyLocation(resource.name)end}
inventory={items=list()}
function inventory:getItems()return self.items end
function inventory:getItemById(id)for _,entry in ipairs(self.items)do if entry.id==id then return entry end end end
function inventory:getItemWithIDRecursiv(id)return self:getItemById(id)or(nested and nested[id])end
function inventory:Remove(value)remove(self.items,value);value.container=nil end
local function item(id,kind,uses)
 local value={id=id,kind=kind,uses=uses,container=inventory,wornLocation=bodyLocation('base:hat')}
 function value:getID()return self.id end;function value:getFullType()return self.kind end
 function value:getCurrentUses()return self.uses end;function value:getContainer()return self.container end
 function value:getWorldItem()return self.world end;function value:getBodyLocation()return self.wornLocation end
 inventory.items[#inventory.items+1]=value;return value
end
hat=item(1,'Base.Hat')
player={x=10.25,y=20.75,z=0,primary=hat,secondary=nil,worn={hat},wornLocations={},levels={Mechanics=0,MetalWelding=0},raw={Mechanics=5,MetalWelding=7},total=12}
function player:getInventory()return inventory end
function player:getPrimaryHandItem()return self.primary end;function player:getSecondaryHandItem()return self.secondary end
function player:setPrimaryHandItem(value)self.primary=value end;function player:setSecondaryHandItem(value)self.secondary=value end
function player:getWornItems()
 local values={};for _,entry in ipairs(self.worn)do local value=entry
  values[#values+1]={getItem=function()return value end,getLocation=function()return self.wornLocations[value.id]or value.wornLocation end}
 end
 return list(values)
end
function player:removeWornItem(value)remove(self.worn,value);self.wornLocations[value.id]=nil end
function player:setWornItem(location,value)
 assert(type(location)=='table'and location.name,'restore must resolve the native saved slot')
 for i=#self.worn,1,-1 do local entry=self.worn[i]
  if (self.wornLocations[entry.id]or entry.wornLocation)==location then self.wornLocations[entry.id]=nil;table.remove(self.worn,i)end
 end
 if value then self.worn[#self.worn+1]=value;self.wornLocations[value.id]=location end
end
function player:getX()return self.x end;function player:getY()return self.y end;function player:getZ()return self.z end
function player:teleportTo(x,y,z)teleports=(teleports or 0)+1;self.x=x;self.y=y;self.z=z end
function player:setX(x)self.x=x end;function player:setY(y)self.y=y end
function player:setNextX(x)end;function player:setNextY(y)end;function player:setLastX(x)end;function player:setLastY(y)end
function player:getPerkLevel(perk)return self.levels[perk]end
function player:setPerkLevelDebug(perk,level)self.levels[perk]=level end
function player:getCharacterActions()return {size=function()return busy and 1 or 0 end}end
function player:hasPath()return false end
xp={}
function xp:getTotalXp()return player.total end;function xp:setTotalXP(n)player.total=n end
function xp:getXP(perk)return player.raw[perk]end
function xp:setXPToLevel(perk,level)player.raw[perk]=level*100 end
function xp:AddXP(perk,delta,a,b,c,d)assert(a==false and b==false and c==false and d==false);player.raw[perk]=player.raw[perk]+delta end
function player:getXp()return xp end
originalFactory=function()return item end
squares={}
local function square(x,y)
 local sq={x=x,y=y,objects=list(),special=list(),world=list()}
 function sq:getX()return self.x end;function sq:getY()return self.y end;function sq:getZ()return 0 end
 function sq:getObjects()return self.objects end;function sq:getSpecialObjects()return self.special end
 function sq:getWorldObjects()return self.world end
 function sq:transmitRemoveItemFromSquare(object,flag)publications=(publications or 0)+1 end
 squares[x..':'..y]=sq;return sq
end
repairSquare=square(30,40);salvageSquare=square(40,50)
function groundItem(id,kind)
 local value={id=id,kind=kind}
 function value:getID()return self.id end;function value:getFullType()return self.kind end
 function value:getContainer()return nil end;function value:getWorldItem()return self.world end
 local object={value=value,square=salvageSquare}
 function object:getItem()return self.value end;function object:getSquare()return self.square end
 function object:getContainer()return nil end
 function object:getObjectIndex()for i,entry in ipairs(self.square.objects)do if entry==self then return i-1 end end;return -1 end
 function object:removeFromWorld()end
 function object:removeFromSquare()remove(self.square.objects,self);remove(self.square.world,self)end
 value.world=object;salvageSquare.objects[#salvageSquare.objects+1]=object;salvageSquare.world[#salvageSquare.world+1]=object
 return object
end
foreignGround=groundItem(800,'Base.Apple');drop=groundItem(900,'Base.SteelScrap')
-- B42.21 IsoCell.getVehicles() returns a Java Set, with no indexed get().
vehicles={}
function vehicles:iterator()
 local index=0
 return {hasNext=function()return index<#vehicles end,next=function()index=index+1;return vehicles[index]end}
end
function makeVehicle(id,installedID,tag)
 local installed={getID=function()return installedID end,getCondition=function()return 76 end,getHaveBeenRepaired=function()return 1 end}
 local md={};if tag then md.VROGameplayFixtureV1=tag end
 local part={getInventoryItem=function()return installed end,getCondition=function()return 76 end,getModData=function()return md end,getItemContainer=function()return nil end}
 local vehicle={id=id,part=part}
 function vehicle:getId()return self.id end;function vehicle:isRemovedFromWorld()return self.removed or false end
 function vehicle:getPartById(name)assert(name=='EngineDoor');return self.part end
 function vehicle:getVehicleTowing()return nil end;function vehicle:getVehicleTowedBy()return nil end
 function vehicle:getMaxPassengers()return 1 end;function vehicle:getCharacter()return nil end
 function vehicle:getAnimals()return list()end;function vehicle:getPartCount()return 1 end
 function vehicle:getPartByIndex()return self.part end
 function vehicle:permanentlyRemove()vehicleRemovals=(vehicleRemovals or 0)+1;self.removed=true;remove(vehicles,self)end
 vehicles[#vehicles+1]=vehicle;return vehicle
end
repairVehicle=makeVehicle(77,500,'repair');foreignVehicle=makeVehicle(88,700,nil)
cell={getVehicles=function()return vehicles end}
function cell:getGridSquare(x,y,z)
 if unloaded then return nil end
 return squares[x..':'..y]or square(x,y)
end
getCell=function()return cell end
function player:getCurrentSquare()return cell:getGridSquare(math.floor(self.x),math.floor(self.y),self.z)end
getVehicleById=function()error('reload must identify persisted installed identity, never old wire IDs')end
ModData={get=function(key)assert(key=='VROGameplayFixtureV1');return checkpoint end}
'''

SETUP = r'''
local original=F.actor(player)
repairTorch=originalFactory()(10,'Base.BlowTorch',7)
salvageTorch=originalFactory()(11,'Base.BlowTorch',0)
mask=originalFactory()(12,'Base.WeldingMask')
player.primary=salvageTorch;player.worn={mask};player.levels={Mechanics=4,MetalWelding=4}
player.raw={Mechanics=430,MetalWelding=480};player.total=910;player.x=41;player.y=51
checkpoint={version=1,original=original,clientOriginals={client1=original},finalActor=F.actor(player),owned={
 {id=10,fullType='Base.BlowTorch'},{id=11,fullType='Base.BlowTorch'},
 {id=12,fullType='Base.WeldingMask'},{id=13,fullType='Base.SheetMetal'},{id=14,fullType='Base.SheetMetal'}},
 packet={repair={vehicleID=31,vehicleKey='repair',installedID=500,x=30,y=40,z=0},
  salvage={vehicleID=32,vehicleKey='salvage',installedID=600,x=40,y=50,z=0},
  repairTorchID=10,salvageTorchID=11,maskID=12,metalIDs={13,14}},
 receipts={{},{after={torch={uses=7}}},{},{before={ground={{id=800,fullType='Base.Apple'}}},after={torchUses=0}}},
 worlds={repair={vehicleKey='repair',vehicleID=31,removed=false,itemID=500,condition=76,itemCondition=76,hbr=1,ground={}},
  salvage={vehicleKey='salvage',vehicleID=32,removed=true,ground={{id=800,fullType='Base.Apple'},{id=900,fullType='Base.SteelScrap'}}}}}
'''


class ReloadTests(unittest.TestCase):
    def runtime(self, before_setup=''):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(HARNESS)
        for name, path in [
            ('VROGameplayFixture', ROOT / 'vro-gameplay/shared/VROGameplayFixture.lua'),
            ('QueueFixtureWorldCleanup', ROOT / 'support/QueueFixtureWorldCleanup.lua'),
            ('QueueFixtureItemCleanup', ROOT / 'support/QueueFixtureItemCleanup.lua'),
        ]:
            lua.globals().loadedModule = lua.execute(path.read_text())
            lua.execute("package.preload['%s']=function()return loadedModule end" % name)
            # Freeze each preload value before the next module is loaded.
            lua.execute("package.loaded['%s']=loadedModule" % name)
        lua.execute("F=require 'VROGameplayFixture'")
        lua.execute(before_setup)
        lua.execute(SETUP)
        lua.globals().R = lua.execute((ROOT / 'vro-gameplay/shared/VROGameplayReload.lua').read_text())
        return lua

    def test_verification_uses_exact_persisted_identity_and_actual_paid_resources(self):
        lua = self.runtime()
        lua.execute('''
        local row=R.verify(player)
        assert(row.role=='authority' and row.worlds.repair.vehicleID==77 and row.worlds.repair.itemID==500)
        assert(checkpoint.packet.repair.vehicleID==77 and row.worlds.salvage.removed)
        assert(row.resources.repairTorch.uses==7 and row.resources.salvageTorch.uses==0)
        assert(row.resources.metal[1].present==false and row.actor.x==41)
        assert(row.worlds.salvage.ground[2].id==900 and #vehicles==2)
        ''')

    def test_unloaded_neighborhood_waits_without_assertion_or_mutation(self):
        lua = self.runtime()
        lua.execute('''
        unloaded=true;local before=checkpoint.packet.repair.vehicleID
        assert(R.verify(player)==nil and R.worlds(checkpoint)==nil)
        assert(checkpoint.packet.repair.vehicleID==before and not vehicleRemovals)
        unloaded=false;assert(R.verify(player))
        ''')

    def test_cleanup_preserves_foreign_world_and_restores_exact_original_actor(self):
        lua = self.runtime()
        lua.execute('''
        R.verify(player);assert(R.cleanup(player)==nil);clock=clock+501;local receipt=R.cleanup(player)
        assert(receipt and receipt.restored and receipt.vehicles.removed[1].installedID==500)
        assert(receipt.items.removalCalls==3 and #receipt.items.removedIds==3)
        assert(receipt.ground.removedObjects==1 and receipt.ground.publicationAttempts==1)
        assert(#vehicles==1 and vehicles[1]==foreignVehicle and not foreignVehicle:isRemovedFromWorld())
        assert(#salvageSquare.world==1 and salvageSquare.world[1]==foreignGround)
        assert(#inventory.items==1 and inventory.items[1]==hat and player.primary==hat)
        assert(player.worn[1]==hat and #player.worn==1)
        assert(player.raw.Mechanics==5 and player.raw.MetalWelding==7 and player.total==12)
        assert(player.levels.Mechanics==0 and player.levels.MetalWelding==0)
        assert(player.x==10.25 and player.y==20.75 and receipt.actor.x==10.25)
        assert(R.cleanup(player)==receipt and vehicleRemovals==1 and publications==1)
        ''')

    def test_cleanup_restores_actual_saved_bag_slot_without_item_metadata(self):
        lua = self.runtime('''
        bag=originalFactory()(2,'Base.Bag_GolfBag')
        bag.getBodyLocation=function()return nil end
        bag.canBeEquipped=function()return ItemBodyLocation.get(ResourceLocation.of('base:back'))end
        player.worn[#player.worn+1]=bag
        player.wornLocations[bag.id]=ItemBodyLocation.get(ResourceLocation.of('mod:frontpack'))
        ''')
        lua.execute('''
        assert(checkpoint.original.worn[2].id==bag.id and checkpoint.original.worn[2].location=='mod:frontpack')
        checkpoint.original.worn={checkpoint.original.worn[2],checkpoint.original.worn[1]}
        R.verify(player);assert(R.cleanup(player)==nil);clock=clock+501
        local receipt=assert(R.cleanup(player))
        assert(receipt.restored and #inventory.items==2 and inventory:getItemById(2)==bag)
        assert(#player.worn==2 and bag:getBodyLocation()==nil)
        assert(tostring(player.wornLocations[bag.id])=='mod:frontpack')
        assert(player.wornLocations[bag.id]~=bag:canBeEquipped(),'restoration inferred the default bag slot')
        local found={};for _,entry in ipairs(receipt.actor.worn)do found[entry.id]=entry.location end
        assert(found[1]=='base:hat'and found[2]=='mod:frontpack')
        ''')

    def test_peer_cleanup_waits_for_recursive_inventory_absence_and_original_actor(self):
        lua = self.runtime()
        lua.execute('''
        R.verify(player);assert(R.cleanup(player)==nil);clock=clock+501;assert(R.cleanup(player))
        assert(R.cleanedActor(player,checkpoint.original,checkpoint))
        local calls,removed=publications,vehicleRemovals
        nested={[repairTorch:getID()]=repairTorch}
        assert(R.cleanedActor(player,checkpoint.original,checkpoint)==nil,'nested owned input escaped replica absence gate')
        nested=nil;player.raw.Mechanics=player.raw.Mechanics+1
        assert(R.cleanedActor(player,checkpoint.original,checkpoint)==nil,'replicated XP mismatch escaped cleanup gate')
        player.raw.Mechanics=checkpoint.original.xp.Mechanics.xp
        player.x=player.x+.25
        assert(R.cleanedActor(player,checkpoint.original,checkpoint)==nil,'moved peer escaped original-position gate')
        player.x=checkpoint.original.x;assert(R.cleanedActor(player,checkpoint.original,checkpoint))
        assert(publications==calls and vehicleRemovals==removed and #inventory.items==1,'cleanup observation repeated effects')
        ''')

    def test_incomplete_client_originals_quarantine_before_persistence_or_cleanup(self):
        lua = self.runtime()
        lua.execute('''
        checkpoint.clientOriginals=nil
        assert(not pcall(R.verify,player))
        assert(not publications and not vehicleRemovals and #inventory.items==4)
        ''')

    def test_uncertain_vehicle_or_persistence_identity_quarantines_before_cleanup(self):
        for mutation, message in [
            ("makeVehicle(99,500,'repair')", 'duplicate persisted'),
            ("makeVehicle(99,600,'salvage')", 'persisted salvage absence'),
            ("checkpoint.packet.repair.installedID=501", 'installed identity changed'),
            ("repairTorch.uses=10", 'paid torch changed'),
            ("player.raw.MetalWelding=481", 'actor inventory/equipment/XP changed'),
            ("drop.value.kind='Base.Wire'", 'salvage absence/ground changed'),
            ("repairVehicle.removed=true", 'repair condition/history/ground changed'),
        ]:
            with self.subTest(mutation=mutation):
                lua = self.runtime()
                lua.execute(mutation)
                ok, reason = lua.eval('function()return pcall(R.verify,player)end')()
                self.assertFalse(ok)
                self.assertIn(message, reason)
                lua.execute('assert(not vehicleRemovals and not publications and #inventory.items==4)')

    def test_foreign_inventory_or_vehicle_contents_block_cleanup_without_deleting_them(self):
        lua = self.runtime()
        lua.execute("R.verify(player);foreignItem=originalFactory()(100,'Base.Apple')")
        ok, reason = lua.eval('function()return pcall(R.cleanup,player)end')()
        self.assertFalse(ok)
        self.assertIn('foreign or changed actor inventory', reason)
        lua.execute('assert(inventory:getItemById(100)==foreignItem and not publications and not vehicleRemovals)')
        lua = self.runtime()
        lua.execute('R.verify(player);repairVehicle.getVehicleTowing=function()return foreignVehicle end')
        ok, reason = lua.eval('function()return pcall(R.cleanup,player)end')()
        self.assertFalse(ok)
        self.assertIn('towing changed', reason)
        lua.execute('assert(#inventory.items==4 and not publications and not vehicleRemovals)')

    def test_missing_paid_item_after_verification_blocks_cleanup(self):
        lua = self.runtime()
        lua.execute('R.verify(player);server=true;player.primary=hat;player.worn={hat};player.x=10.25;player.y=20.75;inventory:Remove(repairTorch)')
        lua.execute('assert(R.cleanup(player)==nil);clock=clock+501')
        ok, reason = lua.eval('function()return pcall(R.cleanup,player)end')()
        self.assertFalse(ok)
        self.assertIn('paid actor inventory changed', reason)
        lua.execute('assert(not publications and not vehicleRemovals)')

    def test_peer_world_only_api_never_observes_actor_inventory_or_xp(self):
        lua = self.runtime()
        lua.execute('''
        player.getInventory=function()error('peer actor inventory must not be read')end
        local row=R.worlds({packet=checkpoint.packet,worlds=checkpoint.worlds})
        assert(row.repair.itemID==500 and row.salvage.removed and row.salvage.ground[2].id==900)
        ''')

    def test_server_cleanup_waits_for_client_restore_and_never_teleports_remote_actor(self):
        lua = self.runtime()
        lua.execute('R.verify(player);server=true')
        lua.execute('assert(R.cleanup(player)==nil and not publications and not vehicleRemovals)')
        lua.execute('''
        server=false;assert(R.restoreActor(player,checkpoint.original,checkpoint)==nil);clock=clock+501
        assert(R.restoreActor(player,checkpoint.original,checkpoint));teleports=0
        player.raw.Mechanics=430;player.raw.MetalWelding=480;player.total=910
        server=true;sendRemoveItemFromContainer=function()end
        assert(R.cleanup(player)==nil);clock=clock+501;local receipt=R.cleanup(player)
        assert(receipt and receipt.restored and teleports==0 and receipt.items.noticeAttempts==3)
        ''')

    def test_local_restore_waits_for_native_quiet_and_changes_no_inventory_membership(self):
        lua = self.runtime()
        lua.execute('''
        busy=true;assert(R.restoreActor(player,checkpoint.original,checkpoint)==nil and not teleports)
        busy=false;assert(R.restoreActor(player,checkpoint.original,checkpoint)==nil)
        assert(teleports==1);clock=clock+501
        local row=R.restoreActor(player,checkpoint.original,checkpoint)
        assert(teleports==1 and row.restored and #inventory.items==4 and not publications and not vehicleRemovals)
        ''')

    def test_restore_waits_for_native_square_update_without_repeating_teleport(self):
        lua = self.runtime()
        lua.execute("""
        local native=player.getCurrentSquare
        player.getCurrentSquare=function()return salvageSquare end
        assert(R.restoreActor(player,checkpoint.original,checkpoint)==nil and teleports==1)
        clock=clock+501
        assert(R.restoreActor(player,checkpoint.original,checkpoint)==nil and teleports==1)
        player.getCurrentSquare=native;assert(R.restoreActor(player,checkpoint.original,checkpoint)==nil)
        clock=clock+501;assert(R.restoreActor(player,checkpoint.original,checkpoint)and teleports==1)
        """)


if __name__ == '__main__':
    unittest.main()
