if not NativeActionRoot then
    print('Vehicle door native contracts skipped (pass --native-action-root media/lua).')
    return
end

require = function() end
local function derive(self, name)
    local class = {Type = name, derive = derive}; class.__index = class
    return setmetatable(class, {__index = self})
end
local function read(path)
    if NativeReadText then return NativeReadText(path) end
    local file = assert(io.open(path)); local text = file:read('*a'); file:close(); return text
end
local function native(path) assert(loadstring(read(NativeActionRoot .. '/' .. path)))() end
ISBaseObject, ISPanelJoypad = {derive = derive}, {derive = derive}
native('shared/TimedActions/ISBaseTimedAction.lua')
native('shared/Vehicles/TimedActions/ISCloseVehicleDoor.lua')
native('client/ISUI/ISRadialMenu.lua')
-- Run the current native menu builder, avoiding unrelated global initializers.
ISVehicleMenu = {}
local nativeMenuText = read(NativeActionRoot .. '/client/Vehicles/ISUI/ISVehicleMenu.lua'):gsub('\r', '')
assert(loadstring(assert(nativeMenuText:match('(function ISVehicleMenu.showRadialMenu%(playerObj%).-\nend)'))))()
assert(loadstring(assert(nativeMenuText:match('(function ISVehicleMenu.onCloseDoor%(playerObj, part%).-\nend)'))))()
local nativeNew, nativeValid, nativePerform, nativeComplete = ISCloseVehicleDoor.new,
    ISCloseVehicleDoor.isValid, ISCloseVehicleDoor.perform, ISCloseVehicleDoor.complete

