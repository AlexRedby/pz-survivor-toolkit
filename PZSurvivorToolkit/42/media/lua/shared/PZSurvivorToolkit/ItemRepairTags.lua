-- Native adhesive-repair supplies. Classification reads recipe metadata only;
-- it never creates an item or executes recipe/item callbacks.
local Repair = {}
local catalog
local nativeRecipes = {
    FixWithDuctTape = "genericBetterFixing",
    FixWithAdhesiveTape = "genericFixing",
    FixWithZipties = "genericFixing",
    FixWithGlue = "genericFixing",
    FixWithWoodGlue = "genericBetterFixing",
    FixWithEpoxy = "genericEvenBetterFixing",
    FixWithEpoxyAndRags = "genericFixing",
}

local function supplies(recipe)
    local handler = nativeRecipes[recipe:getName()]
    if not handler or toolkitRecipeOnCreate(recipe) ~= "RecipeCodeOnCreate." .. handler
        or toolkitRecipeHasItemTest(recipe) ~= false then return end
    local inputs, subject, result = recipe:getInputs(), nil, {}
    for i = 0, inputs:size() - 1 do
        local input = inputs:get(i)
        -- These native handlers repair the IsDamaged input. A changed recipe
        -- must still identify one kept subject separately from its supplies.
        if input:getResourceType() ~= ResourceType.Item then return end
        if input:isDamaged() then
            if subject or not input:isKeep() then return end
            subject = input
        elseif not input:isKeep() and not input:isTool() and not input:isApplyOnTick()
            and not input:hasConsumeFromItem() and not input:hasCreateToItem()
            and not input:isReplace() and input:getIntAmount() > 0 then
            result[#result + 1] = input
        end
    end
    if subject then return result end
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
    local byType = {}
    for i = 0, count - 1 do
        for _, input in ipairs(supplies(recipes:get(i)) or {}) do
            local choices = input:getPossibleInputItems()
            for j = 0, choices:size() - 1 do byType[choices:get(j):getFullName()] = true end
        end
    end
    catalog = {manager = manager, recipes = recipes, count = count,
        create = toolkitRecipeOnCreate, test = toolkitRecipeHasItemTest, byType = byType}
    return byType
end

-- nil leaves unrelated imported repair families unchanged: this index manages
-- consumed adhesive supplies, not repaired subjects, sharpening tools, legacy
-- firearm fixing, furniture or vehicle repair definitions. A supply role does
-- not promise enough material, tools or player skills for a particular repair.
-- Script-only drainables have no current quantity; the second result gives the
-- coherent empty/nonempty preview alternatives, using whole remaining uses.
function Repair.read(script, item)
    script = script or item and item.getScriptItem and item:getScriptItem()
    if not script or not script.getFullName then return nil end
    local index = indexRecipes()
    if not index or not index[script:getFullName()] then return nil end
    local drainable
    if item and item.IsDrainable then drainable = item:IsDrainable()
    elseif script.isItemType and ItemType and ItemType.DRAINABLE then
        drainable = script:isItemType(ItemType.DRAINABLE)
    end
    if drainable == false then return true end
    if drainable then
        if item then
            if item.getCurrentUses then return item:getCurrentUses() > 0 end
            return nil
        end
        return nil, {false, true}
    end
    return nil
end

function Repair.invalidate() catalog = nil end
if Events and Events.OnGameBoot then Events.OnGameBoot.Add(Repair.invalidate) end

return Repair
