-- Observations of the original road dumpster. No fixture commands carry its items.
local config = require "QueueTestSelection"
if config.suite ~= "loot-demand" or not config.options or config.options.loot_demand_orange_pair ~= true then return end
LootDemandOrangePair = {}
local P = LootDemandOrangePair
local parts = {
    {x=10634, y=10376, sprite="trashcontainers_01_13"},
    {x=10634, y=10377, sprite="trashcontainers_01_12"},
}
local function locate(part)
    local square = getCell():getGridSquare(part.x, part.y, 0)
    local obj = square and square:getObjects():size() > 1 and square:getObjects():get(1)
    assert(obj and obj:getSprite() and obj:getSprite():getName() == part.sprite, "Natural orange dumpster part missing: "..part.sprite)
    local container = obj:getContainer()
    assert(container and container:getType() == "dumpster", "Wrong native orange container")
    return container
end
local function witness(container)
    local result = {}
    for key, value in lootDemandCensusWitness(container):gmatch("([%w_]+)=([^\n]+)") do
        result[key] = tonumber(value) or value
    end
    return result
end
local function line(kind, message)
    print("[LOOT_ORANGE] "..kind.." "..message)
end
function P.prepareServer(arm)
    for _,part in ipairs(parts) do
        local c = locate(part)
        part.container = c
        if arm == "defer" then
            assert(not c:isExplored() and c:isEmpty(), "Orange part already generated before approach")
            if witness(c).known == "false" then assert(lootDemandWatch(c), "Missing native first-fill observer") end
        else
            assert(c:isExplored(), "Ordinary orange part was not explored before approach")
        end
    end
end
function P.authority(arm, approachClock)
    local rows = {}
    for i,part in ipairs(parts) do
        local c = locate(part)
        assert(c == part.container, "Orange part changed during the approach")
        if not c:isExplored() then return end
        local w = witness(c)
        if w.known == "true" and w.active_depth > 0 then return end
        if w.known == "true" then
            assert(w.active_depth == 0 and w.concurrent_fills == 0 and w.fill_failed == 0
                and w.reentries == 0 and w.repeat_fills == 0, "Invalid native orange fill")
        end
        if arm == "defer" then
            assert(w.known == "true" and w.fill_kind == "demand" and w.fill_ns >= 0
                and w.first_fill_ns >= approachClock, "Missing first demand for actual orange section")
        end
        rows[i] = {sprite=part.sprite, fingerprint=lootDemandFingerprint(c), count=c:getItems():size(),
            fill_ns=w.fill_ns or -1, first_fill_ns=w.first_fill_ns or 0, origin=w.origin}
    end
    for _,row in ipairs(rows) do
        line("SERVER","sprite="..row.sprite.." count="..row.count.." hash="..row.fingerprint.." fill_ns="..tostring(row.fill_ns)
            .." first_fill_ns="..tostring(row.first_fill_ns).." origin="..row.origin)
    end
    return rows
end
local renders
function P.startClient()
    for _,part in ipairs(parts) do
        part.container = locate(part)
        part.observed = {}
    end
    renders = {}
end
if isClient() then Events.OnPostRender.Add(function()
    if renders and #renders < 8192 then renders[#renders + 1] = lootDemandClock() end
end) end
function P.sampleClient(page)
    for _,part in ipairs(parts) do
        local c = locate(part)
        assert(c == part.container, "Client orange part changed during approach")
        local listed = false
        for _,button in ipairs(page.backpacks or {}) do
            if button.inventory == c then listed = true; break end
        end
        if listed then
            local now = lootDemandClock()
            part.listed = part.listed or now
            if c:isExplored() then
                local hash = lootDemandFingerprint(c)
                part.observed[hash] = part.observed[hash] or {at=now, count=c:getItems():size()}
            end
        end
    end
end
function P.delivered(rows)
    assert(type(rows) == "table" and #rows == 2, "Incomplete authoritative orange pair")
    local first, last
    for i,part in ipairs(parts) do
        local row = rows[i]
        assert(row.sprite == part.sprite, "Unexpected authority part")
        local seen = part.observed[row.fingerprint]
        if not seen or seen.count ~= row.count then return false end
        first = math.min(first or part.listed, part.listed)
        last = math.max(last or seen.at, seen.at)
    end
    if #renders < 2 or renders[#renders] <= last then return false end
    assert(#renders < 8192 and renders[1] < first, "Render timeline does not bracket first access")
    local longest, intervals = 0, 0
    for i=2,#renders do
        if renders[i] >= first and renders[i-1] <= last then
            longest = math.max(longest, renders[i]-renders[i-1])
            intervals = intervals + 1
        end
    end
    assert(intervals > 0, "No client render callbacks across access")
    for i,part in ipairs(parts) do
        local row = rows[i]
        line("CLIENT","sprite="..part.sprite.." count="..row.count.." hash="..row.fingerprint
            .." listed_ns="..tostring(part.listed).." ready_ns="..tostring(part.observed[row.fingerprint].at))
    end
    line("WINDOW","list_to_both_ns="..tostring(last-first).." max_render_gap_ns="..tostring(longest).." intervals="..intervals)
    renders = nil
    return true
end
