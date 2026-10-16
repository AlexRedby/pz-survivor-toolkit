"""One-client fixture barriers retain the shared session's fail-closed lifecycle."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class AnimalSessionTests(unittest.TestCase):
    def test_actual_grab_callback_waits_after_native_drain_for_echo_and_never_manually_releases(self):
        lua = shutil.which('luajit') or shutil.which('lua')
        if not lua:
            self.skipTest('Lua interpreter unavailable')
        code = r'''
local source=arg[1]
local function list(values)return {size=function()return #values end,get=function(self,i)return values[i+1]end}end
local function run(timeout,missingHands)
 local now,armed,grabbed,verified,quarantined=0,0,0,0,0
 local logs,globalEvents,callbacks={}, {}, {}
 local function events(target)return setmetatable({},{__index=function(self,name)
  local event={Add=function(fn)target[name]=fn end};self[name]=event;return event
 end})end
 Events=events(globalEvents);AnimalTraceLast=nil
 AnimalTrailerFixtureConfig={cases={'equipment-fixed'},waitBeforeGrabMs=5,waitAfterGrabMs=9000}
 local animals={};for i=1,3 do local id=i;animals[i]={getAnimalID=function()return 100+id end,getOnlineID=function()return 200+id end}end
 local vehicle={getAnimals=function()return list(animals)end}
 local inventory,hand={},nil
 local square={getX=function()return 1 end,getY=function()return 2 end}
 local player={getPrimaryHandItem=function()return hand end,getSecondaryHandItem=function()return hand end,
  getInventory=function()return {getItems=function()return list(inventory)end}end,getSquare=function()return square end}
 local queue={queue={}}
 function getTimestampMs()return now end
 function getPlayer()return player end
 function getCore()return {getVersion=function()return '42.21.0'end}end
 function getVehicleById(id)assert(id==7);return vehicle end
 function getSquare()return nil end
 function instanceof(item,kind)return kind=='AnimalInventoryItem' and item.animal~=nil end
 function print(text)logs[#logs+1]=text end
 local status='armed=true pending=301 wireAnimal=-1 echoedAnimal=-1 releases=0 player=0 primary=-1 secondary=-1'
 function animalHandsRaceArm(owner)assert(owner==player);armed=armed+1;return 'armed'end
 function animalHandsRaceStatus()return status end
 function animalHandsRaceRelease()error('terminal observation must never force a grant release')end
 ISTimedActionQueue={getTimedActionQueue=function(owner)assert(owner==player);return queue end}
 ISVehicleAnimalUI={onGrabAnimal=function(ui,animal)
  assert(ui.character==player and ui.vehicle==vehicle and animal==animals[1]);grabbed=grabbed+1
  queue.queue={{Type='ISWalkToTimedAction'}}
 end}
 local context={case='equipment-fixed',events=events(callbacks),send=function(command,args)
  assert(command=='Verify' and args.index==1);verified=verified+1
 end,quarantine=function(reason)assert(reason=='native equip echo/release deadline');quarantined=quarantined+1 end}
 package.preload['TimedActions/Animals/ISRemoveAnimalFromTrailer']=function()return true end
 package.preload['ISUI/ISVehicleAnimalUI']=function()return true end
 package.preload.QueueAnimalMovement=function()return {}end
 package.preload.QueueAnimalOwnership=function()return {}end
 package.loaded.QueueAnimalLifecycle=nil
 package.preload.QueueAnimalLifecycle=function()return {start=function(cfg,factory,server)assert(not server);factory(context)end}end
 dofile(source);globalEvents.OnGameStart()
 callbacks.OnServerCommand('AnimalTrailerBaseline','Fixture',{vehicleId=7,ids={101,102,103}})
 now=6;callbacks.OnTick();assert(armed==1 and grabbed==1 and verified==0)
 now=20000;callbacks.OnTick();assert(verified==0,'native walking must not consume a drain deadline')
 queue.queue={};now=20001;callbacks.OnTick();assert(verified==0 and quarantined==0)
 local function auditCount()
  local count=0;for _,line in ipairs(logs)do if line:find('CLIENT WHERE',1,true) or line:find('CLIENT AFTER',1,true) or line:find('CLIENT ORDER_STATUS',1,true) then count=count+1 end end
  return count
 end
 assert(auditCount()==0,'pending echo must have no terminal audit')
 if timeout then
  now=35002;callbacks.OnTick()
  assert(quarantined==1 and verified==0 and auditCount()==0,'one later callback must enforce elapsed deadline without frame counting')
  return
 end
 status='armed=false pending=-1 wireAnimal=-1 echoedAnimal=-1 releases=1 player=0 primary=-1 secondary=-1'
 now=20050;callbacks.OnTick();assert(verified==0 and auditCount()==0,'a release without the actual echo identity must not pass')
 local animal={getAnimalID=function()return 101 end}
 local item={animal=animal,getAnimal=function()return animal end,getID=function()return 301 end,getFullType=function()return 'Base.Animal'end}
 inventory={item};if not missingHands then hand=item end;table.remove(animals,1)
 -- A later unrelated Equip may reset wireAnimal; echoedAnimal remains the proof from the actual release.
 status='armed=false pending=-1 wireAnimal=-1 echoedAnimal=301 releases=1 player=0 primary='..(missingHands and '-1 secondary=-1' or '301 secondary=301')
 now=20100;callbacks.OnTick();assert(verified==0 and auditCount()==0)
 now=29001;callbacks.OnTick();assert(verified==0 and auditCount()==0,'full configured wait must follow actual drain')
 now=29002;callbacks.OnTick();assert(verified==1 and auditCount()==3 and quarantined==0)
 assert(table.concat(logs,'\n'):find('WHERE index=1 inventory=301/101 groundAlive= groundItems=',1,true))
 assert(table.concat(logs,'\n'):find('AFTER index=1 count=2 hand='..(missingHands and 'nil animal=nil' or tostring(item)..' animal=101')..' queue=0',1,true),
  'negative missing-hands control must retain real empty hands and the exact inventory identity')
 now=50000;callbacks.OnTick();assert(verified==1,'terminal audit and verification must occur once')
end
run(false,false);run(false,true);run(true,false)
io.write('PASS actual waiting/drain/echo/audit callback, empty-hands control, elapsed timeout and no manual release\n')
'''
        result = subprocess.run([lua, '-', str(ROOT / 'tests/native_queue/contributions/animal-trailer/lua/client/ZZAnimalTrailer_Client.lua')],
                                input=code, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_reset_uses_native_path_then_requires_actual_server_position_receipt(self):
        lua = shutil.which('luajit') or shutil.which('lua')
        if not lua:
            self.skipTest('Lua interpreter unavailable')
        code = r'''
local movement=dofile(arg[1])
local actions,sends,quarantines={},{},{}
local position={x=20,y=30,z=0};local origin={x=1.25,y=2.75,z=0}
local player={getX=function()return position.x end,getY=function()return position.y end,getZ=function()return position.z end}
local context={send=function(command,args)sends[#sends+1]=command end,quarantine=function(reason)quarantines[#quarantines+1]=reason end}
package.preload['Vehicles/TimedActions/ISPathFindAction']=function()return true end
ISPathFindAction={pathToLocationF=function(self,owner,x,y,z)
 assert(owner==player and x==origin.x and y==origin.y and z==origin.z)
 return {setOnComplete=function(self,fn)self.complete=fn end,setOnFail=function(self,fn)self.fail=fn end}
end}
ISTimedActionQueue={add=function(action)actions[#actions+1]=action end}
local state=movement.restore(context,player,origin)
assert(#actions==1 and #sends==0 and not state.arrived and not state.confirmed)
assert(not movement.confirm(state,origin),'a receipt before native arrival must fail')
actions[1].complete();assert(#quarantines==1 and #sends==0,'wrong native endpoint must quarantine')
state=movement.restore(context,player,origin)
position.x=origin.x;position.y=origin.y
actions[2].complete();assert(state.arrived and #sends==1 and sends[1]=='VerifyPosition' and not state.confirmed)
assert(not movement.confirm(state,{x=99,y=origin.y,z=0}) and not state.confirmed,'wrong authoritative receipt must fail')
assert(not movement.confirm(state,{x=0/0,y=origin.y,z=0}) and not state.confirmed,'non-finite authoritative receipt must fail')
assert(movement.confirm(state,origin) and state.confirmed and movement.at(player,origin))
actions[2].fail();assert(#quarantines==2,'native path failure must quarantine')
assert(not pcall(movement.restore,context,player,{}))
print('PASS native path only, endpoint proof, authoritative ACK and path failure gates')
'''
        result = subprocess.run([lua, '-', str(ROOT / 'tests/native_queue/contributions/animal-trailer/lua/shared/QueueAnimalMovement.lua')],
                                input=code, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_native_disconnect_quarantines_on_ui_event_without_another_game_tick(self):
        lua = shutil.which('luajit') or shutil.which('lua')
        if not lua:
            self.skipTest('Lua interpreter unavailable')
        code = r'''
local events={}
Events=setmetatable({},{__index=function(self,name)
 local event={Add=function(fn)events[name]=fn end};self[name]=event;return event
end})
local active,disconnected,count=nil,false,0
function animalFixtureDisconnected()return disconnected end
local S={phase='prepare',current=function()return active end,tick=function()error('OnTick must not be required')end,command=function()end}
S.prepare=function()active={};S.configure(active);S.phase='running'end
S.quarantine=function(reason)assert(type(reason)=='string');count=count+1;S.phase='quarantined'end
package.preload.QueueAnimalSession=function()return function()return S end end
local lifecycle=dofile(arg[1]);lifecycle.start({cases={'timer-shared'}},function()end,false)
disconnected=true;events.OnPreUIDraw();assert(count==0,'pre-game UI must not quarantine an unstarted fixture')
events.OnGameStart();assert(active.quarantine==S.quarantine)
events.OnPreUIDraw();assert(count==1 and S.phase=='quarantined','actual native kick must quarantine even with no OnTick')
events.OnPreUIDraw();assert(count==1,'quarantine must be terminal')
S.phase='running';disconnected=false;events.OnDisconnect();assert(count==2)
S.phase='running';events.OnMainMenuEnter();assert(count==3)
S.phase='done';disconnected=true;events.OnPreUIDraw();events.OnDisconnect();assert(count==3,'successful session remains terminal')
print('PASS disconnect/kick UI and native event guards without a game tick')
'''
        result = subprocess.run([lua, '-', str(ROOT / 'tests/native_queue/contributions/animal-trailer/lua/shared/QueueAnimalLifecycle.lua')],
                                input=code, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_owned_cleanup_keeps_foreign_entities_and_requires_replicated_absence(self):
        lua = shutil.which('luajit') or shutil.which('lua')
        if not lua:
            self.skipTest('Lua interpreter unavailable')
        code = r'''
local ownership=dofile(arg[1])
local function list(values)
 return {values=values,size=function(self)return #self.values end,get=function(self,i)return self.values[i+1]end}
end
local inventory=list({})
local container={getItems=function()return inventory end,contains=function(self,item)for _,v in ipairs(inventory.values)do if v==item then return true end end return false end,
 Remove=function(self,item)for i,v in ipairs(inventory.values)do if v==item then table.remove(inventory.values,i);return end end end}
local ground=list({});local animals=list({})
local square={getX=function()return 1 end,getY=function()return 2 end,getZ=function()return 0 end,
 getAnimals=function()return animals end,getWorldObjects=function()return ground end}
function getSquare()return square end
local function item(id,owner)return {getID=function()return id end,getContainer=function()return owner end,getWorldItem=function()return nil end}end
local foreign=item(999,container);local bat=item(4,container);inventory.values={foreign,bat}
ground.values={{getItem=function()return foreign end}}
local player={getInventory=function()return container end,getPrimaryHandItem=function()return nil end,getSecondaryHandItem=function()return nil end,
 removeFromHands=function()end}
function sendRemoveItemFromContainer(c,it)assert(c==container and it==bat)end
local registry,vehicles,deleted={},{},{}
function getAnimal(id)return registry[id]end
function getVehicleById(id)return vehicles[id]end
for id=1,3 do
 local animal={getAnimalID=function()return id+100 end,getSquare=function()return square end,isExistInTheWorld=function()return true end,
 getVehicle=function()return nil end,getHutch=function()return nil end}
 registry[id]=animal;animals.values[#animals.values+1]=animal
end
local foreignAnimal={getAnimalID=function()return 999 end};registry[999]=foreignAnimal;animals.values[#animals.values+1]=foreignAnimal
function animalFixtureDelete(animal)
 local found
 for id,current in pairs(registry)do if current==animal then found=id end end
 assert(found and found>=1 and found<=3,'foreign animal deletion')
 registry[found]=nil;deleted[#deleted+1]=found
 for i,current in ipairs(animals.values)do if current==animal then table.remove(animals.values,i);break end end
 return 'removed='..found
end
local foreignContents=false
local vehicle={getAnimals=function()return list({})end,getId=function()return 7 end,getSquare=function()return square end,
 getMaxPassengers=function()return 1 end,getCharacter=function()return nil end,getPartCount=function()return 1 end,
 getPartByIndex=function()return{getItemContainer=function()return{getItems=function()return list(foreignContents and {foreign} or {})end}end}end,
 permanentlyRemove=function()vehicles[7]=nil end}
vehicles[7]=vehicle;vehicles[88]={foreign=true}
local removedWorld,transmissions=false,0
local ownedGround=item(3)
local ownedWorld={getItem=function()return ownedGround end,getSquare=function()return not removedWorld and square or nil end}
ownedGround.getWorldItem=function()return ownedWorld end
ground.values[#ground.values+1]=ownedWorld
square.transmitRemoveItemFromSquare=function(self,object)
 assert(self==square and object==ownedWorld,'foreign world-object removal')
 transmissions=transmissions+1;removedWorld=true
 for i,current in ipairs(ground.values)do if current==object then table.remove(ground.values,i);break end end
end
local state={vehicle=vehicle,player=player,animals={{id=101,online=1},{id=102,online=2},{id=103,online=3}},
 items={[1]=item(1),[2]=item(2),[3]=ownedGround,[4]=bat}}
foreignContents=true;assert(not pcall(ownership.remove,state));assert(#deleted==0 and #inventory.values==2 and #ground.values==2)
foreignContents=false
local receipt=ownership.remove(state)
assert(#deleted==3 and not vehicles[7] and vehicles[88].foreign and registry[999]==foreignAnimal)
assert(#inventory.values==1 and inventory.values[1]==foreign and #ground.values==1 and ground.values[1]:getItem()==foreign)
assert(removedWorld and transmissions==1,'owned ground-item removal must use the native broadcast/mutation path exactly once')
assert(ownership.verify(receipt,player))
registry[1]={isExistInTheWorld=function()return true end};assert(not ownership.verify(receipt,player));registry[1]=nil
inventory.values[#inventory.values+1]=item(1,container);assert(not ownership.verify(receipt,player));table.remove(inventory.values)
vehicles[7]=vehicle;assert(not ownership.verify(receipt,player))
print('PASS exact owned cleanup, foreign entity retention, foreign contents refusal and replication ACK gates')
'''
        result = subprocess.run([lua, '-', str(ROOT / 'tests/native_queue/contributions/animal-trailer/lua/shared/QueueAnimalOwnership.lua')],
                                input=code, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_one_actor_barriers_reset_failure_and_default_two_actor_barrier(self):
        lua = shutil.which('luajit') or shutil.which('lua')
        if not lua:
            self.skipTest('Lua interpreter unavailable')
        code = r'''
local create=dofile(arg[1])
local now=0
function getTimestampMs() return now end
function sendServerCommand() end
local online=-1
local player={getUsername=function() return 'client1' end,getOnlineID=function()return online end}
local other={getUsername=function() return 'client2' end,getOnlineID=function()return 2 end}
local cleanCount=0
local factories={}
for _,case in ipairs({'timer-shared','combined-shared'}) do
 factories[case]=function(ctx) ctx.cleanup=function() cleanCount=cleanCount+1;return true end end
end
local function args(s,actor) return {fixtureCase=s.cases[s.index],fixtureEpoch=s.epoch,fixtureActor=actor or 'client1',ok=true} end
local function session(actors)
 local s=create({user='server',actors=actors,cases={'timer-shared','combined-shared'}},factories,true)
 s.prepare();return s
end
local s=session({'client1'});s.receive('Prepare',player,args(s));assert(s.phase=='running')
local stale=args(s);s.receive('Finish',player,args(s));assert(s.phase=='clean' and cleanCount==1 and s.index==1)
s.receive('Cleaned',player,args(s));assert(s.phase=='prepare' and s.index==2)
s.receive('Finish',player,stale);assert(s.phase=='prepare' and s.index==2)
s.receive('Prepare',player,args(s));s.receive('Finish',player,args(s));s.receive('Cleaned',player,args(s));assert(s.phase=='done' and cleanCount==2)
s=session({'client1'});s.receive('Prepare',other,args(s,'client2'));assert(s.phase=='quarantined')
s=session({'client1'});s.receive('Prepare',player,args(s));s.current().cleanup=function()return false,'pending owned animal'end
s.receive('Finish',player,args(s));assert(s.phase=='quarantined' and s.index==1)
s=session(nil);s.receive('Prepare',player,args(s));assert(s.phase=='prepare','default still requires both clients')
s.receive('Prepare',other,args(s,'client2'));assert(s.phase=='running')
local current,sends=nil,0
function getPlayer()return current end
function sendClientCommand(module,command,value)
 assert(module=='QueueFixtureSession' and command=='Prepare' and value.fixtureActor=='client1')
 sends=sends+1
end
local client=create({user='client1',actors={'client1'},cases={'timer-shared'}},factories,false)
client.prepare();assert(sends==0 and client.pendingPrepare,'OnGameStart must not transmit')
client.tick();assert(sends==0,'missing player must keep Prepare pending')
current=player;client.tick();assert(sends==0,'unassigned online identity must keep Prepare pending')
online=1;client.tick();assert(sends==1 and not client.pendingPrepare and client.phase=='prepare')
client.tick();client.tick();assert(sends==1,'actual Prepare is one-shot, never retransmitted')
s=session({'client1'});s.tick();assert(sends==1,'server must not use client API')
for _,actors in ipairs({{}, {'client2'}, {'client1','client1'}, {'client1','client2','client3'}, {'client1',extra='client2'}, false}) do
 assert(not pcall(session,actors),'invalid participant list accepted')
end
print('PASS one-client barriers, stale receipts, reset refusal, deferred one-shot Prepare and unchanged two-client default')
'''
        result = subprocess.run([lua, '-', str(ROOT / 'tests/native_queue/support/QueueFixtureSession.lua')],
                                input=code, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
