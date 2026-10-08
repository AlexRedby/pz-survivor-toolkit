-- Load Toolkit after CleanUI and before ContainerCapacityIndicator.
local mods = getActivatedMods()
if not mods:contains("CleanUI") or not mods:contains("ContainerCapacityIndicator") then return end
require "ISUI/ISInventoryPane"
require "ISUI/ISInventoryPage"
require "PZAPI/ModOptions"
if PZAPI.ModOptions:getOptions("ContainerCapacityIndicator") then
    print("[PZSurvivorToolkit] CCI compatibility needs load order: CleanUI;PZSurvivorToolkit;ContainerCapacityIndicator")
    return
end

-- Capture CCI's private overlays once, independently of the active UI class.
local paneClass, pageClass = ISInventoryPane, ISInventoryPage
local details, icons, addButton = paneClass.renderdetails, paneClass.rendericons, pageClass.addContainerButton
paneClass.renderdetails, paneClass.rendericons = function() end, function() end
pageClass.addContainerButton = function(_, button) return button end
local ok, err = pcall(require, "ContainerCapacityIndicator")
local cciDetails, cciIcons, cciButton = paneClass.renderdetails, paneClass.rendericons, pageClass.addContainerButton
paneClass.renderdetails, paneClass.rendericons, pageClass.addContainerButton = details, icons, addButton
if not ok then error(err) end

local contexts, installedPanes, installedPages = {}, {}, {}
local originalIcon = ISInventoryItem.renderItemIcon
ISInventoryItem.renderItemIcon = function(pane, item, x, y, alpha, width, height, ...)
    local context = contexts[pane]
    if context and not context.overlay then
        local size = width or 32
        local row = math.floor((y - pane.headerHgt - (pane.itemHgt - size) / 2) / pane.itemHgt + 0.5)
        context.icons[row] = {x = x, y = y, width = size, height = height or size}
    end
    -- B42's icon view omits alpha; native DrawItemIcon requires a number.
    return originalIcon(pane, item, x, y, alpha or 1, width, height, ...)
end

local function projectRows(pane, context)
    -- CleanUI has already built the actual visible rows, including separators.
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
end

local function installPane(class, enhanced)
    if not class or installedPanes[class] then return end
    installedPanes[class] = true
    local nativeDetails, nativeIcons = class.renderdetails, class.rendericons
    class.rendericons = function(pane, ...)
        local result = nativeIcons(pane, ...)
        cciIcons(pane, ...)
        return result
    end
    class.renderdetails = function(pane, doDragged, ...)
        if doDragged then return nativeDetails(pane, doDragged, ...) end
        if not enhanced then
            local result = nativeDetails(pane, doDragged, ...)
            cciDetails(pane, doDragged, ...)
            return result
        end
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
        local function render(...)
            local result = nativeDetails(pane, doDragged, ...)
            projectRows(pane, context)
            cciDetails(pane, doDragged, ...)
            return result
        end
        local success, result = pcall(render, ...)
        if context.itemslist then pane.itemslist = context.itemslist end
        pane.drawRect, pane.drawRectBorder = savedRect, savedBorder
        pane.getYScroll = savedScroll
        contexts[pane] = nil
        if not success then error(result) end
        return result
    end
end

local function installPage(class)
    if not class or installedPages[class] then return end
    installedPages[class] = true
    local nativeAddButton = class.addContainerButton
    class.addContainerButton = function(page, ...)
        return cciButton(page, nativeAddButton(page, ...))
    end
end

local function installClasses()
    installPane(_G.CleanUI_Clean_ISInventoryPane, true)
    installPane(_G.CleanUI_Vanilla_ISInventoryPane, false)
    installPane(ISInventoryPane, ISInventoryPane ~= _G.CleanUI_Vanilla_ISInventoryPane)
    installPage(_G.CleanUI_Clean_ISInventoryPage)
    installPage(_G.CleanUI_Vanilla_ISInventoryPage)
    installPage(ISInventoryPage)
end
installClasses()
if type(CleanUI_RegisterInventoryUiToggleCallback) == "function" then
    CleanUI_RegisterInventoryUiToggleCallback(installClasses)
end
print("[PZSurvivorToolkit] CleanUI / CCI compatibility loaded")
