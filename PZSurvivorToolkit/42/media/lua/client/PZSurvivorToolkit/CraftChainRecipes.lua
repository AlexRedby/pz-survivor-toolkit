require "PZSurvivorToolkit/BulkActions"
require "PZSurvivorToolkit/ActionQueueOperations"
require "TimedActions/ISQueueActionsAction"
require "Entity/ISEntityUI"
require "Entity/TimedActions/ISHandcraftAction"
require "ISUI/ISCraftingUI"

local Recipes = {}
PZSurvivorToolkit.CraftChainRecipes = Recipes
local Bulk = PZSurvivorToolkit.BulkActions
local Operations = PZSurvivorToolkit.ActionQueueOperations
local Settings = PZSurvivorToolkit.Settings

local function reason(kind)
    return getText("UI_PZST_CraftChain" .. kind)
end

local intentions = setmetatable({}, {__mode = "k"})
local hooked = setmetatable({}, {__mode = "k"})

local function recipeChanged(state, recipe)
    if state.recipe ~= recipe then state.recipe, state.inputs = recipe, {} end
end

local function manualSelectChanged(state, manualSelectInputs)
    if not manualSelectInputs then state.inputs = {} end
end

local function intention(logic)
    local state = intentions[logic]
    if not state then
        state = {recipe = logic:getRecipe(), inputs = {}}
        intentions[logic] = state
        if logic.addEventListener then
            logic:addEventListener("onRecipeChanged", recipeChanged, state)
            logic:addEventListener("onManualSelectChanged", manualSelectChanged, state)
        end
    end
    recipeChanged(state, logic:getRecipe())
    return state
end

local function remember(logic, input)
    if not input then return end
    local state = intention(logic)
    local items = logic:getManualInputsFor(input, ArrayList.new())
    local selection = {ids = {}}
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local fullType = item:getFullType()
        if selection.fullType and selection.fullType ~= fullType then selection.mixed = true end
        selection.fullType = fullType
        selection.ids[item:getID()] = true
    end
    state.inputs[input] = selection.fullType and selection or nil
end

local function hookPicker(class, name)
    if not class or type(class[name]) ~= "function" then return end
    local original = class[name]
    if hooked[original] then return end
    local wrapped = function(self, ...)
        local logic = not self.itemSlot and self.logic
        local input = logic and logic:getManualSelectInputScriptFilter()
        if logic then intention(logic) end
        local result = original(self, ...)
        if logic and result ~= false then remember(logic, input) end
        return result
    end
    class[name] = wrapped
    hooked[wrapped] = true
end

function Recipes.install()
    -- Manual mode also auto-populates; only picker actions express a preference.
    hookPicker(ISCraftInventoryPanel, "onListItemClicked")
    hookPicker(NC_InputSwitch_Panel, "onItemSelected")
    hookPicker(NC_InputSwitch_Panel, "onItemGroupDoubleClick")
end

local function integer(value)
    return value and value > 0 and value == math.floor(value)
end

local function callbacks(recipe)
    -- LuaCall is not exposed in B42; loaded bodies are public in normal play.
    local bodies = recipe:getLoadedScriptBodies()
    if not bodies or bodies:size() < 2 then return true end
    for i = 1, bodies:size() - 1, 2 do
        local body = tostring(bodies:get(i)):lower()
        for _, name in ipairs({"ontest", "onstart", "onupdate", "oncreate", "onfailed"}) do
            if body:find("%f[%a]" .. name .. "%s*=") then return true end
        end
    end
    return false
end

local function available(recipe, logic, player, containers)
    if not CraftRecipeManager.isValidRecipeForCharacter(recipe, player, nil, containers) then
        return false
    end
    logic:setRecipe(recipe)
    if recipe:isAnySurfaceCraft() then
        local surface = logic:getIsoObject()
        if not surface or not surface:getSquare() or not logic:isCharacterInRangeOfWorkbench() then
            return false
        end
    end
    return logic:hasRequiredWorkstation()
end

