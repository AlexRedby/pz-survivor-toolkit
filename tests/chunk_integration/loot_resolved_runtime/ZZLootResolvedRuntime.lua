-- Explicit test bridge only. The owned native adapter decides when authority is ready.
function LootResolvedRuntimeAccept(container, item)
    local allowed = lootResolvedRuntimeAccept(container, item)
    if lootResolvedRuntimeWantsAcceptError() then
        error("LOOT_RESOLVED_EXPECTED_ACCEPT_ERROR")
    end
    return allowed
end

Events.OnFillContainer.Add(function(room, name, target)
    lootResolvedRuntimeFill(room, name, target)
end)
