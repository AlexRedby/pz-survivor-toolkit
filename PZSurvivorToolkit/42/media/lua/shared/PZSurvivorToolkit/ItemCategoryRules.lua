-- Inventory-only classification, adapted from augustaugur's organizedCategories rules.
-- No ScriptItem writes or provider lifecycle hooks. Exact type data lives in ItemCategoryData.
local data = require "PZSurvivorToolkit/ItemCategoryData"
local Legacy = require "PZSurvivorToolkit/LegacyItemCategories"
local Rules = {}

local VANILLA_ALIASES = {
    Accessory = "clothingAccessory_wearable",
    Ammo = "ammunitionFirearm",
    Animal = "petsCare",
    Appearance = "characterHair",
    Bag = "containerWearable",
    Bandage = "medicalFirstAid",
    Camping = "survivalCamping",
    Cartography = "literatureCartography",
    Clothing = "clothingTop",
    Communications = "survivalCommunication",
    Container = "containerGeneral",
    Cooking = "cookingUtensil",
    Electronics = "craftingElectrical",
    Entertainment = "entertainmentHobbies",
    FireSource = "survivalCamping",
    FirstAid = "medicalFirstAid",
    Fishing = "toolFishing",
    Food = "foodPerishable",
    Furniture = "furnitureMiscellaneous",
    Gardening = "farmingMaterial",
    Household = "junkMiscellaneous",
    Instrument = "entertainmentInstrument",
    Junk = "junkMiscellaneous",
    LightSource = "survivalLighting",
    Literature = "literatureReadable",
    MakeUp = "characterMakeup",
    Material = "craftingCarpentry_material",
    Memento = "collectableMemento",
    Paint = "constructionPaint",
    ProtectiveGear = "clothingProtection",
    Security = "securityLock",
    SkillBook = "literatureExperience",
    Sports = "junkSports",
    Tool = "toolSurvival",
    Trapping = "survivalTrapping",
    VehicleMaintenance = "mechanicsVehiclePart",
    WaterContainer = "containerLiquid",
    Weapon = "weaponBlunt",
    WeaponCrafted = "weaponBlunt_crafted",
    WeaponImprovised = "weaponBlunt_improvised",
    WeaponPart = "weaponPart",
}

local FLUID_FP_KEY = "OC_FluidFP"
local FLUID_LAST_KEY = "OC_FluidLast"
local FLUID_CHEAP_KEY = "OC_FluidCheap"
local FLUID_CAT_KEY = "OC_FluidCat"
local FLUID_VER_KEY = "OC_FluidVer"

local FLUID_RESOLVER_VERSION = 3
local ROTTEN_SENTINEL = 100000000
local MIX_AMOUNT_EPSILON = 0.00001

local function isDebugOrWoundItem(fullName)
    if fullName == nil then
        return false
    end
    local text = tostring(fullName)
    return string.find(text, "ZedDmg", 1, true)
        or string.find(text, "DEV", 1, true)
        or string.find(text, "Test", 1, true)
        or string.find(text, "debug", 1, true)
        or string.find(text, "Wound", 1, true)
end

local function isPerishableFood(item)
    if item:getItemType() ~= ItemType.FOOD then
        return false
    end
    local days = item:getDaysTotallyRotten()
    return days > 0 and days < ROTTEN_SENTINEL
end

local function containerNameSuggestsCooking(containerName)
    if not containerName then
        return false
    end
    return containerName:contains("Pot")
        or containerName:contains("Pan")
        or containerName:contains("Bowl")
end

local function categoryFromFluidChecks(hasCategory, item)

    if hasCategory(FluidCategory.Medical) then
        return "medicalFirstAid"
    elseif hasCategory(FluidCategory.Alcoholic) then
        return "foodBeverage_alcoholic"
    elseif hasCategory(FluidCategory.Beverage) then
        return "foodBeverage"
    elseif hasCategory(FluidCategory.Fuel) then

        return "mechanicsFuel"
    elseif hasCategory(FluidCategory.HairDyes) then
        return "characterHair"
    elseif FluidCategory.Dyes and hasCategory(FluidCategory.Dyes) then

        return "craftingTailoring_material"
    elseif hasCategory(FluidCategory.Paint) then
        return "constructionPaint"

    elseif hasCategory(FluidCategory.Water) and isPerishableFood(item) then
        return "foodPerishable"
    elseif hasCategory(FluidCategory.Water) then
        return "containerLiquid"
    elseif hasCategory(FluidCategory.Hazardous) then
        return "cleaningComponent"
    end
    return "containerLiquid"
