-- Capacity and magazine presentation adapted from Container Capacity Indicator 1.2.0.
-- This module draws at the layout owner's actual icon/button bounds; it never rebuilds rows.
require "PZAPI/ModOptions"
local Capacity = {}
-- Keep the persisted key so existing magazine preferences survive the move to Toolkit.
local options = PZAPI.ModOptions:create("ContainerCapacityIndicator", "Toolkit: Container Capacity")
local magazines = options:addTickBox("showMagazineIndicators", "Show magazine indicators", true,
    "Show load indicators on loose detachable magazines. Turn off to show only container capacity bars.")

function Capacity.ratio(inventory, player)
    if not inventory or not player then return nil end
    local maximum = inventory:getEffectiveCapacity(player)
    if not maximum or maximum <= 0 then return nil end
    return math.max(0, math.min(inventory:getCapacityWeight() / maximum, 1))
end

local function itemValue(item, method)
    local fn = item and item[method]
    if not fn then return nil end
    local ok, value = pcall(fn, item)
    if ok then return value end
end

local function magazineRatio(item)
    if not magazines:getValue() or itemValue(item, "IsWeapon") then return nil end
    local maximum = tonumber(itemValue(item, "getMaxAmmo")) or 0
    if maximum <= 0 or not itemValue(item, "getAmmoType") then return nil end
    return math.max(0, math.min((tonumber(itemValue(item, "getCurrentAmmoCount")) or 0) / maximum, 1))
end

local function capacityBar(target, x, y, width, ratio)
    if ratio == nil or width < 3 then return end
    target:drawRect(x, y, width, 4, 0.88, 0.08, 0.08, 0.08)
    if ratio > 0 then
        local r, g, b = 0.24, 0.78, 0.32
        if ratio >= 0.95 then r, g, b = 0.90, 0.22, 0.18
        elseif ratio >= 0.75 then r, g, b = 0.95, 0.68, 0.16 end
        target:drawRect(x + 1, y + 1, math.max(1, math.floor((width - 2) * ratio)), 2, 0.95, r, g, b)
    end
    target:drawRectBorder(x, y, width, 4, 0.70, 0.65, 0.65, 0.65)
end

local magazineColors = {
    [0] = {0.92, 0.16, 0.12}, {0.95, 0.36, 0.12}, {0.95, 0.72, 0.14},
    {0.30, 0.68, 0.94}, {0.24, 0.82, 0.34},
}
local function magazineBar(target, x, y, width, ratio)
    if ratio == nil or width < 8 then return end
    local state = ratio >= 1 and 4 or math.min(math.ceil(ratio * 4), 3)
    local color = magazineColors[state]
    local r, g, b = color[1], color[2], color[3]
    local segmentWidth = (width - 5) / 4
    target:drawRect(x, y, width, 4, 0.92, 0.06, 0.06, 0.06)
    for segment = 1, 4 do
        local start = math.floor((segment - 1) * (segmentWidth + 1))
        local finish = math.floor(segment * segmentWidth + segment - 1)
        if segment <= state then
            target:drawRect(x + 1 + start, y + 1, math.max(1, finish - start), 2, 0.98, r, g, b)
        else
            target:drawRect(x + 1 + start, y + 1, math.max(1, finish - start), 2, 0.82, 0.18, 0.18, 0.18)
        end
    end
    target:drawRectBorder(x, y, width, 4, 0.82, r, g, b)
end

function Capacity.drawIcon(pane, item, x, y, width, height, details)
    local barY = y + height - 4
    local visibleY = barY + pane:getYScroll()
    if visibleY < (details and pane.headerHgt or 0) or visibleY > pane.height then return end
    local player = getSpecificPlayer(pane.player or 0)
    if not player then return end
    if itemValue(item, "IsInventoryContainer") then
        capacityBar(pane, x + 1, barY, width - 2, Capacity.ratio(item:getInventory(), player))
    else
        magazineBar(pane, x + 1, barY, width - 2, magazineRatio(item))
    end
end

function Capacity.drawButton(button, playerIndex)
    capacityBar(button, 2, button:getHeight() - 6, button:getWidth() - 4,
        Capacity.ratio(button.inventory, getSpecificPlayer(playerIndex or 0)))
end

return Capacity
