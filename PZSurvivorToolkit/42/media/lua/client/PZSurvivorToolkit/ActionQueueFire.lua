require "PZSurvivorToolkit/ActionQueueOperations"
require "PZSurvivorToolkit/ActionQueueDefinitions"
require "Camping/ISCampingMenu"
require "Camping/TimedActions/ISAddFuelAction"
require "Camping/TimedActions/ISLightFromLiterature"
require "Camping/TimedActions/ISLightFromPetrol"
require "Camping/TimedActions/ISLightFromKindle"
require "TimedActions/ISBBQAddFuel"
require "TimedActions/ISBBQLightFromLiterature"
require "TimedActions/ISBBQLightFromPetrol"
require "TimedActions/ISBBQLightFromKindle"
require "TimedActions/ISInventoryTransferUtil"
require "ISUI/ISCraftingUI"

local Toolkit = PZSurvivorToolkit
local Fire = {}
Toolkit.ActionQueueFire = Fire
local Operations, Definitions = Toolkit.ActionQueueOperations, Toolkit.ActionQueueDefinitions
local records = {}
local equipmentRecords = {}
local Carts = Toolkit.ActionQueueCarts
local cartConstructor = Carts and Carts.isTransferConstructor
local cartUnequip, cartItem, cartMatches = Carts and Carts.isUnequipConstructor, Carts and Carts.isNonCartItem, Carts and Carts.isNonCartUnequip
local function verifiedCartConstructor(callback)
    return Carts and Toolkit.ActionQueueCarts == Carts and Carts.isTransferConstructor == cartConstructor
        and type(cartConstructor) == "function" and cartConstructor(callback) == true
end
local snapshots = {}
local expanded = {}
local returns = {}

function Fire.prune()
    local pending = false
    for _, registry in ipairs({records, snapshots, expanded, returns, equipmentRecords}) do
        for _ in pairs(registry) do pending = true; break end
        if pending then break end
    end
    if not pending then return end
    local queued, active = {}, {}
    for character, queue in pairs(ISTimedActionQueue.queues) do
        if not character:isDead() then
            for _, action in ipairs(queue.queue or {}) do queued[action] = true end
        end
    end
    for action, record in pairs(records) do
        if queued[action] then active[record.saved] = true else records[action] = nil end
    end
    for _, registry in ipairs({returns, equipmentRecords}) do
        for action in pairs(registry) do if not queued[action] then registry[action] = nil end end
    end
    -- Retries use their parent's sealed request even after the command and parent have completed.
    for saved in pairs(snapshots) do
        if not active[saved] then snapshots[saved], expanded[saved] = nil, nil end
    end
end
Events.OnTick.Add(Fire.prune)
if Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(function()
    for _, registry in ipairs({records, snapshots, expanded, returns, equipmentRecords}) do
        for key in pairs(registry) do registry[key] = nil end
    end
end) end
local classes, callbacks, helpers, bindings = {}, {}, {}, {}
local lifecycle = {"new", "isValid", "isValidStart", "waitToStart", "start", "update", "stop", "perform", "complete",
    "getDuration", "serverStart", "serverStop", "animEvent", "forceStop", "forceCancel"}
local hashes = {ISAddFuelAction = 4284759792, ISLightFromLiterature = 3684576966, ISLightFromPetrol = 2461512401,
    ISLightFromKindle = 314037598, ISBBQAddFuel = 541222922, ISBBQLightFromLiterature = 1313125538,
    ISBBQLightFromPetrol = 1501433250, ISBBQLightFromKindle = 2588990961}
local utf8Strings = string.byte("洗") == 230
local function sourceMatches(path, expected, mod)
    local input = mod and getModFileReader or getGameFilesInput
    if type(input) ~= "function" then return false end
    local ok, reader
    if mod then ok, reader = pcall(input, mod, "media/lua/" .. path, false)
    else ok, reader = pcall(input, "media/lua/" .. path) end
    if not ok or not reader then return false end
    local valid, hash = pcall(function()
        local value, bytes = 5381, 0
        while true do
            local line = reader:readLine()
            if not line then break end
            bytes = bytes + #line + 1
            if bytes > 2000000 then return end
            local i = 1
            while i <= #line do
                local code = string.byte(line, i)
                if utf8Strings and code >= 192 then
                    local count = code < 224 and 2 or code < 240 and 3 or 4
                    code = code % (2 ^ (7 - count))
                    for offset = 1, count - 1 do code = code * 64 + string.byte(line, i + offset) % 64 end
                    i = i + count - 1
                    if code > 65535 then
                        code = code - 65536
                        value = (value * 33 + 55296 + math.floor(code / 1024)) % 4294967296
                        code = 56320 + code % 1024
                    end
                end
                value = (value * 33 + code) % 4294967296
                i = i + 1
            end
            value = (value * 33 + 10) % 4294967296
        end
        return value
    end)
    pcall(function() reader:close() end)
    -- shortcut: queue permissions require the reviewed B42.21 sources; re-audit newer native code.
    return valid and hash == expected
