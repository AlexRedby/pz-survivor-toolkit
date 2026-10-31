require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISScrollingListBox"
require "ISUI/ISPanel"
require "ISUI/ISButton"
local Tags = require "PZSurvivorToolkit/ItemTags"
local Schema = require "PZSurvivorToolkit/ItemTagSchema"
local Visuals = require "PZSurvivorToolkit/TagVisuals"
local UIStyle = require "PZSurvivorToolkit/UIStyle"
local Choice = require "PZSurvivorToolkit/TagRuleTagPicker"
local Picker = ISCollapsableWindowJoypad:derive("PZSTTagRulePicker")
PZSurvivorToolkit.TagRulePicker = Picker
local function text(key) return getText("UI_PZST_TagRule" .. key) end
local function closed(owner)
    return owner and (owner.removed or (owner.isReallyVisible and not owner:isReallyVisible())
        or (owner.getIsVisible and not owner:getIsVisible()))
end

function Picker.summary(rule)
    if not Tags.ruleActive(rule) then return text("NoRule") end
    local groups = Tags.ruleGroups(rule)
    local parts, size = {}, 0
    -- Keep the single-line caption cheap to measure even for large legacy ANY
    -- rules, whose global exclusions are repeated in every editable branch.
    local function append(value)
        local remaining = 320 - size
        if #value > remaining then
            if #"é" > 1 then
                local byte = value:byte(remaining + 1)
                while remaining > 0 and byte and byte >= 128 and byte < 192 do
                    remaining = remaining - 1; byte = value:byte(remaining + 1)
                end
            end
            parts[#parts + 1] = value:sub(1, remaining) .. "..."
            return false
        end
        parts[#parts + 1], size = value, size + #value
        return true
    end
    for index, group in ipairs(groups or {}) do
        if index > 1 and not append(" " .. text("Or") .. " ") then break end
        local bracket = #groups > 1 and #group.include + #group.exclude > 1
        if bracket and not append("(") then break end
        local first = true
        for _, field in ipairs({"include", "exclude"}) do
            for _, id in ipairs(group[field]) do
                if not first and not append(" " .. text("And") .. " ") then return table.concat(parts) end
                first = false
                if not append((field == "exclude" and text("Not") .. " " or "") .. Tags.label(id)) then
                    return table.concat(parts)
                end
            end
        end
        if bracket and not append(")") then break end
    end
    return table.concat(parts)
end

function Picker:groupsFromConditions()
    local groups = {}
    for _, conditions in ipairs(self.conditions) do
        local group = {include={}, exclude={}}
        for _, condition in ipairs(conditions) do
            local list = condition.excluded and group.exclude or group.include
            list[#list + 1] = condition.id
        end
        groups[#groups + 1] = group
    end
    return groups
end

function Picker:refreshRule()
    local previousIndex = self.list.selected or 1
    local previousItem = self.list.items[previousIndex]
    local previous = previousItem and previousItem.item
    local selectedCondition = self.pendingConditionSelection or (previous and previous.condition)
    local previousScroll = self.list:getYScroll()
    self.pendingConditionSelection = nil
    local rule, err
    if #self.conditions == 0 then rule = Tags.normalizeRule(nil)
    else rule, err = Tags.fromRuleGroups(self:groupsFromConditions()) end
    self.rule, self.validationMessage = rule, err and text("Conflict") or nil
    local included = {}
    for _, conditions in ipairs(self.conditions) do
        for _, condition in ipairs(conditions) do if not condition.excluded then included[condition.id] = true end end
    end
    for index = #self.selectionOrder, 1, -1 do
        if not included[self.selectionOrder[index]] then table.remove(self.selectionOrder, index) end
    end
    self.applyButton:setEnable(rule ~= nil)
    self.list:clear()
    for gi, conditions in ipairs(self.conditions) do
        self.list:addItem(gi == 1 and text("Group") or text("Or"), {kind="group", group=gi, conditions=conditions})
        for ri, condition in ipairs(conditions) do
            self.list:addItem(Tags.label(condition.id), {kind="condition", group=gi, index=ri, condition=condition})
        end
        self.list:addItem(text("AddAnd"), {kind="add", group=gi, conditions=conditions})
    end
    if #self.conditions == 0 then self.list:addItem(text("AddCondition"), {kind="add", group=1}) end
    local selectedIndex = math.max(1, math.min(previousIndex, #self.list.items))
    for index, item in ipairs(self.list.items) do
        local row = item.item
        if (selectedCondition and row.condition == selectedCondition)
            or (not selectedCondition and previous and row.kind == previous.kind
                and row.conditions and row.conditions == previous.conditions) then
            selectedIndex = index; break
        end
    end
    -- Native clear resets selection but leaves scroll height and smooth-scroll state.
    -- Restore the old viewport, then reveal the edited/new row only if necessary.
    self.list.selected = selectedIndex
    self.list:setScrollHeight(#self.list.items * self.list.itemheight)
    local scroll = math.min(0, math.max(previousScroll, self.list.height - #self.list.items * self.list.itemheight))
    self.list.smoothScrollTargetY, self.list.smoothScrollY = nil, scroll
    self.list:setYScroll(scroll)
    self.list:ensureVisible(selectedIndex)
    self.validationMessage = err and text("Conflict") or nil
end

function Picker:rememberSelection(id)
    for _, selected in ipairs(self.selectionOrder) do if selected == id then return end end
    self.selectionOrder[#self.selectionOrder + 1] = id
end

function Picker:addCondition(groupIndex, id, excluded)
    if not id then
        return self:chooseTag(function(value) self:addCondition(groupIndex, value, excluded) end)
    end
    if groupIndex < 1 or groupIndex > #self.conditions + 1 or groupIndex > 64 then
        self.validationMessage = text("Limit"); return false
    end
    local conditions = self.conditions[groupIndex] or {}
    local count = 0
    for _, condition in ipairs(conditions) do
        if condition.id == id then self.validationMessage = text("Duplicate"); return false end
        if condition.excluded == (excluded == true) then count = count + 1 end
    end
    if count >= 64 or not Tags.normalizeRule({include=excluded and {} or {id},exclude=excluded and {id} or {}}) then
        self.validationMessage = text("Limit"); return false
    end
    self.conditions[groupIndex] = conditions
    conditions[#conditions + 1] = {id=id, excluded=excluded == true}
    self.pendingConditionSelection = conditions[#conditions]
    if not excluded then self:rememberSelection(id) end
    self:refreshRule()
    return true
end

function Picker:addGroup(id, excluded)
    if #self.conditions >= 64 then self.validationMessage = text("Limit"); return false end
    return self:addCondition(#self.conditions + 1, id, excluded)
end

function Picker:changeCondition(groupIndex, rowIndex, id)
    local conditions = self.conditions[groupIndex]
    local condition = conditions and conditions[rowIndex]
    if not condition then return end
    if not id then
        return self:chooseTag(function(value) self:changeCondition(groupIndex, rowIndex, value) end)
    end
    for index, other in ipairs(conditions) do
        if index ~= rowIndex and other.id == id then self.validationMessage = text("Duplicate"); return false end
    end
    if not Tags.normalizeRule({include={id}}) then return false end
    condition.id = id
    if not condition.excluded then self:rememberSelection(id) end
    self:refreshRule()
    return true
end

function Picker:toggleCondition(groupIndex, rowIndex)
    local conditions = self.conditions[groupIndex]
    local condition = conditions and conditions[rowIndex]
    if not condition then return end
    local count = 0
    for _, other in ipairs(conditions) do if other.excluded ~= condition.excluded then count = count + 1 end end
    if count >= 64 then self.validationMessage = text("Limit"); return false end
    condition.excluded = not condition.excluded
    if not condition.excluded then self:rememberSelection(condition.id) end
    self:refreshRule()
    return true
end

function Picker:removeCondition(groupIndex, rowIndex)
    local conditions = self.conditions[groupIndex]
    if not conditions or not conditions[rowIndex] then return end
    table.remove(conditions, rowIndex)
    if #conditions == 0 then table.remove(self.conditions, groupIndex) end
    self:refreshRule()
end

function Picker:clearRule()
    self.conditions, self.selectionOrder = {}, {}
    self:refreshRule()
end

-- Script choices are prepared lazily once. Live inventory references are re-read when
-- opening the chooser; their categories can change while the rule editor stays open.
function Picker:catalogEntries()
    local revision = Tags.revision and Tags.revision() or 0
    if self.entries and not self.options.items and self.tagRevision == revision then return self.entries, self.families end
    local entries, byId, families, familySet, roots = {}, {}, {}, {}, {}
    for _, definition in pairs(Schema.categories) do if definition[1] then roots[definition[1]] = true end end
    local function add(id, sourceFamilies)
        local row = byId[id]
        if not row then
            local label = Tags.label(id)
            row = {id=id, label=label, search=(label .. " " .. id):lower(), families={}}
            byId[id], entries[#entries + 1] = row, row
        end
        for _, family in ipairs(sourceFamilies) do
            row.families[family] = true
            if not familySet[family] then familySet[family], families[#families + 1] = true, family end
        end
    end
    local function addSource(ids, prepared)
        if not prepared then ids = Tags.choices and Tags.choices(ids) or ids end
        local sourceFamilies = {}
        for _, id in ipairs(ids) do if roots[id] then sourceFamilies[#sourceFamilies + 1] = id end end
        if #sourceFamilies == 0 and ids[1] then sourceFamilies[1] = ids[1] end
        for _, id in ipairs(ids) do add(id, sourceFamilies) end
    end
    local options = self.options
    if options.tagSources then
        for _, ids in ipairs(options.tagSources()) do addSource(ids) end
    else
        local context = options.scriptItems and Tags.newScriptProjectionContext()
        local prepared = not options.items and options.scriptItems ~= nil
        for _, source in ipairs(options.items or options.scriptItems or options.categories or {}) do
            addSource(options.items and Tags.forItem(source)
                or options.scriptItems and Tags.choicesForScriptItem(source, context) or Tags.forCategory(source), prepared)
        end
    end
    for _, id in ipairs(Tags.customIds()) do add(id, {}) end
    for _, conditions in ipairs(self.conditions) do
        for _, condition in ipairs(conditions) do add(condition.id, {}) end
    end
    table.sort(entries, function(a,b) if a.label == b.label then return a.id < b.id end; return a.label < b.label end)
    table.sort(families, function(a,b) return Tags.label(a) < Tags.label(b) end)
    self.entries, self.families, self.tagRevision = entries, families, revision
    return entries, families
end

function Picker:chooseTag(onPick)
    local entries, families = self:catalogEntries()
    return Choice.open(self, entries, families, onPick)
end

function Picker:activate(row)
    if row.kind == "add" then self:addCondition(row.group)
    elseif row.kind == "condition" then self:changeCondition(row.group, row.index) end
end

function Picker:clickRow(row)
    if row.kind ~= "condition" then self:activate(row); return end
    local x = self.list:getMouseX()
    if x < 108 then self:toggleCondition(row.group, row.index)
    elseif x >= self.list.width - 56 then self:removeCondition(row.group, row.index)
    else self:changeCondition(row.group, row.index) end
end

function Picker.drawRow(list, y, item)
    local h, w, row = item.height, list.width, item.item
    local scroll = list:getYScroll()
    if y + scroll + h < 0 or y + scroll >= list:getHeight() then return y + h end
    if row.kind == "group" then
        list:drawText(row.group == 1 and text("Group") or text("Or"), 10, y + 8, 0.9, 0.72, 0.45, 1, UIFont.Small)
        return y + h
    end
    if list.selected == item.index then list:drawRect(0, y, w - 18, h, 0.25, 0.3, 0.5, 0.7) end
    if row.kind == "add" then
        list:drawText(item.text, 32, y + 8, 0.85, 0.85, 0.8, 1, UIFont.Small)
        return y + h
    end
    local condition = row.condition
    local r, g, b = condition.excluded and 1 or 0.8, condition.excluded and 0.55 or 0.85, 0.55
    if row.index > 1 then list:drawText(text("And"), 4, y + 8, 0.75, 0.75, 0.75, 1, UIFont.Small) end
    list:drawRectBorder(32, y + 2, 70, h - 4, 0.8, r, g, b)
    list:drawText(UIStyle.fit(text(condition.excluded and "Absent" or "Present"), 58), 38, y + 8, r, g, b, 1, UIFont.Small)
    list:drawRectBorder(108, y + 2, w - 170, h - 4, 0.6, 0.6, 0.6, 0.6)
    local style = Visuals.get(condition.id)
    if style.texture then list:drawTextureScaledAspect(style.texture, 114, y + 6, 20, 20, 1, style.r, style.g, style.b) end
    list:drawText(UIStyle.fit(Tags.label(condition.id), w - 204), 138, y + 8, 1, 1, 1, 1, UIFont.Small)
    list:drawRectBorder(w - 56, y + 2, 30, h - 4, 0.6, 0.6, 0.6, 0.6)
    list:drawText("x", w - 46, y + 8, 1, 1, 1, 1, UIFont.Small)
    return y + h
end

function Picker:apply()
    if not Tags.enabled() or closed(self.owner) then self:close(); return end
    local rule = self.rule and Tags.normalizeRule(self.rule)
    if not rule then return end
    local first
    for _, id in ipairs(self.selectionOrder) do if Tags.ruleIncludes(rule, id) then first = id; break end end
    self.onApply(rule, first)
    self:close()
end

function Picker:close()
    if self.tagChoice then self.tagChoice:close() end
    if self.list.tooltipUI then self.list.tooltipUI:setVisible(false); self.list.tooltipUI:removeFromUIManager() end
    self:setVisible(false); self:removeFromUIManager()
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
    local fontHeight = getTextManager():getFontHeight(UIFont.Small)
    local controlHeight = math.max(28, fontHeight + 10)
    local top = math.max(32, self:titleBarHeight() + 8)
    local footerY = self.height - controlHeight - 12
    self.hintY = footerY - fontHeight - 10
    local groupY = self.hintY - controlHeight - 10
    local function button(x, y, w, title, callback)
        local b = ISButton:new(x, y, w, controlHeight, title, self, callback)
        b:initialise(); b:instantiate(); UIStyle.button(b); self:addChild(b); return b
    end
    self.list = ISScrollingListBox:new(12, top, self.width - 24, math.max(40, groupY - top - 8))
    self.list:initialise(); self.list:instantiate()
    self.list.itemheight = math.max(34, getTextManager():getFontHeight(UIFont.Small) + 16)
    self.list.doDrawItem = Picker.drawRow
    self.list:setOnMouseDownFunction(self, Picker.clickRow)
    Choice.configureList(self.list, self, Picker.activate)
    local onJoypadDown = self.list.onJoypadDown
    self.list.onJoypadDown = function(list, key, data)
        local row = list.items[list.selected]
        if row and row.item.kind == "condition" and key == Joypad.XButton then
            self:toggleCondition(row.item.group, row.item.index)
        elseif row and row.item.kind == "condition" and key == Joypad.YButton then
            self:removeCondition(row.item.group, row.item.index)
        else onJoypadDown(list, key, data) end
    end
    self:addChild(self.list)
    self.addGroupButton = button(12, groupY, self.width - 24, text("AddOr"), function(owner) owner:addGroup() end)
    local w = (self.width - 48) / 3
    self.clearButton = button(12, footerY, w, text("Clear"), Picker.clearRule)
    self.cancelButton = button(24 + w, footerY, w, text("Cancel"), Picker.close)
    self.applyButton = button(36 + w * 2, footerY, w, text("Apply"), Picker.apply)
    self.dimmer = ISPanel:new(0, 0, self.width, self.height)
    self.dimmer:initialise(); self.dimmer:instantiate()
    self.dimmer.backgroundColor = {r=0,g=0,b=0,a=0.65}
    self.dimmer.onMouseDown = function() if self.tagChoice then self.tagChoice.reassertTop = true end; return true end
    self:addChild(self.dimmer); self.dimmer:setVisible(false)
    self:refreshRule()
end

function Picker:onGainJoypadFocus(data)
    ISCollapsableWindowJoypad.onGainJoypadFocus(self, data)
    if self.joypadConfigured then return end
    self.joypadConfigured = true
    self:insertNewLineOfButtons(self.list)
    self:insertNewLineOfButtons(self.addGroupButton)
    self:insertNewLineOfButtons(self.clearButton, self.cancelButton, self.applyButton)
    self.joypadIndexY, self.joypadIndex = 1, 1
    self:restoreJoypadFocus(data)
end

function Picker:onJoypadDown(key, data)
    if key == Joypad.BButton then self:close(); return end
    ISCollapsableWindowJoypad.onJoypadDown(self, key, data)
end

function Picker:prerender()
    if not Tags.enabled() or closed(self.owner) then self:close(); return end
    if self.reassertTop then
        self.reassertTop = false; self:bringToTop()
        if self.tagChoice then self.tagChoice:bringToTop(); self.tagChoice.reassertTop = true end
    end
    ISCollapsableWindowJoypad.prerender(self)
    local hint = self.validationMessage or (self.grabbedJoypad and text("ControllerHint") or "")
    self:drawText(UIStyle.fit(hint, self.width - 24), 12, self.hintY, 0.9, 0.75, 0.55, 1, UIFont.Small)
end

function Picker.open(options)
    if not Tags.enabled() then return end
    local rule, err = Tags.normalizeRule(options.rule)
    if not rule then return nil, err end
    if options.owner and options.owner.toolkitRulePicker then options.owner.toolkitRulePicker:close() end
    local w = math.min(700, getCore():getScreenWidth() - 24)
    local h = math.min(570, getCore():getScreenHeight() - 24)
    local picker = Picker:new((getCore():getScreenWidth() - w) / 2, (getCore():getScreenHeight() - h) / 2, w, h)
    picker.options, picker.conditions, picker.selectionOrder = options, {}, options.selectedTag and {options.selectedTag} or {}
    if Tags.ruleActive(rule) then
        for _, group in ipairs(Tags.ruleGroups(rule)) do
            local conditions = {}
            for _, id in ipairs(group.include) do conditions[#conditions + 1] = {id=id, excluded=false} end
            for _, id in ipairs(group.exclude) do conditions[#conditions + 1] = {id=id, excluded=true} end
            picker.conditions[#picker.conditions + 1] = conditions
        end
    end
    picker.owner, picker.onApply = options.owner, options.onApply
    picker.title, picker.resizable = options.title or text(""), false
    picker.background, picker.backgroundColor = true, {r=0.04,g=0.04,b=0.04,a=1}
    picker.playerNum = type(options.player) == "number" and options.player or options.player and options.player:getPlayerNum()
    picker:initialise(); picker:instantiate(); picker:addToUIManager()
    picker:bringToTop()
    -- The native opening mouse event may raise the owner after this callback.
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
    local joypad = picker.playerNum and JoypadState and JoypadState.players[picker.playerNum + 1]
    if joypad and setJoypadFocus then
        picker.previousFocus, picker.grabbedJoypad = joypad.focus, true
        setJoypadFocus(picker.playerNum, picker)
    end
    return picker
end

return Picker
