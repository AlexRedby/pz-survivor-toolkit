-- Test-only native Lua microbenchmark. No drawing, FPS estimate or gameplay writes.
-- Call start(pane, realItems) with a nonempty Lua array of physical items, then
-- step() once per OnTick, outside the timed render profile. step() returns nil
-- until the final block, when it returns the complete serializable result table.
-- No module-owned event handlers or per-block logging are installed.
-- Require this module BEFORE installing fixture profiling wrappers, so both
-- research variants measure their implementation without instrumentation.
local Research = require "PZSurvivorToolkit/InventoryResearch"
local currentShouldShow = Research.shouldShow
local Benchmark = {}
local active
local ICONS, CYCLES, SERIES = 24, 1000, 6
local SLOTS = {"a1_ms", "b1_ms", "b2_ms", "a2_ms"}

local function legacyResearch()
    -- Frozen owned source: InventoryResearch.shouldShow from repository commit
    -- 8c05b9a9e804999c63bd6a931e9fbc3a4f89d5aa. Keep this timed function unchanged.
    -- Its private cache has the original TTL/cap. No legacy event handlers are
    -- installed: per-block warmup/parity checks reject changed eligibility.
    local CACHE_TTL_MS, MAX_CACHE_ENTRIES = 500, 256
    local caches = {}
    return function(pane, item)
        if not pane or not item then return false end
        local player = getSpecificPlayer(pane.player or 0)
        local script = item:getScriptItem()
        if not player or not script then return false end

        local now = getTimestampMs()
        local recipes = player:getKnownRecipes()
        local knownCount = recipes and recipes:size() or -1
        local index = player:getPlayerNum()
        local cache = caches[index]
        if not cache or cache.player ~= player or cache.knownCount ~= knownCount or now >= cache.expiresAt then
            cache = {player = player, knownCount = knownCount, expiresAt = now + CACHE_TTL_MS,
                entries = {}, count = 0}
            caches[index] = cache
        end
        local cached = cache.entries[script]
        if cached ~= nil then return cached end
        if cache.count >= MAX_CACHE_ENTRIES then
            cache.entries, cache.count, cache.expiresAt = {}, 0, now + CACHE_TTL_MS
        end

        -- true excludes recipes already known by this player; native canResearch also checks skill gates.
        local available = script:getResearchableRecipes(player, true)
        local result = available ~= nil and available:size() > 0
        cache.entries[script], cache.count = result, cache.count + 1
        return result
    end
end

local function groupValue(group)
    if group == nil then return 0 end
    return group and 2 or 1
end

local function fieldsChecksum(ids, item, x, y, width, height, group)
    return assert(ids[item], "buffer changed item identity") * 3
        + x * 5 + y * 7 + width * 11 + height * 13 + groupValue(group) * 17
end

local function researchBlock(state, contextual)
    local checksum = 0
    local shouldShow = contextual and state.shouldShow or state.legacy
    for cycle = 1, CYCLES do
        -- Match one context per 24-icon render, rather than sharing one across
        -- this whole timing block. The direct control allocates no context.
        local context = contextual and {} or nil
        for index = 1, ICONS do
            if shouldShow(state.pane, state.rows[index].item, context) then
                checksum = checksum + index
            end
        end
    end
    return checksum
end

local function recordsBlock(state)
    local checksum, rows, ids = 0, state.rows, state.ids
    for cycle = 1, CYCLES do
        -- Mirror InventoryPresentation's current six-field ephemeral records.
        local icons = {}
        for index = 1, ICONS do
            local source = rows[index]
            icons[#icons + 1] = {item=source.item, x=source.x, y=source.y,
                width=source.width, height=source.height, group=source.group}
        end
        for _, icon in ipairs(icons) do
            checksum = checksum + fieldsChecksum(ids, icon.item, icon.x, icon.y,
                icon.width, icon.height, icon.group)
        end
    end
    return checksum
end

local function flatBlock(state)
    local checksum, rows, ids = 0, state.rows, state.ids
    for cycle = 1, CYCLES do
        local icons, count = {}, 0
        for index = 1, ICONS do
            local source = rows[index]
            local offset = count * 6
            icons[offset + 1], icons[offset + 2], icons[offset + 3] = source.item, source.x, source.y
            icons[offset + 4], icons[offset + 5], icons[offset + 6] = source.width, source.height, source.group
            count = count + 1
        end
        -- Never use # on the flat array: nullable group fields leave holes.
        for offset = 0, (count - 1) * 6, 6 do
            checksum = checksum + fieldsChecksum(ids, icons[offset + 1], icons[offset + 2],
                icons[offset + 3], icons[offset + 4], icons[offset + 5], icons[offset + 6])
        end
    end
    return checksum
end

-- Synthetic column comparison hoists the arrays into locals. A real capture
-- callback would access them through its context; this is not a qualified
-- measurement of that integration and cannot justify a renderer change alone.
local function columnsBlock(state)
    local checksum, rows, ids = 0, state.rows, state.ids
    for cycle = 1, CYCLES do
        local items, xs, ys, widths, heights, groups = {}, {}, {}, {}, {}, {}
        local count = 0
        for index = 1, ICONS do
            local source = rows[index]
            count = count + 1
            items[count], xs[count], ys[count] = source.item, source.x, source.y
            widths[count], heights[count], groups[count] = source.width, source.height, source.group
        end
        for index = 1, count do
            checksum = checksum + fieldsChecksum(ids, items[index], xs[index], ys[index],
                widths[index], heights[index], groups[index])
        end
    end
    return checksum
