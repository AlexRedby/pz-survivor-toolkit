require 'Vehicles/TimedActions/ISEnterVehicle'
require 'Vehicles/TimedActions/ISExitVehicle'
local F = require 'VehicleDoorsFixture'
local config = require 'VehiclePoseConfig'
local recording, cleanReported = false, false
-- Disposable presentation only. Repeat before UI drawing so late mod windows,
-- dashboards and MiniHealth Plus's body-outline panel cannot cover the capture.
local function cleanView()
    if not isIngameState() or not getPlayer() then return end
    UIManager.setVisibleAllUI(false)
    local ui=UIManager.getUI()
    for i=0,ui:size()-1 do ui:get(i):setVisible(false) end
    local tip=UIManager.getToolTip()
    if tip then tip:setVisible(false) end
    if recording and not cleanReported then
        local state=vehiclePoseCleanView()
        assert(string.find(state,'visible=0 global=false',1,true),state)
        print('[VEHICLE_POSE] CLEAN_VIEW ' .. state)
        cleanReported=true
    end
end
Events.OnPreUIDraw.Add(cleanView)

local cases = {
    {name='enter-driver', enter=true, seat=0},
    {name='cancel-exit', cancel=true, seat=0},
    {name='exit-driver', seat=-1},
    {name='cancel-enter', enter=true, cancel=true, seat=-1},
    {name='enter-passenger', enter=true, seat=1},
    {name='exit-passenger', seat=-1},
}
local id, requested, stage, index, started, shot, action, authority, failed = nil, false, 'prepare', 1, nil, false, nil, nil, false
local nextAt, ticks = 0, 0
local function vehicle() return isClient() and id and getVehicleById(id) or F.vehicle end
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= 'VehiclePoseTest' then return end
    if command == 'vehicle' then id=args.id end
    if command == 'checked' then authority=args.name end
end)
local function check(p, v, c)
    assert(p:getVehicle() == (c.seat >= 0 and v or nil), 'Wrong final vehicle')
    assert(v:getSeat(p) == c.seat, 'Wrong final seat')
    assert(not p:getVariableBoolean('bEnteringVehicle') and not p:getVariableBoolean('bExitingVehicle'), 'Stale transition flag')
    assert(not p:getVariableBoolean('EnterAnimationFinished') and not p:getVariableBoolean('ExitAnimationFinished'), 'Stale completion flag')
    if isClient() then sendClientCommand('VehiclePoseTest', 'check', {id=id, name=c.name, seat=c.seat})
    else print('[VEHICLE_POSE] AUTHORITY ' .. c.name); authority=c.name end
