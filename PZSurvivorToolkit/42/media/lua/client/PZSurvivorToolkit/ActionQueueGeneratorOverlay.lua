local Overlay = {}
PZSurvivorToolkit.ActionQueueGeneratorOverlay = Overlay
local attempted, range, functions, owners, wrappers
local files = {{"client/BGI/BGI_PowerRange.lua", 213747652}}

local function helpersUnchanged()
    if not range or BGI_PowerRange ~= range or getmetatable(range) then return false end
    if range.TargetGen ~= nil and not instanceof(range.TargetGen, "IsoGenerator") then return false end
    for name, callback in pairs(functions) do if range[name] ~= callback then return false end end
    for name, callback in pairs(range) do
        if type(callback) == "function" and functions[name] ~= callback then return false end
    end
    for name, owner in pairs(owners) do if _G[name] ~= owner then return false end end
    return ISPlugGenerator.complete == wrappers[1].callback and ISActivateGenerator.complete == wrappers[2].callback
end

function Overlay.powerScopeKnown() return helpersUnchanged() end

function Overlay.matches(owner, key, callback)
    if not helpersUnchanged() then return false end
    for _, saved in ipairs(wrappers) do
        if saved.owner == owner and saved.key == key and saved.callback == callback then return true end
    end
    return false
end

function Overlay.prepare(sourceMatches, nativeClosure)
    if attempted then return helpersUnchanged() end
    attempted = true
    if not getActivatedMods or not getActivatedMods():contains("BetterGeneratorInfo") or BGI_PowerRange ~= nil then return false end
    require "PZSurvivorToolkit/ActionQueueCompat"
    local Compat = PZSurvivorToolkit.ActionQueueCompat
    if not Compat or not Compat.verifySources or not Compat.verifySources("BetterGeneratorInfo", files) then return false end
    if not sourceMatches("client/BGI/BGI_PowerRange.lua", 1926030886) then return false end
    for _, module in ipairs({"TimedActions/ISPlugGenerator", "TimedActions/ISActivateGenerator",
        "ISUI/ISWorldObjectContextMenu", "ISUI/ISGeneratorInfoWindow"}) do
        if not pcall(require, module) then return false end
    end
    if not ISPlugGenerator or not ISActivateGenerator or not ISWorldObjectContextMenu or not ISGeneratorInfoWindow
        or ISPlugGenerator._BGI_wrapComplete or ISActivateGenerator._BGI_wrapComplete
        or ISWorldObjectContextMenu._BGI_wrapActivateGenerator then return false end
    local captures = {
        {ISPlugGenerator, "complete", "shared/TimedActions/ISPlugGenerator.lua", 4207143728, "ISPlugGenerator.lua"},
        {ISActivateGenerator, "complete", "shared/TimedActions/ISActivateGenerator.lua", 844646271, "ISActivateGenerator.lua"},
        {ISWorldObjectContextMenu, "onActivateGenerator", "client/ISUI/ISWorldObjectContextMenu.lua", 1920579052, "ISWorldObjectContextMenu.lua"},
    }
    for _, saved in ipairs(captures) do
        if not sourceMatches(saved[3], saved[4]) or not nativeClosure(saved[1][saved[2]], saved[5]) then return false end
    end
    local nativeOwners = {ISPlugGenerator = ISPlugGenerator, ISActivateGenerator = ISActivateGenerator,
        ISWorldObjectContextMenu = ISWorldObjectContextMenu}
    -- The pinned module captures these verified delegates synchronously; never reload installed BGI hooks.
    if not pcall(require, "BGI/BGI_PowerRange") then return false end
    local installed = BGI_PowerRange
    if type(installed) ~= "table" or getmetatable(installed) then return false end
    local installedWrappers = {}
    for _, saved in ipairs(captures) do
        local callback = saved[1][saved[2]]
        if not nativeClosure(callback, "BGI_PowerRange.lua") then return false end
        installedWrappers[#installedWrappers + 1] = {owner = saved[1], key = saved[2], callback = callback}
    end
    local installedFunctions = {}
    for name, callback in pairs(installed) do
        if type(callback) == "function" then
            if not nativeClosure(callback, "BGI_PowerRange.lua") then return false end
            installedFunctions[name] = callback
        end
    end
    if not installedFunctions._rebuildUnionEdges then return false end
    range, functions, owners, wrappers = installed, installedFunctions, nativeOwners, installedWrappers
    return helpersUnchanged()
end

return Overlay
