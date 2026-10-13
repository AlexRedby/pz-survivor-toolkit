require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISComboBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISButton"
local Organizer = require "PZSurvivorToolkit/ContextMenus"
local Rules = require "PZSurvivorToolkit/ContextMenuRules"
local UIStyle = require "PZSurvivorToolkit/UIStyle"
local Editor = ISCollapsableWindow:derive("PZSurvivorToolkitContextMenuEditor")
local instance

local function text(id)
    return getText("UI_PZSurvivorToolkit_context_" .. id)
end

function Editor:createChildren()
    ISCollapsableWindow.createChildren(self)
    local width, height = self.width, self.height
    self.search = ISTextEntryBox:new("", 12, 36, width - 24, 26)
    self.search:initialise()
    self.search:instantiate()
    self.search:setTooltip(text("search"))
    self:addChild(self.search)
    self.list = ISScrollingListBox:new(12, 72, width - 24, height - 172)
    self.list:initialise()
    self.list:instantiate()
    local fontHeight = getTextManager():getFontHeight(UIFont.Small)
    self.list.itemheight = fontHeight * 2 + 12
    self.list.doDrawItem = function(list, y, row)
        if list.selected == row.index then list:drawRect(0, y, list.width, list.itemheight, 0.4, 0.2, 0.35, 0.6) end
        list:drawText(row.item.label, 8, y + 6, 1, 1, 1, 1, UIFont.Small)
        local id = Organizer.overrides[row.item.key]
        local label = id and Organizer.groupName(id) or text("auto")
        list:drawTextRight(label, list.width - 20, y + 6 + fontHeight, 0.7, 0.8, 0.9, 1, UIFont.Small)
        return y + list.itemheight
    end
    self.list:setOnMouseDownFunction(self, Editor.selectEntry)
    self:addChild(self.list)
    self.destination = ISComboBox:new(12, height - 84, width - 250, 28)
    self.destination:initialise()
    self.destination:instantiate()
    self.destination:addOptionWithData(text("auto"), false)
    for _, id in ipairs({"root", "hidden"}) do self.destination:addOptionWithData(Organizer.groupName(id), id) end
    for _, id in ipairs(Rules.groups) do self.destination:addOptionWithData(Organizer.groupName(id), id) end
    self:addChild(self.destination)
    local function button(x, y, width, label, callback)
        local control = ISButton:new(x, y, width, 28, label, self, callback)
        control:initialise()
        control:instantiate()
        UIStyle.button(control)
        self:addChild(control)
        return control
    end
    self.applyButton = button(width - 226, height - 84, 214, text("apply"), Editor.applyEntry)
    button(12, height - 44, 190, text("reset"), Editor.resetRules)
    button(width - 122, height - 44, 110, getText("UI_btn_close"), Editor.close)
    self:reload()
end

function Editor:reload()
    local selected = self.list.items[self.list.selected]
    local selectedKey = selected and selected.item.key
    self.list:clear()
    local query = self.search:getText():lower()
    local entries = {}
    for _, entry in pairs(Organizer.entries) do
        if entry.label:lower():find(query, 1, true) then entries[#entries + 1] = entry end
    end
    table.sort(entries, function(a, b) return a.label < b.label end)
    for _, entry in ipairs(entries) do
        self.list:addItem(entry.label, entry)
        if entry.key == selectedKey then self.list.selected = #self.list.items end
    end
    self.lastQuery, self.lastRevision = query, Organizer.revision
    local row = self.list.items[self.list.selected]
    if row then self:selectEntry(row.item) end
end

function Editor:selectEntry(entry)
    local id = Organizer.overrides[entry.key] or false
    for index = 1, #self.destination.options do
        if self.destination:getOptionData(index) == id then self.destination.selected = index; break end
    end
end

function Editor:applyEntry()
    local row = self.list.items[self.list.selected]
    if not row then return end
    local id = self.destination:getOptionData(self.destination.selected)
    Organizer.setOverride(row.item.key, id or nil)
    self:reload()
end

function Editor:resetRules()
    Organizer.reset()
    self:reload()
end

function Editor:prerender()
    if not PZSurvivorToolkit.Settings.contextMenus() then self:close(); return end
    if self.search:getText():lower() ~= self.lastQuery or self.lastRevision ~= Organizer.revision then self:reload() end
    self.applyButton:setEnable(self.list.items[self.list.selected] ~= nil)
    ISCollapsableWindow.prerender(self)
    if #self.list.items == 0 then self:drawText(text("empty"), 20, 104, 0.8, 0.8, 0.8, 1, UIFont.Small) end
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
    local width = math.min(760, getCore():getScreenWidth() - 24)
    local height = math.min(540, getCore():getScreenHeight() - 24)
    instance = Editor:new((getCore():getScreenWidth() - width) / 2, (getCore():getScreenHeight() - height) / 2, width, height)
    instance.title = text("editor")
    instance.resizable = false
    instance:initialise()
    instance:instantiate()
    instance:addToUIManager()
    return instance
end

return Editor
