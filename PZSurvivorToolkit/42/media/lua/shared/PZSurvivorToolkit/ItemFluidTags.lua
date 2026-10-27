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
    if not script or not script.getComponentScriptFor
        or not ComponentType or not ComponentType.FluidContainer then return nil, {}, nil end
    local component = script:getComponentScriptFor(ComponentType.FluidContainer)
    if not component then return nil, {}, false end
    return nil, initialPossibilities(component), true
end

return FluidTags
