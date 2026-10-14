require "PZSurvivorToolkit/ActionQueueDefinitions"
require "PZSurvivorToolkit/SetStoveStateAction"
require "Fluids/ISFluidContainer"
require "Fluids/ISFluidTransferAction"
require "Fluids/ISFluidEmptyAction"
require "TimedActions/ISActivateGenerator"
require "TimedActions/ISFixGenerator"
require "TimedActions/ISRemoveCarBatteryFromChargerAction"
require "TimedActions/ISTakeCarBatteryChargerAction"

local Toolkit = PZSurvivorToolkit
local Policy = {}
Toolkit.ActionQueuePolicy = Policy
local Operations = Toolkit.ActionQueueOperations
local nativeForceCancel = ISBaseTimedAction.forceCancel
local inspect
local ordinaryTransfer

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

local function independentBulk(action)
    local contract = inspect and inspect(action)
    return action.toolkitIndependentBulk and contract and contract.bulk == true
end

local function stoppable(action)
    local contract = inspect and inspect(action)
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

function Policy.cancelReason(queue, action)
    if not Toolkit.Settings.actionQueue() or not queue or not live(queue)
        or queue:indexOf(action) == -1 then return "unavailable" end
    if queue.toolkitCancel or queue.toolkitGroupCancel then return "stopping" end
    if craft(action) then return Policy.cancelOperationReason(queue, action) end
    if appliance(action) then return Policy.cancelOperationReason(queue, action) end
    local contract = inspect and inspect(action)
    if contract and contract.cancelOperation == false then return "dependent" end
    if action.Type == "ISQueueActionsAction" then
        if not deferredWorld(action) and not (contract and contract.deferred) then return "dependent" end
        return Policy.cancelOperationReason(queue, action)
    end
    local auditedCallbacks = contract and contract.callbacksSafe
    if action._isAddingActions or (action.onStartFunc and not craft(action) and not auditedCallbacks)
        or ((action.onCompleteFunc or action.onCancelFunc) and not resumableWorld(action) and not craft(action) and not auditedCallbacks)
        or action.retriggerLastAction or action.toolkitQueueLinked then return "dependent" end
    if not stoppable(action) and contract and contract.cancelWaiting then return Policy.cancelOperationReason(queue, action) end
    if not stoppable(action) and not independentBulk(action) then
        return "dependent"
    end
    if independentBulk(action) then
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
        if not stoppable(action) then return "active" end
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
local function sharedItem(a, b)
    local left, right = operationItems(a), operationItems(b)
    for item in pairs(left) do if right[item] then return item end end
    local leftContract, rightContract = inspect(a), inspect(b)
    for item in pairs(leftContract and leftContract.containerOwners or {}) do if right[item] then return item end end
    for item in pairs(rightContract and rightContract.containerOwners or {}) do if left[item] then return item end end
end

local function knownCraftInputs(action)
    if action.toolkitWorldOperation == "fuel" or action.toolkitWorldOperation == "wreck" then return false end
    if craft(action) and not Toolkit.ActionQueueCraft.futureResources then return Toolkit.ActionQueueCraft.collectItems(action, {}) end
    local contract = inspect(action)
    return contract ~= nil and contract.knownInputs ~= false
end

local function dynamicConflict(a, b)
    local left, right = inspect(a), inspect(b)
    if not left or not right then return false end
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

local function sharedWorldTarget(a, b)
    local left, right = inspect and inspect(a), inspect and inspect(b)
    if left and right then
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

local function preparationCanFinish(action)
    if action.Type == "ISInventoryTransferAction" and ordinaryTransfer and not ordinaryTransfer(action) then return false end
    local contract = inspect and inspect(action)
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

operationItems = function(action)
    local items = {}
    for _, key in ipairs(itemFields) do
        local item = action[key]
        if item and instanceof(item, "InventoryItem") then items[item] = true end
    end
    if action.recipeItem and instanceof(action.recipeItem, "InventoryItem") then items[action.recipeItem] = true end
    if Toolkit.ActionQueueCraft then Toolkit.ActionQueueCraft.collectItems(action, items) end
    local keys = {}
    for item in pairs(items) do keys[itemKey(item)] = true end
    local contract = inspect and inspect(action)
    if contract then for key in pairs(contract.items or {}) do keys[key] = true end end
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

