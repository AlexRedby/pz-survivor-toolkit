require "Vehicles/TimedActions/ISEnterVehicle"
require "Vehicles/ISUI/ISVehicleMenu"
local F = require "DrivingBenchFixture"
local C = {stage="waiting", ready=false}
PZDrivingBenchClient = C
local started, nextAt, result, vehicle, entryAt, engineAt
Events.OnGameStart.Add(function() C.gameStarted=F.allowed() end)
Events.OnPreUIDraw.Add(function()
    if C.gameStarted and not isClient() and not C.ready and C.stage~="failed" and isIngameState() and isGamePaused() then setGameSpeed(1) end
end)
local function fail(reason)
    C.stage, C.error = "failed", tostring(reason)
    print("[PZDrivingBench] FAIL " .. C.error)
    if getPlayer() then getPlayer():Say("Driving starter: " .. C.error) end
end
local function receive(value)
    if type(value) ~= "table" then return end
    if value.status == "error" then
        if value.retryable then C.lastWait = value.reason else fail(value.reason) end
        return
    end
    if value.status == "ready" and type(value.id) == "number" and type(value.sqlId) == "number" then result=value end
end
Events.OnServerCommand.Add(function(module, command, args)
    if module == F.MODULE and F.allowed() and (command=="ready" or command=="error") then receive(args) end
end)
local function findVehicle()
    if not result then return end
    if isClient() then return getVehicleById(result.id) end
    local vehicles = getCell():getVehicles():iterator()
    while vehicles:hasNext() do
        local v = vehicles:next()
        if v:getSqlId() == result.sqlId then return v end
    end
end
local function prepare(player)
    if not result then
        if not C.requestAt or getTimestampMs()-C.requestAt >= 3000 then
            C.requestAt=getTimestampMs()
            if isClient() then sendClientCommand(F.MODULE,"prepare",{}) else receive(F.prepare(player)) end
        end
        return
    end
    vehicle = findVehicle()
    if not vehicle or not vehicle:getSquare() then return end
    local ignitionKey=vehicle:getCurrentKey()
    if not player:getInventory():haveThisKeyId(vehicle:getKeyId())
        and not (vehicle:isKeysInIgnition() and ignitionKey and ignitionKey:getKeyId()==vehicle:getKeyId()) then return end
    if not vehicle:isSeatOccupied(0) and not entryAt then
        local outside = vehicle:getPassengerPosition(0,"outside")
        assert(outside,"No native driver entry position")
        local pos = Vector3f.new()
        vehicle:getWorldPos(outside:getOffset(),pos)
        player:setX(pos:x()); player:setY(pos:y()); player:setZ(0)
        player:setNextX(pos:x()); player:setNextY(pos:y())
        player:setLastX(pos:x()); player:setLastY(pos:y())
        ISTimedActionQueue.add(ISEnterVehicle:new(player,vehicle,0))
        entryAt=getTimestampMs()
        C.stage="entering"
    end
    if player:getVehicle() ~= vehicle or vehicle:getSeat(player) ~= 0 then
        if entryAt and getTimestampMs()-entryAt>20000 then fail("Driver entry did not finish; the unlocked car and key remain available.") end
        return
    end
    if #ISTimedActionQueue.getTimedActionQueue(player).queue>0 then return end
    if not engineAt then
        ISVehicleMenu.onStartEngine(player)
        engineAt=getTimestampMs()
        C.stage="starting-engine"
        return
    end
    if not vehicle:isEngineRunning() then
        if getTimestampMs()-engineAt>20000 then fail("Engine did not start; check the ignition in the vehicle dashboard.") end
        return
    end
    C.stage, C.ready, C.vehicle = "ready", true, vehicle
    print("[PZDrivingBench] READY driver=true engine=true x="..vehicle:getX().." y="..vehicle:getY())
    player:Say("Ready to drive. Use your normal vehicle controls.")
end
Events.OnTick.Add(function()
    if C.ready or C.stage=="failed" or not isIngameState() or not F.allowed() then return end
    local player=getPlayer()
    if not player or player:isDead() or not player:getSquare() then return end
    local now=getTimestampMs()
    if not started then
        started=now
        if not isClient() then getGameTime():setTimeOfDay(12) end
        if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:onClose() end
    end
    if now-started>90000 then fail(C.lastWait or "Preparation timed out; check the test profile console.txt."); return end
    if nextAt and now<nextAt then return end
    nextAt=now+200
    local ok, problem=pcall(prepare,player)
    if not ok then fail(problem) end
end)
