"""Execute the owned server invalidation callback with exact native API doubles."""
import json
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'tests/native_queue/contributions/wooden_cart_multiplayer/action-invalidation.lua'
LUA=shutil.which('luajit') or shutil.which('lua')
HARNESS=r'''
local cb;Events={OnClientCommand={Add=function(fn) cb=fn end}}
isServer=function() return true end
local rows={};package.preload.QueueTestSelection=function() return {disposable=true,options={cart_action_invalidation=true}} end
package.preload.CartMPJSON=function() return {encode=function(v) if type(v)=='string' then return '"'..v..'"' end return tostring(v) end} end
getTimestampMs=function() return 1000 end
print=function(row) assert(not row:find(' ERROR ',1,true),row);rows[#rows+1]=row end
local function list(values) return {size=function() return #values end,get=function(_,i) return values[i+1] end} end
local cargo={getID=function() return 99 end,getActualWeight=function() return 30 end}
local cart={getID=function() return 42 end,getInventory=function() return {getItems=function() return list({cargo}) end} end,
 getWorldItem=function(self) return self.world end,setWorldItem=function(self,v) self.world=v end,
 getWorldZRotation=function() return 0 end,setWorldZRotation=function() end}
local primary,secondary=cart,cart
local p={getUsername=function() return 'client1' end,getOnlineID=function() return 7 end,
 getPrimaryHandItem=function() return primary end,getSecondaryHandItem=function() return secondary end,
 getX=function() return 100 end,getY=function() return 100 end,getZ=function() return 0 end,
 getCharacterActions=function() return list({}) end,hasPath=function() return false end,
 getInventory=function() return {getItems=function() return list(primary and {cart} or {}) end} end}
local observer={getUsername=function() return 'client2' end,getOnlineID=function() return 8 end}
getOnlinePlayers=function() return list({p,observer}) end
local ownerConnection={};local nativeScope=false;local source=true
cartLeaseSource=function(player) assert(nativeScope);return source and ownerConnection or nil end
cartLeaseTarget=function(id) assert(nativeScope);return id==7 and p or id==8 and observer or nil end
cartLeaseOwnerConnection=function(player) assert(nativeScope and player==p);return ownerConnection end
local groundObjects={};local mutations=0;local oldWorld
local square={getX=function() return 100 end,getY=function() return 100 end,getZ=function() return 0 end,
 getWorldObjects=function() return list(groundObjects) end,getObjects=function() return list(groundObjects) end}
function square:transmitRemoveItemFromSquare(world)
 assert(nativeScope and world==oldWorld and cart.world==world);mutations=mutations+1;groundObjects={}
end
function square:removeWorldObject(world) assert(world==oldWorld) end
local destination={TreatAsSolidFloor=function() return true end,getWorldObjects=function() return list({}) end}
function destination:AddWorldInventoryItem(item,x,y,z,auto)
 assert(nativeScope and item==cart and x==.5 and y==.5 and z==0 and auto==false)
 cart.world={getSquare=function() return destination end,transmitCompleteItemToClients=function() end}
 groundObjects={cart.world};cart.world.getItem=function() return cart end
 return cart
end
getCell=function() return {getGridSquare=function(_,x,y,z)
 if x==102 and y==100 then return destination end
 return x==100 and y==100 and square or {getWorldObjects=function() return list({}) end}
end} end
local native={token='10000000-0000-4000-8000-000000000001',transaction=1,cart=42,owner=7,
 stage='terminal',reason='completed',nativeState='Done',accepted=true,admittedBindingValid=true}
cartActionAdmission=function(player)
 assert(nativeScope and player==p)
 local row={};for k,v in pairs(native) do row[k]=v end
 if mutations>0 then row.stage='terminal';row.reason='item-invalid';row.nativeBindingValid=false end
 return row
end
local stops=0
cartActionInvalidationStop=function(player,token,epoch)
 assert(nativeScope and player==p and token==native.token and epoch==123 and mutations==1)
 stops=stops+1;return true
end
local sent={}
sendServerCommand=function(player,module,command,args) assert(nativeScope);sent[#sent+1]=command end
local function command(name,args)
 nativeScope=true;cb('CartActionInvalidation',name,p,args or {owner=7});nativeScope=false
end
dofile(SOURCE)
source=false;command('Begin');assert(mutations==0 and stops==0 and #sent==0)
-- The rejected callback must not initialize or mutate the experiment.
source=true;command('Begin');assert(sent[1]=='Init')
primary=nil;secondary=nil
oldWorld={square=square,getItem=function() return cart end,getSquare=function(self) return self.square end}
cart.world=oldWorld;groundObjects={oldWorld}
command('Released',{owner=7,token=native.token,transaction=1})
native.token='20000000-0000-4000-8000-000000000002';native.transaction=-128
native.stage='accepted';native.reason='native-accepted';native.nativeState='Accept';native.nativeBindingValid=true
native.actionEpoch=123;native.tableEpoch=124;native.itemEpoch=125;native.worldEpoch=126;native.kind='ToolkitWoodCartPickup'
command('Inspect',{owner=7,token=native.token,transaction=-128})
source=false;command('Invalidate',{owner=7,token=native.token,transaction=-128});assert(mutations==0 and stops==0)
source=true;command('Invalidate',{owner=7,token=native.token,transaction=-128})
assert(mutations==1 and stops==1 and cart.world~=oldWorld and oldWorld:getSquare()==square)
assert(sent[#sent]=='Moved')
assert(not primary and not secondary and cargo:getID()==99)
'''


@unittest.skipUnless(LUA,'Lua interpreter required')
class InvalidationControllerTests(unittest.TestCase):
    def test_missing_transport_cannot_mutate_and_exact_world_loss_precedes_native_stop(self):
        # Expected refused callbacks are emitted, not suppressed by a permissive source double.
        code=HARNESS.replace("assert(not row:find(' ERROR ',1,true),row);",'')
        result=subprocess.run([LUA,'-e','local SOURCE='+json.dumps(str(SOURCE))+'\n'+code],capture_output=True,text=True,timeout=15)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
