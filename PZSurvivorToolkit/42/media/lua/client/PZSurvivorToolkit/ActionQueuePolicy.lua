require "PZSurvivorToolkit/ActionQueueDefinitions"
require "PZSurvivorToolkit/SetStoveStateAction"
require "Fluids/ISFluidContainer"
require "Fluids/ISFluidTransferAction"
require "Fluids/ISFluidEmptyAction"
require "TimedActions/ISActivateGenerator"
require "TimedActions/ISFixGenerator"
require "TimedActions/ISTransferAction"
require "TimedActions/ISEatFoodAction"
require "TimedActions/ISDrinkFluidAction"
require "TimedActions/ISWashClothing"
require "TimedActions/ISWashYourself"
require "TimedActions/ISDryMyself"
require "TimedActions/ISRemoveCarBatteryFromChargerAction"
require "TimedActions/ISTakeCarBatteryChargerAction"

local Toolkit = PZSurvivorToolkit
local Grooming = require 'PZSurvivorToolkit/ActionQueueGrooming'
Toolkit.ActionQueueGrooming = Grooming
local adoptGroomingBase = Grooming and Grooming.adoptBase
local Makeup = require 'PZSurvivorToolkit/ActionQueueMakeup'
local Policy = {}
Toolkit.ActionQueuePolicy = Policy
local Operations = Toolkit.ActionQueueOperations
local nativeForceCancel = ISBaseTimedAction.forceCancel
local Proof = require "PZSurvivorToolkit/SourceProof"
local EditModel = require "PZSurvivorToolkit/ActionQueueEditModel"
local EditAdapters = require "PZSurvivorToolkit/ActionQueueEditAdapters"
local ItemEditAdapters = require "PZSurvivorToolkit/ActionQueueItemEditAdapters"
local Weights = require "PZSurvivorToolkit/ActionQueueWeights"
local Firearms = require "PZSurvivorToolkit/ActionQueueFirearms"
local rackResources = Firearms and Firearms.rack
local nativePendingCancelProof
local function nativePendingCancelHasNoEffects()
    if nativePendingCancelProof == nil then
        if not Proof or type(getGameFilesInput) ~= "function" or type(getFilenameOfClosure) ~= "function" then return false end
        nativePendingCancelProof = Proof.closure(nativeForceCancel, "ISBaseTimedAction.lua")
            and Proof.matches("media/lua/shared/TimedActions/ISBaseTimedAction.lua", 3104185167, nil, true)
    end
    return nativePendingCancelProof and ISBaseTimedAction.forceCancel == nativeForceCancel
end
local nativeTransferItem = ISTransferAction and ISTransferAction.transferItem
local nativeDropItemOffset = ISTransferAction and ISTransferAction.GetDropItemOffset
local transferItemGuard
local inspect
-- Private, synchronous decision lifetime; never stored on an action or descriptor.
local activeDecision
local ordinaryTransfer
-- Record evidence only at an existing rejecting gate. Raw reason APIs and their
-- tuple layout stay compatible; public decisions can explain the same denial.
local function clearDenial(context)
    context.denialGate, context.denialReason, context.denialBlocker = nil, nil, nil
end
local function deny(context, gate, reason, blocker)
    context.denialGate, context.denialReason, context.denialBlocker = gate, reason, blocker
    return gate
end
local function unknownDenial(context, gate, action)
    local facts = context.contracts[action]
    return deny(context, gate, (action._isAddingActions or (facts and facts.inFlight))
        and "edit_in_flight" or "edit_unknown", action)
end
local function protectedDenial(context, gate, action)
    local facts = context.contracts[action]
    if facts and facts.requiredCleanup then return deny(context, gate, "edit_required_cleanup", action) end
    return gate
end
local pendingReturnReason, pendingReturnGuard
local function pendingReturnTarget(queue, action)
    return action.Type == "ISInventoryTransferAction" and action.allowMissingItems == true
        and action.srcContainer == queue.character:getInventory()
        and action.destContainer ~= action.srcContainer and action ~= queue.current
        and not action.action and queue:indexOf(action) > 1
end
local sharedEditResource
local targetCheckers = {}
local targetModules = {world = "ActionQueueWorld", generators = "ActionQueueGenerators"}

-- Owned modules register their original helper at definition time. A later
-- override or module replacement cannot silently extend this negative proof.
function Policy.registerTargetChecker(kind, owner, callback)
    local name = targetModules[kind]
    if not name or targetCheckers[kind] or type(owner) ~= "table" or owner ~= Toolkit[name]
        or type(callback) ~= "function" or owner.sharesTarget ~= callback then return false end
    targetCheckers[kind] = {owner = owner, callback = callback}
    return true
end

local function targetCheckersUnchanged()
    for kind, name in pairs(targetModules) do
        local owner, saved = Toolkit[name], targetCheckers[kind]
        if owner and owner.sharesTarget then
            if not saved or saved.owner ~= owner or saved.callback ~= owner.sharesTarget then return false end
        elseif saved then return false end
    end
    return true
end

local function craft(action)
    return Toolkit.ActionQueueCraft and Toolkit.ActionQueueCraft.supports(action)
end

Policy.isCraftAction = craft

local function live(queue)
    local player = queue.character
    return player and getSpecificPlayer(player:getPlayerNum()) == player
        and not player:isDead() and not player:isAsleep()
end

local function resumableWorld(action)
    if action and Toolkit.ActionQueueWorld and Toolkit.ActionQueueWorld.canResume then
        return Toolkit.ActionQueueWorld.canResume(action)
    end
end

local function independentBulk(action, context)
    local contract = inspect and inspect(action, context)
    return action.toolkitIndependentBulk and contract and contract.bulk == true
end

local function stoppable(action, context)
    local contract = inspect and inspect(action, context)
    return (contract and (contract.interrupt == "audited-stop" or contract.interrupt == "audited-resume"))
        or resumableWorld(action) or craft(action)
end

local function deferredWorld(action)
    return action.Type == "ISQueueActionsAction" and Toolkit.ActionQueueWorld
        and type(Toolkit.ActionQueueWorld.isDeferredAction) == "function"
        and Toolkit.ActionQueueWorld.isDeferredAction(action)
end
Policy.isDeferredWorldAction = deferredWorld

local function appliance(action)
    local world = Toolkit.ActionQueueWorld
    return world and world.isApplianceAction and world.isApplianceAction(action)
end

function Policy.cancelReason(queue, action, context)
    context = context or {contracts = {}, items = {}}
    clearDenial(context)
    if not Toolkit.Settings.actionQueue() or not queue or not live(queue)
        or queue:indexOf(action) == -1 then return "unavailable" end
    if queue.toolkitCancel or queue.toolkitGroupCancel then return "stopping" end
    if craft(action) then return Policy.cancelOperationReason(queue, action, context) end
    if appliance(action) then return Policy.cancelOperationReason(queue, action, context) end
    local contract = inspect and inspect(action, context)
    if contract and contract.cancelOperation == false then return protectedDenial(context, "dependent", action) end
    if pendingReturnTarget(queue, action) then return pendingReturnReason(queue, action, context) end
    if action.Type == "ISQueueActionsAction" then
        if not deferredWorld(action) and not (contract and contract.deferred) then return unknownDenial(context, "dependent", action) end
        return Policy.cancelOperationReason(queue, action, context)
    end
    local auditedCallbacks = contract and contract.callbacksSafe
    if action._isAddingActions or (action.onStartFunc and not craft(action) and not auditedCallbacks)
        or ((action.onCompleteFunc or action.onCancelFunc) and not resumableWorld(action) and not craft(action) and not auditedCallbacks)
        or action.retriggerLastAction or action.toolkitQueueLinked then
        if action._isAddingActions or not action.toolkitQueueLinked then return unknownDenial(context, "dependent", action) end
        return "dependent"
    end
    if not stoppable(action, context) and contract and contract.cancelWaiting then return Policy.cancelOperationReason(queue, action, context) end
    if not stoppable(action, context) and not independentBulk(action, context) then
        if not contract then return unknownDenial(context, "dependent", action) end
        return "dependent"
    end
    if independentBulk(action, context) then
        -- A later arbitrary craft/generator may require this operation's output.
        for i = queue:indexOf(action) + 1, #queue.queue do
            local following = queue.queue[i]
            if not following.toolkitIndependentBulk and not following.toolkitBulkPreparation
                and following.Type ~= "ISReadABook"
                and following.Type ~= "ISInventoryTransferAction" then return "dependent" end
        end
    end
    if action == queue.current or queue.queue[1] == action then
        -- These native stop paths clean up visuals/sound; materials and outputs belong to completion.
        if not stoppable(action, context) then return "active" end
        if not action.action or not action.action:isStarted() or action.action:finished() or action.action:isForceComplete() then
            return "starting"
        end
    elseif action.action then
        return "active"
    end
end

local itemFields = {"item", "gun", "magazine", "weapon", "primary", "secondary"}
local function itemKey(item)
    return instanceof(item, "InventoryItem") and item:getID() or item
end
local operationItems
local function sharedItem(a, b, context)
    local left, right = operationItems(a, context), operationItems(b, context)
    for item in pairs(left) do if right[item] then return item end end
    local leftContract, rightContract = inspect(a, context), inspect(b, context)
    local owners = leftContract and leftContract.containerOwners
    if owners then for item in pairs(owners) do if right[item] then return item end end end
    owners = rightContract and rightContract.containerOwners
    if owners then for item in pairs(owners) do if left[item] then return item end end end
end

local function knownCraftInputs(action, context)
    if action.toolkitWorldOperation == "fuel" or action.toolkitWorldOperation == "wreck" then return false end
    if craft(action) and not Toolkit.ActionQueueCraft.futureResources then return Toolkit.ActionQueueCraft.collectItems(action, {}) end
    local contract = inspect(action, context)
    return contract ~= nil and contract.knownInputs ~= false
end

local function dynamicConflict(a, b, context)
    local left, right = inspect(a, context), inspect(b, context)
    if not left or not right then return false end
    local dynamic = left.dynamicInputsByType
    if dynamic then
        for kind in pairs(dynamic) do
            if right.unknownOutputs or (right.dynamicInputsByType and right.dynamicInputsByType[kind]) then return kind end
            for _, types in pairs({right.itemTypes, right.dynamicInputs, right.outputTypes}) do
                for fullType in pairs(types) do
                    if fullType:match("[^.]+$") == kind then return kind end
                end
            end
        end
    end
    if left.dynamicInputs then
        for kind in pairs(left.dynamicInputs) do
            if right.unknownOutputs then return true end
            if (right.itemTypes and right.itemTypes[kind]) or (right.dynamicInputs and right.dynamicInputs[kind])
                or (right.outputTypes and right.outputTypes[kind]) then return kind end
        end
    end
    local outputs = left.outputTypes
    if outputs then
        for kind in pairs(outputs) do
            if (right.itemTypes and right.itemTypes[kind]) or (right.outputTypes and right.outputTypes[kind]) then return kind end
        end
    end
    return false
end

-- Audited property setters are independent of VHS inventory/playback effects.
-- Playback retains its asynchronous native state; this only removes a disjoint
-- target edge, never power/media ordering, item or capacity dependencies.
local mediaSetterModes = {SetVolume = true, SetChannel = true, MuteMicrophone = true,
    MuteVolume = true, UnMuteVolume = true}
local function mediaSetterIndependent(a, b, context)
    local setter, media = a, b
    if not mediaSetterModes[setter.mode] then setter, media = b, a end
    if not mediaSetterModes[setter.mode] or not EditAdapters then return false end
    local edit = EditAdapters.radio(setter)
    if not edit or not instanceof(setter.device, "IsoTelevision") then return false end
    if not inspect then return false end
    local contract, source = inspect(media, context)
    local cassette = source == "native.device-media-insert" or source == "native.device-media-eject"
    local playback = source == "native.ISRadioAction" and media.mode == "TogglePlayMedia"
        and media.device == setter.device and EditAdapters.radioCallbacksTrusted(media) and media.maxTime == 30
    if not contract or not (cassette and media.Type == "ISDeviceMediaAction" or playback)
        or media.character ~= setter.character
        or media.action or media.started or media._isAddingActions
        or (type(media.toolkitQueueOperation) == "table" and media.toolkitQueueOperation.toolkitStarted)
        or media.deviceData ~= setter.deviceData or setter.deviceData:getParent() ~= setter.device then return false end
    local targetCount = 0
    for target in pairs(contract.targets or {}) do
        if target ~= setter.device then return false end
        targetCount = targetCount + 1
    end
    return targetCount == 1
end

