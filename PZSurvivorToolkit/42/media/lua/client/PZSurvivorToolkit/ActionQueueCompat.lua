require "PZSurvivorToolkit/ActionQueueOperations"
require "PZSurvivorToolkit/ActionQueueLifecycle"
require "PZSurvivorToolkit/ActionQueueDefinitions"
require "ISUI/ISXuiSkin"

local Toolkit = PZSurvivorToolkit
local Operations = Toolkit.ActionQueueOperations
local TidyIntent = require "PZSurvivorToolkit/ActionQueueTidyIntent"
local Compat = {}
Toolkit.ActionQueueCompat = Compat
local records = {}
local classes, installed, sessions = {}, {}, {}
local owners = {}
local craftOwners = {}
local projectCookConfig
local nativeXuiMethods = ISXuiSkinFunctions and {
    xuiRecalculateLayout = ISXuiSkinFunctions.xuiRecalculateLayout,
    xuiRootElement = ISXuiSkinFunctions.xuiRootElement,
} or {}
local ready = {}
local sourceScope
local worldGeneration = 0
local installAttempted
local readFixAttempted
local transferSourceSafe = true
local containerTransferPerform
local containerHelpersUnchanged
local manifestTransferPerform, manifestHelpersUnchanged
local washWalkHelper
local tidyClassUnchanged, tidyActionUnchanged
local tidyFloorPage, tidyFloorGetter
local tidyFloorValid
local repairedFloors = setmetatable({}, {__mode = "k"})
local lifecycle = {"new", "isValid", "isValidStart", "waitToStart", "start", "update", "stop", "perform",
    "complete", "getDuration", "serverStart", "serverStop", "animEvent", "forceStop", "forceCancel"}
local projectCookActionSources = {
    {"client/Project_Cook/EvolvedRecipePanel/OverrideFoodRelatedAction.lua", 222676723},
    {"shared/Project_Cook/PJCK_FrozenCooking.lua", 3756381974},
}
local sourceFiles = {
    SaucedCartsTransfers = {
        {"shared/SaucedCarts/TimedActions/ISCartTransferAction.lua", 3962234240},
        {"shared/SaucedCarts/CartTransferInterceptor.lua", 2772644904},
        {"shared/SaucedCarts/Core.lua", 2570266575},
        {"shared/SaucedCarts/Network.lua", 2897409368},
        {"client/SaucedCarts/Restrictions/TransferRestrictions.lua", 2976371209},
        {"client/SaucedCarts/CartState/VisualUpdateQueue.lua", 2627823607},
    },
    WashFix = {
        {"client/ISUI/WMI_WashingSubmenus.lua", 3809430929},
        {"client/ISUI/WMI_CleanBandagesContext.lua", 2564019136},
        {"shared/TimedActions/WMI_PatchWashClothing.lua", 2935848012},
    },
    NeatUI_Equipment = {
        {"client/NeatEquipment/NEQ_Dresser.lua", 859961585},
        {"client/NeatEquipment/NEQ_AttachAction.lua", 3212833623},
    },
    P4TidyUpMeister = {
        {"client/P4TidyUpMeister.lua", 389269229},
        {"shared/TimedActions/P4RestoreAction.lua", 1645293368},
        {"shared/TimedActions/P4RestoreFloorAction.lua", 1126532530},
    },
    Neat_Crafting = {{"client/Neat_Crafting/NC_CraftActionPanel.lua", 2203522815}},
    Project_Cook = {
        {"client/Project_Cook/HandCraftPanel/PJCK_CraftActionPanel.lua", 253384307},
        {"client/Project_Cook/EvolvedRecipePanel/PJCK_EvoPanel.lua", 286152189},
        {"client/Project_Cook/PJCK_Config.lua", 2629049005},
        projectCookActionSources[1],
        projectCookActionSources[2],
        {"shared/Project_Cook/PJCK_EvolvedSpiceGuard.lua", 2430144672},
    },
    MPFastForward = {{"server/MPFastForward_ReadFix.lua", 598888215}},
    SaucedCarts = {
        {"client/SaucedCarts/ConsumeWithCart.lua", 2924576916},
        {"shared/SaucedCarts/Core.lua", 2570266575},
    },
    EURY_CONTAINERS = {
        {"client/BetterContainers/Proximity.lua", 3626949969},
        {"client/BetterContainers/Proximity/Proximity_ISInventoryTransferAction.lua", 909048245},
        {"client/BetterContainers/Nested.lua", 2806093898},
        {"shared/BetterContainers/Helpers.lua", 365367801},
    },
}

local function pack(...) return {n = select("#", ...), ...} end

function Compat.prune()
    local pending = false
    for _, registry in ipairs({records, sessions}) do
        for _ in pairs(registry) do pending = true; break end
        if pending then break end
    end
    if not pending then return end
    local queued = {}
    for character, queue in pairs(ISTimedActionQueue.queues) do
        if not character:isDead() then
            for _, action in ipairs(queue.queue or {}) do queued[action] = true end
        end
    end
    for action in pairs(records) do if not queued[action] then records[action] = nil end end
    for character, session in pairs(sessions) do
        if character:isDead() or ISTimedActionQueue.queues[character] ~= session.queue
            or (session.queue.toolkitOperationGeneration or 0) ~= session.generation then
            sessions[character] = nil
        else
            -- Delayed Tidy restores still need task/pickup history after the source action leaves the queue.
            for action in pairs(session.seen) do if not queued[action] then session.seen[action] = nil end end
        end
    end
end
Events.OnTick.Add(Compat.prune)
if Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(function()
    worldGeneration = worldGeneration + 1
    for action in pairs(records) do records[action] = nil end
    for character in pairs(sessions) do sessions[character] = nil end
end) end

-- getModFileReader resolves the selected B42 version, then common; no Workshop path is assumed.
local Proof = require "PZSurvivorToolkit/SourceProof"
local function verified(id, files)
    for _, file in ipairs(files or sourceFiles[id]) do
        if not Proof.matches("media/lua/" .. file[1], file[2], id, true) then return false end
    end
    return true
end
Compat.verifySources = verified

local quartermasterContainers
local CraftContainers = require "PZSurvivorToolkit/QuartermasterCraftContainers"
local activeCraftContext = CraftContainers.active
function Compat.matchesQuartermasterContainerGetter(previous, replacement)
    local saved = quartermasterContainers
    if not saved or saved.previous ~= previous or saved.replacement ~= replacement or LootSorter ~= saved.owner
        or not saved.owner._craftHooksAdded or not saved.owner._getContainersWrapped
        or ISTimedActionQueue ~= saved.queue or saved.queue.isPlayerDoingAction ~= saved.busy
        or CraftContainers.active ~= saved.active or saved.owner.DBG ~= saved.debug then return false end
    -- Only forwarding is audited; an active availability scan may call arbitrary storage helpers.
    if saved.owner.craftFromBoxes and not saved.owner._activelyCrafting and saved.active() then return false end
    return true
