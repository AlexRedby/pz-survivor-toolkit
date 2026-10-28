require "TimedActions/ISRackFirearm"
require "TimedActions/ISReloadWeaponAction"
local Proof = require "PZSurvivorToolkit/SourceProof"
local Toolkit = PZSurvivorToolkit
local Firearms = {}
Toolkit.ActionQueueFirearms = Firearms
local rack, reload, base = ISRackFirearm, ISReloadWeaponAction, ISBaseTimedAction
if type(rack) ~= "table" or type(reload) ~= "table" or type(base) ~= "table" then
    function Firearms.rack() end
    function Firearms.adoptBase() return false end
    return Firearms
end
local methods, ownMethods, baseMethods, helpers, adopted = {}, {}, {}, {}, {}
local globalNames = {"instanceItem", "sendAddItemToContainer", "syncHandWeaponFields", "emulateAnimEventOnce", "getClassSimpleName"}
local globals = {}
for _, name in ipairs(globalNames) do globals[name] = _G[name] end
for name, callback in pairs(rack) do
    if type(callback) == "function" then methods[name], ownMethods[name] = callback, true end
end
for name, callback in pairs(base) do
    if type(callback) == "function" and name ~= "derive" then
        baseMethods[name] = callback
        if not methods[name] then methods[name] = rack[name] or false end
    end
end
for _, name in ipairs({"canRack", "setReloadSpeed", "getReloadTime"}) do helpers[name] = reload[name] or false end
-- Deleted native overrides must not be mistaken for inherited implementations.
local requiredRack = {"isValid", "start", "update", "rackBullet", "removeBullet", "ejectSpentRounds", "initVars",
    "stop", "perform", "serverStart", "getDuration", "complete", "animEvent", "new"}
local requiredBase = {"isValidStart", "isValid", "isUsingTimeout", "update", "forceComplete", "forceStop", "forceCancel",
    "getJobDelta", "setJobDelta", "resetJobDelta", "waitToStart", "interruptWaitToStart", "start", "isStarted", "stop",
    "perform", "getDuration", "create", "begin", "setCurrentTime", "setTime", "adjustMaxTime", "setActionAnim",
    "setOverrideHandModels", "setOverrideHandModelsString", "overrideWeaponType", "restoreWeaponType", "setAnimVariable",
    "addAfter", "beginAddingActions", "endAddingActions", "getDeltaModifiers", "new"}
local baselineSafe = true
for _, name in ipairs(requiredRack) do if not ownMethods[name] then baselineSafe = false end end
for _, name in ipairs(requiredBase) do if not baseMethods[name] then baselineSafe = false end end
local ammoClass, scriptClass = AmmoType, ScriptManager
local scripts = scriptClass and scriptClass.instance
local ammunition = {}
for _, name in ipairs({"BULLETS_3030", "BULLETS_308", "BULLETS_357", "BULLETS_38", "BULLETS_44",
    "BULLETS_45", "BULLETS_556", "BULLETS_9MM", "SHOTGUN_SHELLS"}) do
    local value = ammoClass and ammoClass[name]
    if value then ammunition[value] = {name = name, key = value:getItemKey()} end
end
local sourceTrusted
local function nativeGlobal(callback)
    if type(callback) ~= "function" or type(globals.getClassSimpleName) ~= "function" then return false end
    local ok, kind = pcall(globals.getClassSimpleName, callback)
    return ok and (kind == "LuaJavaInvoker" or kind == "MultiLuaJavaInvoker")
end

-- Only the owned queue's inherited boundaries may replace native base methods.
function Firearms.adoptBase(name, previous, replacement)
    if (name ~= "begin" and name ~= "stop") or ISBaseTimedAction ~= base or base[name] ~= replacement
        or baseMethods[name] ~= previous or not Proof or not Proof.closure(previous, "ISBaseTimedAction.lua")
        or not Proof.closure(replacement, "ActionQueue.lua") then return false end
    baseMethods[name], adopted[name] = replacement, replacement
    -- PZ Kahlua rawget follows the metatable; only the captured own-method set
    -- distinguishes an inherited boundary from this class's native override.
    if not ownMethods[name] then methods[name] = replacement end
    return true
