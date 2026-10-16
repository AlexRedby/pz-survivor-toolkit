require "XpSystem/ISUI/ISHealthPanel"
require "TimedActions/ISRemoveGlass"
require "TimedActions/ISApplyBandage"
require "TimedActions/ISDisinfect"
require "TimedActions/ISStitch"
require "TimedActions/ISSplint"
require "TimedActions/ISRemoveBullet"
require "TimedActions/ISCleanBurn"
require "TimedActions/ISComfreyCataplasm"
require "TimedActions/ISGarlicCataplasm"
require "TimedActions/ISPlantainCataplasm"

local Toolkit = PZSurvivorToolkit
local Health = {}
Toolkit.ActionQueueHealth = Health
local handlers, trustedPanel = {}, nil
local bindings = {}
local actionBindings = {}
local children = {}
local records = {}
local panelHelpers = {}
local containersHelper
local containerAdapter, containerGuard
local playerLookup = getPlayerByOnlineID
local function nativeClosure(callback, filename)
    if type(getFilenameOfClosure) ~= "function" then return false end
    local ok, source = pcall(getFilenameOfClosure, callback)
    return ok and type(source) == "string" and source:gsub("\\", "/"):match("([^/]+)$") == (filename or "ISHealthPanel.lua")
end
local function nativeSource(path, expected)
    if type(getGameFilesInput) ~= "function" then return false end
    local ok, reader = pcall(getGameFilesInput, path or "media/lua/client/XpSystem/ISUI/ISHealthPanel.lua")
    if not ok or not reader then return false end
    local valid, hash = pcall(function()
        local value, bytes = 5381, 0
        while true do
            local line = reader:readLine()
            if not line then break end
            bytes = bytes + #line + 1
            if bytes > 200000 then return end
            for i = 1, #line do value = (value * 33 + string.byte(line, i)) % 4294967296 end
            value = (value * 33 + 10) % 4294967296
        end
        return value
    end)
    pcall(function() reader:close() end)
    -- shortcut: private handlers require this reviewed B42.21 source; re-audit the adapter when the source changes.
    return valid and hash == (expected or 3948596941)
end
local kinds = {HApplyBandage = 1, HDisinfect = 1, HStitch = 2, HSplint = 2, HRemoveGlass = 1,
    HRemoveBullet = 1, HCleanBurn = 1, HRemoveBandage = 0, HRemoveStitch = 0, HRemoveSplint = 0,
    HApplyComfrey = 1, HApplyGarlic = 1, HApplyPlantain = 1}
local childNames = {HApplyBandage = "ISApplyBandage", HRemoveBandage = "ISApplyBandage", HDisinfect = "ISDisinfect",
    HStitch = "ISStitch", HRemoveStitch = "ISStitch", HSplint = "ISSplint", HRemoveSplint = "ISSplint",
    HRemoveGlass = "ISRemoveGlass", HRemoveBullet = "ISRemoveBullet", HCleanBurn = "ISCleanBurn",
    HApplyComfrey = "ISComfreyCataplasm", HApplyGarlic = "ISGarlicCataplasm", HApplyPlantain = "ISPlantainCataplasm"}
local childSources = {ISApplyBandage = 2803499221, ISDisinfect = 3741707122, ISStitch = 2530457766,
    ISSplint = 2375527233, ISRemoveGlass = 3698948194, ISRemoveBullet = 3894979839, ISCleanBurn = 3569789416,
    ISComfreyCataplasm = 2138588477, ISGarlicCataplasm = 3991409036, ISPlantainCataplasm = 2742789526}

local function captureChild(name)
    local class = _G[name]
    if not class or class.Type ~= name or type(rawget(class, "new")) ~= "function" then return end
    local snapshot = {class = class, methods = {}, base = {}}
    for key, value in pairs(class) do
        if type(value) == "function" then
            if not (key == "derive" and value == ISBaseTimedAction.derive) and not nativeClosure(value, name .. ".lua") then return end
            snapshot.methods[key] = value
        end
    end
    for key, value in pairs(ISBaseTimedAction) do
        if type(value) == "function" then
            if not snapshot.methods[key] and class[key] ~= value then return end
            snapshot.base[key] = value
        end
    end
    return snapshot
end

