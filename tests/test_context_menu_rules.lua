local Rules = dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ContextMenuRules.lua')
local language = 'EN'
local translations = {
    EN = {ContextMenu_Eat = 'Eat', ContextMenu_Move_To = 'Move To', ContextMenu_Patch = 'Patch',
        ContextMenu_Bandage = 'Bandage', ContextMenu_CarBatteryCharger = 'Car Battery Charger'},
    RU = {ContextMenu_Eat = 'Съесть', ContextMenu_Move_To = 'Переместить', ContextMenu_Patch = 'Заплатка',
        ContextMenu_Bandage = 'Перевязать', ContextMenu_CarBatteryCharger = 'Зарядное устройство'},
}
getText = function(key) return translations[language][key] or key end
local function noop() end
local function expect(option, category, key)
    local actualCategory, actualKey = Rules.classify(option)
    assert(actualCategory == category, 'unexpected category for ' .. tostring(option and option.name))
    if not category then assert(actualKey == nil, 'unknown actions must not claim a native identity') end
    if key then assert(actualKey == key, 'unstable action identity: ' .. tostring(actualKey)) end
    return actualKey
end

-- Require can run before the native classes and patches; classifications use live callbacks.
ISInventoryPaneContextMenu = {onEatItems = function() end, OnNewCraft = function() end,
    onDropItems = function() end, onResearchRecipe = function() end, onFix = function() end,
    onUnloadBulletsFromMagazine = function() end, onRenameMap = function() end,
    onConsolidate = function() end, onConsolidateAll = function() end}
ISWorldObjectContextMenu = {onOpenCloseWindow = function() end, onCleanBlood = function() end}
ISVehiclePartMenu = {onUninstallPart = function() end}
ISFarmingMenu = {onSeed = function() end}
ISContextMenu = {onGetUpAndThen = function() end}
ISTimedActionQueue = {queueActions = function() end}
ISHealthPanel = {}

local eat = {name = 'Eat', onSelect = ISInventoryPaneContextMenu.onEatItems, param1 = 1}
local oldEat = eat.onSelect
expect(eat, 'consume', 'callback:ISInventoryPaneContextMenu.onEatItems')
ISInventoryPaneContextMenu.onEatItems = function() end
expect(eat, nil)
eat.onSelect = ISInventoryPaneContextMenu.onEatItems
expect(eat, 'consume', 'callback:ISInventoryPaneContextMenu.onEatItems')
assert(oldEat ~= eat.onSelect)
expect({name = 'Drop', onSelect = ISInventoryPaneContextMenu.onDropItems}, 'transfer')
expect({name = 'Research craft', onSelect = ISInventoryPaneContextMenu.onResearchRecipe}, 'research')
expect({name = 'Uninstall', onSelect = ISVehiclePartMenu.onUninstallPart}, 'vehicle')
expect({name = 'Sow seeds', onSelect = ISFarmingMenu.onSeed}, 'farming')
expect({onSelect = ISInventoryPaneContextMenu.onFix}, 'maintenance', 'callback:ISInventoryPaneContextMenu.onFix')
expect({onSelect = ISInventoryPaneContextMenu.onFix, param4 = {}}, 'vehicle', 'callback:ISInventoryPaneContextMenu.onFix:vehiclePart')

-- Native get-up wrappers must classify by the wrapped callback, never by the shared wrapper.
local target, tooltip, submenu, recipe = {}, {}, 17, {getName = function() return 'DismantleElectronics' end}
local wrapped = {name = 'Open window', onSelect = ISContextMenu.onGetUpAndThen, target = {},
    param1 = ISWorldObjectContextMenu.onOpenCloseWindow, param2 = target, param3 = 5,
    subOption = submenu, toolTip = tooltip, notAvailable = true}
expect(wrapped, 'world', 'callback:ISWorldObjectContextMenu.onOpenCloseWindow')
assert(wrapped.target ~= target and wrapped.param1 == ISWorldObjectContextMenu.onOpenCloseWindow
    and wrapped.param2 == target and wrapped.param3 == 5 and wrapped.subOption == submenu
    and wrapped.toolTip == tooltip and wrapped.notAvailable, 'classifier must never alter menu options')
