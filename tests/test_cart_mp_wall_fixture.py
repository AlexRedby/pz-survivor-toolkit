"""Disposable Host wall fixture geometry; Lua doubles, without a game launch."""
import json
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'tests/native_queue/contributions/wooden_cart_multiplayer'
LUA = shutil.which('luajit') or shutil.which('lua')

HARNESS = r'''
-- Native Kahlua has pairs but does not expose the standard next global.
next=nil
local config={disposable=true,kind='mp',options={mp_host=true,cart_wall_exit='left'}}
package.preload.QueueTestSelection=function() return config end
local mode='empty';local server=true;local client=false;local fresh=true
isServer=function() return server end;isClient=function() return client end;cartMPPadHost=function() return fresh end
IsoFlagType={collideW='W',collideN='N'}
local floorSprite='carpentry_02_57';local wallSprite='walls_exterior_wooden_01_0'
local function list(values)
 values=values or {};values.size=function(self) return #self end;values.get=function(self,i) return self[i+1] end;return values
end
local function properties(w,n)
 return {has=function(_,flag) return flag=='W' and w or flag=='N' and n or false end}
end
local sprite={getProperties=function() return properties(mode~='bad-W',mode=='bad-N') end}
getSprite=function(name) assert(name==wallSprite);if mode=='missing-sprite' then return nil end;return sprite end
local writes,floorCount,wallAdds,wallRemoves=0,0,0,0
local upper={};local empty=list();local occupied=list({{}});local chunk={};local cell={}
local function object(name,spriteObject)
 return {getSpriteName=function() return name end,getSprite=function() return spriteObject end}
end
local function square(x,y)
 local sq={objects=list(),x=x,y=y}
 function sq:getFloor() return self.floor end
 function sq:TreatAsSolidFloor() return self.floor~=nil end
 function sq:getObjects() return self.objects end
 function sq:getSpecialObjects() return empty end
 function sq:getWorldObjects() return empty end
 function sq:getStaticMovingObjects() return empty end
 function sq:getMovingObjects() return empty end
 function sq:getRoom() return nil end
 function sq:isVehicleIntersecting() return false end
 function sq:addFloor(name)
  assert(name==floorSprite);writes=writes+1;floorCount=floorCount+1
  self.floor=object(name);self.objects[#self.objects+1]=self.floor;return self.floor
 end
 function sq:testCollideAdjacent(_,dx,dy,z)
  assert(z==0)
  if mode=='missing-collision' then return false end
  if dy~=0 then return false end
  local target=dx==-1 and self or upper[(self.x+1)..','..self.y]
  if target then for _,value in ipairs(target.objects) do
   if value:getSpriteName()==wallSprite then return true end
  end end
  return false
 end
 function sq:transmitAddObjectToSquare(value,index)
  assert(index==-1);writes=writes+1;wallAdds=wallAdds+1;self.objects[#self.objects+1]=value
 end
 function sq:transmitRemoveItemFromSquare(value,multiple)
  assert(multiple==false and value~=self.floor,'Floor or multistile removal forbidden')
  for i,entry in ipairs(self.objects) do if entry==value then
   table.remove(self.objects,i);writes=writes+1;wallRemoves=wallRemoves+1;return i-1
  end end
  return -1
 end
 return sq
end
local ground={getX=function() return 0 end,getY=function() return 0 end,getZ=function() return 0 end}
function cell:getChunkForGridSquare(x,y,z)
 assert(z==0)
 if mode=='unloaded' and x==32 and y==32 then return nil end
 return chunk
end
function cell:getGridSquare(x,y,z)
 if z==0 then
  if mode=='ground-unloaded' and x==32 and y==32 then return nil end
  return ground
 end
 assert(z==7)
 if x==32 and y==32 and mode:sub(1,5)=='halo-' then
  local bad=square(x,y)
  local kind=mode:sub(6)
  if kind=='floor' then bad.floor={} end
  if kind=='object' then bad.objects=occupied end
  if kind=='special' then bad.getSpecialObjects=function() return occupied end end
  if kind=='world' then bad.getWorldObjects=function() return occupied end end
  if kind=='corpse' then bad.getStaticMovingObjects=function() return occupied end end
  if kind=='actor' then bad.getMovingObjects=function() return occupied end end
  if kind=='room' then bad.getRoom=function() return {} end end
  if kind=='vehicle' then bad.isVehicleIntersecting=function() return true end end
  return bad
 end
 return upper[x..','..y]
end
function cell:createNewGridSquare(x,y,z)
 assert(z==7);writes=writes+1
 local sq=square(x,y);upper[x..','..y]=sq;return sq
end
function cell:setCacheGridSquare(x,y,z,sq) assert(z==7 and upper[x..','..y]==sq);writes=writes+1 end
function cell:setCacheChunk(value) assert(value==chunk);writes=writes+1 end
getCell=function() return cell end
IsoObject={new=function(c,sq,s) assert(c==cell and s==sprite);return object(wallSprite,s) end}
local player={getCurrentSquare=function() return ground end}
local wall
package.preload.CartMPWall=function() wall=dofile(WALL);return wall end
local place=assert(dofile(PLACEMENT))
'''