local function childMatches(kind, action)
    local name = childNames[kind]
    local snapshot = children[name]
    if not snapshot or _G[name] ~= snapshot.class or snapshot.class.Type ~= name then return false end
    for key, value in pairs(snapshot.methods) do if rawget(snapshot.class, key) ~= value then return false end end
    for key, value in pairs(snapshot.base) do
        if ISBaseTimedAction[key] ~= value or not snapshot.methods[key] and snapshot.class[key] ~= value then return false end
    end
    if action then
        if getmetatable(action) ~= snapshot.class or action.onStartFunc or action.onCompleteFunc or action.onCancelFunc
            or action.retriggerLastAction or action.onFailFunc or action.additionalTest then return false end
        for name, callback in pairs(snapshot.methods) do if action[name] ~= callback then return false end end
        for name, callback in pairs(snapshot.base) do
            if not snapshot.methods[name] and action[name] ~= callback then return false end
        end
    end
    return true
end

local function capture(handler)
    if not handler or handler.panel ~= trustedPanel or not kinds[handler.Type] then return end
    local class = getmetatable(handler)
    if handlers[class] then return end
    for _, name in ipairs({"new", "perform", "isValid", "checkItems", "getDoctor", "getPatient", "toPlayerInventory"}) do
        if not nativeClosure(handler[name]) then return end
    end
    local methods, prototypes, parent = {}, {}, class
    while parent and parent ~= ISBaseObject do
        local own = {}
        for key, value in pairs(parent) do
            if type(value) == "function" then
                if not (key == "derive" and value == ISBaseObject.derive) and not nativeClosure(value) then return end
                own[key] = value
                if methods[key] == nil then methods[key] = value end
            end
        end
        prototypes[parent] = own
        local meta = getmetatable(parent)
        parent = meta and type(meta.__index) == "table" and meta.__index or nil
    end
    if parent ~= ISBaseObject or handler.derive ~= ISBaseObject.derive then return end
    handlers[class] = {methods = methods, prototypes = prototypes, kind = handler.Type, actionClass = handler.actionClass, itemType = handler.itemType}
end

local function pack(...) return {n = select("#", ...), ...} end
local function producer(callback, panel, ...)
    local previous = trustedPanel
    trustedPanel = panel
    local result = pack(pcall(callback, panel, ...))
    trustedPanel = previous
    if not result[1] then error(result[2], 0) end
    return unpack(result, 2, result.n)
end

local function handlerContract(action)
    for name, callback in pairs(bindings) do if ISHealthPanel[name] ~= callback then return end end
    for name, callback in pairs(actionBindings) do if HealthPanelAction[name] ~= callback then return end end
    local handler = action.handler
    local snapshot = handler and handlers[getmetatable(handler)]
    if not snapshot or handler.Type ~= snapshot.kind or handler.actionClass ~= snapshot.actionClass
        or handler.itemType ~= snapshot.itemType or not handler.panel or not handler.bodyPart then return end
    if not instanceof(handler.panel.character, "IsoPlayer") or not instanceof(handler.bodyPart, "BodyPart") then return end
    if not childMatches(handler.Type) then return end
    if handler.actionClass and handler.actionClass ~= children[childNames[handler.Type]].class then return end
    for name, method in pairs(snapshot.methods) do if handler[name] ~= method then return end end
    -- Native leaf handlers call parent methods explicitly, even when a leaf shadows the same name.
    for class, methods in pairs(snapshot.prototypes) do
        for name, method in pairs(methods) do if rawget(class, name) ~= method then return end end
    end
    if (handler.panel.otherPlayer or handler.panel.character) ~= action.character then return end
    for _, name in ipairs({"getDoctor", "checkContainerItems"}) do
        if handler.panel[name] ~= panelHelpers[name] then return end
    end
    local inputs = {}
    for i = 1, kinds[handler.Type] do
        local value = action.args and action.args[i]
        if value == nil and handler.Type == "HSplint" and i == 1 then
            -- A ready-made splint supplies only the second argument.
        elseif type(value) ~= "string" then return
        elseif value ~= "Hands" then inputs[value] = true end
    end
    local result = {items = {}, itemTypes = {}, targets = {[handler.bodyPart] = true}, dynamicInputs = inputs,
        cancelWaiting = true, interrupt = "finish-step",
        unknownOutputs = handler.Type == "HRemoveBandage" or handler.Type == "HRemoveSplint"}
    -- Native body updates add/remove hidden clothing in the patient's inventory.
    local part, gender = handler.bodyPart:getType(), handler.panel.character:getCharacterGender()
    result.outputTypes = {}
    local bandage = part:getBandageModel()
    for _, kind in pairs({bandage, bandage and bandage ~= "" and bandage .. "_Blood" or nil, part:getBiteWoundModel(gender),
        part:getScratchWoundModel(gender), part:getCutWoundModel(gender)}) do
        if kind ~= "" then result.itemTypes[kind], result.outputTypes[kind] = true, true end
    end
    if handler.Type == "HStitch" or handler.Type == "HRemoveStitch" then result.dynamicInputsByType = {SutureNeedleHolder = true} end
    if handler.Type == "HStitch" or handler.Type == "HDisinfect" or handler.Type == "HCleanBurn" then
        -- UseAndSync can create script-defined replacements, including modded ones.
        for kind in pairs(inputs) do
            local script = getScriptManager and getScriptManager():FindItem(kind)
            if not script or script:getReplaceOnUse() or script:getReplaceOnDeplete() or script:getOnBreak() then
                result.unknownOutputs = true
            end
        end
    end
    return result
