-- LootSorter core: designation storage + the sort/haul engine.
-- (Walk action -> LootSorter_WalkAction.lua; right-click menus -> LootSorter_ContextMenu.lua.)
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISInventoryTransferAction"
local TagRules = require "PZSurvivorToolkit/QuartermasterTagRules"
local Tags = require "PZSurvivorToolkit/ItemTags"
local Categories = require "PZSurvivorToolkit/ItemCategories"

LootSorter = LootSorter or {}
-- diagnostic trace: silent unless LootSorter.DEBUG is set or the game runs in -debug mode

-- PZ's Kahlua sandbox has no global next(); use a pairs-based emptiness check
local function tableHasAny(t) if t then for _ in pairs(t) do return true end end return false end

-- Reload-safety: on every (re)load, tear down any of the mod's OPEN windows so a hot-reload leaves a
-- clean slate -- no stranded or duplicate UI, nothing left dimmed. No-op at boot (all handles nil).
-- Order matters: closing the preset editor first restores focus to its box picker, then closing that
-- restores focus to the original (inventory), so a controller is never stranded on a removed window.
function LootSorter.closeAllWindows()
    for _, field in ipairs({ "_categoryView", "_presetEditor", "_picker", "_manifestWin" }) do
        local win = LootSorter[field]
        if win then
            pcall(function()
                if win.grabbedJoypad and win.prevFocus ~= nil then
                    setJoypadFocus(win.playerNum or 0, win.prevFocus)
                end
                win:removeFromUIManager()
            end)
            LootSorter[field] = nil
        end
    end
end
LootSorter.closeAllWindows()

----------------------------------------------------------------------
-- Designation storage (per-box data on ModData) + a coord index for fast lookup
----------------------------------------------------------------------

-- Index of designated box TILE-coords ("x,y,z" -> true) -- ONLY a fast lookup; the authoritative
-- per-box data lives on each object's ModData. Owned by server/LootSorter_Coords.lua.
-- The fallback is not redundant: on an MP client getOrCreate is permanently empty and the live table
-- arrives via OnReceiveGlobalModData, while in SP that event never fires and getOrCreate is the real
-- shared table.
function LootSorter.getRegistry()
    local md = LootSorter._receivedRegistry or ModData.getOrCreate("LootSorter_Registry")
    md.boxes = md.boxes or {}
    return md.boxes
end

-- Before the server's copy arrives, an empty index means "not synced yet", not "no boxes".
function LootSorter.isRegistrySynced()
    if LootSorter._receivedRegistry then return true end
    return not isClient()          -- SP/host: getOrCreate is the real table, always trustworthy
end

-- Capture the server's table. Must keep THIS reference -- getOrCreate will not reflect it.
LootSorter.addOrReplaceHandler(Events.OnReceiveGlobalModData, "_onReceiveModData",
    function(key, receivedTable)
        if key ~= "LootSorter_Registry" or not receivedTable then return end
        LootSorter._receivedRegistry = receivedTable
        LootSorter.DBG("registry received from server")
    end)

-- Never call this at file scope: ModData.request needs a live client connection and throws without
-- one. The server only pushes on its own boot, so a client joining later must ask.
local function requestRegistry()
    pcall(function() if isClient() then ModData.request("LootSorter_Registry") end end)
end

LootSorter.removeHandler(Events.OnTick, "_syncRetryTick")

LootSorter.addOrReplaceHandler(Events.OnGameStart, "_onGameStartSync", function()
    LootSorter._receivedRegistry = nil      -- same reason as the preset store: never carry one world's index into another
    requestRegistry()
    -- one retry, in case the first request raced the connection
    local retryAt = getTimestampMs() + LootSorter.SYNC_RETRY_MS
    local retryTick
    retryTick = function()
        if getTimestampMs() < retryAt then return end
        Events.OnTick.Remove(retryTick)
        if LootSorter._syncRetryTick == retryTick then LootSorter._syncRetryTick = nil end
        if not LootSorter._receivedRegistry then requestRegistry() end
    end
    LootSorter.addOrReplaceHandler(Events.OnTick, "_syncRetryTick", retryTick)
end)

-- The client's view of the presets (getPresetStore / loadPresets / savePresets / sync) lives in
-- LootSorter_PresetSync.lua; the pure (de)serialization is in shared/LootSorter_Presets.lua.
local function keyOf(x, y, z) return math.floor(x) .. "," .. math.floor(y) .. "," .. math.floor(z) end
local findDesignatedOnSquare   -- forward declaration (defined below; used by setBoxCats + gatherBoxes)

-- container index of a container within its parent object (0-based), or nil
function LootSorter.containerIndex(obj, container)
    if not obj then return nil end
    local n = obj:getContainerCount() or 0
    for i = 0, n - 1 do
        if obj:getContainerByIndex(i) == container then return i end
    end
    return nil
