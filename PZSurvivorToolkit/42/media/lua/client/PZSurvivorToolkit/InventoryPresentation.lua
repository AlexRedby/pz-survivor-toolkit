-- One boundary for Toolkit's item icons, expanded details and stack ordering.
-- CleanUI/native panes own layout; presenters receive actual render coordinates.
require "ISUI/ISInventoryPane"
require "ISUI/ISInventoryPage"
local Classes = require "PZSurvivorToolkit/InventoryClasses"
local Capacity = require "PZSurvivorToolkit/InventoryCapacity"
local Details = require "PZSurvivorToolkit/InventoryDetails"
local Sort = require "PZSurvivorToolkit/InventoryDetailSort"
local Rows = require "PZSurvivorToolkit/InventoryRows"
local Indicators = require "PZSurvivorToolkit/InventoryIndicators"
local Retention = require "PZSurvivorToolkit/InventoryRetention"
local Wishlist = require "PZSurvivorWishlist/Inventory"
local PlantingTooltip = require "PZSurvivorToolkit/InventoryPlantingTooltip"
local MediaTooltip = require "PZSurvivorToolkit/InventoryMediaTooltip"
local ClothingTooltip = require "PZSurvivorToolkit/InventoryClothingTooltip"
local Freshness = require "PZSurvivorToolkit/InventoryFreshness"
local Presentation = {}
local contexts, panes, pages = {}, {}, {}

local originalIcon = ISInventoryItem.renderItemIcon
ISInventoryItem.renderItemIcon = function(pane, item, x, y, alpha, width, height, ...)
    local context = contexts[pane]
    -- Native/CleanUI append the current row before drawing its icon. Capture its
    -- identity here; the final row cache cannot identify repeated physical icons.
    local row = context and context.details and pane.items and pane.items[#pane.items]
    local group = type(row) == "table" and row.items ~= nil
        and row.type ~= "separator" and not row._bcEquippedAttachedSeparator
    -- The native icon view omits alpha although DrawItemIcon requires a number.
    local result = originalIcon(pane, item, x, y, alpha or 1, width, height, ...)
    local texture = context and item and item:getTex()
    if texture then
        if not (width and height) then width, height = texture:getWidthOrig(), texture:getHeightOrig() end
        context.icons[#context.icons + 1] = {item = item, x = x, y = y, width = width, height = height, group = group}
    end
    return result
end

local function render(pane, native, details, class, ...)
    local previous = contexts[pane]
    -- Dirty native redraw clears pane.items before refreshing its groups.
    local context = {icons = {}, details = details, anchor = Rows.captureAnchor(pane)}
    contexts[pane] = context
    local ok, result = pcall(native, pane, ...)
    contexts[pane] = previous
    if not ok then error(result) end
    -- Draw last so native badges cannot erase the indicators. No row projection or coordinate remapping.
    for _, icon in ipairs(context.icons) do
        Capacity.drawIcon(pane, icon.item, icon.x, icon.y, icon.width, icon.height, details)
        Indicators.drawIcon(pane, icon.item, icon.x, icon.y, icon.width, icon.height, details, icon.group)
    end
    -- Wishlist decorates full rows, including mixed stacks and items without an
    -- icon. Keep its row projection separate from individual icon presenters.
    if details then Wishlist.draw(pane); Retention.draw(pane); Freshness.draw(pane, class) end
    return result
end

local function installPane(class)
    if not class or panes[class] then return end
    panes[class] = true
    local nativeDetails, nativeIcons = class.renderdetails, class.rendericons
    class.renderdetails = function(pane, dragged, ...)
        if dragged then return nativeDetails(pane, dragged, ...) end
        return render(pane, nativeDetails, true, class, dragged, ...)
    end
    class.rendericons = function(pane, ...) return render(pane, nativeIcons, false, class, ...) end
    local nativeDraw = class.drawItemDetails
    class.drawItemDetails = function(pane, item, y, xoff, yoff, red)
        if not Details.draw(pane, item, y, xoff, yoff, red, Freshness.layout(class, pane, item)) then
            return nativeDraw(pane, item, y, xoff, yoff, red)
        end
    end
    local nativeRefresh = class.refreshContainer
    class.refreshContainer = function(pane, ...)
        Wishlist.invalidate(pane)
        Retention.invalidate(pane)
        local anchor = Rows.captureAnchor(pane)
        anchor = anchor or (contexts[pane] and contexts[pane].anchor)
        local result = nativeRefresh(pane, ...)
        Sort.refresh(pane, class, anchor)
        -- Native dirty rendering clears the row cache before refresh. Its
        -- physical anchor must survive even when detail sorting is disabled.
        if pane.itemslist then Rows.restoreAnchor(pane, anchor) end
        return result
    end
end

local function installPage(class)
    if not class or pages[class] then return end
    pages[class] = true
    local nativeAdd = class.addContainerButton
    class.addContainerButton = function(page, ...)
        local button = nativeAdd(page, ...)
        if not button then return end
        button.toolkitCapacityPlayer = page.player
        if not button.toolkitCapacityRender then
            button.toolkitCapacityRender = button.render
            button.render = function(self, ...)
                local result = self.toolkitCapacityRender(self, ...)
                Capacity.drawButton(self, self.toolkitCapacityPlayer)
                return result
            end
        end
        return button
    end
end

function Presentation.install()
    PlantingTooltip.install()
    MediaTooltip.install()
    ClothingTooltip.install()
    Classes.panes(installPane, true)
    installPage(CleanUI_Clean_ISInventoryPage)
    installPage(CleanUI_Vanilla_ISInventoryPage)
    installPage(ISInventoryPage)
end
Presentation.install()
Classes.onToggle(Presentation.install)
return Presentation
