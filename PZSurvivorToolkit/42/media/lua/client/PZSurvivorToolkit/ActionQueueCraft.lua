require "TimedActions/ISFixAction"
require "TimedActions/ISFixVehiclePartAction"
require "TimedActions/ISCraftAction"
require "Entity/TimedActions/ISHandcraftAction"
require "Entity/ISUI/CraftRecipe/ISWidgetHandCraftControl"

local Craft = {}
PZSurvivorToolkit.ActionQueueCraft = Craft
local nativeHandcraftNew = ISHandcraftAction.new
-- NetTimedAction serializes this constructor by its exact parameter names.
function ISHandcraftAction:new(character, craftRecipe, containers, isoObject, craftBench, manualInputs, items, recipeItem, variableInputRatio, eatPercentage)
    local action = nativeHandcraftNew(self, character, craftRecipe, containers, isoObject, craftBench,
        manualInputs, items, recipeItem, variableInputRatio, eatPercentage)
    -- Java queued-item accounting accepts an absent selection, but casts a false sentinel to a table.
    if getmetatable(action) == ISHandcraftAction and action.manualInputs == false then action.manualInputs = nil end
    return action
end
local contextComplete = ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.OnNewCraftComplete
local legacyComplete = ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.OnCraftComplete
if legacyComplete then
    local nativeLegacyComplete = legacyComplete
    ISInventoryPaneContextMenu.OnCraftComplete = function(action, ...)
        local token = action.toolkitQueueOperation
        if token then
            local settings = PZSurvivorToolkit.Settings
            if token.toolkitCancelled or action.toolkitLegacyContinued or (settings and not settings.actionQueue())
                or (action.character.isDead and action.character:isDead()) then return end
            action.toolkitLegacyContinued = true
        end
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
local lifecycle = {"new", "isValid", "isValidStart", "waitToStart", "start", "update", "stop", "perform", "complete",
    "getDuration", "serverStart", "serverStop", "animEvent", "forceCancel", "forceStop"}
local classes = {}
for _, class in ipairs({ISFixAction, ISCraftAction, ISHandcraftAction, ISFixVehiclePartAction}) do
    local methods = {}
    for _, name in ipairs(lifecycle) do methods[name] = class[name] end
    for name, method in pairs(class) do
        if type(method) == "function" then methods[name] = method end
    end
    classes[class] = methods
end

local owners = {}
local function ownerClass(name)
    if not owners[name] then
        local class = _G[name]
        if class then
            local methods = {}
            if name == "ISWidgetHandCraftControl" then
                -- Native completion calls only these helpers; UI/producer wrappers do not change its effects.
                for _, method in ipairs({"onHandcraftActionStart", "onHandcraftActionComplete",
                    "onHandcraftActionCancelled", "setCraftQuantity", "sanitizeCraftQuantity"}) do
                    methods[method] = class[method]
                end
            else
                for method, callback in pairs(class) do if type(callback) == "function" then methods[method] = callback end end
            end
            owners[name] = {class = class, start = class.onHandcraftActionStart,
                complete = class.onHandcraftActionComplete, cancel = class.onHandcraftActionCancelled,
                methods = methods, trigger = class.triggerEvent}
        end
    end
    return owners[name]
end
ownerClass("ISWidgetHandCraftControl")

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
    for _, name in ipairs({"ISWidgetHandCraftControl", "NC_CraftActionPanel", "PJCK_CraftActionPanel"}) do
        local Compat = PZSurvivorToolkit.ActionQueueCompat
        local verified = name == "ISWidgetHandCraftControl" or (Compat and Compat.isCraftOwner
            and Compat.isCraftOwner(name, target, action))
        local owner = verified and ownerClass(name)
        if owner then
            for method, callback in pairs(owner.methods) do
                if owner.class[method] ~= callback or target[method] ~= callback then owner = nil; break end
            end
        end
        if owner and getmetatable(target) == owner.class and owner.start and owner.complete and owner.cancel
            and _G[name] == owner.class
            and target.triggerEvent == owner.trigger
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
    for name, method in pairs(methods) do if action[name] ~= method then return false end end
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
    if not list or not instanceof(list, "List") then return false end
    return pcall(function()
        for i = 0, list:size() - 1 do
            local item = list:get(i)
            if item and instanceof(item, "InventoryItem") then items[item] = true end
        end
    end)
end

function Craft.repairInputs(action)
    if not Craft.supports(action) or (getmetatable(action) ~= ISFixAction and getmetatable(action) ~= ISFixVehiclePartAction) then return end
    local types = {}
    -- Kahlua logs failed assertions even inside pcall; unsupported inputs are ordinary rejections.
    local ok, result = pcall(function()
        -- MP reconstructs these selections from their indices, not the client's cached fields.
        if FixingManager.getFixes(action.item):get(action.fixingNum) ~= action.fixing then return end
        if action.fixing:getFixers():get(action.fixerNum) ~= action.fixer then return end
        local function add(fixer)
            local name = fixer:getFixerName()
            if type(name) ~= "string" or name == "" then return false end
            types[name] = true
            return true
        end
        if not add(action.fixer) then return end
        local global = action.fixing:getGlobalItem()
        if global and not add(global) then return end
        return types
    end)
    if ok then return result end
