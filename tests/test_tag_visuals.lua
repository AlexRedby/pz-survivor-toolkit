package.path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/?.lua;'..package.path
isClient=function()return false end
local world={}
ModData={getOrCreate=function()return world end}
local calls, textures = {}, {}
getTexture = function(name)
    assert(type(name) == 'string' and name ~= '', 'texture lookup needs a name')
    calls[name] = (calls[name] or 0) + 1
    if name == 'Item_GlassJar' then return nil end
    textures[name] = textures[name] or {name = name}
    return textures[name]
end
local Visuals = dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/TagVisuals.lua')
local schema = dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/ItemTagSchema.lua')
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
assert(Visuals.get('beverage', tags).texture == nil, 'missing texture must retain text/color fallback')
assert(Visuals.get('beverage', tags).texture == nil and calls.Item_GlassJar == 1, 'missing texture retried')
local unknown = Visuals.get('category:UnknownMod')
assert(unknown.texture == textures.Item_Clipboard and Visuals.get(nil).texture == nil, 'category/overflow icon fallback changed')
assert(Visuals.get('category:UnknownMod', tags).g == food.g, 'unknown tag lost contextual color')
assert(Visuals.get('perishable').r == unknown.r, 'standalone qualifier must remain neutral')
assert(#tags == 3 and tags[1] == 'food', 'visual lookup mutated tags')

for tag, name in pairs({vegetable='Item_Carrots',liquid='Item_WaterBottle',fuel='Item_Petrol',fishing='Item_FishingRod'}) do
 assert(Visuals.get(tag).texture.name==name,'missing useful qualifier icon '..tag)
end

for id in pairs(schema.labels) do
    local style = Visuals.get(id)
    assert(style.texture or id == 'nonperishable' or id == 'preserved' or id == 'beverage', 'schema tag has no icon: '..id)
end
assert(Visuals.get('adhesive').texture == nil, 'non-schema adhesive mapping must not be added')
assert(Visuals.get('caliber:12ga').texture == textures.Item_ShotgunAmmo, 'shotgun caliber icon missing')
assert(Visuals.get('caliber:9x19mm').texture == textures.Item_PistolAmmo, 'pistol caliber icon missing')
assert(Visuals.get('caliber:.22').texture == textures.Item_PistolAmmo and Visuals.get('caliber:.45').texture == textures.Item_PistolAmmo,
    'common pistol calibers must share the pistol ammo icon')
assert(Visuals.get('caliber:7.62x39mm').texture == textures.Item_RifleAmmo223
    and Visuals.get('caliber:.50magnum').texture == textures.Item_RifleAmmo223, 'rifle caliber fallback changed')
for tag, icon in pairs({prepared='Item_GlassWine', equipment='Item_SheepShears', video='Item_Cassette3',
    vinyl='Item_Disc', tracking='Item_CompassDirectional', arms='Item_Chainmail_Sleeve'}) do
    assert(Visuals.get(tag).texture == textures[icon], 'wrong semantic icon for '..tag)
end
assert(Visuals.get('category:UnknownMod') == unknown and calls.Item_Clipboard == 1, 'category icon cache missed')

local Custom=require 'PZSurvivorToolkit/TagCustomization'
world.definitions.food={color={r=0.9,g=0.1,b=0.2},icon='Item_Wrench'};world.revision=1
local changed=Visuals.get('food')
assert(changed.r==0.9 and changed.texture==textures.Item_Wrench and changed.icon=='Item_Wrench')
assert(Visuals.get('perishable',{'food','perishable'}).r==0.9,'qualifier lost edited family color')
assert(Visuals.defaults('food').texture==food.texture,'default reset inherited customization')
world.definitions.food=nil;world.revision=2
assert(Visuals.get('food').r==food.r,'definition reset left stale appearance')

-- Equal server revisions across saves must not retain a prior world's style.
world.definitions.food={color={r=.6,g=.2,b=.1}};world.revision=3;Custom.changed({})
assert(Visuals.get('food').r==.6)
world={version=1,revision=3,nextId=1,definitions={food={color={r=.1,g=.6,b=.2}}},types={}}
Custom.resetReceived()
assert(Visuals.get('food').r==.1,'equal-revision world reset retained cached tag appearance')
