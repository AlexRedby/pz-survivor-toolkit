require "PZSurvivorToolkit/BulkActions"
require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISEquipWeaponAction"
require "TimedActions/ISUnequipAction"
require "TimedActions/ISUnloadBulletsFromFirearm"
require "TimedActions/ISUnloadBulletsFromMagazine"
require "TimedActions/ISRemoveWeaponUpgrade"

local Toolkit = PZSurvivorToolkit
local Actions = Toolkit.BulkActions
local Bulk = {}
Toolkit.BulkFirearms = Bulk

local function unloadKind(item)
    if item:getCurrentAmmoCount() <= 0 or not item:getAmmoType() then return end
    if instanceof(item, "HandWeapon") then
        -- Native unloading leaves chambered rounds and inserted magazines to their own actions.
        if not item:getMagazineType() then return "gun" end
    elseif item:getMaxAmmo() > 0 then
        return "magazine"
    end
end

function Bulk.unloadEntries(player, rows)
    local entries = {}
    for _, item in ipairs(Actions.selectedItems(rows)) do
        local kind = unloadKind(item)
        if kind and Actions.safeItem(player, item) then
            entries[#entries + 1] = {item = item, kind = kind}
        end
    end
    return entries
end

function Bulk.attachmentEntries(player, rows)
    local entries = {}
    for _, item in ipairs(Actions.selectedItems(rows)) do
        if instanceof(item, "HandWeapon") and Actions.safeItem(player, item) then
            local detachable, parts = item:getDetachableWeaponParts(player), {}
            for i = 0, detachable:size() - 1 do parts[#parts + 1] = detachable:get(i) end
            if #parts > 0 then entries[#entries + 1] = {item = item, parts = parts} end
        end
    end
    return entries
end

-- Native callbacks may be wrapped by TidyUpMeister; retain them and intercept only their queued actions.
local function nativeQueue(player, moved, decorate, callback, ...)
    local add = ISTimedActionQueue.add
    ISTimedActionQueue.add = function(action)
        if action.Type == "ISInventoryTransferAction" and action.destContainer == player:getInventory() then
            local id = action.item:getID()
            if moved[id] then return end
            moved[id] = true
            Actions.guardTransfer(action)
        end
        decorate(action)
        return add(action)
    end
    local ok, result = pcall(callback, ...)
    ISTimedActionQueue.add = add
    if not ok then error(result) end
end

local function safeStart(player, item, ownEquip)
    if not item or not item:getContainer() or item:isFavorite() or player:isEquippedClothing(item) then
        return false
    end
    return ownEquip or (player:getPrimaryHandItem() ~= item and player:getSecondaryHandItem() ~= item)
end

function Bulk.queueUnload(player, entries)
    if not Toolkit.Settings.bulkUnload() or not player or player:isDead() then return end
    local count, moved = 0, {}
    for _, entry in ipairs(entries) do
        local item, guard = entry.item, {}
        if Actions.safeItem(player, item) and unloadKind(item) == entry.kind then
            local id = item:getID()
            nativeQueue(player, moved, function(action)
                if action.Type == "ISEquipWeaponAction" and action.item:getID() == id then
                    action.isValidStart = function(self)
                        return self:isValid() and Actions.safeItem(player, self.item)
                    end
                    local start = action.start
                    action.start = function(self)
                        -- The first action in a native queue skips isValidStart.
                        if not Actions.safeItem(player, self.item) then self:forceStop(); return end
                        guard.equipping = true
                        return start(self)
                    end
                elseif action.Type == "ISUnloadBulletsFromFirearm" or action.Type == "ISUnloadBulletsFromMagazine" then
                    -- Check before starting only: MP sends ammo changes before client completion.
                    action.isValidStart = function(self)
                        local current = player:getInventory():getItemById(id)
                        if not safeStart(player, current, guard.equipping) or unloadKind(current) ~= entry.kind then
                            return false
                        end
                        if entry.kind == "gun" then self.gun = current else self.magazine = current end
                        return self:isValid()
                    end
                end
            end, entry.kind == "gun" and ISInventoryPaneContextMenu.onUnloadBulletsFromFirearm
                or ISInventoryPaneContextMenu.onUnloadBulletsFromMagazine, player, item)
            count = count + 1
        end
    end
    return count
end

function Bulk.queueAttachments(player, entries)
    if not Toolkit.Settings.bulkRemoveAttachments() or not player or player:isDead() then return end
    local count, moved = 0, {}
    for _, entry in ipairs(entries) do
        local weapon = entry.item
        if Actions.safeItem(player, weapon) then
            for _, part in ipairs(entry.parts) do
                local partType, partID = part:getPartType(), part:getID()
                local current = weapon:getWeaponPart(partType)
                if current and current:getID() == partID and current:canDetach(player, weapon) then
                    local id = weapon:getID()
                    nativeQueue(player, moved, function(action)
                        if action.Type ~= "ISRemoveWeaponUpgrade" then return end
                        action.isValidStart = function(self)
                            local item = player:getInventory():getItemById(id)
                            if not Actions.safeItem(player, item) then return false end
                            local attached = item:getWeaponPart(partType)
                            if not attached or attached:getID() ~= partID or not attached:canDetach(player, item) then
                                return false
                            end
                            self.weapon = item
                            return self:isValid()
                        end
                    end, ISInventoryPaneContextMenu.onRemoveUpgradeWeapon, weapon, current, player)
                    count = count + 1
                end
            end
        end
    end
    return count
end

local function findOptions(menu, matches, found)
    for _, option in ipairs(menu.options) do
        if matches(option) then found[#found + 1] = {menu = menu, option = option}
        else
            local child = menu:getSubMenu(option.subOption)
            if child then findOptions(child, matches, found) end
        end
    end
end

local function fillMenu(playerIndex, context, rows)
    local player = getSpecificPlayer(playerIndex)
    if not player or player:isDead() then return end
    if Toolkit.Settings.bulkUnload() then
        local entries = Bulk.unloadEntries(player, rows)
        if #entries >= 2 then
            local found = {}
            findOptions(context, function(option)
                return option.toolkitBulkUnload or option.onSelect == ISInventoryPaneContextMenu.onUnloadBulletsFromFirearm
                    or option.onSelect == ISInventoryPaneContextMenu.onUnloadBulletsFromMagazine
            end, found)
            if #found == 0 then
                local entry = entries[1]
                local gun = entry.kind == "gun"
                local option = context:addOption(gun and getText("ContextMenu_UnloadRounds", entry.item:getDisplayName())
                    or getText("ContextMenu_UnloadMagazine"), player,
                    gun and ISInventoryPaneContextMenu.onUnloadBulletsFromFirearm
                        or ISInventoryPaneContextMenu.onUnloadBulletsFromMagazine, entry.item)
                found[1] = {menu = context, option = option}
            end
            for _, row in ipairs(found) do
                if not row.option.toolkitBulkUnload then
                    local child = Actions.submenu(row.menu, row.option, getText("UI_PZSurvivorToolkit_action_one"))
                    local option = child:addOption(getText("UI_PZSurvivorToolkit_unload_selected", #entries),
                        player, Bulk.queueUnload, entries)
                    option.iconTexture = row.option.iconTexture
                    option.itemForTexture = row.option.itemForTexture
                    row.option.toolkitBulkUnload = true
                end
            end
        end
    end
    if Toolkit.Settings.bulkRemoveAttachments() then
        local entries = Bulk.attachmentEntries(player, rows)
        if #entries == 0 then return end
        local found = {}
        findOptions(context, function(option)
            return option.toolkitBulkAttachments or option.name == getText("ContextMenu_Remove_Weapon_Upgrade")
        end, found)
        if #found == 0 then
            local entry = entries[1]
            local option = context:addOption(getText("ContextMenu_Remove_Weapon_Upgrade"), rows, nil)
            local child = context:getNew(context)
            context:addSubMenu(option, child)
            for _, part in ipairs(entry.parts) do
                child:addOption(part:getName(), entry.item, ISInventoryPaneContextMenu.onRemoveUpgradeWeapon, part, player)
            end
            found[1] = {menu = context, option = option}
        end
        for _, row in ipairs(found) do
            if not row.option.toolkitBulkAttachments then
                local child = Actions.submenu(row.menu, row.option, getText("UI_PZSurvivorToolkit_action_one"))
                child:addOption(getText("UI_PZSurvivorToolkit_remove_attachments_selected", #entries),
                    player, Bulk.queueAttachments, entries)
                row.option.toolkitBulkAttachments = true
            end
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(fillMenu)
