local Planner = {}
PZSurvivorToolkit.CraftPlanner = Planner

local function copy(list)
    local result = {}
    for key, value in pairs(list) do result[key] = value end
    return result
end

-- Resources are individual items, so two input slots cannot spend the same item.
function Planner.plan(model, target, count)
    if not model.recipes[target] or type(count) ~= "number" or count ~= math.floor(count)
        or count < 1 or count > 100 then return nil, "quantity" end
    local producers = {}
    for _, recipe in pairs(model.recipes) do
        for fullType in pairs(recipe.outputs) do
            producers[fullType] = producers[fullType] or {}
            table.insert(producers[fullType], recipe)
        end
    end
    for _, recipes in pairs(producers) do
        table.sort(recipes, function(a, b) return a.id < b.id end)
    end
    local budget, work, reason, missing = 2000, 500000, "missing", nil
    local function spend(amount)
        work = work - amount
        if work < 0 then reason = "complex"; return false end
        return true
    end
    local function available(state, input, choice, scope)
        local result, others = {}, {}
        if not spend(#state.resources) then return result end
        for index, resource in ipairs(state.resources) do
            local reserved = state.reserved[resource]
            if resource.fullType == choice.fullType
                and (not reserved or input.keep and reserved[scope] == nil)
                and (not resource.item and not input.selectedIds or model.accepts(input, resource)) then
                local preferred = input.preferredIds and resource.item and input.preferredIds[resource.item:getID()]
                local list = preferred and result or others
                list[#list + 1] = index
            end
        end
        for _, index in ipairs(others) do result[#result + 1] = index end
        return result
    end
    local function branch(state)
        return {resources = copy(state.resources), steps = copy(state.steps), consumed = copy(state.consumed),
            reserved = copy(state.reserved)}
    end
    local craft, acquire
    acquire = function(state, input, choice, active, scope, done)
        budget = budget - 1
        if budget < 0 or work < 0 then reason = "complex"; return end
        local indices = available(state, input, choice, scope)
        if #indices >= choice.amount then
            local selection = {}
            for i = 1, choice.amount do selection[i] = i end
            while true do
                budget = budget - 1
                if budget < 0 or not spend(#state.resources + #selection) then reason = "complex"; return end
                local nextState = branch(state)
                local selectedIndices, ids, generated = {}, {}, 0
                for _, i in ipairs(selection) do selectedIndices[indices[i]] = true end
                for i, resource in ipairs(state.resources) do
                    if selectedIndices[i] then
                        if resource.item then ids[#ids + 1] = resource.item:getID() else generated = generated + 1 end
                        -- Prerequisites may borrow reserved inputs as tools before this recipe runs.
                        local reserved = copy(nextState.reserved[resource] or {})
                        reserved[scope] = not not input.keep
                        nextState.reserved[resource] = reserved
                    end
                end
                local result = done(nextState, ids, generated)
                if result then return result end
                local i = #selection
                while i > 0 and selection[i] == #indices - #selection + i do i = i - 1 end
                if i == 0 then break end
                selection[i] = selection[i] + 1
                for j = i + 1, #selection do selection[j] = selection[j - 1] + 1 end
            end
        end
        missing = choice.fullType
        for _, recipe in ipairs(producers[choice.fullType] or {}) do
            if not active[recipe.id] then
                local result = craft(state, recipe, active, function(nextState)
                    return acquire(nextState, input, choice, active, scope, done)
                end)
                if result then return result end
            end
        end
    end
    craft = function(state, recipe, active, done)
        budget = budget - 1
        if budget < 0 or work < 0 or #state.steps >= 100 then reason = "complex"; return end
        if active[recipe.id] then return end
        local depth = 0
        for _ in pairs(active) do depth = depth + 1 end
        if depth >= 32 then reason = "complex"; return end
        active = copy(active)
        active[recipe.id] = true
        local scope = {}
        local inputs = copy(recipe.inputs)
        table.sort(inputs, function(a, b)
            -- Protect explicitly chosen tools before planning prerequisites for other slots.
            local first = a.keep and a.preferredIds ~= nil or false
            local second = b.keep and b.preferredIds ~= nil or false
            if first ~= second then return first end
            if a.keep ~= b.keep then return not a.keep end
            return a.index < b.index
        end)
        local function slot(current, index, selected)
            local input = inputs[index]
            if not input then
                if not spend(#current.resources) then return end
                local nextState = branch(current)
                nextState.resources = {}
                for _, resource in ipairs(current.resources) do
                    local reserved = current.reserved[resource]
                    if reserved and reserved[scope] == false then
                        if resource.item then
                            nextState.consumed[resource.fullType] = (nextState.consumed[resource.fullType] or 0) + 1
                        end
                    else
                        nextState.resources[#nextState.resources + 1] = resource
                    end
                    if reserved and reserved[scope] ~= nil then
                        local remaining = copy(reserved)
                        remaining[scope] = nil
                        local hasReservation = false
                        for _ in pairs(remaining) do hasReservation = true; break end
                        nextState.reserved[resource] = hasReservation and remaining or nil
                    end
                end
                for fullType, amount in pairs(recipe.outputs) do
                    if not spend(amount) then return end
                    for i = 1, amount do table.insert(nextState.resources, {fullType = fullType}) end
                end
                table.insert(nextState.steps, {recipe = recipe, inputs = selected})
                return done(nextState)
            end
            local choices, scores = copy(input.choices), {}
            for _, choice in ipairs(choices) do
                scores[choice] = #available(current, input, choice, scope) / choice.amount
                if work < 0 then return end
            end
            table.sort(choices, function(a, b)
                local first, second = scores[a], scores[b]
                if first ~= second then return first > second end
                return a.fullType < b.fullType
            end)
            for _, choice in ipairs(choices) do
                local result = acquire(current, input, choice, active, scope, function(nextState, ids, generated)
                    local nextSelected = copy(selected)
                    nextSelected[input.index] = {fullType = choice.fullType, amount = choice.amount,
                        resourceIds = ids, generated = generated}
                    return slot(nextState, index + 1, nextSelected)
                end)
                if result then return result end
            end
        end
        return slot(state, 1, {})
    end
    local function repeatTarget(state, left)
        if left == 0 then return state end
        return craft(state, model.recipes[target], {}, function(nextState) return repeatTarget(nextState, left - 1) end)
    end
    local result = repeatTarget({resources = copy(model.resources), steps = {}, consumed = {}, reserved = {}}, count)
    if not result then return nil, reason, missing end
    result.reserved = nil
    result.target, result.count = target, count
    result.initialIds = {}
    for _, resource in ipairs(model.resources) do result.initialIds[resource.item:getID()] = true end
    return result
end

return Planner