end
local companionProof
local function canRackTrusted()
    local current, captured = reload.canRack, helpers.canRack
    if current == captured and Proof.closure(current, "ISReloadWeaponAction.lua") then return true end
    local wpanc = WPANC
    local bow, archery = wpanc and wpanc.BowReload, wpanc and wpanc.ArcheryContract
    if type(bow) ~= "table" or type(archery) ~= "table" or current ~= bow._canRackHook
        or archery.BowFullType ~= "Base.Primitive_Bow" then return false end
    local original, predicate, itemPredicate = bow._originalCanRack, bow.isPrimitiveBow, archery.isPrimitiveBow
    if (captured ~= current and captured ~= original) or not Proof.closure(original, "ISReloadWeaponAction.lua")
        or not Proof.closure(current, "WPANC_BowReload.lua") or not Proof.closure(predicate, "WPANC_BowReload.lua")
        or not Proof.closure(itemPredicate, "WPANC_ArcheryContract.lua") then return false end
    if not companionProof then
        local mod = "WildernessProgressionArcheryNexusCompanion"
        if not Proof.matches("media/lua/shared/WPANC_BowReload.lua", 3277238911, mod, true)
            or not Proof.matches("media/lua/shared/WPANC_ArcheryContract.lua", 848735890, mod, true) then return false end
        -- The approved wrapper only checks the exact bow type, then delegates
        -- non-bows to its native predecessor. No bow-specific effects run here.
        companionProof = {wpanc, bow, archery, current, original, predicate, itemPredicate}
    end
    local saved = companionProof
    return wpanc == saved[1] and bow == saved[2] and archery == saved[3] and current == saved[4]
        and original == saved[5] and predicate == saved[6] and itemPredicate == saved[7]
end
local function trusted(action)
    if not baselineSafe then return false, "missing-native-method" end
    if not Proof or Toolkit.ActionQueueFirearms ~= Firearms or ISRackFirearm ~= rack or ISReloadWeaponAction ~= reload or ISBaseTimedAction ~= base
        or AmmoType ~= ammoClass or ScriptManager ~= scriptClass or not scripts or scriptClass.instance ~= scripts
        or getmetatable(action) ~= rack or action.Type ~= rack.Type then return false, "class-identity" end
    for _, name in ipairs(globalNames) do
        if _G[name] ~= globals[name] or not nativeGlobal(globals[name]) then return false, "global:" .. name end
    end
    if sourceTrusted == nil then
        sourceTrusted = Proof.matches("media/lua/shared/TimedActions/ISRackFirearm.lua", 3852187013, nil, true)
            and Proof.matches("media/lua/shared/TimedActions/ISReloadWeaponAction.lua", 1833975495, nil, true)
            and Proof.matches("media/lua/shared/TimedActions/ISBaseTimedAction.lua", 3104185167, nil, true)
    end
    if not sourceTrusted then return false, "native-source" end
    for name, callback in pairs(rack) do
        if type(callback) == "function" and name ~= "derive"
            and (methods[name] ~= callback or not Proof.closure(callback, "ISRackFirearm.lua")) then return false, "rack-method:" .. name end
    end
    for name, callback in pairs(baseMethods) do
        if base[name] ~= callback or not (Proof.closure(callback, "ISBaseTimedAction.lua")
            or adopted[name] == callback and Proof.closure(callback, "ActionQueue.lua")) then return false, "base-method:" .. name end
    end
    for name, callback in pairs(methods) do if (action[name] or false) ~= callback then return false, "action-method:" .. name end end
    for name, callback in pairs(action) do if type(callback) == "function" and methods[name] ~= callback then return false, "action-callback:" .. name end end
    for name, callback in pairs(helpers) do
        if name == "canRack" then
            if not canRackTrusted() then return false, "reload-helper:canRack" end
        elseif reload[name] ~= callback or not Proof.closure(callback, "ISReloadWeaponAction.lua") then return false, "reload-helper:" .. name end
    end
    if action.onStartFunc or action.onCompleteFunc or action.onCancelFunc or action.onFailFunc
        or action.additionalTest or action.retriggerLastAction then return false, "action-callback" end
    return true
