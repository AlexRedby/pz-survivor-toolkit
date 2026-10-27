-- LootSorter pure planner: NO engine calls. Takes plain data, returns a trip plan.
-- This is the testable heart of the mod (routing + overflow + carry-load/trip batching).
--
-- Inputs (all plain Lua tables):
--   items    = { {ref, cat=<string>, name=<display name string>, weight=<num>}, ... }
--   boxes    = { {ref, cats={[catName]=true}, items={[displayName]=true}, capacity=<num>, used=<num>, dist=<num>, priority=<num|nil>}, ... }
--              (nearest-first; reordered internally by priority -- higher first, 0 default -- with
--               distance breaking ties)
--   carriers = { {ref, factor=<num 0..1>, space=<num>}, ... }  (bags-first = lowest factor first)
--   budget   = <num>  effective-weight room before overburden
--   Designations are read-only snapshots for this plan; callbacks must not rewrite them.
--   noDuplicates boxes supply existingTypes[fullType] = first existing item ref.
--   Item records supply fullType. Reservations apply across the whole haul, not per trip.
--   matches  = optional function(box, item) -> bool : category/tag match; explicit item names still win.
--   accepts  = optional function(carrierRef, itemRef) -> bool : may this carrier hold this item?
--              Injected so the pure planner never calls the engine directly -- in-game it wraps
--              ItemContainer:isItemAllowed (so a Key Ring / wallet / ammo strap won't be used as a
--              general haul bag); tests pass a stub. Defaults to "accept everything" when omitted, so
--              existing callers/tests are unaffected. It is a pure READ: eligibility is captured
--              before destination reservation and reused when placing items into carry-loads.
--   acceptsDestination = optional function(box, item) -> bool : may this destination hold this item?
--              Called only for matching boxes with enough planned space, with the original records.
--              Defaults to accepting all destinations. This does not change designation matching;
--              matching boxes that reject an item count as unavailable ("full"), not "nomatch".
--
-- Output:
--   { trips = { { perBox = {[boxRec]={ {item=itemRec, carrier=carrierRec}, ...}}, visit = {boxRec,...} }, ... },
--     leftover = { itemRec, ... } }

LootSorter = LootSorter or {}

-- Priority is a plain number: HIGHER wins, 0 is the default, and negatives push a box below the ones
-- that never mention it. Absent means 0, so every box designated before this existed and every caller
-- that passes no priority behave exactly as they did. Open-ended on purpose -- nothing here cares
-- whether a UI offers three levels or twenty.
--
-- Boxes arrive nearest-first and the matching loops below take the FIRST box with room, so the order
-- of this list IS the preference. Priority therefore needs no new matching logic: it reorders, and
-- distance breaks ties. table.sort is not stable, so the incoming order is the final tiebreak --
-- without it, two equal boxes could swap between runs and route the same haul differently.
local function inPreferenceOrder(boxes)
    local ordered, incoming = {}, {}
    for index, b in ipairs(boxes) do
        ordered[index] = b
        incoming[b] = index
    end
    table.sort(ordered, function(a, b)
        local pa, pb = a.priority or 0, b.priority or 0
        if pa ~= pb then return pa > pb end
        local da, db = a.dist or 0, b.dist or 0
        if da ~= db then return da < db end
        return incoming[a] < incoming[b]
    end)
    return ordered
end

