-- Exercise the post-profile observer's bounds and cleanup with UI doubles.
-- The native fixture separately supplies the actual CleanUI/BC callbacks.
local originalRequire = require
local fixture = (ProjectRoot or '.') .. '/tests/native_queue/contributions/base-walking-profile/client/InventoryRefreshChecks.lua'
table.wipe = table.wipe or function(value) for key in pairs(value) do value[key] = nil end end

local function setup(settings)
    settings = settings or {}
    local stats = {refreshes=0, direct=0, time=0}
    local itemA, itemB = {}, {}
    local list = {itemA, itemB}
    function list:size() return 2 end
    function list:get(index) return self[index + 1] end
    local inventory = {getItems=function() return list end, getType=function() return 'inventory' end}
    local player = {getJoypadBind=function() return -1 end}
    local Pane, Page = {}, {}
    Pane.__index, Page.__index = Pane, Page
    CleanUI_Clean_ISInventoryPage = Page
    local pane = setmetatable({mode='details', selected={}, refreshContainerCount=9990}, Pane)
    local page = setmetatable({player=0, onCharacter=true, visible=settings.visible == true,
        isCollapsed=settings.collapsed, inventory=inventory, inventoryPane=pane, backpacks={},
        toolkitRefreshState={scope=0, force=settings.force}}, Page)
    pane.inventory = inventory
    local state = page.toolkitRefreshState
    local button = {inventory=inventory}
    page.backpacks = {button}
    function Pane:refreshContainer()
        stats.direct = stats.direct + 1
        self.refreshContainerCount = (self.refreshContainerCount + 1) % 10001
        self.itemslist = {{name='stack', cat='example', count=3, realCount=2,
            cleanUIFirstActualIndex=2, items={itemA, itemA, itemB}}}
        state.rowsPending = false
        if settings.badProjection then self.itemslist[1].items[3] = {} end
    end
    function Page:getIsVisible() return self.visible end
    function Page:refreshBackpacks()
        stats.refreshes = stats.refreshes + 1
        if settings.failAt == stats.refreshes then error('injected native refresh failure') end
        if settings.changeItemsAt == stats.refreshes then list[2] = {} end
        if settings.rotateButtons then self.backpacks[1] = {inventory=inventory} end
        local defer = not self.visible and not state.force
        if defer then
            state.rowsPending, state.countPending, state.tooltipsPending = true, true, true
        else
            pane:refreshContainer()
            state.rowsPending, state.countPending, state.tooltipsPending = false, false, false
        end
        if settings.selectAt == stats.refreshes then pane.selected[1] = true end
    end
    function Page:setVisible(visible)
        self.visible = visible
        if visible and not state.force and (state.rowsPending or state.countPending or state.tooltipsPending) then
            state.force = true
            self:refreshBackpacks()
            state.force = false
        end
    end
    getSpecificPlayer = function() return player end
    getPlayerInventory = function() return page end
    getTimestampMs = function() stats.time = stats.time + 1; return stats.time end
    getFilenameOfClosure = function() return 'test-callback.lua' end
    ISMouseDrag = {}
    require = function(name)
        if name == 'BetterContainers/_Options' then
            return {enableNestedContainers_Player=true, enableNestedContainers_Loot=true, nestedContainersDepth=3,
                getEffectivePermissions=function() return {proximityActive=true, autoLock=true} end}
        end
        if name == 'BetterContainers/Nested' or name == 'BetterContainers/Proximity' then
            return {OnButtonsAdded=function() end}
        end
        return originalRequire(name)
    end
    return dofile(fixture), page, pane, state, stats, inventory
end

