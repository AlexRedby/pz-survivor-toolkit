-- Better Containers supplies the options and freshness semantics. Toolkit owns
-- presentation on the same installed pane class, using its published row map.
local Freshness = {}
local installed, fallback = {}, {}
local Options

local function clamp01(value)
    return math.max(0, math.min(1, value))
end

local function getFreshness(item)
    if not (item and instanceof(item, "Food")) then return nil end
    local maxAge = item:getOffAgeMax()
    if not maxAge or maxAge <= 0 or maxAge >= 1000000000 then return nil end
    return clamp01(1 - (item:getAge() or 0) / maxAge), clamp01(1 - (item:getOffAge() or 0) / maxAge)
end

local function leastFresh(items)
    local selected, minimum
    for _, item in ipairs(items) do
        local value = getFreshness(item)
        if value and (minimum == nil or value < minimum) then selected, minimum = item, value end
    end
    return selected
end

local function drawIndicator(pane, item, index, child)
    local value, stale = getFreshness(item)
    if value == nil then return end
    local top = pane.headerHgt + (index - 1) * pane.itemHgt
    local font = pane.font or UIFont.Medium
    local percentage = Options.showFoodFreshnessPercentage and (child or pane.mouseOverOption == index)
    local slotWidth = percentage and getTextManager():MeasureStringX(font, "100%") or 0
    local x, right = pane.column2 + 8, pane.column3 - 8
    if child and slotWidth > 0 then right = pane.column3 - slotWidth - 4 end
    local width = right - x
    if Options.showFoodFreshnessBar and width >= 48 then
        local y = top + pane.itemHgt - 4
        local fill = math.floor(width * value + 0.5)
        local marker = x + math.floor(width * stale + 0.5) - 1
        pane:drawRect(x, y, width, 3, 0.62, 0.08, 0.08, 0.08)
        if fill > 0 then
            local r, g, b = 0.30, 0.62, 0.34
            if not (value > stale) then r, g, b = 0.72, 0.48, 0.18 end
            pane:drawRect(x, y, fill, 3, 0.88, r, g, b)
        end
        pane:drawRect(marker - 1, y - 2, 4, 7, 0.80, 0.08, 0.08, 0.08)
        pane:drawRect(marker, y - 1, 2, 5, 0.92, 0.88, 0.66, 0.38)
    end
    if percentage then
        local text = tostring(math.floor(value * 100 + 0.5)) .. "%"
        local textWidth = getTextManager():MeasureStringX(font, text)
        local slotX = pane.column3 - slotWidth
        local textX = slotX + math.floor((slotWidth - textWidth) / 2)
        local fontHeight = pane.fontHgt or getTextManager():getFontHeight(font)
        pane:drawRect(slotX, top, slotWidth, pane.itemHgt, 1.0, 0.0, 0.0, 0.0)
        pane:drawText(text, textX, top + math.max(0, (pane.itemHgt - fontHeight) / 2), 0.7, 0.7, 0.7, 1.0, font)
    end
end

local function drawRows(pane, first, last)
    for index = first, last do
        local entry = pane.items[index]
        local dragging = pane.dragStarted and pane.dragging and pane.selected and pane.selected[index]
        local separator = type(entry) == "table" and (entry.type == "separator" or entry._bcEquippedAttachedSeparator)
        if not dragging and not separator then
            if type(entry) == "table" and entry.items then
                drawIndicator(pane, leastFresh(entry.items), index, false)
            else
                drawIndicator(pane, entry, index, true)
            end
        end
    end
end

function Freshness.draw(pane, class)
    if not Options or not installed[class or getmetatable(pane)] then return end
    if not Options.showFoodFreshnessBar and not Options.showFoodFreshnessPercentage then return end
    if pane.mode ~= "details" or not pane.items or not pane:isReallyVisible() then return end
    local height, header = pane.itemHgt, pane.headerHgt
    if not height or height <= 0 then return end
    local scroll = pane:getYScroll()
    local first = math.max(1, math.floor(-scroll / height) + 1)
    local clipHeight = pane.height - header - 1
    local last = math.min(#pane.items, math.ceil((clipHeight - scroll) / height))
    if first > last or clipHeight <= 0 then return end
    -- All item reads happen inside the visible interval. A visible group still
    -- examines every member: no freshness cache and no change to food ageing.
    pane:setStencilRect(0, header, pane.width - 1, clipHeight)
    local ok, err = pcall(drawRows, pane, first, last)
    pane:clearStencilRect()
    pane:repaintStencilRect(0, header, pane.width - 1, clipHeight)
    if not ok then error(err, 0) end
end

function Freshness.layout(class, pane, item)
    if Options and (installed[class] or fallback[class]) and Options.showFoodFreshnessPercentage
        and item and instanceof(item, "Food") then
        local maxAge = item:getOffAgeMax()
        if maxAge and maxAge > 0 and maxAge < 1000000000 then
            local width = getTextManager():MeasureStringX(pane.font or UIFont.Medium, "100%")
            return {reservedLeft = pane.column3 - width, reservedRight = pane.column3}
        end
    end
end

if getActivatedMods():contains("EURY_CONTAINERS") then
    Options = require "BetterContainers/_Options"
    local upstream = require "BetterContainers/Upgrades/FoodFreshness"
    if upstream._installed then
        -- An installed closure has no public uninstall API. Keep its rendering
        -- and the existing reservation observer instead of stacking presenters.
        print("[PZSurvivorToolkit] Freshness compatibility needs Toolkit before Better Containers")
        local original = upstream.install
        upstream.install = function(...)
            local class, wasInstalled = ISInventoryPane, upstream._installed
            local result = original(...)
            if not wasInstalled and upstream._installed then fallback[class] = true end
            return result
        end
    else
        upstream.install = function()
            if upstream._installed then return end
            upstream._installed = true
            require "ISUI/ISInventoryPane"
            if ISInventoryPane and ISInventoryPane.renderdetails then installed[ISInventoryPane] = true end
        end
    end
end

return Freshness