local starts, client, server, paused, completions, updates = {}, true, false, false, 0, 0
PZSurvivorToolkit = {}
Events = {OnGameStart = {Add = function(fn) starts[#starts + 1] = fn end}}
isClient = function() return client end
isServer = function() return server end
getText, getTexture = function(key) return key end, function(path) return path end
UIManager = {getSpeedControls = function()
    return {getCurrentGameSpeed = function() return paused and 0 or 1 end}
end}
Joypad, JoypadState = {Texture = {}, DPadUp = 1}, {players = {}}
VehicleUtils = {getChildWindow = function() return nil end}
ISVehiclePartMenu = {}
getServerOptions = function() return {getBoolean = function() return false end} end
getSoundManager = function() return {playUISound = function() end} end
getPlayerScreenLeft, getPlayerScreenTop = function() return 0 end, function() return 0 end
getPlayerScreenWidth, getPlayerScreenHeight = function() return 1200 end, function() return 800 end
triggerEvent = function(event) if event == 'OnContainerUpdate' then updates = updates + 1 end end
ISLogSystem = {logAction = function() end}
local queue = {queue = {}, onCompleted = function(self, action)
    completions = completions + 1
    for index, candidate in ipairs(self.queue) do
        if candidate == action then table.remove(self.queue, index); break end
    end
end}
ISTimedActionQueue = {getTimedActionQueue = function() return queue end,
    queues = {}, add = function(action) queue.queue[#queue.queue + 1] = action end}
local menu = setmetatable({slices = {}, sounds = {}, visible = false}, ISRadialMenu)
function menu:isReallyVisible() return self.visible end
function menu:addToUIManager() self.pendingDisplay = true end
function menu:undisplay() self.visible = false; self.pendingDisplay = nil end
function menu:getWidth() return 200 end
function menu:getHeight() return 200 end
function menu:setX() end
function menu:setY() end
getPlayerRadialMenu = function() return menu end
local outsideCalls = 0
ISVehicleMenu.showRadialMenuOutside = function() outsideCalls = outsideCalls + 1 end

local function fixture()
    local door = {open = true, changes = 0}
    function door:isOpen() return self.open end
    function door:setOpen(value) self.open = value; self.changes = self.changes + 1 end
    local vehicle = {seat = 2, transmissions = 0}
    local part = {door = door, item = {}}
    function part:getDoor() return self.door end
    function part:getInventoryItem() return self.item end
    function part:getContainerSeatNumber() return 2 end
    function part:getVehicle() return vehicle end
    function part:getId() return 'DoorRearLeft' end
    function vehicle:getSeat() return self.seat end
    function vehicle:getPassengerDoor(seat) if seat == 2 then return self.part end end
    function vehicle:isDriver() return false end
    function vehicle:getPartById() return nil end
    function vehicle:hasLightbar() return false end
    function vehicle:isAnyDoorLocked() return false end
    function vehicle:isStopped() return true end
    function vehicle:transmitPartDoor(sent) assert(sent == part); self.transmissions = self.transmissions + 1 end
    function vehicle:playPassengerAnim(seat, animation) self.animation = animation; self.animationSeat = seat end
    vehicle.part = part
    local character = {vehicle = vehicle}
    function character:getVehicle() return self.vehicle end
    function character:getPlayerNum() return 0 end
    function character:isDead() return self.dead == true end
    function character:isAsleep() return false end
    function character:PlayAnim() end
    function character:setIsFarming() end
    return character, vehicle, part, door
end
local nativeShow, foreignClose = ISVehicleMenu.showRadialMenu, false
ISVehicleMenu.showRadialMenu = function(player)
    nativeShow(player)
    if foreignClose and (menu.visible or menu.pendingDisplay) and player:getVehicle() then
        menu:addSlice('ContextMenu_Close_door', 'foreign-icon', ISVehicleMenu.onCloseDoor,
            player, player:getVehicle().part)
    end
end
local modulePath = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/VehicleDoors.lua'
assert(loadfile(modulePath))()
for _, fn in ipairs(starts) do fn() end
local api = assert(PZSurvivorToolkit.VehicleDoors)
local wrappedMenu = ISVehicleMenu.showRadialMenu
for _, fn in ipairs(starts) do fn() end
assert(ISVehicleMenu.showRadialMenu == wrappedMenu, 'repeated game start must not stack wrappers')
assert(ISCloseVehicleDoor.new == nativeNew and ISCloseVehicleDoor.isValid == nativeValid
    and ISCloseVehicleDoor.perform == nativePerform and ISCloseVehicleDoor.complete == nativeComplete,
    'door control must retain the native timed action class')

local character, vehicle, part, door = fixture()
ISTimedActionQueue.queues[character] = queue
ISVehicleMenu.showRadialMenu(character)
local closeSlice
for _, slice in ipairs(menu.slices) do
    if slice.text == 'ContextMenu_Close_door' then
        assert(not closeSlice, 'only one Close Door slice is added'); closeSlice = slice
    end
end
assert(closeSlice and closeSlice.texture == 'media/textures/PZSurvivorToolkit/vehicle_close_door_radial.png',
    'occupied open door gains the native translated label and distinct closing-door icon')
closeSlice.command[1](unpack(closeSlice.command, 2))
assert(menu.pendingDisplay and not menu.visible, 'native AddUI becomes visible on the next frame')
menu.visible = true; menu.pendingDisplay = nil
local action = assert(queue.queue[1])
assert(#queue.queue == 1 and getmetatable(action) == ISCloseVehicleDoor
    and action.character == character and action.vehicle == vehicle and action.part == part and action.seat == 2)
assert(door.open and door.changes == 0 and vehicle.transmissions == 0,
    'selecting Close Door only queues authority; it must not mutate the part directly')
api.close(character, vehicle, part)
assert(#queue.queue == 1, 'repeated selection must not queue a duplicate native close')
ISVehicleMenu.showRadialMenu(character)
assert(not menu.visible and #menu.slices == 0, 'a second V press closes and clears the menu')
paused = true
ISVehicleMenu.showRadialMenu(character)
assert(not menu.visible and #menu.slices == 0, 'paused calls preserve the native early return')
paused = false

-- Completion and door synchronization remain native in SP and on the server.
client, server = false, false
assert(action:isValid())
action:perform()
assert(door.open and completions == 1, 'perform must not predict authoritative door closure')
assert(action:complete() and not door.open and door.changes == 1
    and vehicle.transmissions == 1 and updates == 1, 'native SP completion closes and transmits the exact part')
client, server = true, false
door.open = true
api.close(character, vehicle, part)
action = queue.queue[1]
action:perform()
assert(door.open and vehicle.transmissions == 1, 'client perform must leave door mutation to server completion')
client, server = false, true
assert(action:complete() and not door.open and vehicle.transmissions == 2 and updates == 2,
    'native server completion performs the synchronized closure')
client, server, door.open = true, false, true

local function rejected(change, restore)
    queue.queue = {}
    change(); api.close(character, vehicle, part)
    assert(#queue.queue == 0, 'a stale menu callback must not queue another door or detached part')
    restore()
end
rejected(function() character.vehicle = nil end, function() character.vehicle = vehicle end)
rejected(function() character.vehicle = {} end, function() character.vehicle = vehicle end)
rejected(function() vehicle.seat = 3 end, function() vehicle.seat = 2 end)
rejected(function() vehicle.part = setmetatable({}, {__index = part}) end, function() vehicle.part = part end)
rejected(function() vehicle.part = nil end, function() vehicle.part = part end)
rejected(function() part.door = nil end, function() part.door = door end)
rejected(function() part.item = nil end, function() part.item = {} end)
rejected(function() door.open = false end, function() door.open = true end)
api.close(nil, vehicle, part); api.close(character, nil, part); api.close(character, vehicle, nil)
assert(#queue.queue == 0, 'missing callback arguments are harmless')
local function noSlice(change, restore)
    menu.visible = false; menu:clear(); change(); ISVehicleMenu.showRadialMenu(character)
    for _, slice in ipairs(menu.slices) do assert(slice.text ~= 'ContextMenu_Close_door') end
    restore()
end
noSlice(function() door.open = false end, function() door.open = true end)
noSlice(function() part.item = nil end, function() part.item = {} end)
noSlice(function() part.door = nil end, function() part.door = door end)
noSlice(function() character.vehicle = nil end, function() character.vehicle = vehicle end)
assert(outsideCalls == 1, 'outside vehicle calls still delegate to the native outside builder')
menu.visible, foreignClose = false, true
ISVehicleMenu.showRadialMenu(character)
local closeCount = 0
for _, slice in ipairs(menu.slices) do
    if slice.text == 'ContextMenu_Close_door' then closeCount = closeCount + 1 end
end
assert(closeCount == 1, 'an existing mod slice calling the native close for this part must not be duplicated')
print('Vehicle door native contracts passed: radial lifecycle, target validation, installed door, deduplication and SP/server synchronization.')
