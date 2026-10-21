-- LootSorter manifest: a read-only window that aggregates the contents of ALL designated boxes
-- into one global item list (icon + name + count), sortable and filterable.
--
-- Contents are kept in a PERSISTED per-coord snapshot store (central world ModData), so the manifest
-- still shows boxes whose tiles aren't currently loaded. Snapshots refresh two ways:
--   * a hook on ISInventoryTransferAction re-snapshots a designated tile whenever an item lands in or
--     leaves one of its containers (covers virtually all player-driven moves, incl. our own sort);
--   * reconcile-on-open re-scans every loaded designated tile and drops coords no longer designated.
-- Pure aggregation/sort lives in shared/LootSorter_ManifestAgg.lua (unit-tested).
require "ISUI/ISCollapsableWindow"
require "ISUI/ISCollapsableWindowJoypad"
require "TimedActions/ISInventoryTransferAction"
local Categories = require "PZSurvivorToolkit/ItemCategories"
local UIStyle = require "PZSurvivorToolkit/UIStyle"

LootSorter = LootSorter or {}

-- Single-player only for now. The snapshot store is ModData.getOrCreate, which on a multiplayer
-- client is a real but permanently empty table -- so the manifest would show only what you happened
-- to touch this session, forget it on every relog, and share nothing between players. Showing an
-- authoritative-looking list that is quietly wrong is worse than not offering it.
-- Returning here also skips the snapshot store, the ISInventoryTransferAction hook and the tick
-- handler, so multiplayer pays none of the cost. LootSorter.toggleManifest is then undefined, which
-- is what the context menu already guards on.
if isClient() then return end

----------------------------------------------------------------------
-- Snapshot store
----------------------------------------------------------------------

-- store = { [coordKey "x,y,z"] = { [displayName] = { n = <count>, ft = <fullType> } } }
local function getStore()
    local md = ModData.getOrCreate("LootSorter_Manifest")
    md.boxes = md.boxes or {}
    return md.boxes
end
local function keyOf(x, y, z) return math.floor(x) .. "," .. math.floor(y) .. "," .. math.floor(z) end
local function parseKey(k)
    local x, y, z = string.match(k, "(%-?%d+),(%-?%d+),(%-?%d+)")
    if not x then return nil end
    return tonumber(x), tonumber(y), tonumber(z)
end

-- (re)snapshot every designated container on a square into one coord entry. No designation -> drop it.
local function snapshotSquare(sq)
    if not sq then return end
    local k = keyOf(sq:getX(), sq:getY(), sq:getZ())
    local store = getStore()
    local found = LootSorter.findDesignatedOnSquare and LootSorter.findDesignatedOnSquare(sq) or {}
    if #found == 0 then store[k] = nil; return end
    local map = {}
    for _, rec in ipairs(found) do
        local c = rec.container
        if c then
            Categories.prepareContainer(c)
            local items = c:getItems()
            for i = 0, items:size() - 1 do
                local it = items:get(i)
                local nm = it:getDisplayName()
                local e = map[nm]
                if not e then e = { n = 0, ft = it:getFullType(), cat = it:getDisplayCategory() }; map[nm] = e end
                e.n = e.n + 1
            end
        end
    end
    store[k] = map
end

-- Re-scan every loaded designated tile; keep unloaded tiles' last snapshot; drop undesignated coords.
function LootSorter.manifestReconcile()
    local reg = LootSorter.getRegistry()
    local cell = getCell()
    for k in pairs(reg) do
        local x, y, z = parseKey(k)
        if x and cell then
            local sq = cell:getGridSquare(x, y, z)
            if sq then snapshotSquare(sq) end     -- loaded -> refresh; unloaded -> keep last snapshot
        end
    end
    local store = getStore()
    for k in pairs(store) do
        if not reg[k] then store[k] = nil end     -- registry is authoritative for "still designated"
    end
end