expect({onSelect = ISContextMenu.onGetUpAndThen, param1 = ISWorldObjectContextMenu.onCleanBlood}, 'maintenance')
expect({name = 'Eat', onSelect = ISContextMenu.onGetUpAndThen, param1 = noop}, nil)
-- addActionsOption supplies the character as target and moves callback arguments one slot.
local queuedRecipe = {getName = function() return 'DismantleElectronics' end}
local queueWrapped = {name = 'Craft', onSelect = ISTimedActionQueue.queueActions, target = target,
    param1 = ISInventoryPaneContextMenu.OnNewCraft, param2 = queuedRecipe,
    param3 = 0, param4 = false, param5 = tooltip}
expect(queueWrapped, 'electronics', 'callback:ISInventoryPaneContextMenu.OnNewCraft:DismantleElectronics')
assert(queueWrapped.onSelect == ISTimedActionQueue.queueActions and queueWrapped.target == target
    and queueWrapped.param1 == ISInventoryPaneContextMenu.OnNewCraft and queueWrapped.param2 == queuedRecipe
    and queueWrapped.param3 == 0 and queueWrapped.param4 == false and queueWrapped.param5 == tooltip)
expect({onSelect = ISTimedActionQueue.queueActions, param1 = ISWorldObjectContextMenu.onCleanBlood}, 'maintenance')
expect({onSelect = ISTimedActionQueue.queueActions, param1 = ISInventoryPaneContextMenu.onFix,
    param4 = tooltip}, 'maintenance', 'callback:ISInventoryPaneContextMenu.onFix')
expect({onSelect = ISTimedActionQueue.queueActions, param1 = ISInventoryPaneContextMenu.onFix,
    param5 = tooltip}, 'vehicle', 'callback:ISInventoryPaneContextMenu.onFix:vehiclePart')
local nested = {onSelect = ISContextMenu.onGetUpAndThen, target = {},
    param1 = ISTimedActionQueue.queueActions, param2 = target,
    param3 = ISInventoryPaneContextMenu.OnNewCraft, param4 = queuedRecipe}
expect(nested, 'electronics', 'callback:ISInventoryPaneContextMenu.OnNewCraft:DismantleElectronics')
assert(nested.onSelect == ISContextMenu.onGetUpAndThen and nested.param1 == ISTimedActionQueue.queueActions
    and nested.param2 == target and nested.param3 == ISInventoryPaneContextMenu.OnNewCraft and nested.param4 == queuedRecipe)
expect({onSelect = ISContextMenu.onGetUpAndThen, param1 = ISInventoryPaneContextMenu.onFix,
    param6 = tooltip}, 'vehicle', 'callback:ISInventoryPaneContextMenu.onFix:vehiclePart')
expect({onSelect = ISContextMenu.onGetUpAndThen, param1 = ISTimedActionQueue.queueActions,
    param3 = ISInventoryPaneContextMenu.onFix, param6 = tooltip}, 'maintenance')
expect({onSelect = ISContextMenu.onGetUpAndThen, param1 = ISTimedActionQueue.queueActions,
    param3 = ISInventoryPaneContextMenu.onFix, param7 = tooltip}, 'vehicle', 'callback:ISInventoryPaneContextMenu.onFix:vehiclePart')
expect({name = 'Eat', onSelect = ISTimedActionQueue.queueActions, param1 = noop}, nil)
expect({name = 'Eat', onSelect = ISTimedActionQueue.queueActions}, nil)
expect({name = 'Eat', onSelect = ISContextMenu.onGetUpAndThen,
    param1 = ISTimedActionQueue.queueActions, param3 = noop}, nil)
expect({onSelect = noop, param1 = ISInventoryPaneContextMenu.OnNewCraft, param2 = queuedRecipe}, nil)
expect({onSelect = ISInventoryPaneContextMenu.onRenameMap}, 'world', 'callback:ISInventoryPaneContextMenu.onRenameMap')
expect({onSelect = ISInventoryPaneContextMenu.onConsolidate}, 'transfer', 'callback:ISInventoryPaneContextMenu.onConsolidate')
expect({onSelect = ISInventoryPaneContextMenu.onConsolidateAll}, 'transfer', 'callback:ISInventoryPaneContextMenu.onConsolidateAll')
expect({onSelect = ISInventoryPaneContextMenu.OnNewCraft, param1 = recipe}, 'electronics',
    'callback:ISInventoryPaneContextMenu.OnNewCraft:DismantleElectronics')
