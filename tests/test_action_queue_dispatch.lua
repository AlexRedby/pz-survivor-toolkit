if not NativeActionRoot then print('Device dispatch native checks skipped (pass --native-action-root media/lua).'); return end
require = function(name)
    if name == 'PZSurvivorToolkit/SourceProof' then return dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/' .. name .. '.lua') end
end
local enabled, paused = true, false
PZSurvivorToolkit = {Settings = {actionQueue = function() return enabled end}}
local function derive(self, name)
    local class = {Type = name, derive = derive}; class.__index = class
    return setmetatable(class, {__index = self})
end
ISBaseObject = {derive = derive}
local install
Events = {OnTick = {Add = function() end}, OnServerCommand = {Add = function() end},
    OnGameStart = {Add = function(callback) install = callback end}}
for _, name in ipairs({'ClimbThroughWindowState','ClimbOverFenceState','ClimbOverWallState','ClimbSheetRopeState',
    'ClimbDownSheetRopeState','CloseWindowState','OpenWindowState'}) do _G[name] = {instance = function() return {} end} end
table.wipe = function(t) for key in pairs(t) do t[key] = nil end end
instanceof = function(value, name) return value and value.class == name end
local function native(path) assert(loadfile(NativeActionRoot .. '/' .. path))() end
local function text(path)
    if NativeReadText then return NativeReadText(path):gsub('\r', '') end
    local file = assert(io.open(path)); local source = file:read('*a'); file:close(); return source:gsub('\r', '')
end
local function nativeFunction(source, pattern) assert(loadstring(assert(source:match(pattern))))() end
native('shared/TimedActions/ISBaseTimedAction.lua')
native('client/TimedActions/ISTimedActionQueue.lua')
native('client/TimedActions/ISQueueActionsAction.lua')
ISInventoryTransferAction = {canMergeAction = function() return true end}
ISContextMenu, ISButton, ISInventoryPane, ISInventoryPaneContextMenu = {}, {}, {}, {}
ISMoveableCursor = {create = function() end}
ISBuildingObject = {tryBuild = function() end}
ISMoveablesAction = {new = function() end}
ISDisassembleMenu = {disassemble = function() end}
ISWorldObjectContextMenu = {}
local player = {class = 'IsoPlayer', getPlayerNum = function() return 0 end,
    isAsleep = function() return false end, isLocalPlayer = function() return true end,
    isDraggingCorpse = function() return false end, isFarming = function() return false end,
    StopAllActionQueue = function(self) self.stopped = (self.stopped or 0) + 1 end}