end
local function nativeClosure(callback, filename)
    if type(callback) ~= "function" or type(getFilenameOfClosure) ~= "function" then return false end
    local ok, source = pcall(getFilenameOfClosure, callback)
    return ok and type(source) == "string" and source:gsub("\\", "/"):match("([^/]+)$") == filename
end
local cleanUI = sourceMatches("client/ISUI/ISInventoryPaneContextMenu.lua", 1953753890)
local trusted = sourceMatches("shared/Camping/ISCampingMenu.lua", 125174138)
    and sourceMatches("client/Map/CGlobalObject.lua", 1926494845)
    and sourceMatches("client/Camping/CCampfireGlobalObject.lua", 1516961117)
    and (cleanUI or sourceMatches("client/ISUI/ISInventoryPaneContextMenu.lua", 4293448388))
    and sourceMatches("client/ISUI/ISCraftingUI.lua", 722324844)
    and sourceMatches("shared/luautils.lua", 1091751327)
    and sourceMatches("shared/TimedActions/ISInventoryTransferUtil.lua", 1281392797)
local names = {"ISAddFuelAction", "ISLightFromLiterature", "ISLightFromPetrol", "ISLightFromKindle",
    "ISBBQAddFuel", "ISBBQLightFromLiterature", "ISBBQLightFromPetrol", "ISBBQLightFromKindle"}
for _, name in ipairs(names) do
    local class = _G[name]
    local methods = {}
    for _, method in ipairs(lifecycle) do methods[method] = class[method] end
    for method, callback in pairs(class) do if type(callback) == "function" then methods[method] = callback end end
    local path = name:find("^ISBBQ") and "shared/TimedActions/" or "shared/Camping/TimedActions/"
    local valid = sourceMatches(path .. name .. ".lua", hashes[name])
    for method, callback in pairs(class) do
        if type(callback) == "function" and method ~= "derive" then valid = valid and nativeClosure(callback, name .. ".lua") end
    end
    classes[class] = {name = name, methods = methods, trusted = valid}
end
for _, name in ipairs({"getFuelDurationForItem", "getFuelDurationForItemInHours", "getFuelItemUses", "isValidFuel", "isValidTinder",
    "shouldBurn", "isPetrol", "toPlayerInventory", "walkToCampfire"}) do
    helpers[name] = ISCampingMenu[name]
    trusted = trusted and nativeClosure(helpers[name], "ISCampingMenu.lua")
end
local getContainers = ISInventoryPaneContextMenu.getContainers
local initialGetContainers = getContainers
local transferIfNeeded = ISInventoryPaneContextMenu.transferIfNeeded
local returnItem = ISCraftingUI.ReturnItemToContainer
local proximity, proximityGetter
local containerSourceSafe = nativeClosure(getContainers, "ISInventoryPaneContextMenu.lua")
if not containerSourceSafe and nativeClosure(getContainers, "CraftingFix.lua")
    and sourceMatches("client/ProximityInventory/CraftingFix.lua", 2752217643, "ProximityInventory")
    and sourceMatches("client/ProximityInventory/ProximityInventory.lua", 3363253772, "ProximityInventory") then
    local loaded, module = pcall(require, "ProximityInventory/ProximityInventory")
    if loaded and type(module) == "table" and nativeClosure(module.GetItemContainer, "ProximityInventory.lua") then
        proximity, proximityGetter, containerSourceSafe = module, module.GetItemContainer, true
    end
end
trusted = trusted and containerSourceSafe
    and nativeClosure(transferIfNeeded, "ISInventoryPaneContextMenu.lua") and nativeClosure(returnItem, "ISCraftingUI.lua")
