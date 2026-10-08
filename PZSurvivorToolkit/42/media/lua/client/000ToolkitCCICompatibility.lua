-- Load Toolkit after CleanUI and before ContainerCapacityIndicator.
local mods = getActivatedMods()
if not mods:contains("CleanUI") or not mods:contains("ContainerCapacityIndicator") then return end
require "ISUI/ISInventoryPane"
require "PZAPI/ModOptions"
if PZAPI.ModOptions:getOptions("ContainerCapacityIndicator") then
    print("[PZSurvivorToolkit] CCI compatibility needs load order: CleanUI;PZSurvivorToolkit;ContainerCapacityIndicator")
    return
end

local paneClass = ISInventoryPane
local contexts = {}
local originalIcon = ISInventoryItem.renderItemIcon
ISInventoryItem.renderItemIcon = function(pane, item, x, y, alpha, width, height, ...)
    local context = contexts[pane]
    if context and not context.overlay then
        local size = width or 32
        local row = math.floor((y - pane.headerHgt - (pane.itemHgt - size) / 2) / pane.itemHgt + 0.5)
        context.icons[row] = {x = x, y = y, width = size, height = height or size}
    end
    return originalIcon(pane, item, x, y, alpha, width, height, ...)
end

local cleanDetails = paneClass.renderdetails
paneClass.renderdetails = function(pane, doDragged, ...)
    local result = cleanDetails(pane, doDragged, ...)
    local context = contexts[pane]
    if not context or doDragged then return result end
    -- CleanUI has already built the actual visible rows, including its separators.
    local projected, group = {}, nil
    context.itemslist = pane.itemslist
    for index, row in ipairs(pane.items) do
        local child = not row.items and row.type ~= "separator"
        if child and group then
            table.insert(group.items, row)
        else
            group = {items = {row.items and row.items[1] or {}}}
            table.insert(projected, group)
        end
        local icon = context.icons[index - 1]
        if icon then
            local size = math.min(pane.itemHgt - 2, 32)
            icon.oldX = (child and 26 or pane.column2 - size - (pane.itemHgt - size) / 2) + 1
            icon.oldY = pane.headerHgt + (index - 1) * pane.itemHgt + (pane.itemHgt - size) / 2 + size - 4
            icon.oldWidth = size - 2
        end
    end
    pane.itemslist = projected
    context.overlay = true
    return result
end

-- Require CCI here so its private overlay wraps our CleanUI row projection.
require "ContainerCapacityIndicator"
local cciDetails = paneClass.renderdetails
paneClass.renderdetails = function(pane, doDragged, ...)
    if doDragged then return cciDetails(pane, doDragged, ...) end
    local context = {icons = {}}
    contexts[pane] = context
    local savedRect, savedBorder = rawget(pane, "drawRect"), rawget(pane, "drawRectBorder")
    local savedScroll = rawget(pane, "getYScroll")
    local rect, border, scroll = pane.drawRect, pane.drawRectBorder, pane.getYScroll
    pane.getYScroll = function(self)
        local offset = context.overlay and ((self.cleanUIItemIconSize or 32) - math.min(self.itemHgt - 2, 32)) / 2 or 0
        return scroll(self) + offset
    end
    local function draw(method, self, x, y, width, height, ...)
        if context.overlay then
            local row = math.floor((y - self.headerHgt) / self.itemHgt)
            local icon = context.icons[row]
            if not icon or not icon.oldX then return end
            local scale = (icon.width - 2) / icon.oldWidth
            x = icon.x + 1 + (x - icon.oldX) * scale
            y = icon.y + icon.height - 4 + (y - icon.oldY)
            width = width * scale
        end
        return method(self, x, y, width, height, ...)
    end
    pane.drawRect = function(self, ...) return draw(rect, self, ...) end
    pane.drawRectBorder = function(self, ...) return draw(border, self, ...) end
    local ok, result = pcall(cciDetails, pane, doDragged, ...)
    if context.itemslist then pane.itemslist = context.itemslist end
    pane.drawRect, pane.drawRectBorder = savedRect, savedBorder
    pane.getYScroll = savedScroll
    contexts[pane] = nil
    if not ok then error(result) end
    return result
end
print("[PZSurvivorToolkit] CleanUI / CCI compatibility loaded")
