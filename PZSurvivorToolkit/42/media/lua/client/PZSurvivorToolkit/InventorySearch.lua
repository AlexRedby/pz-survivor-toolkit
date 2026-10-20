-- CleanUI owns search inputs and sort priority. Toolkit owns which physical
-- items remain visible, so a mixed stack's cached matchesSearch is insufficient.
local Search = {}

local function normalized(value)
    if value == nil then return nil end
    local text = tostring(value):lower()
    return text ~= "" and text or nil
end

function Search.forPane(pane)
    local mode = pane.searchMode or "name"
    local name = mode ~= "category" and normalized(pane.searchText) or nil
    local category = mode ~= "name" and normalized(pane.searchCategoryText) or nil
    if name or category then
        return {name = name, category = category, player = name and getSpecificPlayer(pane.player) or nil}
    end
end

local function contains(value, query)
    local text = normalized(value)
    return text and string.find(text, query, 1, true) ~= nil
end

local function categoryMatches(category, query)
    return category and (contains(category, query) or contains(getText("IGUI_ItemCat_" .. category), query))
end

function Search.matches(query, item)
    if not query then return true end
    if query.name and not (contains(item:getName(query.player), query.name)
        or contains(item:getDisplayName(), query.name) or contains(item:getType(), query.name)) then return false end
    if query.category and not (categoryMatches(item:getDisplayCategory(), query.category)
        or categoryMatches(item:getCategory(), query.category)) then return false end
    return true
end

return Search
