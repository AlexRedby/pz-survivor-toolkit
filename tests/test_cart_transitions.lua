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
    for _, event in ipairs({"OnPlayerDeath", "OnMainMenuEnter"}) do
        Events[event] = {Add = function(fn) w.events[event] = fn end}
    end
    getTimestampMs = function() return 100 end
    getText = function(key) return key end
    Metabolics = {HeavyDomestic = "heavy"}
    ItemTag = {WEARABLE = "wearable"}
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
    ISUnequipAction = ISBaseTimedAction:derive("ISUnequipAction")
    function ISUnequipAction:new(character, item, duration, reason)
        return setmetatable({character = character, item = item, maxTime = duration, reason = reason,
            stopOnWalk = false, stopOnRun = true, stopOnAim = false}, self)
    end
    function ISUnequipAction:start() self.nativeStarted = true end
    function ISUnequipAction:update() self.item:setJobDelta(self:getJobDelta()) end
    function ISUnequipAction:complete() self.character:removeWornItem(self.item); return self.character.completeResult ~= false end
    if SaucedCartsSource then dofile(SaucedCartsSource .. "/TimedActions/ISCartPickupAction.lua") end
    if NativeActionRoot then dofile(NativeActionRoot .. "/shared/TimedActions/ISUnequipAction.lua") end
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
    ToolkitWoodCartPickup, ToolkitWoodCartSetdown = nil, nil
    w.unequipFingerprint = {}; for key, value in pairs(ISUnequipAction) do w.unequipFingerprint[key] = value end
    local transitions = dofile(shared)
    require = function(name) return name == "ToolkitWoodCartActions" and transitions or true end
    dofile(client)
    local p = {vars = {}, inventory = {}}
    function p:isTimedActionInstant() return self.instant end
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
    function p:getInventory() return {getItemById = function(_, id) return self.inventory[id] end,
        contains = function(_, item) return self.inventory[item:getID()] == item end} end
    function p:setVariable(name, value) self.vars[name] = value end
    function p:clearVariable(name) self.vars[name] = nil end
    function p:faceLocationF(x, y) self.faceX, self.faceY = x, y end
    function p:shouldBeTurning() return self.turning end
    function p:setMetabolicTarget(value) self.metabolic = value end
    function p:DistTo() return self.distance or 1 end
    function p:getPlayerNum() return 0 end
    function p:isHandItem(item) return self.primary == item or self.secondary == item end
    function p:getPathFindBehavior2() return {cancel = function() end} end
    function p:setPath2() end
    function p:getSquare() return {canReachTo = function() return true end} end
    function w.item(kind, id)
        local item = {kind = kind or "SaucedWheelbarrow.WheelbarrowWood", id = id or 123, cart = true}
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
        function item:hasTag() return false end
        return item
    end
    w.square = {getX = function() return 1 end, getY = function() return 2 end, getZ = function() return 0 end}
    function w.square:getWorldObjects() return {size = function() return w.world and 1 or 0 end, get = function() return w.world end} end
    getCell = function() return {getGridSquare = function(_, x, y, z) return x == 1 and y == 2 and z == 0 and w.square or nil end} end
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
local release = setmetatable({character=p, item=wood}, ToolkitWoodCartSetdown)
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
for _, reason in ipairs({"drop", "place"}) do
    local action = ISUnequipAction:new(p, wood, 1, reason)
    assert(ISTimedActionQueue.addToQueue(queue, action) == "queued" and queue.last == action)
    assert(getmetatable(action) == ToolkitWoodCartSetdown and action.maxTime == 88)
    assert(action.stopOnWalk and action.stopOnRun and action.stopOnAim)
    assert(action.toolkitDropX == 1.25 and action.toolkitDropY == 2.75 and action.toolkitDropZ == 0 and action.toolkitDropRotation == 90)
    action:start(); action:update(); assert(p.vars.ToolkitWoodCartAction and wood.delta == .4)
    local waiting = ISUnequipAction:new(p, wood, 1, reason)
    ISTimedActionQueue.addToQueue(queue, waiting); waiting:forceCancel()
    assert(p.vars.ToolkitWoodCartAction, "queued setdown cancellation cleared another action presentation")
    action:forceCancel(); assert(not p.vars.ToolkitWoodCartAction and not p.vars.ToolkitWoodCartProgress)
    action:start(); action:stop(); assert(action.stopped and not p.vars.ToolkitWoodCartAction)
    action:start(); action:perform(); assert(action.performed == 1 and not p.vars.ToolkitWoodCartAction)
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
print("PASS wooden setdown dispatch is limited to exact native drop/place actions holding wood in both hands; duration, flags and ordinary class fingerprints are preserved")

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
w.queue = {orderedWalk, nextCommand}; orderedWalk:perform()
assert(w.startedNext == w.added[1] and w.queue[1] == w.added[1] and w.queue[2] == nextCommand,
    "pickup must run before commands already queued after the approach")
w.queue = nil
assert(#w.added == 1 and w.added[1].itemId == 123 and getmetatable(w.added[1]) == ToolkitWoodCartPickup)
p.distance = .09
assert(getmetatable(ISCartPickupAction.FromWorldItem(p, world)) == ISWalkToTimedActionF, "old stance skipped the small step behind the handles")
p.distance = .04
assert(getmetatable(ISCartPickupAction.FromWorldItem(p, world)) == ToolkitWoodCartPickup, "already-positioned pickup queued another walk")
p.distance = 1; p.instant = true
assert(getmetatable(ISCartPickupAction.FromWorldItem(p, world)) == ISCartPickupAction, "instant pickup queued an approach")
p.instant = false
p.distance = 1; w.worldFor(steel)
assert(getmetatable(ISCartPickupAction.FromWorldItem(p, steel.world)) == ISCartPickupAction)
local beforeEnd = w.ended
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
require = originalRequire
print("PASS wooden approach preserves exact world identity, skips disappeared/replaced targets, does not queue after cancellation and falls back safely without bridge helpers")
