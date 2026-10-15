if isServer() or not getActivatedMods or not getActivatedMods():contains("SaucedCarts") then return end
PZSurvivorToolkit = PZSurvivorToolkit or {}
local Toolkit = PZSurvivorToolkit
Toolkit.cartCapacityMatches = nil
local meta = ItemContainer and __classmetatables and __classmetatables[ItemContainer.class]
local methods = meta and meta.__index
if not methods or not getClassSimpleName then return end
local previous = {}
for _, name in ipairs({"getCapacity", "getEffectiveCapacity", "hasRoomFor", "getCapacityWeight",
    "getContainingItem", "getParent", "getType", "getAcceptItemFunction"}) do
    local callback = methods[name]
    local kind = callback and getClassSimpleName(callback)
    if kind ~= "LuaJavaInvoker" and kind ~= "MultiLuaJavaInvoker" then return end
    previous[name] = callback
end

-- Observe private Java delegates before the mod's load-time wrappers hide them.
require "SaucedCarts/CapacityOverride"
local current = {}
for name, callback in pairs(previous) do
    current[name] = methods[name]
    if name == "getCapacity" or name == "getEffectiveCapacity" or name == "hasRoomFor" then
        if not current[name] or current[name] == callback or getClassSimpleName(current[name]) ~= "LuaClosure" then return end
    elseif current[name] ~= callback then return end
end
Toolkit.cartCapacityMatches = function(container)
    for name, callback in pairs(current) do if container[name] ~= callback then return false end end
    return true
end
