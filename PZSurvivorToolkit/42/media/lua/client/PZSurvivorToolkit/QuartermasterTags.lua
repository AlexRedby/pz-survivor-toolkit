local Tags = require "PZSurvivorToolkit/ItemTags"
local Categories = require "PZSurvivorToolkit/ItemCategories"
local Visuals = require "PZSurvivorToolkit/TagVisuals"
local Rules = require "PZSurvivorToolkit/QuartermasterTagRuleClient"
local RulePicker = require "PZSurvivorToolkit/TagRulePicker"

-- Tag projection and rule helpers. The owned Picker constructs and dispatches its UI directly.
local Adapter = {}
PZSurvivorToolkit.QuartermasterTags = Adapter

function Adapter.isTagView(picker)
    return Tags.enabled() and picker.mode == "cats" and picker.toolkitTagView
end

function Adapter.categories(source, selectedCats)
    local result, seen = {}, {}
    for _, category in ipairs(source) do
        result[#result + 1], seen[category] = category, true
    end
    -- A saved category may disappear from the installed scripts; keep it available for refinement.
    for category, selected in pairs(selectedCats) do
        if selected and not seen[category] then result[#result + 1] = category end
    end
    table.sort(result)
    return result
end

function Adapter.state(selectedCats, row)
    local checked = 0
    for _, category in ipairs(row.categories) do
        if selectedCats[category] then checked = checked + 1 end
    end
    return checked, #row.categories
end

function Adapter.selectRow(selectedCats, row, selected)
    for _, category in ipairs(row.categories) do selectedCats[category] = selected or nil end
end

function Adapter.openRule(picker, rule, onApply)
    RulePicker.open({player = getSpecificPlayer(picker.playerNum or 0), owner = picker,
        rule = rule, categories = picker:activeList(), scriptItems = Rules.scriptItems(),
        title = getText("UI_PZST_QMTagRuleTitle"), onApply = function(value)
            picker.toolkitTagRule = Tags.normalizeRule(value)
            picker.toolkitTagRuleTouched = true
            if onApply then onApply() end
        end})
end

function Adapter.rows(categoryList, catalog)
    local rows, byTag, groups = {}, {}, {}
    for _, script in ipairs(catalog) do
        local category = Categories.forScript(script)
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

function Adapter.drawRow(list, y, item)
    local row, picker = item.item, list.target
    local checked, total = Adapter.state(picker.selectedCats, row)
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

function Adapter.presetArgs(picker, args)
    if picker.targetKind ~= "preset" or picker.toolkitTagRuleTouched or Rules.presetsSynced() then
        args.pzstTagRule = Tags.normalizeRule(picker.toolkitTagRule)
    end
    return args
end

return Adapter