local function repairCanCross(repair, other)
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
        and other.Type ~= "ISWalkToTimedActionF" and other.Type ~= "ISPathFindAction") or not preparationCanFinish(other) then
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
local function ordinaryTransferContainer(container, character)
    if not instanceof(container, "ItemContainer") then return false end
    local kind = container:getType()
    if kind == "floor" or kind == "proximityInv" or kind == "twistInv_corpses" then return false end
    local bag = container:getContainingItem()
    if not bag then return true end
    return instanceof(bag, "InventoryContainer") and instanceof(character, "IsoPlayer")
        and bag:getContainer() == character:getInventory()
end
ordinaryTransfer = function(action)
    if not transferMethodsAdopted then return true end
    for _, guard in ipairs(transferHelperGuards) do if not guard() then return false end end
    return ordinaryTransferContainer(action.srcContainer, action.character)
        and ordinaryTransferContainer(action.destContainer, action.character)
end
Policy.isOrdinaryTransfer = ordinaryTransfer
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

function Policy.adoptReadAnimEvent(previous, replacement)
    local snapshot = snapshots[ISReadABook]
    if not snapshot or snapshot.methods.animEvent ~= previous or ISReadABook.animEvent ~= replacement
        or type(previous) ~= "function" or type(replacement) ~= "function" then return false end
    snapshot.methods.animEvent = replacement
    return true
end

function Policy.adoptTransferFloorHelper(previous, replacement)
    local snapshot = snapshots[ISInventoryTransferAction]
    if not snapshot or snapshot.helpers.getNotFullFloorSquare ~= previous
        or ISInventoryTransferAction.getNotFullFloorSquare ~= replacement
        or type(previous) ~= "function" or type(replacement) ~= "function" then return false end
    -- The native transfer ignores the helper's square for a non-floor destination.
    transferFloorHelper = {previous = previous, replacement = replacement}
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
    return true
end

local function itemResources(action)
    if not action.item or not instanceof(action.item, "InventoryItem") then return end
    return resources(action)
end

function Policy.addContainerResources(result, container)
    if not instanceof(container, "ItemContainer") then return end
    local parent = container:getParent()
    if parent and not instanceof(parent, "IsoGameCharacter") then result.targets[parent] = true end
    local bag = container.getContainingItem and container:getContainingItem()
    if instanceof(bag, "InventoryContainer") then
        result.containerOwners = result.containerOwners or {}
        result.containerOwners[bag:getID()] = true
        result.itemTypes[bag:getFullType()] = true
    end
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
    return result
end
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
        if instanceof(owner, "InventoryItem") then result.items[itemKey(owner)] = true else result.targets[owner] = true end
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
    return result
end
function Policy.installContracts()
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

inspect = function(action)
    if action._isAddingActions or (Operations.isContinuationPending and Operations.isContinuationPending(action.toolkitQueueOperation)) then return end
    return Definitions.inspect(action)
end
Policy.inspect = inspect

local capacityNeutral = {ISReadABook = true, ISWalkToTimedAction = true, ISWalkToTimedActionF = true, ISPathFindAction = true}
local function carriedContainer(container, character)
    if not instanceof(container, "ItemContainer") or not instanceof(character, "IsoPlayer") then return false end
    if container == character:getInventory() then return true end
    local bag = container:getContainingItem()
    return instanceof(bag, "InventoryContainer") and bag:getContainer() == character:getInventory()
end

local function finiteWeight(value)
    return type(value) == "number" and value >= 0 and value < math.huge
end

local function transferCapacityConflict(queue, a, b, last, check)
    if a.Type ~= "ISInventoryTransferAction" or b.Type ~= "ISInventoryTransferAction" then return end
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
    if check.done then return check.blocker end
    local root = character:getInventory()
    check.done, check.blocker = true, shared or root
    local incoming = {[root] = 0}
    -- Ignore outgoing space: neither reordering nor cancellation may depend on a prior transfer freeing it.
    for i = 1, last do
        local action = queue.queue[i]
        local contract = inspect(action)
        if not contract or contract.knownInputs == false then return check.blocker end
        if action.Type == "ISInventoryTransferAction" then
            if action.character ~= character or not carriedContainer(action.srcContainer, character)
                or not carriedContainer(action.destContainer, character) then return check.blocker end
            local destination, seen = action.destContainer, {}
            local function add(item)
                if not instanceof(item, "InventoryItem") or instanceof(item, "InventoryContainer") then return false end
                local id, kind = item:getID(), item:getType()
                if seen[id] then return true end
                seen[id] = true
                if kind == "CandleLit" or kind == "Lantern_HurricaneLit" then return false end
                local weight = item:getUnequippedWeight()
                if not finiteWeight(weight) then return false end
                incoming[root] = incoming[root] + weight
                if destination ~= root then incoming[destination] = (incoming[destination] or 0) + weight end
                return true
            end
            if not add(action.item) then return check.blocker end
            for _, batch in ipairs(action.queueList or {}) do
                for _, item in ipairs(batch.items or {}) do if not add(item) then return check.blocker end end
            end
        elseif not capacityNeutral[action.Type] then
            -- shortcut: other actions may change carried weight; add verified weight effects before crossing their prefix.
            return check.blocker
        end
    end
    for container, weight in pairs(incoming) do
        check.blocker = container
        if container:getAcceptItemFunction() ~= nil then return container end
        local current, capacity = container:getCapacityWeight(), container:getEffectiveCapacity(character)
        -- Native capacity checks round the current load to hundredths at each transfer.
        if not finiteWeight(current) or not finiteWeight(capacity) or not finiteWeight(weight)
            or current + weight + 0.01 > capacity then return container end
    end
    check.blocker = nil
