require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISScrollingListBox"
require "ISUI/ISComboBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISButton"
local Tags = require "PZSurvivorToolkit/ItemTags"
local Schema = require "PZSurvivorToolkit/ItemTagSchema"
local Visuals = require "PZSurvivorToolkit/TagVisuals"
local UIStyle = require "PZSurvivorToolkit/UIStyle"
local Picker = ISCollapsableWindowJoypad:derive("PZSTTagRulePicker")
PZSurvivorToolkit.TagRulePicker = Picker

local function text(key) return getText("UI_PZST_TagRule" .. key) end
local fit = UIStyle.fit
local function categoryName(category) return getTextOrNull("IGUI_ItemCat_" .. category) or category end
local function closed(owner)
    return owner and (owner.removed or (owner.isReallyVisible and not owner:isReallyVisible())
        or (owner.getIsVisible and not owner:getIsVisible()))
end
-- Keep the native list viewport guard when replacing doDrawItem. The base
-- prerender supplies the stencil for rows crossing the top/bottom edge.
local function rowVisible(list, y, item)
    return item.height > 0 and y + list:getYScroll() + item.height > 0
        and y + list:getYScroll() < list.height
end
local function contains(values, id)
    for index, value in ipairs(values) do if value == id then return index end end
end

function Picker:state(id)
    if contains(self.rule.include, id) then return "Include" end
    if contains(self.rule.exclude, id) then return "Exclude" end
    return "Neutral"
end