end

local function helpersMatch()
    if getPlayerByOnlineID ~= playerLookup then return false end
    if containerGuard then
        if Toolkit.ActionQueueFire ~= containerAdapter or containerAdapter.matchesContainerGetter ~= containerGuard
            or not containerGuard(containersHelper) then return false end
    elseif ISInventoryPaneContextMenu.getContainers ~= containersHelper then return false end
    for name, callback in pairs(bindings) do if ISHealthPanel[name] ~= callback then return false end end
    for name, callback in pairs(actionBindings) do if HealthPanelAction[name] ~= callback then return false end end
    for name, callback in pairs(panelHelpers) do if ISHealthPanel[name] ~= callback then return false end end
    return true
end

local function parentMatches(action, saved)
    if action.character ~= saved.character or action.toolkitQueueOperation ~= saved.token or action.handler ~= saved.handler
        or action.handler.panel ~= saved.panel or action.handler.bodyPart ~= saved.bodyPart
        or saved.panel.character ~= saved.patient or (saved.panel.otherPlayer or saved.panel.character) ~= saved.character then return false end
    for i = 1, 8 do if not action.args or action.args[i] ~= saved.args[i] then return false end end
    return true
end

local function patientAvailable(saved)
    local doctor, patient = saved.character, saved.patient
    if doctor:isDead() or patient:isDead() or not doctor:getSquare() or not patient:getSquare() then return false end
    local remote = isClient() and patient ~= doctor and not patient:isLocalPlayer()
    if remote and (not playerLookup or playerLookup(patient:getOnlineID()) ~= patient) then return false end
    local damage = remote and patient:getBodyDamageRemote() or patient:getBodyDamage()
    if damage:getBodyPart(saved.bodyPart:getType()) ~= saved.bodyPart then return false end
    if patient == doctor then return true end
    if doctor:getVehicle() and doctor:getVehicle() == patient:getVehicle() then return true end
    return doctor:getZ() == patient:getZ() and math.abs(doctor:getX() - patient:getX()) <= 2
        and math.abs(doctor:getY() - patient:getY()) <= 2
        and math.abs(patient:getX() - saved.patientX) <= 0.5 and math.abs(patient:getY() - saved.patientY) <= 0.5
        and math.abs(doctor:getX() - saved.doctorX) <= 0.5 and math.abs(doctor:getY() - saved.doctorY) <= 0.5
end

local function selectedItems(action)
    local handler, selected = action.handler, {}
    for i = 1, kinds[handler.Type] do
        local kind = action.args[i]
        if kind and kind ~= "Hands" then
            for _, list in pairs(handler.items) do
                for _, item in ipairs(list) do
                    if item:getFullType() == kind then selected[i] = item; break end
                end
                if selected[i] then break end
            end
            if not selected[i] then return end
        end
    end
    return selected
end

local function childMatchesRecord(action, saved)
    if action.character ~= saved.character or action.otherPlayer ~= saved.patient or action.bodyPart ~= saved.bodyPart
        or action.toolkitQueueOperation ~= saved.token then return false end
    for field, item in pairs(saved.fields) do
        local value = action[field]
        if item == false then if value ~= nil then return false end
        elseif not instanceof(value, "InventoryItem") or value:getID() ~= item:getID()
            or value:getFullType() ~= item:getFullType() then return false end
    end
    return action.doIt == saved.doIt and action.handPain == saved.handPain and action.doctor == saved.doctor
end

