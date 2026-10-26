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
local droppedSupplies = {}
local miniPanel, miniBindings, miniReplace
local inventoryBindings
local dropAttempt
local panelHelpers = {}
local containersHelper
local containerAdapter, containerGuard
local playerLookup = getPlayerByOnlineID
local Proof = require "PZSurvivorToolkit/SourceProof"
local function nativeClosure(callback, filename)
    return Proof.closure(callback, filename or "ISHealthPanel.lua")
end
local function nativeSource(path, expected, mod)
    return Proof.matches(path or "media/lua/client/XpSystem/ISUI/ISHealthPanel.lua",
        expected or 3948596941, mod, false, 300000)
end
local kinds = {HApplyBandage = 1, HDisinfect = 1, HStitch = 2, HSplint = 2, HRemoveGlass = 1,
    HRemoveBullet = 1, HCleanBurn = 1, HRemoveBandage = 0, HRemoveStitch = 0, HRemoveSplint = 0,
    HApplyComfrey = 1, HApplyGarlic = 1, HApplyPlantain = 1, HReplaceBandage = 1}
local childNames = {HApplyBandage = "ISApplyBandage", HRemoveBandage = "ISApplyBandage", HDisinfect = "ISDisinfect",
    HStitch = "ISStitch", HRemoveStitch = "ISStitch", HSplint = "ISSplint", HRemoveSplint = "ISSplint",
    HRemoveGlass = "ISRemoveGlass", HRemoveBullet = "ISRemoveBullet", HCleanBurn = "ISCleanBurn",
    HApplyComfrey = "ISComfreyCataplasm", HApplyGarlic = "ISGarlicCataplasm", HApplyPlantain = "ISPlantainCataplasm",
    HReplaceBandage = "ISApplyBandage"}
local childSources = {ISApplyBandage = 2803499221, ISDisinfect = 3741707122, ISStitch = 2530457766,
    ISSplint = 2375527233, ISRemoveGlass = 3698948194, ISRemoveBullet = 3894979839, ISCleanBurn = 3569789416,
    ISComfreyCataplasm = 2138588477, ISGarlicCataplasm = 3991409036, ISPlantainCataplasm = 2742789526}

local function captureChild(name)
    local class = _G[name]
    if not class or class.Type ~= name then return end
    local snapshot = {class = class, methods = {}, base = {}}
    for key, value in pairs(class) do
        if type(value) == "function" then
            if not (key == "derive" and value == ISBaseTimedAction.derive) and not nativeClosure(value, name .. ".lua") then return end
            snapshot.methods[key] = value
        end
    end
    -- The constructor must belong to this child, not resolve through its base.
    if type(snapshot.methods.new) ~= "function" then return end
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
    for key, value in pairs(snapshot.methods) do if Proof.own(snapshot.class, key) ~= value then return false end end
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

local function boundDoctor(handler) return handler.toolkitHealthActor end
local function miniMatches()
    if not miniBindings or not TwisTonFire_MHP or TwisTonFire_MHP.MiniHealthTreatment ~= miniPanel then return false end
    for name, callback in pairs(miniBindings) do if miniPanel[name] ~= callback then return false end end
    return true
end
local function inventoryHelpersMatch()
    local saved = inventoryBindings
    if not saved or ISInventoryPaneContextMenu ~= saved.menu or luautils ~= saved.utils
        or ISInventoryTransferUtil ~= saved.transfer or getSpecificPlayer ~= saved.player then return false end
    for name, callback in pairs(saved.menuMethods) do if saved.menu[name] ~= callback then return false end end
    for name, callback in pairs(saved.utilsMethods) do if saved.utils[name] ~= callback then return false end end
    for name, callback in pairs(saved.transferMethods) do if saved.transfer[name] ~= callback then return false end end
    if saved.cartVerified or ISInventoryTransferAction.new ~= saved.constructor then
        return saved.carts ~= nil and Toolkit.ActionQueueCarts == saved.carts and saved.carts.isTransferConstructor == saved.cartConstructor
            and saved.cartConstructor(saved.constructor) == true and saved.cartConstructor(ISInventoryTransferAction.new) == true
    end
    return true
