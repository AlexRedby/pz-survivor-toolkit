-- Toolkit must load before Item Details so its lossy refresh hook is never used.
if not getActivatedMods():contains("BravoItemDetails") then return end
require "ISUI/ISInventoryPane"
require "PZAPI/ModOptions"
if PZAPI.ModOptions:getOptions("BravoItemDetails") then
    print("[PZSurvivorToolkit] Item Details compatibility needs load order: PZSurvivorToolkit;BravoItemDetails")
    return
end

local InventoryClasses = require "PZSurvivorToolkit/InventoryClasses"

local config = require "BravoItemDetailsConfig"
local numericOption = PZAPI.ModOptions:getOptions("BravoItemDetails").dict.showNumeric
-- Mod Options formats tooltip text; the upstream literal percent needs escaping.
if numericOption.tooltip == "Show the numeric value (x/y or x%)" then
    numericOption.tooltip = "Show the numeric value (x/y or x%%)"
end
local Sorter = require "BravoItemDetailsSorter"
local paneClass = ISInventoryPane
local nativeDraw, nativeRefresh = paneClass.drawItemDetails, paneClass.refreshContainer
-- Keep the upstream renderer, with each UI class's own native fallback.
paneClass.drawItemDetails = function(pane, ...)
    return pane:_toolkitItemDetailsNativeDraw(...)
end
local ok, err = pcall(require, "BravoItemDetails")
local itemDetailsDraw = paneClass.drawItemDetails
paneClass.drawItemDetails, paneClass.refreshContainer = nativeDraw, nativeRefresh
if not ok then error(err) end

local function upstreamCondition(item)
    local fullType = item:getFullType()
    return instanceof(item, "HandWeapon") or item:hasTag(ItemTag.SHOW_CONDITION)
        or item:hasTag(ItemTag.SHARPENABLE) or item:getDisplayCategory() == "Tool"
        or (item:getDisplayCategory() == "VehicleMaintenance" and fullType ~= "Base.PetrolCan" and fullType ~= "Base.JerryCan")
        or luautils.stringStarts(fullType, "Base.LightBulb")
end

local function sortFunction(item)
    if instanceof(item, "Drainable") and item:getUseDelta() > 0 then
        return Sorter.uses[config.usesSortDir]
    elseif instanceof(item, "HandWeapon") then
        return Sorter.weapon[config.weaponSortDir]
    elseif item:hasTag(ItemTag.SHOW_CONDITION) or item:hasTag(ItemTag.SHARPENABLE) or item:getDisplayCategory() == "Tool" then
        return Sorter.tools[config.weaponSortDir]
    elseif upstreamCondition(item) or item:getDisplayCategory() == "mechanicsVehiclePart" then
        return Sorter.condition[config.vehicleSortDir]
    elseif item:getMaxAmmo() > 0 then
        return Sorter.ammo[1]
    elseif instanceof(item, "Food") and item:getHungerChange() ~= 0 then
        return Sorter.hunger[config.foodSortDir]
    elseif item:isFluidContainer() or (instanceof(item:getWorldItem(), "IsoWorldInventoryObject") and item:getWorldItem():getFluidContainer()) then
        return Sorter.fluid[config.fluidSortDir]
    elseif instanceof(item, "Clothing") and not item:isCosmetic() then
        return Sorter.clothes[config.clothesSortDir]
    end
end

