-- Opt-in test observer. Wrap public dispatch points only, for one measured phase.
-- Pane classes/instances stay untouched: BC repairs class identity every tick,
-- and Toolkit owns the instance deferred-row gate. Native source profiling
-- measures executed pane refreshes without replacing either owner's callback.
local Profile = {}
local phase, clock, encode, emit, options, patches, stack, metrics, samples
local rows = {}
local completed = {}
local output = 'base-walking-inventory-discovery.jsonl.txt'
local function pack(...) return {n=select('#', ...), ...} end
local function own(object, key)
    -- Kahlua rawget also searches metatables; enumerate actual owned fields.
    for name, value in pairs(object) do if name == key then return value end end
end
local function settings()
    local effective = options.getEffectivePermissions()
    return {nestedPlayer=options.enableNestedContainers_Player,
        nestedLoot=options.enableNestedContainers_Loot,depth=options.nestedContainersDepth,
        playerFilter=options.nestedContainersPlayerFilter,parentIcon=options.showNestedContainerParentIcon,
        proximity=effective.proximityActive,corpseOnly=effective.corpseOnly,autoLock=effective.autoLock,
        dualMode=effective.dualMode,showCorpsesOnlyWhenNearby=effective.showCorpsesOnlyWhenNearby,
        hideIndividualCorpseContainers=effective.hideIndividualCorpseContainers,
        proximityIncludeNestedContainers=options.proximityIncludeNestedContainers}
end
local function cardinality(record, key, value)
    record[key..'_last'] = value
    record[key..'_min'] = math.min(record[key..'_min'] or value, value)
    record[key..'_max'] = math.max(record[key..'_max'] or value, value)
end
local function floorFor(page)
    local floors = ISInventoryPage and ISInventoryPage.floorContainer
    return floors and floors[page.player + 1]
