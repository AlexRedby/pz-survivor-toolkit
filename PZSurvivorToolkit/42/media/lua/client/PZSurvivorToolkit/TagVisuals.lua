local Visuals = {}
local Custom = require "PZSurvivorToolkit/TagCustomization"
local green = {r = 0.48, g = 0.80, b = 0.40}
local yellow = {r = 0.95, g = 0.80, b = 0.30}
local blue = {r = 0.40, g = 0.68, b = 0.95}
local red = {r = 0.95, g = 0.43, b = 0.40}
local brown = {r = 0.76, g = 0.56, b = 0.36}
local purple = {r = 0.74, g = 0.58, b = 0.86}
local neutral = {r = 0.80, g = 0.78, b = 0.70}

-- Vanilla B42 inventory icons and UI symbols; no inventory items are created.
local families = {
    food = {green, "Item_Plate"}, cooking = {green, "Item_Pan"},
    farming = {green, "Item_Seeds_Carrot"}, husbandry = {green, "Item_Dogfood"},
    pets = {green, "Item_Dogfood"}, survival = {green, "Item_Lighter"},
    electrical = {yellow, "media/ui/Entity/Energy/icon_energy_electric.png"},
    tool = {blue, "Item_Hammer"}, mechanics = {blue, "Item_Wrench"},
    maintenance = {blue, "Item_Glue"}, cleaning = {blue, "Item_Toothbrush"},
    medical = {red, "media/ui/LootableMaps/map_medcross.png"}, drug = {red, "Item_Pills"},
    material = {brown, "Item_Plank"}, construction = {brown, "Item_Hammer"},
    crafting = {brown, "Item_Hammer"}, furniture = {brown, "media/ui/Sidebar/48/Furniture_On_48.png"},
    clothing = {purple, "Item_ShirtGeneric"}, character = {purple, "Item_Toothbrush"},
    collectable = {purple, "Item_PlushSpiffo"}, entertainment = {purple, "Item_Baseball"},
    readable = {blue, "Item_Book"}, literature = {blue, "Item_Book"}, writeable = {blue, "Item_Paper"},
    container = {blue, "Item_Backpack_Blue"},
    weapon = {red, "Item_HandGun3"}, ammunition = {red, "Item_PistolAmmo"},
    security = {yellow, "Item_Key1"}, placeable = {neutral, "Item_Plank"},
    junk = {neutral, "Item_Money"},
    fresh = {green, "Item_Apple"}, stale = {yellow, "Item_AlarmClock"}, rotten = {brown, "Item_AppleRotten"},
    raw = {red, "Item_Steak"}, cooked = {green, "Item_Pan"}, burnt = {brown, "Item_Charcoal"},
    edible = {green, "Item_Fork"}, dismantle = {blue, "Item_Screwdriver"},
    bandage = {red, "Item_Bandage"}, disinfectant = {red, "Item_Alcohol"}, dirty = {brown, "Item_BandageDirty"},
    ignite = {yellow, "Item_Lighter"}, smelting = {brown, "Item_Ingot_Iron"},
    ingredient = {green, "Item_Pan"}, beverage = {green, "Item_GlassJar"},
    fruit = {green, "Item_Apple"}, vegetable = {green, "Item_Carrots"}, meat = {green, "Item_Steak"},
}
local icons = {
    perishable = "Item_AlarmClock", nonperishable = "Item_CannedCorn", preserved = "Item_CannedPeas",
    fruit = "Item_Apple", meat = "Item_Steak", seasoning = "Item_Salt", beverage = "Item_GlassJar",
    ingredient = "Item_Pan", serving = "Item_Pan", utensil = "Item_Pan",
    electronic = "Item_Battery", power = "Item_Battery", lightbulb = "Item_Flashlight2",
    lighting = "Item_Flashlight2", firstaid = "Item_Bandage", treatment = "Item_Bandage",
    repair = "Item_Glue", vehiclemaintenance = "Item_Wrench", vehiclepart = "Item_Wrench",
    carpentry = "Item_Hammer", cloth = "Item_ShirtGeneric", tailoring = "Item_ShirtGeneric",
    metalworking = "Item_MetalTube", welding = "Item_MetalTube", seed = "Item_Seeds_Carrot",
    firearm = "Item_HandGun3", ranged = "Item_HandGun3", magazine = "Item_PistolAmmo",
    readable = "Item_Book", experience = "Item_Book", recipe = "Item_Book", writeable = "Item_Paper",
    doorkey = "Item_Key1", itemkey = "Item_Key1", vehiclekey = "Item_Key1", keyring = "Item_Key1",
    door = "Item_Doorhinge", hygiene = "Item_Toothbrush", plushie = "Item_PlushSpiffo",
    sports = "Item_Baseball", money = "Item_Money", camping = "Item_Lighter",
    vegetable = "Item_Carrots", liquid = "Item_WaterBottle", fuel = "Item_Petrol",
    fishing = "Item_FishingRod",
    accessory = "Item_Glasses", alcoholic = "Item_BeerBottle", animalcare = "Item_DogTreats",
    animalpart = "Item_Feather", arms = "Item_Chainmail_Sleeve", attachment = "Item_Scope2x",
    audio = "Item_Radio", axe = "Item_Axe", bait = "Item_Worm", base = "Item_BeerBottle",
    belt = "Item_Belt", blade = "Item_KnifeHunting", blunt = "Item_BaseballBat", bomb = "Item_PipeBomb",
    bottom = "Item_Trousers", care = "Item_DogTreats", cartography = "Item_Map", carving = "Item_KnifeHunting",
    cassette = "Item_Cassette1", cd = "Item_CDplayer", comfort = "Item_Pillow", communication = "Item_Radio",
    component = "Item_ScrapMetal", condiment = "Item_Salt", corpse = "Item_Bone", crafted = "Item_SpearStone",
    decorative = "Item_PlushSpiffo", denim = "Item_ShirtDenimBlue", ears = "Item_EarMuffs",
    equipment = "Item_SheepShears", explosive = "Item_PipeBomb", eyes = "Item_Glasses",
    feed = "Item_Dogfood", feet = "Item_Shoes", fitness = "Item_Dumbbell", foraging = "Item_BerryBlack",
    general = "Item_Backpack_Blue", glassmaking = "Item_GlassPane", hair = "Item_HairDye",
    handlehead = "Item_Hammer", hands = "Item_GlovesFingerlessWhite", head = "Item_BaseballHat_3n",
    heating = "Item_Candle", hobbies = "Item_CardDeck", improvised = "Item_SpearStone",
    incendiary = "Item_Molotov", instrument = "Item_GuitarAcoustic", knapping = "Item_Flint",
    leather = "Item_LeatherStrips", legs = "Item_Trousers", lock = "Item_Padlock",
    makeup = "Item_MakeupEyeshadow", masonry = "Item_ClayBrick_Fired", memento = "Item_PhotoAlbum",
    miscellaneous = "Item_Money", mold = "Item_BulletMold", narcotic = "Item_Pills",
    neck = "Item_NecklaceLong_Gold", nonfirearm = "Item_BaseballBat", outerwear = "Item_JacketBlack",
    paint = "Item_Paint_Black", part = "Item_ScrapMetal", plumbing = "Item_Wrench",
    pottery = "Item_Pot", prepared = "Item_GlassWine", protection = "Item_HardHatYellow",
    recreational = "Item_Cigarette", refrigeration = "Item_Cooler", seating = "Item_TableLeg",
    snack = "Item_CornChips", spear = "Item_SpearStone", station = "Item_Anvil_Forged",
    storage = "Item_AmmoCase", surface = "Build_TableLargeWood", tabletop = "Item_CardDeck",
    thrown = "Item_Limestone", top = "Item_ShirtGeneric", toy = "Item_ToyBear", tracking = "Item_CompassDirectional",
    trapping = "Item_Mousetrap", undergarment = "Item_Underwear1", unfinished = "Item_SpearHead_Crude01",
    vehicleaddition = "Item_CarBattery", video = "Item_Cassette3", vinyl = "Item_Disc",
    wall = "Item_Wall", wallpaper = "Item_Wallpaper_BeigeStripe", wearable = "Item_Backpack_Blue",
    window = "Item_WallWindow",
}

