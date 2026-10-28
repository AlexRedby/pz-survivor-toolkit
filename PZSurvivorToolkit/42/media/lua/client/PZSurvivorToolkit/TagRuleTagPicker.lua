require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISScrollingListBox"
require "ISUI/ISComboBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISButton"
local Tags = require "PZSurvivorToolkit/ItemTags"
local Visuals = require "PZSurvivorToolkit/TagVisuals"
local UIStyle = require "PZSurvivorToolkit/UIStyle"
local Choice = ISCollapsableWindowJoypad:derive("PZSTTagRuleTagPicker")
local function text(key) return getText("UI_PZST_TagRule" .. key) end

-- Both lists keep navigation separate from activation; moving the cursor never edits a rule.
function Choice.configureList(list, owner, activate)
    list.joypadParent = owner
    list.setJoypadFocused = function(self, focused) self.joypadFocused = focused end
    list.onJoypadDownInParent = function(self, key, data)
        if key ~= Joypad.AButton then return false end
        data.focus = self; updateJoypadFocus(data)
        if (self.selected or 0) < 1 then self.selected = 1 end
        return true
    end
    list.onJoypadDirUp = function(self)
        self.selected = self:prevVisibleIndex(self.selected)
        if self.selected <= 0 then self.selected = self:prevVisibleIndex(self.count + 1) end
        self:ensureVisible(self.selected)
    end
    list.onJoypadDirDown = function(self)
        self.selected = self:nextVisibleIndex(self.selected)
        if self.selected == -1 then self.selected = self:nextVisibleIndex(0) end
        self:ensureVisible(self.selected)
    end
    list.onJoypadDown = function(self, key, data)
        if key == Joypad.AButton then
            local row = self.items[self.selected]
            if row then activate(owner, row.item) end
        elseif key == Joypad.BButton then
            data.focus = owner; updateJoypadFocus(data)
        else ISScrollingListBox.onJoypadDown(self, key, data) end
    end
end

function Choice:reload()
    self.list:clear()
    local query = self.search:getInternalText():lower()
    local family = self.group:getOptionData(self.group.selected)
    for _, entry in ipairs(self.entries) do
        if (not family or entry.families[family]) and entry.search:find(query, 1, true) then
            self.list:addItem(entry.label, entry, entry.label)
        end
    end
    self.lastQuery, self.lastGroup = query, self.group.selected
end

function Choice.drawRow(list, y, item)
    local h = item.height
    local scroll = list:getYScroll()
    if y + scroll + h < 0 or y + scroll >= list:getHeight() then return y + h end
    if list.selected == item.index then list:drawRect(0, y, list.width, h, 0.35, 0.3, 0.5, 0.7) end
    local entry, x = item.item, 8
    local style = Visuals.get(entry.id)
    if style.texture then
        list:drawTextureScaledAspect(style.texture, x, y + 4, h - 8, h - 8, 1, style.r, style.g, style.b)
    end
    x = x + h
    list:drawText(UIStyle.fit(entry.label, list.width - x - 20), x, y + 5, 1, 1, 1, 1, UIFont.Small)
    return y + h
end

function Choice:choose(entry)
    if not entry or not entry.id then
        local row = self.list.items[self.list.selected]
        entry = row and row.item
    end
    if not entry or not self.owner:getIsVisible() then return end
    self:close()
    self.onPick(entry.id)
end

function Choice:close()
    self.search:unfocus()
    if self.group.expanded and self.group.popup and self.group.popup.parentCombo == self.group then
        self.group:hidePopup(); self.group.expanded = false
    end
    if self.list.tooltipUI then self.list.tooltipUI:setVisible(false); self.list.tooltipUI:removeFromUIManager() end
    self:setVisible(false); self:removeFromUIManager()
    if self.owner.tagChoice == self then
        self.owner.tagChoice = nil
        self.owner.dimmer:setVisible(false)
    end
    if self.grabbedJoypad then setJoypadFocus(self.playerNum, self.owner); self.grabbedJoypad = false end
end

