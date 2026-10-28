"""Run the actual SP controls fixture with native menu, world and action doubles."""
import json
from pathlib import Path
import unittest

try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None


PROJECT = Path(__file__).resolve().parent.parent
FIXTURE = PROJECT / 'tests/native_queue/contributions/wooden_cart_motion/scenario-controls.lua'
SHARED_ACTIONS = PROJECT / 'PZSurvivorToolkit/42/media/lua/shared/ToolkitWoodCartActions.lua'
CLIENT_ACTIONS = PROJECT / 'PZSurvivorToolkit/42/media/lua/client/ZZToolkitWoodCartActions.lua'
HARNESS = r'''
logs={};clock=1000;frame=0;videoStarts=0;videoStops=0;menuCalls=0;dropCalls=0;poseCalls=0
fault='';approach=false;drive=0;gait=0;dropMenuCalls=0;durationValue=50;durationAdjustment=0
print=function(line) logs[#logs+1]=line end
require=function() return true end
getTimestampMs=function() return clock end
getWorld=function() return {getWorld=function() return 'CartTestArea' end} end
isClient=function() return false end;isServer=function() return false end;setGameSpeed=function() end
Perks={Sprinting=1};CharacterStat={ENDURANCE=1};Keyboard={KEY_F5=1}
Events={OnTick={Add=function(cb) tick=cb end,Remove=function() end},
 OnPlayerUpdate={Add=function() end},OnPlayerDeath={Add=function() end},OnMainMenuEnter={Add=function() end}}
getActivatedMods=function() return {contains=function() return true end} end
local function list(values)
 return {size=function() return #values end,get=function(_,i) return values[i+1] end,isEmpty=function() return #values==0 end}
end
cargo={id=99,getID=function(self) return self.id end,setActualWeight=function() end,setCustomWeight=function() end}
local contents={}
bag={getItems=function() return list(contents) end,getCapacityWeight=function() return bag.weight or #contents end,
 AddItem=function() contents[1]=cargo;return cargo end}
local inventoryItems={}
inventory={getItems=function() return list(inventoryItems) end}
item={getID=function() return 42 end,getFullType=function() return 'SaucedCarts.ShoppingCart' end,
 getInventory=function() return bag end,getContainer=function(self) return self.container end,
 getWorldItem=function(self) return self.world end,container=inventory}
inventoryItems[1]=item
world={getItem=function() return item end}
local square={};local floor={getSquare=function() return square end};square.getFloor=function() return floor end
p={primary=item,secondary=item,x=0,y=0,z=0,
 getPrimaryHandItem=function(self) return self.primary end,getSecondaryHandItem=function(self) return self.secondary end,
 getInventory=function() return inventory end,getPlayerNum=function() return 0 end,
 getCurrentSquare=function() return square end,
 isTimedActionInstant=function() return false end,setPerkLevelDebug=function() end,
 getXp=function() return {setXPToLevel=function() end} end,
 getStats=function() return {reset=function() end} end,
 getX=function(self) return self.x end,getY=function(self) return self.y end,getZ=function(self) return self.z end,
 setX=function(self,x) self.x=x end,setY=function(self,y) self.y=y end,setZ=function(self,z) self.z=z end,
 setNextX=function() end,setNextY=function() end,setLastX=function() end,setLastY=function() end,
 ensureOnTile=function() end,setCurrentSquareFromPosition=function() end,setMovingSquareNow=function() end,
 isRunning=function() return gait==1 end,isSprinting=function() return gait==2 end,
 hasPath=function() return current and current.Type=='ISWalkToTimedActionF' or false end,
 getCharacterActions=function() return {isEmpty=function() return current==nil end,size=function() return current and 1 or 0 end} end}
getPlayer=function() return p end
CartTestArea={ready=true,x=0,y=0,z=0,checkPosition=function() end}
CartLabKey=function() error('Unexpected fixture cycling') end
CartLabSelectScenes=function(cases) return {cases[1]} end
cartLabDrive=function(value) drive=value end;cartLabGait=function(value) gait=value end
cartLabHeading=function() return 0 end;cartLabSteeringHeading=function() return 0 end
cartLabFrame=function() return frame end;cartLabPoseHeading=function() poseCalls=poseCalls+1 end
toolkitVideoStart=function() videoStarts=videoStarts+1;return true end
toolkitVideoStop=function() videoStops=videoStops+1;return true end
toolkitVideoStatus=function() return {state=videoStops>0 and 'completed' or 'recording',file='test.mp4',frames=frame,seconds=clock/1000} end
local emptySquare={getWorldObjects=function() return list({}) end}
local ownedSquare={getWorldObjects=function() return list(item.world and {world} or {}) end}
getCell=function() return {getGridSquare=function(_,x,y) return x==0 and y==0 and ownedSquare or emptySquare end} end
q={queue={}}
ISTimedActionQueue={getTimedActionQueue=function() return q end,
 addToQueue=function(queue,value) current=value;queue.queue={value} end}
local function base(name)
 local class={Type=name};class.__index=class
 function class:derive(derived)
  local child={Type=derived};child.__index=child;return setmetatable(child,{__index=self})
 end
 return class
end
ISUnequipAction=base('ISUnequipAction');ISCartPickupAction=base('ISCartPickupAction')
ISDropWorldItemAction=base('ISDropWorldItemAction');ISWalkToTimedActionF=base('ISWalkToTimedActionF')
toolkitWoodCartUpdate=function() end
toolkitWoodCartStance=function() return {x=0,y=0} end
toolkitWoodCartDropPose=function() return {x=0,y=0,z=0,rotation=0} end
SaucedCarts={}

local function action(kind)
 return setmetatable({character=p,item=item,itemId=42,toolkitWoodCartItem=item,maxTime=durationValue,at=clock,progress=0,
  getDuration=function() return durationValue end,getJobDelta=function(self) return self.progress end,
  findItem=function() return item end,findWorldItem=function() return world end,
  isStarted=function(self) return self.action~=nil end},_G[kind])
end
ISCartPickupAction.new=function() return action('ISCartPickupAction') end
ISCartPickupAction.FromWorldItem=function() end
local function enqueue(kind)
 if fault=='missing' then return end
 local value=kind=='ISCartPickupAction' and ISCartPickupAction:new(p,0,0,0,42) or action(kind)
 ISTimedActionQueue.addToQueue(q,value)
end
ISInventoryPaneContextMenu={onUnEquip=function(items,num)
 assert(items[1]==item and #items==1 and num==0);dropCalls=dropCalls+1;enqueue('ISUnequipAction')
end}
getText=function(key) return key end
local pickupCallback=function(actual,num,actualWorld)
 assert(actual[1]==world and num==0 and actualWorld==world and item.world==world);menuCalls=menuCalls+1
 enqueue(approach and 'ISWalkToTimedActionF' or 'ISCartPickupAction')
end
local leaf={}
ISContextMenu={get=function(num,x,y) assert(num==0 and x==50 and y==50);return {
 options={},getSubMenu=function() return leaf end,hideAndChildren=function() hidden=true end} end}
ISWorldObjectContextMenu={createMenu=function(num,objects,x,y,test)
 assert(num==0 and objects[1]==floor and x==50 and y==50 and not test);dropMenuCalls=dropMenuCalls+1
 local target={item}
 if fault=='wrong-menu' then target={} end
 return {options={{subOption=1}},getSubMenu=function() return {options={{name='ContextMenu_DropNamedItem',
  target=target,param1=0,onSelect=ISInventoryPaneContextMenu.onUnEquip,notAvailable=fault=='unavailable'}}} end,
 hideAndChildren=function() hidden=true end}
end}
triggerEvent=function(name,num,context,objects,test)
 assert(name=='OnFillWorldObjectContextMenu' and num==0 and objects[1]==world and not test)
 leaf.options={{name='UI_SaucedCarts_PushCart',target=objects,param1=0,param2=world,onSelect=pickupCallback}}
 context.options={{subOption=1}}
end
function advance(ms)
 clock=clock+ms;frame=frame+1
 if current then
  if fault~='no-start' and not current.action then
   current.maxTime=current.maxTime+durationAdjustment
   local nativeTime=math.floor(current.maxTime)
   current.action={getTime=function() return fault=='duration' and 1 or nativeTime end}
  end
  current.progress=math.min(.8,(clock-current.at)/400)
  if fault~='stall' and clock-current.at>=400 then
   local kind=current.Type;current=nil;q.queue={}
   if kind=='ISWalkToTimedActionF' then enqueue('ISCartPickupAction')
   elseif kind=='ToolkitWoodCartSetdown' then
    if fault~='wrong-drop' then item.world=world;item.container=nil;inventoryItems={};p.primary=nil;p.secondary=nil end
   elseif kind=='ToolkitWoodCartPickup' then
    if fault~='wrong-pickup' then item.world=nil;item.container=inventory;inventoryItems={item};p.primary=item;p.secondary=item end
   end
  end
 end
 if WoodPrototypeTick then WoodPrototypeTick() end
end
function corruptCargo() cargo.id=100 end
function duplicateWorld() inventoryItems={item};item.world=world end
'''


