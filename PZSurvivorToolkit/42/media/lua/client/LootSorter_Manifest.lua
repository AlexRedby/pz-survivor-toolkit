-- Read-only warehouse window; authority and network lifecycle live outside the UI.
require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "ISUI/ISScrollingListBox"
require "ISUI/ISComboBox"
local Client = require "PZSurvivorToolkit/ManifestClient"
local View = require "PZSurvivorToolkit/ManifestView"
local Tags = require "PZSurvivorToolkit/ItemTags"
local Presentation = require "PZSurvivorToolkit/ManifestPresentation"
local Visuals = require "PZSurvivorToolkit/TagVisuals"
local helpersOK, containerHelpers = pcall(require, "BetterContainers/Helpers")
local UIStyle = require "PZSurvivorToolkit/UIStyle"
LootSorter = LootSorter or {}

local function tr(key, ...)
    return getText("UI_PZST_Manifest_" .. key, ...)
end
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
    local pad, w = 8, self:getWidth()
    local y = self:titleBarHeight() + pad
    self.filterEntry:setX(pad); self.filterEntry:setY(y)
    self.filterEntry:setWidth(w - 188)
    self.tagPicker:setX(w - 172); self.tagPicker:setY(y); self.tagPicker:setWidth(164)
    y = y + 30
    local c = colsFor(w - pad * 2)
    self.btnItem:setX(pad); self.btnItem:setY(y); self.btnItem:setWidth(c.catX)
    self.btnCat:setX(pad + c.catX); self.btnCat:setY(y); self.btnCat:setWidth(CAT_W)
    self.btnCount:setX(pad + c.catX + CAT_W); self.btnCount:setY(y)
    self.btnCount:setWidth(COUNT_W + SCROLLBAR)
    y = y + 24
    self.listBox:setX(pad); self.listBox:setY(y); self.listBox:setWidth(w - pad * 2)
    self.listBox:setHeight(self:getHeight() - y - 204)
    y = self.listBox:getY() + self.listBox:getHeight() + 24
    self.locations:setX(pad); self.locations:setY(y); self.locations:setWidth(w - pad * 2)
    self.locations:setHeight(self:getHeight() - y - 48)
    self.layoutWidth, self.layoutHeight = w, self:getHeight()
end

function ManifestWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.title = tr("Title")
    self.view = View.new(Presentation.describe, Tags)
    self.sortBy = "count"
    self.asc = false
    self.filterText = ""
    self.shownCount = 0
    self.totalCount = 0

    self.filterEntry = ISTextEntryBox:new("", 0, 0, 100, 22)
    self.filterEntry:initialise(); self.filterEntry:instantiate()
    self.filterEntry.font = UIFont.Small
    self.filterEntry:setTooltip(tr("Search"))
    self:addChild(self.filterEntry)
    self.tagPicker = ISComboBox:new(0, 0, 164, 22, self, function(win) win:rebuild() end)
    self.tagPicker:initialise(); self.tagPicker:instantiate()
    self.tagPicker:addOptionWithData(tr("AllTags"), false)
    self:addChild(self.tagPicker)

    -- titleLeft pins each label to the left of its column so the right-anchored sort triangle
    -- always has clear space after the text (otherwise a centred label crowds the arrow).
    self.btnItem = ISButton:new(0, 0, 100, 20, tr("Item"), self, function() self:setSort("name") end)
    self.btnItem:initialise(); self.btnItem:instantiate(); self.btnItem.font = UIFont.Small
    self.btnItem.titleLeft = true
    self:addChild(self.btnItem)
    self.btnCat = ISButton:new(0, 0, CAT_W, 20, tr("Tags"), self, function() self:setSort("cat") end)
    self.btnCat:initialise(); self.btnCat:instantiate(); self.btnCat.font = UIFont.Small
    self.btnCat.titleLeft = true
    self:addChild(self.btnCat)
    self.btnCount = ISButton:new(0, 0, 60, 20, tr("Count"), self, function() self:setSort("count") end)
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

    self.locations = ISScrollingListBox:new(0, 0, 100, 100)
    self.locations:initialise(); self.locations:instantiate()
    self.locations.itemheight = 40
    self.locations.font = UIFont.Small
    self.locations.drawBorder = true
    self.locations.doDrawItem = function(lst, y, item, alt) return win:drawLocation(lst, y, item, alt) end
    self.locations.joypadParent = self
    self:addChild(self.locations)
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
    self:insertNewLineOfButtons(self.filterEntry, self.tagPicker)
    self:insertNewLineOfButtons(self.btnItem, self.btnCat, self.btnCount)
    self:insertNewLineOfButtons(self.listBox)
    self:insertNewLineOfButtons(self.locations)
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

