local F = require 'VehicleDoorsFixture'
local Doors = require 'PZSurvivorToolkit/VehicleDoors'
local selection = require 'QueueTestSelection'
local IdleUI = selection.options and selection.options.idle_ui and require 'SidebarIdleUI'
local stage, id, requested, authority, command, nextAt, failed = 0, nil, false, false, nil, 0, false
Events.OnServerCommand.Add(function(module, name, args)
    if module ~= 'VehicleDoorsTest' then return end
    if name == 'vehicle' then id = args.id end
    if name == 'verified' then assert(args.id == id); authority = true end
end)
local function pass(name) print('[VEHICLE_DOORS] PASS ' .. name) end
local function vehicle() return isClient() and id and getVehicleById(id) or F.vehicle end
local function run()
    local player = getPlayer()
    if stage == 0 then
        assert(ISVehicleMenu.PZSTCloseDoorInstalled)
        if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:onClose() end
        if not requested then
            requested = true
            if isClient() then sendClientCommand('VehicleDoorsTest', 'prepare', {}) else id = F.prepare(player) end
        end
        local v = vehicle()
        if not v or not v:getPartById('DoorFrontLeft'):getDoor():isOpen() then return end
        -- Recreate an already seated occupant with an open door without auto-close on entry.
        v:enter(0, player)
        v:setCharacterPosition(player, 0, 'inside')
        triggerEvent('OnEnterVehicle', player)
        assert(player:getVehicle() == v and v:getSeat(player) == 0)
        pass('seated-open-door'); stage = 1
    elseif stage == 1 then
        local v = vehicle()
        ISVehicleMenu.showRadialMenu(player)
        stage = 1.5
    elseif stage == 1.5 then
        local v = vehicle()
        local menu = getPlayerRadialMenu(player:getPlayerNum())
        if not menu:isReallyVisible() then return end
        local count, closeIndex = 0, nil
        for index, slice in ipairs(menu.slices) do
            if slice.command[1] == Doors.close then
                command = slice.command; count = count + 1; closeIndex = index
                assert(slice.text == getText('ContextMenu_Close_door'))
                local expectedTexture = getTexture('media/textures/PZSurvivorToolkit/vehicle_close_door_radial.png')
                assert(expectedTexture and slice.texture == expectedTexture)
            end
        end
        assert(count == 1 and command[3] == v and command[4] == v:getPassengerDoor(0))
        -- Select the real native slice through the fixture's owned-process capture helper.
        local writer = assert(getFileWriter('vehicle-doors-radial-index.txt', true, false))
        writer:write(tostring(closeIndex)); writer:close()
        print('[VEHICLE_DOORS] RADIAL_CAPTURE_READY')
        stage = 1.55
    elseif stage == 1.55 then
        local ready = getFileReader('queue-probes-ready.txt', false)
        if not ready then return end
        ready:close()
        stage = 1.6; nextAt = getTimestampMs() + 700
    elseif stage == 1.6 then
        local menu = getPlayerRadialMenu(player:getPlayerNum())
        assert(menu:isReallyVisible())
        getCore():TakeFullScreenshot('vehicle-doors-radial-open.png')
        stage = 1.7; nextAt = getTimestampMs() + 600
    elseif stage == 1.7 then
        local restore = assert(getFileWriter('vehicle-doors-radial-restore.txt', true, false))
        restore:write('restore'); restore:close()
        stage = 1.75; nextAt = getTimestampMs() + 700
    elseif stage == 1.75 then
        assert(getPlayerRadialMenu(player:getPlayerNum()):isReallyVisible())
        getCore():TakeFullScreenshot('vehicle-doors-radial-idle.png')
        stage = 1.8; nextAt = getTimestampMs() + 600
    elseif stage == 1.8 then
        getPlayerRadialMenu(player:getPlayerNum()):undisplay()
        pass('native-radial'); stage = 2; nextAt = getTimestampMs() + 700
    elseif stage == 2 then
        local panel = getPlayerVehicleDashboard(player:getPlayerNum())
        local button = assert(panel.pzstCloseDoorButton)
        assert(button:getIsVisible() and button.enable and button.tooltip == getText('ContextMenu_Close_door'))
        local side = panel.__YourDashMoveSeatButton
        if side and side:getIsVisible() then
            assert(button:getY() + button:getHeight() <= side:getY() or button:getX() >= side:getX() + side:getWidth())
        end
        getCore():TakeFullScreenshot('vehicle-doors-dashboard-open.png')
        pass('dashboard-button')
        stage = 2.5; nextAt = getTimestampMs() + 600
    elseif stage == 2.5 then
        local button = assert(getPlayerVehicleDashboard(player:getPlayerNum()).pzstCloseDoorButton)
        button.onclick(button.target, button)
        button.onclick(button.target, button)
        local count = 0
        for _, action in ipairs(ISTimedActionQueue.getTimedActionQueue(player).queue) do
            if action.Type == 'ISCloseVehicleDoor' then count = count + 1 end
        end
        assert(count == 1, 'Repeated click queued duplicate closes')
        pass('native-action-once'); stage = 3
    elseif stage == 3 then
        local v = vehicle()
        if #ISTimedActionQueue.getTimedActionQueue(player).queue > 0 or v:getPartById('DoorFrontLeft'):getDoor():isOpen() then return end
        assert(player:getVehicle() == v and v:getSeat(player) == 0)
        if getPlayerVehicleDashboard(player:getPlayerNum()).pzstCloseDoorButton.enable then return end
        assert(v:getPartById('DoorFrontRight'):getDoor():isOpen())
        ISVehicleMenu.showRadialMenu(player)
        for _, slice in ipairs(getPlayerRadialMenu(player:getPlayerNum()).slices) do assert(slice.command[1] ~= Doors.close) end
        getPlayerRadialMenu(player:getPlayerNum()):undisplay()
        pass('closed-driver-only')
        if isClient() then sendClientCommand('VehicleDoorsTest', 'verify', {id=id}) else F.verify(v, player); authority = true end
        stage = 4; nextAt = getTimestampMs() + 700
    elseif stage == 4 and authority then
        -- Wait for ordinary queue-window refresh before capturing the closed state.
        getCore():TakeFullScreenshot('vehicle-doors-dashboard-closed.png')
        stage = 4.5; nextAt = getTimestampMs() + 600
    elseif stage == 4.5 then
        pass('authority')
        if IdleUI then IdleUI.start(player, pass); stage = 4.75
        else stage = 5; print('[VEHICLE_DOORS] COMPLETE close') end
    elseif stage == 4.75 and IdleUI.step() then
        stage = 5; print('[VEHICLE_DOORS] COMPLETE close')
    end
end
Events.OnTick.Add(function()
    if failed or stage == 5 or not isIngameState() or not getPlayer() or not getPlayer():getSquare() or getTimestampMs() < nextAt then return end
    nextAt = getTimestampMs() + 100
    local ok, err = pcall(run)
    if not ok then
        failed = true
        if IdleUI then
            local restored, reason = pcall(IdleUI.restore)
            if not restored then print('[VEHICLE_DOORS] IDLE_SIDEBAR restore_failed=' .. tostring(reason)) end
        end
        print('[VEHICLE_DOORS] FAIL stage=' .. stage .. ' ' .. tostring(err))
    end
end)
