require = function() end
table.wipe = function(t) for k in pairs(t) do t[k] = nil end end
local starts = {}
Events = {OnGameStart = {Add = function(fn) starts[#starts + 1] = fn end}}
PZSurvivorToolkit = {Settings = {inventoryFilters = function() return true end}}
getTextOrNull = function() end
getText = function(key) return key end
ISMouseDrag = {}
instanceof = function(value) return value and value.isItem == true end
isShiftKeyDown = function() return false end
isCtrlKeyDown = isShiftKeyDown
CleanUI_isInventoryPageLocked = function() return false end

-- Exact shared mouse branch, used without installed game sources. The optional
-- source arguments exercise the complete native/CleanUI methods instead.
local fallback = [=[
function ISInventoryPane:selectIndex(index)
    local listItem = self.items[index]
    if not listItem then return end
    self.selected[index] = listItem
end
function ISInventoryPane:onMouseMove(dx, dy)
    local x, y = self:getMouseX(), self:getMouseY()
    if self.draggingMarquis then
        local x2, y2 = self.draggingMarquisX, self.draggingMarquisY
        if x2 < x then x, x2 = x2, x end
        if y2 < y then y, y2 = y2, y end
        if x > self.column3 then return end
        local startY = math.floor((y-self.headerHgt) / self.itemHgt) + 1
        local endY = math.floor((y2-self.headerHgt) / self.itemHgt) + 1
        if startY < 1 then startY = 1 end
        self.selected = {}
        for i=startY,endY do self:selectIndex(i) end
    end
end
function ISInventoryPane:saveSelection(selected)
    for _, v in pairs(self.selected) do
        if instanceof(v, 'InventoryItem') then selected[v] = selected[v] or 'item'
        else selected[v.items[1]] = 'group' end
    end
    return selected
end
function ISInventoryPane:restoreSelection(selected)
    local row = 1
    for _, v in ipairs(self.itemslist) do
        local item = v.items[1]
        if selected[item] == 'group' then self.selected[row] = item end
        row = row + 1
        if not self.collapsed[v.name] then
            for j=2,#v.items do
                if selected[v.items[j]] then self.selected[row] = v.items[j] end
                row = row + 1
            end
        end
    end
end
function ISInventoryPane:renderdetails(doDragged)
    if doDragged == false then
        table.wipe(self.items)
        if self.inventory:isDrawDirty() then
            self:refreshContainer()
        end
    end
end
function ISInventoryPane:unused()
end
]=]

local function method(source, name)
    local begin = assert(source:find('function ISInventoryPane:' .. name .. '(', 1, true))
    local finish = source:find('\nfunction ISInventoryPane:', begin + 1, true) or #source + 1
    -- restoreSelection is followed by local anchor helpers in CleanUI.
    if name == 'restoreSelection' then
        finish = source:find('\nlocal function CleanUI_captureSelectionAnchor', begin, true) or finish
    end
    return source:sub(begin, finish - 1)
end

local function buildClass(source, enhanced)
    source = source:gsub('\r', '')
    local class = {MAX_ITEMS_IN_STACK_TO_RENDER = 50}
    local env = setmetatable({ISInventoryPane = class}, {__index = _G})
    env.CleanUI_getStackDisplayItem = function(group)
        return group and (group.cleanUIDisplayItem or group.firstItem or group.items[1])
    end
    env.CleanUI_getStackActualStartIndex = function(group)
        return group.cleanUILargeStackOptimized and 1 or 2
    end
    for _, name in ipairs({'selectIndex', 'onMouseMove', 'saveSelection', 'restoreSelection'}) do
        local chunk = assert(loadstring(method(source, name))); setfenv(chunk, env); chunk()
    end
    if source ~= fallback then
        local chunk = assert(loadstring(method(source, 'onMouseMoveOutside')))
        setfenv(chunk, env); chunk()
    else
        class.onMouseMoveOutside = class.onMouseMove
    end
    if enhanced and source == fallback then
        -- CleanUI 2.9.7 restores the group object, unlike native B42.21.
        function class:restoreSelection(saved)
            for row, group in ipairs(self.itemslist) do
                if saved[group.items[1]] == 'group' then self.selected[row] = group end
            end
        end
    end
    local capture, restoreAnchor
    if enhanced then
        local begin = source:find('local function CleanUI_captureSelectionAnchor', 1, true)
        if begin then
            local finish = assert(source:find('\nfunction ISInventoryPane:refreshContainer', begin, true))
            local chunk = assert(loadstring(source:sub(begin, finish - 1)
                .. '\nreturn CleanUI_captureSelectionAnchor,CleanUI_restoreSelectionAnchor'))
            setfenv(chunk, env); capture, restoreAnchor = chunk()
        end
    end
    -- Keep the real refresh ordering while omitting item metadata and drawing.
    function class:refreshContainer()
        local anchor = capture and capture(self)
        local saved = self:saveSelection({})
        table.wipe(self.selected)
        self.itemslist = {}
        for _, group in ipairs(self.groups) do self.itemslist[#self.itemslist + 1] = group end
        self:restoreSelection(saved)
        if restoreAnchor then restoreAnchor(self, anchor) end
        self.inventory:setDrawDirty(false)
        if self:isMouseOver() then self:onMouseMove(0, 0) end
    end
    local render = method(source, 'renderdetails')
    local branch = assert(render:match('(if doDragged == false then.-\n    end)'))
    local chunk = assert(loadstring('return function(self,doDragged) local needsWeightValues=false; '
        .. branch .. ' end'))
    setfenv(chunk, env)
    local renderRefresh = chunk()
    function class:renderdetails(doDragged)
        renderRefresh(self, doDragged)
        if not doDragged then
            table.wipe(self.items)
            for _, group in ipairs(self.itemslist) do
                self.items[#self.items + 1] = group
                if not self.collapsed[group.name] then
                    local first = env.CleanUI_getStackActualStartIndex(group)
                    for i=first,math.min(#group.items, first + 49) do
                        self.items[#self.items + 1] = group.items[i]
                    end
                end
            end
        end
    end
    function class:prerender() end
    function class:transferItemsByWeight() end
    return class, capture ~= nil
end

local native = buildClass(NativeInventoryPaneSource or fallback, false)
local enhanced, hasAnchor = buildClass(CleanUIInventoryPaneSource or fallback, true)
ISInventoryPane, CleanUI_Vanilla_ISInventoryPane, CleanUI_Clean_ISInventoryPane = native, native, enhanced
dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/InventoryFilter.lua')
dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/InventoryInteraction.lua')
for _, start in ipairs(starts) do start() end

local function pane(class)
    local a, b = {isItem = true}, {isItem = true}
    local groups = {{name = 'a', cat = 'Tool', items = {a,a}}, {name = 'b', cat = 'Food', items = {b,b}}}
    local dirty = false
    local inventory = {isDrawDirty = function() return dirty end,
        setDrawDirty = function(_, value) dirty = value end}
    local hide = {setVisible = function() end}
    return setmetatable({player = 0, inventory = inventory, groups = groups, itemslist = groups,
        items = {groups[1],groups[2]}, selected = {groups[1],groups[2]}, collapsed = {a = true,b = true},
        mode = 'details', column3 = 100, headerHgt = 0, itemHgt = 10,
        draggingMarquisX = 0, draggingMarquisY = 15,
        getMouseX = function() return 50 end, getMouseY = function() return 5 end,
        getYScroll = function() return 0 end, getHeight = function() return 1000 end,
        setYScroll = function() end,
        isMouseOver = function() return true end, updateScrollbars = function() end,
        contextButton1 = hide, contextButton2 = hide, contextButton3 = hide}, {__index = class})
end

local failures = {}
local function check(name, fn)
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = name .. ': ' .. tostring(err) end
end
for _, spec in ipairs({{name='native',class=native}, {name='CleanUI',class=enhanced}}) do
    if spec.class == enhanced then
        check(spec.name .. ' repeated group restoration', function()
            local p = pane(spec.class)
            p.isMouseOver = function() return false end
            p:refreshContainer(); p:refreshContainer()
            assert(p.selected[1] == p.groups[1] and p.selected[2] == p.groups[2], 'group selection lost its row semantics')
        end)
    end
    check(spec.name .. ' filtered page marquee', function()
        local p = pane(spec.class)
        p.draggingMarquis, p.toolkitCategory = true, 'Tool'
        p:refreshContainer()
        assert(p.selected[1] ~= nil, 'refresh erased restored selection before render')
        p:renderdetails(false)
        assert(p.selected[1] == p.groups[1] and not p.selected[2], 'marquee cleared or retained hidden rows')
    end)
    check(spec.name .. ' dirty render marquee', function()
        local p = pane(spec.class)
        p.draggingMarquis = true
        p.inventory:setDrawDirty(true)
        p:renderdetails(false)
        assert(p.selected[1] == p.groups[1] and p.selected[2] == p.groups[2], 'dirty render cleared marquee selection')
    end)
    check(spec.name .. ' dirty render fresh groups', function()
        local p = pane(spec.class)
        p.draggingMarquis = true
        -- refreshContainer recreates group tables even when physical items stay.
        for row, old in ipairs(p.groups) do
            p.groups[row] = {name=old.name, cat=old.cat, items=old.items}
        end
        p.inventory:setDrawDirty(true)
        p:renderdetails(false)
        assert(p.selected[1] == p.groups[1] and p.selected[2] == p.groups[2], 'marquee retained stale group references')
    end)
    check(spec.name .. ' outside marquee replay', function()
        local p = pane(spec.class)
        p.items, p.draggingMarquis = {}, true
        p:onMouseMoveOutside(0, 0)
        assert(p.selected[1] == p.groups[1], 'outside move erased selection before rows existed')
        p:renderdetails(false)
        assert(p.selected[1] == p.groups[1] and p.selected[2] == p.groups[2], 'outside marquee was not replayed')
    end)
    check(spec.name .. ' cancelled pending marquee', function()
        local p = pane(spec.class)
        p.items, p.draggingMarquis = {}, true
        p:onMouseMove(0, 0)
        p.draggingMarquis = false
        p.selected = {}
        p:renderdetails(false)
        assert(next(p.selected) == nil, 'released marquee was replayed')
    end)
    check(spec.name .. ' empty filter result', function()
        local p = pane(spec.class)
        p.draggingMarquis, p.toolkitCategory = true, 'Missing'
        p:refreshContainer(); p:renderdetails(false)
        assert(next(p.selected) == nil and #p.items == 0, 'empty filter retained selection')
    end)
    check(spec.name .. ' expanded stack row limit', function()
        local p = pane(spec.class)
        local expanded = {name='expanded', cat='Tool', items={}}
        for i=1,53 do expanded.items[i] = {isItem=true} end
        local virtual = {name='virtual', cat='Food', items={{isItem=true},{isItem=true}},
            cleanUILargeStackOptimized=true}
        virtual.cleanUIDisplayItem = virtual.items[1]
        p.groups, p.itemslist, p.items, p.selected = {expanded,virtual}, {expanded,virtual}, {}, {}
        p.collapsed, p.draggingMarquis, p.draggingMarquisY = {expanded=false, virtual=true}, true, 515
        p:refreshContainer(); p:renderdetails(false)
        assert(#p.items == 52 and p.items[52] == virtual, 'render fixture did not cap expanded rows')
        assert(p.selected[1] == expanded and p.selected[51] == expanded.items[51], 'expanded children missed replay')
        assert(p.selected[52] == virtual, 'virtual header shifted after capped expanded stack')
    end)
end
if hasAnchor then
    check('CleanUI dirty render Shift anchor', function()
        local p = pane(enhanced)
        p.firstSelect = 2
        p.inventory:setDrawDirty(true)
        p:renderdetails(false)
        assert(p.firstSelect == 2, 'render cleared flat rows before capturing Shift-selection anchor')
    end)
end
assert(#failures == 0, table.concat(failures, '\n'))
print('Inventory interaction checks passed: group semantics, filtered/dirty marquee and Shift anchor.')
