-- Who owns the data: the one question the rest of the mod branches on.
--
-- Kept apart from the transport in LootSorter_Rpc.lua because it is asked in places that have nothing
-- to do with sending anything -- whether to register a tick handler, whether to touch the world store.
LootSorter = LootSorter or {}

-- Not isServer(): single-player is NEITHER client nor server, and owns its own data. A dedicated
-- server owns everyone's. So the question is only ever "am I the client of someone else".
function LootSorter.isAuthority()
    return not isClient()
end
