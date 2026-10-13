-- Use the actual shipped translations; native-key checks run against an installed game.
PZSurvivorToolkit = {}
instanceof = function(value, class) return type(value) == 'table' and value.class == class end
Translator = {getMoveableDisplayName = function(value) return 'Translated ' .. value end}
ISWorldObjectContextMenu = {getMoveableDisplayName = function(object) return object.name end}
local labels = assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueLabels.lua'))()
local function item(name, custom)
    return {class = 'InventoryItem', getDisplayName = function() return name end,
        getCustomMenuOption = function() return custom end}
end
local expected = {
    EN = {walk = 'Walk to target', transfer = 'Move items', rack = 'Rack firearm',
        load = 'Load magazine', media = 'Eject media', insertMedia = 'Insert media', playback = 'Toggle playback',
        clothing = 'Adjust clothing', craft = 'Craft', power = 'Toggle device power',
        volume = 'Change volume', channel = 'Change channel', unknown = 'Action: MyModAction',
        read = 'Read', equip = 'Equip Primary', secondary = 'Equip Secondary', both = 'Equip in Both Hands',
        unequip = 'Unequip', unload = 'Unload Rounds', unloadMagazine = 'Unload Magazine',
        reload = 'Load Rounds', insert = 'Insert Magazine', eject = 'Eject Magazine',
        removePart = 'Remove Upgrade', addPart = 'Upgrade', battery = 'Remove Battery',
        addBattery = 'Add Battery', eat = 'Eat', drink = 'Drink', wear = 'Wear', disassemble = 'Disassemble', repair = 'Repair'},
    RU = {walk = 'Подойти к цели', transfer = 'Переместить предметы', rack = 'Передёрнуть затвор',
        load = 'Зарядить магазин', media = 'Извлечь носитель', insertMedia = 'Вставить носитель', playback = 'Переключить воспроизведение',
        clothing = 'Поправить одежду', craft = 'Изготовить', power = 'Переключить питание устройства',
        volume = 'Изменить громкость', channel = 'Сменить канал', unknown = 'Действие: MyModAction',
        read = 'Читать', equip = 'Взять в основную руку', secondary = 'Взять в дополнительную руку', both = 'Взять в обе руки',
        unequip = 'Снять', unload = 'Разрядить патроны', unloadMagazine = 'Разрядить магазин',
        reload = 'Зарядить патроны', insert = 'Вставить магазин', eject = 'Достать магазин',
        removePart = 'Снять насадку', addPart = 'Установить насадку', battery = 'Вытащить батарейку',
        addBattery = 'Подключить батарейку', eat = 'Есть', drink = 'Пить', wear = 'Надеть', disassemble = 'Разобрать', repair = 'Починить'},
}
for _, language in ipairs({'EN', 'RU'}) do
    local translations = assert(ActionQueueTranslations and ActionQueueTranslations[language], 'runner must load EN/RU UI JSON')
    getText = function(key, ...)
        local text = translations[key] or key
        local args = {...}
        return (text:gsub('%%(%d+)', function(index) return tostring(args[tonumber(index)] or '%' .. index) end))
    end
    local e = expected[language]
    assert(labels.label({Type = 'ISToggleStoveAction', object = {class = 'IsoObject', name = 'Oven'}}) == e.power .. ': Oven')
    assert(labels.label({Type = 'ISQueueActionsAction', toolkitWorldOperation = 'appliance',
        toolkitWorldTarget = {class = 'IsoObject'}}) == e.power)
    local function check(action, title)
        local actual, signature = labels.title(action)
        assert(actual == title, language .. ': ' .. tostring(action.Type) .. ': ' .. actual .. ' ~= ' .. title)
        assert(type(signature) == 'string' and signature ~= '')
        assert(not actual:find('%%[1-9]'), 'no unresolved native placeholders')
        return signature
    end
    local signature = check({Type = 'ISWalkToTimedAction'}, e.walk)
    local buildTitle = language == 'EN' and 'Build' or 'Построить'
    check({Type = 'ISBuildAction'}, buildTitle)
    check({Type = 'ISQueueActionsAction', toolkitWorldOperation = 'build'}, buildTitle)
    assert(labels.label({Type = 'ISQueueActionsAction', toolkitWorldOperation = 'build', toolkitWorldName = 'Crate'})
        == buildTitle .. ': Translated Crate')
    assert(check({Type = 'ISWalkToTimedActionF'}, e.walk) == signature)
    assert(check({Type = 'ISPathFindAction'}, e.walk) == signature)
    check({Type = 'ISInventoryTransferAction'}, e.transfer)
    check({Type = 'ISRackFirearm'}, e.rack)
    check({Type = 'ISLoadBulletsInMagazine', ammoCount = 12}, e.load)
    check({Type = 'ISClothingExtraAction'}, e.clothing)
    check({Type = 'ISHandcraftAction'}, e.craft)
    check({Type = 'ISCraftAction'}, e.craft)
    check({Type = 'ISDeviceMediaAction', isRemove = true}, e.media)
    check({Type = 'ISDeviceMediaAction', isRemove = false}, e.insertMedia)
    check({Type = 'ISRadioAction', mode = 'TogglePlayMedia'}, e.playback)
    check({Type = 'ISRadioAction', mode = 'ToggleOnOff'}, e.power)
    check({Type = 'ISRadioAction', mode = 'SetVolume', secondaryItem = 0.5}, e.volume)
    check({Type = 'ISRadioAction', mode = 'SetChannel', secondaryItem = 88000}, e.channel)
    local gun = item('Custom named pistol')
    assert(labels.label({Type = 'ISRackFirearm', gun = gun}) == e.rack .. ': Custom named pistol')
    assert(labels.label({Type = 'ISInventoryTransferAction', item = false}) == e.transfer)
    local callbackCalls = 0
    local unknown = {Type = 'MyModAction', item = gun, getName = function() callbackCalls = callbackCalls + 1 end,
        getJobType = function() callbackCalls = callbackCalls + 1 end}
    local text, unknownSignature = labels.title(unknown)
    assert(text == e.unknown and unknownSignature == nil)
    assert(labels.label(unknown) == e.unknown .. ': Custom named pistol' and callbackCalls == 0)
    local fakeRecipe = {getTranslationName = function() error('unverified recipe getter executed') end}
    check({Type = 'ISHandcraftAction', craftRecipe = fakeRecipe}, e.craft)
    local fakeItem = {getDisplayName = function() error('unverified item getter executed') end}
    assert(labels.label({Type = 'ISInventoryTransferAction', item = fakeItem}) == e.transfer)
    assert(not labels.preparation({Type = 'ISInventoryTransferAction'}))
    assert(not labels.preparation(unknown))
    assert(labels.preparation({Type = 'MyModAction', toolkitBulkPreparation = true}))
    for _, kind in ipairs({'ISWalkToTimedAction', 'ISWalkToTimedActionF', 'ISPathFindAction',
        'ISEquipWeaponAction', 'ISEquipHeavyItem', 'ISUnequipAction', 'ISWearClothing'}) do
        assert(labels.preparation({Type = kind}))
    end
    local recipe = {class = 'CraftRecipe', getTranslationName = function() return 'Native recipe name' end,
        getName = function() return 'NativeRecipe' end}
    assert(check({Type = 'ISHandcraftAction', craftRecipe = recipe}, 'Native recipe name') == 'craft:NativeRecipe')
    assert(labels.label({Type = 'ISQueueActionsAction', toolkitWorldOperation = 'build', craftRecipe = recipe})
        == buildTitle .. ': Native recipe name')
    assert(labels.label({Type = 'ISBuildAction', item = {craftRecipe = recipe, name = 'ScriptEntityId'}})
        == buildTitle .. ': Native recipe name')
    local oldRecipe = {class = 'Recipe', getName = function() return 'Legacy recipe name' end}
    check({Type = 'ISCraftAction', recipe = oldRecipe}, 'Legacy recipe name')
    if NativeActionRoot then
        for _, entry in ipairs({{'ISAddGasolineToVehicle', 'ContextMenu_VehicleAddGas', false},
            {'ISTakeGasolineFromVehicle', 'ContextMenu_VehicleSiphonGas', true}}) do
            local title = assert(translations[entry[2]])
            check({Type = entry[1]}, title)
            check({Type = 'ISQueueActionsAction', toolkitWorldOperation = 'fuel', toolkitFuelTake = entry[3]}, title)
        end
        local cases = {
            {'ISReadABook', 'read'}, {'ISReadWorldMap', 'read'}, {'ISUnequipAction', 'unequip'},
            {'ISUnloadBulletsFromFirearm', 'unload'}, {'ISUnloadBulletsFromMagazine', 'unloadMagazine'},
            {'ISReloadWeaponAction', 'reload'}, {'ISInsertMagazine', 'insert'}, {'ISEjectMagazine', 'eject'},
            {'ISRemoveWeaponUpgrade', 'removePart'}, {'ISUpgradeWeapon', 'addPart'},
            {'ISEatFoodAction', 'eat'}, {'ISDrinkFromBottle', 'drink'}, {'ISDrinkFluidAction', 'drink'},
            {'ISWearClothing', 'wear'}, {'ISDismantleAction', 'disassemble'}, {'ISFixAction', 'repair'},
        }
        for _, entry in ipairs(cases) do check({Type = entry[1], item = gun}, e[entry[2]]) end
        assert(labels.label({Type = 'ISFixAction', item = gun}) == e.repair .. ': Custom named pistol',
            language .. ': repair label must retain the repaired item name')
        check({Type = 'ISEquipWeaponAction', primary = true}, e.equip)
        check({Type = 'ISEquipWeaponAction', primary = false}, e.secondary)
        check({Type = 'ISEquipWeaponAction', twoHands = true}, e.both)
        check({Type = 'ISEquipHeavyItem'}, e.both)
        check({Type = 'ISDeviceBatteryAction', isRemove = true}, e.battery)
        check({Type = 'ISDeviceBatteryAction', isRemove = false}, e.addBattery)
        assert(labels.label({Type = 'ISMoveablesAction', mode = 'scrap', moveProps = {name = 'Bench'}})
            == e.disassemble .. ': Translated Bench')
        assert(labels.label({Type = 'CustomDismantle', toolkitWorldDismantle = true, toolkitWorldName = 'Door'})
            == e.disassemble .. ': Translated Door')
        local drink = item('Drink', e.drink)
        local drinkSignature = check({Type = 'ISDrinkFromBottle', item = gun}, e.drink)
        assert(check({Type = 'ISEatFoodAction', item = drink}, e.drink) == drinkSignature)
        assert(check({Type = 'ISDrinkFluidAction', item = drink}, e.drink) == drinkSignature)
        local eat = item('Eat', e.eat)
        local eatSignature = check({Type = 'ISEatFoodAction', item = gun}, e.eat)
        assert(check({Type = 'ISEatFoodAction', item = eat}, e.eat) == eatSignature)
        assert(check({Type = 'ISDrinkFromBottle', item = eat}, e.eat) == eatSignature)
        assert(check({Type = 'ISEatFoodAction', item = item('Custom', 'Custom consume')}, 'Custom consume')
            == 'consume:Custom consume')
        for mode, key in pairs({MuteVolume = 'IGUI_RadioMuteSpeaker', UnMuteVolume = 'IGUI_RadioUnmuteSpeaker',
            AddHeadphones = 'IGUI_RadioAddHeadphones', RemoveHeadphones = 'IGUI_RadioRemoveHeadphones'}) do
            check({Type = 'ISRadioAction', mode = mode}, assert(translations[key]))
        end
        check({Type = 'ISRadioAction', mode = 'MuteMicrophone', secondaryItem = true}, assert(translations.IGUI_RadioMuteMic))
        check({Type = 'ISRadioAction', mode = 'MuteMicrophone', secondaryItem = false}, assert(translations.IGUI_RadioUnmuteMic))
    end
end
print('Action queue labels EN/RU checks passed.')