end

local BUFFER_BLOCKS = {records=recordsBlock, flat=flatBlock, soa=columnsBlock}

local function addComparison(state, name, first, second)
    local comparison = {a=first, b=second, samples={}, a_total_ms=0, b_total_ms=0}
    state.result[name] = comparison
    for series = 1, SERIES do
        local sample = {series=series}
        comparison.samples[#comparison.samples + 1] = sample
        for slot, variant in ipairs({first, second, second, first}) do
            state.jobs[#state.jobs + 1] = {name=name, variant=variant,
                sample=sample, slot=SLOTS[slot], position=slot, comparison=comparison}
        end
    end
end

function Benchmark.start(pane, realItems)
    assert(not active, "inventory microbenchmark already running")
    assert(pane and type(realItems) == "table" and #realItems > 0,
        "inventory microbenchmark needs a pane and physical item array")
    local state = {pane=pane, rows={}, ids={}, jobs={}, nextJob=1,
        shouldShow=currentShouldShow, legacy=legacyResearch()}
    local height = math.floor(tonumber(pane.itemHgt) or 30)
    local header = math.floor(tonumber(pane.headerHgt) or 0)
    local unique, bufferChecksum = 0, 0
    for index = 1, ICONS do
        local item = assert(realItems[(index - 1) % #realItems + 1])
        if not state.ids[item] then
            unique = unique + 1
            state.ids[item] = unique
        end
        local group
        if index % 3 == 0 then group = true
        elseif index % 3 == 1 then group = false end
        local row = {item=item, x=26 + index % 3, y=header + (index - 1) * height,
            width=18 + index % 4 * 4, height=18 + index % 5 * 3, group=group}
        state.rows[index] = row
        bufferChecksum = bufferChecksum + fieldsChecksum(state.ids, row.item,
            row.x, row.y, row.width, row.height, row.group)
    end
    state.bufferChecksum = bufferChecksum * CYCLES
    state.result = {format=1, samples={}, units="ms", order="ABBA", series=SERIES,
        icons_per_cycle=ICONS, cycles_per_block=CYCLES, unique_items=unique,
        control="InventoryResearch.shouldShow@8c05b9a9e804999c63bd6a931e9fbc3a4f89d5aa",
        limits="Native Lua callback/buffer microbenchmark; no draw calls or FPS evidence. "
            .. "Research direct is frozen legacy, context is current; both caches are warmed before every block. "
            .. "Normal TTL remains active; no legacy event handlers are installed. "
            .. "Buffers are ephemeral each cycle; columns hoist arrays unlike real capture callbacks. "
            .. "GC and millisecond timer noise remain included."}
    addComparison(state, "research", "direct", "context")
    addComparison(state, "flat", "records", "flat")
    addComparison(state, "soa", "records", "soa")
    state.result.blocks = #state.jobs
    active = state
    return {blocks=#state.jobs, icons_per_cycle=ICONS, cycles_per_block=CYCLES}
end

local function runBlock(state, job)
    local expected
    if job.name == "research" then
        local cycleChecksum = 0
        -- Warm the real script cache outside the timer. Also detect changed
        -- eligibility between blocks instead of comparing unequal workloads.
        for index = 1, ICONS do
            local item = state.rows[index].item
            local direct = state.legacy(state.pane, item)
            local current = state.shouldShow(state.pane, item)
            assert(direct == current, "legacy/current research eligibility differs during warmup")
            if direct then
                cycleChecksum = cycleChecksum + index
            end
        end
        expected = cycleChecksum * CYCLES
        if state.researchChecksum == nil then state.researchChecksum = expected end
        assert(expected == state.researchChecksum, "research eligibility changed between benchmark blocks")
    else
        expected = state.bufferChecksum
    end
    local before = getTimestampMs()
    local checksum
    if job.name == "research" then checksum = researchBlock(state, job.variant == "context")
    else checksum = BUFFER_BLOCKS[job.variant](state) end
    local elapsed = getTimestampMs() - before
    assert(elapsed >= 0, "inventory microbenchmark clock moved backwards")
    assert(checksum == expected, "inventory microbenchmark checksum differs: " .. job.variant)
    job.sample[job.slot], job.sample.checksum = elapsed, checksum
    state.result.samples[#state.result.samples + 1] = {family=job.name, series=job.sample.series,
        slot=job.position, variant=job.variant, ms=elapsed, calls=ICONS * CYCLES, checksum=checksum}
    if job.variant == job.comparison.a then
        job.comparison.a_total_ms = job.comparison.a_total_ms + elapsed
    else
        job.comparison.b_total_ms = job.comparison.b_total_ms + elapsed
    end
end

function Benchmark.step()
    local state = active
    if not state then return nil end
    local job = state.jobs[state.nextJob]
    local ok, message = pcall(runBlock, state, job)
    if not ok then active = nil; error(message) end
    state.nextJob = state.nextJob + 1
    if state.nextJob <= #state.jobs then return nil end
    active = nil
    return state.result
end

return Benchmark
