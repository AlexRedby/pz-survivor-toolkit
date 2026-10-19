-- LootSorter: item DisplayCategory list (built dynamically from loaded item scripts) + config.
local Categories = require "PZSurvivorToolkit/ItemCategories"
LootSorter = LootSorter or {}

-- These caches live on the global LootSorter, which a hot reload does not clear: it redefines the
-- functions but leaves the previous load's data, so a change to what they hold would stay masked for
-- the rest of the session. A no-op at boot, one lazy rebuild per reload while developing.
LootSorter._cats = nil
LootSorter._itemNames = nil
LootSorter._itemFullTypes = nil
LootSorter._catItems = nil

-- Vanilla skips hidden/obsolete items wherever it enumerates them (forageSystem, ISItemsListViewer).
-- Fails open: an item that cannot answer stays listed, since hiding real ones is the worse failure.
local function isListable(scriptItem)
    local listable = true
    pcall(function()
        if scriptItem:isHidden() or scriptItem:getObsolete() then listable = false end
    end)
    return listable
end

-- Rule previews include hidden items: they may share a routable category with visible items and
-- change whether a tag covers that whole category. Only obsolete scripts are excluded here.
-- The picker owns the snapshot lifetime; reopening it reads the current loaded scripts again.
function LootSorter.getTagScriptItems()
    local items = getAllItems and getAllItems()
    local result = {}
    if items then
        for i = 0, items:size() - 1 do
            local script = items:get(i)
            if script and (not script.getObsolete or not script:getObsolete()) then result[#result + 1] = script end
        end
    end
    return result
end

-- Every inventory category declared by any loaded item (vanilla + whatever mods are installed),
-- deduped and alpha-sorted. Built lazily on first use and cached, so the picker always matches
-- the actual game/mods instead of a frozen snapshot. Provider reads preserve loot-safe scripts.
function LootSorter.getCategories()
    if LootSorter._cats then return LootSorter._cats end
    local set, list = {}, {}
    pcall(function()
        local items = getScriptManager():getAllItems()
        for i = 1, items:size() do
            local it = items:get(i - 1)
            local cat
            if isListable(it) then pcall(function() cat = Categories.forScript(it) end) end
            if cat and cat ~= "" and not set[cat] then
                set[cat] = true
                list[#list + 1] = cat
            end
        end
    end)
    table.sort(list)
    if #list > 0 then LootSorter._cats = list end  -- cache only a good result; retry next open otherwise
    return list
end

-- Every item's DisplayName (vanilla + mods), deduped and alpha-sorted, for the picker's "Items" view.
-- Same lazy-build-and-cache approach as getCategories. Items are matched by display name (so variants
-- that share a name group together), which is what the picker ticks and the planner routes on.
function LootSorter.getItemNames()
    if LootSorter._itemNames then return LootSorter._itemNames end
    local set, list, fullTypes = {}, {}, {}
    pcall(function()
        local items = getScriptManager():getAllItems()
        for i = 1, items:size() do
            local it = items:get(i - 1)
            local nm, fullType
            if isListable(it) then
                pcall(function()
                    nm = it:getDisplayName()
                    fullType = it:getFullName()
                end)
            end
            if nm and nm ~= "" and not set[nm] then
                set[nm] = true
                list[#list + 1] = nm
                fullTypes[nm] = fullType   -- first variant wins; they share a name, so they read alike
            end
        end
    end)
    table.sort(list)
    if #list > 0 then                                  -- cache only a good result; retry next open otherwise
        LootSorter._itemNames = list
        LootSorter._itemFullTypes = fullTypes
    end
    return list
end

-- The full type behind a display name, for its icon. Built by getItemNames, so ask for the list first
-- (the picker always has) -- otherwise this is a miss and the row simply draws without an icon.
function LootSorter.getItemFullType(name)
    local fullTypes = LootSorter._itemFullTypes
    return fullTypes and fullTypes[name] or nil
end

function LootSorter.getDisplayNameForFullType(fullType)
    if not fullType or fullType == "" then return nil end
    local name
    pcall(function()
        local scriptItem = getScriptManager():FindItem(fullType)
        if scriptItem then name = scriptItem:getDisplayName() end
    end)
    return name
end

-- PZ's Kahlua sandbox has no global next(), so emptiness is a pairs check.
local function hasAny(t) if t then for _ in pairs(t) do return true end end return false end

-- The items belonging to one DisplayCategory: { {name=<display name>, fullType=<full type>}, ... },
-- alpha-sorted. Deduped by DISPLAY NAME to match getItemNames above -- the picker ticks names and the
-- planner routes on them, so listing every variant separately would advertise entries you cannot pin.
-- The whole map is built on first use and cached like the two lists above.
function LootSorter.getItemsInCategory(category)
    if not LootSorter._catItems then
        local byCategory, seen = {}, {}
        pcall(function()
            local items = getScriptManager():getAllItems()
            for i = 1, items:size() do
                local it = items:get(i - 1)
                local cat, name, fullType
                if isListable(it) then
                    pcall(function()
                        cat = Categories.forScript(it)
                        name = it:getDisplayName()
                        fullType = it:getFullName()
                    end)
                end
                if cat and cat ~= "" and name and name ~= "" then
                    local key = cat .. "\0" .. name
                    if not seen[key] then
                        seen[key] = true
                        byCategory[cat] = byCategory[cat] or {}
                        table.insert(byCategory[cat], { name = name, fullType = fullType })
                    end
                end
            end
        end)
        for _, list in pairs(byCategory) do
            table.sort(list, function(a, b) return a.name < b.name end)
        end
        if hasAny(byCategory) then LootSorter._catItems = byCategory end   -- cache only a good result
        return byCategory[category] or {}
    end
    return LootSorter._catItems[category] or {}
end
