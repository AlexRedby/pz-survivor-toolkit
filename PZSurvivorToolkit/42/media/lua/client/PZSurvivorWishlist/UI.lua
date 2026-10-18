require "PZSurvivorWishlist/Client"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISComboBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISTextBox"
require "ISUI/ISTickBox"
require "ISUI/ISInventoryItem"
require "ISUI/ISButton"

local W = PZSurvivorWishlist
local UI = { windows = {} }
W.UI = UI
local FONT = UIFont.Small
local FH = getTextManager():getFontHeight(FONT)
local BH, RH = FH + 10, FH * 2 + 12
local Window = ISCollapsableWindow:derive("PZSWWindow")
local Catalog = ISCollapsableWindow:derive("PZSWCatalog")
local Sharing = ISCollapsableWindow:derive("PZSWSharing")

local function text(key, ...)
    return getText("UI_PZSW_" .. key, ...)
end

local function button(parent, x, y, width, label, callback)
    local control = ISButton:new(x, y, width, BH, label, parent, callback)
    control:initialise()
    control:instantiate()
    if PZSurvivorToolkit and PZSurvivorToolkit.UIStyle then
        PZSurvivorToolkit.UIStyle.button(control)
    else
        control.backgroundColor = {r = 0.10, g = 0.085, b = 0.07, a = 0.82}
        control.backgroundColorMouseOver = {r = 0.55, g = 0.27, b = 0.09, a = 0.92}
        control.borderColor = {r = 0.42, g = 0.34, b = 0.25, a = 0.65}
        control.textColor = {r = 0.94, g = 0.90, b = 0.83, a = 1}
    end
    parent:addChild(control)
    return control
end

local function entry(parent, x, y, width, value)
    local control = ISTextEntryBox:new(value or "", x, y, width, BH)
    control:initialise()
    control:instantiate()
    parent:addChild(control)
    return control
end

local function listbox(parent, x, y, width, height)
    local control = ISScrollingListBox:new(x, y, width, height)
    control:initialise()
    control:instantiate()
    control.itemheight, control.font, control.drawBorder = RH, FONT, true
    control.selected = 0
    parent:addChild(control)
    return control
end

local function setupWindow(class, width, height, title, playerNum)
    local w = math.min(width, getCore():getScreenWidth() - 40)
    local h = math.min(height, getCore():getScreenHeight() - 60)
    local window = ISCollapsableWindow.new(class,
        (getCore():getScreenWidth() - w) / 2, (getCore():getScreenHeight() - h) / 2, w, h)
    window.playerNum = playerNum
    window:setTitle(title)
    window:setResizable(false)
    window:setWantKeyEvents(true)
    return window
end

local function show(window)
    window:initialise()
    window:addToUIManager()
    window:setVisible(true)
    window:bringToTop()
    return window
end

function UI.close(window)
    if window.catalogWindow then window.catalogWindow:close() end
    if window.shareWindow then window.shareWindow:close() end
    if window.selector then window.selector:hidePopup() end
    if window.search then window.search:unfocus() end
    if window.quantity then window.quantity:unfocus() end
    if window.username then window.username:unfocus() end
    window:setVisible(false)
    -- The base close only hides windows; catalog instances must leave UIManager.
    window:removeFromUIManager()
end
Window.close, Catalog.close, Sharing.close = UI.close, UI.close, UI.close

local function escape(window, key)
    if key == Keyboard.KEY_ESCAPE then window:close(); return true end
    return false
end
Window.onKeyRelease, Catalog.onKeyRelease, Sharing.onKeyRelease = escape, escape, escape

-- Cut only at UTF-8 boundaries so translated item names remain valid text.
function UI.fit(value, width)
    if getTextManager():MeasureStringX(FONT, value) <= width then return value end
    while #value > 0 do
        local index = #value
        while index > 1 and value:byte(index) >= 128 and value:byte(index) < 192 do index = index - 1 end
        value = value:sub(1, index - 1)
        if getTextManager():MeasureStringX(FONT, value .. "...") <= width then return value .. "..." end
    end
    return ""
end

function UI.itemName(fullType)
    local script = getScriptManager():getItem(fullType)
    return script and script:getDisplayName() or fullType, script
end

