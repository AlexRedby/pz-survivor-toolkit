-- Native furnace subjects. Classification reads recipe metadata and pure input
-- status predicates; it never creates items or executes recipe Lua callbacks.
local Smelting = {}
local catalog
local nativeRecipes = {
    ExtractIronBloom = {2, 2},
    SmeltCopperOre = {2, 2},
    ExtractIronFromIronBloom = {4, 4},
    ExtractIronFromBloom = {2, 4},
    ExtractIronFromIronOre = {4, 4, "smeltIronOrSteelIngot"},
    ExtractIronFromSmallerItems = {4, 4},
    ExtractSteelFromSmallerIronItems = {5, 5},
    MeltSand = {3, 5},
    MeltGlass = {3, 5},
}
for _, size in ipairs({"Large", "Medium", "MediumPlus", "Small"}) do
    nativeRecipes["ExtractIronFrom" .. size .. "Item"] = {4, 4}
    nativeRecipes["ExtractSteelFrom" .. size .. "Item"] = {4, 4}
    nativeRecipes["ExtractSteelFrom" .. size .. "IronItem"] = {5, 5}
end
for _, size in ipairs({"Large", "Medium", "MediumPlus", "Small", "Smaller"}) do
    local handler = "smeltIronOrSteel" .. (size == "Smaller" and "Small" or size)
    for _, metal in ipairs({"Iron", "Steel"}) do
        nativeRecipes["Smelt" .. size .. metal .. "Item"] = {4, 4, handler}
    end
end

local function subject(recipe)
    local definition = nativeRecipes[recipe:getName()]
    -- Mod overrides may keep the name, callback and input count while changing
    -- the role at this position. Their semantics are unknown to this reader.
    -- Mod items can still participate through the vanilla recipe's tag choices.
    if not definition or not recipe.isVanilla or recipe:isVanilla() ~= true
        or toolkitRecipeHasItemTest(recipe) ~= false then return end
    local expected = definition[3] and "RecipeCodeOnCreate." .. definition[3] or nil
    if toolkitRecipeOnCreate(recipe) ~= expected then return end
    local inputs = recipe:getInputs()
    if inputs:size() ~= definition[2] then return end
    -- Native recipes mix the material with fuel, flux, tools, firestarters and
    -- sometimes a consumed crucible. Only this verified input is transformed.
    local input = inputs:get(definition[1] - 1)
    if input:getResourceType() ~= ResourceType.Item or input:isKeep() or input:isTool()
        or input:isApplyOnTick() or input:hasConsumeFromItem() or input:hasCreateToItem()
        or input:isReplace() or input:getIntAmount() <= 0 then return end
    return input
end

local function indexRecipes()
    local manager = getScriptManager and getScriptManager()
    if not manager or not manager.getAllCraftRecipes
        or not toolkitRecipeOnCreate or not toolkitRecipeHasItemTest then return end
    local recipes = manager:getAllCraftRecipes()
    if not recipes then return end
    local count = recipes:size()
    if catalog and catalog.manager == manager and catalog.recipes == recipes and catalog.count == count
        and catalog.create == toolkitRecipeOnCreate and catalog.test == toolkitRecipeHasItemTest then
        return catalog.byType
    end
    local byType, ready, found = {}, count > 0, false
    for i = 0, count - 1 do
        local input = subject(recipes:get(i))
        if input then
            local choices = input:getPossibleInputItems()
            -- Recipe objects can exist before their tag choices are resolved.
            -- Never freeze an empty early catalog for the rest of the session.
            if not choices or choices:size() == 0 then ready = false
            else
                found = true
                for j = 0, choices:size() - 1 do
                    local script = choices:get(j)
                    local name = script:getFullName()
                    local entries = byType[name] or {}
                    byType[name] = entries
                    entries[#entries + 1] = {input = input, partial = input:isUsesPartialItem(script)}
                end
            end
        end
    end
    if ready and found then
        catalog = {manager = manager, recipes = recipes, count = count,
            create = toolkitRecipeOnCreate, test = toolkitRecipeHasItemTest, byType = byType}
    end
    return byType
end

local predicates = {
    "doesItemPassClothingTypeStatusTests", "doesItemPassSharpnessStatusTests",
    "doesItemPassDamageStatusTests", "doesItemPassIsOrNotEmptyAndFullTests",
    "doesItemPassFoodAndCookingTests",
}
local function allowed(input, item)
    if input.doesItemPassRoutineStatusTests and not input:doesItemPassRoutineStatusTests(item, nil) then
        return false
    end
    for _, method in ipairs(predicates) do
        if input[method] and not input[method](input, item) then return false end
    end
    return true
end

-- true means a material subject, independent of the available furnace, skills,
-- other supplies or required stack quantity. false means all recognized paths
-- reject this physical item's state. nil preserves unrelated imported families
-- and arbitrary mod recipes. Partial drainable subjects (native sandbags) need
-- remaining material; script previews expose both empty/nonempty alternatives.
function Smelting.read(script, item)
    script = script or item and item.getScriptItem and item:getScriptItem()
    if not script or not script.getFullName then return nil end
    local index = indexRecipes()
    local entries = index and index[script:getFullName()]
    if not entries then return nil end
    local unknown = false
    for _, entry in ipairs(entries) do
        if not item then
            if not entry.partial then return true end
            unknown = true
        elseif allowed(entry.input, item) then
            if not entry.partial then return true end
            if item.getCurrentUses then
                if item:getCurrentUses() > 0 then return true end
            else unknown = true end
        end
    end
    if unknown then
        if not item then return nil, {false, true} end
        return nil
    end
    return false
end

function Smelting.invalidate() catalog = nil end
if Events and Events.OnGameBoot then Events.OnGameBoot.Add(Smelting.invalidate) end

return Smelting
