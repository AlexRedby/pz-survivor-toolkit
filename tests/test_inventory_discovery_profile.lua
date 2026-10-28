-- Diagnostic dispatch/timing contracts; native clock, UI and files are doubles.
local time, scopeDepth, sampled = 0, 0, 0
local floor = {}
local failClock, failEntry = false, false
local clockFailure, entryFailure = {}, {}
function baseWalkingProfileClockMs()
    if failClock then failClock=false;error(clockFailure) end
    return time
end
function baseWalkingInventoryScope(...)
    assert(select('#', ...) == 2, 'native scope bridge requires exactly two arguments')
    local entering, container = ...
    if entering then
        if failEntry then error(entryFailure) end
        assert(container == floor)
        scopeDepth = scopeDepth + 1
    else
        scopeDepth = scopeDepth - 1
        assert(scopeDepth >= 0)
    end
end
function floor:getItems()
    assert(scopeDepth == 0, 'cardinality sampling entered native timing scope')
    sampled = sampled + 1
    return {size=function() return 11 end}
end
ISInventoryPage = {floorContainer={[1]=floor}}
local options = {enableNestedContainers_Player=true,enableNestedContainers_Loot=false,
    nestedContainersDepth=2,nestedContainersPlayerFilter=1,showNestedContainerParentIcon=true,
    proximityIncludeNestedContainers=false}
function options.getEffectivePermissions(...)
    assert(select('#', ...) == 0, 'zero-argument dispatch gained an argument')
    return {proximityActive=true,corpseOnly=false,autoLock=false,dualMode=true,
        showCorpsesOnlyWhenNearby=true,hideIndividualCorpseContainers=false}
end
local nested = {OnButtonsAdded=function(page) time=time+3;return nil,'nested',nil end}
local proximity = {OnBeginRefresh=function() end,OnButtonsAdded=function() end}
local modules = {['BetterContainers/_Options']=options,['BetterContainers/Nested']=nested,
    ['BetterContainers/Proximity']=proximity}
require = function(name) return assert(modules[name], name) end
local Pane = {}; Pane.__index = Pane
function Pane:refreshContainer() error('deferred pane rebuilt') end
local paneRefresh, paneRepairs = Pane.refreshContainer, 0
local paneWrappers = {[paneRefresh]=true}
local function repairPane()
    -- Better Containers 42.21 InventoryPaneRender repairs unknown class callback
    -- identities every tick. An observer decorator would make it repair itself.
    local predecessor = Pane.refreshContainer
    if paneWrappers[predecessor] then return end
    local wrapper = function(...) return predecessor(...) end
    paneWrappers[wrapper] = true
    Pane.refreshContainer = wrapper
    paneRepairs = paneRepairs + 1
end
local Page = {}; Page.__index = Page
for _, name in ipairs({'addContainerButton','checkExplored','refreshWeight','updateItemCount'}) do
    Page[name] = function() end
end
local failure = {reason='source failure'}
function Page:refreshBackpacks(...)
    assert(select('#', ...) == 2 and select(1, ...) == 'arg' and select(2, ...) == nil,
        'method arguments changed')
    assert(self.inventoryPane.refreshContainer == self.savedGate, 'pane instance gate changed')
    time = time + 2
    local values = {nested.OnButtonsAdded(self)}
    assert(values[1] == nil and values[2] == 'nested' and values[3] == nil)
    options.getEffectivePermissions()
    time = time + 5
    if self.fail then error(failure) end
    if self.failClockAfter then failClock=true end
    return nil,'page',nil
end
local own = setmetatable({onCharacter=true,player=0,backpacks={{}},
    inventoryPane=setmetatable({},Pane)},Page)
local loot = setmetatable({onCharacter=false,player=0,backpacks={{},{}},
    inventoryPane=setmetatable({},Pane),toolkitRefreshState={rowsPending=true}},Page)
for _, page in ipairs({own,loot}) do
    page.inventoryPane.refreshContainer = function() end
    page.savedGate = page.inventoryPane.refreshContainer