local function sharedWorldTarget(a, b, context)
    local generators = Toolkit.ActionQueueGenerators
    if generators and generators.sharesTarget then
        local target = generators.sharesTarget(a, b, context)
        if target then return target end
    end
    local left, right = inspect and inspect(a, context), inspect and inspect(b, context)
    if left and right then
        if sharedEditResource and sharedEditResource(left, right) then return true end
        if not context or (a ~= context.failurePositionPrerequisite and b ~= context.failurePositionPrerequisite) then
            local positions = left.positions
            if positions then
                for actor in pairs(positions) do if right.positions and right.positions[actor] then return actor end end
            end
        end
        local targets = left.targets
        if targets then
            for target in pairs(targets) do
                if right.targets and right.targets[target] and not mediaSetterIndependent(a, b, context) then return target end
            end
        end
        if left.hands and left.hands == right.hands then return left.hands end
        if (left.equipment and left.equipment == right.hands) or (right.equipment and right.equipment == left.hands) then return left.equipment or right.equipment end
    end
    local world = Toolkit.ActionQueueWorld
    if world and world.sharesTarget and world.sharesTarget(a, b) then return true end
    -- Capture every source field before any object callback, as the original
    -- sparse array did. Most comparisons have no spatial fields at all.
    local generator, charger, object, moveObject, worldTarget, isoObject =
        a.generator, a.charger, a.object, a.moveProps and a.moveProps.object, a.toolkitWorldTarget, a.isoObject
    if not (generator or charger or object or moveObject or worldTarget or isoObject) then return end
    local objects = {generator, charger, object, moveObject, worldTarget, isoObject}
    for i = 1, 6 do
        local object = objects[i]
        if object and instanceof(object, "IsoObject") and (object == b.generator or object == b.charger
            or object == b.object or (b.moveProps and object == b.moveProps.object)
            or object == b.toolkitWorldTarget or object == b.isoObject) then return true end
    end
end

local groupPreparation = {
    ISWalkToTimedAction = true, ISWalkToTimedActionF = true, ISPathFindAction = true,
    ISEquipWeaponAction = true, ISEquipHeavyItem = true, ISUnequipAction = true,
}

local preparationMethods = {"start", "stop", "perform", "complete", "isValid", "update", "forceStop", "forceCancel"}
local nativePreparation = {}
for kind in pairs(groupPreparation) do
    local class = _G[kind]
    if class then
        local methods = {}
        for _, name in ipairs(preparationMethods) do methods[name] = class[name] end
        nativePreparation[class] = methods
    end
end
local transferMethods = {}
for _, name in ipairs(preparationMethods) do transferMethods[name] = ISInventoryTransferAction[name] end
nativePreparation[ISInventoryTransferAction] = transferMethods

local function preparationCanFinish(action, context)
    if action.Type == "ISInventoryTransferAction" and ordinaryTransfer and not ordinaryTransfer(action) then return false end
    local contract = inspect and inspect(action, context)
    if contract and contract.preparationFinish then return true end
    if appliance(action) then return true end
    if Toolkit.BulkActions.canFinish and Toolkit.BulkActions.canFinish(action) then return true end
    local methods = nativePreparation[getmetatable(action)]
    if not methods then return false end
    for _, name in ipairs(preparationMethods) do
        if action[name] ~= methods[name] and not (name == "stop" and action.Type == "ISInventoryTransferAction"
            and Toolkit.BulkActions.isGuardedTransfer(action, methods.stop)) then return false end
    end
    return true
end

operationItems = function(action, context)
    if context and context.items[action] then return context.items[action] end
    local items = {}
    for _, key in ipairs(itemFields) do
        local item = action[key]
        if item and instanceof(item, "InventoryItem") then items[item] = true end
    end
    if action.recipeItem and instanceof(action.recipeItem, "InventoryItem") then items[action.recipeItem] = true end
    if Toolkit.ActionQueueCraft then Toolkit.ActionQueueCraft.collectItems(action, items) end
    local keys = {}
    for item in pairs(items) do keys[itemKey(item)] = true end
    local contract = inspect and inspect(action, context)
    if contract then for key in pairs(contract.items or {}) do keys[key] = true end end
    if context then context.items[action] = keys end
    return keys
end

local repairIndependent = {}
for _, class in ipairs({ISReadABook, ISRadioAction}) do
    local methods = {}
    for _, name in ipairs(preparationMethods) do methods[name] = class[name] end
    repairIndependent[class] = methods
end
local radioModes = {ToggleOnOff = true, SetChannel = true, MuteVolume = true, UnMuteVolume = true,
    SetVolume = true, MuteMicrophone = true, TogglePlayMedia = true}
local radioMethods = {}
if ISRadioAction then
    for mode in pairs(radioModes) do
        for _, prefix in ipairs({"isValid", "start", "perform"}) do
            local name = prefix .. mode
            radioMethods[name] = ISRadioAction[name] or false
        end
    end
end

local function repairInputs(action)
    local helper = Toolkit.ActionQueueCraft
    return helper and helper.repairInputs and helper.repairInputs(action)
end

local function repairCanCross(repair, other, context)
    local types = repairInputs(repair)
    if not types then return true end
    if other.onStartFunc or other.onCompleteFunc or other.onCancelFunc or other.retriggerLastAction then return false end
    local methods = repairIndependent[getmetatable(other)]
    if methods then
        for _, name in ipairs(preparationMethods) do
            if other[name] ~= methods[name] then return false end
        end
        if getmetatable(other) == ISRadioAction then
            if not radioModes[other.mode] then return false end
            for name, method in pairs(radioMethods) do
                if (other[name] or false) ~= method then return false end
            end
        end
    elseif (other.Type ~= "ISInventoryTransferAction" and other.Type ~= "ISWalkToTimedAction"
        and other.Type ~= "ISWalkToTimedActionF" and other.Type ~= "ISPathFindAction") or not preparationCanFinish(other, context) then
        -- shortcut: craft/world outputs and other repairs can supply new donors; audit their outputs before allowing a crossing.
        return false
    end
    local function independent(item)
        if not item or not instanceof(item, "InventoryItem") then return true end
        return not instanceof(item, "InventoryContainer") and not types[item:getFullType()]
            and item:getID() ~= repair.item:getID()
    end
    for _, name in ipairs(itemFields) do if not independent(other[name]) then return false end end
    if not independent(other.device) or not independent(other.secondaryItem) then return false end
    for _, batch in ipairs(other.queueList or {}) do
        for _, item in ipairs(batch.items) do if not independent(item) then return false end end
    end
    return true
end

local function craftPlan(action)
    return action.Type == "ISQueueActionsAction" and action.toolkitCraftPlanCancellation == true
        and Toolkit.CraftChainRecipes and type(Toolkit.CraftChainRecipes.addStep) == "function"
        and action.addActionsFunction == Toolkit.CraftChainRecipes.addStep
end
Policy.isCraftPlanAction = craftPlan

