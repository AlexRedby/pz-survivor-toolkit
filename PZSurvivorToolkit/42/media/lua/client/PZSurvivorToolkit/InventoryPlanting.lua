local PlantingTags = require "PZSurvivorToolkit/PlantingTags"
local Planting = {}
local cachedProps, seeds, recipes

local function key(value)
    return string.lower(tostring(value))
end

local function reset()
    cachedProps, seeds, recipes = nil, nil, nil
end

if Events and Events.OnGameBoot then Events.OnGameBoot.Add(reset) end

local function cropIndex()
    local props = farming_vegetableconf and farming_vegetableconf.props
    if not props then return nil end
    -- As with PlantingTags, crop definitions are stable after the game boots.
    -- Do not cache an empty table while native farming definitions are loading.
    local populated = false
    for _ in pairs(props) do populated = true; break end
    if not populated then return nil end
    if cachedProps ~= props then
        seeds, recipes, cachedProps = {}, {}, props
        for crop, definition in pairs(props) do
            local entry = {crop = crop, props = definition}
            if definition.seedTypes then
                for _, fullType in ipairs(definition.seedTypes) do seeds[key(fullType)] = entry end
            elseif definition.seedName then
                seeds[key(definition.seedName)] = entry
            end
            if definition.seasonRecipe then recipes[key(definition.seasonRecipe)] = entry end
        end
    end
    return seeds
end

function Planting.resolve(item)
    if not item or not item.getFullType then return nil end
    local inputs = cropIndex()
    if not inputs then return nil end
    local fullType = item:getFullType()
    if not fullType then return nil end
    local entry = inputs[key(fullType)]
    if entry then return entry.crop, entry.props end

    -- Full and empty native packets both teach a growing-season recipe.
    -- Only an actual planting input may use that recipe to identify its crop.
    local script = item.getScriptItem and item:getScriptItem()
    if PlantingTags.role(fullType, script) ~= "seed" or not item.getLearnedRecipes then return nil end
    local learned = item:getLearnedRecipes()
    if not learned then return nil end
    for i = 0, learned:size() - 1 do
        entry = recipes[key(learned:get(i))]
        if entry then return entry.crop, entry.props end
    end
    return nil
end

local function hasMonth(months, month)
    if not months then return false end
    for _, value in ipairs(months) do if value == month then return true end end
    return false
end

function Planting.describe(player, item, preferBestWithoutDefinedMonth)
    local options = getSandboxOptions and getSandboxOptions()
    local seasons = options and options:getOptionByName("PlantGrowingSeasons")
    if not seasons or seasons:getValue() ~= true then return nil end
    local crop, props = Planting.resolve(item)
    if not props or not props.sowMonth or not props.seasonRecipe
        or not player or not player.isRecipeActuallyKnown
        or not player:isRecipeActuallyKnown(props.seasonRecipe) then return nil end
    local time = getGameTime and getGameTime()
    if not time then return nil end
    local month = time:getMonth() + 1
    local status = "outofseason"
    if hasMonth(props.sowMonth, month) then
        if hasMonth(props.bestMonth, month) then status = "best"
        elseif hasMonth(props.riskMonth, month) then status = "risk"
        elseif preferBestWithoutDefinedMonth and not props.bestMonth then status = "best"
        else status = "inseason" end
    end
    local growDays
    if props.timeToGrow and props.harvestLevel and calcNextTimeFactor then
        -- Match the native farming tooltip, including FarmingSpeedNew.
        growDays = math.floor(props.timeToGrow * props.harvestLevel / 24 * calcNextTimeFactor())
    end
    return {
        crop = crop, props = props, status = status, currentMonth = month,
        waterLvl = props.waterLvl, growDays = growDays, texture = props.texture or props.icon,
        sowMonth = props.sowMonth, bestMonth = props.bestMonth,
        riskMonth = props.riskMonth, badMonth = props.badMonth,
    }
end

return Planting