@unittest.skipUnless(LuaRuntime, 'Requires Lupa Lua51')
class CartSPVisualExtendedTests(unittest.TestCase):
    def boot(self, extended=True, setup=''):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(HARNESS)
        lua.globals().transitions = lua.execute(SHARED_ACTIONS.read_text())
        lua.globals().require = lua.eval("function(name) if name=='ToolkitWoodCartActions' then return transitions end;return true end")
        lua.execute(CLIENT_ACTIONS.read_text())
        lua.execute('CartMotionConfig={disposable=true,videoRoot="test",ffmpeg="ffmpeg",controlsExtended=' +
                    ('true' if extended else 'false') + '}\n' + setup)
        lua.execute(FIXTURE.read_text())
        return lua

    def lines(self, lua):
        return list(lua.globals().logs.values())

    def rows(self, lua, event, prefix='CART_CONTROLS_ACTION'):
        marker = f'[{prefix}] {event} '
        return [json.loads(line[len(marker):]) for line in self.lines(lua) if line.startswith(marker)]

    def run_to(self, lua, predicate, limit=3000):
        for _ in range(limit):
            if predicate():
                return
            lua.globals().advance(25)
        self.fail('Fixture did not reach requested state')

    def run_done(self, lua):
        self.run_to(lua, lambda: lua.globals().WoodPrototypeTick is None)

    def assert_failure(self, lua, message):
        self.run_done(lua)
        failures = [line for line in self.lines(lua) if '[CART_CONTROLS] FAIL ' in line]
        self.assertEqual(len(failures), 1, self.lines(lua)[-10:])
        self.assertIn(message, failures[0])
        self.assertFalse(any('[CART_CONTROLS] ALL_COMPLETE' in line for line in self.lines(lua)))

    def test_default_retains_original_eighteen_phases_without_action_menus(self):
        lua = self.boot(extended=False)
        self.run_done(lua)
        self.assertEqual(len(self.rows(lua, 'PHASE', 'CART_CONTROLS')), 18)
        self.assertEqual(lua.globals().dropCalls, 0)
        self.assertEqual(lua.globals().menuCalls, 0)
        self.assertEqual(lua.globals().videoStarts, 1)
        self.assertEqual(lua.globals().videoStops, 1)

    def test_extended_corrections_and_native_actions_share_one_video_with_settled_tails(self):
        lua = self.boot(setup='approach=true')
        self.run_done(lua)
        self.assertFalse(any(' FAIL ' in line for line in self.lines(lua)), self.lines(lua)[-10:])
        phases = self.rows(lua, 'PHASE', 'CART_CONTROLS')
        self.assertEqual([r['phase'] for r in phases[-5:]], [
            'correction-left', 'correction-left-release', 'correction-right', 'correction-right-release', 'correction-stop'])
        for name in ('correction-left', 'correction-right'):
            samples = [r for r in self.rows(lua, 'SAMPLE', 'CART_CONTROLS') if r['phase'] == name]
            self.assertEqual([r['elapsed'] for r in samples[:8]], list(range(0, 200, 25)))
        self.assertEqual(lua.globals().videoStarts, 1)
        self.assertEqual(lua.globals().videoStops, 1)
        self.assertEqual(lua.globals().dropCalls, 1)
        self.assertEqual(lua.globals().dropMenuCalls, 1)
        self.assertEqual(lua.globals().menuCalls, 1)
        self.assertTrue(lua.globals().hidden)
        for event in ('BEGIN', 'QUEUED', 'COMPLETE'):
            self.assertEqual([r['phase'] for r in self.rows(lua, event)], ['drop', 'pickup'])
        rows = self.rows(lua, 'SAMPLE')
        self.assertEqual(sorted({row['wall'] for row in rows}), [row['wall'] for row in rows])
        self.assertEqual(sorted({row['frame'] for row in rows}), [row['frame'] for row in rows])
        self.assertTrue(any(r['actionType'] == 'ISWalkToTimedActionF' for r in rows))
        for phase, kind in (('drop', 'ToolkitWoodCartSetdown'), ('pickup', 'ToolkitWoodCartPickup')):
            self.assertTrue(any(r['phase'] == phase and r['actionType'] == kind and r['started'] and
                                r['nativeStarted'] and 0 < r['progress'] < 1 for r in rows))
        drop, pickup = self.rows(lua, 'COMPLETE')
        for row in (drop, pickup):
            self.assertEqual((row['id'], row['cargoID'], row['cargoWeight']), (42, 99, 1))
            self.assertEqual((row['luaActions'], row['nativeActions'], row['hasPath']), (0, 0, False))
            self.assertGreaterEqual(row['settledElapsed'], 700)
            self.assertTrue(row['progressed'])
            tail = [r for r in rows if r['phase'] == row['phase'] and r['wall'] >= row['wall'] - 650]
            self.assertGreaterEqual(len(tail), 4)
            self.assertGreaterEqual(tail[-1]['wall'] - tail[0]['wall'], 500)
            self.assertTrue(all(r['luaActions'] == r['nativeActions'] == 0 and not r['hasPath'] for r in tail))
        self.assertEqual((drop['primaryID'], drop['secondaryID'], drop['worldID'], drop['worldCount'], drop['inventoryCount']), (-1, -1, 42, 1, 0))
        self.assertEqual((pickup['primaryID'], pickup['secondaryID'], pickup['worldCount'], pickup['inventoryCount']), (42, 42, 0, 1))
        self.assertLess(drop['wall'], pickup['wall'])
        self.assertLess(drop['frame'], pickup['frame'])

    def test_missing_action_stall_and_missing_native_start_fail_closed(self):
        for fault, message in (('missing', 'queued no action'), ('stall', 'timed out'),
                               ('no-start', 'without started native progress'), ('duration', 'duration differs')):
            with self.subTest(fault=fault):
                self.assert_failure(self.boot(setup=f'fault="{fault}"'), message)

    def test_fractional_duration_and_physiological_adjustment_keep_native_conversion(self):
        for duration, adjustment in ((50.5, .375), (50.75, .5), (50, 10)):
            with self.subTest(duration=duration, adjustment=adjustment):
                lua = self.boot(setup=f'durationValue={duration};durationAdjustment={adjustment}')
                self.run_done(lua)
                self.assertFalse(any(' FAIL ' in line for line in self.lines(lua)), self.lines(lua)[-10:])
                progressing = [row for row in self.rows(lua, 'SAMPLE') if row['nativeStarted']]
                self.assertTrue(progressing)
                for row in progressing:
                    self.assertEqual(row['duration'], duration)
                    self.assertEqual(row['luaMaxTime'], duration + adjustment)
                    self.assertEqual(row['nativeMaxTime'], int(duration + adjustment))
                # The fixture observes the stock create adjustment without rewriting it.
                self.assertEqual(self.rows(lua, 'QUEUED')[0]['luaMaxTime'], duration)

    def test_shortened_lua_duration_and_wrong_native_conversion_are_rejected(self):
        lua = self.boot(setup='durationValue=50.5;durationAdjustment=-.5')
        self.assert_failure(lua, 'native action duration changed')
        lua = self.boot(setup='durationValue=50.5;durationAdjustment=.375')
        self.run_to(lua, lambda: any(r['nativeStarted'] for r in self.rows(lua, 'SAMPLE')))
        lua.execute('current.action.getTime=function() return 51 end')
        self.assert_failure(lua, 'native duration differs')

    def test_wrong_drop_and_pickup_endpoint_fail_closed(self):
        for fault, message in (('wrong-drop', 'Drop did not transfer'), ('wrong-pickup', 'Pickup did not retain')):
            with self.subTest(fault=fault):
                self.assert_failure(self.boot(setup=f'fault="{fault}"'), message)

    def test_wrong_and_unavailable_real_menu_options_fail_before_callback(self):
        for fault in ('wrong-menu', 'unavailable'):
            with self.subTest(fault=fault):
                lua = self.boot(setup=f'fault="{fault}"')
                self.assert_failure(lua, 'menu option unavailable')
                self.assertEqual(lua.globals().dropCalls, 0)

    def test_cargo_corruption_and_duplicate_ownership_during_action_are_rejected(self):
        for mutation, message in (('corruptCargo()', 'cargo identity/weight'), ('bag.weight=2', 'cargo identity/weight'),
                                  ('duplicateWorld()', 'lost/duplicated cart ownership')):
            with self.subTest(mutation=mutation):
                lua = self.boot()
                self.run_to(lua, lambda: bool(self.rows(lua, 'QUEUED')))
                lua.execute(mutation)
                self.assert_failure(lua, message)

    def test_native_action_identity_and_queue_bounds_remain_frozen(self):
        for mutation, message in ((
            'local copy={};for k,v in pairs(current) do copy[k]=v end;setmetatable(copy,getmetatable(current));q.queue[1]=copy', 'native action identity changed'),
            ('current.action={getTime=function() return 50 end}', 'native action identity changed'),
            ('q.queue[2]=current;q.queue[3]=current', 'queue bounds exceeded'),
            ('current.item={}', 'cart binding changed'),
            ('current.Type="ISUnequipAction"', 'Unexpected controls native action')):
            with self.subTest(mutation=mutation):
                lua = self.boot()
                self.run_to(lua, lambda: any(r['nativeStarted'] for r in self.rows(lua, 'SAMPLE')))
                lua.execute(mutation)
                self.assert_failure(lua, message)

    def test_settled_endpoint_is_rechecked_until_tail_completes(self):
        lua = self.boot()
        self.run_to(lua, lambda: any(row['phase'] == 'drop' and row['luaActions'] == 0 for row in self.rows(lua, 'SAMPLE')))
        lua.execute('p.primary=item')
        self.assert_failure(lua, 'Drop did not transfer')
        self.assertEqual(self.rows(lua, 'COMPLETE'), [])

    def test_extended_configuration_rejects_extra_scenes_and_instant_actions(self):
        for setup, error in (("CartLabSelectScenes=function(cases) return cases end", 'only shopping-cart'),
                             ('p.isTimedActionInstant=function() return true end', 'Native action durations required')):
            with self.subTest(setup=setup), self.assertRaisesRegex(Exception, error):
                self.boot(setup=setup)


if __name__ == '__main__':
    unittest.main()
