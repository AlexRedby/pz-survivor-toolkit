local output = print
local script = ProjectRoot .. '/tests/optimizer_trial/PZOptimizerTrialTelemetry.lua'
local function setup(client, server)
    local state = {now=10000, logs={}, callbacks={}, world=true, onFoot=false, paused=false,
        worldId='PZDrivingBench-OptimizerTrial-fixture', fileWrites=0,
        clockReads=0, cellReads=0, playerReads=0, positionReads=0, countReads=0, speedReads=0,
        zoomReads=0, zombieReads=0, adds=0}
    print=function(line) state.logs[#state.logs+1]=line end
    getFileWriter=function() state.fileWrites=state.fileWrites+1; error('no observer file writes') end
    isClient=function() return client or false end
    isServer=function() return server or false end
    Events={}
    for _, name in ipairs({'OnGameStart','OnTickEvenPaused','OnMainMenuEnter','OnPostSave','OnSave'}) do
        local event=name
        Events[event]={Add=function(callback)
            state.adds=state.adds+1
            assert(not state.callbacks[event], 'duplicate event registration')
            state.callbacks[event]=callback
        end}
    end
    getWorld=function() return {getWorld=function() return state.worldId end} end
    getTimestampMs=function() state.clockReads=state.clockReads+1; return state.now end
    local zombies={size=function() state.countReads=state.countReads+1; return 23 end,
        get=function() error('telemetry must not scan the loaded zombie list') end}
    local cell={getZombieList=function() state.zombieReads=state.zombieReads+1; return zombies end}
    getCell=function() state.cellReads=state.cellReads+1; if state.world then return cell end end
    local vehicle={getCurrentSpeedKmHour=function() state.speedReads=state.speedReads+1; return -42.125 end,
        getScriptName=function() return 'Base.SportsCar' end}
    state.vehicle=vehicle
    local player={getSquare=function() return state.square ~= false and {} or nil end,
        getPlayerNum=function() return 0 end,
        getX=function() state.positionReads=state.positionReads+1; return 10620.5 end,
        getY=function() return 10004.25 end, getZ=function() return 0 end,
        getVehicle=function() if not state.onFoot then return state.vehicle end end}
    getPlayer=function() state.playerReads=state.playerReads+1; if not state.missingPlayer then return player end end
    getCore=function() return {getZoom=function(_,number)
        assert(number==0);state.zoomReads=state.zoomReads+1;return 1.25
    end} end
    isGamePaused=function() return state.paused end
    dofile(script)
    return state
end

local s=setup()
assert(s.adds==3 and not s.callbacks.OnTickEvenPaused and #s.logs==0, 'no sampling before world start')
s.callbacks.OnMainMenuEnter();s.callbacks.OnPostSave()
assert(#s.logs==0, 'initial menu/exit cannot commit a nonexistent world')
s.callbacks.OnGameStart();s.callbacks.OnGameStart()
assert(s.adds==4, 'start must install one sampler only')
assert(s.callbacks.OnPostSave and not s.callbacks.OnSave and not Events.OnGameExit,
    'B42 SP end policy uses actual OnPostSave, never ordinary OnSave or nonexistent OnGameExit')
s.callbacks.OnTickEvenPaused()
for time=10001,10999 do s.now=time;s.callbacks.OnTickEvenPaused() end
assert(#s.logs==0 and s.fileWrites==0, 'no ongoing console/file writes while playing')
assert(s.cellReads==1 and s.playerReads==1 and s.positionReads==1
    and s.countReads==1 and s.speedReads==1 and s.zoomReads==1, 'throttle before expensive getters')
s.now=11000;s.paused=true;s.onFoot=true;s.callbacks.OnTickEvenPaused()
assert(#s.logs==0 and s.speedReads==1, 'paused sampling is buffered too')
s.now=999999;s.callbacks.OnMainMenuEnter()
assert(#s.logs==4 and s.logs[1]:find('flush begin format=2 world='..s.worldId..' samples=2 dropped=0 reason=MainMenu',1,true))
assert(s.logs[2]:find('^%[OptimizerTrial%] drive sample tsMs=10000 '), 'retain observation timestamp, not flush time')
for _, text in ipairs({'x=10620.500','y=10004.250','z=0.000','inVehicle=true','speedKmh=-42.125',
    'vehicleScript="Base.SportsCar"','zoom=1.250','loadedZombieCount=23','paused=false'}) do
    assert(s.logs[2]:find(text,1,true), 'missing driving context: '..text)
end
assert(s.logs[3]:find('tsMs=11000',1,true) and s.logs[3]:find('inVehicle=false',1,true)
    and s.logs[3]:find('paused=true',1,true))
assert(not s.logs[3]:find('speedKmh=',1,true) and not s.logs[3]:find('vehicleScript=',1,true))
assert(s.logs[4]:find('samples=2 dropped=0 status=Complete',1,true))
s.callbacks.OnPostSave();s.callbacks.OnTickEvenPaused()
assert(#s.logs==4, 'menu plus process exit flushes one batch only')
s.worldId='PZDrivingBench-OptimizerTrial-next';s.callbacks.OnGameStart();s.callbacks.OnTickEvenPaused();s.callbacks.OnPostSave()
assert(#s.logs==7 and s.logs[5]:find('world='..s.worldId..' samples=1',1,true), 'new world has a separate identity and fresh buffer')
assert(s.adds==4, 'new worlds must reuse the single sampler')

s=setup();s.callbacks.OnGameStart();s.world=false;s.callbacks.OnTickEvenPaused()
assert(#s.logs==0 and s.playerReads==0, 'no sample outside a world')
s.now=11000;s.world=true;s.missingPlayer=true;s.callbacks.OnTickEvenPaused()
s.now=12000;s.missingPlayer=false;s.square=false;s.callbacks.OnTickEvenPaused()
s.now=13000;s.square=true;s.onFoot=true;s.callbacks.OnTickEvenPaused()
assert(#s.logs==0, 'missing world/player/square never writes or permanently disables sampling')
s.callbacks.OnPostSave()
assert(#s.logs==3 and s.logs[2]:find('tsMs=13000',1,true))

s=setup();s.callbacks.OnGameStart()
for index=0,1804 do s.now=10000+index*1000;s.callbacks.OnTickEvenPaused() end
assert(#s.logs==0 and s.fileWrites==0, 'even an overflowing buffer causes zero ongoing writes')
s.callbacks.OnPostSave()
assert(#s.logs==1802 and s.logs[1]:find('samples=1800 dropped=5',1,true), 'buffer capacity is fixed')
assert(s.logs[2]:find('tsMs=15000 ',1,true) and s.logs[1801]:find('tsMs=1814000 ',1,true), 'retain the newest bounded interval in order')
assert(s.logs[1802]:find('dropped=5 status=Incomplete',1,true), 'truncation is explicit, never complete')

s=setup();s.callbacks.OnGameStart()
s.vehicle.getScriptName=function() return string.rep('"\\', 100000) end
s.callbacks.OnTickEvenPaused()
assert(#s.logs==0, 'large input still stays in memory during play')
s.callbacks.OnPostSave()
assert(#s.logs==3 and #s.logs[2]<=1024 and s.logs[3]:find('status=Complete',1,true),
    'bound variable-length context before serialization and storage')

s=setup();s.callbacks.OnGameStart()
s.vehicle.getCurrentSpeedKmHour=function() error('unsupported\nvehicle API') end
s.callbacks.OnTickEvenPaused()
local clockReads=s.clockReads
for time=11000,15000,1000 do s.now=time;s.callbacks.OnTickEvenPaused() end
s.callbacks.OnGameStart()
assert(#s.logs==0 and s.clockReads==clockReads and s.adds==4, 'errors disable once without synchronous output')
s.callbacks.OnPostSave()
assert(#s.logs==3 and s.logs[2]:find('drive telemetry disabled error=',1,true)
    and not s.logs[2]:find('\n',1,true) and s.logs[3]:find('status=Incomplete',1,true))

s=setup();s.callbacks.OnGameStart()
isClient=function() return true end
s.callbacks.OnGameStart();s.callbacks.OnTickEvenPaused()
assert(#s.logs==0 and s.clockReads==0, 'do not carry an SP sampler into an MP world')
s=setup(true,false);assert(s.adds==0 and #s.logs==0, 'no event registration for MP client')
s=setup(false,true);assert(s.adds==0 and #s.logs==0, 'no event registration on server')
print=output
print('PASS optimizer trial telemetry: zero ongoing writes, bounded context buffer, end-only flush, identity, original timestamps, explicit truncation/failure')
