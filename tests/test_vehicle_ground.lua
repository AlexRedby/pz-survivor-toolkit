require = function() end
local function derive(self, name)
    local class = {Type = name, derive = self.derive}
    class.__index = class
    return setmetatable(class, {__index = self})
end
ISBaseTimedAction = {derive = derive, new = function(self, character)
    return setmetatable({character = character}, self)
end, stop = function(self) self.stopped = true end, perform = function() end}

local adds, removes, callbacks = 0, 0, 0
sendAddItemToContainer = function() adds = adds + 1 end
sendRemoveItemFromContainer = function() removes = removes + 1 end
isServer = function() return true end
instanceof = function(item, kind) return item.kind == kind end
getText = function(key) return key end
getGameTime = function() return {getCalender = function()
    return {getTimeInMillis = function() return 1 end}
end} end
IsoObjectChange = {MECHANIC_ACTION_DONE = 1}
VehicleUtils = {getPerksTableForChr = function() return {} end,
    calculateInstallationSuccess = function() return 100, 0 end,
    callLua = function() callbacks = callbacks + 1 end}
ZombRand = function(a, b) return b and a or 0 end
Perks = {Mechanics = 1}
playServerSound = function() end
addXp = function() end
ISTransferAction = {GetDropItemOffset = function() return 0.25, 0.5, 0 end}
ISInventoryPage = {}

