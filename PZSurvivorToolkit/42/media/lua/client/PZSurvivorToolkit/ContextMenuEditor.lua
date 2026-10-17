require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISComboBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISButton"
local Organizer = require "PZSurvivorToolkit/ContextMenus"
local UIStyle = require "PZSurvivorToolkit/UIStyle"
local Editor = ISCollapsableWindow:derive("PZSurvivorToolkitContextMenuEditor")
local instance
local utf8Strings = #"é" > 1

local function text(id)
    return getText("UI_PZSurvivorToolkit_context_" .. id)
end

local function selected(list)
    local row = list.items[list.selected]
    return row and row.item
end

local function choose(combo, value)
    for index = 1, #combo.options do
        if combo:getOptionData(index) == value then combo.selected = index; return end
    end
    combo.selected = 1
end

local function fit(label, width)
    local manager = getTextManager()
    if manager:MeasureStringX(UIFont.Small, label) <= width then return label end
    -- Kahlua indexes UTF-16 characters; Lua test runtimes index UTF-8 bytes.
    while #label > 0 and manager:MeasureStringX(UIFont.Small, label .. "...") > width do
        local last = #label
        if utf8Strings then
            while last > 1 and label:byte(last) >= 128 and label:byte(last) <= 191 do last = last - 1 end
        elseif last > 1 and label:byte(last) >= 56320 and label:byte(last) <= 57343 then last = last - 1 end
        label = label:sub(1, last - 1)
    end
    return label .. "..."
end

function Editor:createChildren()
    ISCollapsableWindow.createChildren(self)
    local width, height = self.width, self.height
    local column = math.floor((width - 36) / 2)
    self.rightX = column + 24
    self.scopeID, self.parentID = Organizer.lastItemType or "*", "root"
    local function add(control)
        control:initialise(); control:instantiate(); self:addChild(control)
        return control
    end
    local function button(x, y, w, id, callback)
        local control = add(ISButton:new(x, y, w, 28, text(id), self, callback))
        UIStyle.button(control)
        return control
    end
    self.scope = add(ISComboBox:new(12, 54, width - 24, 28, self, Editor.changeScope))
    self.search = add(ISTextEntryBox:new("", 12, 108, column, 28))
    self.search:setTooltip(text("search"))
    self.parent = add(ISComboBox:new(self.rightX, 108, column, 28, self, Editor.changeParent))
    self.list = add(ISScrollingListBox:new(12, 144, column, height - 304))
    self.orderList = add(ISScrollingListBox:new(self.rightX, 144, column, height - 414))
    local fontHeight = getTextManager():getFontHeight(UIFont.Small)
    self.list.itemheight = fontHeight * 2 + 12
    self.list.doDrawItem = function(list, y, row)
        if list.selected == row.index then list:drawRect(0, y, list.width, list.itemheight, 0.4, 0.2, 0.35, 0.6) end
        list:drawText(fit(row.item.label, list.width - 28), 8, y + 5, 1, 1, 1, 1, UIFont.Small)
        local label = Organizer.groupName(row.item.category or "root", self.scopeID)
        list:drawText(fit(label, list.width - 28), 8, y + 6 + fontHeight, 0.7, 0.8, 0.9, 1, UIFont.Small)
        return y + list.itemheight
    end
    self.list:setOnMouseDownFunction(self, Editor.selectEntry)
    self.orderList.itemheight = fontHeight + 12
    self.orderList.doDrawItem = function(list, y, row)
        if list.selected == row.index then list:drawRect(0, y, list.width, list.itemheight, 0.4, 0.2, 0.35, 0.6) end
        local label = row.item.kind == "group" and text("group_prefix") .. row.item.label or row.item.label
        list:drawText(fit(label, list.width - 28), 8, y + 5, 1, 1, 1, 1, UIFont.Small)
        return y + list.itemheight
    end
    self.orderList:setOnMouseDownFunction(self, Editor.selectOrderEntry)
    local half = math.floor((column - 8) / 2)
    self.upButton = button(self.rightX, height - 262, half, "up", Editor.moveUp)
    self.downButton = button(self.rightX + half + 8, height - 262, column - half - 8, "down", Editor.moveDown)
    self.groupName = add(ISTextEntryBox:new("", self.rightX, height - 202, column, 28))
    self.groupName:setTooltip(text("group_name_tip"))
    local third = math.floor((column - 16) / 3)
    self.createButton = button(self.rightX, height - 166, third, "create", Editor.createGroup)
    self.renameButton = button(self.rightX + third + 8, height - 166, third, "rename", Editor.renameGroup)
    self.deleteButton = button(self.rightX + (third + 8) * 2, height - 166, column - (third + 8) * 2, "delete", Editor.deleteGroup)
    self.deleteButton:setTooltip(text("delete_tip"))
    self.destination = add(ISComboBox:new(12, height - 136, column, 28))
    self.applyButton = button(12, height - 100, column, "apply", Editor.applyEntry)
    local resetWidth = math.floor((width - 150) / 2)
    self.resetButton = button(12, height - 44, resetWidth, "reset_scope", Editor.resetScope)
    self.resetAllButton = button(20 + resetWidth, height - 44, resetWidth, "reset", Editor.resetRules)
    self.resetAllButton:setTooltip(text("reset_tip"))
    local close = add(ISButton:new(width - 122, height - 44, 110, 28, getText("UI_btn_close"), self, Editor.close))
    UIStyle.button(close)
    self:reload()