end
function Compat.installQuartermasterCraft(install)
    local owner = LootSorter
    if owner._craftHooksAdded then return end
    local previous = ISInventoryPaneContextMenu.getContainers
    local queue, busy = ISTimedActionQueue, ISTimedActionQueue.isPlayerDoingAction
    local active = activeCraftContext
    local debug = owner.DBG
    local neat = craftOwners.NC_CraftActionPanel
    local neatUnchanged = neat and NC_CraftActionPanel == neat.class
    if neatUnchanged then
        for method, expected in pairs(neat.methods) do
            if neat.class[method] ~= expected then neatUnchanged = false; break end
        end
    end
    install()
    local replacement = ISInventoryPaneContextMenu.getContainers
    if LootSorter ~= owner or not owner._craftHooksAdded or not owner._getContainersWrapped
        or CraftContainers.active ~= active then return end
    quartermasterContainers = {previous = previous, replacement = replacement, owner = owner, debug = debug,
        queue = queue, busy = busy, active = active}
    if neatUnchanged and NC_CraftActionPanel == neat.class then
        for method, expected in pairs(neat.methods) do
            if method ~= "prerender" and method ~= "onCraftButtonClick" and neat.class[method] ~= expected then
                neatUnchanged = false; break
            end
        end
        if neatUnchanged then
            neat.methods.prerender = neat.class.prerender
            neat.methods.onCraftButtonClick = neat.class.onCraftButtonClick
        end
    end
end

local function snapshot(class)
    local methods = {Type = class.Type}
    for _, name in ipairs(lifecycle) do methods[name] = class[name] end
    for name, method in pairs(class) do if type(method) == "function" then methods[name] = method end end
    return methods
end

local function classUnchanged(class, methods)
    for name, method in pairs(methods) do if class[name] ~= method then return false end end
    for _, name in ipairs(lifecycle) do if class[name] ~= methods[name] then return false end end
    return true
end

local function sourceClassUnchanged(id, class, methods)
    return classUnchanged(class, methods) or id == "P4TidyUpMeister" and (class == ISInventoryTransferAction or class == ISUnequipAction)
        and tidyClassUnchanged and tidyClassUnchanged(class, class, methods)
end

local function live(record)
    local character, queue, token = record.character, record.queue, record.token
    if not token or token.toolkitCancelled or not Toolkit.Settings.actionQueue()
        or (record.worldGeneration and record.worldGeneration ~= worldGeneration)
        or character:isDead() or ISTimedActionQueue.queues[character] ~= queue
        or (queue.toolkitOperationGeneration or 0) ~= record.generation then return false end
    local target = record.target
    if target and ((target.getObjectIndex and target:getObjectIndex() == -1)
        or (target.getSquare and not target:getSquare())) then return false end
    if record.id == "WashFix" and target and character.getSquare and target.getSquare then
        local here, there = character:getSquare(), target:getSquare()
        if not here or not there or here:getZ() ~= there:getZ()
            or math.abs(here:getX() - there:getX()) > 1 or math.abs(here:getY() - there:getY()) > 1 then return false end
    end
    return true
end

local function captureProjectCookConfig()
    if not pcall(require, "Project_Cook/PJCK_Config") or type(PJCK_Config) ~= "table" then return false end
    local methods = {}
    for _, name in ipairs({"get", "getBaseItemHandling", "shouldReturnBaseItemToSource", "load", "validate"}) do
        local callback = PJCK_Config[name]
        if not Proof.closure(callback, "PJCK_Config.lua") then return false end
        methods[name] = callback
    end
    projectCookConfig = {owner = PJCK_Config, methods = methods}
    return true
end

local function ownerUnchanged(id)
    if id == "Project_Cook" then
        if not projectCookConfig or PJCK_Config ~= projectCookConfig.owner then return false end
        for name, callback in pairs(projectCookConfig.methods) do
            if PJCK_Config[name] ~= callback then return false end
        end
    end
    if id == "WashFix" and washWalkHelper then
        local scopedWalk = sourceScope and sourceScope.id == id and sourceScope.walkAdjacentWrapper
        if luautils ~= washWalkHelper.owner or (luautils.walkAdj ~= washWalkHelper.callback and luautils.walkAdj ~= scopedWalk) then return false end
    end
    for _, owner in ipairs(owners[id] or {}) do
        for name, method in pairs(owner.methods) do if owner.target[name] ~= method then return false end end
    end
    return true
end

local function instanceUnchanged(target, class)
    if not target or getmetatable(target) ~= class then return false end
    for name, callback in pairs(class) do
        if type(callback) == "function" and target[name] ~= callback then return false end
    end
    for name, callback in pairs(target) do
        if type(callback) == "function" and callback ~= class[name] then return false end
    end
    return true
end

local function sourceMatches(action, record)
    record = record or records[action]
    if not record or getmetatable(action) ~= record.class or action.Type ~= record.class.Type
        or action.character ~= record.character or action.toolkitQueueOperation ~= record.token
        or not sourceClassUnchanged(record.id, record.class, record.baseline) or not ownerUnchanged(record.id)
        or (record.owner and not instanceUnchanged(record.owner, PJCK_EvoPanel))
        or (record.class == ISInventoryTransferAction and containerHelpersUnchanged and not containerHelpersUnchanged()) then return false end
    local policy = Toolkit.ActionQueuePolicy
    if record.class == ISInventoryTransferAction and policy and policy.isOrdinaryTransfer and not policy.isOrdinaryTransfer(action) then return false end
    if record.class == ISEquipWeaponAction and (action.primary ~= record.primary or action.twoHands ~= record.twoHands
        or action.alwaysTurnOn ~= record.alwaysTurnOn) then return false end
    if record.class == ISUnequipAction and (action.reason ~= record.reason or action.fromHotbar ~= record.fromHotbar
        or action.hotbar ~= record.hotbar) then return false end
    for _, name in ipairs(lifecycle) do if action[name] ~= record.methods[name] then return false end end
    for name, method in pairs(record.methods) do if action[name] ~= method then return false end end
    for name, method in pairs(action) do
        if type(method) == "function" and method ~= record.methods[name] then return false end
    end
    for _, name in ipairs({"onStartFunc", "onCancelFunc", "onCompleteFunc", "onCompleteTarget", "onCompleteArgs"}) do
        if action[name] ~= record[name] then return false end
    end
    for name, value in pairs(record.fields) do
        local identity = record.itemIdentities[name]
        if identity then
            local item = action[name]
            if not instanceof(item, "InventoryItem") or item:getID() ~= identity.id
                or item:getFullType() ~= identity.fullType then return false end
        elseif action[name] ~= value then return false end
    end
    if record.args then
        if getmetatable(action.onCompleteArgs) then return false end
        for i = 1, 8 do if action.onCompleteArgs[i] ~= record.args[i] then return false end end
    end
    if record.commandArgs then
        if getmetatable(action.args) then return false end
        for i, value in ipairs(record.commandArgs) do if action.args[i] ~= value then return false end end
    end
    return not action.retriggerLastAction and not action.onFailFunc and not action.additionalTest
end

local function matches(action, record)
    record = record or records[action]
    if not record or record.opaque then return false end
    return sourceMatches(action, record)
end

