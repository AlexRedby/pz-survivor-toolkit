local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/'
package.path = root .. 'shared/?.lua;' .. root .. 'client/?.lua;' .. package.path
local boot = {}
Events = {OnGameBoot = {Add = function(fn) boot[#boot + 1] = fn end}}
local function reset() for _, fn in ipairs(boot) do fn() end end
local function list(values)
    return {size = function() return #values end, get = function(_, i) return values[i + 1] end}
end
local function scriptItem(fullType)
    return {getFullName = function() return fullType end}
end
local function recipe(inputs, outputs)
    local function items(types)
        local result = {}
        for _, fullType in ipairs(types) do result[#result + 1] = scriptItem(fullType) end
        return list(result)
    end
    return {
        getInputs = function() return list({{getPossibleInputItems = function() return items(inputs) end}}) end,
        getOutputs = function() return list({{getPossibleResultItems = function() return items(outputs) end}}) end,
    }
end
local packetRecipe = recipe({'Base.FullPacket'}, {'Base.TestSeed', 'Base.EmptyPacket'})
ScriptManager = {instance = {getCraftRecipe = function(_, name)
    assert(name == 'Base.OpenPacketOfSeeds'); return packetRecipe
end}}
local function item(fullType, learned, doubleClick)
    return {
        getFullType = function() return fullType end,
        getLearnedRecipes = function() return learned and list(learned) end,
        getScriptItem = function() return {getDoubleClickRecipe = function() return doubleClick end} end,
        getDisplayCategory = function() error('planting must not consult or mutate categories') end,
        setDisplayCategory = function() error('planting must not mutate categories') end,
    }
end
local month, seasons, speed, known = 4, true, 1, true
getGameTime = function() return {getMonth = function() return month - 1 end} end
getSandboxOptions = function() return {getOptionByName = function(_, name)
    if name == 'PlantGrowingSeasons' then return {getValue = function() return seasons end} end
    assert(name == 'FarmingSpeedNew'); return {getValue = function() return speed end}
end} end
calcNextTimeFactor = function() return 1 / speed end
local player = {isRecipeActuallyKnown = function(_, name) assert(name == 'base:test growing season'); return known end}
local Planting = require 'PZSurvivorToolkit/InventoryPlanting'
local seed = item('Base.TestSeed')
assert(Planting.resolve(seed) == nil, 'native definitions may load after this module')
farming_vegetableconf = {props = {}}
assert(Planting.resolve(seed) == nil)
local props = {
    seedName = 'Base.TestSeed', seasonRecipe = 'base:test growing season',
    sowMonth = {4, 5, 6}, bestMonth = {4}, riskMonth = {6}, badMonth = {12},
    waterLvl = 35, timeToGrow = 25, harvestLevel = 7, texture = 'native_crop_texture',
}
farming_vegetableconf.props.Test = props
assert(Planting.resolve(seed) == 'Test')
local crop, definition = Planting.resolve(seed)
assert(crop == 'Test' and definition == props)
local full = item('Base.FullPacket', {'base:test growing season'})
local empty = item('Base.EmptyPacket', {'base:test growing season'})
assert(Planting.resolve(full) == 'Test', 'recipe inputs identify full packets without relying on their spelling')
assert(Planting.resolve(empty) == nil, 'empty packets teach the same recipe but cannot be planted')
assert(Planting.resolve(item('Base.Magazine', {'base:test growing season'})) == nil)
assert(Planting.resolve(item('Base.OtherPacket', {'base:unknown growing season'}, 'OpenPacketOfSeeds')) == nil)
assert(Planting.resolve(item('Base.DynamicPacket', {'base:test growing season'}, 'Base.OpenPacketOfSeeds')) == 'Test')
local model = assert(Planting.describe(player, full))
assert(model.status == 'best' and model.currentMonth == 4 and model.crop == 'Test')
assert(model.growDays == 7 and model.waterLvl == 35 and model.texture == props.texture)
assert(model.sowMonth == props.sowMonth and model.badMonth == props.badMonth)
props.texture, props.icon = nil, 'native_crop_icon'
assert(Planting.describe(player, seed).texture == 'native_crop_icon')
props.texture = 'native_crop_texture'
month = 5; assert(Planting.describe(player, seed).status == 'inseason')
month = 6; assert(Planting.describe(player, seed).status == 'risk')
month = 12; assert(Planting.describe(player, seed).status == 'outofseason')
known = false; assert(Planting.describe(player, seed) == nil)
known = true; month = 4; assert(Planting.describe(player, seed).status == 'best')
seasons = false; assert(Planting.describe(player, seed) == nil)
seasons = true; speed = 2; assert(Planting.describe(player, seed).growDays == 3)
speed = 1
assert(Planting.describe(nil, seed) == nil and Planting.describe(player, empty) == nil)
props.bestMonth = nil
month = 5; assert(Planting.describe(player, seed, true).status == 'best')
assert(Planting.describe(player, seed, false).status == 'inseason')
month = 6; assert(Planting.describe(player, seed, true).status == 'risk', 'risk wins over optional best fallback')
month = 12; assert(Planting.describe(player, seed, true).status == 'outofseason')
props.bestMonth = {}; month = 5
assert(Planting.describe(player, seed, true).status == 'inseason', 'an explicitly empty best-month list is not absent')
-- Native seedTypes replaces seedName: edible planting inputs are intentionally included.
farming_vegetableconf = {props = {Corn = {seedName = 'Base.Ignored', seedTypes = {'Base.CornSeed', 'Base.Corn'}}}}
assert(Planting.resolve(item('Base.Corn')) == 'Corn')
assert(Planting.resolve(item('Base.Ignored')) == nil)
reset()
assert(Planting.resolve(item('Base.CornSeed')) == 'Corn')
assert(props.seedName == 'Base.TestSeed' and props.waterLvl == 35 and props.sowMonth[1] == 4)
print('Inventory planting model: identity, seasons, knowledge, live month and sandbox checks passed.')

if not NativePlantingLuaRoot then return end
-- Load game-owned data directly; no native tables or third-party mod sources are bundled here.
dofile(NativePlantingLuaRoot .. '/server/Farming/farming_vegetableconf.lua')
package.loaded['Farming/farming_vegetableconf'] = true
dofile(NativePlantingLuaRoot .. '/server/Farming/farming_vegetableconf_vegetables.lua')
dofile(NativePlantingLuaRoot .. '/server/Farming/farming_vegetableconf_herbs.lua')
reset()
player.isRecipeActuallyKnown = function(_, name) return known and name == 'base:carrot growing season' end
local carrot = item('Base.CarrotSeed')
month = 4; known = true
model = assert(Planting.describe(player, carrot))
assert(model.crop == 'Carrots' and model.props == farming_vegetableconf.props.Carrots)
assert(model.growDays == math.floor(model.props.timeToGrow * model.props.harvestLevel / 24))
speed = 3
assert(Planting.describe(player, carrot).growDays == math.floor(model.props.timeToGrow * model.props.harvestLevel / 72))
speed = 1
local file = assert(io.open(NativePlantingLuaRoot .. '/../scripts/generated/items/literature.txt'))
local source = file:read('*a'); file:close()
local count, fullCount = 0, 0
for name, body in source:gmatch('item%s+([%w_]+)%s*(%b{})') do
    local learnedRecipe = body:match('LearnedRecipes%s*=%s*([^,\r\n]+)')
    if learnedRecipe and learnedRecipe:find('growing season', 1, true) then
        local doubleClick = body:match('DoubleClickRecipe%s*=%s*([^,\r\n]+)')
        local candidate = item('Base.' .. name, {learnedRecipe}, doubleClick)
        if doubleClick == 'OpenPacketOfSeeds' then
            assert(Planting.resolve(candidate), 'unresolved native full packet: ' .. name)
            fullCount = fullCount + 1
        else
            assert(Planting.resolve(candidate) == nil, 'non-input literature resolved: ' .. name)
        end
        count = count + 1
    end
end
assert(fullCount >= 50 and count > fullCount, 'native packet coverage unexpectedly small')
local cropCount = 0
for name, cropProps in pairs(farming_vegetableconf.props) do
    for _, fullType in ipairs(cropProps.seedTypes or {cropProps.seedName}) do
        assert(Planting.resolve(item(fullType)) == name, 'unresolved native seed: ' .. tostring(fullType))
    end
    cropCount = cropCount + 1
end
assert(cropCount >= 50)
known = false; assert(Planting.describe(player, carrot) == nil)
print('Inventory planting native data: ' .. cropCount .. ' crops and ' .. count .. ' packet/literature definitions passed.')
