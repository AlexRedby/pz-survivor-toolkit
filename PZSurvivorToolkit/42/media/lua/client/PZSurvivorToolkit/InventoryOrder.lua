-- Shared row priority for retained physical copies and Better Containers type pins.
-- Stable partitions preserve the native column order within each priority.
local Retention = require "PZSurvivorToolkit/ItemRetention"
local Order = {}

local function itemRow(row)
    return row.type ~= "separator" and not row._bcEquippedAttachedSeparator and not row._ocPinned
        and row.items and row.items[1] and row.items[1].getFullType
end

function Order.prioritize(pane, pins)
    if not pane.itemslist then return false end
    local showPins = pins and pins.displayPinnedItem(pane.inventoryPage)
    local rows, ordered, first = pane.itemslist, {}, 1
    while first <= #rows do
        local head, last = rows[first], first
        if itemRow(head) then
            while last < #rows do
                local row = rows[last + 1]
                if not itemRow(row) or (row.equipped == true) ~= (head.equipped == true)
                    or (row.matchesSearch == true) ~= (head.matchesSearch == true) then break end
                last = last + 1
            end
            local buckets = {{}, {}, {}}
            for index = first, last do
                local row = rows[index]
                local item = row.cleanUIDisplayItem or row.firstItem or row.items[1]
                local priority = Retention.isRetained(item) and 1
                    or showPins and pins.isFavourite(item:getFullType()) and 2 or 3
                local bucket = buckets[priority]
                bucket[#bucket + 1] = row
            end
            for _, bucket in ipairs(buckets) do
                for _, row in ipairs(bucket) do ordered[#ordered + 1] = row end
            end
        else
            ordered[#ordered + 1] = head
        end
        first = last + 1
    end
    local changed = false
    for index, row in ipairs(ordered) do
        changed = changed or rows[index] ~= row
        rows[index] = row
    end
    return changed
end

return Order
