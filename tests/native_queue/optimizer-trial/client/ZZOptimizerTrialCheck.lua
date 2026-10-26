-- Functional smoke only: normal timed actions in the disposable starter world.
-- No input injection, terrain/population edits, teleport or chunk preload.
require "TimedActions/ISTimedActionQueue"
require "TimedActions/WalkToTimedAction"
require "Vehicles/TimedActions/ISExitVehicle"
local config = require "QueueTestSelection"
local F = require "DrivingBenchFixture"
local MARK = "[OPTIMIZER_TRIAL_TEST] "
local readyAt, began, ended, stage, phaseAt, nextSample, nextScan
local vehicle, sqlId, target, walkRequested
local samples, visibleSamples, missingSamples, maxHoleRun = 0, 0, 0, 0
local holeSince, totalDistance, lastX, lastY = nil, 0, nil, nil
local initialChunks, arrivedChunks, visitedChunks = {}, {}, {}
local initialChunkCount, arrivedChunkCount, visitedChunkCount = 0, 0, 0
local mode = "stationary"
local function log(text) print(MARK .. text) end
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < 100000000
end
local function queue(player) return ISTimedActionQueue.getTimedActionQueue(player).queue end
local function stop(problem)
    if ended then return end
    ended = true
    if walkRequested and getPlayer() then ISTimedActionQueue.clear(getPlayer()) end
    log("FAIL " .. tostring(problem))
end
local function capture(name)
    getCore():TakeFullScreenshot("optimizer-trial-" .. name .. ".png")
    log("SCREENSHOT name=optimizer-trial-" .. name .. ".png")
end
local function countLoaded(player, initial)
    -- Read only the current loaded map; getGridSquare never requests a chunk.
    -- B42.21 chunks are 8 tiles wide. The radius covers the ordinary starter grid.
    local cx, cy = math.floor(player:getX() / 8), math.floor(player:getY() / 8)
    for dx = -16, 16 do for dy = -16, 16 do
        local wx, wy = cx + dx, cy + dy
        local square = getCell():getGridSquare(wx * 8 + 4, wy * 8 + 4, 0)
        if square and square:getChunk() then
            local key = wx .. "," .. wy
            if initial then
                if not initialChunks[key] then initialChunks[key] = true; initialChunkCount = initialChunkCount + 1 end
            elseif not initialChunks[key] and not arrivedChunks[key] then
                arrivedChunks[key] = true; arrivedChunkCount = arrivedChunkCount + 1
                log("CHUNK_AVAILABLE key=" .. key .. " elapsedMs=" .. (getTimestampMs() - began))
            end
        end
    end end
end
local function sample(player, now)
    assert(player, "Player missing")
    assert(not player:isDead(), "Player died during functional observation")
    assert(player:getCurrentSquare(), "Player current square missing")
    assert(finite(player:getX()) and finite(player:getY()) and finite(player:getZ()), "Nonfinite player position")
    assert(math.floor(player:getZ()) == 0, "Unexpected player level")
    assert(vehicle and vehicle == PZDrivingBenchClient.vehicle and vehicle:getSqlId() == sqlId
        and vehicle:getSquare(), "Prepared native vehicle identity or square changed")
    assert(finite(vehicle:getX()) and finite(vehicle:getY()), "Nonfinite vehicle position")
    assert(not player:getVehicle() or player:getVehicle() == vehicle, "Player entered a foreign vehicle")
    local x, y, z = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    local missing, visible, lit = 0, 0, 0
    for dx = -2, 2 do for dy = -2, 2 do
        local square = getCell():getGridSquare(x + dx, y + dy, z)
        if not square or not square:getChunk() or not square:getFloor() or not square:TreatAsSolidFloor() then
            missing = missing + 1
        else
            if square:isCanSee(player:getPlayerNum()) then visible = visible + 1 end
            local light = assert(square:getLightInfo(player:getPlayerNum()), "No native square light info")
            for _, value in ipairs({light:getR(), light:getG(), light:getB()}) do
                assert(finite(value) and value >= 0 and value <= 4, "Invalid native square light channel")
            end
            lit = lit + 1
        end
    end end
    samples = samples + 1
    if missing > 0 then
        missingSamples = missingSamples + 1
        if not holeSince then holeSince = now end
        maxHoleRun = math.max(maxHoleRun, now - holeSince)
        assert(now - holeSince < 3000, "Persistent missing floor/chunk within two tiles of player")
    else holeSince = nil end
    if visible > 0 then visibleSamples = visibleSamples + 1 end
    assert(lit > 0, "No nearby native lighting samples")
    local key = math.floor(player:getX() / 8) .. "," .. math.floor(player:getY() / 8)
    if not visitedChunks[key] then visitedChunks[key] = true; visitedChunkCount = visitedChunkCount + 1 end
    if lastX then
        local distance = math.sqrt((player:getX() - lastX)^2 + (player:getY() - lastY)^2)
        assert(distance < 5, "Unexpected player displacement between functional samples")
        totalDistance = totalDistance + distance
    end
    lastX, lastY = player:getX(), player:getY()
    if samples % 10 == 0 then
        log("SAMPLE elapsedMs=" .. (now - began) .. " samples=" .. samples .. " floors=" .. lit
            .. " visible=" .. visible .. " missing=" .. missing .. " visitedChunks=" .. visitedChunkCount
            .. " availableAfterStart=" .. arrivedChunkCount .. " distance=" .. string.format("%.2f", totalDistance))
    end
