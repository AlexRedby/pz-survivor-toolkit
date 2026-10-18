local gate = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/server/000ToolkitSaucedCartsCompatibility.lua"
local nativeRequire = require
local function setup(server, active)
    local w = {starts = {}, calls = {}, dropped = 0, damaged = 0, spilled = 0, ended = 0}
    isServer = function() return server end
    isClient = function() return false end
    getActivatedMods = function() return {contains = function(_, id) return active and id == "SaucedCarts" end} end
    Events = {OnGameStart = {Add = function() end}, OnServerStarted = {Add = function(fn) table.insert(w.starts, fn) end}}
    SaucedCarts = {debug = function() end, error = error,
        safeIsCart = function(item) return item.cart end, isCart = function(item) return item.cart end,
        markDropPersistent = function(item) item.persistent = true end,
        resolveCartDropSquare = function(square) return square end, updateCartVisual = function() end,
        Durability = {applyAccumulatedDamage = function(item) w.damaged = w.damaged + 1; return item.condition end,
            dropContentsAndDestroy = function() w.spilled = w.spilled + 1 end}}
    ISDropWorldItemAction = {complete = function() w.dropped = w.dropped + 1; return "native" end,
        isValid = function() return true end, new = function() end}
    ISUnequipAction = {complete = function() return "unequip" end, new = function() end}
    ISBaseTimedAction = {perform = function() w.ended = w.ended + 1 end}
    sendRemoveItemFromContainer = function() end
    forceDropHeavyItems = function(character)
        local item = character:getPrimaryHandItem()
        if item then w.dropped = w.dropped + 1; character:removeFromHands(item) end
        return "forced"
    end
    local loaded = {}
    require = function(name)
        w.calls[#w.calls + 1] = name
        if loaded[name] then return loaded[name] end
        if name == "SaucedCarts/ContainerRestrictions" or name == "SaucedCarts/ForceDropGuard" then
            local file = name:match("/([^/]+)$")
            loaded[name] = dofile(SaucedCartsSource .. "/" .. file .. ".lua")
            return loaded[name]
        end
        return true
    end
    return w
end
for _, mode in ipairs({{false, true}, {true, false}}) do
    local w = setup(mode[1], mode[2]); dofile(gate)
    assert(#w.starts == 0 and #w.calls == 0)
end
print("PASS cart compatibility inactive without SaucedCarts or outside server")
if not SaucedCartsSource then
    require = nativeRequire
    print("SKIP cart server behavior requires upstream SaucedCarts source")
    return
end
local w = setup(true, true)
local originalDrop, originalUnequip, originalForce = ISDropWorldItemAction.complete, ISUnequipAction.complete, forceDropHeavyItems
dofile(gate)
assert(#w.starts == 1 and #w.calls == 0 and forceDropHeavyItems == originalForce)
w.starts[1]()
assert(SaucedCarts._forceDropGuardInstalled and SaucedCarts.ContainerRestrictions.isUnequipHookInitialized())
assert(ISDropWorldItemAction.complete ~= originalDrop and ISUnequipAction.complete ~= originalUnequip)
local drop, unequip, force = ISDropWorldItemAction.complete, ISUnequipAction.complete, forceDropHeavyItems
w.starts[1]()
assert(drop == ISDropWorldItemAction.complete and unequip == ISUnequipAction.complete and force == forceDropHeavyItems)
local character = {item = nil, inventory = {contains = function() return true end, Remove = function() end}}
function character:getCurrentSquare() return {} end
function character:getPrimaryHandItem() return self.item end
function character:getSecondaryHandItem() return self.item end
function character:getInventory() return self.inventory end
function character:removeFromHands(item) if self.item == item then self.item = nil end end
function character:setSecondaryHandItem(item) self.item = item end
local cart = {cart = true, condition = 0, getWorldItem = function() return {} end}
assert(drop({item = {cart = false}, character = character}) == "native" and w.dropped == 1)
drop({item = cart, character = character})
assert(w.damaged == 1 and w.spilled == 1 and w.ended == 0 and w.dropped == 1, "broken cart reached ordinary drop")
character.item = cart
assert(force(character) == "forced" and character.item == nil and w.dropped == 1 and cart.persistent,
    "already-ground cart was duplicated")
character.item = {cart = false}
assert(force(character) == "forced" and w.dropped == 2, "non-cart forced drop changed")
assert(unequip({item = {cart = false}, character = character}) == "unequip", "ordinary unequip changed")
cart.getWorldItem = function() return nil end
character.item = cart
unequip({item = cart, character = character})
assert(w.damaged == 2 and w.spilled == 2 and w.ended == 0 and character.item == nil and w.dropped == 2,
    "broken-cart unequip bypassed the server spill hook")
require = nativeRequire
print("PASS actual upstream server hooks initialize once, spill broken carts, prevent stale-hand duplication and preserve ordinary drops")

local nativePerform
if NativeActionRoot then
    local file=assert(io.open(NativeActionRoot..'/shared/TimedActions/ISBaseTimedAction.lua','r'))
    local source=file:read('*a');file:close()
    local body=assert(source:match('function ISBaseTimedAction:perform%(%)(.-)\nend'),'Native base perform changed')
    nativePerform=assert(loadstring('return function(self)'..body..'\nend'))()
end
local function serverDrop(condition)
    local state=setup(true,true)
    local cart={cart=true,condition=condition or 100,children=1}
    function cart:getWorldItem() return self.world end
    function cart:getCondition() return self.condition end
    function cart:getConditionMax() return 100 end
    function cart:getInventory() return {getItems=function() return {isEmpty=function() return self.children==0 end} end} end
    local inventory={item=cart}
    function inventory:contains(item) return self.item==item end
    function inventory:Remove(item) assert(self.item==item);self.item=nil;state.removed=(state.removed or 0)+1 end
    local square={}
    function square:AddWorldInventoryItem(item,x,y,z,transmit)
        assert(item==cart and x==0 and y==0 and z==0 and transmit==true,'Changed upstream placement/transmission')
        state.placed=(state.placed or 0)+1
        local world={getItem=function() return item end,getSquare=function() return self end}
        item.world=world;return world
    end
    local player={primary=cart,secondary=cart,square=square}
    function player:getPrimaryHandItem() return self.primary end
    function player:getSecondaryHandItem() return self.secondary end
    function player:getCurrentSquare() return self.square end
    function player:getInventory() return inventory end
    function player:removeFromHands(item)
        if self.primary==item then self.primary=nil end
        if self.secondary==item then self.secondary=nil end
    end
    function player:setSecondaryHandItem(item) self.secondary=item end
    SaucedCarts.Durability.dropContentsAndDestroy=function(item)
        state.spilled=state.spilled+1;item.children=0
    end
    SaucedCarts.error=function() state.failures=(state.failures or 0)+1 end
    sendRemoveItemFromContainer=function(owner,item)
        assert(owner==inventory and item==cart);state.sent=(state.sent or 0)+1
    end
    ISTimedActionQueue=nil
    ISBaseTimedAction.perform=nativePerform or function(self)
        -- Same forbidden server queue access when the optional native source is unavailable.
        ISTimedActionQueue.getTimedActionQueue(self.character):onCompleted(self)
    end
    local perform=ISBaseTimedAction.perform
    dofile(gate);state.starts[1]()
    return state,cart,player,{item=cart,character=player},perform
end

for _,className in ipairs({'ISUnequipAction','ISDropWorldItemAction'}) do
    local state,cart,player,action,perform=serverDrop(0)
    assert(_G[className].complete(action)==true,'Broken cart completion must return native Boolean success: '..className)
    assert(state.spilled==1 and state.damaged==1 and state.removed==1 and state.sent==1 and not state.placed,
        'Broken cart effects changed: '..className)
    assert(not player.primary and not player.secondary and cart.children==0 and not cart.world,'Broken cart ownership/cargo changed')
    assert(ISBaseTimedAction.perform==perform,'Broken completion leaked perform guard')
end
local state,cart,player,action,perform=serverDrop()
assert(ISUnequipAction.complete(action)==true,'Successful server cart unequip returned no Boolean')
assert(state.damaged==1 and state.placed==1 and state.removed==1 and state.sent==1 and cart.children==1,
    'Normal server cart drop changed durability, cargo or transmission')
assert(not player.primary and not player.secondary and cart.world.persistent,'Normal server cart drop lost ownership/persistence')
assert(ISBaseTimedAction.perform==perform,'Successful cart completion leaked perform guard')
assert(ISUnequipAction.complete(action)==true and state.placed==1 and state.damaged==1,'Already dropped cart repeated native effects')

state,cart,player,action,perform=serverDrop()
player.square=nil
assert(ISUnequipAction.complete(action)==false,'Missing square falsely acknowledged server drop')
assert(player.primary==cart and player:getInventory():contains(cart) and state.damaged==0 and cart.children==1,
    'Failed drop changed ownership/cargo')
assert(ISBaseTimedAction.perform==perform,'Failed cart completion leaked perform guard')
state,cart,player,action,perform=serverDrop()
player.square.AddWorldInventoryItem=function() error('placement failed') end
assert(ISUnequipAction.complete(action)==false,'Failed world placement falsely acknowledged server drop')
assert(not cart.world and cart.children==1 and ISBaseTimedAction.perform==perform,'Failed placement lost cargo/leaked perform guard')

state,cart,player,action,perform=serverDrop()
player.square=nil
SaucedCarts.error=function() error('upstream failure') end
local ok,why=pcall(ISUnequipAction.complete,action)
assert(not ok and tostring(why):find('upstream failure',1,true),'Upstream error was swallowed')
assert(ISBaseTimedAction.perform==perform,'Throwing completion leaked perform guard')

state,cart,player,action,perform=serverDrop()
local foreign={character=player}
local delegated=0
ISBaseTimedAction.perform=function(target)
    assert(target==foreign,'Cart completion reached client queue')
    delegated=delegated+1
end
perform=ISBaseTimedAction.perform
SaucedCarts.updateCartVisual=function() ISBaseTimedAction.perform(foreign) end
assert(ISUnequipAction.complete(action)==true and delegated==1,'Exact-action guard swallowed unrelated base perform')
assert(ISBaseTimedAction.perform==perform,'Foreign perform delegation leaked guard')
assert(ISUnequipAction.complete({item={cart=false},character=player})=='unequip','Ordinary completion return changed')

state,cart,player,action,perform=serverDrop()
local ordinary=0
SaucedCarts.updateCartVisual=function()
    assert(ISUnequipAction.complete({item={cart=false},character=player})=='unequip')
    ordinary=ordinary+1
    -- Reentrant completion of the same authoritative drop must not place it twice.
    assert(ISUnequipAction.complete(action)==true)
end
assert(ISUnequipAction.complete(action)==true and state.placed==1 and state.damaged==1 and ordinary==1,
    'Reentrant completion duplicated effects or lost the original callback')
assert(ISBaseTimedAction.perform==perform,'Nested completion failed to restore the outer perform scope')
require=nativeRequire
print('PASS upstream server cart completions preserve authoritative drop/spill effects, Boolean outcomes and exact-action perform scope'..(nativePerform and ' with actual native base perform' or ' (native base source not provided)'))