local function drawVehicleCondition(pane, item, y, xoff, yoff, red)
    local top = pane.headerHgt + y * pane.itemHgt + yoff
    local x = xoff + 70
    local textY = top + (pane.itemHgt - pane.fontHgt) / 2
    local bad, good = getCore():getBadHighlitedColor(), getCore():getGoodHighlitedColor()
    local r, g, b = 0.6, 0.6, 0.8
    if red then r, g, b = bad:getR(), bad:getG(), bad:getB() end
    if config.showLabels then
        local label = getText("Tooltip_weapon_Condition") .. ":"
        pane:drawText(label, x, textY, r, g, b, 0.5, pane.font)
        x = x + getTextManager():MeasureStringX(pane.font, label) + 10
    end
    if config.showBars then
        local fraction = item:getCurrentCondition() / 100
        local color = ColorInfo.new(0, 0, 0, 1)
        bad:interp(good, fraction, color)
        pane:drawProgressBar(x, top + (pane.itemHgt - 3) / 2 + 1, 80, 3, fraction,
            {r=color:getR(), g=color:getG(), b=color:getB(), a=1})
        x = x + 90
    end
    if config.showNumeric then
        local value = round(item:getCurrentCondition()) .. "%"
        x = x + getTextManager():MeasureStringX(pane.font, "100%") - getTextManager():MeasureStringX(pane.font, value)
        pane:drawText(value, x, textY, r, g, b, 0.5, pane.font)
    end
end

local installed = {}
local function install(class)
    if not class or installed[class] then return end
    installed[class] = true
    class._toolkitItemDetailsNativeDraw = class.drawItemDetails
    class.drawItemDetails = function(pane, item, y, xoff, yoff, red)
        if item and item:getDisplayCategory() == "mechanicsVehiclePart" and not upstreamCondition(item)
            and not (instanceof(item, "Drainable") and item:getUseDelta() > 0)
            and (config.showLabels or config.showBars or config.showNumeric) then
            return drawVehicleCondition(pane, item, y, xoff, yoff, red)
        end
        return itemDetailsDraw(pane, item, y, xoff, yoff, red)
    end
    local refresh = class.refreshContainer
    class.refreshContainer = function(pane, ...)
        local anchor = pane.items and pane.firstSelect and pane.items[pane.firstSelect]
        local anchorItem = anchor and instanceof(anchor, "InventoryItem") and anchor
        local anchorName = anchor and not anchorItem and anchor.name
        local result = refresh(pane, ...)
        if not config.enableSort then return result end
        local maxSort = math.floor(tonumber(config.maxSort) or class.MAX_ITEMS_IN_STACK_TO_RENDER or 50)
        if maxSort < 1 then return result end
        local selected = pane:saveSelection({})
        for _, stack in ipairs(pane.itemslist) do
            local items = stack.items
            if items and #items > 2 and not pane.collapsed[stack.name] and stack.cleanUIFirstActualIndex ~= 1 then
                local compare = sortFunction(items[1])
                if compare then
                    local count = math.min(#items - 1, maxSort)
                    local prefix = {}
                    for index = 1, count do prefix[index] = items[index + 1] end
                    table.sort(prefix, compare)
                    if selected[items[1]] == "group" then selected[prefix[1]] = "group" end
                    -- Replace only the sorted prefix; the real-item tail stays intact.
                    for index = 1, count do items[index + 1] = prefix[index] end
                    items[1] = items[2]
                    if stack.cleanUIDisplayItem then stack.cleanUIDisplayItem = items[1] end
                end
            end
        end
        for index in pairs(pane.selected) do pane.selected[index] = nil end
        pane:restoreSelection(selected)
        if anchorItem or anchorName then
            local row = 1
            pane.firstSelect = nil
            for _, stack in ipairs(pane.itemslist) do
                if anchorName == stack.name then pane.firstSelect = row end
                row = row + 1
                if not pane.collapsed[stack.name] then
                    local start = stack.cleanUIFirstActualIndex or 2
                    local last = math.min(#stack.items, start + (class.MAX_ITEMS_IN_STACK_TO_RENDER or 50) - 1)
                    for index = start, last do
                        if anchorItem == stack.items[index] then pane.firstSelect = row end
                        row = row + 1
                    end
                end
            end
        end
        return result
    end
end

local function installClasses()
    InventoryClasses.panes(install, true)
end
installClasses()
InventoryClasses.onToggle(installClasses)
print("[PZSurvivorToolkit] Item Details compatibility loaded")
