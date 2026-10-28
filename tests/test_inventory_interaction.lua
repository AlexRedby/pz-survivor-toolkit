require = function(name)
    if name == "PZSurvivorToolkit/InventoryClasses" or name == "PZSurvivorToolkit/InventoryRows"
        or name == "PZSurvivorToolkit/InventorySearch" then
        return dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/" .. name .. ".lua")
    end
    if name == "PZSurvivorToolkit/TagVisuals" then
        return {get=function() return {r=0.4,g=0.8,b=0.3,texture={}} end}
    end
    if name == "PZSurvivorToolkit/ItemTags" or name == "PZSurvivorToolkit/ItemTagSchema" then
        return dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/shared/" .. name .. ".lua")
    end
end
table.wipe = function(t) for k in pairs(t) do t[k] = nil end end
local starts = {}
Events = {OnGameStart = {Add = function(fn) starts[#starts + 1] = fn end}}
PZSurvivorToolkit = {Settings = {inventoryFilters = function() return true end}}
getTextOrNull = function() end
getText = function(key) return key end
ISMouseDrag = {}
local shift, ctrl = false, false
local playerInventory = {}
getSpecificPlayer = function() return {nullifyAiming=function() end} end
getPlayerInventory = function() return {inventory=playerInventory} end
getPlayerLoot = getPlayerInventory
getCore = function() return {getGameMode=function() return 'Sandbox' end} end
CleanUI_getColumnDividerAtPoint = function() end
instanceof = function(value) return value and value.isItem == true end
isShiftKeyDown = function() return shift end
isCtrlKeyDown = function() return ctrl end
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
function ISInventoryPane:onMouseDown(x, y)
    self.downX, self.downY = x, y
    local row = self.items[self.mouseOverOption]
    if not row then return end
    if x < self.column2 and not instanceof(row, 'InventoryItem') then
        self.collapsed[row.name] = not self.collapsed[row.name]
        return
    end
    if not isShiftKeyDown() and not isCtrlKeyDown() and not self.selected[self.mouseOverOption] then self.selected = {} end
    self.selected[self.mouseOverOption] = row
    self.dragging = self.mouseOverOption
    self.draggingX, self.draggingY = x, y
    self.dragStarted = false
    ISMouseDrag.dragging, ISMouseDrag.draggingFocus = {}, self
end
function ISInventoryPane:onMouseUp(x, y)
    self.previousMouseUp = self.mouseOverOption
    if not isShiftKeyDown() and not isCtrlKeyDown() and x >= self.column2 and x == self.downX and y == self.downY
        and self.mouseOverOption ~= 0 and self.items[self.mouseOverOption] then
        self.selected = {}
        self:selectIndex(self.mouseOverOption)
    end
    self.dragging, ISMouseDrag.dragging, ISMouseDrag.draggingFocus = nil, nil, nil
    if x >= 0 and y >= 0 and x < self.column3 then
        self.mouseOverOption = math.floor((y-self.headerHgt)/self.itemHgt)+1
    end
    return true
end
function ISInventoryPane:onMouseDoubleClick(x, y)
    if self.previousMouseUp == self.mouseOverOption then
        local row = self.items[self.mouseOverOption]
        self:doContextualDblClick(row.items and row.items[2] or row)
        self.previousMouseUp = nil
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
    local MOUSEX, MOUSEY = self:getMouseX(), self:getMouseY()
    for index in ipairs(self.items) do
        local y, xoff, yoff, doIt = index - 1, 0, 0, true
        local isDragging = false
        if self.dragging ~= nil and self.selected[y+1] ~= nil and self.dragStarted then
            xoff = MOUSEX - self.draggingX
            yoff = MOUSEY - self.draggingY
            if not doDragged then doIt = false else self:suspendStencil(); isDragging = true end
        elseif doDragged then doIt = false end
        local topOfItem = y * self.itemHgt
        if doIt then
            self:drawRect(1+xoff, (y*self.itemHgt)+self.headerHgt+yoff, self:getWidth()-1, self.itemHgt, 0.20, 1.0, 1.0, 1.0)
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
    -- CleanUI's vanilla-mode clone uses a distinct class/helper namespace.
    source = source:gsub('CleanUI_Vanilla_ISInventoryPane', 'ISInventoryPane'):gsub('CleanUI_Vanilla_', 'CleanUI_')
    local class = {MAX_ITEMS_IN_STACK_TO_RENDER = 50}
    local env = setmetatable({ISInventoryPane = class}, {__index = _G})
    env.CleanUI_getStackDisplayItem = function(group)
        return group and (group.cleanUIDisplayItem or group.firstItem or group.items[1])
    end
    env.CleanUI_getValidDblClickContainer = function(value) return value:getContainer() end
    env.CleanUI_getStackActualStartIndex = function(group)
        return group.cleanUILargeStackOptimized and 1 or 2
    end
    for _, name in ipairs({'selectIndex', 'onMouseDown', 'onMouseUp', 'onMouseDoubleClick', 'onMouseMove', 'saveSelection', 'restoreSelection'}) do
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
    -- Execute the upstream drag-offset branch and draw call, recording its
    -- coordinates without mocking the formula that caused the drift.
    local dragBranch = assert(render:match('(local isDragging = false.-)local topOfItem'))
    local dragRect = assert(render:match('(self:drawRect%(1%+xoff,[^\n]+)'))
    local dragChunk = assert(loadstring('return function(self) local doDragged=true; '
        .. 'local MOUSEX,MOUSEY=self:getMouseX(),self:getMouseY(); '
        .. 'for index in ipairs(self.items) do local y,xoff,yoff,doIt=index-1,0,0,true; '
        .. dragBranch .. ' if doIt then ' .. dragRect .. ' end end end'))
    setfenv(dragChunk, env)
    local renderDrag = dragChunk()
    function class:renderdetails(doDragged)
        if doDragged then return renderDrag(self) end
        renderRefresh(self, doDragged)
        if not doDragged then
            table.wipe(self.items)
            for _, group in ipairs(self.itemslist) do
                if not (self.equippedCollapsed and group.equipped) then
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

local function item(category)
    return {isItem=true, getContainer=function() return playerInventory end,
        getDisplayCategory=function() return category or 'Tool' end}
end

local function pane(class)
    local a, b = item('Tool'), item('Food')
    local groups = {{name = 'a', cat = 'Tool', items = {a,a}}, {name = 'b', cat = 'Food', items = {b,b}}}
    local dirty = false
    local inventory = {isDrawDirty = function() return dirty end,
        setDrawDirty = function(_, value) dirty = value end}
    local hide = {setVisible = function() end}
    return setmetatable({player = 0, inventory = inventory, groups = groups, itemslist = groups,
        items = {groups[1],groups[2]}, selected = {groups[1],groups[2]}, collapsed = {a = true,b = true},
        mode = 'details', column2 = 20, column3 = 100, mouseOverOption = 0,
        draggedItems = {reset=function() end}, headerHgt = 0, itemHgt = 10,
        draggingMarquisX = 0, draggingMarquisY = 15,
        getMouseX = function() return 50 end, getMouseY = function() return 5 end,
        getYScroll = function() return 0 end, getHeight = function() return 1000 end,
        getWidth = function() return 100 end, suspendStencil = function() end,
        drawRect = function(self, x, y) self.preview[#self.preview + 1] = {x=x, y=y} end,
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
    check(spec.name .. ' repeated group restoration', function()
            local p = pane(spec.class)
            p.isMouseOver = function() return false end
            p:refreshContainer(); p:refreshContainer()
            assert(p.selected[1] == p.groups[1] and p.selected[2] == p.groups[2], 'group selection lost its row semantics')
    end)
    local function clickPane()
        ISMouseDrag.dragging, ISMouseDrag.draggingFocus = nil, nil
        shift, ctrl = false, false
        local p = pane(spec.class)
        p.isMouseOver = function() return false end
        p.selected = {}
        p.doContextualDblClick = function(self, value) self.doubleClicked = value end
        local c = item()
        p.groups[3] = {name='c', cat='Tool', items={c,c}}
        p:renderdetails(false)
        p.mouseOverOption = 2
        return p
    end
    check(spec.name .. ' click survives row removal', function()
        local p = clickPane()
        local clicked = p.groups[2]
        p:onMouseDown(50, 15)
        table.remove(p.groups, 1)
        p.inventory:setDrawDirty(true)
        p:renderdetails(false)
        p:onMouseUp(50, 15)
        assert(p.selected[1] == clicked and not p.selected[2], 'mouse-up selected the replacement row')
        assert(p.previousMouseUp ~= p.mouseOverOption, 'shifted row still accepted as a double click')
        p:onMouseDoubleClick(50, 15); p:onMouseUp(50, 15)
        assert(not p.doubleClicked and p.selected[2] == p.groups[2] and not p.selected[1],
            'next rapid click after a shifted press was ignored or treated as a double click')
    end)
    check(spec.name .. ' consecutive clicks after transfer are not a double click', function()
        local p = clickPane()
        p:onMouseDown(50, 15); p:onMouseUp(50, 15)
        table.remove(p.groups, 1)
        p:refreshContainer(); p:renderdetails(false)
        p:onMouseDoubleClick(50, 15); p:onMouseUp(50, 15)
        assert(not p.doubleClicked, 'rapid click acted on replacement row as a double click')
        assert(p.selected[2] == p.groups[2] and not p.selected[1], 'replacement row did not receive an ordinary click')
    end)
    check(spec.name .. ' real double click after harmless refresh', function()
        local p = clickPane()
        p:onMouseDown(50, 15); p:onMouseUp(50, 15)
        local clicked = p.groups[2]
        p.groups[2] = {name=clicked.name, cat=clicked.cat, items=clicked.items}
        p:refreshContainer(); p:renderdetails(false)
        p:onMouseDoubleClick(50, 15)
        assert(p.doubleClicked == clicked.items[2], 'same group lost its native double-click action')
    end)
    check(spec.name .. ' click survives recreated groups', function()
        local p = clickPane()
        p:onMouseDown(50, 15)
        local clicked = p.groups[2]
        p.groups[2] = {name=clicked.name, cat=clicked.cat, items=clicked.items}
        p:refreshContainer(); p:renderdetails(false)
        p:onMouseUp(50, 15)
        assert(p.selected[2] == p.groups[2] and not p.selected[1], 'new group table lost the click')
    end)
    check(spec.name .. ' vanished click target', function()
        local p = clickPane()
        p:onMouseDown(50, 15)
        table.remove(p.groups, 2)
        p:refreshContainer(); p:renderdetails(false)
        p:onMouseUp(50, 15)
        assert(next(p.selected) == nil, 'vanished item selected a different item')
    end)
    check(spec.name .. ' click collapses existing multiselection', function()
        local p = clickPane()
        p.selected = {p.groups[1], p.groups[2], p.groups[3]}
        local clicked = p.groups[2]
        p:onMouseDown(50, 15)
        table.remove(p.groups, 1)
        p:refreshContainer(); p:renderdetails(false)
        p:onMouseUp(50, 15)
        assert(p.selected[1] == clicked and not p.selected[2], 'ordinary click failed to collapse selection')
    end)
    check(spec.name .. ' expanded child survives reorder', function()
        local p = clickPane()
        local first, clicked, last = item(), item(), item()
        local stack = {name='seeds', cat='Tool', items={first,first,clicked,last}}
        p.groups, p.itemslist, p.selected = {stack}, {stack}, {}
        p.collapsed.seeds = false
        p:renderdetails(false)
        p.mouseOverOption = 3
        p:onMouseDown(50, 25)
        stack.items = {clicked,clicked,first,last}
        p:refreshContainer(); p:renderdetails(false)
        p:onMouseUp(50, 25)
        assert(p.selected[2] == clicked and not p.selected[3], 'mouse-up selected the reordered child')
    end)
    check(spec.name .. ' moved pointer keeps native drag selection', function()
        local p = clickPane()
        local clicked = p.groups[2]
        p:onMouseDown(50, 15)
        p.dragStarted = true
        table.remove(p.groups, 1)
        p:refreshContainer(); p:renderdetails(false)
        local selected = p.selected
        p:onMouseUp(51, 15)
        assert(p.selected == selected and p.selected[1] ~= nil and not p.selected[2], 'drag release replaced selection')
    end)
    check(spec.name .. ' drag preview stays at pointer during earlier batch transfers', function()
        for _, scroll in ipairs({0, -17}) do
            local p = clickPane()
            p.collapsed.c = true
            for index=4,7 do
                local value = item()
                p.groups[index] = {name='row'..index, cat='Tool', items={value,value}}
                p.collapsed['row'..index] = true
            end
            p:refreshContainer(); p:renderdetails(false)
            local first, last = p.groups[5], p.groups[6]
            p.firstSelect, p.mouseOverOption = 5, 6
            p.selected = {[5]=first}
            shift = true
            p:onMouseDown(50, 55)
            shift = false
            assert(p.selected[5] == first and p.selected[6] == last, 'Shift range setup failed')
            p.dragStarted = true
            local mouseY = 95
            p.getYScroll = function() return scroll end
            p.getMouseY = function() return mouseY - scroll end
            local dragY, downY, payload = p.draggingY, p.downY, ISMouseDrag.dragging
            local function preview()
                p.preview = {}
                p:renderdetails(true)
                assert(p.draggingY == dragY and p.downY == downY, 'render changed persistent input coordinates')
                assert(ISMouseDrag.dragging == payload, 'render replaced drop payload')
                assert(#p.preview == 2, 'drag lost selected rows')
                return p.preview[1].y + scroll, p.preview[2].y + scroll
            end
            local top, bottom = preview()
            table.remove(p.groups, #p.groups)
            p:refreshContainer(); p:renderdetails(false)
            assert(preview() == top, 'removal below selection moved preview')
            for pass=1,3 do
                table.remove(p.groups, 1)
                p.inventory:setDrawDirty(true)
                p:renderdetails(false)
                assert(p.selected[5-pass] == first and p.selected[6-pass] == last, 'refresh changed selected identities')
                local nextTop, nextBottom = preview()
                assert(nextTop == top and nextBottom == bottom, 'earlier transfer moved drag preview upward')
            end
            mouseY = mouseY - 30
            local nextTop, nextBottom = preview()
            assert(nextTop == top - 30 and nextBottom == bottom - 30, 'preview stopped following pointer')
            p:onMouseUp(51, 95)
            p.mouseOverOption = 1
            p:onMouseDown(50, 5)
            p.dragStarted, p.preview = true, {}
            p:renderdetails(true)
            assert(p.preview[1].y + scroll == mouseY - 5, 'next drag reused the previous origin')
        end
    end)
    check(spec.name .. ' expanded child drag survives refresh before first preview', function()
        local p = clickPane()
        local a, b, c, d = item(), item(), item(), item()
        local stack = {name='stack', cat='Tool', items={a,a,b,c,d}}
        p.groups, p.itemslist, p.collapsed = {stack}, {stack}, {stack=false}
        p:renderdetails(false)
        p.selected, p.mouseOverOption = {[4]=c,[5]=d}, 5
        p:onMouseDown(50, 45)
        p.dragStarted = true
        p.getMouseY = function() return 75 end
        stack.items = {b,b,c,d}
        p:refreshContainer(); p:refreshContainer(); p:renderdetails(false)
        p.preview = {}
        p:renderdetails(true)
        assert(p.preview[1].y == 60 and p.preview[2].y == 70,
            'first preview used the refreshed rows as its origin')
        assert(p.selected[3] == c and p.selected[4] == d, 'expanded child selection changed')
        local drawRect, dragY = p.drawRect, p.draggingY
        p.drawRect = function() error('draw failure') end
        local ok, err = pcall(p.renderdetails, p, true)
        assert(not ok and tostring(err):find('draw failure', 1, true), 'render error swallowed')
        assert(p.draggingY == dragY, 'render failure leaked compensated input coordinates')
        p.drawRect = drawRect
        p.selected, p.preview = {}, {}
        p:renderdetails(true)
        assert(#p.preview == 0 and p.draggingY == dragY, 'empty selection retained preview')
    end)
    check(spec.name .. ' disjoint drag retains native spacing', function()
        local p = clickPane()
        p.collapsed.c = true
        local d = item()
        p.groups[4] = {name='d', cat='Tool', items={d,d}}
        p.collapsed.d = true
        p:refreshContainer(); p:renderdetails(false)
        p.selected, p.mouseOverOption = {[2]=p.groups[2],[4]=p.groups[4]}, 4
        p:onMouseDown(50, 35)
        p.dragStarted = true
        p.getMouseY = function() return 85 end
        p.preview = {}; p:renderdetails(true)
        local top, bottom = p.preview[1].y, p.preview[2].y
        assert(bottom - top == 20, 'disjoint preview compacted the selection')
        table.remove(p.groups, 3)
        p:refreshContainer(); p:renderdetails(false)
        p.preview = {}; p:renderdetails(true)
        assert(p.preview[1].y == top and p.preview[2].y == bottom - 10,
            'gap removal changed the top anchor or native row spacing')
    end)
    check(spec.name .. ' modifier release keeps selection', function()
        for _, modifier in ipairs({'shift', 'ctrl'}) do
            local p = clickPane()
            p:onMouseDown(50, 15)
            table.remove(p.groups, 1)
            p:refreshContainer(); p:renderdetails(false)
            local selected = p.selected
            shift, ctrl = modifier == 'shift', modifier == 'ctrl'
            p:onMouseUp(50, 15)
            assert(p.selected == selected, 'modifier release replaced selection')
        end
        shift, ctrl = false, false
    end)
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
    check(spec.name .. ' saved selection uses rendered rows', function()
        local p = pane(spec.class)
        p.isMouseOver = function() return false end
        local head = item()
        local expanded = {name='wide', cat='Tool', items={head,head}}
        for index=2,60 do expanded.items[index+1] = item() end
        local last = item()
        local later = {name='later', cat='Tool', items={last,last}}
        local hiddenItem = item()
        local hidden = {name='equipped',cat='Tool',equipped=true,items={hiddenItem,hiddenItem}}
        p.groups = spec.class == enhanced and {hidden,expanded,later} or {expanded,later}
        p.itemslist,p.collapsed,p.selected = p.groups,{equipped=true,wide=false,later=false},{}
        p.equippedCollapsed = spec.class == enhanced
        p:renderdetails(false)
        local saved = {[last]='group',[expanded.items[4]]='item',[expanded.items[58]]='item'}
        if p.equippedCollapsed then saved[hiddenItem]='group' end
        p:restoreSelection(saved)
        for pass=1,2 do
            p:renderdetails(false)
            assert(p.selected[52]==later and p.items[52]==later,'group after clipped/hidden rows moved')
            assert(p.selected[4]==expanded.items[4] and p.items[4]==expanded.items[4],'physical child moved')
            local count=0
            for index,value in pairs(p.selected) do
                count=count+1;assert(p.items[index]==value,'selected row differs from rendered row')
            end
            assert(count==2,'hidden or clipped selections survived, or group became a child')
            p:refreshContainer()
        end
        p.groups={expanded};p:refreshContainer();p:renderdetails(false)
        assert(not p.selected[52] and p.selected[4]==expanded.items[4],'removed group retained selection')
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
print('Inventory interaction checks passed: stable drag preview, click identity, group semantics, filtered/dirty marquee and Shift anchor.')
