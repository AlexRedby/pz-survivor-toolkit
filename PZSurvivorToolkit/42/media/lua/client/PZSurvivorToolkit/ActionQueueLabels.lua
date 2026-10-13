local Labels = {}
PZSurvivorToolkit.ActionQueueLabels = Labels

local prefix = "UI_PZSurvivorToolkit_queue_action_"
local keys = {
    ISReadABook = "ContextMenu_Read",
    ISReadWorldMap = "ContextMenu_Read",
    ISInventoryTransferAction = prefix .. "transfer",
    ISWalkToTimedAction = prefix .. "walk",
    ISWalkToTimedActionF = prefix .. "walk",
    ISPathFindAction = prefix .. "walk",
    ISUnequipAction = "ContextMenu_Unequip",
    ISWearClothing = "ContextMenu_Wear",
    ISClothingExtraAction = prefix .. "clothing",
    ISCraftAction = prefix .. "craft",
    ISHandcraftAction = prefix .. "craft",
    ISFixAction = "ContextMenu_Repair",
    ISDismantleAction = "ContextMenu_Disassemble",
    ISUnloadBulletsFromFirearm = "IGUI_JobType_UnloadBulletsFromFirearm",
    ISUnloadBulletsFromMagazine = "ContextMenu_UnloadMagazine",
    ISReloadWeaponAction = "IGUI_JobType_LoadBulletsIntoFirearm",
    ISRackFirearm = prefix .. "rack",
    ISInsertMagazine = "ContextMenu_InsertMagazine",
    ISEjectMagazine = "ContextMenu_EjectMagazine",
    ISLoadBulletsInMagazine = prefix .. "load_magazine",
    ISRemoveWeaponUpgrade = "ContextMenu_Remove_Weapon_Upgrade",
    ISUpgradeWeapon = "ContextMenu_Add_Weapon_Upgrade",
    ISEatFoodAction = "ContextMenu_Eat",
    ISDrinkFromBottle = "ContextMenu_Drink",
    ISDrinkFluidAction = "ContextMenu_Drink",
    ISToggleStoveAction = prefix .. "power",
    ISToggleClothingWasher = prefix .. "power",
    ISToggleClothingDryer = prefix .. "power",
    ISToggleComboWasherDryer = prefix .. "power",
    ISOvenUITimedAction = "ContextMenu_StoveSetting",
    ISAddGasolineToVehicle = "ContextMenu_VehicleAddGas",
    ISTakeGasolineFromVehicle = "ContextMenu_VehicleSiphonGas",
}
local radioKeys = {
    ToggleOnOff = prefix .. "power",
    SetChannel = prefix .. "channel",
    SetVolume = prefix .. "volume",
    MuteVolume = "IGUI_RadioMuteSpeaker",
    UnMuteVolume = "IGUI_RadioUnmuteSpeaker",
    RemoveHeadphones = "IGUI_RadioRemoveHeadphones",
    AddHeadphones = "IGUI_RadioAddHeadphones",
    TogglePlayMedia = prefix .. "playback",
}
local preparation = {
    ISWalkToTimedAction = true, ISWalkToTimedActionF = true, ISPathFindAction = true,
    ISEquipWeaponAction = true, ISEquipHeavyItem = true, ISUnequipAction = true,
    ISWearClothing = true,
}

function Labels.preparation(action)
    return action.toolkitBulkPreparation == true or preparation[action.Type] == true
end

