local Protection = {}
PZSurvivorToolkit = PZSurvivorToolkit or {}
PZSurvivorToolkit.InventoryTransferProtection = Protection

require "PZSurvivorToolkit/ItemRetention"

function Protection.allowsAutomatic(item)
    return not PZSurvivorToolkit.ItemRetention.isRetained(item)
end

function Protection.items(rows)
    local result, seen = {}, {}
    local function add(item)
        if instanceof(item, "InventoryItem") and not seen[item] then
            result[#result + 1], seen[item] = item, true
        end
    end
    for _, entry in ipairs(rows or {}) do
        if instanceof(entry, "InventoryItem") then add(entry)
        elseif type(entry) == "table" and entry.type ~= "separator" then
            local first = entry.cleanUILargeStackOptimized and 1 or entry.cleanUIFirstActualIndex or 2
            for index = first, #(entry.items or {}) do add(entry.items[index]) end
        end
    end
    return result
end

local function members(rows)
    local set, found = {}, false
    for _, item in ipairs(Protection.items(rows)) do set[item], found = true, true end
    return set, found
end
local function contained(set, rows)
    local found = false
    for _, item in ipairs(Protection.items(rows)) do
        if not set[item] then return false end
        found = true
    end
    return found
end

-- Membership comes from the original user pick, never its size, name or source.
function Protection.containsSelection(rows, entries)
    return contained(members(rows), entries)
end

-- Native Kahlua does not collect weak table keys. Bound menu payload snapshots
-- explicitly; unrelated/new arrays cannot inherit a previous menu's intent.
local selections, order, scope = {}, {}, nil
function Protection.rememberSelection(rows, playerNum)
    if type(rows) ~= "table" then return end
    local set, found = members(rows)
    if not found then return end
    if not selections[rows] then
        if #order >= 64 then selections[table.remove(order, 1)] = nil end
        order[#order + 1] = rows
    end
    selections[rows] = {items = set, player = playerNum}
end

function Protection.selectionAllowsStuck(rows, playerNum)
    local saved = selections[rows]
    if saved and saved.player == playerNum and contained(saved.items, rows) then return true end
    return scope ~= nil and scope.player == playerNum and contained(scope.items, rows)
end

local function pack(...) return {n = select("#", ...), ...} end
-- Row buttons, controller picks and quantity commands create fresh arrays.
-- Bind their synchronous callbacks to exact selected objects, including nested
-- calls, and restore the previous scope even when a native callback fails.
function Protection.withSelection(rows, playerNum, callback, ...)
    local previous = scope
    scope = {items = members(rows), player = playerNum}
    local result = pack(pcall(callback, ...))
    scope = previous
    if not result[1] then error(result[2], 0) end
    return unpack(result, 2, result.n)
end

return Protection
