-- LootSorter: the designation window -- pick CATEGORIES and/or specific ITEMS a box should hold, or the
-- PRESETS (reusable bundles) it uses. Three mode buttons switch the list source; the active one is
-- highlighted. Filter checkboxes "Only Checked" / "Only Contents" combine (AND). Each mode keeps its own
-- selection set, filter, and checkbox state; Save persists all three. In Presets mode, right-click a row
-- (or Y/triangle on a controller) opens the New/Edit/Delete context menu.
require "ISUI/ISCollapsableWindow"
require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISPanel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISTextBox"
require "ISUI/ISModalDialog"
require "ISUI/ISContextMenu"
require "ISUI/ISButton"
require "ISUI/ISLabel"
local TagPicker = require "PZSurvivorToolkit/QuartermasterTags"
local TagRules = require "PZSurvivorToolkit/QuartermasterTagRules"
local Tags = require "PZSurvivorToolkit/ItemTags"
local Categories = require "PZSurvivorToolkit/ItemCategories"
local AppearanceControls = require "PZSurvivorToolkit/ContainerAppearanceControls"

LootSorter = LootSorter or {}
LootSorter.toolkitTagPicker = true

-- ISCollapsableWindowJoypad = a collapsable window with ISPanelJoypad navigation baked in, so the
-- designation window can take controller focus and d-pad between its rows (see configJoypad).
local Picker = ISCollapsableWindowJoypad:derive("LootSorterPicker")

local BOX = 16  -- checkbox glyph size (px)
local ICON = 18 -- item icon size on an Items row (px)
local WIN_W, WIN_H = 480, 700
local ACTIVE_BG = { r = 0.25, g = 0.45, b = 0.75, a = 0.9 }
local IDLE_BG   = { r = 0.20, g = 0.20, b = 0.20, a = 0.9 }
local function tickTex() return getTexture("media/ui/inventoryPanes/Tickbox_Tick.png") end
local function countSet(t) local n = 0; if t then for _, v in pairs(t) do if v then n = n + 1 end end end return n end
local function ui(key) return getText("UI_PZST_Container" .. key) end

-- Keep checked rows, counts and Save on the same effective link selection. This changes only the
-- editor draft: reads must not publish an object's ModData. In SP the library is per-machine while
-- links belong to a world, so an absent library preset cannot justify clearing a world link.
-- Before the initial snapshot arrives on a Host client,
-- absence is unknown, so retain every saved link until synchronization can resolve it reliably.
function Picker:resolvePresetSelection()
    if self.targetKind == "preset" or not isClient() or not LootSorter.arePresetsSynced() then return end
    local presets = LootSorter.getPresetStore()
    for name, link in pairs(self.selectedPresets) do
        if not LootSorter.linkResolves(presets[name], link) then
            self.selectedPresets[name] = nil
            self.needRebuild = true
        end
    end
end

-- the list source for the active mode (categories vs item display names)
function Picker:activeList()
    if self.mode == "items" then return LootSorter.getItemNames()
    elseif self.mode == "presets" then return LootSorter.presetNames(LootSorter.getPresetStore())
    elseif Tags.enabled() then return TagPicker.categories(LootSorter.getCategories(), self.selectedCats)
    else return LootSorter.getCategories() end
end

-- entries matching what's currently in the target box (for "Only Contents"), cached per mode
function Picker:contentsSet()
    self._contents = self._contents or {}
    if self._contents[self.mode] then return self._contents[self.mode] end
    local set = {}
    pcall(function()
        local cont = self.targetObj and self.targetObj:getContainerByIndex(self.targetCI)
        if cont then
            Categories.prepareContainer(cont)
            local items = cont:getItems()
            for i = 0, items:size() - 1 do
                local it = items:get(i)
                if it then
                    if self.mode == "items" then
                        local nm = it:getDisplayName(); if nm and nm ~= "" then set[nm] = true end
                    else
                        local c = it:getDisplayCategory(); if c and c ~= "" then set[c] = true end
                    end
                end
            end
        end
    end)
    self._contents[self.mode] = set
    return set
end

function Picker:setPriority(value)
    self.priority = value
    self.priorityEntry:setText(tostring(value))
end

function Picker:onPriorityDown() self:setPriority(self.priority - 1) end
function Picker:onPriorityUp() self:setPriority(self.priority + 1) end

-- Anything that is not a digit or a leading minus is dropped as it is typed, and digits past the limit
-- are refused rather than accepted and clamped later. Counting DIGITS, not characters, is the point: a
-- character cap would let an unsigned number run one longer than a negative one. Nothing clamps the
-- number itself -- only the ORDER of two boxes ever matters, never the gap between them.
function Picker:onPriorityTyped()
    local typed = self.priorityEntry:getInternalText()
    local sign = (typed:sub(1, 1) == "-") and "-" or ""
    local digits = typed:gsub("%D", ""):sub(1, LootSorter.PRIORITY_MAX_DIGITS)
    local cleaned = sign .. digits
    if cleaned ~= typed then self.priorityEntry:setText(cleaned) end
    self.priority = tonumber(cleaned) or 0      -- "" and "-" are mid-edit states, both mean 0
end

-- an ISButton drawn as a checkbox bound to self[field] (a bool)
function Picker:makeCheckbox(field, label)
    local picker = self
    local b = ISButton:new(10, 0, 10, 22, "", self, function()
        picker[field] = not picker[field]
        picker.needRebuild = true
    end)
    b.qmField, b.qmLabel = field, label
    b.prerender = function(self2)
        local w, h = self2:getWidth(), self2:getHeight()
        if self2:isMouseOver() then self2:drawRect(0, 0, w, h, 0.08, 1, 1, 1) end
        if self2.joypadFocused then self2:drawRectBorder(0, 0, w, h, 0.9, 0.55, 0.85, 1.0) end
        local bx, by = 2, (h - BOX) / 2
        self2:drawRect(bx, by, BOX, BOX, 0.7, 0.08, 0.08, 0.08)
        self2:drawRectBorder(bx, by, BOX, BOX, 0.9, 0.7, 0.7, 0.7)
        if picker[self2.qmField] then
            local gc = getCore():getGoodHighlitedColor()
            self2:drawTextureScaled(tickTex(), bx + 2, by + 2, BOX - 4, BOX - 4, 1, gc:getR(), gc:getG(), gc:getB())
        end
        local fh = getTextManager():getFontHeight(UIFont.Small)
        self2:drawText(self2.qmDynLabel or self2.qmLabel, bx + BOX + 6, (h - fh) / 2, 1, 1, 1, 1, UIFont.Small)
    end
    return b
end