local function tidyRestoreContext(context, action)
    local session = context.tidySession
    local policy = Toolkit.ActionQueuePolicy
    if not session or not session.mixed or getmetatable(action) ~= ISInventoryTransferAction
        or not policy or not policy.isOrdinaryTransfer or not policy.isOrdinaryTransfer(action)
        or action.srcContainer ~= action.character:getInventory() or not instanceof(action.item, "InventoryItem") then return context end
    local id, fullType = action.item:getID(), action.item:getFullType()
    local owner
    for token, task in pairs(session.tasks) do
        local pickup = task.pickups[id]
        if pickup and pickup.fullType == fullType and pickup.container == action.destContainer then
            if owner then return context end
            owner = token
        end
    end
    if not owner then return context end
    for token, task in pairs(session.tasks) do
        if token ~= owner and (task.unknownInputs or task.items[id]) then return context end
    end
    return {id = context.id, token = owner, character = context.character, queue = context.queue,
        generation = context.generation}
end

local scoped, rememberTidy
local function adopt(action)
    local context = sourceScope
    if not context then return end
    local class = getmetatable(action)
    local baseline = classes[context.id] and classes[context.id][class]
    if not baseline or not sourceClassUnchanged(context.id, class, baseline) or action.onStartFunc or action.onCancelFunc
        or action.retriggerLastAction or action.onFailFunc or action.additionalTest then return end
    local tidyHandUnequip = context.id == "P4TidyUpMeister" and class == ISUnequipAction and not action.fromHotbar
            and (action.item == action.character:getPrimaryHandItem() or action.item == action.character:getSecondaryHandItem())
            and not action.character:getWornItems():contains(action.item) and not isForceDropHeavyItem(action.item)
    if context.id == "P4TidyUpMeister" and class == ISUnequipAction and not classUnchanged(class, baseline)
        and (not tidyHandUnequip or not tidyClassUnchanged(action, class, baseline)) then return end
    context = tidyRestoreContext(context, action)
    if context.id == "P4TidyUpMeister" and not live(context) then return false end
    Operations.adopt(action, context.token)
    if records[action] then return end
    local queue = ISTimedActionQueue.getTimedActionQueue(action.character)
    local record = {class = class, baseline = baseline, character = action.character,
        token = action.toolkitQueueOperation, queue = queue, generation = queue.toolkitOperationGeneration or 0, worldGeneration = worldGeneration,
        id = context.id, target = context.target, fields = {}, itemIdentities = {}, owner = context.owner,
        primary = action.primary, twoHands = action.twoHands, alwaysTurnOn = action.alwaysTurnOn,
        reason = action.reason, fromHotbar = action.fromHotbar, hotbar = action.hotbar,
        tidyHandUnequip = tidyHandUnequip,
        opaque = context.opaque or (context.sharedCleanup and class == P4RestoreFloorAction), sharedCleanup = context.sharedCleanup}
    records[action] = record
    if context.id == "Project_Cook" and class == ISAddItemInRecipe then context.lastApply = action end
    if class == ISQueueActionsAction then
        record.cleanupFor, context.lastApply = context.lastApply, nil
        local callback = action.addActionsFunction
        record.commandArgs = {}
        for i, value in ipairs(action.args) do record.commandArgs[i] = value end
        action.start = function(self)
            if record.expanded then return end
            record.expanded = true
            if live(record) and matches(self) then
                self:beginAddingActions()
                scoped(record, callback, self.character, unpack(self.args))
                self:endAddingActions()
            end
            -- The source may have lost its target; native's empty-command path clears unrelated work.
            self:forceComplete()
        end
        action.waitToStart = function(self)
            if not self.toolkitCompletionWaited then self.toolkitCompletionWaited = true; return true end
            return false
        end
    end
    for _, name in ipairs({"item", "sink", "srcContainer", "destContainer", "slotType", "activated", "x", "y", "z",
        "offX", "offY", "offZ", "rotationX", "rotationY", "rotationZ",
        "addActionsFunction", "args", "toolkitQueueCommand", "wmiTransferAction", "wmiReturnContainer", "wmiOriginalContainer",
        "baseItem", "usedItem", "recipe", "soaps"}) do
        if action[name] ~= nil then
            record.fields[name] = action[name]
            if instanceof(action[name], "InventoryItem") then
                -- Native transferItem can rebind a Java item proxy; its inventory identity must stay the same.
                record.itemIdentities[name] = {id = action[name]:getID(), fullType = action[name]:getFullType()}
            end
        end
    end
    if action.onCompleteFunc then
        local callback, args = action.onCompleteFunc, action.onCompleteArgs
        if type(args) ~= "table" or args[1] ~= action then records[action] = nil; return end
        record.args = {}
        for i = 1, 8 do record.args[i] = args[i] end
        action.onCompleteFunc = function(...)
            if record.continued or not matches(action, record) or not live(record) then return end
            record.continued = true
            local handle = Operations.attachContinuation(record.token, record.character)
            return Operations.runContinuation(handle, function(...)
                return scoped(record, callback, ...)
            end, ...)
        end
    end
    local perform = action.perform
    action.perform = function(self, ...)
        if matches(self, record) then
            return Operations.perform(self, function(...) return scoped(record, perform, ...) end, ...)
        end
        return perform(self, ...)
    end
    action.toolkitQueueSafeOnComplete = action.onCompleteFunc
    record.methods = snapshot(action)
    for name in pairs(baseline) do if record.methods[name] == nil then record.methods[name] = action[name] end end
    for _, name in ipairs({"onStartFunc", "onCancelFunc", "onCompleteFunc", "onCompleteTarget", "onCompleteArgs"}) do
        record[name] = action[name]
    end
end

scoped = function(context, callback, ...)
    if not context.token and (not ownerUnchanged(context.id) or not Toolkit.Settings.actionQueue()) then
        return callback(...)
    end
    local previous = sourceScope
    sourceScope = context
    local insert, add, addAfter, queueActions = table.insert, ISTimedActionQueue.add,
        ISTimedActionQueue.addAfter, ISTimedActionQueue.queueActions
    local addOption = ISContextMenu and ISContextMenu.addOption
    local walkAdjacent = luautils and luautils.walkAdj
    local previousWalkWrapper = context.walkAdjacentWrapper
    local function valid() return ownerUnchanged(context.id) and (not context.token or live(context)) end
    ISTimedActionQueue.add = function(action)
        if context.id == "P4TidyUpMeister" and sessions[action.character] then sessions[action.character].restored = true end
        if not valid() then return end
        if adopt(action) == false then return end
        return add(action)
    end
    ISTimedActionQueue.addAfter = function(previousAction, action)
        if not valid() then return end
        if previousAction then action.toolkitQueueOperation = previousAction.toolkitQueueOperation end
        if adopt(action) == false then return end
        return addAfter(previousAction, action)
    end
    table.insert = function(target, ...)
        local args = pack(...)
        local action = args[args.n]
        local queue = type(action) == "table" and action.character and ISTimedActionQueue.queues[action.character]
        if queue and target == queue.queue then
            if not valid() then return end
            if adopt(action) == false then return end
            local results = pack(insert(target, unpack(args, 1, args.n)))
            if rememberTidy then rememberTidy(action) end
            return unpack(results, 1, results.n)
        end
        return insert(target, unpack(args, 1, args.n))
    end
    ISTimedActionQueue.queueActions = function(character, callback, ...)
        if not valid() then return end
        return queueActions(character, callback, ...)
    end
    if addOption and context.id == "WashFix" then
        ISContextMenu.addOption = function(menu, label, target, callback, ...)
            if callback then
                local original, sink = callback, select(1, ...)
                callback = function(...)
                    return Operations.run(function(...)
                        local context = {id = "WashFix", target = instanceof(sink, "IsoObject") and sink or nil}
                        return scoped(context, original, ...)
                    end, ...)
                end
            end
            return addOption(menu, label, target, callback, ...)
        end
    end
    if walkAdjacent and context.id == "WashFix" then
        -- Native walkAdj clears existing work before even checking whether the sink is already adjacent.
        context.walkAdjacentWrapper = function(character, square, keepActions, excluded)
            return walkAdjacent(character, square, true, excluded)
        end
        luautils.walkAdj = context.walkAdjacentWrapper
    end
    local results = pack(pcall(callback, ...))
    table.insert, ISTimedActionQueue.add, ISTimedActionQueue.addAfter, ISTimedActionQueue.queueActions = insert, add, addAfter, queueActions
    if addOption then ISContextMenu.addOption = addOption end
    if walkAdjacent then luautils.walkAdj = walkAdjacent end
    context.walkAdjacentWrapper = previousWalkWrapper
    sourceScope = previous
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2, results.n)
end

