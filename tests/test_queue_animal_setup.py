"""Animal setup uses reachable native squares and observed teleport receipts."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
LUA = ROOT / 'tests/native_queue/contributions/animal-trailer/lua'


class AnimalSetupTests(unittest.TestCase):
    def run_lua(self, code, *sources):
        lua = shutil.which('lua5.4') or shutil.which('lua') or shutil.which('luajit')
        if not lua:
            self.skipTest('Lua interpreter unavailable')
        result = subprocess.run([lua, '-', *map(str, sources)], input=code, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_start_square_rejects_unsafe_neighbors_and_never_crosses_a_fence(self):
        self.run_lua(r'''
local movement=dofile(arg[1])
local squares={}
local function square(x,y)
 local s={x=x,y=y,free=true,floor=true,outside=true,vehicle=false,reachable=true,blocked=false}
 function s:getX()return self.x end
 function s:getY()return self.y end
 function s:getZ()return 0 end
 function s:getFloor()return self.floor end
 function s:isOutside()return self.outside end
 function s:isFree(occupants)assert(occupants==true);return self.free end
 function s:isVehicleIntersecting()return self.vehicle end
 function s:canReachTo(entry)assert(entry==squares['10,20']);return self.reachable end
 function s:testCollideAdjacent(actor,dx,dy,z)
  assert(actor==nil and dx==10-self.x and dy==20-self.y and z==0)
  return self.blocked
 end
 squares[x..','..y]=s;return s
end
function getSquare(x,y,z)assert(z==0);return squares[x..','..y]end
local point={getX=function()return 10.2 end,getY=function()return 20.7 end}
local vehicle={getAreaCenter=function(self,name)assert(name=='AnimalEntry');return point end,getZ=function()return 0 end}
for x=9,11 do for y=19,21 do square(x,y)end end
local entry=squares['10,20']
assert(movement.startSquare(vehicle)==entry,'the usable entry itself must beat a farther neighbor')
entry.vehicle=true
squares['9,19'].free=false
squares['9,20'].floor=false
squares['9,21'].vehicle=true
squares['10,19'].blocked=true
squares['10,21'].reachable=false
squares['11,19'].outside=false
local safe=squares['11,20']
assert(movement.startSquare(vehicle)==safe,'occupied/no-floor/vehicle/wall/unreachable/inside candidates must be rejected')
safe.blocked=true;squares['11,21'].reachable=false
square(12,20)
assert(movement.startSquare(vehicle)==nil,'a distant square beyond the fence must not revive a blocked setup')
squares['10,20']=nil
assert(movement.startSquare(vehicle)==nil,'unloaded AnimalEntry must fail closed')
point=nil
assert(movement.startSquare(vehicle)==nil,'missing vehicle area must fail closed')
''', LUA / 'shared/QueueAnimalMovement.lua')

    def test_staged_position_requires_the_current_square_and_native_reach(self):
        self.run_lua(r'''
local movement=dofile(arg[1])
local target={x=10.5,y=20.5,z=0}
local position={x=10.5,y=20.5,z=0}
local current
local function square(x,y,z)
 return {getX=function()return x end,getY=function()return y end,getZ=function()return z end}
end
local entry=square(10,20,0)
local reachable=true
entry.canReachTo=function(self,to)assert(to==entry);return reachable end
local player={getX=function()return position.x end,getY=function()return position.y end,getZ=function()return position.z end,
 getSquare=function()return current end}
local vehicle={getAreaCenter=function()return {getX=function()return 10.5 end,getY=function()return 20.5 end}end,getZ=function()return 0 end}
function getSquare()return entry end
luautils={getCorrectSquareForWall=function(owner,to)assert(owner==player and to==entry);return entry end}
assert(not movement.stagedAt(player,target),'matching coordinates without a loaded square are not arrival')
for _,wrong in ipairs({square(9,20,0),square(10,19,0),square(10,20,1)})do
 current=wrong;assert(not movement.stagedAt(player,target),'stale square must not pass coordinate-only arrival')
end
current=entry;assert(movement.stagedAt(player,target) and movement.nearEntry(player,vehicle))
reachable=false;assert(not movement.nearEntry(player,vehicle),'a high fence cannot count as native entry reach')
reachable=true;position.x=10.651
assert(not movement.stagedAt(player,target),'arrival tolerance must remain 0.15')
position.x=10.5;position.z=1
assert(not movement.stagedAt(player,target) and not movement.nearEntry(player,vehicle),'wrong floor must fail')
''', LUA / 'shared/QueueAnimalMovement.lua')

    def test_actual_server_setup_requires_owned_receipt_and_observed_arrival(self):
        self.run_lua(r'''
local movement=dofile(arg[2])
package.preload.QueueAnimalMovement=function()return movement end
package.preload.QueueAnimalOwnership=function()return {}end
local function list(values)return {size=function()return #values end,get=function(self,i)return values[i+1]end}end
local function events(target)return setmetatable({},{__index=function(self,name)
 local event={Add=function(fn)target[name]=fn end};self[name]=event;return event
end})end
local function run(mode)
 local callbacks,replies,squares,quarantines={}, {}, {}, {}
 local now,issued=0,0
 local position={x=1.25,y=2.75,z=0}
 local current
 local function square(x,y,vehicle)
  local s={getX=function()return x end,getY=function()return y end,getZ=function()return 0 end,
   getFloor=function()return {getSprite=function()return {getName=function()return 'street'end}end}end,
   isOutside=function()return true end,isFree=function(self,occupants)assert(occupants==true);return true end,
   isVehicleIntersecting=function()return vehicle or false end,canReachTo=function()return true end,
   testCollideAdjacent=function()return false end}
  squares[x..','..y]=s;return s
 end
 local original=square(1,2)
 square(10818,10118)
 local entry=square(10820,10120,true)
 local start=square(10819,10119)
 if mode=='blocked' then squares['10819,10119']=nil end
 current=original
 local animals={}
 local vehicle={getSquare=function()return entry end,getId=function()return 7 end,getZ=function()return 0 end,
  getAreaCenter=function()return {getX=function()return 10820.2 end,getY=function()return 10120.2 end}end,
  getAnimals=function()return list(animals)end,addAnimalInTrailer=function(self,a)animals[#animals+1]=a end}
 local player={getX=function()return position.x end,getY=function()return position.y end,getZ=function()return position.z end,
  getSquare=function()return current end,getPrimaryHandItem=function()return nil end,getSecondaryHandItem=function()return nil end}
 Events=events({});AnimalTrailerFixtureConfig={cases={'timer-shared'},timerObservationMs=0}
 luautils={getCorrectSquareForWall=function(owner,to)assert(owner==player and to==entry);return entry end}
 function getSquare(x,y,z)return squares[x..','..y]end
 function getCell()return {}end
 function getTimestampMs()return now end
 function addVehicleDebug()return vehicle end
 IsoDirections={N=1}
 AnimalDefinitions={getDef=function()return {getBreedByName=function()return {}end}end}
 local identity=100
 function addAnimal()
  identity=identity+1;local id=identity
  return {getAnimalID=function()return id end,getOnlineID=function()return id+100 end,
   getData=function()return {}end,setWild=function()end,addToWorld=function()end}
 end
 function animalFixtureRestorePosition(owner,x,y,z)
  assert(owner==player and x==10819.5 and y==10119.5 and z==0,'only the server-selected clear square may be issued')
  issued=issued+1;return mode=='nativeFailure' and 'FAIL unavailable' or 'issued'
 end
 local context={case='timer-shared',events=events(callbacks),quarantine=function(reason)quarantines[#quarantines+1]=reason end,reply=function(owner,command,args)
  assert(owner==player);replies[#replies+1]={command=command,args=args}
 end}
 package.loaded.QueueAnimalLifecycle=nil
 package.preload.QueueAnimalLifecycle=function()return {start=function(cfg,factory,server)assert(server);factory(context)end}end
 dofile(arg[1])
 local function command(name,args,owner)return callbacks.OnClientCommand('AnimalTrailerBaseline',name,owner or player,args or {})end
 local function count(name)local n=0;for _,reply in ipairs(replies)do if reply.command==name then n=n+1 end end;return n end
 assert(not pcall(command,'VerifyStartPosition'),'unissued setup receipt must fail')
 command('Ready');assert(count('Fixture')==0 and #animals==3)
 now=1
 if mode=='nativeFailure' or mode=='blocked' then
  callbacks.OnTick()
  assert(#quarantines==1 and issued==(mode=='blocked' and 0 or 1) and count('StartPositionIssued')==0 and count('Fixture')==0)
  callbacks.OnTick();callbacks.OnTick();assert(#quarantines==1,'failed setup must stop later callbacks');return
 end
 callbacks.OnTick();assert(issued==1 and count('StartPositionIssued')==1 and count('Fixture')==0)
 command('Ready');callbacks.OnTick();assert(issued==1 and count('Fixture')==0,'Ready retries cannot bypass setup')
 assert(not pcall(command,'Ready',{},{}),'foreign owner cannot reuse the fixture')
 assert(not pcall(command,'VerifyStartPosition',{},{}),'foreign owner cannot acknowledge teleport')
 if mode=='timeout' then
  now=30002;callbacks.OnTick()
  assert(#quarantines==1 and count('Fixture')==0,'missing arrival must expire')
  callbacks.OnTick();assert(#quarantines==1,'elapsed setup must quarantine once');return
 end
 if mode=='withoutReceipt' then
  position.x=10819.5;position.y=10119.5;current=start
  callbacks.OnTick();assert(count('StartPositionReady')==0 and count('Fixture')==0,'server arrival alone is insufficient');return
 end
 command('VerifyStartPosition',{x=999,y=999,z=9})
 callbacks.OnTick();assert(count('Fixture')==0,'client receipt alone cannot replace native server position')
 position.x=10819.5;position.y=10119.5
 callbacks.OnTick();assert(count('Fixture')==0,'matching floats with stale server square cannot pass')
 current=start;callbacks.OnTick()
 assert(count('StartPositionReady')==1 and count('Fixture')==1)
 assert(replies[#replies].args.origin.x==1.25 and replies[#replies].args.origin.y==2.75,'cleanup must retain the original authoritative origin')
 local readyIndex,fixtureIndex
 for i,reply in ipairs(replies)do if reply.command=='StartPositionReady' then readyIndex=i elseif reply.command=='Fixture' then fixtureIndex=i end end
 assert(readyIndex<fixtureIndex,'setup ACK must precede the gameplay fixture')
 callbacks.OnTick();assert(count('StartPositionReady')==1 and count('Fixture')==1,'setup ACK must be one-shot')
 assert(not pcall(command,'VerifyStartPosition'),'late duplicate arrival must fail')
end
for _,mode in ipairs({'success','withoutReceipt','timeout','nativeFailure','blocked'})do run(mode)end
''', LUA / 'server/ZZAnimalTrailer_Server.lua', LUA / 'shared/QueueAnimalMovement.lua')

    def test_actual_client_setup_waits_for_loaded_reachable_arrival_and_server_ack(self):
        self.run_lua(r'''
local movement=dofile(arg[2])
package.preload.QueueAnimalMovement=function()return movement end
package.preload.QueueAnimalOwnership=function()return {}end
package.preload['TimedActions/Animals/ISRemoveAnimalFromTrailer']=function()return true end
package.preload['ISUI/ISVehicleAnimalUI']=function()return true end
local function events(target)return setmetatable({},{__index=function(self,name)
 local event={Add=function(fn)target[name]=fn end};self[name]=event;return event
end})end
local function run(mode)
 local callbacks,globalEvents,sends,quarantines={},{},{},{}
 local position={x=1.25,y=2.75,z=0}
 local target={x=10.5,y=20.5,z=0,vehicleId=7}
 local current,reachable=nil,true
 local entry={getX=function()return 10 end,getY=function()return 20 end,getZ=function()return 0 end,
  canReachTo=function()return reachable end}
 local player={getX=function()return position.x end,getY=function()return position.y end,getZ=function()return position.z end,
  getSquare=function()return current end,getPrimaryHandItem=function()return nil end,getSecondaryHandItem=function()return nil end}
 local vehicle={getAreaCenter=function()return {getX=function()return 10.5 end,getY=function()return 20.5 end}end,getZ=function()return 0 end}
 local now=0
 Events=events(globalEvents);AnimalTrailerFixtureConfig={cases={'timer-shared'}}
 luautils={getCorrectSquareForWall=function(owner,to)assert(owner==player and to==entry);return entry end}
 function getSquare()return entry end
 function getPlayer()return player end
 function getTimestampMs()return now end
 function getCore()return {getVersion=function()return '42.21.0'end}end
 function getVehicleById(id)assert(id==7);return vehicle end
 local context={case='timer-shared',events=events(callbacks),quarantine=function(reason)quarantines[#quarantines+1]=reason end,
  send=function(command,args)
   assert(command=='VerifyStartPosition','setup cannot send gameplay requests')
   local fields=0;for _ in pairs(args)do fields=fields+1 end
   assert(fields==0,'client cannot supply setup coordinates');sends[#sends+1]=command
  end}
 package.loaded.QueueAnimalLifecycle=nil
 package.preload.QueueAnimalLifecycle=function()return {start=function(cfg,factory,server)assert(not server);factory(context)end}end
 dofile(arg[1]);globalEvents.OnGameStart()
 local function command(name,args)callbacks.OnServerCommand('AnimalTrailerBaseline',name,args)end
 if mode=='earlyFixture' then
  command('Fixture',{vehicleId=7});assert(#quarantines==1 and #sends==0);return
 end
 command('StartPositionIssued',target);callbacks.OnTick();assert(#sends==0)
 if mode=='timeout' then
  now=30001;callbacks.OnTick();assert(#quarantines==1 and #sends==0);return
 elseif mode=='earlyAck' then
  command('StartPositionReady',target);assert(#quarantines==1 and #sends==0);return
 elseif mode=='duplicateIssue' then
  command('StartPositionIssued',target);assert(#quarantines==1 and #sends==0);return
 end
 position.x=target.x;position.y=target.y
 callbacks.OnTick();assert(#sends==0,'matching coordinates without a current square are not arrival')
 current={getX=function()return 1 end,getY=function()return 2 end,getZ=function()return 0 end}
 callbacks.OnTick();assert(#sends==0,'stale client square must not acknowledge setup')
 current=entry;reachable=false
 callbacks.OnTick();assert(#sends==0,'adjacency across a high fence must not acknowledge setup')
 reachable=true;callbacks.OnTick();callbacks.OnTick()
 assert(#sends==1 and #quarantines==0,'native arrival produces one receipt and still waits for server ACK')
 if mode=='wrongAck' or mode=='expiredAck' then
  if mode=='expiredAck' then now=30001 end
  command('StartPositionReady',mode=='wrongAck' and {x=99,y=target.y,z=0} or target)
  assert(#quarantines==1 and #sends==1,'invalid or expired server receipt must fail closed');return
 end
 command('StartPositionReady',target)
 command('Fixture',{vehicleId=7,ids={101,102,103}})
 assert(#quarantines==0 and #sends==1,'confirmed setup must admit the unchanged gameplay fixture')
end
for _,mode in ipairs({'success','earlyFixture','earlyAck','timeout','duplicateIssue','wrongAck','expiredAck'})do run(mode)end
''', LUA / 'client/ZZAnimalTrailer_Client.lua', LUA / 'shared/QueueAnimalMovement.lua')


if __name__ == '__main__':
    unittest.main()
