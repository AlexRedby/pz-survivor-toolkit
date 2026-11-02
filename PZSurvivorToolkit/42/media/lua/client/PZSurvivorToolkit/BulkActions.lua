require "PZSurvivorToolkit/Settings"
require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISUnloadBulletsFromFirearm"
require "TimedActions/ISUnloadBulletsFromMagazine"
require "TimedActions/ISRemoveWeaponUpgrade"

local Actions = {}
PZSurvivorToolkit.BulkActions = Actions
local transferGuard = {}
-- Receipts live only on their existing guard. No module map retains actions in
-- Kahlua, where weak-table modes do not provide weak ownership.
local bindingType,bindingMeta,bindingRaw,bindingPairs,bindingEqual,bindingCall=type,getmetatable,rawget,pairs,rawequal,pcall
local bindingGlobals,bindingToolkit=_G,PZSurvivorToolkit
local bindingFilename,bindingLine=getFilenameOfClosure,getFirstLineOfClosure
local loadedProof,bindingSource=bindingCall(require,"PZSurvivorToolkit/SourceProof")
if not loadedProof then bindingSource=nil end
local bindingOrigin
if bindingType(bindingSource)=="table" and bindingMeta(bindingSource)==nil then
    bindingOrigin=bindingRaw(bindingSource,"closure")
end
local receiptKey,receiptChallenge,receiptProof={},{},{}
local bindingBusy,bindingEpoch=false,0
local bindingGuard,bindingGuarded,bindingFactory
local function receiptFor(action,guard,guardedStop,original,complete,meta)
    return function(challenge)
        if bindingEqual(challenge,receiptChallenge) then
            return receiptProof,action,guard,guardedStop,original,complete,meta
        end
    end
end
-- Its immutable multiline prototype identifies the pure receipt role before a
-- public callback is invoked. Other same-file callbacks may execute effects.
local sampleReceipt=receiptFor()
local function bindingOwn(owner,key)
    if bindingType(owner)~="table" then return nil end
    if bindingMeta(owner)==nil then
        -- Native Kahlua rawget can return no values for an absent field.
        local value=bindingRaw(owner,key);return value
    end
    local count=0
    for name,value in bindingPairs(owner) do
        count=count+1
        if count>128 then return nil end
        if bindingEqual(name,key) then return value end
    end
    return nil
end
local function actionBinding(action)
    local stop,guard,complete,safe
    local count=0
    for key,value in bindingPairs(action) do
        count=count+1
        if count>128 then return nil end
        if bindingEqual(key,"stop") then stop=value
        elseif bindingEqual(key,"toolkitTransferGuard") then guard=value
        elseif bindingEqual(key,"onCompleteFunc") then complete=value
        elseif bindingEqual(key,"toolkitQueueSafeOnComplete") then safe=value end
    end
    return stop,guard,complete,safe,bindingMeta(action)
end
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

function Actions.guardTransfer(transfer, allowNativeMerge)
    local guard = transfer.toolkitTransferGuard
    -- Returns retain their singleton guard. Pickup observers may keep native
    -- merging and revoke their own authority if later siblings join the batch.
    -- Always preserve an existing owner's callback.
    local ownedComplete
    if allowNativeMerge ~= true and not transfer.onCompleteFunc then
        local callback=function() end
        transfer:setOnComplete(callback)
        local installedComplete=transfer.onCompleteFunc
        transfer.toolkitQueueSafeOnComplete = installedComplete
        if bindingEqual(installedComplete,callback) then ownedComplete=callback end
    end
    if guard and guard.marker == transferGuard and transfer.stop == guard.stop then return transfer end
    local stop = transfer.stop
    local guardedStop = function(self)
        local execution = PZSurvivorToolkit.ActionQueueExecution
        if execution then execution.beforeStop(self) end
        local pickup = PZSurvivorToolkit.ActionQueuePickupFailure
        if pickup then pickup.beforeStop(self) end
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
    local ownedGuard = {marker = transferGuard, stop = guardedStop, original = stop}
    ownedGuard[receiptKey]=receiptFor(transfer,ownedGuard,guardedStop,stop,ownedComplete,bindingMeta(transfer))
    transfer.toolkitTransferGuard = ownedGuard
    return transfer
end

function Actions.isGuardedTransfer(action, originalStop)
    local guard = action.toolkitTransferGuard
    return guard and guard.marker == transferGuard and action.stop == guard.stop and guard.original == originalStop
end

