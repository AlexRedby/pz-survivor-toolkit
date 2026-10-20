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
--   matches  = optional function(box, item) -> bool : category/tag match; explicit item names still win.
--   accepts  = optional function(carrierRef, itemRef) -> bool : may this carrier hold this item?
--              Injected so the pure planner never calls the engine directly -- in-game it wraps
--              ItemContainer:isItemAllowed (so a Key Ring / wallet / ammo strap won't be used as a
--              general haul bag); tests pass a stub. Defaults to "accept everything" when omitted, so
--              existing callers/tests are unaffected. It is a pure READ: it gates WHICH carrier an item
--              may go in, never the space/weight math (that only mutates on actual placement).
--   acceptsDestination = optional function(box, item) -> bool : may this destination hold this item?
--              Called only for matching boxes with enough planned space, with the original records.
--              Defaults to accepting all destinations. This does not change designation matching;
--              matching boxes that reject an item count as unavailable ("full"), not "nomatch".
--
-- Output:
--   { trips = { { perBox = {[boxRec]={ {item=itemRec, carrier=carrierRec}, ...}}, visit = {boxRec,...} }, ... },
--     leftover = { itemRec, ... } }

LootSorter = LootSorter or {}

local function hasAny(t) if t then for _ in pairs(t) do return true end end return false end

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

function LootSorter.planTrips(items, boxes, carriers, budget, accepts, matches, acceptsDestination)
    accepts = accepts or function() return true end
    matches = matches or function(box, item) return item.cat and box.cats and box.cats[item.cat] end
    acceptsDestination = acceptsDestination or function() return true end
    boxes = inPreferenceOrder(boxes)
    -- 1) assign each item to a same-category box WITH ROOM, cascading to further same-cat boxes.
    -- An item heavier than the biggest carrier can never be carried, so it must NOT reserve box
    -- space -- otherwise it starves a smaller same-category item that could actually be hauled.
    local byBox, boxUsed, leftover = {}, {}, {}
    -- why leftover items couldn't be placed, so the caller can show a clear message:
    --   carry   = too heavy / no room in the player's carriers (inventory)
    --   full    = a box IS designated for it, but every matching box is full or rejects it
    --   nomatch = no designated box for this item's category/name at all
    local reasons = { carry = 0, full = 0, nomatch = 0 }
    local function addLeftover(it, why) leftover[#leftover + 1] = it; reasons[why] = (reasons[why] or 0) + 1 end
    for _, b in ipairs(boxes) do boxUsed[b] = b.used or 0 end
    local maxCarrier = 0
    for _, c in ipairs(carriers) do if (c.space or 0) > maxCarrier then maxCarrier = c.space end end
    for _, it in ipairs(items) do
        local dest = nil
        if it.weight <= maxCarrier then                  -- only route items that can actually be carried
            -- pass 1: a box that names THIS item (by display name) wins over any category box
            if it.name then
                for _, b in ipairs(boxes) do             -- boxes nearest-first
                    if b.items and b.items[it.name] and (boxUsed[b] + it.weight) <= b.capacity
                        and acceptsDestination(b, it) then
                        dest = b; break
                    end
                end
            end
            -- pass 2: otherwise fall back to a same-category box (cascading to further same-cat boxes)
            if not dest then
                for _, b in ipairs(boxes) do
                    if matches(b, it) and (boxUsed[b] + it.weight) <= b.capacity
                        and acceptsDestination(b, it) then
                        dest = b; break
                    end
                end
            end
        end
        if dest then
            boxUsed[dest] = boxUsed[dest] + it.weight
            byBox[dest] = byBox[dest] or {}
            table.insert(byBox[dest], it)
        elseif it.weight > maxCarrier then
            addLeftover(it, "carry")                     -- can't be carried (too heavy / carriers full)
        else
            -- carryable but unplaced: distinguish "matching box(es) full" from "no matching box at all"
            local matched = false
            for _, b in ipairs(boxes) do
                if (it.name and b.items and b.items[it.name]) or matches(b, it) then
                    matched = true; break
                end
            end
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
            for ci, c in ipairs(carriers) do             -- bags first, main last
                -- room check first (cheap) so the injected accepts() -- a possible engine read -- only
                -- runs when this carrier could take the item. accepts() gates eligibility ONLY; the
                -- space/weight bookkeeping below is untouched by it.
                if free[ci] >= w and accepts(c.ref, it.ref) then
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
