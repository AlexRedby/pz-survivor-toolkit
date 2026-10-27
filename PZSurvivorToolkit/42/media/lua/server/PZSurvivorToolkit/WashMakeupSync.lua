-- B42 body washing removes makeup on the authority but omits its inventory packet.
-- Keep the native removal and publish only the exact root item it actually removed.
if not isServer() or isClient() then return end
require "TimedActions/ISWashYourself"
local Proof = require "PZSurvivorToolkit/SourceProof"
local matches, closure = Proof.matches, Proof.closure
local owner, locations, notify = ISWashYourself, ItemBodyLocation, sendRemoveItemFromContainer
if not notify or type(owner) ~= "table" or not locations or type(matches) ~= "function" or type(closure) ~= "function"
    or not matches("media/lua/shared/TimedActions/ISWashYourself.lua", 1510864116, nil, true) then return end
local names = {"new", "isValid", "update", "start", "stopSound", "stop", "washPart", "removeAllMakeup", "removeMakeup",
    "GetRequiredSoap", "GetSoapRemaining", "GetRequiredWater", "perform", "complete", "animEvent", "getDuration"}
local methods, seen = {}, {}
for name, callback in pairs(owner) do
    if type(callback) == "function" and name ~= "derive" then
        if seen[callback] or not closure(callback, "ISWashYourself.lua") then return end
        methods[name], seen[callback] = callback, true
    end
end
for _, name in ipairs(names) do if type(methods[name]) ~= "function" then return end end
local slots = {locations.MAKE_UP_FULL_FACE, locations.MAKE_UP_EYES, locations.MAKE_UP_EYES_SHADOW, locations.MAKE_UP_LIPS}
if #slots ~= 4 then return end
local original, kind = methods.removeMakeup, owner.Type
local replacement
local function live(action)
    if not isServer() or isClient() or ISWashYourself ~= owner or ItemBodyLocation ~= locations
        or sendRemoveItemFromContainer ~= notify or Proof.matches ~= matches or Proof.closure ~= closure
        or owner.Type ~= kind or (owner.__index ~= nil and owner.__index ~= owner)
        or type(action) ~= "table" or getmetatable(action) ~= owner or action.Type ~= kind then return false end
    if locations.MAKE_UP_FULL_FACE ~= slots[1] or locations.MAKE_UP_EYES ~= slots[2]
        or locations.MAKE_UP_EYES_SHADOW ~= slots[3] or locations.MAKE_UP_LIPS ~= slots[4] then return false end
    for name, callback in pairs(methods) do
        local expected = name == "removeMakeup" and replacement or callback
        if owner[name] ~= expected or action[name] ~= expected or not closure(callback, "ISWashYourself.lua") then return false end
    end
    for name, callback in pairs(owner) do
        if type(callback) == "function" and name ~= "derive" and not methods[name] then return false end
    end
    -- Per-instance callbacks are not part of the reviewed native completion path.
    for _, value in pairs(action) do if type(value) == "function" then return false end end
    return not action.onStartFunc and not action.onCompleteFunc and not action.onCancelFunc and not action.onFailFunc
        and not action.additionalTest and not action.retriggerLastAction
end
local function count(root, item, id)
    local references, ids = 0, 0
    local values = root:getItems()
    for i = 0, values:size() - 1 do
        local value = values:get(i)
        if value == item then references = references + 1 end
        if value:getID() == id then ids = ids + 1 end
    end
    return references, ids
end
local function context(action, item)
    if not live(action) or not instanceof(item, "Clothing") or not instanceof(action.character, "IsoPlayer") then return end
    local actor = action.character
    local root, slot, id = actor:getInventory(), item:getBodyLocation(), item:getID()
    if not instanceof(root, "ItemContainer") or root:getParent() ~= actor or root:getContainingItem() ~= nil
        or item:getContainer() ~= root or root:getItemById(id) ~= item then return end
    local supported = false
    for _, value in ipairs(slots) do if value == slot then supported = true end end
    if not supported or actor:getWornItem(slot) ~= item then return end
    local references, ids = count(root, item, id)
    if references ~= 1 or ids ~= 1 then return end
    return {actor = actor, root = root, slot = slot, id = id, fullType = item:getFullType()}
end
local function pack(...) return {n = select("#", ...), ...} end
replacement = function(action, item)
    local before = context(action, item)
    local results = pack(original(action, item))
    if before and live(action) and action.character == before.actor and before.actor:getInventory() == before.root
        and before.root:getParent() == before.actor and item:getID() == before.id and item:getFullType() == before.fullType
        and before.actor:getWornItem(before.slot) == nil and before.root:getItemById(before.id) == nil then
        local references, ids = count(before.root, item, before.id)
        if references == 0 and ids == 0 then notify(before.root, item) end
    end
    return unpack(results, 1, results.n)
end
owner.removeMakeup = replacement