local cleanUIHelpers = {}
if cleanUI then
    for _, name in ipairs({"cleanUIResetStaleTimedActionRetrigger", "cleanUILogTimedActionFix"}) do
        cleanUIHelpers[name] = ISInventoryPaneContextMenu[name]
        trusted = trusted and nativeClosure(cleanUIHelpers[name], "ISInventoryPaneContextMenu.lua")
    end
end
local transferConstructor = ISInventoryTransferAction.new
local transferCart = verifiedCartConstructor(transferConstructor)
trusted = trusted and (transferCart or nativeClosure(transferConstructor, "ISInventoryTransferAction.lua"))
local unequipClass = ISUnequipAction
local unequipMethods = {}
for name, callback in pairs(unequipClass or {}) do if type(callback) == "function" then unequipMethods[name] = callback end end
local transferWalk = luautils.walkToContainer
local transferPredicate = luautils.haveToBeTransfered
trusted = trusted and nativeClosure(transferPredicate, "luautils.lua") and nativeClosure(transferWalk, "luautils.lua")
local transferHelpers = {}
for name, callback in pairs(ISInventoryTransferUtil) do
    if type(callback) == "function" then
        trusted = trusted and nativeClosure(callback, "ISInventoryTransferUtil.lua")
        transferHelpers[name] = callback
    end
end
local campfireClass = CCampfireGlobalObject
local campfireMethods = {}
if campfireClass then
    for _, name in ipairs({"getSquare", "getObject", "getIsoObject", "updateFromIsoObject"}) do
        campfireMethods[name] = campfireClass[name]
        trusted = trusted and nativeClosure(campfireMethods[name], name == "getObject" and "CCampfireGlobalObject.lua" or "CGlobalObject.lua")
    end
end

local containerFilterUnchanged
-- Observe BC's native install instead of recapturing an arbitrary later container getter.
if getActivatedMods and getActivatedMods():contains("EURY_CONTAINERS")
    and sourceMatches("client/BetterContainers/Proximity.lua", 330528904, "EURY_CONTAINERS")
    and sourceMatches("client/BetterContainers/Proximity/Proximity_ISLootWindowContainerControls.lua", 1373322689, "EURY_CONTAINERS") then
    local loaded, controls = pcall(require, "BetterContainers/Proximity/Proximity_ISLootWindowContainerControls")
    local gotProximity, owner = pcall(require, "BetterContainers/Proximity")
    if loaded and gotProximity and type(controls) == "table" and type(owner) == "table"
        and controls._installed == false and nativeClosure(controls.install, "Proximity_ISLootWindowContainerControls.lua")
        and type(owner.itemContainer) == "table" and not getmetatable(owner.itemContainer)
        and type(owner.corpseContainer) == "table" and not getmetatable(owner.corpseContainer) then
        local nativeInstall, itemContainers, corpseContainers = controls.install, owner.itemContainer, owner.corpseContainer
        local install
        local function ownersUnchanged()
            return controls.install == install and owner.itemContainer == itemContainers and owner.corpseContainer == corpseContainers
                and not getmetatable(itemContainers) and not getmetatable(corpseContainers)
        end
        install = function(...)
            local predecessor = ISInventoryPaneContextMenu.getContainers
            local verified = controls._installed == false and predecessor == getContainers and ownersUnchanged()
            local result = nativeInstall(...)
            local replacement = ISInventoryPaneContextMenu.getContainers
            if verified and controls._installed == true and ownersUnchanged()
                and nativeClosure(replacement, "Proximity_ISLootWindowContainerControls.lua") then
                getContainers = replacement
                containerFilterUnchanged = function() return controls._installed == true and ownersUnchanged() end
            end
            return result
        end
        controls.install = install
    end
end

function Fire.matchesContainerGetter(callback)
    return containerSourceSafe and (callback == initialGetContainers or callback == getContainers)
        and ISInventoryPaneContextMenu.getContainers == getContainers
        and (not proximity or proximity.GetItemContainer == proximityGetter)
        and (not containerFilterUnchanged or containerFilterUnchanged())
end

local function unchanged(class)
    local record = classes[class]
    if not record or not record.trusted or _G[record.name] ~= class then return false end
    for _, name in ipairs(lifecycle) do if class[name] ~= record.methods[name] then return false end end
    for name, callback in pairs(record.methods) do if class[name] ~= callback then return false end end
    return true