recipe.getName = function() return 'CraftMakeshiftRadio' end
expect({onSelect = ISInventoryPaneContextMenu.OnNewCraft, param1 = recipe}, 'craft',
    'callback:ISInventoryPaneContextMenu.OnNewCraft:CraftMakeshiftRadio')
expect({onSelect = ISInventoryPaneContextMenu.OnNewCraft, param1 = 7}, 'craft',
    'callback:ISInventoryPaneContextMenu.OnNewCraft')
expect({toolkitBulkRecipe = 'RemoveBattery', subOption = 9}, 'electronics', 'callback:ISInventoryPaneContextMenu.OnNewCraft:RemoveBattery')
expect({toolkitBulkUnload = true}, 'equipment', 'toolkit:bulkUnload')
expect({toolkitBulkUnload = true, toolkitOriginalOnSelect = ISInventoryPaneContextMenu.onUnloadBulletsFromMagazine},
    'equipment', 'callback:ISInventoryPaneContextMenu.onUnloadBulletsFromMagazine')
expect({toolkitBulkAttachments = true}, 'equipment', 'text:ContextMenu_Remove_Weapon_Upgrade')
expect({pzstCategory = 'farming', pzstKey = 'plantSelected'}, 'farming', 'toolkit:plantSelected')
expect({pzstCategory = 'invented', pzstKey = 'plantSelected'}, nil)

PZSurvivorToolkit = {BulkClothing = {queue = function() end}}
expect({onSelect = PZSurvivorToolkit.BulkClothing.queue}, 'craft',
    'callback:PZSurvivorToolkit.BulkClothing.queue')
expect({toolkitBulkRecipe = 'RipClothing', toolkitOriginalOnSelect = ISInventoryPaneContextMenu.OnNewCraft,
    param1 = {getName = function() return 'RipClothing' end}}, 'craft',
    'callback:ISInventoryPaneContextMenu.OnNewCraft:RipClothing')
expect({toolkitBulkRecipe = 'CutUpBelt', toolkitOriginalOnSelect = ISInventoryPaneContextMenu.OnNewCraft,
    param1 = {getName = function() return 'CutUpBelt' end}}, 'craft',
    'callback:ISInventoryPaneContextMenu.OnNewCraft:CutUpBelt')
assert(Rules.priority('craft', 'callback:ISInventoryPaneContextMenu.OnNewCraft:CutUpBelt', 'inventory')
    == Rules.priority('craft', 'callback:ISInventoryPaneContextMenu.OnNewCraft:RipClothing', 'inventory'))

local handler = {Type = 'HRemoveBandage', panel = setmetatable({}, ISHealthPanel), onMenuOptionSelected = noop}
expect({target = handler, onSelect = noop}, 'medical', 'medical:HRemoveBandage')
handler.panel = {}
expect({name = 'Remove bandage', target = handler, onSelect = noop}, nil)

for _, lang in ipairs({'EN', 'RU'}) do
    language = lang
    expect({name = getText('ContextMenu_Eat'), subOption = 12}, 'consume', 'text:ContextMenu_Eat')
    expect({name = getText('ContextMenu_Move_To'), subOption = 13}, 'transfer', 'text:ContextMenu_Move_To')
    expect({name = getText('ContextMenu_Bandage'), subOption = 14}, 'medical', 'text:ContextMenu_Bandage')
    expect({name = getText('ContextMenu_CarBatteryCharger'), subOption = 15}, 'electronics')
    expect({name = getText('ContextMenu_Patch'), onSelect = noop}, nil)
    expect({name = getText('ContextMenu_Eat') .. ' zombies'}, nil)
    expect({name = 'Mega ' .. getText('ContextMenu_Eat')}, nil)
    expect({name = getText('ContextMenu_Move_To') .. ' custom destination'}, nil)
    expect({name = 'ContextMenu_Read'}, nil, nil)
    expect({name = 'Handheld Radio', subOption = 16}, nil)
    eat.name = lang == 'EN' and 'Eat all (3)' or 'Съесть всё (27)'
    expect(eat, 'consume', 'callback:ISInventoryPaneContextMenu.onEatItems')