end

function Policy.cancelOperationReason(queue, action)
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
    for i = first, last do
        local member = queue.queue[i]
        if (member.action or member == queue.current or i == 1) and not (active and i == first) then
            return "operation_active"
        end
        local auditedCraft = craft(member)
        local contract = inspect(member)
        if contract and contract.cancelOperation == false then return "operation_dependent", nil, nil, member end
        local auditedCallbacks = contract and contract.callbacksSafe
        if member._isAddingActions or ((member.onStartFunc or member.onCancelFunc) and not auditedCraft and not resumableWorld(member) and not auditedCallbacks) or member.retriggerLastAction
            or (member.onCompleteFunc and member.onCompleteFunc ~= member.toolkitQueueSafeOnComplete
                and not auditedCraft and not resumableWorld(member) and not auditedCallbacks)
            or member.forceCancel ~= nativeForceCancel then return "operation_dependent" end
        local plannedCraft, world = craftPlan(member), deferredWorld(member)
        if member.Type == "ISQueueActionsAction" and not plannedCraft and not world and not (contract and contract.deferred) then
            return "operation_dependent"
        end
        local supported = stoppable(member) or independentBulk(member) or world or plannedCraft or appliance(member)
            or (contract and contract.cancelWaiting)
        if not supported and not (contract and contract.preparation) then return "operation_dependent" end
        main = main or supported
        if supported then
            scrapOnly = scrapOnly and ((world and member.toolkitWorldDismantle)
                or (member.Type == "ISMoveablesAction" and member.mode == "scrap"))
        end
        output = output or member.toolkitIndependentBulk or auditedCraft or (world and member.toolkitWorldDismantle) or plannedCraft
            or (member.Type == "ISMoveablesAction" and member.mode == "scrap")
        for item in pairs(operationItems(member)) do inputs[item] = true end
    end
    if not main then return "operation_dependent" end
    if active then
        local current = queue.current
        if current.action and (current.action:finished() or current.action:isForceComplete()) then return "starting" end
        if stoppable(current) then
            if not current.action or not current.action:isStarted() then return "starting" end
        elseif not preparationCanFinish(current) then
            return "operation_active"
        end
    end
    for item in pairs(type(token) == "table" and token.toolkitPickups or {}) do inputs[itemKey(item)] = true end
    local capacityCheck = {}
    for i, other in ipairs(queue.queue) do
        if i < first or i > last then
            if other._isAddingActions or not knownCraftInputs(other) then return "operation_dependent", nil, nil, other end
            for item in pairs(operationItems(other)) do
                if inputs[item] then return "operation_shared_item", nil, nil, other, item end
            end
            for j = first, last do
                local item = sharedItem(queue.queue[j], other)
                if item then return "operation_shared_item", nil, nil, other, item end
                local conflict = sharedWorldTarget(queue.queue[j], other) or dynamicConflict(queue.queue[j], other)
                    or dynamicConflict(other, queue.queue[j])
                if conflict then return "operation_dependent", nil, nil, other, conflict end
                local capacity = transferCapacityConflict(queue, queue.queue[j], other, #queue.queue, capacityCheck)
                if capacity then return "container_capacity", nil, nil, other, capacity end
            end
            -- shortcut: output requirements of arbitrary later actions are unknown; add verified adapters to allow them.
            if output and i > last then
                local independentCraft = craft(other) and knownCraftInputs(other)
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

function Policy.moveReason(queue, action, target, after)
    if not Toolkit.Settings.actionQueue() or not queue or not live(queue)
        or queue:indexOf(action) == -1 or queue:indexOf(target or action) == -1 then return "unavailable" end
    if queue.toolkitCancel or queue.toolkitGroupCancel then return "stopping" end
    local first, last = Operations.bounds(queue, action)
    local targetFirst, targetLast = Operations.bounds(queue, target or action)
    if not first or not targetFirst then return "move_dependent" end
    for i = first, last do
        local member = queue.queue[i]
        if member.action or member == queue.current or i == 1 then return "move_active" end
        if member._isAddingActions then return "move_dependent" end
        if not knownCraftInputs(member) and not repairInputs(member) then
            return craft(member) and "move_craft_inputs" or "move_dependent"
        end
    end
    if first == targetFirst then return nil, first, first, last end
    local to = after and targetLast + 1 or targetFirst
    local preempt = to == 1
    if preempt then
        local supported, reason = resumableWorld(queue.current)
        if not queue.current or (queue.current.Type ~= "ISReadABook" and not supported)
            or Policy.cancelReason(queue, queue.current) then return reason or "move_active" end
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
    local capacityCheck = {}
    for i = math.min(first, to), math.min(#queue.queue, math.max(last, to - 1)) do
        if i < first or i > last then
            local crossed = queue.queue[i]
            if crossed._isAddingActions then return "move_dependent", nil, nil, nil, nil, crossed end
            if not knownCraftInputs(crossed) and not repairInputs(crossed) then
                return craft(crossed) and "move_craft_inputs" or "move_dependent", nil, nil, nil, nil, crossed
            end
            for j = first, last do
                local item = sharedItem(queue.queue[j], crossed)
                if item then return "move_shared_item", nil, nil, nil, nil, crossed, item end
                local dynamic = dynamicConflict(queue.queue[j], crossed) or dynamicConflict(crossed, queue.queue[j])
                if dynamic then return "move_craft_inputs", nil, nil, nil, nil, crossed, dynamic end
                if not repairCanCross(queue.queue[j], crossed) or not repairCanCross(crossed, queue.queue[j]) then
                    return "move_craft_inputs", nil, nil, nil, nil, crossed
                end
                local target = sharedWorldTarget(queue.queue[j], crossed)
                if target then return "move_dependent", nil, nil, nil, nil, crossed, target end
                local capacity = transferCapacityConflict(queue, queue.queue[j], crossed, math.max(last, to - 1), capacityCheck)
                if capacity then return "container_capacity", nil, nil, nil, nil, crossed, capacity end
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
    for _, snapshot in pairs(snapshots) do
        if snapshot.methods.stop == previous then snapshot.methods.stop = replacement end
    end
    for _, snapshots in ipairs({nativePreparation, repairIndependent}) do
        for _, methods in pairs(snapshots) do
            if methods.stop == previous then methods.stop = replacement end
        end
    end
end

function Policy.evaluateMove(queue, action, target, after)
    local reason, to, first, last, preempt, blocker, resource = Policy.moveReason(queue, action, target, after)
    return {allowed = reason == nil, reason = reason, to = to, first = first, last = last,
        mode = preempt and "audited-resume" or "move", preempt = preempt, blocker = blocker, resource = resource}
end

function Policy.evaluateCancel(queue, action, whole)
    local reason, first, last, blocker, resource
    if whole then reason, first, last, blocker, resource = Policy.cancelOperationReason(queue, action)
    else reason, first, last, blocker, resource = Policy.cancelReason(queue, action) end
    return {allowed = reason == nil, reason = reason, first = first, last = last,
        mode = queue and action == queue.current and "active" or "pending", blocker = blocker, resource = resource}
end

function Policy.evaluatePriority(queue, action, preempt)
    if not queue or not queue.current or queue.queue[1] ~= queue.current then return {allowed = false, reason = "unavailable"} end
    local _, activeLast = Operations.bounds(queue, queue.current)
    if not activeLast then return {allowed = false, reason = "operation_dependent"} end
    local activeToken = queue.current.toolkitQueueOperation
    if preempt and activeLast == 1 and not (activeToken and activeToken.toolkitPriority == "urgent") then
        local decision = Policy.evaluateMove(queue, action, queue.current, false)
        if decision.allowed then decision.target = queue.current; return decision end
    end
    local target = queue.queue[activeLast]
    local decision = Policy.evaluateMove(queue, action, target, true)
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
