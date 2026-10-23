require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISButton"
require "ISUI/ISLabel"
local UIStyle = require "PZSurvivorToolkit/UIStyle"
local Picker = ISCollapsableWindowJoypad:derive("PZSTContainerIconPicker")
local function text(key) return getText("UI_PZST_Container" .. key) end

function Picker:reload()
    local query = (self.search:getInternalText() or ""):lower()
    self.list:clear()
    for _, entry in ipairs(self.entries) do
        if query == "" or entry.search:find(query, 1, true) then self.list:addItem(entry.label, entry) end
    end
    self.lastQuery = query
end

function Picker.drawRow(list, y, row)
    local h, entry = row.height, row.item
    if y + list:getYScroll() + h < 0 or y + list:getYScroll() >= list:getHeight() then return y + h end
    if list.selected == row.index then list:drawRect(0, y, list.width, h, 0.35, 0.3, 0.5, 0.7) end
    if entry.texture then list:drawTextureScaledAspect(entry.texture, 6, y + 3, h - 6, h - 6, 1, 1, 1, 1) end
    list:drawText(UIStyle.fit(entry.label, list.width - h - 28), h + 4, y + 5, 1, 1, 1, 1, UIFont.Small)
    return y + h
end

function Picker:choose()
    local row = self.list.items[self.list.selected]
    if row then self.onPick(row.item.icon); self:close() end
end

function Picker:clearIcon() self.onPick(nil); self:close() end

function Picker:close()
    self.search:unfocus()
    self:setVisible(false)
    self:removeFromUIManager()
    if self.owner and self.owner.toolkitIconPicker == self then
        self.owner.toolkitIconPicker = nil
        self.owner.dimmer:setVisible(false)
        self.owner.dimmer.onMouseDown = self.previousDimmerMouseDown
    end
    if self.grabbedJoypad then setJoypadFocus(self.playerNum, self.owner); self.grabbedJoypad = false end
end

function Picker:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    self.searchLabel = ISLabel:new(12, 0, 24, text("IconSearch"), 1, 1, 1, 1, UIFont.Small, true)
    self.searchLabel:initialise(); self.searchLabel:instantiate(); self:addChild(self.searchLabel)
    self.searchLabel:setY(28)
    self.search = ISTextEntryBox:new("", 12, 54, self.width - 24, 26)
    self.search:initialise(); self.search:instantiate(); self:addChild(self.search)
    self.search:setTooltip(text("IconSearch"))
    self.search.backgroundColor = {r = 0.08, g = 0.10, b = 0.13, a = 1}
    self.search.borderColor = {r = 0.5, g = 0.65, b = 0.8, a = 1}
    self.list = ISScrollingListBox:new(12, 86, self.width - 24, self.height - 134)
    self.list:initialise(); self.list:instantiate(); self.list.itemheight = 30
    self.list.font = UIFont.Small
    self.list.joypadParent = self
    self.list.doDrawItem = Picker.drawRow
    self.list:setOnMouseDoubleClick(self, Picker.choose)
    self:addChild(self.list)
    local bw = (self.width - 40) / 3
    local function button(x, label, callback)
        local b = ISButton:new(x, self.height - 36, bw, 26, label, self, callback)
        b:initialise(); b:instantiate(); self:addChild(b); return b
    end
    self.defaultButton = button(12, text("Default"), Picker.clearIcon)
    self.cancelButton = button(20 + bw, getText("UI_Cancel"), Picker.close)
    self.selectButton = button(28 + bw * 2, text("SelectIcon"), Picker.choose)
    self:reload()
end

function Picker:prerender()
    if self.owner.toolkitTagClosed then self:close(); return end
    if self.reassertTop then self.reassertTop = false; self:bringToTop() end
    if (self.search:getInternalText() or ""):lower() ~= self.lastQuery then self:reload() end
    ISCollapsableWindowJoypad.prerender(self)
end

function Picker:onGainJoypadFocus(data)
    ISCollapsableWindowJoypad.onGainJoypadFocus(self, data)
    if self.joypadConfigured then return end
    self.joypadConfigured = true
    self:insertNewLineOfButtons(self.search)
    self:insertNewLineOfButtons(self.list)
    self:insertNewLineOfButtons(self.defaultButton, self.cancelButton, self.selectButton)
    self.joypadIndexY, self.joypadIndex = 1, 1
    self:restoreJoypadFocus(data)
end

function Picker:onJoypadDown(key, data)
    if key == Joypad.BButton then self:close(); return end
    ISCollapsableWindowJoypad.onJoypadDown(self, key, data)
end

function Picker.open(owner, onPick)
    if owner.toolkitIconPicker then owner.toolkitIconPicker:close() end
    local catalogue = require("BetterContainers/Customize/ui/IconCatalogue").getCatalogue()
    local entries, byTexture, withoutTexture = {}, {}, {}
    -- Consume BC's cached catalogue without changing its expansion/selection state.
    local function add(entry)
        if not entry.icon then return end
        local key = entry.icon.kind .. "|" .. entry.icon.value
        -- BC children share their group's actual texture. Descriptor and item names
        -- differ even when the displayed image is identical; other textures remain choices.
        local representative
        if entry.tex then representative = byTexture[entry.tex] else representative = withoutTexture[key] end
        if not representative then
            representative = {icon = {kind = entry.icon.kind, value = entry.icon.value},
                label = entry.label or entry.name or entry.icon.value, texture = entry.tex, search = ""}
            entries[#entries + 1] = representative
            if entry.tex then byTexture[entry.tex] = representative else withoutTexture[key] = representative end
        end
        -- Search every collapsed alias while leaving BC's cached catalogue untouched.
        local terms = {entry.searchText or "", entry.label or "", entry.name or "", entry.icon.value}
        for _, alias in ipairs(entry._aliasList or {}) do terms[#terms + 1] = alias end
        representative.search = representative.search .. "\n" .. table.concat(terms, "\n"):lower()
    end
    for _, group in ipairs(catalogue.groupsSorted or {}) do
        add(group)
        for _, child in ipairs(group.children or {}) do add(child) end
    end
    local w, h = 440, math.min(530, getCore():getScreenHeight() - 40)
    local picker = Picker:new((getCore():getScreenWidth() - w) / 2, (getCore():getScreenHeight() - h) / 2, w, h)
    picker.owner, picker.onPick, picker.entries = owner, onPick, entries
    picker.playerNum, picker.title, picker.resizable = owner.playerNum or 0, text("SelectIcon"), false
    picker.background, picker.backgroundColor = true, {r = 0.04, g = 0.04, b = 0.04, a = 1}
    picker:initialise(); picker:addToUIManager()
    owner.toolkitIconPicker = picker
    picker.previousDimmerMouseDown = owner.dimmer.onMouseDown
    owner.dimmer:setVisible(true)
    owner.dimmer.onMouseDown = function() picker.reassertTop = true; return true end
    local player = getSpecificPlayer(picker.playerNum)
    if player and player:getJoypadBind() ~= -1 then
        picker.grabbedJoypad = true
        setJoypadFocus(picker.playerNum, picker)
    end
    return picker
end

return Picker