end
expect(nil, nil)
expect({}, nil)
assert(table.concat(Rules.groups, ',') == 'consume,equipment,medical,craft,maintenance,electronics,transfer,world,vehicle,farming,research')
print('Context menu rules checks passed: live native callbacks, wrappers, recipes, EN/RU labels, unknown mod actions and no mutations.')

assert(Rules.priority('consume','callback:ISInventoryPaneContextMenu.onEatItems','inventory')
    < Rules.priority('transfer','callback:ISInventoryPaneContextMenu.onGrabItems','inventory'))
assert(Rules.priority('transfer','callback:ISInventoryPaneContextMenu.onGrabItems','loot')
    < Rules.priority('consume','callback:ISInventoryPaneContextMenu.onEatItems','loot'))
assert(Rules.priority('transfer','callback:ISInventoryPaneContextMenu.onDumpContents','loot')
    > Rules.priority('transfer','callback:ISInventoryPaneContextMenu.onGrabItems','loot'))
assert(Rules.priority('world','callback:ISWorldObjectContextMenu.onOpenCloseDoor','world')
    < Rules.priority('world','callback:ISWorldObjectContextMenu.onBurnCorpse','world'))
assert(Rules.priority(nil,nil,'inventory')==nil)
print('PASS priority policy distinguishes carried/loot purposes and keeps destructive actions below common ones')

assert(Rules.priority('transfer','callback:ISInventoryPage.removeAll','loot')
    > Rules.priority('transfer','callback:ISInventoryPage.lootAll','loot'), 'trash deletion must stay below ordinary loot transfer')

assert(Rules.priority('vehicle','toolkit:uninstallGround','vehicle')==Rules.priority('vehicle','callback:ISVehiclePartMenu.onUninstallPart','vehicle'), 'native and ground removal retain their choice order')

-- Exact item-filtered native lookups are utilities; opening specific recipes remains crafting.
ISEntityUI = {OpenBuildWindow = function() end, OpenHandcraftWindow = function() end}
for _, method in ipairs({'OpenBuildWindow','OpenHandcraftWindow'}) do
    local callback = ISEntityUI[method]
    local lookup = {onSelect = callback, param2 = '*', param3 = false, param5 = '!Base.Plank'}
    expect(lookup, 'world', 'callback:ISEntityUI.'..method)
    expect({onSelect = ISContextMenu.onGetUpAndThen, param1 = callback, param4 = '*', param5 = false,
        param7 = '!Base.Plank'}, 'world', 'callback:ISEntityUI.'..method)
    expect({onSelect = ISTimedActionQueue.queueActions, param1 = callback, param3 = '*', param4 = false,
        param6 = '!Base.Plank'}, 'world', 'callback:ISEntityUI.'..method)
    expect({onSelect = ISContextMenu.onGetUpAndThen, param1 = ISTimedActionQueue.queueActions,
        param3 = callback, param5 = '*', param6 = false, param8 = '!Base.Plank'}, 'world', 'callback:ISEntityUI.'..method)
    for field, value in pairs({param1 = {}, param2 = 'Other', param3 = true, param4 = {}, param5 = 'Base.Plank'}) do
        local previous = lookup[field];lookup[field] = value
        expect(lookup, 'craft', 'callback:ISEntityUI.'..method);lookup[field] = previous
    end
    lookup.param5 = '!';expect(lookup, 'craft');lookup.param5 = '!Base.Plank extra';expect(lookup, 'craft')
    lookup.param5 = '!Base.Plank';lookup.param4 = recipe;expect(lookup, 'craft')
    expect({onSelect = callback}, 'craft', 'callback:ISEntityUI.'..method)
end
local nativeLookup = {onSelect = ISEntityUI.OpenBuildWindow, param2 = '*', param3 = false, param5 = '!Base.Plank'}
local nativeMoreChild = {options = {nativeLookup}}
local nativeMoreMenu = {getSubMenu = function() return nativeMoreChild end}
assert(Rules.isMore(nativeMoreMenu, {name = getText('ContextMenu_More'), subOption = 1}))
nativeMoreChild.options[2] = {onSelect = noop}
assert(not Rules.isMore(nativeMoreMenu, {name = getText('ContextMenu_More'), subOption = 1}))

