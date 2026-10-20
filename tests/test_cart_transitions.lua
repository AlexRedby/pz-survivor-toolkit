local shared = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/shared/ToolkitWoodCartActions.lua"
local client = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/ZZToolkitWoodCartActions.lua"
local hands = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/000ToolkitCartHandsCompatibility.lua"
local originalRequire = require
local function setup(server, enabled, bridge)
    local w = {added = {}, ended = 0, presented = 0, equipped = 0}
    ToolkitCartRefreshVisual = nil
    isServer = function() return server end
    isClient = function() return not server end
    getActivatedMods = function() return {contains = function(_, name) return enabled and name == "SaucedCarts" end} end
    Events = {}
    w.events = {}
    for _, event in ipairs({"OnPlayerUpdate", "OnPlayerDeath", "OnMainMenuEnter", "OnGameStart", "OnKeyStartPressed"}) do
        Events[event] = {Add = function(fn) w.events[event] = fn end}
    end
    getTimestampMs = function() return 100 end
    getText = function(key) return key end
    Metabolics = {HeavyDomestic = "heavy"}
    ItemTag = {WEARABLE = "wearable"}
    CharacterTrait = {DEXTROUS="dextrous",ALL_THUMBS="thumbs"}
    ISInventoryPage = {}
    triggerEvent = function() end
    getPlayerInventory = function() return {refreshBackpacks = function() end} end
    getPlayerHotbar = function() return nil end
    ISWearClothing = {isStopOnWalk = function() return false end}
    ISBaseTimedAction = {}
    function ISBaseTimedAction:derive(name)
        local class = {Type = name}; class.__index = class
        return setmetatable(class, {__index = self})
    end
    function ISBaseTimedAction:new(character) return setmetatable({character = character}, self) end
    function ISBaseTimedAction:getJobDelta() return .4 end
    function ISBaseTimedAction:isStarted() return self.started == true end
    function ISBaseTimedAction:setActionAnim(anim) self.anim = anim end
    function ISBaseTimedAction:setAnimVariable() end
    function ISBaseTimedAction:setOverrideHandModels(item) self.override = item end
    function ISBaseTimedAction:setOverrideHandModelsString(primary, secondary)
        assert(primary == nil or type(primary) == "string", "action must override the model without item hand masks")
        assert(secondary == nil, "transition duplicated its cart model")
        self.override = primary; self.stringOverride = true
    end
    function ISBaseTimedAction:addAfter(action)
        w.added[#w.added + 1] = action
        if w.queue then
            assert(w.queue[1] == self, "continuation must be inserted before the approach completes")
            table.insert(w.queue, 2, action)
        end
    end
    function ISBaseTimedAction:perform()
        if w.queue and w.queue[1] == self then table.remove(w.queue, 1); w.startedNext = w.queue[1] end
        if self.expectCart then
            assert(self.character.primary == self.expectCart and self.character.secondary == self.expectCart,
                "pickup must bind its exact cart before native perform starts the next action")
        end
        self.performed = (self.performed or 0) + 1
        return "performed"
    end
    function ISBaseTimedAction:stop() self.stopped = true; return "stopped" end
    function ISBaseTimedAction:forceCancel() end
    function ISBaseTimedAction:forceStop() self.forcedStop=true;self:stop() end
    SaucedCarts = {isCart = function(item) return item.cart == true end}
    function SaucedCarts.clearCartPose(player)
        for _, name in ipairs({"Weapon", "RightHandMask", "LeftHandMask"}) do player:setVariable(name, "") end
    end
    sendEquip = function() w.equipped = w.equipped + 1 end
    require = function() return true end
    ISCartPickupAction = ISBaseTimedAction:derive("ISCartPickupAction")
    function ISCartPickupAction:getDuration() return self.character:isTimedActionInstant() and 1 or 50 end
    function ISCartPickupAction:findWorldItem()
        local world = w.world
        return world and world:getItem():getID() == self.itemId and self.squareX == 1 and world or nil
    end
    function ISCartPickupAction:findItem() local world = self:findWorldItem(); return world and world:getItem() end
    function ISCartPickupAction:isValid() return self:findWorldItem() ~= nil end
    function ISCartPickupAction:waitToStart() self.character.nativeFace = true; return self.character:shouldBeTurning() end
    function ISCartPickupAction:new(character, x, y, z, id)
        local action = ISBaseTimedAction.new(self, character)
        action.squareX, action.squareY, action.squareZ, action.itemId = x, y, z, id
        action.maxTime = action:getDuration()
        action.stopOnWalk, action.stopOnRun, action.stopOnAim = false, false, false
        return action
    end
    function ISCartPickupAction.FromWorldItem(character, world)
        local sq = world:getSquare()
        return ISCartPickupAction:new(character, sq:getX(), sq:getY(), sq:getZ(), world:getItem():getID())
    end
    ISDropWorldItemAction = ISBaseTimedAction:derive("ISDropWorldItemAction")
    function ISDropWorldItemAction:getDuration() return self.character:isTimedActionInstant() and 1 or 15 end
    function ISDropWorldItemAction:new(character, item, sq, xoffset, yoffset, zoffset, rotation, isMultiple)
        return setmetatable({character=character,item=item,sq=sq,xoffset=xoffset,yoffset=yoffset,zoffset=zoffset,
            rotation=rotation,isMultiple=isMultiple,maxTime=15},self)
    end
    function ISDropWorldItemAction:start() self.nativeDropStarted=true end
    function ISDropWorldItemAction:update() self.item:setJobDelta(self:getJobDelta()) end
    function ISDropWorldItemAction:complete() self.nativeDropCompleted=(self.nativeDropCompleted or 0)+1; return true end
    ISUnequipAction = ISBaseTimedAction:derive("ISUnequipAction")
    function ISUnequipAction:new(character, item, duration, reason)
        return setmetatable({character = character, item = item, maxTime = duration, reason = reason,
            stopOnWalk = false, stopOnRun = true, stopOnAim = false}, self)
    end
    function ISUnequipAction:start() self.nativeStarted = true end
    function ISUnequipAction:update() self.item:setJobDelta(self:getJobDelta()) end
    function ISUnequipAction:complete() self.character:removeWornItem(self.item); return self.character.completeResult ~= false end
    if SaucedCartsSource then dofile(SaucedCartsSource .. "/TimedActions/ISCartPickupAction.lua") end
    if NativeActionRoot then
        dofile(NativeActionRoot .. "/shared/TimedActions/ISUnequipAction.lua")
        dofile(NativeActionRoot .. "/shared/TimedActions/ISDropWorldItemAction.lua")
    end
    ISCartEquipAction = {findCart = function() end, isValid = function() return false end, perform = ISBaseTimedAction.perform}
    dofile(hands)
    w.nativeComplete, w.nativeUnequipComplete = ISCartPickupAction.complete, ISUnequipAction.complete
    w.pickupPerform = ISCartPickupAction.perform
    ISTimedActionQueue = {add = function(action) w.added[#w.added + 1] = action end,
        addToQueue = function(queue, action) queue.last = action; return "queued" end}
    ISWalkToTimedActionF = ISBaseTimedAction:derive("ISWalkToTimedActionF")
    function ISWalkToTimedActionF:new(character, location) return setmetatable({character = character, location = location}, self) end
    function ISWalkToTimedActionF:setOnComplete(fn) self.onCompleteFunc = fn end
    function ISWalkToTimedActionF:perform() ISBaseTimedAction.perform(self); if self.onCompleteFunc then self.onCompleteFunc() end end
    if NativeActionRoot then dofile(NativeActionRoot .. "/client/TimedActions/WalkToTimedActionF.lua") end
    Vector3f = {new = function(x, y, z) return {x = function() return x end, y = function() return y end, z = function() return z end} end}
    toolkitWoodCartStance = bridge and function() return {x = 1.3, y = 2.2, faceX = 1.8, faceY = 2.8, aligned = w.aligned} end or nil
    toolkitWoodCartUpdate = bridge and function() w.presented = w.presented + 1 end or nil
    toolkitWoodCartEnd = bridge and function(character) w.ended = w.ended + 1; w.endedCharacter = character end or nil
    toolkitWoodCartCancel = nil
    toolkitWoodCartTick = bridge and function(character) w.ticked = character end or nil
    toolkitWoodCartDropPose = bridge and function(character, item)
        assert(character == w.p and item:getFullType() == "SaucedWheelbarrow.WheelbarrowWood")
        return not w.noDropPose and (w.dropPose or {x = 1.25, y = 2.75, z = 0, rotation = 90}) or nil
    end or nil
    toolkitWoodCartSetdownPose = bridge and function(character, item, x, y, z, rotation)
        assert(character == w.p and item:getFullType() == "SaucedWheelbarrow.WheelbarrowWood")
        w.setdownPose = {x = x, y = y, z = z, rotation = rotation}
    end or nil
    toolkitWoodCartDropBegin = bridge and function(character, item, x, y, z, rotation)
        assert(character == w.p and item:getFullType() == "SaucedWheelbarrow.WheelbarrowWood")
        assert(x == 1.25 and y == 2.75 and z == 0 and rotation == 90, "prepared drop lost exact stored pose")
        w.begins = (w.begins or 0) + 1
        w.dropActive = w.prepareResult ~= false
        return w.dropActive
    end or nil
    toolkitWoodCartDropEnd = bridge and function()
        assert(w.dropActive, "unprepared scope was cleared")
        w.dropEnds = (w.dropEnds or 0) + 1; w.dropActive = false
    end or nil
    ToolkitWoodCartPickup, ToolkitWoodCartSetdown, ToolkitWoodCartDrop = nil, nil, nil
    w.dropFingerprint = {}; for key, value in pairs(ISDropWorldItemAction) do w.dropFingerprint[key] = value end
    w.unequipFingerprint = {}; for key, value in pairs(ISUnequipAction) do w.unequipFingerprint[key] = value end
    local transitions = dofile(shared)
    require = function(name) return name == "ToolkitWoodCartActions" and transitions or true end
    dofile(client)
    local p = {vars = {}, inventory = {}}
    function p:hasTrait() return false end
    function p:isWearingAwkwardGloves() return false end
    function p:getEmitter() return {isPlaying=function() return false end} end
    function p:playSound() return 1 end
    function p:stopOrTriggerSound() end
    function p:isTimedActionInstant() return self.instant end
    function p:getCurrentSquare() return w.square end
    function p:getPrimaryHandItem() return self.primary end
    function p:getSecondaryHandItem() return self.secondary end
    function p:setPrimaryHandItem(item) self.primary = item end
    function p:setSecondaryHandItem(item) self.secondary = item end
    function p:removeWornItem(item)
        self.completeCalls = (self.completeCalls or 0) + 1
        w.completeInScope = w.dropActive == true
        assert(item == self.primary, "native complete received another item")
        if self.completeError then error("native complete failure") end
    end
    function p:getInventory() return {containsID=function(_,id) return self.inventory[id]~=nil end, getItemById = function(_, id) return self.inventory[id] end,
        contains = function(_, item) return self.inventory[item:getID()] == item end} end
    function p:setVariable(name, value) self.vars[name] = value end
    function p:clearVariable(name) self.vars[name] = nil end
    function p:faceLocationF(x, y) self.faceX, self.faceY = x, y end
    function p:shouldBeTurning() return self.turning end
    function p:setMetabolicTarget(value) self.metabolic = value end
    function p:DistTo() error("integer DistTo overload truncates fractional stance coordinates") end
    function p:DistToSquared() return (self.distance or 1)^2 end
    function p:getPlayerNum() return 0 end
    function p:getZ() return self.z or 0 end
    function p:isHandItem(item) return self.primary == item or self.secondary == item end
    function p:getPathFindBehavior2() return {cancel = function() end} end
    function p:setPath2() end
    function p:getSquare() return {canReachTo = function() return w.reachable ~= false end} end
    function w.item(kind, id)
        local item = {kind = kind or "SaucedWheelbarrow.WheelbarrowWood", id = id or 123, cart = true}
        function item:getType() return "WheelbarrowWood" end
        function item:getActualWeight() return 10 end
        function item:getUnequippedWeight() return 10 end
        function item:getPlaceOneSound() end
        function item:setWorldZRotation(rotation) self.worldRotation=rotation end
        function item:getFullType() return self.kind end
        function item:getID() return self.id end
        function item:isForceDropHeavyItem() return true end
        function item:isTwoHandWeapon() return true end
        function item:isRequiresEquippedBothHands() return true end
        function item:getWorldItem() return self.world end
        function item:getStaticModel() return "WheelbarrowWood" end
        function item:setJobDelta(value) self.delta = value end
        function item:setJobType(value) self.job = value end
        function item:getName() return "cart" end
        function item:getUnequipSound() end
        function item:canBeActivated() return false end
        function item:getContainer() end
        function item:IsInventoryContainer() return false end
        function item:IsClothing() return false end
        function item:hasTag() return false end
        return item
    end
    w.square = {getX = function() return 1 end, getY = function() return 2 end, getZ = function() return 0 end}
    function w.square:getWorldObjects() return {size = function() return w.world and 1 or 0 end, get = function() return w.world end} end
    getCell = function() return {getGridSquare = function(_, x, y, z)
        if w.missingDropSquare then return nil end
        if w.extraSquare and x==2 and y==3 and z==0 then return w.extraSquare end
        return x == 1 and y == 2 and z == 0 and w.square or nil end} end
    instanceof = function(_, kind) return kind == "IsoWorldInventoryObject" end
    function w.worldFor(item)
        local world = {getItem = function() return item end, getSquare = function() return w.square end}
        item.world = world; w.world = world; return world
    end
    w.p = p
    return w
end

local w = setup(false, false, true)
assert(not ToolkitWoodCartPickup and not ToolkitWoodCartSetdown)
w = setup(true, true, false)
assert(ToolkitWoodCartPickup.Type == "ToolkitWoodCartPickup" and ToolkitWoodCartSetdown.Type == "ToolkitWoodCartSetdown")
-- NetTimedAction serializes the fields named by the constructor's Lua parameters.
local constructor, parameters = ISCartPickupAction.new, {}
debug.sethook(function()
    if debug.getinfo(2, "f").func ~= constructor then return end
    for index = 1, 6 do parameters[index] = debug.getlocal(2, index) end
end, "c")
local serialized = ISCartPickupAction:new(w.p, 1, 2, 0, 123)
debug.sethook()
local arguments = {}
for index = 2, 6 do
    local name = parameters[index]
    assert(name and serialized[name] ~= nil, "native MP constructor parameter has no serialized field: " .. tostring(name))
    arguments[index - 1] = serialized[name]
end
local reconstructed = ISCartPickupAction:new(unpack(arguments, 1, 5))
assert(reconstructed.character == w.p and reconstructed.squareX == 1 and reconstructed.squareY == 2
    and reconstructed.squareZ == 0 and reconstructed.itemId == 123, "native server reconstruction lost pickup identity")
print("PASS cart pickup constructor preserves the native parameter-name serialization contract")
assert(ISCartPickupAction.complete == w.nativeComplete and ISUnequipAction.complete == w.nativeUnequipComplete,
    "shared registration must retain authoritative pickup and ordinary unequip complete")
local wood = w.item(); w.worldFor(wood)
assert(getmetatable(ISCartPickupAction:new(w.p, 1, 2, 0, 123)) == ISCartPickupAction)
w.p.primary, w.p.secondary = wood, wood
local serverSetdown = setmetatable({character = w.p, item = wood, reason = "drop", toolkitDropX = 1.25,
    toolkitDropY = 2.75, toolkitDropZ = 0, toolkitDropRotation = 90}, ToolkitWoodCartSetdown)
assert(serverSetdown:complete() == true and w.p.completeCalls == 1 and not w.completeInScope,
    "server subclass must preserve native completion without client placement bridge")
print("PASS wooden transitions register shared action types and preserve native fallback without the animation bridge")

w = setup(false, true, true)
local p = w.p
wood = w.item(); local world = w.worldFor(wood)
local unequipFingerprint = w.unequipFingerprint
local pickup = ISCartPickupAction:new(p, 1, 2, 0, 123)
assert(getmetatable(pickup) == ToolkitWoodCartPickup and pickup.maxTime == 88)
assert(pickup.stopOnWalk and pickup.stopOnRun and pickup.stopOnAim)
assert(ISCartPickupAction.complete == w.nativeComplete and ToolkitWoodCartPickup.perform ~= w.pickupPerform)
p.instant = true
local instantPickup = ISCartPickupAction:new(p, 1, 2, 0, 123)
assert(instantPickup.maxTime == 1 and getmetatable(instantPickup) == ISCartPickupAction)
p.instant = false
assert(getmetatable(ISCartPickupAction:new(p, 1, 2, 0, 124)) == ISCartPickupAction, "wrong item ID was promoted")
local steel = w.item("SaucedWheelbarrow.Wheelbarrow", 124); w.worldFor(steel)
local normal = ISCartPickupAction:new(p, 1, 2, 0, 124)
assert(getmetatable(normal) == ISCartPickupAction and normal.maxTime == 50 and not normal.stopOnWalk)
w.world = world
p.turning = true; assert(pickup:waitToStart() and p.faceX == 1.8 and p.faceY == 2.8)
p.turning = false; w.aligned = false
assert(pickup:waitToStart(), "stale native twist must not start pickup before the body faces the handles")
w.aligned = true; assert(not pickup:waitToStart(), "aligned body should start pickup without an extra delay")
p.vars.ToolkitCartMotion = true
pickup:start(); pickup:update()
assert(p.vars.ToolkitCartMotion == false, "timed action must disable steering immediately")
assert(p.vars.ToolkitWoodCartAction and p.vars.ToolkitWoodCartProgress == .4
    and pickup.stringOverride and pickup.override == wood:getStaticModel() and wood.delta == .4)
local queued = ISCartPickupAction:new(p, 1, 2, 0, 123)
queued:forceCancel(); assert(p.vars.ToolkitWoodCartAction and w.ended == 0, "queued cancellation cleared the current presentation")
pickup:stop()
assert(pickup.stopped and not p.vars.ToolkitWoodCartAction and not p.vars.ToolkitWoodCartProgress and w.ended == 1)
pickup:forceCancel(); assert(w.ended == 1, "transition cleanup was repeated")
pickup.started = true; pickup:start(); wood.world = nil; w.world = nil; p.inventory[123] = wood
pickup.expectCart = wood
pickup:perform()
assert(pickup.performed == 1 and w.equipped == 1 and w.ended == 2)
assert(p.primary == wood and p.secondary == wood and not p.vars.ToolkitWoodCartAction)
local beforeEquip = w.equipped
local wrongId = ToolkitWoodCartPickup:new(p, 1, 2, 0, 124); wrongId.started = true
p.primary, p.secondary = nil, nil; wrongId:perform()
assert(not p.primary and not p.secondary and w.equipped == beforeEquip, "pickup rebound a different inventory ID")
p.primary, p.secondary = steel, steel; pickup.expectCart = nil; pickup:perform()
assert(p.primary == steel and p.secondary == steel and w.equipped == beforeEquip, "pickup overwrote a foreign heavy cart")
print("PASS wooden pickup selects exact IDs, preserves ordinary carts, faces the stance, clears owned presentation and routes MP hand repair through native perform")
local nativeComplete, nativePerform = ISCartPickupAction.complete, ISCartPickupAction.perform
local order, finishing = {}, {}
pickup.action = finishing
ToolkitCartRefreshVisual = function(player, action)
    assert(player == p and action == finishing, "visual refresh lost its exact finishing native action")
    order[#order + 1] = "visual"
end
ISCartPickupAction.complete = function(self)
    assert(self == pickup); order[#order + 1] = "complete"
    p.primary, p.secondary = wood, wood
    return false
end
assert(pickup:complete() == false and table.concat(order, ",") == "complete,visual",
    "SP visual handoff must follow exactly one authoritative complete and preserve its result")
order = {}
ISCartPickupAction.perform = function(self)
    assert(self == pickup); order[#order + 1] = "perform"
    p.primary, p.secondary = wood, wood
    return "native-result"
end
assert(pickup:perform() == "native-result" and table.concat(order, ",") == "perform,visual",
    "client visual handoff must follow native perform/equip repair")
order = {}
ISCartPickupAction.perform = function() p.primary, p.secondary = steel, steel end
pickup:perform()
assert(#order == 0, "pickup visual handoff adopted a replacement cart")
ISCartPickupAction.complete = function() error("native pickup failure") end
local ok, err = pcall(pickup.complete, pickup)
assert(not ok and tostring(err):find("native pickup failure", 1, true) and #order == 0,
    "visual handoff swallowed native completion failure")
ISCartPickupAction.complete, ISCartPickupAction.perform = nativeComplete, nativePerform
ToolkitCartRefreshVisual = nil


w.world = world; wood.world = world; p.primary, p.secondary = wood, wood
local release = setmetatable({character=p, item=wood, reason="drop"}, ToolkitWoodCartSetdown)
p.vars.Weapon, p.vars.RightHandMask, p.vars.LeftHandMask = "cart", "holdingcartright", "holdingcartleft"
release:start()
assert(release.stringOverride and release.override == wood:getStaticModel(), "setdown reused the item's hand mask")
assert(p.vars.Weapon == "" and p.vars.RightHandMask == "" and p.vars.LeftHandMask == "",
    "setdown must fade the underlying cart-idle before releasing its action pose")
-- A first holder update may restore cart variables once in an immediate pickup -> setdown chain.
p.vars.Weapon, p.vars.RightHandMask, p.vars.LeftHandMask = "cart", "holdingcartright", "holdingcartleft"
release:update()
assert(p.vars.Weapon == "" and p.vars.RightHandMask == "" and p.vars.LeftHandMask == ""
    and p.primary == wood and p.secondary == wood, "pose retirement changed ownership or allowed a stale idle layer")
release:stop()
local stopOriginal = rawget(ISUnequipAction, "stop")
local stopCalls, visualCalls = 0, 0
release.action = {}
ISUnequipAction.stop = function(self)
    assert(self == release); stopCalls = stopCalls + 1
    if self.stopError then error("native stop failure") end
    return "native stopped"
end
ToolkitCartRefreshVisual = function(player, action, stopped)
    assert(player == p and action == release.action and stopped == true and stopCalls == 1,
        "cancelled setdown refreshed before native stop or lost exact identity")
    visualCalls = visualCalls + 1
end
local completed, performed = p.completeCalls, release.performed
assert(release:stop() == "native stopped" and visualCalls == 1 and stopCalls == 1)
assert(p.completeCalls == completed and release.performed == performed, "stop transferred cart ownership")
p.primary, p.secondary = steel, steel
release:stop(); assert(stopCalls == 2 and visualCalls == 1, "cancelled setdown adopted a replacement cart")
p.primary, p.secondary = wood, wood; release.stopError = true
local stopOK, stopError = pcall(release.stop, release)
assert(not stopOK and tostring(stopError):find("native stop failure", 1, true) and visualCalls == 1)
ISUnequipAction.stop, ToolkitCartRefreshVisual = stopOriginal, nil
local queue = {}
for _, reason in ipairs({false, "drop", "place"}) do
    local action = ISUnequipAction:new(p, wood, reason and 1 or 50, reason or nil)
    assert(ISTimedActionQueue.addToQueue(queue, action) == "queued" and queue.last == action)
    assert(getmetatable(action) == ToolkitWoodCartSetdown and action.maxTime == 88)
    assert(action.stopOnWalk and action.stopOnRun and action.stopOnAim)
    assert(action.toolkitDropX == 1.25 and action.toolkitDropY == 2.75 and action.toolkitDropZ == 0 and action.toolkitDropRotation == 90)
    action:start(); action:update(); assert(p.vars.ToolkitWoodCartAction and wood.delta == .4)
    local waiting = ISUnequipAction:new(p, wood, 1, reason or nil)
    ISTimedActionQueue.addToQueue(queue, waiting); waiting:forceCancel()
    assert(p.vars.ToolkitWoodCartAction, "queued setdown cancellation cleared another action presentation")
    action:forceCancel(); assert(not p.vars.ToolkitWoodCartAction and not p.vars.ToolkitWoodCartProgress)
    action:start(); action:stop(); assert(action.stopped and not p.vars.ToolkitWoodCartAction)
    action:start(); action:perform(); assert(action.performed == 1 and not p.vars.ToolkitWoodCartAction)
end
SaucedCarts.TransferRestrictions = {hasPendingTransfer = function(id) return id == wood:getID() end}
local vehicleUnequip = ISUnequipAction:new(p, wood, 50)
ISTimedActionQueue.addToQueue(queue, vehicleUnequip)
assert(getmetatable(vehicleUnequip) == ISUnequipAction, "vehicle transfer became a ground setdown")
SaucedCarts.TransferRestrictions = nil
if NativeActionRoot then
    getTextManager = function() return {getFontHeight = function() return 16 end} end
    UIFont = {Small = "small"}
    ISToolTip = ISBaseTimedAction
    dofile(NativeActionRoot .. "/client/ISUI/ISInventoryPaneContextMenu.lua")
    ISInventoryPane = {getActualItems = function(items) return items end}
    getSpecificPlayer = function(number) assert(number == 0); return p end
    function p:isEquipped(item) return self:isHandItem(item) end
    function wood:getType() return "WheelbarrowWood" end
    local add = ISTimedActionQueue.add
    ISTimedActionQueue.add = function(action) return ISTimedActionQueue.addToQueue(queue, action) end
    -- ISWorldObjectContextMenuLogic binds DropNamedItem to this inventory callback.
    ISInventoryPaneContextMenu.onUnEquip({wood}, 0)
    assert(queue.last.Type == "ToolkitWoodCartSetdown" and queue.last.reason == nil
        and queue.last.maxTime == 88, "native world-menu drop bypassed wooden setdown")
    ISTimedActionQueue.add = add
    print("PASS native world-menu onUnEquip callback dispatches wooden setdown without a drop reason")
end
-- Exact native drop instances retain their constructor fields and authoritative callbacks.
local dropBaseComplete = ISDropWorldItemAction.complete
local dropCalls = 0
ISDropWorldItemAction.complete = function(self)
    dropCalls=dropCalls+1
    assert(not w.dropActive, "drop must not enter the unequip hook that transmits automatically")
    return "native drop complete"
end
local dropped = ISDropWorldItemAction:new(p,wood,w.square,.5,.5,0,0,false)
ISTimedActionQueue.addToQueue(queue,dropped)
assert(dropped.Type=="ToolkitWoodCartDrop" and dropped.maxTime==88)
assert(dropped.rotation==90 and dropped.xoffset==.25 and dropped.yoffset==.75)
assert(dropped:complete()=="native drop complete" and dropCalls==1)
local copy = ToolkitWoodCartDrop:new(p,wood,dropped.sq,dropped.xoffset,dropped.yoffset,dropped.zoffset,dropped.rotation,dropped.isMultiple)
assert(copy.Type=="ToolkitWoodCartDrop" and copy.rotation==90 and copy.xoffset==.25 and copy.yoffset==.75,
    "server reconstruction lost native drop constructor fields")
p.inventory[wood:getID()]=wood
w.dropPose={x=1,y=2,z=0,rotation=135}
dropped:start()
assert(dropped.rotation==135 and dropped.xoffset==.00001 and dropped.yoffset==.00001,
    "start must refresh serialized placement and avoid randomized zero offsets")
dropped:update();assert(wood.delta==.4 and p.vars.ToolkitWoodCartAction)
dropped:stop();assert(not p.vars.ToolkitWoodCartAction and dropCalls==1,"cancel must not complete or mutate ownership")
w.dropPose=nil
for _,kind in ipairs({"place","multiple","remote-square","onehand","item","instant","subclass","no-pose","transfer"}) do
    local action=ISDropWorldItemAction:new(p,wood,w.square,.5,.5,0,0,false)
    if kind=="place" then action.isPlaceItem=true
    elseif kind=="multiple" then action.isMultiple=true
    elseif kind=="remote-square" then action.sq={}
    elseif kind=="onehand" then p.secondary=nil
    elseif kind=="item" then action.item=steel
    elseif kind=="instant" then p.instant=true
    elseif kind=="subclass" then setmetatable(action,ISDropWorldItemAction:derive("OtherDrop"))
    elseif kind=="no-pose" then w.noDropPose=true
    else SaucedCarts.TransferRestrictions={hasPendingTransfer=function() return true end} end
    local class=getmetatable(action)
    ISTimedActionQueue.addToQueue(queue,action)
    assert(getmetatable(action)==class and action.xoffset==.5 and action.rotation==0,kind.." drop was hijacked")
    p.secondary=wood;p.instant=false;w.noDropPose=false;SaucedCarts.TransferRestrictions=nil
end
w.extraSquare={getX=function() return 2 end,getY=function() return 3 end,getZ=function() return 0 end}
w.dropPose={x=2.25,y=3.75,z=0,rotation=135}
local adjacent=ISDropWorldItemAction:new(p,wood,w.square,.5,.5,0,0,false)
ISTimedActionQueue.addToQueue(queue,adjacent);adjacent:start()
assert(adjacent.sq==w.extraSquare and adjacent.xoffset==.25 and adjacent.yoffset==.75 and adjacent.rotation==135)
local adjacentCopy=ToolkitWoodCartDrop:new(p,wood,adjacent.sq,adjacent.xoffset,adjacent.yoffset,adjacent.zoffset,adjacent.rotation,false)
assert(adjacentCopy.sq==w.extraSquare and adjacentCopy.rotation==135,"cross-square MP constructor fields changed")
adjacent:stop();w.dropPose=nil;w.extraSquare=nil
for _,missing in ipairs({"pose","square"}) do
    local unavailable=ISDropWorldItemAction:new(p,wood,w.square,.5,.5,0,0,false)
    ISTimedActionQueue.addToQueue(queue,unavailable)
    local presented=w.presented
    if missing=="pose" then w.noDropPose=true else w.missingDropSquare=true end
    unavailable:start()
    assert(unavailable.forcedStop and not p.vars.ToolkitWoodCartAction and w.presented==presented and dropCalls==1,
        "missing safe "..missing.." must cancel before presentation or completion")
    w.noDropPose=false;w.missingDropSquare=false
end
ISDropWorldItemAction.complete=dropBaseComplete
for key,value in pairs(ISDropWorldItemAction) do assert(w.dropFingerprint[key]==value,"ordinary drop class changed: "..key) end
print("PASS wooden native drop dispatch preserves placement, lifecycle, constructor fields and ordinary drop classes")

if SaucedCartsSource and NativeActionRoot then
    PZAPI={ModOptions={create=function() return {addKeyBind=function() return {getValue=function() return 99 end} end} end}}
    Keyboard={KEY_V=99};SandboxVars={};SaucedCarts.debug=function() end
    function p:isDead() return false end
    function p:getVehicle() end
    getSpecificPlayer=function(index) assert(index==0);return p end
    ISTimedActionQueue.getTimedActionQueue=function() return {queue={}} end
    local add=ISTimedActionQueue.add
    ISTimedActionQueue.add=function(action) return ISTimedActionQueue.addToQueue(queue,action) end
    dofile(SaucedCartsSource.."/../../client/SaucedCarts/Hotkeys.lua")
    w.events.OnGameStart();queue.last=nil
    w.events.OnKeyStartPressed(98);assert(not queue.last)
    w.events.OnKeyStartPressed(99)
    local action=queue.last
    assert(action.Type=="ToolkitWoodCartDrop" and action.item==wood and action.maxTime==88,
        "installed Sauced hotkey bypassed natural wooden setdown")
    local nativeComplete=ISDropWorldItemAction.complete
    local damage,transmissions,placed,removed=0,0,0,0
    local inv=p:getInventory();inv.Remove=function(_,item) assert(item==wood);p.inventory[item:getID()]=nil;removed=removed+1 end
    local getInventory=p.getInventory;p.getInventory=function() return inv end
    sendRemoveItemFromContainer=function(_,item) assert(item==wood) end
    w.square.getTotalWeightOfItemsOnFloor=function() return 0 end
    w.square.AddWorldInventoryItem=function(_,item,x,y,z,transmit)
        assert(item==wood and x==.25 and y==.75 and z==0 and transmit==false,
            "drop changed placement or enabled automatic duplicate transmission")
        placed=placed+1
        item.world={setIgnoreRemoveSandbox=function() end,setExtendedPlacement=function() end,
            transmitCompleteItemToClients=function() assert(item.worldRotation==90);transmissions=transmissions+1 end}
        return item
    end
    ISDropWorldItemAction.complete=function(self)
        damage=damage+1
        if w.breakDrop then inv:Remove(self.item);return nil end
        return nativeComplete(self)
    end
    action:start();assert(action:isValid());action:update()
    action:stop();assert(removed==0 and not p.vars.ToolkitWoodCartAction)
    action:start();assert(action:complete()==true)
    assert(damage==1 and placed==1 and transmissions==1 and removed==1,"drop lost native completion/durability chain")
    action:perform();assert(not p.vars.ToolkitWoodCartAction and action.performed==1)
    p.inventory[wood:getID()]=wood;wood.world=nil
    w.breakDrop=true
    local broken=ToolkitWoodCartDrop:new(p,wood,w.square,.25,.75,0,90,false)
    assert(broken:complete()==nil and damage==2 and placed==1 and transmissions==1 and removed==2,
        "destroyed cart must stay destroyed instead of falling through to world placement")
    ISDropWorldItemAction.complete=nativeComplete;w.breakDrop=nil;p.getInventory=getInventory
    p.inventory[wood:getID()]=wood;wood.world=nil;ISTimedActionQueue.add=add
    print("PASS installed Sauced hotkey uses native drop constructor, one authoritative placement/transmit, cancellation and live completion hooks")
end

local refreshed = ISUnequipAction:new(p, wood, 1, "drop")
ISTimedActionQueue.addToQueue(queue, refreshed)
assert(refreshed.toolkitDropX == 1.25)
w.dropPose = {x = 2.25, y = 3.75, z = 0, rotation = 135}
refreshed:start()
assert(refreshed.toolkitDropX == 2.25 and refreshed.toolkitDropY == 3.75 and refreshed.toolkitDropRotation == 135,
    "setdown must refresh its serialized pose when it starts")
assert(w.setdownPose.x == 2.25 and w.setdownPose.y == 3.75 and w.setdownPose.rotation == 135,
    "setdown presentation did not receive the refreshed native placement pose")
refreshed:stop(); w.dropPose = nil
p.instant = true
local instant = ISUnequipAction:new(p, wood, 1, "drop"); ISTimedActionQueue.addToQueue(queue, instant)
assert(instant.maxTime == 1 and getmetatable(instant) == ISUnequipAction); p.instant = false
for _, kind in ipairs({"reason", "item", "onehand", "subclass"}) do
    local action = ISUnequipAction:new(p, wood, 1, "drop")
    if kind == "reason" then action.reason = "unequip"
    elseif kind == "item" then action.item = steel
    elseif kind == "onehand" then p.secondary = nil
    else setmetatable(action, ISUnequipAction:derive("OtherUnequip")) end
    local class = getmetatable(action)
    ISTimedActionQueue.addToQueue(queue, action)
    assert(getmetatable(action) == class, kind .. " unexpectedly became a wooden setdown")
    p.secondary = wood
end
for key, value in pairs(ISUnequipAction) do assert(unequipFingerprint[key] == value, "ordinary unequip class fingerprint changed: " .. key) end
for key, value in pairs(unequipFingerprint) do assert(ISUnequipAction[key] == value) end
print("PASS wooden setdown handles native unequip/drop/place while preserving vehicle transfers, exact classes, hands and ordinary fingerprints")

for _, prepared in ipairs({true, false}) do
    for _, fails in ipairs({false, true}) do
        p.primary, p.secondary = wood, wood
        local action = ISUnequipAction:new(p, wood, 1, "drop")
        ISTimedActionQueue.addToQueue(queue, action)
        w.prepareResult, p.completeError = prepared, fails
        local beforeEnds, beforeCalls = w.dropEnds or 0, p.completeCalls or 0
        local ok, result = pcall(action.complete, action)
        assert(ok ~= fails and p.completeCalls == beforeCalls + 1, "native complete must run once regardless of preparation")
        if fails then assert(tostring(result):find("native complete failure", 1, true)) else assert(result == true) end
        assert(w.completeInScope == prepared and not w.dropActive, "placement scope leaked past native complete")
        assert((w.dropEnds or 0) == beforeEnds + (prepared and 1 or 0), "drop end must clear only its successful begin")
    end
end
p.completeError, w.prepareResult = nil, nil
p.primary, p.secondary = wood, wood
w.noDropPose = true
local noPose = ISUnequipAction:new(p, wood, 1, "drop")
ISTimedActionQueue.addToQueue(queue, noPose)
assert(getmetatable(noPose) == ISUnequipAction and not noPose.toolkitDropX, "unsafe pose promoted native unequip")
w.noDropPose = false
local dropPose = toolkitWoodCartDropPose; toolkitWoodCartDropPose = nil
local noPoseBridge = ISUnequipAction:new(p, wood, 1, "drop")
ISTimedActionQueue.addToQueue(queue, noPoseBridge)
assert(getmetatable(noPoseBridge) == ISUnequipAction)
toolkitWoodCartDropPose = dropPose
assert(ISUnequipAction.complete == w.nativeUnequipComplete, "scoped completion mutated ordinary unequip")
print("PASS wooden placement forwards the stored pose, runs native complete once for prepared/unprepared scopes and clears its scope after success or error")

p.primary, p.secondary = nil, nil
local walk = ISCartPickupAction.FromWorldItem(p, world)
assert(getmetatable(walk) == ISWalkToTimedActionF and #w.added == 0)
assert(walk.toolkitWoodCartItem == wood, "cart approach lost the exact pending item")
assert(ISWalkToTimedActionF:new(p, walk.location).toolkitWoodCartItem == nil, "ordinary approach inherited a cart owner")
assert(walk.location:x() == 1.3 and walk.location:y() == 2.2 and walk.location:z() == 0)
walk:stop(); assert(#w.added == 0, "cancelled approach enqueued a pickup")
local replaced = ISCartPickupAction.FromWorldItem(p, world)
w.worldFor(w.item(nil, 123)); replaced:perform()
assert(#w.added == 0, "same-ID replacement world object was accepted after approach")
w.world = world
local missing = ISCartPickupAction.FromWorldItem(p, world)
w.world = nil; missing:perform(); assert(#w.added == 0)
w.world = world
local orderedWalk = ISCartPickupAction.FromWorldItem(p, world)
local nextCommand = {Type = "AnotherQueuedCommand"}
w.queue = {orderedWalk, nextCommand}; p.distance = 0; orderedWalk:perform()
assert(w.startedNext == w.added[1] and w.queue[1] == w.added[1] and w.queue[2] == nextCommand,
    "pickup must run before commands already queued after the approach")
w.queue = nil
assert(#w.added == 1 and w.added[1].itemId == 123 and getmetatable(w.added[1]) == ToolkitWoodCartPickup)
p.distance = .09
assert(getmetatable(ISCartPickupAction.FromWorldItem(p, world)) == ISWalkToTimedActionF, "old stance skipped the small step behind the handles")
p.distance = .02
assert(getmetatable(ISCartPickupAction.FromWorldItem(p, world)) == ISWalkToTimedActionF, "nearby off-center pickup skipped alignment")
p.distance = .001
assert(getmetatable(ISCartPickupAction.FromWorldItem(p, world)) == ToolkitWoodCartPickup, "already-positioned pickup queued another walk")
p.distance = 1; p.instant = true
assert(getmetatable(ISCartPickupAction.FromWorldItem(p, world)) == ISCartPickupAction, "instant pickup queued an approach")
p.instant = false
p.distance = 1; w.worldFor(steel)
assert(getmetatable(ISCartPickupAction.FromWorldItem(p, steel.world)) == ISCartPickupAction)
-- Other cart types still need the ordinary approach that their upstream callback omits.
for _, kind in ipairs({"SaucedCarts.ShoppingCart", "SaucedWheelbarrow.WheelbarrowMetal"}) do
    local cart = w.item(kind, 125); w.worldFor(cart)
    local stanceBridge = toolkitWoodCartStance; toolkitWoodCartStance = nil
    w.reachable = false
    local destination = {getX=function() return 0 end,getY=function() return 2 end,getZ=function() return 0 end}
    AdjacentFreeTileFinder = {Find=function(square, character)
        assert(square == cart.world:getSquare() and character == p)
        return not w.noAdjacent and destination or nil
    end}
    local approach = ISCartPickupAction.FromWorldItem(p, cart.world)
    assert(getmetatable(approach) == ISWalkToTimedActionF, kind .. " distant pickup omitted approach")
    assert(approach.location:x() == .5 and approach.location:y() == 2.5 and approach.location:z() == 0)
    local added = #w.added
    approach:stop(); assert(#w.added == added, "cancelled cart approach queued a pickup")
    local vanished = ISCartPickupAction.FromWorldItem(p, cart.world)
    local originalWorld = cart.world; w.world = nil
    vanished:perform(); assert(#w.added == added, "missing cart was picked up after approach")
    w.world = originalWorld
    local success = ISCartPickupAction.FromWorldItem(p, cart.world)
    w.reachable = true; success:perform()
    assert(#w.added == added + 1 and w.added[#w.added].itemId == 125
        and getmetatable(w.added[#w.added]) == ISCartPickupAction, "ordinary cart inherited wooden action")
    assert(getmetatable(ISCartPickupAction.FromWorldItem(p, cart.world)) == ISCartPickupAction,
        "reachable cart queued an unnecessary approach")
    w.reachable = false; w.noAdjacent = true
    assert(getmetatable(ISCartPickupAction.FromWorldItem(p, cart.world)) == ISCartPickupAction,
        "unreachable cart invented a path")
    w.noAdjacent = nil; w.reachable = nil; toolkitWoodCartStance = stanceBridge
end
w.worldFor(steel)
print("PASS shopping and metal cart approach uses native reachability, exact target, cancellation and unchanged pickup actions")
local beforeEnd = w.ended
w.events.OnPlayerUpdate(p)
assert(w.ticked == p, "presentation recovery tick lost its exact player")
toolkitWoodCartTick = nil
w.events.OnPlayerUpdate(p)
w.events.OnPlayerDeath(p)
assert(w.ended == beforeEnd + 1 and w.endedCharacter == p)
w.events.OnMainMenuEnter()
assert(w.ended == beforeEnd + 2 and not w.endedCharacter)
local originalStance = toolkitWoodCartStance
toolkitWoodCartStance = function() return nil end
assert(getmetatable(ISCartPickupAction:new(p, 1, 2, 0, 123)) == ISCartPickupAction, "unsafe stance promoted a pickup")
toolkitWoodCartStance = originalStance
toolkitWoodCartStance, toolkitWoodCartUpdate = nil, nil
w.world = world
assert(getmetatable(ISCartPickupAction.FromWorldItem(p, world)) == ISCartPickupAction)
p.primary, p.secondary = wood, wood
local fallback = ISUnequipAction:new(p, wood, 1, "drop"); ISTimedActionQueue.addToQueue(queue, fallback)
assert(getmetatable(fallback) == ISUnequipAction)
w = setup(false, true, true)
local missing = setmetatable({character=w.p, squareX=1, itemId=-1}, ToolkitWoodCartPickup)
missing:start()
assert(missing.stringOverride and missing.override == nil, "missing pickup target should clear the model override safely")
missing:stop()

for _, pickupAction in ipairs({true, false}) do
    for _, outcome in ipairs({"accepted", "refused", "missing", "error"}) do
        local state = setup(false, true, true)
        local player, item = state.p, state.item()
        state.worldFor(item)
        if not pickupAction then player.primary, player.secondary = item, item end
        local action
        if pickupAction then
            action = ISCartPickupAction:new(player, 1, 2, 0, 123)
        else
            action = ISUnequipAction:new(player, item, 1, "drop")
            ISTimedActionQueue.addToQueue({}, action)
        end
        action.action = {}
        action:start()
        local owner = pickupAction and ISCartPickupAction or ISUnequipAction
        local order, sourceError = {}, {}
        local nativeStop = owner.stop
        owner.stop = function(self)
            assert(self == action and self.toolkitPresentation, "native stop lost its owned action")
            order[#order + 1] = "stop"
            if pickupAction then item.world, state.world = nil, nil end
            if outcome == "error" then error(sourceError) end
            return "native stopped"
        end
        if outcome ~= "missing" then
            toolkitWoodCartCancel = function(character, cart, pickup, stoppingAction)
                assert(character == player and cart == item and pickup == pickupAction and stoppingAction == action.action,
                    "recovery lost the exact player, pre-stop item, direction or native action")
                assert(table.concat(order, ",") == "stop", "recovery preceded or repeated native stop")
                order[#order + 1] = "cancel"
                return outcome == "accepted"
            end
        end
        local ended = toolkitWoodCartEnd
        toolkitWoodCartEnd = function(character)
            order[#order + 1] = "end"
            ended(character)
        end
        local visualCalls = 0
        ToolkitCartRefreshVisual = function(character, stoppingAction, stopped)
            assert(not pickupAction and character == player and stoppingAction == action.action and stopped == true,
                "stopped setdown lost its exact visual handoff")
            assert(not action.toolkitPresentation and not player.vars.ToolkitWoodCartAction and not player.vars.ToolkitWoodCartProgress,
                "visual refresh preceded Lua presentation retirement")
            order[#order + 1] = "visual"
            visualCalls = visualCalls + 1
        end
        local completed, performed = player.completeCalls, action.performed
        local ok, result = pcall(action.stop, action)
        assert(not action.toolkitPresentation and not player.vars.ToolkitWoodCartAction and not player.vars.ToolkitWoodCartProgress,
            "stop retained Lua presentation ownership")
        assert(player.completeCalls == completed and action.performed == performed, "stop performed an ownership transfer")
        if outcome == "error" then
            assert(not ok and result == sourceError and table.concat(order, ",") == "stop,end" and visualCalls == 0,
                "native stop error changed identity, started recovery or skipped immediate cleanup")
        else
            local expected = outcome == "accepted" and "stop,cancel" or outcome == "refused" and "stop,cancel,end" or "stop,end"
            if not pickupAction then expected = expected .. ",visual" end
            assert(ok and result == "native stopped" and table.concat(order, ",") == expected,
                "stop order, fallback or native result changed: " .. outcome)
            assert(state.ended == (outcome == "accepted" and 0 or 1), "recovery ended the accepted state or leaked a refused state")
        end
        local before = #order
        action:forceCancel()
        assert(#order == before, "forceCancel repeated retired presentation cleanup")
        owner.stop = nativeStop
    end
end
print("PASS wooden cancellation follows one native stop, preserves exact identities/results/errors, retires Lua ownership and falls back without recovery")

for _, pickupAction in ipairs({true, false}) do
    local state = setup(false, true, true)
    local item, player = state.item(), state.p
    state.worldFor(item)
    player.primary, player.secondary = item, item
    local class = pickupAction and ToolkitWoodCartPickup or ToolkitWoodCartSetdown
    local action = setmetatable({character = player, item = item, itemId = 123, squareX = 1, reason = "drop"}, class)
    local cancels = 0
    toolkitWoodCartCancel = function() cancels = cancels + 1; return true end
    action:start()
    local waiting = setmetatable({character = player}, class)
    waiting:forceCancel()
    assert(action.toolkitPresentation and player.vars.ToolkitWoodCartAction and state.ended == 0 and cancels == 0,
        "waiting forceCancel touched the current presentation")
    action:forceCancel()
    assert(not action.toolkitPresentation and not player.vars.ToolkitWoodCartAction and state.ended == 1 and cancels == 0,
        "forceCancel started recovery instead of immediate owned cleanup")
end
require = originalRequire
print("PASS wooden approach preserves exact world identity, skips disappeared/replaced targets, does not queue after cancellation and falls back safely without bridge helpers")

local server = setup(true, true, true)
local serverCart = server.item(); server.worldFor(serverCart)
toolkitWoodCartStance = function() error("server must not load render models for pickup") end
local serverPickup = ToolkitWoodCartPickup:new(server.p, 1, 2, 0, 123)
assert(getmetatable(serverPickup) == ToolkitWoodCartPickup and serverPickup.maxTime == 88
    and serverPickup.itemId == 123 and serverPickup.squareX == 1,
    "server reconstruction changed the client action class, duration or identity")
require = originalRequire
print("PASS server pickup reconstructs the authored action without probing client render models")

-- Native08: engine clips a vehicle-obstructed requested X=10822.4541015625 to X=10822.4599609375.
-- A successful native walk must still check the current original handle stance before queuing pickup.
for _, outcome in ipairs({"native-clipped", "exact", "target-moved", "different-floor"}) do
    local state=setup(false,true,true)
    local cart,player=state.item(),state.p;local target=state.worldFor(cart)
    local goalX,goalY=10822.4541015625,10142.5
    toolkitWoodCartStance=function() return {x=goalX,y=goalY,faceX=goalX+1,faceY=goalY,aligned=true} end
    function player:DistToSquared(x,y) return (self.x-x)^2+(self.y-y)^2 end
    player.x,player.y=goalX+1,goalY
    local approach=ISCartPickupAction.FromWorldItem(player,target)
    assert(approach.Type=="ISWalkToTimedActionF")
    player.x=outcome=="native-clipped" and 10822.4599609375 or goalX
    if outcome=="target-moved" then goalX=goalX+.05 end
    if outcome=="different-floor" then player.z=1 end
    approach.result="Succeeded"
    local independent={Type="AnotherQueuedCommand"};state.queue={approach,independent}
    approach:perform()
    if outcome=="exact" then
        assert(#state.added==1 and state.added[1].itemId==cart:getID()
            and state.queue[1]==state.added[1] and state.queue[2]==independent,
            "exact original stance lost its pickup or independent tail")
    else
        assert(#state.added==0 and state.startedNext==independent and state.queue[1]==independent,
            "clipped/moved/different-floor stance queued an off-center pickup or consumed the independent tail")
        assert(approach.performed==1 and cart:getWorldItem()==target and player.primary==nil and player.secondary==nil,
            "denied pickup changed native completion, cart ownership or hands")
    end
end
require=originalRequire
print("PASS native clipped target cannot queue off-center pickup; exact current stance keeps pickup and independent tail")
