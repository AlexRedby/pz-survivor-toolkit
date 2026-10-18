require "PZSurvivorToolkit/ActionQueueOperations"
require "PZSurvivorToolkit/ActionQueuePolicy"
require "TimedActions/ISGeneratorInfoAction"
require "TimedActions/ISPlugGenerator"
require "TimedActions/ISActivateGenerator"
require "TimedActions/ISFixGenerator"
require "TimedActions/ISAddFuel"
require "TimedActions/ISTakeGenerator"
require "TimedActions/ISInventoryTransferUtil"

local Toolkit = PZSurvivorToolkit
local Generators = {}
Toolkit.ActionQueueGenerators = Generators
local Operations, Policy = Toolkit.ActionQueueOperations, Toolkit.ActionQueuePolicy
local Overlay = require "PZSurvivorToolkit/ActionQueueGeneratorOverlay"
local overlayMatches, overlayScope = Overlay.matches, Overlay.powerScopeKnown
local function overlayUnchanged()
    return Toolkit.ActionQueueGeneratorOverlay == Overlay and Overlay.matches == overlayMatches
        and Overlay.powerScopeKnown == overlayScope
end
local function matchesOverlay(owner, name, callback)
    return overlayUnchanged() and overlayMatches(owner, name, callback)
end
local Carts, cartCheck, equipmentCheck, unequipCheck, unequipMatches
local equipmentRecords = {}
local marker, records, bindings, classes, helpers = {}, {}, {}, {}, {}
local trustedInstalled, basicInstalled
local noEquipmentHooks = {ISGeneratorInfoAction = true, ISPlugGenerator = true, ISActivateGenerator = true, ISFixGenerator = true}
local helperOwners = {}
local continued = {}
local pendingPerform = {}

function Generators.prune()
    local pending = false
    for _, registry in ipairs({records, continued, pendingPerform, equipmentRecords}) do
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
    for _, registry in ipairs({records, continued, pendingPerform, equipmentRecords}) do
        for action in pairs(registry) do if not queued[action] then registry[action] = nil end end
    end
end
Events.OnTick.Add(Generators.prune)
if Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(function()
    for _, registry in ipairs({records, continued, pendingPerform, equipmentRecords}) do
        for key in pairs(registry) do registry[key] = nil end
    end
end) end
local kinds = {onInfoGenerator = "ISGeneratorInfoAction", onPlugGenerator = "ISPlugGenerator",
    onActivateGenerator = "ISActivateGenerator", onFixGenerator = "ISFixGenerator",
    onTakeGenerator = "ISTakeGenerator", doAddFuelGenerator = "ISAddFuel"}
local hashes = {ISGeneratorInfoAction = 2497952627, ISPlugGenerator = 4207143728,
    ISActivateGenerator = 844646271, ISFixGenerator = 2090470527, ISAddFuel = 1340790859, ISTakeGenerator = 2180174053}
local function sourceMatches(path, expected)
    if type(getGameFilesInput) ~= "function" then return false end
    local ok, reader = pcall(getGameFilesInput, "media/lua/" .. path)
    if not ok or not reader then return false end
    local valid, hash = pcall(function()
        local value, bytes = 5381, 0
        while true do
            local line = reader:readLine()
            if not line then break end
            bytes = bytes + #line + 1
            if bytes > 2000000 then return end
            for i = 1, #line do value = (value * 33 + string.byte(line, i)) % 4294967296 end
            value = (value * 33 + 10) % 4294967296
        end
        return value
    end)
    pcall(function() reader:close() end)
    -- shortcut: permissions require the reviewed B42.21 Lua; re-audit when native source changes.
    return valid and hash == expected
end
local function nativeClosure(callback, filename)
    if type(callback) ~= "function" or type(getFilenameOfClosure) ~= "function" then return false end
    local ok, source = pcall(getFilenameOfClosure, callback)
    return ok and type(source) == "string" and source:gsub("\\", "/"):match("([^/]+)$") == filename
end
function Generators.prepareOverlay()
    Overlay.prepare(sourceMatches, nativeClosure)
end
local function captureClass(name)
    local class = _G[name]
    if not class or class.Type ~= name then return end
    local methods = {}
    for key, value in pairs(class) do
        if type(value) == "function" then
            if key ~= "derive" and not nativeClosure(value, name .. ".lua") and not matchesOverlay(class, key, value) then return end
            methods[key] = value
        end
    end
    return {class = class, methods = methods, overlay = matchesOverlay(class, "complete", class.complete)}