-- Neat Building's exact lookup duplicates only the same player's native exact-type route.
NB_InventoryBuildSearch = {openExact = function() end, openByDisplayName = function() end}
ISEntityUI = {OpenBuildWindow = function() end}
PZSurvivorToolkit.Settings = {itemTags = function() return false end}
local buildPlayer = {}
getSpecificPlayer = function(index) return index == 0 and buildPlayer or {} end
local buildItem = {getFullType = function() return 'Base.Plank' end}
local function buildingMenu()
    local exact = {name = 'Exact', target = buildItem, onSelect = NB_InventoryBuildSearch.openExact, param1 = 0}
    local names = {name = 'Matching names', target = buildItem, onSelect = NB_InventoryBuildSearch.openByDisplayName, param1 = 0}
    local search = {name = 'Building search', subOption = 1}
    local native = {name = 'Build', target = buildPlayer, onSelect = ISEntityUI.OpenBuildWindow,
        param2 = '*', param3 = false, param5 = '!Base.Plank'}
    local child = {options = {exact, names}}
    local menu = {player = 0, options = {search, native}, getSubMenu = function(_, index) return index == 1 and child or nil end}
    return menu, search, native, child, exact, names
end
local function visible(row) return not row.notAvailable and not row.hidden end
local menu, search, native, child, exact, names = buildingMenu()
assert(Rules.isBuildingSearch(menu, search))
local defaults = Rules.defaults(menu, menu.options, 'inventory', visible)
assert(defaults[search] == 'world' and defaults[native] == 'hidden')
assert(search.subOption == 1 and native.onSelect == ISEntityUI.OpenBuildWindow and native.param5 == '!Base.Plank')
assert(Rules.defaults(menu, menu.options, 'loot', visible)[native] == 'hidden')
assert(next(Rules.defaults(menu, menu.options, 'world', visible)) == nil)
menu.parent = {};assert(next(Rules.defaults(menu, menu.options, 'inventory', visible)) == nil);menu.parent = nil
for _, field in ipairs({'notAvailable', 'hidden'}) do
    search[field] = true;assert(Rules.defaults(menu, menu.options, 'inventory', visible)[native] == nil);search[field] = nil
    exact[field] = true;assert(Rules.defaults(menu, menu.options, 'inventory', visible)[native] == nil);exact[field] = nil
end
names.notAvailable = true
assert(Rules.defaults(menu, menu.options, 'inventory', visible)[native] == 'hidden', 'unavailable name matching does not affect exact lookup')
names.notAvailable = nil
for field, value in pairs({target = {}, param1 = true, param2 = 'Other', param3 = true, param4 = {}, param5 = '!Base.Nails'}) do
    local previous = native[field];native[field] = value
    assert(Rules.defaults(menu, menu.options, 'inventory', visible)[native] == nil, 'foreign native build argument: '..field)
    native[field] = previous
end
exact.param1 = 1;assert(Rules.defaults(menu, menu.options, 'inventory', visible)[native] == nil);exact.param1 = 0
exact.param1 = nil;assert(Rules.defaults(menu, menu.options, 'inventory', visible)[native] == nil);exact.param1 = 0
exact.target = {};assert(Rules.defaults(menu, menu.options, 'inventory', visible)[native] == nil)
exact.target = {getFullType = function() return nil end};assert(Rules.defaults(menu, menu.options, 'inventory', visible)[native] == nil);exact.target = buildItem
exact.onSelect = noop
assert(not Rules.isBuildingSearch(menu, search))
assert(Rules.defaults(menu, menu.options, 'inventory', visible)[native] == nil)
exact.onSelect = NB_InventoryBuildSearch.openExact
child.options[3] = {onSelect = noop}
assert(not Rules.isBuildingSearch(menu, search))
assert(Rules.defaults(menu, menu.options, 'inventory', visible)[native] == nil)
child.options[3] = nil
child.options = {names};assert(Rules.isBuildingSearch(menu, search))
assert(Rules.defaults(menu, menu.options, 'inventory', visible)[native] == nil)
child.options = {};assert(not Rules.isBuildingSearch(menu, search));child.options = {exact, names}
search.onSelect = noop;assert(not Rules.isBuildingSearch(menu, search));search.onSelect = nil
search.subOption = 9;assert(not Rules.isBuildingSearch(menu, search));search.subOption = 1
local more = {name = getText('ContextMenu_More'), subOption = 2}
local moreChild = {options = {search}, getSubMenu = menu.getSubMenu}
local moreMenu = {getSubMenu = function(_, index) return index == 2 and moreChild or nil end}
assert(Rules.isMore(moreMenu, more), 'native More containing Neat Building stays coherent')
moreChild.options[2] = {name = 'Unknown', onSelect = noop}
assert(not Rules.isMore(moreMenu, more))
NB_InventoryBuildSearch = nil
assert(not Rules.isBuildingSearch(menu, search))
assert(Rules.defaults(menu, menu.options, 'inventory', visible)[native] == nil)
print('PASS queued native callbacks and coherent Neat Building lookup preserve foreign/hidden/player-specific routes')

