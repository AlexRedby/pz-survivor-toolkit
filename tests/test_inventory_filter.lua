require = function() end
table.wipe = function(t) for k in pairs(t) do t[k] = nil end end
local enabled = true
PZSurvivorToolkit = {Settings = {inventoryFilters = function() return enabled end}}
local starts, toggles = {}, {}
Events = {OnGameStart = {Add = function(fn) starts[#starts + 1] = fn end}}
CleanUI_RegisterInventoryUiToggleCallback = function(fn) toggles[#toggles + 1] = fn; fn() end
getText = function(key) return key end
getTextOrNull = function(key) if key == 'IGUI_ItemCat_Tool' then return 'Tools' end end
JoypadState = {players = {}}
local function button()
    return setmetatable({}, {__index = function(_, name)
        if name == 'getHeight' then return function() return 20 end end
        if name == 'getAbsoluteX' or name == 'getAbsoluteY' then return function() return 0 end end
        return function() end
    end})
end
ISButton = {new = function(_, _, _, _, _, _, target, callback)
    local b = button(); b.target, b.callback = target, callback; return b
end}
local menu
ISContextMenu = {get = function()
    menu = {options = {}, setOptionChecked = function(_, option, checked) option.checked = checked end}
    function menu:addOption(name, target, callback, arg)
        local option = {name = name, target = target, callback = callback, arg = arg}
        self.options[#self.options + 1] = option; return option
    end
    return menu
end}
local hammer, beans, screwdriver, modItem = {}, {}, {}, {}
local source, incomingSource = {}, {}
for _, item in ipairs({hammer, beans, screwdriver, modItem}) do
    item.getContainer = function() return source end
end
source.getItems = function() return {contains = function(_, item) return item:getContainer() == source end} end
local groups = {
    {cat = 'Food', name = 'beans', items = {beans, beans}, matchesSearch = false},
    {cat = 'Tool', name = 'hammer', items = {hammer, hammer}, matchesSearch = true},
    {cat = 'Tool', name = 'screwdriver', items = {screwdriver, screwdriver}, matchesSearch = false},
    {cat = 'ModCategory', name = 'mod item', items = {modItem, modItem}, matchesSearch = false}
}
local class = {}
ISInventoryPageTransferHandler = {
    canTransferItem = function(item) return item ~= nil end,
    transferSameType = function(page) return 'type' end,
    transferSameCategory = function(page) return 'category' end,
    moveToFloor = function(page) return 'floor' end
}
function class:restoreSelection(saved)
    for row, group in ipairs(self.itemslist) do
        if saved[group.items[1]] then self.selected[row] = group end
    end
end
function class:refreshContainer()
    local saved = self.saved or {}
    self.itemslist, self.selected = {}, {}
    for _, group in ipairs(groups) do self.itemslist[#self.itemslist + 1] = group end
    self:restoreSelection(saved)
end
function class:prerender() return 'native' end
function class:transferItemsByWeight(items, container, token) self.transferred = items; return token end
ISInventoryPane, CleanUI_Clean_ISInventoryPane, CleanUI_Vanilla_ISInventoryPane = class, class, {}
for name, fn in pairs(class) do CleanUI_Vanilla_ISInventoryPane[name] = fn end
dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/InventoryFilter.lua')
starts[1]()
local wrapped = class.restoreSelection
starts[1](); toggles[1]()
assert(class.restoreSelection == wrapped, 'duplicate wrapper')
local pane = setmetatable({items = {}, saved = {[hammer] = true, [beans] = true}, player = 0,
    inventory = source,
    setYScroll = function() end, mode = 'details', headerHgt = 20, addChild = function() end,
    typeHeader = {getIsVisible = function() return true end, getWidth = function() return 140 end,
        getX = function() return 200 end, getY = function() return 0 end}}, {__index = class})
pane:refreshContainer()
assert(#pane.itemslist == 4 and #pane.toolkitCategories == 3)
pane.toolkitCategory = 'Tool'
pane:refreshContainer()
assert(#pane.itemslist == 2 and pane.itemslist[1].items[1] == hammer)
assert(pane.selected[1] == groups[2] and not pane.selected[2], 'selection moved onto another item')
assert(#pane.toolkitCategories == 3, 'category choices reduced by active filter')
pane.searchMode, pane.searchText = 'name', 'hammer'
pane:refreshContainer()
assert(#pane.itemslist == 1)
assert(pane:transferItemsByWeight({beans, hammer, screwdriver}, {}, 'native result') == 'native result')
assert(#pane.transferred == 1 and pane.transferred[1] == hammer, 'bulk transfer included hidden items')
local incoming = {getContainer = function() return incomingSource end}
pane:transferItemsByWeight({incoming}, source)
assert(#pane.transferred == 1 and pane.transferred[1] == incoming, 'destination filter blocked incoming drag')
local page = {inventoryPane = pane}
getPlayerInventory = function() return page end
getPlayerLoot = function() return {inventoryPane = {inventory = incomingSource}} end
local player = {getPlayerNum = function() return 0 end}
assert(ISInventoryPageTransferHandler.transferSameType(page) == 'type')
assert(ISInventoryPageTransferHandler.transferSameCategory(page) == 'category')
assert(ISInventoryPageTransferHandler.moveToFloor(page) == 'floor')
assert(ISInventoryPageTransferHandler.canTransferItem(hammer, {}, player))
assert(not ISInventoryPageTransferHandler.canTransferItem(beans, {}, player), 'nearby/floor path included hidden item')
assert(not ISInventoryPageTransferHandler.canTransferItem(nil, {}, player))
assert(ISInventoryPageTransferHandler.canTransferItem(hammer, {}, nil), "CleanUI hover passes no player")
assert(ISInventoryPageTransferHandler.takeSameType == ISInventoryPageTransferHandler.transferSameType)
assert(ISInventoryPageTransferHandler.takeSameCategory == ISInventoryPageTransferHandler.transferSameCategory)
groups[2].matchesSearch = false
pane:refreshContainer()
assert(#pane.itemslist == 0 and next(pane.selected) == nil, 'zero matches must be empty')
pane.searchMode, pane.searchText, pane.searchCategoryText = 'category', nil, 'missing'
pane:refreshContainer(); assert(#pane.itemslist == 0)
pane.searchMode, pane.searchText = 'both', 'hammer'
pane:refreshContainer(); assert(#pane.itemslist == 0)
pane.searchText, pane.searchCategoryText = nil, nil
pane.toolkitCategory = 'Tool'
pane:refreshContainer(); assert(#pane.itemslist == 2)
assert(pane:prerender() == 'native')
local b = pane.toolkitCategoryButton
b.callback(b.target, b)
assert(#menu.options == 4 and menu.options[1].name == 'UI_PZSurvivorToolkit_all_categories')
assert(menu.options[4].name == 'Tools' and menu.options[4].checked)
pane.firstSelect = 3
menu.options[1].callback(menu.options[1].target, menu.options[1].arg)
assert(pane.firstSelect == nil, "category changes left a stale Shift-selection row")
assert(pane.toolkitCategory == nil and #pane.itemslist == 4, 'clear did not restore all rows')
pane.inventory = {getItems = function() return {contains = function(_, item) return item == hammer or item == beans end} end}
pane.toolkitCategory = 'Tool'
pane:refreshContainer()
pane:transferItemsByWeight({beans, hammer}, source)
assert(#pane.transferred == 1 and pane.transferred[1] == hammer, 'Proximity source ownership bypassed filtering')
pane.inventory = source
pane.toolkitCategory, enabled = 'Tool', false
pane:refreshContainer(); assert(#pane.itemslist == 4 and not pane.toolkitVisibleItems)
assert(#groups[1].items == 2 and groups[1].items[1] == beans, 'real inventory/group contents changed')
print('Inventory filter checks passed: exact categories, search, empty results, selections, bulk actions and clear.')