local function list(items)
    return {get = function(_, index) assert(items[index + 1], 'native empty list must not be indexed'); return items[index + 1] end,
        size = function() return #items end, isEmpty = function() return #items == 0 end}
end
player.inventory = {items = {}}
function player.inventory:getAllEvalRecurse(predicate)
    local found = {}; for _, item in ipairs(self.items) do if predicate(item) then found[#found + 1] = item end end
    return list(found)
end
function player:getInventory() return self.inventory end
player.getVehicle = function() end
player.getPrimaryHandItem = function() end
player.getSecondaryHandItem = function() end
player.inventory.getFirstTypeRecurse = function() return {} end
ISInventoryPaneContextMenu.transferIfNeeded = function() end
getSpecificPlayer = function() return player end
UIManager = {getSpeedControls = function() return {getCurrentGameSpeed = function() return paused and 0 or 1 end} end}
local function action(kind, object)
    return {character = player, Type = kind, object = object,
        begin = function(self) self.started = true; self.action = {} end,
        isStarted = function(self) return self.started end, forceCancel = function() end}
end
for _, kind in ipairs({'ISActivateGenerator','ISPlugGenerator','ISGeneratorInfoAction','ISFixGenerator','ISTakeGenerator',
    'ISActivateCarBatteryChargerAction','ISConnectCarBatteryToChargerAction','ISRemoveCarBatteryFromChargerAction',
    'ISTakeCarBatteryChargerAction','ISBBQToggle','ISBBQExtinguish','ISBBQRemovePropaneTank','ISBBQInsertPropaneTank','ISAddFuel','ISWaitWhileGettingUp'}) do
    _G[kind] = {new = function(_, character, object, mode)
        local a = action(kind, object); a.mode = mode; return a
    end}
end
ISToggleStoveAction = {new = function(_, character, object) return action('ISToggleStoveAction', object) end}
PZSurvivorToolkitSetStoveState = {new = function(_, character, object, desired)
    local a = action('PZSurvivorToolkitSetStoveState', object); a.desired = desired; return a
end}
ISBaseTimedAction.begin = function(self) self.action = {forceComplete = function() end} end
luautils = {walkAdj = function(character, square)
    ISTimedActionQueue.clear(character)
    local walk = action('ISWalkToTimedAction'); walk.square = square; ISTimedActionQueue.add(walk)
    return true
end}
local contextSource = text(NativeActionRoot .. '/client/ISUI/ISWorldObjectContextMenu.lua')
for _, name in ipairs({'onInfoGenerator','onPlugGenerator','onActivateGenerator','onToggleStove','doAddFuelGenerator','onFixGenerator','onTakeGenerator'}) do
    nativeFunction(contextSource, '(ISWorldObjectContextMenu%.' .. name .. ' = function.-\nend)')
end
nativeFunction(contextSource, '(local function onCarBatteryCharger_Activate.-function ISWorldObjectContextMenu.handleCarBatteryCharger.-\nend)')
native('client/ISUI/ISBBQMenu.lua')
PJCK_CookerPicker = {}
local cookPath = ProjectCookPickerSourcePath
if cookPath then nativeFunction(text(cookPath), '(function PJCK_CookerPicker:onStoveButtonClick%(%)%s.-\nend)') end
local function project(name) return assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/' .. name .. '.lua'))() end
require = function(name)
    if name == 'PZSurvivorToolkit/ActionQueueGeneratorOverlay' then return project('ActionQueueGeneratorOverlay') end
    if name == 'PZSurvivorToolkit/SourceProof' then
        return assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/' .. name .. '.lua'))()
    end
end
getText = function(key) return key end
project('ActionQueueOperations'); project('ActionQueueDefinitions'); project('ActionQueueGenerators'); project('ActionQueueWorld'); install()
local operations, world = PZSurvivorToolkit.ActionQueueOperations, PZSurvivorToolkit.ActionQueueWorld
local q = ISTimedActionQueue.getTimedActionQueue(player)
local function reset()
    q.queue, q.current, player.stopped = {}, nil, 0
    local book = action('ISReadABook'); ISTimedActionQueue.add(book); return book
end
local function object()
    local obj = {square = {}, activated = false}
    function obj:getSquare() return self.square end
    function obj:getObjectIndex() return self.removed and -1 or 1 end
    function obj:Activated() return self.activated end
    function obj:getContainer() return {isPowered = function() return not self.unpowered end} end
    return obj
end
local function expand(command)
    q:removeFromQueue(q.queue[1]); q.current = command
    command.action = {forceComplete = function() end}
    command:start()
end
for _, dispatch in ipairs({
    function(obj) ISWorldObjectContextMenu.onActivateGenerator(nil, true, obj, 0) end,
    function(obj) ISWorldObjectContextMenu.onPlugGenerator(nil, obj, 0, true) end,
    function(obj) ISWorldObjectContextMenu.onInfoGenerator(nil, obj, 0) end,
    function(obj) ISWorldObjectContextMenu.onFixGenerator(nil, obj, 0) end,
    function(obj) ISWorldObjectContextMenu.onTakeGenerator(nil, obj, 0) end,
    function(obj) ISBBQMenu.onToggle(nil, 0, obj) end,
    function(obj) ISBBQMenu.onExtinguish(nil, 0, obj) end,
    function(obj) ISBBQMenu.onRemovePropaneTank(nil, 0, obj) end,
}) do
    local book, obj = reset(), object()
    dispatch(obj); local command = q.queue[2]
    assert(#q.queue == 2 and q.current == book and player.stopped == 0 and operations.isCommand(command))
    assert(not world.isDeferredAction(command), 'device resources remain opaque to movement/cancellation')
    local tail = action('Tail'); ISTimedActionQueue.add(tail)
    expand(command)
    assert(#q.queue == 4 and q.queue[2].Type == 'ISWalkToTimedAction' and q.queue[3].object == obj
        and q.queue[4] == tail and player.stopped == 0)
    assert(q.queue[2].toolkitQueueOperation == command.toolkitQueueOperation and q.queue[3].toolkitQueueOperation == command.toolkitQueueOperation)
    reset(); dispatch(obj); command = q.queue[2]; ISTimedActionQueue.add(tail); obj.removed = true
    expand(command); assert(#q.queue == 2 and q.queue[2] == tail)
end
reset(); local target = object()
ISWorldObjectContextMenu.onActivateGenerator(nil, false, target, 0)
expand(q.queue[2]); assert(q.queue[3].mode == false, 'generator desired=false remains native constructor input')
reset(); ISWorldObjectContextMenu.onActivateGenerator(nil, true, target, 0)
local command = q.queue[2]
ISWorldObjectContextMenu.onActivateGenerator = function() error('changed callback must not run') end
expand(command); assert(#q.queue == 1, 'replaced binding invalidates deferred callback')

-- Generator fuel selects live native IDs at expansion and copies the clicked list.
Fluid = {Petrol = 'petrol'}
ISWorldObjectContextMenu.equip = function() end
ISWorldObjectContextMenu.transferIfNeeded = function() end
local function fuel(id)
    local item = {getID = function() return id end, getContainer = function() end, getFullType = function() return 'Base.PetrolCan' end}
    item.getFluidContainer = function() return {contains = function() return true end, getAmount = function() return 2 end} end
    return item
end
player.getPrimaryHandItem = function() end
reset(); local generator = object(); generator.getFuelPercentage = function() return 0 end
player.inventory.getFirstEvalRecurse = function(self, predicate)
    for _, item in ipairs(self.items) do if predicate(item) then return item end end
end
local original, replacement = fuel(42), fuel(42)
local selected = {original}
ISWorldObjectContextMenu.doAddFuelGenerator(nil, generator, selected, nil, 0)
command = q.queue[2]; selected[1] = nil; player.inventory.items = {replacement}
expand(command); assert(q.queue[3].Type == 'ISAddFuel' and q.queue[3].mode == replacement)
reset(); ISWorldObjectContextMenu.doAddFuelGenerator(nil, generator, {original}, nil, 0)
player.inventory.items = {}; expand(q.queue[2]); assert(#q.queue == 1, 'missing fuel skips only its request')

-- Inventory propane-tank insertion also re-resolves the selected native ID.
reset(); local bbq = object(); original, replacement = fuel(43), fuel(43)
ISBBQMenu.onInsertPropaneTank(nil, 0, bbq, original)
player.inventory.items = {replacement}; expand(q.queue[2])
assert(q.queue[3].Type == 'ISBBQInsertPropaneTank' and q.queue[3].mode == replacement)

-- Charger locals are rebound through the exact native get-up option shape, without global menu/walk hooks.
local charger = object()
charger.getBattery = function() return {getCurrentUsesFloat = function() return 0.5 end} end
charger.isActivated = function() return true end
charger.getTexture = function() end
ISWorldObjectContextMenu.fetchVars = {carBatteryCharger = charger}
getText = function(key) return key end
local menus, nextMenu = {}, 0
local function menu()
    local ctx = {options = {}}
    function ctx:addOption(name, target, callback, ...)
        local args = {...}; local option = {name = name, target = target, onSelect = callback}
        for i, value in pairs(args) do option['param' .. i] = value end
        self.options[#self.options + 1] = option; return option
    end
    function ctx:onGetUpAndThen(callback, ...) return callback(...) end
    function ctx:addGetUpOption(name, target, callback, ...) return self:addOption(name, self, self.onGetUpAndThen, callback, target, ...) end
    function ctx:getNew() nextMenu = nextMenu + 1; local child = menu(); child.subOptionNums = nextMenu; menus[nextMenu] = child; return child end
    function ctx:addSubMenu(option, child) option.subOption = child.subOptionNums end
    function ctx:getSubMenu(id) return menus[id] end
    return ctx
end
reset(); local ctx = menu()
ISWorldObjectContextMenu.handleCarBatteryCharger(false, ctx, {}, player, player.inventory)
local sub = menus[ctx.options[1].subOption]
for _, option in ipairs(sub.options) do
    reset()
    option.onSelect(option.target, option.param1, option.param2, option.param3, option.param4)
    command = q.queue[2]; assert(operations.isCommand(command) and player.stopped == 0)
    local tail = action('Tail'); ISTimedActionQueue.add(tail); expand(command)
    assert(q.queue[2].Type == 'ISWaitWhileGettingUp' and q.queue[3].Type == 'ISWalkToTimedAction' and q.queue[5] == tail)
end
-- Charger connect uses a live ID replacement; missing selected batteries do not clear the tail.
reset(); original, replacement = fuel(44), fuel(44)
for _, item in ipairs({original, replacement}) do
    item.getCurrentUsesFloat = function() return 0.5 end
    item.getName = function() return 'battery' end
    item.getIcon = function() return {splitIcon = function() return {} end} end
end
player.inventory.items = {original}
player.inventory.getAllTypeEvalRecurse = function(self, kind, predicate, previous) return previous or list(self.items) end
player.inventory.getAllTagEvalRecurse = function() end
ItemTag = {CAR_BATTERY = 'battery'}
charger.getBattery = function() end
ctx = menu(); ISWorldObjectContextMenu.handleCarBatteryCharger(false, ctx, {}, player, player.inventory)
sub = menus[ctx.options[1].subOption]
local connectMenu = menus[sub.options[1].subOption]
local connect = connectMenu.options[1]
connect.onSelect(connect.target, connect.param1, connect.param2, connect.param3, connect.param4)
command = q.queue[2]; player.inventory.items = {replacement}; expand(command)
assert(q.queue[4].Type == 'ISConnectCarBatteryToChargerAction' and q.queue[4].mode == replacement)
reset(); player.inventory.items = {original}
connect.onSelect(connect.target, connect.param1, connect.param2, connect.param3, connect.param4)
command = q.queue[2]; player.inventory.items = {}; tail = action('Tail'); ISTimedActionQueue.add(tail)
expand(command); assert(#q.queue == 2 and q.queue[2] == tail)

-- Every queued stove route uses the captured desired state and the authoritative shared action.
for _, initial in ipairs({false, true}) do
    reset(); local stove = object(); stove.activated = initial
    ISWorldObjectContextMenu.onToggleStove(nil, stove, 0)
    command = q.queue[2]
    assert(command.toolkitQueuePriority == 'urgent' and command.toolkitQueueOperation.toolkitPriority == 'urgent')
    assert(command.args[1].desired == not initial)
    assert(command.toolkitApplianceLabel == (initial and 'UI_PZSurvivorToolkit_queue_action_stove_off' or 'UI_PZSurvivorToolkit_queue_action_stove_on'))
    stove.activated = not initial
    expand(command)
    assert(q.queue[3].Type == 'PZSurvivorToolkitSetStoveState' and q.queue[3].desired == not initial)
end
reset(); local unavailable = object()
ISWorldObjectContextMenu.onToggleStove(nil, unavailable, 0)
local tail = action('Tail'); ISTimedActionQueue.add(tail); unavailable.unpowered = true
expand(q.queue[2]); assert(#q.queue == 2 and q.queue[2] == tail, 'power loss skips desired-on without losing unrelated work')
if cookPath then
    reset(); local stove = object(); local cooker = {getParent = function() return stove end}
    local panel = {player = player, CookerPanel = {selectedCooker = cooker, isPowered = true}}
    PJCK_CookerPicker.onStoveButtonClick(panel)
    command = q.queue[2]; assert(operations.isCommand(command) and command.toolkitQueuePriority == 'urgent' and player.stopped == 0)
    panel.CookerPanel.selectedCooker = {getParent = object}
    expand(command); assert(q.queue[3].object == stove and q.queue[3].Type == 'PZSurvivorToolkitSetStoveState')
    reset(); paused = true; PJCK_CookerPicker.onStoveButtonClick(panel); assert(#q.queue == 1); paused = false
else print('Project Cook callback source check SKIP (provide ProjectCookPickerSourcePath).') end
enabled = false; reset(); ISWorldObjectContextMenu.onToggleStove(nil, object(), 0)
assert(player.stopped == 1 and q.queue[#q.queue].Type == 'ISToggleStoveAction', 'disabled setting preserves original callback')
print('Device dispatch native callbacks: generator, charger, BBQ, deferred target/binding checks and stove intent passed.')