-- Optional cart-corpse actions are identified without enabling or changing the feature.
local sources = {}
getFilenameOfClosure = function(callback) return sources[callback] end
local oldGetText = getText
getText = function(key, cartName)
    if key == 'UI_SaucedCarts_LoadCorpseInto' then return 'Load corpse into ' .. tostring(cartName) end
    if key == 'UI_SaucedCarts_LoadCorpse' then return 'Load corpse' end
    return oldGetText(key)
end
local cart = {}
local cartPlayer = {getPlayerNum = function() return 0 end, getInventory = function() return {} end}
local enabled = false
SaucedCarts = {isCart = function(item) return item == cart end,
    getCartDisplayName = function(item) assert(item == cart);return 'Shopping cart' end,
    CorpseStorage = {isEnabled = function() return enabled end}}
local rootCorpse = {name = getText('UI_SaucedCarts_LoadCorpseInto', 'Shopping cart'),
    target = cartPlayer, param1 = cart, onSelect = function() end}
local nestedCorpse = {name = getText('UI_SaucedCarts_LoadCorpse'), target = cartPlayer,
    param1 = cart, onSelect = function() end}
sources[rootCorpse.onSelect] = '/mods/SaucedCarts/ContextMenu.lua'
sources[nestedCorpse.onSelect] = 'C:\\mods\\SaucedCarts\\ContextMenu\\CartSubmenu.lua'
assert(Rules.cartCorpseRole(rootCorpse) == 'root' and Rules.cartCorpseRole(nestedCorpse) == 'nested')
expect(rootCorpse, 'world', 'mod:SaucedCarts.loadCorpseRoot')
expect(nestedCorpse, 'world', 'mod:SaucedCarts.loadCorpseNested')
assert(not enabled and rootCorpse.target == cartPlayer and rootCorpse.param1 == cart
    and sources[rootCorpse.onSelect] == '/mods/SaucedCarts/ContextMenu.lua')
