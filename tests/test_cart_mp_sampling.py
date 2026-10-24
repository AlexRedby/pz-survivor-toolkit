"""Exercise the real MP client tick with mock native APIs and strict coverage gates."""
import json
from pathlib import Path
import runpy
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'tests/native_queue/contributions/wooden_cart_multiplayer'
COVERAGE = runpy.run_path(str(SOURCE / 'analyze.py'))['coverage']
EPOCH = 100000
# Recorded state times around a real turn-window trailing-edge failure.
COARSE_TICKS = [5509, 5629, 5744, 5844, 5959, 6070, 6212, 6314,
                6414, 6530, 6630, 6745, 6855, 7013, 7115, 7545]


@unittest.skipUnless(shutil.which('luajit'), 'LuaJIT required')
class CartMPSamplingTests(unittest.TestCase):
    def run_client(self, ticks, *, role='client1', legacy=False):
        source = (SOURCE / 'client.lua').read_text()
        if legacy:
            guard = 'if elapsed<=duration or now-lastSample>=100 then'
            self.assertEqual(source.count(guard), 1)
            source = source.replace(guard, 'if now-lastSample>=100 then')
        # Load the complete current script, preserving its setup, phases, action
        # bank and error handling. Only the game/native API surface is mocked.
        script = r'''
local source,role,ticks,epoch=%s,%s,{%s},%s
local now=epoch-10000
local handlers={}
local noOp=function() end
Events=setmetatable({}, {__index=function(_,name)
 return {Add=function(fn) assert(not handlers[name]);handlers[name]=fn end}
end})
local cart={getFullType=function() return 'SaucedWheelbarrow.WheelbarrowWood' end}
local function player(name,id)
 local p={name=name,id=id}
 function p:getUsername() return self.name end
 function p:getPrimaryHandItem() return cart end
 function p:getSecondaryHandItem() return cart end
 function p:getInventory() return {getItemById=function(_,id) assert(id==42);return cart end} end
 function p:getPerkLevel() return 10 end
 function p:getStats() return {reset=noOp} end
 function p:getX() return 10.5 end
 function p:getY() return 20.5 end
 function p:getZ() return 0 end
 for _,name in ipairs({'setGodMod','setGhostMode','setAutoDrink','teleportTo','setX','setY','setZ',
  'setNextX','setNextY','setLastX','setLastY','setLastZ','ensureOnTile',
  'setCurrentSquareFromPosition','setMovingSquareNow','setPrimaryHandItem',
  'setSecondaryHandItem','updateHandEquips'}) do p[name]=noOp end
 return p
end
local owner=player('client1',7)
local observer=player('client2',8)
local localPlayer=role=='client1' and owner or observer
local selection={disposable=true,mode='toolkit',cases={'owner_observer_motion'},ffmpeg='/owned/ffmpeg',
 videoRoot={client1='/owned/client1',client2='/owned/client2'},options={cart_actions=true}}
local actions={sample=function(p,user)
 assert(p==owner and user==role);print('ACTION '..now)
end,tick=function(p,setup,time)
 assert(role=='client1' and p==owner and setup.cartId==42 and time==now)
end,done=function() return false end}
function require(name)
 if name=='QueueTestSelection' then return selection end
 if name=='CartMPJSON' then return {encode=function() return '{}' end,emit=function(row)
  assert(row.event~='error',row.reason);assert(row.event~='complete','Unexpected completion')
 end} end
 if name=='CartMPActions' then return actions end
 assert(name=='SaucedCarts/Core' or name=='SaucedCarts/CartVisuals','Unexpected require '..name)
 return {}
end
PZAPI={ModOptions={getOptions=function() return {getOption=function()
 return {setValue=function(_,value) assert(value==true) end}
end} end}}
SaucedCarts={applyCartPose=noOp,updateCartVisual=noOp}
Perks={Sprinting=1};CharacterStat={ENDURANCE=1}
function getFileReader() return {readLine=function() return role end,close=noOp} end
function getPlayer() return localPlayer end
function getOnlinePlayers() return {size=function() return 2 end,get=function(_,index)
 assert(index==0 or index==1);return index==0 and owner or observer
end} end
function getTimestampMs() return now end
function getCore() return {setOptionPauseOnFocusloss=noOp,setOptionAutoDrink=noOp,
 getZoom=function() return role=='client1' and .25 or 1 end} end
function sendClientCommand(module,command,args)
 assert(module=='CartMP' and command=='Armed','Unexpected client command '..tostring(command))
 print('SEND '..command..' '..now)
end
cartLabDrive=noOp;cartLabGait=noOp;cartLabPoseHeading=noOp
function cartMPZoom(isObserver) return isObserver and 1 or .25 end
function cartMPCamera(p) assert(p==owner) end
cartMPHideUI=noOp
function cartMPState(p) return now..' '..p.id end
function cartMPTraffic() return '{}' end
function toolkitVideoStart() return true end
function toolkitVideoStatus() return {file='/owned/video.mp4',state='recording'} end
assert(loadstring(source,'@client.lua'))()
handlers.OnGameStart()
handlers.OnServerCommand('CartMP','Setup',{variant='wooden-wheelbarrow',
 cartType='SaucedWheelbarrow.WheelbarrowWood',cartId=42,x=10.5,y=20.5,z=0})
handlers.OnServerCommand('CartMP','Start',{epoch=epoch})
for _,elapsed in ipairs(ticks) do now=epoch+elapsed;handlers.OnTick() end
''' % (json.dumps(source), json.dumps(role), ','.join(map(str, ticks)), EPOCH)
        result = subprocess.run([shutil.which('luajit'), '-'], input=script,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        states, actions, sends = [], [], []
        for line in result.stdout.splitlines():
            if line.startswith('[CART_MP_STATE] '):
                when, actor = map(int, line.removeprefix('[CART_MP_STATE] ').split())
                states.append(dict(wall=when, id=actor))
            elif line.startswith('ACTION '):
                actions.append(int(line.split()[1]))
            elif line.startswith('SEND '):
                sends.append(line.split()[1])
        self.assertEqual(sends, ['Armed'], 'Sampling must not introduce client commands')
        return states, actions

    def owner_times(self, rows):
        return [row['wall'] - EPOCH for row in rows if row['id'] == 7]

    def turn_coverage(self, rows):
        return COVERAGE([row for row in rows if row['id'] == 7], 'wall', EPOCH,
                        (5500, 7500), 'owner/turn')

    def test_intervening_native_tick_closes_recorded_trailing_edge(self):
        for role in ('client1', 'client2'):
            with self.subTest(role=role):
                ticks = sorted(COARSE_TICKS + [7162])
                rows, actions = self.run_client(ticks, role=role)
                self.assertEqual(self.owner_times(rows), ticks)
                self.assertEqual([row['wall'] - EPOCH for row in rows if row['id'] == 8], ticks)
                self.assertEqual(sum(row['wall'] == EPOCH + 7162 for row in rows if row['id'] == 7), 1)
                self.assertEqual(actions, [])
                selected = self.turn_coverage(rows)
                self.assertEqual(selected[-1]['wall'], EPOCH + 7162)
                self.assertNotIn(EPOCH + 7545, [row['wall'] for row in selected])

    def test_old_100ms_throttle_discards_actual_edge_tick(self):
        rows, _ = self.run_client(sorted(COARSE_TICKS + [7162]), legacy=True)
        self.assertEqual(self.owner_times(rows), COARSE_TICKS)
        with self.assertRaisesRegex(ValueError, 'missing window edges'):
            self.turn_coverage(rows)

    def test_real_gap_still_fails_without_invented_catchup(self):
        rows, _ = self.run_client(COARSE_TICKS)
        self.assertEqual(self.owner_times(rows), COARSE_TICKS)
        self.assertFalse(any(EPOCH + 7150 <= row['wall'] <= EPOCH + 7500 for row in rows))
        with self.assertRaisesRegex(ValueError, 'missing window edges'):
            self.turn_coverage(rows)

    def test_dense_sampling_is_bounded_and_action_probe_keeps_25ms_cadence(self):
        ticks = [-1, 0, 1, 24, 25, 99, 100, 14999, 15000, 15001, 15024,
                 15025, 15026, 15099, 15100, 15101, 15124, 15125, 15126, 15200]
        for role in ('client1', 'client2'):
            with self.subTest(role=role):
                rows, actions = self.run_client(ticks, role=role)
                expected = [tick for tick in ticks if 0 <= tick <= 15000] + [15100, 15200]
                self.assertEqual(self.owner_times(rows), expected)
                self.assertEqual([row['wall'] - EPOCH for row in rows if row['id'] == 8], expected)
                self.assertEqual([time - EPOCH for time in actions],
                                 [15000, 15025, 15099, 15124, 15200])


    def run_server(self, ticks, *, options=None, start=True, pending=False, legacy=False):
        options = dict(cart_actions=True, cart_fast_motion=True) if options is None else options
        source = (SOURCE / 'server.lua').read_text()
        if legacy:
            gate = 'not inMotion and now-last<'
            self.assertEqual(source.count(gate), 1)
            source = source.replace(gate, 'now-last<')
        option_fields = ','.join(key + '=' + ('true' if value is True else json.dumps(value))
                                 for key, value in options.items())
        script = r"""
local source,ticks,epoch=%s,{%s},%s
local options={%s}
local now=epoch-25000
local handlers={}
Events=setmetatable({}, {__index=function(_,name) return {Add=function(fn) handlers[name]=fn end} end})
local function list(values) return {size=function() return #values end,get=function(_,i) return values[i+1] end} end
local sampling=false
local cargo={getID=function() return 99 end,getFullType=function() return 'Base.Log' end,
 getActualWeight=function() return 70 end,setActualWeight=function() end,setCustomWeight=function() end}
local cargoInventory={getItems=function() return list({cargo}) end,AddItem=function() return cargo end,
 getEffectiveCapacity=function() return 70 end}
local inventory
local cart={getID=function() return 42 end,getFullType=function() return 'SaucedWheelbarrow.WheelbarrowWood' end,
 getInventory=function() return cargoInventory end,getWorldItem=function() return nil end,
 getContainer=function() return inventory end}
inventory={AddItem=function() return cart end,getItems=function() return list({cart}) end}
local square={getWorldObjects=function() return list({}) end}
local size=options.cart_wall_exit and 63 or 31
local origin={x=10.5,y=20.5,z=7,minX=0,minY=0,size=size,margin=2,
 elevated=true,vegetationFree=true,bankVersion=options.cart_wall_exit and 4 or 3}
local function player(user,id)
 return {getUsername=function() return user end,getCurrentSquare=function() return square end,
 getInventory=function() return inventory end,getPrimaryHandItem=function() return cart end,
 getSecondaryHandItem=function() return cart end,getX=function() return 10.5 end,
 getY=function() return 20.5 end,getZ=function() return 7 end,getPerkLevel=function() return 10 end,
 teleportTo=function() end,getCharacterActions=function()
  if sampling then print('POLL '..now) end;return list({})
 end,hasPath=function() return false end,id=id}
end
local owner,observer=player('client1',7),player('client2',8)
function require(name)
 if name=='QueueTestSelection' then return {disposable=true,options=options} end
 if name=='CartMPJSON' then return {encode=function() return '{}' end} end
 if name=='CartMPPlacement' then return function() return origin end end
 if name=='CartMPWall' then return {} end
 error('Unexpected require '..name)
end
function getTimestampMs() return now end
function getCell() return {getGridSquare=function() return square end} end
function sendServerCommand(_,module,command,args)
 assert(not sampling,'Sampling/pending polling sent '..command)
 assert(module=='CartMP')
 assert(command=='Setup' or command=='Start' or command=='ActionPhase','Unexpected server command '..command)
 if command=='Start' then assert(args.epoch==epoch) end
end
function sendAddItemToContainer() assert(not sampling) end
function cartMPSeedSprinting() return 10 end
Perks={Sprinting=1}
function cartMPState(p) return now..' '..p.id end
function cartMPTraffic() return '{}' end
assert(loadstring(source,'@server.lua'))()
local function command(name,p,args) handlers.OnClientCommand('CartMP',name,p,args or {}) end
command('Ready',owner);command('Ready',observer)
if %s then
 local args={sprintLevel=10,padFloors=size*size,padVersion=origin.bankVersion,padWalls=49}
 command('Armed',owner,args);command('Armed',observer,args)
end
if %s then
 now=epoch+ticks[1]
 command('ActionBegin',owner,{index=1,phase='drop-complete',id=42})
 command('ActionCheck',owner,{index=1,phase='drop-complete',id=42})
end
sampling=true
for _,elapsed in ipairs(ticks) do now=epoch+elapsed;handlers.OnTick() end
""" % (json.dumps(source), ','.join(map(str, ticks)), EPOCH, option_fields,
       str(start).lower(), str(pending).lower())
        result = subprocess.run([shutil.which('luajit'), '-'], input=script,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('[QUEUE_TEST] FAIL', result.stdout)
        states, polls = [], []
        for line in result.stdout.splitlines():
            if line.startswith('[CART_MP_STATE] '):
                when, actor = map(int, line.removeprefix('[CART_MP_STATE] ').split())
                states.append(dict(wall=when, id=actor))
            elif line.startswith('POLL '):
                polls.append(int(line.split()[1]) - EPOCH)
        return states, polls

    def test_server_keeps_actual_99ms_ticks_in_short_run_window(self):
        ticks = [15295, 15394, 15494, 15593, 15693, 15792, 15891, 15990, 16094, 16193, 16292]
        rows, _ = self.run_server(ticks)
        self.assertEqual(self.owner_times(rows), ticks)
        self.assertEqual([row['wall'] - EPOCH for row in rows if row['id'] == 8], ticks)
        owner = [row for row in rows if row['id'] == 7]
        selected = COVERAGE(owner, 'wall', EPOCH, (15300, 16200), 'run/server/state')
        self.assertEqual(len(selected), 9)
        old_rows, _ = self.run_server(ticks, legacy=True)
        self.assertEqual([row['wall'] - EPOCH for row in old_rows
                          if row['id'] == 7 and 15300 <= row['wall'] - EPOCH <= 16200],
                         [15494, 15693, 15891, 16094])
        with self.assertRaisesRegex(ValueError, 'fewer than five samples'):
            COVERAGE([row for row in old_rows if row['id'] == 7], 'wall', EPOCH,
                     (15300, 16200), 'run/server/state')

    def test_server_actual_no_tick_gap_still_fails_coverage(self):
        ticks = [15295, 15494, 15693, 15891, 16094, 16292]
        rows, _ = self.run_server(ticks)
        self.assertEqual(self.owner_times(rows), ticks)
        with self.assertRaisesRegex(ValueError, 'fewer than five samples'):
            COVERAGE([row for row in rows if row['id'] == 7], 'wall', EPOCH,
                     (15300, 16200), 'run/server/state')

    def test_server_dense_window_respects_all_motion_durations(self):
        for options, duration in ((dict(cart_actions=True), 15000),
                                  (dict(cart_actions=True, cart_fast_motion=True), 26000),
                                  (dict(cart_actions=True, cart_wall_exit='front'), 18000),
                                  (dict(cart_actions=True, cart_wall_exit='left'), 29000)):
            with self.subTest(options=options):
                ticks = [-101, -100, -2, -1, 0, 1, 99, 100, duration - 1, duration,
                         duration + 1, duration + 99, duration + 100, duration + 101, duration + 200]
                rows, polls = self.run_server(ticks, options=options)
                self.assertEqual(self.owner_times(rows),
                                 [-101, -1, 0, 1, 99, 100, duration - 1, duration,
                                  duration + 100, duration + 200])
                self.assertEqual(polls, [])
        rows, _ = self.run_server([-1000, -999, -501, -500, -499, 0, 1, 499, 500], start=False)
        self.assertEqual(self.owner_times(rows), [-1000, -500, 0, 500])

    def test_server_pending_action_poll_runs_before_post_motion_state_gate(self):
        ticks = [26000, 26001, 26024, 26025, 26099, 26100]
        rows, polls = self.run_server(ticks, pending=True)
        self.assertEqual(self.owner_times(rows), [26000, 26100])
        self.assertEqual(polls, ticks)


if __name__ == '__main__':
    unittest.main()
