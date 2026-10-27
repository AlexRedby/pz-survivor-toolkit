local nativeRequire = require
require = function() end
local boot
Events = {OnGameBoot = {Add = function(fn) boot = fn end}}
ResourceType = {Item = 1}
toolkitRecipeHasItemTest = function(recipe) return recipe.itemTest end
local scans = 0
local function list(values)
    return {size = function() return #values end, get = function(_, i) scans = scans + 1; return values[i + 1] end}
end
local function script(name, tags)
    return {getFullName = function() return name end, tags = tags or {}}
end
local function perk(id) return {getId = function() return id end} end
local function input(items, keep, options)
    local value = options or {}
    value.getResourceType = function() return ResourceType.Item end
    value.isKeep = function() return keep == true end
    value.getIntAmount = function() return value.amount or 1 end
    value.getPossibleInputItems = function() return list(items) end
    value.isUsesPartialItem = function() return value.partial == true end
    for _, method in ipairs({'hasConsumeFromItem', 'hasCreateToItem', 'isApplyOnTick', 'isReplace'}) do
        value[method] = function() return false end
    end
    value.doesItemPassRoutineStatusTests = function(_, item, ...)
        assert(select('#', ...) == 1 and ... == nil, 'routine native predicate needs one nullable character argument')
        return (not item.broken or value.destroyed == true) and not item.favorite and not item.sealed
    end
    value.doesItemPassClothingTypeStatusTests = function(_, item, ...)
        assert(select('#', ...) == 0, 'clothing native predicate accepts only an item')
        return not value.notWorn or not item.worn
    end
    for _, method in ipairs({'doesItemPassSharpnessStatusTests', 'doesItemPassDamageStatusTests',
        'doesItemPassIsOrNotEmptyAndFullTests', 'doesItemPassFoodAndCookingTests'}) do
        value[method] = function(_, item, ...)
            assert(item and select('#', ...) == 0, 'native predicate accepts only an item: ' .. method)
            return true
        end
    end
    return value
end
local function recipe(name, inputs, xp, tested)
    local value = {itemTest = tested or false}
    value.getName = function() return name end
    value.getInputs = function() return list(inputs) end
    value.getXPAwardCount = function() return xp and 1 or 0 end
    value.getXPAward = function() return {getPerk = function() return perk(xp) end, getAmount = function() return 2 end} end
    return value
end
local cd, radio, tv = script('Base.CDplayer'), script('Base.RadioRed'), script('Base.TvAntique')
local watch, screwdriver = script('Base.WristWatch_Left_DigitalBlack'), script('Base.Screwdriver')
local lighter, blade, wire = script('Base.Lighter_Battery'), script('Base.HuntingKnife'), script('Base.ElectricWire')
local unopened = script('Base.CannedFoodBox')
local pliers, smallSaw = script('Base.Pliers'), script('Base.SmallSaw')
local modJewelry = script('Test.GoldPendant', {['base:tinygoldscrap'] = true})
local recipes = list({
    recipe('DismantleMiscElectronics', {input({screwdriver}, true), input({cd}, false)}, 'Electricity'),
    recipe('DismantleElectronicsDevice', {input({radio, tv}, false), input({screwdriver}, true)}, 'Electricity'),
    recipe('DismantleElectronics', {input({screwdriver}, true), input({watch}, false, {notWorn = true})}, 'Electricity'),
    recipe('DismantleImprovisedLighter', {input({lighter}, false)}),
    recipe('DismantleBlade', {input({blade}, false)}),
    recipe('CraftMakeshiftRadio', {input({wire}, false), input({screwdriver}, true)}, 'Electricity'),
    recipe('OpenFoodBox', {input({unopened}, false)}),
    recipe('Scrap_Gold_Jewellery', {input({modJewelry}, false, {destroyed = true}), input({pliers, smallSaw}, true)}),
})
local legacy = list({})
local manager = {getAllCraftRecipes = function() return recipes end, getAllRecipes = function() return legacy end}
getScriptManager = function() return manager end
local definitions = {
    isScrapDefinitionValid = function(material) return material == 'Wood' or material == 'Electric' end,
    getScrapDefinition = function(material) return {perk = perk(material == 'Wood' and 'Woodwork' or 'Electricity')} end,
}
ISMoveableDefinitions = {getInstance = function() return definitions end}
local spriteDefinitions = {}
getSprite = function(name) return spriteDefinitions[name] end
local function sprite(material, canScrap)
    return {getProperties = function()
        return {has = function(_, key) return key == 'Material' or key == 'CanScrap' and canScrap end,
            get = function(_, key) if key == 'Material' then return material end end}
    end}
end
local disassembly = dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/ItemDisassemblyTags.lua')
local function expect(definition, item, supported, skill)
    local actual, skills = disassembly.read(definition, item)
    assert(actual == supported, definition:getFullName() .. ' dismantle capability differs')
    assert(table.concat(skills, ',') == (skill or ''), definition:getFullName() .. ' awarded skill tags differ')
end
for _, definition in ipairs({cd, radio, tv, watch}) do expect(definition, nil, true, 'electrical') end
expect(lighter, nil, true)
expect(blade, nil, true)
for _, definition in ipairs({screwdriver, wire, unopened}) do expect(definition, nil, false) end
-- Recipe-resolved subjects include mod items; kept jewelry tools are not subjects.
expect(modJewelry, nil, true)
for _, definition in ipairs({pliers, smallSaw}) do expect(definition, nil, false) end
local jewelryItem = {broken = true}
expect(modJewelry, jewelryItem, true)
jewelryItem.favorite = true
expect(modJewelry, jewelryItem, false)
jewelryItem.favorite = false
expect(modJewelry, jewelryItem, true)
expect(watch, {worn = true}, false)
expect(watch, {worn = false}, true, 'electrical')
expect(cd, {broken = true}, false)
expect(cd, {sealed = true}, false)
local before = scans
for i = 1, 100 do expect(cd, nil, true, 'electrical') end
assert(scans == before, 'repeated item classification rescanned the recipe catalog')

-- A name/animation/required skill never substitutes for a consumed subject.
recipes = list({recipe('DismantleElectronics', {input({screwdriver}, true)}, 'Electricity'),
    recipe('DismantleMiscElectronics', {input({cd}, false), input({wire}, false)}, 'Electricity'),
    recipe('DismantleElectronicsDevice', {input({radio}, false, {amount = 2})}, 'Electricity'),
    recipe('DismantleBlade', {input({blade}, false, {partial = true})})})
for _, definition in ipairs({screwdriver, cd, radio, blade}) do expect(definition, nil, false) end
recipes = list({recipe('DismantleMiscElectronics', {input({cd}, false)}, 'Electricity', true)})
expect(cd, nil, false)
recipes = list({recipe('DismantleMiscElectronics', {input({cd}, false)}, 'Electricity')})
local bridge = toolkitRecipeHasItemTest
toolkitRecipeHasItemTest = nil
expect(cd, nil, false)
toolkitRecipeHasItemTest = function() return nil end
expect(cd, nil, false)
toolkitRecipeHasItemTest = bridge
expect(cd, nil, true, 'electrical')

-- Native generated MovableRecipe exposes its XP perk; generic old Recipe does
-- not expose callback predicates and must stay conservative.
local legacyTarget, legacyOther = script('Test.LegacyMovable'), script('Test.LegacyUnknown')
local function oldSource(name, keep)
    return {isKeep = function() return keep end, getCount = function() return 1 end,
        getUse = function() return 0 end, getItems = function() return list({name}) end}
end
local old = {getOriginalname = function() return 'Dismantle Test Movable' end,
    getSource = function() return list({oldSource('Base.Screwdriver', true), oldSource('Test.LegacyMovable', false)}) end,
    hasXpPerk = function() return true end, getXpPerk = function() return perk('Woodwork') end,
    isValid = function() return true end}
legacy = list({old, {getOriginalname = function() return 'Dismantle Other' end,
    getSource = function() return list({oldSource('Test.LegacyUnknown', false)}) end}})
expect(legacyTarget, nil, true, 'carpentry')
expect(screwdriver, nil, false)
expect(legacyOther, nil, false)
expect(legacyTarget, {isBroken = function() return true end}, false)
legacy = list({})

-- Carried furniture uses its native scrap definition, not its display category.
local furniture = script('Base.Mov_TestChair')
furniture.getWorldObjectSprite = function() return 'chair' end
spriteDefinitions.chair = sprite('Wood', true)
expect(furniture, nil, true, 'carpentry')
spriteDefinitions.chair = sprite('Wood', false)
expect(furniture, nil, false)
spriteDefinitions.chair = sprite('UnknownMaterial', true)
expect(furniture, nil, false)
spriteDefinitions.chair = sprite('Electric', true)
expect(furniture, nil, true, 'electrical')
spriteDefinitions.chair = sprite('Wood', true)
expect(furniture, {getWorldSprite = function() return 'missing' end}, false)
local nativeDefinitions = ISMoveableDefinitions
ISMoveableDefinitions = nil
spriteDefinitions.chair = sprite('Wood', false)
require = function() error('ordinary storage-only sprites must not require moveables') end
expect(furniture, nil, false)
local required = 0
require = function(name)
    assert(name == 'Moveables/ISMoveableDefinitions')
    required = required + 1
    ISMoveableDefinitions = nativeDefinitions
end
spriteDefinitions.chair = sprite('Wood', true)
expect(furniture, nil, true, 'carpentry')
assert(required == 1, 'actual scrap furniture must resolve the native shared definitions')
assert(type(boot) == 'function')
boot()

-- Exercise the real installed B42.21 recipe declarations through the same index
-- fixture. No recipe callbacks or inventory-item constructors are executed.
if NativeDisassemblyScriptsRoot then
    local jewelry = {}
    for _, name in ipairs({'Ring_Right_MiddleFinger_Gold', 'NecklaceLong_Gold',
        'Earring_LoopLrg_Silver', 'NoseStud_Silver', 'Necklace_Choker_Diamond', 'Earring_Stone_Ruby'}) do
        jewelry[#jewelry + 1] = script('Base.' .. name)
    end
    local pearl, signet = script('Base.Necklace_Pearl'), script('Base.Ring_Right_MiddleFinger_Signet')
    local scripts = {cd, radio, tv, watch, screwdriver, lighter, blade, wire, unopened,
        pliers, smallSaw, pearl, signet, modJewelry}
    for _, definition in ipairs(jewelry) do scripts[#scripts + 1] = definition end
    local declared = {}
    local itemRoot = NativeDisassemblyScriptsRoot .. '/../items/'
    for _, name in ipairs({'normal.txt', 'radio.txt', 'alarmclockclothing.txt', 'weapon.txt', 'clothing.txt'}) do
        local file = assert(io.open(itemRoot .. name));local text = file:read('*a');file:close()
        for nativeName, block in text:gmatch('item%s+([%w_]+)%s*(%b{})') do
            for _, definition in ipairs(scripts) do
                if definition:getFullName() == 'Base.' .. nativeName then
                    declared[definition] = true
                    for tag in (block:match('Tags%s*=%s*([^,]+)') or ''):gmatch('[%w_:]+') do definition.tags[tag] = true end
                end
            end
        end
    end
    for _, definition in ipairs({pliers, smallSaw, pearl, signet}) do
        assert(declared[definition], 'missing native declaration: ' .. definition:getFullName())
    end
    for _, definition in ipairs(jewelry) do
        assert(declared[definition], 'missing native declaration: ' .. definition:getFullName())
    end
    local native = {}
    local jewelryRecipes = {Scrap_Gold_Jewellery = false, Scrap_Silver_Jewellery = false, scrap_jewellery = false}
    for _, filename in ipairs({'recipes_electrical.txt', 'recipes_radio.txt', 'recipes_disassembly.txt',
        '../entities/blacksmith/craftRecipes/recipes_blacksmith_other_metals.txt'}) do
        local file = assert(io.open(NativeDisassemblyScriptsRoot .. '/' .. filename))
        local text = file:read('*a');file:close()
        for name, block in text:gmatch('craftRecipe%s+([%w_]+)%s*(%b{})') do
            local inputs = {}
            local body = block:match('inputs%s*(%b{})') or ''
            for line in body:gmatch('[^\r\n]+') do
                local amount, choices = line:match('item%s+(%d+)%s+(.-),')
                if amount then
                    local candidates = {}
                    local tags = choices:match('tags%[(.-)%]')
                    local types = choices:match('%[(.-)%]') or ''
                    for _, definition in ipairs(scripts) do
                        local matches = false
                        for id in types:gmatch('[^;]+') do
                            if tags and definition.tags[id] or not tags and definition:getFullName() == id then matches = true end
                        end
                        if matches then candidates[#candidates + 1] = definition end
                    end
                    inputs[#inputs + 1] = input(candidates, choices:find('mode:keep', 1, true) ~= nil,
                        {amount = tonumber(amount), notWorn = choices:find('IsNotWorn', 1, true) ~= nil,
                            destroyed = choices:find('AllowDestroyedItem', 1, true) ~= nil})
                end
            end
            local xp = block:match('xpAward%s*=%s*([%w_]+):')
            if jewelryRecipes[name] ~= nil then
                jewelryRecipes[name] = true
                assert(not xp, 'native jewelry scrapping must not fabricate a skill award')
            end
            native[#native + 1] = recipe(name, inputs, xp)
        end
    end
    for name, found in pairs(jewelryRecipes) do assert(found, 'missing native jewelry recipe: ' .. name) end
    recipes = list(native)
    for _, definition in ipairs({cd, radio, tv, watch}) do expect(definition, nil, true, 'electrical') end
    expect(watch, {worn = true}, false)
    expect(lighter, nil, true)
    expect(blade, nil, true)
    for _, definition in ipairs({screwdriver, wire, unopened}) do expect(definition, nil, false) end
    -- Gold/silver and gem-only items exercise all three recipes and several shapes.
    for _, definition in ipairs(jewelry) do
        expect(definition, nil, true)
        expect(definition, {broken = true}, true)
        expect(definition, {favorite = true}, false)
    end
    expect(modJewelry, nil, true)
    for _, definition in ipairs({pearl, signet, pliers, smallSaw}) do expect(definition, nil, false) end
    print('native B42.21 disassembly recipe declarations checked')
else
    print('SKIP native disassembly declaration check (NativeDisassemblyScriptsRoot not supplied)')
end
require = nativeRequire
print('item disassembly tags tests passed')
