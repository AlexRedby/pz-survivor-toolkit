-- Exact food selection and native eating chains; Java animation/network state is represented explicitly.
require = function(name)
    if name == "PZSurvivorToolkit/ActionQueueWeights" then
        return assert(loadfile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/" .. name .. ".lua"))()
    end
    if name == "PZSurvivorToolkit/InventoryMembership" then
        return assert(loadfile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/shared/" .. name .. ".lua"))()
    end
    if name == "PZSurvivorToolkit/ActionQueueMembership" then
        return assert(loadfile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/" .. name .. ".lua"))()
    end
    if name == 'PZSurvivorToolkit/InventoryClasses' then
        return assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/InventoryClasses.lua'))()
    end
end
local fill, enabled, fullness, dead = nil, true, 0, false
local onGameStart, onTick, serverCommands = {}, {}, {}
local function derive(self, name)
    local class = {Type = name, derive = derive}; class.__index = class
    return setmetatable(class, {__index = self})
end
ISBaseObject = {derive = derive}
PZSurvivorToolkit = {Settings = {actionQueue = function() return enabled end}}
Events = {OnTick = {Add = function(fn) onTick[#onTick + 1] = fn end}, OnGameStart = {Add = function(fn) onGameStart[#onGameStart + 1] = fn end},
    OnFillInventoryObjectContextMenu = {Add = function(fn) fill = fn end},
    OnServerCommand = {Add = function(fn) serverCommands[#serverCommands + 1] = fn end}}
instanceof = function(value, name)
    return type(value) == 'table' and (value.class == name or name == 'InventoryItem' and value.class == 'Food')
end
getText = function(key, count) return key .. (count and '(' .. tostring(count) .. ')' or '') end
getTexture = function(path) return path end
isClient, isServer = function() return false end, function() return false end
MoodleType, ItemTag = {FOOD_EATEN = 'full'}, {SMOKABLE = 'smoke', SPOON = 'spoon', FORK = 'fork'}
ItemBodyLocation = setmetatable({}, {__index = function(_, name) return name end})
getPlayerHotbar, sendEquip, triggerEvent = function() end, function() end, function() end
isForceDropHeavyItem = function() return false end
table.wipe = function(t) for key in pairs(t) do t[key] = nil end end
DebugType = {Action = {warn = function() end}}
ISLogSystem = {logAction = function() end}
for _, name in ipairs({'ClimbThroughWindowState','ClimbOverFenceState','ClimbOverWallState','ClimbSheetRopeState',
    'ClimbDownSheetRopeState','CloseWindowState','OpenWindowState'}) do _G[name] = {instance = function() return {} end} end
local function project(name)
    return assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/' .. name .. '.lua'))()
end
local function read(path)
    if NativeReadText then return NativeReadText(path):gsub('\r', '') end
    local file = assert(io.open(path)); local source = file:read('*a'); file:close(); return source:gsub('\r', '')
end
local function native(path) assert(loadstring((read(NativeActionRoot .. '/' .. path):gsub('(%d+%.%d+)f', '%1'))))() end
if NativeActionRoot then
    native('shared/TimedActions/ISBaseTimedAction.lua')
    native('client/TimedActions/ISTimedActionQueue.lua')
    native('client/TimedActions/ISQueueActionsAction.lua')
    native('shared/TimedActions/ISEatFoodAction.lua')
    native('shared/TimedActions/ISWearClothing.lua')
    native('shared/TimedActions/ISUnequipAction.lua')
else
    ISBaseTimedAction = ISBaseObject:derive('ISBaseTimedAction')
    function ISBaseTimedAction:new(character) return setmetatable({character = character}, self) end
    function ISBaseTimedAction:isValidStart() return true end
    function ISBaseTimedAction:isValid() return true end
    function ISBaseTimedAction:forceComplete() self.action:forceComplete() end
    function ISBaseTimedAction:forceStop() self.action:forceStop() end
    function ISBaseTimedAction:forceCancel() end
    function ISBaseTimedAction:beginAddingActions() self._isAddingActions, self._numAddedActions = true, 0 end
    function ISBaseTimedAction:endAddingActions() self._isAddingActions, self._numAddedActions = nil, nil end
    function ISBaseTimedAction:perform() ISTimedActionQueue.getTimedActionQueue(self.character):onCompleted(self) end
    function ISBaseTimedAction:stop() ISTimedActionQueue.getTimedActionQueue(self.character):resetQueue() end
    ISTimedActionQueue = {queues = {}}
    function ISTimedActionQueue.getTimedActionQueue(player)
        if not ISTimedActionQueue.queues[player] then ISTimedActionQueue.queues[player] = setmetatable({character = player, queue = {}}, {__index = ISTimedActionQueue}) end
        return ISTimedActionQueue.queues[player]
    end
    function ISTimedActionQueue:indexOf(action) for i, candidate in ipairs(self.queue) do if candidate == action then return i end end return -1 end
    function ISTimedActionQueue:isCurrentActionAddingOtherActions() return self.current and self.current._isAddingActions end
    function ISTimedActionQueue:addToQueue(action)
        self.queue[#self.queue + 1] = action
        if #self.queue == 1 then self.current = action; action:begin() end
    end
    function ISTimedActionQueue.add(action)
        local q = ISTimedActionQueue.getTimedActionQueue(action.character)
        if q:isCurrentActionAddingOtherActions() then
            table.insert(q.queue, 2 + q.current._numAddedActions, action); q.current._numAddedActions = q.current._numAddedActions + 1
        else q:addToQueue(action) end
        return q
    end
    function ISTimedActionQueue.addAfter(previous, action)
        local q = ISTimedActionQueue.getTimedActionQueue(action.character); local index = q:indexOf(previous)
        if index > 0 then table.insert(q.queue, index + 1, action); return q, action end
    end
    function ISTimedActionQueue:onCompleted(action)
        local index = self:indexOf(action); if index > 0 then table.remove(self.queue, index) end
        self.current = self.queue[1]; if self.current then self.current:begin() end
    end
    function ISTimedActionQueue:resetQueue() self.queue, self.current = {}, nil end
    ISTimedActionQueue.clearQueue = ISTimedActionQueue.resetQueue
    ISQueueActionsAction = ISBaseTimedAction:derive('ISQueueActionsAction')
    function ISQueueActionsAction:new(player, callback, snapshot)
        return setmetatable({character = player, addActionsFunction = callback, args = {snapshot}}, self)
    end
    ISEatFoodAction = ISBaseTimedAction:derive('ISEatFoodAction')
    function ISEatFoodAction:new(player, item, percentage)
        return setmetatable({character = player, item = item, percentage = percentage}, self)
    end
    function ISEatFoodAction:complete() self.character:Eat(self.item, self.percentage); return true end
end
-- Native begin allocates a Java action; dispatch remains under test control.
function ISBaseTimedAction:begin()
    self.action = {forceComplete = function() end, forceStop = function() end, isStarted = function() return true end,
        finished = function() return false end, isForceComplete = function() return false end, setOverrideHandModels = function() end, setOverrideHandModelsObject = function() end}
end
ISInventoryTransferAction = ISBaseTimedAction:derive('ISInventoryTransferAction')
ISInventoryTransferAction.canMergeAction = function() return false end
ISInventoryPage, ISContextMenu, ISButton, ISInventoryPane, ISInventoryPaneContextMenu = {}, {}, {}, {}, {}
local function list(values)
    return {size = function() return #values end, get = function(_, i) return values[i + 1] end,
        isEmpty = function() return #values == 0 end, add = function(_, value) values[#values + 1] = value end,
        set = function(_, index, value) values[index + 1] = value end,
        contains = function(_, value) for _, candidate in ipairs(values) do if candidate == value then return true end end return false end}
end
local function container()
    return {items = {}, getItems = function(self)
            local values = {}; for _, item in pairs(self.items) do values[#values + 1] = item end
            return list(values)
        end, contains = function(self, item) return self.items[item:getID()] == item end,
        containsID = function(self, id) return self.items[id] ~= nil end,
        getItemById = function(self, id) return self.items[id] end,
        getFirstTagEvalRecurse = function() end, getFirstTypeEvalRecurse = function() end}
end
local inventory, bag, remote = container(), container(), container()
local available = {inventory, bag}
local eaten, calls, portions = {}, {}, {}
local mask
local player = {getInventory = function() return inventory end, getPlayerNum = function() return 0 end,
    isDead = function() return dead end, isAsleep = function() return false end,
    getMoodles = function() return {getMoodleLevel = function() return fullness end} end,
    isEquippedClothing = function(_, item) return item == mask end, getPrimaryHandItem = function() end, getSecondaryHandItem = function() end,
    removeWornItem = function(_, item) if mask == item then mask = nil end end,
    setWornItem = function(_, _, item) mask = item end,
    getWornItem = function() return mask end,
    getHumanVisual = function() return {getHairModel = function() return {contains = function() return false end} end} end,
    isTimedActionInstant = function() return false end, getVehicle = function() end,
    getEmitter = function() return {isPlaying = function() return false end} end, setIsFarming = function() end,
    Eat = function(_, item, percentage)
        eaten[#eaten + 1], portions[#portions + 1] = item, percentage
        item.hunger = math.min(0, item.hunger - item.baseHunger * percentage)
        if item.hunger == 0 then item.container.items[item.id] = nil end
    end}
getSpecificPlayer = function(index) assert(index == 0); return player end
ISInventoryPaneContextMenu.getContainers = function() return list(available) end
ISInventoryPaneContextMenu.addToolTip = function() return {} end
ISInventoryPaneContextMenu.hasOpenFlame = function() return false end
local nextID = 0
local function food(options)
    nextID = nextID + 1
    local item = {class = 'Food', id = nextID, container = inventory, hunger = -.01, baseHunger = -.01, options = options or {}}
    function item:getID() return self.id end
    function item:getContainer() return self.container end
    function item:getCategory() return self.options.category or 'Food' end
    function item:getHungChange() return self.hunger end
    item.getHungerChange = item.getHungChange
    function item:getBaseHunger() return self.baseHunger end
    function item:getScriptItem() return {isCantEat = function() return self.options.cantEat end, getOpeningRecipe = function() return self.options.opening end} end
    function item:getOpeningRecipe() return self.options.opening end
    function item:getCustomMenuOption() return self.options.custom end
    function item:getRequireInHandOrInventory() return self.options.required end
    function item:isFavorite() return self.options.favorite end
    function item:getFullType() return self.options.fullType or 'Base.Herb' end
    function item:getDisplayName() return 'Herb' end
    function item:getTex() return 'herb-icon' end
    function item:getModData() self.modData = self.modData or {}; return self.modData end
    function item:hasTag() return false end
    function item:getEatType() return '' end
    function item:getEatTime() return 0 end
    function item:getCustomEatSound() return '' end
    function item:setJobDelta() end
    function item:setJobType() end
    function item:getClothingItem() return {} end
    function item:getBodyLocation() return ItemBodyLocation.MASK end
    function item:canBeEquipped() return '' end
    function item:isBroken() return self.options.broken or false end
    function item:IsClothing() return self:getCategory() == 'Clothing' end
    function item:IsInventoryContainer() return false end
    function item:getIsCraftingConsumed() return false end
    item.container = item.options.container or inventory; item.container.items[item.id] = item
    return item
end
local function action(kind, item)
    local result = ISBaseTimedAction:new(player); result.Type, result.item = kind, item
    if kind == 'ISInventoryTransferAction' then setmetatable(result, ISInventoryTransferAction) end
    function result:setOnComplete(callback) self.onCompleteFunc = callback end
    return result
end
ISInventoryPaneContextMenu.transferIfNeeded = function(_, item)
    if item.container ~= inventory then
        local transfer = action('ISInventoryTransferAction', item); transfer.srcContainer, transfer.destContainer = item.container, inventory
        ISTimedActionQueue.add(transfer)
    end
end
ISInventoryPaneContextMenu.getEatingMask = function(_, remove)
    if mask and remove then ISTimedActionQueue.add(NativeActionRoot and ISUnequipAction:new(player, mask, 50) or action('ISUnequipAction', mask)) end
    return mask
end
if not NativeActionRoot then ISWearClothing = {new = function(_, _, item) return action('ISWearClothing', item) end} end
ISCraftingUI = {ReturnItemToOriginalContainer = function(_, item)
    if item.container ~= inventory then
        local transfer = action('ISInventoryTransferAction', item); transfer.srcContainer, transfer.destContainer = inventory, item.container
        transfer.allowMissingItems = true; ISTimedActionQueue.add(transfer)
    end
end}
local nativeEatItem
if NativeActionRoot then
    local source = read(NativeActionRoot .. '/client/ISUI/ISInventoryPaneContextMenu.lua')
    assert(loadstring(assert(source:match('(ISInventoryPaneContextMenu%.eatItem = function.-\nend)'))))()
    nativeEatItem = ISInventoryPaneContextMenu.eatItem
else
    nativeEatItem = function(item, percentage, index)
        local p = getSpecificPlayer(index)
        ISInventoryPaneContextMenu.transferIfNeeded(p, item)
        local worn = ISInventoryPaneContextMenu.getEatingMask(p, true)
        ISTimedActionQueue.add(ISEatFoodAction:new(p, item, percentage))
        if worn then ISTimedActionQueue.add(ISWearClothing:new(p, worn, 50)) end
        ISCraftingUI.ReturnItemToOriginalContainer(p, item)
    end
end
ISInventoryPaneContextMenu.eatItem = function(item, percentage, index, ...)
    calls[#calls + 1] = item; return nativeEatItem(item, percentage, index, ...)
end
local nativeCalls = 0
local originalEat = function() nativeCalls = nativeCalls + 1 end
ISInventoryPaneContextMenu.onEatItems = originalEat
project('BulkActions')
local Operations, Batch = project('ActionQueueOperations'), project('ActionQueueBatch')
local Packaged
if NativeActionRoot then
    local nativeOpening = function() end
    RecipeCodeOnCreate = {openAndEat = nativeOpening}
    getScriptManager = function() return {getCraftRecipe = function() end} end
    local className, stringify = getClassSimpleName, tostring
    -- Only this fixture stand-in represents the Java callback during module loading.
    getClassSimpleName = function(value)
        if value == nativeOpening then return 'LuaJavaInvoker' end
        if className then return className(value) end
    end
    tostring = function(value) return value == nativeOpening and 'openAndEat' or stringify(value) end
    Packaged = assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/PackagedFood.lua'))()
    getClassSimpleName, tostring = className, stringify
end
local Bulk = project('BulkFood')
local q = ISTimedActionQueue.getTimedActionQueue(player)
local function reset() q.queue, q.current, eaten, calls, portions, fullness, mask = {}, nil, {}, {}, {}, 0, nil end
local function executeCommand(command)
    assert(Bulk.isCommand(command)); command:start(); q:onCompleted(command)
end
local function finish()
    local current = assert(q.current)
    if Bulk.isCommand(current) then executeCommand(current)
    else
        if current.Type == 'ISInventoryTransferAction' then
            if current.srcContainer:contains(current.item) then
                current.srcContainer.items[current.item.id] = nil; current.destContainer.items[current.item.id] = current.item
                current.item.container = current.destContainer
            end
        elseif current.Type == 'ISEatFoodAction' then current:complete(); Batch.completed(current)
        elseif NativeActionRoot and (current.Type == 'ISUnequipAction' or current.Type == 'ISWearClothing') then current:complete() end
        q:onCompleted(current)
    end
end
-- Realistic large selections must enumerate each source once, rather than call
-- the native recursive ID search for every selected food.
do
    for _, count in ipairs({32, 128, 512}) do
        local source, selected, reads, searches, snapshots = container(), {}, 0, 0, 0
        local beforeAvailable = available
        available = {source}
        for i = 1, count do selected[i] = food({container = source}) end
        source.getItems = function()
            snapshots = snapshots + 1
            local values = {}; for _, item in pairs(source.items) do values[#values + 1] = item end
            return {size = function() return #values end, get = function(_, i) reads = reads + 1; return values[i + 1] end}
        end
        source.getItemById = function(_, id)
            searches = searches + 1
            for _, item in pairs(source.items) do if item:getID() == id then return item end end
        end
        assert(#Bulk.entries(player, {{items = selected}}) == count)
        assert(searches == 0 and snapshots == 1 and reads == count,
            'food selection must make one raw source pass, not one recursive ID search per item')
        source.items[selected[1].id] = nil
        assert(#Bulk.entries(player, selected) == count - 1, 'the next enumeration must see removal')
        local replacement = food({container = source})
        source.items[replacement.id] = nil; replacement.id = selected[1].id; source.items[replacement.id] = replacement
        assert(Bulk.entries(player, {selected[1]})[1] == selected[1],
            'selection admission retains native ID semantics for a replicated replacement')
        available = beforeAvailable
    end
end
local a, b, unselected = food(), food({container = bag}), food()
local rows = {{items = {a, a, b}}, a}
local selected = Bulk.entries(player, rows)
assert(#selected == 2 and selected[1] == a and selected[2] == b, 'exact selected stack expands once and excludes unselected food')
for _, options in ipairs({{cantEat = true}, {opening = 'OpenCan'}, {custom = 'Smoke'}, {custom = 'Drink'},
    {required = list({'Lighter'})}, {category = 'Literature'}, {container = remote}, {favorite = true}}) do
    assert(#Bulk.entries(player, {food(options)}) == 0, 'special, protected and unavailable selections must not enter batch')
end
local zero = food(); zero.hunger = 0; assert(#Bulk.entries(player, {zero}) == 0)
assert(Bulk.queue(player, selected) == 2 and #q.queue == 2 and #calls == 0, 'batch queues exact deferred commands, not immediate consumption')
local first, second = q.queue[1], q.queue[2]
assert(first.toolkitQueueOperation == second.toolkitQueueOperation)
assert(Bulk.isCommand(first) and Bulk.isCommand(second) and #Bulk.entries(player, rows) == 0, 'pending commands reserve exact selected IDs')
local callback = first.addActionsFunction; first.addActionsFunction = function() end
assert(not Bulk.isCommand(first), 'replacing an owned command callback revokes ownership')
first.addActionsFunction = callback
assert(Batch.progress(q, first).total == 2, 'one operation counts foods, not preparation steps')
local tail = action('Unrelated'); ISTimedActionQueue.add(tail)
mask = food({category = 'Clothing'})
executeCommand(first)
local eat
for _, entry in ipairs(q.queue) do if entry.Type == 'ISEatFoodAction' then eat = entry end end
assert(eat and Bulk.isEat(eat) and eat.item == a and #calls == 1 and calls[1] == a)
assert(not Bulk.isEat(ISEatFoodAction:new(player, a, 1)), 'foreign native eating action cannot claim selected-food ownership')
eat.percentage = .5; assert(not Bulk.isEat(eat), 'a changed portion cannot retain full-food ownership'); eat.percentage = 1
assert(q.queue[1].Type == 'ISUnequipAction' and q.queue[3].Type == 'ISWearClothing', 'native eatItem mask preparation and restoration stay in group')
for i = 1, 3 do assert(q.queue[i].toolkitQueueOperation == first.toolkitQueueOperation) end
while q.current ~= second do finish() end
assert(Batch.progress(q, second).completed == 1)
executeCommand(second)
assert(q.queue[1].Type == 'ISInventoryTransferAction' and q.queue[1].item == b, 'native eating preserves source-container pickup')
while q.current ~= tail do finish() end
assert(#eaten == 2 and eaten[1] == a and eaten[2] == b and inventory:contains(unselected) and #q.queue == 1)
assert(#calls == 2 and Batch.progress(q, first).total == 2 and Batch.progress(q, first).completed == 2)
reset()
a, b = food(), food()
do
    local actions = PZSurvivorToolkit.BulkActions
    local original, preparations, laterChecks = actions.selectedItems, 0, 0
    local laterScript = b.getScriptItem
    actions.selectedItems = function(...) preparations = preparations + 1; return original(...) end
    b.getScriptItem = function(...) laterChecks = laterChecks + 1; return laterScript(...) end
    assert(Bulk.queueOne({{items = {a, a, b}}}, 1, 0, nil, 100) == 1)
    actions.selectedItems, b.getScriptItem = original, laterScript
    assert(preparations == 1, 'a single-food click must prepare its selection only once')
    assert(laterChecks == 0, 'a one-food click needs no eligibility checks after its first eligible item')
end
assert(Bulk.queueOne({{items = {a, a, b}}}, 1, 0, nil, 100) == 1)
assert(#q.queue == 2 and #Bulk.entries(player, {a, b}) == 0, 'repeat All clicks reserve successive foods without cancelling earlier commands')
assert(Bulk.queueOne({a, b}, 1, 0, nil, 100) == 0 and #q.queue == 2, 'exhausted selection never substitutes an unselected item')
reset(); a, b = food(), food()
a.hunger, a.baseHunger, b.hunger, b.baseHunger = -.2, -.2, -.2, -.2
assert(Bulk.queueOne({a, b}, .5, 0, nil, 50) == 1 and Bulk.queueOne({a, b}, .25, 0, nil, 25) == 1)
assert(Bulk.queue(player, {a, b}, 0) == 0 and Bulk.queue(player, {a, b}, 2) == 0)
while q.current do finish() end
assert(#eaten == 2 and eaten[1] == a and eaten[2] == b and portions[1] == .5 and portions[2] == .25
    and math.abs(a.hunger + .1) < .0001 and math.abs(b.hunger + .15) < .0001,
    'native half and quarter use distinct selected IDs, preserve exact portions and retain leftovers')
assert(Bulk.queueOne({a}, .5, 0, nil, 50) == 1, 'a completed partial portion releases its surviving food for a later request')
while q.current do finish() end
assert(not inventory:contains(a) and inventory:contains(b) and #eaten == 3, 'a later portion consumes only the existing remainder')
reset(); a = food(); assert(Bulk.queue(player, {a}) == 1)
local ownedCommand = q.current
assert(onTick[#onTick] == Bulk.prune, 'ownership pruning must run independently of settings and the panel')
Bulk.prune(); assert(Bulk.isCommand(ownedCommand), 'queued command retains its private entry during pruning')
do
    local visits = assert(loadfile(ProjectRoot .. '/tests/support/queue_registry_visits.lua'))()
    local original = q.queue
    q.queue = {ownedCommand}
    for i = 2, 4097 do q.queue[i] = {} end
    assert(visits(q.queue, Bulk.prune) == 1 and Bulk.isCommand(ownedCommand),
        'one retained food command must not inspect 4096 unrelated queued actions every tick')
    q.queue = original
end
executeCommand(ownedCommand)
local ownedMeal = q.current
Bulk.prune()
assert(not Bulk.isCommand(ownedCommand) and Bulk.isEat(ownedMeal), 'finished command is released without revoking its queued native meal')
finish(); Bulk.prune(); assert(not Bulk.isEat(ownedMeal), 'finished native meal is released on the next tick')
reset(); a = food(); Bulk.queue(player, {a}); ownedCommand = q.current
local otherPlayer = {}; ISTimedActionQueue.queues[otherPlayer] = {queue = {ownedCommand}}
q.queue = {}; Bulk.prune()
assert(Bulk.isCommand(ownedCommand), 'pruning must preserve actions present in any registered player queue')
ISTimedActionQueue.queues[otherPlayer] = nil
enabled = false; Bulk.prune(); enabled = true
assert(not Bulk.isCommand(ownedCommand), 'disabled queue UI does not retain absent command ownership')
reset()
a, b = food(), food(); Bulk.queue(player, {a, b}); tail = action('Unrelated'); ISTimedActionQueue.add(tail)
local progressAction = q.queue[1]; inventory.items[a.id] = nil; fullness = 3
executeCommand(q.current); executeCommand(q.current)
assert(q.current == tail and #calls == 0 and #q.queue == 1 and Batch.progress(q, progressAction).total == 0,
    'missing food and native satiety skip batch without stopping unrelated tail or counting consumption')
local function menu()
    local result = {options = {}}
    function result:addOption(name, target, callback, ...)
        local option = {name = name, target = target, onSelect = callback}
        for i = 1, select('#', ...) do option['param' .. i] = select(i, ...) end
        self.options[#self.options + 1] = option; return option
    end
    function result:getNew() return menu() end
    function result:getSubMenu(child) return child end
    function result:addSubMenu(option, child) option.subOption = child end
    return result
end
reset(); a, b = food(), food()
local context, sub = menu(), menu(); local parent = context:addOption(getText('ContextMenu_Eat')); context:addSubMenu(parent, sub)
local all = sub:addOption(getText('ContextMenu_Eat_All'), {a, b}, originalEat, 1, 0, nil, 100)
local half = sub:addOption(getText('ContextMenu_Eat_Half'), {a, b}, originalEat, .5, 0, nil, 50)
local quarter = sub:addOption(getText('ContextMenu_Eat_Quarter'), {a, b}, originalEat, .25, 0, nil, 25)
local smart = function() end
local smartOption = sub:addOption('Smart target', {a, b}, smart, 1, 0); smartOption.ES_EatSmart = true
do
    local actions = PZSurvivorToolkit.BulkActions
    local original, preparations = actions.selectedItems, 0
    actions.selectedItems = function(...) preparations = preparations + 1; return original(...) end
    fill(0, context, {a, b})
    actions.selectedItems = original
    assert(preparations == 1, 'one food menu must normalize selected rows once')
end
fill(0, context, {a, b})
assert(ISInventoryPaneContextMenu.onEatItems == originalEat and half.onSelect == Bulk.queueOne and smartOption.onSelect == smart,
    'native portions select unreserved items while public callback and EatSmart retain their contracts')
assert(all.onSelect == Bulk.queueOne and all.param1 == 1 and all.param2 == 0, 'only native All option chooses an unreserved exact item')
local selectedOptions = 0
for _, option in ipairs(sub.options) do if option.onSelect == Bulk.queue then selectedOptions = selectedOptions + 1 end end
assert(quarter.onSelect == Bulk.queueOne and selectedOptions == 3, 'repeated fill appends one batch command per visible native portion')
local special = food({opening = 'OpenCan'})
local specialMenu, specialSub = menu(), menu()
local specialParent = specialMenu:addOption(getText('ContextMenu_OpenAndEat')); specialMenu:addSubMenu(specialParent, specialSub)
local specialAll = specialSub:addOption(getText('ContextMenu_Eat_All'), {special, a}, originalEat, 1, 0, nil, 100)
fill(0, specialMenu, {special, a})
assert(specialAll.onSelect == originalEat and #specialSub.options == 1,
    'special first-item eating cannot silently redirect to a different selected ordinary food')
all.onSelect(all.target, all.param1, all.param2, all.param3, all.param4)
all.onSelect(all.target, all.param1, all.param2, all.param3, all.param4)
local reservedMenu, reservedSub = menu(), menu()
local reservedParent = reservedMenu:addOption(getText('ContextMenu_Eat')); reservedMenu:addSubMenu(reservedParent, reservedSub)
local reservedAll = reservedSub:addOption(getText('ContextMenu_Eat_All'), {a, b}, originalEat, 1, 0, nil, 100)
fill(0, reservedMenu, {a, b})
assert(reservedAll.onSelect == Bulk.queueOne and reservedAll.notAvailable,
    'an entirely reserved stack cannot fall through to native duplicate eating')
reset()
enabled = false
Bulk.queueOne({a, b}, 1, 0, nil, 100)
assert(nativeCalls == 1 and #q.queue == 0, 'disabled queue feature delegates to native single-food callback')
enabled = true
reset(); a = food()
Bulk.queue(player, {a})
local replacement = food(); inventory.items[replacement.id] = nil; replacement.id = a.id; inventory.items[a.id] = replacement
executeCommand(q.current)
assert(calls[1] == replacement and Bulk.isEat(q.current), 'server replacement of the same ID resolves before native dispatch')
if NativeActionRoot then
    -- Use the real policy/controller to verify cancellation owns the batch boundary.
    native('shared/TimedActions/ISReadABook.lua')
    player.isPlayerMoving, player.pressedMovement = function() return false end, function() return false end
    local Definitions = project('ActionQueueDefinitions'); Definitions.taskTitle = function() return 'Food' end
    project('ActionQueueLabels')
    local Policy = project('ActionQueuePolicy'); Policy.installContracts()
    for _, callback in ipairs(onGameStart) do callback() end
    project('ActionQueueLifecycle')
    project('ActionQueueAcknowledgements')
    local Controller = project('ActionQueue')
    local function book()
        local value = ISBaseTimedAction.new(ISReadABook, player); value.item = unselected; return value
    end
    reset(); a, b = food(), food()
    local prefix = book(); ISTimedActionQueue.add(prefix)
    Bulk.queue(player, {a, b}); local pending = q.queue[2]; tail = book(); tail.item = food(); ISTimedActionQueue.add(tail)
    local description = Definitions.describe(pending)
    assert(description.title == 'ContextMenu_Eat' and description.target == 'Herb'
        and description.icon() == 'herb-icon' and description.role ~= 'preparation',
        'pending food displays the native Eat title, selected item and icon before expansion')
    assert(Controller.cancelOperation(q, pending), 'real policy permits cancellation of an entirely waiting owned food batch')
    assert(#q.queue == 2 and q.current == prefix and q.queue[2] == tail and #calls == 0)
    reset(); a, b = food(), food()
    Bulk.queue(player, {a, b}); executeCommand(q.current)
    local current = q.current; tail = book(); tail.item = food(); ISTimedActionQueue.add(tail)
    assert(current.Type == 'ISEatFoodAction' and Policy.inspect(current).interrupt == 'finish-step')
    assert(Controller.cancelOperation(q, current), 'real policy permits stopping after the current native food')
    assert(q.current == current and not q.toolkitCancel, 'cancellation must finish current native eating without partial replay')
    current:complete(); q:onCompleted(current)
    assert(#eaten == 1 and eaten[1] == a and #calls == 1 and q.current == tail and #q.queue == 1,
        'current food is consumed once, future meals are dropped, unrelated work survives')
    current.complete = function() end
    assert(not Policy.inspect(current), 'foreign food completion removes audited cancellation permission')

    for _, phase in ipairs({'removal', 'eating'}) do
        reset(); a, b = food(), food(); mask = food({category = 'Clothing'})
        local originalMask = mask
        Bulk.queue(player, {a, b}); local maskCommand, futureCommand = q.current, q.queue[2]
        executeCommand(maskCommand); Bulk.prune()
        local plannedMeal = q.queue[2]
        assert(not Bulk.isCommand(maskCommand), 'mask preparation does not keep a completed command in its registry')
        assert(Bulk.isMaskRemoval(q.current) and not Bulk.isMaskRemoval(ISUnequipAction:new(player, mask, 50)),
            'only the privately recorded food mask removal owns its exact native step')
        local removal = q.current
        local originalItem = removal.item
        removal.item = {getID = function() return originalItem:getID() end}
        assert(Bulk.isMaskRemoval(removal), 'native replacement proxy with the same mask ID retains ownership')
        removal.item = {getID = function() return originalItem:getID() + 1 end}
        assert(not Bulk.isMaskRemoval(removal), 'a different mask ID cannot borrow the private removal record')
        removal.item = originalItem; removal.character = {}
        assert(not Bulk.isMaskRemoval(removal), 'a different character cannot borrow the private removal record')
        removal.character = player
        if phase == 'eating' then
            finish(); Bulk.prune()
            assert(not Bulk.isMaskRemoval(removal) and Bulk.isEat(q.current), 'finished mask removal does not revoke its queued meal')
        end
        local active, restore = q.current
        for _, candidate in ipairs(q.queue) do if Bulk.isCleanup(candidate) then restore = candidate end end
        tail = book(); tail.item = food(); ISTimedActionQueue.add(tail)
        assert(restore and Policy.inspect(restore), 'only the native owned mask restoration gets a cleanup contract')
        local complete = restore.complete; restore.complete = function() end
        assert(not Controller.cancelOperation(q, active), 'changed mask effects cannot inherit group cancellation permission')
        restore.complete = complete
        assert(Controller.cancelOperation(q, active), 'mask removal and eating both permit finish-step group cancellation')
        finish()
        Bulk.prune()
        assert(not Bulk.isCommand(futureCommand) and not Bulk.isMaskRemoval(removal) and not Bulk.isEat(plannedMeal),
            'group cancellation releases removed commands, mask removal and meal ownership')
        assert(q.current == restore and #q.queue == 2 and q.queue[2] == tail and not mask and inventory:contains(b),
            'cancel drops future food and preserves the original native restoration before unrelated work')
        assert(Bulk.isCleanup(restore), 'retained cleanup survives pruning of its finished command and removal')
        assert(not Controller.cancelOperation(q, restore), 'retained mandatory mask cleanup cannot itself be dropped')
        finish()
        Bulk.prune(); assert(not Bulk.isCleanup(restore), 'completed mandatory restoration leaves no ownership record')
        assert(mask == originalMask and q.current == tail and #calls == 1
            and #eaten == (phase == 'eating' and 1 or 0), 'mask is restored once and only a started meal is consumed')
    end

    for _, reason in ipairs({'clear', 'death', 'missing-queue'}) do
        reset(); a = food(); mask = food({category = 'Clothing'})
        Bulk.queue(player, {a}); local command = q.current; executeCommand(command)
        local removal, meal, restore = q.current, q.queue[2], q.queue[3]
        assert(Bulk.isCommand(command) and Bulk.isMaskRemoval(removal) and Bulk.isEat(meal) and Bulk.isCleanup(restore))
        if reason == 'clear' then q:clearQueue()
        elseif reason == 'death' then dead = true; q.queue, q.current = {}, nil
        else ISTimedActionQueue.queues[player] = nil end
        Bulk.prune()
        assert(not Bulk.isCommand(command) and not Bulk.isMaskRemoval(removal) and not Bulk.isEat(meal) and not Bulk.isCleanup(restore),
            'absent actions must leave every ownership registry after '..reason)
        dead = false; ISTimedActionQueue.queues[player] = q
    end

    reset(); a = food(); mask = food({category = 'Clothing'})
    local lostMask = mask
    Bulk.queue(player, {a}); executeCommand(q.current); finish()
    tail = book(); tail.item = food(); ISTimedActionQueue.add(tail)
    assert(Controller.cancelOperation(q, q.current))
    inventory.items[lostMask.id] = nil
    finish()
    assert(q.current == tail and #eaten == 1 and not mask, 'missing mask is never recreated or allowed to clear the unrelated tail')

    reset(); a, b = food({container = bag}), food()
    Bulk.queue(player, {a, b}); executeCommand(q.current)
    tail = book(); tail.item = food(); ISTimedActionQueue.add(tail)
    local pickup, missingMeal = q.current, q.queue[2]
    assert(pickup.Type == 'ISInventoryTransferAction' and Bulk.isEat(missingMeal) and not missingMeal.action,
        'a deferred native meal remains unstarted behind its pickup')
    local batchProgress = Batch.progress(q, missingMeal)
    assert(batchProgress.total == 2)
    bag.items[a.id] = nil
    -- Native pickup treats an absent source item as dontAdd and finishes without transferring it.
    q:onCompleted(pickup)
    assert(q:indexOf(missingMeal) == -1 and q.current.Type == 'ISInventoryTransferAction'
        and q.current.allowMissingItems and Batch.progress(q, missingMeal).total == 1,
        'a disappearing pickup target skips its native meal while retaining return cleanup and the rest of the batch')
    while q.current ~= tail do finish() end
    assert(#eaten == 1 and eaten[1] == b and #q.queue == 1 and Batch.progress(q, missingMeal).completed == 1,
        'missing-after-dispatch neither eats a missing item nor clears later food and unrelated work')

    reset(); a, b = food(), food(); mask = food({category = 'Clothing'})
    Bulk.queue(player, {a, b}); executeCommand(q.current)
    tail = book(); tail.item = food(); ISTimedActionQueue.add(tail)
    local unequip, fullMeal, cleanup = q.current, q.queue[2], q.queue[3]
    assert(unequip.Type == 'ISUnequipAction' and Bulk.isEat(fullMeal) and not fullMeal.action)
    fullness = 3
    q:onCompleted(unequip)
    assert(q:indexOf(fullMeal) == -1 and q.current == cleanup and cleanup.Type == 'ISWearClothing',
        'satiety reached during mask preparation skips unstarted food and still restores the mask')
    while q.current ~= tail do finish() end
    assert(#eaten == 0 and #calls == 1 and #q.queue == 1 and Batch.progress(q, fullMeal).total == 0,
        'satiety during preparation preserves unrelated tail and prevents future food dispatch')

    reset(); a = food(); mask = food({category = 'Clothing'})
    Bulk.queue(player, {a}); executeCommand(q.current); q:onCompleted(q.current)
    local activeMeal = q.current; cleanup = q.queue[2]
    tail = book(); tail.item = food(); ISTimedActionQueue.add(tail)
    assert(Bulk.isEat(activeMeal) and activeMeal.action and cleanup.Type == 'ISWearClothing')
    inventory.items[a.id] = nil
    assert(not activeMeal:isValid() and Bulk.missing(activeMeal), 'only an audited owned active missing meal qualifies for a safe stop')
    local completion = activeMeal.complete; activeMeal.complete = function() end
    assert(not Bulk.missing(activeMeal), 'modified native completion cannot gain missing-meal stop permission')
    activeMeal.complete = completion
    activeMeal:stop()
    assert(q.toolkitCancelStopped and q.current == activeMeal and q:indexOf(cleanup) > 0 and q:indexOf(tail) > 0,
        'native active missing-food stop retains mask restoration and unrelated tail')
    -- Java removes the stopped action before the controller advances; no replay or manual Eat occurs.
    player.getCharacterActions = function() return {contains = function() return false end} end
    q:tick()
    assert(q.current == cleanup and #q.queue == 2 and q.queue[2] == tail and not q.toolkitCancel,
        'after Java stop acknowledgement the controller resumes native cleanup, not the missing meal')
    q:onCompleted(cleanup)
    assert(q.current == tail and #eaten == 0 and #calls == 1 and Batch.progress(q, activeMeal).total == 0,
        'active missing meal consumes nothing, is counted as discarded, and is never replayed')
end
reset(); Bulk.prune()
local registeredQueues = ISTimedActionQueue.queues
ISTimedActionQueue.queues = nil; Bulk.prune(); ISTimedActionQueue.queues = registeredQueues
if NativeActionRoot then
    -- Exercise native context opening order and action callbacks with real queue/policy modules.
    local clock, multiplayer = 1000, false
    getTimestampMs = function() return clock end
    isClient = function() return multiplayer end
    getPlayerByOnlineID = function(id) return id == 17 and player or nil end
    convertToPZNetTable = function(value) return value end
    log, showDebugInfoInChat = function() end, function() end
    CharacterTrait, ItemType, ResourceType = {ALL_THUMBS = 'thumbs'}, {CONTAINER = 'container'}, {Item = 'item'}
    ISPanelJoypad = {derive = derive}
    UIFont, getTextManager = {Small = 'small'}, function() return {getFontHeight = function() return 12 end} end
    player.hasTrait, player.isWearingAwkwardGloves = function() return false end, function() return false end
    ISInventoryPage.dirtyUI = function() end
    ArrayList = {new = function() return list({}) end}
    native('shared/TimedActions/ISFixAction.lua')
    native('shared/TimedActions/ISFixVehiclePartAction.lua')
    native('shared/TimedActions/ISCraftAction.lua')
    native('shared/Entity/TimedActions/ISHandcraftAction.lua')
    native('client/Entity/ISUI/CraftRecipe/ISWidgetHandCraftControl.lua')
    local contextSource = read(NativeActionRoot .. '/client/ISUI/ISInventoryPaneContextMenu.lua')
    for _, name in ipairs({'OnNewCraft', 'OnNewCraftComplete'}) do
        assert(loadstring(assert(contextSource:match('(ISInventoryPaneContextMenu%.' .. name .. ' = function.-\nend)'))))()
    end
    ISEntityUI = {}
    local entitySource = read(NativeActionRoot .. '/client/Entity/ISEntityUI.lua')
    assert(loadstring(assert(entitySource:match('(function ISEntityUI%.HandcraftStart%(%s.-\nend)'))))()
    local body = assert(read(NativeActionRoot .. '/../scripts/generated/recipes/recipes_cannedFood.txt')
        :match('craftRecipe%s+OpenCannedFood%s*(%b{})'))
    local openingRecipe = {class = 'CraftRecipe', body = 'craftRecipe OpenCannedFood' .. body}
    function openingRecipe:getName() return 'OpenCannedFood' end
    openingRecipe.getTranslationName = openingRecipe.getName
    function openingRecipe:getScriptObjectFullType() return 'Base.OpenCannedFood' end
    function openingRecipe:getLoadedScriptBodies() return list({'pz-vanilla', self.body}) end
    function openingRecipe:getScriptLines() return list({self.body}) end
    function openingRecipe:getTimedActionScript() end
    function openingRecipe:isCanWalk() return false end
    function openingRecipe:isCanBeDoneFromFloor() return false end
    function openingRecipe:isAnySurfaceCraft() return false end
    function openingRecipe:getTime() return 1 end
    local canInput, openerInput = {getResourceType = function() return ResourceType.Item end},
        {getResourceType = function() return ResourceType.Item end}
    function openingRecipe:getInputs() return list({openerInput, canInput}) end
    function openingRecipe:getIndexForIO(input) return input == openerInput and 0 or 1 end
    function openingRecipe:getIOForIndex(index) return index == 0 and openerInput or canInput end
    function openingRecipe:getOutputs()
        return list({{getItem = function() return {getFullName = function() return 'Base.OpenBeans' end} end}})
    end
    getScriptManager = function() return {getCraftRecipe = function(_, name)
        if name == 'OpenCannedFood' or name == 'Base.OpenCannedFood' then return openingRecipe end
    end} end
    local Craft = project('ActionQueueCraft')
    local Policy, Definitions, Controller = PZSurvivorToolkit.ActionQueuePolicy,
        PZSurvivorToolkit.ActionQueueDefinitions, PZSurvivorToolkit.ActionQueue
    Actions = {addOrDropItem = function(_, item) inventory.items[item.id] = item; item.container = inventory end}
    local opener
    local function safeScript(cantEat, opening)
        return {isCantEat = function() return cantEat end, getOpeningRecipe = function() return opening end,
            isItemType = function() return false end, getReplaceOnUse = function() end,
            getReplaceOnDeplete = function() end, getOnBreak = function() end}
    end
    local function canned()
        local item = food({cantEat = true, opening = 'OpenCannedFood', fullType = 'Base.TinnedBeans'})
        item.hunger, item.baseHunger = 0, 0 -- Native sealed cans define no HungerChange until opened.
        item.getScriptItem = function() return safeScript(true, 'OpenCannedFood') end
        return item
    end
    local function resultFood()
        local item = food({fullType = 'Base.OpenBeans'}); item.hunger, item.baseHunger = -.2, -.2
        item.getScriptItem = function() return safeScript(false) end
        return item
    end
    HandcraftLogic = {new = function(character)
        local logic = {class = 'HandcraftLogic', player = character}
        function logic:getPlayer() return self.player end
        function logic:findCraftSurface() end
        function logic:setIsoObject(value) self.surface = value end
        function logic:getIsoObject() return self.surface end
        function logic:getCraftBench() end
        function logic:setContainers(value) self.containers = value end
        function logic:getContainers() return self.containers end
        function logic:setRecipeFromContextClick(recipe, source) self.recipe, self.source = recipe, source end
        function logic:getRecipe() return self.recipe end
        function logic:setRecipe(recipe) self.recipe = recipe end
        function logic:setTargetVariableInputRatio() end
        function logic:setManualSelectInputs() end
        function logic:clearManualInputs() end
        function logic:setManualInputsFor(input, items) if input == canInput then self.source = items:get(0) end; return true end
        function logic:getModelHandOne() end
        function logic:getModelHandTwo() end
        function logic:canPerformCurrentRecipe() return true end
        function logic:isManualSelectInputs() return true end
        function logic:isUsingRecipeAtHandBenefit() return false end
        function logic:getManualInputsFor(input) return list({input == openerInput and opener or self.source}) end
        function logic:startCraftAction(value) self.action = value end
        function logic:stopCraftAction() self.stopped = true end
        function logic:getRecipeData()
            if not self.data then
                local data = {logic = self}
                function data:getAllInputItems() return list({opener, self.logic.source}) end
                function data:getAllPutBackInputItems() return list({opener}) end
                function data:getVariableInputRatio() return 1 end
                function data:getRecipe() return self.logic.recipe end
                function data:getEatPercentage() return 0 end
                function data:getAllConsumedItems() return list({self.logic.source}) end
                function data:getAllCreatedItems() return list({self.logic.output}) end
                function data:getFirstInputItemWithFlag() return self.logic.source end
                function data:luaCallOnCreate(p) RecipeCodeOnCreate.openAndEat(self, p) end
                function data:processDestroyAndUsedItems() inventory.items[self.logic.source.id] = nil end
                self.data = data
            end
            return self.data
        end
        function logic:performCurrentRecipe() self.output = resultFood(); return true end
        function logic:getCreatedOutputItems(items)
            -- Native receives a mutable Java ArrayList; expose the same append contract in this fixture.
            items:add(self.output)
        end
        return logic
    end}
    ArrayList.new = function() return list({}) end
    ISCraftingUI.ReturnItemsToOriginalContainer = function(_, items)
        for _, item in ipairs(items) do ISCraftingUI.ReturnItemToOriginalContainer(player, item) end
    end
    Policy.installContracts()
    local function prepare(percentage, withMask, leavePrepared)
        reset(); Bulk.prune(); clock, multiplayer = 1000, false
        opener = food({category = 'Tool', container = bag, fullType = 'Base.TinOpener'})
        opener.class, opener.getScriptItem = 'InventoryItem', function() return safeScript(false) end
        local source = canned()
        if withMask then mask = food({category = 'Clothing'}) end
        local originalMask = mask
        assert(Bulk.queue(player, {source}, percentage) == 1)
        local command = q.current
        executeCommand(command)
        local opening, wait, restore, returned
        for _, entry in ipairs(q.queue) do
            if entry.Type == 'ISHandcraftAction' then opening = entry
            elseif Bulk.isOpeningWait(entry) then wait = entry
            elseif Bulk.isCleanup(entry) then restore = entry
            elseif entry.Type == 'ISInventoryTransferAction' and entry.allowMissingItems then returned = entry end
        end
        assert(opening and wait, 'native OnNewCraft must bind its callback before packaged opening capture')
        assert(Bulk.isOpening(opening) and Craft.futureResources(opening).outputTypes['Base.OpenBeans'])
        assert(Policy.inspect(opening).knownInputs and not Policy.inspect(opening).unknownOutputs,
            'packaged craft exposes audited exact inputs and mapped future output to real policy')
        assert(Definitions.resolve(opening) == Definitions.resolve(wait)
            and Definitions.describe(opening).title == 'OpenCannedFood'
            and Definitions.describe(opening).target == source:getDisplayName()
            and Definitions.describe(opening).icon() == source:getTex()
            and Definitions.describe(opening).role == 'preparation'
            and Definitions.describe(wait).icon() == source:getTex()
            and Definitions.describe(wait).title == 'ContextMenu_Eat', 'native opening title retains selected-food target and icon')
        assert(q:indexOf(wait) == q:indexOf(opening) + 1 and (not restore or q:indexOf(wait) < q:indexOf(restore))
            and returned and q:indexOf(wait) < q:indexOf(returned), 'receipt wait precedes native mask restoration and tool returns')
        if not leavePrepared then while q.current ~= opening do finish() end end
        return source, command, opening, wait, restore, returned, originalMask
    end
    local function completeOpening(opening)
        if not opening.craftStarted then opening:start() end
        opening:perform(); opening:complete()
    end
    local function receipt(source, output, changes)
        local args = {sourceID = source.id, outputID = output.id, outputType = output:getFullType(),
            recipe = 'OpenCannedFood', onlineID = 17}
        for key, value in pairs(changes or {}) do args[key] = value end
        for _, callback in ipairs(serverCommands) do callback('PZSurvivorToolkitFood', 'Opened', args) end
    end
    local function finishWait(wait)
        assert(q.current == wait and wait:waitToStart(), 'first completion boundary must wait one native tick')
        assert(not wait:waitToStart(), 'confirmed output or rejection must release the readiness gate')
        wait:start(); q:onCompleted(wait)
    end
    for _, percentage in ipairs({1, .5, .25}) do
        local source, command, opening, wait, restore, returned, originalMask = prepare(percentage, true)
        local tail = action('Unrelated'); ISTimedActionQueue.add(tail)
        local before = Batch.progress(q, command)
        assert(before.total == 1 and before.completed == 0)
        completeOpening(opening)
        assert(q.current == wait and #eaten == 0 and Batch.progress(q, command).completed == 0,
            'opening a selected can does not count a completed meal')
        local output = assert(opening.logic.output)
        finishWait(wait)
        assert(Bulk.isEat(q.current) and q.current.item == output and q.current.percentage == percentage,
            'authoritative opening result binds the exact full, half or quarter native meal')
        assert(q:indexOf(restore) > 0 and q:indexOf(returned) > 0 and not inventory:contains(source))
        while q.current ~= tail do finish() end
        assert(#eaten == 1 and eaten[1] == output and portions[1] == percentage and mask == originalMask
            and bag:contains(opener) and Batch.progress(q, command).completed == 1 and Batch.progress(q, command).total == 1,
            'only native eating completes the can meal and restores its original mask')
    end
    for _, timing in ipairs({'before-completion', 'after-completion'}) do
        local source, command, opening, wait = prepare(.5)
        multiplayer = true
        local output, wrong = resultFood(), resultFood()
        inventory.items[output.id] = nil -- Receipt and created-item replication are separate MP deliveries.
        if timing == 'before-completion' then receipt(source, output) end
        completeOpening(opening)
        assert(wait:waitToStart() and wait:waitToStart(), 'receipt alone cannot release an unreplicated output')
        if timing == 'after-completion' then
            for _, changes in ipairs({{sourceID = -1}, {recipe = 'Other'}, {outputType = 'Base.Wrong'}, {onlineID = -1}}) do
                receipt(source, wrong, changes)
                assert(wait:waitToStart(), 'wrong server receipt cannot release an exact selected can')
            end
            receipt(source, output)
        end
        receipt(source, wrong) -- duplicate receipt must never redirect a captured output.
        assert(wait:waitToStart(), 'duplicate receipt cannot substitute an already replicated same-type neighbour')
        inventory.items[output.id] = output
        assert(not wait:waitToStart())
        wait:start(); q:onCompleted(wait)
        assert(Bulk.isEat(q.current) and q.current.item == output and q.current.percentage == .5)
        while q.current do finish() end
        assert(#eaten == 1 and eaten[1] == output and Batch.progress(q, command).completed == 1)
    end
    for _, reason in ipairs({'missing-output', 'timeout', 'generation', 'cancel', 'death', 'clear'}) do
        local source, command, opening, wait, restore, returned, originalMask = prepare(.25, true)
        local tail = action('Unrelated'); ISTimedActionQueue.add(tail)
        multiplayer = true
        local output = resultFood()
        if reason == 'generation' then Operations.invalidateQueue(q)
        elseif reason == 'cancel' then command.toolkitQueueOperation.toolkitCancelled = true
        elseif reason == 'death' then dead = true end
        completeOpening(opening)
        if reason == 'clear' then
            q:clearQueue(); Bulk.prune(); receipt(source, output)
            assert(not Bulk.isOpeningWait(wait) and #eaten == 0 and #q.queue == 0, 'cleared wait cannot accept a late receipt')
        else
            if reason ~= 'timeout' then receipt(source, output) end
            if reason == 'missing-output' then inventory.items[output.id] = nil end
            assert(wait:waitToStart())
            if reason == 'timeout' or reason == 'missing-output' then
                assert(wait:waitToStart(), 'MP wait remains ahead of cleanup until output or bounded timeout')
                clock = clock + 30001
            end
            assert(not wait:waitToStart())
            wait:start(); q:onCompleted(wait)
            dead = false
            while q.current ~= tail do finish() end
            assert(#eaten == 0 and mask == originalMask and q.current == tail and q:indexOf(returned) == -1,
                'rejected opening never consumes another food or loses mask cleanup and unrelated tail: ' .. reason)
            assert(Batch.progress(q, command).completed == 0)
        end
        dead = false; multiplayer = false
    end
    local source, command, opening, wait, restore, returned, originalMask = prepare(1, true, true)
    local tail = action('Unrelated'); ISTimedActionQueue.add(tail)
    inventory.items[source.id] = nil
    while q.current ~= wait do finish() end
    assert(q:indexOf(opening) == -1 and not opening.craftStarted and #eaten == 0,
        'a vanished manual can skips the unstarted opening after native pickup preparation')
    finishWait(wait)
    while q.current ~= tail do finish() end
    assert(mask == originalMask and #eaten == 0 and Batch.progress(q, command).total == 0,
        'missing sealed source preserves native returns, mask cleanup and unrelated tail')

    source, command, opening, wait = prepare(.5)
    multiplayer = true
    completeOpening(opening)
    local wrongOutput = food({fullType = 'Base.CannedCornOpen'})
    receipt(source, wrongOutput, {outputType = 'Base.OpenBeans'})
    assert(wait:waitToStart() and not wait:waitToStart())
    wait:start(); q:onCompleted(wait)
    while q.current do finish() end
    assert(#eaten == 0 and Batch.progress(q, command).total == 0,
        'an authoritative ID with unexpected replicated output type cannot become a meal')

    bag.isExistYet = function() return true end
    ISInventoryTransferUtil = {newInventoryTransferAction = function(p, item, src, dest)
        local transfer = action('ISInventoryTransferAction', item)
        transfer.srcContainer, transfer.destContainer = src, dest
        transfer.setAllowMissingItems = function(self, value) self.allowMissingItems = value end
        return transfer
    end}
    for _, phase in ipairs({'opening', 'receipt-wait'}) do
        source, command, opening, wait, restore, returned, originalMask = prepare(1, true)
        tail = ISBaseTimedAction.new(ISReadABook, player); tail.item = food(); ISTimedActionQueue.add(tail)
        if phase == 'opening' then opening:start()
        else multiplayer = true; completeOpening(opening) end
        local current = q.current
        assert(Controller.cancelOperation(q, current), 'real controller cancels the packaged operation during ' .. phase)
        if phase == 'opening' and q.toolkitCancel == opening then
            opening:stop()
            player.getCharacterActions = function() return {contains = function() return false end} end
            q:tick() -- Java acknowledges the native stop before queued cleanup resumes.
        elseif phase == 'opening' then completeOpening(opening)
        else current:start(); q:onCompleted(current) end
        local output = resultFood(); receipt(source, output)
        while q.current ~= tail do finish() end
        Bulk.prune()
        assert(#eaten == 0 and mask == originalMask and q:indexOf(wait) == -1
            and not Bulk.isOpeningWait(wait) and not q.toolkitGroupCancel and bag:contains(opener),
            'controller cancellation drops deferred meal, rejects late receipt and preserves native mask restoration')
    end
    local source, command, opening = prepare(1)
    local manual = opening.manualInputs[1]
    opening.manualInputs[1] = list({resultFood()})
    assert(not Bulk.isOpening(opening) and not Craft.futureResources(opening) and not Policy.inspect(opening).knownInputs
        and Policy.inspect(opening).unknownOutputs,
        'changed manual source IDs revoke packaged craft permissions')
    opening.manualInputs[1] = manual
    local completion = opening.onCompleteFunc
    opening.onCompleteFunc = function() end
    assert(not Bulk.isOpening(opening) and not Policy.inspect(opening), 'changed craft callback cannot inherit opening ownership')
    opening.onCompleteFunc = completion
    reset(); Bulk.prune()
    local verified, other = canned(), canned()
    local options = menu()
    local verifiedAll = options:addOption('Open and Eat', {verified, other}, originalEat, 1, 0, openingRecipe, 100)
    fill(0, options, {verified, other})
    assert(verifiedAll.onSelect == Bulk.queueOne and #options.options == 2, 'verified native opening keeps one-item choice and adds selected batch')
    local nativeBody = openingRecipe.body
    openingRecipe.body = nativeBody:gsub('time = 100', 'time = 101')
    local unsupported = menu()
    local fallback = unsupported:addOption('Open and Eat', {verified}, originalEat, 1, 0, openingRecipe, 100)
    fill(0, unsupported, {verified})
    assert(fallback.onSelect == originalEat and #unsupported.options == 1 and #Bulk.entries(player, {verified}) == 0,
        'modified native opening recipe keeps the native menu fallback')
    local before = nativeCalls
    Bulk.queueOne({verified}, 1, 0, openingRecipe, 100)
    assert(nativeCalls == before + 1 and #q.queue == 0, 'unsupported explicit opening delegates to native callback')
    openingRecipe.body = nativeBody
    reset(); Bulk.prune()
end
print('Bulk food: exact portions, masks/returns, cancellation, stale targets and menus passed'
    .. (NativeActionRoot and '; native authoritative canned-food lifecycle passed.' or '; packaged lifecycle requires native sources.'))
