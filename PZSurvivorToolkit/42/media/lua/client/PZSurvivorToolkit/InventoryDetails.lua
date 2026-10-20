-- Adapted from Bravo Item Details v0.0.12 by Bravo.
-- This module only draws details. The inventory owner chooses when to invoke it
-- and retains each inventory class's native fallback for unhandled items.
local Options = require "PZSurvivorToolkit/InventoryDetailOptions"
local Details = {}

function Details.isConditionItem(item)
    local category, fullType = item:getDisplayCategory(), item:getFullType()
    return instanceof(item, "HandWeapon") or item:hasTag(ItemTag.SHOW_CONDITION)
        or item:hasTag(ItemTag.SHARPENABLE) or category == "Tool"
        or category == "mechanicsVehiclePart"
        or (category == "VehicleMaintenance" and fullType ~= "Base.PetrolCan" and fullType ~= "Base.JerryCan")
        or luautils.stringStarts(fullType, "Base.LightBulb")
end

local function rgb(color)
    return {r=color:getR(), g=color:getG(), b=color:getB(), a=1}
end

local function progressColor(fraction)
    local color = ColorInfo.new(0, 0, 0, 1)
    getCore():getBadHighlitedColor():interp(getCore():getGoodHighlitedColor(), fraction, color)
    return rgb(color)
end

