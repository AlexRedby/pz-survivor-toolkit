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
local Policy = {}
Toolkit.ActionQueuePolicy = Policy
local Operations = Toolkit.ActionQueueOperations
local nativeForceCancel = ISBaseTimedAction.forceCancel
local Proof = require "PZSurvivorToolkit/SourceProof"
local EditModel = require "PZSurvivorToolkit/ActionQueueEditModel"
local EditAdapters = require "PZSurvivorToolkit/ActionQueueEditAdapters"
local ItemEditAdapters = require "PZSurvivorToolkit/ActionQueueItemEditAdapters"
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
local ordinaryTransfer
local sharedEditResource

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
    if not Toolkit.Settings.actionQueue() or not queue or not live(queue)
        or queue:indexOf(action) == -1 then return "unavailable" end
    if queue.toolkitCancel or queue.toolkitGroupCancel then return "stopping" end
    if craft(action) then return Policy.cancelOperationReason(queue, action, context) end
    if appliance(action) then return Policy.cancelOperationReason(queue, action, context) end
    local contract = inspect and inspect(action, context)
    if contract and contract.cancelOperation == false then return "dependent" end
    if action.Type == "ISQueueActionsAction" then
        if not deferredWorld(action) and not (contract and contract.deferred) then return "dependent" end
        return Policy.cancelOperationReason(queue, action, context)
    end
    local auditedCallbacks = contract and contract.callbacksSafe
    if action._isAddingActions or (action.onStartFunc and not craft(action) and not auditedCallbacks)
        or ((action.onCompleteFunc or action.onCancelFunc) and not resumableWorld(action) and not craft(action) and not auditedCallbacks)
        or action.retriggerLastAction or action.toolkitQueueLinked then return "dependent" end
    if not stoppable(action, context) and contract and contract.cancelWaiting then return Policy.cancelOperationReason(queue, action, context) end
    if not stoppable(action, context) and not independentBulk(action, context) then
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
    for item in pairs(leftContract and leftContract.containerOwners or {}) do if right[item] then return item end end
    for item in pairs(rightContract and rightContract.containerOwners or {}) do if left[item] then return item end end
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
    for kind in pairs(left.dynamicInputsByType or {}) do
        if right.unknownOutputs or (right.dynamicInputsByType and right.dynamicInputsByType[kind]) then return kind end
        for _, types in pairs({right.itemTypes, right.dynamicInputs, right.outputTypes}) do
            for fullType in pairs(types) do
                if fullType:match("[^.]+$") == kind then return kind end
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
    for kind in pairs(left.outputTypes or {}) do
        if (right.itemTypes and right.itemTypes[kind]) or (right.outputTypes and right.outputTypes[kind]) then return kind end
    end
    return false
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
        for target in pairs(left.targets or {}) do if right.targets and right.targets[target] then return target end end
        if left.hands and left.hands == right.hands then return left.hands end
        if (left.equipment and left.equipment == right.hands) or (right.equipment and right.equipment == left.hands) then return left.equipment or right.equipment end
    end
    local world = Toolkit.ActionQueueWorld
    if world and world.sharesTarget and world.sharesTarget(a, b) then return true end
    local objects = {a.generator, a.charger, a.object, a.moveProps and a.moveProps.object,
        a.toolkitWorldTarget, a.isoObject}
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
local function carriedContainers(container, character)
    if not instanceof(character, "IsoPlayer") then return end
    local chain, seen = {}, {}
    while instanceof(container, "ItemContainer") and not seen[container] do
        local kind = container:getType()
        if kind == "floor" or kind == "proximityInv" or kind == "twistInv_corpses" then return end
        chain[#chain + 1], seen[container] = container, true
        if container == character:getInventory() then return chain end
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
    return carriedContainers(container, character) ~= nil
end
ordinaryTransfer = function(action)
    if not transferMethodsAdopted then return true end
    for _, guard in ipairs(transferHelperGuards) do if not guard() then return false end end
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
local function nativeMatches(action, snapshot)
    if getmetatable(action) ~= snapshot.class or action.Type ~= snapshot.class.Type or not callbacksSafe(action) then return false end
    if snapshot.startHelperGuard and not snapshot.startHelperGuard() then return false end
    if snapshot.class == ISInventoryTransferAction and not ordinaryTransfer(action) then return false end
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
local function resources(action)
    local result = {items = {}, itemTypes = {}, targets = {}, cancelWaiting = true, interrupt = "finish-step"}
    for _, field in ipairs({"item", "gun", "magazine", "weapon", "primary", "secondary", "secondaryItem", "recipeItem", "device", "battery"}) do
        local item = action[field]
        if item and instanceof(item, "InventoryItem") then
            result.items[itemKey(item)] = true
            if item.getFullType then result.itemTypes[item:getFullType()] = true end
        end
    end
    return result
end
local function registerNative(name, inspector, helpers)
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
        matches = function(action) return nativeMatches(action, snapshot) end,
        inspect = inspector,
    })
