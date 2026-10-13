require "TimedActions/ISFixAction"
require "TimedActions/ISCraftAction"
require "Entity/TimedActions/ISHandcraftAction"

local Craft = {}
PZSurvivorToolkit.ActionQueueCraft = Craft
local contextComplete = ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.OnNewCraftComplete
local legacyComplete = ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.OnCraftComplete
if legacyComplete then
    local nativeLegacyComplete = legacyComplete
    ISInventoryPaneContextMenu.OnCraftComplete = function(action, ...)
        local token = action.toolkitQueueOperation
        if token and token.toolkitCancelled then return end
        local Operations = PZSurvivorToolkit.ActionQueueOperations
        local function continue(...)
            local result = nativeLegacyComplete(action, ...)
            local Batch = PZSurvivorToolkit.ActionQueueBatch
            if Batch then Batch.legacyContinued(action) end
            return result
        end
        if Operations then return Operations.runWith(token, continue, ...) end
        return continue(...)
    end
    legacyComplete = ISInventoryPaneContextMenu.OnCraftComplete
end
-- Native completion callbacks can append returns after onCompleted removed their action.
for _, class in ipairs({ISCraftAction, ISHandcraftAction}) do
    local perform = class.perform
    class.perform = function(action, ...)
        local Operations = PZSurvivorToolkit.ActionQueueOperations
        if Operations then return Operations.perform(action, perform, ...) end
        return perform(action, ...)
    end
end
local lifecycle = {"new", "isValid", "start", "update", "stop", "perform", "complete", "forceCancel", "forceStop"}
local classes = {}
for _, class in ipairs({ISFixAction, ISCraftAction, ISHandcraftAction}) do
    local methods = {}
    for _, name in ipairs(lifecycle) do methods[name] = class[name] end
    methods.serverStart, methods.performRecipe = class.serverStart, class.performRecipe
    classes[class] = methods
end

local owners = {}
local function ownerClass(name)
    if not owners[name] then
        local class = _G[name]
        if class then
            owners[name] = {class = class, start = class.onHandcraftActionStart,
                complete = class.onHandcraftActionComplete, cancel = class.onHandcraftActionCancelled}
        end
    end
    return owners[name]
end

local function callbackOwner(action)
    if not action.onStartFunc and not action.onCompleteFunc and not action.onCancelFunc then return true end
    if getmetatable(action) == ISCraftAction then
        local args = action.onCompleteArgs
        return not action.onStartFunc and not action.onCancelFunc and legacyComplete ~= nil
            and ISInventoryPaneContextMenu.OnCraftComplete == legacyComplete
            and action.onCompleteFunc == legacyComplete and type(args) == "table"
            and args[1] == action and args[2] == action.recipe and args[3] == action.character
            and args[4] == action.container and args[5] == action.containersIn
            and type(args[6]) == "string" and args[7] ~= nil
    end
    if getmetatable(action) ~= ISHandcraftAction then return false end
    if not action.onStartFunc and not action.onCancelFunc and contextComplete and ISInventoryPaneContextMenu
        and ISInventoryPaneContextMenu.OnNewCraftComplete == contextComplete
        and action.onCompleteFunc == contextComplete then
        local logic = action.onCompleteTarget
        if logic and instanceof(logic, "HandcraftLogic") and logic:getPlayer() == action.character then
            return true, logic, "logic"
        end
        return false
    end
    local target = action.onCancelTarget
    if not target or target ~= action.onStartTarget or target ~= action.onCompleteTarget
        or target.player ~= action.character or not target.logic
        or not instanceof(target.logic, "HandcraftLogic") or target.logic:getPlayer() ~= action.character then return false end
    for _, name in ipairs({"ISWidgetHandCraftControl", "NC_CraftActionPanel"}) do
        local owner = ownerClass(name)
        if owner and getmetatable(target) == owner.class and owner.start and owner.complete and owner.cancel
            and action.onStartFunc == owner.start and action.onCompleteFunc == owner.complete
            and action.onCancelFunc == owner.cancel and target.onHandcraftActionStart == owner.start
            and target.onHandcraftActionComplete == owner.complete
            and target.onHandcraftActionCancelled == owner.cancel then return true, target, owner.cancel end
    end
    return false
end

function Craft.callbacksSafe(action)
    return callbackOwner(action) == true
end

