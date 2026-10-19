local gate = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/000ToolkitBCPinsCompatibility.lua'
local classesPath = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/InventoryClasses.lua'
local function wipe(value) for key in pairs(value) do value[key] = nil end end
local function item(name)
    return {getFullType = function() return 'Base.' .. name end, name = name}
end
local function group(name, options)
    local object = item(name)
    local row = {name = name, items = {object, object}}
    for key, value in pairs(options or {}) do row[key] = value end
    return row
end
local function rowMap(pane)
    local result = {}
    for _, row in ipairs(pane.itemslist) do
        if not (pane.equippedCollapsed and row.equipped) then
            result[#result + 1] = row
            if row.items and not pane.collapsed[row.name] then
                local first = row.cleanUIFirstActualIndex or 2
                local last = math.min(#row.items, first + pane.MAX_ITEMS_IN_STACK_TO_RENDER - 1)
                for index = first, last do result[#result + 1] = row.items[index] end
            end
        end
    end
    return result
end
local function anchorKey(row) return row and (row.getFullType and row or row.name) end
local function restoreAnchor(pane, anchor)
    pane.firstSelect = nil
    for index, row in ipairs(rowMap(pane)) do
        if anchorKey(row) == anchor then pane.firstSelect = index; return end
    end
end
local function names(pane)
    local result = {}
    for _, row in ipairs(pane.itemslist) do result[#result + 1] = row.name end
    return table.concat(result, ',')
end
local function setup(active)
    local w = {loads = {}, visualCalls = {}, callbacks = {}, showPlayer = false, favourites = {}}
    local env = setmetatable({PZSurvivorToolkit = {}, table = setmetatable({wipe = wipe}, {__index = table})}, {__index = _G})
    env._G = env
    env.instanceof = function(value, name) return name == 'InventoryItem' and value and value.getFullType ~= nil end
    env.getActivatedMods = function() return {contains = function(_, id) return active and id == 'EURY_CONTAINERS' end} end
    w.texture = {}
    env.getTexture = function(path)
        assert(path == 'media/ui/BetterContainers/PinnedItemMarker.png', 'pin marker texture changed')
        return not w.missingTexture and w.texture or nil
    end
    local function class()
        local value = {MAX_ITEMS_IN_STACK_TO_RENDER = 50}
        value.renderdetails = function(pane, doDragged)
            pane.nativeRenderCalls = (pane.nativeRenderCalls or 0) + 1
            if not doDragged then pane.items = rowMap(pane) end
            return 'native render result'
        end
        value.saveSelection = function(pane, selected)
            for _, row in pairs(pane.selected) do
                if row.getFullType then selected[row] = 'item'
                elseif row.items and row.items[1] then selected[row.items[1]] = 'group' end
            end
            return selected
        end
        value.restoreSelection = function(pane, selected)
            pane.restores = (pane.restores or 0) + 1
            assert(pane.restores < 30, 'recursive selection restore')
            for index, row in ipairs(rowMap(pane)) do
                if row.getFullType then
                    if selected[row] == 'item' then pane.selected[index] = row end
                elseif row.items and selected[row.items[1]] == 'group' then pane.selected[index] = row end
            end
        end
        value.refreshContainer = function(pane)
            local selected = pane:saveSelection({})
            local anchor = pane.firstSelect and anchorKey(pane.items[pane.firstSelect])
            wipe(pane.selected)
            pane.itemslist = {}
            for index, row in ipairs(pane.source) do pane.itemslist[index] = row end
            if not pane.fixedOrder then table.sort(pane.itemslist, pane.itemSortFunc) end
            pane:restoreSelection(selected)
            restoreAnchor(pane, anchor)
            pane.items = rowMap(pane)
            -- A later category/column decorator can sort after native selection restoration.
            if pane.lateSort then table.sort(pane.itemslist, pane.itemSortFunc) end
            return 'native refresh result'
        end
        return value
    end
    w.clean, w.vanilla = class(), class()
    env.ISInventoryPane, env.CleanUI_Clean_ISInventoryPane, env.CleanUI_Vanilla_ISInventoryPane = w.clean, w.clean, w.vanilla
    env.CleanUI_RegisterInventoryUiToggleCallback = function(callback)
        w.callbacks[#w.callbacks + 1] = callback
        callback(true)
    end
    env.Events = {}
    for _, event in ipairs({'OnGameBoot', 'OnGameStart'}) do
        local callbacks = {}
        env.Events[event] = {Add = function(callback) callbacks[#callbacks + 1] = callback end}
        w[event] = function() for _, callback in ipairs(callbacks) do callback() end end
    end
    w.pins = {
        displayPinnedItem = function(page) return page and (page.onCharacter == false or w.showPlayer) end,
        isFavourite = function(fullType) return w.favourites[fullType] == true end,
        installInventoryPaneSortPatch = function()
            if w.pins._panePatched then return end
            w.temporarySortInstalled = true
        end,
        installInventoryPaneVisualPatch = function()
            if w.pins._paneVisualPatched then return end
            w.pins._paneVisualPatched = true
            local target = env.ISInventoryPane
            w.visualCalls[target] = (w.visualCalls[target] or 0) + 1
            error('upstream marker installer was not suppressed')
        end,
    }
    local classes, inventoryRows
    env.require = function(name)
        w.loads[#w.loads + 1] = name
        if name == 'PZSurvivorToolkit' then return env.PZSurvivorToolkit end
        if name == 'PZSurvivorToolkit/InventoryClasses' then
            if not classes then local chunk = assert(loadfile(classesPath)); setfenv(chunk, env); classes = chunk() end
            return classes
        end
        if name == 'PZSurvivorToolkit/InventoryRows' then
            if not inventoryRows then
                local chunk = assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/' .. name .. '.lua'))
                setfenv(chunk, env); inventoryRows = chunk()
            end
            return inventoryRows
        end
        if name == 'BetterContainers/Upgrades/PinnedItems' then return w.pins end
        error('unexpected require ' .. name)
    end
    w.load = function() local chunk = assert(loadfile(gate)); setfenv(chunk, env); return chunk() end
    w.env = env
    w.pane = function(target, source, options)
        local pane = {source = source, itemslist = {}, items = {}, selected = {}, collapsed = {},
            itemHgt = 32, headerHgt = 20, column2 = 100, markers = {},
            drawTextureScaled = function(self, ...) self.markers[#self.markers + 1] = {...} end,
            inventoryPage = {onCharacter = false}, itemSortFunc = function(a, b)
                if (a.matchesSearch == true) ~= (b.matchesSearch == true) then return a.matchesSearch == true end
                return a.name < b.name
            end}
        for _, row in ipairs(source) do pane.collapsed[row.name] = true end
        for key, value in pairs(options or {}) do pane[key] = value end
        return setmetatable(pane, {__index = target})
    end
    return w
end

local w = setup(false)
local untouched = w.clean.refreshContainer
w.load()
assert(#w.loads == 0 and w.clean.refreshContainer == untouched and not w.env.PZSurvivorToolkit.BCPinCompatibility)
print('PASS BC pins inactive mod leaves dependencies and inventory classes untouched')

w = setup(true)
w.load()
assert(w.pins._panePatched and w.pins._paneVisualPatched and w.env.PZSurvivorToolkit.BCPinCompatibility)
w.pins.installInventoryPaneSortPatch()
w.pins.installInventoryPaneVisualPatch()
assert(not w.temporarySortInstalled, 'upstream temporary comparator installer was not suppressed')
assert(not next(w.visualCalls), 'Class hooks installed before later mods could replace their methods')
w.OnGameBoot()
local cleanRefresh, vanillaRefresh = w.clean.refreshContainer, w.vanilla.refreshContainer
w.OnGameBoot(); w.OnGameStart(); w.callbacks[1](false); w.env.ISInventoryPane = w.vanilla; w.callbacks[1](true); w.load()
assert(w.clean.refreshContainer == cleanRefresh and w.vanilla.refreshContainer == vanillaRefresh)
assert(not next(w.visualCalls) and #w.callbacks == 1, 'upstream marker installer was not suppressed')
assert(w.env.ISInventoryPane == w.vanilla and w.pins._paneVisualPatched)
for _, target in ipairs({w.clean, w.vanilla}) do
    local pane = w.pane(target, {group('a'), group('b'), group('c'), group('d'), group('e')}, {lateSort = true})
    w.favourites = {['Base.c'] = true, ['Base.e'] = true}
    local comparator = pane.itemSortFunc
    assert(pane:refreshContainer() == 'native refresh result')
    assert(names(pane) == 'c,e,a,b,d' and pane.itemSortFunc == comparator)
    assert(#pane.itemslist == 5)
    assert(pane:renderdetails(false) == 'native render result' and pane.nativeRenderCalls == 1 and #pane.markers == 2)
end
print('PASS BC pins both classes retain comparator identity and stable priority after later sort; callbacks and owned markers install once')

local pane = w.pane(w.clean, {group('a'), group('c')}, {inventoryPage = {onCharacter = true}})
pane:refreshContainer(); assert(names(pane) == 'a,c')
w.showPlayer = true; pane:refreshContainer(); assert(names(pane) == 'c,a')
print('PASS BC pins respects player-inventory option')

pane = w.pane(w.clean, {group('a', {matchesSearch = true}), group('c', {matchesSearch = true}),
    group('b'), group('e')}, {lateSort = true})
pane:refreshContainer(); assert(names(pane) == 'c,a,e,b')
local rows = {group('a'), group('c'), {name = 'separator', type = 'separator', items = {}},
    group('d', {equipped = true}), group('e', {equipped = true}),
    {name = 'bc-section', _bcEquippedAttachedSeparator = true, items = {}}, group('b'), group('c-child')}
w.favourites['Base.c-child'] = true
pane = w.pane(w.clean, rows, {fixedOrder = true}); pane:refreshContainer()
assert(names(pane) == 'c,a,separator,e,d,bc-section,c-child,b')
assert(#pane.itemslist == #rows and pane.itemslist[3] == rows[3] and pane.itemslist[6] == rows[6])
print('PASS BC pins preserves search matches, equipment boundaries and separator rows without losing rows')

local ocFirst = group('oc-first', {_ocPinned = true, _ocPinRank = 1})
local ocSecond = group('oc-second', {_ocPinned = true, _ocPinRank = 2})
w.favourites = {['Base.oc-second'] = true, ['Base.c'] = true}
pane = w.pane(w.clean, {ocFirst, ocSecond, group('a'), group('c')}, {fixedOrder = true})
pane:refreshContainer()
assert(names(pane) == 'oc-first,oc-second,c,a' and pane.itemslist[1] == ocFirst and pane.itemslist[2] == ocSecond,
    'BC type pins displaced manually ordered OC instance pins')
assert(ocFirst._ocPinRank == 1 and ocSecond._ocPinRank == 2 and #pane.itemslist == 4)
print('PASS BC type pins preserve OC instance-pin rows and manual rank above ordinary pinned types')

for _, lateSort in ipairs({false, true}) do
    local a, b, c = group('a'), group('b'), group('c')
    pane = w.pane(w.clean, {a, b, c}, {lateSort = lateSort})
    w.favourites = {}
    pane:refreshContainer()
    pane.selected, pane.firstSelect = {[1] = a}, 1
    w.favourites['Base.c'] = true
    pane:refreshContainer()
    assert(names(pane) == 'c,a,b' and pane.selected[2] == a, 'selected group identity was lost')
    assert(pane.firstSelect == 2, 'Shift anchor changed after late sort=' .. tostring(lateSort))
end
print('PASS BC pins keeps selected group and Shift anchor through ordinary and late sorting')

local oldStack, replacement = group('a'), group('a')
pane = w.pane(w.clean, {oldStack, group('c')})
w.favourites = {}; pane:refreshContainer()
pane.firstSelect = 1
pane.source[1] = replacement
pane:refreshContainer()
assert(pane.firstSelect == 1, 'A replacement stack representative cleared the surviving group anchor')
print('PASS BC pins retains native group anchor when the first physical item changes')

local equipped, a, c = group('equipped', {_ocPinned = true, equipped = true}), group('a'), group('c')
pane = w.pane(w.clean, {equipped, a, c}, {fixedOrder = true, equippedCollapsed = true})
w.favourites = {}; pane:refreshContainer()
pane.firstSelect, pane.selected = 1, {[1] = a}
w.favourites['Base.c'] = true; pane:refreshContainer()
assert(pane.firstSelect == 2 and pane.selected[2] == a, 'Hidden equipped rows changed the visible selection anchor')
print('PASS BC pins excludes hidden equipped rows from selection anchor indices')

for _, virtual in ipairs({false, true}) do
    local a, b, c = group('a'), group('b'), group('c')
    local child = item('a-child')
    a.items = virtual and {a.items[1], child} or {a.items[1], a.items[1], child}
    a.cleanUIFirstActualIndex = virtual and 1 or nil
    pane = w.pane(w.clean, {a, b, c}, {lateSort = true})
    pane.collapsed.a = false
    w.favourites = {}; pane:refreshContainer()
    pane.selected, pane.firstSelect = {[3] = child}, 3
    w.favourites['Base.c'] = true; pane:refreshContainer()
    assert(names(pane) == 'c,a,b' and pane.selected[4] == child and pane.firstSelect == 4,
        'expanded child selection/anchor changed with virtual header=' .. tostring(virtual))
end
print('PASS BC pins keeps expanded physical-item selection and Shift anchor with native and virtual headers')

-- A preceding expanded stack contributes only its rendered children, even if it retains a long tail.
local wide, target, pinned = group('a'), group('b'), group('c')
for index=1,60 do wide.items[index+1]=item('wide-'..index) end
pane = w.pane(w.clean, {wide,target,pinned}, {lateSort=true})
pane.collapsed.a=false
w.favourites={}; pane:refreshContainer()
pane.selected,pane.firstSelect={[52]=target},52
w.favourites['Base.c']=true; pane:refreshContainer()
assert(names(pane)=='c,a,b' and pane.firstSelect==53,
    'unrendered stack children shifted the following group anchor')

local separator={name='equipment-header',type='separator',items={}}
local hidden=group('equipped',{equipped=true})
local a,c=group('a'),group('c')
pane=w.pane(w.clean,{separator,hidden,a,c},{fixedOrder=true,equippedCollapsed=true})
w.favourites={};pane:refreshContainer()
pane.firstSelect=1
w.favourites['Base.c']=true;pane:refreshContainer()
assert(pane.firstSelect==1 and pane.itemslist[1]==separator,
    'visible separator lost its anchor while hidden equipment and ordinary rows were reordered')
print('PASS BC pins keeps visible separator and following group anchors after clipped stacks')

local restore = w.clean.restoreSelection
w.clean.restoreSelection = function(current, selected)
    if current.itemslist == current.filteredRows then current.itemslist = current.unfilteredRows end
    current.unfilteredRows = current.itemslist
    local filtered = {}
    for _, row in ipairs(current.itemslist) do if row.name ~= 'hidden' then filtered[#filtered + 1] = row end end
    current.itemslist, current.filteredRows = filtered, filtered
    return restore(current, selected)
end
local a, c, hidden = group('a'), group('c'), group('hidden')
pane = w.pane(w.clean, {a, hidden, c}, {lateSort = true})
pane:refreshContainer(); assert(names(pane) == 'c,a' and #pane.unfilteredRows == 3 and pane.restores < 5)
pane.selected = {[2] = a}; pane:refreshContainer()
assert(names(pane) == 'c,a' and pane.selected[2] == a and #pane.unfilteredRows == 3 and pane.restores < 8)
print('PASS BC pins survives Toolkit-style filter reapplication without recursion or hidden-row loss')

-- Native rendering is the authority for the visible header rows, including hidden equipment.
for _, enhanced in ipairs({true, false}) do
    for _, hidden in ipairs({true, false}) do
        w = setup(true); w.load(); w.OnGameBoot(); w.showPlayer = true
        local targetClass = enhanced and w.clean or w.vanilla
        local separator = {name = 'equipment-header', type = 'separator', items = {}}
        local equipment, wide, tail = group('equipment', {equipped = true}), group('wide'), group('tail')
        for index = 1, 60 do wide.items[index + 1] = item('child-' .. index) end
        w.favourites = {['Base.equipment'] = true, ['Base.wide'] = true, ['Base.tail'] = true, ['Base.child-1'] = true}
        pane = w.pane(targetClass, {separator, equipment, wide, tail},
            {fixedOrder = true, equippedCollapsed = hidden, inventoryPage = {onCharacter = true}})
        pane.collapsed.wide = false
        pane:refreshContainer()
        pane.items = {tail} -- The renderer replaces this stale cache before the overlay runs.
        pane:renderdetails(false)
        local firstRow = hidden and 2 or 3
        assert(#pane.markers == (hidden and 2 or 3), 'markers included hidden equipment or physical children')
        local offset = hidden and 0 or 1
        if not hidden then
            assert(pane.markers[1][3] == pane.headerHgt + pane.itemHgt, 'visible equipment marker lost its rendered row')
        end
        assert(pane.markers[offset + 1][3] == pane.headerHgt + (firstRow - 1) * pane.itemHgt,
            'pin marker did not follow the actual rendered header after equipment was hidden')
        assert(pane.markers[offset + 2][3] == pane.headerHgt + (firstRow + 50) * pane.itemHgt,
            'pin marker counted unrendered expanded-stack children')
        for _, marker in ipairs(pane.markers) do
            assert(marker[1] == w.texture and marker[2] == 70 and marker[4] == 11 and marker[5] == 11,
                'upstream marker texture, horizontal position or size changed')
            for index = 6, 9 do assert(marker[index] == 1, 'upstream marker color changed') end
        end
    end
end
print('PASS BC pin markers follow rendered headers with hidden/visible equipment, separators and capped stacks on both classes')

for _, enhanced in ipairs({true, false}) do
    w = setup(true); w.load(); w.OnGameBoot()
    local targetClass = enhanced and w.clean or w.vanilla
    local first, second = group('a'), group('b')
    w.favourites = {['Base.a'] = true, ['Base.b'] = true}
    pane = w.pane(targetClass, {first, second}, {inventoryPage = {onCharacter = true}})
    pane:refreshContainer()
    assert(pane:renderdetails(false) == 'native render result' and #pane.markers == 0,
        'disabled player pins still drew markers or changed the renderer return')
    w.showPlayer = true
    pane:renderdetails(false); assert(#pane.markers == 2)
    pane.markers = {}
    assert(pane:renderdetails(true) == 'native render result' and #pane.markers == 0,
        'dragged render drew duplicate markers or changed the renderer return')
    pane.dragging, pane.dragStarted, pane.selected = {}, true, {[1] = first}
    pane:renderdetails(false)
    assert(#pane.markers == 1 and pane.markers[1][3] == pane.headerHgt + pane.itemHgt,
        'dragging selected header was not suppressed at its rendered row')
    pane.markers, pane.selected = {}, {[2] = first.items[1]}
    pane.collapsed.a = false
    pane:renderdetails(false)
    assert(#pane.markers == 2, 'dragging physical child incorrectly suppressed its group marker')
    pane.markers, pane.dragStarted = {}, false
    pane:renderdetails(false); assert(#pane.markers == 2, 'pending drag suppressed markers before drag started')
    pane.markers, pane.itemHgt = {}, 9
    pane:renderdetails(false)
    assert(#pane.markers == 2 and pane.markers[1][4] == 9 and pane.markers[1][2] == 93,
        'small marker size or icon-relative x geometry changed')
    pane.markers, pane.itemHgt = {}, 7
    pane:renderdetails(false); assert(#pane.markers == 0, 'marker smaller than eight pixels was rendered')
    pane.itemHgt, w.missingTexture = 32, true
    pane:renderdetails(false); assert(#pane.markers == 0, 'missing marker texture was rendered')
end
print('PASS BC pin markers preserve player option, native return, drag suppression, texture and size guards on both classes')

for _, flag in ipairs({'_panePatched', '_paneVisualPatched'}) do
    w = setup(true); w.pins[flag] = true
    local render, refresh = w.clean.renderdetails, w.clean.refreshContainer
    w.load(); w.OnGameBoot()
    assert(w.clean.renderdetails == render and w.clean.refreshContainer == refresh and not w.env.PZSurvivorToolkit.BCPinCompatibility,
        'wrong load order installed duplicate sort or visual hooks')
end
print('PASS BC pins wrong load order preserves already installed upstream methods')

w = setup(true)
w.env.OrganizedCategories = {splitStacksByDisplayCategory = function(current)
    table.sort(current.itemslist, current.itemSortFunc)
end}
w.load()
w.OnGameBoot()
-- OC installs this outer refresh decorator after Toolkit's class hooks.
for _, target in ipairs({w.clean, w.vanilla}) do
    local refresh = target.refreshContainer
    target.refreshContainer = function(current, ...)
        local result = refresh(current, ...)
        w.env.OrganizedCategories.splitStacksByDisplayCategory(current)
        return result
    end
end
w.OnGameStart()
for _, target in ipairs({w.clean, w.vanilla}) do
    local a, b, c = group('a'), group('b'), group('c')
    pane = w.pane(target, {a, b, c})
    w.favourites = {}; pane:refreshContainer()
    pane.selected, pane.firstSelect = {[1] = a}, 1
    w.favourites['Base.c'] = true
    local comparator = pane.itemSortFunc
    pane:refreshContainer()
    assert(names(pane) == 'c,a,b', 'OC outer split sort removed BC pin priority')
    assert(pane.selected[2] == a and pane.firstSelect == 2,
        'OC outer split sort changed selected group identity or Shift anchor')
    assert(pane.itemSortFunc == comparator and #pane.itemslist == 3)
end
print('PASS BC pins survive OC outer stack-split sorting with selection and Shift anchor intact')

w = setup(true); w.load()
local laterRestore = w.clean.restoreSelection
w.clean.restoreSelection = function(current, selected)
    w.laterRestoreCalls = (w.laterRestoreCalls or 0) + 1
    return laterRestore(current, selected)
end
w.OnGameBoot()
w.favourites['Base.c'] = true
pane = w.pane(w.clean, {group('a'), group('c')})
pane:refreshContainer()
assert(names(pane) == 'c,a' and w.laterRestoreCalls > 0,
    'A later mod replacement bypassed pin priority or lost its selection behavior')
print('PASS BC pins installs after other mods replace selection and category methods')
