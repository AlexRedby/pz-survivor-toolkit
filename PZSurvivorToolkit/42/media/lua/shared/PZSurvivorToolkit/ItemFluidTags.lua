-- Fluid roles describe contents, never whether drinking them is safe. In
-- particular, TaintedWater is a Beverage and medical alcohol is not one.
local FluidTags = {}

local function categoriesAvailable()
    return FluidCategory and FluidCategory.Beverage and FluidCategory.Alcoholic
end

local function fluidRole(fluid)
    if not fluid or not fluid.isCategory or not categoriesAvailable() then return nil end
    if not fluid:isCategory(FluidCategory.Beverage) then return "none" end
    return fluid:isCategory(FluidCategory.Alcoholic) and "alcoholic" or "beverage"
end

local function currentRole(container)
    if not container.isEmpty then return nil end
    if container:isEmpty() then return "none" end
    if not container.isCategory or not categoriesAvailable() then return nil end
    -- Native isCategory is existential, so ordinary water/juice reads do not
    -- need to inspect the fluid registry. Two positive categories alone would
    -- incorrectly call a mixture of water and medical alcohol alcoholic.
    if not container:isCategory(FluidCategory.Beverage) then return "none" end
    if not container:isCategory(FluidCategory.Alcoholic) then return "beverage" end
    if not Fluid or not Fluid.getAllFluids or not container.getSpecificFluidAmount then return nil end
    if Fluid.FluidsInitialized and not Fluid.FluidsInitialized() then return nil end
    local fluids = Fluid.getAllFluids()
    if not fluids then return nil end
    for i = 0, fluids:size() - 1 do
        local fluid = fluids:get(i)
        if fluidRole(fluid) == "alcoholic" and container:getSpecificFluidAmount(fluid) > 0 then
            return "alcoholic"
        end
    end
    -- Do not cache registry roles: native script reloads refill the same list
    -- and can change categories without changing its identity or size.
    return "beverage"
end