end

-- designations live per container on the parent object, in three additive layers:
--   md.LSBox[ci]        = { [category]=true }      manual categories
--   md.LSBoxItems[ci]   = { [displayName]=true }   manual specific items
--   md.LSBoxPresets[ci] = { [presetName]=generation }    presets this box uses (see LootSorter_Presets.lua)
-- A container's EFFECTIVE designation is the union of the two manual sets with the contents of every
-- preset it uses, resolved in findDesignatedOnSquare via LootSorter.resolveEffective (the sort/manifest
-- read path). A container may use any combination.
function LootSorter.getBoxCats(obj, ci)
    if not obj then return nil end
    local md = obj:getModData()
    if not md.LSBox then return nil end
    return md.LSBox[tostring(ci)]
end

function LootSorter.getBoxItems(obj, ci)
    if not obj then return nil end
    local md = obj:getModData()
    if not md.LSBoxItems then return nil end
    return md.LSBoxItems[tostring(ci)]
end

-- which PRESETS this container uses: md.LSBoxPresets[ci] = { [presetName]=generation }
function LootSorter.getBoxPresets(obj, ci)
    if not obj then return nil end
    local md = obj:getModData()
    if not md.LSBoxPresets then return nil end
    return md.LSBoxPresets[tostring(ci)]
end

-- Drop links that no longer resolve, using the same predicate as resolution so a link can't be too
-- dead to sort with but too alive to clean up.
local function pruneDeadPresetLinks(sq)
    -- MP only. There the store is the server's, shared and saved with the world, so a preset's
    -- absence is authoritative. In SP the store is a per-machine file while the links are per-world,
    -- so absence proves nothing and deleting on it can't be undone.
    if not isClient() then return end
    if not LootSorter.arePresetsSynced() then return end
    local store = LootSorter.getPresetStore()
    -- An empty store is indistinguishable from one that never arrived, and deleting on that basis
    -- can't be undone.
    local storeHasAny = false
    for _ in pairs(store) do storeHasAny = true; break end
    if not storeHasAny then return end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local obj = objs:get(i)
        if obj and obj.hasModData and obj:hasModData() then
            local md = obj:getModData()
            local dropped = false
            if md.LSBoxPresets then
                for _, links in pairs(md.LSBoxPresets) do
                    if type(links) == "table" then
                        for name, link in pairs(links) do
                            if not LootSorter.linkResolves(store[name], link) then
                                links[name] = nil; dropped = true
                            end
                        end
                    end
                end
            end
            if dropped then
                if obj.transmitModData then obj:transmitModData() end
                LootSorter.DBG("dropped dead preset link(s) on a box")
            end
        end
    end
end

-- Ask the server to add or drop this tile's coord. Uses the raw predicate, not the preset-resolved
-- one: a client whose preset store hasn't synced yet resolves a presets-only box to nothing, and
-- would tell the server to drop a box that does exist.
local function syncCoord(obj)
    local sq = obj and obj:getSquare()
    if not sq then return end
    local k = keyOf(sq:getX(), sq:getY(), sq:getZ())
    if LootSorter.squareHasDesignation(sq) then
        LootSorter.addCoord({ key = k })
    else
        LootSorter.removeCoords({ keys = { k } })
    end
end

-- write a set under a ModData field (LSBox = categories, LSBoxItems = item display names)
local function writeBoxSet(md, ci, set, field)
    md[field] = md[field] or {}
    if set and tableHasAny(set) then md[field][tostring(ci)] = set else md[field][tostring(ci)] = nil end
end

local function setBoxSet(obj, ci, set, field)
    if not obj or ci == nil then return end
    writeBoxSet(obj:getModData(), ci, set, field)
    if obj.transmitModData then obj:transmitModData() end
    syncCoord(obj)
end

-- Higher wins, 0 is the default. Stored per container index like everything else, and left absent
-- when 0 so a box that never mentions priority carries no field at all.
function LootSorter.getBoxPriority(obj, ci)
    if not obj then return 0 end
    local md = obj:getModData()
    if not md.LSBoxPriority then return 0 end
    return tonumber(md.LSBoxPriority[tostring(ci)]) or 0
end

local function writeBoxPriority(md, ci, priority)
    local value = tonumber(priority) or 0
    if value == 0 then
        -- Not created just to hold a zero: saving an untouched box would otherwise add an empty table
        -- to its ModData, so a v0.19 designation would stop round-tripping unchanged.
        if md.LSBoxPriority then md.LSBoxPriority[tostring(ci)] = nil end
    else
        md.LSBoxPriority = md.LSBoxPriority or {}
        md.LSBoxPriority[tostring(ci)] = value
    end
end

function LootSorter.setBoxPriority(obj, ci, priority)
    if not obj or ci == nil then return end
    writeBoxPriority(obj:getModData(), ci, priority)
    if obj.transmitModData then obj:transmitModData() end
