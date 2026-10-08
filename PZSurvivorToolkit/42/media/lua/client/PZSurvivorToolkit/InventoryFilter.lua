require "PZSurvivorToolkit/Settings"

local Toolkit = PZSurvivorToolkit
local Filter = {}
Toolkit.InventoryFilter = Filter
local patched = {}

local function categoryName(category)
    return getTextOrNull("IGUI_ItemCat_" .. category) or category
end

local function hasSearch(pane)
    local mode = pane.searchMode or "name"
    return (mode ~= "category" and pane.searchText and pane.searchText ~= "")
        or (mode ~= "name" and pane.searchCategoryText and pane.searchCategoryText ~= "")
end

local function visibleForTransfer(pane, item)
    if not Toolkit.Settings.inventoryFilters() or not pane.toolkitVisibleItems then return true end
    -- Drag/drop calls the destination pane; its filter must not reject incoming items.
    local fromPane = item:getContainer() == pane.inventory or pane.inventory:getItems():contains(item)
    return not fromPane or pane.toolkitVisibleItems[item] == true
end

local function applyFilter(pane)
    pane.toolkitCategories = {}
    pane.toolkitVisibleItems = nil
    if not Toolkit.Settings.inventoryFilters() then return end
    local categories, kept, visible, equipped = {}, {}, {}, false
    local search = hasSearch(pane)
    for _, group in ipairs(pane.itemslist) do
        if group.type ~= "separator" then
            local category = group.cat
            if category then categories[category] = true end
            if (not pane.toolkitCategory or category == pane.toolkitCategory)
                and (not search or group.matchesSearch) then
                kept[group] = true
                equipped = equipped or group.equipped
                for _, item in ipairs(group.items) do visible[item] = true end
            end
        end
    end
    for category in pairs(categories) do
        pane.toolkitCategories[#pane.toolkitCategories + 1] = {id = category, name = categoryName(category)}
    end
    table.sort(pane.toolkitCategories, function(a, b) return a.name < b.name end)
    if not pane.toolkitCategory and not search then return end
    pane.toolkitVisibleItems = visible
    local rows = {}
    for _, group in ipairs(pane.itemslist) do
        if kept[group] or (group.type == "separator" and equipped) then rows[#rows + 1] = group end
    end
    pane.itemslist = rows
    -- Filter before native selection restoration, so row indices match the view.
    table.wipe(pane.items)
end

local function selectCategory(pane, category)
    pane.toolkitCategory = category
    pane.firstSelect = nil
    pane:setYScroll(0)
    pane.smoothScrollTargetY = nil
    pane:refreshContainer()
end

local function showCategories(pane, button)
    pane:refreshContainer()
    local menu = ISContextMenu.get(pane.player, button:getAbsoluteX(), button:getAbsoluteY() + button:getHeight())
    local all = menu:addOption(getText("UI_PZSurvivorToolkit_all_categories"), pane, selectCategory)
    menu:setOptionChecked(all, pane.toolkitCategory == nil)
    for _, category in ipairs(pane.toolkitCategories) do
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
        .. (pane.toolkitCategory and categoryName(pane.toolkitCategory) or getText("UI_PZSurvivorToolkit_all_categories"))
    button.textColor = pane.toolkitCategory and {r = 0.3, g = 1, b = 0.3, a = 1} or {r = 1, g = 1, b = 1, a = 1}
end

local function install(class)
    if not class or patched[class] then return end
    patched[class] = true
    local restore, prerender, transfer = class.restoreSelection, class.prerender, class.transferItemsByWeight
    class.restoreSelection = function(self, selected)
        applyFilter(self)
        return restore(self, selected)
    end
    class.prerender = function(self, ...)
        local result = prerender(self, ...)
        updateButton(self)
        return result
    end
    class.transferItemsByWeight = function(self, items, container, ...)
        if Toolkit.Settings.inventoryFilters() and (self.toolkitCategory or hasSearch(self)) then
            self:refreshContainer()
        end
        if self.toolkitVisibleItems then
            local filtered = {}
            for _, item in ipairs(items) do
                if visibleForTransfer(self, item) then filtered[#filtered + 1] = item end
            end
            items = filtered
        end
        return transfer(self, items, container, ...)
    end
end

local function installClasses()
    install(ISInventoryPane)
    install(CleanUI_Clean_ISInventoryPane)
    install(CleanUI_Vanilla_ISInventoryPane)
end

local function installQuickTransfers()
    local handler = ISInventoryPageTransferHandler
    if not handler or patched[handler] then return end
    patched[handler] = true
    local canTransfer = handler.canTransferItem
    handler.canTransferItem = function(item, container, player, ...)
        if item and player then
            for _, page in ipairs({getPlayerInventory(player:getPlayerNum()), getPlayerLoot(player:getPlayerNum())}) do
                if page.inventoryPane and not visibleForTransfer(page.inventoryPane, item) then return false end
            end
        end
        return canTransfer(item, container, player, ...)
    end
    -- Nearby transfers and Move To Floor queue actions without transferItemsByWeight.
    for _, name in ipairs({"transferSameType", "transferSameCategory", "moveToFloor"}) do
        local original = handler[name]
        handler[name] = function(page, ...)
            page.inventoryPane:refreshContainer()
            return original(page, ...)
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
    if CleanUI_RegisterInventoryUiToggleCallback then
        CleanUI_RegisterInventoryUiToggleCallback(installClasses)
    end
end)
