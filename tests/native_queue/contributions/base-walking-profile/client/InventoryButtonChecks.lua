-- Test-only best-case geometry-mirror feasibility probe. This does not qualify
-- cached geometry for movement, resize, nested callbacks or remote mutations.
local Checks = {}
local batchCalls, rounds, warmupCalls = 256, 5, 8

local function own(object, key)
    -- Kahlua rawget searches the metatable; enumerate actual own fields.
    for name, value in pairs(object) do if name == key then return value end end
end
local function empty(value)
    for _ in pairs(value or {}) do return false end
    return true
end
local function idle(page, pane, player)
    assert(page:getIsVisible() == false and pane.mode == 'details'
        and not page.joyfocus and not pane.joyfocus and not pane.doController and not pane.firstSelect
        and not pane.dragging and not pane.dragStarted and not pane.draggingMarquis
        and not pane.toolkitPendingMarquee and not pane.toolkitVisibleItems and not pane.toolkitCategory
        and not pane.toolkitTag and not pane.toolkitTagRule
        and (not pane.searchText or pane.searchText == '')
        and (not pane.searchCategoryText or pane.searchCategoryText == '') and empty(pane.selected),
        'Button check requires a hidden idle unfiltered loot pane without selection')
    local drag = ISMouseDrag
    assert(not drag or (drag.draggingFocus ~= pane and (drag.dragging == nil
        or type(drag.dragging) == 'table' and #drag.dragging == 0)), 'Inventory drag is active')
    assert(player:getJoypadBind() == -1, 'Button check requires mouse input')
end
local function ordered(list)
    local result = {}
    for index, value in ipairs(list or {}) do result[index] = value end
    return result
end
local function sameOrder(expected, actual, message)
    assert(#expected == #actual, message .. ': count changed')
    for index, value in ipairs(expected) do assert(value == actual[index], message .. ': ordered identity changed') end
end
local function nativeOrder(panel)
    local result, controls = {}, panel.javaObject:getControls()
    for index = 0, controls:size() - 1 do result[index + 1] = controls:get(index) end
    return result
end
local function allButtons(page)
    local result, seen = {}, {}
    for _, list in ipairs({page.backpacks or {}, page.buttonPool or {}}) do
        for _, button in ipairs(list) do
            assert(not seen[button], 'Button appears twice in active/pool lists')
            seen[button] = true
            result[#result + 1] = button
        end
    end
    return result
end
local function geometry(button)
    local native = assert(button.javaObject, 'Button native element missing')
    local result = {x=button.x, y=button.y, width=button.width, height=button.height}
    for _, key in ipairs({'x', 'y', 'width', 'height'}) do
        assert(type(result[key]) == 'number' and result[key] == result[key]
            and math.abs(result[key]) < math.huge, 'Non-numeric button geometry: ' .. key)
    end
    assert(result.x == native:getX() and result.y == native:getY()
        and result.width == native:getWidth() and result.height == native:getHeight(),
        'Button Lua/native geometry mismatch')
    return result
end
local function capture(page, pane, skipItems)
    local panel = assert(page.containerButtonPanel, 'Container button panel missing')
    local result = {inventory=page.inventory, paneInventory=pane.inventory, backpacks=ordered(page.backpacks),
        pool=ordered(page.buttonPool), children=ordered(panel.childrenInOrder), nativeChildren=nativeOrder(panel),
        childrenMap={}, buttons={}}
    for key, value in pairs(panel.children or {}) do result.childrenMap[key] = value end
    assert(#result.children == #result.nativeChildren, 'Lua/native child count mismatch')
    for index, child in ipairs(result.children) do
        assert(child.javaObject == result.nativeChildren[index] and panel.children[child.ID] == child,
            'Lua/native child order or membership mismatch')
    end
    for _, button in ipairs(allButtons(page)) do
        local raw = {}
        assert(button.inventory, 'Button container missing')
        if not skipItems then
            local source = button.inventory:getItems()
            for index = 0, source:size() - 1 do raw[#raw + 1] = source:get(index) end
        end
        result.buttons[#result.buttons + 1] = {button=button, native=button.javaObject,
            inventory=button.inventory, geometry=geometry(button), luaParent=button.parent,
            nativeParent=button.javaObject:getParent(), items=raw}
    end
    return result
end
local function unchanged(expected, page, pane, skipItems)
    local actual = capture(page, pane, skipItems)
    assert(actual.inventory == expected.inventory and actual.paneInventory == expected.paneInventory,
        'Selected inventory changed')
    for _, key in ipairs({'backpacks', 'pool', 'children', 'nativeChildren'}) do
        sameOrder(expected[key], actual[key], key)
    end
    for key, value in pairs(expected.childrenMap) do assert(actual.childrenMap[key] == value, 'Child map changed') end
    for key, value in pairs(actual.childrenMap) do assert(expected.childrenMap[key] == value, 'Child map changed') end
    assert(#expected.buttons == #actual.buttons, 'Button model count changed')
    for index, entry in ipairs(expected.buttons) do
        local current = actual.buttons[index]
        assert(entry.button == current.button and entry.native == current.native
            and entry.inventory == current.inventory and entry.luaParent == current.luaParent
            and entry.nativeParent == current.nativeParent, 'Button identity/container/parent changed')
        for key, value in pairs(entry.geometry) do
            assert(current.geometry[key] == value, 'Original button geometry changed: ' .. key)
        end
        if not skipItems then sameOrder(entry.items, current.items, 'Button container items') end
    end
end

function Checks.run(playerNum, json, log)
    local player = assert(getSpecificPlayer(playerNum), 'Imported player missing')
    local page = assert(getPlayerLoot(playerNum), 'Loot inventory page missing')
    local pane = assert(page.inventoryPane, 'Loot inventory pane missing')
    local state = assert(page.toolkitRefreshState, 'Toolkit loot refresh state missing')
    assert(page.onCharacter == false and getmetatable(page) == CleanUI_Clean_ISInventoryPage,
        'Button check requires the real CleanUI loot page')
    assert(state.scope == 0 and not state.force, 'Loot refresh is already active or forced')
    idle(page, pane, player)
    local clock = assert(baseWalkingExperimentClockMs, 'High-resolution profile clock missing')
    local baseline, patches = capture(page, pane), {}
    assert(#baseline.buttons <= 128, 'Button experiment source bound exceeded')
    local savedForce, savedCollapsed = state.force, page.isCollapsed
    local defaults, defaultSources = {}, {}
    for _, name in ipairs({'setX', 'setY', 'getKeepOnScreen', 'onResize'}) do
        defaults[name] = assert(ISUIElement[name], 'Default UI method missing: ' .. name)
        local source = getFilenameOfClosure(defaults[name])
        assert(type(source) == 'string' and source:match('/media/lua/client/ISUI/ISUIElement%.lua$')
            and not source:lower():find('/mods/', 1, true), 'Button method is not the native source: ' .. name)
        defaultSources[name] = source
    end
    local enabled, counts = false, {called=0, skipped=0}
    local receipt
    local ok, problem = pcall(function()
        for _, entry in ipairs(baseline.buttons) do
            local button, eligible = entry.button, true
            for name, method in pairs(defaults) do
                if own(button, name) ~= nil or button[name] ~= method then eligible = false end
            end
            if getmetatable(button) ~= ISButton or not button.parent or button:getKeepOnScreen() ~= false then
                eligible = false
            end
            if eligible then
                for _, name in ipairs({'setX', 'setY'}) do
                    local key = name == 'setX' and 'x' or 'y'
                    local patch = {button=button, key=name, previous=own(button, name), original=defaults[name], entry=entry}
                    patch.wrapper = function(self, value, ...)
                        if enabled and self[key] == value then counts.skipped = counts.skipped + 1; return end
                        counts.called = counts.called + 1
                        return patch.original(self, value, ...)
                    end
                    patches[#patches + 1] = patch
                    button[name] = patch.wrapper
                end
            end
        end
        assert(#patches > 0, 'No eligible inherited default container buttons')
        receipt = {kind='inventory-button-checks', playerNum=playerNum, callsPerBatch=batchCalls,
            rounds=rounds, warmupPerMode=warmupCalls, totalCalls=batchCalls * rounds * 2,
            clock='baseWalkingExperimentClockMs', timingMethod='sum of complete refreshBackpacks callback intervals; guard branch/counters included; assertions outside timing',
            itemIdentityCheck='before probe, after each warmup/mode batch, and cleanup; geometry/UI identities before and after every callback',
            sourceLimit=128, defaultSources=defaultSources,
            guardedButtons=#patches / 2, batches={}, workload={buttons=#baseline.backpacks, pooledButtons=#baseline.pool,
                sources={}}, limits={testOnly=true, assumesGeometryMirror=true, movement=false, resize=false,
                nestedReentry=false, remoteMutation=false, classHooks=false, paneHooks=false,
                inventoryMutation=false, worldMutation=false, discoveryAndEventsUnchanged=true}}
        for index, entry in ipairs(baseline.buttons) do
            receipt.workload.sources[index] = {button=tostring(entry.button), container=tostring(entry.inventory),
                kind=entry.inventory:getType(), items=#entry.items, geometry=entry.geometry,
                luaParent=tostring(entry.luaParent), nativeParent=tostring(entry.nativeParent)}
        end
        local function guardsIntact()
            for _, patch in ipairs(patches) do
                local button, entry = patch.button, patch.entry
                assert(own(button, patch.key) == patch.wrapper, 'Button setter successor installed during probe')
                assert(getmetatable(button) == ISButton and button.javaObject == entry.native
                    and button.parent == entry.luaParent and button.parent ~= nil,
                    'Guarded button ownership changed')
                for method, original in pairs(defaults) do
                    assert(ISButton[method] == original, 'Default button class method changed')
                    if method ~= 'setX' and method ~= 'setY' then
                        assert(own(button, method) == nil and button[method] == original,
                            'Guarded button method changed')
                    end
                end
                assert(button:getKeepOnScreen() == false, 'Guarded button screen clamp changed')
            end
        end
        local function refresh()
            idle(page, pane, player)
            assert(state.scope == 0 and not state.force, 'Unexpected refresh scope/force')
            guardsIntact()
            unchanged(baseline, page, pane, true)
            local started = clock()
            page:refreshBackpacks()
            local elapsed = clock() - started
            assert(elapsed >= 0, 'Button check clock moved backwards')
            unchanged(baseline, page, pane, true)
            idle(page, pane, player)
            assert(state.scope == 0 and not state.force, 'Refresh leaked scope/force')
            guardsIntact()
            return elapsed
        end
        for _, mode in ipairs({'control', 'candidate'}) do
            enabled = mode == 'candidate'
            for _ = 1, warmupCalls do refresh() end
            unchanged(baseline, page, pane)
        end
        for round = 1, rounds do
            for _, mode in ipairs(round % 2 == 1 and {'candidate', 'control'} or {'control', 'candidate'}) do
                enabled, counts = mode == 'candidate', {called=0, skipped=0}
                local elapsed = 0
                for _ = 1, batchCalls do elapsed = elapsed + refresh() end
                unchanged(baseline, page, pane)
                assert(counts.called + counts.skipped > 0, 'No guarded setter calls')
                assert(not enabled or counts.skipped > 0, 'Candidate skipped no setters')
                receipt.batches[#receipt.batches + 1] = {round=round, mode=mode, calls=batchCalls,
                    elapsedMs=elapsed, calledSetters=counts.called, skippedSetters=counts.skipped,
                    modelUnchanged=true, geometryMatched=true}
            end
        end
        receipt.checks = {orderedIdentities=true, geometry=true, parentsAndChildren=true, selection=true}
    end)
    enabled = false
    local conflicts = 0
    -- Restore independent entries even when a successor or earlier error exists.
    for index = #patches, 1, -1 do
        local patch = patches[index]
        if own(patch.button, patch.key) == patch.wrapper then patch.button[patch.key] = patch.previous
        else conflicts = conflicts + 1 end
    end
    state.force, page.isCollapsed = savedForce, savedCollapsed
    local cleanupOk, cleanupProblem = pcall(function()
        unchanged(baseline, page, pane)
        assert(conflicts == 0, 'Button setter restoration conflict; successor preserved')
        assert(state.force == savedForce and page.isCollapsed == savedCollapsed, 'Button probe flags not restored')
        for _, patch in ipairs(patches) do assert(own(patch.button, patch.key) == patch.previous,
            'Button own setter not restored exactly') end
    end)
    if not ok then
        if not cleanupOk then error(tostring(problem) .. '; cleanup failed: ' .. tostring(cleanupProblem), 0) end
        error(problem, 0)
    end
    if not cleanupOk then error(cleanupProblem, 0) end
    receipt.checks.restored = true
    receipt.restoreConflicts = conflicts
    return receipt
end

return Checks
