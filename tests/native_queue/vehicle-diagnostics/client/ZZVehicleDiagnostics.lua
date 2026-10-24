require 'Vehicles/TimedActions/ISEnterVehicle'
local D = require 'PZSurvivorToolkit/VehicleDiagnosticsClient'
local Window = require 'PZSurvivorToolkit/VehicleDiagnostics'
local stage, nextAt, began, failed = 'initial', 0, nil, false
local window, id, authority, entered, observedAt, sampleAt
local function pass(name) print('[VEHICLE_DIAGNOSTICS] PASS ' .. name) end
local function advance(name, wait)
    stage = name; nextAt = getTimestampMs() + (wait or 100)
end
local function click(control)
    assert(control and control.enable and not control.disabledOptions[control.optionsIndex[1]], 'Disabled diagnostics checkbox')
    -- The native ISTickBox press/release path calls its registered product callback.
    control.mouseOverOption = 1
    control:onMouseDown(4, 4); control:onMouseUp(4, 4)
end
local function states(localState, serverState)
    window:refresh()
    return D.localStatus() == localState and D.server.status == serverState
        and window.traceStatus == localState and window.serverTraceStatus == serverState
        and window.record:isSelected(1) == (localState == 'active')
        and window.serverRecord:isSelected(1) == (serverState == 'active') and not D.server.pending
end
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= 'VehicleDiagnosticsTest' then return end
    if command == 'vehicle' then id = args.id end
    if command == 'observed' then assert(args.id == id); authority = args.state end
end)
local function observe(state)
    if authority == state then return true end
    if not observedAt or getTimestampMs() - observedAt >= 1000 then
        observedAt = getTimestampMs()
        sendClientCommand('VehicleDiagnosticsTest', 'observe', {id=id, state=state})
    end
    return false
end
local function run()
    local player = getPlayer()
    D.pollServer()
    if stage == 'initial' then
        assert(isClient() and isCoopHost(), 'Requires real menu Host owner')
        if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:onClose() end
        if not window then window = Window.show() end
        if not states('off', 'off') then return end
        pass('initial-off')
        click(window.record)
        assert(D.localStatus() == 'active')
        click(window.serverRecord)
        assert(D.server.pending, 'Server checkbox did not send a request')
        advance('active')
    elseif stage == 'active' then
        if not states('active', 'active') then return end
        local localPath, serverPath = D.localPath(), D.server.path
        assert(type(localPath) == 'string' and type(serverPath) == 'string' and localPath ~= serverPath)
        print('[VEHICLE_DIAGNOSTICS] PATH client=' .. localPath)
        print('[VEHICLE_DIAGNOSTICS] PATH server=' .. serverPath)
        pass('host-ack-active')
        sendClientCommand('VehicleDiagnosticsTest', 'prepare', {})
        advance('vehicle')
    elseif stage == 'vehicle' then
        local v = id and getVehicleById(id)
        if not v or not v:getSquare() or not v:getPartById('DoorFrontLeft'):getDoor():isOpen() then return end
        if not entered then
            entered = true
            local pos = Vector3f.new()
            v:getWorldPos(v:getPassengerPosition(0, 'outside'):getOffset(), pos)
            player:setX(pos:x()); player:setY(pos:y()); player:setZ(0)
            player:setNextX(pos:x()); player:setNextY(pos:y()); player:setLastX(pos:x()); player:setLastY(pos:y())
            ISTimedActionQueue.add(ISEnterVehicle:new(player, v, 0))
        end
        if player:getVehicle() ~= v or v:getSeat(player) ~= 0 or #ISTimedActionQueue.getTimedActionQueue(player).queue > 0 then return end
        if not observe('active') then return end
        sampleAt = getTimestampMs()
        pass('native-driver-authority')
        advance('sample', 4000)
    elseif stage == 'sample' then
        if not states('active', 'active') then return end
        assert(getTimestampMs() - sampleAt >= 4000)
        getCore():TakeFullScreenshot('vehicle-diagnostics-active.png')
        window:close(); window = nil
        pass('recording-survives-close')
        advance('reopen', 700)
    elseif stage == 'reopen' then
        window = Window.show()
        if not states('active', 'active') then return end
        pass('reopen-active')
        click(window.record); click(window.serverRecord)
        assert(D.localStatus() == 'off' and D.server.pending)
        authority = nil; observedAt = nil
        advance('stop')
    elseif stage == 'stop' then
        if not states('off', 'off') or not observe('off') then return end
        pass('host-ack-off')
        advance('off-shot', 700)
    elseif stage == 'off-shot' then
        if not states('off', 'off') then return end
        getCore():TakeFullScreenshot('vehicle-diagnostics-off.png')
        window:close(); window = nil
        advance('reopen-off', 700)
    elseif stage == 'reopen-off' then
        window = Window.show()
        if not states('off', 'off') then return end
        pass('reopen-off')
        window:close()
        stage = 'done'
        print('[VEHICLE_DIAGNOSTICS] COMPLETE controls')
    end
end
Events.OnTick.Add(function()
    if failed or stage == 'done' or not isIngameState() or not getPlayer() or not getPlayer():getSquare() then return end
    if not began then began = getTimestampMs() end
    if getTimestampMs() < nextAt then return end
    nextAt = getTimestampMs() + 100
    local ok, err = pcall(function()
        assert(getTimestampMs() - began < 90000, 'Bounded diagnostics fixture timed out at ' .. stage)
        run()
    end)
    if not ok then failed = true; print('[VEHICLE_DIAGNOSTICS] FAIL stage=' .. stage .. ' ' .. tostring(err)) end
end)
