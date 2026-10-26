local config = require "QueueTestSelection"
if config.cases and config.cases[1] == "seed" then return end
local started, ended, readyAt, screenshot, actualZoom
local options = config.options and config.options.driving_perf or {}
local function fail(problem)
    if ended then return end
    ended = true
    print("[DRIVING_PERF] FAIL Lua: " .. tostring(problem))
end
Events.OnTick.Add(function()
    if ended then return end
    local C = PZDrivingBenchClient
    if not C or not C.ready then return end
    if not readyAt then
        local ok, problem = pcall(function()
            local number=getPlayer():getPlayerNum()
            local inventory=getPlayerInventory(number)
            local loot=getPlayerLoot(number)
            if inventory then inventory:setVisible(false) end
            if loot then loot:setVisible(false) end
            if ISCharacterInfoWindow and ISCharacterInfoWindow.instance then ISCharacterInfoWindow.instance:setVisible(false) end
            getCore():setFramerate(5)
            assert(getPerformance():getFramerate() == 144, "Expected actual 144 FPS cap")
            assert(getCore():getOptionVSync() == false, "Expected VSync off")
            assert(type(drivingPerfSetZoom) == "function", "Missing native benchmark zoom setter")
            local requestedZoom = options.zoom == nil and "max" or options.zoom
            actualZoom = requestedZoom == "max" and getCore():getMaxZoom() or requestedZoom
            assert(type(actualZoom) == "number" and actualZoom >= 1.5 and actualZoom <= 2.5,
                "Native maximum/requested zoom is outside reviewed 1.5..2.5 bounds")
            print("[DRIVING_PERF] MAX_ZOOM requested=" .. tostring(requestedZoom)
                .. " actual=" .. tostring(actualZoom) .. " native_max=" .. tostring(getCore():getMaxZoom()))
            drivingPerfSetZoom(getPlayer(), actualZoom)
            readyAt = getTimestampMs()
        end)
        if not ok then fail(problem); return end
    end
    if not screenshot and getTimestampMs()-readyAt>=1000 then
        getCore():TakeFullScreenshot("driving-perf-begin.png")
        screenshot=true
    end
    if getTimestampMs() - readyAt < 3000 then return end
    local ok, problem = pcall(function()
        if not started then
            assert(type(drivingPerfBegin) == "function" and type(drivingPerfTick) == "function"
                and type(drivingPerfFinish) == "function", "Missing native performance probe globals")
            assert(options.full_throttle == nil or type(options.full_throttle) == "boolean", "full_throttle must be boolean")
            local fullThrottle = options.full_throttle == true
            local gateSpeed = fullThrottle and (options.minimum_approach_kmh or 80) or (options.speed_kmh or 30)
            drivingPerfBegin(getPlayer(), gateSpeed, options.stationary_seconds or 10,
                options.approach_tiles or 40, options.measured_tiles or 300, actualZoom,
                options.min_visible_zombies == nil and 1 or options.min_visible_zombies,
                fullThrottle, options.vehicle_script or "Base.CarNormal")
            started = true
        end
        local state = drivingPerfTick()
        if state == "done" or state == "failed" then
            local output = drivingPerfFinish()
            ended = true
            if state == "done" then
                getCore():TakeFullScreenshot("driving-perf-end.png")
                print("[DRIVING_PERF] LUA_COMPLETE csv=" .. tostring(output))
            end
        end
    end)
    if not ok then fail(problem) end
end)