-- Hook transfers: when an item moves into/out of a designated tile's container, mark that tile
-- DIRTY (don't snapshot yet). A single bulk move (e.g. our sort) queues one transfer action PER
-- item, so snapshotting inline would rescan the whole box once per item (~O(n^2)). Instead we
-- coalesce: flush each dirty tile ONCE, on the tick after the player's action queue drains.
LootSorter._manifestDirty = LootSorter._manifestDirty or {}

-- rebound each reload so edits to this apply (a boolean guard alone would keep running the FIRST
-- load's closure forever).
LootSorter.addOrReplaceHandler(Events.OnTick, "_onManifestTick", function()
    local dirty = LootSorter._manifestDirty
    local any = false
    for _ in pairs(dirty) do any = true; break end       -- cheap early-out on idle ticks
    if not any then return end
    local player = getSpecificPlayer(0)
    if not player then return end
    local q = ISTimedActionQueue.queues and ISTimedActionQueue.queues[player]
    if q and #q.queue > 0 then return end                -- still transferring -> wait for the queue to drain
    local cell = getCell()
    for k in pairs(dirty) do
        local x, y, z = parseKey(k)
        local sq = (x and cell) and cell:getGridSquare(x, y, z) or nil
        if sq then snapshotSquare(sq) end
        dirty[k] = nil
    end
    -- live refresh: if the manifest is open, reflect the new contents immediately
    if LootSorter._manifestWin then LootSorter._manifestWin:rebuild() end
end)

-- one-time monkey-patch: wrap perform ONCE (guarded) -- re-wrapping on every reload would stack a new
-- layer of the wrapper each time. This is correct as a one-time registration.
if not LootSorter._manifestXferHooked then
    LootSorter._manifestXferHooked = true
    local previous = {new = ISInventoryTransferAction.new, perform = ISInventoryTransferAction.perform,
        transferItem = ISInventoryTransferAction.transferItem}
    local origPerform = previous.perform
    function ISInventoryTransferAction:perform()
        origPerform(self)
        pcall(function()
            local reg = LootSorter.getRegistry()
            local function mark(c)
                if not c then return end
                local p = c.getParent and c:getParent()
                local sq = p and p.getSquare and p:getSquare()
                if sq then
                    local k = keyOf(sq:getX(), sq:getY(), sq:getZ())
                    if reg[k] then LootSorter._manifestDirty[k] = true end
                end
            end
            mark(self.srcContainer)
            mark(self.destContainer)
        end)
    end
    LootSorter.manifestTransferHooks = {previous = previous,
        replacement = {new = ISInventoryTransferAction.new, perform = ISInventoryTransferAction.perform,
            transferItem = ISInventoryTransferAction.transferItem},
        registry = LootSorter.getRegistry, parse = LootSorter.parseCoordKey}
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
-- Column geometry (list-relative). `content` excludes the scrollbar so the right-aligned Count
-- never draws under it (the earlier cutoff). Columns: Item | Category | Count.
local SCROLLBAR = 17
local COUNT_W = 52
local CAT_W = 96
local function colsFor(listW)
    local content = listW - SCROLLBAR
    local catX = content - COUNT_W - CAT_W
    if catX < 80 then catX = 80 end
    return { content = content, catX = catX }
end

-- Draw a small filled triangle (sort indicator) from stacked 1px rows. No font glyph / texture needed,
-- so it renders on every font. up=true -> apex at top (ascending); up=false -> apex at bottom.
local function drawTri(ui, cx, top, size, up, a, r, g, b)
    for i = 0, size - 1 do
        local frac = up and (i / size) or ((size - 1 - i) / size)
        local half = frac * (size / 2)
        ui:drawRect(cx - half, top + i, half * 2, 1, a, r, g, b)
    end
end

local function fit(font, s, maxW)
    return UIStyle.fit(s or "", maxW, font, "..")
end

-- ISCollapsableWindowJoypad = a collapsable window with ISPanelJoypad navigation baked in, so the
-- window can take controller focus and d-pad between its focusable rows (see createChildren).
local ManifestWindow = ISCollapsableWindowJoypad:derive("LSManifestWindow")

function ManifestWindow:layout()
    local pad = 8
    local th = self:titleBarHeight()
    local w = self:getWidth()
    local y = th + pad
    if self.filterEntry then
        self.filterEntry:setX(pad); self.filterEntry:setY(y)
        self.filterEntry:setWidth(w - pad * 2)
        y = y + self.filterEntry:getHeight() + pad
    end
    if self.btnItem then
        local listW = w - pad * 2
        local c = colsFor(listW)
        self.btnItem:setX(pad);                    self.btnItem:setY(y);  self.btnItem:setWidth(c.catX)
        self.btnCat:setX(pad + c.catX);            self.btnCat:setY(y);   self.btnCat:setWidth(CAT_W)
        self.btnCount:setX(pad + c.catX + CAT_W);  self.btnCount:setY(y); self.btnCount:setWidth(COUNT_W + SCROLLBAR)
        y = y + self.btnItem:getHeight() + 2
    end
    if self.listBox then
        self.listBox:setX(pad); self.listBox:setY(y)
        self.listBox:setWidth(w - pad * 2)
        self.listBox:setHeight(self:getHeight() - y - 24)   -- leave room for the footer line
    end
end

function ManifestWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.title = "Quartermaster - Manifest"
    self.sortBy = nil          -- nil = no explicit sort (falls back to the default order below)
    self.asc = false
    self.filterText = ""
    self.shownCount = 0
    self.totalCount = 0

    self.filterEntry = ISTextEntryBox:new("", 0, 0, 100, 22)
    self.filterEntry:initialise(); self.filterEntry:instantiate()
    self.filterEntry.font = UIFont.Small
    self.filterEntry:setTooltip("Filter by item name")
    self:addChild(self.filterEntry)

    -- titleLeft pins each label to the left of its column so the right-anchored sort triangle
    -- always has clear space after the text (otherwise a centred label crowds the arrow).
    self.btnItem = ISButton:new(0, 0, 100, 20, "Item", self, function() self:setSort("name") end)
    self.btnItem:initialise(); self.btnItem:instantiate(); self.btnItem.font = UIFont.Small
    self.btnItem.titleLeft = true
    self:addChild(self.btnItem)
    self.btnCat = ISButton:new(0, 0, CAT_W, 20, "Category", self, function() self:setSort("cat") end)
    self.btnCat:initialise(); self.btnCat:instantiate(); self.btnCat.font = UIFont.Small
    self.btnCat.titleLeft = true
    self:addChild(self.btnCat)
    self.btnCount = ISButton:new(0, 0, 60, 20, "Count", self, function() self:setSort("count") end)
    self.btnCount:initialise(); self.btnCount:instantiate(); self.btnCount.font = UIFont.Small
    self.btnCount.titleLeft = true
    self:addChild(self.btnCount)

    self.listBox = ISScrollingListBox:new(0, 0, 100, 100)
    self.listBox:initialise(); self.listBox:instantiate()
    self.listBox.itemheight = 24
    self.listBox.font = UIFont.Small
    self.listBox.drawBorder = true
    local win = self
    self.listBox.doDrawItem = function(lst, y, item, alt) return win:drawRow(lst, y, item, alt) end
    self.listBox.joypadParent = self   -- route the list's left/right to the window's row navigation
    self:addChild(self.listBox)

    self:layout()
    self:rebuild()
end

-- Build the controller focus rows. Deferred (via configJoypadLater) so children are laid out and
-- visible first, and only when a gamepad is actually present. Mirrors vanilla ISButcherHookUI.
function ManifestWindow:configJoypad()
    local joypadData = getJoypadData(self.playerNum)
    self:clearISButtons()
    if not joypadData then return end
    self:clearJoypadFocus(joypadData)
    self.joypadIndexY = 1
    self.joypadIndex = 1
    self.joypadButtonsY = {}
    self.joypadButtons = {}
    self.allJoypadButtons = {}   -- reset too: insertNewLineOfButtons APPENDS to this (else it leaks)
    self.joypadConfigured = true
    -- row 1: filter box (A opens the on-screen keyboard); row 2: the three sort headers
    -- (left/right to pick, A to sort); row 3: the list (up/down scrolls). List is last so the
    -- common scroll path sits at the bottom of the focus order.
    self:insertNewLineOfButtons(self.filterEntry)
    self:insertNewLineOfButtons(self.btnItem, self.btnCat, self.btnCount)
    self:insertNewLineOfButtons(self.listBox)
    self.joypadIndexY = self:getMinVisibleRow()
    self:restoreJoypadFocus(joypadData)
end

function ManifestWindow:onGainJoypadFocus(joypadData)
    ISCollapsableWindowJoypad.onGainJoypadFocus(self, joypadData)
    -- build the focus rows once; re-running on every focus return would leak into allJoypadButtons
    if not self.joypadConfigured then self.configJoypadLater = true end
end

-- B button closes the window (standard console "back"); everything else falls through to the base.
function ManifestWindow:onJoypadDown(button, joypadData)
    if button == Joypad.BButton then
        self:close()
        return
    end
    ISCollapsableWindowJoypad.onJoypadDown(self, button, joypadData)
end

-- names/categories read best A->Z; counts read best biggest-first
local function defaultAsc(col) return col ~= "count" end

-- Each header cycles through three states: default direction -> reversed -> cleared.
function ManifestWindow:setSort(col)
    if self.sortBy ~= col then
        self.sortBy = col; self.asc = defaultAsc(col)          -- 1st click: default direction
    elseif self.asc == defaultAsc(col) then
        self.asc = not self.asc                                -- 2nd click: reverse
    else
        self.sortBy = nil                                      -- 3rd click: clear the sort
    end
    self:rebuild()
end

-- the header button currently sorted on (nil = none)
function ManifestWindow:activeBtn()
    if self.sortBy == "name" then return self.btnItem
    elseif self.sortBy == "cat" then return self.btnCat
    elseif self.sortBy == "count" then return self.btnCount end
    return nil
end

function ManifestWindow:rebuild()
    local lb = self.listBox
    -- preserve the view across a live refresh: remember the selected row BY NAME (indices shift as
    -- items appear/vanish) and the scroll offset, then restore them after repopulating.
    local sel = lb.items[lb.selected]
    local prevName = sel and sel.item and sel.item.name
    local prevScroll = lb:getYScroll()

    -- cleared -> default overview order: biggest piles first
    local sb, asc = self.sortBy, self.asc
    if sb == nil then sb, asc = "count", false end
    local list = LootSorter.manifestAggregate(getStore(), sb, asc)
    local f = self.filterText or ""
    lb:clear()
    local shown, total = 0, 0
    for _, d in ipairs(list) do
        if f == "" or string.find(string.lower(d.name), f, 1, true) then
            lb:addItem(d.name, d)
            shown = shown + 1
            total = total + d.n
        end
    end
    self.shownCount = shown
    self.totalCount = total

    if prevName then
        for i, it in ipairs(lb.items) do
            if it.item.name == prevName then lb.selected = i; break end
        end
    end
    lb:setYScroll(prevScroll)
end

function ManifestWindow:drawRow(list, y, item, alt)
    local d = item.item
    local h = list.itemheight
    local font = list.font
    local c = colsFor(list:getWidth())
    if list.selected == item.index then
        list:drawRect(0, y, list:getWidth(), h - 1, 0.3, 0.7, 0.7, 0.7)
    end
    -- Item: icon + name (name clipped to the category column start)
    local tex = LootSorter.itemTexture(d.ft)
    if tex then list:drawTextureScaled(tex, 4, y + 3, 18, 18, 1.0) end
    list:drawText(fit(font, d.name, c.catX - 28 - 4), 28, y + 4, 1, 1, 1, 1, font)
    -- Category
    list:drawText(fit(font, d.cat, CAT_W - 6), c.catX, y + 4, 0.85, 0.85, 0.85, 1, font)
    -- Count: right-aligned within the content area (never under the scrollbar)
    local cnt = tostring(d.n)
    local fw = getTextManager():MeasureStringX(font, cnt)
    list:drawText(cnt, c.content - fw - 6, y + 4, 1, 1, 1, 1, font)
    return y + h
end

function ManifestWindow:prerender()
    ISCollapsableWindow.prerender(self)
    -- poll the filter box (no reliable per-keystroke callback across builds)
    -- OSK-aware: while the controller's on-screen keyboard is editing our filter, read its LIVE
    -- buffer so the list filters per keystroke (the box itself only updates on Enter).
    local raw = self.filterEntry:getInternalText()
    if OnScreenKeyboard and OnScreenKeyboard.IsVisible() and OnScreenKeyboard.instance
        and OnScreenKeyboard.instance.textEntryBox == self.filterEntry then
        raw = OnScreenKeyboard.GetCurrentText()
        -- mirror the live buffer into the box so the typed text is visible (it otherwise stays
        -- empty until Enter); display-only, the keyboard rewrites it on accept
        if self.filterEntry:getInternalText() ~= raw then self.filterEntry:setText(raw) end
    end
    local ft = string.lower(raw or "")
    if ft ~= self.filterText then self.filterText = ft; self:rebuild() end
    if self.configJoypadLater then self.configJoypadLater = false; self:configJoypad() end
    self:layout()
    self:drawText((self.shownCount or 0) .. " items  -  " .. (self.totalCount or 0) .. " total",
        10, self:getHeight() - 20, 0.7, 1.0, 1.0, 1.0, UIFont.Small)
end

-- render() runs AFTER children draw, so the sort triangle paints on top of the header button
-- (drawing it in prerender put it under the button, which then covered it).
function ManifestWindow:render()
    ISCollapsableWindow.render(self)
    local b = self:activeBtn()
    if b then
        local sz = 7
        drawTri(self, b:getX() + b:getWidth() - sz - 6, b:getY() + (b:getHeight() - sz) / 2 + 1,
            sz, self.asc, 1.0, 0.85, 0.85, 0.85)
    end
end

function ManifestWindow:close()
    -- Hand controller focus BACK to whatever held it before we grabbed it (the inventory) rather than
    -- nil: setJoypadFocus(_, nil) drops focus entirely, leaving the inventory frozen on-screen with
    -- nothing selectable (the same bug the v0.8 "Configure sorting..." fix addressed). prevFocus is
    -- captured when the window grabs focus on open.
    local restore = self.grabbedJoypad and self.prevFocus or nil
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if self.grabbedJoypad then setJoypadFocus(self.playerNum, restore); self.grabbedJoypad = false end
    LootSorter._manifestWin = nil
end

----------------------------------------------------------------------
-- Open / toggle (triggered from the right-click menu -> LootSorter_ContextMenu.lua)
----------------------------------------------------------------------
local function toggleManifest()
    if LootSorter._manifestWin then
        LootSorter._manifestWin:close()
        return
    end
    LootSorter.manifestReconcile()
    local w, h = 420, 480
    local x = getCore():getScreenWidth() / 2 - w / 2
    local y = getCore():getScreenHeight() / 2 - h / 2
    local win = ManifestWindow:new(x, y, w, h)
    win.resizable = true
    win.playerNum = 0
    win:initialise()
    win:addToUIManager()
    win:setVisible(true)
    -- hand controller focus to the window ONLY if a gamepad is bound, so mouse/keyboard is untouched
    local pl = getSpecificPlayer(0)
    if pl and pl:getJoypadBind() ~= -1 then
        local jd = getJoypadData(0)             -- remember who had focus (the inventory) so close()
        win.prevFocus = jd and jd.focus or nil  -- can hand it back instead of dropping focus to nil
        setJoypadFocus(0, win)
        win.grabbedJoypad = true
    end
    LootSorter._manifestWin = win
end
LootSorter.toggleManifest = toggleManifest