end

function LootSorter.setBoxCats(obj, ci, catsSet)      setBoxSet(obj, ci, catsSet, "LSBox") end
function LootSorter.setBoxItems(obj, ci, itemsSet)    setBoxSet(obj, ci, itemsSet, "LSBoxItems") end
function LootSorter.setBoxPresets(obj, ci, presetsSet) setBoxSet(obj, ci, presetsSet, "LSBoxPresets") end

-- Copy/paste of a whole designation. Copied on BOTH ends, never aliased: the getters hand back the
-- live ModData table, so holding it would track later edits to the source, and pasting one table into
-- several boxes would leave them sharing a single set.
local function copySet(set)
    if not set then return nil end
    local out = {}
    for key, value in pairs(set) do if value then out[key] = value end end
    return out
end

local function countSet(set)
    local total = 0
    for _ in pairs(set or {}) do total = total + 1 end
    return total
end

-- A detached value shared by clipboard and editor saves. Preset links carry generations, not
-- booleans: changing a link to true would let it resolve a deleted-and-recreated preset by name.
function LootSorter.snapshotDesignation(value)
    return {
        cats = copySet(value.cats), items = copySet(value.items), presets = copySet(value.presets),
        priority = tonumber(value.priority) or 0,
        pzstTagRule = value.pzstTagRule and Tags.normalizeRule(value.pzstTagRule) or nil,
    }
end

-- Publish a complete native designation once. A tag-rule edit must first be accepted by
-- TagRules.saveBox; it owns rule authorization/revisions and updates this same object's ModData.
function LootSorter.setBoxDesignation(obj, ci, value)
    if not obj or ci == nil then return end
    local snapshot, md = LootSorter.snapshotDesignation(value), obj:getModData()
    writeBoxSet(md, ci, snapshot.cats, "LSBox")
    writeBoxSet(md, ci, snapshot.items, "LSBoxItems")
    writeBoxSet(md, ci, snapshot.presets, "LSBoxPresets")
    writeBoxPriority(md, ci, snapshot.priority)
    if obj.transmitModData then obj:transmitModData() end
    syncCoord(obj)
end

function LootSorter.copyDesignation(obj, ci)
    LootSorter.clipboard = LootSorter.snapshotDesignation({
        cats = LootSorter.getBoxCats(obj, ci), items = LootSorter.getBoxItems(obj, ci),
        presets = LootSorter.getBoxPresets(obj, ci), priority = LootSorter.getBoxPriority(obj, ci),
        pzstTagRule = TagRules.getBox(obj, ci),
    })
    return LootSorter.clipboard
end

-- Replaces rather than merges. Capture the request now: another Copy may replace the clipboard
-- before the server accepts it. The complete sorting snapshot shares the editor's authority;
-- appearance stays absent so a paste preserves the destination's name, icon and color.
function LootSorter.pasteDesignation(obj, ci)
    if not LootSorter.clipboard then return false end
    local snapshot = LootSorter.snapshotDesignation(LootSorter.clipboard)
    local player = getSpecificPlayer(0)
    local revision = TagRules.getBoxRevision(obj, ci)
    TagRules.saveBox(obj, ci, snapshot.pzstTagRule, player, function(verdict)
        if verdict ~= "ok" and LootSorter.notify then
            LootSorter.notify(player, getText("UI_PZST_QMTagRuleFailed", tostring(verdict)))
        end
    end, revision, snapshot)
    return true
end

-- Empty counts as nothing to paste, not as "paste an empty set": copying an undesignated box is the
-- only way to get one, and offering "Paste (empty)" reads as a broken feature rather than a state.
function LootSorter.hasClipboardContent()
    local clipboard = LootSorter.clipboard
    if not clipboard then return false end
    if (clipboard.priority or 0) ~= 0 or Tags.ruleActive(clipboard.pzstTagRule) then return true end
    return countSet(clipboard.cats) + countSet(clipboard.items) + countSet(clipboard.presets) > 0
end