-- Presentation entries never grant permission to edit native actions.
local Definitions = Toolkit.ActionQueueDefinitions
local snapshots = {}
local transferFloorHelper
local transferMethodsAdopted = false
local transferHelperGuards = {}
local function carriedContainers(container, character, presenceOnly)
    if not instanceof(character, "IsoPlayer") then return end
    local chain = not presenceOnly and {}
    local seen
    while instanceof(container, "ItemContainer") and (not seen or not seen[container]) do
        local kind = container:getType()
        if kind == "floor" or kind == "proximityInv" or kind == "twistInv_corpses" then return end
        if chain then chain[#chain + 1] = container end
        if container == character:getInventory() then return chain or true end
        seen = seen or {}
        seen[container] = true
        local bag = container:getContainingItem()
        if not instanceof(bag, "InventoryContainer") then return end
        container = bag:getContainer()
    end
end
local function ordinaryTransferContainer(container, character)
    if not instanceof(container, "ItemContainer") then return false end
    local kind = container:getType()
    if kind == "floor" or kind == "proximityInv" or kind == "twistInv_corpses" then return false end
    local bag = container:getContainingItem()
    if not bag then return true end
    return carriedContainers(container, character, true) ~= nil
        or ItemEditAdapters and type(ItemEditAdapters.worldContainer) == "function"
            and ItemEditAdapters.worldContainer(container, character) ~= nil
end
local function transferHelpersMatch()
    if not transferMethodsAdopted then return true end
    for _, guard in ipairs(transferHelperGuards) do if not guard() then return false end end
    return true
end
ordinaryTransfer = function(action)
    if not transferHelpersMatch() then return false end
    if not transferMethodsAdopted then return true end
    return ordinaryTransferContainer(action.srcContainer, action.character)
        and ordinaryTransferContainer(action.destContainer, action.character)
end
Policy.isOrdinaryTransfer = ordinaryTransfer
function Policy.adoptTransferItemHelper(previous, replacement, helpersUnchanged, previousOffset, replacementOffset)
    if type(previous) ~= "function" or nativeTransferItem ~= previous
        or type(replacement) ~= "function" or type(helpersUnchanged) ~= "function"
        or type(ISTransferAction) ~= "table" or ISTransferAction.transferItem ~= replacement
        or not helpersUnchanged() then return false end
    local before, after = {transferItem = previous}, {transferItem = replacement}
    if previousOffset ~= nil or replacementOffset ~= nil then
        if type(previousOffset) ~= "function" or nativeDropItemOffset ~= previousOffset
            or type(replacementOffset) ~= "function" or ISTransferAction.GetDropItemOffset ~= replacementOffset then return false end
        before.GetDropItemOffset, after.GetDropItemOffset = previousOffset, replacementOffset
        nativeDropItemOffset = replacementOffset
    end
    nativeTransferItem, transferItemGuard = replacement, helpersUnchanged
    if ItemEditAdapters then ItemEditAdapters.adoptMethods(ISTransferAction, before, after, helpersUnchanged) end
    return true
end
local lifecycle = {"new", "isValid", "isValidStart", "waitToStart", "start", "update", "stop", "perform", "complete",
    "getDuration", "serverStart", "serverStop", "animEvent", "forceStop", "forceCancel"}
local function callbacksSafe(action)
    return not action.onStartFunc and not action.onCancelFunc and not action.retriggerLastAction
        and not action.onFailFunc and not action.additionalTest
        and (not action.onCompleteFunc or (action.Type == "ISInventoryTransferAction"
            and action.onCompleteFunc == action.toolkitQueueSafeOnComplete and action.toolkitTransferGuard
            and Toolkit.BulkActions and Toolkit.BulkActions.isGuardedTransfer(action, action.toolkitTransferGuard.original)))
end
local function nativeMatches(action, snapshot, observingCleanup)
    local binding = snapshot.binding
    if binding then
        return binding.guard() and binding.applies(action)
            and nativeMatches(action, binding.variant, observingCleanup)
    end
    if getmetatable(action) ~= snapshot.class or action.Type ~= snapshot.class.Type or not callbacksSafe(action) then return false end
    if snapshot.startHelperGuard and not snapshot.startHelperGuard() then return false end
    if snapshot.class == ISInventoryTransferAction then
        if not transferHelpersMatch() then return false end
        if not ordinaryTransfer(action) and not observingCleanup then
            local settlement = Toolkit.ActionQueueSettlement
            if not settlement or type(settlement.isCleanupPickup) ~= "function"
                or not settlement.isCleanupPickup(action) then return false end
        end
    end
    for _, name in ipairs(lifecycle) do
        if action[name] ~= snapshot.methods[name] and not (name == "stop" and action.Type == "ISInventoryTransferAction"
            and Toolkit.BulkActions and Toolkit.BulkActions.isGuardedTransfer(action, snapshot.methods.stop)) then return false end
    end
    for name, value in pairs(snapshot.helpers) do
        if (action[name] or false) ~= value then
            local audited = snapshot.class == ISInventoryTransferAction and name == "getNotFullFloorSquare"
                and transferFloorHelper and value == transferFloorHelper.previous
                and action[name] == transferFloorHelper.replacement
                and instanceof(action.destContainer, "ItemContainer") and action.destContainer:getType() ~= "floor"
            if not audited then return false end
        end
    end
    return true
end
-- Reuse the installed native/approved-mod binding contract without resolving behavior descriptors.
function Policy.matchesNative(action)
    local snapshot = snapshots[getmetatable(action)]
    return snapshot ~= nil and nativeMatches(action, snapshot)
end
-- Binding verification only: this does not grant queue edit permission. Shared
-- settlement must separately prove the exact earned drop/current cleanup owner.
function Policy.matchesCleanupPickupBinding(action)
    local snapshot = snapshots[getmetatable(action)]
    return snapshot ~= nil and snapshot.class == ISInventoryTransferAction
        and action.srcContainer and action.srcContainer:getType() == "floor"
        and action.destContainer == action.character:getInventory()
        and nativeMatches(action, snapshot, true)
end
local resourceItemFields = {"item", "gun", "magazine", "weapon", "primary", "secondary", "secondaryItem", "recipeItem", "device", "battery"}
local function resources(action)
    local result = {items = {}, itemTypes = {}, targets = {}, cancelWaiting = true, interrupt = "finish-step"}
    for _, field in ipairs(resourceItemFields) do
        local item = action[field]
        if item and instanceof(item, "InventoryItem") then
            result.items[itemKey(item)] = true
            if item.getFullType then result.itemTypes[item:getFullType()] = true end
        end
    end
    return result
end
local function registerNative(name, inspector, helpers, applies)
    local class = _G[name]
    if not class or snapshots[class] then return end
    local snapshot = {class = class, methods = {}, helpers = {}}
    for _, method in ipairs(lifecycle) do snapshot.methods[method] = class[method] end
    for method, callback in pairs(class) do
        if type(callback) == "function" and snapshot.methods[method] == nil then snapshot.helpers[method] = callback end
    end
    for _, method in ipairs(helpers or {}) do snapshot.helpers[method] = class[method] or false end
    snapshots[class] = snapshot
    Definitions.registerBehavior("native." .. name, {
        types = {name},
        -- Family-owned native cleanup must not claim unrelated uses of the same class.
        matches = function(action)
            local scope = activeDecision
            local proven = scope and scope.native[action] == snapshot
            return (proven or nativeMatches(action, snapshot)) and (not applies or applies(action))
        end,
        inspect = inspector,
    })
end
Policy.registerNative = registerNative

local function unequipVariant(previous, replacement, guard)
    local snapshot = snapshots[ISUnequipAction]
    if not snapshot or type(previous) ~= "table" or type(replacement) ~= "table"
        or type(guard) ~= "function" or not guard() then return end
    local variant = {class = snapshot.class, methods = {}, helpers = snapshot.helpers}
    for name, method in pairs(snapshot.methods) do variant.methods[name] = method end
    for _, name in ipairs({"new", "complete"}) do
        if snapshot.methods[name] ~= previous[name] or ISUnequipAction[name] ~= replacement[name]
            or type(replacement[name]) ~= "function" then return end
        variant.methods[name] = replacement[name]
    end
    return variant, snapshot
end
function Policy.nativeUnequipVariant(previous, replacement, guard)
    local variant = unequipVariant(previous, replacement, guard)
    if not variant then return end
    return function(action) return guard() and nativeMatches(action, variant) end
end
-- One canonical preparation binding for an audited delegate branch. Family
-- contracts still own instance wrappers and required cleanup; cart branches fail
-- applies and can never fall back to the pre-wrapper native snapshot.
function Policy.adoptNativeUnequipVariant(previous, replacement, guard, applies)
    if type(applies) ~= "function" then return false end
    local variant, snapshot = unequipVariant(previous, replacement, guard)
    if not variant then return false end
    local binding = snapshot.binding
    if binding then
        return binding.guard == guard and binding.applies == applies
            and binding.variant.methods.new == variant.methods.new
            and binding.variant.methods.complete == variant.methods.complete
    end
    snapshot.binding = {variant = variant, guard = guard, applies = applies}
    return true
end

function Policy.adoptTransferHooks(previous, replacement, guard)
    local snapshot = snapshots[ISInventoryTransferAction]
    local preparation = nativePreparation[ISInventoryTransferAction]
    if not snapshot then return false,"missing_contract" end
    if type(guard) ~= "function" then return false,"missing_guard" end
    local available,reason=guard()
    if not available then return false,reason or "guard_changed" end
    for _, name in ipairs({"new", "perform"}) do
        if snapshot.methods[name] ~= previous[name] then return false,"previous_"..name end
        if ISInventoryTransferAction[name] ~= replacement[name] then return false,"current_"..name end
        if type(previous[name]) ~= "function" or type(replacement[name]) ~= "function" then return false,"invalid_"..name end
    end
    if snapshot.helpers.transferItem ~= (previous.transferItem or false) then return false,"previous_transferItem" end
    if ISInventoryTransferAction.transferItem ~= replacement.transferItem then return false,"current_transferItem" end
    for _, name in ipairs({"new", "perform"}) do snapshot.methods[name] = replacement[name] end
    snapshot.helpers.transferItem = replacement.transferItem or false
    if preparation then preparation.perform = replacement.perform end
    transferMethodsAdopted = true
    transferHelperGuards[#transferHelperGuards + 1] = guard
    if ItemEditAdapters then ItemEditAdapters.adoptMethods(ISInventoryTransferAction, previous, replacement, guard) end
    return true
end

function Policy.adoptMoveablesConstructor(previous, replacement)
    local snapshot = snapshots[ISMoveablesAction]
    if not snapshot or type(previous) ~= "function" or type(replacement) ~= "function"
        or snapshot.methods.new ~= previous or ISMoveablesAction.new ~= replacement then return false end
    snapshot.methods.new = replacement
    return true
end

function Policy.adoptReadAnimEvent(previous, replacement)
    local snapshot = snapshots[ISReadABook]
    if not snapshot or snapshot.methods.animEvent ~= previous or ISReadABook.animEvent ~= replacement
        or type(previous) ~= "function" or type(replacement) ~= "function" then return false end
    snapshot.methods.animEvent = replacement
    return true
end

function Policy.adoptConsumeStarts(previous, helpersUnchanged)
    if not ISEatFoodAction or not ISDrinkFluidAction or type(previous) ~= "table"
        or type(helpersUnchanged) ~= "function" or not helpersUnchanged() then return false end
    local classes = {ISEatFoodAction, ISDrinkFluidAction}
    for _, class in ipairs(classes) do
        local snapshot = snapshots[class]
        if not snapshot or snapshot.methods.start ~= previous[class]
            or type(previous[class]) ~= "function" or type(class.start) ~= "function" then return false end
    end
    for _, class in ipairs(classes) do
        local snapshot = snapshots[class]
        snapshot.methods.start, snapshot.startHelperGuard = class.start, helpersUnchanged
    end
    if ItemEditAdapters then
        for _,class in ipairs(classes) do
            ItemEditAdapters.adoptMethods(class,{start = previous[class]}, {start = class.start}, helpersUnchanged)
        end
    end
    return true
end

function Policy.adoptTransferQueueObserver(previous,replacement)
    local snapshot=snapshots[ISInventoryTransferAction]
    local intent=Toolkit.ActionQueueTidyIntent
    if not snapshot or snapshot.helpers.checkQueueList~=previous or ISInventoryTransferAction.checkQueueList~=replacement
        or not intent or not intent.isQueueObserver(previous,replacement) then return false end
    snapshot.helpers.checkQueueList=replacement
    if ItemEditAdapters then ItemEditAdapters.adoptMethods(ISInventoryTransferAction,
        {checkQueueList=previous}, {checkQueueList=replacement}, function()return intent.isQueueObserver(previous,replacement)end) end
    return true
end

function Policy.adoptTransferFloorHelper(previous, replacement)
    local snapshot = snapshots[ISInventoryTransferAction]
    if not snapshot or snapshot.helpers.getNotFullFloorSquare ~= previous
        or ISInventoryTransferAction.getNotFullFloorSquare ~= replacement
        or type(previous) ~= "function" or type(replacement) ~= "function" then return false end
    -- The native transfer ignores the helper's square for a non-floor destination.
    transferFloorHelper = {previous = previous, replacement = replacement}
    if ItemEditAdapters then ItemEditAdapters.adoptMethods(ISInventoryTransferAction,
        {getNotFullFloorSquare = previous}, {getNotFullFloorSquare = replacement}, function()
            return ISInventoryTransferAction.getNotFullFloorSquare == replacement
        end) end
    return true
end

function Policy.adoptTransferMethods(previous, replacement, helpersUnchanged)
    local snapshot = snapshots[ISInventoryTransferAction]
    local preparation = nativePreparation[ISInventoryTransferAction]
    if not snapshot or type(previous) ~= "table" or type(replacement) ~= "table"
        or getmetatable(previous) or getmetatable(replacement) or type(helpersUnchanged) ~= "function"
        or not helpersUnchanged() then return false end
    for _, name in ipairs({"isValid", "start", "perform", "stop"}) do
        if snapshot.methods[name] ~= previous[name] or ISInventoryTransferAction[name] ~= replacement[name]
            or type(previous[name]) ~= "function" or type(replacement[name]) ~= "function"
            or (preparation and preparation[name] ~= previous[name]) then return false end
    end
    for _, name in ipairs({"isValid", "start", "perform", "stop"}) do
        snapshot.methods[name] = replacement[name]
        if preparation then preparation[name] = replacement[name] end
    end
    transferMethodsAdopted = true
    transferHelperGuards[#transferHelperGuards + 1] = helpersUnchanged
    if ItemEditAdapters then ItemEditAdapters.adoptMethods(ISInventoryTransferAction, previous, replacement, helpersUnchanged) end
    return true
end

local function itemResources(action)
    if not action.item or not instanceof(action.item, "InventoryItem") then return end
    return resources(action)
end

function Policy.addContainerResources(result, container)
    if not instanceof(container, "ItemContainer") then return end
    local seen = {}
    while instanceof(container, "ItemContainer") and not seen[container] do
        seen[container] = true
        if container.getAcceptItemFunction and container:getAcceptItemFunction() ~= nil then
            result.knownInputs, result.cancelWaiting, result.cancelOperation = false, false, false
        end
        local parent = container:getParent()
        if parent and not instanceof(parent, "IsoGameCharacter") then result.targets[parent] = true end
        local bag = container.getContainingItem and container:getContainingItem()
        if not instanceof(bag, "InventoryContainer") then return end
        result.containerOwners = result.containerOwners or {}
        result.containerOwners[bag:getID()] = true
        result.itemTypes[bag:getFullType()] = true
        container = bag:getContainer()
    end
    if container then result.knownInputs = false end
end

local function transferResources(action, context)
    local result = itemResources(action)
    if not result then return end
    if instanceof(action.item, "InventoryContainer") then result.knownInputs = false end
    for _, batch in ipairs(action.queueList or {}) do
        for _, item in ipairs(batch.items or {}) do
            result.items[itemKey(item)] = true
            if instanceof(item, "InventoryItem") then result.itemTypes[item:getFullType()] = true end
            if instanceof(item, "InventoryContainer") then result.knownInputs = false end
        end
    end
    -- Native transfers switch microwaves off; their container owner is a shared world resource.
    for _, container in pairs({source = action.srcContainer, destination = action.destContainer}) do
        Policy.addContainerResources(result, container)
    end
    if ItemEditAdapters then
        result.edit = ItemEditAdapters.transfer(action)
        if result.edit and (not carriedContainers(action.srcContainer,action.character,true)
            or not carriedContainers(action.destContainer,action.character,true)) then result.positions={[action.character]=true} end
    end
    return result
end
Policy.transferResources = transferResources
local function targetResources(action)
    if action.Type == "ISSetComboWasherDryerMode" and action.mode ~= "washer" and action.mode ~= "dryer" then return end
    if action.Type == "ISActivateGenerator" and type(action.activate) ~= "boolean" then return end
    if action.Type == "PZSurvivorToolkitSetStoveState" and type(action.desired) ~= "boolean" then return end
    local result = resources(action)
    local target = action.generator or action.charger or action.object or action.stove or action.mcwave
    if not target then return end
    result.targets[target] = true
    return result
end
local function fluidResources(action)
    local result = resources(action)
    local wrappers = action.Type == "ISFluidTransferAction" and {action.source, action.target} or {action.container}
    for i = 1, action.Type == "ISFluidTransferAction" and 2 or 1 do
        local wrapper = wrappers[i]
        -- Read fields of the native wrapper: getters on an unknown mod wrapper can have side effects.
        if not ISFluidContainer or type(wrapper)~="table" or getmetatable(wrapper) ~= ISFluidContainer then return end
        local fluid,resource=rawget(wrapper,"fluidContainer"),rawget(wrapper,"fluidResource")
        if not instanceof(fluid, "FluidContainer") then return end
        if rawget(wrapper,"isFluidResource") then
            if not instanceof(resource, "ResourceFluid") then return end
        elseif resource then return end
        local owner = rawget(wrapper,"isFluidResource") and resource:getGameEntity() or fluid:getOwner()
        if not owner then return end
        if instanceof(owner, "InventoryItem") then
            result.items[itemKey(owner)], result.itemTypes[owner:getFullType()] = true, true
        else result.targets[owner] = true end
        if resource then result.targets[resource] = true end
    end
    if action.Type=="ISFluidEmptyAction" and ItemEditAdapters and type(ItemEditAdapters.emptyFluid)=="function" then
        result.edit=ItemEditAdapters.emptyFluid(action)
        if result.edit then
            -- The captured emptying peak is bounded by current full weight;
            -- completion's released fluid is never a capacity credit.
            result.capacityNonIncreasing=true
            Policy.addContainerResources(result,action.container.fluidContainer:getOwner():getContainer())
        end
    end
    return result
end
local function radioResources(action, projectionIndependent)
    if not radioModes[action.mode] then return end
    for name, method in pairs(radioMethods) do if (action[name] or false) ~= method then return end end
    local result = resources(action)
    local target = action.device or action.deviceData
    if target and not instanceof(target, "InventoryItem") then result.targets[target] = true end
    if EditAdapters and projectionIndependent ~= true then result.edit = EditAdapters.radio(action) end
    return result
end
local function dryItem(item)
    return instanceof(item, "DrainableComboItem") and (item:getType() == "BathTowel" or item:getType() == "DishCloth")
end
local function hygieneResources(action)
    local dry = action.Type == "ISDryMyself"
    if not instanceof(action.character, "IsoPlayer") then return end
    if (dry or action.Type == "ISWashClothing") and not instanceof(action.item, "InventoryItem") then return end
    if not dry and not instanceof(action.sink, "IsoObject") then return end
    local result = resources(action)
    result.preparationFinish, result.unknownOutputs = true, true
    if dry or action.Type == "ISWashYourself" then result.targets[action.character] = true end
    if dry then
        if not dryItem(action.item) then
            local kind = action.item:getFullType()
            if kind ~= "Base.BathTowelWet" and kind ~= "Base.DishClothWet" then return end
            -- MP replaces queued towel fields with the wet output; this is skip-only, never editable work.
            result.cancelWaiting, result.cancelOperation, result.knownInputs, result.preparationFinish = false, false, false, false
        end
        return result
    end
    result.targets[action.sink] = true
    if instanceof(action.sink, "IsoWorldInventoryObject") then
        local item = action.sink:getItem()
        if not instanceof(item, "InventoryItem") then return end
        result.items[itemKey(item)], result.itemTypes[item:getFullType()] = true, true
    end
    if not instanceof(action.soaps, "List") then return end
    result.dynamicInputs = {}
    for i = 0, action.soaps:size() - 1 do
        local soap = action.soaps:get(i)
        if not instanceof(soap, "InventoryItem") then return end
        result.items[itemKey(soap)], result.itemTypes[soap:getFullType()] = true, true
        result.dynamicInputs[soap:getFullType()] = true
    end
    -- Server constructors select soap again; body washing also removes current makeup.
    if action.Type == "ISWashYourself" or not action.noSoap
        or (not instanceof(action.item, "Clothing") and not instanceof(action.item, "InventoryContainer")
            and not action.item:getItemAfterCleaning()) then result.knownInputs = false end
    return result
end

function Policy.hygieneUnavailable(action)
    local kind = action and action.Type
    if kind ~= "ISDryMyself" and kind ~= "ISWashClothing" and kind ~= "ISWashYourself" then return false end
    local snapshot = snapshots[getmetatable(action)]
    if not snapshot or not nativeMatches(action, snapshot) or not hygieneResources(action) then return false end
    if kind == "ISDryMyself" then
        if action.character:getStats():get(CharacterStat.WETNESS) <= 0 then return true end
        -- Running MP drying deliberately leaves item depletion to the authoritative server tick.
        if isClient() and action.started then return false end
        local inventory = action.character:getInventory()
        local item = action.item
        if isClient() then item = inventory:getItemById(item:getID())
        elseif not inventory:contains(item) then return true end
        return not item or not dryItem(item) or item:getCurrentUsesFloat() <= 0
    end
    local sink = action.sink
    if not sink:getSquare() then return true end
    local index = instanceof(sink, "IsoWorldInventoryObject") and sink:getWorldObjectIndex() or sink:getObjectIndex()
    if index < 0 then return true end
    if kind == "ISWashYourself" then return action.sink:getFluidAmount() <= 0 end
    local inventory = action.character:getInventory()
    return action.sink:getFluidAmount() < action.GetRequiredWater(action.item)
        or (isClient() and not inventory:getItemById(action.item:getID()))
        or (not isClient() and action.item:getContainer() ~= inventory)
end

function Policy.skipUnavailableHygiene(queue)
    local action = queue.queue[2]
    while action and not action.action and Policy.hygieneUnavailable(action) do
        table.remove(queue.queue, 2)
        action:forceCancel()
        action = queue.queue[2]
    end
end

function Policy.installContracts()
    registerNative("ISDrinkFluidAction", function(action)
        local result = itemResources(action)
        if result and action.fluidContainer and action.fluidContainer == action.item:getFluidContainer() then
            if action.item:getContainer() ~= action.character:getInventory() then
                Policy.addContainerResources(result, action.item:getContainer())
            end
            if ItemEditAdapters then result.edit = ItemEditAdapters.drink(action) end
            if ItemEditAdapters and not ItemEditAdapters.fullnessNeutralDrink(action) then
                result.targets[action.character]=true
            end
            return result
        end
    end, {"updateEat", "setOverrideHandModels"})
    registerNative("ISEatFoodAction", function(action)
        local edit,fullOutput
        if ItemEditAdapters then edit,fullOutput=ItemEditAdapters.food(action) end
        if edit then
            local result=resources(action)
            result.edit=edit
            local extraFoodWeight=action.item:haveExtraItems()
            result.capacityNonIncreasing=not fullOutput and not extraFoodWeight
                and not (action.item:getReplaceOnUse() or action.item:getScriptItem():getReplaceOnUse())
            -- Replacement food decreases in weight only while it survives every
            -- portion. A transfer edit can otherwise bypass the food component.
            -- Native full replacement adds its output before removing food;
            -- Host may temporarily retain both. Do not use the surviving-food
            -- conditional bypass for any transfer prefix containing this step.
            result.capacityRequiresEdit=not fullOutput and not result.capacityNonIncreasing
            if fullOutput then
                result.outputTypes={[fullOutput]=true}
                result.capacityReplacement=true
            end
            result.targets[action.character]=true
            for _,resource in ipairs(edit.resources) do
                if resource.domain=="item" then
                    local item=resource.facts.item
                    result.items[itemKey(item)],result.itemTypes[item:getFullType()]=true,true
                    Policy.addContainerResources(result,item:getContainer())
                end
            end
            return result
        end
        local Food = Toolkit.BulkFood
        if not Food or not Food.isEat(action) then return end
        local result = resources(action)
        result.preparationFinish, result.unknownOutputs = true, true
        return result
    end, {"setOverrideHandModels"})
    registerNative("ISReadABook", function(action)
        local result = itemResources(action)
        if result then result.interrupt = "audited-resume" end
        return result
    end)
    registerNative("ISMoveablesAction", function(action)
        if action.mode ~= "scrap" or not action.moveProps then return end
        local result = resources(action)
        result.interrupt, result.unknownOutputs = "audited-stop", true
        if action.moveProps.object then result.targets[action.moveProps.object] = true end
        return result
    end)
    registerNative("ISRackFirearm", function(action)
        if Firearms and Toolkit.ActionQueueFirearms == Firearms and Firearms.rack == rackResources then return rackResources(action) end
    end)
    registerNative("ISInventoryTransferAction", transferResources)
    registerNative("ISRadioAction", radioResources)
    for _, name in ipairs({"ISWalkToTimedAction", "ISWalkToTimedActionF", "ISPathFindAction"}) do
        registerNative(name, function(action)
            local result = resources(action); result.cancelWaiting, result.preparation = false, true
            result.positions={[action.character]=true}; return result
        end)
    end
    for _, name in ipairs({"ISEquipWeaponAction", "ISEquipHeavyItem", "ISUnequipAction"}) do
        registerNative(name, function(action)
            local result = itemResources(action)
            if result then
                result.hands = action.character; result.cancelWaiting, result.preparation = false, true
                local snapshot = snapshots[getmetatable(action)]
                if snapshot and snapshot.binding then result.preparationFinish = true end
            end
            return result
        end)
    end
    for _, name in ipairs({"ISRemoveCarBatteryFromChargerAction",
        "ISTakeCarBatteryChargerAction", "ISConnectCarBatteryToChargerAction", "ISToggleStoveAction",
        "PZSurvivorToolkitSetStoveState", "ISToggleClothingWasher", "ISToggleClothingDryer", "ISToggleComboWasherDryer", "ISSetComboWasherDryerMode", "ISOvenUITimedAction"}) do
        registerNative(name, targetResources)
    end
    registerNative("ISFluidTransferAction", fluidResources)
    registerNative("ISFluidEmptyAction", fluidResources, {"updateEmpty"})
    registerNative("ISDryMyself", hygieneResources)
    registerNative("ISWashYourself", hygieneResources, {"setOverrideHandModels", "setActionAnim"})
    -- WashFix completion/returns require the separately verified source-owned contract.
    if ISWashClothing and not ISWashClothing._wmiPatchedReturnContainer then
        registerNative("ISWashClothing", hygieneResources, {"setOverrideHandModels", "setActionAnim"})
    end
    if Grooming then Grooming.install(Policy, resources) end
    if Makeup then Makeup.install(Policy, resources) end
end
Policy.installContracts()
if Events.OnGameStart then Events.OnGameStart.Add(Policy.installContracts) end

Definitions.registerBehavior("toolkit.craft", {types = {"ISFixAction", "ISFixVehiclePartAction", "ISCraftAction", "ISHandcraftAction"}, matches = craft, inspect = function(action)
    local result = resources(action)
    local items = {}
    result.knownInputs = Toolkit.ActionQueueCraft.collectItems(action, items)
    result.dynamicInputs = repairInputs(action)
    if action.vehiclePart then result.targets[action.vehiclePart] = true end
    for item in pairs(items) do
        result.items[itemKey(item)] = true
        if instanceof(item, "InventoryItem") then result.itemTypes[item:getFullType()] = true end
    end
    result.unknownOutputs = true
    local future = Toolkit.ActionQueueCraft.futureResources and Toolkit.ActionQueueCraft.futureResources(action)
    if future then
        result.knownInputs, result.unknownOutputs = true, false
        result.dynamicInputs, result.outputTypes, result.equipment = future.dynamicInputs, future.outputTypes, future.equipment
        if action.isoObject then result.targets[action.isoObject] = true end
    elseif Toolkit.ActionQueueCraft.futureResources and (action.Type == "ISCraftAction" or action.Type == "ISHandcraftAction") then
        result.knownInputs = false
    end
    return result
end})
Definitions.registerBehavior("toolkit.world", {types = {"ISQueueActionsAction", "ISBuildAction", "ISMoveablesAction"}, matches = function(action)
    return deferredWorld(action) or (resumableWorld(action) and (not snapshots[getmetatable(action)]
        or not nativeMatches(action, snapshots[getmetatable(action)])))
end, inspect = function(action)
    local result = resources(action)
    local target = action.toolkitWorldTarget or action.object or (action.moveProps and action.moveProps.object)
    if target then result.targets[target] = true end
    return result
end})
Definitions.registerBehavior("toolkit.bulk", {types = {"ISUnloadBulletsFromFirearm", "ISUnloadBulletsFromMagazine", "ISRemoveWeaponUpgrade"}, matches = function(action)
    return Toolkit.BulkActions and Toolkit.BulkActions.canFinish and Toolkit.BulkActions.canFinish(action)
end, inspect = function(action)
    local result = resources(action); result.unknownOutputs, result.bulk = true, true; return result
end})

Definitions.registerBehavior("toolkit.approach", {types = {"ISQueueActionsAction"}, matches = function(action)
    local approach=Toolkit.ActionQueueApproach
    return approach and approach.isAction(action)
end, inspect = function(action)
    local result=resources(action)
    result.deferred,result.preparation,result.preparationFinish=true,true,true
    result.cancelWaiting=true
    result.positions={[action.character]=true}
    result.capacityNonIncreasing=true
    return result
end})

Definitions.registerBehavior("toolkit.food", {types = {"ISQueueActionsAction"}, matches = function(action)
    local Food = Toolkit.BulkFood
    return Food and (Food.isCommand(action) or (Food.isOpeningWait and Food.isOpeningWait(action)))
end, inspect = function(action)
    local result = resources(action)
    result.deferred, result.preparationFinish, result.unknownOutputs = true, true, true
    return result
end})

inspect = function(action, context)
    local override = context and context.failureOverrides and context.failureOverrides[action]
    if override then return unpack(override, 1, 3) end
    local cached = context and context.contracts[action]
    if cached then return unpack(cached, 1, 3) end
    if action._isAddingActions or (Operations.isContinuationPending and Operations.isContinuationPending(action.toolkitQueueOperation)) then
        if context then context.contracts[action] = {inFlight = true} end
        return
    end
    local result = {Definitions.inspect(action, context)}
    local settlement = Toolkit.ActionQueueSettlement
    if result[1] and settlement and settlement.requiredStep(action) then
        local contract = {}
        for key, value in pairs(result[1]) do contract[key] = value end
        contract.cancelOperation, contract.cancelWaiting = false, false
        result[1] = contract
        result.requiredCleanup = true
    end
    if context then context.contracts[action] = result end
    return unpack(result, 1, 3)
end
Policy.inspect = inspect

-- Expand the changed operations to their whole dependency component, including
-- an unchanged prefix and downstream users. The model may prove a different
-- final state legal; it does not require the old and new orders to commute.
-- Incomplete components retain the existing conservative resource policy.
sharedEditResource = function(left, right)
    left, right = left.edit, right.edit
    if type(left) ~= "table" or type(right) ~= "table" or getmetatable(left) or getmetatable(right)
        or type(left.resources) ~= "table" or type(right.resources) ~= "table"
        or getmetatable(left.resources) or getmetatable(right.resources) then return false end
    for _, a in pairs(left.resources) do
        for _, b in pairs(right.resources) do
            if type(a) == "table" and type(b) == "table" and not getmetatable(a) and not getmetatable(b)
                and type(a.domain) == "string" and a.domain == b.domain and a.key ~= nil and rawequal(a.key, b.key) then return true end
        end
    end
    return false
end

local function emptyResourceMap(value)
    if value == nil then return true end
    if type(value) ~= "table" or getmetatable(value) then return false end
    for _ in pairs(value) do return false end
    return true
end

local pairResourceMaps = {"targets", "positions", "dynamicInputs", "dynamicInputsByType", "outputTypes"}
local spatialFields = {"generator", "charger", "object", "moveProps", "toolkitWorldTarget", "isoObject",
    "toolkitWorldX", "toolkitGeneratorCommand", "toolkitWorldCommand", "stove", "mcwave"}
local function plainItemFootprint(action, context, connectivity)
    local contract = inspect(action, context)
    if type(contract) ~= "table" or getmetatable(contract)
        or (contract.knownInputs ~= nil and contract.knownInputs ~= true)
        or contract.unknownOutputs or (not connectivity and contract.edit ~= nil) or contract.hands or contract.equipment
        or type(contract.items) ~= "table" or getmetatable(contract.items)
        or (contract.itemTypes ~= nil and (type(contract.itemTypes) ~= "table" or getmetatable(contract.itemTypes)))
        or (not connectivity and (action.Type == "ISInventoryTransferAction" or action.Type == "ISCartTransferAction"))
        or repairInputs(action) then return end
    if connectivity then
        if contract.containerOwners ~= nil and (type(contract.containerOwners) ~= "table" or getmetatable(contract.containerOwners)) then return end
    elseif not emptyResourceMap(contract.containerOwners) then return end
    for _, name in ipairs(pairResourceMaps) do if not emptyResourceMap(contract[name]) then return end end
    for _, name in ipairs(spatialFields) do if action[name] ~= nil then return end end
    return operationItems(action, context)
end

-- Only eliminate pairs whose complete legacy footprint is item IDs. Anything
-- unknown, spatial, dynamic, projected, repairing or capacity-sensitive keeps
-- the original ordered pair checks, including their exact diagnostic result.
local function plainGroupItems(queue, first, last, context)
    if not targetCheckersUnchanged() then return end
    local items = {}
    for index = first, last do
        local footprint = plainItemFootprint(queue.queue[index], context)
        if not footprint then return end
        for item in pairs(footprint) do items[item] = true end
    end
    return items
end

local function mayShareGroupResource(items, other, context)
    if not items then return true end
    local footprint = plainItemFootprint(other, context)
    if not footprint or not targetCheckersUnchanged() then return true end
    for item in pairs(footprint) do if items[item] then return true end end
    return false
end

local function connectivityFootprint(action, context)
    local items = plainItemFootprint(action, context, true)
    if not items then return end
    local contract = inspect(action, context)
    local edit = contract.edit
    local footprint = {items = items, owners = contract.containerOwners or {}, edits = {}}
    if edit == nil then return footprint end
    if type(edit) ~= "table" or getmetatable(edit) or edit.version ~= 1 or edit.complete ~= true
        or (edit.capacity ~= "unchanged" and edit.capacity ~= "external")
        or type(edit.resources) ~= "table" or getmetatable(edit.resources) then return end
    for index, resource in pairs(edit.resources) do
        if type(index) ~= "number" or index < 1 or index % 1 ~= 0 or index > #edit.resources
            or type(resource) ~= "table" or getmetatable(resource) or type(resource.domain) ~= "string"
            or resource.key == nil or (type(resource.key) == "number" and (resource.key ~= resource.key
                or resource.key == math.huge or resource.key == -math.huge)) then return end
        local keys = footprint.edits[resource.domain] or {}
        footprint.edits[resource.domain] = keys
        keys[resource.key] = true
    end
    return footprint
end

local function addConnectivity(index, footprint)
    for item in pairs(footprint.items) do index.items[item] = true end
    for owner in pairs(footprint.owners) do index.owners[owner] = true end
    for domain, keys in pairs(footprint.edits) do
        local aggregate = index.edits[domain] or {}
        index.edits[domain] = aggregate
        for key in pairs(keys) do aggregate[key] = true end
    end
end

local function mayConnect(index, footprint)
    if not index or not footprint or not targetCheckersUnchanged() then return true end
    for item in pairs(footprint.items) do if index.items[item] or index.owners[item] then return true end end
    for owner in pairs(footprint.owners) do if index.items[owner] then return true end end
    for domain, keys in pairs(footprint.edits) do
        local aggregate = index.edits[domain]
        if aggregate then for key in pairs(keys) do if aggregate[key] then return true end end end
    end
    return false
end

local function editComponent(queue, members, component, context)
    if not EditModel then return {status = "unhandled"} end
    local contracts = {}
    for _, member in ipairs(members) do
        local contract = inspect(member, context)
        -- Unknown callbacks/selectors can reach resources outside their reported
        -- footprint. They cannot be dismissed as an independent empty action.
        if not contract or contract.knownInputs == false or contract.unknownOutputs then
            return {status = "unhandled", reason = "edit_unknown", blocker = member}
        end
        contracts[member] = contract
    end
    -- Capacity validation remains downstream. Connectivity only names shared
    -- items, item owners and declared edit resources; owner-owner references
    -- alone do not connect independent transfers through the same carried bag.
    local footprints, index = {}, nil
    if targetCheckersUnchanged() then
        index = {items = {}, owners = {}, edits = {}}
        for _, member in ipairs(members) do footprints[member] = connectivityFootprint(member, context) or false end
        for member in pairs(component) do
            if not footprints[member] then index = nil; break end
            addConnectivity(index, footprints[member])
        end
    end
    local changed = true
    while changed do
        changed = false
        for _, member in ipairs(members) do
            if not component[member] and mayConnect(index, footprints[member]) then
                for related in pairs(component) do
                    if sharedEditResource(contracts[member], contracts[related])
                        or sharedItem(member, related, context) or sharedWorldTarget(member, related, context)
                        or dynamicConflict(member, related, context) or dynamicConflict(related, member, context) then
                        component[member], changed = true, true
                        if index then
                            if footprints[member] then addConnectivity(index, footprints[member])
                            else index = nil end
                        end
                        break
                    end
                end
            end
        end
    end
    local externalCapacity = false
    for member in pairs(component) do
        local contract, token = contracts[member], member.toolkitQueueOperation
        if member.character ~= queue.character or (type(token) == "table" and token.toolkitCancelled) then
            return {status = "denied", reason = "unavailable", blocker = member}
        end
        if not contract.edit or (contract.edit.capacity ~= "unchanged" and contract.edit.capacity ~= "external") then
            return {status = "unhandled", reason = "edit_unknown", blocker = member}
        end
        externalCapacity = externalCapacity or contract.edit.capacity == "external"
        if member == queue.current or member.action or (type(token) == "table" and token.toolkitStarted) then
            -- Live state already includes an unknown fraction of an in-flight
            -- effect. Never project that action again from the live snapshot.
            return {status = "unhandled", reason = "edit_in_flight", blocker = member}
        end
    end
    return {status = "allowed", contracts = contracts, component = component, externalCapacity = externalCapacity}
end

local function evaluateComponent(projection, entries)
    local result = EditModel.evaluate(entries)
    result.externalCapacity = projection.externalCapacity
    -- A declared contract with an unsupported schema is not permission to use
    -- a less complete legacy footprint. No valid proof was obtained for it.
    if result.status == "unhandled" then result.status = "denied" end
    return result
end

local function proposedEdit(queue, first, last, to, context)
    local selected, component = {}, {}
    for i = first, last do
        local member = queue.queue[i]
        local contract = inspect(member, context)
        if not contract or not contract.edit then return {status = "unhandled"} end
        selected[member], component[member] = true, true
    end
    local projection = editComponent(queue, queue.queue, component, context)
    if projection.status ~= "allowed" then return projection end
    local contracts = projection.contracts
    local entries = {}
    local function add(member)
        if component[member] then entries[#entries + 1] = {action = member, edit = contracts[member].edit} end
    end
    for i = 1, #queue.queue + 1 do
        if i == to then for j = first, last do add(queue.queue[j]) end end
        if i <= #queue.queue and not selected[queue.queue[i]] then add(queue.queue[i]) end
    end
    if not to then
        for i = first, last do
            local member = queue.queue[i]
            entries[#entries + 1] = {action = member, edit = contracts[member].edit, snapshotOnly = true}
        end
    end
    return evaluateComponent(projection, entries)
end

local capacityNeutral = {ISReadABook = true, ISWalkToTimedAction = true, ISWalkToTimedActionF = true, ISPathFindAction = true}
local function carriedContainer(container, character)
    return carriedContainers(container, character, true) ~= nil
end
Policy.isCarriedContainer = carriedContainer

local function finiteWeight(value)
    return type(value) == "number" and value >= 0 and value < math.huge
end

local waterPropertyEffects = {"getFatigueChange", "getHungerChange", "getStressChange", "getUnhappyChange",
    "getCalories", "getCarbohydrates", "getLipids", "getProteins", "getAlcohol", "getPoison",
    "getFluReduction", "getPainReduction", "getEnduranceChange", "getFoodSicknessChange"}
local function boundedWaterDrink(action, character, source)
    -- Clean water only reduces bottle weight and thirst. Keep every transfer's full current weight;
    -- neither consumption nor cancellation grants additional space in this projection.
    if source ~= "native.ISDrinkFluidAction" or action.character ~= character or action.useUtensil ~= false then return false end
    local fluid = action.fluidContainer
    if not instanceof(fluid, "FluidContainer") or not Fluid or not Fluid.Water
        or not fluid:isPureFluid(Fluid.Water) or fluid:isTainted() or fluid:isPoisonous() then return false end
    local amount, capacity, ratio = fluid:getAmount(), fluid:getCapacity(), fluid:getFilledRatio()
    if not finiteWeight(amount) or amount == 0 or not finiteWeight(capacity) or amount > capacity
        or not finiteWeight(ratio) or ratio == 0 or ratio > 1 then return false end
    for _, field in ipairs({"percentage", "startRatio", "endRatio", "targetConsumedRatio", "consumedRatio"}) do
        if not finiteWeight(action[field]) or action[field] > 1 then return false end
    end
    if action.percentage == 0 or action.startRatio == 0 or action.endRatio > ratio or ratio > action.startRatio
        or action.consumedRatio > action.targetConsumedRatio or action.targetConsumedRatio > action.startRatio
        or math.abs(action.targetConsumedRatio - (action.startRatio - action.endRatio)) > 0.000001
        or math.abs(action.targetConsumedRatio - action.startRatio * action.percentage) > 0.000001 then return false end
    local properties = fluid:getProperties()
    for _, method in ipairs(waterPropertyEffects) do
        if properties[method](properties) ~= 0 then return false end
    end
    local thirst = properties:getThirstChange()
    return type(thirst) == "number" and thirst <= 0 and thirst > -math.huge
end

local function fixedWorldContainer(container)
    if not instanceof(container, "ItemContainer") or container:getContainingItem()
        or not container:isExistYet() or container:getAcceptItemFunction() ~= nil
        or container:getOnlyAcceptCategory() ~= nil then return end
    local kind, parent = container:getType(), container:getParent()
    if kind == "floor" or kind == "proximityInv" or kind == "twistInv_corpses"
        or not instanceof(parent, "IsoObject") or not parent:getSquare() then return end
    for i = 0, parent:getContainerCount() - 1 do
        if parent:getContainerByIndex(i) == container then return {container} end
    end
end

local function returnCapacityCapability(action, contract, context)
    if not contract or contract.knownInputs == false then return end
    local execution = Toolkit.ActionQueueExecution
    if not execution or type(execution.inspect) ~= "function" then return end
    local scope = activeDecision
    local cached = scope and scope.context == context and scope.executions[action]
    if cached and cached.owner == execution and cached.inspect == execution.inspect then return cached[1], execution end
    local capability = execution.inspect(action)
    if scope and scope.context == context then
        scope.executions[action] = {capability, owner = execution, inspect = execution.inspect}
    end
    return capability, execution
end

local function transferCapacityConflict(queue, a, b, last, check, context, comparison)
    local carts = Toolkit.ActionQueueCarts
    local function transfer(action)
        return action.Type == "ISInventoryTransferAction"
            or (action.Type == "ISCartTransferAction" and carts and type(carts.isTransfer) == "function" and carts.isTransfer(action))
    end
    local aTransfer, bTransfer = transfer(a), transfer(b)
    if (aTransfer and not bTransfer) or (bTransfer and not aTransfer) then
        local equipment = inspect(aTransfer and b or a, comparison or context)
        -- Hand/slot changes can alter carried weight or move heavy items out of external containers.
        if equipment and equipment.hands == queue.character then
            local transferAction = aTransfer and a or b
            local contract = inspect(transferAction, context)
            local capability, execution = returnCapacityCapability(transferAction, contract, context)
            -- Native live admission and exact outcome handling own this earned
            -- single return. No equipment-neutrality or future-space claim.
            if not capability or not execution or not execution.capacityDeferred
                or not execution.capacityDeferred(transferAction, capability) then return queue.character:getInventory() end
        end
    end
    if not aTransfer or not bTransfer then return end
    if check.done then return check.blocker end
    local shared
    for _, left in pairs({a.srcContainer, a.destContainer}) do
        for _, right in pairs({b.srcContainer, b.destContainer}) do
            if left == right then shared = left end
        end
    end
    local character = queue.character
    local aCarried = carriedContainer(a.srcContainer, character) or carriedContainer(a.destContainer, character)
    local bCarried = carriedContainer(b.srcContainer, character) or carriedContainer(b.destContainer, character)
    if not shared and not (aCarried and bCarried) then return end
    local root = character:getInventory()
    check.done, check.blocker = true, shared or root
    local incoming, touched, order, removed, loads = {[root] = 0}, {}, {}, {}, {}
    if not check.to then
        -- Keep incoming bounds for cancelled work, including an in-flight pickup's native return.
        for i = check.first, check.last do removed[queue.queue[i]] = true end
    end
    for i = 1, last + 1 do
        if i == check.to then
            for j = check.first, check.last do order[#order + 1] = queue.queue[j] end
        end
        if i <= last and (not check.to or i < check.first or i > check.last) then order[#order + 1] = queue.queue[i] end
    end
    local cartCapacity, conditionalCapacity, hasConditionalCapacity = false, {}, false
    for _, action in ipairs(order) do
        if action.Type == "ISCartTransferAction" or (carts and type(carts.involvesCart) == "function" and carts.involvesCart(action)) then cartCapacity = true end
        local contract = inspect(action, context)
        if contract and contract.capacityRequiresEdit then
            conditionalCapacity[action], hasConditionalCapacity = true, true
        end
    end
    if hasConditionalCapacity then
        -- Prove all conditional weight effects in the global proposed prefix,
        -- including unchanged portions and their required pickups/returns. The
        -- selected edit's dependency component alone may contain none of them.
        local projection = editComponent(queue, order, conditionalCapacity, context)
        if projection.status ~= "allowed" then return check.blocker end
        local entries = {}
        for _, action in ipairs(order) do
            if projection.component[action] then
                entries[#entries + 1] = {action = action, edit = projection.contracts[action].edit,
                    snapshotOnly = removed[action] == true}
            end
        end
        if evaluateComponent(projection, entries).status ~= "allowed" then return check.blocker end
    end
    local function fits(container, weight)
        local load = loads[container]
        if not load then
            local current=Weights.capacity(container,character)
            if not finiteWeight(current) then return false end
            if cartCapacity and (not carts or not carts.capacitySafe or not carts.capacitySafe(container)) then return false end
            load = {current, container:getEffectiveCapacity(character), container:getAcceptItemFunction() == nil}
            loads[container] = load
        end
        local current, capacity = load[1], load[2]
        -- Native capacity checks round the current load to hundredths at each transfer.
        return load[3] and finiteWeight(current) and finiteWeight(capacity) and type(weight) == "number"
            and math.abs(weight) < math.huge and math.max(0, current + weight) + 0.01 <= capacity
    end
    for _, action in ipairs(order) do
        local contract, source = inspect(action, context)
        if not contract or contract.knownInputs == false then return check.blocker end
        if transfer(action) then
            local destination, source, seen = action.destContainer, action.srcContainer, {}
            local destinations = carriedContainers(destination, character)
            local sourceCarried = carriedContainer(source, character)
            local destinationCarried = destinations ~= nil
            -- Active shelf reading may move its world return past a tape pickup. Bound both
            -- endpoints at their current loads, without spending space from future returns.
            if check.readDemotion then destinations = destinations or fixedWorldContainer(destination)
            elseif ItemEditAdapters and ItemEditAdapters.worldContainer then
                destinations = destinations or ItemEditAdapters.worldContainer(destination,character)
            end
            if action.character ~= character or (not sourceCarried
                and not (check.readDemotion and fixedWorldContainer(source))
                and not (not check.readDemotion and ItemEditAdapters and ItemEditAdapters.worldContainer
                    and ItemEditAdapters.worldContainer(source,character)))
                or not destinations then return check.blocker end
            if not sourceCarried and not destinationCarried and not check.readDemotion then return check.blocker end
            local function add(item)
                if not instanceof(item, "InventoryItem") or instanceof(item, "InventoryContainer") then return false end
                if not check.readDemotion and (not sourceCarried or not destinationCarried)
                    and (not ItemEditAdapters or not ItemEditAdapters.worldTransferItem
                        or not ItemEditAdapters.worldTransferItem(item,not destinationCarried,character,source,destination)) then return false end
                local id, kind = item:getID(), item:getType()
                if seen[id] then return true end
                seen[id] = true
                if kind == "CandleLit" or kind == "Lantern_HurricaneLit" then return false end
                local weight,release = Weights.unequipped(item)
                if not finiteWeight(weight) or not finiteWeight(release) then return false end
                if destinationCarried then incoming[root] = incoming[root] + weight end
                for _, container in ipairs(destinations) do
                    if container ~= root then
                        incoming[container] = (incoming[container] or 0) + weight
                        check.blocker = container
                        if not fits(container, incoming[container]) then return false end
                    end
                end
                -- shortcut: MP transactions may be rejected later; count released space only for verified SP pickups.
                if not cartCapacity and nativeTransferItem and not isClient() and type(ISTransferAction) == "table"
                    and ISTransferAction.transferItem == nativeTransferItem
                    and (not transferItemGuard or transferItemGuard())
                    and not removed[action] and not touched[id]
                    and not instanceof(item, "AnimalInventoryItem")
                    and sourceCarried and destination == root and source ~= root and not source:getParent()
                    and item:getContainer() == source and source:contains(item) and not item:getIsCraftingConsumed()
                    and not character:getVehicle() and root:getAcceptItemFunction() == nil
                    and root:getOnlyAcceptCategory() == nil then
                    incoming[source] = (incoming[source] or 0) - release
                end
                touched[id] = true
                return true
            end
            if not add(action.item) then return check.blocker end
            for _, batch in ipairs(action.queueList or {}) do
                for _, item in ipairs(batch.items or {}) do if not add(item) then return check.blocker end end
            end
        elseif not capacityNeutral[action.Type] and source~="toolkit.approach" and not boundedWaterDrink(action, character, source)
            and not (source=="native.ISFluidEmptyAction" and contract.edit and contract.capacityNonIncreasing==true)
            and not (source == "native.ISEatFoodAction" and contract.edit
                and (contract.capacityNonIncreasing == true or conditionalCapacity[action]
                    or removed[action] and contract.capacityReplacement==true))
            and not (check.readDemotion and source == "native.ISRadioAction"
                and instanceof(action.device, "IsoTelevision"))
            and not (check.readDemotion and source == "native.device-media-insert" and contract.capacityNonIncreasing == true) then
            -- shortcut: other actions may change carried weight; add verified weight effects before crossing their prefix.
            return check.blocker
        end
    end
    check.blocker = root
    if not fits(root, incoming[root]) then return root end
    check.blocker = nil
end

local function editCapacityConflict(queue, edit, first, last, to, context)
    if not edit.externalCapacity then return end
    -- The item projection proves locations/amounts, not available weight. Even a
    -- successful projection must scan every later transfer at full current
    -- weight: cancelling a drink must not spend its hypothetical weight loss.
    for index, member in ipairs(queue.queue) do
        -- A pure pending removal cannot change an earlier transfer. Only later
        -- transfers need the bound; this also leaves safe tail removal free.
        if (to or index > last) and (member.Type == "ISInventoryTransferAction" or member.Type == "ISCartTransferAction") then
            return transferCapacityConflict(queue, member, member, #queue.queue,
                {first = first, last = last, to = to}, context)
        end
    end
end

-- Dropping an automatic return is a deliberate "keep carried" intent, not
-- cancellation of the body that still needs the borrowed item. Only the exact
-- earned loan may waive its return; later dependencies/capacity still apply.
pendingReturnGuard = function(action, reference)
    if not nativePendingCancelHasNoEffects() or action.forceCancel ~= nativeForceCancel
        or not callbacksSafe(action) or action.item:getID() ~= reference.id
        or action.item:getFullType() ~= reference.fullType then return false end
    local intent = Toolkit.ActionQueueTidyIntent
    if intent and type(intent.canKeepReturn) == "function" then
        if not intent.canKeepReturn(action) then return false end
    elseif P4TidyUpMeister then return false end
    local groups = action.queueList
    if groups == nil then return true end
    if type(groups) ~= "table" or getmetatable(groups) then return false end
    local count = 0
    for index in pairs(groups) do if index ~= 1 then return false end; count = count + 1 end
    if count == 0 then return true end
    if type(groups[1]) ~= "table" or type(groups[1].items) ~= "table" then return false end
    count = 0
    for index, item in pairs(groups[1].items) do
        if index ~= 1 or item ~= action.item and not (ItemEditAdapters
            and type(ItemEditAdapters.matchesTransferMember) == "function"
            and ItemEditAdapters.matchesTransferMember(action, item)) then return false end
        count = count + 1
    end
    return count == 1
end
local returnRadioInspector = EditAdapters and EditAdapters.radio
local returnRadioClosure = Proof and Proof.closure
local function returnRadioProjectionIndependent(own)
    if not EditAdapters or Toolkit.ActionQueueEditAdapters ~= EditAdapters
        or EditAdapters.radio ~= returnRadioInspector or type(returnRadioInspector) ~= "function"
        or not Proof or Proof.closure ~= returnRadioClosure
        or not returnRadioClosure(returnRadioInspector, "ActionQueueEditAdapters.lua") then return false end
    -- The owned radio adapter adds only domain=device. The exact return has
    -- item/container edits; its plain resource footprint is otherwise unchanged.
    local edit = own.edit
    if edit ~= nil and (type(edit) ~= "table" or getmetatable(edit)
        or type(edit.resources) ~= "table" or getmetatable(edit.resources)) then return false end
    for _, resource in pairs(edit and edit.resources or {}) do
        if type(resource) ~= "table" or getmetatable(resource) or resource.domain == "device" then return false end
    end
    return true
end
-- A comparison-only view may omit an optional, source-owned device edit only
-- after every changed member's complete contract proves that domain absent.
-- Full planner/forecast caches retain their complete contracts.
local function cancellationComparisons(queue, first, last, context)
    if #queue.queue > 32 or not targetCheckersUnchanged() then return context end
    for index = first, last do
        local own = inspect(queue.queue[index], context)
        if not own or not returnRadioProjectionIndependent(own) then return context end
    end
    return {contracts = context.contracts, items = context.items, failureOverrides = {}}
end
local function cancellationComparison(other, context)
    if not context.failureOverrides or other.Type ~= "ISRadioAction" or not mediaSetterModes[other.mode]
        or other._isAddingActions or other.action
        or (Operations.isContinuationPending and Operations.isContinuationPending(other.toolkitQueueOperation))
        or context.contracts[other] or context.failureOverrides[other] then return context end
    local snapshot = snapshots[getmetatable(other)]
    local scope = activeDecision
    local proven = scope and scope.native[other] == snapshot
    if not snapshot or not (proven or nativeMatches(other, snapshot)) then return context end
    local behavior, source = Definitions.behavior(other)
    if behavior and source == "native.ISRadioAction" and behavior.inspect == radioResources then
        context.failureOverrides[other] = {radioResources(other, true), source, behavior}
    end
    return context
end
pendingReturnReason = function(queue, action, context)
    local settlement = Toolkit.ActionQueueSettlement
    if not settlement or not settlement.canWaivePendingReturn
        or not settlement.canWaivePendingReturn(action, pendingReturnGuard) then return "dependent" end
    local index = queue:indexOf(action)
    local capacity = {first = index, last = index}
    local comparisons = cancellationComparisons(queue, index, index, context)
    for otherIndex, other in ipairs(queue.queue) do
        if other ~= action then
            local comparison = cancellationComparison(other, comparisons)
            if not knownCraftInputs(other, comparison) then return "operation_dependent", nil, nil, other end
            if otherIndex > index then
                local shared = sharedItem(action, other, comparison)
                if shared then return "operation_shared_item", nil, nil, other, shared end
                local conflict = sharedWorldTarget(action, other, comparison)
                    or dynamicConflict(action, other, comparison) or dynamicConflict(other, action, comparison)
                if conflict then return "operation_dependent", nil, nil, other, conflict end
            end
            local blocker = transferCapacityConflict(queue, action, other, #queue.queue, capacity, context, comparison)
            if blocker then return "container_capacity", nil, nil, other, blocker end
        end
    end
end
function Policy.commitReturnCancellation(action, capability)
    local settlement = Toolkit.ActionQueueSettlement
    return settlement and settlement.waivePendingReturn
        and settlement.waivePendingReturn(capability, action, pendingReturnGuard) or false
end

function Policy.cancelOperationReason(queue, action, context)
    context = context or {contracts = {}, items = {}}
    context.editFallback = nil
    clearDenial(context)
    if not Toolkit.Settings.actionQueue() or not queue or not live(queue)
        or queue:indexOf(action) == -1 then return "unavailable" end
    if queue.toolkitCancel or queue.toolkitGroupCancel then return "stopping" end
    local first, last = Operations.bounds(queue, action)
    if not first then return "operation_dependent" end
    local token = action.toolkitQueueOperation
    if Operations.isContinuationPending and Operations.isContinuationPending(token) then
        return deny(context, "operation_dependent", "edit_in_flight", action)
    end
    local active = first == 1 and queue.current == queue.queue[1]
    if type(token) == "table" and token.toolkitStarted and not active then return "operation_active" end
    local main, output, inputs, scrapOnly = false, false, {}, true
    local pendingRemovalOnly = not active and nativePendingCancelHasNoEffects()
    for i = first, last do
        local member = queue.queue[i]
        if (member.action or member == queue.current or i == 1) and not (active and i == first) then
            return "operation_active"
        end
        local auditedCraft = craft(member)
        -- The reviewed native forceCancel is empty. Removing unstarted steps
        -- with that handler has no world effects on the preceding work.
        -- Craft also runs cancelWaiting, so retain its existing conservative path.
        pendingRemovalOnly = pendingRemovalOnly and member.forceCancel == nativeForceCancel
            and not member.onCancelFunc and not auditedCraft
        local contract = inspect(member, context)
        if contract and contract.cancelOperation == false then return protectedDenial(context, "operation_dependent", member), nil, nil, member end
        local auditedCallbacks = contract and contract.callbacksSafe
        if member._isAddingActions or ((member.onStartFunc or member.onCancelFunc) and not auditedCraft and not resumableWorld(member) and not auditedCallbacks) or member.retriggerLastAction
            or (member.onCompleteFunc and member.onCompleteFunc ~= member.toolkitQueueSafeOnComplete
                and not auditedCraft and not resumableWorld(member) and not auditedCallbacks)
            or (member.forceCancel ~= nativeForceCancel and not (contract and contract.forceCancel == member.forceCancel)) then
            return unknownDenial(context, "operation_dependent", member)
        end
        local plannedCraft, world = craftPlan(member), deferredWorld(member)
        if member.Type == "ISQueueActionsAction" and not plannedCraft and not world and not (contract and contract.deferred) then
            return unknownDenial(context, "operation_dependent", member)
        end
        local supported = stoppable(member, context) or independentBulk(member, context) or world or plannedCraft or appliance(member)
            or (contract and contract.cancelWaiting)
        if not supported and not (contract and contract.preparation) then
            if not contract then return unknownDenial(context, "operation_dependent", member) end
            return "operation_dependent"
        end
        main = main or supported
        if supported then
            scrapOnly = scrapOnly and ((world and member.toolkitWorldDismantle)
                or (member.Type == "ISMoveablesAction" and member.mode == "scrap"))
        end
        output = output or member.toolkitIndependentBulk or auditedCraft or (world and member.toolkitWorldDismantle) or plannedCraft
            or (member.Type == "ISMoveablesAction" and member.mode == "scrap")
        for item in pairs(operationItems(member, context)) do inputs[item] = true end
    end
    if not main then return "operation_dependent" end
    if active then
        local current = queue.current
        if current.action and (current.action:finished() or current.action:isForceComplete()) then return "starting" end
        if stoppable(current, context) then
            if not current.action or not current.action:isStarted() then return "starting" end
        elseif not preparationCanFinish(current, context) then
            return "operation_active"
        end
    end
    if pendingRemovalOnly then
        local edit = proposedEdit(queue, first, last, nil, context)
        if edit.status == "allowed" then
            local capacity = editCapacityConflict(queue, edit, first, last, nil, context)
            if capacity then return "container_capacity", nil, nil, action, capacity end
            return nil, first, last
        end
        if edit.status == "denied" then return edit.reason, nil, nil, edit.blocker, edit.resource end
        context.editFallback = edit
    end
    for item in pairs(type(token) == "table" and token.toolkitPickups or {}) do inputs[itemKey(item)] = true end
    local capacityCheck = {first = first, last = last}
    local comparisons = cancellationComparisons(queue, first, last, context)
    local groupItems = plainGroupItems(queue, first, last, context)
    for i, other in ipairs(queue.queue) do
        if i > last or (i < first and not pendingRemovalOnly) then
            local comparison = cancellationComparison(other, comparisons)
            if other._isAddingActions or not knownCraftInputs(other, comparison) then
                return unknownDenial(context, "operation_dependent", other), nil, nil, other
            end
            for item in pairs(operationItems(other, comparison)) do
                if inputs[item] then return "operation_shared_item", nil, nil, other, item end
            end
            if mayShareGroupResource(groupItems, other, comparison) then
                for j = first, last do
                    local item = sharedItem(queue.queue[j], other, comparison)
                    if item then return "operation_shared_item", nil, nil, other, item end
                    local conflict = sharedWorldTarget(queue.queue[j], other, comparison) or dynamicConflict(queue.queue[j], other, comparison)
                        or dynamicConflict(other, queue.queue[j], comparison)
                    if conflict then return "operation_dependent", nil, nil, other, conflict end
                    local capacity = transferCapacityConflict(queue, queue.queue[j], other, #queue.queue, capacityCheck, context, comparison)
                    if capacity then return "container_capacity", nil, nil, other, capacity end
                end
            end
            -- shortcut: output requirements of arbitrary later actions are unknown; add verified adapters to allow them.
            if output and i > last then
                local independentCraft = craft(other) and knownCraftInputs(other, comparison)
                if ((other.onStartFunc or other.onCancelFunc) and not independentCraft) or other.retriggerLastAction
                    or (other.onCompleteFunc and other.onCompleteFunc ~= other.toolkitQueueSafeOnComplete and not independentCraft)
                    or (not independentCraft and not other.toolkitIndependentBulk and not other.toolkitBulkPreparation
                        and not (scrapOnly and deferredWorld(other) and other.toolkitWorldDismantle)
                        and not groupPreparation[other.Type] and other.Type ~= "ISReadABook"
                        and other.Type ~= "ISInventoryTransferAction") then return "operation_dependent" end
            end
        end
    end
    return nil, first, last
end

local function moveConflict(queue, member, crossed, crossedLast, capacityCheck, context)
    local item = sharedItem(member, crossed, context)
    if item then return "move_shared_item", item end
    local dynamic = dynamicConflict(member, crossed, context) or dynamicConflict(crossed, member, context)
    if dynamic then return "move_craft_inputs", dynamic end
    if not repairCanCross(member, crossed, context) or not repairCanCross(crossed, member, context) then
        return "move_craft_inputs"
    end
    local target = sharedWorldTarget(member, crossed, context)
    if target then return "move_dependent", target end
    local capacity = transferCapacityConflict(queue, member, crossed, crossedLast, capacityCheck, context)
    if capacity then return "container_capacity", capacity end
end

-- Lowering a reader promotes the intervening range without changing its internal order.
-- Keep the native current action in slot 1 until stop/removal; Queue.move reconstructs it
-- after that range, immediately before its still-owned returns/cleanup.
local function demoteReading(queue, first, last, targetFirst, targetLast, after, context)
    local current = queue.current
    if first ~= 1 or queue.queue[1] ~= current or not current or current.Type ~= "ISReadABook"
        or Policy.cancelReason(queue, current, context) then return "move_active" end
    for i = first, last do
        local member = queue.queue[i]
        if (member ~= current and member.action) or member._isAddingActions
            or not knownCraftInputs(member, context) then
            if not (member ~= current and member.action) then return unknownDenial(context, "move_dependent", member) end
            return "move_dependent"
        end
    end
    if targetFirst == first then return nil, first, first, last end
    local rangeFirst, rangeLast = last + 1, after and targetLast or targetFirst - 1
    if rangeLast < rangeFirst then return nil, first, first, last end
    local capacityCheck = {first = rangeFirst, last = rangeLast, to = 1, readDemotion = true}
    for i = rangeFirst, rangeLast do
        local member = queue.queue[i]
        local opFirst, opLast = Operations.bounds(queue, member)
        if not opFirst or opFirst < rangeFirst or opLast > rangeLast or member.action
            or member._isAddingActions or (not knownCraftInputs(member, context) and not repairInputs(member)) then
            if opFirst and opFirst >= rangeFirst and opLast <= rangeLast and not member.action then
                return unknownDenial(context, "move_dependent", member), nil, nil, nil, nil, member
            end
            return "move_dependent", nil, nil, nil, nil, member
        end
        if member.Type == "ISReadABook" and member.item:getFullType() == current.item:getFullType() then
            return "move_shared_book", nil, nil, nil, nil, member
        end
        for j = first, last do
            local reason, resource = moveConflict(queue, member, queue.queue[j], rangeLast, capacityCheck, context)
            if reason then return reason, nil, nil, nil, nil, queue.queue[j], resource end
        end
    end
    return nil, 1, rangeFirst, rangeLast, true, nil, nil, true
end

function Policy.moveReason(queue, action, target, after, context)
    context = context or {contracts = {}, items = {}}
    context.editFallback = nil
    clearDenial(context)
    if not Toolkit.Settings.actionQueue() or not queue or not live(queue)
        or queue:indexOf(action) == -1 or queue:indexOf(target or action) == -1 then return "unavailable" end
    if queue.toolkitCancel or queue.toolkitGroupCancel then return "stopping" end
    local first, last = Operations.bounds(queue, action)
    local targetFirst, targetLast = Operations.bounds(queue, target or action)
    if not first or not targetFirst then return "move_dependent" end
    if first == 1 then
        return demoteReading(queue, first, last, targetFirst, targetLast, after, context)
    end
    for i = first, last do
        local member = queue.queue[i]
        if member.action or member == queue.current or i == 1 then return "move_active" end
        if member._isAddingActions then return deny(context, "move_dependent", "edit_in_flight", member) end
        if not knownCraftInputs(member, context) and not repairInputs(member) then
            return craft(member) and "move_craft_inputs" or unknownDenial(context, "move_dependent", member)
        end
    end
    if first == targetFirst then return nil, first, first, last end
    local to = after and targetLast + 1 or targetFirst
    local preempt = to == 1
    if preempt then
        local supported, reason = resumableWorld(queue.current)
        if not queue.current or (queue.current.Type ~= "ISReadABook" and not supported)
            or Policy.cancelReason(queue, queue.current, context) then return reason or "move_active" end
    end
    if preempt then
        for i = first, last do
            local member = queue.queue[i]
            -- Native reading progress is shared by book type, including different copies.
            if queue.current.Type == "ISReadABook" and member.Type == "ISReadABook"
                and member.item:getFullType() == queue.current.item:getFullType() then
                return "move_shared_book"
            end
        end
    end
    local capacityCheck = {first = first, last = last, to = to}
    -- Structural/callback guards apply even when the declarative model proves
    -- resource conditions. An incomplete contract never upgrades these gates.
    for i = math.min(first, to), math.min(#queue.queue, math.max(last, to - 1)) do
        if i < first or i > last then
            local crossed = queue.queue[i]
            if crossed._isAddingActions then return deny(context, "move_dependent", "edit_in_flight", crossed), nil, nil, nil, nil, crossed end
            if not knownCraftInputs(crossed, context) and not repairInputs(crossed) then
                return craft(crossed) and "move_craft_inputs" or unknownDenial(context, "move_dependent", crossed), nil, nil, nil, nil, crossed
            end
        end
    end
    if not preempt then
        local edit = proposedEdit(queue, first, last, to, context)
        if edit.status == "denied" then return edit.reason, nil, nil, nil, nil, edit.blocker, edit.resource end
        if edit.status == "allowed" then
            local capacity = editCapacityConflict(queue, edit, first, last, to, context)
            if capacity then return "container_capacity", nil, nil, nil, nil, action, capacity end
            if first < to then to = to - (last - first + 1) end
            return nil, to, first, last, false
        end
        context.editFallback = edit
    end
    local groupItems = plainGroupItems(queue, first, last, context)
    for i = math.min(first, to), math.min(#queue.queue, math.max(last, to - 1)) do
        if i < first or i > last then
            local crossed = queue.queue[i]
            if crossed._isAddingActions then return deny(context, "move_dependent", "edit_in_flight", crossed), nil, nil, nil, nil, crossed end
            if not knownCraftInputs(crossed, context) and not repairInputs(crossed) then
                return craft(crossed) and "move_craft_inputs" or unknownDenial(context, "move_dependent", crossed), nil, nil, nil, nil, crossed
            end
            if mayShareGroupResource(groupItems, crossed, context) then
                for j = first, last do
                    local reason, resource = moveConflict(queue, queue.queue[j], crossed, math.max(last, to - 1), capacityCheck, context)
                    if reason then return reason, nil, nil, nil, nil, crossed, resource end
                end
            end
        end
    end
    if first < to then to = to - (last - first + 1) end
    return nil, to, first, last, preempt
end


Policy.live, Policy.stoppable = live, stoppable
Policy.resumableWorld, Policy.preparationCanFinish = resumableWorld, preparationCanFinish
Policy.operationItems = operationItems

-- Failure isolation never guesses that an unknown or resource-dependent suffix
-- is independent. Capacity-sharing future transfers remain on their native path
-- until their own admission/outcome contracts are migrated. No inventory scan.
local MAX_RETURN_EXECUTION_MEMBERS = 32
local returnFailureSuffix = {ISReadABook = true, ISWalkToTimedAction = true,
    ISWalkToTimedActionF = true, ISPathFindAction = true, ISEquipWeaponAction = true, ISUnequipAction = true,
    ISRadioAction = true}
local returnApproachBinding
local returnApproachClosure = Proof and Proof.closure
local function returnFailureApproach(action)
    local owner = Toolkit.ActionQueueApproach
    local checker = owner and owner.isAction
    if type(checker) ~= "function" or not Proof or Proof.closure ~= returnApproachClosure
        or type(returnApproachClosure) ~= "function" or not returnApproachClosure(checker, "ActionQueueApproach.lua") then return false end
    if not returnApproachBinding then returnApproachBinding = {owner = owner, checker = checker} end
    return owner == returnApproachBinding.owner and checker == returnApproachBinding.checker and checker(action) == true
end
local function returnFailureIndependent(queue, action, scope)
    -- Unsupported is a closed result, never permission on budget exhaustion.
    -- The first slice intentionally has no large-queue or recipe-input forecast.
    if not queue or #queue.queue > MAX_RETURN_EXECUTION_MEMBERS then return false, "unsupported_queue_size" end
    if not targetCheckersUnchanged() then return false, "unsupported_target_checker" end
    local index = queue and queue:indexOf(action)
    if not index or index < 1 then return false end
    local outer = scope and scope.context
    local context = {contracts = outer and outer.contracts or {}, items = outer and outer.items or {},
        executionProbe = true, failurePositionPrerequisite = action}
    local own = inspect(action, context)
    if not own or own.knownInputs == false or own.unknownOutputs then return false end
    local radioProjectionIndependent = returnRadioProjectionIndependent(own)
    context.failureOverrides = {}
    -- Transfer reachability is a position prerequisite, not a position effect.
    -- A later walk remains independent of its terminal no-effect rejection.
    for i = index + 1, #queue.queue do
        local other = queue.queue[i]
        local approach = other.Type == "ISQueueActionsAction" and returnFailureApproach(other)
        if not returnFailureSuffix[other.Type] and not approach
            or other.Type == "ISRadioAction" and not mediaSetterModes[other.mode] then
            return false, "unsupported_tail_kind"
        end
        if other._isAddingActions or other.action then return false end
        local snapshot = snapshots[getmetatable(other)]
        if not approach and (not snapshot or not nativeMatches(other, snapshot)) then return false, "unsupported_tail_binding" end
        if scope and not approach then scope.native[other] = snapshot end
        if other.Type == "ISRadioAction" and radioProjectionIndependent and not context.contracts[other] then
            local behavior, source = Definitions.behavior(other)
            if behavior and source == "native.ISRadioAction" and behavior.inspect == radioResources then
                -- Tail-only override: never publish a partial device edit into
                -- the outer decision's full planner contract cache.
                context.failureOverrides[other] = {radioResources(other, true), source, behavior}
            end
        end
        local contract, source = inspect(other, context)
        if approach and (source ~= "toolkit.approach" or not contract or not contract.deferred
            or not contract.preparation or contract.capacityNonIncreasing ~= true) then
            return false, "unsupported_tail_binding"
        end
        if not contract or contract.knownInputs == false or contract.unknownOutputs
            or sharedItem(action, other, context) or sharedWorldTarget(action, other, context)
            or dynamicConflict(action, other, context) or dynamicConflict(other, action, context) then return false end
    end
    return true
end

function Policy.returnFailureIndependent(queue, action)
    local scope = activeDecision
    if scope and scope.queue == queue then
        -- Reuse only inside the current synchronous source-owned decision. A new
        -- decision, admission, rejection or click always starts with fresh facts.
        local cached = scope.failures[action]
        if cached then return cached[1], cached[2] end
        local result, reason = returnFailureIndependent(queue, action, scope)
        scope.failures[action] = {result, reason}
        return result, reason
    end
    return returnFailureIndependent(queue, action)
end

function Policy.replaceStop(previous, replacement)
    if type(adoptGroomingBase) == "function" and Toolkit.ActionQueueGrooming == Grooming and Grooming.adoptBase == adoptGroomingBase then adoptGroomingBase("stop", previous, replacement) end
    if Firearms then Firearms.adoptBase("stop", previous, replacement) end
    if EditAdapters then EditAdapters.adoptBase("stop", previous, replacement) end
    if ItemEditAdapters then ItemEditAdapters.adoptBase("stop", previous, replacement) end
    for _, snapshot in pairs(snapshots) do
        if snapshot.methods.stop == previous then snapshot.methods.stop = replacement end
    end
    for _, snapshots in ipairs({nativePreparation, repairIndependent}) do
        for _, methods in pairs(snapshots) do
            if methods.stop == previous then methods.stop = replacement end
        end
    end
end

function Policy.adoptBegin(previous, replacement)
    if type(adoptGroomingBase) == "function" and Toolkit.ActionQueueGrooming == Grooming and Grooming.adoptBase == adoptGroomingBase then adoptGroomingBase("begin", previous, replacement) end
    if Firearms then Firearms.adoptBase("begin", previous, replacement) end
    if EditAdapters then EditAdapters.adoptBase("begin", previous, replacement) end
    if ItemEditAdapters then ItemEditAdapters.adoptBase("begin", previous, replacement) end
end

local function editSnapshot(queue)
    if not queue then return end
    local snapshot = {owner = queue.character, members = {}, list = queue.queue, current = queue.current,
        generation = queue.toolkitOperationGeneration, cancel = queue.toolkitCancel, groupCancel = queue.toolkitGroupCancel}
    for i, member in ipairs(queue.queue) do
        local token = member.toolkitQueueOperation
        snapshot.members[i] = {member = member, action = member.action, owner = member.character, token = token,
            started = type(token) == "table" and token.toolkitStarted,
            cancelled = type(token) == "table" and token.toolkitCancelled}
    end
    return snapshot
end

function Policy.editUnchanged(queue, snapshot)
    if not snapshot or not queue or not live(queue) or not Toolkit.Settings.actionQueue()
        or ISTimedActionQueue.queues[queue.character] ~= queue
        or queue.character ~= snapshot.owner or queue.queue ~= snapshot.list or queue.current ~= snapshot.current
        or queue.toolkitOperationGeneration ~= snapshot.generation or queue.toolkitCancel ~= snapshot.cancel
        or queue.toolkitGroupCancel ~= snapshot.groupCancel or #queue.queue ~= #snapshot.members then return false end
    for i, record in ipairs(snapshot.members) do
        local member, token = queue.queue[i], record.token
        if member ~= record.member or member.action ~= record.action or member.character ~= record.owner
            or member.toolkitQueueOperation ~= token
            or (type(token) == "table" and (token.toolkitStarted ~= record.started
                or token.toolkitCancelled ~= record.cancelled)) then return false end
    end
    return true
end

local resourceDenials = {move_shared_item = true, move_craft_inputs = true, move_dependent = true,
    operation_shared_item = true, operation_dependent = true, container_capacity = true}
local function editDenial(reason, blocker, resource, context)
    local edit = context.editFallback
    if reason and resourceDenials[reason] and edit and edit.reason then
        return edit.reason, edit.blocker or blocker, edit.resource or resource
    end
    if reason and context.denialGate == reason and context.denialReason then
        return context.denialReason, context.denialBlocker or blocker, resource
    end
    return reason, blocker, resource
end

-- Presentation only: no edit snapshot or authority to mutate the queue. Callers
-- must evaluate again at the actual move/cancel boundary, with fresh live facts.
function Policy.previewMove(queue, action, target, after, context)
    context = context or {contracts = {}, items = {}}
    local reason, to, first, last, preempt, blocker, resource = Policy.moveReason(queue, action, target, after, context)
    reason, blocker, resource = editDenial(reason, blocker, resource, context)
    return {reason = reason, blocker = blocker, resource = resource,
        to = to, first = first, last = last, preempt = preempt}
end

function Policy.previewCancel(queue, action, whole, context)
    context = context or {contracts = {}, items = {}}
    local reason, first, last, blocker, resource
    if whole then reason, first, last, blocker, resource = Policy.cancelOperationReason(queue, action, context)
    else reason, first, last, blocker, resource = Policy.cancelReason(queue, action, context) end
    reason, blocker, resource = editDenial(reason, blocker, resource, context)
    return {reason = reason, blocker = blocker, resource = resource}
end

function Policy.evaluateMove(queue, action, target, after, context)
    context = context or {contracts = {}, items = {}}
    local snapshot = editSnapshot(queue)
    local reason, to, first, last, preempt, blocker, resource, demote = Policy.moveReason(queue, action, target, after, context)
    reason, blocker, resource = editDenial(reason, blocker, resource, context)
    if not reason and not Policy.editUnchanged(queue, snapshot) then reason = "unavailable" end
    return {allowed = reason == nil, reason = reason, to = to, first = first, last = last,
        mode = preempt and "audited-resume" or "move", preempt = preempt, demote = demote,
        blocker = blocker, resource = resource, snapshot = snapshot}
end

function Policy.evaluateCancel(queue, action, whole, context)
    context = context or {contracts = {}, items = {}}
    local snapshot = editSnapshot(queue)
    local reason, first, last, blocker, resource
    if whole then reason, first, last, blocker, resource = Policy.cancelOperationReason(queue, action, context)
    else reason, first, last, blocker, resource = Policy.cancelReason(queue, action, context) end
    reason, blocker, resource = editDenial(reason, blocker, resource, context)
    local returnWaiver
    if not reason and not whole and pendingReturnTarget(queue, action) then
        returnWaiver = Toolkit.ActionQueueSettlement.pendingReturnWaiver(action, pendingReturnGuard)
        if not returnWaiver then reason = "unavailable" end
    end
    if not reason and not Policy.editUnchanged(queue, snapshot) then reason = "unavailable" end
    return {allowed = reason == nil, reason = reason, first = first, last = last,
        mode = returnWaiver and "pending-return" or queue and action == queue.current and "active" or "pending",
        returnWaiver = returnWaiver, blocker = blocker, resource = resource, snapshot = snapshot}
end

-- A caller's table is bounded output only. Each public invocation owns its
-- actual analysis maps, including reentrant calls using the same output table.
local decisionContextMarker = {}
local decisionContextFields = {"contracts", "items", "denialGate", "denialReason", "denialBlocker",
    "editFallback", "failureOverrides", "failurePositionPrerequisite", "executionProbe"}
local function freshDecisionContext(output)
    if type(output) ~= "table" or getmetatable(output) or output[decisionContextMarker] then output = nil end
    if output then for _, name in ipairs(decisionContextFields) do output[name] = nil end end
    return {contracts = {}, items = {}, [decisionContextMarker] = true}, output
end
local function inDecision(queue, context, output, callback, ...)
    local previous = activeDecision
    activeDecision = {queue = queue, context = context, failures = {}, executions = {}, native = {}}
    local result = {pcall(callback, ...)}
    activeDecision = previous
    if output then for _, name in ipairs(decisionContextFields) do output[name] = context[name] end end
    if not result[1] then error(result[2], 0) end
    return result[2]
end
local previewMove, previewCancel = Policy.previewMove, Policy.previewCancel
local evaluateMove, evaluateCancel = Policy.evaluateMove, Policy.evaluateCancel
function Policy.previewMove(queue, action, target, after, context)
    local fresh, output = freshDecisionContext(context)
    return inDecision(queue, fresh, output, previewMove, queue, action, target, after, fresh)
end
function Policy.evaluateMove(queue, action, target, after, context)
    local fresh, output = freshDecisionContext(context)
    return inDecision(queue, fresh, output, evaluateMove, queue, action, target, after, fresh)
end
function Policy.previewCancel(queue, action, whole)
    local context = freshDecisionContext()
    return inDecision(queue, context, nil, previewCancel, queue, action, whole, context)
end
function Policy.evaluateCancel(queue, action, whole)
    local context = freshDecisionContext()
    return inDecision(queue, context, nil, evaluateCancel, queue, action, whole, context)
end

local function priorityDecision(queue, action, preempt, decide)
    if not queue or not queue.current or queue.queue[1] ~= queue.current then return {allowed = false, reason = "unavailable"} end
    local _, activeLast = Operations.bounds(queue, queue.current)
    if not activeLast then return {allowed = false, reason = "operation_dependent"} end
    local activeToken = queue.current.toolkitQueueOperation
    local context = {contracts = {}, items = {}}
    if preempt and activeLast == 1 and not (activeToken and activeToken.toolkitPriority == "urgent")
        and (queue.current.Type == "ISReadABook" or resumableWorld(queue.current)) then
        local decision = decide(queue, action, queue.current, false, context)
        if not decision.reason then decision.target = queue.current; return decision end
    end
    local target = queue.queue[activeLast]
    local decision = decide(queue, action, target, true, context)
    decision.target, decision.after = target, true
    return decision
end

function Policy.evaluatePriority(queue, action, preempt)
    return priorityDecision(queue, action, preempt, Policy.evaluateMove)
end

-- A tick only chooses a possible move. Authority and its edit snapshot belong
-- to Queue.move immediately before mutation, not every unsuccessful retry.
function Policy.priorityIntent(queue, action, preempt)
    local decision = priorityDecision(queue, action, preempt, Policy.previewMove)
    decision.candidate = not decision.reason and decision.to ~= decision.first
    return decision
end

local diagnostics, diagnosticEnabled = {}, false
function Policy.setDiagnostics(enabled)
    diagnosticEnabled = enabled == true
    diagnostics = {}
end

function Policy.record(command, action, decision)
    if not diagnosticEnabled then return end
    local contract, adapter = inspect(action)
    local keys = {}
    for key in pairs(contract and contract.items or {}) do keys[#keys + 1] = tostring(key) end
    for key in pairs(contract and contract.containerOwners or {}) do keys[#keys + 1] = "container:" .. tostring(key) end
    for key in pairs(contract and contract.dynamicInputs or {}) do keys[#keys + 1] = "type:" .. tostring(key) end
    for key in pairs(contract and contract.dynamicInputsByType or {}) do keys[#keys + 1] = "short-type:" .. tostring(key) end
    if #diagnostics == 64 then table.remove(diagnostics, 1) end
    diagnostics[#diagnostics + 1] = {command = command, type = action.Type, adapter = adapter,
        mode = action.mode, source = action.toolkitWorldOperation, resources = table.concat(keys, ","),
        interrupt = contract and contract.interrupt, allowed = decision.allowed, reason = decision.reason,
        blocker = decision.blocker and decision.blocker.Type}
end

function Policy.getDiagnostics()
    local result = {}
    for i, entry in ipairs(diagnostics) do
        result[i] = {}
        for key, value in pairs(entry) do result[i][key] = value end
    end
    return result
end

return Policy