end
local function classUnchanged(kind)
    local saved = classes[kind]
    if not saved or _G[kind] ~= saved.class or saved.class.Type ~= kind then return false end
    for method, callback in pairs(saved.methods) do if saved.class[method] ~= callback then return false end end
    if saved.overlay and not matchesOverlay(saved.class, "complete", saved.methods.complete) then return false end
    return true
end
local function cartConstructor(callback)
    return Carts and Toolkit.ActionQueueCarts == Carts and Carts.isTransferConstructor == cartCheck
        and type(cartCheck) == "function" and cartCheck(callback) == true
end
local function cartUnequip(callback)
    return Carts and Toolkit.ActionQueueCarts == Carts and Carts.isUnequipConstructor == unequipCheck
        and type(unequipCheck) == "function" and unequipCheck(callback) == true
end
local function equipmentSafe(kind, character)
    if noEquipmentHooks[kind] then return true end
    if Carts and equipmentCheck then
        return Toolkit.ActionQueueCarts == Carts and Carts.equipmentSafe == equipmentCheck
            and Carts.isNonCartUnequip == unequipMatches and Carts.isUnequipConstructor == unequipCheck
            and equipmentCheck(character)
    end
    return not (getActivatedMods and getActivatedMods():contains("SaucedCarts"))
end
local function unchanged(kind, character)
    if character and not equipmentSafe(kind, character) then return false end
    for name, owner in pairs(helperOwners) do
        if _G[name] ~= owner and (not noEquipmentHooks[kind] or (name ~= "ISEquipWeaponAction" and name ~= "ISUnequipAction")) then return false end
    end
    for _, saved in ipairs(helpers) do
        local current = saved.owner[saved.name]
        if (not noEquipmentHooks[kind] or not saved.equipment) and (saved.cart or current ~= saved.callback)
            and not (saved.owner == ISInventoryTransferAction and saved.name == "new"
            and cartConstructor(saved.callback) and cartConstructor(current))
            and not (saved.owner == ISUnequipAction and saved.name == "new"
                and cartUnequip(saved.callback) and cartUnequip(current)) then return false end
    end
    return classUnchanged(kind)
end
local function contract(character, object, kind, selected)
    if not instanceof(object, "IsoGenerator") then return end
    local result = {items = {}, itemTypes = {}, targets = {[object] = true}, cancelWaiting = true,
        interrupt = "audited-stop"}
    if kind == "ISFixGenerator" then
        result.dynamicInputs, result.dynamicInputsByType = {["Base.ElectronicsScrap"] = true}, {ElectronicsScrap = true}
    end
    if kind == "ISAddFuel" then
        result.equipment = character
        for _, saved in ipairs(selected or {}) do
            result.items[saved.id], result.itemTypes[saved.kind] = true, true
            Policy.addContainerResources(result, saved.source)
        end
    elseif kind == "ISTakeGenerator" then
        result.equipment, result.unknownOutputs = character, true
    elseif kind == "ISGeneratorInfoAction" then result.interrupt = "finish-step" end
    return result
end
function Generators.inspect(action)
    local kind = action.Type
    if not unchanged(kind, action.character) then return end
    local object = kind == "ISGeneratorInfoAction" and action.object or action.generator
    local selected
    if kind == "ISAddFuel" then
        local item = action.petrol
        if not instanceof(item, "InventoryItem") or item:getFluidContainer() ~= action.fluidCont then return end
        selected = {{id = item:getID(), kind = item:getFullType(), source = item:getContainer()}}
    elseif kind == "ISActivateGenerator" and type(action.activate) ~= "boolean" then return
    elseif kind == "ISPlugGenerator" and type(action.plug) ~= "boolean" then return end
    return contract(action.character, object, kind, selected)
end
local function commandRecord(action)
    local saved = records[action]
    if not saved or not Operations.isCommand(action) or action.toolkitGeneratorCommand ~= marker
        or action.args[1] ~= saved.target or action.generator ~= saved.target.object then return end
    for key, value in pairs(saved.fields) do if saved.target[key] ~= value then return end end
    for i = 1, saved.args.n do if saved.target.args[i] ~= saved.args[i] then return end end
    if saved.args.n ~= saved.target.args.n then return end
    for i, item in ipairs(saved.selected) do
        local current = saved.target.selected[i]
        if not current or current.id ~= item.id or current.kind ~= item.kind or current.source ~= item.source then return end
    end
    if saved.target.selected and #saved.target.selected ~= #saved.selected then return end
    if saved.trusted and unchanged(saved.target.kind, action.character) and ISWorldObjectContextMenu[saved.target.method] == bindings[saved.target.method] then return saved end