-- Resolve each requested display name once per plan. Do not enumerate every
-- designation in large presets when only one item/name is being distributed.
local function boxesForItemName(index, boxes, name)
    local candidates = index[name]
    if not candidates then
        candidates = {}
        for _, box in ipairs(boxes) do
            local names = box.items
            if names and names[name] then candidates[#candidates + 1] = box end
        end
        index[name] = candidates
    end
    return candidates
end

function LootSorter.planTrips(items, boxes, carriers, budget, accepts, matches, acceptsDestination)
    accepts = accepts or function() return true end
    matches = matches or function(box, item) return item.cat and box.cats and box.cats[item.cat] end
    acceptsDestination = acceptsDestination or function() return true end
    boxes = inPreferenceOrder(boxes)
    local namedBoxes = {}
    -- 1) assign each item to a same-category box WITH ROOM, cascading to further same-cat boxes.
    -- Only items with a roomy, accepting carrier may reserve destination space.
    -- Otherwise an impossible haul can block later items or force them into overflow boxes.
    local byBox, boxUsed, leftover, carrierChoices, reservedTypes = {}, {}, {}, {}, {}
    local function scope(box) return box.duplicateScope or box end
    local function existingKeeper(box, item)
        return box.noDuplicates and item.fullType and box.existingTypes
            and box.existingTypes[item.fullType] == item.ref and box.container == item.container
    end
    local function admits(box, item)
        if box.noDuplicates then
            if not item.fullType then return false end
            local existing = box.existingTypes and box.existingTypes[item.fullType]
            if (existing and not existingKeeper(box, item))
                or (reservedTypes[scope(box)] and reservedTypes[scope(box)][item.fullType]) then return false end
            -- Sorting this very shelf must keep its first copy, even when the shelf is full.
            if existingKeeper(box, item) then return true end
        end
        return (boxUsed[box] + item.weight) <= box.capacity and acceptsDestination(box, item)
    end
    -- why leftover items couldn't be placed, so the caller can show a clear message:
    --   carry   = no carrier has both enough room and permission to hold the item
    --   full    = a box IS designated for it, but every matching box is full or rejects it
    --   nomatch = no designated box for this item's category/name at all
    local reasons = { carry = 0, full = 0, nomatch = 0 }
    local function addLeftover(it, why) leftover[#leftover + 1] = it; reasons[why] = (reasons[why] or 0) + 1 end
    for _, b in ipairs(boxes) do boxUsed[b] = b.used or 0 end
    for _, it in ipairs(items) do
        local choices = {}
        for ci, c in ipairs(carriers) do
            if (c.space or 0) >= it.weight and accepts(c.ref, it.ref) then choices[#choices + 1] = ci end
        end
        carrierChoices[it] = choices
        local dest, matched = nil, false
        if #choices > 0 then
            -- pass 1: a box that names THIS item (by display name) wins over any category box
            if it.name then
                for _, b in ipairs(boxesForItemName(namedBoxes, boxes, it.name)) do
                    matched = true
                    if admits(b, it) then
                        dest = b; break
                    end
                end
            end
            -- pass 2: otherwise fall back to a same-category box (cascading to further same-cat boxes)
            if not dest then
                for _, b in ipairs(boxes) do
                    if matches(b, it) then
                        matched = true
                        if admits(b, it) then
                            dest = b; break
                        end
                    end
                end
            end
        end
        if dest then
            if not existingKeeper(dest, it) then boxUsed[dest] = boxUsed[dest] + it.weight end
            if dest.noDuplicates then
                local key = scope(dest)
                reservedTypes[key] = reservedTypes[key] or {}
                reservedTypes[key][it.fullType] = true
            end
            byBox[dest] = byBox[dest] or {}
            table.insert(byBox[dest], it)
        elseif #choices == 0 then
            addLeftover(it, "carry")
        else
            -- The completed search already distinguished unavailable designations
            -- from no match; do not repeat every rule evaluation for the reason.
            addLeftover(it, matched and "full" or "nomatch")
        end
    end

    -- 2) flatten assigned items (tagged with destination box)
    local plan = {}
    for b, list in pairs(byBox) do
        for _, it in ipairs(list) do plan[#plan + 1] = { item = it, box = b } end
    end

    -- 3) build carry-loads spanning MULTIPLE boxes; one trip distributes to all (nearest-first)
    local trips = {}
    local pidx = 1
    while pidx <= #plan do
        local free = {}
        for ci, c in ipairs(carriers) do free[ci] = c.space end
        local perBox, loadEff, anyLoaded = {}, 0, false
        while pidx <= #plan do
            local it, b = plan[pidx].item, plan[pidx].box
            local w = it.weight
            local placed = false
            -- Preserve bags-first order; only remaining space changes between loads.
            for _, ci in ipairs(carrierChoices[it]) do
                local c = carriers[ci]
                if free[ci] >= w then
                    local addEff = w * c.factor
                    if (not anyLoaded) or (loadEff + addEff) <= budget then
                        perBox[b] = perBox[b] or {}
                        table.insert(perBox[b], { item = it, carrier = c })
                        free[ci] = free[ci] - w; loadEff = loadEff + addEff
                        anyLoaded = true; pidx = pidx + 1; placed = true
                        break
                    end
                end
            end
            if not placed then
                if not anyLoaded then addLeftover(it, "carry"); pidx = pidx + 1 -- fits no carrier this trip
                else break end                            -- carry-load full
            end
        end
        if not anyLoaded then break end
        local visit = {}
        for b in pairs(perBox) do visit[#visit + 1] = b end
        table.sort(visit, function(a, b) return (a.dist or 0) < (b.dist or 0) end)
        trips[#trips + 1] = { perBox = perBox, visit = visit }
    end

    return { trips = trips, leftover = leftover, leftoverReasons = reasons }
end

-- Drop trip entries already sitting in their destination (box.container == sourceContainer) -- an
-- item is already there, so hauling it out and back in is a no-op. Returns the filtered trips + cut count.
function LootSorter.stripSelfPlacements(trips, sourceContainer)
    local kept, cut = {}, 0
    for _, trip in ipairs(trips) do
        local perBox, visit = {}, {}
        for _, b in ipairs(trip.visit) do
            local entries = trip.perBox[b]
            local filtered = {}
            for _, e in ipairs(entries) do
                local origin = e.item.container or sourceContainer
                if origin == b.container then
                    cut = cut + 1
                else
                    filtered[#filtered + 1] = e
                end
            end
            if #filtered > 0 then
                perBox[b] = filtered
                visit[#visit + 1] = b
            end
        end
        if #visit > 0 then
            kept[#kept + 1] = { perBox = perBox, visit = visit }
        end
    end
    return kept, cut
end
