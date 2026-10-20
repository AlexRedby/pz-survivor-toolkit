require "PZSurvivorToolkit"
require "Vehicles/ISUI/ISVehicleMenu"
require "Vehicles/TimedActions/ISCloseVehicleDoor"

local Doors = {}
PZSurvivorToolkit.VehicleDoors = Doors

local function openDoor(character, vehicle)
    if not character or character:isDead() or character:getVehicle() ~= vehicle or not vehicle then return end
    local seat = vehicle:getSeat(character)
    if seat < 0 then return end
    local part = vehicle:getPassengerDoor(seat)
    if part and part:getInventoryItem() and part:getDoor() and part:getDoor():isOpen() then return part end
end

local function pendingClose(character, vehicle, part)
    local queue = ISTimedActionQueue.queues[character]
    for _, action in ipairs(queue and queue.queue or {}) do
        if action.Type == "ISCloseVehicleDoor" and action.vehicle == vehicle and action.part == part then return true end
    end
    return false
end

function Doors.canClose(character, vehicle, part)
    local speeds = UIManager.getSpeedControls()
    if speeds and speeds:getCurrentGameSpeed() == 0 then return false end
    return part ~= nil and openDoor(character, vehicle) == part and not pendingClose(character, vehicle, part)
end

function Doors.close(character, vehicle, part)
    -- Menu callbacks can outlive their seat, vehicle or installed door.
    if not Doors.canClose(character, vehicle, part) then return end
    ISTimedActionQueue.add(ISCloseVehicleDoor:new(character, vehicle, part))
end

local function hasCloseSlice(menu, character, part)
    for _, slice in ipairs(menu.slices) do
        local command = slice.command
        if command and command[2] == character then
            if command[1] == Doors.close and command[4] == part then return true end
            if command[1] == ISVehicleMenu.onCloseDoor and command[3] == part then return true end
        end
    end
    return false
end

local function install()
    if ISVehicleMenu.PZSTCloseDoorInstalled then return end
    ISVehicleMenu.PZSTCloseDoorInstalled = true
    local showRadialMenu = ISVehicleMenu.showRadialMenu
    function ISVehicleMenu.showRadialMenu(character, ...)
        local menu = getPlayerRadialMenu(character:getPlayerNum())
        local wasVisible = menu:isReallyVisible()
        local result = showRadialMenu(character, ...)
        local speeds = UIManager.getSpeedControls()
        if speeds and speeds:getCurrentGameSpeed() == 0 then return result end
        local vehicle = character:getVehicle()
        local part = openDoor(character, vehicle)
        if not part then return result end
        -- AddUI is deferred; the opened menu is not really visible until the next frame.
        -- Its previous visibility distinguishes native open from toggle-close.
        if not wasVisible and not hasCloseSlice(menu, character, part) then
            menu:addSlice(getText("ContextMenu_Close_door"), getTexture("media/textures/PZSurvivorToolkit/vehicle_close_door_radial.png"),
                Doors.close, character, vehicle, part)
        end
        return result
    end
end

Events.OnGameStart.Add(install)
return Doors
