-- Keep nearby-container discovery/BC aggregates live, but do not build unused
-- details rows for a hidden or collapsed idle loot window. Header values and
-- explicit pane refreshes stay live.
require "ISUI/ISInventoryPage"
local Classes = require "PZSurvivorToolkit/InventoryClasses"
PZSurvivorToolkit = PZSurvivorToolkit or {}
if PZSurvivorToolkit.InventoryRefresh then return PZSurvivorToolkit.InventoryRefresh end
local Refresh = {}
PZSurvivorToolkit.InventoryRefresh = Refresh
local installed = {}

local function pack(...) return {n=select("#", ...), ...} end
local function result(values)
    if not values[1] then error(values[2], 0) end
    return unpack(values, 2, values.n)
end

local function hidden(page)
    return type(page.getIsVisible) == "function" and page:getIsVisible() == false
end

local function detailsHidden(page)
    return hidden(page) or page.isCollapsed == true
end

local function idleDetailsHidden(page)
    local pane = page.inventoryPane
    if page.onCharacter or not detailsHidden(page) or not pane or pane.mode ~= "details" then return false end
    -- Keep selection, drag, controller and active-filter consumers on their live
    -- path. An idle clipped list has no row identity that an input can consume.
    if page.joyfocus or pane.joyfocus or pane.doController or pane.firstSelect
        or pane.dragging or pane.dragStarted or pane.draggingMarquis or pane.toolkitPendingMarquee
        or pane.toolkitVisibleItems or pane.toolkitCategory
        or pane.toolkitTag or pane.toolkitTagRule
        or (pane.searchText and pane.searchText ~= "")
        or (pane.searchCategoryText and pane.searchCategoryText ~= "") then return false end
    for _ in pairs(pane.selected or {}) do return false end
    local drag = ISMouseDrag
    if drag and (drag.draggingFocus == pane or drag.dragging ~= nil
        and (type(drag.dragging) ~= "table" or #drag.dragging > 0)) then return false end
    local player = getSpecificPlayer(page.player)
    if player and player.getJoypadBind and player:getJoypadBind() ~= -1 then return false end
    return true
end

local function stateFor(page)
    local state = page.toolkitRefreshState
    if not state then
        state = {scope=0}
        page.toolkitRefreshState = state
    end
    return state
end

local function mayDefer(page, state)
    return state.scope > 0 and not state.force and idleDetailsHidden(page)
end

local function gatePane(page, state)
    local pane = page.inventoryPane
    if not pane or type(pane) ~= "table" then return false end
    if state.pane == pane and pane.refreshContainer == state.gate then return true end
    -- Instance overrides belong to their owner. Supported panes inherit their
    -- refresh chain; resolve that chain at call time so later installers survive.
    local class = getmetatable(pane)
    if type(class) ~= "table" or type(class.refreshContainer) ~= "function" then return false end
    -- Kahlua rawget also searches the metatable. Enumerate own fields only
    -- when attaching a gate; the retained gate takes the constant-time path above.
    for name in pairs(pane) do
        if name == "refreshContainer" then return false end
    end
    if state.pane ~= pane then state.rowsPending = false end
    state.pane = pane
    state.gate = function(self, ...)
        if self == state.pane and mayDefer(page, state) then
            if not state.rowsPending and self.items then table.wipe(self.items) end
            state.rowsPending = true
            return
        end
        local current = getmetatable(self)
        local values = pack(pcall(current.refreshContainer, self, ...))
        if values[1] and self == state.pane then state.rowsPending = false end
        return result(values)
    end
    pane.refreshContainer = state.gate
    return true
end

function Refresh.flush(page)
    local state = page and page.toolkitRefreshState
    if not state or state.force or not (state.rowsPending or state.countPending or state.tooltipsPending) then return end
    local previous = state.force
    state.force = true
    -- Reopen refreshes discovery too, covering remote changes since the last
    -- hidden movement. Native render owns rebuilding the flattened input rows.
    local values = pack(pcall(page.refreshBackpacks, page))
    state.force = previous
    return result(values)
end

local function finishUpdate(page, ...)
    -- Native/CleanUI update can expand a pinned/dragged page without setVisible.
    -- Flush before child input updates; forward all returns without a per-tick pack.
    if not idleDetailsHidden(page) then Refresh.flush(page) end
    return ...
end

local function install(class)
    if not class or installed[class] or type(class.refreshBackpacks) ~= "function" then return end
    installed[class] = true
    local add = class.addContainerButton
    if add then
        class.addContainerButton = function(page, ...)
            local state = stateFor(page)
            -- CleanUI sums the entire container just to build this invisible
            -- tooltip. Keep button identity/discovery live and rebuild on show.
            if getmetatable(page) == CleanUI_Clean_ISInventoryPage and mayDefer(page, state)
                and select("#", ...) >= 4 and select(4, ...) then
                local args = pack(...)
                args[4] = nil
                state.tooltipRevision = (state.tooltipRevision or 0) + 1
                state.tooltipsPending = true
                return add(page, unpack(args, 1, args.n))
            end
            return add(page, ...)
        end
    end
    local backpacks = class.refreshBackpacks
    class.refreshBackpacks = function(page, ...)
        local state = stateFor(page)
        local supported = gatePane(page, state)
        local player = getSpecificPlayer(page.player)
        local square = player and player:getCurrentSquare()
        local direction = player and player:getDir()
        local scope, tooltipRevision = state.scope, state.tooltipRevision
        if supported then state.scope = scope + 1 end
        local values = pack(pcall(backpacks, page, ...))
        state.scope = scope
        if values[1] and state.tooltipRevision == tooltipRevision then state.tooltipsPending = false end
        if values[1] and not supported then state.rowsPending = false end
        if not values[1] then
            -- Native update writes one pose field before calling discovery.
            -- An exception must leave both invalid so the next update retries.
            page.lastSquare, page.lastDir = nil, nil
        end
        -- One successful discovery already used both pose values. A simultaneous
        -- turn/tile change must not rebuild again on the next unchanged update.
        -- Do not acknowledge a pose changed by a nested callback or failed scan.
        if values[1] and player and player == getSpecificPlayer(page.player)
            and player:getCurrentSquare() == square and player:getDir() == direction then
            page.lastSquare, page.lastDir = square, direction
        end
        return result(values)
    end
    local count = class.updateItemCount
    if count then
        class.updateItemCount = function(page, ...)
            local state = stateFor(page)
            -- Collapsed pages still draw their title/count; only fully hidden
            -- pages may defer that separate presentation obligation.
            if hidden(page) and mayDefer(page, state) and state.rowsPending then
                state.countPending = true
                return
            end
            local values = pack(pcall(count, page, ...))
            if values[1] then state.countPending = false end
            return result(values)
        end
    end
    local visible = class.setVisible
    if visible then
        class.setVisible = function(page, value, ...)
            local values = pack(visible(page, value, ...))
            if value then Refresh.flush(page) end
            return unpack(values, 1, values.n)
        end
    end
    local update = class.update
    if update then
        class.update = function(page, ...)
            if not idleDetailsHidden(page) then Refresh.flush(page) end
            return finishUpdate(page, update(page, ...))
        end
    end
    local prerender = class.prerender
    if prerender then
        class.prerender = function(page, ...)
            if not idleDetailsHidden(page) then Refresh.flush(page) end
            return prerender(page, ...)
        end
    end
end

function Refresh.install()
    install(CleanUI_Clean_ISInventoryPage)
    install(CleanUI_Vanilla_ISInventoryPage)
    install(ISInventoryPage)
end
Events.OnGameBoot.Add(Refresh.install)
Events.OnGameStart.Add(Refresh.install)
Classes.onToggle(Refresh.install)
return Refresh