end
local function replaceHelpersMatch()
    return miniReplace and MHP_SB_IsReplaceBandageEnabled == miniReplace.enabled and MHP_SB_GetBool == miniReplace.boolean
        and inventoryHelpersMatch()
end
local function patientFor(handler)
    return handler.getPatient == boundDoctor and handler.toolkitHealthActor or handler.panel.character
end
local function doctorFor(handler)
    return handler.getDoctor == boundDoctor and handler.toolkitHealthActor or handler.panel.otherPlayer or handler.panel.character
end
local function capture(handler, miniActor)
    if not handler or handler.panel ~= trustedPanel or not kinds[handler.Type] then return end
    local class = getmetatable(handler)
    if handlers[class] then
        if not miniActor then return end
    end
    local filename = miniActor and "MiniHealthTreatments.lua" or "ISHealthPanel.lua"
    for _, name in ipairs({"new", "perform", "isValid", "checkItems", "getDoctor", "getPatient", "toPlayerInventory"}) do
        if not nativeClosure(handler[name], filename) then return end
    end
    local methods, prototypes, parent = {}, {}, class
    while parent and parent ~= ISBaseObject do
        local own = {}
        for key, value in pairs(parent) do
            if type(value) == "function" then
                if not (key == "derive" and value == ISBaseObject.derive) and not nativeClosure(value, filename) then return end
                own[key] = value
                if methods[key] == nil then methods[key] = value end
            end
        end
        prototypes[parent] = own
        local meta = getmetatable(parent)
        parent = meta and type(meta.__index) == "table" and meta.__index or nil
    end
    if parent ~= ISBaseObject or handler.derive ~= ISBaseObject.derive then return end
    handlers[class] = {methods = methods, prototypes = prototypes, kind = handler.Type, actionClass = handler.actionClass,
        itemType = handler.itemType, mini = miniActor ~= nil}
    if miniActor then
        handler.toolkitHealthActor = miniActor
        handler.getDoctor, handler.getPatient = boundDoctor, boundDoctor
    end
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

local function bodyResources(patient, body)
    local result = {items = {}, itemTypes = {}, targets = {[body] = true}, outputTypes = {},
        cancelWaiting = true, interrupt = "finish-step"}
    -- Native body updates add/remove hidden clothing in the patient's inventory.
    local part, gender = body:getType(), patient:getCharacterGender()
    local bandage = part:getBandageModel()
    for _, kind in pairs({bandage, bandage and bandage ~= "" and bandage .. "_Blood" or nil, part:getBiteWoundModel(gender),
        part:getScratchWoundModel(gender), part:getCutWoundModel(gender)}) do
        if kind ~= "" then result.itemTypes[kind], result.outputTypes[kind] = true, true end
    end
    return result
end