local function drawItem(list, y, item)
    local row, h = item.item, list.itemheight
    if y + list:getYScroll() + h < 0 or y + list:getYScroll() >= list.height then return y + h end
    if list.selected == item.index then list:drawRect(0, y, list.width, h, 0.28, 0.25, 0.85, 0.75) end
    list:drawRectBorder(0, y, list.width, h, 0.2, 0.7, 0.7, 0.7)
    if row.script then ISInventoryItem.renderScriptItemIcon(list, row.script, 6, y + 5, 1, h - 10, h - 10) end
    local x, right = h + 2, list.width - 24
    local amount = row.amountText or ""
    local availableWidth = right - x - getTextManager():MeasureStringX(FONT, amount) - 10
    local shade = row.done and 0.55 or 0.95
    list:drawText(UI.fit(row.name, availableWidth), x, y + 4, shade, shade, shade, 1, FONT)
    list:drawTextRight(amount, right, y + 4, 0.4, 0.9, 0.8, 1, FONT)
    list:drawText(UI.fit(row.detail or row.fullType, right - x), x, y + FH + 6, 0.65, 0.65, 0.65, 1, FONT)
    return y + h
end

local function selectedRow(list)
    return list.items[list.selected] and list.items[list.selected].item
end

function Window:initialise()
    ISCollapsableWindow.initialise(self)
    local top = self:titleBarHeight() + 10
    self.selector = ISComboBox:new(10, top, self.width - 140, BH, self, function(target)
        local id = target.selector:getOptionData(target.selector.selected)
        W.Client.select(target.playerNum, id)
    end)
    self.selector:initialise()
    self:addChild(self.selector)
    self.shareButton = button(self, self.width - 120, top, 110, text("Share"), Window.share)
    self.list = listbox(self, 10, top + BH + 30, self.width - 20, self.height - top - BH * 3 - 68)
    self.list.doDrawItem = drawItem
    local y = self.list:getBottom() + 10
    local gap, width = 7, (self.width - 41) / 4
    self.addButton = button(self, 10, y, width, text("Add"), Window.catalog)
    self.amountButton = button(self, 10 + (width + gap), y, width, text("Amount"), Window.amount)
    self.doneButton = button(self, 10 + (width + gap) * 2, y, width, text("Done"), Window.done)
    self.removeButton = button(self, 10 + (width + gap) * 3, y, width, text("Remove"), Window.remove)
    self.footerY = y + BH + 8
    self.nextRefresh = 0
end

function Window:refresh()
    local state = W.Client.state(self.playerNum)
    local now = getTimestampMs()
    if now < self.nextRefresh and self.generation == state.generation then return end
    self.nextRefresh, self.generation = now + 750, state.generation
    local selected, scroll = selectedRow(self.list), self.list:getYScroll()
    self.selector:clear()
    for _, list in ipairs(state.lists) do
        local label = list.owner == state.username and text("Personal") or text("SharedBy", list.owner)
        self.selector:addOptionWithData(label, list.id)
        if list.id == state.selectedId then self.selector.selected = #self.selector.options end
    end
    local list = W.Client.selected(self.playerNum)
    self.list:clear()
    self.list.selected = 0
    if list then
        local rows, counts = {}, W.Client.carried(self.playerNum)
        for fullType, value in pairs(list.entries) do
            local name, script = UI.itemName(value.vehicleTypes and value.vehicleTypes[1] or fullType)
            if value.vehicleTypes then
                local class = getText("IGUI_VehicleType_" .. value.vehicleClass)
                if not name:find(class, 1, true) then name = name .. " (" .. class .. ")" end
            end
            rows[#rows + 1] = { fullType = fullType, name = name, script = script, amount = value.amount,
                done = value.done, amountText = value.done and text("Completed") or tostring(value.amount),
                detail = text("Carried", W.Client.carriedCount(counts, fullType, value)) .. "  |  "
                    .. (value.vehicleTypes and text("VehicleVariants") or fullType) }
        end
        table.sort(rows, function(a, b)
            if a.done ~= b.done then return not a.done end
            if a.name ~= b.name then return a.name < b.name end
            return a.fullType < b.fullType
        end)
        for _, row in ipairs(rows) do
            self.list:addItem(row.name, row)
            if selected and selected.fullType == row.fullType then self.list.selected = #self.list.items end
        end
    end
    self.list:setYScroll(scroll)
    self.shareButton:setEnable(list ~= nil and list.owner == state.username)
    self.addButton:setEnable(list ~= nil)
end

