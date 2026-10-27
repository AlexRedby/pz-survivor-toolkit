-- Laundry follows the native wash-menu admission and covered-part stain model.
-- In particular, Clothing.isDirty/getDirtiness and getBloodLevel are aggregate
-- fields and do not establish the stains checked by InventoryItem.hasDirt/Blood.
local Laundry = {}

local function kind(script, item, method, id)
    if item and item[method] then return item[method](item) end
    if script and script.isItemType and ItemType and ItemType[id] then
        return script:isItemType(ItemType[id])
    end
end

local function covered(script)
    if not script or not script.getBloodClothingType then return nil end
    local types = script:getBloodClothingType()
    if types == nil then return false end
    if not types.size then return nil end
    if types:size() == 0 then return false end
    if not BloodClothingType or not BloodClothingType.getCoveredParts then return nil end
    local parts = BloodClothingType.getCoveredParts(types)
    if parts == nil then return false end
    if not parts.size then return nil end
    return parts:size() > 0
end

-- The third result distinguishes managed clothing/bags from other Dirty roles
-- (such as bandages). A managed nil state is unknown, never evidence of clean.
-- Script previews return no current state; the second result contains coherent
-- clean/dirty alternatives only when native metadata proves stains are possible.
function Laundry.read(script, item)
    script = script or item and item.getScriptItem and item:getScriptItem()
    local clothing = kind(script, item, "IsClothing", "CLOTHING")
    local bag = kind(script, item, "IsInventoryContainer", "CONTAINER")
    if clothing ~= true and bag ~= true then
        if clothing == false and bag == false then return nil, nil, false end
        return nil, nil, nil
    end
    local source = item or script
    if not source or not source.isHidden then return nil, nil, true end
    local hidden = source:isHidden()
    if hidden == true then return false, nil, true end
    if hidden ~= false then return nil, nil, true end
    if clothing then
        if not source.hasTag or not ItemTag or not ItemTag.BREAK_WHEN_WET then return nil, nil, true end
        local fragile = source:hasTag(ItemTag.BREAK_WHEN_WET)
        if fragile == true then return false, nil, true end
        if fragile ~= false then return nil, nil, true end
    end
    if item then
        -- Native hasBlood/hasDirt call getVisual, which can initialize randomized
        -- cosmetics. The optional bridge reads the existing visual field only.
        local dirty = toolkitItemLaundryDirty and toolkitItemLaundryDirty(item)
        if dirty ~= true and dirty ~= false then dirty = nil end
        return dirty, nil, true
    end
    local stains = covered(script)
    if stains == false then return false, nil, true end
    if stains then return nil, {false, true}, true end
    return nil, nil, true
end

return Laundry