local originalSource = sources[rootCorpse.onSelect]
sources[rootCorpse.onSelect] = '/mods/OtherMod/ContextMenu.lua'
assert(Rules.cartCorpseRole(rootCorpse) == nil);expect(rootCorpse, nil)
sources[rootCorpse.onSelect] = originalSource
rootCorpse.name = getText('UI_SaucedCarts_LoadCorpse')
assert(Rules.cartCorpseRole(rootCorpse) == nil);rootCorpse.name = getText('UI_SaucedCarts_LoadCorpseInto', 'Shopping cart')
rootCorpse.param1 = {};assert(Rules.cartCorpseRole(rootCorpse) == nil);rootCorpse.param1 = cart
rootCorpse.target = {};assert(Rules.cartCorpseRole(rootCorpse) == nil)
rootCorpse.target = 1;assert(Rules.cartCorpseRole(rootCorpse) == nil)
rootCorpse.target = {getInventory = noop, getPlayerNum = function() error('foreign player') end}
assert(Rules.cartCorpseRole(rootCorpse) == nil);rootCorpse.target = cartPlayer
local isCart, displayName = SaucedCarts.isCart, SaucedCarts.getCartDisplayName
SaucedCarts.isCart = function() error('foreign cart') end
assert(Rules.cartCorpseRole(rootCorpse) == nil)
SaucedCarts.isCart = nil;assert(Rules.cartCorpseRole(rootCorpse) == nil);SaucedCarts.isCart = isCart
SaucedCarts.getCartDisplayName = function() error('foreign cart name') end
assert(Rules.cartCorpseRole(rootCorpse) == nil)
SaucedCarts.getCartDisplayName = function() return nil end;assert(Rules.cartCorpseRole(rootCorpse) == nil)
SaucedCarts.getCartDisplayName = nil;assert(Rules.cartCorpseRole(rootCorpse) == nil);SaucedCarts.getCartDisplayName = displayName
local sourceLookup = getFilenameOfClosure
getFilenameOfClosure = function() error('foreign closure') end
assert(Rules.cartCorpseRole(rootCorpse) == nil)
getFilenameOfClosure = nil;assert(Rules.cartCorpseRole(rootCorpse) == nil);getFilenameOfClosure = sourceLookup
SaucedCarts = nil;assert(Rules.cartCorpseRole(rootCorpse) == nil)
assert(Rules.cartCorpseRole(nil) == nil and Rules.cartCorpseRole({}) == nil)
getText = oldGetText
print('PASS cart corpse roles require exact source, translated action, cart and player guards without feature mutations')

-- Automatic shells retain fast actions and native selectors at root without changing their identity.
local function groupable(category, key, context, option, owner)
    return Rules.canGroupAutomatically(owner or {getSubMenu = function() end}, option or {}, category, key, context or 'inventory')
end
for _, method in ipairs({'OnPrimaryWeapon', 'OnSecondWeapon', 'OnTwoHandsEquip'}) do
    local key = 'callback:ISInventoryPaneContextMenu.' .. method
    assert(groupable('equipment', key), 'hand choices may share a shell: ' .. method)
    assert(not groupable('equipment', key, 'inventory', {subOption = 3}), 'native hand selectors remain intact')
end
for _, method in ipairs({'onWearItems', 'onUnEquip', 'onClothingItemExtra', 'onInspectClothing', 'onUpgradeWeapon',
    'onRemoveUpgradeWeapon', 'onChangefiremode', 'onLoadBulletsInMagazine', 'onInsertMagazine', 'onRackGun', 'addLure'}) do
    assert(not groupable('equipment', 'callback:ISInventoryPaneContextMenu.' .. method), 'equipment action stays root: '..method)
end
for _, definition in ipairs({{'consume','ISInventoryPaneContextMenu.onEatItems'}, {'consume','ISInventoryPaneContextMenu.onDrinkFluid'},
    {'medical','ISInventoryPaneContextMenu.onPillsItems'}, {'medical','ISInventoryPaneContextMenu.onApplyBandage'},
    {'research','ISInventoryPaneContextMenu.onLiteratureItems'}, {'electronics','ISInventoryPaneContextMenu.onActivateItem'},
    {'transfer','ISInventoryPaneContextMenu.onGrabItems'}, {'transfer','ISInventoryPaneContextMenu.onDropItems'},
    {'world','ISInventoryPaneContextMenu.onPlaceItemOnGround'}, {'world','ISWorldObjectContextMenu.onOpenCloseDoor'},
    {'consume','PZSurvivorToolkit.BulkFood.queue'}, {'consume','PZSurvivorToolkit.BulkFood.queueOne'}}) do
    assert(not groupable(definition[1], 'callback:'..definition[2]), 'primary action stays root: '..definition[2])
end
for _, method in ipairs({'onWalkTo','onSitOnGround','onRest','onSleep','onOpenCloseCurtain'}) do
    assert(not groupable('world', 'callback:ISWorldObjectContextMenu.'..method, 'world'), 'primary world action stays root: '..method)
end
assert(groupable('world', 'callback:ISInventoryPaneContextMenu.onRenameMap'))
assert(groupable('maintenance', 'callback:ISInventoryPaneContextMenu.onWringClothing'))
assert(groupable('electronics', 'callback:ISInventoryPaneContextMenu.onSetAlarm'))
assert(not groupable('maintenance', 'text:ContextMenu_Patch', 'inventory', {subOption = 7}))
assert(not groupable('world', nil, 'inventory', {subOption = 8}), 'coherent lookup exceptions require the owning menu check')
print('PASS automatic eligibility preserves primary actions, hands-only equipment and native selector depth')

