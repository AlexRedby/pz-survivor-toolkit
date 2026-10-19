-- Quartermaster: PURE craft-fetch planning (no engine calls -> unit-testable, like LootSorter_Plan).
-- The client engine (LootSorter_Craft.lua) reads the recipe/world via the game API, reduces it to the
-- plain-data shapes below, calls these, then turns the result into walk + transfer + craft actions.
--
-- Data shapes:
--   inputs  = array of { per = <items needed per craft>, tool = <bool: kept, not consumed> }
--   avail   = map { [inputIndex] = <count available across accessible + boxes> }
--   access  = map { [inputIndex] = <count already accessible without fetching> }
--   boxes   = array of boxes; each box = array whose k-th entry is the input index that box's k-th
--             item satisfies, or `false` if it satisfies none. (Use false, never nil -- ipairs stops at nil.)
LootSorter = LootSorter or {}
LootSorter.craftPlan = LootSorter.craftPlan or {}

local function perOf(e) return (e.per and e.per >= 1) and e.per or 1 end

-- Max whole crafts supported by `avail`. A required tool that's absent (avail < 1) forces 0;
-- present tools don't limit the count. Consumables limit by floor(available / per-craft).
function LootSorter.craftPlan.maxCraftable(inputs, avail)
    local maxN, toolMissing = nil, false
    for idx, e in ipairs(inputs) do
        local have = (avail and avail[idx]) or 0
        if e.tool then
            if have < 1 then toolMissing = true end
        else
            local can = math.floor(have / perOf(e))
            if maxN == nil or can < maxN then maxN = can end
        end
    end
    if toolMissing then return 0 end
    return maxN or 0
end

-- Plan which box items to pull for `qty` crafts, given what's already accessible.
-- Greedy, nearest-box-first (boxes are assumed pre-sorted by distance). Reserves exactly the shortfall;
-- tools are fetched once (need 1) and only if not already accessible.
-- Returns { trips = { { box=<boxIndex>, picks={ <itemIndex>, ... } }, ... }, shortfall = { [inputIdx]=remaining } }.
function LootSorter.craftPlan.plan(inputs, qty, access, boxes)
    qty = qty or 1; if qty < 1 then qty = 1 end

    local need = {}
    for idx, e in ipairs(inputs) do
        local want = e.tool and 1 or (qty * perOf(e))
        need[idx] = math.max(0, want - ((access and access[idx]) or 0))
    end

    local trips = {}
    for bi, boxItems in ipairs(boxes or {}) do
        local picks = {}
        for ii, matchIdx in ipairs(boxItems) do
            if matchIdx and (need[matchIdx] or 0) > 0 then
                picks[#picks + 1] = ii
                need[matchIdx] = need[matchIdx] - 1
            end
        end
        if #picks > 0 then trips[#trips + 1] = { box = bi, picks = picks } end
    end

    return { trips = trips, shortfall = need }
end