function Craft.isLegacyAll(action)
    return getmetatable(action) == ISCraftAction and action.onCompleteFunc == legacyComplete
        and legacyComplete ~= nil and Craft.callbacksSafe(action)
end

function Craft.supports(action)
    if type(action) ~= "table" then return false end
    local class = getmetatable(action)
    local methods = classes[class]
    if not methods or action.Type ~= class.Type then return false end
    for _, name in ipairs(lifecycle) do
        if action[name] ~= methods[name] then return false end
    end
    if action.serverStart ~= methods.serverStart or action.performRecipe ~= methods.performRecipe then return false end
    if class == ISHandcraftAction then
        if not action.craftRecipe or not instanceof(action.craftRecipe, "CraftRecipe") then return false end
    elseif not action.item or not instanceof(action.item, "InventoryItem") then
        if class ~= ISCraftAction or not Craft.isLegacyAll(action) or action.item ~= nil then return false end
    end
    return Craft.callbacksSafe(action)
end

function Craft.cancelWaiting(action)
    if not Craft.supports(action) or (action.action and action.action:isStarted()) or action.craftStarted then return false end
    local _, owner, cancel = callbackOwner(action)
    if not owner then return true end
    local token = action.toolkitQueueOperation or action
    token.toolkitCraftCancelledOwners = token.toolkitCraftCancelledOwners or {}
    if not token.toolkitCraftCancelledOwners[owner] then
        token.toolkitCraftCancelledOwners[owner] = true
        if cancel == "logic" then owner:stopCraftAction(true) else cancel(owner) end
    end
    return true
end

function Craft.nativeStopped(action)
    if not Craft.supports(action) then return false end
    local _, owner, cancel = callbackOwner(action)
    if not owner or cancel == "logic" then return false end
    local token = action.toolkitQueueOperation or action
    token.toolkitCraftCancelledOwners = token.toolkitCraftCancelledOwners or {}
    token.toolkitCraftCancelledOwners[owner] = true
    return true
end

function Craft.cancelQueue(queue)
    local current = queue.current
    if current and current.action and current.action:isStarted() and Craft.supports(current) then Craft.nativeStopped(current) end
    for _, action in ipairs(queue.queue) do
        local Batch = PZSurvivorToolkit.ActionQueueBatch
        if Batch then Batch.cancel(action) end
        Craft.cancelWaiting(action)
    end
end

local function addList(list, items)
    if not list then return false end
    return pcall(function()
        for i = 0, list:size() - 1 do
            local item = list:get(i)
            if item and instanceof(item, "InventoryItem") then items[item] = true end
        end
    end)
end

function Craft.repairInputs(action)
    if not Craft.supports(action) or getmetatable(action) ~= ISFixAction then return end
    local types = {}
    local ok = pcall(function()
        -- MP reconstructs these selections from their indices, not the client's cached fields.
        assert(FixingManager.getFixes(action.item):get(action.fixingNum) == action.fixing)
        assert(action.fixing:getFixers():get(action.fixerNum) == action.fixer)
        local function add(fixer)
            local name = fixer:getFixerName()
            assert(type(name) == "string" and name ~= "")
            types[name] = true
        end
        add(action.fixer)
        local global = action.fixing:getGlobalItem()
        if global then add(global) end
    end)
    if ok then return types end
end

function Craft.collectItems(action, items)
    if not Craft.supports(action) then return false, false end
    local _, owner = callbackOwner(action)
    if owner then items[owner] = true end -- One UI owner can maintain several queued batches.
    if action.item then items[action.item] = true end
    if action.recipeItem then items[action.recipeItem] = true end
    if getmetatable(action) == ISFixAction then
        local ok, required = pcall(function()
            return action.fixing:getRequiredItems(action.character, action.fixer, action.item)
        end)
        if ok then addList(required, items) end
        -- Native server completion selects donors again by type, without binding these item IDs.
        return false, true
    elseif getmetatable(action) == ISHandcraftAction then
        local known = addList(action.items, items)
        if action.manualInputs then
            if type(action.manualInputs) ~= "table" then return false, true end
            known = true
            for _, list in pairs(action.manualInputs) do
                if not addList(list, items) then known = false end
            end
        end
        -- shortcut: automatic multicraft and legacy recipes select inputs later; keep their reordering protected.
        return known, true
    end
    return false, true
end

return Craft
