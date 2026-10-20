-- One boundary for Toolkit's item icons, expanded details and stack ordering.
-- CleanUI/native panes own layout; presenters receive actual render coordinates.
require "ISUI/ISInventoryPane"
require "ISUI/ISInventoryPage"
local Classes = require "PZSurvivorToolkit/InventoryClasses"
local Capacity = require "PZSurvivorToolkit/InventoryCapacity"
local Details = require "PZSurvivorToolkit/InventoryDetails"
local Sort = require "PZSurvivorToolkit/InventoryDetailSort"
local Indicators = require "PZSurvivorToolkit/InventoryIndicators"
local PlantingTooltip = require "PZSurvivorToolkit/InventoryPlantingTooltip"
local MediaTooltip = require "PZSurvivorToolkit/InventoryMediaTooltip"
local ClothingTooltip = require "PZSurvivorToolkit/InventoryClothingTooltip"
local Presentation = {}
local contexts, panes, pages = {}, {}, {}

-- Better Containers owns its freshness bar/percentage. Reserve the percentage's
-- actual column only on the class where its public installer adds that overlay.
local freshnessClasses, freshnessOptions = {}, nil
if getActivatedMods():contains("EURY_CONTAINERS") then
    freshnessOptions = require "BetterContainers/_Options"
    local freshness = require "BetterContainers/Upgrades/FoodFreshness"
    local install = freshness.install
    freshness.install = function(...)
        local class, wasInstalled = ISInventoryPane, freshness._installed
        local result = install(...)
        if not wasInstalled and freshness._installed then freshnessClasses[class] = true end
        return result
    end
end

local function detailLayout(class, pane, item)
    if freshnessClasses[class] and freshnessOptions.showFoodFreshnessPercentage
        and item and instanceof(item, "Food") then
        local maxAge = item:getOffAgeMax()
        if maxAge and maxAge > 0 and maxAge < 1000000000 then
            local width = getTextManager():MeasureStringX(pane.font or UIFont.Medium, "100%")
            return {reservedLeft = pane.column3 - width, reservedRight = pane.column3}
        end
    end
end

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

local function render(pane, native, details, ...)
    local previous = contexts[pane]
    -- Dirty native redraw clears pane.items before refreshing its groups.
    local context = {icons = {}, details = details, anchor = pane.items and pane.firstSelect and pane.items[pane.firstSelect]}
    contexts[pane] = context
    local ok, result = pcall(native, pane, ...)
    contexts[pane] = previous
    if not ok then error(result) end
    -- Draw last so native badges cannot erase the indicators. No row projection or coordinate remapping.
    for _, icon in ipairs(context.icons) do
        Capacity.drawIcon(pane, icon.item, icon.x, icon.y, icon.width, icon.height, details)
        Indicators.drawIcon(pane, icon.item, icon.x, icon.y, icon.width, icon.height, details, icon.group)
    end
    return result
end

local function installPane(class)
    if not class or panes[class] then return end
    panes[class] = true
    local nativeDetails, nativeIcons = class.renderdetails, class.rendericons
    class.renderdetails = function(pane, dragged, ...)
        if dragged then return nativeDetails(pane, dragged, ...) end
        return render(pane, nativeDetails, true, dragged, ...)
    end
    class.rendericons = function(pane, ...) return render(pane, nativeIcons, false, ...) end
    local nativeDraw = class.drawItemDetails
    class.drawItemDetails = function(pane, item, y, xoff, yoff, red)
        if not Details.draw(pane, item, y, xoff, yoff, red, detailLayout(class, pane, item)) then
            return nativeDraw(pane, item, y, xoff, yoff, red)
        end
    end
    local nativeRefresh = class.refreshContainer
    class.refreshContainer = function(pane, ...)
        local anchor = pane.items and pane.firstSelect and pane.items[pane.firstSelect]
        anchor = anchor or (contexts[pane] and contexts[pane].anchor)
        local result = nativeRefresh(pane, ...)
        Sort.refresh(pane, class, anchor)
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