end

-- Loaded script lines include overrides; never execute recipe callbacks to discover effects.
local function recipeCallbacksSafe(recipe)
    local lines = recipe:getScriptLines()
    if lines:size() <= 0 then return false end
    for i = 0, lines:size() - 1 do
        for key in lines:get(i):lower():gmatch("([%w_]+)%s*[:=]") do
            if key:sub(1, 2) == "on" or key:sub(1, 3) == "lua" then return false end
        end
    end
    return true
end

function Craft.futureResources(action)
    if not Craft.supports(action) then return end
    local Food = PZSurvivorToolkit.BulkFood
    if Food and Food.isOpening and Food.isOpening(action) then return Food.openingResources(action) end
    local class = getmetatable(action)
    if class ~= ISHandcraftAction and class ~= ISCraftAction then return end
    local recipe = class == ISHandcraftAction and action.craftRecipe or action.recipe
    local result = {dynamicInputs = {}, outputTypes = {}, equipment = action.character}
    local ok, complete = pcall(function()
        if not instanceof(recipe, class == ISHandcraftAction and "CraftRecipe" or "Recipe") then return end
        if action.items and not addList(action.items, {}) then return end
        if action.manualInputs then
            if type(action.manualInputs) ~= "table" then return end
            for _, items in pairs(action.manualInputs) do if not addList(items, {}) then return end end
        end
        local _, owner = callbackOwner(action)
        if owner and owner.returnToContainer then
            if type(owner.returnToContainer) ~= "table" then return end
            for _, item in ipairs(owner.returnToContainer) do if not instanceof(item, "InventoryItem") then return end end
        end
        if not recipeCallbacksSafe(recipe) then return end
        local function addType(types, name)
            if type(name) ~= "string" or not name:match("^[%w_]+%.[%w_]+$") then return false end
            types[name] = true
            return true
        end
        local function addScriptItems(list, types, input)
            if list:size() <= 0 then return false end
            for i = 0, list:size() - 1 do
                local script = list:get(i)
                if not instanceof(script, "Item") or not addType(types, script:getFullName()) then return false end
                if input then
                    -- Depleted/used items and broken tools can create undeclared items or run callbacks.
                    if script:isItemType(ItemType.CONTAINER) or script:getReplaceOnUse()
                        or script:getReplaceOnDeplete() or script:getOnBreak() then return false end
                end
            end
            return true
        end
        if class == ISHandcraftAction then
            local function output(script)
                if not instanceof(script, "OutputScript") or script:getResourceType() ~= ResourceType.Item
                    or script:getCreateToItemScript() then return false end
                return addScriptItems(script:getPossibleResultItems(), result.outputTypes)
            end
            local inputs = recipe:getInputs()
            if inputs:size() <= 0 then return end
            for i = 0, inputs:size() - 1 do
                local input = inputs:get(i)
                if not instanceof(input, "InputScript") or input:getResourceType() ~= ResourceType.Item
                    or input:isAcceptsAnyItem() or input:getConsumeFromItemScript() then return end
                if not addScriptItems(input:getPossibleInputItems(), result.dynamicInputs, true) then return end
                if input:getCreateToItemScript() and not output(input:getCreateToItemScript()) then return end
                if input:isReplace() and not output(input:getReplaceOutputScript()) then return end
            end
            local outputs = recipe:getOutputs()
            for i = 0, outputs:size() - 1 do if not output(outputs:get(i)) then return end end
        else
            if not instanceof(recipe, "Recipe") or instanceof(recipe, "MovableRecipe") then return end
            if recipe:isRequiresWorkstation() or recipe:getNearItem() or recipe:getHeat() ~= 0 then return end
            local sources = recipe:getSource()
            if sources:size() <= 0 then return end
            for i = 0, sources:size() - 1 do
                local types = sources:get(i):getItems()
                if types:size() <= 0 then return end
                for j = 0, types:size() - 1 do
                    local name = types:get(j)
                    if not addType(result.dynamicInputs, name) then return end
                    local script = getScriptManager():FindItem(name)
                    if not script or script:isItemType(ItemType.CONTAINER) or script:getReplaceOnUse()
                        or script:getReplaceOnDeplete() or script:getOnBreak() then return end
                end
            end
            local outputs = recipe:getResults()
            if outputs:size() <= 0 then return end
            for i = 0, outputs:size() - 1 do
                if not addType(result.outputTypes, outputs:get(i):getFullType()) then return end
            end
        end
        return result
    end)
    if ok then return complete end
end

