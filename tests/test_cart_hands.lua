local source = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/000ToolkitCartHandsCompatibility.lua"
local nativeRequire = require
local handler, required, equipped, models
local client = true
local now=0
getTimestampMs=function() return now end
local function setup(server, carts, tidy)
    handler, required, equipped, models = nil, 0, 0, 0
    isServer = function() return server end
    isClient = function() return client end
    getActivatedMods = function() return {contains = function(_, id)
        return id == "SaucedCarts" and carts or id == "P4TidyUpMeister" and tidy
    end} end
    require = function(name) assert(name:find("SaucedCarts/", 1, true)); required = required + 1 end
    local function perform(self, result)
        if self.expectCart then
            assert(self.character.primary == self.expectCart and self.character.secondary == self.expectCart)
            assert(equipped == self.expectEquipCount, "hands must be synchronized before native completion starts the next action")
        end
        return result
    end
    ISCartPickupAction = {findWorldItem=function(self) return self.source end, isValid = function() return "pickup-original" end, perform = function(self) return perform(self, "pickup-performed") end}
    ISCartEquipAction = {findCart=function(self) return self.source end, isValid = function() return "equip-original" end, perform = function(self) return perform(self, "equip-performed") end}
    Events = {OnPlayerUpdate = {Add = function(fn) handler = fn end}}
    SaucedCarts = {isCart = function(item) return item.cart end}
    sendEquip = function() equipped = equipped + 1 end
end
for _, mode in ipairs({{true,true,true}, {false,false,true}}) do
    setup(unpack(mode)); dofile(source); assert(not handler and required == 0)
end
setup(false,true,false); dofile(source); assert(not handler and required == 3)
setup(false,true,true); dofile(source); assert(handler and required == 3)
local function item(cart, ground, carried)
    return {cart=cart, carried=carried, isForceDropHeavyItem=function() return cart end, getID=function() return 123 end,
        getWorldItem=function() return ground and {} or nil end}
end
local p = {localPlayer=true}
function p:isLocalPlayer() return self.localPlayer end
function p:getPrimaryHandItem() return self.primary end
function p:getSecondaryHandItem() return self.secondary end
function p:getInventory() return {
    contains=function(_, it) return it.carried end,
    getItemById=function(_, id) return self.target and self.target:getID() == id and self.target or nil end,
} end
function p:setPrimaryHandItem(it) self.primary = it end
function p:setSecondaryHandItem(it) self.secondary = it end
function p:removeFromHands(it)
    if self.primary == it then self.primary = nil end
    if self.secondary == it then self.secondary = nil end
end
function p:resetEquippedHandsModels() models = models + 1 end
local valid, razor = item(true,false,true), item(false,false,true)
p.primary, p.secondary = valid, razor; handler(p)
assert(p.primary == valid and p.secondary == razor and equipped == 0)
local dropped = item(true,true,false)
p.primary, p.secondary = dropped, dropped; handler(p)
assert(not p.primary and not p.secondary and equipped == 1 and models == 1)
p.primary, p.secondary = razor, dropped; handler(p)
assert(p.primary == razor and not p.secondary and equipped == 2)
p.primary, p.secondary = item(true,false,false), valid; handler(p)
assert(not p.primary and p.secondary == valid and equipped == 3)
p.primary, p.secondary = dropped, dropped; p.localPlayer = false; handler(p)
assert(p.primary == dropped and p.secondary == dropped and equipped == 3)
p.localPlayer = true; p.primary, p.secondary = razor, nil; handler(p)
assert(p.primary == razor and equipped == 3 and models == 3)
require = nativeRequire
print("PASS cart cancellation hand cleanup preserves valid equipment, clears both stale slots once and ignores remote players/inactive mods")
local action = {character=p, itemId=123, cartId=123, started=true,
    isStarted=function(self) return self.started end}