-- Every sort has an explicit column and direction.
function ManifestWindow:setSort(col)
    if self.sortBy == col then self.asc = not self.asc
    else self.sortBy, self.asc = col, defaultAsc(col) end
    self:rebuild()
end

-- the header button currently sorted on (nil = none)
function ManifestWindow:activeBtn()
    if self.sortBy == "name" then return self.btnItem
    elseif self.sortBy == "cat" then return self.btnCat
    elseif self.sortBy == "count" then return self.btnCount end
    return nil
end

function ManifestWindow:receive(payload, status)
    self.connectionStatus = status
    if payload and self.view:setPayload(payload) then
        local tag = self.tagPicker.options[self.tagPicker.selected]
        tag = tag and tag.data
        self.tagPicker:clear()
        self.tagPicker.selected = 1
        self.tagPicker:addOptionWithData(tr("AllTags"), false)
        for _, id in ipairs(self.view.tagOptions) do
            self.tagPicker:addOptionWithData(Tags.label(id), id)
            if id == tag then self.tagPicker.selected = #self.tagPicker.options end
        end
        self:rebuild()
        self.selectedKey = nil -- refresh location quantities without losing the selected item
    end
end

function ManifestWindow:rebuild()
    local lb = self.listBox
    local sel = lb.items[lb.selected]
    local previousKey, scroll = sel and sel.item and sel.item.key, lb:getYScroll()
    local option = self.tagPicker.options[self.tagPicker.selected]
    local list, count = self.view:select(self.filterText, option and option.data or nil, self.sortBy, self.asc)
    lb:clear()
    for _, row in ipairs(list) do lb:addItem(row.name, row) end
    self.shownCount, self.totalCount = #list, count
    lb.selected = #list > 0 and 1 or 0
    for i, item in ipairs(lb.items) do if item.item.key == previousKey then lb.selected = i; break end end
    lb:setYScroll(scroll)
    self.selectedKey = nil
end

function ManifestWindow:updateLocations()
    local item = self.listBox.items[self.listBox.selected]
    local row = item and item.item
    local key = row and row.key or false
    if self.selectedKey == key then return end
    self.selectedKey = key
    local scroll = self.locations:getYScroll()
    self.locations:clear()
    local origins = {}
    for i, origin in ipairs(row and row.locations or {}) do origins[i] = origin end
    table.sort(origins, function(a, b) return a.id < b.id end)
    for _, origin in ipairs(origins) do self.locations:addItem(origin.id, origin) end
    self.locations:setYScroll(scroll)
end

local function ageText(container)
    if not container.sampledAt or container.sampledAt <= 0 then return tr("UnknownAge") end
    local seconds = math.max(0, math.floor((getTimestampMs() - container.sampledAt) / 1000))
    if seconds < 60 then return tr("SecondsAgo", seconds) end
    if seconds < 3600 then return tr("MinutesAgo", math.floor(seconds / 60)) end
    return tr("HoursAgo", math.floor(seconds / 3600))
end