end
local function helpersSafe()
    if not trusted or luautils.haveToBeTransfered ~= transferPredicate or luautils.walkToContainer ~= transferWalk then return false end
    if containerFilterUnchanged and not containerFilterUnchanged() then return false end
    if (transferCart or ISInventoryTransferAction.new ~= transferConstructor)
        and not (verifiedCartConstructor(transferConstructor) and verifiedCartConstructor(ISInventoryTransferAction.new)) then return false end
    for name, callback in pairs(cleanUIHelpers) do if ISInventoryPaneContextMenu[name] ~= callback then return false end end
    for name, callback in pairs(bindings) do if ISCampingMenu[name] ~= callback then return false end end
    if proximity and proximity.GetItemContainer ~= proximityGetter then return false end
    if CCampfireGlobalObject ~= campfireClass then return false end
    for name, callback in pairs(campfireMethods) do if campfireClass[name] ~= callback then return false end end
    for name, callback in pairs(transferHelpers) do if ISInventoryTransferUtil[name] ~= callback then return false end end
    for name, callback in pairs(helpers) do if ISCampingMenu[name] ~= callback then return false end end
    return ISInventoryPaneContextMenu.getContainers == getContainers
        and ISInventoryPaneContextMenu.transferIfNeeded == transferIfNeeded and ISCraftingUI.ReturnItemToContainer == returnItem
end
local function equipmentSafe(saved)
    if not saved.multiple then return true end
    if ISUnequipAction ~= unequipClass then return false end
    if Carts and cartUnequip then
        if Toolkit.ActionQueueCarts ~= Carts or Carts.isUnequipConstructor ~= cartUnequip
            or Carts.isNonCartItem ~= cartItem or Carts.isNonCartUnequip ~= cartMatches
            or not cartUnequip(ISUnequipAction.new) then return false end
        for _, entry in ipairs(saved.items) do if not cartItem(entry.item) then return false end end
        return true
    end
    for name, callback in pairs(unequipMethods) do
        if ISUnequipAction[name] ~= callback or name ~= "derive" and not nativeClosure(callback, "ISUnequipAction.lua") then return false end
    end
    return nativeClosure(unequipMethods.new, "ISUnequipAction.lua") and nativeClosure(unequipMethods.complete, "ISUnequipAction.lua")
end
local function worldObject(target, class)
    if not target then return end
    if class == ISAddFuelAction or class == ISLightFromLiterature or class == ISLightFromPetrol or class == ISLightFromKindle then
        if not campfireClass or getmetatable(target) ~= campfireClass then return nil, "unsupported" end
        for name, method in pairs(campfireMethods) do if target[name] ~= method then return nil, "unsupported" end end
        return target:getIsoObject()
    end
    if instanceof(target, "IsoBarbecue") or instanceof(target, "IsoFireplace") then return target end
    return nil, "unsupported"
end
local function available(character, entry)
    local containers = getContainers(character)
    for i = 0, containers:size() - 1 do
        local container = containers:get(i)
        local item = container:getFirstTypeEvalRecurse(entry.kind, function(candidate) return candidate:getID() == entry.id end)
        if item and item:getContainer() and item:getContainer():contains(item) then return item end
    end
end
local function remainingUses(character, item)
    local remaining = ISCampingMenu.getFuelItemUses(item)
    local queue = ISTimedActionQueue.queues[character]
    for _, action in ipairs(queue and queue.queue or {}) do
        local record = records[action]
        local saved = record and record.expected
        if saved and not (record.token and record.token.toolkitCancelled) then
            if record.command and not expanded[record.saved] then
                for i, entry in ipairs(saved.items) do
                    if entry.id == item:getID() then
                        if saved.fuel then remaining = remaining - entry.uses
                        elseif saved.mode == "onLightFromLiterature" and i == 1 then remaining = remaining - 1 end
                    end
                end
            elseif not record.command and (saved.fuel or saved.mode == "onLightFromLiterature") and record.fields.item
                and record.fields.item:getID() == item:getID() then remaining = remaining - 1 end
        end
    end
    return math.max(0, remaining)
end
local function selected(character, kind, all, count, predicate)
    local result, containers = {}, getContainers(character)
    local nativePredicate = predicate
    predicate = function(item) return nativePredicate(item) and remainingUses(character, item) > 0 end
    local list = ArrayList.new()
    for i = 0, containers:size() - 1 do
        local container = containers:get(i)
        if all then
            if kind then container:getAllTypeEval(kind, predicate, list) else container:getAllEval(predicate, list) end
        else
            local item = container:getFirstTypeEvalRecurse(kind, predicate)
            if item then list:add(item); break end
        end
    end
    local seen = {}
    for i = 0, list:size() - 1 do
        local item = list:get(i)
        if not seen[item:getID()] then
            seen[item:getID()] = true
            result[#result + 1] = {item = item, id = item:getID(), kind = item:getFullType(), source = item:getContainer(),
                uses = all and remainingUses(character, item) or 1}
            if count and #result >= count then break end
        end
    end
    return result