local function spec(recipe, logic, player, containers)
    if callbacks(recipe) or recipe:hasOnTickInputs() or recipe:hasOnTickOutputs() then
        return nil, reason("UnsupportedCallbacks")
    end
    local result = {id = recipe:getName(), name = recipe:getTranslationName(), native = recipe,
        inputs = {}, outputs = {}}
    local outputs, outputCount = recipe:getOutputs(), 0
    for i = 0, outputs:size() - 1 do
        local output = outputs:get(i)
        local items = output:getResourceType() == ResourceType.Item and output:getPossibleResultItems()
        if not items or items:size() ~= 1 or output:isVariableAmount() or output:getChance() ~= 1
            or output:isReplaceInput() or output:hasCreateToItem() or output:isApplyOnTick()
            or tostring(output:getOriginalLine()):lower():find("mapper%s*:")
            or not integer(output:getAmount()) then
            return nil, reason("UnsupportedOutputs")
        end
        local item = items:get(0)
        if item:getCount() ~= 1 then return nil, reason("UnsupportedOutputs") end
        local fullType = item:getFullName()
        outputCount = outputCount + output:getIntAmount()
        if outputCount > 1000 then return nil, reason("UnsupportedOutputs") end
        result.outputs[fullType] = (result.outputs[fullType] or 0) + output:getIntAmount()
    end
    if outputCount == 0 then return nil, reason("UnsupportedOutputs") end
    local inputs = recipe:getInputs()
    if inputs:size() > 32 then return nil, reason("UnsupportedInputs") end
    for i = 0, inputs:size() - 1 do
        local input = inputs:get(i)
        if input:getResourceType() ~= ResourceType.Item or input:isVariableAmount()
            or input:hasConsumeFromItem() or input:hasCreateToItem() or input:isReplace()
            or input:isApplyOnTick() then
            return nil, reason("UnsupportedInputs")
        end
        local slot = {index = recipe:getIndexForIO(input), native = input,
            keep = input:isKeep(), choices = {}}
        local items = input:getPossibleInputItems()
        if items:size() > 256 then return nil, reason("UnsupportedInputs") end
        for j = 0, items:size() - 1 do
            local item = items:get(j)
            local fullType, amount = item:getFullName(), input:getAmount(item:getFullName())
            if not integer(amount) or amount > 1000 or input:isUsesPartialItem(item) then
                return nil, reason("UnsupportedInputs")
            end
            slot.choices[#slot.choices + 1] = {fullType = fullType, amount = amount}
        end
        if #slot.choices == 0 then return nil, reason("UnsupportedInputs") end
        slot.allChoices = slot.choices
        result.inputs[#result.inputs + 1] = slot
    end
    if not available(recipe, logic, player, containers) then return nil, reason("Unavailable") end
    return result
end

local function accepts(player, input, resource)
    if input.selectedIds and (not resource.item or not input.selectedIds[resource.item:getID()]) then return false end
    if not resource.item then return true end
    local item = resource.item
    if not input.keep and not Bulk.safeItem(player, item) then return false end
    return input.native:canUseItem(item, player)
end

local function resources(logic)
    local result, seen = {}, {}
    local items = logic:getAllItems()
    if items:size() > 10000 then return end
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if not seen[item:getID()] then
            seen[item:getID()] = true
            result[#result + 1] = {fullType = item:getFullType(), item = item}
        end
    end
    return result
end

local function collect(panel, overrides)
    if not panel or not panel.logic then return nil, reason("Unavailable") end
    local selected = panel.logic
    local player, target = selected:getPlayer(), selected:getRecipe()
    if not player or not target then return nil, reason("Unavailable") end
    local state = intention(selected)
    if not selected:isManualSelectInputs() then state.inputs = {} end
    local nativeIntent = state.inputs
    local context = {player = player, craftBench = selected:getCraftBench(), surface = selected:getIsoObject()}
    local containers = ISInventoryPaneContextMenu.getContainers(player)
    local logic = HandcraftLogic.new(player, context.craftBench, context.surface)
    logic:setContainers(containers)
    local stock = resources(logic)
    if not stock then return nil, reason("complex") end
    local model = {recipes = {}, resources = stock,
        accepts = function(input, resource) return accepts(player, input, resource) end}
    local targetSpec, failure = spec(target, logic, player, containers)
    if not targetSpec then return nil, failure end
    local all = getScriptManager():getAllCraftRecipes()
    for i = 0, all:size() - 1 do
        local native = all:get(i)
        if native ~= target then
            local candidate = spec(native, logic, player, containers)
            if candidate then model.recipes[candidate.id] = candidate end
        end
    end
    model.recipes[targetSpec.id] = targetSpec
    if overrides ~= nil and type(overrides) ~= "table" then return nil, reason("UnsupportedSelection") end
    for id, slots in pairs(overrides or {}) do
        local candidate = model.recipes[id]
        if not candidate or type(slots) ~= "table" then return nil, reason("UnsupportedSelection") end
        for index, value in pairs(slots) do
            local found
            for _, slot in ipairs(candidate.inputs) do if slot.index == index then found = true end end
            if not found or (value ~= false and type(value) ~= "string") then
                return nil, reason("UnsupportedSelection")
            end
        end
    end
    local stockById = {}
    for _, resource in ipairs(stock) do stockById[resource.item:getID()] = resource end
    for id, candidate in pairs(model.recipes) do
        for _, slot in ipairs(candidate.inputs) do
            local override = overrides and overrides[id] and overrides[id][slot.index]
            local imported = candidate == targetSpec and nativeIntent[slot.native]
            if override == nil and imported then
                if imported.mixed then return nil, reason("UnsupportedSelection") end
                for itemId in pairs(imported.ids) do
                    local resource = stockById[itemId]
                    if not resource or resource.fullType ~= imported.fullType or not accepts(player, slot, resource) then
                        return nil, reason("UnsupportedSelection")
                    end
                end
                slot.preference, slot.nativeSelection, slot.preferredIds = imported.fullType, true, imported.ids
            elseif override ~= nil and override ~= false then
                slot.preference = override
            end
            if slot.preference then
                local chosen = {}
                for _, choice in ipairs(slot.allChoices) do
                    if choice.fullType == slot.preference then chosen[#chosen + 1] = choice end
                end
                if #chosen == 0 then return nil, reason("UnsupportedSelection") end
                slot.choices = chosen
            end
        end
    end
    return model, targetSpec.id, context
end

function Recipes.collect(panel, overrides)
    Recipes.install()
    local selected = panel and panel.logic and panel.logic:getRecipe()
    local model, target, context = collect(panel, overrides)
    if selected then panel.logic:setLastSelectedRecipe(selected) end
    return model, target, context
end

local function fail(player)
    HaloTextHelper.addBadText(player, reason("Changed"))
    -- A failed generator adds nothing; native ISQueueActionsAction stops its whole tail.
end

local function live(player, context)
    return Settings.craftChains() and context.player == player
        and getSpecificPlayer(player:getPlayerNum()) == player
        and not player:isDead() and not player:isAsleep()
end

local function addStep(player, step, context, initialIds)
    if not live(player, context) then return end
    local logic = HandcraftLogic.new(player, context.craftBench, context.surface)
    local containers = ISInventoryPaneContextMenu.getContainers(player)
    logic:setContainers(containers)
    local recipe = step.recipe.native
    if not available(recipe, logic, player, containers) then return fail(player) end
    local availableItems, used, selected = resources(logic), {}, {}
    if not availableItems then return fail(player) end
    -- Pick every input before adding pickups, so a changed later slot cannot cost items.
    for _, input in ipairs(step.recipe.inputs) do
        local choice = step.inputs[input.index]
        if not choice or not integer(choice.amount) or type(choice.resourceIds) ~= "table"
            or type(choice.generated) ~= "number" or choice.generated < 0 or choice.generated ~= math.floor(choice.generated)
            or #choice.resourceIds + choice.generated ~= choice.amount or type(initialIds) ~= "table" then
            return fail(player)
        end
        local items = ArrayList.new()
        for _, id in ipairs(choice.resourceIds) do
            for _, resource in ipairs(availableItems) do
                local item = resource.item
                if item:getID() == id and resource.fullType == choice.fullType and not used[id]
                    and accepts(player, input, resource) then
                    items:add(item); used[id] = true
                    break
                end
            end
        end
        if items:size() ~= #choice.resourceIds then return fail(player) end
        if choice.generated > 0 then
            for _, resource in ipairs(availableItems) do
                local item = resource.item
                if resource.fullType == choice.fullType and not initialIds[item:getID()] and not used[item:getID()]
                    -- Another player's new shared-container item is not evidence of our craft output.
                    and item:getContainer() == player:getInventory() and accepts(player, input, resource) then
                    items:add(item); used[item:getID()] = true
                    if items:size() == choice.amount then break end
                end
            end
        end
        if items:size() ~= choice.amount then return fail(player) end
        selected[#selected + 1] = {input = input, items = items}
    end
    logic:setManualSelectInputs(true)
    logic:clearManualInputs()
    for _, selection in ipairs(selected) do
        if not logic:setManualInputsFor(selection.input.native, selection.items) then
            return fail(player)
        end
    end
    if not logic:canPerformCurrentRecipe() then return fail(player) end
    local action = ISHandcraftAction.FromLogic(logic)
    if recipe:isAnySurfaceCraft() and not ISEntityUI.WalkToEntity(player, context.surface) then
        return fail(player)
    end
    local items = logic:getRecipeData():getAllInputItems()
    local kept = logic:getRecipeData():getAllPutBackInputItems()
    local returns, transferred = {}, {}
    if logic:isUsingRecipeAtHandBenefit() then
        local book = logic:getUsingRecipeAtHandItem()
        if book then items:add(book); kept:add(book) end
    end
    if not recipe:isCanBeDoneFromFloor() then
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item:getContainer() ~= player:getInventory() and not transferred[item:getID()] then
                transferred[item:getID()] = true
                Bulk.transfer(player, item)
                if kept:contains(item) then returns[#returns + 1] = item end
            end
        end
    end
    ISTimedActionQueue.add(action)
    ISCraftingUI.ReturnItemsToOriginalContainer(player, returns)
end

function Recipes.enqueue(player, plan, context)
    if not player or not plan or not context or not plan.steps or #plan.steps == 0
        or not live(player, context) then return false end
    Operations.run(function()
        for _, step in ipairs(plan.steps) do
            local action = ISQueueActionsAction:new(player, addStep, step, context, plan.initialIds)
            action.craftRecipe = step.recipe.native
            action.toolkitCraftPlanCancellation = true
            ISTimedActionQueue.add(action)
        end
    end)
    return true
end

-- Cancellation trusts only our generator and the native forceCancel implementation.
Recipes.addStep = addStep
if Events and Events.OnGameStart then Events.OnGameStart.Add(Recipes.install) end
return Recipes
