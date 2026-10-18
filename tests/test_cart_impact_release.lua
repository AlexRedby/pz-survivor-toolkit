local source = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/ZZToolkitWoodCartImpact.lua"
local originalRequire = require
local function state(name)
    return {getName = function() return name end}
end
local collide, getup, idle = state("CollideWithWallState"), state("PlayerGetUpState"), state("IdleState")

local function setup(options)
    options = options or {}
    local w = {calls = 0, begins = 0, ends = 0, requests = {}, world = {}, events = {}, now = 100,
        removes = 0, spills = 0, queue = {"native-action"}}
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
        w.calls = w.calls + 1;w.calledPlayer = player;w.calledCart = item
        if w.handleError then error(w.handleError) end
        return handle(player, item)
    end
    toolkitWoodCartDropPose = function()
        if w.poseError then error("pose-unavailable") end
        if w.noPose then return nil end
        return {x = 10.25, y = 20.75, z = 0, rotation = 90}
    end
    toolkitWoodCartDropBegin = function(player, item, x, y, z, rotation)
        assert(x == 10.25 and y == 20.75 and z == 0 and rotation == 90)
        w.begins = w.begins + 1;w.scope = true
        if w.beginError then error("begin-failed") end
        return not w.beginRefused
    end
    toolkitWoodCartDropEnd = function()
        w.ends = w.ends + 1;w.scope = false
        if w.endError then error("cleanup-failed") end
    end
    Events = {OnAIStateChange = {Add = function(handler) w.handler = handler end}}
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
    assert(w.calls == 0 and w.begins == 0 and w.ends == 0, "unsafe release: " .. invalid)
end

for _, failure in ipairs({"noPose", "poseError", "beginError", "beginRefused", "noBridge"}) do
    w = setup();p = w.player();cart = p:equip();w[failure] = true
    if failure == "noBridge" then toolkitWoodCartDropPose, toolkitWoodCartDropBegin, toolkitWoodCartDropEnd = nil, nil, nil end
    w.fire(p, collide)
    assert(w.calls == 1 and w.calledCart == cart and not w.scope, "presentation failure blocked release: " .. failure)
    assert(w.ends == (failure == "noBridge" and 0 or 1), "presentation scope leaked: " .. failure)
end

w = setup();p = w.player();p:equip();w.handleError = "upstream-failed"
local ok, err = pcall(w.fire, p, collide)
assert(not ok and tostring(err):find("upstream-failed", 1, true) and w.ends == 1 and not w.scope,
    "upstream error was hidden or placement scope leaked")
w.fire(p, collide);assert(w.calls == 1, "failed endpoint retried within the same impact episode")
w = setup();p = w.player();p:equip();w.endError = true
ok, err = pcall(w.fire, p, collide)
assert(not ok and tostring(err):find("cleanup-failed", 1, true), "cleanup failure was hidden")
w = setup();p = w.player();p:equip();w.handleError = "upstream-failed";w.endError = true
ok, err = pcall(w.fire, p, collide)
assert(not ok and tostring(err):find("upstream-failed", 1, true) and not tostring(err):find("cleanup-failed", 1, true),
    "cleanup failure replaced the original upstream error")

w = setup({client = true});p = w.player();cart = p:equip();w.fire(p, collide)
assert(w.calls == 1 and w.begins == 0 and w.ends == 0 and p.handWrites == 0
    and p.primary == cart and p.secondary == cart and #w.world == 0 and w.removes == 0,
    "MP release performed optimistic local ownership changes or SP placement")
print("PASS impact release: exact native-state event, ownership guards, one release per protected episode, fallback and error cleanup")

if SaucedCartsSource then
    for _, broken in ipairs({false, true}) do
        w = setup({native = true});p = w.player();cart = p:equip();local cargo = cart.cargo
        if broken then cart.condition = 0 end
        w.fire(p, collide);w.fire(p, collide);w.fire(p, getup)
        assert(w.calls == 1 and not p.primary and not p.secondary and not p.inventory:contains(cart)
            and w.removes == 1 and w.ends == 1 and not w.scope and #w.queue == 1)
        if broken then
            assert(w.spills == 1 and w.spilledCart == cart and w.spilledCargo == cargo and #w.world == 0
                and w.events[1][1] == "broke", "installed broken-cart branch lost its content delegation")
        else
            assert(#w.world == 1 and w.world[1].item == cart and cart.cargo == cargo
                and cart.world == w.world[1] and cart.world.persistent and w.events[1][1] == "drop",
                "installed SP endpoint did not preserve the exact cart/cargo/world identity")
        end
    end
    for _, fallback in ipairs({"noPose", "poseError", "beginError", "beginRefused"}) do
        w = setup({native = true});p = w.player();cart = p:equip();w[fallback] = true
        w.fire(p, collide)
        assert(#w.world == 1 and w.world[1].item == cart and not p.primary and not p.secondary
            and not p.inventory:contains(cart) and w.ends == 1 and not w.scope,
            "installed SP fallback did not release the exact cart: " .. fallback)
    end
    w = setup({native = true, client = true});p = w.player();cart = p:equip()
    w.fire(p, collide)
    assert(#w.requests == 1 and w.requests[1].player == p and w.requests[1].command == "requestInstantDrop"
        and w.requests[1].args.cartId == cart:getID() and p.poseCleared and w.drop.isPending(p))
    w.now = w.now + 5000;assert(not w.drop.isPending(p));w.fire(p, getup);w.fire(p, collide)
    assert(#w.requests == 1 and w.calls == 1 and p.primary == cart and p.secondary == cart
        and p.inventory:contains(cart) and p.handWrites == 0 and #w.world == 0 and w.removes == 0,
        "installed MP endpoint retried after pending timeout or mutated local authority")
    print("PASS installed InstantDrop: healthy cart/cargo exact identity, broken delegation, persistent world drop and MP authoritative request without local mutation")
else
    print("SKIP installed InstantDrop integration: SaucedCartsSource not supplied")
end
require = originalRequire