end
local function resource(item)
    if not instanceof(item, "InventoryItem") then return end
    return {item = item, id = item:getID(), kind = item:getFullType(), source = item:getContainer()}
end
local function snapshot(character, mode, ...)
    local args = {...}
    local target, class, items
    if mode == "onAddFuel" or mode == "onAddMultipleFuel" then
        target, class = args[1], args[3]
        items = selected(character, args[2], mode == "onAddMultipleFuel", args[5], ISCampingMenu.isValidFuel)
    elseif mode == "onAddAllFuel" then
        target, class = args[1], args[2]
        items = selected(character, nil, true, nil, ISCampingMenu.isValidFuel)
    elseif mode == "onLightFromLiterature" then
        target, class = args[3], args[4] or ISLightFromLiterature
        items = selected(character, args[1], false, nil, ISCampingMenu.isValidTinder)
        items[2] = resource(args[2])
    elseif mode == "onLightFromPetrol" then
        target, class = args[3], args[4] or ISLightFromPetrol
        items = {resource(args[1]), resource(args[2])}
    else
        target, class = args[3], args[4] or ISLightFromKindle
        items = {resource(args[1]), resource(args[2])}
    end
    if not unchanged(class) then return nil, "unsupported" end
    local object, reason = worldObject(target, class)
    if not object then return nil, reason end
    if object:getObjectIndex() == -1 or not object:getSquare() then return end
    local fuel = mode == "onAddFuel" or mode == "onAddAllFuel" or mode == "onAddMultipleFuel"
    if not items[1] or (not fuel and not items[2]) then return end
    local saved = {target = target, object = object, square = object:getSquare(), class = class, mode = mode, items = items, fuel = fuel,
        multiple = mode == "onAddAllFuel" or mode == "onAddMultipleFuel"}
    if not equipmentSafe(saved) then return nil, "unsupported" end
    return saved
end
local function seal(saved)
    local result = {}
    for key, value in pairs(saved) do result[key] = value end
    result.items = {}
    for i, entry in ipairs(saved.items) do
        result.items[i] = {}
        for key, value in pairs(entry) do result.items[i][key] = value end
    end
    return result
end
local function snapshotUnchanged(saved, expected)
    if type(saved) ~= "table" or getmetatable(saved) or type(saved.items) ~= "table" or getmetatable(saved.items) then return false end
    for key, value in pairs(expected) do
        if key ~= "items" and saved[key] ~= value then return false end
    end
    if #saved.items ~= #expected.items then return false end
    for i, entry in ipairs(expected.items) do
        if type(saved.items[i]) ~= "table" or getmetatable(saved.items[i]) then return false end
        for key, value in pairs(entry) do if saved.items[i][key] ~= value then return false end end
    end
    return true
end
local function actionRecord(action, saved, class, character)
    local record = {saved = saved, expected = seal(saved), class = class, character = character, token = saved.token, fields = {}}
    for _, name in ipairs({"item", "plank", "lighter", "petrol", "fuelAmt"}) do record.fields[name] = action[name] end
    return record
end
local function add(character, saved, ...)
    local action = saved.class:new(character, ...)
    action.toolkitQueueOperation = saved.token
    records[action] = actionRecord(action, saved, saved.class, character)
    ISTimedActionQueue.add(action)
    return action
end
local function addReturn(character, saved, item, entry)
    local queue, before = ISTimedActionQueue.getTimedActionQueue(character), {}
    for _, action in ipairs(queue.queue) do before[action] = true end
    returnItem(character, item, entry.source)
    for _, action in ipairs(queue.queue) do
        if not before[action] then
            returns[action] = {item = item, batchItem = item, id = entry.id, kind = entry.kind, source = entry.source,
                inventory = character:getInventory(), token = saved.token}
        end
    end