function Window:prerender()
    self:refresh()
    ISCollapsableWindow.prerender(self)
    local row = selectedRow(self.list)
    self.amountButton:setEnable(row ~= nil)
    self.doneButton:setEnable(row ~= nil)
    self.removeButton:setEnable(row ~= nil)
    self.doneButton:setTitle(text(row and row.done and "Reopen" or "Done"))
    self:drawText(UI.fit(text("HighlightHint"), self.width - 20), 10, self.selector:getBottom() + 7, 0.7, 0.7, 0.7, 1, FONT)
    local state = W.Client.state(self.playerNum)
    local footer = state.error and text("Error_" .. state.error) or (state.pending and text("Saving") or text("ManualHint"))
    self:drawText(UI.fit(footer, self.width - 20), 10, self.footerY, state.error and 1 or 0.7, 0.65, 0.65, 1, FONT)
end

function Window:catalog()
    local list = W.Client.selected(self.playerNum)
    if not list then return end
    if self.catalogWindow then self.catalogWindow:close() end
    local window = setupWindow(Catalog, 600, 510, text("Catalog"), self.playerNum)
    window.listId = list.id
    self.catalogWindow = show(window)
end

function Window:share()
    local list = W.Client.selected(self.playerNum)
    if not list then return end
    if self.shareWindow then self.shareWindow:close() end
    local window = setupWindow(Sharing, 510, 410, text("Sharing"), self.playerNum)
    window.source, window.listId = list, list.id
    self.shareWindow = show(window)
end

function Window:done()
    local row = selectedRow(self.list)
    if row then W.Client.edit(self.playerNum, "done", { fullType = row.fullType, done = not row.done }) end
end

function Window:remove()
    local row = selectedRow(self.list)
    if row then W.Client.edit(self.playerNum, "remove", { fullType = row.fullType }) end
end

function Window:amount()
    local row, list = selectedRow(self.list), W.Client.selected(self.playerNum)
    if not row or not list then return end
    local dialog = ISTextBox:new(0, 0, 340, 180, text("AmountPrompt"), tostring(row.amount), self,
        function(target, clicked)
            if clicked.internal == "OK" then
                W.Client.edit(target.playerNum, "set", { listId = list.id, fullType = row.fullType,
                    amount = tonumber(clicked.parent.entry:getInternalText()) })
            end
        end, self.playerNum)
    dialog:initialise()
    dialog:setOnlyNumbers(true)
    dialog:setValidateFunction(nil, function(_, value)
        local number = tonumber(value)
        return number ~= nil and number == math.floor(number) and number >= 1 and number <= 9999
    end)
    dialog:addToUIManager()
    dialog.entry:focus()
end

local catalogItems
function UI.catalog()
    if catalogItems then return catalogItems end
    catalogItems = {}
    local items = getAllItems()
    for i = 0, items:size() - 1 do
        local script = items:get(i)
        if not script:getObsolete() and not script:isHidden() then
            local name, fullType = script:getDisplayName(), script:getFullName()
            catalogItems[#catalogItems + 1] = { name = name, fullType = fullType, script = script,
                search = string.lower(name .. " " .. fullType) }
        end
    end
    table.sort(catalogItems, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.fullType < b.fullType
    end)
    return catalogItems
end

function Catalog:initialise()
    ISCollapsableWindow.initialise(self)
    local top = self:titleBarHeight() + 10
    self.search = entry(self, 10, top, self.width - 20)
    self.search:setClearButton(true)
    self.search:setTooltip(text("SearchHint"))
    self.list = listbox(self, 10, top + BH + 10, self.width - 20, self.height - top - BH * 2 - 56)
    self.list.doDrawItem = drawItem
    local y = self.list:getBottom() + 10
    self.quantity = entry(self, 10, y, 70, "1")
    self.quantity:setOnlyNumbers(true)
    self.quantity:setTooltip(text("AmountPrompt"))
    self.addButton = button(self, 90, y, self.width - 100, text("AddTo", self.listId), Catalog.add)
    self.search:focus()
    self:filter()
end

function Catalog:filter()
    local query = string.lower(self.search:getInternalText())
    if query == self.query then return end
    self.query = query
    self.list:clear()
    self.list.selected = 0
    self.list:setYScroll(0)
    for _, row in ipairs(UI.catalog()) do
        if query == "" or row.search:find(query, 1, true) then self.list:addItem(row.name, row, row.fullType) end
    end
end

