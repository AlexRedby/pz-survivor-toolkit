require "RadioCom/ISRadioAction"
local Proof = require "PZSurvivorToolkit/SourceProof"
local Adapters = {}
PZSurvivorToolkit.ActionQueueEditAdapters = Adapters

local class, base = ISRadioAction, ISBaseTimedAction
local methods = {}
local lifecycle = {"new", "begin", "create", "adjustMaxTime", "isValid", "isValidStart", "waitToStart", "start", "update",
    "stop", "perform", "complete", "getDuration", "serverStart", "serverStop", "animEvent", "forceComplete", "forceStop", "forceCancel", "invoke"}
for name, callback in pairs(class) do if type(callback) == "function" then methods[name] = callback end end
for _, name in ipairs(lifecycle) do methods[name] = class[name] or false end
local basePerform = base.perform
local modes = {SetVolume = true, MuteMicrophone = true, SetChannel = true,
    MuteVolume = true, UnMuteVolume = true, ToggleOnOff = true}
local controlModes = {SetVolume = true, MuteMicrophone = true, SetChannel = true,
    MuteVolume = true, UnMuteVolume = true, ToggleOnOff = true, TogglePlayMedia = true}
local sourceTrusted
local adoptedBase = {}

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

-- The queue installs these two inherited hooks after Policy requires this module.
-- Only the known native boundary may be adopted, once, by the owned queue wrapper.
function Adapters.adoptBase(name, previous, replacement)
    if (name ~= "begin" and name ~= "stop") or ISRadioAction ~= class or ISBaseTimedAction ~= base
        or methods[name] ~= previous or base[name] ~= replacement or class[name] ~= replacement
        or not Proof or not Proof.closure(previous, "ISBaseTimedAction.lua")
        or not Proof.closure(replacement, "ActionQueue.lua") then return false end
    methods[name] = replacement
    adoptedBase[name] = replacement
    return true
end

local function trusted(action)
    if not Proof or type(getFilenameOfClosure) ~= "function" or type(getGameFilesInput) ~= "function"
        or ISRadioAction ~= class or ISBaseTimedAction ~= base or getmetatable(action) ~= class or action.Type ~= class.Type
        or base.perform ~= basePerform or not Proof.closure(basePerform, "ISBaseTimedAction.lua") then return false end
    -- Disk changes cannot replace already loaded closures. Pin their source once,
    -- while keeping callback identities and closure origins live on every inspection.
    if sourceTrusted == nil then
        sourceTrusted = Proof.matches("media/lua/shared/RadioCom/ISRadioAction.lua", 60322390, nil, true)
            and Proof.matches("media/lua/shared/TimedActions/ISBaseTimedAction.lua", 3104185167, nil, true)
    end
    if not sourceTrusted then return false end
    for name, callback in pairs(class) do
        if type(callback) == "function" and (methods[name] ~= callback
            or name ~= "derive" and not Proof.closure(callback, "ISRadioAction.lua")) then return false end
    end
    for name, callback in pairs(methods) do
        if (action[name] or false) ~= callback then return false end
        if callback and not rawget(class, name)
            and not Proof.closure(callback, "ISBaseTimedAction.lua")
            and not (adoptedBase[name] == callback and Proof.closure(callback, "ActionQueue.lua")) then return false end
    end
    for name, callback in pairs(action) do
        if type(callback) == "function" and methods[name] ~= callback then return false end
    end
    return true
end

-- Callback provenance remains useful after native execution changes live validity.
-- Callers must separately validate the captured device binding and lifecycle ownership.
function Adapters.radioCallbacksTrusted(action)
    return type(action) == "table" and controlModes[action.mode] == true and trusted(action)
        and action.stopOnWalk == false and action.stopOnRun == true and action.ignoreHandsWounds == true
        and instanceof(action.character, "IsoPlayer") and not action.onStartFunc and not action.onCompleteFunc
        and not action.onCancelFunc and not action.onFailFunc and not action.additionalTest and not action.retriggerLastAction
end

-- This describes pending native controls only, without invoking validity or effects.
-- Playback and inventory/vehicle devices retain the conservative policy.
function Adapters.radio(action)
    if type(action) ~= "table" or not modes[action.mode] or not trusted(action)
        or action.action or action.started or action._isAddingActions
        or (type(action.toolkitQueueOperation) == "table" and action.toolkitQueueOperation.toolkitStarted)
        or action.maxTime ~= 30 or action.stopOnWalk ~= false or action.stopOnRun ~= true or action.ignoreHandsWounds ~= true
        or not instanceof(action.character, "IsoPlayer") or action.onStartFunc or action.onCompleteFunc or action.onCancelFunc
        or action.onFailFunc or action.additionalTest or action.retriggerLastAction then return end
    local device, data = action.device, action.deviceData
    if not (instanceof(device, "IsoTelevision") or instanceof(device, "IsoRadio")) or not instanceof(data, "DeviceData")
        or device:getObjectIndex() < 0 or not device:getSquare() or device:getDeviceData() ~= data
        or data:getParent() ~= device or not data:isIsoDevice() or data:isVehicleDevice() then return end
    local on, power, volume, channel, mic = data:getIsTurnedOn(), data:getPower(), data:getDeviceVolume(), data:getChannel(), data:getMicIsMuted()
    if type(on) ~= "boolean" or not finite(power) or not finite(volume) or volume < 0 or volume > 1
        or not finite(channel) or channel % 1 ~= 0 or type(mic) ~= "boolean" then return end
    local field, value, toggle
    local facts = {on = on, powered = power > 0, volume = volume, channel = channel, micMuted = mic}
    local requires = {{field = "on", equal = true}, {field = "powered", equal = true}}
    if action.mode == "ToggleOnOff" then
        -- Bound power projection to fixed mains-powered TVs. Native powerability
        -- also accounts for the world's electricity; battery charge is not a substitute.
        if not instanceof(device, "IsoTelevision") or data:getIsBatteryPowered() ~= false then return end
        local powerable = data:canBePoweredHere()
        if type(powerable) ~= "boolean" then return end
        facts.powerable = powerable
        requires = {{field = "powerable", equal = true}}
        field, toggle = "on", true
    elseif action.mode == "MuteVolume" then
        requires[#requires + 1] = {field = "volume", above = 0}
        field, value = "volume", 0
    elseif action.mode == "UnMuteVolume" then
        if not finite(action.secondaryItem) then return end
        requires[#requires + 1] = {field = "volume", max = 0}
        field, value = "volume", math.max(0, math.min(1, action.secondaryItem))
    elseif action.mode == "SetVolume" then
        if not finite(action.secondaryItem) then return end
        field, value = "volume", math.max(0, math.min(1, action.secondaryItem))
    elseif action.mode == "MuteMicrophone" then
        if type(action.secondaryItem) ~= "boolean" then return end
        field, value = "micMuted", action.secondaryItem
    else
        local minimum, maximum = data:getMinChannelRange(), data:getMaxChannelRange()
        if not finite(action.secondaryItem) or action.secondaryItem % 1 ~= 0
            or action.secondaryItem < -2147483648 or action.secondaryItem > 2147483647
            or not finite(minimum) or not finite(maximum) or minimum > maximum
            or action.secondaryItem < minimum or action.secondaryItem > maximum then return end
        field, value = "channel", action.secondaryItem
    end
    return {version = 1, complete = true, capacity = "unchanged", resources = {{domain = "device", key = device,
        facts = facts, requires = requires,
        effects = {{field = field, set = value, toggle = toggle}}, bounds = {volume = {min = 0, max = 1}}}}}
end

return Adapters
