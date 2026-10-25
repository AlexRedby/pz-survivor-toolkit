-- Toolkit owns inventory classifications. ScriptItem categories stay untouched:
-- the native loot system reads them independently of inventory tags and routing.
local Rules = require "PZSurvivorToolkit/ItemCategoryRules"
local Categories = {}
PZSurvivorToolkit = PZSurvivorToolkit or {}
PZSurvivorToolkit.ItemCategories = Categories

function Categories.forScript(script)
    return Rules.forScript(script)
end

function Categories.refineMediaCategory(item, category)
    return Rules.refineMediaCategory(item, category)
end

function Categories.prepareItem(item)
    if not item then return end
    local category = Rules.forItem(item)
    if category and category ~= "" and item.setDisplayCategory
        and item:getDisplayCategory() ~= category then
        item:setDisplayCategory(category)
    end
    return category
end

function Categories.prepareContainer(container)
    if not container or not container.getItems then return end
    local items = container:getItems()
    if not items then return end
    for i = 0, items:size() - 1 do Categories.prepareItem(items:get(i)) end
end

return Categories
