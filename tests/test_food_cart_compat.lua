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
    fixture.native('shared/TimedActions/ISDrinkFluidAction.lua')
    SaucedCarts = nil
    LootSorter = {} -- Unrelated owned transfer integration has no hooks in this presentation fixture.
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
    local nativeStart, drinkStart = ISEatFoodAction.start, ISDrinkFluidAction.start
    if mode == 'foreign-predecessor' then ISEatFoodAction.start = function() end end
    if mode == 'foreign-drink-predecessor' then ISDrinkFluidAction.start = function() end end
    if mode == 'prewrapped' then require('SaucedCarts/ConsumeWithCart').install() end
    ISDrinkFromBottle = {start = function() return 'bottle native' end}
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
    local bottle=fixture.item('Base.WaterBottle')
    local fluid={getFilledRatio=function()return 1 end,getProperties=function()return {getHungerChange=function()return 0 end}end,
        getCustomDrinkSound=function()return ''end}
    bottle.getFluidContainer=function()return fluid end
    for _,method in ipairs({'getCustomMenuOption','getEatType','setJobType','setJobDelta'})do bottle[method]=meal.item[method]end
    local drink=ISDrinkFluidAction:new(fixture.player,bottle,.5)
    drink.toolkitQueueOperation={};drink.action=meal.action
    owned = meal
    return {Policy = Policy, Compat = Compat, meal = meal, drink = drink, fixture = fixture, owner = owner, callbacks = callbacks,
        nativeStart = nativeStart, drinkStart = drinkStart, setHeld = function(value) held = value end,
        overrides = overrides, nativeAnimations = function() return nativeAnimations end}
end
local f = setup()
assert(f.Compat.isInstalled('SaucedCarts') and ISEatFoodAction.start ~= f.nativeStart,
    'verified cart presentation starts early and adopts only the observed native predecessor')
assert(not f.Compat.isInstalled('SaucedCartsTransfers'),
    'unverified transfer sources must remain separate from verified eating compatibility')
assert(f.Policy.inspect(f.meal).interrupt == 'finish-step')
assert(f.Policy.inspect(f.drink).interrupt == 'finish-step' and not f.Policy.stoppable(f.drink),
    'verified native fluid wrapper retains waiting-only drink controls')
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
f.setHeld(nil)
local animations,overrides=f.nativeAnimations(),#f.overrides
f.drink:start()
assert(f.nativeAnimations()==animations+1 and #f.overrides==overrides+1 and f.overrides[#f.overrides][2]==f.drink.item,
    'actual upstream fluid wrapper delegates native drinking exactly once')
local wrapped,drinkWrapped = ISEatFoodAction.start,ISDrinkFluidAction.start
f.owner.ConsumeWithCart.install()
assert(ISEatFoodAction.start == wrapped and ISDrinkFluidAction.start == drinkWrapped
    and f.Policy.inspect(f.meal) and f.Policy.inspect(f.drink), 'later OnGameStart public install is idempotent for both contracts')
for _, field in ipairs({'safeIsCart', 'isCart', 'debug'}) do
    local original = f.owner[field]; f.owner[field] = function() end
    assert(not f.Policy.inspect(f.meal) and not f.Policy.inspect(f.drink), 'replaced cart helper revokes both consume permissions: ' .. field)
    f.owner[field] = original
end
for _, field in ipairs({'install', '_wrapStart'}) do
    local original = f.owner.ConsumeWithCart[field]; f.owner.ConsumeWithCart[field] = function() end
    assert(not f.Policy.inspect(f.meal) and not f.Policy.inspect(f.drink), 'replaced consume producer cannot retain either source-pinned contract')
    f.owner.ConsumeWithCart[field] = original
end
local handModels = f.meal.setOverrideHandModels; f.meal.setOverrideHandModels = function() end
assert(not f.Policy.inspect(f.meal), 'unknown per-action hand-model helpers cannot inherit the cart permission')
f.meal.setOverrideHandModels = handModels
local drinkModels=f.drink.setOverrideHandModels;f.drink.setOverrideHandModels=function()end
assert(not f.Policy.inspect(f.drink),'unknown per-drink hand-model helper cannot inherit the cart permission')
f.drink.setOverrideHandModels=drinkModels
local fluid=f.drink.fluidContainer;f.drink.fluidContainer={}
assert(not f.Policy.inspect(f.drink),'verified cart wrapper must retain exact bottle-fluid binding')
f.drink.fluidContainer=fluid
f.drink.action.finished=function()return false end
f.drink.action.isForceComplete=function()return false end
local queue=f.fixture.queue(f.drink)
assert(f.Policy.cancelOperationReason(queue,f.drink)=='operation_active','cart presentation must not authorize stopping partial fluid effects')
ISEatFoodAction.start = function() end
assert(not f.Policy.inspect(f.meal), 'later foreign food start remains opaque')
assert(not f.Policy.adoptConsumeStarts({[ISEatFoodAction]=f.nativeStart,[ISDrinkFluidAction]=f.drinkStart}, function() return true end),
    'a stale previous-start claim cannot authorize a subsequent foreign wrapper')
ISDrinkFluidAction.start = function() end
assert(not f.Policy.inspect(f.drink), 'later foreign fluid start remains opaque')
for _, mode in ipairs({'changed-source', 'foreign-predecessor', 'foreign-drink-predecessor', 'prewrapped'}) do
    f = setup(mode)
    assert(not f.Compat.isInstalled('SaucedCarts'), mode .. ' cannot claim a known private native delegate')
    if mode == 'changed-source' then require('SaucedCarts/ConsumeWithCart').install() end
    assert(not f.Policy.inspect(f.meal) and not f.Policy.inspect(f.drink), mode .. ' protects both consume contracts atomically')
end
print('Food/cart compatibility: actual pinned Core/ConsumeWithCart, native food/fluid delegates, atomic adoption, idempotent install and unknown-hook rejection passed.')