local function fixture(weight, capacity)
    local inventory = {items = {}, capacity = capacity or 50}
    function inventory:contains(item) return self.items[item] == true end
    function inventory:hasRoomFor(_, item) return item.weight <= self.capacity end
    function inventory:AddItem(item) self.items[item] = true end
    function inventory:Remove(item) self.items[item] = nil end
    local square = {items = {}, totalWeight = 100}
    function square:AddWorldInventoryItem(item, x, y, z)
        if self.reject then return nil end
        self.items[#self.items + 1] = item
        self.offsets = {x, y, z}
        return item
    end
    local character = {square = square, inventory = inventory}
    function character:getCurrentSquare() return self.square end
    function character:getInventory() return self.inventory end
    function character:isMechanicsCheat() return false end
    function character:isTimedActionInstant() return false end
    function character:getPerkLevel() return 0 end
    function character:sendObjectChange(_, args) self.success = args.success end
    function character:addMechanicsItem() self.mechanicsRecorded = true end
    local item = {weight = weight, setItemCapacity = function(self, value) self.content = value end,
        getID = function() return 123 end, getDisplayName = function() return "Test vehicle part" end}
    local vehicle = {canUninstallPart = function() return true end,
        transmitPartItem = function(self) self.transmitted = true end,
        getMechanicalID = function() return 456 end}
    local part = {item = item, vehicle = vehicle}
    function part:getInventoryItem() return self.item end
    function part:setInventoryItem(value) self.item = value end
    function part:getVehicle() return self.vehicle end
    function part:getTable(name) return name == "install" and {skills = {}, time = 50} or {complete = "nativeCallback"} end
    function part:getContainerContentAmount() return 12 end
    function part:getCondition() return 100 end
    function part:setCondition(value) self.condition = value end
    function vehicle:transmitPartCondition() self.failureTransmitted = true end
    return character, part, item
end

if NativeUninstallSource then
    assert(loadstring(NativeUninstallSource))()
else
    ISUninstallVehiclePart = ISBaseTimedAction:derive("ISUninstallVehiclePart")
    function ISUninstallVehiclePart:new(character, part, workTime)
        local action = ISBaseTimedAction.new(self, character)
        action.part, action.vehicle, action.workTime = part, part:getVehicle(), workTime
        return action
    end
    function ISUninstallVehiclePart:isValid() return self.part:getInventoryItem() ~= nil end
    function ISUninstallVehiclePart:complete()
        local item = self.part:getInventoryItem()
        if not item then return false end
        self.part:setInventoryItem(nil)
        if self.character:getInventory():hasRoomFor(self.character, item) then
            self.character:getInventory():AddItem(item)
            sendAddItemToContainer(self.character:getInventory(), item)
        else self.character:getCurrentSquare():AddWorldInventoryItem(item, 0.25, 0.5, 0) end
        return true
    end
end
local nativeNew, nativeComplete = ISUninstallVehiclePart.new, ISUninstallVehiclePart.complete
dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/UninstallToGround.lua")

for _, weight in ipairs({0.1, 1, 49, 1000}) do
    local character, part, item = fixture(weight)
    local action = PZSTUninstallToGround:new(character, part, 50)
    assert(action.Type == "PZSTUninstallToGround" and action.workTime == 50)
    local serverAction = PZSTUninstallToGround:new(action.character, action.part, action.workTime)
    assert(serverAction:isValid() and serverAction:complete())
    assert(part:getInventoryItem() == nil and #character.square.items == 1)
    assert(character.square.items[1] == item and not character.inventory:contains(item))
    assert(character.inventory.capacity == 50, "must never mutate inventory capacity")
    if NativeUninstallSource then
        assert(item.content == 12 and character.success and character.mechanicsRecorded and part.vehicle.transmitted)
    end
    assert(not serverAction:isValid() and not serverAction:complete(), "repeat completion must not duplicate")
    assert(#character.square.items == 1)
end
assert(adds == 3 and removes == 3, "already-dropped heavy parts need no inventory removal")
if NativeUninstallSource then assert(callbacks == 4, "native callbacks must run once") end

local character, part, item = fixture(1)
local action = PZSTUninstallToGround:new(character, part, 50)
character.square = nil
assert(not action:isValid() and not action:complete() and part.item == item)
character.square = fixture(1).square
character.square.reject = true
assert(action:complete() and character.inventory:contains(item), "failed world placement must retain item")

character, part, item = fixture(1)
action = PZSTUninstallToGround:new(character, part, 50)
action:stop()
assert(action.stopped and part.item == item and #character.square.items == 0, "cancel must not remove part")
if NativeUninstallSource then
    character, part, item = fixture(1)
    action = PZSTUninstallToGround:new(character, part, 50)
    VehicleUtils.calculateInstallationSuccess = function() return 0, 100 end
    assert(action:complete() and part.item == item and #character.square.items == 0)
    assert(not character.success and part.condition < 100 and part.vehicle.failureTransmitted)
    VehicleUtils.calculateInstallationSuccess = function() return 100, 0 end
end

character, part, item = fixture(1)
assert(ISUninstallVehiclePart:new(character, part, 50):complete())
assert(character.inventory:contains(item) and #character.square.items == 0, "default removal stays native")
assert(ISUninstallVehiclePart.new == nativeNew and ISUninstallVehiclePart.complete == nativeComplete)

local start
local groundEnabled = true
PZSurvivorToolkit = {Settings = {uninstallToGround = function() return groundEnabled end}}
Events = {OnGameStart = {Add = function(callback) start = callback end}}
local function vehicleItem(fullType, kind, scriptType)
    return {kind = kind, getFullType = function() return fullType end,
        getCondition = function() return 100 end, getID = function() return 0 end,
        getDisplayName = function() return "Identical vehicle part" end,
        getTags = function() return {toArray = function() return {"VehiclePart", "Installable"} end} end,
        getWorldSprite = function() return "vehicle_sprite" end,
        getScriptItem = function() return {getFullName = function() return scriptType end} end}
end
local windshield = vehicleItem("Base.Windshield1")
local spareWindshield = vehicleItem("Base.Windshield1")
local moveable = vehicleItem("Base.Moveable", "Moveable", "Base.CarSeat")
local refreshed, nilMaps = false, false
local collector
if NativeVehicleItemsSource then
    local source = assert(NativeVehicleItemsSource:match(
        "(function VehicleUtils%.getInventoryContainersRecurse.-)function VehicleUtils%.split"))
    assert(loadstring(source))()
    local function list(values)
        return {size = function() return #values end, get = function(_, i) return values[i + 1] end,
            isEmpty = function() return #values == 0 end}
    end
    local function container(values)
        return {getItems = function() return list(values()) end,
            getAllEvalRecurse = function() return list({}) end}
    end
    local inventory = container(function() return {} end)
    local floor = container(function() return refreshed and {spareWindshield} or {windshield, moveable} end)
    local proximity = container(function()
        return refreshed and {spareWindshield} or {windshield, spareWindshield, moveable, windshield}
    end)
    luautils = {tableContains = function(values, value)
        for _, existing in ipairs(values) do if existing == value then return true end end
        return false
    end}
    getPlayerInventory = function() return {inventoryPane = {inventoryPage = {backpacks = {{inventory = inventory}}}}} end
    getPlayerLoot = function() return {inventoryPane = {inventoryPage = {backpacks = {
        {inventory = floor}, {inventory = proximity}}}}} end
    collector = VehicleUtils.getItems
else
    collector = function()
        if refreshed then
            return {["Base.Windshield1"] = {spareWindshield, spareWindshield}},
                {VehiclePart = {spareWindshield, spareWindshield}, Installable = {spareWindshield, spareWindshield}}
        end
        return {["Base.Windshield1"] = {windshield, windshield, spareWindshield, windshield},
            ["Base.Moveable"] = {moveable, moveable}, ["Base.CarSeat"] = {moveable, moveable}},
            {VehiclePart = {windshield, moveable, windshield, spareWindshield, moveable, windshield},
                Installable = {windshield, moveable, windshield, spareWindshield, moveable, windshield}}
    end
end
local collectorCalls, rawByType, rawByTag, rawWindshields = 0
local forwarded = {}
VehicleUtils.getItems = function(playerNum, extra)
    assert(playerNum == 2 and extra == forwarded, "collector arguments must be forwarded")
    collectorCalls = collectorCalls + 1
    if nilMaps == true then return nil, nil end
    rawByType, rawByTag = collector(playerNum)
    rawWindshields = rawByType["Base.Windshield1"]
    if nilMaps == "types" then return nil, rawByTag end
    if nilMaps == "tags" then return rawByType, nil end
    return rawByType, rawByTag
end
local queued, throw = {}, false
ISVehiclePartMenu = {onUninstallPart = function(player, targetPart)
    queued[#queued + 1] = "native path/tools/hood"
    if throw then error("native menu failed") end
    queued[#queued + 1] = ISUninstallVehiclePart:new(player, targetPart, 50)
    queued[#queued + 1] = "native close hood"
end}
local context = {}
function context:getOptionFromName(name)
    for _, option in ipairs(self.options) do if option.name == name then return option end end
end
function context:insertOptionAfter(_, name, target, onSelect, param1)
    local option = {name = name, target = target, onSelect = onSelect, param1 = param1}
    table.insert(self.options, 2, option)
    return option
end
ISVehicleMechanics = {doPartContextMenu = function(self, targetPart)
    self.context = context
    context.options = self.removable and {{name = "Uninstall", target = character,
        onSelect = ISVehiclePartMenu.onUninstallPart, param1 = targetPart,
        notAvailable = self.blocked, toolTip = "native tool/skill requirements"}} or {}
end}
dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/VehicleMechanics.lua")
start()
local installedMenu = ISVehicleMechanics.doPartContextMenu
local installedCollector = VehicleUtils.getItems
start()
assert(ISVehicleMechanics.doPartContextMenu == installedMenu, "repeated game starts must not stack hooks")
assert(VehicleUtils.getItems == installedCollector, "repeated game starts must not stack collector hooks")
local byType, byTag = VehicleUtils.getItems(2, forwarded)
assert(byType == rawByType and byTag == rawByTag, "native result maps must be preserved")
assert(byType["Base.Windshield1"] == rawWindshields, "native result lists must be compacted in place")
assert(#byType["Base.Windshield1"] == 2, "floor/proximity overlap must list each physical windshield once")
assert(byType["Base.Windshield1"][1] == windshield and byType["Base.Windshield1"][2] == spareWindshield,
    "distinct parts with matching type, name, condition and unset ID must retain first-seen order")
assert(#byType["Base.Moveable"] == 1 and byType["Base.Moveable"][1] == moveable
    and #byType["Base.CarSeat"] == 1 and byType["Base.CarSeat"][1] == moveable,
    "the same item must retain both native type aliases")
for _, tag in ipairs({"VehiclePart", "Installable"}) do
    assert(#byTag[tag] == 3 and byTag[tag][1] == windshield and byTag[tag][2] == moveable
        and byTag[tag][3] == spareWindshield, "each tag needs its own identity deduplication")
end
assert(collectorCalls == 1, "one refresh must call the native collector once")
refreshed, groundEnabled = true, false
byType, byTag = VehicleUtils.getItems(2, forwarded)
assert(collectorCalls == 2 and #byType["Base.Windshield1"] == 1
    and byType["Base.Windshield1"][1] == spareWindshield and byType["Base.Moveable"] == nil,
    "live refresh must reflect current containers even when uninstall-to-ground is disabled")
assert(#byTag.VehiclePart == 1 and byTag.VehiclePart[1] == spareWindshield)
nilMaps = "types"
byType, byTag = VehicleUtils.getItems(2, forwarded)
assert(byType == nil and #byTag.VehiclePart == 1, "tag maps must still be deduplicated without a type map")
nilMaps = "tags"
byType, byTag = VehicleUtils.getItems(2, forwarded)
assert(#byType["Base.Windshield1"] == 1 and byTag == nil, "type maps must still be deduplicated without a tag map")
nilMaps = true
byType, byTag = VehicleUtils.getItems(2, forwarded)
assert(byType == nil and byTag == nil, "nil native result maps must stay nil")
nilMaps, groundEnabled = false, true
local window = setmetatable({removable = true, blocked = true}, {__index = ISVehicleMechanics})
window:doPartContextMenu(part)
assert(#context.options == 2 and context.options[1].onSelect == ISVehiclePartMenu.onUninstallPart)
local ground = context.options[2]
assert(ground.notAvailable and ground.toolTip == context.options[1].toolTip)
window.blocked = false
window:doPartContextMenu(part)
ground = context.options[2]
assert(not ground.notAvailable)
groundEnabled = false
window:doPartContextMenu(part)
assert(#context.options == 1, "disabled feature leaves only native uninstall")
ground.onSelect(ground.target, ground.param1)
assert(#queued == 0, "stale context callback must respect feature disable")
groundEnabled = true
window:doPartContextMenu(part)
ground = context.options[2]
ground.onSelect(ground.target, ground.param1)
assert(queued[1] == "native path/tools/hood" and queued[2].Type == "PZSTUninstallToGround"
    and queued[3] == "native close hood" and ISUninstallVehiclePart.new == nativeNew)
throw = true
assert(not pcall(ground.onSelect, ground.target, ground.param1) and ISUninstallVehiclePart.new == nativeNew,
    "native constructor must restore after a menu error")
window.removable = false
window:doPartContextMenu(part)
assert(#context.options == 0, "non-removable parts must not gain a new action")
print("Vehicle mechanics regressions passed" .. (NativeUninstallSource and " against native completion" or "")
    .. (NativeVehicleItemsSource and " and native item collection." or "."))