function Health.inspect(action)
    local saved = records[action]
    if not saved or not helpersMatch() or not childMatches(saved.kind) or not patientAvailable(saved) then return end
    if saved.parent then
        if not parentMatches(action, saved) then return end
        return handlerContract(action)
    end
    if not childMatches(saved.kind, action) or not childMatchesRecord(action, saved) then return end
    local result = {items = {}, itemTypes = {}, targets = {[saved.bodyPart] = true},
        dynamicInputs = saved.contract.dynamicInputs, dynamicInputsByType = saved.contract.dynamicInputsByType,
        outputTypes = saved.contract.outputTypes,
        unknownOutputs = saved.contract.unknownOutputs, cancelWaiting = true, interrupt = "audited-stop"}
    for kind in pairs(saved.contract.itemTypes) do result.itemTypes[kind] = true end
    for _, item in pairs(saved.selected) do
        result.items[item:getID()], result.itemTypes[item:getFullType()] = true, true
    end
    return result
end

local function clinicalAvailable(saved)
    local body, kind = saved.bodyPart, saved.kind
    if kind == "HRemoveBandage" then return body:bandaged() end
    if kind == "HRemoveStitch" then return body:stitched() end
    if kind == "HRemoveSplint" then return body:getSplintFactor() > 0 end
    if kind == "HSplint" then return body:HasInjury() and not body:stitched() and body:getFractureTime() > 0 and body:getSplintFactor() <= 0 end
    if body:bandaged() or not (body:HasInjury() or body:stitched() or body:getSplintFactor() > 0) then return false end
    if kind == "HStitch" then return body:isDeepWounded() and not body:haveGlass() end
    if kind == "HRemoveGlass" then return body:haveGlass() end
    if kind == "HRemoveBullet" then return body:haveBullet() end
    if kind == "HCleanBurn" then return body:isNeedBurnWash() end
    if kind == "HApplyComfrey" or kind == "HApplyGarlic" or kind == "HApplyPlantain" then
        return body:getPlantainFactor() == 0 and body:getComfreyFactor() == 0 and body:getGarlicFactor() == 0
    end
    return true
end

local function preparationMatches(action, saved)
    return action.character == saved.character and action.toolkitQueueOperation == saved.token
        and action.item == saved.item and action.srcContainer == saved.source and action.destContainer == saved.destination
        and Toolkit.ActionQueuePolicy.inspect(action) ~= nil
end

local function suppliesAvailable(saved, inventory)
    for _, item in pairs(saved.selected) do
        local current = inventory:getItemById(item:getID())
        if not current or current:getFullType() ~= item:getFullType() then return false end
        if current:IsDrainable() and current:getCurrentUsesFloat() <= 0 then return false end
    end
    if saved.kind == "HDisinfect" then
        local item = inventory:getItemById(saved.selected[1]:getID())
        if item:hasComponent(ComponentType.FluidContainer) then
            local fluid = item:getFluidContainer()
            return fluid:getAmount() > 0.15 and fluid:getProperties():getAlcohol() / fluid:getAmount() + 0.001 >= 0.4
        end
        return item:IsDrainable() and item:getAlcoholPower() == 4
    end
    return true
end

function Health.canSkip(action)
    if not Toolkit.Settings.actionQueue() then return false end
    local saved = records[action]
    if not saved or not helpersMatch() or not childMatches(saved.kind) then return false end
    if saved.preparation then
        return preparationMatches(action, saved) and (not patientAvailable(saved) or not action:isValid())
    end
    if saved.parent then
        for name, callback in pairs(actionBindings) do if action[name] ~= callback then return false end end
        -- The native panel can clear otherPlayer when closed; never switch doctors with it.
        if not parentMatches(action, saved) or not patientAvailable(saved) then return true end
        if not handlerContract(action) then return false end
        action.handler:checkItems()
        return not selectedItems(action) or not clinicalAvailable(saved)
    end
    if not childMatches(saved.kind, action) then return false end
    if not childMatchesRecord(action, saved) or not patientAvailable(saved) then return true end
    -- Authoritative consumption/body updates can precede MP perform; never veto completed effects.
    local nativeValid = children[childNames[saved.kind]].nativeValid
    if isClient() and action.action and action.action:isStarted() then return not nativeValid(action) end
    if not clinicalAvailable(saved) then return true end
    return not suppliesAvailable(saved, action.character:getInventory()) or not nativeValid(action)
end

function Health.canPreserveStop(action)
    if not Toolkit.Settings.actionQueue() then return false end
    local saved = records[action]
    if not saved or action.character ~= saved.character or action.toolkitQueueOperation ~= saved.token
        or not helpersMatch() or not childMatches(saved.kind) then return false end
    if saved.parent then return Health.canSkip(action) end
    if saved.preparation then return preparationMatches(action, saved) end
    -- A server refusal can stop a child before its local inventory/body snapshot reflects the reason.
    return childMatches(saved.kind, action)
