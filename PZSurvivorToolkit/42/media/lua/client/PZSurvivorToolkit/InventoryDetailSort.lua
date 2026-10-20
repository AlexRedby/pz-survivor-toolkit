-- Adapted from Bravo Item Details v0.0.12 by Bravo.
local config = require("PZSurvivorToolkit/InventoryDetailOptions").config
local Details = require "PZSurvivorToolkit/InventoryDetails"
local Rows = require "PZSurvivorToolkit/InventoryRows"

local Sorter = {
    condition = {
        [1] = function (a, b) return a:getCondition() > b:getCondition() end,
        [2] = function (a, b) return a:getCondition() < b:getCondition() end
    },
    uses = {
        [1] = function (a, b) return a:getCurrentUses() > b:getCurrentUses() end,
        [2] = function (a, b) return a:getCurrentUses() < b:getCurrentUses() end
    },
    ammo = {
        [1] = function (a, b) return a:getCurrentAmmoCount() > b:getCurrentAmmoCount() end,
        [2] = function (a, b) return a:getCurrentAmmoCount() < b:getCurrentAmmoCount() end
    },
    attachments = {
        [1] = function (a, b) return (a:getAllWeaponParts():size() + (a:isContainsClip() and 1 or 0)) > (b:getAllWeaponParts():size() + (b:isContainsClip() and 1 or 0)) end,
        [2] = function (a, b) return (a:getAllWeaponParts():size() + (a:isContainsClip() and 1 or 0)) < (b:getAllWeaponParts():size() + (b:isContainsClip() and 1 or 0)) end
    },
    hunger = {
        [1] = function (a, b) return a:getHungerChange() < b:getHungerChange() end,
        [2] = function (a, b) return a:getHungerChange() > b:getHungerChange() end
    },
    fluid = {
        [1] = function (a, b) return (a:getFluidContainer() or a:getWorldItem():getFluidContainer()):getAmount() > (b:getFluidContainer() or b:getWorldItem():getFluidContainer()):getAmount() end,
        [2] = function (a, b) return (a:getFluidContainer() or a:getWorldItem():getFluidContainer()):getAmount() < (b:getFluidContainer() or b:getWorldItem():getFluidContainer()):getAmount() end
    },
    clothes = {
        [1] = function (a, b) return a:getCondition() == b:getCondition() and a:getHolesNumber() > b:getHolesNumber() or a:getCondition() > b:getCondition() end,
        [2] = function (a, b) return a:getCondition() == b:getCondition() and a:getHolesNumber() < b:getHolesNumber() or a:getCondition() < b:getCondition() end
    },
    tools = {
        [1] =
        function (a, b)
            if a:getCondition() == b:getCondition() then
                if a:hasHeadCondition() and a:getHeadCondition() ~= b:getHeadCondition() then return a:getHeadCondition() > b:getHeadCondition() end
                if a:hasSharpness() and a:getSharpness() ~= b:getSharpness() then return a:getSharpness() > b:getSharpness() end
                return false
            end
            return a:getCondition() > b:getCondition()
        end,
        [2] =
        function (a, b)
            if a:getCondition() == b:getCondition() then
                if a:hasHeadCondition() and a:getHeadCondition() ~= b:getHeadCondition() then return a:getHeadCondition() < b:getHeadCondition() end
                if a:hasSharpness() and a:getSharpness() ~= b:getSharpness() then return a:getSharpness() < b:getSharpness() end
                return false
            end
            return a:getCondition() < b:getCondition()
        end
    },
    weapon = {
        [1] =
        function (a, b)
            if a:getCondition() == b:getCondition() then
                if a:getMaxAmmo() > 0 then
                    if (a:getCurrentAmmoCount() + (a:isRoundChambered() and 1 or 0)) == (b:getCurrentAmmoCount() + (b:isRoundChambered() and 1 or 0)) then
                        return (a:getAllWeaponParts():size() + (a:isContainsClip() and 1 or 0)) > (b:getAllWeaponParts():size() + (b:isContainsClip() and 1 or 0))
                    else
                        return (a:getCurrentAmmoCount() + (a:isRoundChambered() and 1 or 0)) > (b:getCurrentAmmoCount() + (b:isRoundChambered() and 1 or 0))
                    end
                else
                    if a:hasHeadCondition() and a:getHeadCondition() ~= b:getHeadCondition() then return a:getHeadCondition() > b:getHeadCondition() end
                    if a:hasSharpness() and a:getSharpness() ~= b:getSharpness() then return a:getSharpness() > b:getSharpness() end
                    return false
                end
            else
                return a:getCondition() > b:getCondition()
            end
        end,
        [2] =
        function (a, b)
            if a:getCondition() == b:getCondition() then
                if a:getMaxAmmo() > 0 then
                    if (a:getCurrentAmmoCount() + (a:isRoundChambered() and 1 or 0)) == (b:getCurrentAmmoCount() + (b:isRoundChambered() and 1 or 0)) then
                        return (a:getAllWeaponParts():size() + (a:isContainsClip() and 1 or 0)) < (b:getAllWeaponParts():size() + (b:isContainsClip() and 1 or 0))
                    else
                        return (a:getCurrentAmmoCount() + (a:isRoundChambered() and 1 or 0)) < (b:getCurrentAmmoCount() + (b:isRoundChambered() and 1 or 0))
                    end
                else
                    if a:hasHeadCondition() and a:getHeadCondition() ~= b:getHeadCondition() then return a:getHeadCondition() < b:getHeadCondition() end
                    if a:hasSharpness() and a:getSharpness() ~= b:getSharpness() then return a:getSharpness() < b:getSharpness() end
                    return false
                end
            else
                return a:getCondition() < b:getCondition()
            end
        end
    },
}

Sorter.config = config

local function sortFunction(item)
    if instanceof(item, "Drainable") and item:getUseDelta() > 0 then
        return Sorter.uses[config.usesSortDir]
    elseif instanceof(item, "HandWeapon") then
        return Sorter.weapon[config.weaponSortDir]
    elseif item:hasTag(ItemTag.SHOW_CONDITION) or item:hasTag(ItemTag.SHARPENABLE) or item:getDisplayCategory() == "Tool" then
        return Sorter.tools[config.weaponSortDir]
    elseif Details.isConditionItem(item) then
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

-- Called by the inventory owner after its class-specific native refresh.
function Sorter.refresh(pane, class, anchor)
    if not config.enableSort then return end
    local maxSort = math.floor(tonumber(config.maxSort) or class.MAX_ITEMS_IN_STACK_TO_RENDER or 50)
    if maxSort < 1 then return end
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
                -- Mutate only the bounded prefix after sorting succeeds. The
                -- dummy header and CleanUI cache follow its first real item.
                for index = 1, count do items[index + 1] = prefix[index] end
                items[1] = items[2]
                if stack.cleanUIDisplayItem then stack.cleanUIDisplayItem = items[1] end
            end
        end
    end
    for index in pairs(pane.selected) do pane.selected[index] = nil end
    pane:restoreSelection(selected)
    Rows.restoreAnchor(pane, anchor)
end

return Sorter
