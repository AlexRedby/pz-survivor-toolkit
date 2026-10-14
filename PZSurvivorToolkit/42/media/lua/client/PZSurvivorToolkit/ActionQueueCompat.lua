require "PZSurvivorToolkit/ActionQueueOperations"
require "PZSurvivorToolkit/ActionQueueDefinitions"

local Toolkit = PZSurvivorToolkit
local Operations = Toolkit.ActionQueueOperations
local Compat = {}
Toolkit.ActionQueueCompat = Compat
local records = setmetatable({}, {__mode = "k"})
local classes, installed, sessions = {}, {}, setmetatable({}, {__mode = "k"})
local owners = {}
local craftOwners = {}
local ready = {}
local sourceScope
local installAttempted
local readFixAttempted
local transferSourceSafe = true
local containerHelpersUnchanged
local washWalkHelper
local lifecycle = {"new", "isValid", "isValidStart", "waitToStart", "start", "update", "stop", "perform",
    "complete", "getDuration", "serverStart", "serverStop", "animEvent", "forceStop", "forceCancel"}
local sourceFiles = {
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
        {"client/Project_Cook/EvolvedRecipePanel/PJCK_EvoPanel.lua", 3224482149},
        {"client/Project_Cook/EvolvedRecipePanel/OverrideFoodRelatedAction.lua", 222676723},
        {"shared/Project_Cook/PJCK_FrozenCooking.lua", 3756381974},
        {"shared/Project_Cook/PJCK_EvolvedSpiceGuard.lua", 2430144672},
    },
    MPFastForward = {{"server/MPFastForward_ReadFix.lua", 598888215}},
    EURY_CONTAINERS = {
        {"client/BetterContainers/Proximity.lua", 3626949969},
        {"client/BetterContainers/Proximity/Proximity_ISInventoryTransferAction.lua", 909048245},
        {"client/BetterContainers/Nested.lua", 1899062461},
    },
}

local function pack(...) return {n = select("#", ...), ...} end

-- getModFileReader resolves the selected B42 version, then common; no Workshop path is assumed.
-- Kahlua strings use UTF16; development Lua uses UTF8. Hash the same normalized source in both.
local utf8Strings = string.byte("洗") == 230
local function sourceHash(reader)
    local a, b = 1, 0
    local function add(value) a = (a + value) % 65521; b = (b + a) % 65521 end
    local line = reader:readLine()
    while line do
        local i = 1
        while i <= #line do
            local value = string.byte(line, i)
            if utf8Strings and value >= 192 then
                local count = value < 224 and 2 or value < 240 and 3 or 4
                value = value % (2 ^ (7 - count))
                for offset = 1, count - 1 do value = value * 64 + string.byte(line, i + offset) % 64 end
                i = i + count - 1
                if value > 65535 then
                    value = value - 65536
                    add(55296 + math.floor(value / 1024)); value = 56320 + value % 1024
                end
            end
            add(value); i = i + 1
        end
        add(10); line = reader:readLine()
    end
    return b * 65536 + a
end

local function verified(id)
    if not getModFileReader then return false end
    for _, file in ipairs(sourceFiles[id]) do
        local ok, reader = pcall(getModFileReader, id, "media/lua/" .. file[1], false)
        if not ok or not reader then return false end
        local hashed, checksum = pcall(sourceHash, reader)
        local closed = pcall(function() reader:close() end)
        if not hashed or not closed or checksum ~= file[2] then return false end
    end
    return true
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

local function live(record)
    local character, queue, token = record.character, record.queue, record.token
    if not token or token.toolkitCancelled or not Toolkit.Settings.actionQueue()
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

local function ownerUnchanged(id)
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

