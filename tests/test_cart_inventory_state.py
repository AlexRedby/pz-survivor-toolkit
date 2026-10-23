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
    def test_actual_counts_queues_and_remote_scope_without_lifetime_side_effect(self):
        result = subprocess.run([LUA,'-e','local MODULE='+json.dumps(str(MODULE))+'\n'+HARNESS],
                                capture_output=True,text=True,timeout=15)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('INVENTORY_ENDPOINT_PASS',result.stdout)
