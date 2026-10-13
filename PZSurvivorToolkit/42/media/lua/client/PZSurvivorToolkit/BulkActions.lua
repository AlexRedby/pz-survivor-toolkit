require "PZSurvivorToolkit/Settings"
require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISUnloadBulletsFromFirearm"
require "TimedActions/ISUnloadBulletsFromMagazine"
require "TimedActions/ISRemoveWeaponUpgrade"

local Actions = {}
PZSurvivorToolkit.BulkActions = Actions
local transferGuard = {}
local bulkMethods = {"new", "start", "update", "stop", "perform", "complete", "isValid", "getDuration",
    "animEvent", "serverStart", "serverStop", "forceStop", "forceCancel"}
local nativeBulk = {}
for _, name in ipairs({"ISUnloadBulletsFromFirearm", "ISUnloadBulletsFromMagazine", "ISRemoveWeaponUpgrade"}) do
    local class = _G[name]
    if class then
        local methods = {}
        for _, method in ipairs(bulkMethods) do methods[method] = class[method] end
        nativeBulk[class] = methods
    end
end

function Actions.canFinish(action)
    local class = getmetatable(action)
    local methods = nativeBulk[class]
    if not action.toolkitIndependentBulk or not methods or action.Type ~= class.Type then return false end
    for _, method in ipairs(bulkMethods) do if action[method] ~= methods[method] then return false end end
    return not action.onStartFunc and not action.onCompleteFunc and not action.onCancelFunc
end

function Actions.safeItem(player, item)
    return item and item:getContainer() and not item:isFavorite()
        and not player:isEquippedClothing(item)
        and player:getPrimaryHandItem() ~= item and player:getSecondaryHandItem() ~= item
end

function Actions.selectedItems(rows)
    local items, seen = {}, {}
    local function add(item)
        if not instanceof(item, "InventoryItem") then return end
        local id = item:getID()
        if not seen[id] then
            seen[id] = true
            items[#items + 1] = item
        end
    end
    for _, row in ipairs(rows) do
        if instanceof(row, "InventoryItem") then add(row)
        elseif row.items then
            -- Native groups duplicate the first item; CleanUI virtual groups do not.
            for _, item in ipairs(row.items) do add(item) end
        end
    end
    return items
end

function Actions.guardTransfer(transfer)
    -- Keep this guard when an ordinary pickup is already queued.
    transfer:setOnComplete(function() end)
    transfer.toolkitQueueSafeOnComplete = transfer.onCompleteFunc
    local stop = transfer.stop
    local guardedStop = function(self)
        -- B42 cancellation uses a client-local ID without an owner on the server.
        if isClient() and self.transactionId ~= 0
            and isItemTransactionRejected(self.transactionId)
            and not isItemTransactionDone(self.transactionId) then
            removeItemTransaction(self.transactionId, false)
            self.transactionId = 0
        end
        return stop(self)
    end
    transfer.stop = guardedStop
    transfer.toolkitTransferGuard = {marker = transferGuard, stop = guardedStop, original = stop}
    return transfer
end

function Actions.isGuardedTransfer(action, originalStop)
    local guard = action.toolkitTransferGuard
    return guard and guard.marker == transferGuard and action.stop == guard.stop and guard.original == originalStop
end

function Actions.transfer(player, item)
    if not luautils.haveToBeTransfered(player, item) then return end
    local transfer = Actions.guardTransfer(ISInventoryTransferUtil.newInventoryTransferAction(player,
        item, item:getContainer(), player:getInventory()))
    ISTimedActionQueue.add(transfer)
    return transfer
end

function Actions.submenu(menu, option, oneLabel)
    local submenu = menu:getSubMenu(option.subOption)
    if not submenu then
        submenu = menu:getNew(menu)
        local single = submenu:addOption(oneLabel, option.target, option.onSelect,
            option.param1, option.param2, option.param3, option.param4, option.param5,
            option.param6, option.param7, option.param8, option.param9, option.param10)
        for _, key in ipairs({"iconTexture", "itemForTexture", "color", "toolTip", "notAvailable"}) do
            single[key] = option[key]
        end
        option.toolkitOriginalOnSelect = option.onSelect
        option.onSelect = nil
        menu:addSubMenu(option, submenu)
    end
    return submenu
end

return Actions