function ManifestWindow:drawLocation(list, y, item)
    local origin, font = item.item, list.font
    local c, width = origin.container, list:getWidth() - SCROLLBAR - 8
    local label = c.name or (getTextOrNull("IGUI_ContainerTitle_" .. (c.kind or ""))) or tr("Container")
    local appearance = c.color or {r = .8, g = .8, b = .8}
    local icon = c.icon
    local tex
    if icon then
        if helpersOK and containerHelpers then tex = containerHelpers.getIconTexture(icon)
        elseif icon.kind == "pzst-tag" then tex = Visuals.get(icon.value).texture
        elseif icon.kind == "item" then tex = LootSorter.itemTexture(icon.value)
        else tex = getTexture(icon.value) end
    end
    if tex then list:drawTextureScaled(tex, 4, y + 3, 18, 18, 1, appearance.r, appearance.g, appearance.b)
    else list:drawRect(6, y + 7, 12, 12, 1, appearance.r, appearance.g, appearance.b) end
    local count = tostring(origin.n)
    local countWidth = getTextManager():MeasureStringX(font, count)
    list:drawText(fit(font, label, width - countWidth - 36), 28, y + 2,
        appearance.r, appearance.g, appearance.b, 1, font)
    list:drawText(count, width - countWidth, y + 2, 1, 1, 1, 1, font)
    local position = tostring(c.x) .. ", " .. tostring(c.y) .. ", " .. tostring(c.z)
    local detail = position .. " | " .. (c.loaded and tr("Checked") or tr("LastKnown")) .. ": " .. ageText(c)
    list:drawText(fit(font, detail, width - 28), 28, y + 20, .7, .7, .7, 1, font)
    return y + list.itemheight
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
    if self.layoutWidth ~= self:getWidth() or self.layoutHeight ~= self:getHeight() then self:layout() end
    self:updateLocations()
    self:drawText(tr("Locations"), 10, self.locations:getY() - 20, .8, .8, .8, 1, UIFont.Small)
    if #self.listBox.items == 0 then
        self:drawText(fit(UIFont.Small, tr(self.connectionStatus == "loading" and "Loading" or "Empty"), self:getWidth() - 32),
            16, self.listBox:getY() + 12, .7, .7, .7, 1, UIFont.Small)
    end
    self:drawText(fit(UIFont.Small, tr("Totals", self.shownCount or 0, self.totalCount or 0), self:getWidth() - 20),
        10, self:getHeight() - 42, .8, .8, .8, 1, UIFont.Small)
    self:drawText(fit(UIFont.Small, tr(self.connectionStatus == "error" and "Error" or self.connectionStatus == "loading" and "Loading" or "Shared"), self:getWidth() - 20),
        10, self:getHeight() - 24, .7, .8, .8, 1, UIFont.Small)
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
    Client.close(self.playerNum)
    LootSorter._manifestWin = nil
end

----------------------------------------------------------------------
-- Open / toggle (triggered from the right-click menu -> LootSorter_ContextMenu.lua)
----------------------------------------------------------------------
local function toggleManifest(playerNum)
    if LootSorter._manifestWin then LootSorter._manifestWin:close(); return end
    playerNum = playerNum or 0
    local w, h = 640, 600
    local core = getCore()
    w, h = math.min(w, core:getScreenWidth()), math.min(h, core:getScreenHeight())
    local win = ManifestWindow:new((core:getScreenWidth() - w) / 2, (core:getScreenHeight() - h) / 2, w, h)
    win.resizable, win.minimumWidth, win.minimumHeight = true, 480, 440
    win.backgroundColor = {r = .025, g = .025, b = .025, a = .97}
    win.playerNum = playerNum
    win:initialise(); win:addToUIManager(); win:setVisible(true)
    LootSorter._manifestWin = win
    Client.open(playerNum, function(payload, status) win:receive(payload, status) end)
    local player = getSpecificPlayer(playerNum)
    if player and player:getJoypadBind() ~= -1 then
        local jd = getJoypadData(playerNum)
        win.prevFocus = jd and jd.focus or nil
        setJoypadFocus(playerNum, win)
        win.grabbedJoypad = true
    end
end
LootSorter.toggleManifest = toggleManifest
LootSorter.addOrReplaceHandler(Events.OnMainMenuEnter, "_manifestClose", function()
    if LootSorter._manifestWin then LootSorter._manifestWin:close() end
end)