p.primary, p.target = valid, valid
assert(ISCartPickupAction.isValid(action) == true and ISCartEquipAction.isValid(action) == true)
action.itemId=124
assert(ISCartPickupAction.isValid(action) == "pickup-original" and ISCartEquipAction.isValid(action) == true)
action.itemId=123; action.started=false
assert(ISCartPickupAction.isValid(action) == "pickup-original")
action.started=true; p.primary, p.target=dropped, dropped
assert(ISCartPickupAction.isValid(action) == "pickup-original")
p.primary=item(true,false,false); p.target=p.primary
assert(ISCartEquipAction.isValid(action) == "equip-original")
p.primary, p.target=valid, valid; client=false
assert(ISCartPickupAction.isValid(action) == "pickup-original" and ISCartEquipAction.isValid(action) == "equip-original")
client=true; p.primary,p.secondary,p.target=nil,nil,valid
assert(ISCartPickupAction.isValid(action) == true)
local before=equipped
action.expectCart,action.expectEquipCount=valid,before+1
assert(ISCartPickupAction.perform(action) == "pickup-performed")
assert(p.primary == valid and p.secondary == valid and equipped == before+1)
assert(ISCartEquipAction.perform(action) == "equip-performed" and equipped == before+1)
p.primary,p.secondary=razor,razor
assert(ISCartPickupAction.isValid(action) == true)
action.expectEquipCount=before+2
ISCartPickupAction.perform(action)
assert(p.primary == valid and p.secondary == valid and equipped == before+2)
before=equipped
action.expectCart=nil
local foreignHeavy=item(true,false,true)
p.primary,p.secondary=foreignHeavy,foreignHeavy
assert(ISCartPickupAction.isValid(action) == "pickup-original")
ISCartPickupAction.perform(action)
assert(p.primary == foreignHeavy and p.secondary == foreignHeavy and equipped == before)
before=equipped
p.primary,p.secondary=nil,razor; action.started=false
ISCartEquipAction.perform(action)
assert(not p.primary and p.secondary == razor and equipped == before)
action.started=true; p.target=nil
assert(ISCartPickupAction.isValid(action) == "pickup-original")
ISCartPickupAction.perform(action)
assert(not p.primary and p.secondary == razor and equipped == before)
p.target=valid; client=false
ISCartEquipAction.perform(action)
assert(not p.primary and p.secondary == razor and equipped == before)
print("PASS MP cart completion accepts only its started action's own inventory cart, repairs missing equip on successful perform and preserves other targets, cancellation, SP and server validation")

client=true
setup(false,true,false)
ISCartPickupAction.isValid=function() return false end
ISCartEquipAction.isValid=function() return false end
dofile(source)
local gap={character=p,itemId=123,cartId=123,started=true,isStarted=action.isStarted}
p.primary,p.target=nil,nil
now=2000
assert(ISCartPickupAction.isValid(gap) == true and gap.toolkitCartSyncUntil == 3000)
now=2999
assert(ISCartEquipAction.isValid(gap) == true and gap.toolkitCartSyncUntil == 3000)
now=3000
assert(ISCartPickupAction.isValid(gap) == false and gap.toolkitCartSyncUntil == 3000)
gap.toolkitCartSyncUntil=nil; gap.source={}
assert(ISCartPickupAction.isValid(gap) == false and not gap.toolkitCartSyncUntil)
gap.source=nil; p.primary=foreignHeavy
foreignHeavy.getID=function() return 124 end
assert(ISCartPickupAction.isValid(gap) == false and not gap.toolkitCartSyncUntil)
p.primary=nil; gap.started=false
assert(ISCartPickupAction.isValid(gap) == false and not gap.toolkitCartSyncUntil)
gap.started=true; client=false
assert(ISCartEquipAction.isValid(gap) == false and not gap.toolkitCartSyncUntil)
client=true; p.target=valid; now=4000; gap.toolkitCartSyncUntil=3000
assert(ISCartPickupAction.isValid(gap) == true, "exact inventory acknowledgement supersedes expired packet grace")
print("PASS missing-target MP packet grace is limited to one second, never extends and preserves range/foreign-heavy/prestart/SP rejection")