end

function Editor:reload()
    local entry, orderEntry = selected(self.list), selected(self.orderList)
    self.scope:clear()
    self.scope:addOptionWithData(text("scope_all"), "*")
    local items = {}
    for fullType, name in pairs(Organizer.items) do items[#items + 1] = {id=fullType, name=name} end
    table.sort(items, function(a, b) return a.name < b.name or a.name == b.name and a.id < b.id end)
    for _, item in ipairs(items) do self.scope:addOptionWithData(item.name, item.id) end
    self.scope:setToolTipMap({defaultTooltip = text("scope_tip")})
    choose(self.scope, self.scopeID)
    self.scopeID = self.scope:getOptionData(self.scope.selected)
    self.parent:clear()
    self.parent:addOptionWithData(text("order_root"), "root")
    self.destination:clear()
    self.destination:addOptionWithData(text("auto"), false)
    for _, id in ipairs({"root", "hidden"}) do self.destination:addOptionWithData(Organizer.groupName(id, self.scopeID), id) end
    for _, id in ipairs(Organizer.groupIds(self.scopeID)) do
        local name = Organizer.groupName(id, self.scopeID)
        self.parent:addOptionWithData(name, id)
        self.destination:addOptionWithData(name, id)
    end
    self.parent:setToolTipMap({defaultTooltip = text("order_tip")})
    choose(self.parent, self.parentID)
    self.parentID = self.parent:getOptionData(self.parent.selected)
    self.list:clear()
    self.list.selected = 0
    local query, entries = self.search:getText():lower(), {}
    for _, value in ipairs(Organizer.getEntries(self.scopeID)) do
        if value.label:lower():find(query, 1, true) then entries[#entries + 1] = value end
    end
    table.sort(entries, function(a, b) return a.label < b.label or a.label == b.label and a.key < b.key end)
    for _, value in ipairs(entries) do
        self.list:addItem(value.label, value)
        if entry and value.key == entry.key then self.list.selected = #self.list.items end
    end
    self.orderList:clear()
    self.orderList.selected = 0
    for _, value in ipairs(Organizer.getLayout(self.scopeID, self.parentID)) do
        self.orderList:addItem(value.label, value)
        if orderEntry and value.key == orderEntry.key then self.orderList.selected = #self.orderList.items end
    end
    self.lastQuery, self.lastRevision = query, Organizer.revision
    if selected(self.list) then self:selectEntry(selected(self.list)) end
    self:updateButtons()
end

function Editor:changeScope()
    self.scopeID = self.scope:getOptionData(self.scope.selected)
    self.status = nil
    self:reload()
    self:selectOrderEntry()
end

function Editor:changeParent()
    self.parentID = self.parent:getOptionData(self.parent.selected)
    self.orderList:clear()
    self.status = nil
    self:reload()
    self:selectOrderEntry()
end

function Editor:selectEntry(entry)
    choose(self.destination, Organizer.getOverride(entry.key, self.scopeID) or false)
end

function Editor:selectedGroup()
    local entry = selected(self.orderList)
    if entry and entry.kind == "group" then return entry.key:sub(7) end
    if self.parentID ~= "root" then return self.parentID end
end

function Editor:selectOrderEntry()
    local id = self:selectedGroup()
    self.groupName:setText(id and Organizer.groupName(id, self.scopeID) or "")
    self:updateButtons()
end

function Editor:updateButtons()
    local row, id = selected(self.orderList), self:selectedGroup()
    local before = self.orderList.items[self.orderList.selected - 1]
    local after = self.orderList.items[self.orderList.selected + 1]
    self.applyButton:setEnable(selected(self.list) ~= nil)
    self.upButton:setEnable(row ~= nil and row.kind ~= "title" and before ~= nil and before.item.kind ~= "title")
    self.downButton:setEnable(row ~= nil and row.kind ~= "title" and after ~= nil and after.item.kind ~= "title")
    self.renameButton:setEnable(id ~= nil)
    self.deleteButton:setEnable(id ~= nil and Organizer.isCustomGroup(id))
    self.resetButton:setEnable(self.scopeID ~= "*")
end

function Editor:applyEntry()
    local entry = selected(self.list)
    if not entry then return end
    local id = self.destination:getOptionData(self.destination.selected)
    Organizer.setOverride(entry.key, id or nil, self.scopeID)
    self:reload()
end

function Editor:moveEntry(delta)
    local entry = selected(self.orderList)
    if entry then Organizer.moveEntry(self.scopeID, self.parentID, entry.key, delta); self:reload() end
end

function Editor:moveUp() self:moveEntry(-1) end
function Editor:moveDown() self:moveEntry(1) end

function Editor:createGroup()
    local id = Organizer.createGroup(self.groupName:getText(), self.scopeID)
    self.status = nil
    if id then self.parentID = id; self.orderList:clear() else self.status = text("group_invalid") end
    self:reload()
end

function Editor:renameGroup()
    local id = self:selectedGroup()
    if not id then return end
    self.status = nil
    if not Organizer.renameGroup(id, self.groupName:getText(), self.scopeID) then self.status = text("group_invalid") end
    self:reload()
end

function Editor:deleteGroup()
    local id = self:selectedGroup()
    if id and Organizer.deleteGroup(id) then
        self.parentID, self.status = "root", nil
        self.groupName:setText("")
        self:reload()
    end
end

function Editor:resetScope()
    if self.scopeID == "*" then return end
    Organizer.reset(self.scopeID)
    self.status = nil
    self:reload()
    self:selectOrderEntry()
end

function Editor:resetRules()
    Organizer.reset()
    self.parentID, self.status = "root", nil
    self:reload()
    self:selectOrderEntry()
end

function Editor:prerender()
    if not PZSurvivorToolkit.Settings.contextMenus() then self:close(); return end
    if self.search:getText():lower() ~= self.lastQuery or self.lastRevision ~= Organizer.revision then self:reload() end
    self:updateButtons()
    ISCollapsableWindow.prerender(self)
    self:drawText(text("scope"), 12, 34, 0.8, 0.8, 0.8, 1, UIFont.Small)
    self:drawText(text("search"), 12, 88, 0.8, 0.8, 0.8, 1, UIFont.Small)
    self:drawText(text("order"), self.rightX, 88, 0.8, 0.8, 0.8, 1, UIFont.Small)
    self:drawText(text("group_name"), self.rightX, self.height - 224, 0.8, 0.8, 0.8, 1, UIFont.Small)
    self:drawText(fit(text("group_scope_tip"), self.width - self.rightX - 16), self.rightX, self.height - 128, 0.7, 0.8, 0.9, 1, UIFont.Small)
    self:drawText(fit(self.status or text("scope_tip"), self.width - 28), 12, self.height - 66, 0.8, 0.8, 0.8, 1, UIFont.Small)
    if #self.list.items == 0 then
        self:drawText(fit(text("empty"), self.list.width - 20), 20, 152, 0.8, 0.8, 0.8, 1, UIFont.Small)
    end
end

function Editor:close()
    Organizer.save()
    self:setVisible(false)
    self:removeFromUIManager()
    instance = nil
end

function Editor.show()
    if not PZSurvivorToolkit.Settings.contextMenus() then return end
    if instance then instance:bringToTop(); return instance end
    local width = math.min(960, getCore():getScreenWidth() - 24)
    local height = math.min(680, getCore():getScreenHeight() - 24)
    instance = Editor:new((getCore():getScreenWidth() - width) / 2, (getCore():getScreenHeight() - height) / 2, width, height)
    instance.title = text("editor")
    instance.resizable = false
    instance:initialise()
    instance:instantiate()
    instance:addToUIManager()
    return instance
end

return Editor
