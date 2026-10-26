-- Focused state-machine regression; native API existence is verified in-game separately.
local source = arg[1] or "tests/driving_benchmark/mods/PZDrivingBench/42/media/lua/client/DrivingBenchClient.lua"
local function check(reused, allowed)
    local callbacks = {}
    Events = setmetatable({}, {__index=function(t,k)
        local event={Add=function(fn) callbacks[k]=fn end}; rawset(t,k,event); return event
    end})
    local now, prepared, entered, started = 0, 0, 0, 0
    local hasKey, engine = true, false
    local vehicle
    local player = {getInventory=function() return {haveThisKeyId=function() return hasKey end} end,
        getSquare=function() return {} end, isDead=function() return false end,
        getVehicle=function(self) return self.vehicle end, Say=function() end}
    for _,name in ipairs({"setX","setY","setZ","setNextX","setNextY","setLastX","setLastY"}) do player[name]=function() end end
    local position={x=function() return 10818 end,y=function() return 10118 end}
    Vector3f={new=function() return position end}
    vehicle={getSqlId=function() return 123 end,getSquare=function() return {} end,getKeyId=function() return 456 end,
        getCurrentKey=function() return not hasKey and {getKeyId=function() return 456 end} or nil end,
        isKeysInIgnition=function() return not hasKey end,isSeatOccupied=function() return player.vehicle~=nil end,
        getPassengerPosition=function() return {getOffset=function() return {} end} end,
        getWorldPos=function() end,getSeat=function() return player.vehicle and 0 or -1 end,
        isEngineRunning=function() return engine end,getX=function() return 10818 end,getY=function() return 10118 end}
    -- Current B42.21 API returns a Set; deliberately offer no indexed get().
    getCell=function() return {getVehicles=function() return {iterator=function()
        local used=false
        return {hasNext=function() return not used end,next=function() used=true;return vehicle end}
    end} end} end
    ISEnterVehicle={new=function() return {kind="enter"} end}
    ISTimedActionQueue={getTimedActionQueue=function() return {queue={}} end,
        add=function(action) assert(action.kind=="enter");entered=entered+1;player.vehicle=vehicle end}
    ISVehicleMenu={onStartEngine=function()
        started=started+1; engine=true; hasKey=false
    end}
    local fixture={MODULE="PZDrivingBench",allowed=function() return allowed end,
        prepare=function() prepared=prepared+1;return {status="ready",id=-1,sqlId=123,reused=reused} end}
    local original=require
    require=function(name)
        if name=="DrivingBenchFixture" then return fixture end
        if name=="Vehicles/TimedActions/ISEnterVehicle" or name=="Vehicles/ISUI/ISVehicleMenu" then return true end
        return original(name)
    end
    getTimestampMs=function() return now end
    isIngameState=function() return true end
    isClient=function() return false end
    isGamePaused=function() return false end
    getPlayer=function() return player end
    getGameTime=function() return {setTimeOfDay=function() end} end
    SurvivalGuide=nil
    assert(loadfile(source))()
    callbacks.OnGameStart()
    for i=1,8 do now=i*250;callbacks.OnTick() end
    if allowed then
        assert(PZDrivingBenchClient.ready and PZDrivingBenchClient.vehicle==vehicle)
        assert(prepared==1 and entered==1 and started==1,"reused/ignition state restarted setup")
    else
        assert(not PZDrivingBenchClient.ready and prepared==0 and entered==0 and started==0,"foreign game was changed")
    end
    require=original
end
check(false,true)
check(true,true) -- a delayed SQL-ID retry can reuse a car before the first driver entry.
check(false,false)
print("PASS driving client: Set lookup, delayed reuse, ignition key, single entry/start, isolation")