function Picker:createChildren()
    ISCollapsableWindow.createChildren(self)
    local pad = 10

    self.toolkitTagRuleRevision = TagRules.getBoxRevision(self.targetObj, self.targetCI)
    if self.targetKind == "preset" then
        self.toolkitTagRule = TagRules.getPreset(self.presetName, LootSorter.getPresetStore()[self.presetName])
    else
        self.toolkitTagRule = TagRules.getBox(self.targetObj, self.targetCI)
    end
    AppearanceControls.create(self)

    local function label(key, font, r, g, b)
        local child = ISLabel:new(pad, 0, 22, ui(key), r or 1, g or 1, b or 1, 1, font or UIFont.Small, true)
        child:initialise(); child:instantiate(); self:addChild(child)
        return child
    end
    self.sortingHeading = label("Sorting", UIFont.Medium, 0.85, 0.9, 1)
    self.sortingHint = label("SortingHint", UIFont.Small, 0.8, 0.8, 0.8)
    self.filterLabel = label("Search")

    self.filter = ISTextEntryBox:new("", pad, 0, 10, 22)
    self.filter:initialise(); self.filter:instantiate()
    self.filter:setFont(UIFont.Medium)
    self:addChild(self.filter)
    self.filter:setTooltip(ui("SearchHint"))
    self.filter.backgroundColor = {r = 0.08, g = 0.10, b = 0.13, a = 1}
    self.filter.borderColor = {r = 0.5, g = 0.65, b = 0.8, a = 1}
    self.lastFilter = nil

    -- mode row: Categories | Items (highlighted buttons)
    self.btnModeCat = ISButton:new(pad, 0, 10, 22, "Categories", self, Picker.onModeCat)
    self.btnModeItem = ISButton:new(pad, 0, 10, 22, "Items", self, Picker.onModeItem)
    self.btnModePreset = ISButton:new(pad, 0, 10, 22, "Presets", self, Picker.onModePreset)
    self.btnModeCat:setTooltip("Designate by item category")
    self.btnModeItem:setTooltip("Designate specific items (by name)")
    self.btnModePreset:setTooltip("Reusable bundles of categories/items. Ticking a preset makes this box use it in addition to any manual categories/items picks. Global presets can also be modified here.")

    -- filter row: two combinable checkboxes
    self.chkChecked = self:makeCheckbox("onlyChecked", ui("OnlyChecked"))
    self.chkContents = self:makeCheckbox("onlyContents", ui("OnlyContents"))
    self.chkChecked:setTooltip(ui("OnlyCheckedHint"))
    self.chkContents:setTooltip(ui("OnlyContentsHint"))
    self.chkNoDuplicates = self:makeCheckbox("noDuplicates", ui("NoDuplicates"))
    self.chkNoDuplicates:setTooltip(ui("NoDuplicatesHint"))

    self.toolkitTagSwitch = ISButton:new(pad, 0, 10, 22, "", self, Picker.onTagView)
    self.toolkitTagRuleButton = ISButton:new(pad, 0, 10, 22, "", self, Picker.onTagRule)
    self.toolkitTagSwitch:setTooltip(getText("UI_PZST_QMTagsHint"))
    self.toolkitTagRuleButton:setTooltip(getText("UI_PZST_QMTagRuleHint"))

    -- Priority: higher boxes are filled first, 0 is normal, negatives go last. A preset is not a box,
    -- so the editor hides these.
    self.btnPriorityDown = ISButton:new(0, 0, 22, 22, "-", self, Picker.onPriorityDown)
    self.btnPriorityUp = ISButton:new(0, 0, 22, 22, "+", self, Picker.onPriorityUp)
    local priorityTip = ui("PriorityHint")
    -- Not setOnlyNumbers: that rejects the minus sign too, and negatives are half the point. The
    -- change handler validates instead.
    self.priorityEntry = ISTextEntryBox:new(tostring(self.priority), 0, 0, 40, 22)
    self.priorityEntry:initialise(); self.priorityEntry:instantiate()
    self.priorityEntry:setFont(UIFont.Small)
    self.priorityEntry.target = self
    self.priorityEntry.onTextChangeFunction = Picker.onPriorityTyped
    self.priorityEntry:setMaxTextLength(LootSorter.PRIORITY_MAX_DIGITS + 1)   -- +1 for a minus sign
    self:addChild(self.priorityEntry)

    self.priorityLabel = ISLabel:new(0, 0, 22, ui("Priority"), 1, 1, 1, 1, UIFont.Small, true)
    self.priorityLabel:initialise(); self.priorityLabel:instantiate()
    self.priorityLabel:setTooltip(priorityTip)
    self:addChild(self.priorityLabel)

    -- the list
    self.listbox = ISScrollingListBox:new(pad, 0, 10, 10)
    self.listbox.itemheight = 22
    self.listbox.drawBorder = true
    -- Restore the window's stencil before drawing empty-state text over this list.
    self.listbox.doRepaintStencil = true
    self.listbox.target = self
    self.listbox.doDrawItem = Picker.doDrawItem
    self.listbox.prerender = Picker.prerenderList
    self.listbox.onmousedown = Picker.onRowClick        -- left-click toggles the row (all modes)
    self.listbox.joypadParent = self
    -- right-click a row -> the menu for the active mode: preset management (Edit / Delete / New) in
    -- Presets, "List items in ..." in Categories. Items mode has none.
    self.listbox.onRightMouseUp = function(lb, x, y)
        local row = lb.mouseoverselected and lb.items[lb.mouseoverselected]
        local key = row and row.item and row.item.key
        -- Tag rows have no category inspector; saved unknown categories retain their exact key.
        if TagPicker.isTagView(lb.target) and not key then return end
        Picker.openRowMenu(lb.target, key, getMouseX(), getMouseY())
    end
    -- Controller model: the list is a normal navigable ROW -- up/down pass OVER it to the rows above/
    -- below (so the action buttons below stay reachable). Press A to ENTER it; then up/down scroll and
    -- A toggles the highlighted item; B exits back to row navigation.
    --
    -- By default a focused ISScrollingListBox captures input (joypadData.focus = self), which traps
    -- up/down. Override setJoypadFocused to only set the highlight flag, NOT capture:
    self.listbox.setJoypadFocused = function(lb, focused, joypadData)
        lb.joypadFocused = focused
    end
    -- A while the window is highlighting the list row -> enter (capture focus for scrolling)
    self.listbox.onJoypadDownInParent = function(lb, button, joypadData)
        if button == Joypad.AButton then
            lb.joypadFocused = true
            joypadData.focus = lb
            updateJoypadFocus(joypadData)
            if (lb.selected or 0) < 1 and lb.count > 0 then lb.selected = 1 end
            return true
        end
        return false
    end
    -- Once entered (focus == list): A toggles the highlighted item, B exits to row nav.
    -- (Own onJoypadDown, nil-guarded -- vanilla's A path indexes self.items[self.selected] unchecked.)
    self.listbox.onJoypadDown = function(lb, button, joypadData)
        if button == Joypad.LBumper then lb.target:cycleMode(-1); return end
        if button == Joypad.RBumper then lb.target:cycleMode(1); return end
        if button == Joypad.YButton then
            -- Y/triangle on the highlighted row -> the same menu the mouse gets from right-click
            local selection = lb.items[lb.selected]
            local key = selection and selection.item and selection.item.key
            if TagPicker.isTagView(lb.target) and not key then return end
            Picker.openRowMenu(lb.target, key,
                lb.target:getAbsoluteX() + 30, lb.target:getAbsoluteY() + 40)
            return
        end
        if button == Joypad.AButton then
            local selection = lb.items[lb.selected]
            if selection then Picker.onRowClick(lb.target, selection.item) end
            return
        end
        if button == Joypad.BButton then
            lb.joypadFocused = false
            joypadData.focus = lb.joypadParent
            updateJoypadFocus(joypadData)
            return
        end
        ISPanelJoypad.onJoypadDown(lb, button, joypadData)
    end
    -- up/down scroll ONLY while entered (they fire only when focus == list); move the highlight
    -- without invoking onmousedown (vanilla's up/down would toggle the checkbox every step).
    self.listbox.onJoypadDirUp = function(lb)
        lb.selected = lb:prevVisibleIndex(lb.selected)
        if lb.selected <= 0 then lb.selected = lb:prevVisibleIndex(lb.count + 1) end
        getSoundManager():playUISound("UISelectListItem")
        lb:ensureVisible(lb.selected)
    end
    self.listbox.onJoypadDirDown = function(lb)
        lb.selected = lb:nextVisibleIndex(lb.selected)
        if lb.selected == -1 then lb.selected = lb:nextVisibleIndex(0) end
        getSoundManager():playUISound("UISelectListItem")
        lb:ensureVisible(lb.selected)
    end

    -- action buttons (uniform across all modes; preset management is via the row's context menu)
    self.btnAll = ISButton:new(pad, 0, 10, 26, ui("CheckFiltered"), self, Picker.onSelectFiltered)
    self.btnClear = ISButton:new(pad, 0, 10, 26, ui("UncheckAll"), self, Picker.onClear)
    self.btnSave = ISButton:new(pad, 0, 10, 26, ui("Save"), self, Picker.onSave)
    self.btnSave.backgroundColor = {r = 0.15, g = 0.3, b = 0.22, a = 1}

    -- priorityEntry is absent on purpose: like self.filter it is a text box, already initialised and
    -- added where it was created.
    for _, b in ipairs({ self.btnModeCat, self.btnModeItem, self.btnModePreset, self.chkChecked, self.chkContents, self.chkNoDuplicates,
                         self.toolkitTagSwitch, self.toolkitTagRuleButton,
                         self.btnPriorityDown, self.btnPriorityUp,
                         self.listbox, self.btnAll, self.btnClear, self.btnSave }) do
        b:initialise(); b:instantiate(); self:addChild(b)
    end

    -- Dim overlay shown over THIS window only while its preset editor is open: it greys the picker and
    -- eats clicks to it (so it can't be touched behind the editor) WITHOUT dimming the rest of the
    -- screen. Added last so it's the topmost child (covers the buttons/list); hidden until the editor opens.
    self.dimmer = ISPanel:new(0, 0, self:getWidth(), self:getHeight())
    self.dimmer.background = false
    self.dimmer:initialise()
    self.dimmer:setVisible(false)
    self.dimmer.prerender = function(dim) dim:drawRect(0, 0, dim:getWidth(), dim:getHeight(), 0.65, 0, 0, 0) end
    self.dimmer.onMouseDown = function()
        local editor = LootSorter._presetEditor
        if editor then
            if editor.nudge then editor:nudge() end
            editor._reassertTop = true   -- the click raises the picker above the editor; re-raise it next frame
        end
        return true   -- swallow the click; do NOT fall through to the picker's buttons beneath
    end
    self:addChild(self.dimmer)

    self:layout()
    self:rebuild()
end

-- position every control from the CURRENT window size, so resizing stays aligned and nothing clips
function Picker:layout()
    local pad, gap = 10, 6
    local rowH = math.max(26, getTextManager():getFontHeight(UIFont.Small) + 8)
    local searchH = math.max(rowH, getTextManager():getFontHeight(UIFont.Medium) + 8)
    local hintH = getTextManager():getFontHeight(UIFont.Small) + 6
    local btnH = rowH + 4
    local w, h = self:getWidth(), self:getHeight()
    local innerW = w - pad * 2
    local halfW = (innerW - gap) / 2
    local rightX = pad + halfW + gap
    local top = self:titleBarHeight() + 8
    top = AppearanceControls.layout(self, top)
    self.sortingHeading:setY(top); self.sortingHeading:setHeight(rowH)
    self.sortingHint:setY(top + rowH); self.sortingHint:setHeight(hintH)
    top = top + rowH + hintH + gap
    local searchLabelW = getTextManager():MeasureStringX(UIFont.Small, ui("Search")) + 12
    self.filterLabel:setY(top); self.filterLabel:setHeight(searchH)
    self.filter:setX(pad + searchLabelW); self.filter:setY(top)
    self.filter:setWidth(innerW - searchLabelW); self.filter:setHeight(searchH)

    self.listbox.itemheight = math.max(22, getTextManager():getFontHeight(UIFont.Medium) + 6)
    local modeY = top + searchH + gap
    -- box picker: three mode toggles (Categories / Items / Presets). Preset editor: two only (no nested
    -- Presets tab), so the Presets button is hidden and the row splits in half.
    local editingPreset = self.targetKind == "preset"
    self.btnModePreset:setVisible(not editingPreset)
    if editingPreset then
        self.btnModeCat:setX(pad); self.btnModeCat:setY(modeY); self.btnModeCat:setWidth(halfW); self.btnModeCat:setHeight(rowH)
        self.btnModeItem:setX(rightX); self.btnModeItem:setY(modeY); self.btnModeItem:setWidth(halfW); self.btnModeItem:setHeight(rowH)
    else
        local thirdW = (innerW - gap * 2) / 3
        self.btnModeCat:setX(pad); self.btnModeCat:setY(modeY); self.btnModeCat:setWidth(thirdW); self.btnModeCat:setHeight(rowH)
        self.btnModeItem:setX(pad + thirdW + gap); self.btnModeItem:setY(modeY); self.btnModeItem:setWidth(thirdW); self.btnModeItem:setHeight(rowH)
        self.btnModePreset:setX(pad + (thirdW + gap) * 2); self.btnModePreset:setY(modeY); self.btnModePreset:setWidth(thirdW); self.btnModePreset:setHeight(rowH)
    end

    -- Filter checkboxes share two rows with priority. The per-container duplicate policy gets
    -- a separate row below them so translated labels remain readable at the minimum width.
    local viewY = modeY + rowH + gap
    local stack = 2                                  -- breathing room between the stacked checkboxes
    local secondRowY = viewY + rowH + stack
    local showPriority = self.targetKind ~= "preset"
    local stepW, valueW, tight = rowH, 54, 2
    local priorityW = stepW * 2 + valueW + tight * 2
    priorityW = math.max(priorityW, getTextManager():MeasureStringX(UIFont.Small, ui("Priority")))
    for _, b in ipairs({ self.btnPriorityDown, self.btnPriorityUp, self.priorityEntry, self.priorityLabel }) do
        b:setVisible(showPriority)
    end
    if showPriority then
        local blockX = pad + innerW - priorityW
        self.priorityLabel:setX(blockX); self.priorityLabel:setY(viewY)
        self.priorityLabel:setHeight(rowH)
        self.btnPriorityDown:setX(blockX); self.btnPriorityDown:setY(secondRowY)
        self.btnPriorityDown:setWidth(stepW); self.btnPriorityDown:setHeight(rowH)
        self.btnPriorityUp:setX(blockX + stepW + tight); self.btnPriorityUp:setY(secondRowY)
        self.btnPriorityUp:setWidth(stepW); self.btnPriorityUp:setHeight(rowH)
        self.priorityEntry:setX(blockX + (stepW + tight) * 2); self.priorityEntry:setY(secondRowY)
        self.priorityEntry:setWidth(valueW); self.priorityEntry:setHeight(rowH)
    end
    -- Sized to their own text, not to the space available: the whole width is clickable and highlights
    -- on hover, so a full-width checkbox reads as a button stretching far past its label.
    local available = innerW - (showPriority and (priorityW + gap) or 0)
    local function checkboxWidth(b)
        local label = b.qmDynLabel or b.qmLabel or ""
        local textW = getTextManager():MeasureStringX(UIFont.Small, label)
        return math.min(available, BOX + 12 + textW)   -- glyph, its inset, the gap after it, a tail
    end
    self.chkChecked:setX(pad); self.chkChecked:setY(viewY)
    self.chkChecked:setWidth(checkboxWidth(self.chkChecked)); self.chkChecked:setHeight(rowH)
    self.chkContents:setX(pad); self.chkContents:setY(secondRowY)
    self.chkContents:setWidth(checkboxWidth(self.chkContents)); self.chkContents:setHeight(rowH)
    self.chkNoDuplicates:setVisible(showPriority)
    local thirdRowY = secondRowY + rowH + stack
    self.chkNoDuplicates:setX(pad); self.chkNoDuplicates:setY(thirdRowY)
    available = innerW
    self.chkNoDuplicates:setWidth(checkboxWidth(self.chkNoDuplicates)); self.chkNoDuplicates:setHeight(rowH)

    local showTags = Tags.enabled() and self.mode == "cats"
    local listY = (showPriority and thirdRowY or secondRowY) + rowH + gap
    local visibleListY = listY + (showTags and (rowH + gap) * 2 or 0)
    self.minimumHeight = math.max(600, visibleListY + math.max(40, self.listbox.itemheight * 2) + gap + btnH + 12)
    if h < self.minimumHeight then h = self.minimumHeight; self:setHeight(h) end
    local by = h - btnH - 12                        -- action row, kept clear of the resize corner
    local bw = (innerW - pad * 2) / 3
    local xs = { pad, pad * 2 + bw, pad * 3 + bw * 2 }
    for i, b in ipairs({ self.btnAll, self.btnClear, self.btnSave }) do
        b:setX(xs[i]); b:setY(by); b:setWidth(bw); b:setHeight(btnH)
    end

    self.toolkitTagSwitch:setVisible(showTags)
    self.toolkitTagRuleButton:setVisible(showTags)
    if showTags then
        self.toolkitTagSwitch:setX(pad); self.toolkitTagSwitch:setY(listY)
        self.toolkitTagSwitch:setWidth(innerW); self.toolkitTagSwitch:setHeight(rowH)
        self.toolkitTagRuleButton:setX(pad); self.toolkitTagRuleButton:setY(listY + rowH + gap)
        self.toolkitTagRuleButton:setWidth(innerW); self.toolkitTagRuleButton:setHeight(rowH)
    end
    self.listbox:setX(pad); self.listbox:setY(listY); self.listbox:setWidth(innerW)
    self.listbox:setHeight(math.max(40, (by - gap) - listY))
    if showTags then
        self.listbox:setY(listY + (rowH + gap) * 2)
        self.listbox:setHeight(math.max(12, self.listbox:getHeight() - (rowH + gap) * 2))
    end
    -- This layout owns the scrollbar frame. Native anchors apply a deferred parent-size delta
    -- after Lua layout; combining them with these exact sizes resizes/moves the bar twice.
    local scroll = self.listbox.vscroll
    if scroll then
        scroll:setAnchorRight(false)
        scroll:setAnchorBottom(false)
        scroll:setX(innerW - 16)
        scroll:setY(0)
        scroll:setHeight(self.listbox:getHeight())
        self.listbox:updateScrollbars()
    end

    if self.dimmer then                              -- cover the whole window (incl. title bar) when shown
        self.dimmer:setX(0); self.dimmer:setY(0)
        self.dimmer:setWidth(self:getWidth()); self.dimmer:setHeight(self:getHeight())
    end
end

function Picker:countChecked()
    local n = 0
    for _, v in pairs(self.selection) do if v then n = n + 1 end end
    return n
end

-- rebuild the visible list: active-mode source, filtered by text AND the two checkboxes (combinable)
-- OSK-aware live filter text: while the controller's on-screen keyboard is editing our filter box,
-- read its live buffer so filtering updates per keystroke instead of only on Enter.
function Picker:currentFilter()
    if OnScreenKeyboard and OnScreenKeyboard.IsVisible() and OnScreenKeyboard.instance
        and OnScreenKeyboard.instance.textEntryBox == self.filter then
        return OnScreenKeyboard.GetCurrentText() or ""
    end
    return self.filter:getInternalText() or ""
end

function Picker:rebuild()
    local text = string.lower(self:currentFilter())
    local contents = self.onlyContents and self:contentsSet() or nil
    local tagView = TagPicker.isTagView(self)
    local entries = self:activeList()
    if tagView then
        entries = TagPicker.rows(self, entries)
    end
    self.listbox:clear()
    for _, entry in ipairs(entries) do
        local label = tagView and entry.label or entry
        local checked, hasContents
        if tagView then
            checked = TagPicker.state(self.selectedCats, entry, self.toolkitTagRule) > 0
            hasContents = not contents
            if contents then
                for _, category in ipairs(entry.sourceCategories) do
                    if contents[category] then hasContents = true; break end
                end
            end
        else
            checked = self.selection[entry]
            hasContents = not contents or contents[entry]
        end
        if (text == "" or string.find(string.lower(label), text, 1, true))
            and (not self.onlyChecked or checked) and hasContents then
            self.listbox:addItem(label, tagView and entry or {key = entry})
        end
    end
    self.lastFilter = text
    self.needRebuild = false
    self.emptyListKey = nil
    if self.listbox.count == 0 then
        local key = "NoEntries"
        if text ~= "" or self.onlyContents then key = "NoMatches"
        elseif self.onlyChecked and countSet(self.selection) == 0 then key = "NoSelected"
        elseif self.mode == "presets" and #entries == 0 then key = "NoPresets" end
        self.emptyListKey = key
    end
end

-- Keep empty-state text in the list's own drawing pass, above its background.
function Picker.prerenderList(list)
    ISScrollingListBox.prerender(list)
    local key = list.target.emptyListKey
    if not key then return end
    local top = 12 - list:getYScroll()
    list:drawText(ui(key), 12, top, 0.8, 0.82, 0.85, 1, UIFont.Small)
    if key ~= "NoEntries" then
        list:drawText(ui(key .. "Hint"), 12, top + getTextManager():getFontHeight(UIFont.Small) + 6,
            0.65, 0.68, 0.72, 1, UIFont.Small)
    end
end

function Picker:prerender()
    self:resolvePresetSelection()
    local tagRevision = Tags.revision and Tags.revision() or 0
    if self.toolkitTagRevision ~= tagRevision then
        self.toolkitTagRevision, self.needRebuild = tagRevision, true
    end
    local enabled = Tags.enabled()
    if self.toolkitTagsEnabled ~= enabled then
        self.toolkitTagsEnabled, self.needRebuild = enabled, true
        self:layout()
        if self.joypadConfigured then self:configJoypad() end
    end
    local ruleActive = Tags.ruleActive(self.toolkitTagRule)
    self.toolkitTagRuleButton:setTitle(ui(ruleActive and "EditRule" or "AddRule"))
    self.toolkitTagRuleButton.backgroundColor = ruleActive and ACTIVE_BG or IDLE_BG
    self.toolkitTagSwitch:setTitle(getText(self.toolkitTagView and "UI_PZST_QMShowCategories" or "UI_PZST_QMShowTags"))
    ISCollapsableWindow.prerender(self)
    if self.configJoypadLater then self.configJoypadLater = false; self:configJoypad() end
    if self._lw ~= self:getWidth() or self._lh ~= self:getHeight() then
        self._lw, self._lh = self:getWidth(), self:getHeight()
        self:layout()
    end
    -- A tag may cover several categories; do not present the category count as a tag count.
    self.btnModeCat:setTitle(enabled and self.toolkitTagView and ui("Tags")
        or (ui("Categories") .. " (" .. countSet(self.selectedCats) .. ")"))
    self.btnModeItem:setTitle(ui("Items") .. " (" .. countSet(self.selectedItems) .. ")")
    self.btnModeCat.backgroundColor  = (self.mode == "cats")  and ACTIVE_BG or IDLE_BG
    self.btnModeItem.backgroundColor = (self.mode == "items") and ACTIVE_BG or IDLE_BG
    if self.targetKind ~= "preset" then
        self.btnModePreset:setTitle(ui("Presets") .. " (" .. countSet(self.selectedPresets) .. ")")
        self.btnModePreset.backgroundColor = (self.mode == "presets") and ACTIVE_BG or IDLE_BG
    end
    -- "Only Contents" filters by what's physically in the box -- meaningless for presets, hide it there
    self.chkContents:setVisible(self.mode ~= "presets")
    -- mirror the on-screen keyboard's live text into the visible filter box so it shows while typing
    if OnScreenKeyboard and OnScreenKeyboard.IsVisible() and OnScreenKeyboard.instance
        and OnScreenKeyboard.instance.textEntryBox == self.filter then
        local live = OnScreenKeyboard.GetCurrentText() or ""
        if self.filter:getInternalText() ~= live then self.filter:setText(live) end
    end
    local text = string.lower(self:currentFilter())
    if self.needRebuild or text ~= self.lastFilter then self:rebuild() end
    -- modal-nudge flash: a bright border for a few frames when the user clicks the blocked backdrop
    if self._nudgeFrames and self._nudgeFrames > 0 then
        self._nudgeFrames = self._nudgeFrames - 1
        self:drawRectBorder(0, 0, self:getWidth(), self:getHeight(), 0.85, 0.95, 0.85, 0.25)
    end
    -- a click on the dimmed box picker raised it above us; re-raise this editor so it stays on top
    if self._reassertTop then self._reassertTop = false; self:bringToTop() end
end

-- draw a row: real checkbox glyph + label, with hover / checked highlight
function Picker.doDrawItem(self, y, item, alt)
    local picker = self.target
    if TagPicker.isTagView(picker) and item.item.toolkitTagRow then return TagPicker.drawRow(self, y, item) end
    local key = item.item.key
    local on = picker.selection[key] and true or false
    local w, h = self:getWidth(), item.height

    -- ISScrollingListBox draws every row every frame regardless of visibility; skip off-screen ones
    -- like vanilla's own long lists do (LuaFileBrowser). Still return the row height for measurement.
    local scroll = self:getYScroll()
    if y + scroll + h < 0 or y + scroll >= self:getHeight() then return y + h end

    if on then
        self:drawRect(0, y, w, h - 1, 0.28, 0.25, 0.45, 0.75)
    elseif self.mouseoverselected == item.index and self:isMouseOver() then
        self:drawRect(0, y, w, h - 1, 0.25, 0.35, 0.35, 0.35)
    end
    -- cursor row: a translucent highlight OVER whatever's underneath, so controller/keyboard focus is
    -- clear on both checked (blue) and unchecked rows (checked + cursor reads as a lighter blue).
    if self.selected == item.index then
        self:drawRect(0, y, w, h - 1, 0.30, 0.55, 0.75, 1.0)
    end

    local bx, by = 6, y + (h - BOX) / 2
    self:drawRect(bx, by, BOX, BOX, 0.7, 0.08, 0.08, 0.08)
    self:drawRectBorder(bx, by, BOX, BOX, 0.9, 0.7, 0.7, 0.7)
    if on then
        local gc = getCore():getGoodHighlitedColor()
        self:drawTextureScaled(tickTex(), bx + 2, by + 2, BOX - 4, BOX - 4, 1, gc:getR(), gc:getG(), gc:getB())
    end

    -- Items rows carry the item's icon; a category or preset has no single item to show one for.
    local textX = bx + BOX + 8
    if picker.mode == "items" then
        local texture = LootSorter.itemTexture(LootSorter.getItemFullType(key))
        if texture then self:drawTextureScaled(texture, textX, y + 2, ICON, ICON, 1.0) end
        textX = textX + ICON + 6            -- indent even without an icon, so names stay in one column
    end
    local fh = getTextManager():getFontHeight(UIFont.Medium)
    self:drawText(key, textX, y + (h - fh) / 2, 1, 1, 1, 1, UIFont.Medium)
    if picker.mode == "presets" then
        -- in Presets mode, show each preset's size ("3 cats, 1 item") right-aligned
        local preset = LootSorter.getPresetStore()[key]
        if preset then
            local nc = 0; for _ in pairs(preset.cats or {}) do nc = nc + 1 end
            local ni = 0; for _ in pairs(preset.items or {}) do ni = ni + 1 end
            local summary = ("%d cat%s, %d item%s"):format(nc, nc == 1 and "" or "s", ni, ni == 1 and "" or "s")
            local sfh = getTextManager():getFontHeight(UIFont.Small)
            self:drawTextRight(summary, w - 8, y + (h - sfh) / 2, 0.7, 0.7, 0.7, 1, UIFont.Small)
        end
    end
    return y + h
end

-- A preset link records the generation it was made against, so a preset deleted and remade under
-- the same name no longer matches. Everything else is a plain flag.
function Picker:selectionValue(key)
    if self.mode ~= "presets" then return true end
    local preset = LootSorter.getPresetStore()[key]
    if preset and preset.gen then return preset.gen end
    return true
end

function Picker.onRowClick(picker, itemData)
    if not itemData then return end
    if TagPicker.isTagView(picker) and itemData.toolkitTagRow then
        local checked, total = TagPicker.state(picker.selectedCats, itemData, picker.toolkitTagRule)
        TagPicker.select(picker, itemData, checked ~= total)
        picker.needRebuild = true
        return
    end
    local key = itemData.key
    if picker.selection[key] then
        picker.selection[key] = nil
    else
        picker.selection[key] = picker:selectionValue(key)
        AppearanceControls.select(picker, picker.mode, key)
    end
    if picker.onlyChecked then picker.needRebuild = true end -- unticking drops it from the checked view
end

function Picker:onSelectFiltered()
    if TagPicker.isTagView(self) then
        for _, entry in ipairs(self.listbox.items) do
            TagPicker.select(self, entry.item, true)
        end
        self.needRebuild = true
        return
    end
    for i = 1, #self.listbox.items do
        local key = self.listbox.items[i].item.key
        if not self.selection[key] then AppearanceControls.select(self, self.mode, key) end
        self.selection[key] = self:selectionValue(key)
    end
end

function Picker:onClear()
    if self.mode == "items" then self.selectedItems = {}; self.selection = self.selectedItems
    elseif self.mode == "presets" then self.selectedPresets = {}; self.selection = self.selectedPresets
    else
        self.selectedCats = {}; self.selection = self.selectedCats
        self.toolkitTagRule = Tags.normalizeRule(nil)
        self.toolkitTagRuleTouched = true
    end
    if self.onlyChecked then self.needRebuild = true end
end

function Picker:onTagView()
    self.toolkitTagView = not self.toolkitTagView
    self.needRebuild = true
    self.listbox:setYScroll(0)
end

function Picker:onTagRule()
    TagPicker.openRule(self, self.toolkitTagRule)
end

-- The row context menu, opened by right-click or Y/triangle. Each mode offers its own; Items has
-- nothing to offer, so it opens no menu at all rather than an empty one.
function Picker.openRowMenu(picker, key, x, y)
    if picker.mode == "presets" then return Picker.openPresetMenu(picker, key, x, y) end
    if picker.mode == "cats" then return Picker.openCategoryMenu(picker, key, x, y) end
end

-- Categories: read what a category actually contains before ticking it. An entry named for the
-- category rather than a bare "List items", so the menu says which row it opened on.
function Picker.openCategoryMenu(picker, key, x, y)
    if not key then return end
    local menu = ISContextMenu.get(picker.playerNum or 0, x, y)
    menu:addOption('List items in "' .. key .. '"', picker, Picker.onCategoryList, key)
    if picker.grabbedJoypad then
        menu.origin = picker
        menu.mouseOver = 1
        setJoypadFocus(picker.playerNum, menu)
    end
    return menu
end

function Picker.onCategoryList(picker, key)
    if key then LootSorter.openCategoryView(key, picker.playerNum, picker) end
end

-- Preset management lives in a context menu (right-click a preset, or Y/triangle on the highlighted one
-- with a controller) instead of bottom buttons, so it works cleanly with a pad. `key` is the preset the
-- menu was opened on (nil when opened over empty space -> only New is offered).
function Picker.openPresetMenu(picker, key, x, y)
    if picker.mode ~= "presets" then return end
    local menu = ISContextMenu.get(picker.playerNum or 0, x, y)
    if key then
        menu:addOption('Edit "' .. key .. '"', picker, Picker.onPresetEdit, key)
        menu:addOption('Delete "' .. key .. '"', picker, Picker.onPresetDelete, key)
    end
    menu:addOption("New preset from current selection...", picker, Picker.onPresetNew)
    -- controller: hand the menu joypad focus; B returns to the picker (menu.origin). Mirror vanilla's
    -- open sequence (ISInventoryPage): set origin + mouseOver=1 (so the first option is highlighted and
    -- ISContextMenu:onJoypadDown's `self.mouseOver > 0` never indexes nil), then setJoypadFocus (which
    -- keeps the prevfocus chain, unlike assigning joypadData.focus directly).
    if picker.grabbedJoypad then
        menu.origin = picker
        menu.mouseOver = 1
        setJoypadFocus(picker.playerNum, menu)
    end
    return menu
end

-- New: name-prompt, then save the CURRENT MANUAL selection (Categories + Items) as a fresh preset.
-- Captures manual ticks only -- presets don't nest, so ticked presets aren't rolled in.
function Picker:onPresetNew()
    local modal = ISTextBox:new(getCore():getScreenWidth() / 2 - 150, getCore():getScreenHeight() / 2 - 90,
        300, 180, "Name this preset (saves your current Categories + Items selection):", "", nil,
        Picker.onPresetNamed, self.playerNum)
    modal.target = self
    modal:initialise()
    self:openModal(modal)
end
function Picker.onPresetNamed(target, button)
    local refused = false
    if button.internal == "OK" then
        local name = button.parent.entry:getText()
        if name and name ~= "" then
            LootSorter.putPreset(TagPicker.presetArgs(target, { name = name, cats = target.selectedCats,
                items = target.selectedItems, expectExisting = false }),
                function(verdict, detail)
                    if verdict and verdict ~= "ok" then
                        LootSorter.notifyPresetFailure(name, verdict, (detail and detail.action) or "save")
                        refused = true
                    end
                    target.needRebuild = true
                end)
        end
    end
    -- A refusal put an error modal up; taking the pad back would leave it undismissable.
    if not refused then target:restoreModalFocus() end
end

-- Edit: open the preset editor on the chosen preset (edits its OWN cats/items, not this box's).
function Picker.onPresetEdit(picker, name)
    if name then LootSorter.openPresetEditor(name, picker.playerNum, picker) end
end

-- Delete: confirm first (it's destructive and affects every box that uses the preset), then remove it
-- from the store and drop it from this box's usage.
function Picker.onPresetDelete(picker, name)
    if not name then return end
    -- read now, not on confirm: the point is what the user was looking at when they chose to delete.
    -- A row can outlive its preset by a frame, and confirming with no generation deletes by name --
    -- which would destroy a preset that reused the name in between.
    local preset = LootSorter.getPresetStore()[name]
    if not preset then picker.needRebuild = true; return end
    local modal = ISModalDialog:new(getCore():getScreenWidth() / 2 - 175, getCore():getScreenHeight() / 2 - 75,
        350, 150, 'Delete preset "' .. name .. '"?\nAny box using it will stop using it.', true, picker,
        Picker.onPresetDeleteConfirm, picker.playerNum, name, preset and preset.gen)
    modal:initialise()
    picker:openModal(modal)
end
function Picker.onPresetDeleteConfirm(target, button, name, baseGen)
    local refusedAlready = false
    if button.internal == "YES" and name then
        LootSorter.removePreset({ name = name, baseGen = baseGen },
            function(verdict, detail)
                -- nil means the server never answered with a verdict; say nothing rather than
                -- blame a conflict that may not have happened.
                if verdict and verdict ~= "ok" then
                    LootSorter.notifyPresetFailure(name, verdict, (detail and detail.action) or "delete")
                end
                -- Only drop the link once the delete is known to have happened. A refusal means the
                -- preset is still there and the link still right; a link left behind is inert anyway.
                if verdict == "ok" then target.selectedPresets[name] = nil end
                target.needRebuild = true
                refusedAlready = verdict ~= "ok"
            end
        )
    end
    -- Single-player answered inside that call, so a refusal has already put a modal up and taking the
    -- pad back would leave it undismissable. Multiplayer has not answered yet, so restore now; if the
    -- refusal arrives later its modal claims focus itself.
    if not refusedAlready then target:restoreModalFocus() end
end

-- hand controller focus to a modal (name prompt) and remember to give it back; a no-op for mouse users
function Picker:openModal(modal)
    modal:addToUIManager()
    if self.grabbedJoypad then setJoypadFocus(self.playerNum, modal) end
end
function Picker:restoreModalFocus()
    if self.grabbedJoypad then setJoypadFocus(self.playerNum, self) end
end

-- switch Categories <-> Items: stash the current mode's filter + checkbox states, restore the target's
function Picker:setMode(target)
    if self.mode == target then return end
    local st = self._modeState[self.mode]
    st.onlyChecked = self.onlyChecked
    st.onlyContents = self.onlyContents
    st.filterText = self.filter:getInternalText() or ""

    self.mode = target
    if target == "items" then self.selection = self.selectedItems
    elseif target == "presets" then self.selection = self.selectedPresets
    else self.selection = self.selectedCats end

    local ns = self._modeState[target]
    self.onlyChecked = ns.onlyChecked or false
    self.onlyContents = ns.onlyContents or false
    self.filter:setText(ns.filterText or "")
    self.lastFilter = nil
    self.needRebuild = true
    self:layout()
    -- rebuild controller nav: the checkbox row differs by mode ("Only Contents" is hidden for presets),
    -- so the d-pad rows must match the now-visible controls. Cheap; only on an explicit mode switch.
    if self.joypadConfigured and getJoypadData(self.playerNum) then self:configJoypad() end
end
function Picker:onModeCat()    self:setMode("cats") end
function Picker:onModeItem()   self:setMode("items") end
function Picker:onModePreset() self:setMode("presets") end

-- LB/RB step through the mode tabs (Categories / Items / Presets; the preset editor has only two).
-- Clamps at the ends -- no wrap-around.
function Picker:cycleMode(direction)
    local order = (self.targetKind == "preset") and { "cats", "items" } or { "cats", "items", "presets" }
    local index = 1
    for i, m in ipairs(order) do if m == self.mode then index = i; break end end
    index = index + direction
    if index < 1 or index > #order then return end   -- clamp: don't loop around
    self:setMode(order[index])
end

-- Build the controller focus rows. Deferred (configJoypadLater) so children are laid out first and
-- only when a gamepad is present. Mirrors the Manifest window / vanilla ISButcherHookUI.
function Picker:configJoypad()
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
    if self.appearanceName then
        self:insertNewLineOfButtons(self.appearanceName)
        self:insertNewLineOfButtons(self.appearanceIcon, self.appearanceColor, self.appearanceReset)
    end
    self:insertNewLineOfButtons(self.filter)                            -- filter (A = keyboard)
    if self.targetKind == "preset" then
        self:insertNewLineOfButtons(self.btnModeCat, self.btnModeItem)  -- preset editor: 2 modes only
    else
        self:insertNewLineOfButtons(self.btnModeCat, self.btnModeItem, self.btnModePreset)  -- mode row
    end
    -- filter row, plus the priority controls when there is a box to prioritise. The entry is included
    -- so a controller can reach it: A opens the on-screen keyboard, as it does for the filter above.
    local filterRow = { self.chkChecked }
    if self.mode ~= "presets" then filterRow[#filterRow + 1] = self.chkContents end
    if self.targetKind ~= "preset" then
        filterRow[#filterRow + 1] = self.btnPriorityDown
        filterRow[#filterRow + 1] = self.btnPriorityUp
        filterRow[#filterRow + 1] = self.priorityEntry
    end
    self:insertNewLineOfButtons(unpack(filterRow))
    if self.targetKind ~= "preset" then self:insertNewLineOfButtons(self.chkNoDuplicates) end
    if Tags.enabled() and self.mode == "cats" then
        self:insertNewLineOfButtons(self.toolkitTagSwitch)
        self:insertNewLineOfButtons(self.toolkitTagRuleButton)
    end
    self:insertNewLineOfButtons(self.listbox)                           -- the list (A = toggle, Y = preset menu)
    self:insertNewLineOfButtons(self.btnAll, self.btnClear, self.btnSave)  -- action row (uniform)
    self.joypadIndexY = self:getMinVisibleRow()
    self:restoreJoypadFocus(joypadData)
end

function Picker:onGainJoypadFocus(joypadData)
    ISCollapsableWindowJoypad.onGainJoypadFocus(self, joypadData)
    -- build the focus rows once; re-running on every focus return (e.g. exiting the list) would leak
    -- into allJoypadButtons and reset the cursor to the top row
    if not self.joypadConfigured then self.configJoypadLater = true end
end

-- B cancels (closes without saving); other buttons fall through to the base navigation.
function Picker:onJoypadDown(button, joypadData)
    if button == Joypad.BButton then
        self:closePicker()
        return
    end
    if button == Joypad.LBumper then self:cycleMode(-1); return end
    if button == Joypad.RBumper then self:cycleMode(1); return end
    ISCollapsableWindowJoypad.onJoypadDown(self, button, joypadData)
end

function Picker:closePicker()
    self.toolkitTagClosed = true
    AppearanceControls.close(self)
    -- Restore joypad focus to whatever had it before we opened (the inventory/loot window), NOT nil.
    -- Handing focus to nil leaves the controller focused on nothing, so the still-open inventory goes
    -- dead until you reopen something -- the reported "menu glitches out" bug.
    local restore = self.grabbedJoypad and self.prevFocus or nil
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if self.grabbedJoypad then setJoypadFocus(self.playerNum, restore); self.grabbedJoypad = false end
    if self.targetKind == "preset" then
        LootSorter._presetEditor = nil
        if self.returnTo then
            if self.returnTo.dimmer then self.returnTo.dimmer:setVisible(false) end   -- un-dim the box picker
            self.returnTo.needRebuild = true                                          -- reflect the edit
        end
    else
        LootSorter._picker = nil
    end
end
-- IMPORTANT: the title-bar X button calls self:close(); route it through closePicker so it releases
-- joypad focus (otherwise a controller is left focused on the hidden window and input freezes).
Picker.close = Picker.closePicker

-- A refused preset write, told to the player. The dialog has no error styling, so the words carry it,
-- and name the mod: an unattributed modal is a mystery to anyone running a pile of them.
local function describe(action, name, outcome)
    if outcome == "deleted" then
        return "Quartermaster: couldn't " .. action .. " '" .. name .. "' - it was deleted by someone else."
    elseif outcome == "nameTaken" then
        return "Quartermaster: couldn't save - a preset called '" .. name .. "' already exists."
    end
    return "Quartermaster: couldn't " .. action .. " '" .. name
        .. "' - someone else changed it while you had it open."
end

function LootSorter.notifyPresetFailure(name, outcome, action)
    local player = getSpecificPlayer(0)
    if not player then return end
    local text = describe(action or "save", name, outcome)
    -- A modal, not halo text: the user has just lost work they typed in, and halo text draws in the
    -- world layer, so an open picker hides the one message they need to see.
    local shown = pcall(function()
        -- One at a time. Stacked dialogs each stash the focus they saw, so dismissing them out of
        -- order restores focus to a destroyed element -- which strands a pad exactly as nil does.
        -- `removed` is set by removeFromUIManager, so it distinguishes one the user already
        -- dismissed: destroying that again would reset their game speed for no reason.
        local previous = LootSorter._failureDialog
        LootSorter._failureDialog = nil
        if previous and not previous.removed then
            pcall(function() previous:destroy() end)
        end
        local width, height = 380, 140
        local dialog = ISModalDialog:new(getCore():getScreenWidth() / 2 - width / 2,
            getCore():getScreenHeight() / 2 - height / 2, width, height, text, false)
        dialog:initialise()
        dialog:addToUIManager()
        -- After addToUIManager, never before: the java object it forwards to is created there.
        dialog:setAlwaysOnTop(true)
        LootSorter._failureDialog = dialog
        -- Without focus a pad can't dismiss it; without prevFocus, ISModalDialog:destroy() hands
        -- focus to nil and strands whatever had it. It never sets prevFocus itself.
        -- The live focus is often already nil here -- ISTextBox clears it before calling us back, and
        -- ISModalDialog does the same -- so fall back to the window we came from.
        if player:getJoypadBind() ~= -1 then
            local playerNum = player:getPlayerNum()
            local joypadData = getJoypadData(playerNum)
            dialog.prevFocus = (joypadData and joypadData.focus)
                or LootSorter._presetEditor or LootSorter._picker
            setJoypadFocus(playerNum, dialog)
        end
    end)
    if not shown then LootSorter.notify(player, text) end
    LootSorter.DBG("preset write failed: " .. tostring(name) .. " -> " .. tostring(outcome))
end

function Picker:onSave()
    if self.targetKind == "preset" then
        -- Editing a preset's definition: write its cats/items back to the store. Because presets are
        -- linked, this propagates to every box that uses this preset on the next sort/read.
        --
        -- Close from INSIDE the callback, never after it. The callback runs during the call where we
        -- are authoritative and a frame later where we are not, so closing here would close before
        -- the verdict arrives in multiplayer -- taking the user's selection with it, which is the one
        -- thing they cannot get back after a refusal.
        LootSorter.putPreset(TagPicker.presetArgs(self, { name = self.presetName, cats = self.selectedCats,
            items = self.selectedItems, expectExisting = true,
            baseRev = self.presetRev, baseGen = self.presetGen }),
            function(verdict, detail)
                if verdict and verdict ~= "ok" then
                    LootSorter.notifyPresetFailure(self.presetName, verdict,
                        (detail and detail.action) or "save")
                    return                          -- leave the editor open behind the modal
                end
                -- nil verdict means no answer ever came; the write may or may not have landed, so
                -- treat it as done rather than trapping the user in an editor that cannot close.
                self:closePicker()
            end)
        return
    end
    if self.toolkitTagSaving then return end
    self:resolvePresetSelection()
    local obj, ci = self.targetObj, self.targetCI
    local snapshot = LootSorter.snapshotDesignation({cats = self.selectedCats, items = self.selectedItems,
        presets = self.selectedPresets, priority = self.priority, noDuplicates = self.noDuplicates,
        pzstTagRule = self.toolkitTagRule})
    snapshot.appearance = AppearanceControls.value(self)
    self.toolkitTagSaving = true
    TagRules.saveBox(obj, ci, snapshot.pzstTagRule, getSpecificPlayer(self.playerNum or 0),
        function(verdict, revision)
            self.toolkitTagSaving = false
            if self.toolkitTagClosed or LootSorter._picker ~= self or self.targetObj ~= obj
                or self.targetCI ~= ci then return end
            if verdict == "ok" then
                self.selectedCats, self.selectedItems, self.selectedPresets = snapshot.cats, snapshot.items, snapshot.presets
                self.selection = self.mode == "items" and self.selectedItems
                    or self.mode == "presets" and self.selectedPresets or self.selectedCats
                self.priority, self.toolkitTagRule, self.toolkitTagRuleRevision = snapshot.priority, snapshot.pzstTagRule, revision
                self.noDuplicates = snapshot.noDuplicates
                self:closePicker()
            elseif LootSorter.notify then
                LootSorter.notify(getSpecificPlayer(self.playerNum or 0), getText(verdict == "stale"
                    and "UI_PZST_QMTagRuleStale" or "UI_PZST_QMTagRuleFailed", tostring(verdict)))
            end
        end, self.toolkitTagRuleRevision, snapshot)
end

function Picker:new(x, y, w, h)
    local o = ISCollapsableWindowJoypad:new(x, y, w, h)
    setmetatable(o, self); self.__index = self
    o.selectedCats = {}
    o.selectedItems = {}
    o.selectedPresets = {}
    o.mode = "cats"
    o.toolkitTagView = true
    o.selection = o.selectedCats
    o.targetKind = "box"
    o.onlyChecked = false
    o.priority = 0
    o.noDuplicates = false
    o.onlyContents = false
    o._modeState = { cats = {}, items = {}, presets = {} }
    o.title = getText("UI_PZST_ConfigureContainer")
    o.background, o.backgroundColor = true, {r = 0.04, g = 0.04, b = 0.04, a = 1}
    o.resizable = true
    o.minimumWidth = 420
    o.minimumHeight = 600
    return o
end

-- entry point called from the context menu
function LootSorter.openPicker(obj, ci, playerNum)
    LootSorter._cats, LootSorter._catItems = nil, nil
    if LootSorter._presetEditor then LootSorter._presetEditor:closePicker() end   -- don't orphan an editor of the old picker
    if LootSorter._picker then
        LootSorter._picker:closePicker()
    end
    local w, h = WIN_W, WIN_H
    local p = Picker:new(getCore():getScreenWidth() / 2 - w / 2,
                         getCore():getScreenHeight() / 2 - h / 2, w, h)
    p.targetObj = obj
    p.targetCI = ci
    local curCats = LootSorter.getBoxCats(obj, ci)
    if curCats then for k, v in pairs(curCats) do if v then p.selectedCats[k] = true end end end
    local curItems = LootSorter.getBoxItems(obj, ci)
    if curItems then for k, v in pairs(curItems) do if v then p.selectedItems[k] = true end end end
    p.priority = LootSorter.getBoxPriority(obj, ci)
    p.noDuplicates = LootSorter.getBoxNoDuplicates(obj, ci)
    local curPresets = LootSorter.getBoxPresets(obj, ci)
    -- keep the stored value: it carries the generation the link was made against
    if curPresets then for k, v in pairs(curPresets) do if v then p.selectedPresets[k] = v end end end
    p.selection = p.selectedCats
    p.playerNum = playerNum or 0
    p:initialise(); p:addToUIManager()
    -- hand controller focus to the window only if a gamepad is bound (mouse/keyboard untouched)
    local pl = getSpecificPlayer(p.playerNum)
    if pl and pl:getJoypadBind() ~= -1 then
        local jd = getJoypadData(p.playerNum)          -- remember who had focus (the inventory) so
        p.prevFocus = jd and jd.focus or nil           -- closePicker can hand it back instead of nil
        setJoypadFocus(p.playerNum, p)
        p.grabbedJoypad = true
    end
    LootSorter._picker = p
end

-- brief bright-border flash on the editor to signal "finish here" when the modal backdrop is clicked
function Picker:nudge()
    self._nudgeFrames = 12
end

-- Open the preset EDITOR: the same Picker retargeted to a preset. It edits the preset's OWN cats/items
-- (Categories/Items modes only -- no nested Presets tab) and Save writes them back to the store, which
-- propagates to every box using this preset. While it's open the box picker is dimmed and click-blocked
-- via that picker's OWN `dimmer` overlay (only that window, never the whole screen); on close it hands
-- controller focus back to that picker (via prevFocus) and refreshes.
function LootSorter.openPresetEditor(name, playerNum, parent)
    if LootSorter._presetEditor then LootSorter._presetEditor:closePicker() end   -- clean up any prior editor + backdrop/focus
    local store = LootSorter.getPresetStore()
    local preset = store[name]
    if not preset then return end
    local w, h = WIN_W, WIN_H
    local editor = Picker:new(getCore():getScreenWidth() / 2 - w / 2 + 24,
                              getCore():getScreenHeight() / 2 - h / 2 + 24, w, h)
    editor.targetKind = "preset"
    editor.presetName = name
    editor.presetRev = preset.rev or 0        -- what we loaded; the server rejects a save against a newer one
    editor.presetGen = preset.gen             -- and against a different preset that reused the name
    editor.returnTo = parent
    editor.title = "Quartermaster - edit preset: " .. name
    if preset.cats then for k, v in pairs(preset.cats) do if v then editor.selectedCats[k] = true end end end
    if preset.items then for k, v in pairs(preset.items) do if v then editor.selectedItems[k] = true end end end
    editor.playerNum = playerNum or 0
    editor:initialise()
    editor:addToUIManager()
    -- dim + block just the BOX PICKER beneath (its own overlay), not the whole screen
    if parent and parent.dimmer then parent.dimmer:setVisible(true) end
    local pl = getSpecificPlayer(editor.playerNum)
    if pl and pl:getJoypadBind() ~= -1 then
        editor.prevFocus = parent                      -- return focus to the box picker on close (not a transient menu)
        setJoypadFocus(editor.playerNum, editor)
        editor.grabbedJoypad = true
    end
    LootSorter._presetEditor = editor
end

-- (Reload-safety: LootSorter.closeAllWindows() in LootSorter_Core.lua tears down this window and the
-- others on every reload, so nothing needs cleaning up here.)
