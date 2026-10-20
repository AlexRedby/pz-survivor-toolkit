-- The selected EatSmartInt release only installs timed-action debug wrappers
-- when its private, source-level logging switch is enabled. Exercise the real
-- public menu producer and callback before granting any wrapper adoption.
if not NativeActionRoot or not (EatSmartSource or NativeWishlistWorkshopRoot) then
    print('Food/EatSmart actual-source checks skipped (pass native and EatSmartInt source roots).'); return
end
local function read(path)
    if NativeReadText then return NativeReadText(path):gsub('\r', '') end
    local file = assert(io.open(path)); local source = file:read('*a'); file:close(); return source:gsub('\r', '')
end
local sourcePath = EatSmartSource or NativeWishlistWorkshopRoot
    .. '/3456212729/mods/EatSmartInt/42/media/lua/client/ISUI/ES_subMenuEat.lua'
local source = read(sourcePath)
local Proof = assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'))()
local lines, position = {}, 0
for line in (source:gsub('\n$', '') .. '\n'):gmatch('([^\n]*)\n') do lines[#lines + 1] = line end
assert(Proof.checksum({readLine = function() position = position + 1; return lines[position] end}, true) == 2834352006,
    'EatSmartInt source changed; review the private debug installer and menu callback before updating this pin')

local f = assert(loadfile(ProjectRoot .. '/tests/support/action_queue_native.lua'))()
f.native('shared/TimedActions/ISEatFoodAction.lua')
local nativeComplete, nativeServerStop = ISEatFoodAction.complete, ISEatFoodAction.serverStop
local calls, queued = {}, {}
local playerCalories = 0
local nutrition = {getCalories = function() return playerCalories end, getProteins = function() return 0 end,
    getWeight = function() return 80 end}
f.player.getStats = function() return {getHunger = function() return .1 end} end
f.player.getNutrition = function() return nutrition end
f.player.Eat = function(_, item, percentage, utensil)
    calls[#calls + 1] = {item = item, percentage = percentage, utensil = utensil}
end
f.player.inventory.contains = function(_, item) return item == queued[1].item end
local food = f.item('Base.Herb')
food.getBaseHunger = function() return -.4 end
food.getHungChange = function() return -.3 end
food.getHungerChange = food.getHungChange
food.getCalories = function() return 1000 end
food.getProteins = function() return 0 end
food.getActualWeight = function() return .3 end
food.getType = function() return 'Herb' end
food.getFullType = function() return 'Base.Herb' end
food.setBaseHunger = function() error('ordinary partially eaten food must not need repair') end
local rows = {food}
ISInventoryPane.getActualItems = function(value) return value end
ISInventoryPaneContextMenu.onEatItems = function(items, percentage, player, openingRecipe, eatPercentage)
    queued[#queued + 1] = {item = items[1], percentage = percentage, player = player,
        openingRecipe = openingRecipe, eatPercentage = eatPercentage}
end
ISInventoryPaneContextMenu.addToolTip = function() return {} end
local options = {['1'] = true, ['6'] = true, ['7'] = 500}
PZAPI = {ModOptions = {getOptions = function(_, id)
    assert(id == 'EatSmart')
    return {getOption = function(_, key) return {getValue = function() return options[key] or false end} end}
end}}
SandboxVars, Excrementum = {}, nil
-- Public debug state does not enable the private source-level logging switch.
EatSmart_Debug = {pendingById = {}, enabled = true, logging = true, debug = true}
require = function() end
assert(loadstring(source, '@' .. sourcePath))()
assert(ISEatFoodAction.complete == nativeComplete and ISEatFoodAction.serverStop == nativeServerStop,
    'loading the selected source must preserve native effects')
local menu = {options = {}, addOption = function(self, name, target, callback, ...)
    local option = {name = name, target = target, callback = callback, args = {n = select('#', ...), ...}}
    self.options[#self.options + 1] = option
    return option
end}
ES_subMenuEat(menu, rows, rows, 0, f.player)
assert(#menu.options == 2 and menu.options[1].ES_EatSmart and menu.options[2].ES_EatSmart,
    'actual menu must expose the enabled hunger and calories targets')
local function choose(option) option.callback(option.target, unpack(option.args, 1, option.args.n)) end
choose(menu.options[1])
assert(#queued == 1 and queued[1].item == food and math.abs(queued[1].percentage - .25) < .000001,
    'hunger target delegates the original-food fraction and exact item')
assert(queued[1].player == 0 and queued[1].openingRecipe == nil and queued[1].eatPercentage == 25,
    'native context callback arguments remain unchanged')
playerCalories = 250
choose(menu.options[2])
assert(#queued == 2 and queued[2].item == food and math.abs(queued[2].percentage - .1875) < .000001,
    'nutrition target re-reads nutrition at click time and converts remaining fraction to native original fraction')
assert(not EatSmart_Debug.hookedEatAction and next(EatSmart_Debug.pendingById) == nil
    and ISEatFoodAction.complete == nativeComplete and ISEatFoodAction.serverStop == nativeServerStop,
    'ordinary selected-pack callbacks must never install the private debug action wrappers')
local action = {item = food, character = f.player, percentage = .25, useUtensil = false,
    getJobDelta = function() return .5 end, eat = ISEatFoodAction.eat}
assert(ISEatFoodAction.complete(action) == true and #calls == 1
    and calls[1].item == food and calls[1].percentage == .25 and calls[1].utensil == false,
    'native completion delegates exactly one requested portion')
ISEatFoodAction.serverStop(action)
assert(#calls == 2 and calls[2].item == food and calls[2].percentage == .125,
    'native active interruption retains its progress-scaled portion')
print('Food/EatSmart compatibility: pinned actual menu callbacks, original partial fractions, click-time nutrition and unchanged native complete/serverStop passed.')