end
Policy.registerNative = registerNative

function Policy.nativeUnequipVariant(previous, replacement, guard)
    local snapshot = snapshots[ISUnequipAction]
    if not snapshot or type(guard) ~= "function" or not guard() then return end
    local variant = {class = snapshot.class, methods = {}, helpers = snapshot.helpers}
    for name, method in pairs(snapshot.methods) do variant.methods[name] = method end
    for _, name in ipairs({"new", "complete"}) do
        if snapshot.methods[name] ~= previous[name] or ISUnequipAction[name] ~= replacement[name]
            or type(replacement[name]) ~= "function" then return end
        variant.methods[name] = replacement[name]
    end
    return function(action) return guard() and nativeMatches(action, variant) end
end

function Policy.adoptTransferHooks(previous, replacement, guard)
    local snapshot = snapshots[ISInventoryTransferAction]
    local preparation = nativePreparation[ISInventoryTransferAction]
    if not snapshot or type(guard) ~= "function" or not guard() then return false end
    for _, name in ipairs({"new", "perform"}) do
        if snapshot.methods[name] ~= previous[name] or ISInventoryTransferAction[name] ~= replacement[name]
            or type(previous[name]) ~= "function" or type(replacement[name]) ~= "function" then return false end
    end
    if snapshot.helpers.transferItem ~= (previous.transferItem or false)
        or ISInventoryTransferAction.transferItem ~= replacement.transferItem then return false end
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

local function transferResources(action)
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
    if ItemEditAdapters then result.edit = ItemEditAdapters.transfer(action) end
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
        if not ISFluidContainer or getmetatable(wrapper) ~= ISFluidContainer then return end
        if not instanceof(wrapper.fluidContainer, "FluidContainer") then return end
        if wrapper.isFluidResource then
            if not instanceof(wrapper.fluidResource, "ResourceFluid") then return end
        elseif wrapper.fluidResource then return end
        local owner = wrapper.isFluidResource and wrapper.fluidResource:getGameEntity() or wrapper.fluidContainer:getOwner()
        if not owner then return end
        if instanceof(owner, "InventoryItem") then
            result.items[itemKey(owner)], result.itemTypes[owner:getFullType()] = true, true
        else result.targets[owner] = true end
        if wrapper.fluidResource then result.targets[wrapper.fluidResource] = true end
    end
    return result
