local InventoryClasses = require "PZSurvivorToolkit/InventoryClasses"
local Rows = require "PZSurvivorToolkit/InventoryRows"
local Membership = require "PZSurvivorToolkit/InventoryMembership"
local Search = require "PZSurvivorToolkit/InventorySearch"
require "PZSurvivorToolkit/Settings"
local UIStyle = require "PZSurvivorToolkit/UIStyle"
local Tags = require "PZSurvivorToolkit/ItemTags"
local Visuals = require "PZSurvivorToolkit/TagVisuals"
local TagRulePicker = require "PZSurvivorToolkit/TagRulePicker"
local PresetsMenu = require "PZSurvivorToolkit/TagFilterPresetsMenu"

local Toolkit = PZSurvivorToolkit
local Filter = {}
Toolkit.InventoryFilter = Filter
local patched = {}
local transferMembership

local function pack(...)
    return {n = select("#", ...), ...}
end

-- A command only enumerates/queues transfers; native execution validates them later.
-- Never retain membership across commands, frames, or nested enumerations.
local function withTransferMembership(callback, ...)
    local previous = transferMembership
    transferMembership = {parent = previous, index = {}}
    local result = pack(pcall(callback, ...))
    transferMembership = previous
    if not result[1] then error(result[2], 0) end
    return unpack(result, 2, result.n)
end

local function categoryName(category)
    return getTextOrNull("IGUI_ItemCat_" .. category) or category
end

local function hasSearch(pane)
    return Search.forPane(pane) ~= nil
end

local function tagRule(pane)
    return pane.toolkitTagRule or (pane.toolkitTag and {mode="all", include={pane.toolkitTag}, exclude={}})
end

local function tagFilterActive(pane)
    return Tags.enabled() and Tags.ruleActive(tagRule(pane))
end

local function visibleForTransfer(pane, item, membership)
    if not Toolkit.Settings.inventoryFilters() or not pane.toolkitVisibleItems then return true end
    if not pane.toolkitCategory and not tagFilterActive(pane) and not hasSearch(pane) then return true end
    -- Drag/drop calls the destination pane; its filter must not reject incoming items.
    local index = membership or transferMembership and transferMembership.index
    local fromPane = item:getContainer() == pane.inventory or Membership.contains(index, pane.inventory, item)
    return not fromPane or pane.toolkitVisibleItems[item] == true
end