function Craft.canSkip(action)
    if not Craft.supports(action) or getmetatable(action) ~= ISHandcraftAction or action.force
        or action.action or action.craftStarted ~= false or type(action.manualInputs) ~= "table" then return false end
    local ok, missing = pcall(function()
        -- Before native allocation, missing pinned IDs can be rejected without consuming or breaking any item.
        if not recipeCallbacksSafe(action.craftRecipe) then return false end
        local root = action.character:getInventory()
        if not instanceof(root, "ItemContainer") or not instanceof(action.containers, "List")
            or action.containers:size() == 0 then return false end
        local containers = {root}
        for i = 0, action.containers:size() - 1 do
            local container = action.containers:get(i)
            if not instanceof(container, "ItemContainer") then return false end
            containers[#containers + 1] = container
        end
        local inputs, indices, selections = action.craftRecipe:getInputs(), {}, {}
        local pooled, duplicate = false, false
        if inputs:size() == 0 then return false end
        for i = 0, inputs:size() - 1 do
            local input = inputs:get(i)
            if not instanceof(input, "InputScript") or input:getResourceType() ~= ResourceType.Item
                or input:isAcceptsAnyItem() or input:getConsumeFromItemScript() then return false end
            local index = action.craftRecipe:getIndexForIO(input)
            local selected, amount = action.manualInputs[index], input:getIntAmount()
            if type(index) ~= "number" or index < 0 or index % 1 ~= 0
                or action.craftRecipe:getIOForIndex(index) ~= input or indices[index]
                or input:isVariableAmount() or amount <= 0 or not instanceof(selected, "List")
                or selected:size() < amount then return false end
            pooled = pooled or selected:size() > amount
            indices[index] = true
            local selection = {input = input, amount = amount, ids = {}, items = selected}
            selections[#selections + 1] = selection
            local seen = {}
            for j = 0, selected:size() - 1 do
                local item = selected:get(j)
                if not instanceof(item, "InventoryItem") then return false end
                local id = item:getID()
                if type(id) ~= "number" or id % 1 ~= 0 then return false end
                duplicate = duplicate or seen[id] == true
                seen[id] = true; selection.ids[#selection.ids + 1] = id
            end
        end
        for index in pairs(action.manualInputs) do if not indices[index] then return false end end
        if pooled then
            local _, owner, cancel = callbackOwner(action)
            if not owner or cancel == "logic" or duplicate then return false end
            for _, selection in ipairs(selections) do
                local input = selection.input
                if input:getAmount() ~= selection.amount or input:getCreateToItemScript() or input:isReplace() then return false end
                for i = 0, selection.items:size() - 1 do
                    local item = selection.items:get(i)
                    local script = item:getScriptItem()
                    if not instanceof(script, "Item") or script:isItemType(ItemType.DRAINABLE)
                        or script:isItemType(ItemType.FOOD) or script:isItemType(ItemType.CONTAINER)
                        or script:getReplaceOnUse() or script:getReplaceOnDeplete()
                        or input:getRelativeScale(item:getFullType()) ~= 1 then return false end
                    -- Native use/removal does not invoke OnBreak; only degrading kept tools can reach it.
                    if script:getOnBreak() and input:isKeep() and (action.craftRecipe:isSmithing()
                        or input:hasFlag(InputFlag.MayDegradeHeavy) or input:hasFlag(InputFlag.MayDegrade)
                        or input:hasFlag(InputFlag.MayDegradeLight) or input:hasFlag(InputFlag.MayDegradeVeryLight)
                        or input:hasFlag(InputFlag.SharpnessCheck)) then return false end
                end
            end
        end
        local missing = false
        for _, selection in ipairs(selections) do
            local available = 0
            for index, id in ipairs(selection.ids) do
                local found = false
                for _, container in ipairs(containers) do
                    -- MP can replace item objects; native container lookups also search carried bags.
                    local item = container:getItemById(id)
                    if item then
                        if not instanceof(item, "InventoryItem") or item:getID() ~= id then return false end
                        -- Unflagged ordinary inputs count uses, so only one unscaled live use proves one item.
                        if pooled and (item:getCurrentUses() ~= 1
                            or item:getFullType() ~= selection.items:get(index - 1):getFullType()
                            or item:getScriptItem() ~= selection.items:get(index - 1):getScriptItem()) then return false end
                        found = true
                    end
                end
                if found then available = available + 1 end
            end
            if available < selection.amount then missing = true end
        end
        return missing
    end)
    return ok and missing == true
end

function Craft.collectItems(action, items)
    if not Craft.supports(action) then return false, false end
    local _, owner = callbackOwner(action)
    if owner then items[owner] = true end -- One UI owner can maintain several queued batches.
    if owner and type(owner.returnToContainer) == "table" then
        for _, item in ipairs(owner.returnToContainer) do
            if instanceof(item, "InventoryItem") then items[item] = true end
        end
    end
    if action.item then items[action.item] = true end
    if action.recipeItem then items[action.recipeItem] = true end
    if getmetatable(action) == ISFixAction or (ISFixVehiclePartAction and getmetatable(action) == ISFixVehiclePartAction) then
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
        -- Late selections are described separately by the recipe contract.
        return known, true
    end
    return false, true
end

return Craft