end

local function categoryFromFluid(fluid, item)
    if not fluid then
        return "containerLiquid"
    end
    return categoryFromFluidChecks(function(cat)
        return fluid:isCategory(cat)
    end, item)
end

local function categoryFromFluidContainer(fluidContainer, item)
    return categoryFromFluidChecks(function(cat)
        return fluidContainer:isCategory(cat)
    end, item)
end

local function fluidTypeString(fluid)
    if not fluid then
        return nil
    end
    local ok, name = pcall(function()
        return fluid:getFluidTypeString()
    end)
    if ok and name and name ~= "" then
        return tostring(name)
    end
    return tostring(fluid)
end

local function mixFingerprint(entries)
    if not entries or #entries == 0 then
        return "empty"
    end
    local parts = {}
    for i = 1, #entries do
        parts[i] = entries[i].type .. "=" .. string.format("%.5f", entries[i].amount)
    end
    table.sort(parts)
    return table.concat(parts, ";")
end

local function parseMixMap(fingerprint)
    local map = {}
    if not fingerprint or fingerprint == "" or fingerprint == "empty"
        or fingerprint == "none" or fingerprint == "filled" then
        return map
    end
    if not string.find(fingerprint, "=", 1, true) then
        return map
    end
    for token in string.gmatch(fingerprint, "[^;]+") do
        local name, amount = token:match("^(.+)=([%d%.eE%+%-]+)$")
        if name and amount then
            map[name] = tonumber(amount) or 0
        end
    end
    return map
end

local function collectFluidEntries(fluidContainer)
    local entries = {}
    if not fluidContainer then
        return entries
    end
    local ok, sample = pcall(function()
        return fluidContainer:createFluidSample()
    end)
    local size = 0
    if ok and sample then
        local sizeOk, sampleSize = pcall(function()
            return sample:size()
        end)
        if sizeOk and sampleSize then
            size = sampleSize
        end
    end
    if (not ok or not sample or size == 0) then
        if sample then
            pcall(function()
                sample:release()
            end)
        end
        sample = nil
        size = 0
        local amountOk, total = pcall(function()
            return fluidContainer:getAmount()
        end)
        if amountOk and total and total > 0 then
            ok, sample = pcall(function()
                return fluidContainer:createFluidSample(total)
            end)
            if ok and sample then
                local sizeOk, sampleSize = pcall(function()
                    return sample:size()
                end)
                if sizeOk and sampleSize then
                    size = sampleSize
                end
            end
        end
    end
    if not sample then
        return entries
    end
    for i = 0, size - 1 do
        local fluidOk, fluid = pcall(function()
            return sample:getFluid(i)
        end)
        if fluidOk and fluid then
            local amount = 0
            local specOk, spec = pcall(function()
                return fluidContainer:getSpecificFluidAmount(fluid)
            end)
            if specOk and spec then
                amount = spec
            else
                local pctOk, pct = pcall(function()
                    return sample:getPercentage(i)
                end)
                if pctOk and pct then
                    amount = pct
                end
            end
            local name = fluidTypeString(fluid)
            if name and amount > MIX_AMOUNT_EPSILON then
                entries[#entries + 1] = {
                    fluid = fluid,
                    type = name,
                    amount = amount,
                }
            end
        end
    end
    pcall(function()
        sample:release()
    end)
    return entries
end

