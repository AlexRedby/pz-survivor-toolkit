"""Falsify negative storage snapshots/native walk admission; no gameplay proof."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest
import zlib

from test_fitness_storage_fixture import HARNESS as STORAGE_HARNESS

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / 'tests/native_queue/fitness/shared/QueueFitnessStorageNegative.lua'
LUA = shutil.which('luajit') or shutil.which('lua')

HARNESS = r'''
function isClient()return client or false end
now=1000;function getTimestampMs()return now end
local originSquare=square
local squares={['10:20:0']=originSquare}
function grid(x,y,z)
 local key=x..':'..y..':'..z
 if squares[key]then return squares[key]end
 local sq={x=x,y=y,z=z,objects={}}
 function sq:getX()return self.x end;function sq:getY()return self.y end;function sq:getZ()return self.z end
 function sq:getWorldObjects()return list(self.objects)end
 squares[key]=sq;return sq
end
local function terrain(sq)
 function sq:TreatAsSolidFloor()return not self.noFloor end
 function sq:isFree()return not self.occupied end
 function sq:isBlockedTo()return self.blocked or false end
end
terrain(originSquare)
local createGrid=grid
function grid(x,y,z)local sq=createGrid(x,y,z);terrain(sq);return sq end
function getCell()return{getGridSquare=function(_,x,y,z)if unloadedOrigin and x==10 and y==20 and z==0 then return end;return grid(x,y,z)end}end
function getWorld()return{getCell=getCell,getFrameNo=function()return 100 end}end
local basePlayer=playerNew
function playerNew()
 local p=basePlayer();p.x=10.5;p.y=20.5;p.z=0;p.onlineID=1;p.readPages={}
 function p:getX()return self.x end;function p:getY()return self.y end;function p:getZ()return self.z end
 function p:getOnlineID()return self.onlineID end;function p:getPlayerNum()return self.onlineID-1 end
 function p:getCurrentSquare()return grid(math.floor(self.x),math.floor(self.y),math.floor(self.z))end
 function p:getCurrentState()return 'idle'end
 function p:getAlreadyReadPages(kind)return self.readPages[kind]or 0 end
 function p:setX()error('fixture must not teleport')end;function p:setY()error('fixture must not teleport')end
 function p:setZ()error('fixture must not teleport')end
 p.path={}
 function p.path:pathToLocation(x,y,z)self.destination={x=x,y=y,z=z};self.cancelled=false end
 function p.path:update()
  local destination=assert(self.destination);p.x=p.x+1;now=now+50
  if p.x>=destination.x+.5 then return BehaviorResult.Succeeded end
  return BehaviorResult.Working
 end
 function p.path:cancel()self.cancelled=true end
 function p:getPathFindBehavior2()return self.path end
 function p:setPath2()end
 function p:pressedMovement()return false end;function p:pressedCancelAction()return false end
 return p
end
function prepareNegative()
 local p=playerNew();state={case='storage-walk-away',player=p,items={},ids={items={}}}
 for name,kind in pairs({bag='Base.Bag_Schoolbag',hammer='Base.Hammer',screwdriver='Base.Screwdriver',front='Base.BookCarpentry1',dumbbell='Base.DumbBell',tail='Base.BookFirstAid1'})do
  local item=p.inventory:AddItem(kind);state.items[name]=item;state.ids.items[name]=item.id
 end
 local items=state.items;items.bag.inner:AddItem(items.front);items.bag.inner:AddItem(items.dumbbell)
 function items.tail:getNumberOfPages()return 10 end
 p.readPages[items.tail:getFullType()]=9
 if tail then tail.Type='ISReadABook';tail.character=p;tail.item=items.tail end
 p:setWornItem(items.bag:canBeEquipped(),items.bag);p:setPrimaryHandItem(items.hammer);p:setSecondaryHandItem(items.screwdriver)
 N.prepare(state);spec=state.ids.negativeStorage
 peer=playerNew();peer.onlineID=2;peer.x=11.5
 return state
end
function floorBag()
 state.player.inventory:AddItem(state.items.dumbbell)
 return place(state.items.bag)
end
function refuses(callback,part)
 local ok,problem=pcall(callback);assert(not ok,'invalid native producer accepted')
 if part then assert(tostring(problem):find(part,1,true),tostring(problem))end
end
'''

NATIVE_HARNESS = r'''
package.preload['BuildingObjects/ISWalkToCursor']=function()return true end
package.preload['TimedActions/ISBaseTimedAction']=function()return true end
ISBaseTimedAction={}
function ISBaseTimedAction:derive(name)local value={Type=name};setmetatable(value,{__index=self});value.__index=value;return value end
function ISBaseTimedAction:isStarted()return self.nativeStarted==true end
function ISBaseTimedAction:forceComplete()
 assert(N.begin(state,self,'perform'));self:perform();q.queue={};q.current=nil;self.nativeStarted=false
 N.finish(state,self,'perform',true)
end
function ISBaseTimedAction:forceStop()self:stop();q.queue={};q.current=nil;self.nativeStarted=false end
function ISBaseTimedAction:perform()end;function ISBaseTimedAction:stop()end
ISBuildingObject={derive=ISBaseTimedAction.derive,init=function()end,setSprite=function()end,setNorthSprite=function()end}
for _,name in ipairs({'ClimbOverFenceState','ClimbOverWallState','ClimbSheetRopeState','ClimbDownSheetRopeState','ClimbThroughWindowState'})do
 _G[name]={instance=function()return name end}
end
DebugType={Action='action'};function log()end
BehaviorResult={Succeeded='succeeded',Failed='failed',Working='working'}
tail={Type='independent-tail'};body={Type='ISFitnessAction'}
q={queue={body,tail},current=body};clears=0;walks=0
function q:indexOf(value)for i,item in ipairs(self.queue)do if item==value then return i end end;return -1 end
ISTimedActionQueue={getTimedActionQueue=function()return q end}
function ISTimedActionQueue.clear(player)assert(player==state.player);clears=clears+1;q.queue={};q.current=nil end
function ISTimedActionQueue.add(action)
 walks=walks+1;table.insert(q.queue,action);q.current=action
 N.begin(state,action,'start')
 action.action={setPathfinding=function()end,setAllowedWhileDraggingCorpses=function()end}
 action.nativeStarted=true;action:start()
end
function initializeProvenance()
 local sources={}
 for _,name in ipairs({'new','create','locateTargetSquare'})do sources[ISWalkToCursor[name]]='ISWalkToCursor.lua'end
 sources[ISWalkToTimedAction.new]='WalkToTimedAction.lua'
 local originalWalkPerform=ISWalkToTimedAction.perform
 package.preload['PZSurvivorToolkit/SourceProof']=function()return{
  matches=function(path,pin,mod,adler)
   if mod~=nil or adler~=true then return false end
   return path=='media/lua/server/BuildingObjects/ISWalkToCursor.lua'and pin==2852789671 and not changedCursorSource
    or path=='media/lua/client/TimedActions/WalkToTimedAction.lua'and pin==2037641019 and not changedWalkSource
  end,
  closure=function(callback,filename)return sources[callback]==filename end}end
 PZSurvivorToolkit={ActionQueuePolicy={matchesNative=function(action)
  return action.perform==originalWalkPerform and not rejectedPolicy
 end}}
end
'''


@unittest.skipUnless(LUA, 'Lua runtime unavailable')
class FitnessNegativeFixtureTests(unittest.TestCase):
    def check(self, body, native=False):
        source = STORAGE_HARNESS + HARNESS
        if native:
            game = os.environ.get('PZ_GAME')
            if not game:
                self.skipTest('PZ_GAME required for actual native movement producer')
            lua = Path(game) / 'media/lua'
            cursor = (lua / 'server/BuildingObjects/ISWalkToCursor.lua').read_text()
            walk = (lua / 'client/TimedActions/WalkToTimedAction.lua').read_text()
            self.assertEqual(zlib.adler32(cursor.encode()), 2852789671)
            self.assertEqual(zlib.adler32(walk.encode()), 2037641019)
            source += NATIVE_HARNESS + '\n' + walk + '\n' + cursor + '\ninitializeProvenance()\n'
        source += '\nN=dofile(' + json.dumps(str(MODULE)) + ')\nprepareNegative()\n' + body
        result = subprocess.run([LUA, '-'], input=source, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_initial_exact_resources_hands_slots_and_flags(self):
        self.check(r'''
assert(N.matches('storage-walk-away')and N.matches('storage-peer-pickup')and not N.matches('multi-storage'))
assert(N.competition('storage-peer-pickup')and not N.competition('storage-walk-away')and N.ready(state))
local snap=N.snapshot(state.player,spec)
assert(#snap.resources==3 and snap.primary==state.ids.items.hammer and snap.secondary==state.ids.items.screwdriver)
assert(N.endpoint(snap,spec.bag.id).container=='client1-root'and N.endpoint(snap,spec.bag.id).favorite)
assert(N.endpoint(snap,spec.prop.id).container==spec.bag.id and N.endpoint(snap,spec.prop.id).favorite)
assert(N.endpoint(snap,spec.content.id).container==spec.bag.id)
assert(snap.worn[1].id==spec.bag.id and snap.peerPosition==false and snap.position.onlineID==-1)
state.items.bag.favorite=false;assert(not N.ready(state))
''')

    def test_far_actor_snapshot_keeps_origin_world_and_all_unchanged_contents(self):
        self.check(r'''
local extra=state.items.bag.inner:AddItem('Base.Pencil');extra:setFavorite(true)
floorBag();state.player.x=14.5
local snap=N.snapshot(state.player,spec)
local bag=N.endpoint(snap,spec.bag.id)
assert(bag.container=='world'and bag.owner=='world'and bag.world.linked and bag.favorite)
assert(bag.world.x==10 and bag.world.y==20 and snap.position.x==14.5 and #snap.resources==4)
assert(N.endpoint(snap,spec.content.id).container==spec.bag.id and N.endpoint(snap,extra.id).favorite)
assert(N.endpoint(snap,spec.prop.id).container=='client1-root')
assert(state.items.bag:getWorldItem()and state.items.front:getContainer()==state.items.bag.inner)
''')

    def test_distinct_peer_root_and_world_square_deduplication(self):
        self.check(r'''
client=true;floorBag();peer.x=10.5
local before=N.snapshot(state.player,spec,peer)
assert(#before.resources==3 and N.endpoint(before,spec.bag.id).world.linked)
recover(state.items.bag);peer.inventory:AddItem(state.items.bag)
local snap=N.snapshot(state.player,spec,peer)
assert(#snap.resources==3 and snap.position.onlineID==1 and snap.peerPosition.onlineID==2)
assert(N.endpoint(snap,spec.bag.id).owner=='client2'and N.endpoint(snap,spec.bag.id).container=='client2-root')
assert(N.endpoint(snap,spec.content.id).owner=='client2'and N.endpoint(snap,spec.prop.id).owner=='client1')
local peerOnly=N.snapshot(peer,spec,nil,'client2')
assert(N.endpoint(peerOnly,spec.bag.id).container=='client2-root'and not N.endpoint(peerOnly,spec.prop.id))
''')

    def test_duplicate_missing_wrong_type_and_unlinked_resources_remain_visible(self):
        self.check(r'''
floorBag()
local lookalike=peer.inventory:AddItem('Base.Bag_Schoolbag')
local snap=N.snapshot(state.player,spec,peer)
assert(N.endpoint(snap,spec.bag.id).owner=='world'and not N.endpoint(snap,lookalike.id))
lookalike.id=spec.bag.id
assert(N.endpoint(N.snapshot(state.player,spec,peer),spec.bag.id)==false)
peer.inventory:Remove(lookalike);state.items.bag.kind='Base.Bag_Satchel'
assert(N.endpoint(N.snapshot(state.player,spec,peer),spec.bag.id).kind=='Base.Bag_Satchel')
state.items.bag.world=nil
assert(not N.endpoint(N.snapshot(state.player,spec,peer),spec.bag.id).world.linked)
square.objects={}
assert(not N.endpoint(N.snapshot(state.player,spec,peer),spec.bag.id))
''')

    def test_actual_native_cursor_cancels_old_tail_and_samples_native_path_positions(self):
        self.check(r'''
local before=state.player.x
local witness=N.walk(state,tail)
assert(clears==1 and walks==1 and q:indexOf(tail)==-1 and q:indexOf(body)==-1 and witness.oldTailCancelled)
assert(witness.producer=='ISWalkToCursor.create'and witness.destination.x==14 and witness.destination.y==20)
assert(state.player.x==before and witness.maxTime==-1 and witness.maxDisplacement==0)
assert(state.player.path.destination.x==14 and q.current==state.negativeWalk.action)
assert(N.observeWalk(state).nativeStarted and witness.maxDisplacement==0)
local action=state.negativeWalk.action
for i=1,4 do action:update();N.observeWalk(state)end
assert(state.player.x==14.5 and witness.after.x==14.5 and witness.maxDisplacement==4)
assert(state.player.path.cancelled and #q.queue==0 and witness.nativeStarted)
assert(witness.nativeBegin and witness.nativePerformCalls==1 and witness.nativeCompleted and witness.nativeResult=='Succeeded')
assert(witness.tailId==state.ids.items.tail and witness.tailPages==9 and witness.tailTotal==10 and witness.completedAt>witness.requestedAt)
local conserved=N.snapshot(state.player,spec)
assert(N.endpoint(conserved,spec.bag.id).container=='client1-root'and N.ready(state))
''', native=True)

    def test_preexisting_wrong_producers_or_changed_sources_reject_before_queue_clear(self):
        for mutation in (
            'ISWalkToCursor.new=function()error("foreign cursor new executed")end',
            'ISWalkToCursor.create=function()error("foreign create executed")end',
            'ISWalkToCursor.locateTargetSquare=function()error("foreign locate executed")end',
            'ISWalkToTimedAction.new=function()error("foreign walk new executed")end',
            'changedCursorSource=true', 'changedWalkSource=true',
        ):
            with self.subTest(mutation=mutation):
                self.check(mutation + r'''
refuses(function()N.walk(state,tail)end,'native walk producer changed')
assert(clears==0 and walks==0 and #q.queue==2 and q.queue[2]==tail and not state.negativeWalk)
assert(state.player.x==10.5)
''', native=True)

    def test_already_read_or_absent_original_reader_rejected_before_clear(self):
        self.check(r'''
state.player.readPages[state.items.tail:getFullType()]=state.items.tail:getNumberOfPages()
refuses(function()N.walk(state,tail)end,'original independent reader already started or finished')
assert(clears==0 and walks==0 and #q.queue==2 and q.queue[2]==tail and not state.negativeWalk)
assert(state.player.x==10.5 and state.player.readPages['Base.BookFirstAid1']==10)
''', native=True)
        self.check(r'''
q.queue={body}
refuses(function()N.walk(state,tail)end,'original independent reader already started or finished')
assert(clears==0 and walks==0 and not state.negativeWalk and state.player.readPages['Base.BookFirstAid1']==9)
''', native=True)

    def test_blocked_unloaded_or_rejected_native_path_never_claims_valid_walk(self):
        self.check(r'''
for _,direction in ipairs({{1,0},{-1,0},{0,1},{0,-1}})do grid(10+direction[1],20+direction[2],0).blocked=true end
refuses(function()N.walk(state,tail)end,'no native unobstructed');assert(clears==0 and walks==0)
''', native=True)
        self.check("unloadedOrigin=true;refuses(function()N.walk(state,tail)end,'origin unloaded');assert(clears==0)", native=True)
        self.check("rejectedPolicy=true;refuses(function()N.walk(state,tail)end,'failed to enqueue');assert(not state.negativeWalk.witness.nativeCompleted)", native=True)
        self.check("N.walk(state,tail);state.negativeWalk.action.maxTime=1;refuses(function()N.observeWalk(state)end,'duration changed')", native=True)

    def test_unstarted_failed_or_replayed_native_callbacks_cannot_complete(self):
        self.check(r'''
N.walk(state,tail);local action=state.negativeWalk.action
assert(not N.begin(state,{},'perform')and not N.begin(state,action,'complete'))
action.result=BehaviorResult.Succeeded
refuses(function()N.begin(state,action,'perform')end,'perform once successfully')
assert(not state.negativeWalk.witness.nativePerformCalls and not state.negativeWalk.witness.nativeCompleted)
''', native=True)
        self.check(r'''
N.walk(state,tail);N.observeWalk(state);local action=state.negativeWalk.action
action.result=BehaviorResult.Failed
refuses(function()N.begin(state,action,'perform')end,'perform once successfully')
refuses(function()N.finish(state,action,'perform',true)end,'callback failed')
assert(not state.negativeWalk.witness.nativeCompleted)
''', native=True)
        self.check(r'''
N.walk(state,tail);N.observeWalk(state);local action=state.negativeWalk.action
action.result=BehaviorResult.Succeeded;assert(N.begin(state,action,'perform'))
refuses(function()N.finish(state,action,'perform',false)end,'callback failed')
assert(not state.negativeWalk.witness.nativeCompleted)
''', native=True)
        self.check(r'''
N.walk(state,tail);N.observeWalk(state);local action=state.negativeWalk.action
for i=1,4 do action:update();N.observeWalk(state)end
refuses(function()N.begin(state,action,'perform')end,'perform once successfully')
refuses(function()N.finish(state,action,'perform',true)end,'callback failed')
assert(state.negativeWalk.witness.nativePerformCalls==1 and state.negativeWalk.witness.nativeCompleted)
''', native=True)


if __name__ == '__main__':
    unittest.main()
