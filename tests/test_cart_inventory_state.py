"""Exercise the read-only initial-entry endpoint against explicit native doubles."""
from pathlib import Path
import json
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT/'tests/native_queue/contributions/wooden_cart_multiplayer/lease-inventory-state.lua'
LUA = shutil.which('luajit') or shutil.which('lua')
HARNESS = r'''
local function list(values) return {size=function() return #values end,get=function(_,i) return values[i+1] end} end
local config={disposable=true,options={cart_lease_inventory=true}}
package.preload.QueueTestSelection=function() return config end
package.preload.CartMPJSON=function() return {encode=function() return '{}' end} end
local cargo={getID=function() return 99 end,getActualWeight=function() return 30 end}
local cart={getID=function() return 42 end,getFullType=function() return 'SaucedWheelbarrow.WheelbarrowWood' end,
 getInventory=function() return {getItems=function() return list({cargo}) end} end,getWorldItem=function() return nil end}
local values={cart};local native={};local queue={queue={}};local primary,secondary,path=nil,nil,false
local inventoryCalls,queueCalls=0,0
local p={getUsername=function() return 'client1' end,getOnlineID=function() return 7 end,
 getPrimaryHandItem=function() return primary end,getSecondaryHandItem=function() return secondary end,
 getInventory=function() inventoryCalls=inventoryCalls+1;return {getItems=function() return list(values) end} end,
 getCharacterActions=function() return list(native) end,hasPath=function() return path end,
 getX=function() return 100 end,getY=function() return 100 end,getZ=function() return 0 end}
ISTimedActionQueue={getTimedActionQueue=function() queueCalls=queueCalls+1;return queue end}
local worlds={};getCell=function() return {getGridSquare=function() return {getWorldObjects=function() return list(worlds) end} end} end
getTimestampMs=function() return 1000 end
-- Endpoint reads must never instantiate an equipment lifetime before real equip.
cartLeaseLifetime=function() error('unexpected lifetime read') end
local M=dofile(MODULE)
local cell=getCell
getCell=function() return {getGridSquare=function() return nil end} end
assert(not M.loaded(p));getCell=cell;assert(M.loaded(p))
local unheld=M.emit('client1','unheld',p,cart,'source')
assert(unheld.inventoryCount==1 and unheld.luaActions==0 and unheld.primaryID==-1)
primary=cart;secondary=cart
local beforeInv,beforeQueue=inventoryCalls,queueCalls
local observer=M.emit('client2','held',p,cart,'source')
assert(inventoryCalls==beforeInv and queueCalls==beforeQueue)
assert(observer.inventoryCount==nil and observer.luaActions==nil and observer.queueScope=='remote-native-only')
local server=M.emit('server','held',p,cart,'source')
assert(server.guarded and server.luaActions==nil and server.queueScope=='native-server-only')
local function refused() assert(not pcall(M.emit,'client1','held',p,cart,'source')) end
values={cart,cart};refused();values={cart}
native={42};refused();native={}
queue.queue={42};refused();queue.queue={}
path=true;refused();path=false
secondary=nil;refused();secondary=cart
worlds={{getItem=function() return cart end}};refused();worlds={}
assert(M.emit('client1','held',p,cart,'source').handSameItem)
print('INVENTORY_ENDPOINT_PASS')
'''


