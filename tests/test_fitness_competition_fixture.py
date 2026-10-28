"""Falsify peer movement/transaction witnesses; doubles establish no gameplay pass."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / 'tests/native_queue/fitness/shared/QueueFitnessCompetition.lua'
LUA = shutil.which('luajit') or shutil.which('lua')

HARNESS = r'''
package.preload['TimedActions/WalkToTimedAction']=function()return true end
package.preload['TimedActions/ISInventoryTransferUtil']=function()return true end
function list(values)return{size=function()return #values end,get=function(_,i)return values[i+1]end,
 isEmpty=function()return #values==0 end,contains=function(_,value)for _,row in ipairs(values)do if row==value then return true end end;return false end}end
function instanceof(value,kind)return value and value.class==kind end
function isClient()return true end;function isServer()return false end
now=1000;function getTimestampMs()return now end
BehaviorResult={Succeeded='succeeded',Failed='failed'}
local squares={}
function square(x,y,z)
 local key=x..':'..y..':'..z
 if squares[key]then return squares[key]end
 local sq={x=x,y=y,z=z,objects={}}
 function sq:getX()return self.x end;function sq:getY()return self.y end;function sq:getZ()return self.z end
 function sq:isBlockedTo()return self.blocked or false end
 function sq:TreatAsSolidFloor()return true end;function sq:isFree()return true end
 function sq:getWorldObjects()return list(self.objects)end
 squares[key]=sq;return sq
end
function getCell()return{getGridSquare=function(_,x,y,z)return square(x,y,z)end}end
function container(kind)
 local c={items={},kind=kind}
 function c:getItems()return list(self.items)end
 function c:getType()return self.kind end
 function c:getItemById(id)for _,item in ipairs(self.items)do if item.id==id then return item end end end
 function c:isInCharacterInventory(player)return self==player.inventory end
 function c:isVehicleSeat()return false end
 function c:AddItem(item)self.items[#self.items+1]=item;item.source=self;return item end
 function c:Remove(item)for i,value in ipairs(self.items)do if item==value then table.remove(self.items,i);item.source=nil;return end end end
 return c
end
function item(id,kind)
 local value={id=id,kind=kind,favorite=false}
 function value:getID()return self.id end;function value:getFullType()return self.kind end
 function value:getContainer()return self.source end;function value:getWorldItem()return self.world end
 function value:getItemContainer()return self.inner end;function value:isFavorite()return self.favorite end
 function value:getActualWeight()return 1 end
 return value
end
origin=square(10,20,0);floor=container('floor')
bag=item(100,'Base.Bag_Schoolbag');bag.inner=container('bag');bag.class='InventoryContainer';bag.favorite=true
marker=item(101,'Base.BookCarpentry1');bag.inner:AddItem(marker)
world={class='IsoWorldInventoryObject',getItem=function()return bag end,getSquare=function()return origin end}
floor:AddItem(bag);bag.world=world;origin.objects={world}
player={x=10.5,y=20.5,z=0,inventory=container('inventory'),actions={}}
function player:getPlayerNum()return 0 end
function player:getCurrentSquare()return square(math.floor(self.x),math.floor(self.y),math.floor(self.z))end
function player:getX()return self.x end;function player:getY()return self.y end;function player:getZ()return self.z end
function player:getInventory()return self.inventory end
function player:getCharacterActions()return list(self.actions)end
function player:hasTimedActions()return #self.actions>0 end
function player:isDead()return self.dead or false end
function player:hasTrait()return false end;function player:isWearingAwkwardGloves()return false end
function player:isTimedActionInstant()return false end
function getSpecificPlayer()return activePlayer or player end
function getCore()return{getGameMode=function()return 'Sandbox'end}end
CharacterTrait={DEXTROUS='dextrous',ALL_THUMBS='all-thumbs'}
loot={refreshBackpacks=function()refreshes=refreshes+1 end};refreshes=0
function getPlayerLoot()return loot end
ISInventoryPage={GetFloorContainer=function()return floor end}
q={queue={}};ISTimedActionQueue={}
function ISTimedActionQueue.getTimedActionQueue()return replacementQueue or q end
function ISTimedActionQueue.add(action)
 table.insert(q.queue,action);q.current=action
 C.begin(state,action,'start') -- Native begin observation precedes native allocation/start.
 action.action={};player.actions={action.action}
end
ISWalkToTimedAction={Type='ISWalkToTimedAction'};ISWalkToTimedAction.__index=ISWalkToTimedAction
function ISWalkToTimedAction:new(actor,destination)return setmetatable({Type=self.Type,character=actor,location=destination,maxTime=-1},self)end
function ISWalkToTimedAction:start()end;function ISWalkToTimedAction:perform()end;function ISWalkToTimedAction:stop()end
ISInventoryTransferAction={Type='ISInventoryTransferAction'};ISInventoryTransferAction.__index=ISInventoryTransferAction
function ISInventoryTransferAction:new(actor,value,source,destination)
 return setmetatable({Type=self.Type,character=actor,item=value,srcContainer=source,destContainer=destination,
  maxTime=-1,transactionId=0,queueList={{items={value},type=value.kind}}},self)
end
function ISInventoryTransferAction:start()end;function ISInventoryTransferAction:perform()end
function ISInventoryTransferAction:transferItem()end;function ISInventoryTransferAction:stop()end
ISInventoryTransferUtil={newInventoryTransferAction=function(...)return ISInventoryTransferAction:new(...)end}
done=true;rejected=false
function isItemTransactionDone(id)return done end;function isItemTransactionRejected(id)return rejected end
spec={origin={x=10,y=20,z=0},bag={id=100,kind='Base.Bag_Schoolbag'},prop={id=102,kind='Base.DumbBell'},content={id=101,kind='Base.BookCarpentry1'}}
function initializeProvenance()
 local classes={[ISWalkToTimedAction]={},[ISInventoryTransferAction]={}}
 for class,snapshot in pairs(classes)do
  for _,name in ipairs({'new','start','stop','perform','transferItem'})do snapshot[name]=class[name]end
 end
 local walkConstructor=ISWalkToTimedAction.new
 package.preload['PZSurvivorToolkit/SourceProof']=function()return{
  matches=function(path,hash,mod,adler)return not changedWalkSource and path=='media/lua/client/TimedActions/WalkToTimedAction.lua'and hash==2037641019 and mod==nil and adler==true end,
  closure=function(callback,path)return callback==walkConstructor and path=='WalkToTimedAction.lua'end}end
 local function valid(action)
  local snapshot=classes[getmetatable(action)];if not snapshot then return false end
  for _,name in ipairs({'new','start','stop','perform','transferItem'})do if action[name]~=snapshot[name]then return false end end
  return true
 end
 PZSurvivorToolkit={ActionQueuePolicy={
  matchesNative=function(action)return not adoptedFloorPolicy and valid(action)end,
  matchesCleanupPickupBinding=function(action)return valid(action)and action.Type=='ISInventoryTransferAction'
   and action.srcContainer==floor and action.destContainer==player.inventory end}}
end
function approach()state=C.approach(player,spec);return state end
function pickup()approach();assert(C.poll(state)=='ready');action=C.pickup(state);return action end
function clearQueue()q.queue={};q.current=nil;player.actions={}end
function transfer(fresh)
 floor:Remove(bag);origin.objects={};bag.world=nil
 if fresh then
  local replacement=item(bag.id,bag.kind);replacement.inner=bag.inner;replacement.class=bag.class;replacement.favorite=bag.favorite
  player.inventory:AddItem(replacement)
 else player.inventory:AddItem(bag)end
 action.started=true;action.transactionId=7
end
function paid(fresh)
 pickup();transfer(fresh);assert(C.begin(state,action,'perform'))
 action.transactionId=0;action.started=false;action.queueList={};clearQueue()
 C.finish(state,action,'perform',true);assert(C.poll(state)=='picked');return C.result(state)
end
function refuses(callback,part)
 local ok,problem=pcall(callback);assert(not ok,'invalid witness accepted')
 if part then assert(tostring(problem):find(part,1,true),tostring(problem))end
end
'''


@unittest.skipUnless(LUA, 'Lua runtime unavailable')
class FitnessCompetitionFixtureTests(unittest.TestCase):
    def check(self, body, native=''):
        script = HARNESS + '\n' + native + '\ninitializeProvenance();C=dofile(' + json.dumps(str(MODULE)) + ')\n' + body
        result = subprocess.run([LUA, '-'], input=script, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_already_adjacent_pickup_requires_paid_callback_and_keeps_values(self):
        self.check(r'''
local result=paid(false)
assert(result.phase=='picked'and result.id==100 and result.favorite and result.callbacks==1 and result.queueDrained)
assert(not result.walkRequired and result.pickupStart.callback=='ISBaseTimedAction.begin')
assert(result.transaction.transactionId==7 and result.transaction.completed and not result.transaction.rejected)
assert(#result.contents==1 and result.contents[1].id==101 and result.contents[1].container==100)
assert(refreshes==1 and bag:getContainer()==player.inventory and marker:getContainer()==bag.inner)
''')

    def test_completed_transaction_accepts_fresh_host_replica(self):
        self.check(r'''
local original=bag;local result=paid(true)
assert(player.inventory:getItemById(100)~=original and result.id==100 and result.callbacks==1)
assert(original:getContainer()==nil and original:getWorldItem()==nil)
''')

    def test_real_walk_requires_begin_perform_displacement_and_arrival(self):
        self.check(r'''
player.x=5.5;approach();assert(#q.queue==0 and state.phase=='approaching')
assert(C.poll(state)=='approaching'and #q.queue==1 and state.walkStarted)
local walk=state.walk;assert(walk.maxTime==-1 and not walk.onCompleteFunc and not walk.additionalTest)
player.x=state.destination:getX()+.5;player.y=state.destination:getY()+.5;walk.result=BehaviorResult.Succeeded
assert(C.begin(state,walk,'perform'));clearQueue();C.finish(state,walk,'perform',true)
assert(C.poll(state)=='ready'and state.walkMoved)
action=C.pickup(state);transfer();assert(C.begin(state,action,'perform'))
action.transactionId=0;clearQueue();C.finish(state,action,'perform',true)
local result=C.result(state);assert(result.walkRequired and result.walkStarted and result.walkMoved and result.walkFinished)
''')

    def test_missing_or_duplicate_exact_world_source_is_rejected(self):
        for mutation in (
            'origin.objects={}',
            'origin.objects={world,world}',
            "bag.kind='Base.Bag_Satchel'",
            'bag.world=nil',
            'world.getSquare=function()return square(11,20,0)end',
            'floor.items={}',
            'bag.source=player.inventory',
            'player.inventory:AddItem(item(100,"Base.Bag_Schoolbag"))',
            'bag.inner.items={}',
            'bag.inner:AddItem(item(101,"Base.BookCarpentry1"))',
            'bag.inner:AddItem(item(102,"Base.DumbBell"))',
        ):
            with self.subTest(mutation=mutation):
                self.check('approach();' + mutation + ';refuses(function()C.pickup(state)end)')

    def test_distant_blocked_foreign_or_stale_boundaries_fail_closed(self):
        for mutation in (
            'player.x=12.5', 'player.z=1', 'player.x=11.5;origin.blocked=true',
            'player.dead=true', 'activePlayer={}', 'replacementQueue={}',
            'q.toolkitOperationGeneration=1',
        ):
            with self.subTest(mutation=mutation):
                self.check('approach();' + mutation + ';refuses(function()C.pickup(state)end)')
        self.check('q.queue={{}};refuses(function()approach()end,"idle queue")')
        self.check('approach();spec.bag.id=999;assert(state.spec.bag.id==100)')

    def test_disappearance_and_unearned_callbacks_never_prove_effect(self):
        self.check('pickup();clearQueue();refuses(function()C.poll(state)end,"without completed callback")')
        self.check('player.x=5.5;approach();C.poll(state);clearQueue();refuses(function()C.poll(state)end,"without native arrival")')
        self.check('pickup();transfer();refuses(function()C.finish(state,action,"perform",true)end,"callback")')
        self.check('pickup();refuses(function()C.result(state)end,"before completed pickup")')

    def test_failed_transaction_and_forged_action_members_do_not_pay(self):
        for mutation in (
            'done=false', 'rejected=true', 'action.transactionId=0', 'action.transactionId=1.5',
            'action.character={}', 'action.srcContainer=player.inventory', 'action.destContainer=floor',
            'action.item=item(999,"Base.Bag_Schoolbag")', 'setmetatable(action,{})',
            'action.perform=function()end', 'action.onCompleteFunc=function()end',
            'action.queueList={}', 'action.queueList[1].items={bag,bag}',
            'action.queueList[1].items={item(100,"Base.Bag_Schoolbag")}',
            'action.started=false', 'origin.objects={world}', 'bag.favorite=false',
            'bag.inner.items={}', 'player.inventory:AddItem(item(100,"Base.Bag_Schoolbag"))',
        ):
            with self.subTest(mutation=mutation):
                self.check('pickup();transfer();' + mutation + ';refuses(function()C.begin(state,action,"perform")end)')

    def test_preexisting_foreign_callbacks_are_rejected_before_admission(self):
        module = json.dumps(str(MODULE))
        self.check('''
ISInventoryTransferAction.perform=function()end
C=dofile(''' + module + ''')
approach();refuses(function()C.pickup(state)end,'provenance')
assert(#q.queue==0 and not state.pickupStarted and bag:getContainer()==floor)
''')
        self.check('''
ISWalkToTimedAction.perform=function()end
C=dofile(''' + module + ''')
player.x=5.5;refuses(function()approach()end,'provenance');assert(#q.queue==0)
''')
        self.check('''
local constructor=ISInventoryTransferUtil.newInventoryTransferAction
ISInventoryTransferUtil.newInventoryTransferAction=function(...)
 local action=constructor(...);action.perform=function()end;return action
end
approach();refuses(function()C.pickup(state)end,'provenance');assert(#q.queue==0)
''')
        self.check('ISWalkToTimedAction.new=function()error("foreign constructor must not run")end;player.x=5.5;refuses(function()approach()end,"provenance")')
        self.check('adoptedFloorPolicy=true;local result=paid();assert(result.callbacks==1)')
        self.check('changedWalkSource=true;player.x=5.5;refuses(function()approach()end,"provenance")')

    def test_foreign_callbacks_ignored_but_duplicate_or_failed_owned_callbacks_fail(self):
        self.check('pickup();assert(not C.begin(state,{},"perform"));C.finish(state,{},"perform",true);assert(not state.performCount)')
        self.check('pickup();transfer();C.begin(state,action,"perform");refuses(function()C.begin(state,action,"perform")end,"unique start")')
        for finish in ('false', 'true'):
            self.check('pickup();transfer();C.begin(state,action,"perform");refuses(function()C.finish(state,action,"perform",' + finish + ')end,"callback")')
        self.check('paid();refuses(function()C.finish(state,action,"perform",true)end,"callback")')
        self.check('pickup();refuses(function()C.begin(state,action,"start")end,"start repeated")')
        self.check('paid();player.inventory:Remove(bag);refuses(function()C.result(state)end,"settled pickup")')

    def test_actual_native_constructors_keep_unmodified_movement_and_transfer(self):
        game = os.environ.get('PZ_GAME')
        if not game:
            self.skipTest('PZ_GAME required for native constructors')
        lua = Path(game) / 'media/lua'
        walk = (lua / 'client/TimedActions/WalkToTimedAction.lua').read_text()
        self.assertEqual(zlib.adler32(walk.encode()), 2037641019)
        transfer = (lua / 'client/TimedActions/ISInventoryTransferAction.lua').read_text()
        constructor = transfer[transfer.index('function ISInventoryTransferAction:new'):transfer.index('function javaTransferItems')]
        # Execute the real walk class and transfer constructor; actual effects are
        # deliberately doubled and remain separate from native gameplay evidence.
        base = r'''
package.preload['TimedActions/ISBaseTimedAction']=function()return true end
ISBaseTimedAction={derive=function(self,name)local value={Type=name};value.__index=value;return value end}
'''
        self.check(r'''
player.x=5.5;approach();assert(C.poll(state)=='approaching'and state.walk.maxTime==-1)
assert(state.walk.stopOnWalk==false and state.walk.stopOnRun==false and not state.walk.additionalTest)
player.x=state.destination:getX()+.5;player.y=state.destination:getY()+.5;state.walk.result=BehaviorResult.Succeeded
C.begin(state,state.walk,'perform');clearQueue();C.finish(state,state.walk,'perform',true);assert(C.poll(state)=='ready')
action=C.pickup(state);assert(action.maxTime==-1 and action.transactionId==0 and action.queueList[1].items[1]==bag)
transfer();assert(C.begin(state,action,'perform'));action.transactionId=0;clearQueue();C.finish(state,action,'perform',true)
assert(C.result(state).callbacks==1)
''', native=base + walk + '\n' + constructor)


if __name__ == '__main__':
    unittest.main()
