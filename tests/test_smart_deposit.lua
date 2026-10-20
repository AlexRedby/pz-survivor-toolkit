-- One plan must drive partial-drop feedback and the actual native transfers.
local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/'
local gate = root .. 'client/000ToolkitBCSmartDepositCompatibility.lua'
local function list(values)
    return {size = function() return #values end, get = function(_, i) return values[i + 1] end}
end
local function setup(active, native)
    local w = {loads = {}, queued = {}, backpacks = {}, corpseOnly = false, delegated = {}}
    PZSurvivorToolkit, OrganizedCategories = {}, nil
    ISMouseDrag = {}
    instanceof = function(value, class) return value and value.class == class end
    w.player = {getCurrentSquare = function() return {} end, getVehicle = function() end}
    getSpecificPlayer = function(number) assert(number == 0); return w.player end
    getPlayerLoot = function(number) assert(number == 0); return {backpacks = w.backpacks} end
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
            assert(player == w.player)
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
            self.itemNotOK = {}
            for _, x in ipairs(self.items) do self.itemNotOK[x] = true end
            self.nativeMarker = marker
            return 'native drag'
        end}
    end
    ISInventoryPaneDraggedItems, CleanUI_Vanilla_ISInventoryPaneDraggedItems = dragClass(), dragClass()
    ISTimedActionQueue = {add = function(action) w.queued[#w.queued + 1] = action end}
    ISInventoryTransferUtil = {newInventoryTransferAction = function(player, x, source, destination)
        assert(player == w.player); return {item = x, source = source, destination = destination}
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