local function filterGroup(group, accepts)
    local items = {}
    local first = group.cleanUIFirstActualIndex or (group.cleanUILargeStackOptimized and 1 or 2)
    for index = first, #group.items do
        local item = group.items[index]
        if accepts(item) then
            items[#items + 1] = item
        end
    end
    if #items == 0 then return end
    if #items == #group.items - first + 1 then return group end
    -- Native rows duplicate the header; CleanUI can keep a virtual header instead.
    local copy = {}
    for key, value in pairs(group) do copy[key] = value end
    local weight, equippedWeight = 0, 0
    for _, item in ipairs(items) do
        weight = weight + item:getUnequippedWeight()
        if group.equipped then equippedWeight = equippedWeight + item:getEquippedWeight() end
    end
    copy.firstItem, copy.cleanUIDisplayItem = items[1], items[1]
    copy.cat = items[1]:getDisplayCategory() or items[1]:getCategory()
    copy.realCount, copy.count, copy.weight, copy.equippedWeight = #items, #items + 1, weight, equippedWeight
    copy.cleanUIStackCountSuffix = " (" .. #items .. ")"
    copy.cleanUIWeightText, copy.cleanUITooltipWeight = nil, nil
    copy.cleanUITooltipWeightKnown = false
    if first == 2 then table.insert(items, 1, items[1]) end
    copy.items = items
    return copy
end

-- Menu choices use the complete refresh universe, never its filtered/split rows.
-- Read live instance metadata on demand; ordinary restores need no menu labels/tags.
function Filter.choices(pane, includeTags)
    local categories, tags, result = {}, {}, {}
    if not Toolkit.Settings.inventoryFilters() then return result, tags end
    local tagsEnabled = includeTags ~= false and Tags.enabled()
    for _, item in ipairs(pane.toolkitFilterItems or {}) do
        local category = item:getDisplayCategory() or item:getCategory()
        if category then categories[category] = true end
        if tagsEnabled then
            for _, id in ipairs(Tags.forItem(item)) do tags[id] = true end
        end
    end
    for category in pairs(categories) do
        result[#result + 1] = {id = category, name = categoryName(category)}
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result, tags
end

local function applyFilter(pane, selected)
    -- Later selection restores may follow stack/category changes from other mods.
    if pane.itemslist == pane.toolkitFilteredRows then pane.itemslist = pane.toolkitUnfilteredRows end
    pane.toolkitFilteredRows = nil
    pane.toolkitUnfilteredRows = pane.itemslist
    pane.toolkitVisibleItems = nil
    if not Toolkit.Settings.inventoryFilters() then return end
    -- Choices belong to the full refresh, not a later split/pinned projection.
    -- Keep physical references so changed instance categories are still live.
    if not pane.toolkitFilterItems then
        local items, seen = {}, {}
        for _, group in ipairs(pane.itemslist) do
            for _, item in ipairs(group.items or {}) do
                if not seen[item] then items[#items + 1], seen[item] = item, true end
            end
        end
        pane.toolkitFilterItems = items
    end
    local search = Search.forPane(pane)
    local filterTags = tagFilterActive(pane)
    if not pane.toolkitCategory and not filterTags and not search then return end
    local itemTags = {}
    local function tagsFor(item)
        if not itemTags[item] then itemTags[item] = Tags.forItem(item) end
        return itemTags[item]
    end
    local kept, visible, equipped = {}, {}, false
    local rule = filterTags and tagRule(pane)
    local function accepts(item)
        return (not pane.toolkitCategory or (item:getDisplayCategory() or item:getCategory()) == pane.toolkitCategory)
            and Search.matches(search, item)
            and (not filterTags or Tags.matchesRule(tagsFor(item), rule))
    end
    local remappedSelection
    for _, group in ipairs(pane.itemslist) do
        if group.type ~= "separator" then
            local shown = filterGroup(group, accepts)
            if shown then
                kept[group] = shown
                if shown ~= group and selected and selected[group.items[1]] == "group" then
                    if not remappedSelection then
                        remappedSelection = {}
                        for item, state in pairs(selected) do remappedSelection[item] = state end
                    end
                    remappedSelection[shown.items[1]] = "group"
                end
                equipped = equipped or group.equipped
                for _, item in ipairs(shown.items) do visible[item] = true end
            end
        end
    end
    pane.toolkitVisibleItems = visible
    local rows = {}
    for _, group in ipairs(pane.itemslist) do
        if kept[group] then rows[#rows + 1] = kept[group]
        elseif group.type == "separator" and equipped then rows[#rows + 1] = group end
    end
    pane.itemslist, pane.toolkitFilteredRows = rows, rows
    -- Filter before native selection restoration, so row indices match the view.
    table.wipe(pane.items)
    return remappedSelection
end

local function selectFilter(pane, category, tag, rule)
    pane.toolkitCategory, pane.toolkitTag, pane.toolkitTagRule = category, tag, rule
    pane.firstSelect = nil
    pane:setYScroll(0)
    pane.smoothScrollTargetY = nil
    pane:refreshContainer()
end

local function selectCategory(pane, category)
    selectFilter(pane, category)
end

local function selectTag(pane, id)
    selectFilter(pane, nil, id)
end

local function selectRule(pane, rule)
    local copy = Tags.normalizeRule(rule)
    if not copy then return end
    selectFilter(pane, nil, nil, Tags.ruleActive(copy) and copy or nil)
end

local function showTagRule(pane)
    pane:refreshContainer()
    local categories, items = {}, {}
    local choices = Filter.choices(pane, false)
    for _, entry in ipairs(choices) do categories[#categories + 1] = entry.id end
    for _, item in ipairs(pane.toolkitFilterItems or {}) do items[#items + 1] = item end
    TagRulePicker.open({player=pane.player, owner=pane, rule=tagRule(pane), categories=categories, items=items,
        onApply=function(rule) selectRule(pane, rule) end})
end

local function showCategories(pane, button)
    pane:refreshContainer()
    local categories, tags = Filter.choices(pane)
    local menu = ISContextMenu.get(pane.player, button:getAbsoluteX(), button:getAbsoluteY() + button:getHeight())
    local all = menu:addOption(getText("UI_PZSurvivorToolkit_all_categories"), pane, selectCategory)
    menu:setOptionChecked(all, pane.toolkitCategory == nil)
    if Tags.enabled() then
        local manage = menu:addOption(getText("UI_PZST_TagEdit_Catalog"), pane, function(target)
            require("PZSurvivorToolkit/TagEditor").open({playerNum=target.player,owner=target,items=target.toolkitFilterItems})
        end)
        manage.pzstKey = "manageTags"
        local combined = menu:addOption(getText("UI_PZST_TagRule"), pane, showTagRule)
        menu:setOptionChecked(combined, Tags.ruleActive(pane.toolkitTagRule))
        PresetsMenu.add(menu, {owner=pane, player=pane.player, rule=tagRule(pane),
            onApply=function(rule) selectRule(pane, rule) end})
        local entries = {}
        for id in pairs(tags) do entries[#entries + 1] = {id = id, label = Tags.label(id)} end
        table.sort(entries, function(a, b) return a.label < b.label end)
        local root = menu:addOption(getText("UI_PZST_Tags"))
        local submenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(root, submenu)
        for _, entry in ipairs(entries) do
            local option = submenu:addOption(entry.label, pane, selectTag, entry.id)
            local style = Visuals.get(entry.id)
            option.iconTexture = style.texture
            if style.texture then option.color = {r = style.r, g = style.g, b = style.b} end
            submenu:setOptionChecked(option, entry.id == pane.toolkitTag)
        end
        menu:setOptionChecked(all, pane.toolkitCategory == nil and not tagFilterActive(pane))
    end
    for _, category in ipairs(categories) do
        local option = menu:addOption(category.name, pane, selectCategory, category.id)
        menu:setOptionChecked(option, pane.toolkitCategory == category.id)
    end
    menu.mouseOver = 1
    if JoypadState.players[pane.player + 1] then
        menu.origin = JoypadState.players[pane.player + 1].focus
        setJoypadFocus(pane.player, menu)
    end
end

local function updateButton(pane)
    local header = pane.typeHeader
    if not header then return end
    local button = pane.toolkitCategoryButton
    if not button then
        button = ISButton:new(0, 0, 20, 20, "v", pane, showCategories)
        button:initialise()
        UIStyle.button(button)
        button:setScrollWithParent(false)
        pane:addChild(button)
        pane.toolkitCategoryButton = button
        local draw = header.drawTextureScaled
        header.drawTextureScaled = function(h, texture, x, ...)
            if button:getIsVisible() and (texture == pane.sortAscIcon or texture == pane.sortDescIcon) then
                x = x - button:getWidth() - 2
            end
            return draw(h, texture, x, ...)
        end
    end
    local enabled = Toolkit.Settings.inventoryFilters()
    local size = math.max(16, pane.headerHgt or 16)
    local visible = enabled and pane.mode == "details" and header:getIsVisible() and header:getWidth() > size * 2
    button:setVisible(visible)
    if not visible then return end
    button:setX(header:getX() + header:getWidth() - size - 2)
    button:setY(header:getY())
    button:setWidth(size)
    button:setHeight(size)
    button.tooltip = getText("UI_PZSurvivorToolkit_category_filter") .. ": "
        .. (tagFilterActive(pane) and pane.toolkitTagRule and getText("UI_PZST_TagRule")
            or Tags.enabled() and pane.toolkitTag and Tags.label(pane.toolkitTag)
            or pane.toolkitCategory and categoryName(pane.toolkitCategory) or getText("UI_PZSurvivorToolkit_all_categories"))
    button.textColor = (pane.toolkitCategory or tagFilterActive(pane)) and {r = 1, g = 0.65, b = 0.3, a = 1}
        or {r = 0.94, g = 0.90, b = 0.83, a = 1}
end

local function install(class)
    if not class or patched[class] then return end
    patched[class] = true
    local refresh = class.refreshContainer
    class.refreshContainer = function(self, ...)
        local membership = transferMembership
        while membership do
            membership.index = {}
            membership = membership.parent
        end
        self.toolkitFilterItems = nil
        return refresh(self, ...)
    end
    local restore, prerender, transfer = class.restoreSelection, class.prerender, class.transferItemsByWeight
    class.restoreSelection = function(self, selected)
        local saved = applyFilter(self, selected) or selected
        local result = restore(self, saved)
        -- Keep mod ordering/filter hooks, then publish indices for the final view.
        if self.mode == "details" then Rows.restoreSelection(self, saved) end
        return result
    end
    class.prerender = function(self, ...)
        local enabled, filtersEnabled = Tags.enabled(), Toolkit.Settings.inventoryFilters()
        if self.toolkitTagsEnabled ~= enabled or self.toolkitFiltersEnabled ~= filtersEnabled then
            self.toolkitTagsEnabled, self.toolkitFiltersEnabled = enabled, filtersEnabled
            if self.toolkitCategory or self.toolkitTag or self.toolkitTagRule or self.toolkitVisibleItems then self:refreshContainer() end
            if not filtersEnabled and self.toolkitRulePicker then self.toolkitRulePicker:close() end
        end
        local result = prerender(self, ...)
        updateButton(self)
        return result
    end
    class.transferItemsByWeight = function(self, items, container, ...)
        if self.toolkitVisibleItems or (Toolkit.Settings.inventoryFilters()
            and (self.toolkitCategory or tagFilterActive(self) or hasSearch(self))) then
            self:refreshContainer()
        end
        if self.toolkitVisibleItems then
            local filtered = {}
            local membership = {}
            for _, item in ipairs(items) do
                if visibleForTransfer(self, item, membership) then filtered[#filtered + 1] = item end
            end
            items = filtered
        end
        return transfer(self, items, container, ...)
    end
end

local function installClasses()
    InventoryClasses.panes(install)
end

local function installQuickTransfers()
    local handler = ISInventoryPageTransferHandler
    if not handler or patched[handler] then return end
    patched[handler] = true
    local canTransfer = handler.canTransferItem
    handler.canTransferItem = function(item, container, player, ...)
        if item and player then
            local playerNum = player:getPlayerNum()
            local pane = getPlayerInventory(playerNum).inventoryPane
            if pane and not visibleForTransfer(pane, item) then return false end
            pane = getPlayerLoot(playerNum).inventoryPane
            if pane and not visibleForTransfer(pane, item) then return false end
        end
        return canTransfer(item, container, player, ...)
    end
    -- Nearby transfers and Move To Floor queue actions without transferItemsByWeight.
    for _, name in ipairs({"transferSameType", "transferSameCategory", "moveToFloor"}) do
        local original = handler[name]
        handler[name] = function(page, ...)
            page.inventoryPane:refreshContainer()
            return withTransferMembership(original, page, ...)
        end
    end
    -- These enumerate the same eligibility predicate without executing transfers.
    for _, name in ipairs({"getQuickTransferItems", "showTransferMenu"}) do
        local original = handler[name]
        if original then
            handler[name] = function(...) return withTransferMembership(original, ...) end
        end
    end
    handler.takeSameType = handler.transferSameType
    handler.takeSameCategory = handler.transferSameCategory
end

local function installSortMenu()
    local handler = ISInventoryCommonHandler_SortMenu
    if not handler or patched[handler] then return end
    patched[handler] = true
    local perform = handler.perform
    handler.perform = function(self, ...)
        local result = perform(self, ...)
        local window = self:getWindow()
        if window and Toolkit.Settings.inventoryFilters() then
            -- Keep Clear filter accessible when the Category header is hidden.
            getPlayerContextMenu(self.playerNum):addOption(getText("UI_PZSurvivorToolkit_category_filter"),
                window.inventoryPane, showCategories, self.control)
        end
        return result
    end
end

function Filter.settingsChanged()
    for playerNum = 0, getNumActivePlayers() - 1 do
        for _, page in ipairs({getPlayerInventory(playerNum), getPlayerLoot(playerNum)}) do
            if page.inventoryPane then page.inventoryPane:refreshContainer() end
        end
    end
end

Events.OnGameStart.Add(function()
    installClasses()
    installQuickTransfers()
    installSortMenu()
    InventoryClasses.onToggle(installClasses)
end)