end
local function method(value, name) return value and type(value[name]) == "function" end
local function outputType(gun)
    local ammo = gun:getAmmoType()
    local saved = ammunition[ammo]
    if not saved or ammoClass[saved.name] ~= ammo or ammo:getItemKey() ~= saved.key then return end
    local key = saved.key
    if type(key) ~= "string" or not key:match("^Base%.[%w_]+$") then return end
    local script = scripts:getItem(key)
    if not script then return end
    for _, name in ipairs({"getFullName", "getItemType", "getLuaCreate", "getItemConfig", "getItemConfigKey",
        "hasComponents", "getObsolete", "getReplaceOnUse", "getReplaceOnDeplete", "getOnBreak"}) do
        if not method(script, name) then return end
    end
    if script:getFullName() ~= key or tostring(script:getItemType()) ~= "base:normal"
        or script:getLuaCreate() or script:getItemConfig() or script:getItemConfigKey() or script:hasComponents()
        or script:getObsolete() or script:getReplaceOnUse() or script:getReplaceOnDeplete() or script:getOnBreak() then return end
    -- Native instanceItem creates one physical item; the script's distribution Count is unrelated.
    return key
end
function Firearms.rack(action)
    local valid, reason = trusted(action)
    if not valid then return nil, reason end
    if not instanceof(action.character, "IsoPlayer") or not instanceof(action.gun, "HandWeapon")
        or globals.getClassSimpleName(action.gun) ~= "HandWeapon" then return nil, "actor-or-weapon" end
    local output = outputType(action.gun)
    if not output then return nil, "ammunition-script" end
    local player = action.character
    local result = {items = {}, itemTypes = {}, targets = {[player:getInventory()] = true, [player] = true}, equipment = player, positions = {[player] = true},
        outputTypes = {[output] = true}, cancelWaiting = false, cancelOperation = false, interrupt = "finish-step"}
    local function add(item)
        if not item then return true end
        if not instanceof(item, "InventoryItem") then return false end
        local id, kind = item:getID(), item:getFullType()
        if type(id) ~= "number" or id % 1 ~= 0 or id == -1 or type(kind) ~= "string"
            or not kind:match("^[%w_]+%.[%w_]+$") then return false end
        result.items[id], result.itemTypes[kind] = true, true
        return true
    end
    if not add(action.gun) or not add(player:getPrimaryHandItem()) or not add(player:getSecondaryHandItem()) then return nil, "item-identity" end
    -- MP start rebinds by ID from the main inventory. A stale queued proxy must
    -- not describe a different live weapon or ammunition as an independent input.
    local live = player:getInventory():getItemById(action.gun:getID())
    if live and (not instanceof(live, "HandWeapon") or globals.getClassSimpleName(live) ~= "HandWeapon"
        or live:getID() ~= action.gun:getID() or live:getFullType() ~= action.gun:getFullType()
        or live:getAmmoType() ~= action.gun:getAmmoType()) then return nil, "live-weapon" end
    -- Reload speed reads equipped/worn tags and AmmoStrap. Snapshot current gear;
    -- the shared settlement also retains queued equipment writers for later reads.
    local worn = player:getWornItems()
    for index = 0, worn:size() - 1 do if not add(worn:getItemByIndex(index)) then return nil, "worn-identity" end end
    local policy = Toolkit.ActionQueuePolicy
    if policy and policy.addContainerResources then policy.addContainerResources(result, action.gun:getContainer()) end
    return result
end
return Firearms