local function inspect(action)
    local record = records[action]
    local result = {items = {}, itemTypes = {}, targets = {}, callbacksSafe = true,
        cancelWaiting = true, interrupt = "audited-stop", preparationFinish = true}
    for _, field in ipairs({"item", "primary", "secondary", "baseItem", "usedItem"}) do
        local item = action[field]
        if instanceof(item, "InventoryItem") then result.items[item:getID()] = true; result.itemTypes[item:getFullType()] = true end
    end
    for _, batch in ipairs(action.queueList or {}) do
        for _, item in ipairs(batch.items or {}) do
            if not instanceof(item, "InventoryItem") then return end
            result.items[item:getID()] = true; result.itemTypes[item:getFullType()] = true
        end
    end
    if action.sink then result.targets[action.sink] = true end
    if record.class == ISWashClothing and action.soaps then
        if not instanceof(action.soaps, "List") then return end
        result.dynamicInputs = {}
        for i = 0, action.soaps:size() - 1 do
            local item = action.soaps:get(i)
            if not instanceof(item, "InventoryItem") then return end
            result.items[item:getID()] = true; result.itemTypes[item:getFullType()] = true
            result.dynamicInputs[item:getFullType()] = true
        end
        -- MP chooses soap again on the server, including newly reachable fluid containers.
        -- Native's generic-item branch uses soap even when noSoap is true.
        if not action.noSoap or (not instanceof(action.item, "Clothing") and not instanceof(action.item, "InventoryContainer")
            and not action.item:getItemAfterCleaning()) then result.knownInputs = false end
    end
    for _, container in pairs({action.srcContainer, action.destContainer, action.wmiReturnContainer}) do
        Toolkit.ActionQueuePolicy.addContainerResources(result, container)
    end
    if record.target then result.targets[record.target] = true end
    if record.id ~= "WashFix" then result.hands = action.character end
    if record.class == ISQueueActionsAction then result.deferred, result.knownInputs = true, false end
    if record.class == ISWashClothing or record.class == ISAddItemInRecipe then result.unknownOutputs = true end
    -- The following source command repairs invalid consumed spice on the authoritative side.
    if record.class == ISAddItemInRecipe or record.cleanupFor or record.sharedCleanup then result.cancelOperation = false end
    if record.class == P4RestoreFloorAction then
        -- Floor placement is a server completion effect, never an interrupted client-side restore.
        result.interrupt, result.preparationFinish = "finish-step", true
        local target = getCell and getCell():getGridSquare(action.x, action.y, action.z)
        if not target then return end
        result.targets[target] = true
    end
    return result
end

