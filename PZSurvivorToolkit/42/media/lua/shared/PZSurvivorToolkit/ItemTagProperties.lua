-- Read physical capabilities without creating items or changing native definitions.
local Properties = {}

local function slot(value)
    return value ~= nil and value ~= false and tostring(value) ~= ""
end

local function wearable(script, item)
    local source = item or script
    if not source then return nil end
    if source.getBodyLocation and slot(source:getBodyLocation()) then return true end
    if source.hasTag and ItemTag and ItemTag.WEARABLE and source:hasTag(ItemTag.WEARABLE) then return true end
    if item then
        if item.canBeEquipped and slot(item:canBeEquipped()) then return true end
        if item.canBeEquipped and item.getBodyLocation then return false end
    elseif toolkitScriptCanBeEquipped then
        -- Item.canBeEquipped has no Lua getter. The optional Java helper reads
        -- that field directly, without InstanceItem, random draws or OnCreate.
        return toolkitScriptCanBeEquipped(script)
    end
    -- Without complete metadata, retain the imported classification.
    return nil
end

local function hasStorage(sprite)
    local properties = sprite and sprite:getProperties()
    return properties and properties:has("container") or false
end

local function storageFurniture(script, item)
    local name = item and item.getWorldSprite and item:getWorldSprite()
    if not slot(name) and script and script.getWorldObjectSprite then name = script:getWorldObjectSprite() end
    if not slot(name) or not getSprite then return false end
    local sprite = getSprite(tostring(name))
    if not sprite then return false end
    if hasStorage(sprite) then return true end
    -- Each carried part of a multi-tile cupboard belongs to the same furniture.
    local grid = sprite:getSpriteGrid()
    if grid then
        for i = 0, grid:getSpriteCount() - 1 do
            if hasStorage(grid:getSpriteFromIndex(i)) then return true end
        end
    end
    return false
end

function Properties.read(script, item)
    local worn = wearable(script, item)
    local container
    if item and item.IsInventoryContainer then
        container = item:IsInventoryContainer()
    elseif script and script.isItemType and ItemType and ItemType.CONTAINER then
        container = script:isItemType(ItemType.CONTAINER)
    end
    local fluid
    if item and item.isFluidContainer then
        fluid = item:isFluidContainer()
    elseif item and item.getFluidContainer then
        fluid = item:getFluidContainer() ~= nil
    elseif script and script.containsComponent and ComponentType and ComponentType.FluidContainer then
        fluid = script:containsComponent(ComponentType.FluidContainer)
    end
    if container then return worn, true, false, fluid end
    local furniture = storageFurniture(script, item)
    return worn, furniture or fluid == true, furniture, fluid
end

local function itemType(script, item, method, kind)
    if item and item[method] then return item[method](item) end
    if script and script.isItemType and ItemType and ItemType[kind] then
        return script:isItemType(ItemType[kind])
    end
end

local function tagged(source, id)
    return source.hasTag and ItemTag and ItemTag[id] and source:hasTag(ItemTag[id]) or false
end

local function negative(source, method)
    return source[method] and source[method](source) < 0
end

-- Native Eat/Open and Eat capability. Player hunger, tools and recipe knowledge
-- do not change an item's role; Smoke/Drink and merely being Food are not Eat.
function Properties.edible(script, item)
    local food = itemType(script, item, "IsFood", "FOOD")
    if not food then return food end
    if not script or not script.isCantEat then return nil end
    local source = item or script
    local opening = source.getOpeningRecipe and source:getOpeningRecipe()
    if opening and opening ~= "" and getScriptManager then
        local manager = getScriptManager()
        if manager and manager.getCraftRecipe and manager:getCraftRecipe(opening) then return true end
    end
    if script:isCantEat() then return false end
    local eatMenu
    if item and item.getCustomMenuOption then
        local menu = item:getCustomMenuOption()
        eatMenu = menu == nil or getText ~= nil and menu == getText("ContextMenu_Eat")
    elseif toolkitScriptHasEatMenu then
        eatMenu = toolkitScriptHasEatMenu(script)
    end
    if eatMenu ~= true then return eatMenu end
    local hungerMethod = item and "getHungChange" or "getHungerChange"
    local hunger = source[hungerMethod] and source[hungerMethod](source)
    if type(hunger) ~= "number" then return nil end
    return hunger < 0