for _, initial in ipairs({{visible=false}, {visible=true, collapsed=true, rotateButtons=true}, {visible=false, force=false}}) do
    local checks, page, pane, state, stats, inventory = setup(initial)
    local selected = pane.selected
    local receipt = checks.run(0)
    assert(receipt.totalCalls == 384 and receipt.candidateCalls == 192 and receipt.controlCalls == 192)
    assert(receipt.warmupPerMode == 8 and receipt.callsPerBatch == 64 and receipt.rounds == 3)
    assert(#receipt.batches == 6 and receipt.counterModulus == 10001)
    local candidate, control, wrapped = 0, 0, false
    for index, batch in ipairs(receipt.batches) do
        local expectedMode = ({'candidate','control','control','candidate','candidate','control'})[index]
        assert(batch.mode == expectedMode and batch.calls == 64 and batch.elapsedMs == 1)
        assert(batch.identityUnchanged and batch.rowCounterDelta == (batch.mode == 'control' and 64 or 0))
        assert(batch.buttonIdentityStable == not initial.rotateButtons)
        if batch.rowCounterAfter < batch.rowCounterBefore then wrapped = true end
        if batch.mode == 'candidate' then candidate = candidate + 1; assert(batch.allRowsPending)
        else control = control + 1; assert(not batch.allRowsPending) end
    end
    assert(candidate == 3 and control == 3 and wrapped, 'Expected paired batches and wrapped native counter')
    for _, name in ipairs({'hiddenPlayerDeferred','directPaneImmediate','reopenFresh','visibleCollapsedPlayerLive','restored'}) do
        assert(receipt.checks[name], 'Missing native check result: ' .. name)
    end
    assert(receipt.rowProjection.groups == 1 and receipt.rowProjection.actualItems == 2
        and receipt.rowProjection.matchesForcedControl)
    assert(receipt.workload.rawItems == 2 and receipt.workload.buttons == 1 and receipt.workload.sources[1].items == 2)
    assert(page.visible == initial.visible and page.isCollapsed == initial.collapsed and state.force == initial.force
        and page.inventory == inventory and pane.inventory == inventory and pane.selected == selected and next(selected) == nil,
        'Observer did not restore the original UI state')
    assert(receipt.cleanup.forceRestored and receipt.cleanup.selectionRestored)
end

do
    local checks, page, pane, state = setup({visible=true, collapsed=false, failAt=19})
    local ok, problem = pcall(checks.run, 0)
    assert(not ok and tostring(problem):find('injected native refresh failure', 1, true))
    assert(page.visible == true and page.isCollapsed == false and state.force == nil and next(pane.selected) == nil,
        'Native failure bypassed UI cleanup')
end

do
    local checks, page, pane, state = setup({visible=false, collapsed=false, failAt=407})
    local ok, problem = pcall(checks.run, 0)
    assert(not ok and tostring(problem):find('injected native refresh failure', 1, true))
    assert(page.visible == false and page.isCollapsed == false and state.force == nil and next(pane.selected) == nil,
        'Cleanup native failure did not restore simple UI flags and force state')
end

do
    local checks, page, pane, state = setup({visible=false, badProjection=true})
    local ok, problem = pcall(checks.run, 0)
    assert(not ok and tostring(problem):find('ordered item identity changed', 1, true))
    assert(page.visible == false and state.force == nil, 'Row projection mismatch bypassed cleanup')
end

do
    local checks, page, pane, state = setup({visible=true, collapsed=true, changeItemsAt=19})
    local ok, problem = pcall(checks.run, 0)
    assert(not ok and tostring(problem):find('ordered item identity changed', 1, true))
    assert(page.visible == true and page.isCollapsed == true and state.force == nil,
        'Identity mismatch bypassed UI cleanup')
end

do
    local checks, page, pane, state, stats = setup({visible=true})
    pane.selected[1] = true
    local ok, problem = pcall(checks.run, 0)
    assert(not ok and tostring(problem):find('idle unfiltered pane', 1, true)
        and stats.refreshes == 0 and page.visible and pane.selected[1] and state.force == nil,
        'Observer silently cleared an input guard')
end

do
    local checks, page, pane = setup()
    pane.refreshContainerCount = nil
    local ok, problem = pcall(checks.run, 0)
    assert(not ok and tostring(problem):find('native refresh counter unavailable', 1, true)
        and not page.visible, 'Missing native counter was accepted')
end

require = originalRequire
print('PASS inventory refresh native observer: paired batches, counter wrap, row projection, identity guards and error cleanup')
