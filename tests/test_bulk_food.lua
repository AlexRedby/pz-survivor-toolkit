-- Exact food selection and native eating chains; Java animation/network state is represented explicitly.
require = function() end
local fill, enabled, fullness, dead = nil, true, 0, false
local function derive(self, name)
    local class = {Type = name, derive = derive}; class.__index = class
    return setmetatable(class, {__index = self})
end
ISBaseObject = {derive = derive}
PZSurvivorToolkit = {Settings = {actionQueue = function() return enabled end}}
Events = {OnTick = {Add = function() end}, OnGameStart = {Add = function() end},
    OnFillInventoryObjectContextMenu = {Add = function(fn) fill = fn end}}
instanceof = function(value, name)
    return type(value) == 'table' and (value.class == name or name == 'InventoryItem' and value.class == 'Food')
end
getText = function(key, count) return key .. (count and '(' .. tostring(count) .. ')' or '') end
getTexture = function(path) return path end
isClient, isServer = function() return false end, function() return false end
MoodleType, ItemTag = {FOOD_EATEN = 'full'}, {SMOKABLE = 'smoke', SPOON = 'spoon', FORK = 'fork'}
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
        finished = function() return false end, isForceComplete = function() return false end}
end
ISInventoryTransferAction = ISBaseTimedAction:derive('ISInventoryTransferAction')
ISInventoryTransferAction.canMergeAction = function() return false end
ISInventoryPage, ISContextMenu, ISButton, ISInventoryPane, ISInventoryPaneContextMenu = {}, {}, {}, {}, {}
local function list(values)
    return {size = function() return #values end, get = function(_, i) return values[i + 1] end,
        isEmpty = function() return #values == 0 end,
        contains = function(_, value) for _, candidate in ipairs(values) do if candidate == value then return true end end return false end}
end
local function container()
    return {items = {}, contains = function(self, item) return self.items[item:getID()] == item end,
        containsID = function(self, id) return self.items[id] ~= nil end,
        getItemById = function(self, id) return self.items[id] end,
        getFirstTagEvalRecurse = function() end, getFirstTypeEvalRecurse = function() end}
end
local inventory, bag, remote = container(), container(), container()
local available = {inventory, bag}
local eaten, calls = {}, {}
local player = {getInventory = function() return inventory end, getPlayerNum = function() return 0 end,
    isDead = function() return dead end, isAsleep = function() return false end,
    getMoodles = function() return {getMoodleLevel = function() return fullness end} end,
    isEquippedClothing = function() return false end, getPrimaryHandItem = function() end, getSecondaryHandItem = function() end,
    isTimedActionInstant = function() return false end, getVehicle = function() end,
    getEmitter = function() return {isPlaying = function() return false end} end, setIsFarming = function() end,
    Eat = function(_, item, percentage) assert(percentage == 1); eaten[#eaten + 1] = item; item.container.items[item.id] = nil end}
getSpecificPlayer = function(index) assert(index == 0); return player end
ISInventoryPaneContextMenu.getContainers = function() return list(available) end
ISInventoryPaneContextMenu.addToolTip = function() return {} end
ISInventoryPaneContextMenu.hasOpenFlame = function() return false end
local nextID = 0
local function food(options)
    nextID = nextID + 1
    local item = {class = 'Food', id = nextID, container = inventory, hunger = -.01, options = options or {}}
    function item:getID() return self.id end
    function item:getContainer() return self.container end
    function item:getCategory() return self.options.category or 'Food' end
    function item:getHungChange() return self.hunger end
    item.getHungerChange, item.getBaseHunger = item.getHungChange, item.getHungChange
    function item:getScriptItem() return {isCantEat = function() return self.options.cantEat end, getOpeningRecipe = function() return self.options.opening end} end
    function item:getOpeningRecipe() return self.options.opening end
    function item:getCustomMenuOption() return self.options.custom end
    function item:getRequireInHandOrInventory() return self.options.required end
    function item:isFavorite() return self.options.favorite end
    function item:getFullType() return 'Base.Herb' end
    function item:getDisplayName() return 'Herb' end
    function item:getTex() return 'herb-icon' end
    function item:hasTag() return false end
    function item:getEatType() return '' end
    function item:getEatTime() return 0 end
    function item:getCustomEatSound() return '' end
    function item:setJobDelta() end
    item.container = item.options.container or inventory; item.container.items[item.id] = item
    return item
end
local function action(kind, item)
    local result = ISBaseTimedAction:new(player); result.Type, result.item = kind, item
    function result:setOnComplete(callback) self.onCompleteFunc = callback end
    return result
end
local mask
ISInventoryPaneContextMenu.transferIfNeeded = function(_, item)
    if item.container ~= inventory then
        local transfer = action('ISInventoryTransferAction', item); transfer.srcContainer, transfer.destContainer = item.container, inventory
        ISTimedActionQueue.add(transfer)
    end
end
ISInventoryPaneContextMenu.getEatingMask = function(_, remove)
    if mask and remove then ISTimedActionQueue.add(action('ISUnequipAction', mask)) end
    return mask
end
ISWearClothing = {new = function(_, _, item) return action('ISWearClothing', item) end}
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
local Bulk = project('BulkFood')
local q = ISTimedActionQueue.getTimedActionQueue(player)
local function reset() q.queue, q.current, eaten, calls, fullness, mask = {}, nil, {}, {}, 0, nil end
local function executeCommand(command)
    assert(Bulk.isCommand(command)); command:start(); q:onCompleted(command)
end
local function finish()
    local current = assert(q.current)
    if Bulk.isCommand(current) then executeCommand(current)
    else
        if current.Type == 'ISInventoryTransferAction' and current.destContainer == inventory then
            current.srcContainer.items[current.item.id] = nil; inventory.items[current.item.id] = current.item; current.item.container = inventory
        elseif current.Type == 'ISEatFoodAction' then current:complete(); Batch.completed(current) end
        q:onCompleted(current)
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
mask = {id = -1}
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
assert(Bulk.queueOne({{items = {a, a, b}}}, 1, 0, nil, 100) == 1)
assert(Bulk.queueOne({{items = {a, a, b}}}, 1, 0, nil, 100) == 1)
assert(#q.queue == 2 and #Bulk.entries(player, {a, b}) == 0, 'repeat All clicks reserve successive foods without cancelling earlier commands')
assert(Bulk.queueOne({a, b}, 1, 0, nil, 100) == 0 and #q.queue == 2, 'exhausted selection never substitutes an unselected item')
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
local smart = function() end
local smartOption = sub:addOption('Smart target', {a, b}, smart, 1, 0); smartOption.ES_EatSmart = true
fill(0, context, {a, b}); fill(0, context, {a, b})
assert(ISInventoryPaneContextMenu.onEatItems == originalEat and half.onSelect == originalEat and smartOption.onSelect == smart,
    'public callback, partial native option and EatSmart target keep their original contracts')
assert(all.onSelect == Bulk.queueOne and all.param1 == 1 and all.param2 == 0, 'only native All option chooses an unreserved exact item')
local selectedOptions = 0
for _, option in ipairs(sub.options) do if option.onSelect == Bulk.queue then selectedOptions = selectedOptions + 1 end end
assert(selectedOptions == 1, 'repeated fill appends exactly one selected-food batch command')
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

    reset(); a, b = food(), food(); mask = {id = -2}
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

    reset(); a = food(); mask = {id = -3}
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
print('Bulk food: exact selection, reservations, deferred native eating, masks/returns, progress, stale targets and menu compatibility passed.')