local function handlerContract(action)
    for name, callback in pairs(bindings) do if ISHealthPanel[name] ~= callback then return end end
    for name, callback in pairs(actionBindings) do if HealthPanelAction[name] ~= callback then return end end
    local handler = action.handler
    local snapshot = handler and handlers[getmetatable(handler)]
    if not snapshot or handler.Type ~= snapshot.kind or handler.actionClass ~= snapshot.actionClass
        or handler.itemType ~= snapshot.itemType or not handler.panel or not handler.bodyPart then return end
    local patient, doctor = patientFor(handler), doctorFor(handler)
    if not instanceof(patient, "IsoPlayer") or not instanceof(handler.bodyPart, "BodyPart") then return end
    if snapshot.mini then
        if not miniMatches() or not handler.toolkitHealthActor or handler.panel ~= miniPanel
            or handler.getDoctor ~= boundDoctor or handler.getPatient ~= boundDoctor then return end
    end
    if handler.Type == "HReplaceBandage" and (not snapshot.mini or not replaceHelpersMatch()) then return end
    if not childMatches(handler.Type) then return end
    if handler.actionClass and handler.actionClass ~= children[childNames[handler.Type]].class then return end
    for name, method in pairs(snapshot.methods) do
        if not (snapshot.mini and (name == "getDoctor" or name == "getPatient")) and handler[name] ~= method then return end
    end
    -- Native leaf handlers call parent methods explicitly, even when a leaf shadows the same name.
    for class, methods in pairs(snapshot.prototypes) do
        for name, method in pairs(methods) do if Proof.own(class, name) ~= method then return end end
    end
    if doctor ~= action.character then return end
    if not snapshot.mini then
        for _, name in ipairs({"getDoctor", "checkContainerItems"}) do
            if handler.panel[name] ~= panelHelpers[name] then return end
        end
    end
    local inputs = {}
    for i = 1, kinds[handler.Type] do
        local value = action.args and action.args[i]
        if value == nil and handler.Type == "HSplint" and i == 1 then
            -- A ready-made splint supplies only the second argument.
        elseif type(value) ~= "string" then return
        elseif value ~= "Hands" then inputs[value] = true end
    end
    local result = bodyResources(patient, handler.bodyPart)
    result.dynamicInputs = inputs
    result.unknownOutputs = handler.Type == "HRemoveBandage" or handler.Type == "HRemoveSplint" or handler.Type == "HReplaceBandage"
    local dropped = droppedSupplies[handler]
    if snapshot.dropped then
        if not dropped or dropped.panel ~= handler.panel or dropped.bodyPart ~= handler.bodyPart
            or dropped.actor ~= doctor or dropped.patient ~= patient
            or (dropped[1] and dropped[1]:getFullType() or nil) ~= action.args[1]
            or dropped[2]:getFullType() ~= action.args[2] then return end
        for _, item in pairs({dropped[1], dropped[2]}) do result.items[item:getID()] = true end
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
        or patientFor(saved.handler) ~= saved.patient or doctorFor(saved.handler) ~= saved.character then return false end
    for i = 1, 8 do if not action.args or action.args[i] ~= saved.args[i] then return false end end
    return true
end
local function originMatches(saved)
    if saved.direct and (not inventoryHelpersMatch() or inventoryBindings.player(saved.playerNum) ~= saved.character) then return false end
    return not saved.origin or parentMatches(saved.origin, saved) and handlerContract(saved.origin) ~= nil
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
    if not originMatches(saved) then return end
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

function Health.patient(action)
    local saved = records[action]
    return saved and saved.patient
end

local function clinicalAvailable(saved)
    local body, kind = saved.bodyPart, saved.kind
    if saved.direct then return true end -- The native inventory producer also permits covering an already bandaged part.
    if kind == "HReplaceBandage" then return miniReplace.enabled() and body:bandaged() and body:getBandageLife() <= 0 end
    if saved.replacement and kind == "HApplyBandage" then return not body:bandaged() end
    if kind == "HRemoveBandage" then return body:bandaged() end
    if kind == "HRemoveStitch" then return body:stitched() end
    if kind == "HRemoveSplint" then return body:getSplintFactor() > 0 end
    if kind == "HSplint" then return body:HasInjury() and not body:stitched() and body:getFractureTime() > 0 and body:getSplintFactor() <= 0 end
    if saved.origin and handlers[getmetatable(saved.origin.handler)].mini and not saved.origin.handler:isInjured() then return false end
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
    if saved.replacement and saved.kind == "HRemoveBandage" then
        local item, transfer = saved.replacement.item, saved.replacement.transfer
        local container = item:getContainer()
        if not container or container:getItemById(item:getID()) ~= item then return false end
        if container == inventory then return true end
        local preparation = transfer and records[transfer]
        return preparation and container == preparation.source and preparationMatches(transfer, preparation) and transfer:isValid() or false
    end
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
        if not originMatches(saved) then return false end
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
    if not originMatches(saved) then return false end
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
    if not originMatches(saved) then return false end
    if saved.preparation then return preparationMatches(action, saved) end
    -- A server refusal can stop a child before its local inventory/body snapshot reflects the reason.
    return childMatches(saved.kind, action)
