local calls, textures = {}, {}
getTexture = function(name)
    calls[name] = (calls[name] or 0) + 1
    if name == 'Item_GlassJar' then return nil end
    textures[name] = textures[name] or {name = name}
    return textures[name]
end
local Visuals = dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/TagVisuals.lua')
local food, electrical = Visuals.get('food'), Visuals.get('electrical')
local tool, medical, material = Visuals.get('tool'), Visuals.get('medical'), Visuals.get('material')
assert(food.g > food.r and food.g > food.b, 'food must stay green')
assert(food.texture == textures.Item_Plate, 'food must use a plate, distinct from fruit')
assert(electrical.texture == textures['media/ui/Entity/Energy/icon_energy_electric.png'], 'electrical lost lightning symbol')
assert(medical.texture == textures['media/ui/LootableMaps/map_medcross.png'], 'medical lost cross symbol')
assert(electrical.r > electrical.b and electrical.g > electrical.b, 'electrical must stay yellow')
assert(tool.b > tool.r and tool.b > tool.g, 'tool must stay blue')
assert(medical.r > medical.g and medical.r > medical.b, 'medical must stay red')
assert(material.r > material.g and material.g > material.b, 'material must stay brown')
local tags = {'food', 'perishable', 'fruit'}
local perishable, fruit = Visuals.get('perishable', tags), Visuals.get('fruit', tags)
assert(perishable.r == food.r and perishable.g == food.g, 'qualifier lost contextual color')
assert(perishable.texture == textures.Item_AlarmClock and fruit.texture == textures.Item_Apple)
assert(Visuals.get('food', {'electrical'}) == food, 'context replaced an explicit family')
assert(Visuals.get('perishable', {'medical'}).r == medical.r, 'context polluted cached qualifier')
assert(Visuals.get('perishable', tags) == perishable and calls.Item_AlarmClock == 1, 'texture/style cache missed')
assert(Visuals.get('fruit', tags).texture ~= food.texture and calls.Item_Apple == 1, 'fruit lost its distinct icon/cache')
assert(Visuals.get('electronic').texture == Visuals.get('power').texture and calls.Item_Battery == 1, 'shared icon loaded twice')
assert(Visuals.get('preserved', tags).texture == nil, 'missing texture must retain text/color fallback')
assert(Visuals.get('nonperishable', tags).texture == nil and calls.Item_GlassJar == 1, 'missing texture retried')
local unknown = Visuals.get('category:UnknownMod')
assert(unknown.texture == nil and Visuals.get(nil).texture == nil, 'unknown/overflow got an unrelated icon')
assert(Visuals.get('category:UnknownMod', tags).g == food.g, 'unknown tag lost contextual color')
assert(Visuals.get('perishable').r == unknown.r, 'standalone qualifier must remain neutral')
assert(#tags == 3 and tags[1] == 'food', 'visual lookup mutated tags')
