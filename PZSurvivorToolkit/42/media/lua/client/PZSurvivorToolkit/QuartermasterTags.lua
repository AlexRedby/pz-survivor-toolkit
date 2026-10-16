local Tags = require "PZSurvivorToolkit/ItemTags"
local Visuals = require "PZSurvivorToolkit/TagVisuals"

local Adapter = {}
PZSurvivorToolkit.QuartermasterTags = Adapter

local function tagView(picker)
    return Tags.enabled() and picker.mode == "cats" and picker.toolkitTagView
end

local function categories(picker, source)
    local result, seen = {}, {}
    for _, category in ipairs(source(picker)) do
        result[#result + 1], seen[category] = category, true
    end
    -- A saved category may disappear from the installed scripts; keep it available for refinement.
    for category, selected in pairs(picker.selectedCats) do
        if selected and not seen[category] then result[#result + 1] = category end
    end
    table.sort(result)
    return result
end

local function state(picker, row)
    local checked = 0
    for _, category in ipairs(row.categories) do
        if picker.selectedCats[category] then checked = checked + 1 end
    end
    return checked, #row.categories
end

local function selectRow(picker, row, selected)
    for _, category in ipairs(row.categories) do picker.selectedCats[category] = selected or nil end
    picker.needRebuild = true
end

local function drawTag(list, y, item)
    local row, picker = item.item, list.target
    local checked, total = state(picker, row)
    local h, w = item.height, list:getWidth()
    local scroll = list:getYScroll()
    if y + scroll + h < 0 or y + scroll >= list:getHeight() then return y + h end
    if checked > 0 then list:drawRect(0, y, w, h - 1, 0.28, 0.25, 0.45, 0.75)
    elseif list.mouseoverselected == item.index and list:isMouseOver() then
        list:drawRect(0, y, w, h - 1, 0.25, 0.35, 0.35, 0.35)
    end
    if list.selected == item.index then list:drawRect(0, y, w, h - 1, 0.30, 0.55, 0.75, 1) end
    local bx, by = 6, y + (h - 16) / 2
    list:drawRect(bx, by, 16, 16, 0.7, 0.08, 0.08, 0.08)
    list:drawRectBorder(bx, by, 16, 16, 0.9, 0.7, 0.7, 0.7)
    if checked == total then
        local color = getCore():getGoodHighlitedColor()
        list:drawTextureScaled(getTexture("media/ui/inventoryPanes/Tickbox_Tick.png"), bx + 2, by + 2,
            12, 12, 1, color:getR(), color:getG(), color:getB())
    elseif checked > 0 then
        list:drawRect(bx + 3, by + 7, 10, 2, 1, 0.9, 0.9, 0.9)
    end
    local label = row.label
    if total > 1 then label = label .. " (" .. checked .. "/" .. total .. ")" end
    local style, textX = Visuals.get(row.tag), bx + 24
    list:drawRect(textX, y + 3, 3, h - 6, 1, style.r, style.g, style.b)
    textX = textX + 7
    if style.texture then
        local size = math.min(18, h - 4)
        list:drawTextureScaledAspect(style.texture, textX, y + (h - size) / 2, size, size, 1, 1, 1, 1)
        textX = textX + size + 4
    end
    list:drawText(label, textX, y + (h - getTextManager():getFontHeight(UIFont.Medium)) / 2,
        1, 1, 1, 1, UIFont.Medium)
    return y + h
end

function Adapter.attach(picker)
    if not picker or picker.toolkitTagSwitch then return end
    local original = {}
    for _, name in ipairs({"activeList", "rebuild", "layout", "setMode", "prerender", "insertNewLineOfButtons"}) do
        original[name] = picker[name]
    end
    picker.toolkitTagView = true
    local button = ISButton:new(10, 0, 10, 22, "", picker, function(target)
        target.toolkitTagView = not target.toolkitTagView
        target.needRebuild = true
        target.listbox:setYScroll(0)
    end)
    button:initialise(); button:instantiate()
    button:setTooltip(getText("UI_PZST_QMTagsHint"))
    picker.toolkitTagSwitch = button
    picker:addChild(button)
    if picker.dimmer then picker:removeChild(picker.dimmer); picker:addChild(picker.dimmer) end

    picker.activeList = function(self)
        if Tags.enabled() and self.mode == "cats" then return categories(self, original.activeList) end
        return original.activeList(self)
    end
    picker.rebuild = function(self)
        if not tagView(self) then return original.rebuild(self) end
        local rows, byTag = {}, {}
        for _, category in ipairs(self:activeList()) do
            local ids = Tags.forCategory(category)
            if #ids == 0 or (#ids == 1 and ids[1] == "category:" .. category) then
                rows[#rows + 1] = {key = category, label = getTextOrNull("IGUI_ItemCat_" .. category) or category,
                    categories = {category}, toolkitTagRow = true}
            else
                for _, id in ipairs(ids) do
                    local row = byTag[id]
                    if not row then
                        row = {tag = id, label = Tags.label(id), categories = {}, toolkitTagRow = true}
                        byTag[id], rows[#rows + 1] = row, row
                    end
                    row.categories[#row.categories + 1] = category
                end
            end
        end
        table.sort(rows, function(a, b) return a.label < b.label end)
        local filter = string.lower(self:currentFilter())
        local contents = self.onlyContents and self:contentsSet() or nil
        self.listbox:clear()
        for _, row in ipairs(rows) do
            local checked = state(self, row)
            local hasContents = not contents
            if contents then
                for _, category in ipairs(row.categories) do
                    if contents[category] then hasContents = true; break end
                end
            end
            if (filter == "" or string.find(string.lower(row.label), filter, 1, true))
                and (not self.onlyChecked or checked > 0) and hasContents then
                self.listbox:addItem(row.label, row)
            end
        end
        self.lastFilter, self.needRebuild = filter, false
    end
    picker.layout = function(self)
        original.layout(self)
        local visible = Tags.enabled() and self.mode == "cats"
        button:setVisible(visible)
        if visible then
            button:setX(self.listbox:getX()); button:setY(self.listbox:getY())
            button:setWidth(self.listbox:getWidth()); button:setHeight(22)
            self.listbox:setY(self.listbox:getY() + 28)
            self.listbox:setHeight(math.max(12, self.listbox:getHeight() - 28))
        end
        -- Native clipping reads scrollbar geometry, which keeps the picker's initial 10x10 size.
        local scroll = self.listbox.vscroll
        if scroll then
            scroll:setX(self.listbox:getWidth() - 16)
            scroll:setHeight(self.listbox:getHeight())
            self.listbox:updateScrollbars()
        end
    end
    picker.setMode = function(self, mode)
        original.setMode(self, mode)
        self:layout()
    end
    picker.prerender = function(self, ...)
        local enabled = Tags.enabled()
        if self.toolkitTagsEnabled ~= enabled then
            self.toolkitTagsEnabled, self.needRebuild = enabled, true
            self:layout()
            if self.joypadConfigured then self:configJoypad() end
        end
        button:setTitle(getText(self.toolkitTagView and "UI_PZST_QMShowCategories" or "UI_PZST_QMShowTags"))
        return original.prerender(self, ...)
    end
    -- The native controller row builder calls this instance method before inserting the list.
    picker.insertNewLineOfButtons = function(self, first, ...)
        if first == self.listbox and Tags.enabled() and self.mode == "cats" then
            original.insertNewLineOfButtons(self, button)
        end
        return original.insertNewLineOfButtons(self, first, ...)
    end

    local list, rowClick = picker.listbox, picker.listbox.onmousedown
    list.onmousedown = function(target, row, ...)
        if tagView(target) and row and row.toolkitTagRow then
            local checked, total = state(target, row)
            selectRow(target, row, checked ~= total)
            return
        end
        return rowClick(target, row, ...)
    end
    local draw, joypad, rightMouse = list.doDrawItem, list.onJoypadDown, list.onRightMouseUp
    list.doDrawItem = function(self, y, item, ...)
        if tagView(self.target) and item.item.toolkitTagRow then return drawTag(self, y, item) end
        return draw(self, y, item, ...)
    end
    list.onJoypadDown = function(self, key, ...)
        if tagView(self.target) then
            if key == Joypad.AButton then
                local selected = self.items[self.selected]
                if selected then self.onmousedown(self.target, selected.item) end
                return
            end
            if key == Joypad.YButton then
                local selected = self.items[self.selected]
                if not selected or not selected.item.key then return end
            end
        end
        return joypad(self, key, ...)
    end
    list.onRightMouseUp = function(self, ...)
        if not tagView(self.target) then return rightMouse(self, ...) end
        -- Unknown categories still use Quartermaster's category inspector.
        local selected = self.items[self.mouseoverselected]
        if selected and selected.item.key then return rightMouse(self, ...) end
    end
    local selectFiltered = picker.btnAll.onclick
    picker.btnAll.onclick = function(target, ...)
        if not tagView(target) then return selectFiltered(target, ...) end
        for _, row in ipairs(target.listbox.items) do selectRow(target, row.item, true) end
    end
    picker.needRebuild = true
    picker:layout(); picker:rebuild()
    if picker.joypadConfigured then picker:configJoypad() end
end

function Adapter.install()
    if not LootSorter or LootSorter.toolkitTagPicker then return end
    if type(LootSorter.openPicker) ~= "function" or type(LootSorter.openPresetEditor) ~= "function" then return end
    LootSorter.toolkitTagPicker = true
    local open, edit = LootSorter.openPicker, LootSorter.openPresetEditor
    LootSorter.openPicker = function(...)
        local result = open(...)
        Adapter.attach(LootSorter._picker)
        return result
    end
    LootSorter.openPresetEditor = function(...)
        local result = edit(...)
        Adapter.attach(LootSorter._presetEditor)
        return result
    end
end

Events.OnGameStart.Add(Adapter.install)
Events.OnCreatePlayer.Add(Adapter.install)
return Adapter
