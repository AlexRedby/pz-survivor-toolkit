-- Native InventoryItem:hasTag reads this live ScriptItem set, including for
-- worms already present in a save. Keep the native fresh-worm breeding path.
local function allowWormCompost()
    if not ScriptManager or not ScriptManager.instance or not ItemTag or not ItemTag.CANT_COMPOST then return end
    local worm = ScriptManager.instance:FindItem("Base.Worm")
    if worm then worm:getTags():remove(ItemTag.CANT_COMPOST) end
end

-- Shared startup runs on single-player, Host clients and the authoritative server.
Events.OnGameBoot.Add(allowWormCompost)
return allowWormCompost
