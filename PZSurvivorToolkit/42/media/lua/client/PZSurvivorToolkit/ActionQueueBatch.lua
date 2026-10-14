local Batch = {}
PZSurvivorToolkit.ActionQueueBatch = Batch

local function kind(action)
    local Food = PZSurvivorToolkit.BulkFood
    if Food and Food.isCommand(action) then return "food-plan" end
    if Food and Food.isEat(action) then return "action" end
    local Craft, Recipes = PZSurvivorToolkit.ActionQueueCraft, PZSurvivorToolkit.CraftChainRecipes
    if Craft and (action.Type == "ISCraftAction" or action.Type == "ISHandcraftAction")
        and Craft.supports(action) then return "craft" end
    if action.toolkitIndependentBulk then
        return action.Type == "ISHandcraftAction" and "craft" or "action"
    end
    if action.Type == "ISQueueActionsAction" and action.toolkitCraftPlanCancellation
        and Recipes and action.addActionsFunction == Recipes.addStep then return "plan" end
end

function Batch.attach(action)
    local token, unit = action.toolkitQueueOperation, kind(action)
    if type(token) ~= "table" or not unit then return end
    action.toolkitBatchUnit = unit
    local state = token.toolkitBatch
    if not state then
        state = {total = 0, completed = 0, unit = (unit == "action" or unit == "food-plan") and "action" or "craft",
            iterations = {}, finished = {}, discarded = {}}
        token.toolkitBatch = state
    end
    if unit == "action" or unit == "food-plan" then state.unit = "action" end
    if unit == "plan" or unit == "food-plan" then action.toolkitBatchIteration = action end
    local iteration = action.toolkitBatchIteration or action
    if not state.iterations[iteration] then
        state.iterations[iteration] = true
        if not state.lazy then state.total = state.total + 1 end
    end
    local Craft = PZSurvivorToolkit.ActionQueueCraft
    if Craft and Craft.isLegacyAll(action) then
        state.legacyLast = action
        if not state.lazy then
            state.lazy = true
            local ok, count = pcall(RecipeManager and RecipeManager.getNumberOfTimesRecipeCanBeDone,
                action.recipe, action.character, action.containersIn, action.item)
            state.total = ok and type(count) == "number" and count >= 1 and count or nil
        end
    end
end

function Batch.legacyContinued(action)
    local state = action.toolkitQueueOperation and action.toolkitQueueOperation.toolkitBatch
    if state and state.legacyLast == action then
        state.lazy = false
        state.total = state.completed + 1
    end
end

function Batch.completed(action)
    local token = action.toolkitQueueOperation
    local state = token and token.toolkitBatch
    local unit = action.toolkitBatchUnit
    if not state or not unit or unit == "plan" or unit == "food-plan" then return end
    local iteration = action.toolkitBatchIteration or action
    if state.finished[iteration] or state.discarded[iteration] then return end
    state.finished[iteration] = true
    state.completed = state.completed + 1
    if state.total then state.total = math.max(state.total, state.completed) end
end

function Batch.discard(action)
    local state = action.toolkitQueueOperation and action.toolkitQueueOperation.toolkitBatch
    if not state or not action.toolkitBatchUnit then return end
    local iteration = action.toolkitBatchIteration or action
    if state.finished[iteration] or state.discarded[iteration] then return end
    state.discarded[iteration] = true
    if state.total then state.total = math.max(state.completed, state.total - 1) end
end

function Batch.cancel(action)
    local token = action and action.toolkitQueueOperation
    if type(token) == "table" then token.toolkitCancelled = true end
end

function Batch.progress(queue, action)
    local state = action.toolkitQueueOperation and action.toolkitQueueOperation.toolkitBatch
    if not state then return end
    return {total = state.total, completed = state.completed,
        remaining = state.total and math.max(0, state.total - state.completed) or nil,
        unit = state.unit, lazy = state.lazy}
end

return Batch