local function pickMixFluid(entries, lastAddedType)
    if not entries or #entries == 0 then
        return nil
    end
    if #entries == 1 then
        return entries[1].fluid
    end
    local total = 0
    for i = 1, #entries do
        total = total + entries[i].amount
    end
    if total <= MIX_AMOUNT_EPSILON then
        return entries[#entries].fluid
    end
    local majority = {}
    for i = 1, #entries do
        local entry = entries[i]
        if entry.amount + entry.amount + MIX_AMOUNT_EPSILON >= total then
            majority[#majority + 1] = entry
        end
    end
    if #majority == 1 then
        return majority[1].fluid
    end
    if lastAddedType then
        for i = 1, #entries do
            if entries[i].type == lastAddedType then
                return entries[i].fluid
            end
        end
    end
    return entries[#entries].fluid
end

local function detectLastAddedType(prevMap, entries)
    if not entries or #entries == 0 then
        return nil
    end
    local bestType = nil
    local bestDelta = 0
    local bestIndex = 0
    for i = 1, #entries do
        local entry = entries[i]
        local prev = prevMap and prevMap[entry.type] or 0
        local delta = entry.amount - prev
        if delta > bestDelta + MIX_AMOUNT_EPSILON then
            bestDelta = delta
            bestType = entry.type
            bestIndex = i
        elseif bestType and math.abs(delta - bestDelta) <= MIX_AMOUNT_EPSILON and delta > MIX_AMOUNT_EPSILON and i >= bestIndex then
            bestType = entry.type
            bestIndex = i
        end
    end
    if bestDelta <= MIX_AMOUNT_EPSILON then
        return nil
    end
    return bestType
end

local function emptyFluidCategory(containerName)
    if containerNameSuggestsCooking(containerName) then
        return "containerCooking"
    end
    return "containerLiquid"
end

local function resolveScriptFluidCategory(item)
    if not item:containsComponent(ComponentType.FluidContainer) then
        return nil
    end

    local fluidScript = item:getComponentScriptFor(ComponentType.FluidContainer)
    if not fluidScript then
        return nil
    end

    local displayCategory = item:getDisplayCategory()
    if displayCategory == "Water" then
        return "foodBeverage"
    end

    local initialFluids = fluidScript:getInitialFluids()
    local hasInitial = initialFluids and initialFluids:size() > 0
    local treatedAsFilled = false
    if hasInitial then
        -- getInitialAmount() rolls a new value for ranged defaults. A script
        -- preview describes possible starting contents, never a sampled item.
        if not toolkitScriptFluidInitialAmounts then return nil end
        local amounts = toolkitScriptFluidInitialAmounts(fluidScript)
        if not amounts then return nil end
        treatedAsFilled = amounts.max > 0
    end

    if treatedAsFilled then

        if displayCategory == "medicalFirstAid" then
            return nil
        end
        local fluid = initialFluids:get(0):getFluid()
        return categoryFromFluid(fluid, item)
    end

    return emptyFluidCategory(fluidScript:getContainerName())
end

local function itemFullType(item)
    if item.getFullType then
        return tostring(item:getFullType() or "")
    end
    if item.getFullName then
        return tostring(item:getFullName() or "")
    end
    return ""
end

local function restoreEmptyFluidCategory(item)
    return Rules.forScript(item:getScriptItem())
        or emptyFluidCategory(item:getFluidContainer():getContainerName())
end

local function resolveLiveFluidCategory(item, entries, lastAddedType)
    if not item:isFluidContainer() then
        return nil
    end

    local fluid = item:getFluidContainer()
    if not fluid then
        return nil
    end

    local amount = fluid:getAmount()
    local displayCategory = item:getDisplayCategory()

    if amount > 0 then
        if displayCategory == "medicalFirstAid" then
            return nil
        end
        local chosen = pickMixFluid(entries, lastAddedType)
        if chosen then
            return categoryFromFluid(chosen, item)
        end
        local primaryOk, primary = pcall(function()
            return fluid:getPrimaryFluid()
        end)
        if primaryOk and primary then
            return categoryFromFluid(primary, item)
        end
        return categoryFromFluidContainer(fluid, item)
    end

    return restoreEmptyFluidCategory(item)
end

local function cheapFluidStamp(fluid)
    if not fluid then
        return "none"
    end
    if fluid.isEmpty and fluid:isEmpty() then
        return "empty"
    end
    local amount = fluid.getAmount and fluid:getAmount() or 0
    if amount <= 0 then
        return "empty"
    end
    local primary = fluid.getPrimaryFluid and fluid:getPrimaryFluid() or nil
    local ptype = ""
    if primary then
        ptype = fluidTypeString(primary) or ""
    end
    return string.format("%.4f:%s", amount, ptype)
end

local function fluidFingerprint(item, fluid)
    fluid = fluid or (item.getFluidContainer and item:getFluidContainer())
    if not fluid then
        return "none", nil, nil
    end
    if fluid:isEmpty() or fluid:getAmount() <= 0 then
        return "empty", nil, nil
    end
    local entries = collectFluidEntries(fluid)
    if #entries > 0 then
        return mixFingerprint(entries), entries, fluid
    end
    local primary = fluid:getPrimaryFluid()
    if primary then
        return primary:getFluidTypeString() or "filled", nil, fluid
    end
    return "filled", nil, fluid
end

local IBL = ItemBodyLocation

local function ibl(name)
    return IBL and IBL[name] or nil
end

local function bodyLocationIs(location, ...)
    for i = 1, select("#", ...) do
        local candidate = select(i, ...)
        if candidate and location == candidate then
            return true
        end
    end
    if location and location.contains then
        for i = 1, select("#", ...) do
            local candidate = select(i, ...)
            if type(candidate) == "string" and location:contains(candidate) then
                return true
            end
        end
    end
    return false
end

local function resolveClothingCategory(item)
    local clothingCategory = item:getBodyLocation()

    if bodyLocationIs(clothingCategory,
            ibl("DRESS"), "Dress",
            ibl("LONG_DRESS"), "LongDress",
            ibl("SHIRT"), "Shirt",
            ibl("FULL_TOP"), "FullShirt",
            ibl("TSHIRT"), "Tshirt",
            ibl("SHORT_SLEEVE_SHIRT"), "ShortSleeveShirt",
            ibl("BOILERSUIT"), "Boilersuit",
            ibl("TANK_TOP"), "TankTop",
            ibl("TORSO_EXTRA_VEST"), "TorsoExtraVest",
            ibl("VEST_TEXTURE"), "VestTexture",
            ibl("TORSO_EXTRA"), "TorsoExtra", "TorsoExra",
            ibl("TORSO1LEGS1"), "Torso1Legs1",
            ibl("TORSO_EXTRA_VEST_BULLET"), "TorsoExtraVestBullet") then
        return "clothingTop"
    elseif bodyLocationIs(clothingCategory,
            ibl("PANTS"), "Pants",
            ibl("SKIRT"), "Skirt",
            ibl("LONG_SKIRT"), "LongSkirt",
            ibl("SHORT_PANTS"), "ShortPants",
            ibl("SHORTS_SHORT"), "ShortsShort",
            ibl("PANTS_EXTRA"), "PantsExtra",
            ibl("LEGS1"), "Legs1",
            ibl("PANTS_SKINNY"), "Pants_Skinny") then
        return "clothingBottom"
    elseif bodyLocationIs(clothingCategory,
            ibl("JACKET"), "Jacket",
            ibl("JACKET_BULKY"), "Jacket_Bulky",
            ibl("SWEATER"), "Sweater",
            ibl("SWEATER_HAT"), "SweaterHat",
            ibl("JACKET_SUIT"), "JacketSuit",
            ibl("BATH_ROBE"), "BathRobe",
            ibl("JACKET_DOWN"), "JacketDown") then
        return "clothingOuterwear"
    elseif bodyLocationIs(clothingCategory,
            ibl("EYES"), "Eyes",
            ibl("LEFT_EYE"), "LeftEye",
            ibl("RIGHT_EYE"), "RightEye") then
        return "clothingAccessory_eyes"
    elseif bodyLocationIs(clothingCategory,
            ibl("HANDS"), "Hands",
            ibl("HANDS_LEFT"), "HandsLeft",
            ibl("HANDS_RIGHT"), "HandsRight") then
        return "clothingHands"
    elseif bodyLocationIs(clothingCategory,
            ibl("HAT"), "Hat",
            ibl("MASK"), "Mask",
            ibl("FULL_HAT"), "FullHat",
            ibl("MASK_EYES"), "MaskEyes") then
        return "clothingAccessory_head"
    elseif bodyLocationIs(clothingCategory,
            ibl("AMMO_STRAP"), "AmmoStrap") then
        return "containerWearable"
    elseif bodyLocationIs(clothingCategory,
            ibl("BELT_EXTRA"), "BeltExtra",
            ibl("ANKLE_HOLSTER"), "AnkleHolster",
            ibl("SHOULDER_HOLSTER"), "ShoulderHolster",
            ibl("WEBBING"), "Webbing",
            ibl("BELT"), "Belt") then
        return "clothingAccessory_beltHolster"
    elseif bodyLocationIs(clothingCategory,
            ibl("UNDERWEAR"), "Underwear",
            ibl("UNDERWEAR_BOTTOM"), "UnderwearBottom",
            ibl("UNDERWEAR_TOP"), "UnderwearTop",
            ibl("UNDERWEAR_EXTRA1"), "UnderwearExtra1",
            ibl("UNDERWEAR_EXTRA2"), "UnderwearExtra2") then
        return "clothingUndergarment"
    elseif bodyLocationIs(clothingCategory,
            ibl("LEFT_WRIST"), "LeftWrist",
            ibl("RIGHT_WRIST"), "RightWrist", "RightWirst",
            ibl("RIGHT_MIDDLE_FINGER"), "Right_MiddleFinger",
            ibl("LEFT_MIDDLE_FINGER"), "Left_MiddleFinger",
            ibl("LEFT_RING_FINGER"), "Left_RingFinger",
            ibl("RIGHT_RING_FINGER"), "Right_RingFinger",
            ibl("NOSE"), "Nose",
            ibl("BELLY_BUTTON"), "BellyButton") then
        return "clothingAccessory_wearable"
    elseif bodyLocationIs(clothingCategory,
            ibl("SCARF"), "Scarf",
            ibl("NECKLACE"), "Necklace",
            ibl("NECKLACE_LONG"), "NecklaceLong") then
        return "clothingAccessory_neck"
    elseif bodyLocationIs(clothingCategory,
            ibl("EARS"), "Ears",
            ibl("EAR_TOP"), "EarTop") then
        return "clothingAccessory_ears"
    elseif bodyLocationIs(clothingCategory, ibl("SHOES"), "Shoes") then
        return "clothingFootwear"
    elseif item:getDisplayCategory() == "Bag" then
        return "containerWearable"
    end
    return "clothingProtection"
end

local function isFirearmScript(item)
    if item:isRanged() then
        return true
    end
    local ammoType = item:getAmmoType()
    if ammoType ~= nil and ammoType ~= "" then
        return true
    end
    if WeaponCategory.FIREARM and item:containsWeaponCategory(WeaponCategory.FIREARM) then
        return true
    end
    return false
end

local function resolveWeaponCategory(item)
    local displayCategory = item:getDisplayCategory()
    if displayCategory == "Explosives" or displayCategory == "Devices" then
        return "weaponBomb"
    end

    if isFirearmScript(item) then
        return "weaponFirearm"
    end

    if item:containsWeaponCategory(WeaponCategory.SMALL_BLADE)
        or item:containsWeaponCategory(WeaponCategory.LONG_BLADE) then
        return "weaponBlade"
    elseif item:containsWeaponCategory(WeaponCategory.SMALL_BLUNT)
        or item:containsWeaponCategory(WeaponCategory.BLUNT) then
        return "weaponBlunt"
    elseif item:containsWeaponCategory(WeaponCategory.AXE) then
        return "weaponAxe"
    elseif item:containsWeaponCategory(WeaponCategory.SPEAR) then
        return "weaponSpear"
    end
    return "weaponFirearm"
end

local function resolveLiteratureCategory(item)
    local skillTrained = item:getSkillTrained()
    if skillTrained and skillTrained ~= "" and SkillBook and SkillBook[skillTrained] then
        return "literatureExperience"
    end

    local learned = item:getLearnedRecipes()
    if learned and learned:size() > 0 then
        return "literatureRecipe"
    end

    if item:getStressChange() ~= 0 or item:getBoredomChange() ~= 0 or item:getUnhappyChange() ~= 0 then
        return "literatureReadable"
    end
    return "literatureWriteable"
end

local MUSIC_CARRIER_CATEGORY = {
    nm_carrier_cassette = "entertainmentAudio_cassette",
    tsarcraft_music_01_62 = "entertainmentAudio_cassette",
    nm_carrier_vinyl = "entertainmentAudio_vinyl",
    tsarcraft_music_01_63 = "entertainmentAudio_vinyl",
    nm_carrier_cd = "entertainmentAudio_cd",
    tsarcraft_music_01_64 = "entertainmentAudio_cd",
}

local function luaStr(value)
    if value == nil then
        return ""
    end
    return tostring(value)
end

local function luaLower(value)
    return string.lower(luaStr(value))
end

local function shortItemType(fullName)
    local text = luaStr(fullName)
    local lastDot = 0
    local pos = string.find(text, ".", 1, true)
    while pos do
        lastDot = pos
        pos = string.find(text, ".", lastDot + 1, true)
    end
    if lastDot > 0 then
        return string.sub(text, lastDot + 1)
    end
    return text
end

local function normalizeMusicCarrier(carrier)
    if carrier == nil or carrier == "" then
        return nil
    end
    local token = luaStr(carrier)
    if NMMediaContract and NMMediaContract.normalizeCarrierToken then
        local ok, normalized = pcall(NMMediaContract.normalizeCarrierToken, token)
        if ok and normalized and normalized ~= "" then
            token = luaStr(normalized)
        end
    end
    return MUSIC_CARRIER_CATEGORY[token]
end

local function lookupGlobalMusicCarrier(fullName, shortType)
    if type(GlobalMusic) ~= "table" then
        return nil
    end
    return GlobalMusic[shortType] or GlobalMusic[fullName]
end

local function scriptFieldLower(item, methodName)
    local ok, value = pcall(function()
        if methodName == "getIcon" then
            return item:getIcon()
        end
        if methodName == "getWorldStaticModel" then
            return item:getWorldStaticModel()
        end
        return nil
    end)
    if not ok or value == nil then
        return ""
    end
    return luaLower(value)
end

local function typeLooksLikeCD(lowerType)
    if string.sub(lowerType, 1, 2) == "cd" then
        return true
    end
    if string.sub(lowerType, -2) == "cd" then
        return true
    end
    if string.find(lowerType, "cdcover", 1, true) then
        return true
    end
    return false
end

local function inferMusicCarrierFromTypeAndVisuals(item, shortType)
    local lowerType = luaLower(shortType)
    if string.find(lowerType, "cassette", 1, true) then
        return "nm_carrier_cassette"
    end
    if string.find(lowerType, "vinyl", 1, true) then
        return "nm_carrier_vinyl"
    end
    if typeLooksLikeCD(lowerType) then
        return "nm_carrier_cd"
    end

    local visual = scriptFieldLower(item, "getIcon") .. " " .. scriptFieldLower(item, "getWorldStaticModel")
    if string.find(visual, "cassette", 1, true) then
        return "nm_carrier_cassette"
    end
    if string.find(visual, "vinyl", 1, true) then
        return "nm_carrier_vinyl"
    end
    if string.find(visual, "nm_cd", 1, true) or string.find(visual, "cdcover", 1, true) then
        return "nm_carrier_cd"
    end
    return nil
end

local function resolveBoundMusicCarrier(fullName)
    if not (NMMediaContract and NMMediaContract.resolveContainerMediaBinding) then
        return nil
    end
    local ok, bound = pcall(NMMediaContract.resolveContainerMediaBinding, fullName)
    if not ok or not bound or bound == "" then
        return nil
    end
    local boundText = luaStr(bound)
    if NMMediaContract.resolveMediaCarrier then
        local okCarrier, carrier = pcall(NMMediaContract.resolveMediaCarrier, boundText)
        if okCarrier and carrier and carrier ~= "" then
            return carrier
        end
    end
    return lookupGlobalMusicCarrier(boundText, shortItemType(boundText))
end

local function resolveMusicMediaCategory(item)
    local displayCategory = luaStr(item:getDisplayCategory())
    if displayCategory ~= "Entertainment" and displayCategory ~= "entertainmentAudio" then
        return nil
    end

    local fullName = luaStr(item:getFullName())
    local shortType = shortItemType(fullName)

    local carrier = resolveBoundMusicCarrier(fullName)
    if not carrier then
        carrier = lookupGlobalMusicCarrier(fullName, shortType)
    end
    if not carrier and NMMediaContract and NMMediaContract.resolveMediaCarrier then
        local ok, resolved = pcall(NMMediaContract.resolveMediaCarrier, fullName)
        if ok then
            carrier = resolved
        end
    end
    if not carrier then
        carrier = inferMusicCarrierFromTypeAndVisuals(item, shortType)
    end
    return normalizeMusicCarrier(carrier)
end

local function looksLikeSeed(item)
    if not (ItemTag and ItemTag.IS_SEED) then
        return false
    end
    local ok, isSeed = pcall(function()
        return item:hasTag(ItemTag.IS_SEED)
    end)
    return ok and isSeed == true
end

local function looksLikeClothing(item)
    if item:getItemType() == ItemType.CLOTHING then
        return true
    end
    local ok, location = pcall(function()
        return item:getBodyLocation()
    end)
    if ok and location ~= nil and luaStr(location) ~= "" then
        return true
    end
    return false
end

local function openVariantBaseCategory(fullName)
    local base = string.match(fullName, "^(.-)Open%d*$")
    return base and data[string.lower(base)] or nil
end

local function resolveAutoSortCategory(item, fullName)

    if item:containsComponent(ComponentType.FluidContainer) then
        return resolveScriptFluidCategory(item)
    end
    if looksLikeSeed(item) then
        return "farmingSeed"
    end
    local itemType = item:getItemType()
    if looksLikeClothing(item) then
        return resolveClothingCategory(item)
    elseif itemType == ItemType.FOOD then
        if isPerishableFood(item) then
            return "foodPerishable"
        end
        return "foodNonPerishable"
    elseif itemType == ItemType.LITERATURE then
        return resolveLiteratureCategory(item)
    elseif itemType == ItemType.WEAPON then
        return resolveWeaponCategory(item)
    elseif item:getDisplayCategory() == "VehicleMaintenance" then
        return "mechanicsVehiclePart"
    end

    local music = resolveMusicMediaCategory(item)
    if music then
        return music
    end

    local inherited = openVariantBaseCategory(fullName)
    if inherited then
        return inherited
    end

    return VANILLA_ALIASES[tostring(item:getDisplayCategory())]
end

local MEDIA_REFINEMENTS = {
    entertainmentVideo = {
        experience = "entertainmentVideo_experience",
        recipe = "entertainmentVideo_recipe",
    },
    entertainmentAudio_cd = {
        experience = "entertainmentAudio_cd_experience",
        recipe = "entertainmentAudio_cd_recipe",
    },
}

local MEDIA_CATEGORY_BASES = {}
for base, refined in pairs(MEDIA_REFINEMENTS) do
    MEDIA_CATEGORY_BASES[base] = base
    MEDIA_CATEGORY_BASES[refined.experience] = base
    MEDIA_CATEGORY_BASES[refined.recipe] = base
end

local MEDIA_STAT_CODES = {
    ANG = true, BOR = true, END = true, FAT = true, FIT = true,
    HUN = true, MOR = true, STS = true, PAN = true, SAN = true,
    SIC = true, PAI = true, DRU = true, THI = true, UHP = true,
}

local mediaKindById = {}

local function scanMediaCodes(codes, found)
    local len = string.len(codes)
    local pos = 1
    while pos <= len do
        local stop = string.find(codes, ",", pos, true)
        local last = stop and stop - 1 or len
        if last - pos + 1 > 4 then
            local code = string.sub(codes, pos, pos + 2)
            if code == "RCP" then
                found.recipe = true
            elseif not MEDIA_STAT_CODES[code] then
                local amount = tonumber(string.sub(codes, pos + 4, last))
                if amount then
                    if string.sub(codes, pos + 3, pos + 3) == "-" then
                        amount = -amount
                    end
                    if amount > 0 then
                        return true
                    end
                end
            end
        end
        pos = last + 2
    end
    return false
end

local function mediaKind(media)
    local id = media:getId()
    local kind = mediaKindById[id]
    if kind ~= nil then
        return kind
    end
    local found = {}
    kind = false
    for i = 0, media:getLineCount() - 1 do
        local line = media:getLine(i)
        local codes = line and line:getCodes()
        if codes and scanMediaCodes(codes, found) then
            kind = "experience"
            break
        end
    end

    if not kind and found.recipe then
        kind = "recipe"
    end
    mediaKindById[id] = kind
    return kind
end

function Rules.refineMediaCategory(item, category)
    local refinements = category and MEDIA_REFINEMENTS[category]
    if not refinements or not item.getMediaData then
        return nil
    end
    local media = item:getMediaData()
    if not media then
        return nil
    end
    local kind = mediaKind(media)
    return kind and refinements[kind] or nil
end

function Rules.getMediaBaseCategory(category)
    return category and MEDIA_CATEGORY_BASES[category] or nil
end

function Rules.fluidCategory(item)
    if not item or Legacy.useVanillaDefaults() then
        return
    end

    local fluid = item.getFluidContainer and item:getFluidContainer() or nil
    local stamp = cheapFluidStamp(fluid)
    if not item.getModData then
        return
    end
    local modData = item:getModData()

    local cachedCategory = modData[FLUID_CAT_KEY]
    if cachedCategory and cachedCategory ~= ""
        and modData[FLUID_VER_KEY] == FLUID_RESOLVER_VERSION
        and modData[FLUID_CHEAP_KEY] == stamp and modData[FLUID_FP_KEY]
    then
        return cachedCategory
    end

    local fingerprint, entries = fluidFingerprint(item, fluid)

    local lastAdded = nil
    if fingerprint == "empty" or fingerprint == "none" then
        modData[FLUID_LAST_KEY] = nil
    else
        lastAdded = detectLastAddedType(parseMixMap(modData[FLUID_FP_KEY]), entries)
            or modData[FLUID_LAST_KEY]
        if lastAdded then
            modData[FLUID_LAST_KEY] = lastAdded
        end
    end

    local autosortCategory = resolveLiveFluidCategory(item, entries, lastAdded)
    modData[FLUID_FP_KEY] = fingerprint
    modData[FLUID_CHEAP_KEY] = stamp
    modData[FLUID_VER_KEY] = FLUID_RESOLVER_VERSION

    modData[FLUID_CAT_KEY] = autosortCategory

    return autosortCategory
end

function Rules.instanceOverride(item)
    if not item or not item.getModData or not Legacy.instancesEnabled() then return nil end
    if item.hasModData and not item:hasModData() then return nil end
    local category = item:getModData().OC_DisplayCategory
    if type(category) == "string" and category ~= "" then return category end
end

local function baseForScript(script)
    if not script then return nil end
    if Legacy.useVanillaDefaults() then return script:getDisplayCategory() end
    local name = tostring(script:getFullName())
    local exact = data[string.lower(name)]
    if exact then return exact end
    local native = script:getDisplayCategory()
    local category = native and tostring(native) or ""
    if isDebugOrWoundItem(name) or (category == "" and name:sub(-6) == "Visual") then return native end
    if category:match("^[a-z]") or category:find("_", 1, true) then return native end

    if not script.getItemType then return VANILLA_ALIASES[category] or native end
    return resolveAutoSortCategory(script, name) or native
end

-- OC autosorts at OnGameBoot and retains those claims. In particular late
-- SkillBook registration must not reclassify an already resolved literature item.
local bootCategories, bootSeen, bootVanilla
function Rules.snapshotScripts()
    if not getAllItems then return end
    local scripts = getAllItems()
    if not scripts then return end
    bootCategories, bootSeen = {}, {}
    bootVanilla = Legacy.useVanillaDefaults()
    for index = 0, scripts:size() - 1 do
        local script = scripts:get(index)
        local key = string.lower(tostring(script:getFullName()))
        bootSeen[key] = true
        bootCategories[key] = baseForScript(script)
    end
end

function Rules.forScript(script)
    if not script then return nil end
    local name = tostring(script:getFullName())
    local legacy = Legacy.forType(name)
    if legacy then return legacy end
    local key = string.lower(name)
    if bootSeen and bootSeen[key] and bootVanilla == Legacy.useVanillaDefaults() then return bootCategories[key] end
    return baseForScript(script)
end

if Events and Events.OnGameBoot then Events.OnGameBoot.Add(Rules.snapshotScripts) end

function Rules.forItem(item)
    local override = Rules.instanceOverride(item)
    if override then return override end
    local script = item.getScriptItem and item:getScriptItem()
    local category = Rules.forScript(script)
    if Legacy.useVanillaDefaults() then
        if not category or category == "" then return item:getCategory() end
        return Rules.refineMediaCategory(item, category) or category
    end
    if not category then return nil end
    if item.isFluidContainer and item:isFluidContainer() then
        local fluid = Rules.fluidCategory(item)
        if fluid then return fluid end
        local container = item:getFluidContainer()
        -- The original classifier deliberately retains an existing medical
        -- category while this container is filled.
        if container and container:getAmount() > 0 then return item:getDisplayCategory() end
    end
    return Rules.refineMediaCategory(item, category) or category
end

return Rules
