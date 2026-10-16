"""One-client fixture barriers retain the shared session's fail-closed lifecycle."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class AnimalSessionTests(unittest.TestCase):
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
