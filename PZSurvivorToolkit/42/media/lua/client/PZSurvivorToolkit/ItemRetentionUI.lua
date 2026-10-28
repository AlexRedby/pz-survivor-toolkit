local Retention = require "PZSurvivorToolkit/ItemRetention"
local Protection = require "PZSurvivorToolkit/InventoryTransferProtection"
local Classes = require "PZSurvivorToolkit/InventoryClasses"
local request = 0
local itemsIn = Protection.items
local function refresh(playerNum)
    for _, getter in ipairs({getPlayerInventory, getPlayerLoot}) do
        local page = getter(playerNum)
        if page and page.inventoryPane then page.inventoryPane:refreshContainer() end
    end
end

function Retention.setRetained(playerNum, entries, value)
    if type(value) ~= "boolean" then return end
    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() then return end
    local locators = {}
    local function send()
        if #locators == 0 then return end
        request = request + 1
        sendClientCommand(player, Retention.MODULE, "Set", {request=request, retained=value, items=locators})
        locators = {}
    end
    for _, item in ipairs(itemsIn(entries)) do
        if isClient() then
            local locator = Retention.locate(item, player)
            if locator then locators[#locators + 1] = locator end
            if #locators == Retention.MAX_ITEMS then send() end
        else Retention.apply(item, value) end
    end
    if isClient() then send(); return request end
    refresh(playerNum)
end

function Retention.toggle(playerNum, entries)
    local items, value = itemsIn(entries), false
    if #items == 0 then return end
    for _, item in ipairs(items) do if not Retention.isRetained(item) then value = true; break end end
    return Retention.setRetained(playerNum, items, value)
end

Events.OnFillInventoryObjectContextMenu.Add(function(playerNum, context, rows)
    local items, retained = itemsIn(rows), true
    if #items == 0 then return end
    for _, item in ipairs(items) do if not Retention.isRetained(item) then retained = false; break end end
    local key = retained and "release_item" or "retain_item"
    local option = context:addOption(getText("UI_PZSurvivorToolkit_" .. key), playerNum, Retention.toggle, items)
    option.pzstCategory, option.pzstKey = "transfer", retained and "releaseItem" or "retainItem"
    option.iconTexture = getTexture("media/textures/PZSurvivorToolkit/item_retained.png")
    option.toolTip = ISInventoryPaneContextMenu.addToolTip()
    option.toolTip.description = getText("UI_PZSurvivorToolkit_" .. key .. "_tip")
end)

-- Keep the original selection's intent before flattening. Native timed actions
-- (craft inputs/tools included) are deliberately outside this UI mass-move gate.
function Retention.filterTransfer(entries, deliberate)
    if not entries or deliberate then return entries end
    local out, changed = {}, false
    for _, item in ipairs(itemsIn(entries)) do
        if Protection.allowsAutomatic(item) then out[#out + 1] = item else changed = true end
    end
    return changed and out or entries
end
local paneHooks, selectionHooks = {}, {}
local function installPane(class)
    if not class then return end
    local hooks = selectionHooks[class] or {}
    selectionHooks[class] = hooks
    for _, name in ipairs({"onContext", "doGrabOnJoypadSelected"}) do
        local original = class[name]
        if type(original) == "function" and original ~= hooks[name] then
            local wrapper = function(pane, ...)
                local index = name == "onContext" and pane.buttonOption
                    or pane.joyselection and pane.joyselection + 1
                local row = index and pane.items and pane.items[index]
                return Protection.withSelection(row and {row} or {}, pane.player or 0, original, pane, ...)
            end
            hooks[name], class[name] = wrapper, wrapper
        end
    end
    if paneHooks[class] then return end
    paneHooks[class] = true
    local transfer = class.transferItemsByWeight
    if transfer then
        class.transferItemsByWeight = function(pane, entries, destination, ...)
            local drag = ISMouseDrag and ISMouseDrag.dragging
            local deliberate = drag and Protection.containsSelection(drag, entries)
            return transfer(pane, Retention.filterTransfer(entries, deliberate), destination, ...)
        end
    end
end
local actionHooks = {}
local actionNames = {"onGrabItems", "onGrabHalfItems", "onGrabOneItems", "onPutItems", "onDropItems", "onMoveItemsTo"}
local menuHook
local function rememberMenu(context, selected, playerNum, seen)
    if not context or seen[context] then return end
    seen[context] = true
    for _, option in ipairs(context.options or {}) do
        for _, name in ipairs(actionNames) do
            if actionHooks[name] and option.onSelect == actionHooks[name]
                and ISInventoryPaneContextMenu[name] == actionHooks[name]
                and type(option.target) == "table" and Protection.containsSelection(selected, option.target) then
                Protection.rememberSelection(option.target, playerNum)
            end
        end
        if option.subOption and context.getSubMenu then
            rememberMenu(context:getSubMenu(option.subOption), selected, playerNum, seen)
        end
    end
end

-- Only the installed owner closure is recognized. A replacement callback must
-- not inherit the action-queue integration's reviewed-wrapper permission.
function Retention.isContextWrapper(menu, name)
    return menu == ISInventoryPaneContextMenu and type(actionHooks[name]) == "function"
        and menu[name] == actionHooks[name]
end
local function install()
    Classes.panes(installPane)
    local menu = ISInventoryPaneContextMenu
    if menu then
        for _, name in ipairs(actionNames) do
            local original = menu[name]
            if type(original) == "function" and actionHooks[name] == nil then
                local wrapper = function(entries, ...)
                    local playerNum = name == "onMoveItemsTo" and select(2, ...) or select(1, ...)
                    local deliberate = type(entries) == "table" and Protection.selectionAllowsStuck(entries, playerNum)
                    return original(Retention.filterTransfer(entries, deliberate), ...)
                end
                menu[name], actionHooks[name] = wrapper, wrapper
            end
        end
        if type(menu.createMenu) == "function" and menu.createMenu ~= menuHook then
            local original = menu.createMenu
            menuHook = function(playerNum, inInventory, rows, ...)
                local selected = itemsIn(rows)
                local context = original(playerNum, inInventory, rows, ...)
                rememberMenu(context, selected, playerNum, {})
                return context
            end
            menu.createMenu = menuHook
        end
    end
    local handler = ISInventoryPageTransferHandler
    if handler and type(handler.canTransferItem) == "function" and actionHooks[handler] ~= handler.canTransferItem then
        local original = handler.canTransferItem
        local wrapper = function(item, ...)
            if item and not Protection.allowsAutomatic(item) then return false end
            return original(item, ...)
        end
        handler.canTransferItem, actionHooks[handler] = wrapper, wrapper
    end
end
Retention.install = install
Events.OnGameStart.Add(install)
Events.OnCreatePlayer.Add(install)
Classes.onToggle(install)

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= Retention.MODULE or type(args) ~= "table" then return end
    if command == "Result" then Retention.lastResult = args; return end
    if command ~= "State" or type(args.items) ~= "table" or type(args.retained) ~= "boolean" then return end
    for playerNum = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(playerNum)
        if player then
            for _, locator in ipairs(args.items) do
                if not locator.inv or player:getOnlineID() == args.owner then
                    local item = Retention.resolve(player, locator)
                    if item then Retention.apply(item, args.retained) end
                end
            end
            refresh(playerNum)
        end
    end
end)
return Retention