end
getPlayerInventory = function() return own end
getPlayerLoot = function() return loot end
local lines, logs = {}, {}
function getFileWriter(path, rewrite, append)
    assert(path == 'base-walking-inventory-discovery.jsonl.txt' and rewrite and not append)
    lines = {}
    return {write=function(self,line) lines[#lines+1]=line end,close=function() end}
end
local function encode(row) return row.kind..':'..row.phase end
local function emit(kind,row)
    assert(kind == 'INVENTORY_DISCOVERY')
    logs[#logs+1] = row
end
local function pack(...) return {n=select('#', ...), ...} end
local originalRefresh, originalNested, originalOptions = Page.refreshBackpacks,
    nested.OnButtonsAdded, options.getEffectivePermissions
local profile = dofile(ProjectRoot..'/tests/native_queue/contributions/base-walking-profile/client/InventoryDiscoveryProfile.lua')
profile.begin(1,0,encode,emit)
repairPane(); repairPane()
assert(Pane.refreshContainer == paneRefresh and paneRepairs == 0,
    'observer triggered the owning pane identity repair')
local values = pack(loot:refreshBackpacks('arg',nil))
assert(values.n == 3 and values[1] == nil and values[2] == 'page' and values[3] == nil,
    'return nil arity changed')
assert(scopeDepth == 0 and sampled == 1, 'scope/cardinality mismatch')
profile.finishPhase()
assert(Page.refreshBackpacks == originalRefresh and nested.OnButtonsAdded == originalNested
    and options.getEffectivePermissions == originalOptions, 'original dispatch not restored')
local parent, child
for _, row in ipairs(logs) do
    if row.kind == 'timing' and row.name == 'page.refreshBackpacks.loot' then
        assert(row.calls == 1 and row.inclusive_ms == 10 and row.exclusive_ms == 7 and row.max_ms == 10)
        parent = true
    elseif row.kind == 'timing' and row.name == 'bc.Nested.OnButtonsAdded.loot' then
        assert(row.calls == 1 and row.inclusive_ms == 3 and row.exclusive_ms == 3)
        child = true
    elseif row.kind == 'end' then
        assert(row.restore_conflicts == 0 and row.samples.observer_errors == 0
            and row.samples.loot.floor_items_last == 11 and row.samples.loot.rows_pending == 1)
    end
    if row.kind == 'begin' or row.kind == 'end' then
        assert(row.settings.dualMode == true and row.settings.showCorpsesOnlyWhenNearby == true
            and row.settings.hideIndividualCorpseContainers == false
            and row.settings.proximityIncludeNestedContainers == false, '42.21 settings missing from receipt')
    end
    assert(not row.name or not row.name:match('^pane%.'), 'pane metrics must use native source profiling')
end
assert(parent and child, 'timing receipts missing')
profile.begin(2,0,encode,emit)
loot.fail = true
local ok, problem = pcall(loot.refreshBackpacks,loot,'arg',nil)
assert(not ok and problem == failure, 'source error object changed')
assert(scopeDepth == 0, 'source error left native scope active')
profile.finish()
assert(Page.refreshBackpacks == originalRefresh and nested.OnButtonsAdded == originalNested
    and options.getEffectivePermissions == originalOptions, 'failure path did not restore dispatch')
assert(logs[#logs].kind == 'end' and logs[#logs].aborted == true)
-- Unexpected owners still fail visibly; restoration must preserve their callback.
profile.begin(3,0,encode,emit)
local successor = function() return {} end
options.getEffectivePermissions = successor
ok, problem = pcall(profile.finishPhase)
assert(not ok and tostring(problem):find('bc.Options.getEffectivePermissions/getEffectivePermissions',1,true),
    'conflict failure omitted the callback label/key')
assert(options.getEffectivePermissions == successor, 'conflict restoration clobbered its successor')
local final = logs[#logs]
assert(final.restore_conflicts == 1 and final.restore_conflict_details[
    'bc.Options.getEffectivePermissions/getEffectivePermissions'] == 'unknown')
assert(Pane.refreshContainer == paneRefresh and paneRepairs == 0, 'pane owner changed across phases')
assert(#logs < 96 and #lines == #logs, 'bounded file/log receipt counts differ')
for index, row in ipairs(logs) do assert(lines[index] == encode(row)..'\n') end
-- Failed native entry and either clock boundary must not retain a Lua timing
-- frame or a native scope when the caller catches the diagnostic failure.
logs, lines = {}, {}
options.getEffectivePermissions = originalOptions
loot.fail = false
profile = dofile(ProjectRoot..'/tests/native_queue/contributions/base-walking-profile/client/InventoryDiscoveryProfile.lua')
profile.begin(1,0,encode,emit)
failEntry = true
ok, problem = pcall(loot.refreshBackpacks,loot,'arg',nil)
assert(not ok and problem == entryFailure and scopeDepth == 0)
failEntry, failClock = false, true
ok, problem = pcall(loot.refreshBackpacks,loot,'arg',nil)
assert(not ok and problem == clockFailure and scopeDepth == 0)
loot.failClockAfter = true
ok, problem = pcall(loot.refreshBackpacks,loot,'arg',nil)
assert(not ok and problem == clockFailure and scopeDepth == 0)
loot.failClockAfter = false
options.getEffectivePermissions()
values = pack(loot:refreshBackpacks('arg',nil))
assert(values.n == 3 and scopeDepth == 0)
profile.finishPhase()
local shared
for _, row in ipairs(logs) do
    if row.kind == 'timing' and row.name == 'bc.Options.getEffectivePermissions.shared' then
        assert(row.calls == 1, 'failed observer left a parent timing frame active')
        shared = true
    end
end
assert(shared and logs[#logs].samples.observer_errors == 3)
assert(Page.refreshBackpacks == originalRefresh and options.getEffectivePermissions == originalOptions)
print('inventory discovery observer dispatch, timing and restoration contracts passed')