end
local function expand(character, saved)
    if expanded[saved] or not snapshots[saved] or not snapshotUnchanged(saved, snapshots[saved]) or not helpersSafe() or not equipmentSafe(saved) or not unchanged(saved.class) or worldObject(saved.target, saved.class) ~= saved.object
        or saved.object:getObjectIndex() == -1 or saved.object:getSquare() ~= saved.square then return end
    local items = {}
    for i, entry in ipairs(saved.items) do
        local item = available(character, entry)
        if not item then return end
        items[i] = {item = item, source = entry.source, uses = entry.uses}
    end
    local first, second = items[1], items[2]
    local predicate = saved.fuel and ISCampingMenu.isValidFuel or saved.mode == "onLightFromLiterature" and ISCampingMenu.isValidTinder
    if predicate then for _, entry in ipairs(items) do if (saved.fuel or entry == first) and not predicate(entry.item) then return end end end
    expanded[saved] = true
    for _, entry in ipairs(items) do ISCampingMenu.toPlayerInventory(character, entry.item) end
    if not ISCampingMenu.walkToCampfire(character, saved.square) then return end
    if saved.fuel then
        local currentFuel = saved.class == ISAddFuelAction and saved.target.fuelAmt or saved.target:getFuelAmount()
        for _, entry in ipairs(items) do
            if saved.multiple and character:isEquipped(entry.item) then
                local preparation = ISUnequipAction:new(character, entry.item, 50)
                ISTimedActionQueue.add(preparation)
                equipmentRecords[preparation] = {saved = saved, expected = snapshots[saved], character = character, item = entry.item, token = saved.token}
            end
            local amount = ISCampingMenu.getFuelDurationForItem(entry.item)
            for use = 1, math.min(entry.uses, ISCampingMenu.getFuelItemUses(entry.item)) do
                if currentFuel + amount > getCampingFuelMax() then return end
                add(character, saved, saved.target, entry.item, amount)
                currentFuel = currentFuel + amount
            end
        end
    elseif saved.mode == "onLightFromLiterature" then
        add(character, saved, first.item, second.item, saved.target, ISCampingMenu.getFuelDurationForItem(first.item))
        addReturn(character, saved, second.item, saved.items[2])
    elseif saved.mode == "onLightFromPetrol" then
        add(character, saved, saved.target, first.item, second.item, 20)
        addReturn(character, saved, first.item, saved.items[1])
    else
        add(character, saved, first.item, second.item, saved.target)
        addReturn(character, saved, second.item, saved.items[2])
        addReturn(character, saved, first.item, saved.items[1])
    end
end
local function enqueue(character, entry, ...)
    local saved, reason = snapshot(character, entry.mode, ...)
    if not saved then return nil, reason end
    saved.token = {}
    snapshots[saved] = seal(saved)
    local command = Operations.command(character, expand, saved, {fields = {toolkitWorldOperation = "fire", toolkitWorldTarget = saved.object, toolkitActionLabel = saved.fuel and "ContextMenu_DestroyForFuel" or "ContextMenu_Light_fire"}})
    command.toolkitQueueOperation = saved.token
    records[command] = {saved = saved, expected = seal(saved), character = character, token = saved.token, command = true}
    return Operations.runWith(saved.token, ISTimedActionQueue.add, command)
end
local function enabled() return Toolkit.Settings.actionQueue() and helpersSafe() end
for _, mode in ipairs({"onAddFuel", "onAddAllFuel", "onAddMultipleFuel", "onLightFromLiterature", "onLightFromPetrol", "onLightFromKindle"}) do
    local callback = ISCampingMenu[mode]
    trusted = trusted and nativeClosure(callback, "ISCampingMenu.lua")
    local entry = {mode = mode, native = callback}
    local wrapper = function(character, ...)
        if not enabled() then return callback(character, ...) end
        local result, reason = enqueue(character, entry, ...)
        if reason == "unsupported" then return callback(character, ...) end
        return result
    end
    entry.wrapper = wrapper
    ISCampingMenu[mode], bindings[mode], callbacks[callback], callbacks[wrapper] = wrapper, wrapper, entry, entry
end
local queueActions = ISTimedActionQueue.queueActions
ISTimedActionQueue.queueActions = function(character, callback, ...)
    local entry = callbacks[callback]
    if entry and enabled() and ISCampingMenu[entry.mode] == entry.wrapper then
        local result, reason = enqueue(character, entry, ...)
        if reason == "unsupported" then return queueActions(character, entry.native, ...) end
        return result
    end
    return queueActions(character, callback, ...)
end

