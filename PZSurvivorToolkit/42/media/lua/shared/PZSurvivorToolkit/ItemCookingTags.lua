-- Structural cooking capability. Reading tags never constructs inventory items,
-- evaluates recipe callbacks, or tests a player, tools, freshness or quantity.
local Cooking = {}
local catalog
local nativeMilkRecipes = {MakeMilkFromPowderBucket = true, MakeMilkFromPowderBottle = true}

local function milkOutput(recipe)
    -- B42.21 creates milk inside this callback, leaving outputs empty. The
    -- powder is Drainable, so neither a Food-only input check nor declared
    -- output inspection can discover it. Inspect current callback metadata.
    return nativeMilkRecipes[recipe:getName()] and toolkitRecipeOnCreate
        and toolkitRecipeOnCreate(recipe) == "RecipeCodeOnCreate.makeMilkFromPowder"
end

local function food(script)
    return script and script.isItemType and ItemType and ItemType.FOOD
        and script:isItemType(ItemType.FOOD) or false
end

local function cookingRecipe(recipe)
    local action = recipe.getTimedActionScript and recipe:getTimedActionScript()
    local actionName = action and action:getName()
    -- Opening a can only makes its contents accessible. The knife alternative
    -- carries Cooking even though the can is not yet a cooking ingredient.
    if actionName == "OpenTinCan" or actionName == "OpenTinCanWithKnife" then return false end
    if recipe.hasTag and CraftRecipeTag and CraftRecipeTag.COOKING
        and recipe:hasTag(CraftRecipeTag.COOKING) then return true end
    if recipe.getXPAwardCount then
        for i = 0, recipe:getXPAwardCount() - 1 do
            local award = recipe:getXPAward(i)
            local perk = award:getPerk()
            if perk and perk:getId() == "Cooking" and award:getAmount() > 0 then return true end
        end
    end
    return false
end

local function foodOutput(recipe)
    local outputs = recipe:getOutputs()
    for i = 0, outputs:size() - 1 do
        local output = outputs:get(i)
        if output:getResourceType() == ResourceType.Item then
            local choices = output:getPossibleResultItems()
            for j = 0, choices:size() - 1 do
                if food(choices:get(j)) then return true end
            end
        elseif output:getResourceType() == ResourceType.Fluid then
            local choices = output:getPossibleResultFluids()
            for j = 0, choices:size() - 1 do
                local fluid = choices:get(j)
                local properties = fluid:getProperties()
                if not fluid:isPoisonous() and properties
                    and (properties:getHungerChange() < 0 or properties:getThirstChange() < 0) then return true end
            end
        end
    end
    return false
end

local function fullType(recipe, name)
    if not name or name == "" then return end
    if not name:find(".", 1, true) then
        local module = recipe.getModule and recipe:getModule()
        if not module then return end
        return module:getName() .. "." .. name
    end
    return name
end

local function evolvedMeal(recipe, manager)
    local result = manager.getItem and manager:getItem(recipe:getFullResultItem())
    if not food(result) then return false end
    -- EvolvedRecipe also implements fishing chum. A Food implementation alone
    -- does not make its bait additions culinary ingredients.
    return recipe:isCookable()
        or result.getHungerChange and result:getHungerChange() < 0
        or result.getThirstChange and result:getThirstChange() < 0
end

