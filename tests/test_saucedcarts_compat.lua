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
assert(w.damaged == 1 and w.spilled == 1 and w.ended == 1 and w.dropped == 1, "broken cart reached ordinary drop")
character.item = cart
assert(force(character) == "forced" and character.item == nil and w.dropped == 1 and cart.persistent,
    "already-ground cart was duplicated")
character.item = {cart = false}
assert(force(character) == "forced" and w.dropped == 2, "non-cart forced drop changed")
assert(unequip({item = {cart = false}, character = character}) == "unequip", "ordinary unequip changed")
cart.getWorldItem = function() return nil end
character.item = cart
unequip({item = cart, character = character})
assert(w.damaged == 2 and w.spilled == 2 and w.ended == 2 and character.item == nil and w.dropped == 2,
    "broken-cart unequip bypassed the server spill hook")
require = nativeRequire
print("PASS actual upstream server hooks initialize once, spill broken carts, prevent stale-hand duplication and preserve ordinary drops")