local function initialPossibilities(component)
    -- An empty state remains possible, including ranged InitialAmount=0..N.
    -- Its native getter can consume RNG and must never be queried for tags.
    local possible, present = {"none"}, {none = true}
    if not component.getInitialFluids or not component.getCapacity
        or not component.isInitialFluidsIsRandom then return possible end
    if component:getCapacity() <= 0 then return possible end
    local choices = component:getInitialFluids()
    if not choices then return possible end
    local random, mixed = component:isInitialFluidsIsRandom(), "none"
    for i = 0, choices:size() - 1 do
        local choice = choices:get(i)
        if choice:getPercentage() > 0 then
            local role = fluidRole(choice:getFluid())
            if role then
                if random then present[role] = true
                elseif role == "alcoholic" or role == "beverage" and mixed == "none" then mixed = role end
            end
        end
    end
    if not random then present[mixed] = true end
    -- Stable ordering also avoids random-choice order leaking into previews.
    for _, role in ipairs({"beverage", "alcoholic"}) do
        if present[role] then possible[#possible + 1] = role end
    end
    return possible
end

local function stateForRole(role)
    if not role then return {} end
    return {beverage = role ~= "none", alcoholic = role == "alcoholic"}
end

local function emptyState()
    return {beverage = false, alcoholic = false, disinfectant = false, fuel = false}
end

-- These fields are read together so a script preview never combines the
-- beverage role of one random fluid with the disinfectant/fuel of another.
local function currentUsage(container)
    local state = stateForRole(currentRole(container))
    if container.isEmpty and container:isEmpty() then return emptyState() end
    if container.getAmount then
        local amount = container:getAmount()
        if type(amount) == "number" then
            if amount <= 0 then return emptyState() end
            if amount <= 0.15 then state.disinfectant = false
            elseif container.getProperties then
                local properties = container:getProperties()
                local alcohol = properties and properties.getAlcohol and properties:getAlcohol()
                if type(alcohol) == "number" then
                    state.disinfectant = alcohol / amount + 0.001 >= 0.4
                end
            end
        end
    end
    if container.isCategory and FluidCategory and FluidCategory.Fuel then
        state.fuel = container:isCategory(FluidCategory.Fuel)
    end
    return state
end

local function initialUsage(component)
    local result = {emptyState()}
    if not component.getInitialFluids or not component.getCapacity
        or not component.isInitialFluidsIsRandom then return result end
    local capacity, choices = component:getCapacity(), component:getInitialFluids()
    if type(capacity) ~= "number" or capacity <= 0 or not choices then return result end
    local random, mixtures = component:isInitialFluidsIsRandom(), {}
    local mixed = {role = "none", fuel = false, alcohol = 0, percentage = 0, known = true}
    local function addFluid(mixture, fluid, percentage)
        local role = fluidRole(fluid)
        if role == "alcoholic" or role == "beverage" and mixture.role == "none" then mixture.role = role end
        if not role then mixture.role = nil end
        if fluid and fluid.isCategory and FluidCategory and FluidCategory.Fuel then
            if fluid:isCategory(FluidCategory.Fuel) then mixture.fuel = true end
        elseif mixture.fuel ~= true then mixture.fuel = nil end
        local properties = fluid and fluid.getProperties and fluid:getProperties()
        local alcohol = properties and properties.getAlcohol and properties:getAlcohol()
        if type(alcohol) == "number" then mixture.alcohol = mixture.alcohol + alcohol * percentage
        else mixture.known = false end
        mixture.percentage = mixture.percentage + percentage
    end
    for i = 0, choices:size() - 1 do
        local choice = choices:get(i)
        local percentage = choice:getPercentage()
        if percentage > 0 then
            if random then
                local mixture = {role = "none", fuel = false, alcohol = 0, percentage = 0, known = true}
                addFluid(mixture, choice:getFluid(), percentage)
                mixtures[#mixtures + 1] = mixture
            else addFluid(mixed, choice:getFluid(), percentage) end
        end
    end
    if not random and mixed.percentage > 0 then mixtures[1] = mixed end
    local seen = {["false:false:false:false"] = true}
    local function add(state)
        local key = tostring(state.beverage) .. ":" .. tostring(state.alcoholic)
            .. ":" .. tostring(state.disinfectant) .. ":" .. tostring(state.fuel)
        if not seen[key] then seen[key], result[#result + 1] = true, state end
    end
    for _, mixture in ipairs(mixtures) do
        local state = stateForRole(mixture.role)
        state.fuel, state.disinfectant = mixture.fuel, false
        add(state)
        -- getInitialAmount can draw RNG and cannot establish a current amount.
        -- Both small and usable quantities are possible within the capacity.
        if capacity > 0.15 and mixture.known and mixture.alcohol / mixture.percentage + 0.001 >= 0.4 then
            local usable = stateForRole(mixture.role)
            usable.fuel, usable.disinfectant = mixture.fuel, true
            add(usable)
        end
    end
    return result
end

local function componentFor(script)
    if not script or not script.getComponentScriptFor
        or not ComponentType or not ComponentType.FluidContainer then return nil, nil end
    local component = script:getComponentScriptFor(ComponentType.FluidContainer)
    return component, component ~= nil
end

-- Joint fluid usage evidence for ItemUsageTags. Missing live metadata remains
-- unknown; script factory contents are only possibilities, never current facts.
function FluidTags.usage(script, item)
    if item then
        if not item.getFluidContainer then return {}, {}, nil end
        local container = item:getFluidContainer()
        if not container then return {}, {}, false end
        local state = currentUsage(container)
        return state, {state}, true
    end
    local component, isFluid = componentFor(script)
    if not component then return {}, {}, isFluid end
    return {}, initialUsage(component), true
end

-- Returns current state, declared preview possibilities, and isFluid.
-- Current state is one of none/beverage/alcoholic only for a real supplied
-- item. nil preserves unknown data and legacy roles of nonfluid items.
-- Script previews inspect declared initial fluids, without constructing an
-- InventoryItem/FluidContainer, invoking callbacks or drawing game RNG.
function FluidTags.read(script, item)
    if item and item.getFluidContainer then
        local container = item:getFluidContainer()
        if not container then return nil, {}, false end
        local role = currentRole(container)
        return role, role and {role} or {}, true
    end
    script = script or item and item.getScriptItem and item:getScriptItem()
    local component, isFluid = componentFor(script)
    if not component then return nil, {}, isFluid end
    return nil, initialPossibilities(component), true
end

return FluidTags