end
local function run()
    local p = getPlayer()
    p:setGodMod(true)
    cleanView()
    getCore():setAutoZoom(0,false)
    if getCore():getZoom(0)>.501 then getCore():doZoomScroll(0,-1) end
    if ISCharacterInfoWindow and ISCharacterInfoWindow.instance then ISCharacterInfoWindow.instance:setVisible(false) end
    if stage == 'prepare' then
        if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:onClose() end
        if not requested then
            requested=true
            if isClient() then sendClientCommand('VehiclePoseTest', 'prepare', {}) else id=F.prepare(p) end
        end
        local v=vehicle()
        if not v or not v:getPartById('DoorFrontLeft'):getDoor():isOpen() then return end
        if config.capture then
            assert(toolkitVideoStart(config.output, config.ffmpeg))
            recording=true
        end
        stage='queue'; nextAt=getTimestampMs()+5000
    elseif stage == 'queue' then
        assert(#ISTimedActionQueue.getTimedActionQueue(p).queue == 0)
        local c,v=cases[index],vehicle()
        vehiclePoseLabel(c.name)
        if c.enter then
            local seat=c.seat >= 0 and c.seat or 0
            local pos=Vector3f.new()
            v:getWorldPos(v:getPassengerPosition(seat,'outside'):getOffset(),pos)
            p:setX(pos:x());p:setY(pos:y());p:setZ(0)
            p:setNextX(pos:x());p:setNextY(pos:y());p:setLastX(pos:x());p:setLastY(pos:y())
            p:ensureOnTile();p:setCurrentSquareFromPosition();p:setMovingSquareNow()
            action=ISEnterVehicle:new(p,v,seat)
        else action=ISExitVehicle:new(p) end
        stage='approach'; nextAt=getTimestampMs()+700
    elseif stage == 'approach' then
        local c=cases[index]
        getCore():TakeFullScreenshot('vehicle-pose-' .. c.name .. '-before.png')
        print('[VEHICLE_POSE] SAMPLE ' .. c.name .. ' before ' .. vehiclePoseSample(p))
        print('[VEHICLE_POSE] CONTACT_BASE ' .. c.name .. ' ' .. vehiclePoseBoundary(p,vehicle(),c.enter and (c.seat >= 0 and c.seat or 0) or vehicle():getSeat(p),c.enter or false))
        ISTimedActionQueue.add(action)
        started=nil; shot=false; ticks=0; stage='active'
    elseif stage == 'active' then
        local c=cases[index]
        local flag=c.enter and 'bEnteringVehicle' or 'bExitingVehicle'
        if p:getVariableBoolean(flag) then
            if not started then started=getTimestampMs() end
            ticks=ticks+1
            print('[VEHICLE_POSE] SAMPLE ' .. c.name .. ' active ' .. vehiclePoseSample(p))
            if getTimestampMs()-started >= 180 and not shot then
                print('[VEHICLE_POSE] POSE ' .. c.name .. ' ' .. vehiclePoseCheck(p, config.baseline and 'Bob_IdleDriving' or (c.enter and 'Bob_ToolkitVehicleEnter' or 'Bob_ToolkitVehicleExit')))
                -- A synchronous full screenshot stalls this .625s action and drops
                -- its weight-transfer frames. The continuous framebuffer video is
                -- the active capture; retain a frame index for offline extraction.
                if recording then print('[VEHICLE_POSE] FRAME ' .. c.name .. ' index=' .. toolkitVideoStatus().frames)
                else getCore():TakeFullScreenshot('vehicle-pose-' .. c.name .. '.png') end
                shot=true
                if c.cancel then ISTimedActionQueue.clear(p) end
            end
        end
        if #ISTimedActionQueue.getTimedActionQueue(p).queue == 0 then
            assert(started and shot and ticks>=2, 'Transition skipped its active phase')
            print('[VEHICLE_POSE] DURATION ' .. c.name .. ' ms=' .. (getTimestampMs()-started) .. ' ticks=' .. ticks)
            print('[VEHICLE_POSE] SAMPLE ' .. c.name .. ' after ' .. vehiclePoseSample(p))
            getCore():TakeFullScreenshot('vehicle-pose-' .. c.name .. '-after.png')
            check(p,vehicle(),c); stage='authority'; nextAt=getTimestampMs()+500
        end
    elseif stage == 'authority' and authority == cases[index].name then
        print('[VEHICLE_POSE] SAMPLE ' .. cases[index].name .. ' settled ' .. vehiclePoseSample(p))
        getCore():TakeFullScreenshot('vehicle-pose-' .. cases[index].name .. '-settled.png')
        print('[VEHICLE_POSE] PASS ' .. cases[index].name)
        authority=nil; index=index+1
        if index>#cases then
            if recording then assert(toolkitVideoStop()); stage='video'
            else stage='done'; print('[VEHICLE_POSE] COMPLETE transitions') end
        else stage='queue'; nextAt=getTimestampMs()+700 end
    elseif stage == 'video' then
        local status=toolkitVideoStatus()
        assert(status.state~='failed', tostring(status.error))
        if status.state=='completed' then
            print('[VEHICLE_POSE] VIDEO ' .. status.file .. ' frames=' .. status.frames)
            stage='done'; print('[VEHICLE_POSE] COMPLETE transitions')
        end
    end
end
Events.OnTick.Add(function()
    if failed or stage=='done' or not isIngameState() or not getPlayer() or not getPlayer():getSquare() or getTimestampMs()<nextAt then return end
    nextAt=getTimestampMs()+30
    local ok,err=pcall(run)
    if not ok then failed=true; print('[VEHICLE_POSE] FAIL stage=' .. stage .. ' ' .. tostring(err)) end
end)
