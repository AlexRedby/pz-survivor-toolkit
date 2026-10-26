-- Private client trial evidence. This observer never changes the world or controls.
if isServer() then return end

-- Keep the newest 30 minutes at 1 Hz. Never print/write while observing play:
-- native Lua print synchronously writes the console on the main thread.
local maximumSamples, maximumLineBytes = 1800, 1024
local registered, disabled, lastAt = false, false, nil
local active, closed, world, problem = false, true, nil, nil
local multiplayer = false
local samples, head, count, dropped = {}, 1, 0, 0
local function disable(problem)
    if disabled then return end
    disabled = true
    -- Failure evidence is deferred along with samples; even error logging can hitch.
    return tostring(problem):gsub("[\r\n]", " "):sub(1, 256)
end

local function collectSample()
    local now = getTimestampMs()
    -- Only the clock is read every tick, including while the game is paused.
    if lastAt and now - lastAt < 1000 then return end
    lastAt = now
    local cell = getCell()
    if not cell then return end
    local player = getPlayer()
    if not player or not player:getSquare() then return end
    local vehicle = player:getVehicle()
    local fields = {
        "tsMs=" .. string.format("%.0f", now),
        "x=" .. string.format("%.3f", player:getX()),
        "y=" .. string.format("%.3f", player:getY()),
        "z=" .. string.format("%.3f", player:getZ()),
        "inVehicle=" .. tostring(vehicle ~= nil),
        "zoom=" .. string.format("%.3f", getCore():getZoom(player:getPlayerNum())),
        -- Size of the loaded cell list: no visibility/radius claim or list scan.
        "loadedZombieCount=" .. tostring(cell:getZombieList():size()),
        "paused=" .. tostring(isGamePaused()),
    }
    if vehicle then
        fields[#fields + 1] = "speedKmh=" .. string.format("%.3f", vehicle:getCurrentSpeedKmHour())
        local script = vehicle:getScriptName()
        if script then
            script = tostring(script):sub(1, 128):gsub("[\r\n]", " "):gsub('\\', '\\\\'):gsub('"', '\\"')
            fields[#fields + 1] = 'vehicleScript="' .. script .. '"'
        end
    end
    local line = "[OptimizerTrial] drive sample " .. table.concat(fields, " ")
    if #line > maximumLineBytes then error("context sample exceeds bounded line limit") end
    if count < maximumSamples then
        samples[(head + count - 1) % maximumSamples + 1] = line
        count = count + 1
    else
        samples[head] = line
        head = head % maximumSamples + 1
        dropped = dropped + 1
    end
end

local function sample()
    if disabled or not active or isServer() then return end
    local ok, failure = pcall(collectSample)
    if not ok then problem = disable(failure) end
end

local function flush(reason)
    -- Initial menu entry has no world/buffer. A menu followed by process exit
    -- must not print the same world twice. Abrupt termination has no end marker.
    if closed or isServer() then return end
    active, closed = false, true
    pcall(function()
        local identity = "format=2 world=" .. tostring(world) .. " samples=" .. count .. " dropped=" .. dropped
        print("[OptimizerTrial] drive telemetry flush begin " .. identity .. " reason=" .. reason)
        for index = 0, count - 1 do print(samples[(head + index - 1) % maximumSamples + 1]) end
        if problem then print("[OptimizerTrial] drive telemetry disabled error=" .. problem) end
        local status = (not problem and dropped == 0 and count > 0) and "Complete" or "Incomplete"
        -- This marker commits only the preceding bounded batch. Original tsMs
        -- belong to observation time, not this later console-flush time.
        print("[OptimizerTrial] drive telemetry flush end " .. identity .. " status=" .. status)
    end)
    samples = {}
end

-- The pinned bridge calls this before IngameState.exit rebuilds Lua and before
-- ServerDisconnectState.enter clears callbacks. A kick can bypass OnDisconnect.
-- It also runs in Control mode; optimizer/preload activation is unrelated to observation.
PZOptimizerTrialTelemetryFlush = function(reason)
    if multiplayer and (reason == "WorldExit" or reason == "Disconnect") then flush(reason) end
end
if Events.OnDisconnect then Events.OnDisconnect.Add(function()
    PZOptimizerTrialTelemetryFlush("Disconnect")
end) end

local function multiplayerIdentity()
    local reader
    local ok, candidate = pcall(function()
        reader = getFileReader("OptimizerTrial-context-id.txt", false)
        if not reader then return nil end
        local value = reader:readLine()
        if reader:readLine() ~= nil then return nil end
        return value
    end)
    if reader then pcall(function() reader:close() end) end
    local prefix = "PZDrivingBench-OptimizerTrial-MP-"
    if not ok or type(candidate) ~= "string" or #candidate ~= #prefix + 32
        or not candidate:match("^PZDrivingBench%-OptimizerTrial%-MP%-%x+$") then
        -- Never copy a server/save/player name or reader exception into diagnostic output.
        error("invalid multiplayer trial context identity", 0)
    end
    return candidate
end

if Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(function() flush("MainMenu") end) end
-- Current B42 dispatches OnPostSave from GameWindow.exit and IngameState's
-- Core.exiting branch, including clients, before teardown. Ordinary saves do not
-- commit the batch. OnMainMenuEnter alone can run after Lua has been rebuilt.
if Events.OnPostSave then Events.OnPostSave.Add(function() flush("PostSaveExit") end) end
Events.OnGameStart.Add(function()
    if isServer() then disabled = true; active = false; return end
    if not closed then return end
    samples, head, count, dropped = {}, 1, 0, 0
    active, closed, disabled, lastAt, problem = true, false, false, nil, nil
    local ok, failure = pcall(function()
        multiplayer = isClient()
        world = "Unavailable"
        if multiplayer then
            world = multiplayerIdentity()
        else
            local candidate = tostring(getWorld():getWorld())
            if #candidate > 100 or not candidate:match("^PZDrivingBench%-OptimizerTrial%-[%w%-]+$") then
                error("unexpected trial world identity")
            end
            world = candidate
        end
        if not registered then Events.OnTickEvenPaused.Add(sample); registered = true end
        if multiplayer then print("[OptimizerTrial] multiplayer context ready world=" .. world) end
    end)
    if not ok then problem = disable(failure) end
end)