function Fire.isDeferredAction(action)
    local record = records[action]
    return record and record.command and action.character == record.character and action.toolkitQueueOperation == record.token and snapshotUnchanged(record.saved, record.expected) and helpersSafe() and equipmentSafe(record.saved) and unchanged(record.saved.class) and Operations.isCommand(action)
end
function Fire.supports(action)
    local record = records[action]
    if not record or record.command or action.character ~= record.character or action.toolkitQueueOperation ~= record.token
        or getmetatable(action) ~= record.class
        or action.Type ~= record.class.Type or not helpersSafe() or not equipmentSafe(record.saved) or not unchanged(record.class)
        or action.onStartFunc or action.onCompleteFunc or action.onCancelFunc or action.retriggerLastAction then return false end
    for _, name in ipairs(lifecycle) do if action[name] ~= classes[record.class].methods[name] then return false end end
    for name, callback in pairs(classes[record.class].methods) do if action[name] ~= callback then return false end end
    local saved = record.saved
    if not snapshotUnchanged(saved, record.expected) then return false end
    if action.campfire then
        if getmetatable(action.campfire) ~= campfireClass then return false end
        for name, callback in pairs(campfireMethods) do if action.campfire[name] ~= callback then return false end end
    end
    for _, name in ipairs({"item", "plank", "lighter", "petrol", "fuelAmt"}) do
        local item, original = action[name], record.fields[name]
        if item ~= original and (name == "fuelAmt" or not isClient() or not instanceof(item, "InventoryItem") or not instanceof(original, "InventoryItem")
            or item:getID() ~= original:getID() or item:getFullType() ~= original:getFullType()
            or action.character:getInventory():getItemById(original:getID()) ~= item) then return false end
    end
    return (action.campfire or action.fireplace or action.bbq) == saved.target
end
-- Java rebinds direct action fields; native queueList retains the original item reference.
local function unchangedReturn(member, saved, record, inventory)
    if not saved or member.action or member.started or (member.transactionId or 0) ~= 0
        or member.character ~= record.character or member.toolkitQueueOperation ~= record.token or saved.token ~= record.token
        or member.srcContainer ~= inventory or saved.inventory ~= inventory or member.destContainer ~= saved.source
        or saved.source == inventory or not member.allowMissingItems or not instanceof(member.item, "InventoryItem")
        or member.item:getID() ~= saved.id or member.item:getFullType() ~= saved.kind
        or member.onStartFunc or member.onCompleteFunc or member.onCancelFunc then return false end
    local contract, id = Definitions.inspect(member)
    return id == "native.ISInventoryTransferAction" and contract and contract.knownInputs ~= false and contract.cancelWaiting
        and type(member.queueList) == "table" and #member.queueList == 1
        and type(member.queueList[1]) == "table" and type(member.queueList[1].items) == "table"
        and #member.queueList[1].items == 1 and member.queueList[1].items[1] == saved.batchItem
        and saved.batchItem:getID() == saved.id and saved.batchItem:getFullType() == saved.kind
end
-- A missing native return must not merge with the next live return before its MP start.
function Fire.skipUnavailableReturns(queue, action)
    local record = records[action]
    if not Toolkit.Settings.actionQueue() or queue.current ~= action or queue.queue[1] ~= action
        or ISTimedActionQueue.queues[action.character] ~= queue or not Fire.supports(action)
        or record.token.toolkitCancelled then return end
    local inventory = action.character:getInventory()
    while queue.queue[2] do
        local member = queue.queue[2]
        local saved = returns[member]
        if not unchangedReturn(member, saved, record, inventory) or member.item ~= saved.item
            or inventory:getItemById(saved.id) then return end
        table.remove(queue.queue, 2)
        returns[member] = nil
        member:forceCancel()
    end
end
-- Seal native transfer/start proxy replacements before authoritative consumption can revoke their contract.
for _, class in ipairs({ISAddFuelAction, ISLightFromLiterature, ISLightFromPetrol, ISLightFromKindle,
    ISBBQAddFuel, ISBBQLightFromLiterature, ISBBQLightFromPetrol, ISBBQLightFromKindle}) do
    local start = class.start
    class.start = function(action, ...)
        local record = records[action]
        if not record or not Fire.supports(action) then return start(action, ...) end
        local result = start(action, ...)
        if Fire.supports(action) then
            for _, name in ipairs({"item", "plank", "lighter", "petrol", "fuelAmt"}) do record.fields[name] = action[name] end
            local queue, inventory = ISTimedActionQueue.queues[action.character], action.character:getInventory()
            if isClient() and queue and queue.current == action and queue.queue[1] == action and not record.token.toolkitCancelled then
                for _, member in ipairs(queue.queue) do
                    local saved = returns[member]
                    if unchangedReturn(member, saved, record, inventory) and inventory:getItemById(saved.id) == member.item then
                        saved.item = member.item
                    end
                end
            end
        end
        return result
    end
    classes[class].methods.start = class.start
