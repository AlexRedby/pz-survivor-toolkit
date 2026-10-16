local Visuals = {}
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
    medical = {red, "media/ui/LootableMaps/map_medcross.png"}, drug = {red, "Item_SutureNeedle"},
    material = {brown, "Item_Plank"}, construction = {brown, "Item_Hammer"},
    crafting = {brown, "Item_Hammer"}, furniture = {brown, "Item_Plank"},
    clothing = {purple, "Item_ShirtGeneric"}, character = {purple, "Item_Toothbrush"},
    collectable = {purple, "Item_PlushSpiffo"}, entertainment = {purple, "Item_Baseball"},
    literature = {blue, "Item_Book"}, container = {blue, "Item_Backpack_Blue"},
    weapon = {red, "Item_HandGun3"}, ammunition = {red, "Item_PistolAmmo"},
    security = {yellow, "Item_Key1"}, placeable = {neutral, "Item_Plank"},
    junk = {neutral, "Item_Money"},
}
local icons = {
    perishable = "Item_AlarmClock", nonperishable = "Item_GlassJar", preserved = "Item_GlassJar",
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
    fishing = "Item_FishingRod", adhesive = "Item_DuctTape",
}
local textures, styles = {}, {}

function Visuals.get(id, contextTags)
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
        if icon and textures[icon] == nil then
            textures[icon] = (getTexture and getTexture(icon)) or false
        end
        styles[color][key] = {r = color.r, g = color.g, b = color.b,
            texture = icon and textures[icon] or nil}
    end
    return styles[color][key]
end

return Visuals