function Picker:cycle(row, reverse)
    if not row.id then return end
    local state = self:state(row.id)
    local nextState = state == (reverse and "Exclude" or "Neutral") and "Include"
        or state == (reverse and "Neutral" or "Include") and "Exclude" or "Neutral"
    local values = nextState == "Include" and self.rule.include or nextState == "Exclude" and self.rule.exclude
    if values and #values >= 64 then self.validationMessage = text("Limit"); return end
    self.validationMessage = nil
    local include, exclude = contains(self.rule.include, row.id), contains(self.rule.exclude, row.id)
    if include then table.remove(self.rule.include, include) end
    if exclude then table.remove(self.rule.exclude, exclude) end
    local selected = contains(self.selectionOrder, row.id)
    if selected then table.remove(self.selectionOrder, selected) end
    if nextState == "Include" then
        self.rule.include[#self.rule.include + 1] = row.id
        self.selectionOrder[#self.selectionOrder + 1] = row.id
    elseif nextState == "Exclude" then self.rule.exclude[#self.rule.exclude + 1] = row.id end
    self:refreshPreview()
end

function Picker:refreshPreview()
    self.preview:clear()
    local names = {}
    if self.sourceItems then
        for _, item in ipairs(self.sourceItems) do
            if Tags.matchesRule(Tags.forItem(item), self.rule) then names[#names + 1] = item:getName() end
        end
    elseif self.sourceScriptItems then
        for _, script in ipairs(self.sourceScriptItems) do
            if Tags.matchesScriptRule(script, self.rule) then names[#names + 1] = script:getDisplayName() end
        end
    else
        for _, category in ipairs(self.categories) do
            if Tags.matchesRule(category, self.rule) then names[#names + 1] = categoryName(category) end
        end
    end
    table.sort(names)
    for _, name in ipairs(names) do self.preview:addItem(name, name, name) end
    self.matchCount = #names
    if #names == 0 then self.preview:addItem(text("Empty"), false) end
end

function Picker:reload()
    self.list:clear()
    local query = self.search:getText():lower()
    local family = self.group:getOptionData(self.group.selected)
    local buckets = {{label=text("Roots")}, {label=text("Qualifiers")}, {label=text("Categories")}}
    for _, row in ipairs(self.entries) do
        if (not family or row.families[family]) and row.label:lower():find(query, 1, true) then
            local bucket = buckets[row.bucket]
            bucket[#bucket + 1] = row
        end
    end
    for _, bucket in ipairs(buckets) do
        if #bucket > 0 then
            self.list:addItem(bucket.label, {label=bucket.label})
            for _, row in ipairs(bucket) do self.list:addItem(row.label, row, row.label) end
        end
    end
    self.lastQuery, self.lastGroup = query, self.group.selected
end

function Picker:clearRule()
    self.rule = Tags.normalizeRule(nil)
    self.selectionOrder = {}
    self.validationMessage = nil
    self:updateMode()
    self:refreshPreview()
end

function Picker:updateMode()
    self.modeButton:setTitle(text(self.rule.mode == "all" and "All" or "Any"))
end

function Picker:toggleMode()
    self.rule.mode = self.rule.mode == "all" and "any" or "all"
    self:updateMode()
    self:refreshPreview()
end

function Picker:apply()
    if not Tags.enabled() or closed(self.owner) then self:close(); return end
    local rule = Tags.normalizeRule(self.rule)
    if not rule then return end
    self.onApply(rule, self.selectionOrder[1])
    self:close()
end

function Picker:close()
    self.search:unfocus()
    if self.group.expanded and self.group.popup and self.group.popup.parentCombo == self.group then
        self.group:hidePopup()
        self.group.expanded = false
    end
    for _, list in ipairs({self.list, self.preview}) do
        if list.tooltipUI then list.tooltipUI:setVisible(false); list.tooltipUI:removeFromUIManager() end
    end
    self:setVisible(false)
    self:removeFromUIManager()
    if self.owner and self.owner.toolkitRulePicker == self then
        self.owner.toolkitRulePicker = nil
        if self.owner.dimmer and self.owner.dimmer.setVisible then
            self.owner.dimmer:setVisible(self.ownerDimmerVisible)
            self.owner.dimmer.onMouseDown = self.ownerDimmerMouseDown
        end
    end
    if self.grabbedJoypad then
        local restore = self.previousFocus
        if closed(restore) then restore = restore.prevFocus end
        setJoypadFocus(self.playerNum, restore)
    end
    self.previousFocus, self.grabbedJoypad = nil, false
end

function Picker:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    local width, height = self.width, self.height
    local fontHeight = getTextManager():getFontHeight(UIFont.Small)
    local controlHeight = math.max(26, fontHeight + 8)
    local searchY = math.max(34, self:titleBarHeight() + 8)
    local groupY, modeY = searchY + controlHeight + 6, searchY + (controlHeight + 6) * 2
    local footerY = height - controlHeight - 16
    self.hintY = footerY - fontHeight - 26
    local function button(x, y, w, label, callback)
        local result = ISButton:new(x, y, w, controlHeight, label, self, callback)
        result:initialise(); result:instantiate(); UIStyle.button(result); self:addChild(result)
        return result
    end
    self.search = ISTextEntryBox:new("", 12, searchY, width - 24, controlHeight)
    self.search:setFont(UIFont.Small)
    self.search:initialise(); self.search:instantiate(); self.search:setTooltip(text("Search")); self:addChild(self.search)
    self.group = ISComboBox:new(12, groupY, width - 24, controlHeight)
    self.group:initialise(); self.group:instantiate()
    self.group:addOptionWithData(text("AllGroups"), false)
    for _, family in ipairs(self.families) do self.group:addOptionWithData(Tags.label(family), family) end
    self:addChild(self.group)
    self.modeButton = button(12, modeY, width - 24, "", Picker.toggleMode)
    self:updateMode()
    self.modeButton:setTooltip(text("Hint"))
    local top, bottom = modeY + controlHeight + 26, self.hintY - fontHeight - 24
    local previewGap = fontHeight + 10
    local listWidth = width >= 620 and math.floor((width - 36) * 0.55) or width - 24
    local listHeight = width >= 620 and bottom - top or math.floor((bottom - top - previewGap) * 0.6)
    self.list = ISScrollingListBox:new(12, top, listWidth, math.max(40, listHeight))
    self.list:initialise(); self.list:instantiate(); self.list.itemheight = fontHeight + 10
    self.list:setOnMouseDownFunction(self, Picker.cycle)
    self.list.doDrawItem = function(list, y, item)
        if not rowVisible(list, y, item) then return y + item.height end
        local row, x = item.item, 8
        local textY = y + (item.height - fontHeight) / 2
        if list.selected == item.index then list:drawRectBorder(1, y, list.width - 18, item.height, 0.9, 0.65, 0.8, 1) end
        if row.id then
            local state, style = self:state(row.id), Visuals.get(row.id)
            if state ~= "Neutral" then list:drawRect(0, y, list.width, item.height, 0.3,
                state == "Exclude" and 0.7 or 0.2, 0.3, state == "Exclude" and 0.2 or 0.6) end
            if style.texture then
                list:drawTextureScaledAspect(style.texture, x, y + (item.height - 18) / 2, 18, 18, 1, style.r, style.g, style.b)
            end
            x = x + 24
            list:drawText(fit(text(state) .. ": " .. row.label, list.width - x - 20), x, textY, 1, 1, 1, 1, UIFont.Small)
        else list:drawText(fit(row.label, list.width - x - 20), x, textY, 0.9, 0.72, 0.45, 1, UIFont.Small) end
        return y + item.height
    end
    self.list.onRightMouseUp = function(list)
        local row = list.items[list.mouseoverselected]
        if row then self:cycle(row.item, true) end
    end
    self.list.joypadParent = self
    self.list.setJoypadFocused = function(list, focused) list.joypadFocused = focused end
    self.list.onJoypadDownInParent = function(list, key, joypadData)
        if key ~= Joypad.AButton then return false end
        joypadData.focus = list; updateJoypadFocus(joypadData)
        if (list.selected or 0) < 1 then list.selected = 1 end
        return true
    end
    self.list.onJoypadDirUp = function(list)
        list.selected = list:prevVisibleIndex(list.selected)
        if list.selected <= 0 then list.selected = list:prevVisibleIndex(list.count + 1) end
        list:ensureVisible(list.selected)
    end
    self.list.onJoypadDirDown = function(list)
        list.selected = list:nextVisibleIndex(list.selected)
        if list.selected == -1 then list.selected = list:nextVisibleIndex(0) end
        list:ensureVisible(list.selected)
    end
    self.list.onJoypadDown = function(list, key, joypadData)
        if key == Joypad.AButton then
            local row = list.items[list.selected]
            if row then self:cycle(row.item) end
        elseif key == Joypad.BButton then
            joypadData.focus = self; updateJoypadFocus(joypadData)
        else ISScrollingListBox.onJoypadDown(list, key, joypadData) end
    end
    self:addChild(self.list)
    local previewX = width >= 620 and listWidth + 24 or 12
    local previewY = width >= 620 and top or top + self.list.height + previewGap
    self.preview = ISScrollingListBox:new(previewX, previewY, width - previewX - 12, math.max(40, bottom - previewY))
    self.preview:initialise(); self.preview:instantiate(); self.preview.itemheight = fontHeight + 10
    self.preview.doDrawItem = function(list, y, item)
        if not rowVisible(list, y, item) then return y + item.height end
        list:drawText(fit(item.text, list.width - 28), 8, y + (item.height - fontHeight) / 2, 0.9, 0.9, 0.9, 1, UIFont.Small)
        return y + item.height
    end
    self.preview.joypadParent = self
    self.preview.setJoypadFocused = self.list.setJoypadFocused
    self.preview.onJoypadDownInParent = self.list.onJoypadDownInParent
    self.preview.onJoypadDirUp, self.preview.onJoypadDirDown = self.list.onJoypadDirUp, self.list.onJoypadDirDown
    self:addChild(self.preview)
    self.clearButton = button(12, footerY, 100, text("Clear"), Picker.clearRule)
    self.cancelButton = button(width - 224, footerY, 100, text("Cancel"), Picker.close)
    self.applyButton = button(width - 112, footerY, 100, text("Apply"), Picker.apply)
    self:reload(); self:refreshPreview()
end

function Picker:onGainJoypadFocus(joypadData)
    ISCollapsableWindowJoypad.onGainJoypadFocus(self, joypadData)
    if self.joypadConfigured then return end
    self.joypadConfigured = true
    self:insertNewLineOfButtons(self.search)
    self:insertNewLineOfButtons(self.group)
    self:insertNewLineOfButtons(self.modeButton)
    self:insertNewLineOfButtons(self.list)
    self:insertNewLineOfButtons(self.preview)
    self:insertNewLineOfButtons(self.clearButton, self.cancelButton, self.applyButton)
    self.joypadIndexY, self.joypadIndex = 1, 1
    self:restoreJoypadFocus(joypadData)
end

function Picker:onJoypadDown(key, joypadData)
    if key == Joypad.BButton and not self.group.expanded then self:close(); return end
    ISCollapsableWindowJoypad.onJoypadDown(self, key, joypadData)
end

function Picker:prerender()
    if not Tags.enabled() or closed(self.owner) then
        self:close(); return
    end
    if self.reassertTop then self.reassertTop = false; self:bringToTop() end
    if self.search:getText():lower() ~= self.lastQuery or self.group.selected ~= self.lastGroup then self:reload() end
    ISCollapsableWindowJoypad.prerender(self)
    self:drawText(text(self.sourceScriptItems and "PreviewTypes" or "Preview") .. " (" .. self.matchCount .. ")", self.preview.x, self.preview.y - getTextManager():getFontHeight(UIFont.Small) - 5,
        0.9, 0.9, 0.9, 1, UIFont.Small)
    local y = self.hintY
    self:drawText(fit(self.validationMessage or text("Hint"), self.width - 24), 12, y, 0.8, 0.8, 0.8, 1, UIFont.Small)
end

function Picker.open(options)
    if not Tags.enabled() then return end
    local rule, error = Tags.normalizeRule(options.rule)
    if not rule then return nil, error end
    if options.owner and options.owner.toolkitRulePicker then options.owner.toolkitRulePicker:close() end
    local entries, families, roots, seen = {}, {}, {}, {}
    for _, definition in pairs(Schema.categories) do roots[definition[1]] = true end
    local categories = {}
    for _, category in ipairs(options.categories or {}) do
        if not seen[category] then categories[#categories + 1], seen[category] = category, true end
    end
    local byId, familySet = {}, {}
    for _, source in ipairs(options.items or options.scriptItems or categories) do
        local ids = options.items and Tags.forItem(source)
            or options.scriptItems and Tags.forScriptItem(source) or Tags.forCategory(source)
        ids = Tags.choices(ids)
        local sourceFamilies = {}
        for _, id in ipairs(ids) do if roots[id] then sourceFamilies[#sourceFamilies + 1] = id end end
        if #sourceFamilies == 0 and ids[1] then sourceFamilies[1] = ids[1] end
        for _, family in ipairs(sourceFamilies) do
            if not familySet[family] then families[#families + 1], familySet[family] = family, true end
        end
        for _, id in ipairs(ids) do
            local row = byId[id]
            if not row then
                row = {id=id, label=Tags.label(id), families={}, bucket=id:sub(1, 9) == "category:" and 3 or roots[id] and 1 or 2}
                byId[id], entries[#entries + 1] = row, row
            end
            for _, family in ipairs(sourceFamilies) do row.families[family] = true end
        end
    end
    -- Keep saved selections editable even if their last matching item disappeared.
    for _, values in ipairs({rule.include, rule.exclude}) do
        for _, id in ipairs(values) do
            if not byId[id] then entries[#entries + 1] = {id=id, label=Tags.label(id), families={}, bucket=3}; byId[id]=true end
        end
    end
    table.sort(entries, function(a, b) return a.label < b.label end)
    table.sort(families, function(a, b) return Tags.label(a) < Tags.label(b) end)
    local width, height = math.min(760, getCore():getScreenWidth() - 24), math.min(650, getCore():getScreenHeight() - 24)
    local picker = Picker:new((getCore():getScreenWidth() - width) / 2, (getCore():getScreenHeight() - height) / 2, width, height)
    picker.rule, picker.categories, picker.sourceItems = rule, categories, options.items
    picker.selectionOrder = options.selectedTag and {options.selectedTag} or {}
    picker.sourceScriptItems = options.scriptItems
    picker.entries, picker.families = entries, families
    picker.owner, picker.onApply, picker.player = options.owner, options.onApply, options.player
    picker.title, picker.resizable = options.title or text(""), false
    picker:initialise(); picker:instantiate(); picker:addToUIManager()
    picker:bringToTop()
    -- The opening mouse event can still raise the owner after its button callback.
    picker.reassertTop = true
    if picker.owner then
        picker.owner.toolkitRulePicker = picker
        if picker.owner.dimmer and picker.owner.dimmer.setVisible then
            picker.ownerDimmerVisible = picker.owner.dimmer:getIsVisible()
            picker.ownerDimmerMouseDown = picker.owner.dimmer.onMouseDown
            picker.owner.dimmer.onMouseDown = function() picker.reassertTop = true; return true end
            picker.owner.dimmer:setVisible(true)
        end
    end
    picker.playerNum = type(options.player) == "number" and options.player
        or options.player and options.player:getPlayerNum()
    local joypad = picker.playerNum and JoypadState and JoypadState.players[picker.playerNum + 1]
    if joypad and setJoypadFocus then
        picker.previousFocus, picker.grabbedJoypad = joypad.focus, true
        setJoypadFocus(picker.playerNum, picker)
    end
    return picker
end

return Picker