end
local function observe(page)
    local side = page.onCharacter and 'player' or 'loot'
    local record = samples[side]
    record.refreshes = record.refreshes + 1
    cardinality(record, 'buttons', #(page.backpacks or {}))
    if not page.onCharacter then
        local floor = floorFor(page)
        if floor then cardinality(record, 'floor_items', floor:getItems():size()) end
    end
    local state = page.toolkitRefreshState
    if state and state.rowsPending then record.rows_pending = record.rows_pending + 1 end
end
local function wrap(object, key, label, isPage, observeRefresh)
    if not object or type(object[key]) ~= 'function' then return end
    for _, patch in ipairs(patches) do
        if patch.object == object and patch.key == key then return end
    end
    local original, previous = object[key], own(object, key)
    local patch = {object=object,key=key,label=label,previous=previous,enabled=true}
    local function statFor(name)
        if not metrics[name] then metrics[name] = {calls=0,inclusive_ms=0,exclusive_ms=0,max_ms=0,errors=0} end
        return metrics[name]
    end
    statFor(label..'.player'); statFor(label..'.loot')
    if not isPage then statFor(label..'.shared') end
    local wrapper = function(...)
        if not patch.enabled then return original(...) end
        local first = ...
        local page = isPage and first
        local parent = stack[#stack]
        local side = page and (page.onCharacter and 'player' or 'loot') or parent and parent.side or 'shared'
        local name = label..'.'..side
        local stat = statFor(name)
        local floorScope = observeRefresh and not first.onCharacter
        if floorScope then
            local floor = assert(floorFor(first), 'Floor container missing')
            local ok, problem = pcall(baseWalkingInventoryScope, true, floor)
            if not ok then samples.observer_errors=samples.observer_errors+1;error(problem,0) end
        end
        local clockOk, start = pcall(clock)
        if not clockOk then
            if floorScope then pcall(baseWalkingInventoryScope, false, nil) end
            samples.observer_errors=samples.observer_errors+1
            error(start,0)
        end
        local frame = {children=0,side=side}
        stack[#stack+1] = frame
        local values = pack(pcall(original, ...))
        local finishOk, finish = pcall(clock)
        local scopeOk, scopeProblem = true, nil
        if floorScope then scopeOk,scopeProblem=pcall(baseWalkingInventoryScope,false,nil) end
        stack[#stack] = nil
        if not finishOk or not scopeOk then
            samples.observer_errors=samples.observer_errors+1
            if not values[1] then error(values[2],0) end
            error(not finishOk and finish or scopeProblem,0)
        end
        local elapsed = finish - start
        if #stack > 0 then stack[#stack].children = stack[#stack].children + elapsed end
        stat.calls = stat.calls + 1
        stat.inclusive_ms = stat.inclusive_ms + elapsed
        stat.exclusive_ms = stat.exclusive_ms + math.max(0, elapsed - frame.children)
        stat.max_ms = math.max(stat.max_ms, elapsed)
        if not values[1] then stat.errors = stat.errors + 1 end
        if observeRefresh then
            local ok = pcall(observe, first)
            if not ok then samples.observer_errors = samples.observer_errors + 1 end
        end
        if not values[1] then error(values[2], 0) end
        return unpack(values, 2, values.n)
    end
    patch.wrapper = wrapper
    patches[#patches+1] = patch
    object[key] = wrapper
end
local function restore()
    local conflicts, details = 0, {}
    for index=#patches,1,-1 do
        local patch = patches[index]
        patch.enabled = false
        if patch.object[patch.key] == patch.wrapper then
            patch.object[patch.key] = patch.previous
        else
            conflicts = conflicts + 1
            local source = 'unknown'
            if type(getFilenameOfClosure) == 'function' then
                local ok, filename = pcall(getFilenameOfClosure, patch.object[patch.key])
                if ok and type(filename) == 'string' then source = filename end
            end
            details[patch.label..'/'..patch.key] = source
        end
    end
    patches = {}
    return conflicts, details
end
local function write(row)
    assert(#rows < 96, 'Inventory discovery receipt bound exceeded')
    rows[#rows+1] = row
    emit('INVENTORY_DISCOVERY', row)
end
function Profile.begin(number, playerNum, json, log)
    assert(not phase, 'Inventory discovery observer already active')
    assert(number >= 1 and number <= 3 and not completed[number], 'Expected one inventory observation per phase')
    clock = assert(baseWalkingProfileClockMs, 'High-resolution profile clock missing')
    assert(clock() >= 0, 'High-resolution profile clock unavailable')
    encode, emit = json, log
    options = require 'BetterContainers/_Options'
    local initial = settings()
    patches, stack, metrics = {}, {}, {}
    samples = {player={refreshes=0,rows_pending=0},loot={refreshes=0,rows_pending=0},observer_errors=0}
    phase = number
    local ok, problem = pcall(function()
        for _, page in ipairs({getPlayerInventory(playerNum), getPlayerLoot(playerNum)}) do
            local class = assert(getmetatable(page), 'Inventory page class missing')
            for _, name in ipairs({'refreshBackpacks','addContainerButton','checkExplored','refreshWeight','updateItemCount'}) do
                wrap(class, name, 'page.'..name, true, name == 'refreshBackpacks')
            end
            assert(page.inventoryPane, 'Inventory pane missing')
        end
        wrap(require 'BetterContainers/Nested', 'OnButtonsAdded', 'bc.Nested.OnButtonsAdded', true)
        local proximity = require 'BetterContainers/Proximity'
        wrap(proximity, 'OnBeginRefresh', 'bc.Proximity.OnBeginRefresh', true)
        wrap(proximity, 'OnButtonsAdded', 'bc.Proximity.OnButtonsAdded', true)
        wrap(options, 'getEffectivePermissions', 'bc.Options.getEffectivePermissions', false)
        write({kind='begin',phase=phase,settings=initial,clock='monotonic_ms',
            paneMetric='native source callbacks; pane class and instance unchanged',observer=true})
    end)
    if not ok then restore(); phase=nil; error(problem, 0) end
end
function Profile.finishPhase(aborted)
    if not phase then return end
    local number = phase
    local conflicts, details = restore()
    phase = nil
    completed[number] = true
    local names = {}
    for name in pairs(metrics) do names[#names+1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local stat = metrics[name]
        write({kind='timing',phase=number,name=name,calls=stat.calls,
            inclusive_ms=stat.inclusive_ms,exclusive_ms=stat.exclusive_ms,max_ms=stat.max_ms,errors=stat.errors})
    end
    write({kind='end',phase=number,aborted=aborted==true,samples=samples,settings=settings(),
        restore_conflicts=conflicts,restore_conflict_details=details,observerOverheadIncluded=true})
    local writer = assert(getFileWriter(output, true, false))
    for _, row in ipairs(rows) do writer:write(encode(row)..'\n') end
    writer:close()
    local labels = {}
    for label in pairs(details) do labels[#labels+1] = label end
    table.sort(labels)
    assert(conflicts == 0, 'Inventory observer callback changed during phase: '..table.concat(labels,', ')
        ..'; successor preserved')
end
function Profile.finish() Profile.finishPhase(true) end
return Profile