local textures, styles = {}, {}

function Visuals.defaults(id, contextTags)
    local family = families[id]
    if not family then
        for _, tag in ipairs(contextTags or {}) do
            if families[tag] then family = families[tag]; break end
        end
    end
    local color = family and family[1] or neutral
    styles[color] = styles[color] or {}
    local key = id or false
    if not styles[color][key] then
        local icon = icons[id] or (families[id] and families[id][2])
        if not icon and type(id) == "string" then
            if id:sub(1, 9) == "category:" then icon = "Item_Clipboard"
            elseif id:sub(1, 8) == "caliber:" then
                local caliber = id:sub(9)
                icon = caliber:sub(-2) == "ga" and "Item_ShotgunAmmo"
                    or caliber:find("paintball", 1, true) and "Item_PistolAmmo"
                    or caliber:find("bb", 1, true) and "Item_PistolAmmo"
                    or (caliber == "9x19mm" or caliber == ".22" or caliber == ".45") and "Item_PistolAmmo"
                    or "Item_RifleAmmo223"
            end
        end
        if icon and textures[icon] == nil then
            textures[icon] = (getTexture and getTexture(icon)) or false
        end
        styles[color][key] = {r = color.r, g = color.g, b = color.b, icon = icon,
            texture = icon and textures[icon] or nil}
    end
    return styles[color][key]
end

local customStyles, revision = {}, -1
function Visuals.get(id, contextTags)
    local base = Visuals.defaults(id, contextTags)
    local current = Custom.cacheRevision()
    if current ~= revision then customStyles, revision = {}, current end
    local definition = id and Custom.definition(id)
    if definition and definition.deleted then return base end
    local inherited, familyId
    if not families[id] then
        for _, tag in ipairs(contextTags or {}) do
            if families[tag] then
                familyId = tag
                local family = Custom.definition(tag)
                inherited = family and family.color
                break
            end
        end
    end
    if not definition and not inherited then return base end
    definition = definition or {}
    local key = tostring(id) .. "|" .. tostring(base) .. "|" .. tostring(familyId)
    if not customStyles[key] then
        local color, icon = definition.color or inherited or base, definition.icon or base.icon
        if icon and textures[icon] == nil then textures[icon] = (getTexture and getTexture(icon)) or false end
        customStyles[key] = {r=color.r, g=color.g, b=color.b, icon=icon, texture=icon and textures[icon] or nil}
    end
    return customStyles[key]
end

return Visuals
