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
    onUnloadBulletsFromMagazine = function() end}
ISWorldObjectContextMenu = {onOpenCloseWindow = function() end, onCleanBlood = function() end}
ISVehiclePartMenu = {onUninstallPart = function() end}
ISFarmingMenu = {onSeed = function() end}
ISContextMenu = {onGetUpAndThen = function() end}
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
