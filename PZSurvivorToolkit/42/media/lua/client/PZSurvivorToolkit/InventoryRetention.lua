local Retention = require "PZSurvivorToolkit/ItemRetention"
local Inventory = {}

function Inventory.invalidate(pane)
    pane.pzstRetainedRows = {}
end

local function retainedSet(pane, row)
    if row.type == "separator" or row._bcEquippedAttachedSeparator or not row.items then return false end
    local cache = pane.pzstRetainedRows
    local saved = cache and cache[row]
    if saved and saved.items == row.items and saved.count == #row.items then return saved.set end
    local set = false
    local first = row.cleanUILargeStackOptimized and 1 or row.cleanUIFirstActualIndex or 2
    for index = first, #row.items do
        local item = row.items[index]
        if Retention.isRetained(item) then
            set = set or {}
            set[item] = true
        end
    end
    if cache then cache[row] = {items=row.items, count=#row.items, set=set} end
    return set
end

function Inventory.marks(pane)
    local result = {}
    local entries, height = pane.items, pane.itemHgt
    if not entries or not height or height <= 0 or not pane.column3 then return result end
    local scroll, header = pane:getYScroll(), pane.headerHgt or 0
    local first = math.max(1, math.floor(-scroll / height) + 1)
    local last = math.min(#entries, math.ceil((pane.height - header - scroll) / height))
    local row
    -- The viewport may start in the middle of an expanded mixed stack.
    for index = first, 1, -1 do
        local entry = entries[index]
        if type(entry) == "table" and entry.items then row = entry; break end
    end
    for index = first, last do
        local entry = entries[index]
        local marked
        if type(entry) == "table" and entry.items then
            row = entry
            marked = retainedSet(pane, row) ~= false
        elseif row then
            local set = retainedSet(pane, row)
            marked = set and set[entry]
        end
        local dragging = pane.dragStarted and pane.dragging and pane.selected and pane.selected[index]
        if marked and not dragging then result[#result + 1] = index end
    end
    return result
end

function Inventory.draw(pane)
    if not pane.column2 or not pane.column3 or not pane.itemHgt or pane.itemHgt <= 0 then return end
    local texture = getTexture("media/textures/PZSurvivorToolkit/item_retained.png")
    if not texture then return end
    -- Pixel-authored lock: keep a square silhouette and whole-pixel placement.
    local size = math.min(16, math.floor(pane.itemHgt - 4))
    if size < 12 then return end
    local header, scroll = pane.headerHgt or 0, pane:getYScroll()
    for _, index in ipairs(Inventory.marks(pane)) do
        local entry = pane.items[index]
        local group = type(entry) == "table" and entry.items ~= nil
        -- Expanded children have no item icon. Use that empty gutter rather
        -- than the end of the name column, where detail bars and values extend.
        local x = math.floor((group and pane.column3 or pane.column2) - size - 6)
        local y = math.floor(header + (index - 1) * pane.itemHgt + (pane.itemHgt - size) / 2)
        if x >= 0 and y + scroll >= header and y + scroll + size <= pane.height then
            pane:drawTextureScaled(texture, x, y, size, size, 1, 1, 1, 1)
        end
    end
end

return Inventory