@unittest.skipUnless(LUA, 'Requires Lua or LuaJIT')
class CartMPWallFixtureTests(unittest.TestCase):
    def run_lua(self, code):
        source = HARNESS.replace('WALL', json.dumps(str(SOURCE / 'wall.lua'))).replace(
            'PLACEMENT', json.dumps(str(SOURCE / 'placement.lua')))
        result = subprocess.run([LUA, '-e', source + '\n' + code], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_whole_footprint_and_halo_preflight_has_zero_writes(self):
        self.run_lua(r'''
for _,value in ipairs({'halo-floor','halo-object','halo-special','halo-world','halo-corpse',
 'halo-actor','halo-room','halo-vehicle','missing-sprite','bad-W','bad-N'}) do
 mode=value;local ok=pcall(place,player)
 assert(not ok and writes==0 and floorCount==0 and wallAdds==0,'Unsafe preflight wrote: '..value)
end
for _,value in ipairs({'not-server','client','not-fresh','wrong-side'}) do
 mode='empty';server=value~='not-server';client=value=='client';fresh=value~='not-fresh'
 config.options.cart_wall_exit=value=='wrong-side' and 'south' or 'left'
 local ok=pcall(place,player);assert(not ok and writes==0,'Unsafe guard wrote: '..value)
end
''')

    def test_unloaded_wall_ground_waits_without_writes_then_retries(self):
        for unavailable in ('unloaded', 'ground-unloaded'):
            with self.subTest(unavailable=unavailable):
                self.run_lua("mode=" + json.dumps(unavailable) + r'''
assert(place(player)==nil and writes==0 and floorCount==0 and wallAdds==0,
 'Transient native ground readiness must wait without edits')
mode='empty';local area=assert(place(player),'Loaded ground retry did not create fixture')
assert(floorCount==3969 and wallAdds==49 and wall.receipt(area).ready and next==nil,
 'Readiness retry created duplicate or incomplete geometry')
''')

    def test_both_sides_native_receipts_and_owned_only_cleanup(self):
        for side in ('left', 'right'):
            with self.subTest(side=side):
                self.run_lua("config.options.cart_wall_exit=" + json.dumps(side) + r'''
local area=place(player)
assert(area.bankVersion==4 and area.size==63 and area.minX==-31 and area.minY==-31 and area.z==7)
assert(area.wallX==-3 and area.wallMinY==-24 and area.wallMaxY==24 and area.ownedWalls==49 and area.wallSprite==wallSprite)
assert(area.x==area.wallX+2.8 and area.y==.5 and area.wallSide==config.options.cart_wall_exit)
assert(area.initialHeading==(area.wallSide=='left' and .75 or -.75)*math.pi)
assert(floorCount==3969 and wallAdds==49 and next==nil)
local before=writes
assert(not pcall(wall.preflight,area) and writes==before,'Owned guard failed without next')
local receipt=wall.receipt(area);assert(receipt.ready and receipt.floors==3969 and receipt.walls==49)
server=false;client=true
local observer={};for key,value in pairs(area) do observer[key]=value end;observer.x=area.x+2;observer.y=area.y+3
assert(wall.receipt(observer).ready,'Client receipt must not require owner position or private identity')
assert(not pcall(wall.cleanup),'Client mutated server-owned walls')
server=true;client=false
local foreign=object('foreign-decoration');local far=upper['20,20'];far.objects[#far.objects+1]=foreign
assert(wall.cleanup()==49 and wallRemoves==49 and floorCount==3969 and #far.objects==2 and far.objects[2]==foreign)
assert(wall.cleanupReady(observer) and wall.cleanup()==0,'Cleanup did not preserve floor geometry')
''')

    def test_receipt_rejects_missing_wrong_or_noncolliding_geometry(self):
        self.run_lua(r'''
local area=place(player)
area.wallSprite='wrong-wall';assert(not pcall(wall.receipt,area),'Wrong descriptor wall sprite accepted')
area.wallSprite=nil;assert(not pcall(wall.receipt,area),'Missing descriptor wall sprite accepted')
area.wallSprite=wallSprite
local target=upper['-3,24'];local last=target.objects[2];local sq=upper['31,31'];local oldFloor=sq.floor
sq.floor=nil;assert(not wall.receipt(area).ready);sq.floor=oldFloor
last.getSpriteName=function() return 'wrong-wall' end;assert(not wall.receipt(area).ready)
last.getSpriteName=function() return wallSprite end
mode='bad-W';assert(not wall.receipt(area).ready);mode='bad-N';assert(not wall.receipt(area).ready)
mode='missing-collision';assert(not wall.receipt(area).ready);mode='empty'
target.objects[#target.objects+1]=object(wallSprite,sprite);assert(not wall.receipt(area).ready);table.remove(target.objects)
assert(wall.receipt(area).ready)
''')

    def test_cleanup_refuses_foreign_replacement_before_any_removal(self):
        self.run_lua(r'''
local area=place(player);local target=upper['-3,24'];local original=target.objects[2]
target.objects[2]=object(wallSprite,sprite)
assert(not pcall(wall.cleanup) and wallRemoves==0,'Cleanup removed another wall by matching sprite')
assert(not wall.cleanupReady(area));target.objects[2]=original
assert(wall.cleanup()==49 and wall.cleanupReady(area))
''')


if __name__ == '__main__':
    unittest.main()