NB_InventoryBuildSearch = {openExact = function() end, openByDisplayName = function() end}
menu, search, native, child = buildingMenu()
assert(groupable('world', nil, 'inventory', search, menu), 'coherent building lookup belongs in More')
assert(not groupable('craft', nil, 'inventory', search, menu), 'lookup exception requires its world placement')
child.options[3] = {onSelect = noop}
assert(not groupable('world', nil, 'inventory', search, menu), 'foreign building submenu stays root')
NC_InventorySearch = {searchAsInput = function() end, searchAsOutput = function() end}
child.options = {{onSelect = NC_InventorySearch.searchAsInput}, {onSelect = NC_InventorySearch.searchAsOutput}}
assert(groupable('world', nil, 'inventory', search, menu), 'coherent crafting lookup belongs in More')
child.options[2].onSelect = noop
assert(not groupable('world', nil, 'inventory', search, menu), 'foreign crafting submenu stays root')

-- A rebuild reuses classifications without retaining them across native callback changes.
do
    local liveClassify, calls = Rules.classify, 0
    local classify = Rules.newClassifier()
    Rules.classify = function(option)
        calls = calls + 1
        return liveClassify(option)
    end
    local known = {onSelect = ISInventoryPaneContextMenu.onEatItems}
    local unknown = {onSelect = noop}
    for _ = 1, 2 do
        local category, key = classify(known)
        assert(category == 'consume' and key == 'callback:ISInventoryPaneContextMenu.onEatItems')
        category, key = classify(unknown)
        assert(category == nil and key == nil, 'unknown results must keep both nil values')
    end
    assert(calls == 2, 'plain known and unknown actions must each classify once per rebuild')
    classify(nil);classify(nil);classify(false);classify(false)
    assert(calls == 6, 'non-table values must use the live classifier')

    local category = 'consume'
    local opaque = setmetatable({}, {__metatable = false, __index = function(_, key)
        if key == 'pzstCategory' then return category end
        if key == 'pzstKey' then return 'opaque' end
    end})
    assert(classify(opaque) == 'consume')
    category = 'world'
    assert(classify(opaque) == 'world' and calls == 8, 'protected mod options must retain live field reads')

    local callback = ISInventoryPaneContextMenu.onEatItems
    ISInventoryPaneContextMenu.onEatItems = function() end
    assert(Rules.classify(known) == nil, 'direct classification must observe callback replacement')
    assert(Rules.newClassifier()(known) == nil, 'a new rebuild must reject the old native callback')
    known.onSelect = ISInventoryPaneContextMenu.onEatItems
    assert(Rules.newClassifier()(known) == 'consume', 'a new rebuild must recognize the replacement callback')
    ISInventoryPaneContextMenu.onEatItems = callback
    Rules.classify = liveClassify
end
print('PASS per-rebuild classification caches nil results, bypasses opaque options and refreshes native callbacks')

do
    local row, calls = {onSelect = noop}, 0
    local child = {options = {row}}
    local menu = {getSubMenu = function() return child end}
    local option = {name = getText('ContextMenu_More'), subOption = 1}
    assert(not Rules.isMore(menu, option), 'direct More checks must retain live classification')
    assert(Rules.isMore(menu, option, function(candidate)
        assert(candidate == row);calls = calls + 1
        return 'world', 'test:more'
    end) and calls == 1, 'More checks must route through the supplied classifier')

    local fluid = {name = getText('ContextMenu_Fluid')}
    calls = 0
    local defaults = Rules.defaults({options = {fluid}}, {fluid}, 'inventory', function() return true end,
        function(candidate)
            assert(candidate == fluid);calls = calls + 1
            return 'transfer', 'text:ContextMenu_Fluid'
        end)
    assert(defaults[fluid] == 'root' and calls == 1, 'defaults must reuse category and key from one supplied classification')
end
print('PASS More and semantic defaults share an optional rebuild classifier')
