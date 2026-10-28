-- Post-profile checks on the imported player's real inventory page. No pane or
-- class callbacks are replaced, and no items or world objects are modified.
local Checks = {}
local batchCalls, rounds, warmupCalls, counterModulus = 64, 3, 8, 10001

local function counter(pane)
    local value = pane.refreshContainerCount
    assert(type(value) == 'number' and value >= 0 and value < counterModulus
        and value == math.floor(value), 'CleanUI native refresh counter unavailable')
    return value
end

local function delta(before, after) return (after - before + counterModulus) % counterModulus end

local function empty(value)
    for _ in pairs(value or {}) do return false end
    return true
end

local function idle(page, pane, player)
    assert(pane.mode == 'details', 'Player inventory check requires details mode')
    assert(not page.joyfocus and not pane.joyfocus and not pane.doController and not pane.firstSelect
        and not pane.dragging and not pane.dragStarted and not pane.draggingMarquis
        and not pane.toolkitPendingMarquee and not pane.toolkitVisibleItems and not pane.toolkitCategory
        and not pane.toolkitTag and not pane.toolkitTagRule
        and (not pane.searchText or pane.searchText == '')
        and (not pane.searchCategoryText or pane.searchCategoryText == '') and empty(pane.selected),
        'Player inventory check requires an idle unfiltered pane without selection')
    local drag = ISMouseDrag
    assert(not drag or (drag.draggingFocus ~= pane and (drag.dragging == nil
        or type(drag.dragging) == 'table' and #drag.dragging == 0)), 'Inventory drag is active')
    assert(player:getJoypadBind() == -1, 'Player inventory check requires mouse input')
end

local function copy(value)
    local result = {}
    for key, item in pairs(value or {}) do result[key] = item end
    return result
end

local function items(container)
    local result, list = {}, assert(container:getItems(), 'Inventory source items missing')
    for index = 0, list:size() - 1 do result[#result + 1] = list:get(index) end
    return result
end

local function sameItems(expected, actual, message)
    assert(#expected == #actual, message .. ': item count changed')
    for index = 1, #expected do assert(expected[index] == actual[index], message .. ': ordered item identity changed') end
end

local function capture(page, pane)
    local result = {inventory=page.inventory, paneInventory=pane.inventory, raw=items(pane.inventory), buttons={}}
    for _, button in ipairs(page.backpacks or {}) do
        result.buttons[#result.buttons + 1] = {button=button, inventory=button.inventory, raw=items(button.inventory)}
    end
    return result
end

local function unchanged(expected, page, pane)
    assert(page.inventory == expected.inventory and pane.inventory == expected.paneInventory,
        'Player inventory selection changed during check')
    sameItems(expected.raw, items(pane.inventory), 'Current inventory')
    assert(#expected.buttons == #(page.backpacks or {}), 'Player inventory button count changed')
    local buttonChanges = 0
    for index, entry in ipairs(expected.buttons) do
        local button = page.backpacks[index]
        assert(button.inventory == entry.inventory, 'Ordered player inventory button source identity changed')
        if button ~= entry.button then buttonChanges = buttonChanges + 1 end
        sameItems(entry.raw, items(button.inventory), 'Button source ' .. index)
    end
    return buttonChanges
end

-- Compare the complete actual stack projection, including categories and the
-- stack-header representation. Item userdata identity is stronger than item ID.
local function projection(pane)
    local result, physical = {}, 0
    for _, row in ipairs(assert(pane.itemslist, 'Native inventory rows missing')) do
        local entry = {name=row.name, cat=row.cat, type=row.type, count=row.count,
            realCount=row.realCount, first=row.cleanUIFirstActualIndex, equipped=row.equipped,
            inHotbar=row.inHotbar, equippedSeparator=row._bcEquippedAttachedSeparator, items={}}
        for _, item in ipairs(row.items or {}) do entry.items[#entry.items + 1] = item end
        if row.type ~= 'separator' then
            local first = row.cleanUIFirstActualIndex or 2
            physical = physical + math.max(0, #entry.items - first + 1)
        end
        result[#result + 1] = entry
    end
    assert(#result > 0 and physical > 0, 'Native inventory row projection is empty')
    return result, physical
end

local function sameProjection(expected, pane)
    local actual, physical = projection(pane)
    assert(#expected == #actual, 'Reopened native row group count changed')
    for index, row in ipairs(expected) do
        local current = actual[index]
        assert(row.name == current.name and row.cat == current.cat and row.type == current.type
            and row.count == current.count and row.realCount == current.realCount and row.first == current.first
            and row.equipped == current.equipped and row.inHotbar == current.inHotbar
            and row.equippedSeparator == current.equippedSeparator,
            'Reopened native row projection changed')
        sameItems(row.items, current.items, 'Reopened row ' .. index)
    end
    return #actual, physical
end

local function source(fn)
    if type(getFilenameOfClosure) ~= 'function' or type(fn) ~= 'function' then return 'unavailable' end
    local ok, name = pcall(getFilenameOfClosure, fn)
    return ok and tostring(name) or 'unavailable'
end

local function workload(page, pane, baseline)
    local options = require 'BetterContainers/_Options'
    local effective = options.getEffectivePermissions() or {}
    local sources = {}
    for index, entry in ipairs(baseline.buttons) do
        sources[index] = {button=tostring(entry.button), container=tostring(entry.inventory),
            kind=entry.inventory:getType(), items=#entry.raw}
    end
    return {rawItems=#baseline.raw, buttons=#baseline.buttons, currentContainer=tostring(baseline.inventory),
        currentType=baseline.inventory:getType(), pageClass=tostring(getmetatable(page)), paneClass=tostring(getmetatable(pane)),
        pageRefreshSource=source(page.refreshBackpacks), paneRefreshSource=source(getmetatable(pane).refreshContainer),
        cleanUIPageSource=source(page.cleanUIUpdateContainerPanelMetrics),
        cleanUIPaneSource=source(pane.cleanUISaveColumnPersistence),
        bcNestedSource=source(require('BetterContainers/Nested').OnButtonsAdded),
        bcProximitySource=source(require('BetterContainers/Proximity').OnButtonsAdded),
        gateSource=source(pane.refreshContainer), sources=sources,
        settings={mode=pane.mode, onCharacter=page.onCharacter, nestedPlayer=options.enableNestedContainers_Player,
            nestedLoot=options.enableNestedContainers_Loot, depth=options.nestedContainersDepth,
            playerFilter=options.nestedContainersPlayerFilter, parentIcon=options.showNestedContainerParentIcon,
            proximity=effective.proximityActive, corpseOnly=effective.corpseOnly, autoLock=effective.autoLock,
            proximityIncludeNestedContainers=options.proximityIncludeNestedContainers}}
end

function Checks.run(playerNum, json, log)
    local player = assert(getSpecificPlayer(playerNum), 'Imported inventory player missing')
    local page = assert(getPlayerInventory(playerNum), 'Player inventory page missing')
    local pane = assert(page.inventoryPane, 'Player inventory pane missing')
    local state = assert(page.toolkitRefreshState, 'Toolkit player refresh state missing')
    assert(page.onCharacter == true and getmetatable(page) == CleanUI_Clean_ISInventoryPage,
        'Inventory check requires the real CleanUI player page')
    assert(state.scope == 0 and not state.force, 'Player inventory refresh is already active or forced')
    counter(pane)
    idle(page, pane, player)
    local saved = {visible=page:getIsVisible(), collapsed=page.isCollapsed, force=state.force,
        selected=pane.selected, selection=copy(pane.selected), inventory=page.inventory, paneInventory=pane.inventory}
    local receipt
    local ok, problem = pcall(function()
        page:setVisible(false)
        page.isCollapsed = false
        state.force = true
        page:refreshBackpacks()
        assert(page.inventory == saved.inventory and pane.inventory == saved.paneInventory,
            'Forced warmup changed the original inventory selection')
        idle(page, pane, player)
        local baseline = capture(page, pane)
        assert(#baseline.raw > 0 and #baseline.buttons > 0, 'Imported player inventory workload is empty')
        receipt = {kind='inventory-refresh-checks', playerNum=playerNum, clock='getTimestampMs',
            warmupPerMode=warmupCalls, callsPerBatch=batchCalls, rounds=rounds,
            totalCalls=batchCalls * rounds * 2, candidateCalls=batchCalls * rounds, controlCalls=batchCalls * rounds,
            identityMethod='Exact Lua reference equality; ordered items and source containers; button references observed',
            counterModulus=counterModulus, batches={}, checks={}, workload=workload(page, pane, baseline),
            limits={inventoryMutation=false, worldMutation=false, movement=false, categoryMutation=false,
                classHooks=false, paneHooks=false, timingIncludesAssertions=true, identityChecksOutsideTiming=true}}

        local function refresh(mode)
            local pending = mode == 'candidate'
            state.force = not pending
            page:refreshBackpacks()
            assert((state.rowsPending == true) == pending, 'Hidden player row deferral differs from its batch mode')
        end
        for _, mode in ipairs({'control', 'candidate'}) do
            for _ = 1, warmupCalls do refresh(mode) end
            unchanged(baseline, page, pane)
            idle(page, pane, player)
        end
        for round = 1, rounds do
            local order = round % 2 == 1 and {'candidate', 'control'} or {'control', 'candidate'}
            for _, mode in ipairs(order) do
                unchanged(baseline, page, pane)
                idle(page, pane, player)
                local before = counter(pane)
                local started = getTimestampMs()
                for _ = 1, batchCalls do refresh(mode) end
                local elapsed = getTimestampMs() - started
                local after = counter(pane)
                local builds = delta(before, after)
                assert(elapsed >= 0, 'Inventory refresh batch clock moved backwards')
                assert(builds == (mode == 'control' and batchCalls or 0), 'Unexpected native row build count in ' .. mode)
                local buttonChanges = unchanged(baseline, page, pane)
                receipt.batches[#receipt.batches + 1] = {round=round, mode=mode, calls=batchCalls,
                    elapsedMs=elapsed, rowCounterDelta=builds, rowCounterBefore=before, rowCounterAfter=after,
                    allRowsPending=mode == 'candidate', identityUnchanged=true,
                    buttonIdentityChanges=buttonChanges, buttonIdentityStable=buttonChanges == 0}
            end
        end
        receipt.checks.hiddenPlayerDeferred = true

        state.force = false
        page:refreshBackpacks()
        assert(state.rowsPending == true, 'Hidden player check did not defer rows')
        local before = counter(pane)
        pane:refreshContainer()
        assert(delta(before, counter(pane)) == 1 and not state.rowsPending,
            'Direct hidden player pane refresh was deferred')
        unchanged(baseline, page, pane)
        receipt.checks.directPaneImmediate = true

        state.force = true
        page:refreshBackpacks()
        local expected = projection(pane)
        state.force = false
        page:refreshBackpacks()
        assert(state.rowsPending == true, 'Reopen check did not start with pending rows')
        before = counter(pane)
        page:setVisible(true)
        assert(delta(before, counter(pane)) == 1 and not state.rowsPending and not state.countPending
            and not state.tooltipsPending, 'Showing player inventory did not flush all pending presentation')
        unchanged(baseline, page, pane)
        local groups, actualItems = sameProjection(expected, pane)
        receipt.rowProjection = {groups=groups, actualItems=actualItems, matchesForcedControl=true}
        receipt.checks.reopenFresh = true

        page.isCollapsed = true
        before = counter(pane)
        page:refreshBackpacks()
        assert(page:getIsVisible() == true and delta(before, counter(pane)) == 1
            and not state.rowsPending and not state.countPending and not state.tooltipsPending,
            'Visible collapsed player inventory deferred native presentation')
        unchanged(baseline, page, pane)
        sameProjection(expected, pane)
        receipt.checks.visibleCollapsedPlayerLive = true
    end)

    -- Restore the user's UI even on assertion/native errors. Force one complete
    -- refresh so restored visibility never exposes a deferred or stale row list.
    local cleanupOk, cleanupProblem = pcall(function()
        state.force = true
        page.isCollapsed = saved.collapsed
        page.inventory, pane.inventory = saved.inventory, saved.paneInventory
        pane.selected = saved.selected or {}
        table.wipe(pane.selected)
        for key, value in pairs(saved.selection) do pane.selected[key] = value end
        page:setVisible(saved.visible)
        page:refreshBackpacks()
        pane.selected = saved.selected or pane.selected
        table.wipe(pane.selected)
        for key, value in pairs(saved.selection) do pane.selected[key] = value end
        assert(page:getIsVisible() == saved.visible and page.isCollapsed == saved.collapsed
            and page.inventory == saved.inventory and pane.inventory == saved.paneInventory,
            'Player inventory check could not restore its original UI state')
    end)
    state.force = saved.force
    if not ok then
        if not cleanupOk then error(tostring(problem) .. '; UI cleanup failed: ' .. tostring(cleanupProblem), 0) end
        error(problem, 0)
    end
    if not cleanupOk then error(cleanupProblem, 0) end
    receipt.checks.restored = true
    receipt.cleanup = {visible=page:getIsVisible(), collapsed=page.isCollapsed == true,
        selectionRestored=true, inventoryRestored=true, forceRestored=state.force == saved.force}
    return receipt
end

return Checks