end

local function captureExpanded(action, saved, selected, before)
    local queue = ISTimedActionQueue.queues[action.character]
    if not queue then return end
    local replacement, added
    if saved.kind == "HReplaceBandage" then
        added = {}
        for _, child in ipairs(queue.queue) do if not before[child] then added[#added + 1] = child end end
        local remove, apply = added[1], added[#added]
        if (#added ~= 2 and #added ~= 3) or not childMatches("HRemoveBandage", remove)
            or not childMatches("HApplyBandage", apply) or remove.doIt ~= false or remove.item ~= nil
            or apply.doIt ~= true or apply.item ~= selected[1] then return end
        local transfer = #added == 3 and added[2] or nil
        if transfer and (not Toolkit.ActionQueueOperations.isTransfer(transfer) or not Toolkit.ActionQueuePolicy.inspect(transfer)
            or transfer.item ~= selected[1] or transfer.srcContainer ~= selected[1]:getContainer()
            or transfer.destContainer ~= saved.character:getInventory()) then return end
        replacement = {item = selected[1], transfer = transfer}
    end
    for _, child in ipairs(added or queue.queue) do
        if not before[child] and child.toolkitQueueOperation == action.toolkitQueueOperation
            and child.character == saved.character and Toolkit.ActionQueueOperations.isTransfer(child)
            and Toolkit.ActionQueuePolicy.inspect(child) then
            records[child] = {preparation = true, kind = saved.kind, character = saved.character, patient = saved.patient,
                origin = action, handler = saved.handler, panel = saved.panel, args = saved.args,
                bodyPart = saved.bodyPart, patientX = saved.patientX, patientY = saved.patientY,
                doctorX = saved.doctorX, doctorY = saved.doctorY, token = action.toolkitQueueOperation,
                item = child.item, source = child.srcContainer, destination = child.destContainer}
        end
        if not before[child] and child.toolkitQueueOperation == action.toolkitQueueOperation
            and getmetatable(child) == children[childNames[saved.kind]].class
            and child.character == saved.character and child.otherPlayer == saved.patient and child.bodyPart == saved.bodyPart then
            local kind = replacement and (child.doIt and "HApplyBandage" or "HRemoveBandage") or saved.kind
            local fields = {item = false, alcohol = false, bandage = false, rippedSheet = false, plank = false}
            if saved.kind == "HDisinfect" then fields.alcohol = selected[1]
            elseif saved.kind == "HCleanBurn" then fields.bandage = selected[1]
            elseif saved.kind == "HStitch" then fields.item = selected[2]
            elseif saved.kind == "HSplint" then fields.rippedSheet, fields.plank = selected[1] or false, selected[2]
            elseif kind ~= "HRemoveGlass" and kind ~= "HRemoveBullet" and kind ~= "HRemoveBandage" then fields.item = selected[1] or false end
            local record = {kind = kind, character = saved.character, patient = saved.patient, bodyPart = saved.bodyPart,
                origin = action, handler = saved.handler, panel = saved.panel, args = saved.args,
                patientX = saved.patientX, patientY = saved.patientY, doctorX = saved.doctorX, doctorY = saved.doctorY,
                token = action.toolkitQueueOperation, selected = selected, fields = fields, contract = handlerContract(action),
                doIt = child.doIt, handPain = child.handPain, replacement = replacement}
            if saved.kind == "HDisinfect" or saved.kind == "HStitch" or saved.kind == "HRemoveStitch"
                or saved.kind == "HSplint" or saved.kind == "HRemoveSplint" or saved.kind == "HRemoveGlass"
                or saved.kind == "HRemoveBullet" then record.doctor = saved.character end
            if saved.kind == "HApplyBandage" or saved.kind == "HStitch" or saved.kind == "HSplint" then record.doIt = true
            elseif saved.kind == "HRemoveBandage" or saved.kind == "HRemoveStitch" or saved.kind == "HRemoveSplint" then record.doIt = false end
            if saved.kind == "HRemoveGlass" then
                record.handPain = action.args[1] == "Hands"
                if handlers[getmetatable(action.handler)].mini and not record.handPain then record.handPain = nil end
            end
            records[child] = record
            if not childMatchesRecord(child, record) then records[child] = nil end
        end
    end
end

local DropSplint = {Type = "HSplint"}
DropSplint.__index = DropSplint
local function splintAvailable(body)
    local part = body:getType()
    return part ~= BodyPartType.Head and part ~= BodyPartType.Torso_Upper and part ~= BodyPartType.Torso_Lower
        and body:HasInjury() and not body:stitched() and body:getFractureTime() > 0 and body:getSplintFactor() <= 0
end
function DropSplint:getDoctor() return self.panel.otherPlayer or self.panel.character end
function DropSplint:getPatient() return self.panel.character end
function DropSplint:checkItem(item)
    local selected = droppedSupplies[self]
    if selected and (item == selected[1] or item == selected[2]) then
        for _, existing in ipairs(self.items.selected) do if existing == item then return end end
        self.items.selected[#self.items.selected + 1] = item
    end
end
function DropSplint:checkItems()
    self.items.selected = {}
    self.panel:checkItems({self})
end
function DropSplint:isValid(rippedSheetType, plankType)
    local selected = droppedSupplies[self]
    if not selected or selected.panel ~= self.panel or selected.bodyPart ~= self.bodyPart
        or selected.actor ~= self:getDoctor() or selected.patient ~= self:getPatient() or not splintAvailable(self.bodyPart)
        or (selected[1] and selected[1]:getFullType() or nil) ~= rippedSheetType
        or selected[2]:getFullType() ~= plankType then return false end
    self:checkItems()
    return #self.items.selected == (selected[1] and 2 or 1)
end
function DropSplint:toPlayerInventory(item, previousAction)
    local doctor = self:getDoctor()
    if item:getContainer() ~= doctor:getInventory() then
        local action = ISInventoryTransferUtil.newInventoryTransferAction(doctor, item, item:getContainer(), doctor:getInventory())
        ISTimedActionQueue.addAfter(previousAction, action)
        self.panel.actions = self.panel.actions or {}
        self.panel.actions[action] = self.bodyPart
        return action
    end
    return previousAction
end
function DropSplint:perform(previousAction)
    local selected = droppedSupplies[self]
    if selected[1] then previousAction = self:toPlayerInventory(selected[1], previousAction) end
    previousAction = self:toPlayerInventory(selected[2], previousAction)
    ISTimedActionQueue.addAfter(previousAction, ISSplint:new(self:getDoctor(), self:getPatient(), selected[1], selected[2], self.bodyPart, true))
end
local function dropSplint(panel, body, items)
    if not helpersMatch() or not childMatches("HSplint") or not instanceof(body, "BodyPart") or not splintAvailable(body)
        or not instanceof(panel.character, "IsoPlayer") or not instanceof(panel.otherPlayer or panel.character, "IsoPlayer") then return end
    local splint, plank, sheet
    for _, item in ipairs(items) do
        local kind = item:getType()
        if kind == "Splint" and not splint then splint = item end
        if (kind == "Plank" or kind == "TreeBranch2" or kind == "WoodenStick2" or kind == "TreeBranch" or kind == "WoodenStick") and not plank then plank = item end
        if kind == "RippedSheets" and not sheet then sheet = item end
    end
    if not splint and not (plank and sheet) then return end
    local handler = setmetatable({panel = panel, bodyPart = body, items = {selected = {}}}, DropSplint)
    local selected = {sheet, splint or plank, panel = panel, bodyPart = body,
        actor = panel.otherPlayer or panel.character, patient = panel.character}
    -- A drop keeps its exact supplies; an identical item elsewhere must not replace a lost one.
    if splint then selected[1] = nil end
    droppedSupplies[handler] = selected
    handler:checkItems()
    if handler:isValid(selected[1] and selected[1]:getFullType(), selected[2]:getFullType()) then
        ISTimedActionQueue.add(HealthPanelAction:new(selected.actor, handler,
            selected[1] and selected[1]:getFullType(), selected[2]:getFullType()))
    else droppedSupplies[handler] = nil end
end

function Health.installMiniHealth()
    if miniBindings or not TwisTonFire_MHP or not actionBindings.new or actionBindings.new ~= HealthPanelAction.new then return end
    local panel = TwisTonFire_MHP.MiniHealthTreatment
    if not panel or not nativeSource("media/lua/client/MiniHealthPlus/MiniHealthTreatments.lua", 59501056, "MiniHealthPlus") then return end
    for _, name in ipairs({"checkItems", "checkContainerItems", "doBodyPartContextMenu", "_MiniHealthOwn_doBodyPartContextMenu", "restoreOwnContextMenu"}) do
        if not nativeClosure(panel[name], "MiniHealthTreatments.lua") then return end
    end
    miniPanel, miniBindings = panel, {}
    if nativeSource("media/lua/shared/MHP_Sandbox.lua", 2138062714, "MiniHealthPlus")
        and nativeClosure(MHP_SB_IsReplaceBandageEnabled, "MHP_Sandbox.lua") and nativeClosure(MHP_SB_GetBool, "MHP_Sandbox.lua") then
        miniReplace = {enabled = MHP_SB_IsReplaceBandageEnabled, boolean = MHP_SB_GetBool}
    end
    local check = panel.checkItems
    panel.checkItems = function(current, list)
        if trustedPanel == current and miniMatches() then
            local actor = TwisTonFire_MHP.handle and TwisTonFire_MHP.handle.player
            if instanceof(actor, "IsoPlayer") then for _, handler in ipairs(list) do capture(handler, actor) end end
        end
        return check(current, list)
    end
    local menu = panel.doBodyPartContextMenu
    panel.doBodyPartContextMenu = function(current, ...) return producer(menu, current, ...) end
    -- The mod deliberately restores this alias when toggling its menu mode.
    panel._MiniHealthOwn_doBodyPartContextMenu = panel.doBodyPartContextMenu
    for _, name in ipairs({"checkItems", "checkContainerItems", "doBodyPartContextMenu", "_MiniHealthOwn_doBodyPartContextMenu", "restoreOwnContextMenu"}) do
        miniBindings[name] = panel[name]
    end
end

local function installInventoryProducer()
    local menu, utils, transfer = ISInventoryPaneContextMenu, luautils, ISInventoryTransferUtil
    local cleanUI = nativeSource("media/lua/client/ISUI/ISInventoryPaneContextMenu.lua", 1953753890)
    if not (cleanUI or nativeSource("media/lua/client/ISUI/ISInventoryPaneContextMenu.lua", 4293448388))
        or not nativeSource("media/lua/shared/luautils.lua", 1091751327)
        or not nativeSource("media/lua/shared/TimedActions/ISInventoryTransferUtil.lua", 1281392797)
        or type(getSpecificPlayer) ~= "function" then return end
    local saved = {menu = menu, utils = utils, transfer = transfer, player = getSpecificPlayer,
        menuMethods = {}, utilsMethods = {}, transferMethods = {}, constructor = ISInventoryTransferAction.new}
    local carts = Toolkit.ActionQueueCarts
    if carts and type(carts.isTransferConstructor) == "function" then
        saved.carts, saved.cartConstructor = carts, carts.isTransferConstructor
        saved.cartVerified = saved.cartConstructor(saved.constructor) == true
    end
    if not saved.cartVerified and not nativeClosure(saved.constructor, "ISInventoryTransferAction.lua") then return end
    for _, name in ipairs({"applyBandage", "transferIfNeeded"}) do
        if not nativeClosure(menu[name], "ISInventoryPaneContextMenu.lua") then return end
        saved.menuMethods[name] = menu[name]
    end
    if cleanUI then
        for _, name in ipairs({"cleanUIResetStaleTimedActionRetrigger", "cleanUILogTimedActionFix"}) do
            if not nativeClosure(menu[name], "ISInventoryPaneContextMenu.lua") then return end
            saved.menuMethods[name] = menu[name]
        end
    end
    for _, name in ipairs({"haveToBeTransfered", "walkToContainer"}) do
        local callback = utils[name]
        local approach = Toolkit.ActionQueueApproach
        local original = approach and approach.nativeHelper(utils, name, callback) or callback
        if not nativeClosure(original, "luautils.lua") then return end
        saved.utilsMethods[name] = callback
    end
    for _, name in ipairs({"newInventoryTransferAction", "isPlayerCharacter", "isCharacterGrabbingCorpseItem", "isPlayerGrabbingCorpseItem"}) do
        if not nativeClosure(transfer[name], "ISInventoryTransferUtil.lua") then return end
        saved.transferMethods[name] = transfer[name]
    end
    inventoryBindings = saved
    local original = menu.applyBandage
    menu.applyBandage = function(item, bodyPart, player)
        local character = saved.player(player)
        local source = instanceof(item, "InventoryItem") and item:getContainer()
        local eligible = inventoryHelpersMatch() and helpersMatch() and childMatches("HApplyBandage")
            and instanceof(character, "IsoPlayer") and instanceof(bodyPart, "BodyPart")
            and instanceof(item, "InventoryItem") and item:isCanBandage()
            and character:getBodyDamage():getBodyPart(bodyPart:getType()) == bodyPart
            and Toolkit.ActionQueuePolicy.isCarriedContainer(source, character)
        if not eligible then return original(item, bodyPart, player) end
        return Toolkit.ActionQueueOperations.run(function()
            local queue, before = ISTimedActionQueue.queues[character], {}
            if queue then for _, action in ipairs(queue.queue) do before[action] = true end end
            local result = pack(original(item, bodyPart, player))
            queue = ISTimedActionQueue.queues[character]
            if not queue or not inventoryHelpersMatch() then return unpack(result, 1, result.n) end
            local added = {}
            for _, action in ipairs(queue.queue) do if not before[action] then added[#added + 1] = action end end
            local child = added[#added]
            if #added == 3 then
                local preparation, approach = added[1], Toolkit.ActionQueueApproach
                if not approach or not approach.isContainer(preparation, source, character)
                    or preparation.toolkitQueueOperation ~= child.toolkitQueueOperation then
                    return unpack(result, 1, result.n)
                end
                -- Retain preparation in the queue; only the body shape below is
                -- the verified transfer + bandage contract.
                table.remove(added, 1)
            end
            if (#added ~= 1 and #added ~= 2) or not childMatches("HApplyBandage", child)
                or child.character ~= character or child.otherPlayer ~= character or child.bodyPart ~= bodyPart
                or child.item ~= item or child.doIt ~= true then return unpack(result, 1, result.n) end
            local pickup = #added == 2 and added[1] or nil
            if pickup and (not Toolkit.ActionQueueOperations.isTransfer(pickup) or not Toolkit.ActionQueuePolicy.inspect(pickup)
                or pickup.character ~= character or pickup.item ~= item or pickup.srcContainer ~= source
                or pickup.destContainer ~= character:getInventory() or pickup.toolkitQueueOperation ~= child.toolkitQueueOperation) then
                return unpack(result, 1, result.n)
            end
            if (source ~= character:getInventory()) ~= (pickup ~= nil) then return unpack(result, 1, result.n) end
            local record = {kind = "HApplyBandage", character = character, patient = character, bodyPart = bodyPart,
                direct = true, playerNum = player, token = child.toolkitQueueOperation,
                doctorX = character:getX(), doctorY = character:getY(), patientX = character:getX(), patientY = character:getY(),
                selected = {item}, fields = {item = item, alcohol = false, bandage = false, rippedSheet = false, plank = false},
                doIt = true, contract = bodyResources(character, bodyPart)}
            if childMatchesRecord(child, record) then
                records[child] = record
                if pickup then
                    pickup.toolkitQueueLinked, child.toolkitQueueLinked = true, true
                    records[pickup] = {preparation = true, direct = true, playerNum = player, kind = record.kind,
                        character = character, patient = character, bodyPart = bodyPart, token = record.token,
                        doctorX = record.doctorX, doctorY = record.doctorY, patientX = record.patientX, patientY = record.patientY,
                        item = item, source = source, destination = character:getInventory()}
                end
            end
            return unpack(result, 1, result.n)
        end)
    end
    saved.menuMethods.applyBandage = menu.applyBandage
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
    local ownMethods = {}
    for name, callback in pairs(DropSplint) do if type(callback) == "function" then ownMethods[name] = callback end end
    handlers[DropSplint] = {kind = "HSplint", methods = ownMethods, prototypes = {[DropSplint] = ownMethods}, dropped = true}
    for _, name in ipairs({"doBodyPartContextMenu", "dropItemsOnBodyPart"}) do
        local callback = ISHealthPanel[name]
        if callback then
            if name == "dropItemsOnBodyPart" then
                ISHealthPanel[name] = function(panel, body, items)
                    local previous, attempt = dropAttempt, {panel = panel}
                    dropAttempt = attempt
                    local result = pack(pcall(producer, callback, panel, body, items))
                    dropAttempt = previous
                    if not result[1] then error(result[2], 0) end
                    if not attempt.selected then producer(dropSplint, panel, body, items) end
                    return unpack(result, 2, result.n)
                end
            else ISHealthPanel[name] = function(panel, ...) return producer(callback, panel, ...) end end
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
        if dropAttempt and handler and handler.panel == dropAttempt.panel then dropAttempt.selected = true end
        if trustedPanel then capture(handler) end
        local action = new(self, character, handler, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
        if handlerContract(action) and instanceof(character, "IsoPlayer") and instanceof(patientFor(handler), "IsoPlayer")
            and instanceof(handler.bodyPart, "BodyPart") then
            local patient = patientFor(handler)
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
            local saved = records[current]
            local selected = saved and Health.inspect(current) and selectedItems(current)
            local before
            if selected then
                before = {}
                local queue = ISTimedActionQueue.queues[current.character]
                if queue then for _, member in ipairs(queue.queue) do before[member] = true end end
            end
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
            or child.otherPlayer ~= patientFor(parent.handler) or child.character ~= parent.character
            or child.onStartFunc or child.onCompleteFunc or child.onCancelFunc or child.retriggerLastAction then return false end
        for name, method in pairs(methods) do if (child[name] or false) ~= method then return false end end
        return true
    end, true)
    Events.OnTick.Add(function()
        -- Kahlua ignores weak tables; keep proofs only while their actions remain queued.
        local queues, live
        for action, saved in pairs(records) do
            local queue = ISTimedActionQueue.queues[action.character]
            if not queue then records[action] = nil
            else
                queues = queues or {}
                local group = queues[queue]
                if not group then group = {pending = {}, remaining = 0}; queues[queue] = group end
                group.pending[action], group.remaining = saved, group.remaining + 1
            end
        end
        if queues then
            for queue, group in pairs(queues) do
                -- A short tracked prefix must not scan an unrelated long tail.
                for _, action in ipairs(queue.queue) do
                    local saved = group.pending[action]
                    if saved then
                        group.pending[action], group.remaining = nil, group.remaining - 1
                        live = live or {}
                        if saved.handler then live[saved.handler] = true end
                        if saved.origin then live[saved.origin.handler] = true end
                        if group.remaining == 0 then break end
                    end
                end
                for action in pairs(group.pending) do records[action] = nil end
            end
        end
        for handler in pairs(droppedSupplies) do if not live or not live[handler] then droppedSupplies[handler] = nil end end
    end)
    if Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(function() records, droppedSupplies = {}, {} end) end
    installInventoryProducer()
    Health.installMiniHealth()
    if Events.OnGameBoot then Events.OnGameBoot.Add(Health.installMiniHealth) end
end

Health.install()
return Health