end

-- Read/View means native content, not generic Inspect or a disabled Read option.
-- Character traits, darkness and recent reading do not change the item's role.
function Properties.reading(script, item)
    local source = item or script
    if not source then return nil end
    if itemType(script, item, "IsMap", "MAP") then return true, false, false end
    local literature = itemType(script, item, "IsLiterature", "LITERATURE")
    if literature == false then return false, false, false end
    if not literature then return nil end

    local writeable
    if item and item.canBeWrite then writeable = item:canBeWrite()
    elseif not item and toolkitScriptCanBeWrite then writeable = toolkitScriptCanBeWrite(script) end
    if writeable then
        -- A script describes blank paper; only a physical instance has written pages.
        return item ~= nil and item.isEmptyPages ~= nil and not item:isEmptyPages(), false, true
    end
    if tagged(source, "UNINTERESTING") then return false, false, writeable end
    -- CanBeWrite is a script field without a Lua getter. Missing bridge metadata
    -- must not turn every notebook into a book; retain the category fallback.
    if writeable == nil then return nil, false, nil end

    local printed = item and item.hasModData and item:hasModData() and item:getModData().printMedia
    local definition = script or source
    local recipes = source.getLearnedRecipes and source:getLearnedRecipes()
    local skill = source.getSkillTrained and source:getSkillTrained()
    -- OC can replace even the script's Literature display label. Classify by
    -- content and recreation effects; keep study categories for OnCreate lessons.
    local category = definition.getDisplayCategory and definition:getDisplayCategory()
    local study = category == "RecipeResource" or category == "SkillBook"
        or category == "literatureRecipe" or category == "literatureExperience"
    local recreational = not printed and not tagged(source, "PICTURE")
        and not study
        and not slot(skill) and (not recipes or recipes:size() == 0)
        and (negative(definition, "getBoredomChange") or negative(definition, "getStressChange")
            or negative(definition, "getUnhappyChange")) or false
    return true, recreational, false
end

function Properties.food(script, item)
    if not itemType(script, item, "IsFood", "FOOD") then return nil end
    local source = item or script
    local freshMethod = item and "getOffAge" or "getDaysFresh"
    local rottenMethod = item and "getOffAgeMax" or "getDaysTotallyRotten"
    if not source[freshMethod] or not source[rottenMethod] then return nil end
    local freshUntil, rottenAt = source[freshMethod](source), source[rottenMethod](source)
    if type(freshUntil) ~= "number" or type(rottenAt) ~= "number" then return nil end
    -- Native no-expiry sentinel; zero is a real deadline (e.g. RatKing).
    local never = 1000000000
    local states = {}
    if freshUntil > 0 and freshUntil < never then states[#states + 1] = "fresh" end
    if rottenAt < never and rottenAt > freshUntil then states[#states + 1] = "stale" end
    if rottenAt < never then states[#states + 1] = "rotten" end
    local state
    if item and item.isFresh and item.isRotten then
        -- Lowercase isRotten is the actual rot deadline; inherited IsRotten
        -- instead tests the loss of freshness. Fertilized eggs also override these predicates.
        if rottenAt < never and item:isRotten() then state = "rotten"
        elseif not (item.isBurnt and item:isBurnt()) then
            if freshUntil < never and item:isFresh() then state = "fresh"
            elseif rottenAt < never and not item:isFresh() then state = "stale" end
        end
    end
    return state, freshUntil < never or rottenAt < never, states
end

return Properties