function Details.draw(pane, item, y, xoff, yoff, red, layout)
    if not item then return false end
    local showLabels, showBars, showNumeric = Options.showLabels:getValue(), Options.showBars:getValue(), Options.showNumeric:getValue()
    if not (showLabels or showBars or showNumeric) then return false end
    local good, bad = getCore():getGoodHighlitedColor(), getCore():getBadHighlitedColor()
    local textColor = red and rgb(bad) or {r=0.6, g=0.6, b=0.8}
    local barColor = rgb(good)
    local top = pane.headerHgt + y * pane.itemHgt + yoff
    local textY = top + (pane.itemHgt - pane.fontHgt) / 2
    local barY = top + (pane.itemHgt - 3) / 2 + 1
    local iconSize = pane.itemHgt - 4
    local iconY = top + (pane.itemHgt - iconSize) / 2
    local x = xoff + 70
    local function width(text) return getTextManager():MeasureStringX(pane.font, text) end
    -- Another presentation owner may reserve a horizontal field (for example
    -- Better Containers' food freshness percentage). Keep every drawn element
    -- outside it without intercepting drawing methods or changing its renderer.
    local reservedLeft = layout and tonumber(layout.reservedLeft)
    local reservedRight = layout and tonumber(layout.reservedRight)
    local function reserve(size, offset)
        offset = offset or 0
        if reservedLeft and reservedRight and reservedRight > reservedLeft
            and x + offset < reservedRight and x + offset + size > reservedLeft then
            x = reservedRight + 10 - math.min(offset, 0)
        end
    end
    local function text(value, color)
        reserve(width(value))
        color = color or textColor
        pane:drawText(value, x, textY, color.r, color.g, color.b, 0.5, pane.font)
    end
    local function label(value)
        if showLabels then text(value); x = x + width(value) + 10 end
    end
    local function bar(fraction, color, force)
        if showBars or force then
            reserve(80)
            pane:drawProgressBar(x, barY, 80, 3, fraction, color)
            x = x + 90
        end
    end
    local function numeric(value, maximum)
        if showNumeric then
            x = x + width(maximum) - width(value)
            text(value)
            x = x + width(value) + 10
        end
    end
    local function centered(value, maximum, color)
        color = color or textColor
        local size = width(maximum)
        reserve(width(value), (size - width(value)) / 2)
        pane:drawTextCentre(value, x + size / 2, textY, color.r, color.g, color.b, 0.5, pane.font)
        x = x + size + 10
    end
    local function condition(labelKey, fraction)
        label(getText(labelKey) .. ":")
        bar(fraction, progressColor(fraction))
        numeric(round(fraction * 100) .. "%", "100%")
    end

    if instanceof(item, "Drainable") and item:getUseDelta() > 0 then
        local uses, maximum = item:getCurrentUses(), item:getMaxUses()
        local fraction = uses / maximum
        label(getText("IGUI_invpanel_Remaining") .. ":")
        bar(fraction, progressColor(fraction))
        if maximum > 100 then numeric(round(fraction * 100) .. "%", "100%")
        else numeric(uses .. "/" .. maximum, maximum .. "/" .. maximum) end
        return true
    end

    if Details.isConditionItem(item) then
        condition("Tooltip_weapon_Condition", item:getCurrentCondition() / 100)
        if item:hasHeadCondition() then
            condition("IGUI_health_Head", item:getHeadCondition() / item:getHeadConditionMax())
        end
        if item:hasSharpness() then condition("Tooltip_weapon_Sharpness", item:getSharpness()) end
        if item:getMaxAmmo() > 0 then
            -- Upstream always shows gun ammunition and icons when details are
            -- enabled, including the round that is already in the chamber.
            local ammo = (item:getCurrentAmmoCount() + (item:isRoundChambered() and 1 or 0)) .. "/" .. item:getMaxAmmo()
            x = x + width(item:getMaxAmmo() .. "/" .. item:getMaxAmmo()) - width(ammo)
            text(ammo)
            x = x + width(ammo) + 10
            if item:isContainsClip() then
                local magazine = ScriptManager.instance:getItem(item:getMagazineType())
                reserve(iconSize)
                ISInventoryItem.renderScriptItemIcon(pane, magazine, x, iconY, 1, iconSize, iconSize)
                x = x + iconSize + 10
            end
            local parts = item:getAllWeaponParts()
            for index = 0, parts:size() - 1 do
                reserve(iconSize)
                ISInventoryItem.renderItemIcon(pane, parts:get(index), x, iconY, 1, iconSize, iconSize)
                x = x + iconSize + 5
            end
        end
        return true
    end

    if item:getMaxAmmo() > 0 then
        local ammoLabel = getText("Tooltip_weapon_AmmoCount") .. ":"
        if showLabels then
            local ammoItem = getScriptManager():FindItem(item:getAmmoType():getItemKey())
            if ammoItem then ammoLabel = ammoItem:getDisplayName() .. ":" end
        end
        label(ammoLabel)
        local fraction = item:getCurrentAmmoCount() / item:getMaxAmmo()
        bar(fraction, progressColor(fraction))
        numeric(item:getCurrentAmmoCount() .. "/" .. item:getMaxAmmo(), item:getMaxAmmo() .. "/" .. item:getMaxAmmo())
        return true
    end

    if instanceof(item, "Food") then
        local handled = false
        local hunger = item:getHungerChange()
        if item:isIsCookable() and not item:isFrozen() and item:getHeat() > 1.6 then
            local cooking, cookAt, burnAt = item:getCookingTime(), item:getMinutesToCook(), item:getMinutesToBurn()
            local fraction = cooking / cookAt
            local cookingLabel = getText("IGUI_invpanel_Cooking") .. ":"
            if cooking > burnAt then cookingLabel = getText("IGUI_invpanel_Burnt")
            elseif cooking > cookAt then
                cookingLabel = getText("IGUI_invpanel_Burning") .. ":"
                fraction = (cooking - cookAt) / (burnAt - cookAt)
                barColor = rgb(bad)
            end
            label(cookingLabel)
            if item:isBurnt() then return true end
            bar(fraction, barColor, true)
            if showNumeric then centered(round(fraction * 100) .. "%", "100%") end
            handled = true
        elseif item:getFreezingTime() > 0 then
            local fraction = item:getFreezingTime() / 100
            label(getText("IGUI_invpanel_FreezingTime") .. ":")
            bar(fraction, {r=0, g=0, b=1, a=1})
            if showNumeric then centered(round(fraction * 100) .. "%", "100%") end
            handled = true
        elseif hunger ~= 0 then
            label(getText("IGUI_invpanel_Nutrition") .. ":")
            bar(-hunger, barColor)
            handled = true
        end
        if handled then
            if showNumeric then centered(tostring(round(hunger * 100)), "-000", rgb(good)) end
            if Options.showNutritionist:getValue() and getPlayer():hasTrait(CharacterTrait.NUTRITIONIST2) then
                local values = {round(item:getCalories()), round(item:getCarbohydrates()), round(item:getProteins()), round(item:getLipids())}
                if values[1] > 0 or values[2] > 0 or values[3] > 0 or values[4] > 0 then
                    local icons = {"calories", "carbs", "proteins", "lipids"}
                    for index, value in ipairs(values) do
                        reserve(pane.fontHgt)
                        pane:drawTextureScaled(getTexture("media/ui/PZSurvivorToolkit/item-details/" .. icons[index] .. ".png"),
                            x, textY, pane.fontHgt, pane.fontHgt, 1, 1, 1, 1)
                        x = x + pane.fontHgt + 10
                        centered(tostring(value), "0000")
                    end
                end
            end
            return true
        end
    end

    if item:isFluidContainer() or (instanceof(item:getWorldItem(), "IsoWorldInventoryObject") and item:getWorldItem():getFluidContainer()) then
        local fluidContainer = item:getFluidContainer() or item:getWorldItem():getFluidContainer()
        local amount, capacity = fluidContainer:getAmount(), fluidContainer:getCapacity()
        if showLabels then
            local fluidLabel = getText("Fluid_Empty") .. ": "
            if amount > 0 then
                local fluids, names = Fluid.getAllFluids(), {}
                for index = 0, fluids:size() - 1 do
                    local fluid = fluids:get(index)
                    if fluidContainer:contains(fluid) then names[#names + 1] = fluid:getDisplayName() end
                end
                fluidLabel = table.concat(names, "/") .. ":"
            end
            label(fluidLabel)
        end
        bar(amount / capacity, rgb(fluidContainer:getColor()))
        local amountText, capacityText = string.format("%.2f", round(amount, 2)), string.format("%.2f", round(capacity, 2))
        numeric(amountText .. "/" .. capacityText, capacityText .. "/" .. capacityText)
        return true
    end

    if instanceof(item, "Clothing") and not item:isCosmetic() then
        condition("IGUI_invpanel_Condition", item:getCurrentCondition() / 100)
        local holes = item:getHolesNumber()
        if holes > 0 then text("(" .. holes .. ")", rgb(bad)) end
        return true
    end
    return false
end

return Details
