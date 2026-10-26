-- WMI temporarily replaces the class water rule, but skips restoration when
-- native completion throws. Keep its completion/effects and close that scope.
local Rule = {}
local Proof = require "PZSurvivorToolkit/SourceProof"
local matches, closure = Proof.matches, Proof.closure
local owner, methods, replacement
local nativeBase, nativeObject, nativeNew, nativeDerive
local lastInstallReason = "not-installed"
local function ownMember(value, key)
    -- PZ's Kahlua rawget also searches metatables. pairs iterates only the
    -- table's delegate, so it distinguishes owned members from inherited ones.
    for name, member in pairs(value) do if name == key then return member end end
end
local function named(prefix, name)
    return prefix .. (type(name) == "string" and name:sub(1, 64) or type(name))
end
local function refused(reason)
    lastInstallReason = reason
    return false, reason
end
local function hierarchy(class, base, object, constructor, derive)
    if type(class) ~= "table" then return false, "hierarchy:wash-not-table" end
    if type(base) ~= "table" or ISBaseTimedAction ~= base then return false, "hierarchy:base-identity" end
    if type(object) ~= "table" or ISBaseObject ~= object then return false, "hierarchy:object-identity" end
    if getmetatable(class) ~= base then return false, "hierarchy:wash-metatable" end
    if ownMember(class, "SuperType") ~= base then return false, "hierarchy:wash-superclass" end
    if getmetatable(base) ~= object then return false, "hierarchy:base-metatable" end
    if ownMember(base, "SuperType") ~= object then return false, "hierarchy:base-superclass" end
    if getmetatable(object) ~= nil then return false, "hierarchy:object-metatable" end
    if ownMember(base, "Type") ~= "ISBaseTimedAction" then return false, "hierarchy:base-type" end
    if ownMember(object, "Type") ~= "ISBaseObject" then return false, "hierarchy:object-type" end
    if ownMember(class, "Type") ~= "ISWashClothing" then return false, "hierarchy:wash-type" end
    if ownMember(base, "__index") ~= base then return false, "hierarchy:base-index" end
    if ownMember(object, "__index") ~= object then return false, "hierarchy:object-index" end
    if ownMember(base, "new") ~= constructor then return false, "hierarchy:constructor-changed" end
    if ownMember(object, "derive") ~= derive then return false, "hierarchy:derive-changed" end
    -- Observing source loaders can restore an inherited native callback into
    -- this own slot. Its exact reviewed identity, rather than its slot, matters.
    local baseDerive = ownMember(base, "derive")
    if baseDerive ~= nil and baseDerive ~= derive then return false, "hierarchy:base-own-derive" end
    if ownMember(class, "derive") ~= nil then return false, "hierarchy:wash-own-derive" end
    -- Native derive sets only its parent's index. Native base-action new sets
    -- this class's own index on first construction, after shared startup.
    local index = ownMember(class, "__index")
    if index ~= nil and index ~= class then return false, "hierarchy:wash-index" end
    return true
end
local function unchanged()
    if not owner then return false, lastInstallReason end
    if ISWashClothing ~= owner then return false, "class-identity-changed" end
    if owner._wmiPatchedReturnContainer ~= true then return false, "wmi-marker-changed" end
    if Proof.matches ~= matches or Proof.closure ~= closure then return false, "proof-api-changed" end
    local valid, reason = hierarchy(owner, nativeBase, nativeObject, nativeNew, nativeDerive)
    if not valid then return false, reason end
    for name, callback in pairs(methods) do
        if owner[name] ~= (name == "complete" and replacement or callback) then return false, named("method-changed:", name) end
    end
    for name, callback in pairs(owner) do
        if type(callback) == "function" and name ~= "derive" and not methods[name] then return false, named("method-added:", name) end
    end
    return true, "installed"
end

Rule.unchanged = unchanged

