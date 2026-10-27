local Disassembly = {}

-- B42.21 has no dismantling flag. These are the native dismantling recipes,
-- including the no-XP blade/handle recipes; their animation is also used by crafts.
local nativeRecipes = {
    DismantleElectronics = true, DismantleMiscElectronics = true,
    DismantleElectronicsDevice = true, DismantlePowerBar = true,
    DismantleImprovisedLighter = true, DismantleBlade = true,
    DismantleLongImplement = true, DismantleShortImplement = true,
    ReclaimFromSpear = true,
}

local skillTags = {
    Electricity = "electrical", Woodwork = "carpentry", Mechanics = "mechanics",
    MetalWelding = "welding", Blacksmith = "metalworking", Masonry = "masonry",
    Tailoring = "tailoring", Carving = "carving", FlintKnapping = "knapping",
    Pottery = "pottery", Glassmaking = "glassmaking",
}

local catalog, sprites
local function skill(perk)
    return perk and perk.getId and skillTags[perk:getId()] or nil
end

local function awards(recipe)
    local tags = {}
    if recipe.getXPAwardCount then
        for i = 0, recipe:getXPAwardCount() - 1 do
            local award = recipe:getXPAward(i)
            local id = award:getAmount() > 0 and skill(award:getPerk())
            if id then tags[id] = true end
        end
    elseif recipe.hasXpPerk and recipe:hasXpPerk() then
        local id = skill(recipe:getXpPerk())
        if id then tags[id] = true end
    end
    return tags
end

