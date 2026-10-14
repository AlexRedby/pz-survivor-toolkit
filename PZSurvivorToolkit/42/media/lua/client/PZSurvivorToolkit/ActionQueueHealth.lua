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
local function nativeClosure(callback, filename)
    if type(getFilenameOfClosure) ~= "function" then return false end
    local ok, source = pcall(getFilenameOfClosure, callback)
    return ok and type(source) == "string" and source:gsub("\\", "/"):match("([^/]+)$") == (filename or "ISHealthPanel.lua")
end
local function nativeSource()
    if type(getGameFilesInput) ~= "function" then return false end
    local ok, reader = pcall(getGameFilesInput, "media/lua/client/XpSystem/ISUI/ISHealthPanel.lua")
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
    return valid and hash == 3948596941
end
local kinds = {HApplyBandage = 1, HDisinfect = 1, HStitch = 2, HSplint = 2, HRemoveGlass = 1,
    HRemoveBullet = 1, HCleanBurn = 1, HRemoveBandage = 0, HRemoveStitch = 0, HRemoveSplint = 0,
    HApplyComfrey = 1, HApplyGarlic = 1, HApplyPlantain = 1}
local childNames = {HApplyBandage = "ISApplyBandage", HRemoveBandage = "ISApplyBandage", HDisinfect = "ISDisinfect",
    HStitch = "ISStitch", HRemoveStitch = "ISStitch", HSplint = "ISSplint", HRemoveSplint = "ISSplint",
    HRemoveGlass = "ISRemoveGlass", HRemoveBullet = "ISRemoveBullet", HCleanBurn = "ISCleanBurn",
    HApplyComfrey = "ISComfreyCataplasm", HApplyGarlic = "ISGarlicCataplasm", HApplyPlantain = "ISPlantainCataplasm"}

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

local function childMatches(kind)
    local name = childNames[kind]
    local snapshot = children[name]
    if not snapshot or _G[name] ~= snapshot.class or snapshot.class.Type ~= name then return false end
    for key, value in pairs(snapshot.methods) do if rawget(snapshot.class, key) ~= value then return false end end
    for key, value in pairs(snapshot.base) do
        if ISBaseTimedAction[key] ~= value or not snapshot.methods[key] and snapshot.class[key] ~= value then return false end
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

function Health.inspect(action)
    for name, callback in pairs(bindings) do if ISHealthPanel[name] ~= callback then return end end
    for name, callback in pairs(actionBindings) do if HealthPanelAction[name] ~= callback then return end end
    local handler = action.handler
    local snapshot = handler and handlers[getmetatable(handler)]
    if not snapshot or handler.Type ~= snapshot.kind or handler.actionClass ~= snapshot.actionClass
        or handler.itemType ~= snapshot.itemType or not handler.panel or not handler.bodyPart then return end
    if not childMatches(handler.Type) then return end
    if handler.actionClass and handler.actionClass ~= children[childNames[handler.Type]].class then return end
    for name, method in pairs(snapshot.methods) do if handler[name] ~= method then return end end
    -- Native leaf handlers call parent methods explicitly, even when a leaf shadows the same name.
    for class, methods in pairs(snapshot.prototypes) do
        for name, method in pairs(methods) do if rawget(class, name) ~= method then return end end
    end
    if (handler.panel.otherPlayer or handler.panel.character) ~= action.character then return end
    local inputs = {}
    for i = 1, kinds[handler.Type] do
        local value = action.args and action.args[i]
        if value == nil and handler.Type == "HSplint" and i == 1 then
            -- A ready-made splint supplies only the second argument.
        elseif type(value) ~= "string" then return
        elseif value ~= "Hands" then inputs[value] = true end
    end
    return {items = {}, targets = {[handler.bodyPart] = true}, dynamicInputs = inputs,
        cancelWaiting = true, interrupt = "finish-step",
        unknownOutputs = handler.Type == "HRemoveBandage" or handler.Type == "HRemoveSplint"}
end

local installed
function Health.install()
    if installed or not ISHealthPanel or not HealthPanelAction then return end
    installed = true
    if not nativeSource() or not nativeClosure(HealthPanelAction.new) or not nativeClosure(HealthPanelAction.perform)
        or not nativeClosure(ISHealthPanel.checkItems) or not nativeClosure(ISHealthPanel.doBodyPartContextMenu)
        or not nativeClosure(ISHealthPanel.dropItemsOnBodyPart) then return end
    for _, name in pairs(childNames) do if not children[name] then children[name] = captureChild(name) end end
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
        return new(self, character, handler, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
    end
    actionBindings.new = HealthPanelAction.new
    local perform = HealthPanelAction.perform
    HealthPanelAction.perform = function(action, ...)
        return Toolkit.ActionQueueOperations.perform(action, perform, ...)
    end
    actionBindings.perform = HealthPanelAction.perform
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
end

Health.install()
return Health