local function indexRecipes()
    local manager = getScriptManager and getScriptManager()
    if not manager or not manager.getAllEvolvedRecipesList or not manager.getAllCraftRecipes then return end
    local evolved = manager.getAllEvolvedRecipesList and manager:getAllEvolvedRecipesList()
    local craft = manager.getAllCraftRecipes and manager:getAllCraftRecipes()
    if not evolved or not craft then return end
    local evolvedCount, craftCount = evolved and evolved:size() or 0, craft and craft:size() or 0
    if catalog and catalog.manager == manager and catalog.evolved == evolved and catalog.craft == craft
        and catalog.bridge == toolkitRecipeOnCreate
        and catalog.evolvedCount == evolvedCount and catalog.craftCount == craftCount then return catalog end
    local byType, fluids = {}, {}
    if evolved then
        for i = 0, evolvedCount - 1 do
            local recipe = evolved:get(i)
            if evolvedMeal(recipe, manager) then
                local choices = recipe:getPossibleItems()
                for j = 0, choices:size() - 1 do
                    local choice = choices:get(j)
                    if choice:getUse() > 0 then byType[choice:getFullType()] = true end
                end
                -- Bread is an ingredient in a sandwich; an empty soup pot is not.
                local base = fullType(recipe, recipe:getBaseItem())
                if base and manager.getItem and food(manager:getItem(base)) then byType[base] = true end
            end
        end
    end
    if craft then
        for i = 0, craftCount - 1 do
            local recipe = craft:get(i)
            -- Cooking category also contains emptying, packing and nonfood
            -- crafts. Require native cooking semantics and an actual food result.
            local milk = milkOutput(recipe)
            if cookingRecipe(recipe) and (foodOutput(recipe) or milk) then
                local inputs = recipe:getInputs()
                for j = 0, inputs:size() - 1 do
                    local input = inputs:get(j)
                    if not input:isKeep() and not input:isApplyOnTick() then
                        if input:getResourceType() == ResourceType.Item and not input:isTool() then
                            local choices = input:getPossibleInputItems()
                            for k = 0, choices:size() - 1 do
                                local script = choices:get(k)
                                -- mode:destroy is used for real food in jarring.
                                -- FOOD excludes consumed jars, lids, utensils and fuel.
                                if food(script) or milk and script:getFullName() == "Base.AnimalMilkPowder" then
                                    byType[script:getFullName()] = true
                                end
                            end
                        elseif input:getResourceType() == ResourceType.Fluid then
                            fluids[#fluids + 1] = input
                        end
                    end
                end
            end
        end
    end
    catalog = {manager = manager, evolved = evolved, craft = craft, bridge = toolkitRecipeOnCreate,
        evolvedCount = evolvedCount, craftCount = craftCount, byType = byType, fluids = fluids}
    return catalog
end

local function initialMatches(input, choices, random)
    local count, allowed, primary, highest = 0, 0, nil, -1
    for i = 0, choices:size() - 1 do
        local entry = choices:get(i)
        local percentage = entry:getPercentage()
        if percentage > 0 then
            local fluid = entry:getFluid()
            if not fluid then return nil end
            count = count + 1
            if input:containsFluid(fluid) then allowed = allowed + 1 end
            if percentage > highest then primary, highest = fluid, percentage end
        end
    end
    if count == 0 then return false end
    if random then
        if allowed == count or input:isFluidAnything() then return true end
        if allowed == 0 then return false end
        return nil
    end
    if input:isFluidExact() then return count == 1 and allowed == 1 end
    if input:isFluidMixture() then return count == allowed end
    if input:isFluidPrimary() then return input:containsFluid(primary) end
    return input:isFluidAnything()
end

-- A supplied item supplies authoritative current contents. Script-only callers
-- use declared initial fluid types; this is capability, not current availability.
-- nil means native metadata is unavailable or random defaults disagree.
function Cooking.read(script, item, noInitialFluids)
    script = script or item and item.getScriptItem and item:getScriptItem()
    if not script or not script.getFullName then return nil end
    local index = indexRecipes()
    if not index then return nil end
    if index.byType[script:getFullName()] then return true end
    -- Old warehouse rows did not capture their mutable fluid contents. Their
    -- current state cannot be inferred from the factory-filled script default.
    if noInitialFluids and not item then return false end
    if #index.fluids == 0 then return false end
    if item and item.getFluidContainer then
        local container = item:getFluidContainer()
        if not container or container:isEmpty() then return false end
        for _, input in ipairs(index.fluids) do
            -- The native predicate accepts a FluidContainer, never InventoryItem
            -- or a snapshot proxy, and does not execute Lua recipe callbacks.
            if input:isFluidMatch(container) then return true end
        end
        return false
    end
    if not script.getComponentScriptFor or not ComponentType or not ComponentType.FluidContainer then return false end
    local component = script:getComponentScriptFor(ComponentType.FluidContainer)
    if not component then return false end
    local choices = component:getInitialFluids()
    if not choices or component:getCapacity() <= 0 then return false end
    -- getInitialAmount() draws from the game RNG for ranged defaults. Never use
    -- it here, and never create a temporary FluidContainer to inspect defaults.
    local unknown = false
    for _, input in ipairs(index.fluids) do
        local matches = initialMatches(input, choices, component:isInitialFluidsIsRandom())
        if matches then return true end
        unknown = unknown or matches == nil
    end
    if unknown then return nil end
    return false
end

function Cooking.invalidate() catalog = nil end
if Events and Events.OnGameBoot then Events.OnGameBoot.Add(Cooking.invalidate) end

return Cooking