-- "2 categories, 1 preset", or nil when nothing has been copied yet.
function LootSorter.describeClipboard()
    local clipboard = LootSorter.clipboard
    if not clipboard then return nil end
    local parts = {}
    local counts = { { countSet(clipboard.cats), "category", "categories" },
                     { countSet(clipboard.items), "item", "items" },
                     { countSet(clipboard.presets), "preset", "presets" } }
    for _, entry in ipairs(counts) do
        if entry[1] > 0 then
            parts[#parts + 1] = entry[1] .. " " .. (entry[1] == 1 and entry[2] or entry[3])
        end
    end
    if (clipboard.priority or 0) ~= 0 then
        parts[#parts + 1] = "priority " .. tostring(clipboard.priority)
    end
    if Tags.ruleActive(clipboard.pzstTagRule) then parts[#parts + 1] = getText("UI_PZST_QMTagRule") end
    if #parts == 0 then return "empty" end
    return table.concat(parts, ", ")
end

-- Auto-track moved/placed boxes: when a moveable is set down, PZ fires OnObjectAdded with the object
-- (its ModData rides along), so a designated box that MOVED gets its new tile recorded without a
-- re-designate. Pickup/removal is left to gatherBoxes' self-heal (it drops the stale coord).
-- rebound each reload so edits to this handler apply (a boolean guard alone would keep running the
-- FIRST load's closure forever).
LootSorter.addOrReplaceHandler(Events.OnObjectAdded, "_onObjAdded", function(obj)
    pcall(function()
        if obj and obj.hasModData and obj:hasModData() then
            local md = obj:getModData()
            if LootSorter.modDataHasDesignation(md) then
                local sq = obj:getSquare()
                if sq then
                    LootSorter.addCoord({ key = keyOf(sq:getX(), sq:getY(), sq:getZ()) })
                end
            end
        end
    end)
end)

-- return ALL designated boxes on a square: every (object, container index) with a designation.
-- Supports multiple STACKED objects and MULTI-CONTAINER objects sharing one tile.
findDesignatedOnSquare = function(sq, player)
    local out = {}
    if not sq then return out end
    local manifest = LootSorter._manifestWin
    player = player or getSpecificPlayer(manifest and manifest.playerNum or 0)
    if isClient() and (not player or not LootSorter.canLootSquare(sq, player)) then return out end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        -- hasModData() is a cheap read that does NOT instantiate ModData. This matters:
        -- the pure scan visits thousands of tiles, and plain getModData() would attach an
        -- empty ModData table to every wall/floor/furniture it touches (memory + save bloat).
        if o and o.hasModData and o:hasModData() then
            local md = o:getModData()
            if md.LSBox or md.LSBoxItems or md.LSBoxPresets or md[TagRules.FIELD] then
                local store = LootSorter.getPresetStore()
                local n = o:getContainerCount() or 0
                for ci = 0, n - 1 do
                    local key = tostring(ci)
                    -- EFFECTIVE designation = manual categories/items UNION every used preset's contents
                    -- (linked presets, resolved live). A box configured purely via presets counts too.
                    local cats, items = LootSorter.resolveEffective(
                        md.LSBox and md.LSBox[key], md.LSBoxItems and md.LSBoxItems[key],
                        md.LSBoxPresets and md.LSBoxPresets[key], store)
                    local rules = TagRules.forBox(o, ci, md.LSBoxPresets and md.LSBoxPresets[key], store)
                    if tableHasAny(cats) or tableHasAny(items) or #rules > 0 then
                        -- read here, where the ModData and the container index are both in scope:
                        -- the records below carry no ci to look it up with later
                        out[#out + 1] = { obj = o, container = o:getContainerByIndex(ci),
                                          cats = cats, items = items, rules = rules,
                                          priority = tonumber(md.LSBoxPriority
                                              and md.LSBoxPriority[key]) or 0 }
                    end
                end
            end
        end
    end
    return out
end
LootSorter.findDesignatedOnSquare = findDesignatedOnSquare   -- reused by the manifest (LootSorter_Manifest.lua)

-- all the player's carry containers, ordered bags-first (most weight-reduction first), main inventory last
function LootSorter.getCarriers(player)
    local carriers = {}
    pcall(function()
        local page = getPlayerInventory(player:getPlayerNum()).inventoryPane.inventoryPage
        for _, bp in ipairs(page.backpacks) do
            local cont = bp.inventory
            if cont then
                local factor = 1.0
                local it; pcall(function() it = cont:getContainingItem() end)
                if it then
                    local r = 0; pcall(function() r = it:getWeightReduction() end)
                    factor = 1 - (r or 0) / 100
                    if factor < 0.01 then factor = 0.01 end
                end
                table.insert(carriers, { container = cont, factor = factor })
            end
        end
    end)
    if #carriers == 0 then carriers = { { container = player:getInventory(), factor = 1.0 } } end
    table.sort(carriers, function(a, b) return a.factor < b.factor end) -- bags (low factor) first, main last
    return carriers
end

----------------------------------------------------------------------
-- The sort engine
----------------------------------------------------------------------

-- Find designated boxes near the player using the coord index (NOT a world scan).
-- For each registered coord within range: verify a designated box is still on that tile (reading
-- its categories live off the object's ModData), collect it, and self-heal coords whose box is gone.
-- Boxes are ordered floor-first (current floor before any other) then by chebyshev x/y -- reaching
-- another floor means finding stairs, so we prefer the current level. Cost is O(#designated boxes).
-- Returns boxes, synced. An unsynced client sees an empty registry, which is indistinguishable from
-- owning no boxes -- so the flag is what callers must branch on, not #boxes.
local function gatherBoxes(player)
    if not LootSorter.isRegistrySynced() or not LootSorter.arePresetsSynced() then
        LootSorter.DBG(("not yet synced: registry=%s presets=%s"):format(
            tostring(LootSorter.isRegistrySynced()), tostring(LootSorter.arePresetsSynced())))
        if not LootSorter.isRegistrySynced() then
            pcall(function() ModData.request("LootSorter_Registry") end)
        end
        if not LootSorter.arePresetsSynced() and LootSorter.requestPresets then
            LootSorter.requestPresets()
        end
        return {}, false
    end
    local psq = player:getCurrentSquare()
    if not psq then return {}, true end     -- synced, just nowhere to search from
    local px, py, pz = psq:getX(), psq:getY(), psq:getZ()
    local cell = getCell()
    local R = LootSorter.MAX_TILES or 50
    local ZR = LootSorter.MAX_LEVELS or 0
    local zPenalty = R + 1                        -- > any same-floor chebyshev, so floors sort strictly
    local reg = LootSorter.getRegistry()
    local boxes, checked = {}, 0
    -- Collected, not dropped inline: where we own the data the command runs immediately and deletes
    -- from `reg` -- the very table this loop is walking. One batch at the end also beats one command
    -- per stale coord, and they arrive in bursts.
    local stale = {}
    for k in pairs(reg) do
        local sx, sy, sz = k:match("(-?%d+),(-?%d+),(-?%d+)")
        sx, sy, sz = tonumber(sx), tonumber(sy), tonumber(sz)
        if not sx then
            stale[#stale + 1] = k                    -- malformed key -> ask the server to drop it
        else
            local adz = math.abs(sz - pz)
            local adx, ady = math.abs(sx - px), math.abs(sy - py)
            local cheb = adx > ady and adx or ady
            if cheb <= R and adz <= ZR then        -- range filter (cheap); skip far coords (keep them)
                local sq = cell:getGridSquare(sx, sy, sz)
                -- Skip a safehouse we may not loot BEFORE anything else touches the square: not ours
                -- to read, prune, or self-heal. Dropping the coord here would delete another player's
                -- box from the index for everyone.
                if sq and not LootSorter.canLootSquare(sq, player) then
                    sq = nil
                end
                if sq then                         -- loaded -> verify the box is still there
                    checked = checked + 1
                    pruneDeadPresetLinks(sq)       -- before resolving, so the result reflects the prune
                    local found = findDesignatedOnSquare(sq, player)
                    if #found > 0 then
                        local dist = adz * zPenalty + cheb
                        for _, f in ipairs(found) do
                            if f.container then
                                table.insert(boxes, { obj = f.obj, square = sq, cats = f.cats, items = f.items,
                                                      container = f.container, rules = f.rules, dist = dist,
                                                      priority = f.priority })
                            end
                        end
                    elseif not LootSorter.squareHasDesignation(sq) then
                        -- self-heal: nothing designated here anymore. The raw check keeps a client
                        -- with unsynced presets from dropping a box that resolves fine for others.
                        stale[#stale + 1] = k
                    end
                end                                -- not loaded -> keep coord for later
            end
        end
    end
    if #stale > 0 then LootSorter.removeCoords({ keys = stale }) end
    LootSorter.DBG(("gatherBoxes checked %d in-range coord(s), found %d box(es)"):format(checked, #boxes))
    table.sort(boxes, function(a, b) return a.dist < b.dist end)
    return boxes, true
end

LootSorter.gatherBoxes = gatherBoxes   -- reused by the craft-fetch engine (LootSorter_Craft.lua)

function LootSorter.notify(player, message)
    if player then pcall(function() player:setHaloNote(tostring(message)) end) end
    LootSorter.DBG(tostring(message))
end

-- Boxes, or nil when the client hasn't synced (having said so). Distinct from an empty table, which
-- means "synced, and there are none" -- callers must branch on nil, not on #boxes.
function LootSorter.gatherBoxesOrWarn(player)
    local boxes, synced = gatherBoxes(player)
    if not synced then
        LootSorter.notify(player, "Quartermaster: still syncing designated boxes from the server")
        return nil
    end
    return boxes
end

-- pick the destination box for an item's DisplayCategory (nearest matching)
local function boxForCategory(boxes, cat)
    for _, b in ipairs(boxes) do
        if b.cats[cat] then return b end
    end
    return nil
end

-- MAIN: sort everything in sourceContainer into designated boxes
function LootSorter.sort(sourceContainer, playerNum)
    local player = getSpecificPlayer(playerNum)
    if not player or not sourceContainer then return end
    local ok, err = pcall(function()
        Categories.prepareContainer(sourceContainer)
        if LootSorter.applyOptions then LootSorter.applyOptions() end  -- pick up live range settings
        -- Is the source already carried by the player (a bag / main inventory)? Then there's no
        -- hauling to do -- the loot is already on us. We just walk to each box once and deposit.
        local onPlayer = false
        pcall(function() onPlayer = sourceContainer:isInCharacterInventory(player) end)
        local startSquare = player:getCurrentSquare()

        local boxes = LootSorter.gatherBoxesOrWarn(player)
        if not boxes then return end          -- unsynced; nil is not the same as an empty result
        if #boxes == 0 then
            LootSorter.notify(player, "No designated boxes within range.")
            LootSorter.DBG("no designated boxes in range")
            return
        end
        -- Capacity as the acting character sees it: getEffectiveCapacity() bakes in the Organized /
        -- Disorganized trait modifier, which base getCapacity() ignores. Using the base value made a crate
        -- the Organized trait had let fill past its script capacity read as full (getCapacityWeight can then
        -- exceed getCapacity), so the planner routed nothing to it. Falls back to base if unavailable.
        local function effectiveCapacity(container)
            local cap = LootSorter.safeCall(function() return container:getEffectiveCapacity(player) end, nil)
            if not cap or cap <= 0 then cap = container:getCapacity() end
            return cap
        end

        for bi, b in ipairs(boxes) do
            local cs = ""
            for k in pairs(b.cats) do cs = cs .. k .. " " end
            local is = ""                                     -- item-NAME designations (b.items), not contents
            for k in pairs(b.items or {}) do is = is .. k .. " " end
            LootSorter.DBG(("box[%d] cap=%.0f used=%.1f dist=%d cats=[%s] items=[%s]"):format(
                bi, effectiveCapacity(b.container), b.container:getCapacityWeight(), b.dist, cs, is))
        end

        -- Build plain-data records (engine -> data) for the PURE planner.
        -- Skip items the player is using/protecting: equipped in-hand, favorited, or attached to the
        -- hotbar (a holstered pistol, sheathed knife, clipped flashlight, etc.) -- so distributing your
        -- own inventory never sweeps your belt/holster gear. (Worn clothing / back-bags live in a
        -- separate container and aren't scanned here anyway.) Mirrors vanilla's own transfer filter.
        local hotbar = nil
        pcall(function() hotbar = getPlayerHotbar(playerNum) end)
        local itemRecs = {}
        local skippedInUse = {}   -- items excluded here (equipped/favorited/hotbar); logged so they're not invisible
        local items = sourceContainer:getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            if it and not it:isEquipped() and not it:isFavorite()
                   and not (hotbar and hotbar:isInHotbar(it)) then
                -- Measure items with the SAME metric the engine's container room-check uses
                -- (getActualWeight, not getWeight), so the planner's "does it fit?" matches reality
                -- and never over-assigns a box past what a deposit can actually put in.
                local w = it:getWeight() or 0
                pcall(function() local aw = it:getActualWeight(); if aw and aw > 0 then w = aw end end)
                local origin = sourceContainer
                pcall(function() local realContainer = it:getContainer(); if realContainer then origin = realContainer end end)
                itemRecs[#itemRecs + 1] = { ref = it, cat = it:getDisplayCategory(),
                    name = it:getDisplayName(), weight = w, container = origin }
            elseif it and LootSorter.isDebug() then
                local nm = "?"; pcall(function() nm = it:getDisplayName() end)
                skippedInUse[#skippedInUse + 1] = nm
            end
        end
        -- run id: ties every line of this haul together (start header, queued deposits, walk legs, the
        -- watchdog's complete/interrupted) so back-to-back runs stay distinguishable in the log.
        local runId = (LootSorter._sortRunSeq or 0) + 1
        LootSorter._sortRunSeq = runId
        if LootSorter.isDebug() then
            -- log WHICH container was scanned (incl. vehicle compartment via describeContainer) plus the
            -- full item list, so a short/partial run is traceable to the exact source and its contents
            local src = "?"
            pcall(function() if LootSorter.describeContainer then src = LootSorter.describeContainer(sourceContainer) end end)
            LootSorter.DBG(("run #%d START source=%s onPlayer=%s"):format(runId, tostring(src), tostring(onPlayer)))
            local names = {}
            for i, r in ipairs(itemRecs) do names[i] = ("%s(%.2f)"):format(r.name or "?", r.weight or 0) end
            LootSorter.DBG(("run #%d items (%d): %s"):format(runId, #itemRecs, table.concat(names, ", ")))
            if #skippedInUse > 0 then   -- account for items deliberately left as "in use" (not leftovers)
                LootSorter.DBG(("run #%d skipped %d in-use item(s) (equipped/favorited/hotbar): %s"):format(
                    runId, #skippedInUse, table.concat(skippedInUse, ", ")))
            end
        end
        local boxRecs = {}
        for _, b in ipairs(boxes) do                              -- boxes are nearest-first
            local stand = AdjacentFreeTileFinder.Find(b.square, player)
            if stand then
                boxRecs[#boxRecs + 1] = { ref = b, container = b.container, cats = b.cats, items = b.items, rules = b.rules, stand = stand,
                    capacity = effectiveCapacity(b.container) * LootSorter.BOX_FILL_FRACTION,
                    used = b.container:getCapacityWeight(), dist = b.dist, priority = b.priority }
            else
                LootSorter.DBG("box unreachable, skipping")
            end
        end
        local carrierRecs, budget, capacity, carried
        if onPlayer then
            -- already carried: one "carrier" (the source itself) + unlimited budget, so planTrips
            -- routes everything to boxes in a single pass (no weight-limited trips -> no bouncing).
            carrierRecs = { { ref = sourceContainer, factor = 0.01, space = 1e9 } }
            budget, capacity, carried = 1e9, 1e9, 0
        else
            carrierRecs = {}
            for _, c in ipairs(LootSorter.getCarriers(player)) do
                carrierRecs[#carrierRecs + 1] = { ref = c.container, factor = c.factor,
                    space = effectiveCapacity(c.container) - c.container:getCapacityWeight() }
            end
            table.sort(carrierRecs, function(a, b) return a.factor < b.factor end) -- bags first
            local okMW, mw = pcall(function() return player:getMaxWeight() end)
            if okMW and mw and mw > 0 then capacity = mw else capacity = 10 end
            carried = player:getInventory():getCapacityWeight()   -- what the character is already carrying
            budget = capacity * LootSorter.MAX_LOAD_FRACTION - carried
        end
        -- budget = (maxWeight * loadFrac) - carried: the effective-weight room a trip may fill before
        -- hitting the load ceiling. Logging carried + loadFrac makes budgetEff self-explanatory.
        LootSorter.DBG(("maxWeight=%.1f carried=%.1f loadFrac=%.2f budgetEff=%.1f items=%d boxes=%d carriers=%d onPlayer=%s"):format(
            capacity, carried or 0, LootSorter.MAX_LOAD_FRACTION or 0, budget, #itemRecs, #boxRecs, #carrierRecs, tostring(onPlayer)))

        -- PURE planning (this is what the unit tests exercise). Inject a carrier-acceptance predicate
        -- backed by the engine's own ItemContainer:isItemAllowed, so a type-restricted container the
        -- inventory UI lists as a "backpack" (Key Ring, wallet, ammo strap, holster...) is never chosen
        -- as a general haul carrier. Guarded: a container that throws defaults to allowed rather than
        -- killing the sort.
        local function accepts(carrierRef, itemRef)
            if not carrierRef or not itemRef then return true end
            local ok, v = pcall(function() return carrierRef:isItemAllowed(itemRef) end)
            return (not ok) or v == true
        end
        local plan = LootSorter.planTrips(itemRecs, boxRecs, carrierRecs, budget, accepts, TagRules.matches)
        local selfPlaced
        plan.trips, selfPlaced = LootSorter.stripSelfPlacements(plan.trips, sourceContainer)
        if selfPlaced > 0 then
            LootSorter.DBG(("run #%d skipped %d self-placement(s) (already in destination box)"):format(runId, selfPlaced))
        end

        -- EXECUTE (the only engine-touching part): queue transfers + walks from the plan.
        -- Each WALK is tagged with runId + a 1-based leg index, so the watchdog in
        -- LootSorter_WalkAction.lua can tell whether the LAST leg's perform() ever fires; each DEPOSIT
        -- gets runId + a run-unique sequence id so a "queued N / started M" gap exposes deposits merged
        -- away or dropped from the queue. (runId computed above, at the run-start header.)
        local walkIdx = 0
        local function queueWalk(dest)
            walkIdx = walkIdx + 1
            local w = LootSorter.WalkAction:new(player, dest)
            w.lsRunId = runId
            w.lsLegIndex = walkIdx
            ISTimedActionQueue.add(w)
        end
        local depSeq = 0
        local depLog = {}    -- one consolidated "queued deposits" line instead of one print per item
        local function queueDeposit(item, from, to, phase)
            depSeq = depSeq + 1
            local d = LootSorter.DepositAction:new(player, item, from, to)
            d.lsRunId = runId
            d.lsSeq = depSeq
            d.lsPhase = phase
            if LootSorter.isDebug() then
                local nm = "?"; pcall(function() nm = item and item:getName() end)
                depLog[#depLog + 1] = ("#%d %s %s"):format(depSeq, phase, tostring(nm))
            end
            ISTimedActionQueue.add(d)
        end
        local queued = 0
        for ti, trip in ipairs(plan.trips) do
            if LootSorter.isDebug() then          -- per-trip/per-box diagnostics
                local nb = 0; for _ in pairs(trip.perBox) do nb = nb + 1 end
                -- effective weight this trip loads (item weight * carrier reduction factor) and where it
                -- puts the character: expected peak = carried + loadEff, vs max carry weight (>100% = overburdened)
                local loadEff = 0
                for _, entries in pairs(trip.perBox) do
                    for _, e in ipairs(entries) do loadEff = loadEff + (e.item.weight or 0) * (e.carrier.factor or 1) end
                end
                local pctOfMax = (capacity and capacity > 0) and (((carried or 0) + loadEff) / capacity * 100) or 0
                LootSorter.DBG(("run #%d trip %d/%d visits %d box(es); loadEff=%.1f/%.1f budget -> expect ~%.0f%% of max carry"):format(
                    runId, ti, #plan.trips, nb, loadEff, budget, pctOfMax))
                for _, b in ipairs(trip.visit) do
                    local n, w = 0, 0
                    for _, e in ipairs(trip.perBox[b]) do n = n + 1; w = w + (e.item.weight or 0) end
                    LootSorter.DBG(("  -> box dist=%d: %d item(s) %.2fkg into room %.2fkg (cap*frac=%.1f used=%.1f)"):format(
                        b.dist or -1, n, w, (b.capacity or 0) - (b.used or 0), b.capacity or 0, b.used or 0))
                end
            end
            if not onPlayer then                                  -- 1) load whole trip at source
                for _, entries in pairs(trip.perBox) do           --    (skipped when already carried)
                    for _, e in ipairs(entries) do
                        queueDeposit(e.item.ref, e.item.container or sourceContainer, e.carrier.ref, "load")
                    end
                end
            end
            for _, b in ipairs(trip.visit) do                     -- 2) visit each box nearest-first, deposit
                queueWalk(b.stand)
                for _, e in ipairs(trip.perBox[b]) do
                    local from = onPlayer and sourceContainer or e.carrier.ref  -- deposit straight from the bag if on-player
                    queueDeposit(e.item.ref, from, b.container, "box")
                    queued = queued + 1
                end
            end
            if not onPlayer and ti < #plan.trips then             -- 3) return to source for the NEXT load
                queueWalk(startSquare)                            -- (haul only; skipped after last trip)
            end
        end
        -- arm the watchdog only if we actually queued any walking (onPlayer-only sorts never walk)
        LootSorter._sortProgress = (walkIdx > 0) and { runId = runId, total = walkIdx } or nil
        local leftover = #plan.leftover
        local R = plan.leftoverReasons or {}
        local full, carry, nomatch = R.full or 0, R.carry or 0, R.nomatch or 0
        LootSorter.DBG(("run #%d: %d trip(s) total"):format(runId, #plan.trips))
        LootSorter.DBG(("run #%d queued %d items; %d left (full=%d carry=%d nomatch=%d)"):format(runId, queued, leftover, full, carry, nomatch))
        if #depLog > 0 then   -- one consolidated line: every queued deposit (seq/phase/item) for start-gap tracing
            LootSorter.DBG(("run #%d queued %d deposit-actions: %s"):format(runId, #depLog, table.concat(depLog, ", ")))
        end
        if leftover > 0 and (LootSorter.isDebug()) then
            local names = {}
            for i, it in ipairs(plan.leftover) do names[i] = ("%s(%.2f)"):format(it.name or "?", it.weight or 0) end
            LootSorter.DBG(("run #%d leftover items (%d): %s"):format(runId, leftover, table.concat(names, ", ")))
        end
        -- Terminal marker for a no-op run: nothing was queued, so no walk was armed and the watchdog's
        -- complete/interrupted signal never fires. Log an explicit ending so every run has one (and a
        -- 0-queue run isn't mistaken for one still in flight).
        if walkIdx == 0 then
            LootSorter.DBG(("run #%d done: nothing to distribute (0 queued, %d left)"):format(runId, leftover))
        end
        if queued > 0 then
            if leftover > 0 then
                LootSorter.notify(player, ("Sorting %d items (%d couldn't be placed)"):format(queued, leftover))
            else LootSorter.notify(player, ("Sorting %d items"):format(queued)) end
        elseif leftover == 0 then
            LootSorter.notify(player, "Nothing here to sort.")
        else
            -- nothing could be placed: report why (combine if more than one reason applies)
            local parts = {}
            if full > 0    then parts[#parts + 1] = "designated boxes are full" end
            if carry > 0   then parts[#parts + 1] = "no room in your inventory to carry" end
            if nomatch > 0 then parts[#parts + 1] = "nothing matches your designated boxes" end
            local msg = table.concat(parts, "; ")
            msg = string.upper(string.sub(msg, 1, 1)) .. string.sub(msg, 2) .. "."
            LootSorter.notify(player, msg)
        end
    end)
    if not ok then LootSorter.DBG("SORT ERROR: " .. tostring(err)) end
end

LootSorter.DBG("core loaded")