@unittest.skipUnless(LUA, 'Lua interpreter required')
class InventoryEndpointTests(unittest.TestCase):
    def test_actual_client_setup_uses_explicit_player_slot_only_for_inventory_extension(self):
        client=MODULE.with_name('client.lua')
        code=r"""
local selected=SELECTED
package.preload.QueueTestSelection=function() return {disposable=true,cases={'owner_observer_motion'},ffmpeg='/fixture/ffmpeg',videoRoot={client1='/fixture/video'},options={cart_lease_inventory=selected}} end
for _,name in ipairs({'SaucedCarts/Core','SaucedCarts/CartVisuals','CartLeaseInventoryState'}) do package.preload[name]=function() return {} end end
package.preload.CartMPJSON=function() return {emit=function() end,encode=function() return '{}' end} end
local callbacks={};Events={}
for _,name in ipairs({'OnConnectFailed','OnServerCommand','OnGameStart','OnTick'}) do Events[name]={Add=function(fn) callbacks[name]=fn end} end
local core=setmetatable({},{__index=function() return function() end end})
getCore=function() return core end
PZAPI={ModOptions={getOptions=function() return {getOption=function() return {setValue=function() end} end} end}}
getFileReader=function() return {readLine=function() return 'client1' end,close=function() end} end
local cart={getFullType=function() return 'SaucedWheelbarrow.WheelbarrowWood' end}
local p={getUsername=function() return 'client1' end,setGodMod=function() end,setGhostMode=function() end,setAutoDrink=function() end,
 getPrimaryHandItem=function() return cart end,getSecondaryHandItem=function() return cart end,
 getPerkLevel=function() return 10 end,updateHandEquips=function() end}
getPlayer=function() return p end
getOnlinePlayers=function() return {size=function() return 1 end,get=function() return p end} end
getTimestampMs=function() return 2000 end
Perks={Sprinting={}};cartLabDrive=function() end;cartLabGait=function() end
local sends={}
sendClientCommand=function(a,b,c,d)
 if selected then assert(a==p and b=='CartMP' and type(c)=='string' and type(d)=='table');sends[#sends+1]=c
 else assert(a=='CartMP' and type(b)=='string' and type(c)=='table' and d==nil);sends[#sends+1]=b end
end
print=function(value) assert(not value:find('[QUEUE_TEST] FAIL',1,true),value) end
dofile(CLIENT);callbacks.OnGameStart();callbacks.OnTick()
assert(sends[1]=='Ready')
local function set(name,value)
 for i=1,40 do local key=debug.getupvalue(callbacks.OnTick,i);if not key then break end
  if key==name then debug.setupvalue(callbacks.OnTick,i,value);return end
 end
 error('Missing actual client upvalue '..name)
end
set('setup',{size=31,bankVersion=3});set('prepared',true);set('inventoryHeld',true);set('lastSample',2000)
callbacks.OnTick();assert(sends[2]=='Armed' and #sends==2)
"""
        for selected in ('true','false'):
            result=subprocess.run([LUA,'-e',code.replace('SELECTED',selected).replace('CLIENT',json.dumps(str(client)))],
                                  capture_output=True,text=True,timeout=15)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_server_rejects_missing_native_source_before_creating_any_fixture_items(self):
        code=r"""
local command;Events={}
for _,name in ipairs({'OnServerStarted','OnClientCommand','OnTick'}) do Events[name]={Add=function(fn) if name=='OnClientCommand' then command=fn end end} end
package.preload.QueueTestSelection=function() return {disposable=true,options={cart_lease_inventory=true}} end
package.preload.CartMPJSON=function() return {} end
package.preload.CartLeaseInventoryState=function() return {loaded=function() error('Readiness before source validation') end} end
package.preload.CartMPPlacement=function() error('Placement before source validation') end
local p={getUsername=function() return 'client1' end,getCurrentSquare=function() return {} end,
 getInventory=function() error('Fixture items accessed before native source validation') end}
cartLeaseSource=function(player) assert(player==p);return nil end
local failures=0
print=function(line) assert(line:find('Initial inventory owner transport missing',1,true),line);failures=failures+1 end
dofile(SERVER);command('CartMP','Ready',p,{});command('CartMP','Ready',p,{})
assert(failures==2)
"""
        result=subprocess.run([LUA,'-e',code.replace('SERVER',json.dumps(str(MODULE.with_name('server.lua'))))],
                              capture_output=True,text=True,timeout=15)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_actual_counts_queues_and_remote_scope_without_lifetime_side_effect(self):
        result = subprocess.run([LUA,'-e','local MODULE='+json.dumps(str(MODULE))+'\n'+HARNESS],
                                capture_output=True,text=True,timeout=15)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('INVENTORY_ENDPOINT_PASS',result.stdout)