end

local function captureExpanded(action, saved, selected, before)
    local queue = ISTimedActionQueue.queues[action.character]
    if not queue then return end
    for _, child in ipairs(queue.queue) do
        if not before[child] and child.toolkitQueueOperation == action.toolkitQueueOperation
            and child.character == saved.character and Toolkit.ActionQueueOperations.isTransfer(child)
            and Toolkit.ActionQueuePolicy.inspect(child) then
            records[child] = {preparation = true, kind = saved.kind, character = saved.character, patient = saved.patient,
                bodyPart = saved.bodyPart, patientX = saved.patientX, patientY = saved.patientY,
                doctorX = saved.doctorX, doctorY = saved.doctorY, token = action.toolkitQueueOperation,
                item = child.item, source = child.srcContainer, destination = child.destContainer}
        end
        if not before[child] and child.toolkitQueueOperation == action.toolkitQueueOperation
            and getmetatable(child) == children[childNames[saved.kind]].class
            and child.character == saved.character and child.otherPlayer == saved.patient and child.bodyPart == saved.bodyPart then
            local fields = {item = false, alcohol = false, bandage = false, rippedSheet = false, plank = false}
            if saved.kind == "HDisinfect" then fields.alcohol = selected[1]
            elseif saved.kind == "HCleanBurn" then fields.bandage = selected[1]
            elseif saved.kind == "HStitch" then fields.item = selected[2]
            elseif saved.kind == "HSplint" then fields.rippedSheet, fields.plank = selected[1] or false, selected[2]
            elseif saved.kind ~= "HRemoveGlass" and saved.kind ~= "HRemoveBullet" then fields.item = selected[1] or false end
            local record = {kind = saved.kind, character = saved.character, patient = saved.patient, bodyPart = saved.bodyPart,
                patientX = saved.patientX, patientY = saved.patientY, doctorX = saved.doctorX, doctorY = saved.doctorY,
                token = action.toolkitQueueOperation, selected = selected, fields = fields, contract = handlerContract(action),
                doIt = child.doIt, handPain = child.handPain}
            if saved.kind == "HDisinfect" or saved.kind == "HStitch" or saved.kind == "HRemoveStitch"
                or saved.kind == "HSplint" or saved.kind == "HRemoveSplint" or saved.kind == "HRemoveGlass"
                or saved.kind == "HRemoveBullet" then record.doctor = saved.character end
            if saved.kind == "HApplyBandage" or saved.kind == "HStitch" or saved.kind == "HSplint" then record.doIt = true
            elseif saved.kind == "HRemoveBandage" or saved.kind == "HRemoveStitch" or saved.kind == "HRemoveSplint" then record.doIt = false end
            if saved.kind == "HRemoveGlass" then record.handPain = action.args[1] == "Hands" end
            records[child] = record
            if not childMatchesRecord(child, record) then records[child] = nil end
        end
    end
end

