require "TimedActions/ISWaitWhileGettingUp"
local Toolkit = PZSurvivorToolkit
local Ops = Toolkit.ActionQueueOperations
local Proof = require "PZSurvivorToolkit/SourceProof"
local Native = {}
Toolkit.ActionQueueNativeContinuation = Native
local class, base = ISWaitWhileGettingUp, ISBaseTimedAction
local original = class.perform
local boundary = Ops.performNativeContinuation
local methods, helpers = {}, {}
local trusted = Proof.matches("media/lua/shared/TimedActions/ISWaitWhileGettingUp.lua", 1725489935)
    and Proof.matches("media/lua/shared/TimedActions/ISBaseTimedAction.lua", 3104185167, nil, true)
for name, callback in pairs(class) do
    if type(callback) == "function" and name ~= "derive" then
        methods[name] = callback
        trusted = trusted and Proof.closure(callback, "ISWaitWhileGettingUp.lua")
    end
end
for _, name in ipairs({"perform", "beginAddingActions", "endAddingActions"}) do
    helpers[name] = base[name]
    trusted = trusted and Proof.closure(base[name], "ISBaseTimedAction.lua")
end
local wrapper
local function unchanged()
    if not trusted or Toolkit.ActionQueueNativeContinuation ~= Native or Toolkit.ActionQueueOperations ~= Ops
        or Ops.performNativeContinuation ~= boundary or ISWaitWhileGettingUp ~= class or ISBaseTimedAction ~= base then return false end
    for name, callback in pairs(methods) do
        if class[name] ~= (name == "perform" and wrapper or callback) then return false end
    end
    for name, callback in pairs(helpers) do if base[name] ~= callback then return false end end
    return true
end
function Native.isCallback(name, callback)
    return name == "perform" and callback == wrapper and unchanged()
end
function Native.matches(action)
    if not unchanged() or getmetatable(action) ~= class or action.Type ~= class.Type
        or type(action.onCompleteFunc) ~= "function" or type(action.onCompleteArgs) ~= "table" then return false end
    for name, callback in pairs(methods) do
        if action[name] ~= (name == "perform" and wrapper or callback) then return false end
    end
    for name, callback in pairs(helpers) do
        if name ~= "perform" and action[name] ~= callback then return false end
    end
    return true
end
wrapper = function(action, ...)
    if Native.matches(action) then return boundary(action, original, ...) end
    return original(action, ...)
end
function Native.install()
    if class.perform == wrapper then return unchanged() end
    if not trusted or class.perform ~= original then return false end
    class.perform = wrapper
    if unchanged() then return true end
    class.perform = original
    return false
end
Native.install()
return Native