function Rule.matchesComplete(callback)
    if not owner then return false, lastInstallReason end
    if callback ~= replacement then return false, "completion-not-owned" end
    return unchanged()
end

function Rule.install()
    if owner then return unchanged() end
    if Proof.matches ~= matches or Proof.closure ~= closure then return refused("proof-api-changed") end
    if not getActivatedMods or not getActivatedMods():contains("WashFix") then return refused("mod-inactive") end
    if not matches("media/lua/shared/ISBaseObject.lua", 3350606722, nil, true) then return refused("source:ISBaseObject.lua") end
    if not matches("media/lua/shared/TimedActions/ISBaseTimedAction.lua", 3104185167, nil, true) then return refused("source:ISBaseTimedAction.lua") end
    if not matches("media/lua/shared/TimedActions/ISWashClothing.lua", 4034905648, nil, true) then return refused("source:ISWashClothing.lua") end
    if not matches("media/lua/shared/TimedActions/WMI_PatchWashClothing.lua", 2935848012, "WashFix", true) then return refused("source:WMI_PatchWashClothing.lua") end
    require "TimedActions/ISWashClothing"
    require "TimedActions/WMI_PatchWashClothing"
    local class = ISWashClothing
    local base, object = ISBaseTimedAction, ISBaseObject
    local constructor = type(base) == "table" and ownMember(base, "new")
    local derive = type(object) == "table" and ownMember(object, "derive")
    local valid, reason = hierarchy(class, base, object, constructor, derive)
    if not valid then return refused(reason) end
    if not closure(constructor, "ISBaseTimedAction.lua") then return refused("closure:ISBaseTimedAction.new") end
    if not closure(derive, "ISBaseObject.lua") then return refused("closure:ISBaseObject.derive") end
    if class._wmiPatchedReturnContainer ~= true then return refused("wmi-marker-missing") end
    local callbacks, seen = {}, {}
    for name, callback in pairs(class) do
        if type(callback) == "function" and name ~= "derive" then
            local file = (name == "complete" or name == "new" or name == "isValid")
                and "WMI_PatchWashClothing.lua" or "ISWashClothing.lua"
            if seen[callback] then return refused(named("method-aliased:", name)) end
            if not closure(callback, file) then return refused(named("method-source:", name)) end
            callbacks[name], seen[callback] = callback, true
        end
    end
    for _, name in ipairs({"new", "isValid", "complete", "GetRequiredWater", "GetRequiredSoap", "GetSoapRemaining",
        "update", "start", "stopSound", "stop", "useSoap", "perform", "getDuration", "animEvent"}) do
        if type(callbacks[name]) ~= "function" then return refused(named("method-missing:", name)) end
    end
    local original = callbacks.complete
    local function pack(...) return {n = select("#", ...), ...} end
    replacement = function(action, ...)
        -- WMI completion owns this temporary rule independently of observation
        -- wrappers on the instance's perform/start/stop lifecycle methods.
        if not unchanged() or type(action) ~= "table" or getmetatable(action) ~= owner
            or action.Type ~= owner.Type or action.complete ~= replacement
            or not tonumber(action.wmiWaterOverride) then return original(action, ...) end
        local water = owner.GetRequiredWater
        local result = pack(pcall(original, action, ...))
        if not result[1] then
            -- Only the reviewed WMI temporary closure belongs to this scope.
            -- A foreign callback's replacement must remain untouched.
            if ISWashClothing == owner and owner.GetRequiredWater ~= water and not seen[owner.GetRequiredWater]
                and closure(owner.GetRequiredWater, "WMI_PatchWashClothing.lua") then owner.GetRequiredWater = water end
            error(result[2], 0)
        end
        return unpack(result, 2, result.n)
    end
    owner, methods = class, callbacks
    nativeBase, nativeObject, nativeNew, nativeDerive = base, object, constructor, derive
    owner.complete = replacement
    return true, "installed"
end

Rule.install()
return Rule
