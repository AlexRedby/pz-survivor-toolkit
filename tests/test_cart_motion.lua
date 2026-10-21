local source = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/000ToolkitCartMotion.lua"
local originalRequire = require
local function setup(server, active, client)
    local w = {events = {}, dt = 1 / 60, online = {}, client = client == true, synced = {}, repaints = 0, sends = 0}
    ToolkitCartRefreshVisual = nil
    isServer = function() return server end
    isClient = function() return w.client end
    addVariableToSyncList = function(key) w.synced[key] = true end
    getActivatedMods = function() return {contains = function(_, name) return active and name == "SaucedCarts" end} end
    ISWalkToTimedAction, ISWalkToTimedActionF, ISPathFindAction = {}, {}, {}
    for _, entry in ipairs({{ISWalkToTimedAction, "ISWalkToTimedAction"},
        {ISWalkToTimedActionF, "ISWalkToTimedActionF"}, {ISPathFindAction, "ISPathFindAction"}}) do
        local class = entry[1]; class.Type = entry[2]; class.__index = class
        for _, name in ipairs({"start", "update", "stop", "perform", "isValid"}) do class[name] = function() end end
    end
    require = function(name) assert(name == "SaucedCarts/Core" or name == "TimedActions/WalkToTimedAction"
        or name == "TimedActions/WalkToTimedActionF" or name == "Vehicles/TimedActions/ISPathFindAction") end
    instanceof = function(item, kind) return kind == "InventoryContainer" and item.container == true
        or kind == "LuaTimedActionNew" and item.native == true end
    w.types = {
        ["SaucedCarts.ShoppingCart"] = {visualModels = {empty = "ShoppingCartModel", partial = "ShoppingCartPartialModel", full = "ShoppingCartFullModel"}},
        ["SaucedWheelbarrow.WheelbarrowWood"] = {visualModels = {empty = "WheelbarrowWood", partial = "WheelbarrowWood", full = "WheelbarrowWood"}},
        ["SaucedWheelbarrow.WheelbarrowMetal"] = {visualModels = {empty = "WheelbarrowMetal", partial = "WheelbarrowMetal", full = "WheelbarrowMetal"}},
    }
    local models = {}
    for _, data in pairs(w.types) do for _, model in pairs(data.visualModels) do models[model] = {} end end
    models.ShoppingCartFlashlightFullModel = {}
    getScriptManager = function() return {getModelScript = function(_, name) return models[(name:gsub("^Base%.", ""))] end} end
    sendClientCommand = function() w.sends = w.sends + 1 end
    sendServerCommand = sendClientCommand
    SaucedCarts = {
        safeIsCart = function(item) return item.cart == true end,
        getCartData = function(item) return w.types[item:getFullType()] end,
        calculateFillState = function(item, player)
            assert(player and item == player.item)
            return item.weight / item.capacity >= .66 and "full" or item.weight / item.capacity >= .33 and "partial" or "empty"
        end,
        buildCartModelName = function(item, fill)
            if item.flashlight and fill == "full" then return "ShoppingCartFlashlightFullModel" end
            return w.types[item:getFullType()].visualModels[fill]
        end,
        updateCartVisual = function(item, player, force)
            assert(force == true and player.item == item and player.secondary == item)
            w.repaints = w.repaints + 1
            item.model = SaucedCarts.buildCartModelName(item, SaucedCarts.calculateFillState(item, player))
            if isServer() then sendServerCommand() end
        end,
    }
    getGameTime = function() return {getRealworldSecondsSinceLastUpdate = function() return w.dt end} end
    getOnlinePlayers = function() return {size = function() return #w.online end, get = function(_, i) return w.online[i + 1] end} end
    Events = {}
    for _, name in ipairs({"OnPlayerUpdate", "OnPlayerDeath", "OnMainMenuEnter", "OnTick"}) do
        w.events[name] = {}
        Events[name] = {Add = function(fn) w.events[name][#w.events[name] + 1] = fn end}
    end
    function w.fire(name, ...)
        for _, fn in ipairs(w.events[name]) do fn(...) end
    end
    function w.player()
        local p = {normal = 1, running = false, sprinting = false, localPlayer = true, inventory = {}, vars = {}, actions = 0}
        function p:getPrimaryHandItem() return self.item end
        function p:getSecondaryHandItem() return self.secondary end
        function p:getInventory() return self.inventory end
        function p:isDead() return self.dead end
        function p:isAiming() return self.aim end
        function p:isSneaking() return self.sneak end
        function p:getVehicle() return self.vehicle end
        function p:isRunning() return self.running end
        function p:isSprinting() return self.sprinting end
        function p:isLocalPlayer() return self.localPlayer end
        function p:getCharacterActions()
            return {size = function() return self.actions end, get = function(_, index) assert(index == 0); return self.action end}
        end
        function p:getVariableFloat(name, default) return self.vars[name] or default end
        function p:getVariableBoolean(name) return self.vars[name] == true end
        function p:setVariable(name, value) self.vars[name] = value end
        function p:getTurnDelta() return self.sprinting and 0.75 or self.running and 0.8 or self.normal end
        function p:setTurnDelta(value) self.normal = value end
        function p:equip(weight, capacity)
            local cart = {container = true, cart = true, weight = weight or 0, capacity = capacity or 50, owner = self.inventory}
            function cart:getFullType() return self.fullType or "SaucedWheelbarrow.WheelbarrowWood" end
            function cart:getWorldItem() return self.world end
            function cart:getContainer() return self.owner end
            function cart:getStaticModel() return self.model or w.types[self:getFullType()].visualModels.empty end
            function cart:getInventory()
                return {getEffectiveCapacity = function() return self.capacity end, getCapacityWeight = function() return self.weight end}
            end
            self.item, self.secondary = cart, cart
            return cart
        end
        function p:drop() self.item, self.secondary = nil, nil end
        return p
    end
    function w.tick(p, count)
        for _ = 1, count or 1 do w.fire("OnPlayerUpdate", p) end
    end
    dofile(source)
    return w
end

for _, flags in ipairs({{true, true}, {false, false}}) do
    local w = setup(flags[1], flags[2])
    assert(#w.events.OnPlayerUpdate == 0 and ToolkitCartRefreshVisual == nil)
end
assert(#setup(true, true, true).events.OnPlayerUpdate == 1, "host client motion was disabled")
print("PASS cart motion: disabled without SaucedCarts and on dedicated servers; enabled for host clients")

local startup = setup(false, true, false)
assert(startup.synced.ToolkitCartPose and startup.synced.ToolkitCartActionPose,
    "Host menu preload must register exact native snapshot keys before connecting")
local observer = startup.player(); observer.localPlayer = false; observer:equip()
startup.online = {observer}
for _ = 1, 10 do startup.fire("OnTick") end
assert(observer.vars.ToolkitCartMotion == nil, "menu tick queried remote avatars before connecting")
startup.client = true
for _ = 1, 10 do startup.fire("OnTick") end
assert(observer.vars.ToolkitCartMotion, "Host connection must activate the preloaded remote visual callback")
startup.client = false; observer:drop()
for _ = 1, 10 do startup.fire("OnTick") end
assert(observer.vars.ToolkitCartMotion, "disconnected callback continued querying remote avatars")
print("PASS cart motion: menu preload registers native snapshots and enables remote visuals after Host connects")

-- The authored lateral gate is exact-type, locally derived, and cleared with its visual owner.
for _, localPlayer in ipairs({true, false}) do
    local trial = setup(false, true, true)
    local actor = trial.player(); actor.localPlayer = localPlayer
    local held = actor:equip()
    for _, kind in ipairs({"SaucedWheelbarrow.WheelbarrowWood", "SaucedWheelbarrow.WheelbarrowMetal", "SaucedCarts.ShoppingCart"}) do
        held.fullType = kind
        assert(ToolkitCartRefreshVisual(actor) == held)
        assert(actor.vars.ToolkitCartWoodPivot == (kind == "SaucedWheelbarrow.WheelbarrowWood" or kind == "SaucedWheelbarrow.WheelbarrowMetal"),
            "wooden pivot selection was stale or escaped its exact held type")
    end
    held.fullType = "SaucedWheelbarrow.WheelbarrowWood"
    ToolkitCartRefreshVisual(actor)
    actor:drop(); ToolkitCartRefreshVisual(actor)
    assert(actor.vars.ToolkitCartWoodPivot == false)
    actor:equip(); ToolkitCartRefreshVisual(actor); trial.fire("OnPlayerDeath", actor)
    assert(actor.vars.ToolkitCartWoodPivot == false)
    actor:equip(); ToolkitCartRefreshVisual(actor); trial.fire("OnMainMenuEnter")
    assert(actor.vars.ToolkitCartWoodPivot == false)
    assert(not trial.synced.ToolkitCartWoodPivot and trial.sends == 0,
        "local exact-type gate added network traffic")
end
print("PASS cart motion: exact local/remote wooden pivot gate clears on cart change, drop, death and menu without syncing")

local w = setup(false, true)
local p = w.player()
w.tick(p)
assert(p.normal == 1 and p.vars.ToolkitCartMotion == false)
local cart = p:equip()
w.tick(p)
assert(p.normal < 1 and p.normal > 0.9 and p.vars.ToolkitCartMotion, "empty cart snapped to new steering")
w.tick(p, 180)
assert(math.abs(p.normal - 0.9) < 0.00001)
local empty = p.normal
cart.weight = 50
w.tick(p)
assert(p.normal < empty and p.normal > 0.7, "cargo change was not eased")
w.tick(p, 180)
assert(math.abs(p.normal - 0.7) < 0.00001)
cart.weight = 500
w.tick(p, 60)
assert(math.abs(p.normal - 0.7) < 0.00001, "overload exceeded steering limit")
p:drop(); w.tick(p)
assert(p.normal == 1 and not p.vars.ToolkitCartMotion, "drop left sticky steering")
print("PASS cart motion: bounded empty/full/overloaded cargo response and exact release restoration")

local results = {}
for _, fps in ipairs({30, 60, 144}) do
    local trial = setup(false, true)
    trial.dt = 1 / fps
    local actor = trial.player(); actor:equip(50)
    trial.tick(actor, fps)
    results[#results + 1] = actor.normal
end
assert(math.abs(results[1] - results[2]) < 0.000001 and math.abs(results[2] - results[3]) < 0.000001,
    "steering response depends on rendering FPS")
print("PASS cart motion: equal real-time response at 30/60/144 FPS")

w = setup(false, true)
p = w.player(); p.normal = 1.25; p.running = true; p:equip(50)
w.tick(p, 10)
assert(p.normal == 1.25 and p:getTurnDelta() == 0.8 and p.vars.ToolkitCartMotion)
p.running = false; w.tick(p, 180)
assert(math.abs(p.normal - 1.25 * 0.7) < 0.00001)
p.sprinting = true; w.tick(p)
assert(p:getTurnDelta() == 0.75, "sprint steering changed")
p:drop(); w.tick(p); p.sprinting = false; w.tick(p)
assert(p.normal == 1.25)
print("PASS cart motion: equip during running defers capture and sprint restores the saved walking baseline")

for _, condition in ipairs({"aim", "sneak", "dead", "vehicle", "actions", "injury", "world", "owner", "onehand"}) do
    w = setup(false, true); p = w.player(); cart = p:equip(50); w.tick(p, 60)
    if condition == "actions" then p.actions = 1
    elseif condition == "injury" then p.vars.WalkInjury = 0.3
    elseif condition == "world" then cart.world = {}
    elseif condition == "owner" then cart.owner = {}
    elseif condition == "onehand" then p.secondary = nil
    else p[condition] = true end
    w.tick(p)
    assert(p.normal == 1 and not p.vars.ToolkitCartMotion, condition .. " did not restore native controls")
    assert(p.vars.ToolkitCartWoodPivot == false, condition .. " left wooden pivot enabled")
end
print("PASS cart motion: aim, sneak, death, vehicle, actions, injury and stale hand state restore controls")

w = setup(false, true); p = w.player(); cart = p:equip(50)
local finishing = {done = true, finished = function(self) return self.done end}
p.actions, p.action = 1, finishing
assert(ToolkitCartRefreshVisual(p, finishing) == cart and p.vars.ToolkitCartMotion and p.normal == 1,
    "completed exact pickup did not restore its visual without changing steering")
w.tick(p)
assert(not p.vars.ToolkitCartMotion, "finishing-action allowance leaked into an ordinary native frame")
assert(ToolkitCartRefreshVisual(p, finishing) == cart and p.vars.ToolkitCartMotion)
for _, condition in ipairs({"unfinished", "wrongidentity", "newqueued", "twoactions", "dead", "cartmissing"}) do
    p.actions, p.action, p.dead, finishing.done = 1, finishing, false, true
    p.item, p.secondary = cart, cart
    local owner = finishing
    if condition == "unfinished" then finishing.done = false
    elseif condition == "wrongidentity" then owner = {finished = function() return true end}
    elseif condition == "newqueued" then p.action = {finished = function() return true end}
    elseif condition == "twoactions" then p.actions = 2
    elseif condition == "dead" then p.dead = true
    elseif condition == "cartmissing" then p:drop() end
    assert(ToolkitCartRefreshVisual(p, owner) == nil and not p.vars.ToolkitCartMotion,
        condition .. " bypassed the exact finished-action visual gate")
end
p.actions, p.action, p.dead = 0, nil, false; p.item, p.secondary = cart, cart
w.tick(p)
assert(p.vars.ToolkitCartMotion and p.normal < 1, "native cleanup did not retain the ordinary owned-cart visual")
w.tick(p)
assert(p.vars.ToolkitCartMotion, "later native refresh lost the post-pickup visual")
print("PASS cart motion: exact finished-action refresh preserves next-action, ownership, death and normal frame gates")

w = setup(false, true); p = w.player(); cart = p:equip(50)
local stopped = {finished = function() return false end}
p.actions, p.action = 1, stopped
assert(ToolkitCartRefreshVisual(p, stopped, true) == cart and p.vars.ToolkitCartMotion and p.normal == 1)
w.tick(p)
assert(not p.vars.ToolkitCartMotion, "stop allowance persisted into an ordinary active-action frame")
for _, condition in ipairs({"animated", "wrongidentity", "twoactions", "dead", "aim", "onehand", "world", "owner"}) do
    p.actions, p.action, p.dead, p.aim = 1, stopped, false, false
    p.item, p.secondary, cart.world, cart.owner = cart, cart, nil, p.inventory
    p.vars.IsPerformingAnAction = condition == "animated"
    if condition == "wrongidentity" then p.action = {}
    elseif condition == "twoactions" then p.actions = 2
    elseif condition == "dead" then p.dead = true
    elseif condition == "aim" then p.aim = true
    elseif condition == "onehand" then p.secondary = nil
    elseif condition == "world" then cart.world = {}
    elseif condition == "owner" then cart.owner = {} end
    assert(not ToolkitCartRefreshVisual(p, stopped, true), condition .. " bypassed exact stopped-action guards")
end
p.actions, p.action, p.dead, p.aim = 1, stopped, false, false
p.item, p.secondary, cart.world, cart.owner = cart, cart, nil, p.inventory
for _, value in ipairs({false, 1, "true"}) do
    assert(not ToolkitCartRefreshVisual(p, stopped, value), "non-boolean stop allowance accepted")
end
p.actions = 0; w.tick(p)
assert(p.vars.ToolkitCartMotion and p.normal < 1, "ordinary cleanup did not restore held controls")
print("PASS cart motion: exact native stop restores only the visual and preserves active-action/ownership guards")

w = setup(false, true, true)
p = w.player(); p:equip(50); w.tick(p, 60)
p.normal = 0.42; w.tick(p, 60)
assert(p.normal == 0.42, "other controller's setting was overwritten")
p.aim = true; w.tick(p); p.aim = false; w.tick(p, 60)
p.actions = 1; w.tick(p); p.actions = 0; w.tick(p, 60)
assert(p.normal == 0.42, "temporary ineligibility released external ownership")
p:drop(); w.tick(p)
assert(p.normal == 0.42)
p:equip(50); w.tick(p, 60)
w.fire("OnPlayerDeath", p)
assert(p.normal == 0.42 and not p.vars.ToolkitCartMotion)
local remote = w.player(); remote.localPlayer = false; remote:equip(50)
w.online = {p, remote}
for _ = 1, 10 do w.fire("OnTick") end
assert(remote.normal == 1 and remote.vars.ToolkitCartMotion, "remote animation gate modified steering")
remote:drop()
for _ = 1, 10 do w.fire("OnTick") end
assert(not remote.vars.ToolkitCartMotion)
p:equip(50); w.tick(p, 60); p.running = true; w.tick(p)
assert(p.vars.ToolkitCartMotion and p:getTurnDelta() == 0.8)
w.fire("OnMainMenuEnter")
assert(not p.vars.ToolkitCartMotion)
p.running = false; w.tick(p)
assert(p.normal == 0.42, "pending normal restore used running value")
p:drop(); w.tick(p); p:equip(50); w.tick(p, 60)
p.normal = 0.33; p.running = true; w.tick(p)
p:drop(); w.tick(p); p.running = false; w.tick(p, 60)
assert(p.normal == 0.33, "external override while running was overwritten")
getOnlinePlayers = function() return nil end
for _ = 1, 10 do w.fire("OnTick") end
print("PASS cart motion: external controls, death, remote-only visuals, menu cleanup and disconnected clients preserved")
w = setup(false, true); p = w.player(); cart = p:equip()
for _, class in ipairs({ISWalkToTimedAction, ISWalkToTimedActionF, ISPathFindAction}) do
    local object = setmetatable({}, class)
    local action = {native = true, getTable = function() return object end,
        getMetaType = function() return class.Type end}
    p.actions, p.action = 1, action
    for _, kind in ipairs({"SaucedWheelbarrow.WheelbarrowWood", "SaucedWheelbarrow.WheelbarrowMetal"}) do
        cart.fullType = kind
        assert(ToolkitCartRefreshVisual(p) == cart, "stock path action hid the held wheelbarrow: " .. kind .. class.Type)
    end
    cart.fullType = nil
    for _, condition in ipairs({"override", "subclass", "forgedtype", "twotypes", "remote", "shopping"}) do
        p.localPlayer, p.actions, cart.fullType = true, 1, nil
        object = setmetatable({}, class)
        if condition == "override" then object.update = function() end
        elseif condition == "subclass" then object = setmetatable({}, {__index = class})
        elseif condition == "forgedtype" then action.native = false
        elseif condition == "twotypes" then p.actions = 2
        elseif condition == "remote" then p.localPlayer = false
        elseif condition == "metal" then cart.fullType = "SaucedWheelbarrow.WheelbarrowMetal"
        elseif condition == "shopping" then cart.fullType = "SaucedCarts.ShoppingCart" end
        assert(not ToolkitCartRefreshVisual(p), condition .. " bypassed the exact stock path visual gate")
        action.native = true
    end
    p.localPlayer, p.actions, cart.fullType = true, 1, nil
end
print("PASS cart motion: exact stock WalkTo/F/PathFind retains wooden visual; overrides, subclasses, other carts and remote stay gated")

w = setup(false, true, true); p = w.player(); p.localPlayer = false; cart = p:equip(50)
cart.fullType, cart.model = "SaucedCarts.ShoppingCart", "Base.ShoppingCartFullModel"
w.online = {p}
local function remoteTicks(count)
    for _ = 1, count or 10 do w.fire("OnTick") end
end
remoteTicks(30)
assert(w.repaints == 0 and cart.model == "Base.ShoppingCartFullModel", "qualified alias repainted the same model script")
cart.model = "Base.ShoppingCartModel"
remoteTicks(30)
assert(w.repaints == 1 and cart.model == "ShoppingCartFullModel", "wrong replicated fill did not reconcile exactly once")
cart.weight = 20; remoteTicks(30)
assert(w.repaints == 2 and cart.model == "ShoppingCartPartialModel", "replicated cargo change did not refresh fill")
cart.weight = 50; cart.flashlight = true; remoteTicks(30)
assert(w.repaints == 3 and cart.model == "ShoppingCartFlashlightFullModel", "registered upgrade model was lost")
cart.model = "Base.ShoppingCartFlashlightFullModel"; remoteTicks(30)
assert(w.repaints == 3 and w.sends == 0 and p.normal == 1, "remote refresh repainted an alias, sent packets or changed steering")
print("PASS cart motion: remote fill/upgrade reconciliation resolves Base aliases and repaints once without sends or steering changes")

for _, condition in ipairs({"local", "server", "disconnected", "disabled", "actions", "animated", "cartaction", "foreign", "owner", "onehand", "world", "aim", "missingmodel", "unregistered", "nanweight", "infinitecapacity"}) do
    w = setup(condition == "server", condition ~= "disabled", true)
    p = w.player(); p.localPlayer = condition == "local"; cart = p:equip(50)
    cart.fullType, cart.model = "SaucedCarts.ShoppingCart", "ShoppingCartModel"
    w.online = {p}
    if condition == "disconnected" then w.client = false
    elseif condition == "actions" then p.actions = 1
    elseif condition == "animated" then p.vars.IsPerformingAnAction = true
    elseif condition == "cartaction" then p.vars.ToolkitWoodCartAction = true
    elseif condition == "foreign" then cart.fullType = "Other.ForeignCart"; w.types[cart.fullType] = w.types["SaucedCarts.ShoppingCart"]
    elseif condition == "owner" then cart.owner = {}
    elseif condition == "onehand" then p.secondary = nil
    elseif condition == "world" then cart.world = {}
    elseif condition == "aim" then p.aim = true
    elseif condition == "missingmodel" then w.types[cart.fullType].visualModels.full = "UnknownModel"
    elseif condition == "unregistered" then w.types[cart.fullType] = nil
    elseif condition == "nanweight" then cart.weight = 0 / 0
    elseif condition == "infinitecapacity" then cart.capacity = math.huge end
    for _ = 1, 30 do w.fire("OnTick") end
    w.tick(p)
    assert(w.repaints == 0 and w.sends == 0 and cart.model == "ShoppingCartModel", condition .. " bypassed remote model guards")
end
print("PASS cart motion: remote model refresh preserves local/server/action/ownership/registration/finite guards")
require = originalRequire