end
local function chooseTarget(player)
    local x, y = math.floor(player:getX()), math.floor(player:getY())
    local best, bestLength
    for _, direction in ipairs({{1,0},{0,1},{-1,0},{0,-1}}) do
        local last, length
        for step = 1, 24 do
            local square = getCell():getGridSquare(x + direction[1] * step, y + direction[2] * step, 0)
            if not square or not square:getFloor() or not square:TreatAsSolidFloor()
                or not square:isOutside() or not square:isFree(false) then break end
            last, length = square, step
        end
        if length and length >= 8 and (not bestLength or length > bestLength) then best, bestLength = last, length end
    end
    return best, bestLength
end
local function finish(player, now)
    assert(samples >= 40 and visibleSamples >= 20, "Too few real world/visibility samples")
    assert(not holeSince and maxHoleRun < 3000, "Nearby map remained incomplete")
    if mode == "native-walk" then
        assert(target and #queue(player) == 0 and not player:getVehicle(), "Native walk did not finish")
        assert(math.abs(player:getX() - target:getX() - .5) < 1.5
            and math.abs(player:getY() - target:getY() - .5) < 1.5, "Native walk missed its destination")
        assert(totalDistance >= 8 and visitedChunkCount >= 2, "No real walking/chunk-boundary coverage")
    end
    capture("end")
    ended = true
    if arrivedChunkCount == 0 then log("LIMIT no-new-chunk-availability-observed") end
    log("LIMIT functional-SP-only no-FPS-verdict no-Host-verdict no-pixel-visibility-proof mac-TileBatch-may-be-inactive")
    log("COMPLETE mode=" .. mode .. " elapsedMs=" .. (now - began) .. " samples=" .. samples
        .. " visibleSamples=" .. visibleSamples .. " transientMissingSamples=" .. missingSamples
        .. " maxMissingMs=" .. maxHoleRun .. " initialChunks=" .. initialChunkCount
        .. " availableAfterStart=" .. arrivedChunkCount .. " visitedChunks=" .. visitedChunkCount
        .. " distance=" .. string.format("%.2f", totalDistance) .. " screenshots=begin,end")
end
Events.OnTick.Add(function()
    if ended then return end
    local C = PZDrivingBenchClient
    if not C or not C.ready or not F.allowed() then return end
    local now = getTimestampMs()
    if not readyAt then readyAt = now end
    if now - readyAt < 5000 then return end -- let the independent starter driver check finish first
    local ok, problem = pcall(function()
        assert(config.suite == "optimizer-trial" and config.clients == 1 and config.kind == "sp" and not isClient() and not isServer(), "Disposable SP fixture required")
        local player = assert(getPlayer(), "No player")
        if not began then
            began, stage, phaseAt = now, "exit", now
            vehicle, sqlId = assert(C.vehicle), C.vehicle:getSqlId()
            assert(player:getVehicle() == vehicle and vehicle:getSeat(player) == 0 and vehicle:isEngineRunning(), "Starter driver/engine not ready")
            assert(#queue(player) == 0, "Unexpected existing timed action")
            countLoaded(player, true)
            capture("begin")
            ISTimedActionQueue.add(ISExitVehicle:new(player))
            log("BEGIN durationMs=45000 initialChunks=" .. initialChunkCount .. " originalVehicleSql=" .. sqlId)
        end
        assert(now - began <= 60000, "Functional scenario exceeded hard timeout")
        if not nextSample or now >= nextSample then nextSample = now + 500; sample(player, now) end
        if not nextScan or now >= nextScan then nextScan = now + 2000; countLoaded(player, false) end
        if stage == "exit" then
            assert(now - phaseAt < 10000, "Native exit did not finish")
            if not player:getVehicle() and #queue(player) == 0 then
                local length
                target, length = chooseTarget(player)
                stage, phaseAt = "observe", now
                if target then
                    mode, walkRequested = "native-walk", true
                    ISTimedActionQueue.add(ISWalkToTimedAction:new(player, target))
                    log("WALK target=" .. target:getX() .. "," .. target:getY() .. ",0 length=" .. length)
                else log("LIMIT no-safe-loaded-exterior-walk-path stationary-observation-only") end
            end
        end
        if stage == "observe" and now - began >= 45000 then finish(player, now) end
    end)
    if not ok then stop(problem) end
end)