-- Prepare before final native facts. The returned one-use lease reads only own
-- Lua fields and identities; it never invokes the receipt, metadata or gameplay.
bindingFactory=function(action,originalStop,effectiveStop)
    bindingEpoch=bindingEpoch+1
    local epoch=bindingEpoch
    if bindingBusy or bindingType(action)~="table" or bindingType(originalStop)~="function"
        or bindingType(bindingSource)~="table" or bindingMeta(bindingSource)~=nil
        or bindingType(bindingOrigin)~="function" or bindingType(bindingFilename)~="function"
        or bindingType(bindingLine)~="function" then return nil end
    local stop,guard,complete,safe,meta=actionBinding(action)
    local layer=effectiveStop
    if layer==nil then layer=stop end
    if bindingType(layer)~="function" then return nil end
    if bindingType(guard)~="table" or bindingMeta(guard)~=nil or bindingType(stop)~="function"
        or bindingType(complete)~="function" or not bindingEqual(complete,safe)
        or not bindingEqual(bindingOwn(guard,"marker"),transferGuard)
        or not bindingEqual(bindingOwn(guard,"stop"),layer)
        or not bindingEqual(bindingOwn(guard,"original"),originalStop) then return nil end
    local receipt=bindingOwn(guard,receiptKey)
    if bindingType(receipt)~="function" then return nil end
    local function unchanged()
        if bindingMeta(bindingGlobals)~=nil or bindingMeta(bindingToolkit)~=nil
            or bindingMeta(Actions)~=nil or bindingMeta(bindingSource)~=nil
            or not bindingEqual(bindingOwn(bindingGlobals,"PZSurvivorToolkit"),bindingToolkit)
            or not bindingEqual(bindingOwn(bindingToolkit,"BulkActions"),Actions)
            or not bindingEqual(bindingOwn(Actions,"guardTransfer"),bindingGuard)
            or not bindingEqual(bindingOwn(Actions,"isGuardedTransfer"),bindingGuarded)
            or not bindingEqual(bindingOwn(Actions,"transferBinding"),bindingFactory)
            or not bindingEqual(bindingOwn(bindingSource,"closure"),bindingOrigin)
            or not bindingEqual(bindingOwn(bindingGlobals,"getFilenameOfClosure"),bindingFilename)
            or not bindingEqual(bindingOwn(bindingGlobals,"getFirstLineOfClosure"),bindingLine)
            or bindingMeta(guard)~=nil then return false end
        local observedStop,observedGuard,observedComplete,observedSafe,observedMeta=actionBinding(action)
        if not bindingEqual(observedStop,stop) or not bindingEqual(observedGuard,guard)
            or not bindingEqual(observedComplete,complete) or not bindingEqual(observedSafe,safe)
            or not bindingEqual(observedMeta,meta) then return false end
        local count=0
        for key,value in bindingPairs(guard) do
            count=count+1
            if count>4 then return false end
            if bindingEqual(key,"marker") then if not bindingEqual(value,transferGuard) then return false end
            elseif bindingEqual(key,"stop") then if not bindingEqual(value,layer) then return false end
            elseif bindingEqual(key,"original") then if not bindingEqual(value,originalStop) then return false end
            elseif bindingEqual(key,receiptKey) then if not bindingEqual(value,receipt) then return false end
            else return false end
        end
        return count==4
    end
    if not unchanged() then return nil end
    bindingBusy=true
    local ok,proof,owner,ownedGuard,ownedStop,ownedOriginal,ownedComplete,ownedMeta=bindingCall(function()
        -- Proof.closure memoizes callbacks. Only this nil-bound sample may enter
        -- its shared cache; per-action receipts must not retain actions there.
        if not bindingOrigin(sampleReceipt,"BulkActions.lua") then return nil end
        local expectedFile,observedFile=bindingFilename(sampleReceipt),bindingFilename(receipt)
        if bindingType(expectedFile)~="string" or not bindingEqual(expectedFile,observedFile) then return nil end
        local expectedLine,observedLine=bindingLine(sampleReceipt),bindingLine(receipt)
        if bindingType(expectedLine)~="number" or expectedLine<1 or expectedLine%1~=0
            or not bindingEqual(expectedLine,observedLine) or bindingEpoch~=epoch or not unchanged() then return nil end
        return receipt(receiptChallenge)
    end)
    bindingBusy=false
    if not ok or bindingEpoch~=epoch or not bindingEqual(proof,receiptProof) or not bindingEqual(owner,action)
        or not bindingEqual(ownedGuard,guard) or not bindingEqual(ownedStop,layer)
        or not bindingEqual(ownedOriginal,originalStop) or not bindingEqual(ownedComplete,complete)
        or not bindingEqual(ownedMeta,meta) or not unchanged() then return nil end
    -- This describes only the sealed Bulk layer. The caller must separately
    -- prove any outer stop and any wrapped original before composing a chain.
    local description={wrappedStop=layer,stop=originalStop,onComplete=complete}
    local used=false
    return function()
        if used then return false end
        used=true
        if bindingMeta(description)~=nil or not bindingEqual(bindingOwn(description,"wrappedStop"),layer)
            or not bindingEqual(bindingOwn(description,"stop"),originalStop)
            or not bindingEqual(bindingOwn(description,"onComplete"),complete) then return false end
        local count=0
        for _ in bindingPairs(description) do count=count+1;if count>3 then return false end end
        return count==3 and unchanged()
    end,description
end
Actions.transferBinding=bindingFactory
bindingGuard,bindingGuarded=Actions.guardTransfer,Actions.isGuardedTransfer

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

local sourceAdapters=PZSurvivorToolkit.ActionQueueItemEditAdapters
if sourceAdapters and sourceAdapters.registerSourceFactory then
    sourceAdapters.registerSourceFactory(Actions,"transferBinding",Actions.transferBinding)
end
return Actions