end
local function radioResources(action)
    if not radioModes[action.mode] then return end
    for name, method in pairs(radioMethods) do if (action[name] or false) ~= method then return end end
    local result = resources(action)
    local target = action.device or action.deviceData
    if target and not instanceof(target, "InventoryItem") then result.targets[target] = true end
    if EditAdapters then result.edit = EditAdapters.radio(action) end
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
        local edit=ItemEditAdapters and ItemEditAdapters.food(action)
        if edit then
            local result=resources(action)
            result.edit=edit
            result.capacityNonIncreasing=not (action.item:getReplaceOnUse() or action.item:getScriptItem():getReplaceOnUse())
            -- Replacement food decreases in weight only while it survives every
            -- portion. A transfer edit can otherwise bypass the food component.
            result.capacityRequiresEdit=not result.capacityNonIncreasing
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
    registerNative("ISInventoryTransferAction", transferResources)
    registerNative("ISRadioAction", radioResources)
    for _, name in ipairs({"ISWalkToTimedAction", "ISWalkToTimedActionF", "ISPathFindAction"}) do
        registerNative(name, function(action)
            local result = resources(action); result.cancelWaiting, result.preparation = false, true; return result
        end)
    end
    for _, name in ipairs({"ISEquipWeaponAction", "ISEquipHeavyItem", "ISUnequipAction"}) do
        registerNative(name, function(action)
            local result = itemResources(action)
            if result then result.hands = action.character; result.cancelWaiting, result.preparation = false, true end
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

Definitions.registerBehavior("toolkit.food", {types = {"ISQueueActionsAction"}, matches = function(action)
    local Food = Toolkit.BulkFood
    return Food and (Food.isCommand(action) or (Food.isOpeningWait and Food.isOpeningWait(action)))
end, inspect = function(action)
    local result = resources(action)
    result.deferred, result.preparationFinish, result.unknownOutputs = true, true, true
    return result
end})

inspect = function(action, context)
    local cached = context and context.contracts[action]
    if cached then return unpack(cached, 1, 3) end
    if action._isAddingActions or (Operations.isContinuationPending and Operations.isContinuationPending(action.toolkitQueueOperation)) then
        if context then context.contracts[action] = {} end
        return
    end
    if not context then return Definitions.inspect(action) end
    local result = {Definitions.inspect(action)}
    context.contracts[action] = result
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
    local changed = true
    while changed do
        changed = false
        for _, member in ipairs(members) do
            if not component[member] then
                for related in pairs(component) do
                    if sharedEditResource(contracts[member], contracts[related])
                        or sharedItem(member, related, context) or sharedWorldTarget(member, related, context)
                        or dynamicConflict(member, related, context) or dynamicConflict(related, member, context) then
                        component[member], changed = true, true
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
    return carriedContainers(container, character) ~= nil
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

local function transferCapacityConflict(queue, a, b, last, check, context)
    local carts = Toolkit.ActionQueueCarts
    local function transfer(action)
        return action.Type == "ISInventoryTransferAction"
            or (action.Type == "ISCartTransferAction" and carts and type(carts.isTransfer) == "function" and carts.isTransfer(action))
    end
    local aTransfer, bTransfer = transfer(a), transfer(b)
    if (aTransfer and not bTransfer) or (bTransfer and not aTransfer) then
        local equipment = inspect(aTransfer and b or a, context)
        -- Hand/slot changes can alter carried weight or move heavy items out of external containers.
        if equipment and equipment.hands == queue.character then return queue.character:getInventory() end
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
            if cartCapacity and (not carts or not carts.capacitySafe or not carts.capacitySafe(container)) then return false end
            load = {container:getCapacityWeight(), container:getEffectiveCapacity(character), container:getAcceptItemFunction() == nil}
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
            if check.readDemotion then destinations = destinations or fixedWorldContainer(destination) end
            if action.character ~= character or (not sourceCarried
                and not (check.readDemotion and fixedWorldContainer(source)))
                or not destinations then return check.blocker end
            local function add(item)
                if not instanceof(item, "InventoryItem") or instanceof(item, "InventoryContainer") then return false end
                local id, kind = item:getID(), item:getType()
                if seen[id] then return true end
                seen[id] = true
                if kind == "CandleLit" or kind == "Lantern_HurricaneLit" then return false end
                local weight = item:getUnequippedWeight()
                if not finiteWeight(weight) then return false end
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
                    and destination == root and source ~= root and not source:getParent()
                    and item:getContainer() == source and source:contains(item) and not item:getIsCraftingConsumed()
                    and not character:getVehicle() and root:getAcceptItemFunction() == nil
                    and root:getOnlyAcceptCategory() == nil then
                    incoming[source] = (incoming[source] or 0) - weight
                end
                touched[id] = true
                return true
            end
            if not add(action.item) then return check.blocker end
            for _, batch in ipairs(action.queueList or {}) do
                for _, item in ipairs(batch.items or {}) do if not add(item) then return check.blocker end end
            end
        elseif not capacityNeutral[action.Type] and not boundedWaterDrink(action, character, source)
            and not (source == "native.ISEatFoodAction" and contract.edit
                and (contract.capacityNonIncreasing == true or conditionalCapacity[action]))
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

function Policy.cancelOperationReason(queue, action, context)
    context = context or {contracts = {}, items = {}}
    context.editFallback = nil
    if not Toolkit.Settings.actionQueue() or not queue or not live(queue)
        or queue:indexOf(action) == -1 then return "unavailable" end
    if queue.toolkitCancel or queue.toolkitGroupCancel then return "stopping" end
    local first, last = Operations.bounds(queue, action)
    if not first then return "operation_dependent" end
    local token = action.toolkitQueueOperation
    if Operations.isContinuationPending and Operations.isContinuationPending(token) then return "operation_dependent" end
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
        if contract and contract.cancelOperation == false then return "operation_dependent", nil, nil, member end
        local auditedCallbacks = contract and contract.callbacksSafe
        if member._isAddingActions or ((member.onStartFunc or member.onCancelFunc) and not auditedCraft and not resumableWorld(member) and not auditedCallbacks) or member.retriggerLastAction
            or (member.onCompleteFunc and member.onCompleteFunc ~= member.toolkitQueueSafeOnComplete
                and not auditedCraft and not resumableWorld(member) and not auditedCallbacks)
            or (member.forceCancel ~= nativeForceCancel and not (contract and contract.forceCancel == member.forceCancel)) then return "operation_dependent" end
        local plannedCraft, world = craftPlan(member), deferredWorld(member)
        if member.Type == "ISQueueActionsAction" and not plannedCraft and not world and not (contract and contract.deferred) then
            return "operation_dependent"
        end
        local supported = stoppable(member, context) or independentBulk(member, context) or world or plannedCraft or appliance(member)
            or (contract and contract.cancelWaiting)
        if not supported and not (contract and contract.preparation) then return "operation_dependent" end
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
    for i, other in ipairs(queue.queue) do
        if i > last or (i < first and not pendingRemovalOnly) then
            if other._isAddingActions or not knownCraftInputs(other, context) then return "operation_dependent", nil, nil, other end
            for item in pairs(operationItems(other, context)) do
                if inputs[item] then return "operation_shared_item", nil, nil, other, item end
            end
            for j = first, last do
                local item = sharedItem(queue.queue[j], other, context)
                if item then return "operation_shared_item", nil, nil, other, item end
                local conflict = sharedWorldTarget(queue.queue[j], other, context) or dynamicConflict(queue.queue[j], other, context)
                    or dynamicConflict(other, queue.queue[j], context)
                if conflict then return "operation_dependent", nil, nil, other, conflict end
                local capacity = transferCapacityConflict(queue, queue.queue[j], other, #queue.queue, capacityCheck, context)
                if capacity then return "container_capacity", nil, nil, other, capacity end
            end
            -- shortcut: output requirements of arbitrary later actions are unknown; add verified adapters to allow them.
            if output and i > last then
                local independentCraft = craft(other) and knownCraftInputs(other, context)
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
            or not knownCraftInputs(member, context) then return "move_dependent" end
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
        if member._isAddingActions then return "move_dependent" end
        if not knownCraftInputs(member, context) and not repairInputs(member) then
            return craft(member) and "move_craft_inputs" or "move_dependent"
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
            if crossed._isAddingActions then return "move_dependent", nil, nil, nil, nil, crossed end
            if not knownCraftInputs(crossed, context) and not repairInputs(crossed) then
                return craft(crossed) and "move_craft_inputs" or "move_dependent", nil, nil, nil, nil, crossed
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
    for i = math.min(first, to), math.min(#queue.queue, math.max(last, to - 1)) do
        if i < first or i > last then
            local crossed = queue.queue[i]
            if crossed._isAddingActions then return "move_dependent", nil, nil, nil, nil, crossed end
            if not knownCraftInputs(crossed, context) and not repairInputs(crossed) then
                return craft(crossed) and "move_craft_inputs" or "move_dependent", nil, nil, nil, nil, crossed
            end
            for j = first, last do
                local reason, resource = moveConflict(queue, queue.queue[j], crossed, math.max(last, to - 1), capacityCheck, context)
                if reason then return reason, nil, nil, nil, nil, crossed, resource end
            end
        end
    end
    if first < to then to = to - (last - first + 1) end
    return nil, to, first, last, preempt
end


Policy.live, Policy.stoppable = live, stoppable
Policy.resumableWorld, Policy.preparationCanFinish = resumableWorld, preparationCanFinish
Policy.operationItems = operationItems

function Policy.replaceStop(previous, replacement)
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
    if resourceDenials[reason] and edit and edit.reason then
        return edit.reason, edit.blocker or blocker, edit.resource or resource
    end
    return reason, blocker, resource
end

-- Presentation only: no edit snapshot or authority to mutate the queue. Callers
-- must evaluate again at the actual move/cancel boundary, with fresh live facts.
function Policy.previewMove(queue, action, target, after)
    local context = {contracts = {}, items = {}}
    local reason, to, first, last, preempt, blocker, resource = Policy.moveReason(queue, action, target, after, context)
    reason, blocker, resource = editDenial(reason, blocker, resource, context)
    return {reason = reason, blocker = blocker, resource = resource}
end

function Policy.previewCancel(queue, action, whole)
    local context = {contracts = {}, items = {}}
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

function Policy.evaluateCancel(queue, action, whole)
    local context = {contracts = {}, items = {}}
    local snapshot = editSnapshot(queue)
    local reason, first, last, blocker, resource
    if whole then reason, first, last, blocker, resource = Policy.cancelOperationReason(queue, action, context)
    else reason, first, last, blocker, resource = Policy.cancelReason(queue, action, context) end
    reason, blocker, resource = editDenial(reason, blocker, resource, context)
    if not reason and not Policy.editUnchanged(queue, snapshot) then reason = "unavailable" end
    return {allowed = reason == nil, reason = reason, first = first, last = last,
        mode = queue and action == queue.current and "active" or "pending", blocker = blocker, resource = resource, snapshot = snapshot}
end

function Policy.evaluatePriority(queue, action, preempt)
    if not queue or not queue.current or queue.queue[1] ~= queue.current then return {allowed = false, reason = "unavailable"} end
    local _, activeLast = Operations.bounds(queue, queue.current)
    if not activeLast then return {allowed = false, reason = "operation_dependent"} end
    local activeToken = queue.current.toolkitQueueOperation
    local context = {contracts = {}, items = {}}
    if preempt and activeLast == 1 and not (activeToken and activeToken.toolkitPriority == "urgent") then
        local decision = Policy.evaluateMove(queue, action, queue.current, false, context)
        if decision.allowed then decision.target = queue.current; return decision end
    end
    local target = queue.queue[activeLast]
    local decision = Policy.evaluateMove(queue, action, target, true, context)
    decision.target, decision.after = target, true
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