local function matches(action)
    local record = records[action]
    if not record or record.opaque or getmetatable(action) ~= record.class or action.Type ~= record.class.Type
        or action.character ~= record.character or action.toolkitQueueOperation ~= record.token
        or not classUnchanged(record.class, record.baseline) or not ownerUnchanged(record.id)
        or (record.owner and not instanceUnchanged(record.owner, PJCK_EvoPanel))
        or (record.class == ISInventoryTransferAction and containerHelpersUnchanged and not containerHelpersUnchanged()) then return false end
    local policy = Toolkit.ActionQueuePolicy
    if record.class == ISInventoryTransferAction and policy and policy.isOrdinaryTransfer and not policy.isOrdinaryTransfer(action) then return false end
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
    if not baseline or not classUnchanged(class, baseline) or action.onStartFunc or action.onCancelFunc
        or action.retriggerLastAction or action.onFailFunc or action.additionalTest then return end
    context = tidyRestoreContext(context, action)
    if context.id == "P4TidyUpMeister" and not live(context) then return false end
    Operations.adopt(action, context.token)
    if records[action] then return end
    local queue = ISTimedActionQueue.getTimedActionQueue(action.character)
    local record = {class = class, baseline = baseline, character = action.character,
        token = action.toolkitQueueOperation, queue = queue, generation = queue.toolkitOperationGeneration or 0,
        id = context.id, target = context.target, fields = {}, itemIdentities = {}, owner = context.owner,
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
            if record.continued or not matches(action) or not live(record) then return end
            record.continued = true
            local handle = Operations.attachContinuation(record.token, record.character)
            return Operations.runContinuation(handle, function(...)
                return scoped(record, callback, ...)
            end, ...)
        end
    end
    local perform = action.perform
    action.perform = function(self, ...)
        if matches(self) then
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
            eventAdd(function(...)
                if id == "P4TidyUpMeister" then
                    local character = select(1, ...)
                    local record = sessions[character]
                    if record then
                        if not Toolkit.Settings.actionQueue() then
                            sessions[character] = nil
                            return callback(...)
                        end
                        -- Shared native equipment and ambiguous returns outlive cancellation of any one task.
                        if record.mixed and not record.restoreToken then record.restoreToken = {} end
                        local context = {id = id, token = record.restoreToken or record.token, character = character, queue = record.queue,
                            generation = record.generation, tidySession = record, sharedCleanup = record.mixed}
                        local results = pack(scoped(context, callback, ...))
                        if #record.queue.queue == 0 and not character:hasTimedActions() then
                            record.idleTicks = (record.idleTicks or 0) + 1
                        else record.idleTicks = 0 end
                        if record.restored or record.idleTicks >= 2 then sessions[character] = nil end
                        return unpack(results, 1, results.n)
                    end
                    return callback(...)
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
    local proximityMethods = {invName = proximity.invName, invName_corpses = proximity.invName_corpses}
    for _, name in ipairs({"isLockedForPlayer", "setTransferRunning", "hasQueuedTransferAction", "isProximityType"}) do
        if type(proximity[name]) ~= "function" then return end
        proximityMethods[name] = proximity[name]
    end
    containerHelpersUnchanged = function()
        for name, expected in pairs(proximityMethods) do if proximity[name] ~= expected then return false end end
        return true
    end
    local policy = Toolkit.ActionQueuePolicy
    if not policy or not policy.adoptTransferMethods then return end
    for _, module in ipairs({"BetterContainers/Proximity/Proximity_ISInventoryTransferAction", "BetterContainers/Nested"}) do
        local loaded, patch = pcall(require, module)
        if not loaded or type(patch) ~= "table" or patch._installed ~= false or type(patch.install) ~= "function" then return end
        local previous = transferMethods()
        if not pcall(patch.install) or not policy.adoptTransferMethods(previous, transferMethods(), containerHelpersUnchanged) then return end
    end
    transferSourceSafe, ready.EURY_CONTAINERS = true, true
end

function Compat.install()
    if installAttempted then return end
    installAttempted = true
    installContainerTransfers()
    for _, owner in ipairs({
        {"Neat_Crafting", "NC_CraftActionPanel", "Neat_Crafting/NC_CraftActionPanel"},
        {"Project_Cook", "PJCK_CraftActionPanel", "Project_Cook/HandCraftPanel/PJCK_CraftActionPanel"},
    }) do
        if not installed[owner[1]] and getActivatedMods and getActivatedMods():contains(owner[1]) then
            installed[owner[1]] = true
            if not _G[owner[2]] and verified(owner[1]) and pcall(require, owner[3]) then
                local class = _G[owner[2]]
                if class then craftOwners[owner[2]] = {class = class, methods = snapshot(class)}; ready[owner[1]] = true end
                if owner[1] == "Project_Cook" and not PJCK_EvoPanel then
                    ready.Project_Cook = false
                    classes.Project_Cook = {}
                    if pcall(require, "Project_Cook/EvolvedRecipePanel/OverrideFoodRelatedAction")
                        and loadSource("Project_Cook", "Project_Cook/EvolvedRecipePanel/PJCK_EvoPanel") then
                        ready.Project_Cook = true
                        for _, name in ipairs({"addIngredients", "returnBaseItemToOriginalContainer", "setBaseItem"}) do
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
                ok = loadSource(id, "P4TidyUpMeister", "OnPlayerUpdate")
                local policy = Toolkit.ActionQueuePolicy
                if ok and policy and policy.adoptTransferFloorHelper then
                    policy.adoptTransferFloorHelper(previous, ISInventoryTransferAction.getNotFullFloorSquare)
                end
            end
            ready[id] = ok == true
            if not ok then classes[id] = {} end
        end
    end
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

function Compat.isCraftOwner(name, target, action)
    local owner = craftOwners[name]
    if not owner or not target then return false end
    for method, callback in pairs(owner.methods) do if target[method] ~= callback then return false end end
    for method, callback in pairs(target) do
        if type(callback) == "function" and callback ~= owner.methods[method] then return false end
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
                    tasks = {}, seen = setmetatable({}, {__mode = "k"})}
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

Toolkit.ActionQueueDefinitions.registerBehavior("compat.selected-chains", {matches = matches, inspect = inspect})
Operations.registerProducer("compat.selected-chains", matches, function(parent, child)
    return matches(child) and child.toolkitQueueOperation == parent.toolkitQueueOperation
end)
Compat.install()
return Compat
