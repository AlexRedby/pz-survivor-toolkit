-- One allocator drives partial-drop feedback and fresh native transfer admission.
local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/'
local gate = root .. 'client/000ToolkitBCSmartDepositCompatibility.lua'
local function list(values)
    return {size = function() return #values end, get = function(_, i) return values[i + 1] end}
end
local function setup(active, native)
    local w = {loads = {}, queued = {}, backpacks = {}, corpseOnly = false, delegated = {}, now = 1000}
    getTimestampMs = function() return w.now end
    Events = {}
    for _, name in ipairs({'OnContainerUpdate', 'OnRefreshInventoryWindowContainers'}) do
        local callbacks = {}
        Events[name] = {Add = function(callback) callbacks[#callbacks + 1] = callback end}
        Events[name].fire = function(...) for _, callback in ipairs(callbacks) do callback(...) end end
    end
    PZSurvivorToolkit, OrganizedCategories = {}, nil
    ISMouseDrag = {}
    instanceof = function(value, class) return value and value.class == class end
    w.player = {getCurrentSquare = function() return {} end, getVehicle = function() end}
    w.players = {[0] = w.player, [1] = {getCurrentSquare = function() return {} end, getVehicle = function() end}}
    getSpecificPlayer = function(number) return assert(w.players[number]) end
    getPlayerLoot = function(number) assert(w.players[number]); return {backpacks = w.backpacks} end
    getActivatedMods = function() return {contains = function(_, id) return active and id == 'EURY_CONTAINERS' end} end
    CleanUI_RegisterInventoryUiToggleCallback = function(callback) w.toggle = callback end
    function w.container(kind, free, parent)
        local c = {kind = kind or 'crate', free = free or 100, parent = parent, values = {}}
        function c:getType() return self.kind end
        function c:getParent() return self.parent end
        function c:getItems() return list(self.values) end
        function c:isInCharacterInventory() return false end
        function c:isInside(x) return self.inside == x end
        function c:isItemAllowed(x) return not x.forbidden end
        function c:hasRoomFor(player, value, repeated)
            assert(player == w.player or player == w.players[1])
            if type(value) == 'number' then
                assert(repeated == value, 'use the native Build 42 aggregate-weight overload')
                return value <= self.free
            end
            return value.weight <= self.free
        end
        return c
    end
    w.source, w.target = w.container('inventory'), w.container('proximity')
    function w.item(name, weight, category, source)
        local x = {class = 'InventoryItem', name = name, weight = weight or 1, category = category, source = source or w.source}
        function x:getFullType() return self.name end
        function x:getName() return self.name end
        function x:getContainer() return self.source end
        function x:getUnequippedWeight() return self.weight end
        function x:isFavorite() return self.favorite end
        return x
    end
    function w.nearby(...)
        w.backpacks = {}
        for _, container in ipairs({...}) do w.backpacks[#w.backpacks + 1] = {inventory = container} end
    end
    local function paneClass(name)
        return {
            transferItemsByWeight = function(self, items, target, ...)
                w.delegated[#w.delegated + 1] = {name, self, items, target, ...}
                return 'native transfer', 41
            end,
            canPutIn = function(self, ...) w.paneArgs = {self, ...}; return 'native pane', 42 end,
            refreshContainer = function(self, marker) self.refreshMarker = marker; return 'native refresh', 45 end,
            sortItemsByTypeAndWeight = function(_, items)
                table.sort(items, function(a, b) return a.weight > b.weight end)
            end,
            getActualItems = function(rows)
                local result, seen = {}, {}
                local function add(x) if not seen[x] then seen[x] = true; result[#result + 1] = x end end
                for _, row in ipairs(rows) do
                    if instanceof(row, 'InventoryItem') then add(row)
                    else for i = 2, #row.items do add(row.items[i]) end end
                end
                return result
            end,
        }
    end
    w.newPaneClass = paneClass
    ISInventoryPane = paneClass('selected')
    CleanUI_Clean_ISInventoryPane, CleanUI_Vanilla_ISInventoryPane = ISInventoryPane, paneClass('vanilla')
    local function pageClass()
        return {canPutIn = function(self, ...) w.pageArgs = {self, ...}; return 'native page', 43 end}
    end
    ISInventoryPage = pageClass()
    CleanUI_Clean_ISInventoryPage, CleanUI_Vanilla_ISInventoryPage = ISInventoryPage, pageClass()
    local function dragClass()
        return {update = function(self, marker)
            self.nativeUpdates = (self.nativeUpdates or 0) + 1
            if not self.items then self.items = ISInventoryPane.getActualItems(ISMouseDrag.dragging) end
            self.mouseOverContainer = self.mouseOverContainer or self:getDropContainer()
            self.itemNotOK = {}
            for _, x in ipairs(self.items) do self.itemNotOK[x] = true end
            self.nativeMarker = marker
            return 'native drag'
        end, reset = function(self, marker)
            self.nativeResets = (self.nativeResets or 0) + 1
            self.items, self.mouseOverContainer = nil, nil
            self.itemNotOK = {}
            self.resetMarker = marker
            return 'native reset', 44
        end,
            getDropContainer = function() return w.target end,
            cannotDropItem = function(self, item) return self.itemNotOK[item] == true end,
        }
    end
    ISInventoryPaneDraggedItems, CleanUI_Vanilla_ISInventoryPaneDraggedItems = dragClass(), dragClass()
    ISTimedActionQueue = {add = function(action) w.queued[#w.queued + 1] = action end}
    ISInventoryTransferUtil = {newInventoryTransferAction = function(player, x, source, destination)
        assert(player == w.player or player == w.players[1]); return {item = x, source = source, destination = destination}
    end}
    local loaded = {}
    require = function(name)
        if loaded[name] then return loaded[name] end
        w.loads[name] = (w.loads[name] or 0) + 1
        local value
        if name == 'BetterContainers/_Options' then
            value = {getEffectivePermissions = function() return {corpseOnly = w.corpseOnly} end}
        elseif name == 'BetterContainers/Proximity' then
            value = {invName = 'proximity', invName_corpses = 'corpses'}
        elseif name == 'BetterContainers/Categorize/InventoryCategory' then
            value = {get = function(x) return x.category end}
        elseif name == 'PZSurvivorToolkit/InventoryClasses' or name == 'PZSurvivorToolkit/SmartDeposit' then
            value = dofile(root .. 'client/' .. name .. '.lua')
        elseif name == 'PZSurvivorToolkit/InventoryTransferProtection' then
            value = dofile(root .. 'shared/' .. name .. '.lua')
        elseif name == 'BetterContainers/Proximity/Proximity_SmartDeposit' then
            value = native and assert(loadstring(NativeBCSmartDepositSource))() or {_installed = false, install = function() error('upstream installer must be replaced') end}
            w.upstream = value
        elseif name == 'BetterContainers/Helpers' or name == 'TimedActions/ISInventoryTransferUtil'
            or name == 'TimedActions/WalkToTimedAction' then value = {}
        else error('unexpected require: ' .. name) end
        loaded[name] = value
        return value
    end
    function w.pane(class, target)
        return setmetatable({player = 0, inventory = target or w.target}, {__index = class or ISInventoryPane})
    end
    function w.drag(items, class, pane)
        ISMouseDrag.dragging = items
        local d = setmetatable({items = ISInventoryPane.getActualItems(items), inventoryPane = pane or w.pane(), mouseOverContainer = w.target},
            {__index = class or ISInventoryPaneDraggedItems})
        return d
    end
    return w
end

local w = setup(false)
local untouched = ISInventoryPane.transferItemsByWeight
dofile(gate)
assert(next(w.loads) == nil and ISInventoryPane.transferItemsByWeight == untouched,
    'inactive BC must not load dependencies or patch inventory classes')

w = setup(true)
dofile(gate)
assert(not w.upstream._installed, 'bootstrap must wait for BC to install its own proximity hooks')
w.upstream.install()
local D = PZSurvivorToolkit.SmartDeposit
local a, b, overflow = w.item('A', 3), w.item('B', 2), w.item('C', 1)
local crate = w.container('crate', 5)
w.nearby(crate, crate)
local selection = {overflow, a, b, a}
local pane = w.pane()
local plan = D.plan(pane, selection, w.target)
assert(selection[1] == overflow and #selection == 4, 'planning must preserve drag order and contents')
assert(#plan.destinations == 1 and #plan.groups[crate] == 2 and plan.accepted[a] == crate
    and plan.accepted[b] == crate and not plan.accepted[overflow], 'reserve aggregate capacity and deduplicate items/storage')
for _, pair in ipairs({{ISInventoryPane, ISInventoryPaneDraggedItems}, {CleanUI_Vanilla_ISInventoryPane, CleanUI_Vanilla_ISInventoryPaneDraggedItems}}) do
    local view = w.pane(pair[1])
    local drag = w.drag(selection, pair[2], view)
    assert(drag:update('marker') == 'native drag' and drag.nativeMarker == 'marker')
    assert(not drag.itemNotOK[a] and not drag.itemNotOK[b] and drag.itemNotOK[overflow],
        'each preview row must reflect its own capacity allocation on either inventory implementation')
    assert(view:canPutIn() == true)
    local page = setmetatable({inventoryPane = view, mouseOverButton = {inventory = w.target}},
        {__index = pair[1] == ISInventoryPane and ISInventoryPage or CleanUI_Vanilla_ISInventoryPage})
    assert(page:canPutIn() == true)
    w.queued = {}; view:transferItemsByWeight(selection, w.target)
    assert(#w.queued == 2 and w.queued[1].item == a and w.queued[2].item == b
        and w.queued[1].source == w.source and w.queued[1].destination == crate,
        'native actions must contain exactly the accepted preview items')
end
crate.free = 0
assert(not pane:canPutIn())
local rejected = w.drag({a, b}); rejected:update()
assert(rejected.itemNotOK[a] and rejected.itemNotOK[b], 'full storage must retain rejection on every row')

local restricted = w.container()
w.nearby(restricted)
a.forbidden = true
assert(not D.plan(pane, {a}, w.target).accepted[a], 'storage item permissions must be checked')
a.forbidden = nil; restricted.inside = a
assert(not D.plan(pane, {a}, w.target).accepted[a], 'never transfer an item into its own descendant container')
restricted.inside = nil; w.target.inside = a
assert(not D.plan(pane, {a}, w.target).accepted[a], 'virtual target containment also prevents recursive transfers')
w.target.inside = nil

-- Existing contents establish priorities; input/button ordering must not defeat them.
local fallback, category, exact = w.container(), w.container(), w.container()
category.values, exact.values = {w.item('OtherFood', 1, 'Food')}, {w.item('Food', 1, 'Food')}
w.nearby(fallback, category, exact)
local food, tool = w.item('Food', 2, 'Food'), w.item('Tool', 1, 'Tool')
assert(D.plan(pane, {food}, w.target).accepted[food] == exact, 'full type wins over earlier category or fallback')
exact.free = 0
assert(D.plan(pane, {food}, w.target).accepted[food] == category, 'category wins when exact storage is full')
category.free = 0
assert(D.plan(pane, {food, tool}, w.target).accepted[food] == fallback, 'fallback remains available when matching stores are full')
-- Moving contents cannot manufacture an exact-match preference for their origin.
local origin, destination = w.container(), w.container()
local moving = w.item('Moving', 1, nil, origin); origin.values = {moving}
w.nearby(destination, origin)
assert(D.plan(pane, {moving}, w.target).accepted[moving] == destination)

OrganizedCategories = {isItemStickingEnabled = function() return true end, isItemStuck = function(x) return x.stuck end}
local stuck, ordinary, favorite = w.item('Stack', 2), w.item('Other', 1), w.item('Favorite', 1)
stuck.stuck, favorite.favorite = true, true
w.nearby(w.container())
ISMouseDrag.dragging = {stuck, ordinary}
plan = D.plan(pane, {stuck, ordinary, favorite}, w.target)
assert(not plan.accepted[stuck] and plan.accepted[ordinary] and not plan.accepted[favorite],
    'mixed drag protects Stick and favorites')
ISMouseDrag.dragging = {{items = {stuck, stuck}}, ordinary}
assert(not D.plan(pane, {stuck}, w.target).accepted[stuck], 'a narrowed callback must retain original mixed drag intent')
ISMouseDrag.dragging = {{items = {stuck, stuck}}}
assert(D.plan(pane, {stuck}, w.target).accepted[stuck], 'original explicit row permits its Stick item')
ISMouseDrag.dragging = {favorite}
assert(not D.plan(pane, {favorite}, w.target).accepted[favorite], 'deliberate Stick exception never overrides favorites')
OrganizedCategories.isItemStickingEnabled = function() return false end
ISMouseDrag.dragging = {stuck, ordinary}
assert(D.plan(pane, {stuck}, w.target).accepted[stuck], 'read optional Stick provider opt-out live')
OrganizedCategories = nil

local excluded = {'floor', 'local', 'localContainer', 'localInventory', 'stove', 'microwave', 'oven',
    'washingmachine', 'dryer', 'clothingwasher', 'clothingdryer', 'combinationwasherdryer', 'proximity', 'corpses', 'inventorymale', 'inventoryfemale'}
local nearby = {}
for _, kind in ipairs(excluded) do nearby[#nearby + 1] = w.container(kind) end
local locked = w.container('crate', 100, {class = 'IsoThumpable', isLockedToCharacter = function() return true end})
nearby[#nearby + 1] = locked
w.nearby(unpack(nearby))
assert(#D.plan(pane, {a}, w.target).destinations == 0, 'exclude appliances, virtual inventories, locked storage and corpses in ordinary mode')
w.corpseOnly = true
local corpseTarget = w.container('corpses')
assert(D.isTarget(corpseTarget) and D.plan(pane, {a}, corpseTarget).accepted[a] == nearby[#nearby - 2],
    'corpse mode allows real corpse storage while excluding the virtual corpse aggregate')
w.corpseOnly = false
assert(not D.isTarget(corpseTarget))

-- Hooks must be transparent outside BC and must not stack when BC or CleanUI repeats setup.
local methods = {ISInventoryPane.transferItemsByWeight, ISInventoryPane.canPutIn, ISInventoryPage.canPutIn, ISInventoryPaneDraggedItems.update}
w.upstream.install(); w.toggle(); dofile(gate)
assert(methods[1] == ISInventoryPane.transferItemsByWeight and methods[2] == ISInventoryPane.canPutIn
    and methods[3] == ISInventoryPage.canPutIn and methods[4] == ISInventoryPaneDraggedItems.update)
local late = w.newPaneClass('late discovered')
CleanUI_Clean_ISInventoryPane = late
w.toggle()
w.nearby(w.container())
ISMouseDrag.dragging = {a}
assert(w.pane(late):canPutIn(), 'CleanUI toggle installs hooks on a class discovered after initial setup')
local lateMethod = late.canPutIn
w.toggle()
assert(late.canPutIn == lateMethod, 'newly discovered classes are also installed only once')
local normal = w.container()
local view = w.pane(nil, normal)
local r1, r2 = view:transferItemsByWeight({a}, normal, 'extra')
assert(r1 == 'native transfer' and r2 == 41 and #w.delegated == 1 and w.delegated[1][5] == 'extra')
r1, r2 = view:canPutIn('pane extra')
assert(r1 == 'native pane' and r2 == 42 and w.paneArgs[2] == 'pane extra')
local page = setmetatable({mouseOverButton = {inventory = normal}}, {__index = ISInventoryPage})
r1, r2 = page:canPutIn('page extra')
assert(r1 == 'native page' and r2 == 43 and w.pageArgs[2] == 'page extra')
local normalDrag = w.drag({a}); normalDrag.mouseOverContainer = normal
assert(normalDrag:update() == 'native drag' and normalDrag.itemNotOK[a], 'ordinary drag feedback stays owned by the native implementation')

if NativeBCSmartDepositSource then
    w = setup(true, true)
    local native = require('BetterContainers/Proximity/Proximity_SmartDeposit')
    native.install()
    a, b = w.item('Fits', 2), w.item('Overflow', 1)
    w.nearby(w.container('crate', 2))
    local old = w.drag({a, b}); old:update()
    assert(not old.itemNotOK[a] and not old.itemNotOK[b], 'actual BC 42.21 preview clears rejection for the overflowing row')
    w.pane():transferItemsByWeight({a, b}, w.target)
    assert(#w.queued == 1 and w.queued[1].item == a, 'actual BC transfer plan rejects that same overflow row')
    local nativeTransfer = ISInventoryPane.transferItemsByWeight
    dofile(gate)
    assert(not PZSurvivorToolkit.SmartDeposit and ISInventoryPane.transferItemsByWeight == nativeTransfer,
        'late bootstrap preserves already installed upstream hooks and does not claim ownership')
    print('PASS actual BC 42.21 reproduces preview/action mismatch and late-install guard')
end
-- Only drag feedback may reuse a bounded advisory plan; admission and actions are live.
local function checkCachedPreview()
    local world = setup(true)
    dofile(gate); world.upstream.install()
    local deposit = PZSurvivorToolkit.SmartDeposit
    local plans, planFresh = 0, deposit.plan
    deposit.plan = function(...)
        plans = plans + 1
        return planFresh(...)
    end
    local function planning(expected, action, message)
        local before = plans
        local a, b = action()
        assert(plans - before == expected, message .. ': expected ' .. expected .. ' plans, got ' .. (plans - before))
        return a, b
    end
    local first, second = world.item('First', 2), world.item('Second', 1)
    local crate = world.container('crate', 2)
    world.nearby(crate)
    local selection = {first, second}
    local view = world.pane()
    local drag = world.drag(selection, nil, view)
    planning(1, function()
        for i = 1, 60 do
            assert(drag:update(i) == 'native drag' and drag.nativeMarker == i)
            assert(not drag.itemNotOK[first] and drag.itemNotOK[second],
                'cached allocation must overwrite fresh native itemNotOK on every frame')
        end
    end, 'sixty unchanged hover frames must share one plan')
    assert(drag.nativeUpdates == 60, 'native drag update must run on every cached frame')
    local vanilla = world.drag(selection, CleanUI_Vanilla_ISInventoryPaneDraggedItems,
        world.pane(CleanUI_Vanilla_ISInventoryPane))
    planning(1, function()
        for _ = 1, 60 do
            vanilla:update()
            assert(not vanilla.itemNotOK[first] and vanilla.itemNotOK[second])
        end
    end, 'vanilla inventory shares the same bounded partial-preview contract')
    world.now = 1199
    planning(0, function() drag:update() end, 'preview remains valid at 199 ms')
    world.now = 1200
    planning(1, function() drag:update() end, 'preview expires at exactly 200 ms')
    world.now = 1199
    planning(1, function() drag:update() end, 'clock rollback must not retain a future-dated plan')
    planning(0, function() drag:update() end, 'rollback replacement is reusable')

    -- Selection identity and contents must both be observed without waiting for expiry.
    ISMouseDrag.dragging = {first, second}
    planning(1, function() drag:update() end, 'replacement selection invalidates preview')
    ISMouseDrag.dragging[2] = nil
    drag.items = {first}
    planning(1, function() drag:update() end, 'in-place selection removal invalidates preview')
    ISMouseDrag.dragging[1] = second
    drag.items = {second}
    planning(1, function() drag:update() end, 'in-place item replacement invalidates preview')
    assert(not drag.itemNotOK[second], 'replacement item receives its own allocation')
    local row = {items = {first, first}}
    ISMouseDrag.dragging, drag.items = {row}, {first}
    planning(1, function() drag:update() end, 'stack selection invalidates preview')
    row.items[2] = second
    planning(1, function() drag:update() end, 'in-place stack member replacement invalidates preview with an unchanged native item list')
    drag.items[1] = second
    planning(1, function() drag:update() end, 'in-place native item replacement invalidates preview')
    drag.items = {second}
    planning(1, function() drag:update() end, 'native item list rebuild invalidates preview')
    local newTarget = world.container('proximity')
    drag.mouseOverContainer = newTarget
    planning(1, function() drag:update() end, 'target replacement invalidates preview')
    drag.inventoryPane = world.pane(nil, newTarget)
    planning(1, function() drag:update() end, 'pane replacement invalidates preview')
    drag.inventoryPane.player = 1
    planning(1, function() drag:update() end, 'player replacement invalidates preview')
    local other = world.drag({second})
    other.inventoryPane.player = 1
    planning(1, function() other:update() end, 'another drag instance must own a separate plan')
    planning(0, function() other:update() end, 'other player reuses only its own preview')
    Events.OnRefreshInventoryWindowContainers.fire({player = 0}, 'end')
    planning(0, function() other:update() end, 'another player inventory refresh cannot invalidate this drag')
    Events.OnRefreshInventoryWindowContainers.fire({player = 1}, 'end')
    planning(1, function() other:update() end, 'the owning player inventory refresh invalidates this drag')

    local resetA, resetB = other:reset('reset marker')
    assert(resetA == 'native reset' and resetB == 44 and other.resetMarker == 'reset marker',
        'preview reset must preserve the native reset contract')
    other.items, other.inventoryPane, other.mouseOverContainer = {second}, world.pane(), world.target
    ISMouseDrag.dragging = {second}
    planning(1, function() other:update() end, 'reset drag must never reuse its old preview')
    planning(0, function() other:update() end, 'reset replacement is reusable')
    local activeSelection = ISMouseDrag.dragging
    ISMouseDrag.dragging = nil
    planning(0, function() other:update() end, 'absent native selection skips advisory planning')
    ISMouseDrag.dragging = activeSelection
    planning(1, function() other:update() end, 'ending a drag clears its previous preview')
    other.mouseOverContainer = world.container()
    planning(0, function() other:update() end, 'ordinary targets keep native feedback without advisory planning')
    other.mouseOverContainer = world.target
    planning(1, function() other:update() end, 'returning from an ordinary target starts a fresh preview')

    local page = setmetatable({player = 0, inventoryPane = other.inventoryPane, mouseOverButton = {inventory = world.target}},
        {__index = ISInventoryPage})
    local r1, r2 = other.inventoryPane:refreshContainer('container marker')
    assert(r1 == 'native refresh' and r2 == 45 and other.inventoryPane.refreshMarker == 'container marker')
    planning(1, function() other:update() end, 'pane container refresh invalidates cached preview')
    Events.OnContainerUpdate.fire(crate)
    planning(1, function() other:update() end, 'container event invalidates cached preview')
    Events.OnRefreshInventoryWindowContainers.fire(page, 'begin')
    planning(0, function() other:update() end, 'unfinished inventory-window refresh retains the current preview')
    Events.OnRefreshInventoryWindowContainers.fire(page, 'end')
    planning(1, function() other:update() end, 'completed inventory-window refresh invalidates cached preview')
    world.toggle()
    planning(1, function() other:update() end, 'inventory mode toggle invalidates cached preview')

    -- Keep the green hint stale deliberately: it must have no authority over a drop.
    ISMouseDrag.dragging = {first}
    local stale = world.drag({first}, nil, view)
    planning(1, function() stale:update() end, 'initial green preview')
    crate.free = 0
    planning(0, function() stale:update() end, 'capacity changes may await bounded advisory refresh')
    assert(not stale.itemNotOK[first], 'fixture must retain a stale green hint')
    page.inventoryPane = view
    planning(1, function() assert(not view:canPutIn()) end, 'pane rejects full storage from a fresh plan')
    planning(1, function() assert(not page:canPutIn()) end, 'page rejects full storage from a fresh plan')
    world.queued = {}
    planning(1, function() view:transferItemsByWeight({first}, world.target) end, 'execution rechecks full storage')
    assert(#world.queued == 0, 'stale green preview cannot queue an over-capacity transfer')
    crate.free, first.forbidden = 2, true
    planning(1, function() assert(not view:canPutIn()) end, 'pane rechecks newly restricted storage')
    planning(1, function() assert(not page:canPutIn()) end, 'page rechecks newly restricted storage')
    planning(1, function() view:transferItemsByWeight({first}, world.target) end, 'execution rechecks permissions')
    assert(#world.queued == 0, 'stale green preview cannot queue a forbidden transfer')
    first.forbidden, crate.free = nil, 0
    local staleRed = world.drag({first}, nil, view)
    planning(1, function() staleRed:update() end, 'initial red preview')
    crate.free = 2
    planning(0, function() staleRed:update() end, 'new capacity may await bounded advisory refresh')
    assert(staleRed.itemNotOK[first], 'fixture must retain a stale red hint')
    planning(1, function() assert(view:canPutIn()) end, 'pane accepts fresh capacity despite stale red preview')
    planning(1, function() assert(page:canPutIn()) end, 'page accepts fresh capacity despite stale red preview')
    planning(1, function() view:transferItemsByWeight({first}, world.target) end, 'execution replans newly available capacity')
    assert(#world.queued == 1 and world.queued[1].item == first and world.queued[1].destination == crate,
        'stale red preview cannot block a valid fresh transfer')
end
checkCachedPreview()
print('PASS drag-local bounded advisory preview, lifecycle invalidation and fresh drop authority')

-- Affinity must match BC's input mask, after OC has removed protected items.
local function checkSelectedStockAffinity(native)
    local world = setup(true, native)
    if native then require('BetterContainers/Proximity/Proximity_SmartDeposit').install()
    else dofile(gate); world.upstream.install() end
    for _, exactMatch in ipairs({true, false}) do
        local fallback, tagged = world.container(), world.container()
        local retained = world.item(exactMatch and 'Incoming' or 'OtherFood', 2, 'Food', tagged)
        local incoming = world.item('Incoming', 1, 'Food')
        retained.favorite = true
        tagged.values = {retained}
        world.nearby(fallback, tagged)
        ISMouseDrag.dragging = {retained, incoming}
        world.queued = {}; world.pane():transferItemsByWeight({retained, incoming}, world.target)
        assert(#world.queued == 1 and world.queued[1].item == incoming and world.queued[1].destination == fallback,
            'selected favorite must not become existing full-type/category stock merely because it cannot move')
    end
    local fallback, tagged = world.container(), world.container()
    local stuck = world.item('Incoming', 2, 'Food', tagged)
    local incoming = world.item('Incoming', 1, 'Food')
    stuck.stuck = true; tagged.values = {stuck}
    world.nearby(fallback, tagged)
    OrganizedCategories = {isItemStickingEnabled = function() return true end, isItemStuck = function(x) return x.stuck end}
    ISMouseDrag.dragging = {stuck, incoming}
    -- OC's installed transfer wrapper removes this protected item before BC.
    local executionItems = native and {incoming} or {stuck, incoming}
    world.queued = {}; world.pane():transferItemsByWeight(executionItems, world.target)
    assert(#world.queued == 1 and world.queued[1].item == incoming and world.queued[1].destination == tagged,
        'non-deliberate Stick item remains existing stock, matching the OC-filtered native execution')
end
checkSelectedStockAffinity(false)
if NativeBCSmartDepositSource then checkSelectedStockAffinity(true) end
print('PASS selected-favorite and protected-Stick stock affinity matches native execution')
print('PASS smart deposit capacity, priorities, protections, storage exclusions, dual inventory hooks and delegation')

-- Exercise the real button callback: it refreshes feedback before using cannotDropItem.
local function checkNativeButtonDrop(source, name, vanilla)
    if not source then return end
    source = source:gsub('\r', '')
    local method = assert(source:match('(function ' .. name .. ':dropItemsInContainer%(.-)\nfunction ' .. name .. ':'),
        name .. ' dropItemsInContainer handler missing')
    for _, staleRed in ipairs({false, true}) do
        local world = setup(true)
        dofile(gate); world.upstream.install()
        assert(loadstring(method))()
        local class = _G[name]
        local heavy, light = world.item('Heavy', 2), world.item('Light', 1)
        local crate = world.container('crate', staleRed and 0 or 3)
        world.nearby(crate)
        local view = world.pane(vanilla and CleanUI_Vanilla_ISInventoryPane or ISInventoryPane)
        local drag = world.drag({heavy, light}, vanilla and CleanUI_Vanilla_ISInventoryPaneDraggedItems or nil, view)
        view.draggedItems = drag
        drag:update()
        assert((drag.itemNotOK[heavy] == true) == staleRed and (drag.itemNotOK[light] == true) == staleRed)
        crate.free = staleRed and 3 or 1
        drag:update()
        assert((drag.itemNotOK[heavy] == true) == staleRed and (drag.itemNotOK[light] == true) == staleRed,
            'button-drop fixture must retain the stale advisory hints before clicking')
        local submitted, transfer = nil, view.transferItemsByWeight
        view.transferItemsByWeight = function(self, items, target)
            submitted = items
            return transfer(self, items, target)
        end
        local page = setmetatable({player = 0, inventoryPane = view, mouseOverButton = {inventory = world.target},
            refreshWeight = function() end, updateItemCount = function() end}, {__index = class})
        getCore = function() return {getGameMode = function() return 'Sandbox' end} end
        luautils = {walkToContainer = function(target, player) assert(target == world.target and player == 0); return true end}
        getPlayerLoot = function() return {backpacks = world.backpacks, inventoryPane = {selected = {}}} end
        getPlayerInventory = function() return {inventoryPane = {selected = {}}} end
        assert(page:dropItemsInContainer(page.mouseOverButton))
        assert(drag.nativeResets == 1 and drag.nativeUpdates == 3,
            'actual button callback must reset and update drag feedback before filtering')
        if staleRed then
            assert(#submitted == 2 and submitted[1] == heavy and submitted[2] == light,
                'stale red hints must not filter freshly accepted items out of the actual button drop')
            assert(#world.queued == 2 and world.queued[1].item == heavy and world.queued[2].item == light)
        else
            assert(#submitted == 1 and submitted[1] == light,
                'stale green hints must not submit freshly rejected items through the actual button drop')
            assert(#world.queued == 1 and world.queued[1].item == light)
        end
    end
    print('PASS source-backed ' .. name .. ' stale-preview button drop')
end
checkNativeButtonDrop(NativeInventoryPageSource, 'ISInventoryPage')
checkNativeButtonDrop(CleanUIInventoryPageSource, 'ISInventoryPage')
checkNativeButtonDrop(CleanUIVanillaInventoryPageSource, 'CleanUI_Vanilla_ISInventoryPage', true)
