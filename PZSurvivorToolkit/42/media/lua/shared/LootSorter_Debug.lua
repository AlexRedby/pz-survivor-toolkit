-- LootSorter debug/diagnostics helpers: the "are we in debug?" predicate, the trace logger, and the
-- container describer. All debug-specific and pure. Auto-loaded from media/lua/shared before the client
-- and server files, so LootSorter.DBG is always there to call -- no file aliases or guards it.
-- Generic (non-debug) helpers like safeCall live in LootSorter_Util.lua.
LootSorter = LootSorter or {}

-- One source of truth for "are we in debug?": the mod's own flag OR the game's -debug switch.
function LootSorter.isDebug()
    return LootSorter.DEBUG == true or isDebugEnabled() == true
end

-- Trace logger: silent unless in debug. Aliased per file so call sites stay `LootSorter.DBG(...)`.
function LootSorter.DBG(msg)
    if LootSorter.isDebug() then print("[LootSorter] " .. tostring(msg)) end
end

-- Identify WHAT a container is: a worn/carried bag (getContainingItem), a placed world object
-- (getParent), or its raw type. The container's own getType() is appended to the object form, so a
-- vehicle's separate compartments (trunk/bed/seat/glovebox) are distinguishable, not "object:Vehicle".
function LootSorter.describeContainer(c)
    local ty = LootSorter.safeCall(function() return c:getType() end, "?")
    local viaItem = LootSorter.safeCall(function() return c:getContainingItem() end, nil)
    if viaItem then
        local nm = LootSorter.safeCall(function() return viaItem:getName() end, "?")
        return ("item:%s"):format(tostring(nm))
    end
    local parent = LootSorter.safeCall(function() return c:getParent() end, nil)
    if parent then
        local nm = LootSorter.safeCall(function() return parent:getName() end, nil)
            or LootSorter.safeCall(function() return parent:getObjectName() end, nil)
        return ("object:%s[%s]"):format(tostring(nm or "?"), tostring(ty))
    end
    return ("type:%s"):format(tostring(ty))
end
