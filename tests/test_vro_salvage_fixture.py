"""Exercise observation gates; doubles do not qualify installed VSO gameplay."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

SOURCE = Path(__file__).parent / 'native_queue/vro-gameplay/shared/VROSalvageChecks.lua'

HARNESS = r'''
-- Match the installed Kahlua global surface rather than desktop Lua's extras.
next=nil
clock=0; getTimestampMs=function()return clock end
Perks={MetalWelding='MetalWelding'}
local function list(items)
 items=items or {};function items:size()return #self end
 function items:get(index)return self[index+1]end;return items
end
ground=list()
local function groundItem(id,kind)
 local item={getID=function()return id end,getFullType=function()return kind end}
 return {getItem=function()return item end}
end
ground[1]=groundItem(999,'Base.Apple')
square={getWorldObjects=function()return ground end}
getCell=function()return {getGridSquare=function(_,x,y,z)
 assert(x==40 and y==50 and z==0,'observation escaped exact fixture square');return square end}end
inventory={}
-- Native B42.21 ItemContainer has no getID()/getId() method.
function inventory:getType()return 'inventory'end
torch={uses=10,getID=function()return 11 end}
function torch:getCurrentUses()return self.uses end;function torch:getContainer()return inventory end
function inventory:getItemWithIDRecursiv(id)if id==11 and not missingTorch then return torch end end
mask={getID=function()return 12 end}
player={xp=100,worn=false,getInventory=function()return inventory end,getPlayerNum=function()return 0 end}
function player:getPrimaryHandItem()return self.primary end
function player:getSecondaryHandItem()return nil end
function player:getWornItems()
 return list(self.worn and {{getItem=function()return mask end}} or {})
end
function player:getXp()return {getXP=function(_,perk)assert(perk==Perks.MetalWelding);return self.xp end}end
function player:getPerkLevel(perk)assert(perk==Perks.MetalWelding);return 4 end
function player:isTimedActionInstant()return instant or false end
function player:getCharacterActions()return {size=function()return nativeGhost and 1 or 0 end}end
function player:hasPath()return ghostPath or false end
vehicle={getId=function()return 31 end,isRemovedFromWorld=function()return removed or false end}
getVehicleById=function(id)assert(id==31);if not removed then return vehicle end end
ids={vehicleID=31,torchID=11,maskID=12,metalIDs={},x=40,y=50,z=0}
queue={queue={}}
ISTimedActionQueue={getTimedActionQueue=function(actor)assert(actor==player);return queue end}
ISVehicleSalvage={}
nativeCalls=0;stopCalls=0;hideCalls=0;producerCalls=0
ISVehicleMenu={}
ISVehicleMenu.onVehicleSalvage=function(actor,target)
 assert(actor==player and target==vehicle)
 nativeCalls=nativeCalls+1
 player.primary=torch;player.worn=true
 native={Type='ISVehicleSalvage',character=player,vehicle=vehicle,maxTime=2400,progress=0,started=false}
 function native:isStarted()return self.started end
 function native:getJobDelta()return self.progress end
 native.action={forceStop=function()
  stopCalls=stopCalls+1;queue.queue={};queue.current=nil
 end}
 queue.queue={native};queue.current=native
end
function ISVehicleMenu.FillMenuOutsideVehicle(number,menu,target,test)
 producerCalls=producerCalls+1
 assert(number==0 and target==vehicle and test==false)
 if producerFails then error('producer failed')end
 if not absentOption then menu.options={{onSelect=ISVehicleMenu.onVehicleSalvage,
  target=player,param1=vehicle,notAvailable=disabledOption or false}}end
end
ISContextMenu={get=function(number,x,y)
 assert(number==0 and x==150 and y==150)
 menu={options={},hideAndChildren=function()hideCalls=hideCalls+1 end};return menu
end}
function progress()
 clock=clock+100;native.started=true;native.progress=.1
end
function drain()
 queue.queue={};queue.current=nil
end
function effects()
 removed=true;torch.uses=0;player.xp=128;ground[#ground+1]=groundItem(501,'Base.SteelScrap')
end
'''


class SalvageFixtureTests(unittest.TestCase):
    def runtime(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(HARNESS)
        lua.globals().S = lua.execute(SOURCE.read_text())
        return lua

    def test_observation_preserves_exact_actor_and_sorted_ground_identities(self):
        lua = self.runtime()
        lua.execute('''
        player.primary=torch;player.worn=true
        local seen=S.observe(player,ids)
        assert(seen.vehicleID==31 and not seen.removed and seen.torchID==11 and seen.torchPresent)
        assert(seen.torchUses==10 and seen.torchContainerType=='inventory' and seen.torchContainerID==nil)
        assert(seen.torchInRoot and seen.primaryID==11 and seen.secondaryID==-1 and seen.maskWornID==12)
        assert(seen.metalWeldingXP==100 and #seen.ground==1 and seen.ground[1].id==999)
        assert(seen.ground[1].fullType=='Base.Apple')
        ''')

    def test_sp_direct_vehicle_reference_does_not_require_network_registration(self):
        lua = self.runtime()
        lua.execute('''
        ids.vehicle=vehicle;ids.vehicleID=-1;ids.vehicleKey='salvage'
        function vehicle:getId()return -1 end
        function vehicle:getSquare()return square end
        getVehicleById=function()error('SP direct reference must not use network lookup')end
        local baseline=S.observe(player,ids)
        assert(not baseline.removed and baseline.vehicleID==-1 and baseline.vehicleKey=='salvage')
        assert(baseline.vehicle==nil,'serializable observation leaked local vehicle reference')
        state=S.start(player,ids,'complete');progress();S.poll(state);drain();effects()
        assert(ids.vehicle:getSquare()==square,'removed native reference may retain its square')
        assert(S.observe(player,ids).removed,'retained removed reference must not appear alive')
        assert(S.poll(state)==nil);clock=clock+1501
        local receipt=S.poll(state)
        assert(receipt.vehicleID==-1 and receipt.vehicleKey=='salvage' and receipt.after.removed)
        assert(receipt.vehicle==nil and receipt.before.vehicle==nil and receipt.after.vehicle==nil)
        ''')

    def test_complete_requires_real_effects_and_records_adjusted_native_duration(self):
        lua = self.runtime()
        lua.execute('''
        state=S.start(player,ids,'complete')
        assert(nativeCalls==1 and producerCalls==1 and hideCalls==1)
        progress();assert(S.poll(state)==nil)
        drain();assert(S.poll(state)==nil)
        assert(torch.uses==10 and player.xp==100 and not removed and #ground==1)
        effects();assert(S.poll(state)==nil)
        clock=clock+1501;receipt=S.poll(state)
        assert(receipt and receipt.nativeDuration==2400 and receipt.sourceDuration==1920)
        assert(receipt.started and receipt.menuCallback and not receipt.cancelled)
        assert(#receipt.drops==1 and receipt.drops[1].id==501 and receipt.drops[1].fullType=='Base.SteelScrap')
        assert(receipt.after.primaryID==11 and receipt.after.maskWornID==12)
        assert(S.poll(state)==receipt);S.close(state);assert(hideCalls==1 and nativeCalls==1)
        ''')

    def test_cancel_stops_started_java_action_without_effect_replay(self):
        lua = self.runtime()
        lua.execute('''
        state=S.start(player,ids,'cancel');progress();assert(S.poll(state)==nil)
        assert(stopCalls==1 and nativeCalls==1 and #queue.queue==0)
        clock=clock+1501;local receipt=S.poll(state)
        assert(receipt.cancelled and receipt.started and not receipt.after.removed)
        assert(receipt.after.torchUses==10 and receipt.after.metalWeldingXP==100 and #receipt.drops==0)
        assert(receipt.before.primaryID==-1 and receipt.after.primaryID==11)
        assert(receipt.before.maskWornID==-1 and receipt.after.maskWornID==12)
        assert(stopCalls==1 and #ground==1)
        ''')

    def test_missing_effects_fail_without_manufacturing_results_or_asserting_during_lag(self):
        lua = self.runtime()
        lua.execute('''
        state=S.start(player,ids,'complete');progress();S.poll(state);drain()
        local original=assert;assertCalls=0
        assert=function(condition,message)
          if not condition then assertCalls=assertCalls+1 end
          return original(condition,message)
        end
        S.poll(state);clock=clock+1000;S.poll(state)
        original(assertCalls==0,'expected replication lag must not invoke a failing assert')
        clock=clock+21000
        local ok,reason=pcall(S.poll,state)
        original(not ok and tostring(reason):find('vehicle removal not observed',1,true))
        original(assertCalls==1 and nativeCalls==1 and stopCalls==0)
        original(not removed and torch.uses==10 and player.xp==100 and #ground==1)
        ''')

    def test_no_material_output_is_truthful_inconclusive_failure(self):
        lua = self.runtime()
        lua.execute('''
        local before=S.observe(player,ids);removed=true;torch.uses=0;player.xp=110
        local after=S.observe(player,ids)
        local ok,reason=pcall(S.validate,before,after,'complete')
        assert(not ok and tostring(reason):find('material output inconclusive',1,true))
        ''')

    def test_cancel_rejects_late_effects_and_preexisting_ground_loss(self):
        for effect, reason in [
            ('removed=true', 'removed vehicle'),
            ('torch.uses=9', 'consumed torch'),
            ('player.xp=101', 'awarded XP'),
            ("effects();removed=false;torch.uses=10;player.xp=100", 'produced ground items'),
            ('ground={size=function()return 0 end}', 'preexisting ground item disappeared'),
        ]:
            with self.subTest(effect=effect):
                lua = self.runtime()
                lua.execute('before=S.observe(player,ids);' + effect)
                ok, message = lua.eval("function() return pcall(S.validate,before,S.observe(player,ids),'cancel') end")()
                self.assertFalse(ok)
                self.assertIn(reason, message)

    def test_invalid_menu_closes_owned_ui_without_invoking_callback(self):
        for setup, expected in [('disabledOption=true', 'disabled'), ('absentOption=true', 'absent'),
                                ('producerFails=true', 'producer failed')]:
            with self.subTest(setup=setup):
                lua = self.runtime()
                lua.execute(setup)
                ok, reason = lua.eval("function()return pcall(S.start,player,ids,'complete')end")()
                self.assertFalse(ok)
                self.assertIn(expected, reason)
                lua.execute('assert(nativeCalls==0 and hideCalls==1)')

    def test_ghost_native_action_or_path_delays_receipt_until_truly_quiet(self):
        for ghost in ('nativeGhost', 'ghostPath'):
            with self.subTest(ghost=ghost):
                lua = self.runtime()
                lua.execute('state=S.start(player,ids,"cancel");progress();S.poll(state)')
                lua.execute(ghost + '=true;clock=clock+2000;assert(S.poll(state)==nil)')
                lua.execute(ghost + '=false;assert(S.poll(state)==nil);clock=clock+1501')
                lua.execute('local receipt=S.poll(state);assert(receipt and receipt.nativeActions==0 and receipt.luaActions==0 and not receipt.hasPath)')

    def test_draining_without_progress_and_late_cancellation_are_rejected(self):
        lua = self.runtime()
        lua.execute('state=S.start(player,ids,"complete");drain()')
        ok, reason = lua.eval('function()return pcall(S.poll,state)end')()
        self.assertFalse(ok)
        self.assertIn('before ordinary progress', reason)
        lua = self.runtime()
        lua.execute('state=S.start(player,ids,"cancel");progress();native.progress=.95')
        ok, reason = lua.eval('function()return pcall(S.poll,state)end')()
        self.assertFalse(ok)
        self.assertIn('before completion', reason)
        lua.execute('assert(stopCalls==0)')


if __name__ == '__main__':
    unittest.main()