end
function Fire.canSkip(action)
    if not Fire.supports(action) then return false end
    if action.action and (action.action:finished() or action.action:isForceComplete()) then return false end
    local saved = records[action].saved
    if saved.object:getObjectIndex() == -1 or saved.object:getSquare() ~= saved.square then return true end
    for _, field in ipairs({"item", "plank", "lighter", "petrol"}) do
        local item = action[field]
        local inventory = action.character:getInventory()
        if item and ((isClient() and not inventory:containsID(item:getID()))
            or (not isClient() and not inventory:contains(item))) then return true end
    end
    if saved.fuel then
        local fuel = saved.class == ISAddFuelAction and saved.target.fuelAmt or saved.target:getFuelAmount()
        return fuel + action.fuelAmt > getCampingFuelMax()
    end
    if saved.class == ISLightFromLiterature or saved.class == ISLightFromPetrol or saved.class == ISLightFromKindle then
        return saved.target.isLit == true
    end
    return saved.object:isLit()
end
function Fire.inspect(action)
    local record = records[action]
    if not record then return end
    local saved = record.saved
    local result = {items = {}, itemTypes = {}, targets = {[saved.object] = true}, cancelWaiting = true, interrupt = "finish-step",
        deferred = record.command == true}
    for _, entry in ipairs(saved.items) do
        result.items[entry.id], result.itemTypes[entry.kind] = true, true
        if Toolkit.ActionQueuePolicy then Toolkit.ActionQueuePolicy.addContainerResources(result, entry.source) end
    end
    for _, name in ipairs({"item", "plank", "lighter", "petrol"}) do
        local item = action[name]
        if instanceof(item, "InventoryItem") then result.items[item:getID()], result.itemTypes[item:getFullType()] = true, true end
    end
    if saved.multiple then result.hands = action.character end
    if saved.class == ISLightFromKindle then
        result.dynamicInputsByType = {WoodenStick = true, WoodenStick2 = true, TreeBranch = true, TreeBranch2 = true}
        result.dynamicInputs = {['Base.WoodenStick'] = true, ['Base.WoodenStick2'] = true, ['Base.TreeBranch'] = true, ['Base.TreeBranch2'] = true}
    end
    return result
end
Definitions.registerBehavior("toolkit.fire-unequip", {
    types = {"ISUnequipAction"}, matches = function(action)
        local record = equipmentRecords[action]
        return record and action.character == record.character and action.item == record.item
            and action.toolkitQueueOperation == record.token and snapshotUnchanged(record.saved, record.expected)
            and helpersSafe() and equipmentSafe(record.saved) and type(cartMatches) == "function" and cartMatches(action)
    end, inspect = function(action)
        return {items = {[action.item:getID()] = true}, itemTypes = {[action.item:getFullType()] = true}, targets = {},
            hands = action.character, preparation = true, preparationFinish = true, cancelWaiting = false, interrupt = "finish-step"}
    end,
})
Definitions.registerBehavior("toolkit.fire", {types = names, matches = function(action) return Fire.isDeferredAction(action) or Fire.supports(action) end,
    inspect = Fire.inspect})

-- The native campfire retry belongs before this operation's returns and later user requests.
local perform = ISLightFromKindle.perform
ISLightFromKindle.perform = function(action, ...)
    local record = records[action]
    if not record or not Fire.supports(action) then return perform(action, ...) end
    return Operations.perform(action, perform, ...)
end
classes[ISLightFromKindle].methods.perform = ISLightFromKindle.perform
Operations.registerProducer("toolkit.fire", Fire.supports, function(parent, child)
    if getmetatable(child) ~= ISLightFromKindle or child.character ~= parent.character or child.campfire ~= parent.campfire
        or child.plank ~= parent.plank or child.onStartFunc or child.onCompleteFunc or child.onCancelFunc then return false end
    records[child] = actionRecord(child, records[parent].saved, ISLightFromKindle, parent.character)
    return Fire.supports(child), "before-returns"
end)
return Fire
