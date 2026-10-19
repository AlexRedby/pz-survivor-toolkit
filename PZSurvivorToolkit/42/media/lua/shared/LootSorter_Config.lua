-- LootSorter tunables, all in one place. Everything here is a value a maintainer might change;
-- the machinery that reads them lives elsewhere (isDebug/DBG in LootSorter_Debug.lua, the sliders in
-- client/LootSorter_Options.lua). Read at runtime only, so this file's load order does not matter.
LootSorter = LootSorter or {}

-- Developer diagnostics; existing LootSorter option and save identifiers are preserved.
LootSorter.DEBUG = false

LootSorter.MAX_TILES = 50           -- default walk range to a designated box (slider: 5-100)
LootSorter.MAX_LEVELS = 3           -- default floors to also search UP and DOWN (slider: 0-20; 0 = current floor)
LootSorter.MAX_LOAD_FRACTION = 0.99 -- default carry-load ceiling, as a fraction of max carry weight per
                                    -- trip (slider: 50%-400% of capacity; see LootSorter_Options.lua).
                                    -- 100% = normal safe max; above that intentionally overburdens the
                                    -- character (slower, and >150% takes ongoing HP damage -- see PZ's
                                    -- "Heavy load" moodle tiers: 100/125/150/175% of max weight).
LootSorter.BOX_FILL_FRACTION = 0.99 -- plan boxes to ~99% capacity: a hair of headroom so a boundary
                                    -- deposit never fails (a failed deposit would wipe the sort queue)
LootSorter.PRIORITY_MAX_DIGITS = 4  -- digits the designation window's priority field accepts, so the
                                    -- value stays an exact integer and fits the box. Nothing clamps
                                    -- the NUMBER: only the order of two boxes matters, never the gap.

-- Timings, in milliseconds.
LootSorter.SYNC_RETRY_MS = 4000     -- one retry after OnGameStart, in case the first request raced the
                                    -- connection (registry and preset store both)
LootSorter.CRAFT_CONTEXT_MS = 1000  -- how long after a craft-menu interaction the container injection
                                    -- stays live (see LootSorter_CraftMenu.lua)
LootSorter.ADD_GRACE_MS = 30000     -- a freshly added coord refuses removal for this long, so a client
                                    -- that has not yet seen the box cannot drop it (server-side)
LootSorter.RPC_TIMEOUT_MS = 15000   -- give up waiting for a server answer after this, and tell the
                                    -- caller it will never know (see LootSorter_Rpc.lua)
LootSorter.RPC_SWEEP_MS = 5000      -- how often to look for answers that are never coming
