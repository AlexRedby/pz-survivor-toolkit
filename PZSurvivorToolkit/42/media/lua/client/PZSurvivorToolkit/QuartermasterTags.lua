local Tags = require "PZSurvivorToolkit/ItemTags"
local Categories = require "PZSurvivorToolkit/ItemCategories"
local Visuals = require "PZSurvivorToolkit/TagVisuals"
local Rules = require "PZSurvivorToolkit/QuartermasterTagRuleClient"
local RulePicker = require "PZSurvivorToolkit/TagRulePicker"
local AppearanceControls = require "PZSurvivorToolkit/ContainerAppearanceControls"
require "LootSorter_Categories"

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

function Adapter.openRule(picker, rule, onApply, selectedTag)
    RulePicker.open({player = getSpecificPlayer(picker.playerNum or 0), owner = picker,
        selectedTag = selectedTag,
        rule = rule, categories = picker:activeList(),
        tagSources = function() return Adapter.catalog(picker).tagSources end,
        title = getText("UI_PZST_QMTagRuleTitle"), onApply = function(value, firstSelectedTag)
            picker.toolkitTagRule = Tags.normalizeRule(value)
            picker.toolkitTagRuleTouched = true
            if onApply then onApply(picker.toolkitTagRule) end
            AppearanceControls.select(picker, "tag", firstSelectedTag)
        end})
end

-- Loaded scripts and their tag projection are a snapshot for this window. Text/selection filters
-- consume it, and the tag chooser reuses the projection. No session-wide cache survives a reopen.
function Adapter.catalog(picker)
    if picker.toolkitTagCatalog then return picker.toolkitTagCatalog end
    local catalog = {tagSources = {}, groups = {}, visibleCategories = {}}
    local categorySet, sourceSet = {}, {}
    local scripts = getAllItems and getAllItems()
    for index = 0, (scripts and scripts:size() or 0) - 1 do
        local script = scripts:get(index)
        if script then
            local visible = LootSorter.isListableScriptItem(script)
            local routable = not script.getObsolete or not script:getObsolete()
            local tags, category
            if routable then
                tags = Tags.forScriptItem(script)
                category = tags.legacyCategory
            elseif visible then
                -- Preserve the category API's fail-open policy for incomplete script objects.
                pcall(function() category = Categories.forScript(script) end)
            end
            if visible and category and category ~= "" and not categorySet[category] then
                categorySet[category] = true
                catalog.visibleCategories[#catalog.visibleCategories + 1] = category
            end
            if tags then
                -- The chooser uses the first ID as a fallback family when no schema root matches.
                -- Keep that order while collapsing the repeated script projections.
                local sourceKey = table.concat(tags, "\0")
                if not sourceSet[sourceKey] then
                    sourceSet[sourceKey] = true
                    catalog.tagSources[#catalog.tagSources + 1] = tags
                end
                if category then
                    local group = catalog.groups[category] or {count = 0, tags = {}}
                    catalog.groups[category] = group
                    group.count = group.count + 1
                    local seen = {}
                    for _, id in ipairs(tags) do
                        if not seen[id] then group.tags[id] = (group.tags[id] or 0) + 1; seen[id] = true end
                    end
                end
            end
        end
    end
    table.sort(catalog.visibleCategories)
    picker.toolkitTagCatalog = catalog
    return catalog
end

Adapter.ruleSummary = RulePicker.summary

local function sameCategories(left, right)
    if not left or #left ~= #right then return false end
    for i, category in ipairs(left) do if category ~= right[i] then return false end end
    return true
end

function Adapter.rows(picker, categoryList)
    local catalog = Adapter.catalog(picker)
    if sameCategories(catalog.categories, categoryList) then return catalog.rows end
    local rows, byTag = {}, {}
    for _, category in ipairs(categoryList) do
        local members, ids = catalog.groups[category], {}
        if members then
            ids = members.tags
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
            if not members or members.tags[id] == members.count then
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
    table.sort(rows, function(a, b) return a.label < b.label end)
    catalog.categories, catalog.rows = categoryList, rows
    return rows
end

function Adapter.drawRow(list, y, item)
    local row, picker = item.item, list.target
    local h, w = item.height, list:getWidth()
    local scroll = list:getYScroll()
    if y + scroll + h < 0 or y + scroll >= list:getHeight() then return y + h end
    local checked, total = Adapter.state(picker.selectedCats, row)
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
