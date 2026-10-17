local Definitions = {entries = {}, types = {}, behaviorOrder = {}}
PZSurvivorToolkit.ActionQueueDefinitions = Definitions

function Definitions.register(id, descriptor)
    assert(type(id) == "string" and id ~= "", "action definition needs an id")
    assert(type(descriptor) == "table", "action definition needs a descriptor")
    local entry = Definitions.entries[id] or {}
    for _, component in ipairs({"presentation", "behavior"}) do
        local value = descriptor[component]
        if value then
            assert(type(value) == "table", "invalid " .. component .. ": " .. id)
            assert(not entry[component] or entry[component] == value, "conflicting " .. component .. ": " .. id)
        end
    end
    if descriptor.behavior then
        assert(type(descriptor.behavior.matches) == "function" and type(descriptor.behavior.inspect) == "function",
            "behavior needs matches and inspect: " .. id)
    end
    if descriptor.presentation then
        for _, kind in ipairs(descriptor.types or {}) do
            assert(type(kind) == "string" and kind ~= "", "invalid presentation type: " .. id)
            assert(not Definitions.types[kind] or Definitions.types[kind] == id, "duplicate presentation: " .. kind)
        end
    end
    if descriptor.behavior and not entry.behavior then
        Definitions.behaviorOrder[#Definitions.behaviorOrder + 1] = id
    end
    entry.presentation = descriptor.presentation or entry.presentation
    entry.behavior = descriptor.behavior or entry.behavior
    if descriptor.presentation then
        for _, kind in ipairs(descriptor.types or {}) do Definitions.types[kind] = id end
    end
    entry.types = entry.types or descriptor.types or descriptor.behavior and descriptor.behavior.types
    Definitions.entries[id] = entry
    return entry
end

function Definitions.registerBehavior(id, behavior)
    return Definitions.register(id, {behavior = behavior})
end

function Definitions.resolve(action)
    local Food = PZSurvivorToolkit.BulkFood
    local kind = action and action.Type
    if action and Food and (Food.isCommand(action) or (Food.isOpening and Food.isOpening(action))
        or (Food.isOpeningWait and Food.isOpeningWait(action))) then kind = "ISEatFoodAction" end
    local id = kind and Definitions.types[kind]
    local entry = id and Definitions.entries[id]
    return entry and entry.presentation, id
end

function Definitions.behavior(action)
    local found, foundId
    for _, id in ipairs(Definitions.behaviorOrder) do
        local behavior = Definitions.entries[id].behavior
        local ok, matches = pcall(behavior.matches, action)
        if not ok then return nil end
        if matches then
            if found then return nil end -- Ambiguous contracts never grant queue control.
            found, foundId = behavior, id
        end
    end
    return found, foundId
end

function Definitions.inspect(action)
    local behavior, id = Definitions.behavior(action)
    if not behavior then return nil end
    local ok, contract = pcall(behavior.inspect, action)
    if not ok then return nil end
    return contract, id, behavior
end

local prefix = "UI_PZSurvivorToolkit_queue_action_"
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
local medicalKeys = {
    HApplyBandage = "ContextMenu_Apply_Bandage", HRemoveBandage = "ContextMenu_Remove_Bandage",
    HReplaceBandage = "UI_MHP_ReplaceBandage",
    HDisinfect = "ContextMenu_Disinfect", HStitch = "ContextMenu_Stitch", HRemoveStitch = "ContextMenu_Remove_Stitch",
    HSplint = "ContextMenu_Splint", HRemoveSplint = "ContextMenu_Remove_Splint",
    HRemoveGlass = "ContextMenu_Remove_Glass", HRemoveBullet = "ContextMenu_Remove_Bullet", HCleanBurn = "ContextMenu_Clean_Burn",
    HApplyComfrey = "ContextMenu_ComfreyCataplasm", HApplyGarlic = "ContextMenu_GarlicCataplasm", HApplyPlantain = "ContextMenu_PlantainCataplasm",
}
local function preparation(action)
    local description = Definitions.resolve(action)
    local Food = PZSurvivorToolkit.BulkFood
    return action.toolkitBulkPreparation == true
        or (Food and Food.isOpening and Food.isOpening(action))
        or description and (description.role == "preparation" or description.role == "return") or false
end

local function title(action)
    if action.Type == "HealthPanelAction" and type(action.handler) == "table" then
        local key = medicalKeys[action.handler.Type]
        if key then return getText(key), key end
    end
    if (action.toolkitWorldOperation == "generator" or action.toolkitWorldOperation == "fire")
        and type(action.toolkitActionLabel) == "string" then
        return getText(action.toolkitActionLabel), action.toolkitActionLabel
    end
    if action.toolkitWorldOperation == "wreck" then
        return getText("ContextMenu_RemoveBurntVehicle"), "ContextMenu_RemoveBurntVehicle"
    end
    if action.toolkitWorldOperation == "butcher" then
        return getText("UI_PZSurvivorToolkit_queue_native_ISButcherAnimal"), "UI_PZSurvivorToolkit_queue_native_ISButcherAnimal"
    end
    if action.toolkitWorldOperation == "fuel" then
        local key = action.toolkitFuelTake and "ContextMenu_VehicleSiphonGas" or "ContextMenu_VehicleAddGas"
        return getText(key), key
    end
    if action.toolkitWorldOperation == "appliance" then
        local key = action.toolkitApplianceLabel or prefix .. "power"
        return getText(key), key
    end
    if action.Type == "ISAddTakeDispenserBottle" then
        local key = prefix .. (action.bottle and "add_dispenser" or "remove_dispenser")
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
    local presentation = Definitions.resolve(action)
    local modeKey = presentation and presentation.modes and presentation.modes[action[presentation.modeField or "mode"]]
    local key = modeKey or presentation and presentation.key
    if action.Type == "ISApplyBandage" then
        key = action.doIt == false and "ContextMenu_Remove_Bandage" or "ContextMenu_Apply_Bandage"
    elseif action.Type == "ISSplint" then
        key = action.doIt == false and "ContextMenu_Remove_Splint" or "ContextMenu_Splint"
    elseif action.Type == "ISStitch" then
        key = action.doIt == false and "ContextMenu_Remove_Stitch" or "ContextMenu_Stitch"
    end
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
    local presentation = Definitions.resolve(action)
    if presentation then
        local modeKey = presentation.modes and presentation.modes[action[presentation.modeField or "mode"]]
        key = modeKey or presentation.key
        return getText(key), key
    end
    -- Unknown presentation is independent of behavioral recognition.
    return getText(prefix .. "unknown", tostring(action.Type or "?"))
end



local native = {
    ISAddGasolineToVehicle = {key = "ContextMenu_VehicleAddGas", family = "vehicle", targets = {"vehicle", "part"}},
    ISAttachTrailerToVehicle = {key = "UI_PZSurvivorToolkit_queue_native_ISAttachTrailerToVehicle", family = "vehicle", targets = {"vehicleA"}},
    ISCloseVehicleDoor = {key = "UI_PZSurvivorToolkit_queue_native_ISCloseVehicleDoor", family = "vehicle", targets = {"vehicle", "part"}},
    ISConfigHeadlight = {key = "UI_PZSurvivorToolkit_queue_native_ISConfigHeadlight", family = "vehicle", targets = {"vehicle", "part"}},
    ISDeflateTire = {key = "IGUI_JobType_DeflateTire", family = "vehicle", targets = {"vehicle", "part"}},
    ISDetachTrailerFromVehicle = {key = "UI_PZSurvivorToolkit_queue_native_ISDetachTrailerFromVehicle", family = "vehicle", targets = {"vehicle", "part"}},
    ISDropVehicleItemAction = {key = "IGUI_JobType_Dropping", family = "vehicle", targets = {"vehicle", "part"}},
    ISEnterVehicle = {key = "UI_PZSurvivorToolkit_queue_native_ISEnterVehicle", family = "vehicle", targets = {"vehicle", "part"}},
    ISExitVehicle = {key = "UI_PZSurvivorToolkit_queue_native_ISExitVehicle", family = "vehicle", targets = {"vehicle", "part"}},
    ISFixVehiclePartAction = {key = "IGUI_JobType_Repair", family = "vehicle", targets = {"vehiclePart"}},
    ISHorn = {key = "UI_PZSurvivorToolkit_queue_native_ISHorn", family = "vehicle", targets = {}},
    ISHotwireVehicle = {key = "UI_PZSurvivorToolkit_queue_native_ISHotwireVehicle", family = "vehicle", targets = {}},
    ISInflateTire = {key = "IGUI_JobType_InflateTire", family = "vehicle", targets = {"vehicle", "part"}},
    ISInstallVehiclePart = {key = "IGUI_Install", family = "vehicle", targets = {"vehicle", "part"}},
    ISLightbarUITimedAction = {key = "UI_PZSurvivorToolkit_queue_native_ISLightbarUITimedAction", family = "vehicle", targets = {}},
    ISLockDoors = {key = "UI_PZSurvivorToolkit_queue_native_ISLockDoors", family = "vehicle", targets = {"vehicle", "part"}, modeField = "locked", modes = {[true] = "UI_PZSurvivorToolkit_queue_native_ISLockDoors_lock", [false] = "UI_PZSurvivorToolkit_queue_native_ISLockDoors_unlock"}},
    ISLockVehicleDoor = {key = "UI_PZSurvivorToolkit_queue_native_ISLockVehicleDoor", family = "vehicle", targets = {"vehicle", "part"}},
    ISOpenCloseVehicleWindow = {key = "UI_PZSurvivorToolkit_queue_native_ISOpenCloseVehicleWindow", family = "vehicle", targets = {"vehicle", "part"}, modeField = "open", modes = {[true] = "UI_PZSurvivorToolkit_queue_native_ISOpenCloseVehicleWindow_open", [false] = "UI_PZSurvivorToolkit_queue_native_ISOpenCloseVehicleWindow_close"}},
    ISOpenMechanicsUIAction = {key = "UI_PZSurvivorToolkit_queue_native_ISOpenMechanicsUIAction", family = "vehicle", targets = {"vehicle", "part"}},
    ISOpenVehicleDoor = {key = "UI_PZSurvivorToolkit_queue_native_ISOpenVehicleDoor", family = "vehicle", targets = {"vehicle", "part"}},
    ISPathFindAction = {role = "preparation", key = prefix .. "walk", family = "movement", targets = {}},
    ISRefuelFromGasPump = {key = "UI_PZSurvivorToolkit_queue_native_ISRefuelFromGasPump", family = "vehicle", targets = {"vehicle", "part"}},
    ISRemoveBurntVehicle = {key = "ContextMenu_RemoveBurntVehicle", family = "vehicle", targets = {"vehicle", "part"}},
    ISRepairEngine = {key = "IGUI_RepairEngine", family = "vehicle", targets = {"vehicle", "part"}},
    ISRepairLightbar = {key = "ContextMenu_Repair", family = "vehicle", targets = {"vehicle", "part"}},
    ISShutOffVehicleEngine = {key = "UI_PZSurvivorToolkit_queue_native_ISShutOffVehicleEngine", family = "vehicle", targets = {}},
    ISSmashVehicleWindow = {key = "UI_PZSurvivorToolkit_queue_native_ISSmashVehicleWindow", family = "vehicle", targets = {"vehicle", "part"}},
    ISStartVehicleEngine = {key = "UI_PZSurvivorToolkit_queue_native_ISStartVehicleEngine", family = "vehicle", targets = {}},
    ISStopVehicle = {key = "UI_PZSurvivorToolkit_queue_native_ISStopVehicle", family = "vehicle", targets = {}},
    ISSwitchVehicleSeat = {key = "UI_PZSurvivorToolkit_queue_native_ISSwitchVehicleSeat", family = "vehicle", targets = {}},
    ISTakeEngineParts = {key = "IGUI_TakeEngineParts", family = "vehicle", targets = {"vehicle", "part"}},
    ISTakeGasolineFromVehicle = {key = "ContextMenu_VehicleSiphonGas", family = "vehicle", targets = {"vehicle", "part"}},
    ISUninstallVehiclePart = {key = "UI_PZSurvivorToolkit_queue_native_ISUninstallVehiclePart", family = "vehicle", targets = {"vehicle", "part"}},
    ISUnlockVehicleDoor = {key = "UI_PZSurvivorToolkit_queue_native_ISUnlockVehicleDoor", family = "vehicle", targets = {"vehicle", "part"}},
    ISWashVehicle = {key = "UI_PZSurvivorToolkit_queue_native_ISWashVehicle", family = "vehicle", targets = {"vehicle", "part"}},
    ISOpenCloseLid = {key = "UI_PZSurvivorToolkit_queue_native_ISOpenCloseLid", family = "movement", targets = {"barrel"}},
    ISOpenContainerTimedAction = {key = "UI_PZSurvivorToolkit_queue_native_ISOpenContainerTimedAction", family = "movement", targets = {}},
    ISWalkToTimedAction = {role = "preparation", key = prefix .. "walk", family = "movement", targets = {}},
    ISWalkToTimedActionF = {role = "preparation", key = prefix .. "walk", family = "movement", targets = {}},
    ISAddFluidFromItemAction = {key = "IGUI_JobType_PourOut", family = "hygiene", targets = {"objectTo", "itemFrom"}},
    ISAddTakeDispenserBottle = {key = "UI_PZSurvivorToolkit_queue_native_ISAddTakeDispenserBottle", family = "hygiene", targets = {"waterdispenser", "bottle"}},
    ISAddWaterToTrough = {key = "IGUI_JobType_PourOut", family = "animal", targets = {"objectTo", "itemFrom"}},
    ISApplyMakeUp = {key = "UI_PZSurvivorToolkit_queue_native_ISApplyMakeUp", family = "hygiene", targets = {"item"}},
    ISCleanBlood = {key = "UI_PZSurvivorToolkit_queue_native_ISCleanBlood", family = "hygiene", targets = {}},
    ISCleanGraffiti = {key = "UI_PZSurvivorToolkit_queue_native_ISCleanGraffiti", family = "hygiene", targets = {"object"}},
    ISConsolidateDrainable = {key = "IGUI_JobType_PourIn", family = "hygiene", targets = {"drainable", "intoItem"}},
    ISDrinkFluidAction = {key = "ContextMenu_Drink", family = "hygiene", targets = {"item"}},
    ISDrinkFromBottle = {key = "ContextMenu_Drink", family = "hygiene", targets = {"item"}},
    ISDryMyself = {key = "UI_PZSurvivorToolkit_queue_native_ISDryMyself", family = "hygiene", targets = {"item"}},
    ISDumpContentsAction = {key = "IGUI_JobType_PourOut", family = "hygiene", targets = {"item"}},
    ISDumpWaterAction = {key = "IGUI_JobType_PourOut", family = "hygiene", targets = {"item"}},
    ISDyeHair = {key = "UI_PZSurvivorToolkit_queue_native_ISDyeHair", family = "hygiene", targets = {}},
    ISEatFoodAction = {key = "ContextMenu_Eat", family = "hygiene", targets = {"item"}},
    ISEmptyRainBarrelAction = {key = "UI_PZSurvivorToolkit_queue_native_ISEmptyRainBarrelAction", family = "hygiene", targets = {"object"}},
    ISEmptyWaterInTrough = {key = "UI_PZSurvivorToolkit_queue_native_ISEmptyWaterInTrough", family = "animal", targets = {"objectTo"}},
    ISFluidEmptyAction = {key = "IGUI_JobType_PourOut", family = "hygiene", targets = {"containerOwner"}},
    ISFluidPanelAction = {key = "UI_PZSurvivorToolkit_queue_native_ISFluidPanelAction", family = "hygiene", targets = {}},
    ISFluidTransferAction = {key = "UI_PZSurvivorToolkit_queue_native_ISFluidTransferAction", family = "hygiene", targets = {"sourceOwner", "targetOwner"}},
    ISTakeWaterAction = {key = "ContextMenu_Fill", family = "hygiene", targets = {"waterObject", "item"}},
    ISTransferWaterAction = {key = "UI_PZSurvivorToolkit_queue_native_ISTransferWaterAction", family = "hygiene", targets = {"itemFrom", "itemTo"}},
    ISTrimBeard = {key = "UI_PZSurvivorToolkit_queue_native_ISTrimBeard", family = "hygiene", targets = {"item"}},
    ISWashClothing = {key = "UI_PZSurvivorToolkit_queue_native_ISWashClothing", family = "hygiene", targets = {"sink", "item"}},
    ISWashYourself = {key = "UI_PZSurvivorToolkit_queue_native_ISWashYourself", family = "hygiene", targets = {"sink"}},
    ISAddAnimalInTrailer = {key = "UI_PZSurvivorToolkit_queue_native_ISAddAnimalInTrailer", family = "animal", targets = {"animal"}},
    ISAttachAnimalToPlayer = {key = "UI_PZSurvivorToolkit_queue_native_ISAttachAnimalToPlayer", family = "animal", targets = {"animal"}, modeField = "remove", modes = {[true] = "UI_PZSurvivorToolkit_queue_native_ISAttachAnimalToPlayer_release", [false] = "UI_PZSurvivorToolkit_queue_native_ISAttachAnimalToPlayer_lead"}},
    ISAttachAnimalToTree = {key = "UI_PZSurvivorToolkit_queue_native_ISAttachAnimalToTree", family = "animal", targets = {"animal", "tree"}, modeField = "remove", modes = {[true] = "UI_PZSurvivorToolkit_queue_native_ISAttachAnimalToTree_untie", [false] = "UI_PZSurvivorToolkit_queue_native_ISAttachAnimalToTree_tie"}},
    ISButcherAnimal = {key = "UI_PZSurvivorToolkit_queue_native_ISButcherAnimal", family = "animal", targets = {"body"}},
    ISCheckAnimalInsideTrailer = {key = "UI_PZSurvivorToolkit_queue_native_ISCheckAnimalInsideTrailer", family = "animal", targets = {"vehicle", "part"}},
    ISCutAnimalOnHook = {key = "UI_PZSurvivorToolkit_queue_native_ISCutAnimalOnHook", family = "animal", targets = {"body", "hook"}},
    ISDropAnimalCorpseAndThen = {key = "IGUI_JobType_Dropping", family = "animal", targets = {"item"}},
    ISFeedAnimalFromHand = {key = "UI_PZSurvivorToolkit_queue_native_ISFeedAnimalFromHand", family = "animal", targets = {"animal", "food"}},
    ISGatherBloodFromAnimal = {key = "IGUI_Animal_GatheringBlood", family = "animal", targets = {"body", "hook"}},
    ISGetAnimalBones = {key = "UI_PZSurvivorToolkit_queue_native_ISGetAnimalBones", family = "animal", targets = {"body"}},
    ISGetHutchInfo = {key = "UI_PZSurvivorToolkit_queue_native_ISGetHutchInfo", family = "animal", targets = {"animal"}},
    ISGiveWaterToAnimal = {key = "UI_PZSurvivorToolkit_queue_native_ISGiveWaterToAnimal", family = "animal", targets = {"animal"}},
    ISHutchCleanFloor = {key = "UI_PZSurvivorToolkit_queue_native_ISHutchCleanFloor", family = "animal", targets = {"hutch"}},
    ISHutchCleanNest = {key = "UI_PZSurvivorToolkit_queue_native_ISHutchCleanNest", family = "animal", targets = {"hutch"}},
    ISHutchGrabAnimal = {key = "UI_PZSurvivorToolkit_queue_native_ISHutchGrabAnimal", family = "animal", targets = {"hutch"}},
    ISHutchGrabCorpseAction = {key = "ContextMenu_Grab", family = "animal", targets = {"animal", "corpse"}},
    ISHutchGrabEgg = {key = "UI_PZSurvivorToolkit_queue_native_ISHutchGrabEgg", family = "animal", targets = {"hutch"}},
    ISInspectAnimalTrackAction = {key = "UI_PZSurvivorToolkit_queue_native_ISInspectAnimalTrackAction", family = "animal", targets = {"track"}},
    ISKillAnimal = {key = "UI_PZSurvivorToolkit_queue_native_ISKillAnimal", family = "animal", targets = {"animal"}},
    ISKillAnimalInInventory = {key = "ContextMenu_KillAnimal", family = "animal", targets = {}},
    ISLureAnimal = {key = "UI_PZSurvivorToolkit_queue_native_ISLureAnimal", family = "animal", targets = {"animal"}},
    ISMilkAnimal = {key = "ContextMenu_Milk", family = "animal", targets = {"animal"}},
    ISOpenAnimalInfo = {key = "UI_PZSurvivorToolkit_queue_native_ISOpenAnimalInfo", family = "animal", targets = {"animal"}},
    ISOpenButcherHookUI = {key = "UI_PZSurvivorToolkit_queue_native_ISOpenButcherHookUI", family = "animal", targets = {"hook"}},
    ISPetAnimal = {key = "UI_PZSurvivorToolkit_queue_native_ISPetAnimal", family = "animal", targets = {"animal"}},
    ISPickupAnimal = {key = "UI_PZSurvivorToolkit_queue_native_ISPickupAnimal", family = "animal", targets = {"animal"}},
    ISPutAnimalInHutch = {key = "UI_PZSurvivorToolkit_queue_native_ISPutAnimalInHutch", family = "animal", targets = {"hutch"}},
    ISPutAnimalOnHook = {key = "UI_PZSurvivorToolkit_queue_native_ISPutAnimalOnHook", family = "animal", targets = {"body", "hook"}},
    ISRemoveAnimalFromHook = {key = "UI_PZSurvivorToolkit_queue_native_ISRemoveAnimalFromHook", family = "animal", targets = {"body", "hook"}},
    ISRemoveAnimalFromTrailer = {key = "UI_PZSurvivorToolkit_queue_native_ISRemoveAnimalFromTrailer", family = "animal", targets = {"animal"}},
    ISRemoveHeadFromAnimal = {key = "IGUI_Animal_RemovingHead", family = "animal", targets = {"body", "hook"}},
    ISRemoveLeatherFromAnimal = {key = "IGUI_Animal_RemovingLeather", family = "animal", targets = {"body", "hook"}},
    ISRemoveMeatFromAnimal = {key = "IGUI_Animal_GatheringMeat", family = "animal", targets = {"body", "hook"}},
    ISShearAnimal = {key = "ContextMenu_Shear", family = "animal", targets = {"animal"}},
    ISToggleHutchDoor = {key = "UI_PZSurvivorToolkit_queue_native_ISToggleHutchDoor", family = "animal", targets = {"hutch"}},
    ISToggleHutchEggHatchDoor = {key = "UI_PZSurvivorToolkit_queue_native_ISToggleHutchEggHatchDoor", family = "animal", targets = {"hutch"}},
    ISAttachItemHotbar = {key = "UI_PZSurvivorToolkit_queue_native_ISAttachItemHotbar", family = "inventory", targets = {"item"}},
    ISClothingExtraAction = {key = prefix .. "clothing", family = "inventory", targets = {"item"}},
    ISDetachItemHotbar = {key = "UI_PZSurvivorToolkit_queue_native_ISDetachItemHotbar", family = "inventory", targets = {"item"}},
    ISDropCorpseAction = {key = "UI_PZSurvivorToolkit_queue_native_ISDropCorpseAction", family = "inventory", targets = {}},
    ISDropCorpseIntoContainer = {key = "UI_PZSurvivorToolkit_queue_native_ISDropCorpseIntoContainer", family = "inventory", targets = {}},
    ISDropWorldItemAction = {key = "IGUI_JobType_Dropping", family = "inventory", targets = {"item"}},
    ISEquipHeavyItem = {role = "preparation", key = "UI_PZSurvivorToolkit_queue_native_ISEquipHeavyItem", family = "inventory", targets = {"item"}},
    ISGrabCorpseAction = {key = "ContextMenu_Grab", family = "inventory", targets = {"corpse"}},
    ISGrabCorpseItem = {key = "UI_PZSurvivorToolkit_queue_native_ISGrabCorpseItem", family = "inventory", targets = {"item"}},
    ISGrabItemAction = {key = "ContextMenu_Grab", family = "inventory", targets = {"item"}},
    ISInventoryTransferAction = {key = prefix .. "transfer", family = "inventory", targets = {"item"}},
    ISPickUpGroundCoverItem = {key = "UI_PZSurvivorToolkit_queue_native_ISPickUpGroundCoverItem", family = "inventory", targets = {"object"}},
    ISPickupBrokenGlass = {key = "UI_PZSurvivorToolkit_queue_native_ISPickupBrokenGlass", family = "inventory", targets = {}},
    ISPickupDung = {key = "ContextMenu_RakeDung", family = "inventory", targets = {"item"}},
    ISUnequipAction = {role = "preparation", key = "ContextMenu_Unequip", family = "inventory", targets = {"item"}},
    ISWearClothing = {role = "preparation", key = "ContextMenu_Wear", family = "inventory", targets = {"item"}},
    ISWringClothing = {key = "UI_PZSurvivorToolkit_queue_native_ISWringClothing", family = "hygiene", targets = {"item"}},
    ISAddItemInRecipe = {key = "UI_PZSurvivorToolkit_queue_native_ISAddItemInRecipe", family = "craft", targets = {"baseItem"}},
    ISCraftAction = {key = prefix .. "craft", family = "craft", targets = {"item"}},
    ISCraftAnimAction = {key = "UI_PZSurvivorToolkit_queue_native_ISCraftAnimAction", family = "craft", targets = {"entity"}},
    ISCutHair = {key = "ContextMenu_CutHair", family = "hygiene", targets = {"item"}},
    ISFixAction = {key = "ContextMenu_Repair", family = "craft", targets = {"item"}},
    ISGenericCraftStart = {key = "UI_PZSurvivorToolkit_queue_native_ISGenericCraftStart", family = "craft", targets = {"entity"}, role = "preparation"},
    ISHandcraftAction = {key = prefix .. "craft", family = "craft", targets = {}},
    ISResearchRecipe = {key = "ContextMenu_Research", family = "craft", targets = {"item"}},
    ISStartCraftProcessorAction = {key = "UI_PZSurvivorToolkit_queue_native_ISStartCraftProcessorAction", family = "craft", targets = {"entity"}},
    HealthPanelAction = {key = "UI_PZSurvivorToolkit_queue_native_HealthPanelAction", family = "medical", targets = {"otherPlayer", "bodyPart"}, role = "preparation"},
    ISApplyBandage = {key = "ContextMenu_Apply_Bandage", family = "medical", targets = {"otherPlayer", "bodyPart"}},
    ISCleanBandage = {key = "UI_PZSurvivorToolkit_queue_native_ISCleanBandage", family = "medical", targets = {"waterObject", "item"}},
    ISCleanBurn = {key = "ContextMenu_Clean_Burn", family = "medical", targets = {"otherPlayer", "bodyPart"}},
    ISComfreyCataplasm = {key = "ContextMenu_ComfreyCataplasm", family = "medical", targets = {"otherPlayer", "bodyPart"}},
    ISDisinfect = {key = "ContextMenu_Disinfect", family = "medical", targets = {"otherPlayer", "bodyPart"}},
    ISGarlicCataplasm = {key = "ContextMenu_GarlicCataplasm", family = "medical", targets = {"otherPlayer", "bodyPart"}},
    ISMedicalCheckAction = {key = "ContextMenu_Medical_Check", family = "medical", targets = {"otherPlayer"}},
    ISPlantainCataplasm = {key = "ContextMenu_PlantainCataplasm", family = "medical", targets = {"otherPlayer", "bodyPart"}},
    ISRemoveBullet = {key = "ContextMenu_Remove_Bullet", family = "medical", targets = {"otherPlayer", "bodyPart"}},
    ISRemoveGlass = {key = "ContextMenu_Remove_Glass", family = "medical", targets = {"otherPlayer", "bodyPart"}},
    ISSplint = {key = "ContextMenu_Splint", family = "medical", targets = {"otherPlayer", "bodyPart"}},
    ISStitch = {key = "ContextMenu_Stitch", family = "medical", targets = {"otherPlayer", "bodyPart"}},
    ISTakePillAction = {key = "ContextMenu_Take_pills", family = "medical", targets = {"item"}},
    ISEjectMagazine = {key = "ContextMenu_EjectMagazine", family = "weapon", targets = {"gun"}},
    ISEquipWeaponAction = {role = "preparation", key = "UI_PZSurvivorToolkit_queue_native_ISEquipWeaponAction", family = "inventory", targets = {"item"}},
    ISInsertMagazine = {key = "ContextMenu_InsertMagazine", family = "weapon", targets = {"gun", "magazine"}},
    ISLoadBulletsInMagazine = {key = prefix .. "load_magazine", family = "weapon", targets = {"magazine"}},
    ISRackFirearm = {key = prefix .. "rack", family = "weapon", targets = {"gun"}},
    ISReloadWeaponAction = {key = "IGUI_JobType_LoadBulletsIntoFirearm", family = "weapon", targets = {"gun"}},
    ISRemoveWeaponUpgrade = {key = "ContextMenu_Remove_Weapon_Upgrade", family = "weapon", targets = {"weapon"}},
    ISUnloadBulletsFromFirearm = {key = "IGUI_JobType_UnloadBulletsFromFirearm", family = "weapon", targets = {"gun"}},
    ISUnloadBulletsFromMagazine = {key = "ContextMenu_UnloadMagazine", family = "weapon", targets = {"magazine"}},
    ISUpgradeWeapon = {key = "ContextMenu_Add_Weapon_Upgrade", family = "weapon", targets = {"weapon"}},
    ISActivateCarBatteryChargerAction = {key = "UI_PZSurvivorToolkit_queue_native_ISActivateCarBatteryChargerAction", family = "device", targets = {"charger"}, modeField = "activate", modes = {[true] = "UI_PZSurvivorToolkit_queue_native_ISActivateCarBatteryChargerAction_on", [false] = "UI_PZSurvivorToolkit_queue_native_ISActivateCarBatteryChargerAction_off"}},
    ISActivateGenerator = {key = "UI_PZSurvivorToolkit_queue_native_ISActivateGenerator", family = "device", targets = {"generator"}, modeField = "activate", modes = {[true] = "UI_PZSurvivorToolkit_queue_native_ISActivateGenerator_on", [false] = "UI_PZSurvivorToolkit_queue_native_ISActivateGenerator_off"}},
    ISAddFuel = {key = "ContextMenu_GeneratorAddFuel", family = "device", targets = {"generator"}},
    ISAddFuelAction = {key = "UI_PZSurvivorToolkit_queue_native_ISAddFuelAction", family = "device", targets = {"campfire", "item"}},
    ISBBQAddFuel = {key = "UI_PZSurvivorToolkit_queue_native_ISBBQAddFuel", family = "device", targets = {"fireplace"}},
    ISBBQExtinguish = {key = "UI_PZSurvivorToolkit_queue_native_ISBBQExtinguish", family = "device", targets = {"bbq"}},
    ISBBQInfoAction = {key = "UI_PZSurvivorToolkit_queue_native_ISBBQInfoAction", family = "device", targets = {"bbq"}},
    ISBBQInsertPropaneTank = {key = "UI_PZSurvivorToolkit_queue_native_ISBBQInsertPropaneTank", family = "device", targets = {"bbq", "tank"}},
    ISBBQLightFromKindle = {key = "UI_PZSurvivorToolkit_queue_native_ISBBQLightFromKindle", family = "device", targets = {"bbq", "item"}},
    ISBBQLightFromLiterature = {key = "UI_PZSurvivorToolkit_queue_native_ISBBQLightFromLiterature", family = "device", targets = {"bbq", "item"}},
    ISBBQLightFromPetrol = {key = "UI_PZSurvivorToolkit_queue_native_ISBBQLightFromPetrol", family = "device", targets = {"bbq"}},
    ISBBQRemovePropaneTank = {key = "UI_PZSurvivorToolkit_queue_native_ISBBQRemovePropaneTank", family = "device", targets = {"bbq"}},
    ISBBQToggle = {key = "UI_PZSurvivorToolkit_queue_native_ISBBQToggle", family = "device", targets = {"bbq"}},
    ISCampingInfoAction = {key = "UI_PZSurvivorToolkit_queue_native_ISCampingInfoAction", family = "device", targets = {"campfire"}},
    ISConnectCarBatteryToChargerAction = {key = "ContextMenu_AddBattery", family = "device", targets = {"charger", "battery"}},
    ISDeviceBatteryAction = {key = "UI_PZSurvivorToolkit_queue_native_ISDeviceBatteryAction", family = "device", targets = {}},
    ISDeviceMediaAction = {key = "UI_PZSurvivorToolkit_queue_native_ISDeviceMediaAction", family = "device", targets = {}},
    ISFixGenerator = {key = "UI_PZSurvivorToolkit_queue_native_ISFixGenerator", family = "device", targets = {"generator"}},
    ISGeneratorInfoAction = {key = "UI_PZSurvivorToolkit_queue_native_ISGeneratorInfoAction", family = "device", targets = {"object"}},
    ISHurricaneLanternExtinguish = {key = "UI_PZSurvivorToolkit_queue_native_ISHurricaneLanternExtinguish", family = "device", targets = {"item"}},
    ISInsertLightSourceFuelAction = {key = "UI_PZSurvivorToolkit_queue_native_ISInsertLightSourceFuelAction", family = "device", targets = {"lightSource"}},
    ISLightActions = {modes = {AddLightBulb = prefix .. "add_bulb", RemoveLightBulb = prefix .. "remove_bulb", ModifyLamp = prefix .. "modify_lamp", AddBattery = "ContextMenu_AddBattery", RemoveBattery = "ContextMenu_Remove_Battery"}, key = "UI_PZSurvivorToolkit_queue_native_ISLightActions", family = "device", targets = {"lightswitch", "item"}},
    ISLightFromKindle = {key = "UI_PZSurvivorToolkit_queue_native_ISLightFromKindle", family = "device", targets = {"campfire", "item"}},
    ISLightFromLiterature = {key = "UI_PZSurvivorToolkit_queue_native_ISLightFromLiterature", family = "device", targets = {"campfire", "item"}},
    ISLightFromPetrol = {key = "UI_PZSurvivorToolkit_queue_native_ISLightFromPetrol", family = "device", targets = {"campfire"}},
    ISLitCandleExtinguish = {key = "UI_PZSurvivorToolkit_queue_native_ISLitCandleExtinguish", family = "device", targets = {"item"}},
    ISOvenUITimedAction = {key = "ContextMenu_StoveSetting", family = "device", targets = {}},
    ISPlaceCarBatteryChargerAction = {key = "UI_PZSurvivorToolkit_queue_native_ISPlaceCarBatteryChargerAction", family = "device", targets = {"charger"}},
    ISPlugGenerator = {key = "UI_PZSurvivorToolkit_queue_native_ISPlugGenerator", family = "device", targets = {"generator"}, modeField = "plug", modes = {[true] = "UI_PZSurvivorToolkit_queue_native_ISPlugGenerator_connect", [false] = "UI_PZSurvivorToolkit_queue_native_ISPlugGenerator_disconnect"}},
    ISPutOutCampfireAction = {key = "UI_PZSurvivorToolkit_queue_native_ISPutOutCampfireAction", family = "device", targets = {"campfire"}},
    ISPutOutFire = {key = "UI_PZSurvivorToolkit_queue_native_ISPutOutFire", family = "device", targets = {"item"}},
    ISRadioAction = {key = "UI_PZSurvivorToolkit_queue_native_ISRadioAction", family = "device", targets = {"device"}},
    ISRemoveCampfireAction = {key = "UI_PZSurvivorToolkit_queue_native_ISRemoveCampfireAction", family = "device", targets = {"campfire"}},
    ISRemoveCarBatteryFromChargerAction = {key = "UI_PZSurvivorToolkit_queue_native_ISRemoveCarBatteryFromChargerAction", family = "device", targets = {"charger"}},
    ISRemoveLightSourceFuelAction = {key = "UI_PZSurvivorToolkit_queue_native_ISRemoveLightSourceFuelAction", family = "device", targets = {"lightSource"}},
    ISSetComboWasherDryerMode = {key = "UI_PZSurvivorToolkit_queue_native_ISSetComboWasherDryerMode", family = "device", targets = {"object"}},
    ISStopAlarmClockAction = {key = "UI_PZSurvivorToolkit_queue_native_ISStopAlarmClockAction", family = "device", targets = {"alarm"}},
    ISTakeCarBatteryChargerAction = {key = "UI_PZSurvivorToolkit_queue_native_ISTakeCarBatteryChargerAction", family = "device", targets = {"charger"}},
    ISTakeFuel = {key = "ContextMenu_TakeGasFromPump", family = "device", targets = {}},
    ISTakeGenerator = {key = "UI_PZSurvivorToolkit_queue_native_ISTakeGenerator", family = "device", targets = {"generator"}},
    ISToggleClothingDryer = {key = prefix .. "power", family = "device", targets = {"object"}},
    ISToggleClothingWasher = {key = prefix .. "power", family = "device", targets = {"object"}},
    ISToggleComboWasherDryer = {key = prefix .. "power", family = "device", targets = {"object"}},
    ISToggleLightAction = {key = "UI_PZSurvivorToolkit_queue_native_ISToggleLightAction", family = "device", targets = {"object"}},
    ISToggleLightSourceAction = {key = "UI_PZSurvivorToolkit_queue_native_ISToggleLightSourceAction", family = "device", targets = {"lightSource"}},
    ISToggleStoveAction = {key = prefix .. "power", family = "device", targets = {"object"}},
    ISBurnCorpseAction = {key = "IGUI_JobType_Burn", family = "world", targets = {"corpse"}},
    AIAttachLureAction = {key = "UI_PZSurvivorToolkit_queue_native_AIAttachLureAction", family = "fishing", targets = {"rod"}},
    AIRemoveLureAction = {key = "ContextMenu_Remove_Bait", family = "fishing", targets = {"rod"}},
    AddChumToWaterAction = {key = "ContextMenu_Add_Bait", family = "fishing", targets = {}},
    CreateChumFromGroundSandAction = {key = "UI_PZSurvivorToolkit_queue_native_CreateChumFromGroundSandAction", family = "fishing", targets = {}},
    ISAddBaitAction = {key = "UI_PZSurvivorToolkit_queue_native_ISAddBaitAction", family = "fishing", targets = {"trap", "bait"}},
    ISAddBaitToFishNetAction = {key = "ContextMenu_Add_Bait", family = "fishing", targets = {"fishNet", "bait"}},
    ISChangeFishingRodEquip = {key = "UI_ChangeFishingRodEquip", family = "fishing", targets = {"rod", "item"}},
    ISCheckFishingNetAction = {key = "UI_PZSurvivorToolkit_queue_native_ISCheckFishingNetAction", family = "fishing", targets = {"trap"}},
    ISCheckTrapAction = {key = "UI_PZSurvivorToolkit_queue_native_ISCheckTrapAction", family = "fishing", targets = {"trap"}},
    ISPickupFishAction = {key = "UI_PZSurvivorToolkit_queue_native_ISPickupFishAction", family = "fishing", targets = {"rod", "item"}},
    ISPlaceFishingNetAction = {key = "UI_PZSurvivorToolkit_queue_native_ISPlaceFishingNetAction", family = "fishing", targets = {"item"}},
    ISPlaceTrap = {key = "UI_PZSurvivorToolkit_queue_native_ISPlaceTrap", family = "fishing", targets = {"weapon"}},
    ISRemoveBaitAction = {key = "UI_PZSurvivorToolkit_queue_native_ISRemoveBaitAction", family = "fishing", targets = {"trap"}},
    ISRemoveFishingNetAction = {key = "UI_PZSurvivorToolkit_queue_native_ISRemoveFishingNetAction", family = "fishing", targets = {"trap"}},
    ISRemoveTrapAction = {key = "UI_PZSurvivorToolkit_queue_native_ISRemoveTrapAction", family = "fishing", targets = {"trap"}},
    ISTakeTrap = {key = "UI_PZSurvivorToolkit_queue_native_ISTakeTrap", family = "fishing", targets = {"trap"}},
    ISQueueActionsAction = {key = "UI_PZSurvivorToolkit_queue_native_ISQueueActionsAction", family = "helper", targets = {}, role = "preparation"},
    ISWaitWhileGettingUp = {key = "UI_PZSurvivorToolkit_queue_native_ISWaitWhileGettingUp", family = "helper", targets = {}, role = "preparation"},
    ISAddSheetAction = {key = "UI_PZSurvivorToolkit_queue_native_ISAddSheetAction", family = "world", targets = {"item"}},
    ISAddSheetRope = {key = "UI_PZSurvivorToolkit_queue_native_ISAddSheetRope", family = "world", targets = {"window"}},
    ISBarricadeAction = {key = "UI_PZSurvivorToolkit_queue_native_ISBarricadeAction", family = "world", targets = {"item"}},
    ISBuildAction = {key = "UI_PZSurvivorToolkit_queue_native_ISBuildAction", family = "world", targets = {"item"}},
    ISBuryCorpse = {key = "UI_PZSurvivorToolkit_queue_native_ISBuryCorpse", family = "world", targets = {}},
    ISClearAshes = {key = "UI_PZSurvivorToolkit_queue_native_ISClearAshes", family = "world", targets = {}},
    ISClimbOverFence = {key = "UI_PZSurvivorToolkit_queue_native_ISClimbOverFence", family = "movement", targets = {"item"}},
    ISClimbSheetRopeAction = {key = "UI_PZSurvivorToolkit_queue_native_ISClimbSheetRopeAction", family = "movement", targets = {}, modeField = "down", modes = {[true] = "UI_PZSurvivorToolkit_queue_native_ISClimbSheetRopeAction_down", [false] = "UI_PZSurvivorToolkit_queue_native_ISClimbSheetRopeAction_up"}},
    ISClimbThroughWindow = {key = "UI_PZSurvivorToolkit_queue_native_ISClimbThroughWindow", family = "movement", targets = {"item"}},
    ISDestroyStuffAction = {key = "UI_PZSurvivorToolkit_queue_native_ISDestroyStuffAction", family = "world", targets = {"item"}},
    ISDismantleAction = {key = "ContextMenu_Disassemble", family = "world", targets = {"thumpable"}},
    ISExtendedPlacementAction = {key = "UI_PZSurvivorToolkit_queue_native_ISExtendedPlacementAction", family = "world", targets = {"item"}},
    ISFillGrave = {key = "ContextMenu_Dig", family = "world", targets = {"item"}},
    ISItemSlotRemoveAction = {key = "UI_PZSurvivorToolkit_queue_native_ISItemSlotRemoveAction", family = "world", targets = {"entity", "item"}},
    ISLockDoor = {key = "UI_PZSurvivorToolkit_queue_native_ISLockDoor", family = "world", targets = {"door"}, modeField = "lock", modes = {[true] = "UI_PZSurvivorToolkit_queue_native_ISLockDoor_lock", [false] = "UI_PZSurvivorToolkit_queue_native_ISLockDoor_unlock"}},
    ISMoveablesAction = {key = "UI_PZSurvivorToolkit_queue_native_ISMoveablesAction", family = "world", targets = {"object", "item"}, modeField = "mode", modes = {["pickup"] = "UI_PZSurvivorToolkit_queue_native_ISMoveablesAction_pickup", ["place"] = "UI_PZSurvivorToolkit_queue_native_ISMoveablesAction_place", ["rotate"] = "UI_PZSurvivorToolkit_queue_native_ISMoveablesAction_rotate", ["repair"] = "UI_PZSurvivorToolkit_queue_native_ISMoveablesAction_repair", ["scrap"] = "UI_PZSurvivorToolkit_queue_native_ISMoveablesAction_scrap"}},
    ISMultiStageBuild = {key = "UI_PZSurvivorToolkit_queue_native_ISMultiStageBuild", family = "world", targets = {"item"}},
    ISOpenCloseCurtain = {key = "UI_PZSurvivorToolkit_queue_native_ISOpenCloseCurtain", family = "world", targets = {"item"}},
    ISOpenCloseDoor = {key = "UI_PZSurvivorToolkit_queue_native_ISOpenCloseDoor", family = "world", targets = {"item"}},
    ISOpenCloseWindow = {key = "UI_PZSurvivorToolkit_queue_native_ISOpenCloseWindow", family = "world", targets = {"object"}},
    ISPadlockAction = {key = "UI_PZSurvivorToolkit_queue_native_ISPadlockAction", family = "world", targets = {"thump"}, modeField = "lock", modes = {[true] = "UI_PZSurvivorToolkit_queue_native_ISPadlockAction_lock", [false] = "UI_PZSurvivorToolkit_queue_native_ISPadlockAction_unlock"}},
    ISPadlockByCodeAction = {key = "UI_PZSurvivorToolkit_queue_native_ISPadlockByCodeAction", family = "world", targets = {"thump"}, modeField = "lock", modes = {[true] = "UI_PZSurvivorToolkit_queue_native_ISPadlockByCodeAction_lock", [false] = "UI_PZSurvivorToolkit_queue_native_ISPadlockByCodeAction_unlock"}},
    ISPaintAction = {key = "UI_PZSurvivorToolkit_queue_native_ISPaintAction", family = "world", targets = {"thumpable"}},
    ISPaintSignAction = {key = "UI_PZSurvivorToolkit_queue_native_ISPaintSignAction", family = "world", targets = {"wall"}},
    ISPlasterAction = {key = "UI_PZSurvivorToolkit_queue_native_ISPlasterAction", family = "world", targets = {"thumpable"}},
    ISPlumbItem = {key = "UI_PZSurvivorToolkit_queue_native_ISPlumbItem", family = "world", targets = {"itemToPipe"}},
    ISRemoveBrokenGlass = {key = "UI_PZSurvivorToolkit_queue_native_ISRemoveBrokenGlass", family = "world", targets = {"window"}},
    ISRemoveBush = {key = "UI_PZSurvivorToolkit_queue_native_ISRemoveBush", family = "farming", targets = {"weapon"}},
    ISRemoveGrass = {key = "UI_PZSurvivorToolkit_queue_native_ISRemoveGrass", family = "farming", targets = {}},
    ISRemovePatch = {key = "ContextMenu_RemovePatch", family = "craft", targets = {"clothing"}},
    ISRemoveSheetAction = {key = "UI_PZSurvivorToolkit_queue_native_ISRemoveSheetAction", family = "world", targets = {"item"}},
    ISRemoveSheetRope = {key = "UI_PZSurvivorToolkit_queue_native_ISRemoveSheetRope", family = "world", targets = {"window"}},
    ISRepairClothing = {key = "UI_PZSurvivorToolkit_queue_native_ISRepairClothing", family = "craft", targets = {"clothing"}},
    ISSmashWindow = {key = "UI_PZSurvivorToolkit_queue_native_ISSmashWindow", family = "world", targets = {"vehiclePart"}},
    ISTakeBricks = {key = "UI_PZSurvivorToolkit_queue_native_ISTakeBricks", family = "world", targets = {"item"}},
    ISThrowCorpseOverFence = {key = "UI_PZSurvivorToolkit_queue_native_ISThrowCorpseOverFence", family = "world", targets = {}},
    ISThrowCorpseThroughWindow = {key = "UI_PZSurvivorToolkit_queue_native_ISThrowCorpseThroughWindow", family = "world", targets = {"window"}},
    ISUnbarricadeAction = {key = "UI_PZSurvivorToolkit_queue_native_ISUnbarricadeAction", family = "world", targets = {"item"}},
    ISWallpaperAction = {key = "UI_PZSurvivorToolkit_queue_native_ISWallpaperAction", family = "world", targets = {"thumpable"}},
    ISAddCompost = {key = "UI_PZSurvivorToolkit_queue_native_ISAddCompost", family = "farming", targets = {"item"}},
    ISChopTreeAction = {key = "ContextMenu_Chop_Tree", family = "farming", targets = {"tree"}},
    ISCurePlantAction = {key = "ContextMenu_Treat_Problem", family = "farming", targets = {"plant", "item"}},
    ISDigStairsAction = {key = "UI_PZSurvivorToolkit_queue_native_ISDigStairsAction", family = "world", targets = {"item"}},
    ISFertilizeAction = {key = "ContextMenu_Fertilize", family = "farming", targets = {"plant", "item"}},
    ISForageAction = {key = "UI_PZSurvivorToolkit_queue_native_ISForageAction", family = "farming", targets = {}},
    ISGetCompost = {key = "UI_PZSurvivorToolkit_queue_native_ISGetCompost", family = "farming", targets = {"item"}},
    ISHarvestPlantAction = {key = "UI_PZSurvivorToolkit_queue_native_ISHarvestPlantAction", family = "farming", targets = {"plant"}},
    ISPickAxeGroundCoverItem = {key = "UI_PZSurvivorToolkit_queue_native_ISPickAxeGroundCoverItem", family = "farming", targets = {"item"}},
    ISPlantInfoAction = {key = "UI_PZSurvivorToolkit_queue_native_ISPlantInfoAction", family = "farming", targets = {"plant"}},
    ISPlowAction = {key = "ContextMenu_Dig", family = "farming", targets = {"item"}},
    ISScything = {key = "ContextMenu_ScytheGrass", family = "farming", targets = {"item"}},
    ISSeedActionNew = {key = "UI_PZSurvivorToolkit_queue_native_ISSeedActionNew", family = "farming", targets = {"plant"}},
    ISShovelAction = {key = "ContextMenu_Remove", family = "farming", targets = {"plant", "item"}},
    ISShovelGround = {key = "UI_PZSurvivorToolkit_queue_native_ISShovelGround", family = "farming", targets = {"item"}},
    ISWaterPlantAction = {key = "ContextMenu_Water", family = "farming", targets = {"item"}},
    ISFitnessAction = {key = "UI_PZSurvivorToolkit_queue_native_ISFitnessAction", family = "leisure", targets = {}},
    ISGetOnBedAction = {key = "UI_PZSurvivorToolkit_queue_native_ISGetOnBedAction", family = "leisure", targets = {"bed"}},
    ISItemSlotAddAction = {key = "UI_PZSurvivorToolkit_queue_native_ISItemSlotAddAction", family = "world", targets = {"entity", "item"}},
    ISReadABook = {key = "ContextMenu_Read", family = "leisure", targets = {"item"}},
    ISReadWorldMap = {key = "ContextMenu_CheckMap", family = "leisure", targets = {}},
    ISRestAction = {key = "UI_PZSurvivorToolkit_queue_native_ISRestAction", family = "leisure", targets = {"bed"}},
    ISSitOnGround = {key = "UI_PZSurvivorToolkit_queue_native_ISSitOnGround", family = "leisure", targets = {"bed"}},
    ISWakeOtherPlayer = {key = "UI_PZSurvivorToolkit_queue_native_ISWakeOtherPlayer", family = "leisure", targets = {"otherPlayer"}},
    ISWriteSomething = {key = "UI_PZSurvivorToolkit_queue_native_ISWriteSomething", family = "leisure", targets = {"item"}},
}
for kind, presentation in pairs(native) do
    Definitions.register("native." .. kind, {types = kind == "ISCampingInfoAction" and {kind, "IsCampfireInfoAction"} or {kind}, presentation = presentation})
end

for kind, presentation in pairs({
    ISCartTransferAction = {key = prefix .. "transfer", family = "inventory", targets = {"item"}},
    PZSurvivorToolkitSetStoveState = {key = prefix .. "power", targets = {"object"}, modeField = "desired",
        modes = {[true] = prefix .. "stove_on", [false] = prefix .. "stove_off"}},
    PJCK_SequenceWaitAction = {key = prefix .. "wait", role = "preparation"},
    WMI_WaitForInvUpdate = {key = prefix .. "wait", role = "preparation"},
    P4RestoreAction = {key = prefix .. "restore", role = "return", targets = {"item"}},
    P4RestoreFloorAction = {key = prefix .. "return", role = "return", targets = {"item"}},
    NEQ_AttachAction = {key = prefix .. "attach", role = "preparation", targets = {"item"}},
    PZSTUninstallToGround = {key = prefix .. "uninstall_ground", targets = {"vehicle", "part"}},
}) do
    Definitions.register("mod." .. kind, {types = {kind}, presentation = presentation})
end

local function instance(value, class)
    return value ~= nil and instanceof(value, class)
end

local function name(value)
    if instance(value, "InventoryItem") then return value:getDisplayName() end
    if instance(value, "IsoObject") then return ISWorldObjectContextMenu.getMoveableDisplayName(value) end
    if instance(value, "BaseVehicle") then
        local script = value:getScript()
        return script and getText("IGUI_VehicleName" .. (script:getCarModelName() or script:getName()))
    end
    if instance(value, "VehiclePart") then return getText("IGUI_VehiclePart" .. value:getId()) end
    if instance(value, "IsoPlayer") then return value:getDisplayName() end
    if instance(value, "BodyPart") then return BodyPartType.getDisplayName(value:getType()) end
    if instance(value, "IsoAnimal") then return value:getFullName() end
    if instance(value, "ItemContainer") then
        local parent = value:getParent()
        local objectName = parent and name(parent)
        return objectName or getText("IGUI_ContainerTitle_" .. value:getType())
    end
end

local function target(action, presentation)
    if action.Type == "HealthPanelAction" and type(action.handler) == "table" then
        local panel = action.handler.panel
        local health = PZSurvivorToolkit.ActionQueueHealth
        local actor = health and health.patient and health.patient(action) or type(panel) == "table" and panel.character
        local patient, body = name(actor), name(action.handler.bodyPart)
        if patient and body then return patient .. " / " .. body end
        return patient or body
    end
    if action.toolkitWorldOperation == "build" or action.Type == "ISBuildAction" then
        local recipe = action.craftRecipe or (action.item and action.item.craftRecipe)
        if instance(recipe, "CraftRecipe") then return recipe:getTranslationName() end
        local objectName = action.toolkitWorldName or (action.item and action.item.name)
        if objectName then return Translator.getMoveableDisplayName(objectName) end
    end
    if action.toolkitWorldDismantle or action.Type == "ISMoveablesAction" then
        local objectName = action.toolkitWorldName or (action.moveProps and action.moveProps.name)
        if objectName then return Translator.getMoveableDisplayName(objectName) end
    end
    if action.toolkitWorldOperation == "wreck" or action.toolkitWorldOperation == "fuel" then
        return name(action.toolkitWorldTarget or action.vehicle)
    end
    if action.toolkitWorldOperation == "appliance" or action.toolkitWorldOperation == "generator"
        or action.toolkitWorldOperation == "fire" then return name(action.toolkitWorldTarget) end
    if action.toolkitWorldOperation == "butcher" then return name(action.body) end
    if action.Type == "ISDeviceBatteryAction" or action.Type == "ISDeviceMediaAction" then
        local device = instance(action.deviceData, "DeviceData") and action.deviceData:getParent()
        return name(device)
    end
    if action.Type == "ISInventoryTransferAction" or action.Type == "ISCartTransferAction" then return name(action.item) end
    if action.plant and type(action.plant.typeOfSeed) == "string" then
        return getText("Farming_" .. action.plant.typeOfSeed)
    end
    local parts, seen = {}, {}
    if instance(action.vehiclePart, "VehiclePart") then
        local vehicle = action.vehiclePart:getVehicle()
        local display = name(vehicle)
        if display then parts[#parts + 1], seen[vehicle] = display, true end
    end
    for _, field in ipairs(presentation and presentation.targets or {"item", "gun", "magazine", "weapon"}) do
        local value = action[field]
        local display = name(value)
        if display and not seen[value] then
            parts[#parts + 1], seen[value] = display, true
        end
    end
    return #parts > 0 and table.concat(parts, " / ") or nil
end

local function icon(action, presentation)
    local fallback = getTexture("media/ui/Entity/Icon_Tools_48x48.png")
    if presentation and presentation.family == "medical" and getItemTex then
        local item = action.item or action.alcohol or action.bandage or action.plank
        local kind = instance(item, "InventoryItem") and item:getFullType()
        if action.Type == "HealthPanelAction" and type(action.args) == "table" then kind = action.args[1] or action.args[2] end
        local texture = kind and kind ~= "Hands" and getItemTex(kind)
        return texture or getItemTex("Base.Bandage") or fallback
    end
    if action.toolkitWorldOperation == "fuel" or action.Type == "ISAddGasolineToVehicle" or action.Type == "ISTakeGasolineFromVehicle" then
        local take = action.toolkitFuelTake or action.Type == "ISTakeGasolineFromVehicle"
        return getTexture(take and "media/ui/vehicles/gas_siphon.png" or "media/ui/vehicles/gas_refuel.png") or fallback
    end
    local Food = PZSurvivorToolkit.BulkFood
    if instance(action.craftRecipe, "CraftRecipe") and not (Food and Food.isOpening and Food.isOpening(action)) then
        local texture = action.craftRecipe:getIconTexture()
        if texture then return texture end
    end
    if action.Type == "ISWalkToTimedAction" or action.Type == "ISWalkToTimedActionF" or action.Type == "ISPathFindAction" then
        return getTexture("media/ui/craftingMenus/BuildProperty_Walking.png") or fallback
    end
    for _, field in ipairs(presentation and presentation.targets or {"item", "gun", "magazine", "weapon"}) do
        local item = action[field]
        if instance(item, "InventoryItem") then
            local texture = item:getTex()
            if texture then return texture end
        end
    end
    return fallback
end

local function details(action)
    local lines = {}
    local function add(text) if text then lines[#lines + 1] = text end end
    if action.Type == "ISInventoryTransferAction" or action.Type == "ISCartTransferAction" then
        local source, destination = name(action.srcContainer), name(action.destContainer)
        if source and destination then add(source .. " -> " .. destination) end
    elseif action.Type == "ISFluidTransferAction" then
        local source = name(action.sourceOwner or action.sourceFluidObject)
        local destination = name(action.targetOwner or action.targetFluidObject)
        if source and destination then add(source .. " -> " .. destination) end
    elseif action.Type == "ISTransferWaterAction" then
        local source, destination = name(action.itemFrom), name(action.itemTo)
        if source and destination then add(source .. " -> " .. destination) end
    elseif action.Type == "ISRadioAction" then
        if action.mode == "SetChannel" then add(getText(prefix .. "channel_value", action.secondaryItem)) end
        if action.mode == "SetVolume" then add(getText(prefix .. "volume_value", action.secondaryItem)) end
    end
    if action.Type == "ISUpgradeWeapon" then add(name(action.part)) end
    if action.Type == "ISRemoveWeaponUpgrade" and action.partType then add(getText("Tooltip_weapon_" .. action.partType)) end
    if action.Type == "ISClothingExtraAction" and action.extra then add(Translator.getMoveableDisplayName(action.extra)) end
    local amount = action.ammoCount or action.amount or action.percentage or action.uses
    if type(amount) == "number" then add(getText(prefix .. "count", amount)) end
    return #lines > 0 and table.concat(lines, " <LINE> ") or nil
end

function Definitions.describe(action)
    local presentation, id = Definitions.resolve(action)
    -- Display failures (deleted targets or replaced mod getters) must not fail native enqueue.
    local titleFunction = presentation and presentation.title or title
    local ok, text, signature = pcall(titleFunction, action)
    if not ok then
        signature = presentation and presentation.key
        text = signature and getText(signature) or getText(prefix .. "unknown", tostring(action.Type or "?"))
    end
    local targetOk, targetText = pcall(presentation and presentation.target or target, action, presentation)
    local detailsOk, detailText = pcall(presentation and presentation.details or details, action)
    return {id = id, title = text, signature = signature, target = targetOk and targetText or nil,
        details = detailsOk and detailText or nil,
        role = preparation(action) and "preparation" or presentation and presentation.role,
        icon = function()
            local iconOk, texture = pcall(presentation and presentation.icon or icon, action, presentation)
            return iconOk and texture or getTexture("media/ui/Entity/Icon_Tools_48x48.png")
        end}
end

function Definitions.taskTitle(queue, first, last, refresh)
    local token = queue.queue[first] and queue.queue[first].toolkitQueueOperation
    local saved = token and token.presentation
    if saved and saved.rank == 3 and not refresh then return saved.title end
    local text, signature, mixed, priority
    for i = first, last do
        local action = queue.queue[i]
        local description = Definitions.describe(action)
        local rank = description.role == "preparation" or description.role == "return"
        rank = rank and 1 or action.Type == "ISInventoryTransferAction" and 2 or 3
        if not priority or rank >= priority then
            local kind = description.signature or action.Type or description.title
            if not priority or rank > priority then
                text, signature, mixed, priority = description.title, kind, false, rank
            elseif kind ~= signature then mixed = true end
        end
    end
    text = mixed and getText("UI_PZSurvivorToolkit_queue_mixed") or text
    if token and (not saved or priority >= saved.rank) then
        token.presentation = {title = text, signature = signature, rank = priority}
    end
    return token and token.presentation.title or text
end

function Definitions.resourceLabel(resource)
    local ok, text = pcall(name, resource)
    return ok and text or nil
end

return Definitions
