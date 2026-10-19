-- LootSorter: PURE manifest aggregation (no engine calls -> unit-testable).
-- Sums the per-box snapshot store into a single flat, sorted item list for the manifest window.
--
-- store = { [coordKey] = { [displayName] = { n = <count>, ft = <fullType>, cat = <display category> } }, ... }
-- returns { { name=<display>, n=<total count>, ft=<fullType>, cat=<display category> }, ... }
--   sortBy = "name" | "count" | "cat"   asc = bool (nil = ascending)
LootSorter = LootSorter or {}

function LootSorter.manifestAggregate(store, sortBy, asc)
    local total = {}
    for _, boxItems in pairs(store or {}) do
        for nm, e in pairs(boxItems) do
            local t = total[nm]
            if not t then t = { name = nm, n = 0, ft = e.ft, cat = e.cat }; total[nm] = t end
            t.n = t.n + (e.n or 0)
            if not t.ft then t.ft = e.ft end
            if not t.cat then t.cat = e.cat end
        end
    end

    local list = {}
    for _, t in pairs(total) do list[#list + 1] = t end

    if asc == nil then asc = true end
    table.sort(list, function(a, b)
        local av, bv
        if sortBy == "count" then av, bv = a.n, b.n
        elseif sortBy == "cat" then av, bv = (a.cat or ""), (b.cat or "")
        else av, bv = a.name, b.name end
        if av == bv then return a.name < b.name end   -- stable tiebreak by name (ascending)
        if asc then return av < bv else return av > bv end
    end)
    return list
end