function Choice:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    local fontHeight = getTextManager():getFontHeight(UIFont.Small)
    local controlHeight = math.max(26, fontHeight + 8)
    self.searchLabelY = math.max(32, self:titleBarHeight() + 8)
    local searchY = self.searchLabelY + fontHeight + 8
    local groupY = searchY + controlHeight + 8
    local listY = groupY + controlHeight + 10
    local footerY = self.height - controlHeight - 10
    self.search = ISTextEntryBox:new("", 12, searchY, self.width - 24, controlHeight)
    self.search:setFont(UIFont.Small)
    self.search:initialise(); self.search:instantiate(); self:addChild(self.search)
    self.group = ISComboBox:new(12, groupY, self.width - 24, controlHeight)
    self.group:initialise(); self.group:instantiate()
    self.group:addOptionWithData(text("AllGroups"), false)
    for _, family in ipairs(self.families) do self.group:addOptionWithData(Tags.label(family), family) end
    self:addChild(self.group)
    self.list = ISScrollingListBox:new(12, listY, self.width - 24, math.max(40, footerY - listY - 8))
    self.list:initialise(); self.list:instantiate()
    self.list.itemheight = getTextManager():getFontHeight(UIFont.Small) + 12
    self.list.doDrawItem = Choice.drawRow
    self.list:setOnMouseDownFunction(self, Choice.choose)
    Choice.configureList(self.list, self, Choice.choose)
    self:addChild(self.list)
    local width = (self.width - 36) / 2
    local function button(x, title, callback)
        local b = ISButton:new(x, footerY, width, controlHeight, title, self, callback)
        b:initialise(); b:instantiate(); UIStyle.button(b); self:addChild(b); return b
    end
    self.cancelButton = button(12, text("Cancel"), Choice.close)
    self.selectButton = button(24 + width, text("Select"), Choice.choose)
    self:reload()
end

function Choice:prerender()
    if not Tags.enabled() or not self.owner:getIsVisible() then self:close(); return end
    if self.reassertTop then self.reassertTop = false; self:bringToTop() end
    local revision = Tags.revision and Tags.revision() or 0
    if self.tagRevision ~= revision then
        local family = self.group:getOptionData(self.group.selected)
        self.entries, self.families = self.owner:catalogEntries()
        self.group:clear(); self.group:addOptionWithData(text("AllGroups"), false); self.group.selected = 1
        for _, id in ipairs(self.families) do
            self.group:addOptionWithData(Tags.label(id), id)
            if id == family then self.group.selected = #self.group.options end
        end
        self.tagRevision = revision
        self:reload()
    end
    if self.search:getInternalText():lower() ~= self.lastQuery or self.group.selected ~= self.lastGroup then self:reload() end
    ISCollapsableWindowJoypad.prerender(self)
    self:drawText(text("Search"), 12, self.searchLabelY, 0.9, 0.9, 0.9, 1, UIFont.Small)
end

function Choice:onGainJoypadFocus(data)
    ISCollapsableWindowJoypad.onGainJoypadFocus(self, data)
    if self.joypadConfigured then return end
    self.joypadConfigured = true
    self:insertNewLineOfButtons(self.search)
    self:insertNewLineOfButtons(self.group)
    self:insertNewLineOfButtons(self.list)
    self:insertNewLineOfButtons(self.cancelButton, self.selectButton)
    self.joypadIndexY, self.joypadIndex = 1, 1
    self:restoreJoypadFocus(data)
end

function Choice:onJoypadDown(key, data)
    if key == Joypad.BButton and not self.group.expanded then self:close(); return end
    ISCollapsableWindowJoypad.onJoypadDown(self, key, data)
end

function Choice.open(owner, entries, families, onPick)
    if owner.tagChoice then owner.tagChoice:close() end
    local w = math.min(440, getCore():getScreenWidth() - 24)
    local h = math.min(500, getCore():getScreenHeight() - 24)
    local choice = Choice:new((getCore():getScreenWidth() - w) / 2, (getCore():getScreenHeight() - h) / 2, w, h)
    choice.owner, choice.entries, choice.families, choice.onPick = owner, entries, families, onPick
    choice.title, choice.resizable, choice.playerNum = text("Select"), false, owner.playerNum
    choice.background, choice.backgroundColor = true, {r=0.04,g=0.04,b=0.04,a=1}
    choice:initialise(); choice:instantiate(); choice:addToUIManager()
    choice:bringToTop()
    choice.reassertTop = true
    choice.tagRevision = Tags.revision and Tags.revision() or 0
    owner.tagChoice = choice; owner.dimmer:setVisible(true)
    local joypad = choice.playerNum and JoypadState and JoypadState.players[choice.playerNum + 1]
    if joypad and setJoypadFocus then choice.grabbedJoypad = true; setJoypadFocus(choice.playerNum, choice) end
    return choice
end

return Choice
