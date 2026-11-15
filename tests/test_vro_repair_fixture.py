"""Exercise repair observer gates; mocked effects are not native gameplay proof."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / 'tests/native_queue/vro-gameplay/shared/VRORepairChecks.lua'
JSON_MODULE = ROOT / 'tests/native_queue/health/shared/QueueHealthEvents.lua'
LUA = shutil.which('luajit') or shutil.which('lua')

HARNESS = r'''
next=nil -- Native Kahlua exposes pairs, not next.
clock=0; callbacks=0; closed=0; hidden=0; assertFailures=0;nativeCount=0;events={}
local realPrint=print
function print(value)events[#events+1]=value;realPrint(value)end
local realAssert=assert
function assert(value,message)if not value then assertFailures=assertFailures+1 end;return realAssert(value,message)end
function getTimestampMs()return clock end
function require(name)if name=='QueueHealthEvents'then return queueJSON end;return {}end
Perks={Mechanics='Mechanics',MetalWelding='MetalWelding'}
VRO={IsDiminishingRepairsDisabled=function()return false end,UseVanillaFixingRecipes=function()return false end}
function object(id,kind)
 local o={id=id,kind=kind,condition=40,hbr=0,uses=9}
 function o:getID()return self.id end;function o:getFullType()return self.kind end
 function o:getCondition()return self.condition end;function o:getConditionMax()return 100 end
 function o:getHaveBeenRepaired()return self.hbr end;function o:getCurrentUses()return self.uses end
 return o
end
hood=object(101,'Base.EngineDoor1');torch=object(102,'Base.BlowTorch');mask=object(103,'Base.WeldingMask')
inventory={items={[102]=torch,[103]=mask,[104]=object(104,'Base.SheetMetal'),[105]=object(105,'Base.SheetMetal')}}
function inventory:getItemById(id)return self.items[id]end
part={condition=40};function part:getId()return 'EngineDoor'end
function part:getInventoryItem()return hood end;function part:getCondition()return self.condition end
function part:getArea()return 'Engine'end
function part:getSquare()return{getX=function()return 1 end,getY=function()return 3 end,getZ=function()return 0 end}end
vehicle={id=100};function vehicle:getId()return self.id end
function vehicle:getX()return 1 end;function vehicle:getY()return 2 end;function vehicle:getZ()return 0 end
function vehicle:getPartById(id)assert(id=='EngineDoor');return part end
function getVehicleById(id)if id==100 then return vehicle end end
player={xp={Mechanics=20,MetalWelding=30}}
function player:getInventory()return inventory end;function player:getPlayerNum()return 0 end
function player:getX()return 4.5 end;function player:getY()return 2.5 end;function player:getZ()return 0 end
function player:getCharacterActions()return{size=function()return nativeCount end}end
function player:shouldBeTurning()return self.turning==true end
function player:hasPath()return self.path==true end
function player:pressedMovement(ignore)assert(ignore==false);return self.movementInput==true end
function player:pressedCancelAction()return self.cancelInput==true end
function player:getPerkLevel()return 4 end
function player:getXp()return{getXP=function(_,perk)return player.xp[perk]end}end
ids={vehicleID=100,torchID=102,maskID=103,metalIDs={104,105},x=1,y=2,z=0}
q={queue={}};ISTimedActionQueue={getTimedActionQueue=function()return q end}
function visible(value)return{getIsVisible=function()return value end}end
context=visible(false);mechanics=visible(false)
function getPlayerContextMenu()return context end;function getPlayerMechanicsUI()return mechanics end
UIManager={getUI=function()return{size=function()return 0 end}end}
fixing={name='Fix Hood Welding',time=280,conditionModifier=1,globalItem={item='Base.BlowTorch',uses=3}}
fixer={item='Base.SheetMetal',uses=2,skills={Mechanics=3,MetalWelding=3}}
function startAction()
 callbacks=callbacks+1
 action={Type='VRO_DoFixAction',part=part,fixing=fixing,fixer=fixer,fixerIndex=1,character=player,progress=0}
 function action:isStarted()return self.running end;function action:getJobDelta()return self.progress end
 function action:getDuration()return 280 end
 function action:forceStop()self.stopped=true end
 q.current=action;q.queue={action}
end
ISVehicleMechanics={new=function()
 local w={};function w:initialise()end;function w:addToUIManager()end;function w:setVisible()end
 function w:close()closed=closed+1 end
 function w:doPartContextMenu(target)
  assert(target==part)
  leaf={target=player,onSelect=function(p,prt,fx,fr,index)
   assert(p==player and prt==part and fx==fixing and fr==fixer and index==1);startAction()
  end,param1=part,param2=fixing,param3=fixer,param4=1}
  self.context={options={{subOption=1}},getSubMenu=function()return{options={leaf}}end,
   hideAndChildren=function()hidden=hidden+1 end}
 end
 return w
end}
function tickStarted()action.action={};action.running=true;action.progress=.02;nativeCount=1 end
function drain()q.current=nil;q.queue={};nativeCount=0;clock=500 end
function settle()part.condition=76;hood.condition=76;hood.hbr=1;torch.uses=6;inventory.items[104]=nil;inventory.items[105]=nil
 player.xp.Mechanics=21;player.xp.MetalWelding=31 end
'''


@unittest.skipUnless(LUA, 'Lua runtime is unavailable')
class VRORepairFixtureTests(unittest.TestCase):
    def run_lua(self, test, extra=''):
        source = 'queueJSON=dofile(' + json.dumps(str(JSON_MODULE)) + ')\n' + HARNESS + '\nlocal R=dofile(' + json.dumps(str(MODULE)) + ')\n' + extra + '\n' + test
        result = subprocess.run([LUA, '-'], input=source, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_active_cancel_uses_menu_and_preserves_all_effects(self):
        self.run_lua(r'''
local state=R.start(player,ids,'cancel');assert(callbacks==1)
assert(R.poll(state)==nil and not action.stopped)
tickStarted();assert(R.poll(state)==nil and action.stopped)
drain();assert(R.poll(state)==nil);clock=800
local receipt=assert(R.poll(state));assert(receipt.started and receipt.cancelled and receipt.nativeDuration==280)
assert(R.validate(receipt.before,receipt.after,'cancel'))
R.close(state);R.close(state);assert(closed==1)
''')

    def test_complete_waits_for_native_start_queue_and_replication_without_assert_spam(self):
        self.run_lua(r'''
local state=R.start(player,ids,'complete');assert(R.poll(state)==nil)
tickStarted();assert(R.poll(state)==nil and not action.stopped)
drain();R.poll(state);clock=800
for i=1,5 do assert(R.poll(state)==nil)end
assert(assertFailures==0,'expected replication lag raised a native assertion')
settle();local receipt=assert(R.poll(state));assert(receipt.menuCallback and not receipt.cancelled)
assert(R.poll(state)==receipt and callbacks==1)
''')

    def test_rejects_replacement_item_wrong_resources_and_cancel_xp(self):
        self.run_lua(r'''
local before=R.observe(player,ids);settle();local after=R.observe(player,ids)
assert(R.validate(before,after,'complete'))
after.itemID=999;assert(not pcall(R.validate,before,after,'complete'));after.itemID=before.itemID
after.torch.uses=7;assert(not pcall(R.validate,before,after,'complete'));after.torch.uses=6
after.metal[1].present=true;assert(not pcall(R.validate,before,after,'complete'))
local unchanged=R.observe(player,ids);unchanged.xp.Mechanics=unchanged.xp.Mechanics+1
assert(not pcall(R.validate,R.observe(player,ids),unchanged,'cancel'))
''')

    def test_refuses_unowned_ui_and_keeps_a_later_menu_open(self):
        self.run_lua(r'''
context=visible(true);assert(not pcall(R.start,player,ids,'cancel'));assert(callbacks==0 and closed==0)
context=visible(false);local state=R.start(player,ids,'cancel')
state.window.context.options={};local previouslyHidden=hidden
R.close(state);assert(hidden==previouslyHidden and closed==1)
''')

    def test_duration_and_started_action_are_required(self):
        self.run_lua(r'''
local state=R.start(player,ids,'complete');settle();drain();clock=800
local ok,err=pcall(R.poll,state)
assert(not ok and err:find('drained before ordinary progress',1,true),'paid state cannot prove a running native repair')
''')
        self.run_lua(r'''
local state=R.start(player,ids,'complete');tickStarted();action.getDuration=function()return 1 end
assert(not pcall(R.poll,state),'instant repair escaped the duration gate')
''')

    def test_reports_preparation_and_waits_for_native_drain_without_assert_spam(self):
        self.run_lua(r'''
local state=R.start(player,ids,'cancel');local target=action
local preparation={Type='ISPathFindAction',action={},running=true,progress=0,
 isStarted=action.isStarted,getJobDelta=action.getJobDelta}
q.current=preparation;q.queue={preparation,target};nativeCount=1;player.path=true
assert(R.poll(state)==nil and not target.stopped)
assert(state.observation.currentType=='ISPathFindAction' and state.observation.queueTypes[2]=='VRO_DoFixAction')
assert(state.observation.currentStarted and state.observation.currentProgress==0 and state.observation.partArea=='Engine')
assert(state.observation.partSquare.x==1 and state.observation.partSquare.y==3)
assert(#events==1 and events[1]:find('ACTION_WAIT',1,true))
clock=1000;R.poll(state);assert(#events==1,'unchanged waiting stage flooded diagnostics')
clock=5000;R.poll(state);assert(#events==2,'periodic waiting evidence missing')
q.current=target;q.queue={target};player.path=false;tickStarted();R.poll(state)
assert(target.stopped and #events==3,'native action transition was not observed')
q.current=nil;q.queue={};clock=5100;R.poll(state)
assert(state.quietSince==nil,'Lua queue drain hid an active native action')
nativeCount=0;clock=5200;assert(R.poll(state)==nil);clock=5500
assert(R.poll(state).cancelled and assertFailures==0)
''')

    def test_preparation_drain_fails_early_with_serializable_queue_evidence(self):
        self.run_lua(r'''
local state=R.start(player,ids,'cancel')
q.current={Type='ISPathFindAction'};q.queue={q.current,action};nativeCount=1
assert(R.poll(state)==nil)
q.current=nil;q.queue={};clock=400
assert(R.poll(state)==nil,'native preparation still present was mistaken for complete drain')
drain();local ok,err=pcall(R.poll,state)
assert(not ok and clock<120000 and err:find('drained before ordinary progress',1,true))
assert(err:find('"currentType":"none"',1,true) and err:find('"nativeActions":0',1,true))
assert(callbacks==1 and not action.stopped,'observer replayed or stopped preparation')
''')

    def test_timeout_includes_observed_native_preparation_state(self):
        self.run_lua(r'''
local state=R.start(player,ids,'cancel')
q.current={Type='ISPathFindAction',action={},running=true,progress=0,
 isStarted=action.isStarted,getJobDelta=action.getJobDelta}
q.queue={q.current,action};nativeCount=1;player.path=true;player.turning=true;clock=120000
local ok,err=pcall(R.poll,state)
assert(not ok and err:find('native repair did not settle',1,true) and not err:find(': nil',1,true))
assert(err:find('ISPathFindAction',1,true) and err:find('"turning":true',1,true)
 and err:find('"currentProgress":0',1,true) and err:find('"nativeActions":1',1,true))
assert(callbacks==1 and not action.stopped)
''')

    def test_vehicle_path_diagnostics_capture_exact_native_goal_and_input_without_mutation(self):
        self.run_lua(r'''
local state=R.start(player,ids,'cancel');local target=action;local areaReads=0;local pathReads=0
function vehicle:getAreaCenter(area)
 assert(area=='Engine');areaReads=areaReads+1
 return {getX=function()return 1.25 end,getY=function()return 4.75 end}
end
local path={getTargetX=function()return 1.25 end,getTargetY=function()return 4.75 end,getTargetZ=function()return 0 end,
 update=function()error('observer must not advance native pathfinding')end,
 pathToVehicleArea=function()error('observer must not replay native pathfinding')end}
function player:getPathFindBehavior2()pathReads=pathReads+1;return path end
local loaded=true
function getCell()return{getGridSquare=function(_,x,y,z)
 assert(x==1 and y==4 and z==0,'observer used vehicle origin instead of fractional path target')
 if not loaded then return nil end
 return{isFree=function(_,ignore)assert(ignore==false);return false end,
 TreatAsSolidFloor=function()return true end,isSolid=function()return false end,isSolidTrans=function()return true end}
end}end
q.current={Type='ISPathFindAction',goal={'VehicleArea',vehicle,'Engine'},action={},running=true,progress=0,
 isStarted=target.isStarted,getJobDelta=target.getJobDelta}
q.queue={q.current,target};nativeCount=1;player.movementInput=true;player.cancelInput=true
assert(R.poll(state)==nil)
local observed=state.observation;local route=observed.path
assert(observed.pathVehicleMatches and observed.pressedMovement and observed.pressedCancel)
assert(route.area=='Engine' and route.areaCenter.x==1.25 and route.areaCenter.y==4.75)
assert(route.target.x==1.25 and route.target.y==4.75 and route.target.z==0)
assert(route.targetSquare.loaded and not route.targetSquare.free and route.targetSquare.solidFloor
 and not route.targetSquare.solid and route.targetSquare.solidTrans)
loaded=false;R.poll(state);assert(not state.observation.path.targetSquare.loaded)
q.current.goal[2]={};R.poll(state)
assert(not state.observation.pathVehicleMatches and state.observation.path==nil and areaReads==2 and pathReads==2)
assert(callbacks==1 and not target.stopped,'diagnostics changed the producer or action')
''')

    def test_sp_direct_reference_avoids_network_lookup_and_guards_reference(self):
        self.run_lua(r'''
vehicle.id=-1;ids.vehicleID=-1;ids.vehicle=vehicle;ids.vehicleKey='repair'
getVehicleById=function()error('SP must not use the network registry')end
local state=R.start(player,ids,'cancel');assert(state.before.vehicleID==-1 and state.before.vehicleKey=='repair')
tickStarted();R.poll(state);drain();R.poll(state);clock=800
local receipt=assert(R.poll(state));assert(receipt.vehicleKey=='repair' and not receipt.before.vehicle and not receipt.after.vehicle)
local changed={getId=function()return -1 end};ids.vehicle=changed
state.receipt=nil;assert(not pcall(R.poll,state),'SP exact reference replacement was accepted')
ids.vehicle=vehicle;vehicle.id=123;assert(not pcall(R.resolve,ids),'SP changed ID was accepted')
''')

    def test_installed_upstream_formula_and_recipe_contract(self):
        source_root = os.environ.get('PZ_VRO_MOD_DIR')
        if not source_root:
            self.skipTest('Set PZ_VRO_MOD_DIR to audit installed upstream source')
        lua = Path(source_root) / 'media/lua'
        recipes = (lua / 'client/VRO_Recipes.lua').read_text()
        hood_recipe = recipes[recipes.index('name = "Fix Hood Welding"'):]
        hood_recipe = hood_recipe[:hood_recipe.index('name = "Fix Hood"')]
        for contract in (r'require\s*=\s*"@Hood_All"', r'time\s*=\s*280',
                         r'conditionModifier\s*=\s*1\.0', r'item\s*=\s*"Base.BlowTorch",\s*uses\s*=\s*3',
                         r'item\s*=\s*"Base.SheetMetal",\s*uses\s*=\s*2,\s*skills\s*=\s*\{ MetalWelding = 3, Mechanics = 3 \}'):
            self.assertRegex(hood_recipe, contract)
        commands = (lua / 'server/VRO_VehicleCommands.lua').read_text()
        start = commands.index('local function chanceOfFail(')
        end = commands.index('local function consumeUses(', start)
        # Execute the actual installed pure repair math, never a copied oracle.
        math_source = '''local function clamp(v,a,b)return math.max(a,math.min(b,v))end
local function perkLevel()return 4 end
''' + commands[start:end] + '''
assert(chanceOfFail(player,{Mechanics=3,MetalWelding=3},0)==0)
local percent=repairedPercent(player,1,{Mechanics=3,MetalWelding=3},0,1)
assert(percent==60 and 40+math.floor((100-40)*percent/100+.5)==76)
'''
        self.run_lua('', math_source)
        self.assertRegex(commands, r'addXp\(player, perk, ZombRand\(3,6\)\)')
        action = (lua / 'shared/TimedActions/VRO_DoFixAction.lua').read_text()
        stop = action[action.index('function VRO.DoFixAction:stop()'):action.index('function VRO.DoFixAction:perform()')]
        self.assertNotIn('sendClientCommand', stop)
        self.assertIn("sendClientCommand(self.character, 'VRO_vehicle', 'doFix', args)", action)


if __name__ == '__main__':
    unittest.main()