function Labels.title(action)
    if action.toolkitWorldOperation == "fuel" then
        local key = action.toolkitFuelTake and "ContextMenu_VehicleSiphonGas" or "ContextMenu_VehicleAddGas"
        return getText(key), key
    end
    if action.toolkitWorldOperation == "appliance" then
        local key = action.toolkitApplianceLabel or prefix .. "power"
        return getText(key), key
    end
    if action.Type == "ISSetComboWasherDryerMode" then
        local key = "ContextMenu_ComboWasherDryer_SetMode" .. (action.mode == "dryer" and "Dryer" or "Washer")
        return getText(key), key
    end
    if action.toolkitWorldOperation == "build" or action.Type == "ISBuildAction" then
        return getText(prefix .. "build"), "world:build"
    end
    if action.toolkitWorldDismantle or (action.Type == "ISMoveablesAction" and action.mode == "scrap") then
        return getText("ContextMenu_Disassemble"), "world:disassemble"
    end
    if action.craftRecipe and instanceof(action.craftRecipe, "CraftRecipe") then
        return action.craftRecipe:getTranslationName(), "craft:" .. action.craftRecipe:getName()
    end
    if action.Type == "ISCraftAction" and action.recipe and instanceof(action.recipe, "Recipe") then
        local name = action.recipe:getName()
        return name, "craft:" .. name
    end
    local key = keys[action.Type]
    if action.Type == "ISEquipHeavyItem" then
        key = "ContextMenu_Equip_Two_Hands"
    elseif action.Type == "ISEquipWeaponAction" then
        key = action.twoHands and "ContextMenu_Equip_Two_Hands"
            or (action.primary and "ContextMenu_Equip_Primary" or "ContextMenu_Equip_Secondary")
    elseif action.Type == "ISDeviceBatteryAction" then
        key = action.isRemove and "ContextMenu_Remove_Battery" or "ContextMenu_AddBattery"
    elseif action.Type == "ISDeviceMediaAction" then
        key = prefix .. (action.isRemove and "eject_media" or "insert_media")
    elseif action.Type == "ISRadioAction" then
        key = radioKeys[action.mode]
        if action.mode == "MuteMicrophone" then
            key = action.secondaryItem and "IGUI_RadioMuteMic" or "IGUI_RadioUnmuteMic"
        end
    elseif (action.Type == "ISEatFoodAction" or action.Type == "ISDrinkFromBottle"
        or action.Type == "ISDrinkFluidAction") and action.item and instanceof(action.item, "InventoryItem") then
        local custom = action.item:getCustomMenuOption()
        if custom and custom ~= "" then
            if custom == getText("ContextMenu_Eat") then return custom, "ContextMenu_Eat" end
            if custom == getText("ContextMenu_Drink") then return custom, "ContextMenu_Drink" end
            return custom, "consume:" .. custom
        end
    end
    if key then return getText(key), key end
    -- shortcut: unknown mod actions keep their type, add a verified mapping when their contract is known.
    return getText(prefix .. "unknown", tostring(action.Type or "?"))
end

function Labels.label(action)
    local title = Labels.title(action)
    local appliance = action.toolkitWorldOperation == "appliance" or keys[action.Type] == prefix .. "power"
        or action.Type == "ISOvenUITimedAction" or action.Type == "ISSetComboWasherDryerMode"
    local object = appliance and (action.toolkitWorldTarget or action.object or action.stove or action.mcwave)
    if object and instanceof(object, "IsoObject") then
        local name = ISWorldObjectContextMenu.getMoveableDisplayName(object)
        if name then return title .. ": " .. name end
    end
    if action.toolkitWorldOperation == "build" or action.Type == "ISBuildAction" then
        local recipe = action.craftRecipe or (action.item and action.item.craftRecipe)
        if recipe and instanceof(recipe, "CraftRecipe") then return title .. ": " .. recipe:getTranslationName() end
        local name = action.toolkitWorldName or (action.item and action.item.name)
        if name then return title .. ": " .. Translator.getMoveableDisplayName(name) end
    end
    if action.toolkitWorldDismantle or (action.Type == "ISMoveablesAction" and action.mode == "scrap") then
        local name = action.toolkitWorldName or (action.moveProps and action.moveProps.name)
        if name then return title .. ": " .. Translator.getMoveableDisplayName(name) end
    end
    local item = action.item or action.gun or action.magazine or action.weapon
    if not item and action.Type == "ISRadioAction" then item = action.device end
    if item and instanceof(item, "InventoryItem") then return title .. ": " .. item:getDisplayName() end
    return title
end

return Labels
