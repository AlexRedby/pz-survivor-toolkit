-- Pure fetch planning. Inputs contain native base-unit demand, tool and exclusive flags,
-- and ordered full types. Access and each box contain candidates from QuartermasterCraftUnits:
-- { input=<index>, uses=<current uses or ItemCount 1>, scale=<relative scale>,
--   partial=<leftover uses reusable>, fullType=<string> }.
LootSorter = LootSorter or {}
LootSorter.craftPlan = LootSorter.craftPlan or {}

local EPSILON = 0.00001 -- native CraftRecipeData satisfaction tolerance

local function positive(value)
    return type(value) == "number" and value == value and value > 0 and value < math.huge
end

function LootSorter.craftPlan.plan(inputs, qty, access, boxes)
    qty = positive(qty) and math.max(1, math.floor(qty)) or 1
    local byInput, selected = {}, {}
    for idx in ipairs(inputs) do byInput[idx] = {} end
    local function add(candidate, box, item)
        if type(candidate) ~= "table" or not byInput[candidate.input]
            or not positive(candidate.uses) or not positive(candidate.scale) then return end
        local states = byInput[candidate.input]
        states[#states + 1] = { candidate = candidate, remaining = candidate.uses,
            box = box, item = item }
    end
    for _, candidate in ipairs(access or {}) do add(candidate) end
    for bi, contents in ipairs(boxes or {}) do
        for ii, candidate in ipairs(contents) do add(candidate, bi, ii) end
    end

    local shortfall = {}
    for idx, input in ipairs(inputs) do
        local states, demand = byInput[idx], positive(input.per) and input.per or 1
        local types, seen, present = {}, {}, {}
        for _, state in ipairs(states) do present[state.candidate.fullType] = true end
        local function addType(fullType)
            if fullType and present[fullType] and not seen[fullType] then
                seen[fullType] = true
                types[#types + 1] = fullType
            end
        end
        for _, fullType in ipairs(input.types or {}) do addType(fullType) end
        for _, state in ipairs(states) do addType(state.candidate.fullType) end

        -- Try without mutation: exclusive inputs may use one alternative type per craft.
        -- Already accessible items, including earlier selected rolls, always get first credit.
        local function attempt(fullType)
            local need, ordinary, steps, firstBox = demand, 0, {}, math.huge
            for pass = 1, 2 do
                for _, state in ipairs(states) do
                    local accessible = not state.box or state.selected == true
                    if (pass == 1) == accessible and state.remaining > EPSILON
                        and (not fullType or state.candidate.fullType == fullType) then
                        -- Native caps raw/relativeScale at raw uses (also for scales below one).
                        local scale = math.max(1, state.candidate.scale)
                        local take = math.min(need, state.remaining / scale)
                        if take > EPSILON then
                            steps[#steps + 1] = { state = state, raw = take * scale }
                            need = need - take
                            if accessible then ordinary = ordinary + take
                            else firstBox = math.min(firstBox, state.box) end
                            if need <= EPSILON then return { need = 0, steps = steps,
                                ordinary = ordinary, firstBox = firstBox } end
                        end
                    end
                end
            end
            return { need = need, steps = steps, ordinary = ordinary, firstBox = firstBox }
        end

        shortfall[idx] = 0
        for _ = 1, input.tool and 1 or qty do
            local best
            if input.exclusive then
                for _, fullType in ipairs(types) do
                    local trial = attempt(fullType)
                    if not best or trial.need < best.need - EPSILON
                        or (math.abs(trial.need - best.need) <= EPSILON
                            and (trial.ordinary > best.ordinary + EPSILON
                                or (math.abs(trial.ordinary - best.ordinary) <= EPSILON
                                    and trial.firstBox < best.firstBox))) then best = trial end
                end
            else best = attempt() end
            if not best then best = { need = demand, steps = {} } end
            shortfall[idx] = shortfall[idx] + best.need
            for _, step in ipairs(best.steps) do
                local state = step.state
                state.remaining = state.candidate.partial and math.max(0, state.remaining - step.raw) or 0
                if state.box then
                    state.selected = true
                    selected[state.box] = selected[state.box] or {}
                    selected[state.box][state.item] = true
                end
            end
        end
    end

    local trips = {}
    for bi, contents in ipairs(boxes or {}) do
        local picks = {}
        for ii in ipairs(contents) do
            if selected[bi] and selected[bi][ii] then picks[#picks + 1] = ii end
        end
        if #picks > 0 then trips[#trips + 1] = { box = bi, picks = picks } end
    end
    return { trips = trips, shortfall = shortfall }
end