end
local function commandInspect(action)
    local saved = commandRecord(action)
    if not saved then return end
    if saved.target.kind == "ISActivateGenerator" and type(saved.args[2]) ~= "boolean" then return end
    if saved.target.kind == "ISPlugGenerator" and type(saved.args[4]) ~= "boolean" then return end
    local result = contract(action.character, saved.target.object, saved.target.kind, saved.target.selected)
    if result then result.deferred, result.preparationFinish, result.interrupt = true, true, "finish-step" end
    return result
end
local function liveItem(character, saved)
    local predicate = function(item) return item:getID() == saved.id end
    local item = character:getInventory():getFirstEvalRecurse(predicate)
    if not item and saved.source then item = saved.source:getFirstEvalRecurse(predicate) end
    local fluid = item and item:getFluidContainer()
    if item and item:getFullType() == saved.kind and fluid and fluid:contains(Fluid.Petrol) and fluid:getAmount() > 0 then return item end
end
local function execute(character, target)
    local object = target.object
    if object:getObjectIndex() == -1 or object:getSquare() ~= target.square
        or ISWorldObjectContextMenu[target.method] ~= bindings[target.method] then return end
    if target.trusted and not commandRecord(ISTimedActionQueue.getTimedActionQueue(character).current) then return end
    if target.selected then
        local live = {}
        for _, saved in ipairs(target.selected) do
            local item = liveItem(character, saved)
            if item then live[#live + 1] = item end
        end
        if #live == 0 then return end
        return target.callback(target.args[1], object, live, nil, target.args[5])
    end
    local queue, before = ISTimedActionQueue.getTimedActionQueue(character), {}
    for _, member in ipairs(queue.queue) do before[member] = true end
    local result = target.callback(unpack(target.args, 1, target.args.n))
    if target.trusted and target.kind == "ISTakeGenerator" then
        for _, member in ipairs(queue.queue) do
            if not before[member] and member.Type == "ISUnequipAction" then
                equipmentRecords[member] = {character = character, item = member.item, token = member.toolkitQueueOperation}
            end
        end
    end
    return result
end
local function pending(character)
    local queue = character and ISTimedActionQueue.queues[character]
    return Toolkit.Settings.actionQueue() and queue and #queue.queue > 0
end
local function enqueue(character, object, method, callback, args, trusted, selected)
    local target = {object = object, square = object:getSquare(), method = method, kind = kinds[method],
        callback = callback, args = args, trusted = trusted, selected = selected}
    local action = Operations.command(character, execute, target, {fields = {generator = object,
        toolkitGeneratorCommand = marker, toolkitWorldTarget = object, toolkitWorldOperation = trusted and "generator" or "device",
        toolkitActionLabel = Toolkit.ActionQueueDefinitions.describe({Type = target.kind, activate = args[2], plug = args[4]}).signature}})
    local fields, savedArgs, savedSelected = {}, {n = args.n}, {}
    for key, value in pairs(target) do fields[key] = value end
    for i = 1, args.n do savedArgs[i] = args[i] end
    for i, item in ipairs(selected or {}) do savedSelected[i] = {id = item.id, kind = item.kind, source = item.source} end
    records[action] = {target = target, trusted = trusted, fields = fields, args = savedArgs, selected = savedSelected}
    return Operations.run(ISTimedActionQueue.add, action)
end
local function powerConflict(first, second)
    local saved = records[first]
    local kind = saved and saved.target.kind or first.Type
    local object = saved and saved.target.object or first.generator
    if not object or kind == "ISGeneratorInfoAction" or not instanceof(object, "IsoGenerator") then return end
    local origin = object:getSquare()
    if not origin then return true end
    if not IsoGenerator or not IsoGenerator.isPoweringSquare then return true end
    local function contains(square)
        return square and IsoGenerator.isPoweringSquare(origin:getX(), origin:getY(), origin:getZ(), square:getX(), square:getY(), square:getZ())
    end
    local targets = {}
    for _, name in ipairs({"generator", "object", "toolkitWorldTarget", "stove", "mcwave", "charger", "isoObject"}) do
        if second[name] then targets[#targets + 1] = second[name] end
    end
    if second.moveProps and second.moveProps.object then targets[#targets + 1] = second.moveProps.object end
    local other = Policy.inspect(second)
    for target in pairs(other and other.targets or {}) do targets[#targets + 1] = target end
    for _, container in pairs({second.srcContainer, second.destContainer}) do
        if instanceof(container, "ItemContainer") then targets[#targets + 1] = container:getParent() end
    end
    -- Sparse native fields must not truncate later targets.
    local unknownPowerScope = type(BGI_PowerRange) == "table" and not (overlayUnchanged() and overlayScope())
    local building = origin:getBuilding()
    for _, target in pairs(targets) do
        if instanceof(target, "IsoObject") then
            local square = target:getSquare()
            if unknownPowerScope or not square or contains(square) then return target end
            -- Activation changes toxicity for the whole indoor building, beyond the power radius.
            if building and building == square:getBuilding() then return target end
            if instanceof(target, "IsoGenerator") then
                local options = getSandboxOptions and getSandboxOptions()
                local radius = options and options:getOptionByName("GeneratorTileRange")
                local vertical = options and options:getOptionByName("GeneratorVerticalPowerRange")
                if not radius or not vertical then return target end
                local dx, dy, dz = origin:getX() - square:getX(), origin:getY() - square:getY(), origin:getZ() - square:getZ()
                -- Generators can share consumers while neither powers the other's square.
                if dx * dx + dy * dy <= 4 * radius:getValue() ^ 2 and math.abs(dz) <= 2 * vertical:getValue() then return target end
            end
        end
    end
    if second.toolkitWorldX ~= nil then
        if unknownPowerScope then return true end
        local x, y = second.toolkitWorldMinX or second.toolkitWorldX, second.toolkitWorldMinY or second.toolkitWorldY
        local z = second.toolkitWorldZ
        local function clamp(value, low, high) return math.max(low, math.min(value, high)) end
        if IsoGenerator.isPoweringSquare(origin:getX(), origin:getY(), origin:getZ(),
            clamp(origin:getX(), x, x + (second.toolkitWorldWidth or 1) - 1),
            clamp(origin:getY(), y, y + (second.toolkitWorldHeight or 1) - 1),
            clamp(origin:getZ(), z, z + (second.toolkitWorldLayers or 1) - 1)) then return true end
    end
end
function Generators.canSkip(action)
    if not (trustedInstalled or noEquipmentHooks[action.Type] and basicInstalled)
        or not hashes[action.Type] or not Policy.inspect(action) then return false end
    local kind = action.Type
    local object = kind == "ISGeneratorInfoAction" and action.object or action.generator
    if object:getObjectIndex() == -1 or not object:getSquare() then return true end
    if kind == "ISActivateGenerator" then
        return action.activate == object:isActivated() or (action.activate and not object:isConnected())
            or object:getFuel() <= 0 or object:getCondition() <= 0
    elseif kind == "ISPlugGenerator" then return action.plug == object:isConnected()
    elseif kind == "ISFixGenerator" then
        return object:isActivated() or object:getCondition() >= 100
            or not action.character:getInventory():containsTypeRecurse("ElectronicsScrap")
    elseif kind == "ISAddFuel" then
        return object:getFuelPercentage() >= 100 or action.fluidCont:getAmount() <= 0
            or not action.fluidCont:contains(Fluid.Petrol)
    elseif kind == "ISTakeGenerator" then return object:isConnected() end
    return false
end
function Generators.sharesTarget(first, second)
    return powerConflict(first, second) or powerConflict(second, first)
end
local installed
function Generators.install()
    if installed then return end
    installed = true
    Carts = Toolkit.ActionQueueCarts
    cartCheck = Carts and Carts.isTransferConstructor
    equipmentCheck, unequipCheck, unequipMatches = Carts and Carts.equipmentSafe,
        Carts and Carts.isUnequipConstructor, Carts and Carts.isNonCartUnequip
    for _, name in ipairs({"luautils", "ISWorldObjectContextMenu", "ISInventoryPaneContextMenu", "ISInventoryTransferUtil",
        "ISInventoryTransferAction", "ISEquipWeaponAction", "ISUnequipAction", "ISWalkToTimedAction"}) do
        helperOwners[name] = _G[name]
    end
    local nativeInventory = sourceMatches("client/ISUI/ISInventoryPaneContextMenu.lua", 4293448388)
    local cleanUIInventory = not nativeInventory and sourceMatches("client/ISUI/ISInventoryPaneContextMenu.lua", 1953753890)
    local trusted = type(ISInventoryTransferUtil) == "table" and sourceMatches("client/ISUI/ISWorldObjectContextMenu.lua", 1920579052)
        and (nativeInventory or cleanUIInventory)
        and sourceMatches("shared/luautils.lua", 1091751327)
        and sourceMatches("shared/TimedActions/ISInventoryTransferUtil.lua", 1281392797)
    -- Only fuel and pickup use the equipment preparation helpers.
    local basicTrusted = trusted
    for name, hash in pairs(hashes) do
        local path = (name == "ISGeneratorInfoAction" and "client" or "shared") .. "/TimedActions/" .. name .. ".lua"
        classes[name] = sourceMatches(path, hash) and captureClass(name) or nil
    end
    for _, entry in ipairs({{luautils, "walkAdj", "luautils.lua"}, {luautils, "getCorrectSquareForWall", "luautils.lua"},
        {luautils, "haveToBeTransfered", "luautils.lua"}, {luautils, "walkToContainer", "luautils.lua"}, {ISWorldObjectContextMenu, "equip", "ISWorldObjectContextMenu.lua"},
        {ISWorldObjectContextMenu, "transferIfNeeded", "ISWorldObjectContextMenu.lua"},
        {ISInventoryPaneContextMenu, "transferIfNeeded", "ISInventoryPaneContextMenu.lua"}}) do
        local callback = entry[1] and entry[1][entry[2]]
        local equipment = entry[1] == ISWorldObjectContextMenu and (entry[2] == "equip" or entry[2] == "transferIfNeeded")
        local valid = nativeClosure(callback, entry[3])
        trusted, basicTrusted = trusted and valid, basicTrusted and (equipment or valid)
        helpers[#helpers + 1] = {owner = entry[1] or {}, name = entry[2], callback = callback, equipment = equipment}
    end
    if cleanUIInventory then
        for _, name in ipairs({"cleanUIResetStaleTimedActionRetrigger", "cleanUILogTimedActionFix"}) do
            local callback = ISInventoryPaneContextMenu[name]
            local valid = nativeClosure(callback, "ISInventoryPaneContextMenu.lua")
            trusted, basicTrusted = trusted and valid, basicTrusted and valid
            helpers[#helpers + 1] = {owner = ISInventoryPaneContextMenu, name = name, callback = callback}
        end
    end
    for name, callback in pairs(ISInventoryTransferUtil or {}) do
        if type(callback) == "function" then
            local valid = nativeClosure(callback, "ISInventoryTransferUtil.lua")
            trusted, basicTrusted = trusted and valid, basicTrusted and valid
            helpers[#helpers + 1] = {owner = ISInventoryTransferUtil, name = name, callback = callback}
        end
    end
    for _, name in ipairs({"ISInventoryTransferAction", "ISEquipWeaponAction", "ISUnequipAction", "ISWalkToTimedAction"}) do
        local class = _G[name]
        local callback = class and class.new
        local cart = name == "ISInventoryTransferAction" and cartConstructor(callback)
        local equipment = name == "ISEquipWeaponAction" or name == "ISUnequipAction"
        local valid = cart or (name == "ISUnequipAction" and cartUnequip(callback)) or nativeClosure(callback, name == "ISWalkToTimedAction" and "WalkToTimedAction.lua" or name .. ".lua")
        trusted, basicTrusted = trusted and valid, basicTrusted and (equipment or valid)
        helpers[#helpers + 1] = {owner = class or {}, name = "new", callback = callback, cart = cart, equipment = equipment}
    end
    trustedInstalled, basicInstalled = trusted, basicTrusted
    if classes.ISFixGenerator then
        local native = ISFixGenerator.continueFixing
        ISFixGenerator.continueFixing = function(action)
            if action.toolkitQueueOperation and action.toolkitQueueOperation.toolkitCancelled then return end
            if not Toolkit.Settings.actionQueue() or not action.toolkitQueueOperation then return native(action) end
            local queue = ISTimedActionQueue.queues[action.character]
            if continued[action] or not queue or queue:indexOf(action) == -1 then return end
            continued[action] = true
            local continuation = Operations.attachContinuation(action.toolkitQueueOperation, action.character)
            if continuation then return Operations.runContinuation(continuation, native, action) end
        end
        classes.ISFixGenerator.methods.continueFixing = ISFixGenerator.continueFixing
        local perform = ISFixGenerator.perform
        ISFixGenerator.perform = function(action, ...)
            local queue = ISTimedActionQueue.queues[action.character]
            if not isClient() and not isServer() and Toolkit.Settings.actionQueue() and action.toolkitQueueOperation
                and not (Toolkit.ActionQueueLifecycle and Toolkit.ActionQueueLifecycle.current(action.character) == action)
                and queue and queue.current == action and queue.queue[1] == action and classUnchanged("ISFixGenerator") then
                local completed, ownCompleted = queue.onCompleted, rawget(queue, "onCompleted")
                -- SP performs before complete; defer only advancement so native addAfter still has its parent.
                queue.onCompleted = function(current, finished)
                    if finished == action then pendingPerform[action] = queue; return end
                    return completed(current, finished)
                end
                local ok, result = pcall(Operations.runWith, action.toolkitQueueOperation, perform, action, ...)
                queue.onCompleted = ownCompleted
                if not ok then pendingPerform[action] = nil; error(result, 0) end
                return result
            end
            return Operations.perform(action, perform, ...)
        end
        classes.ISFixGenerator.methods.perform = ISFixGenerator.perform
        local complete = ISFixGenerator.complete
        ISFixGenerator.complete = function(action, ...)
            local ok, result = pcall(complete, action, ...)
            local queue = pendingPerform[action]
            if queue then
                pendingPerform[action] = nil
                if ISTimedActionQueue.queues[action.character] == queue and queue.current == action and queue.queue[1] == action then
                    queue:onCompleted(action)
                end
            end
            if not ok then error(result, 0) end
            return result
        end
        classes.ISFixGenerator.methods.complete = ISFixGenerator.complete
        Operations.registerProducer("generators", function(action)
            return action.Type == "ISFixGenerator" and Policy.inspect(action) ~= nil
        end, function(parent, child)
            return child.character == parent.character and child.generator == parent.generator
                and child.Type == "ISFixGenerator" and Policy.inspect(child) ~= nil
        end)
    end
    if trusted or basicTrusted then
        for name in pairs(classes) do
            if trusted or noEquipmentHooks[name] then Policy.registerNative(name, Generators.inspect) end
        end
        Toolkit.ActionQueueDefinitions.registerBehavior("toolkit.generators", {matches = function(action)
            return action.Type == "ISQueueActionsAction" and commandRecord(action) ~= nil
        end, inspect = commandInspect})
    end
    if type(unequipMatches) == "function" then Toolkit.ActionQueueDefinitions.registerBehavior("toolkit.generator-unequip", {
        types = {"ISUnequipAction"}, matches = function(action)
            local saved = equipmentRecords[action]
            return saved and action.character == saved.character and action.item == saved.item
                and action.toolkitQueueOperation == saved.token and saved.token ~= nil
                and unchanged("ISTakeGenerator", action.character) and type(unequipMatches) == "function"
                and unequipMatches(action)
        end, inspect = function(action)
            return {items = {[action.item:getID()] = true}, itemTypes = {[action.item:getFullType()] = true}, targets = {},
                hands = action.character, preparation = true, preparationFinish = true, cancelWaiting = false, interrupt = "finish-step"}
        end,
    }) end
    for method in pairs(kinds) do
        local name, callback = method, ISWorldObjectContextMenu[method]
        if callback then
            local native = (trusted or noEquipmentHooks[kinds[name]] and basicTrusted)
                and classes[kinds[name]] ~= nil and (nativeClosure(callback, "ISWorldObjectContextMenu.lua")
                    or matchesOverlay(ISWorldObjectContextMenu, name, callback))
            local binding
            binding = function(...)
                local args = {n = select("#", ...), ...}
                local playerIndex, objectIndex = name == "doAddFuelGenerator" and 5 or (name == "onActivateGenerator" and 4 or 3), name == "onActivateGenerator" and 3 or 2
                local character, object = getSpecificPlayer(args[playerIndex]), args[objectIndex]
                if not pending(character) or not object or not object:getSquare() then return Operations.run(callback, ...) end
                local selected
                if name == "doAddFuelGenerator" then
                    selected = {}
                    for _, item in ipairs(args[3] and #args[3] > 0 and args[3] or {args[4]}) do
                        selected[#selected + 1] = {id = item:getID(), kind = item:getFullType(), source = item:getContainer()}
                    end
                end
                return enqueue(character, object, name, callback, args, native and equipmentSafe(kinds[name], character), selected)
            end
            ISWorldObjectContextMenu[name], bindings[name] = binding, binding
        end
    end
end
return Generators