local function add(index, fullType, entry)
    if not fullType then return end
    local entries = index[fullType] or {}
    index[fullType] = entries
    entries[#entries + 1] = entry
end

local function craftEntry(recipe)
    if not nativeRecipes[recipe:getName()] then return end
    -- An overridden callback can impose arbitrary item predicates. Reading tags
    -- must not execute it (or any item creation/recipe callback).
    if not toolkitRecipeHasItemTest or toolkitRecipeHasItemTest(recipe) ~= false then return end
    local inputs, subject = recipe:getInputs(), nil
    for i = 0, inputs:size() - 1 do
        local input = inputs:get(i)
        if input:getResourceType() ~= ResourceType.Item then return end
        if not input:isKeep() then
            if subject or input:getIntAmount() ~= 1
                or input:hasConsumeFromItem() or input:hasCreateToItem()
                or input:isApplyOnTick() or input:isReplace() then return end
            subject = input
        end
    end
    if subject then return {input = subject, skills = awards(recipe)} end
end

local function legacyEntry(recipe)
    -- General legacy Recipe hides its Lua predicates and XP callback in B42.21.
    -- Only the native generated MovableRecipe has inspectable validity/XP data.
    if not recipe.hasXpPerk or not recipe.isValid or not recipe:isValid() then return end
    -- This is the exact name criterion used by RecipeManager.getDismantleRecipeFor.
    -- Index its consumed source once, rather than calling that catalog scan per item.
    local name = recipe:getOriginalname() or recipe:getName()
    if not name or not string.lower(name):find("^dismantle") then return end
    local sources, subject = recipe:getSource(), nil
    for i = 0, sources:size() - 1 do
        local source = sources:get(i)
        if not source:isKeep() then
            if subject or source:getCount() ~= 1 or source:getUse() > 0 then return end
            subject = source
        end
    end
    if subject then return {source = subject, skills = awards(recipe)} end
end

local function indexRecipes()
    local manager = getScriptManager and getScriptManager()
    if not manager then return {} end
    local craft = manager.getAllCraftRecipes and manager:getAllCraftRecipes()
    local legacy = manager.getAllRecipes and manager:getAllRecipes()
    local craftCount, legacyCount = craft and craft:size() or 0, legacy and legacy:size() or 0
    if catalog and catalog.manager == manager and catalog.bridge == toolkitRecipeHasItemTest
        and catalog.craft == craft and catalog.legacy == legacy
        and catalog.craftCount == craftCount and catalog.legacyCount == legacyCount then return catalog.byType end
    local byType = {}
    if craft then
        for i = 0, craftCount - 1 do
            local entry = craftEntry(craft:get(i))
            if entry then
                local choices = entry.input:getPossibleInputItems()
                for j = 0, choices:size() - 1 do
                    local script = choices:get(j)
                    if not entry.input:isUsesPartialItem(script) then add(byType, script:getFullName(), entry) end
                end
            end
        end
    end
    if legacy then
        for i = 0, legacyCount - 1 do
            local entry = legacyEntry(legacy:get(i))
            if entry then
                local choices = entry.source:getItems()
                for j = 0, choices:size() - 1 do add(byType, choices:get(j), entry) end
            end
        end
    end
    catalog = {manager = manager, bridge = toolkitRecipeHasItemTest, craft = craft, legacy = legacy,
        craftCount = craftCount, legacyCount = legacyCount, byType = byType}
    return byType
end

local predicates = {
    "doesItemPassClothingTypeStatusTests",
    "doesItemPassSharpnessStatusTests", "doesItemPassDamageStatusTests",
    "doesItemPassIsOrNotEmptyAndFullTests", "doesItemPassFoodAndCookingTests",
}

local function allowed(entry, item)
    if not item then return true end
    if entry.input then
        if entry.input.doesItemPassRoutineStatusTests
            and not entry.input:doesItemPassRoutineStatusTests(item, nil) then return false end
        for _, method in ipairs(predicates) do
            if entry.input[method] and not entry.input[method](entry.input, item) then return false end
        end
    elseif item.isBroken and item:isBroken() then
        -- Legacy Recipe exposes no pure per-item predicate API in B42.21.
        return false
    end
    return true
end

local function furniture(script, item)
    local name = item and item.getWorldSprite and item:getWorldSprite()
    if not name or name == "" then name = script.getWorldObjectSprite and script:getWorldObjectSprite() end
    if not name or name == "" or not getSprite then return end
    local sprite = getSprite(tostring(name))
    if not sprite then return end
    local props = sprite:getProperties()
    local material = props and props:has("Material") and props:get("Material")
    if not props or not props:has("CanScrap") or not material or material == "Undefined" then return end
    -- This is a native shared module, loaded before OnGameBoot in SP and Host.
    -- Ordinary item/offline lookups do not need the moveables subsystem.
    if not ISMoveableDefinitions then require "Moveables/ISMoveableDefinitions" end
    local definitions = ISMoveableDefinitions and ISMoveableDefinitions:getInstance()
    if not definitions or not definitions.isScrapDefinitionValid then return end
    sprites = sprites or {}
    local cached = sprites[name]
    if cached and cached.sprite == sprite and cached.definitions == definitions then return cached.result end
    local result
    if definitions.isScrapDefinitionValid(material) then
        local definition = definitions.getScrapDefinition(material)
        result = {skills = {}}
        local id = definition and skill(definition.perk)
        if id then result.skills[id] = true end
    end
    sprites[name] = {sprite = sprite, definitions = definitions, result = result}
    return result
end

-- The boolean means that this item is the dismantled subject. Skill tags come
-- only from awarded XP, never the recipe's category, tools or skill requirements.
function Disassembly.read(script, item)
    script = script or item and item.getScriptItem and item:getScriptItem()
    if not script or not script.getFullName then return false, {} end
    local found, skills = false, {}
    for _, entry in ipairs(indexRecipes()[script:getFullName()] or {}) do
        if allowed(entry, item) then
            found = true
            for id in pairs(entry.skills) do skills[id] = true end
        end
    end
    local movable = furniture(script, item)
    if movable then
        found = true
        for id in pairs(movable.skills) do skills[id] = true end
    end
    local result = {}
    for id in pairs(skills) do result[#result + 1] = id end
    table.sort(result)
    return found, result
end

function Disassembly.invalidate()
    catalog, sprites = nil, nil
end

if Events and Events.OnGameBoot then Events.OnGameBoot.Add(Disassembly.invalidate) end

return Disassembly
