-- Source-pinned presentation wrapping must preserve owned-food contracts without admitting foreign hooks.
if not NativeActionRoot or not SaucedCartsSource then
    print('Food/cart actual-source checks skipped (pass native action and SaucedCarts shared source roots).'); return
end
local function read(path)
    if NativeReadText then return NativeReadText(path):gsub('\r', '') end
    local file = assert(io.open(path)); local source = file:read('*a'); file:close(); return source:gsub('\r', '')
end
local coreSource = read(SaucedCartsSource .. '/Core.lua')
local consumeSource = read(SaucedCartsSource .. '/../../client/SaucedCarts/ConsumeWithCart.lua')
local function setup(mode)
    local fixture = assert(loadfile(ProjectRoot .. '/tests/support/action_queue_native.lua'))()
    local callbacks = {}
    Events.OnGameStart.Add = function(callback) callbacks[#callbacks + 1] = callback end
    isClient, isServer, getDebug = function() return false end, function() return false end, function() return false end
    SandboxVars, CharacterActionAnims = {}, {Eat = 'Eat', Drink = 'Drink'}
    fixture.native('shared/TimedActions/ISEatFoodAction.lua')
    SaucedCarts = nil
    local loaded = {}
    require = function(name)
        if loaded[name] then return loaded[name] end
        if name == 'PZSurvivorToolkit/SourceProof' then
            return assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'))()
        end
        if name == 'SaucedCarts/Core' then loaded[name] = assert(loadstring(coreSource))()
        elseif name == 'SaucedCarts/ConsumeWithCart' then loaded[name] = assert(loadstring(consumeSource))()
        else return true end
        return loaded[name]
    end
    local owner = require('SaucedCarts/Core')
    getActivatedMods = function() return {contains = function(_, id) return id == 'SaucedCarts' end} end
    getModFileReader = function(id, path)
        assert(id == 'SaucedCarts')
        local source = path:find('ConsumeWithCart', 1, true) and consumeSource or coreSource
        if mode == 'changed-source' then source = source .. '\n-- changed\n' end
        local lines = {}; for line in source:gmatch('([^\n]*)\n') do lines[#lines + 1] = line end
        local index = 0
        return {readLine = function() index = index + 1; return lines[index] end, close = function() end}
    end
    fixture.project('ActionQueueOperations')
    fixture.project('ActionQueueDefinitions')
    local owned
    PZSurvivorToolkit.BulkFood = {isEat = function(action) return action == owned end, isCommand = function() return false end}
    local Policy = fixture.project('ActionQueuePolicy')
    local nativeStart = ISEatFoodAction.start
    if mode == 'foreign-predecessor' then ISEatFoodAction.start = function() end end
    if mode == 'prewrapped' then require('SaucedCarts/ConsumeWithCart').install() end
    ISDrinkFluidAction = {start = function() return 'fluid native' end}
    ISDrinkFromBottle = {start = function() return 'bottle native' end}
    local drinkStart = ISDrinkFluidAction.start
    local Compat = fixture.project('ActionQueueCompat')
    local meal = ISBaseTimedAction.new(ISEatFoodAction, fixture.player)
    meal.item = fixture.item('Base.Herb'); meal.percentage, meal.eatSound, meal.eatAudio = 1, '', 0
    meal.item.getRequireInHandOrInventory = function() end
    meal.item.getCustomMenuOption = function() end
    meal.item.getEatType = function() return 'EatSmall' end
    meal.item.setJobType, meal.item.setJobDelta = function() end, function() end
    fixture.player.getEmitter = function() return {} end
    fixture.player.reportEvent = function() end
    local held
    fixture.player.getPrimaryHandItem = function() return held end
    local overrides, nativeAnimations = {}, 0
    meal.action = {setAnimVariable = function() end, setActionAnim = function() nativeAnimations = nativeAnimations + 1 end,
        setOverrideHandModelsObject = function(_, primary, secondary) overrides[#overrides + 1] = {primary, secondary} end}
    owned = meal
    return {Policy = Policy, Compat = Compat, meal = meal, owner = owner, callbacks = callbacks,
        nativeStart = nativeStart, drinkStart = drinkStart, setHeld = function(value) held = value end,
        overrides = overrides, nativeAnimations = function() return nativeAnimations end}
end
local f = setup()
assert(f.Compat.isInstalled('SaucedCarts') and ISEatFoodAction.start ~= f.nativeStart,
    'verified cart presentation starts early and adopts only the observed native predecessor')
assert(not f.Compat.isInstalled('SaucedCartsTransfers'),
    'unverified transfer sources must remain separate from verified eating compatibility')
assert(f.Policy.inspect(f.meal).interrupt == 'finish-step')
f.meal:start()
assert(f.nativeAnimations() == 1 and #f.overrides == 1 and f.overrides[1][2] == f.meal.item,
    'actual upstream wrapper delegates native eating exactly once without a cart')
if newproxy then
    local cart = newproxy(true)
    getmetatable(cart).__index = {getFullType = function() return 'SaucedCarts.Cart' end}
    local nativeInstanceof = instanceof
    instanceof = function(value, kind) return value == cart and kind == 'InventoryItem' or nativeInstanceof(value, kind) end
    f.owner.CartTypes = {['SaucedCarts.Cart'] = {}}
    f.setHeld(cart); f.meal:start()
    assert(f.nativeAnimations() == 2 and #f.overrides == 3 and f.overrides[3][1] == cart
        and f.overrides[3][2] == f.meal.item, 'actual Core.safeIsCart and consume wrapper retain the cart and selected food models')
end
local wrapped = ISEatFoodAction.start
f.owner.ConsumeWithCart.install()
assert(ISEatFoodAction.start == wrapped and f.Policy.inspect(f.meal), 'later OnGameStart public install is idempotent')
assert(ISDrinkFluidAction.start ~= f.drinkStart and ISDrinkFluidAction.start({character = {}}) == 'fluid native',
    'upstream drink wrapper keeps its native delegate without granting a food contract')
for _, field in ipairs({'safeIsCart', 'isCart', 'debug'}) do
    local original = f.owner[field]; f.owner[field] = function() end
    assert(not f.Policy.inspect(f.meal), 'replaced cart helper revokes owned-food permissions: ' .. field)
    f.owner[field] = original
end
for _, field in ipairs({'install', '_wrapStart'}) do
    local original = f.owner.ConsumeWithCart[field]; f.owner.ConsumeWithCart[field] = function() end
    assert(not f.Policy.inspect(f.meal), 'replaced consume producer cannot retain its source-pinned contract')
    f.owner.ConsumeWithCart[field] = original
end
local handModels = f.meal.setOverrideHandModels; f.meal.setOverrideHandModels = function() end
assert(not f.Policy.inspect(f.meal), 'unknown per-action hand-model helpers cannot inherit the cart permission')
f.meal.setOverrideHandModels = handModels
ISEatFoodAction.start = function() end
assert(not f.Policy.inspect(f.meal), 'later foreign food start remains opaque')
assert(not f.Policy.adoptEatStart(f.nativeStart, ISEatFoodAction.start, function() return true end),
    'a stale previous-start claim cannot authorize a subsequent foreign wrapper')
for _, mode in ipairs({'changed-source', 'foreign-predecessor', 'prewrapped'}) do
    f = setup(mode)
    assert(not f.Compat.isInstalled('SaucedCarts'), mode .. ' cannot claim a known private native delegate')
    if mode == 'changed-source' then require('SaucedCarts/ConsumeWithCart').install() end
    assert(not f.Policy.inspect(f.meal), mode .. ' remains protected')
end
print('Food/cart compatibility: actual pinned Core/ConsumeWithCart, native delegate, idempotent install and unknown-hook rejection passed.')
