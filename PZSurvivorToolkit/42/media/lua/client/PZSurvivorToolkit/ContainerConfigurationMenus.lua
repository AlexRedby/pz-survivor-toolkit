-- Quartermaster owns the world-container editor; carried containers retain their native menus.
local Classes = require 'PZSurvivorToolkit/InventoryClasses'
local Appearance = require 'PZSurvivorToolkit/ContainerAppearance'
local Menus = {}
local installed = setmetatable({}, {__mode = 'k'})
local renameCallbacks = {}

function Menus.target(page, button)
    if not page or page.onCharacter or not button or not button.inventory then return end
    local ok, obj, ci, container = pcall(function()
        local inventory = button.inventory
        if inventory:getContainingItem() then return end
        local parent = inventory:getParent()
        if not parent or not instanceof(parent, 'IsoObject')
            or instanceof(parent, 'BaseVehicle') or instanceof(parent, 'IsoDeadBody')
            or instanceof(parent, 'IsoWorldInventoryObject') then return end
        local kind = inventory:getType()
        if kind == 'floor' or kind == 'inventorymale' or kind == 'inventoryfemale' then return end
        if not parent:getSquare() or parent:getObjectIndex() < 0 then return end
        if not LootSorter or not LootSorter.containerIndex then return end
        local index = LootSorter.containerIndex(parent, inventory)
        if index == nil then return end
        return parent, index, inventory
    end)
    if ok then return obj, ci, container end
end

function Menus.allowed(obj, playerNum)
    local player = getSpecificPlayer(playerNum)
    local square = obj:getSquare()
    if not square or not LootSorter.canLootSquare(square, player) then return false end
    -- Keep the native container-button rename permission, in addition to the sorting gate.
    return SafeHouse.isSafehouseAllowInteract(square, player) and true or false
end

local function rememberRename(class)
    if class and type(class.onRenameContainer) == 'function' then
        renameCallbacks[class.onRenameContainer] = true
    end
end

local function removeRename(context, container)
    local changed = false
    for index = #context.options, 1, -1 do
        local option = context.options[index]
        if option.target == container and renameCallbacks[option.onSelect] then
            table.remove(context.options, index)
            if context.optionPool then table.insert(context.optionPool, option) end
            context.numOptions = context.numOptions - 1
            changed = true
        end
    end
    if changed then
        for index, option in ipairs(context.options) do option.id = index end
        context:calcHeight()
    end
end

function Menus.decorate(page, button)
    local obj, ci, container = Menus.target(page, button)
    if not obj then return false end
    -- A supported but forbidden target must not fall through to BC's less restrictive editor.
    if not Menus.allowed(obj, page.player) then return true end
    local context = getPlayerContextMenu(page.player)
    if not context then return true end
    -- Without BC the unified picker contains sorting only, so keep the native name editor.
    if Appearance.available() then removeRename(context, container) end
    if LootSorter.addBoxOptions then LootSorter.addBoxOptions(context, obj, ci, '', page.player) end
    return true
end

local function installPage(class)
    if not class then return end
    rememberRename(class)
    if installed[class] or type(class.onBackpackRightMouseDown) ~= 'function' then return end
    installed[class] = true
    local original = class.onBackpackRightMouseDown
    class.onBackpackRightMouseDown = function(button, ...)
        local result = original(button, ...)
        -- The callback's self is an actual container button, with the native two-level parent chain.
        local page = button.parent and button.parent.parent
        Menus.decorate(page, button)
        return result
    end
end

local bcInstalled
function Menus.install()
    installPage(ISInventoryPage)
    installPage(CleanUI_Clean_ISInventoryPage)
    installPage(CleanUI_Vanilla_ISInventoryPage)
    if not bcInstalled and getActivatedMods():contains('EURY_CONTAINERS') then
        local customize = require 'BetterContainers/Customize/ContextMenu'
        local original = customize.handleCustomiserOptions
        customize.handleCustomiserOptions = function(page, button, parent)
            if Menus.decorate(page, button) then return end
            return original(page, button, parent)
        end
        bcInstalled = true
    end
end

-- Every script and BC's installation run before these game-start hooks. The CleanUI callback also
-- installs the inactive native class, so a later UI-mode switch keeps the same entry point.
Classes.onToggle(Menus.install)
Events.OnGameStart.Add(Menus.install)
return Menus
