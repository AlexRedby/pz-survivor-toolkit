local source = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/ZZToolkitWoodCartImpact.lua"
local originalRequire = require
local function state(name)
    return {getName = function() return name end}
end
local collide, getup, idle = state("CollideWithWallState"), state("PlayerGetUpState"), state("IdleState")

local function setup(options)
    options = options or {}
    local w = {calls = 0, begins = 0, ends = 0, requests = {}, world = {}, events = {}, now = 100,
        removes = 0, spills = 0, queue = {"native-action"}, trace = {}, captures = 0, poses = 0, finishes = 0, ticks = 0}
    local function trace(name) w.trace[#w.trace + 1] = name end
    isServer = function() return options.server == true end
    isClient = function() return options.client == true end
    getActivatedMods = function() return {contains = function(_, name) return options.disabled ~= true and name == "SaucedCarts" end} end
    instanceof = function(value, name) return value and value.player == true and name == "IsoPlayer" end
    getTimestampMs = function() return w.now end
    ISTimedActionQueue = {clear = function() error("impact release must not clear the native queue") end}
    ISInventoryPage = {renderDirty = false}
    sendRemoveItemFromContainer = function()
        assert(not options.client, "client must not mutate authoritative inventory")
        w.removes = w.removes + 1
    end
    SaucedCarts = {debug = function() end, Events = {onCartDrop = "drop", onCartBroke = "broke"},
        resolveCartDropSquare = function(square) return square end,
        updateCartVisual = function() end,
        markDropPersistent = function(item) if item and item.world then item.world.persistent = true end end,
        clearCartPose = function(player) player.poseCleared = true end,
        _fireEvent = function(event, player, item, square) w.events[#w.events + 1] = {event, player, item, square} end,
        Durability = {applyAccumulatedDamage = function(item) return item.condition end,
            dropContentsAndDestroy = function(item, player, square)
                w.spills = w.spills + 1;w.spilledCart = item;w.spilledCargo = item.cargo
            end}}
    require = function(name)
        if name == "SaucedCarts/CartState/InstantDrop" then return w.drop end
        assert(name == "SaucedCarts/Core" or name == "SaucedCarts/Durability" or name == "SaucedCarts/Network")
    end
    SaucedCarts.Network = {sendToServer = function(player, command, args)
        w.requests[#w.requests + 1] = {player = player, command = command, args = args}
    end}
    if options.native then
        assert(SaucedCartsSource, "Supply SaucedCartsSource for installed InstantDrop integration")
        w.drop = dofile(SaucedCartsSource .. "/../../client/SaucedCarts/CartState/InstantDrop.lua")
    else
        w.drop = {handle = function() return true end}
    end
    local handle = w.drop.handle
    w.drop.handle = function(player, item)
        trace("handle")
        w.calls = w.calls + 1;w.calledPlayer = player;w.calledCart = item
        if w.handleError then error(w.handleError) end
        return handle(player, item)
    end
    toolkitWoodCartDropPose = function()
        trace("pose");w.poses = w.poses + 1
        if w.poseError then error("pose-unavailable") end
        if w.noPose then return nil end
        return {x = 10.25, y = 20.75, z = 0, rotation = 90}
    end
    toolkitWoodCartImpactPose = function(player, item)
        trace("capture");w.captures = w.captures + 1
        assert(player:getPrimaryHandItem() == item and player:getInventory():contains(item),
            "actual held pose was captured after ownership changed")
        if w.impactError then error("capture-failed") end
        -- Java rejects stale snapshots by returning nil, just like an absent snapshot.
        if w.noImpactPose or w.staleImpactPose then return nil end
        return {x = 10.625, y = 20.875, z = 0, rotation = 135}
    end
    toolkitWoodCartDropBegin = function(player, item, x, y, z, rotation)
        trace("begin")
        w.beginPose = {x = x, y = y, z = z, rotation = rotation}
        w.begins = w.begins + 1;w.scope = true
        if w.beginError then error("begin-failed") end
        return not w.beginRefused
    end
    toolkitWoodCartDropEnd = function()
        trace("end")
        w.ends = w.ends + 1;w.scope = false
        if w.endError then error("cleanup-failed") end
    end
    toolkitWoodCartImpactFinish = function(player, item)
        trace("finish");w.finishes = w.finishes + 1
        w.finishedPlayer, w.finishedCart, w.finishedWorld = player, item, item:getWorldItem()
        assert(not w.scope and w.calledPlayer == player and w.calledCart == item,
            "settle finished before upstream drop and scope cleanup")
        if w.finishError then error("settle-failed") end
    end
    toolkitWoodCartImpactTick = function()
        w.ticks = w.ticks + 1
        if w.tickError then error("tick-failed") end
    end
    Events = {OnAIStateChange = {Add = function(handler) w.handler = handler end},
        OnTick = {Add = function(handler) w.tick = handler end}}
    function w.player()
        local p = {player = true, localPlayer = true, state = idle, inventory = {}, handWrites = 0}
        p.inventory.items = {}
        function p.inventory:contains(item) return self.items[item] == true end
        function p.inventory:Remove(item)
            assert(not options.client, "client removed an inventory item")
            self.items[item] = nil;item.owner = nil
        end
        p.square = {}
        function p.square:AddWorldInventoryItem(item, x, y, z, transmit)
            assert(not options.client and x == .25 and y == .75 and z == 0 and transmit == true)
            if w.worldError then error("world-add-failed") end
            item.world = {item = item, square = self};w.world[#w.world + 1] = item.world
            return item
        end
        function p:getCurrentState() return self.state end
        function p:getCurrentStateName() return self.state and self.state:getName() end
        function p:isLocalPlayer() return self.localPlayer end
        function p:isNpc() return self.npc == true end
        function p:isDead() return self.dead == true end
        function p:getPrimaryHandItem() return self.primary end
        function p:getSecondaryHandItem() return self.secondary end
        function p:getInventory() return self.inventory end
        function p:getCurrentSquare() return self.square end
        function p:getX() return 10.25 end
        function p:getY() return 20.75 end
        function p:getOnlineID() return options.client and 17 or nil end
        function p:getPlayerNum() return 0 end
        function p:setPrimaryHandItem(item) self.handWrites = self.handWrites + 1;self.primary = item end
        function p:setSecondaryHandItem(item) self.handWrites = self.handWrites + 1;self.secondary = item end
        function p:equip(kind)
            local item = {kind = kind or "SaucedWheelbarrow.WheelbarrowWood", owner = self.inventory,
                condition = 100, cargo = {{id = 71}, {id = 72}}, md = {SaucedCarts_distancePushed = 0}}
            function item:getFullType() return self.kind end
            function item:getContainer() return self.owner end
            function item:getWorldItem() return self.world end
            function item:getID() return 123 end
            function item:getModData() return self.md end
            self.inventory.items[item] = true;self.primary, self.secondary = item, item
            return item
        end
        return p
    end
    function w.fire(player, nextState)
        local previous = player.state;player.state = nextState
        w.handler(player, nextState, previous)
    end
    dofile(source)
    return w
end

for _, options in ipairs({{server = true}, {disabled = true}}) do
    assert(not setup(options).handler, "disabled impact handler registered")
end
assert(setup({server = true, client = true}).handler, "host client impact release disabled")

local w = setup();local p = w.player();local cart = p:equip()
w.fire(p, collide)
assert(w.calls == 1 and w.calledPlayer == p and w.calledCart == cart and w.begins == 1 and w.ends == 1 and not w.scope)
assert(table.concat(w.trace, ",") == "capture,begin,handle,end,finish" and w.poses == 0
    and w.beginPose.x == 10.625 and w.beginPose.y == 20.875 and w.beginPose.rotation == 135,
    "fresh actual held placement did not take precedence before native release")
assert(p.primary == cart and p.secondary == cart and #w.world == 0 and w.removes == 0,
    "feature must delegate ownership changes to the existing instant-drop endpoint")
w.fire(p, collide);w.fire(p, getup)
local replacement = p:equip()
w.now = w.now + 5000;w.fire(p, collide)
assert(w.calls == 1, "duplicate protected episode dropped a replacement cart")
w.fire(p, idle);w.fire(p, collide)
assert(w.calls == 2 and w.calledCart == replacement, "new impact episode did not release the new cart")

for _, invalid in ipairs({"remote", "npc", "dead", "one-hand", "wrong-kind", "world", "nested", "missing-root", "no-square", "no-cart", "not-player", "stale-state"}) do
    w = setup();p = w.player();cart = p:equip()
    if invalid == "remote" then p.localPlayer = false
    elseif invalid == "npc" then p.npc = true
    elseif invalid == "dead" then p.dead = true
    elseif invalid == "one-hand" then p.secondary = nil
    elseif invalid == "wrong-kind" then cart.kind = "SaucedWheelbarrow.WheelbarrowMetal"
    elseif invalid == "world" then cart.world = {}
    elseif invalid == "nested" then cart.owner = {}
    elseif invalid == "missing-root" then p.inventory.items[cart] = nil
    elseif invalid == "no-square" then p.square = nil
    elseif invalid == "no-cart" then p.primary, p.secondary = nil, nil
    elseif invalid == "not-player" then p.player = false
    end
    if invalid == "stale-state" then w.handler(p, collide, idle) else w.fire(p, collide) end
    assert(w.calls == 0 and w.begins == 0 and w.ends == 0 and w.captures == 0 and w.finishes == 0,
        "unsafe release: " .. invalid)
end

for _, failure in ipairs({"missing", "noImpactPose", "staleImpactPose", "impactError"}) do
    w = setup();p = w.player();cart = p:equip();w[failure] = true
    if failure == "missing" then toolkitWoodCartImpactPose = nil end
    w.fire(p, collide)
    assert(w.calls == 1 and w.poses == 1 and w.begins == 1 and w.finishes == 1
        and w.beginPose.x == 10.25 and w.beginPose.y == 20.75 and w.beginPose.rotation == 90,
        "unavailable actual held pose did not fall back to established placement: " .. failure)
    assert(table.concat(w.trace, ",") == (failure == "missing" and "pose,begin,handle,end,finish"
        or "capture,pose,begin,handle,end,finish"), "fallback call order changed: " .. failure)
end

w = setup();p = w.player();cart = p:equip();toolkitWoodCartDropPose = nil
w.fire(p, collide)
assert(w.calls == 1 and w.captures == 1 and w.begins == 1 and w.ends == 1 and w.finishes == 1,
    "actual held placement unnecessarily required the fallback pose API")

for _, failure in ipairs({"noPose", "poseError", "beginError", "beginRefused", "noBridge"}) do
    w = setup();p = w.player();cart = p:equip();w[failure] = true;w.noImpactPose = true
    if failure == "noBridge" then toolkitWoodCartDropPose, toolkitWoodCartDropBegin, toolkitWoodCartDropEnd = nil, nil, nil end
    w.fire(p, collide)
    assert(w.calls == 1 and w.calledCart == cart and not w.scope and w.finishes == 1,
        "presentation failure blocked release: " .. failure)
    assert(w.ends == (failure == "noBridge" and 0 or 1), "presentation scope leaked: " .. failure)
end

w = setup();p = w.player();p:equip();w.handleError = "upstream-failed"
local ok, err = pcall(w.fire, p, collide)
assert(not ok and tostring(err):find("upstream-failed", 1, true) and w.ends == 1 and not w.scope,
    "upstream error was hidden or placement scope leaked")
assert(w.finishes == 1 and table.concat(w.trace, ",") == "capture,begin,handle,end,finish",
    "failed upstream did not clear its presentation candidate after scope cleanup")
w.fire(p, collide);assert(w.calls == 1, "failed endpoint retried within the same impact episode")
w = setup();p = w.player();p:equip();w.endError = true
ok, err = pcall(w.fire, p, collide)
assert(not ok and tostring(err):find("cleanup-failed", 1, true), "cleanup failure was hidden")
assert(w.finishes == 1, "cleanup error skipped candidate cleanup")
w = setup();p = w.player();p:equip();w.handleError = "upstream-failed";w.endError = true
ok, err = pcall(w.fire, p, collide)
assert(not ok and tostring(err):find("upstream-failed", 1, true) and not tostring(err):find("cleanup-failed", 1, true),
    "cleanup failure replaced the original upstream error")

for _, failure in ipairs({"finishError", "missingFinish"}) do
    w = setup();p = w.player();cart = p:equip();w[failure] = true
    if failure == "missingFinish" then toolkitWoodCartImpactFinish = nil end
    w.fire(p, collide)
    assert(w.calls == 1 and w.ends == 1 and not w.scope, "settle failure blocked release: " .. failure)
end
w = setup();p = w.player();p:equip();w.handleError = "upstream-failed";w.finishError = true
ok, err = pcall(w.fire, p, collide)
assert(not ok and tostring(err):find("upstream-failed", 1, true) and w.finishes == 1,
    "settle error replaced upstream error")
w = setup();p = w.player();p:equip();w.endError = true;w.finishError = true
ok, err = pcall(w.fire, p, collide)
assert(not ok and tostring(err):find("cleanup-failed", 1, true) and w.finishes == 1,
    "settle error replaced scope cleanup error")

w = setup();w.tick();w.tickError = true;w.tick();toolkitWoodCartImpactTick = nil;w.tick()
assert(w.ticks == 2, "missing or failed presentation tick was not tolerated")
for _, options in ipairs({{client = true}, {server = true, client = true}}) do
    w = setup(options);p = w.player();cart = p:equip();w.fire(p, collide);w.tick()
    assert(w.calls == 1 and w.begins == 0 and w.ends == 0 and w.captures == 0 and w.poses == 0
        and w.finishes == 0 and w.ticks == 0 and p.handWrites == 0
        and p.primary == cart and p.secondary == cart and #w.world == 0 and w.removes == 0,
        "MP release performed optimistic local ownership changes or SP presentation")
end
print("PASS impact release: exact native-state event, ownership guards, one release per protected episode, fallback and error cleanup")

if SaucedCartsSource then
    for _, broken in ipairs({false, true}) do
        w = setup({native = true});p = w.player();cart = p:equip();local cargo = cart.cargo
        if broken then cart.condition = 0 end
        w.fire(p, collide);w.fire(p, collide);w.fire(p, getup)
        assert(w.calls == 1 and not p.primary and not p.secondary and not p.inventory:contains(cart)
            and w.removes == 1 and w.ends == 1 and not w.scope and #w.queue == 1)
        assert(w.finishes == 1 and w.finishedPlayer == p and w.finishedCart == cart,
            "installed endpoint did not finish the exact source player and cart")
        if broken then
            assert(w.spills == 1 and w.spilledCart == cart and w.spilledCargo == cargo and #w.world == 0
                and not w.finishedWorld and w.events[1][1] == "broke",
                "installed broken-cart branch lost its content delegation")
        else
            assert(#w.world == 1 and w.world[1].item == cart and cart.cargo == cargo
                and cart.world == w.world[1] and w.finishedWorld == cart.world
                and cart.world.persistent and w.events[1][1] == "drop",
                "installed SP endpoint did not preserve the exact cart/cargo/world identity")
        end
    end
    for _, fallback in ipairs({"noPose", "poseError", "beginError", "beginRefused", "impactError", "finishError"}) do
        w = setup({native = true});p = w.player();cart = p:equip();w[fallback] = true;w.noImpactPose = true
        w.fire(p, collide)
        assert(#w.world == 1 and w.world[1].item == cart and not p.primary and not p.secondary
            and not p.inventory:contains(cart) and w.ends == 1 and not w.scope,
            "installed SP fallback did not release the exact cart: " .. fallback)
    end
    w = setup({native = true});p = w.player();cart = p:equip();w.worldError = true
    ok, err = pcall(w.fire, p, collide)
    assert(not ok and tostring(err):find("world-add-failed", 1, true) and w.ends == 1 and not w.scope
        and w.finishes == 1 and w.finishedCart == cart and not w.finishedWorld and #w.world == 0,
        "installed world-add error was hidden or left its presentation candidate unfinished")
    w = setup({native = true, client = true});p = w.player();cart = p:equip()
    w.fire(p, collide)
    assert(#w.requests == 1 and w.requests[1].player == p and w.requests[1].command == "requestInstantDrop"
        and w.requests[1].args.cartId == cart:getID() and p.poseCleared and w.drop.isPending(p))
    w.now = w.now + 5000;assert(not w.drop.isPending(p));w.fire(p, getup);w.fire(p, collide)
    assert(#w.requests == 1 and w.calls == 1 and p.primary == cart and p.secondary == cart
        and p.inventory:contains(cart) and p.handWrites == 0 and #w.world == 0 and w.removes == 0,
        "installed MP endpoint retried after pending timeout or mutated local authority")
    assert(w.captures == 0 and w.poses == 0 and w.finishes == 0 and w.begins == 0 and w.ends == 0,
        "installed MP endpoint used SP presentation APIs")
    print("PASS installed InstantDrop: healthy cart/cargo exact identity, broken delegation, persistent world drop and MP authoritative request without local mutation")
else
    print("SKIP installed InstantDrop integration: SaucedCartsSource not supplied")
end
require = originalRequire