local installed
function Health.install()
    if installed or not ISHealthPanel or not HealthPanelAction then return end
    installed = true
    if not nativeSource() or not nativeClosure(HealthPanelAction.new) or not nativeClosure(HealthPanelAction.perform)
        or not nativeClosure(ISHealthPanel.checkItems) or not nativeClosure(ISHealthPanel.doBodyPartContextMenu)
        or not nativeClosure(ISHealthPanel.dropItemsOnBodyPart) then return end
    containersHelper = ISInventoryPaneContextMenu.getContainers
    containerAdapter = Toolkit.ActionQueueFire
    containerGuard = containerAdapter and containerAdapter.matchesContainerGetter
    if containerGuard then
        if not containerGuard(containersHelper) then return end
    elseif not nativeClosure(containersHelper, "ISInventoryPaneContextMenu.lua") then return end
    for name, callback in pairs(HealthPanelAction) do
        if type(callback) == "function" then
            if callback ~= ISBaseTimedAction.derive and not nativeClosure(callback) then return end
            actionBindings[name] = callback
        end
    end
    for _, name in ipairs({"DidPatientMove", "setBodyPartActionForPlayer", "getBandageType", "getDoctor", "checkContainerItems"}) do
        if not nativeClosure(ISHealthPanel[name]) then return end
        panelHelpers[name] = ISHealthPanel[name]
    end
    for name, hash in pairs(childSources) do
        if nativeSource("media/lua/shared/TimedActions/" .. name .. ".lua", hash) then children[name] = captureChild(name) end
    end
    for _, name in ipairs({"doBodyPartContextMenu", "dropItemsOnBodyPart"}) do
        local callback = ISHealthPanel[name]
        if callback then
            ISHealthPanel[name] = function(panel, ...) return producer(callback, panel, ...) end
            bindings[name] = ISHealthPanel[name]
        end
    end
    local check = ISHealthPanel.checkItems
    ISHealthPanel.checkItems = function(panel, list)
        if trustedPanel == panel then for _, handler in ipairs(list) do capture(handler) end end
        return check(panel, list)
    end
    bindings.checkItems = ISHealthPanel.checkItems
    local new = HealthPanelAction.new
    -- Keep native parameter names: NetTimedAction serializes constructor parameters by name.
    HealthPanelAction.new = function(self, character, handler, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
        if trustedPanel then capture(handler) end
        local action = new(self, character, handler, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
        if handlerContract(action) and instanceof(character, "IsoPlayer") and instanceof(handler.panel.character, "IsoPlayer")
            and instanceof(handler.bodyPart, "BodyPart") then
            local patient = handler.panel.character
            Toolkit.ActionQueueOperations.adopt(action)
            records[action] = {parent = true, kind = handler.Type, handler = handler, panel = handler.panel,
                character = character, patient = patient, bodyPart = handler.bodyPart,
                token = action.toolkitQueueOperation,
                patientX = patient:getX(), patientY = patient:getY(), doctorX = character:getX(), doctorY = character:getY(),
                args = {arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8}}
        end
        return action
    end
    actionBindings.new = HealthPanelAction.new
    local perform = HealthPanelAction.perform
    HealthPanelAction.perform = function(action, ...)
        if Health.canSkip(action) then return ISBaseTimedAction.perform(action) end
        return Toolkit.ActionQueueOperations.perform(action, function(current, ...)
            local saved, before = records[current], {}
            local queue = ISTimedActionQueue.queues[current.character]
            if queue then for _, member in ipairs(queue.queue) do before[member] = true end end
            local selected = saved and Health.inspect(current) and selectedItems(current)
            local result = pack(perform(current, ...))
            if selected and Health.inspect(current) then captureExpanded(current, saved, selected, before) end
            return unpack(result, 1, result.n)
        end, ...)
    end
    actionBindings.perform = HealthPanelAction.perform
    local valid = HealthPanelAction.isValid
    HealthPanelAction.isValid = function(action)
        return not Health.canSkip(action) and valid(action)
    end
    actionBindings.isValid = HealthPanelAction.isValid
    for name, snapshot in pairs(children) do
        local class, original = snapshot.class, snapshot.class.isValid
        snapshot.nativeValid = original
        class.isValid = function(action) return not Health.canSkip(action) and original(action) end
        snapshot.methods.isValid = class.isValid
        Toolkit.ActionQueuePolicy.registerNative(name, Health.inspect)
    end
    Toolkit.ActionQueuePolicy.registerNative("HealthPanelAction", Health.inspect)
    -- The native bare-hands branch appends its child, unlike the other handlers' addAfter calls.
    local glass, methods = ISRemoveGlass, {}
    if glass then
        for _, name in ipairs({"new", "isValid", "waitToStart", "start", "update", "stop", "perform", "complete", "getDuration", "forceStop", "forceCancel"}) do
            methods[name] = glass[name] or false
        end
    end
    Toolkit.ActionQueueOperations.registerProducer("health", function(action)
        return getmetatable(action) == HealthPanelAction and Toolkit.ActionQueuePolicy.inspect(action) ~= nil
    end, function(parent, child)
        if not glass or parent.handler.Type ~= "HRemoveGlass" or parent.args[1] ~= "Hands"
            or getmetatable(child) ~= glass or child.bodyPart ~= parent.handler.bodyPart
            or child.otherPlayer ~= parent.handler.panel.character or child.character ~= parent.character
            or child.onStartFunc or child.onCompleteFunc or child.onCancelFunc or child.retriggerLastAction then return false end
        for name, method in pairs(methods) do if (child[name] or false) ~= method then return false end end
        return true
    end)
    Events.OnTick.Add(function()
        -- Kahlua ignores weak tables; keep proofs only while their actions remain queued.
        for action in pairs(records) do
            local queue = ISTimedActionQueue.queues[action.character]
            if not queue or queue:indexOf(action) == -1 then records[action] = nil end
        end
    end)
    if Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(function() records = {} end) end
end

Health.install()
return Health
