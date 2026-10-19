-- Inventory categories are distinct from the ScriptItem categories used by loot rolls.
-- Read the selected provider's public API without loading it or copying its policies.
local Categories = {}
PZSurvivorToolkit = PZSurvivorToolkit or {}
PZSurvivorToolkit.ItemCategories = Categories

function Categories.forScript(script)
    if not script then return nil end
    local provider = OrganizedCategories
    if provider and type(provider.getScriptInventoryDisplayCategory) == "function" then
        local category = provider.getScriptInventoryDisplayCategory(script)
        if category and category ~= "" then return category end
    end
    return script:getDisplayCategory()
end

-- Preparation intentionally delegates instance writes to the provider. Its fluid,
-- instance override and recorded-media rules cannot be replaced by a type lookup.
-- Repeating this pass is supported by the provider's inventory refresh path.
function Categories.prepareItem(item)
    if not item then return end
    local provider = OrganizedCategories
    if not provider then return end
    if type(provider.autoSortLiquid) == "function" and item.isFluidContainer and item:isFluidContainer() then
        provider.autoSortLiquid(item)
    end
    if type(provider.applyItemDisplayOverride) == "function" then
        provider.applyItemDisplayOverride(item)
    end
end

function Categories.prepareContainer(container)
    if not container or not container.getItems then return end
    local items = container:getItems()
    if not items then return end
    for i = 0, items:size() - 1 do Categories.prepareItem(items:get(i)) end
end

return Categories