function Catalog:prerender()
    self:filter()
    ISCollapsableWindow.prerender(self)
    local n = tonumber(self.quantity:getInternalText())
    local valid = n and n == math.floor(n) and n >= 1 and n <= 9999
    local state = W.Client.state(self.playerNum)
    local row, list = selectedRow(self.list), W.Client.getList(self.playerNum, self.listId)
    local removing = row and list and list.entries[row.fullType] ~= nil
    self.actionType, self.removing = row and row.fullType, removing
    self.addButton:setTitle(text(removing and "RemoveFrom" or "AddTo", list and list.owner or self.listId))
    self.quantity:setEditable(not removing)
    self.addButton:setEnable(row ~= nil and list ~= nil and not state.pending and (removing or valid == true))
    local status = state.error and text("Error_" .. state.error)
        or (state.pending and text("Saving") or text("CatalogCount", #self.list.items))
    self:drawText(UI.fit(status, self.width - 20), 10, self.addButton:getBottom() + 7, 0.7, 0.7, 0.7, 1, FONT)
end

function Catalog:add()
    local row, list = selectedRow(self.list), W.Client.getList(self.playerNum, self.listId)
    if not row or not list or W.Client.state(self.playerNum).pending then return end
    if self.actionType ~= row.fullType or self.removing ~= (list.entries[row.fullType] ~= nil) then return end
    if self.removing then
        W.Client.edit(self.playerNum, "remove", { listId = self.listId, fullType = row.fullType })
    else
        W.Client.edit(self.playerNum, "addMany", { listId = self.listId,
            entries = { { fullType = row.fullType, amount = tonumber(self.quantity:getInternalText()) } } })
    end
end

function Sharing:initialise()
    ISCollapsableWindow.initialise(self)
    local top = self:titleBarHeight() + 10
    self.username = entry(self, 10, top, self.width - 120)
    self.username:setTooltip(text("UsernameHint"))
    button(self, self.width - 100, top, 90, text("Add"), Sharing.addMember)
    self.list = listbox(self, 10, top + BH + 10, self.width - 20, self.height - top - BH * 4 - 65)
    self.list.itemheight = BH
    local members = {}
    for username in pairs(self.source.members) do members[#members + 1] = username end
    table.sort(members)
    for _, username in ipairs(members) do self.list:addItem(username, username) end
    local y = self.list:getBottom() + 8
    self.removeButton = button(self, 10, y, 170, text("RemoveMember"), Sharing.removeMember)
    self.faction = ISTickBox:new(10, y + BH + 8, self.width - 20, BH, "", self, function() end)
    self.faction:initialise()
    self.faction:addOption(text("Faction"))
    self.faction:setSelected(1, self.source.faction ~= nil and self.source.faction ~= false)
    local player = getSpecificPlayer(self.playerNum)
    local faction = player and Faction.getPlayerFaction(player)
    self.faction.enable = faction ~= nil
    self:addChild(self.faction)
    self.saveButton = button(self, 10, self.faction:getBottom() + 8, self.width - 20, text("SaveSharing"), Sharing.save)
end

function Sharing:addMember()
    local username = self.username:getInternalText():match("^%s*(.-)%s*$")
    if username == "" or username == self.source.owner or #username > 64 or #self.list.items >= 32 then return end
    for _, row in ipairs(self.list.items) do if row.item == username then return end end
    self.list:addItem(username, username)
    self.username:setText("")
end

function Sharing:removeMember()
    local row = self.list.items[self.list.selected]
    if row then self.list:removeItem(row.text) end
end

function Sharing:save()
    local members = {}
    for _, row in ipairs(self.list.items) do members[#members + 1] = row.item end
    W.Client.edit(self.playerNum, "share", { listId = self.listId, members = members,
        faction = self.faction:isSelected(1) })
    self:close()
end

function UI.open(playerNum)
    playerNum = playerNum or 0
    W.Client.sync(playerNum)
    local window = UI.windows[playerNum]
    if not window then
        window = show(setupWindow(Window, 600, 470, text("Title"), playerNum))
        UI.windows[playerNum] = window
    else
        window:addToUIManager()
        window:setVisible(true)
        window:bringToTop()
    end
    return window
end

function UI.toggle(playerNum)
    local window = UI.windows[playerNum]
    if window and window:getIsVisible() then window:close() else UI.open(playerNum) end
end

Events.OnMainMenuEnter.Add(function()
    for _, window in pairs(UI.windows) do
        window:close()
    end
    UI.windows, catalogItems = {}, nil
end)
return UI