local function repairTidyFloor(character, callback, ...)
    if not character or not character:isLocalPlayer() or not isClient() or not tidyActionUnchanged
        or not tidyFloorValid or P4RestoreFloorAction.isValid ~= tidyFloorValid
        or ISInventoryPage ~= tidyFloorPage or not tidyFloorGetter
        or tidyFloorPage.GetFloorContainer ~= tidyFloorGetter then return callback(...) end
    local queue = ISTimedActionQueue.getTimedActionQueue(character)
    local add, buffered = ISTimedActionQueue.add, {}
    ISTimedActionQueue.add = function(action) buffered[#buffered + 1] = action; return queue end
    local results = pack(pcall(callback, ...))
    ISTimedActionQueue.add = add
    if not results[1] then
        for _, action in ipairs(buffered) do add(action) end
        error(results[2], 0)
    end
    if #buffered == 0 then return unpack(results, 2, results.n) end
    if not tidyActionUnchanged() then
        for _, action in ipairs(buffered) do add(action) end
        return unpack(results, 2, results.n)
    end
    local inventory = character:getInventory()
    local floor = tidyFloorGetter(character:getPlayerNum())
    local planned, transfers = {}, {}
    local function validTransfer(action, item)
        return action and action.character == character and getmetatable(action) == ISInventoryTransferAction
            and instanceof(action.item, "InventoryItem") and action.item:getID() == item:getID()
            and action.item:getFullType() == item:getFullType() and action.item:getContainer() == inventory
            and action.srcContainer == inventory and action.destContainer == floor
            and tidyActionUnchanged(action)
    end
    for _, action in ipairs(buffered) do
        if action.character == character and getmetatable(action) == P4RestoreFloorAction and tidyActionUnchanged(action) then
            local old = action.item
            local item = instanceof(old, "InventoryItem") and inventory:getItemById(old:getID())
            if item and old ~= item and item:getID() == old:getID() and item:getFullType() == old:getFullType()
                and old:getContainer() == floor and item:getContainer() == inventory then
                local here = character:getCurrentSquare()
                local target = getCell():getGridSquare(action.x, action.y, action.z)
                if here and target and here:getZ() == action.z and math.abs(here:getX() - action.x) <= 2
                    and math.abs(here:getY() - action.y) <= 2 then
                    local transfer = transfers[item:getID()]
                    if not transfer then
                        transfer = ISInventoryTransferAction:new(character, item, inventory, floor)
                        if validTransfer(transfer, item) then planned[#planned + 1] = transfer else transfer = nil end
                    end
                    if validTransfer(transfer, item) then
                        transfers[item:getID()], action.item = transfer, item
                        local repair = {character = character, queue = queue, generation = queue.toolkitOperationGeneration or 0,
                            worldGeneration = worldGeneration, id = item:getID(), fullType = item:getFullType(),
                            lootGetter = getPlayerLoot, fields = {}}
                        for _, name in ipairs({"x", "y", "z", "offX", "offY", "offZ", "rotationX", "rotationY", "rotationZ", "debugOutput"}) do
                            repair.fields[name] = action[name]
                        end
                        repairedFloors[action] = repair
                    end
                end
            end
        elseif action.character == character and getmetatable(action) == ISInventoryTransferAction
            and instanceof(action.item, "InventoryItem") and action.srcContainer == inventory and action.destContainer == floor then
            transfers[action.item:getID()] = action
        end
        planned[#planned + 1] = action
    end
    for _, action in ipairs(planned) do add(action) end
    return unpack(results, 2, results.n)
end

local function installTidyFloorValidation()
    local page, class = ISInventoryPage, P4RestoreFloorAction
    local getter = page and page.GetFloorContainer
    if not Proof.closure(getter, "ISInventoryPage.lua") then return end
    local valid = class.isValid
    class.isValid = function(action, ...)
        local repair = repairedFloors[action]
        if not repair then return valid(action, ...) end
        local character, queue = repair.character, repair.queue
        if not isClient() or not character:isLocalPlayer() or character:isDead()
            or repair.worldGeneration ~= worldGeneration or action.character ~= character
            or ISTimedActionQueue.queues[character] ~= queue or queue.current ~= action or queue:indexOf(action) == -1
            or (queue.toolkitOperationGeneration or 0) ~= repair.generation
            or ISInventoryPage ~= page or page.GetFloorContainer ~= getter
            or getPlayerLoot ~= repair.lootGetter or not tidyActionUnchanged or not tidyActionUnchanged(action, true)
            or not instanceof(action.item, "InventoryItem") or action.item:getID() ~= repair.id
            or action.item:getFullType() ~= repair.fullType then return false end
        local record = records[action]
        if record and record.token.toolkitCancelled and not record.sharedCleanup then return false end
        for _, name in ipairs({"x", "y", "z", "offX", "offY", "offZ", "rotationX", "rotationY", "rotationZ", "debugOutput"}) do
            if action[name] ~= repair.fields[name] then return false end
        end
        if not valid(action, ...) then return false end
        local floor = getter(character:getPlayerNum())
        local function resolved()
            local item = floor:getItemById(repair.id)
            if not instanceof(item, "InventoryItem") or item:getFullType() ~= repair.fullType
                or item:getID() ~= repair.id or item:getContainer() ~= floor then return end
            local world = item:getWorldItem()
            local square, here = world and world:getSquare(), character:getCurrentSquare()
            if not square or not here or world:getItem() ~= item or square:getZ() ~= here:getZ()
                or math.abs(square:getX() - here:getX()) > 2 or math.abs(square:getY() - here:getY()) > 2 then return end
            return item
        end
        local item = resolved()
        if not item then
            local loot = repair.lootGetter(character:getPlayerNum())
            local refresh = page.refreshBackpacks
            if not loot or loot.player ~= character:getPlayerNum() or loot.onCharacter ~= false
                or type(refresh) ~= "function" or loot.refreshBackpacks ~= refresh then return false end
            -- The normal UI refresh associates the received world replica with the native floor cache.
            refresh(loot)
            item = resolved()
        end
        if not item then return false end
        action.item = item
        return true
    end
    tidyFloorValid = class.isValid
end

local function loadSource(id, module, eventName)
    local event = eventName and Events[eventName]
    local eventAdd, derive = event and event.Add, ISBaseTimedAction.derive
    local privateWait, sequenceWait
    ISBaseTimedAction.derive = function(class, name)
        local result = derive(class, name)
        if id == "WashFix" and name == "WMI_WaitForInvUpdate" then privateWait = result end
        if id == "Project_Cook" and name == "PJCK_SequenceWaitAction" then sequenceWait = result end
        return result
    end
    if event then
        event.Add = function(callback)
            if id == "P4TidyUpMeister" then
                local native = callback
                callback = function(character, ...) return repairTidyFloor(character, native, character, ...) end
            end
            eventAdd(function(...)
                if id == "P4TidyUpMeister" then
                    local character = select(1, ...)
                    local record = sessions[character]
                    if record then
                        if not Toolkit.Settings.actionQueue() then
                            sessions[character] = nil
                            return TidyIntent.update(character, callback, ...)
                        end
                        -- Shared native equipment and ambiguous returns outlive cancellation of any one task.
                        if record.mixed and not record.restoreToken then record.restoreToken = {} end
                        local context = {id = id, token = record.restoreToken or record.token, character = character, queue = record.queue,
                            generation = record.generation, tidySession = record, sharedCleanup = record.mixed}
                        local results = pack(scoped(context, function(...) return TidyIntent.update(character, callback, ...) end, ...))
                        if #record.queue.queue == 0 and not character:hasTimedActions() then
                            record.idleTicks = (record.idleTicks or 0) + 1
                        else record.idleTicks = 0 end
                        if record.restored or record.idleTicks >= 2 then sessions[character] = nil end
                        return unpack(results, 1, results.n)
                    end
                    return TidyIntent.update(character, callback, ...)
                end
                return scoped({id = id}, callback, ...)
            end)
        end
    end
    local results = pack(pcall(require, module))
    ISBaseTimedAction.derive = derive
    if event then event.Add = eventAdd end
    if not results[1] then return false end
    if privateWait then
        -- B42.21 Base has neither a setter nor dispatch for this mod's private retry callback.
        privateWait.setOnComplete = ISInventoryTransferAction.setOnComplete
        local perform = privateWait.perform
        privateWait.perform = function(action)
            if action.onCompleteFunc then action.onCompleteFunc(unpack(action.onCompleteArgs)) end
            perform(action)
        end
        classes[id][privateWait] = snapshot(privateWait)
    end
    if sequenceWait then classes[id][sequenceWait] = snapshot(sequenceWait) end
    return true
end

local names = {"ISInventoryTransferAction", "ISWalkToTimedAction", "ISWalkToTimedActionF", "ISPathFindAction",
    "ISWashClothing", "ISEquipWeaponAction", "ISUnequipAction", "ISWearClothing", "ISClothingExtraAction",
    "ISAttachItemHotbar", "ISDetachItemHotbar", "ISQueueActionsAction", "NEQ_AttachAction", "P4RestoreAction", "P4RestoreFloorAction", "ISAddItemInRecipe"}

local function transferMethods()
    local result = {}
    for _, name in ipairs({"isValid", "start", "perform", "stop"}) do result[name] = ISInventoryTransferAction[name] end
    return result
end

local function installContainerTransfers()
    if not getActivatedMods or not getActivatedMods():contains("EURY_CONTAINERS") then return end
    transferSourceSafe = false
    if not verified("EURY_CONTAINERS") then return end
    local ok, proximity = pcall(require, "BetterContainers/Proximity")
    if not ok or type(proximity) ~= "table" then return end
    local loaded, helpers = pcall(require, "BetterContainers/Helpers")
    if not loaded or type(helpers) ~= "table" or helpers ~= EURY_CONTAINERS
        or type(helpers.isStaleVehicleContainer) ~= "function" then return end
    local staleVehicle = helpers.isStaleVehicleContainer
    local proximityMethods = {invName = proximity.invName, invName_corpses = proximity.invName_corpses}
    for _, name in ipairs({"isLockedForPlayer", "setTransferRunning", "hasQueuedTransferAction", "isProximityType"}) do
        if type(proximity[name]) ~= "function" then return end
        proximityMethods[name] = proximity[name]
    end
    containerHelpersUnchanged = function()
        if EURY_CONTAINERS ~= helpers or helpers.isStaleVehicleContainer ~= staleVehicle then return false end
        for name, expected in pairs(proximityMethods) do if proximity[name] ~= expected then return false end end
        return true
    end
    local policy = Toolkit.ActionQueuePolicy
    if not policy or not policy.adoptTransferMethods then return end
    for _, module in ipairs({"BetterContainers/Proximity/Proximity_ISInventoryTransferAction", "BetterContainers/Nested"}) do
        local loaded, patch = pcall(require, module)
        if not loaded or type(patch) ~= "table" or patch._installed ~= false or type(patch.install) ~= "function" then return end
        local previous = transferMethods()
        if not pcall(patch.install) then return end
        local replacement = transferMethods()
        if not policy.adoptTransferMethods(previous, replacement, containerHelpersUnchanged) then return end
        if Operations.adoptReturnMethods then Operations.adoptReturnMethods(previous, replacement, containerHelpersUnchanged) end
    end
    containerTransferPerform = ISInventoryTransferAction.perform
    transferSourceSafe, ready.EURY_CONTAINERS = true, true
end

local function installCartEating()
    if not getActivatedMods or not getActivatedMods():contains("SaucedCarts") or not verified("SaucedCarts")
        or not ISEatFoodAction or not ISDrinkFluidAction
        or ISEatFoodAction._saucedCartsConsumeWrapped or ISDrinkFluidAction._saucedCartsConsumeWrapped then return end
    if SaucedCarts and SaucedCarts.ConsumeWithCart then return end
    local previous = {[ISEatFoodAction] = ISEatFoodAction.start, [ISDrinkFluidAction] = ISDrinkFluidAction.start}
    local ok, consume = pcall(require, "SaucedCarts/ConsumeWithCart")
    local owner = SaucedCarts
    if not ok or not owner or type(consume) ~= "table" or owner.ConsumeWithCart ~= consume
        or type(consume.install) ~= "function" or type(consume._wrapStart) ~= "function"
        or type(owner.safeIsCart) ~= "function" or type(owner.isCart) ~= "function" or type(owner.debug) ~= "function" then return end
    local install, wrapStart, safeIsCart, isCart, debug = consume.install, consume._wrapStart, owner.safeIsCart, owner.isCart, owner.debug
    local function helpersUnchanged()
        return SaucedCarts == owner and owner.ConsumeWithCart == consume
            and consume.install == install and consume._wrapStart == wrapStart
            and owner.safeIsCart == safeIsCart and owner.isCart == isCart and owner.debug == debug
    end
    if not pcall(install) then return end
    local policy = Toolkit.ActionQueuePolicy
    ready.SaucedCarts = policy and policy.adoptConsumeStarts
        and policy.adoptConsumeStarts(previous, helpersUnchanged) == true
end

local function installManifestTransfers()
    if isClient() then return end
    require "LootSorter_Core"
    require "LootSorter_Manifest"
    local owner, modData, getOrCreate = LootSorter, ModData, ModData and ModData.getOrCreate
    local hooks = owner.manifestTransferHooks
    if not hooks or type(getOrCreate) ~= "function" then return end
    local registry, parse = hooks.registry, hooks.parse
    local function unchanged()
        return LootSorter == owner and owner.getRegistry == registry and owner.parseCoordKey == parse
            and owner.manifestTransferHooks == hooks and owner._manifestXferHooked == true
            and ModData == modData and modData.getOrCreate == getOrCreate and owner._receivedRegistry == nil
            and type(owner._manifestDirty) == "table" and getmetatable(owner._manifestDirty) == nil
            and (not containerHelpersUnchanged or containerHelpersUnchanged())
    end
    if not Toolkit.ActionQueuePolicy.adoptTransferHooks(hooks.previous, hooks.replacement, unchanged)
        or not Operations.adoptReturnHooks(hooks.previous, hooks.replacement, unchanged) then return end
    manifestTransferPerform, manifestHelpersUnchanged = hooks.replacement.perform, unchanged
end

function Compat.install()
    if installAttempted then return end
    installAttempted = true
    installCartEating()
    installContainerTransfers()
    installManifestTransfers()
    if getActivatedMods and getActivatedMods():contains("SaucedCarts") and verified("SaucedCarts", sourceFiles.SaucedCartsTransfers) then
        ready.SaucedCartsTransfers = require("PZSurvivorToolkit/ActionQueueCarts").install()
    end
    -- Snapshot reviewed native modifiers even when an updated cooking UI disables its own adapter.
    if getActivatedMods and getActivatedMods():contains("Project_Cook") and verified("Project_Cook", projectCookActionSources) then
        pcall(require, "Project_Cook/PJCK_FrozenCooking")
        pcall(require, "Project_Cook/EvolvedRecipePanel/OverrideFoodRelatedAction")
    end
    for _, owner in ipairs({
        {"Neat_Crafting", "NC_CraftActionPanel", "Neat_Crafting/NC_CraftActionPanel"},
        {"Project_Cook", "PJCK_CraftActionPanel", "Project_Cook/HandCraftPanel/PJCK_CraftActionPanel"},
    }) do
        if not installed[owner[1]] and getActivatedMods and getActivatedMods():contains(owner[1]) then
            installed[owner[1]] = true
            if not _G[owner[2]] and verified(owner[1])
                and (owner[1] ~= "Project_Cook" or captureProjectCookConfig()) and pcall(require, owner[3]) then
                local class = _G[owner[2]]
                if class and owner[1] == "Project_Cook" then
                    local complete, methods = class.onHandcraftActionComplete
                    class.onHandcraftActionComplete = function(self, ...)
                        local quantity = self.craftTimes
                        local balance = Toolkit.Settings.actionQueue() and type(quantity) == "number" and quantity > 1
                            and classUnchanged(class, methods) and instanceUnchanged(self, class)
                        local result = complete(self, ...)
                        -- Project Cook starts every craft but only stops the last one in a batch.
                        if balance then self.logic:stopCraftAction() end
                        return result
                    end
                    methods = snapshot(class)
                end
                if class then craftOwners[owner[2]] = {class = class, methods = snapshot(class)}; ready[owner[1]] = true end
                if owner[1] == "Project_Cook" and not PJCK_EvoPanel then
                    ready.Project_Cook = false
                    classes.Project_Cook = {}
                    if pcall(require, "Project_Cook/EvolvedRecipePanel/OverrideFoodRelatedAction")
                        and loadSource("Project_Cook", "Project_Cook/EvolvedRecipePanel/PJCK_EvoPanel") then
                        ready.Project_Cook = true
                        for _, name in ipairs({"addIngredients", "returnBaseItemToOriginalContainer", "queueBaseItemReturn", "setBaseItem"}) do
                            local callback = PJCK_EvoPanel[name]
                            PJCK_EvoPanel[name] = function(self, ...)
                                if not instanceUnchanged(self, PJCK_EvoPanel) then return callback(self, ...) end
                                return Operations.run(function(...) return scoped({id = "Project_Cook", owner = self}, callback, self, ...) end, ...)
                            end
                        end
                    end
                end
            end
        end
    end
    for _, id in ipairs({"WashFix", "NeatUI_Equipment", "P4TidyUpMeister"}) do
        local active = getActivatedMods and getActivatedMods():contains(id)
        if not installed[id] and active and verified(id) then
            installed[id], classes[id] = true, {}
            local ok
            if id == "WashFix" and not WS then
                ok = pcall(require, "ISUI/WMI_Compat_TABAS") and pcall(require, "TimedActions/WMI_PatchWashClothing")
                    and loadSource(id, "ISUI/WMI_CleanBandagesContext", "OnFillWorldObjectContextMenu")
                    and loadSource(id, "ISUI/WMI_WashingSubmenus", "OnFillWorldObjectContextMenu")
                if ok then washWalkHelper = {owner = luautils, callback = luautils.walkAdj} end
                if ok and WS.WMI_BuildWashMenu then
                    local callback = WS.WMI_BuildWashMenu
                    WS.WMI_BuildWashMenu = function(...) return scoped({id = id}, callback, ...) end
                end
                if ok and WMI_Clean.queueAllDirtyItems then
                    local callback = WMI_Clean.queueAllDirtyItems
                    WMI_Clean.queueAllDirtyItems = function(character, sink, ...)
                        return Operations.run(function(...)
                            return scoped({id = id, target = sink}, callback, character, sink, ...)
                        end, ...)
                    end
                end
            elseif id == "NeatUI_Equipment" and not NEQ_Dresser then
                ok = loadSource(id, "NeatEquipment/NEQ_Dresser")
                if ok then
                    for _, name in ipairs({"wear", "stripAll", "restore"}) do
                        local callback = NEQ_Dresser[name]
                        if callback then NEQ_Dresser[name] = function(...) return Operations.run(function(...) return scoped({id = id}, callback, ...) end, ...) end end
                    end
                    for _, name in ipairs({"newAttach", "newDetach"}) do
                        local callback = NEQ_AttachAction[name]
                        NEQ_AttachAction[name] = function(...)
                            return Operations.run(function(...)
                                local action = scoped({id = id}, callback, ...)
                                scoped({id = id}, adopt, action)
                                return action
                            end, ...)
                        end
                    end
                end
            elseif id == "P4TidyUpMeister" then
                local previous = ISInventoryTransferAction.getNotFullFloorSquare
                local transferItem = ISTransferAction and ISTransferAction.transferItem
                local dropItemOffset = ISTransferAction and ISTransferAction.GetDropItemOffset
                ok = loadSource(id, "P4TidyUpMeister", "OnPlayerUpdate")
                local policy = Toolkit.ActionQueuePolicy
                if ok and policy and policy.adoptTransferFloorHelper then
                    policy.adoptTransferFloorHelper(previous, ISInventoryTransferAction.getNotFullFloorSquare)
                end
                if ok and policy and policy.adoptTransferItemHelper and type(P4TidyUpMeister) == "table" then
                    local owner = P4TidyUpMeister
                    local registerAction, registerWorn = owner.registerActionPolicy, owner.registerWornItemReplacement
                    local replacementTransfer, replacementOffset = ISTransferAction.transferItem, ISTransferAction.GetDropItemOffset
                    -- The pinned source captures both delegates in its private local table.
                    policy.adoptTransferItemHelper(transferItem, replacementTransfer, function()
                        return P4TidyUpMeister == owner and type(registerAction) == "function" and type(registerWorn) == "function"
                            and owner.registerActionPolicy == registerAction and owner.registerWornItemReplacement == registerWorn
                            and ISTransferAction.transferItem == replacementTransfer
                            and ISTransferAction.GetDropItemOffset == replacementOffset
                    end, dropItemOffset, replacementOffset)
                end
            end
            ready[id] = ok == true
            if not ok then classes[id] = {} end
        end
    end
    if ready.P4TidyUpMeister and transferSourceSafe then
        local previous=ISInventoryTransferAction.checkQueueList
        TidyIntent.observeTransfers()
        local policy=Toolkit.ActionQueuePolicy
        if policy and policy.adoptTransferQueueObserver then policy.adoptTransferQueueObserver(previous,ISInventoryTransferAction.checkQueueList) end
    end
    if ready.P4TidyUpMeister then installTidyFloorValidation() end
    for id, sourceClasses in pairs(classes) do
        if ready[id] then
            for _, name in ipairs(names) do
                local class = _G[name]
                if class and (class ~= ISInventoryTransferAction or transferSourceSafe) then sourceClasses[class] = snapshot(class) end
            end
        end
        owners[id] = {}
        for _, target in ipairs(id == "WashFix" and {WS, WMI_Clean} or id == "NeatUI_Equipment" and {NEQ_Dresser, NEQ_AttachAction}
            or id == "Project_Cook" and {PJCK_EvoPanel, PJCK_FrozenCooking, PJCK_EvolvedSpiceGuard} or {}) do
            if target then owners[id][#owners[id] + 1] = {target = target, methods = snapshot(target)} end
        end
    end
    if ready.P4TidyUpMeister then
        local owner=P4TidyUpMeister
        local actionPolicy,wornPolicy=owner.registerActionPolicy,owner.registerWornItemReplacement
        local carts=ready.SaucedCartsTransfers and Toolkit.ActionQueueCarts
        local transfer=carts and carts.isTransferConstructor
        local unequip=carts and carts.isUnequipConstructor
        local nonCart=carts and carts.isNonCartUnequip
        tidyClassUnchanged = function(target,class,methods)
            if classUnchanged(target,methods) then return true end
            if not carts or Toolkit.ActionQueueCarts~=carts or carts.isTransferConstructor~=transfer
                or carts.isUnequipConstructor~=unequip or carts.isNonCartUnequip~=nonCart then return false end
            local allowed
            if class==ISInventoryTransferAction and transfer(methods.new) and transfer(class.new) then
                allowed={new=true,perform=true,transferItem=true}
            elseif class==ISUnequipAction and unequip(methods.new) and unequip(class.new) then
                if target~=class and not nonCart(target) then return false end
                allowed={new=true,complete=true}
            else return false end
            for name in pairs(allowed) do if target[name]~=class[name] then return false end end
            -- Reuse the existing source-pinned late Cart hooks without accepting other method changes.
            for name,method in pairs(methods) do if not allowed[name] and target[name]~=method then return false end end
            for _,name in ipairs(lifecycle) do if not allowed[name] and target[name]~=methods[name] then return false end end
            return true
        end
        local stickSource=getActivatedMods and getActivatedMods():contains('organizedCategories_core')
            and verified('organizedCategories_core',{{'client/organizedCategories_itemStick.lua',2877670095}})
        local floorPage = ISInventoryPage
        local floorGetter = floorPage and floorPage.GetFloorContainer
        if Proof.closure(floorGetter, "ISInventoryPage.lua") then tidyFloorPage, tidyFloorGetter = floorPage, floorGetter end
        tidyActionUnchanged = function(action, sourceOnly)
            if P4TidyUpMeister~=owner or owner.registerActionPolicy~=actionPolicy or owner.registerWornItemReplacement~=wornPolicy then return false end
            for class,methods in pairs(classes.P4TidyUpMeister) do if not tidyClassUnchanged(class,class,methods) then return false end end
            if not action then return true end
            local baseline=classes.P4TidyUpMeister[getmetatable(action)]
            if not baseline then return false end
            local record=records[action]
            if not record and (action.onStartFunc or action.onCompleteFunc or action.onCancelFunc
                or action.retriggerLastAction or action.onFailFunc or action.additionalTest) then return false end
            return record and (sourceOnly and sourceMatches(action,record) or not sourceOnly and matches(action,record))
                or not record and tidyClassUnchanged(action,getmetatable(action),baseline)
        end
        TidyIntent.install(tidyActionUnchanged,function(menu,name)
            return stickSource and menu==ISInventoryPaneContextMenu and menu['_ocStick_'..name]==menu[name]
                and Proof.closure(menu[name],'organizedCategories_itemStick.lua')
        end)
    end
end

-- Early compatibility entrypoints can precede ActionQueue's shared native stop wrapper.
function Compat.adoptStop(previous,replacement)
    if ISBaseTimedAction.stop~=replacement then return false end
    for _,registry in pairs(classes) do
        for _,methods in pairs(registry) do if methods.stop==previous then methods.stop=replacement end end
    end
    return true
end

-- Server Lua is not resolvable during the client load pass; the early SP server bridge calls this.
function Compat.installReadFix()
    if readFixAttempted then return end
    readFixAttempted = true
    if getActivatedMods and getActivatedMods():contains("MPFastForward") and verified("MPFastForward") then
        local previous = ISReadABook and ISReadABook.animEvent
        if previous and pcall(require, "MPFastForward_ReadFix") and ISReadABook.animEvent ~= previous then
            local policy = Toolkit.ActionQueuePolicy
            ready.MPFastForward = policy and policy.adoptReadAnimEvent and policy.adoptReadAnimEvent(previous, ISReadABook.animEvent) == true
        end
    end
end

function Compat.isInstalled(id) return ready[id] == true end

function Compat.isCartMaskSource()
    return verified("SaucedCarts", {{"shared/SaucedCarts/ContainerRestrictions.lua", 2765771727},
        {"shared/SaucedCarts/Core.lua", 2570266575}})
end

function Compat.isCartCapacitySource()
    return verified("SaucedCarts", {{"shared/SaucedCarts/CapacityOverride.lua", 1655578365},
        {"shared/SaucedCarts/CartData.lua", 3388888445}, {"shared/SaucedCarts/Core.lua", 2570266575}})
end

function Compat.isTransferPerform(callback)
    return type(callback) == "function" and ((ready.EURY_CONTAINERS == true and callback == containerTransferPerform
        and containerHelpersUnchanged()) or (callback == manifestTransferPerform and manifestHelpersUnchanged()))
end

function Compat.isCraftOwner(name, target, action)
    local owner = craftOwners[name]
    if not owner or not target then return false end
    for method, callback in pairs(owner.methods) do if target[method] ~= callback then return false end end
    for method, callback in pairs(target) do
        if type(callback) == "function" and callback ~= owner.methods[method]
            and callback ~= nativeXuiMethods[method] then return false end
    end
    return owner and getmetatable(target) == owner.class and classUnchanged(owner.class, owner.methods)
        and action.onStartFunc == owner.methods.onHandcraftActionStart
        and action.onCompleteFunc == owner.methods.onHandcraftActionComplete
        and action.onCancelFunc == owner.methods.onHandcraftActionCancelled
        and target.onHandcraftActionStart == owner.methods.onHandcraftActionStart
        and target.onHandcraftActionComplete == owner.methods.onHandcraftActionComplete
        and target.onHandcraftActionCancelled == owner.methods.onHandcraftActionCancelled
end

rememberTidy = function(action)
    if installed.P4TidyUpMeister and action.character and action.toolkitQueueOperation then
        local character, token = action.character, action.toolkitQueueOperation
        if not Toolkit.Settings.actionQueue() then
            -- A new native operation while disabled has no single owner with an older tracked Tidy session.
            if sessions[character] and sessions[character].token ~= token then sessions[character] = nil end
            return
        end
        if sourceScope and sourceScope.id == "P4TidyUpMeister" then
            if sessions[character] then sessions[character].restored = true end
        else
            local record = sessions[character]
            if not record then
                local queue = ISTimedActionQueue.getTimedActionQueue(character)
                record = {token = token, queue = queue, generation = queue.toolkitOperationGeneration or 0,
                    tasks = {}, seen = {}}
                sessions[character] = record
            elseif record.token ~= token then record.mixed = true end
            if record.seen[action] then return end
            record.seen[action] = true
            local task = record.tasks[token]
            if not task then task = {items = {}, pickups = {}}; record.tasks[token] = task end
            local contract = Toolkit.ActionQueueDefinitions.inspect(action)
            if not contract or contract.knownInputs == false or contract.dynamicInputs then task.unknownInputs = true end
            for id in pairs(contract and contract.items or {}) do task.items[id] = true end
            for id in pairs(contract and contract.containerOwners or {}) do task.items[id] = true end
            for item, container in pairs(token.toolkitPickups or {}) do
                task.pickups[item:getID()] = {container = container, fullType = item:getFullType()}
            end
        end
    end
end

local add = ISTimedActionQueue.add
ISTimedActionQueue.add = function(action)
    local results = pack(add(action))
    if results[1] then rememberTidy(action) end
    return unpack(results, 1, results.n)
end
local addAfter = ISTimedActionQueue.addAfter
ISTimedActionQueue.addAfter = function(previous, action)
    local results = pack(addAfter(previous, action))
    if results[2] then rememberTidy(results[2]) end
    return unpack(results, 1, results.n)
end
local addToQueue = ISTimedActionQueue.addToQueue
ISTimedActionQueue.addToQueue = function(queue, action)
    local results = pack(addToQueue(queue, action))
    if queue:indexOf(action) ~= -1 then rememberTidy(action) end
    return unpack(results, 1, results.n)
end

local behaviorTypes = {"WMI_WaitForInvUpdate", "PJCK_SequenceWaitAction"}
for _, name in ipairs(names) do behaviorTypes[#behaviorTypes + 1] = name end
local function tidyTransfer(action)
    local record = records[action]
    return record and record.id == "P4TidyUpMeister" and record.class == ISInventoryTransferAction
end
local function matchesTidyTransfer(action) return tidyTransfer(action) and matches(action) end
local function tidyEquipment(action)
    local record = records[action]
    return record and record.id == "P4TidyUpMeister"
        and (record.class == ISEquipWeaponAction or record.class == P4RestoreAction or record.tidyHandUnequip)
end
local function matchesTidyEquipment(action) return tidyEquipment(action) and matches(action) end
local function matchesSelectedChain(action) return not tidyTransfer(action) and not tidyEquipment(action) and matches(action) end
local function acceptsChild(parent, child)
    return matches(child) and child.toolkitQueueOperation == parent.toolkitQueueOperation
end
Toolkit.ActionQueueDefinitions.registerBehavior("compat.selected-chains",
    {types = behaviorTypes, matches = matchesSelectedChain, inspect = inspect})
Operations.registerProducer("compat.selected-chains", matchesSelectedChain, acceptsChild)
Toolkit.ActionQueueDefinitions.registerBehavior("compat.tidy-transfers",
    {types = {"ISInventoryTransferAction"}, matches = matchesTidyTransfer, inspect = inspect})
Operations.registerProducer("compat.tidy-transfers", matchesTidyTransfer, acceptsChild, true)
Toolkit.ActionQueueDefinitions.registerBehavior("compat.tidy-equipment",
    {types = {"ISEquipWeaponAction", "P4RestoreAction", "ISUnequipAction"}, matches = matchesTidyEquipment, inspect = inspect})
Operations.registerProducer("compat.tidy-equipment", matchesTidyEquipment, acceptsChild, true)
require "LootSorter_CraftMenu"
Compat.install()
return Compat
