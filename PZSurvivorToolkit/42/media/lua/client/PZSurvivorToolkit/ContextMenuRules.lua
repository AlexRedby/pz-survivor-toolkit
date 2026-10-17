local Rules = { groups = {
    "consume", "equipment", "medical", "craft", "maintenance", "electronics",
    "transfer", "world", "vehicle", "farming", "research",
} }
local categories, callbacks, labels = {}, {}, {}
for _, id in ipairs(Rules.groups) do categories[id] = true end

local function register(category, owner, names)
    local path, methods = {}, {}
    for name in owner:gmatch("[^.]+") do path[#path + 1] = name end
    for name in names:gmatch("%S+") do methods[#methods + 1] = name end
    callbacks[#callbacks + 1] = {category = category, owner = owner, path = path, methods = methods}
end

-- B42.21 semantic callbacks; resolve their current identities after other mods have loaded.
register("consume", "ISInventoryPaneContextMenu", [[
    onEatItems onDrinkFluid onDrinkForThirst AutoDrinkOn AutoDrinkOff
]])
register("equipment", "ISInventoryPaneContextMenu", [[
    OnPrimaryWeapon OnSecondWeapon OnTwoHandsEquip onWearItems onUnEquip
    onClothingItemExtra onInspectClothing onUpgradeWeapon onRemoveUpgradeWeapon
    onChangefiremode onLoadBulletsInMagazine onLoadBulletsIntoFirearm onInsertMagazine
    onEjectMagazine onRackGun onUnloadBulletsFromFirearm onUnloadBulletsFromMagazine
    addLure removeLure changeHook changeLine
]])
register("medical", "ISInventoryPaneContextMenu", "onPillsItems onApplyBandage")
register("craft", "ISInventoryPaneContextMenu", "OnCraft OnNewCraft onAddItemInEvoRecipe")
register("craft", "ISEntityUI", "OpenBuildWindow OpenHandcraftWindow")
register("maintenance", "ISInventoryPaneContextMenu", [[
    onFix onWringClothing onDryMyself onDyeHair onMakeUp
    removePatch removeAllPatches repairClothing repairAllClothing
]])
register("electronics", "ISInventoryPaneContextMenu", [[
    onActivateItem onSetAlarm onStopAlarm onSetBombTimer
    OnLinkRemoteController OnResetRemoteControlID OnTriggerRemoteController onPlaceCarBatteryCharger
]])
register("electronics", "ISRadioAndTvMenu", "openRadioPanel openTvPanel")
register("transfer", "ISInventoryPaneContextMenu", [[
    onDropItems onGrabItems onGrabOneItems onGrabHalfItems onMoveItemsTo onPutItems
    equipHeavyItem grabCorpseItem onDumpContents
]])
register("transfer", "ISInventoryPage", "transferAll lootAll removeAll")
register("transfer", "ISFluidContainerMenu", "showInfo transferFluids emptyFluidContainer")
register("world", "ISInventoryPaneContextMenu", [[
    onPlaceItemOnGround onPlaceTrap onFavorite onWanted onUnwanted onNoRecipes onRenameBag onRenameFood
]])
register("world", "ISMoveableContextMenu", "openMovableCursor")
register("research", "ISInventoryPaneContextMenu", [[
    onResearchRecipe onLiteratureItems onMediaText onWriteSomething onCheckMap onRenameMap onInspectTrack
]])
register("farming", "ISInventoryPaneContextMenu", "showGrowingSeasons")

register("consume", "ISWorldObjectContextMenu", "onDrink")
register("medical", "ISWorldObjectContextMenu", "onMedicalCheck")
register("craft", "ISWorldObjectContextMenu", [[
    onDestroy onBarricade onUnbarricade onUnbarricadeMetal onUnbarricadeMetalBar onExcavateStairs
]])
register("maintenance", "ISWorldObjectContextMenu", [[
    onWashClothing onWashYourself onCleanBlood onCleanGraffiti onClearAshes
]])
register("electronics", "ISWorldObjectContextMenu", [[
    onInfoGenerator onPlugGenerator onActivateGenerator onFixGenerator onAddFuelGenerator doAddFuelGenerator
    onToggleThumpableLight onInsertFuel onRemoveFuel onToggleLight onLightBulb onLightModify onLightBattery
    activateRadio onToggleStove onMicrowaveSetting onStoveSetting
    onToggleClothingDryer onToggleClothingWasher onToggleComboWasherDryer onSetComboWasherDryerMode
]])
register("electronics", "ISInventoryPage", "toggleStove")
register("transfer", "ISWorldObjectContextMenu", [[
    onGrabWItem onGrabHalfWItems onGrabAllWItems onGrabCorpseItem onTakeGenerator onTakeWater onTakeFuelNew
    onWaterDispenserBottle onAddFluidFromItem onFluidTransfer onFluidInfo onFluidEmpty
]])
register("farming", "ISWorldObjectContextMenu", [[
    onGetCompost onAddCompost onRakeDung onScytheGrass onRemovePlant onRemoveGrass
]])
register("world", "ISWorldObjectContextMenu", [[
    onExtendedPlacement onRemoveFire onTakeSafeHouse onClaimWar onViewSafeHouse
    onFishingNet onCheckFishingNet onAddBaitToWater onRemoveFishingNet onAddBaitToFishingNet
    onAttachAnimalToTree onChopTree onTrade onCheckStats onWakeOther onRest onSleep
    onButcherHook onTakeTrap onGetDoorKey onLockDoor onUnLockDoor onPlumbItem
    onRemoveDigitalPadlock onPutDigitalPadlock onPutPadlock onRemovePadlock onBurnCorpse
    onClimbSheetRope onAddSheet onRemoveCurtain onOpenCloseCurtain onOpenCloseWindow
    onAddSheetRope onRemoveSheetRope onClimbOverFence onClimbThroughWindow onSmashWindow
    onRemoveBrokenGlass onPickupBrokenGlass onThrowCorpseOverFence onThrowCorpseThroughWindow
    onOpenCloseDoor onWalkTo onGetOnBed onDigGraves onBuryCorpse onFillGrave onSitOnGround
    onPickupGroundCoverItem onRemoveGroundCoverItemStump onRemoveGroundCoverItemPickAxe
    onRemoveGroundCoverItemHammerOrPickAxe
]])
register("world", "ISCampingMenu", [[
    onAddAllFuel onAddFuel onAddMultipleFuel onDisplayInfo onDropCorpse onLightFromKindle
    onLightFromLiterature onLightFromPetrol onPutOutCampfire onRemoveCampfire
]])
register("world", "ISBBQMenu", "onDisplayInfo onExtinguish onInsertPropaneTank onRemovePropaneTank onToggle")
register("world", "ISTrapMenu", "onAddBait onCheckTrap onPlaceTrap onRemoveBait onRemoveTrap")
register("vehicle", "ISVehicleMenu", [[
    onCheckAnimalInside onAddAnimalFromHandsInTrailer onAddAnimalInTrailer onRemoveAnimalFromTrailer
    onRemoveBurntVehicle onDisableAlarm onEnableAlarm onMechanic onSwitchSeat onToggleHeadlights
    onToggleTrunkLocked onToggleHeater onSignalDevice onStartEngine onHotwire onShutOff onInfo onSleep
    onOpenDoor onCloseDoor onLockDoor onUnlockDoor onWash onEnter onEnter2 onExit onShowSeatUI
    onHorn onLightbar onAttachTrailer onDetachTrailer
]])
register("vehicle", "ISVehiclePartMenu", [[
    onInstallPart onUninstallPart onPumpGasoline onAddGasoline onTakeGasoline
    onInflateTire onDeflateTire onDeviceOptions onLockDoor onUnlockDoor onOpenCloseWindow
    onLockDoors onSmashWindow onTakeFuelNew onAddFuelNew
]])
register("vehicle", "ISVehicleMechanics", "onTakeEngineParts onRepairEngine onRepairLightbar")
register("farming", "ISFarmingMenu", [[
    onPlow onInfo onFertilize onCompost onHarvest onWater onMildewCure onFliesCure
    onSlugsCure onAphidsCure onShovel onSeed
]])
register("craft", "PZSurvivorToolkit.BulkClothing", "queue")
register("consume", "PZSurvivorToolkit.BulkFood", "queue queueOne")
register("electronics", "PZSurvivorToolkit.BulkDismantle", "queue")
register("electronics", "PZSurvivorToolkit.BulkBatteries", "queue")
register("equipment", "PZSurvivorToolkit.BulkFirearms", "queueUnload queueAttachments")

-- Only callback-less native headers use labels. Item names and mod callbacks stay unclassified.
local function registerLabels(category, keys)
    for key in keys:gmatch("%S+") do labels[#labels + 1] = {category = category, key = key} end
end
registerLabels("consume", "ContextMenu_Eat ContextMenu_OpenAndEat ContextMenu_Drink ContextMenu_OpenAndDrink")
registerLabels("equipment", [[
    ContextMenu_Wear ContextMenu_ChangeFireMode ContextMenu_Add_Weapon_Upgrade ContextMenu_Remove_Weapon_Upgrade
]])
registerLabels("medical", [[
    ContextMenu_Apply_Bandage ContextMenu_Bandage ContextMenu_Disinfect ContextMenu_Stitch
    ContextMenu_Remove_Glass ContextMenu_Splint ContextMenu_Remove_Bullet ContextMenu_Clean_Burn
    ContextMenu_ComfreyCataplasm ContextMenu_GarlicCataplasm ContextMenu_PlantainCataplasm
]])
registerLabels("maintenance", "ContextMenu_Patch ContextMenu_Repair ContextMenu_CleanBandageEtc")
registerLabels("electronics", [[
    ContextMenu_CarBatteryCharger ContextMenu_CarBatteryCharger_ConnectBattery ContextMenu_GeneratorAddFuel
]])
registerLabels("transfer", "ContextMenu_Move_To ContextMenu_Fluid ContextMenu_TakeGasFromPump")
registerLabels("vehicle", "IGUI_Install ContextMenu_PartInfo IGUI_TakeEngineParts ContextMenu_RemoveAnimalFromTrailer ContextMenu_AddAnimalInTrailer")
registerLabels("farming", "ContextMenu_Water ContextMenu_Treat_Problem ContextMenu_AddCompost")
registerLabels("research", "ContextMenu_Read ContextMenu_Inspect")

local electronicRecipes = {
    DismantleElectronics = true, DismantleMiscElectronics = true, DismantleElectronicsDevice = true,
    DismantlePowerBar = true, DismantleImprovisedLighter = true, RemoveBattery = true,
}
local function sourceEndsWith(option, suffix)
    if not getFilenameOfClosure or type(option.onSelect) ~= "function" then return false end
    local ok, source = pcall(getFilenameOfClosure, option.onSelect)
    return ok and type(source) == "string" and source:gsub("\\", "/"):sub(-#suffix) == suffix
end
local healthHandlers = {}
for name in ([[HApplyBandage HRemoveBandage HApplyComfrey HApplyGarlic HApplyPlantain HDisinfect
    HStitch HRemoveStitch HRemoveGlass HSplint HRemoveSplint HRemoveBullet HCleanBurn]]):gmatch("%S+") do
    healthHandlers[name] = true
end

function Rules.classify(option)
    if type(option) ~= "table" then return nil end
    if categories[option.pzstCategory] and type(option.pzstKey) == "string" and option.pzstKey ~= "" then
        return option.pzstCategory, "toolkit:" .. option.pzstKey
    end
    if option.toolkitBulkUnload and not (option.onSelect or option.toolkitOriginalOnSelect) then
        return "equipment", "toolkit:bulkUnload"
    end
    if option.toolkitBulkAttachments then return "equipment", "text:ContextMenu_Remove_Weapon_Upgrade" end
    if electronicRecipes[option.toolkitBulkRecipe] then
        return "electronics", "callback:ISInventoryPaneContextMenu.OnNewCraft:" .. option.toolkitBulkRecipe
    end

    local callback = option.onSelect or option.toolkitOriginalOnSelect
    local target, recipe, fourth = option.target, option.param1, option.param4
    -- addGetUpOption stores the real callback/target/first argument in param1/2/3.
    if callback and ISContextMenu and callback == ISContextMenu.onGetUpAndThen then
        callback, target, recipe, fourth = option.param1, option.param2, option.param3, option.param6
    end
    if callback then
        for _, rule in ipairs(callbacks) do
            local owner = _G
            for _, name in ipairs(rule.path) do owner = owner and owner[name] end
            if owner then
                for _, method in ipairs(rule.methods) do
                    if callback == owner[method] then
                        local key, category = "callback:" .. rule.owner .. "." .. method, rule.category
                        if rule.owner == "ISInventoryPaneContextMenu" and method == "onFix" and fourth then
                            category, key = "vehicle", key .. ":vehiclePart"
                        end
                        if rule.category == "craft" and rule.owner == "ISInventoryPaneContextMenu"
                            and (method == "OnCraft" or method == "OnNewCraft")
                            and (type(recipe) == "table" or type(recipe) == "userdata") and recipe.getName then
                            local name = recipe:getName()
                            if type(name) == "string" then
                                key = key .. ":" .. name
                                if electronicRecipes[name] then category = "electronics" end
                            end
                        end
                        return category, key
                    end
                end
            end
        end
        -- Health handlers are local classes; their native panel and exact method identify them.
        if type(target) == "table" and healthHandlers[target.Type] and ISHealthPanel
            and type(target.panel) == "table" and getmetatable(target.panel) == ISHealthPanel
            and callback == target.onMenuOptionSelected then
            return "medical", "medical:" .. target.Type
        end
        if sourceEndsWith(option, "/BetterContainers/Categorize.lua") then
            return "world", "mod:BetterContainers.category"
        end
        if sourceEndsWith(option, "/BetterContainers/Upgrades/PinnedItems.lua") then
            return "world", "mod:BetterContainers.pin"
        end
        if sourceEndsWith(option, "/PZSurvivorWishlist/Inventory.lua") then
            return "world", "mod:PZSurvivorWishlist.addWanted"
        end
        return nil
    end
    local name = option.name or option.text
    if type(name) ~= "string" or not getText then return nil end
    for _, rule in ipairs(labels) do
        local translated = getText(rule.key)
        if translated ~= rule.key and name == translated then return rule.category, "text:" .. rule.key end
    end
    return nil
end

function Rules.isRecipeSearch(menu, option)
    if option.onSelect or not option.subOption or not NC_InventorySearch then return false end
    local child = menu:getSubMenu(option.subOption)
    if not child or #child.options == 0 then return false end
    for _, row in ipairs(child.options) do
        if row.isDefaultOption or not row.onSelect or (row.onSelect ~= NC_InventorySearch.searchAsInput
            and row.onSelect ~= NC_InventorySearch.searchAsOutput) then return false end
    end
    return true
end

function Rules.isMore(menu, option)
    if option.onSelect or option.name ~= getText("ContextMenu_More") or not option.subOption then return false end
    local child = menu:getSubMenu(option.subOption)
    if not child or #child.options == 0 then return false end
    for _, row in ipairs(child.options) do
        if not row.isDefaultOption and Rules.classify(row) ~= "world" and not Rules.isRecipeSearch(child, row) then return false end
    end
    return true
end

function Rules.isRecipeSelector(menu, option)
    local child = option.subOption and menu:getSubMenu(option.subOption)
    if not child or #child.options == 0 or not ISInventoryPaneContextMenu then return false end
    for _, row in ipairs(child.options) do
        if row.isDefaultOption or not row.onSelect or (row.onSelect ~= ISInventoryPaneContextMenu.onAddItemInEvoRecipe
            and row.onSelect ~= ISInventoryPaneContextMenu.OnCraft and row.onSelect ~= ISInventoryPaneContextMenu.OnNewCraft) then return false end
    end
    return true
end

function Rules.defaults(menu, options, context, visible)
    local defaults = {}
    if menu.parent or (context and context ~= "inventory" and context ~= "loot") then return defaults end
    local cook, input, fluid
    for _, option in ipairs(options) do
        local _, key = Rules.classify(option)
        if key == "mod:BetterContainers.category" and PZSurvivorToolkit.Settings.itemTags
            and PZSurvivorToolkit.Settings.itemTags() then defaults[option] = "hidden" end
        if Rules.isRecipeSearch(menu, option) then defaults[option] = "world" end
        if PJCK_CookingUI and option.onSelect and option.onSelect == PJCK_CookingUI.OnOpenPanel and visible(option) then cook = option end
        if Rules.classify(option) == "transfer" and not option.onSelect and option.name == getText("ContextMenu_Fluid") then
            defaults[option], fluid = "root", true
        end
        local child = option.subOption and menu:getSubMenu(option.subOption)
        if child and NC_InventorySearch and visible(option) then
            for _, row in ipairs(child.options) do
                if row.onSelect and row.onSelect == NC_InventorySearch.searchAsInput and visible(row) then input = row end
            end
        end
    end
    for _, option in ipairs(options) do
        if input and ISEntityUI and option.onSelect == ISEntityUI.OpenHandcraftWindow and input.target
            and input.target.getFullType and option.param5 == "!" .. input.target:getFullType() then defaults[option] = "hidden" end
        if cook or fluid then
            if option.onSelect and (option.onSelect == ISInventoryPaneContextMenu.onDropItems or option.onSelect == ISInventoryPaneContextMenu.onPlaceItemOnGround) then
                defaults[option] = "root"
            end
        end
        if cook and Rules.isRecipeSelector(menu, option) then
            local covered = true
            for _, row in ipairs(menu:getSubMenu(option.subOption).options) do
                -- Project Cook's ingredient and seasoning lists accept Food only.
                if row.onSelect ~= ISInventoryPaneContextMenu.onAddItemInEvoRecipe or row.param1 ~= cook.param1
                    or not instanceof(row.param2, "Food") then covered = false; break end
            end
            if covered then defaults[option] = "hidden" end
        end
        if context == "inventory" and option.name == "Distribute Loot" and sourceEndsWith(option, "/LootSorter_ContextMenu.lua") then
            local player = getSpecificPlayer(menu.player)
            local page = getPlayerInventory(menu.player)
            local controls = page and page.controlsUI
            local handler = controls and controls.handlers and controls.handlers[ISInventoryWindowControlHandler_LootSorterDistribute]
            if handler and handler.control and player and player:getJoypadBind() == -1 and page:getIsVisible() and controls:getIsVisible()
                and handler.control:getIsVisible()
                and handler.container == page.inventoryPane.inventory then defaults[option] = "hidden" end
        end
    end
    return defaults
end

-- Curated defaults by purpose, not measured player click frequency.
local orders = {
    inventory = {"consume", "medical", "equipment", "research", "transfer", "craft", "maintenance", "electronics", "world", "farming", "vehicle"},
    loot = {"transfer", "equipment", "consume", "medical", "research", "craft", "maintenance", "electronics", "world", "farming", "vehicle"},
    world = {"world", "transfer", "consume", "medical", "electronics", "farming", "craft", "maintenance", "research", "equipment", "vehicle"},
    vehicle = {"vehicle", "transfer", "world", "electronics", "maintenance", "consume", "medical", "equipment", "craft", "farming", "research"},
}
local categoryRanks, methodRanks = {}, {}
for context, order in pairs(orders) do
    categoryRanks[context] = {}
    for index, category in ipairs(order) do categoryRanks[context][category] = index end
end
local function rank(value, names)
    for name in names:gmatch("%S+") do methodRanks[name] = value end
end
rank(10, [[
    onEatItems onDrinkFluid onDrinkForThirst onPillsItems onApplyBandage onLiteratureItems onMediaText onCheckMap
    onActivateItem onStopAlarm openRadioPanel openTvPanel
    OnPrimaryWeapon OnSecondWeapon OnTwoHandsEquip onWearItems onUnEquip
    onGrabItems onGrabOneItems onGrabHalfItems onGrabWItem onGrabHalfWItems onGrabAllWItems
    onOpenCloseDoor onOpenCloseWindow onClimbThroughWindow onClimbOverFence onClimbSheetRope
    onEnter onEnter2 onExit onOpenDoor onCloseDoor onOpenCloseWindow
]])
rank(20, [[
    onMoveItemsTo onPutItems transferAll lootAll onDrink onTakeWater onGetOnBed onSitOnGround
    onWalkTo onRest onSleep onSwitchSeat onStartEngine onShutOff onMechanic
    onAddGasoline onTakeGasoline onPumpGasoline onTakeFuelNew onAddFuelNew
    onLoadBulletsInMagazine onLoadBulletsIntoFirearm onInsertMagazine onEjectMagazine onRackGun
    onToggleStove toggleStove onToggleThumpableLight onActivateGenerator onAddFuelGenerator doAddFuelGenerator
    onHarvest onWater onSeed onFertilize onPlow
]])
rank(60, [[
    onDropItems onPlaceItemOnGround onUnloadBulletsFromFirearm onUnloadBulletsFromMagazine
    onUninstallPart onInstallPart onWash onAttachTrailer onDetachTrailer
]])
rank(80, "onInspectClothing onInspectTrack onResearchRecipe onInfo onInfoGenerator onDisplayInfo showInfo")
rank(90, [[
    AutoDrinkOn AutoDrinkOff onSetAlarm onSetBombTimer onRenameBag onRenameFood onRenameMap
    onWriteSomething onFavorite onWanted onUnwanted onNoRecipes onDyeHair onMakeUp
    OnLinkRemoteController OnResetRemoteControlID onChangefiremode
]])
rank(100, "removeAll onDestroy onRemoveBurntVehicle onBurnCorpse onSmashWindow onClaimWar onDumpContents emptyFluidContainer onFluidEmpty")

function Rules.priority(category, key, context)
    local ranks = categoryRanks[context] or categoryRanks.inventory
    if not ranks[category] then return nil end
    local method = key and key:match("^callback:[^:]+%.([^%.:]+)")
    local weight = methodRanks[method] or 40
    if key == "text:ContextMenu_Eat" or key == "text:ContextMenu_OpenAndEat"
        or key == "text:ContextMenu_Drink" or key == "text:ContextMenu_OpenAndDrink"
        or key == "text:ContextMenu_Wear" or key == "text:ContextMenu_Read" then weight = 10 end
    if key == "toolkit:uninstallGround" then weight = 60 end
    if category == "transfer" and context == "loot" and weight < 60 then weight = math.min(weight, 20) end
    if key == "callback:ISInventoryPaneContextMenu.OnNewCraft:RipClothing"
        or key == "callback:ISInventoryPaneContextMenu.OnNewCraft:RipDenimClothing"
        or key == "callback:PZSurvivorToolkit.BulkClothing.queue" then weight = 25 end
    return weight * 100 + ranks[category]
end

return Rules
