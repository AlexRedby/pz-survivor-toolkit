local Tags = require "PZSurvivorToolkit/ItemTags"
local Visuals = require "PZSurvivorToolkit/TagVisuals"
local Rules = require "PZSurvivorToolkit/QuartermasterTagRuleClient"
local RulePicker = require "PZSurvivorToolkit/TagRulePicker"

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

local function openRule(picker, rule, onApply)
    RulePicker.open({player = getSpecificPlayer(picker.playerNum or 0), owner = picker,
        rule = rule, categories = picker:activeList(), scriptItems = Rules.scriptItems(),
        title = getText("UI_PZST_QMTagRuleTitle"), onApply = function(value)
            picker.toolkitTagRule = Tags.normalizeRule(value)
            picker.toolkitTagRuleTouched = true
            if onApply then onApply() end
        end})
end

local function tagRows(categoryList, catalog)
    local rows, byTag, groups = {}, {}, {}
    for _, script in ipairs(catalog) do
        local category = script:getDisplayCategory()
        local entry = {tags = {}}
        for _, id in ipairs(Tags.forScriptItem(script)) do entry.tags[id] = true end
        if category then
            groups[category] = groups[category] or {}
            groups[category][#groups[category] + 1] = entry
        end
    end
    for _, category in ipairs(categoryList) do
        local members, ids = groups[category], {}
        if members then
            for _, entry in ipairs(members) do for id in pairs(entry.tags) do ids[id] = true end end
        else
            for _, id in ipairs(Tags.forCategory(category)) do ids[id] = true end
        end
        for id in pairs(ids) do
            local exact = id == "category:" .. category
            local row = byTag[id]
            if not row then
                row = {tag = not exact and id or nil, key = exact and category or nil,
                    label = exact and (getTextOrNull("IGUI_ItemCat_" .. category) or category) or Tags.label(id),
                    categories = {}, sourceCategories = {}, toolkitTagRow = true}
                byTag[id], rows[#rows + 1] = row, row
            end
            row.sourceCategories[#row.sourceCategories + 1] = category
            local matches = 0
            for _, entry in ipairs(members or {}) do if entry.tags[id] then matches = matches + 1 end end
            if not members or matches == #members then
                row.categories[#row.categories + 1] = category
            else
                -- Native specific-item keys are localized names; item refinements need a stable tag rule.
                row.requiresRule = true
            end
        end
    end
    for _, row in ipairs(rows) do
        if row.requiresRule then row.label = row.label .. " (" .. getText("UI_PZST_QMTagRule") .. ")" end
    end
    return rows
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
    if total > 0 and checked == total then
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
    picker.toolkitTagRuleRevision = Rules.getBoxRevision(picker.targetObj, picker.targetCI)
    if picker.targetKind == "preset" and LootSorter.getPresetStore then
        picker.toolkitTagRule = Rules.getPreset(picker.presetName, LootSorter.getPresetStore()[picker.presetName])
    else
        picker.toolkitTagRule = Rules.getBox(picker.targetObj, picker.targetCI)
    end
    local ruleButton = ISButton:new(10, 0, 10, 22, "", picker, function(target)
        openRule(target, target.toolkitTagRule)
    end)
    ruleButton:initialise(); ruleButton:instantiate()
    ruleButton:setTooltip(getText("UI_PZST_QMTagRuleHint"))
    picker.toolkitTagRuleButton = ruleButton
    picker:addChild(ruleButton)
    local close = picker.closePicker
    if close then
        picker.closePicker = function(self, ...)
            self.toolkitTagClosed = true
            return close(self, ...)
        end
        picker.close = picker.closePicker
    end
    local save = picker.onSave
    picker.onSave = function(self, ...)
        if self.targetKind == "preset" or (not self.toolkitTagRuleTouched and not Tags.ruleActive(self.toolkitTagRule)) then
            return save(self, ...)
        end
        if self.toolkitTagSaving then return end
        self.toolkitTagSaving = true
        local snapshot = {obj = self.targetObj, ci = self.targetCI, priority = self.priority,
            rule = Tags.normalizeRule(self.toolkitTagRule)}
        for _, field in ipairs({"selectedCats", "selectedItems", "selectedPresets"}) do
            snapshot[field] = {}
            for key, value in pairs(self[field]) do snapshot[field][key] = value end
        end
        Rules.saveBox(snapshot.obj, snapshot.ci, snapshot.rule,
            getSpecificPlayer(self.playerNum or 0), function(verdict, revision)
                self.toolkitTagSaving = false
                if self.toolkitTagClosed or LootSorter._picker ~= self or self.targetObj ~= snapshot.obj
                    or self.targetCI ~= snapshot.ci then return end
                if verdict == "ok" then
                    self.selectedCats, self.selectedItems, self.selectedPresets = snapshot.selectedCats,
                        snapshot.selectedItems, snapshot.selectedPresets
                    self.selection = self.mode == "items" and self.selectedItems
                        or self.mode == "presets" and self.selectedPresets or self.selectedCats
                    self.priority, self.toolkitTagRule, self.toolkitTagRuleRevision = snapshot.priority, snapshot.rule, revision
                    save(self)
                elseif LootSorter.notify then
                    LootSorter.notify(getSpecificPlayer(self.playerNum or 0), getText(verdict == "stale" and "UI_PZST_QMTagRuleStale" or "UI_PZST_QMTagRuleFailed", tostring(verdict)))
                end
            end, self.toolkitTagRuleRevision)
    end
    -- Native Save caches Picker.onSave when creating the button.
    if picker.btnSave then picker.btnSave.onclick = picker.onSave end
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
        local rows = tagRows(self:activeList(), Rules.scriptItems())
        table.sort(rows, function(a, b) return a.label < b.label end)
        local filter = string.lower(self:currentFilter())
        local contents = self.onlyContents and self:contentsSet() or nil
        self.listbox:clear()
        for _, row in ipairs(rows) do
            local checked = state(self, row)
            local hasContents = not contents
            if contents then
                for _, category in ipairs(row.sourceCategories) do
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
        ruleButton:setVisible(visible)
        if visible then
            button:setX(self.listbox:getX()); button:setY(self.listbox:getY())
            button:setWidth(self.listbox:getWidth()); button:setHeight(22)
            ruleButton:setX(self.listbox:getX()); ruleButton:setY(self.listbox:getY() + 28)
            ruleButton:setWidth(self.listbox:getWidth()); ruleButton:setHeight(22)
            self.listbox:setY(self.listbox:getY() + 56)
            self.listbox:setHeight(math.max(12, self.listbox:getHeight() - 56))
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
        ruleButton:setTitle(getText("UI_PZST_QMTagRule") .. (Tags.ruleActive(self.toolkitTagRule) and " *" or ""))
        button:setTitle(getText(self.toolkitTagView and "UI_PZST_QMShowCategories" or "UI_PZST_QMShowTags"))
        return original.prerender(self, ...)
    end
    -- The native controller row builder calls this instance method before inserting the list.
    picker.insertNewLineOfButtons = function(self, first, ...)
        if first == self.listbox and Tags.enabled() and self.mode == "cats" then
            original.insertNewLineOfButtons(self, button)
            original.insertNewLineOfButtons(self, ruleButton)
        end
        return original.insertNewLineOfButtons(self, first, ...)
    end

    local list, rowClick = picker.listbox, picker.listbox.onmousedown
    list.onmousedown = function(target, row, ...)
        if tagView(target) and row and row.toolkitTagRow then
            if row.requiresRule then
                openRule(target, {mode = "all", include = {row.tag}, exclude = {}})
                return
            end
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
        local include, entries = {}, target.listbox.items
        for _, entry in ipairs(entries) do
            if entry.item.requiresRule then include[#include + 1] = entry.item.tag end
        end
        if #include > 0 then
            openRule(target, {mode = "any", include = include, exclude = {}}, function()
                for _, entry in ipairs(entries) do
                    if not entry.item.requiresRule then selectRow(target, entry.item, true) end
                end
            end)
            return
        end
        for _, row in ipairs(target.listbox.items) do selectRow(target, row.item, true) end
    end
    picker.needRebuild = true
    picker:layout(); picker:rebuild()
    if picker.joypadConfigured then picker:configJoypad() end
end

function Adapter.presetArgs(picker, args)
    if picker.targetKind ~= "preset" or picker.toolkitTagRuleTouched or Rules.presetsSynced() then
        args.pzstTagRule = Tags.normalizeRule(picker.toolkitTagRule)
    end
    return args
end

return Adapter
