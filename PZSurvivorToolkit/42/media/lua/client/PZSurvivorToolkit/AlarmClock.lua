require "PZSurvivorToolkit"

local AlarmClock = {}
PZSurvivorToolkit.AlarmClock = AlarmClock

local function resetMultiplayerSpeed()
    if not MPFastForward or not MPFF_Panel or not UIManager or not UIManager.getUI then return end
    local normal = MPFastForward.NORMAL
    if type(normal) ~= "number" then return end
    local ui = UIManager.getUI()
    if not ui then return end
    -- MPFF keeps its Client local. Find its live panel without loading or modifying the mod.
    for i = 0, ui:size() - 1 do
        local element = ui:get(i)
        local panel = element and element.getTable and element:getTable()
        if type(panel) == "table" and getmetatable(panel) == MPFF_Panel
            and panel.getSelected and panel.userSelect then
            local time = getGameTime and getGameTime()
            local multiplier = time and time:getMultiplier() or 1
            if panel:getSelected() > normal or multiplier > 1 then
                -- Use the same safety veto as MPFF's nearby-zombie/movement cancellation.
                panel:userSelect(normal, false, true)
            end
            return
        end
    end
end

function AlarmClock.onTick()
    if not toolkitConsumeAlarmRing or toolkitConsumeAlarmRing() ~= true then return end
    if isClient and isClient() then
        resetMultiplayerSpeed()
        return
    end
    local speeds = UIManager and UIManager.getSpeedControls and UIManager.getSpeedControls()
    if speeds and speeds:getCurrentGameSpeed() > 1 then speeds:SetCurrentGameSpeed(1) end
end

Events.OnTick.Add(AlarmClock.onTick)
return AlarmClock
