local source = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/000ToolkitCartMotion.lua"
local originalRequire = require
local function setup(server, active, client)
    local w = {events = {}, dt = 1 / 60, online = {}}
    ToolkitCartRefreshVisual = nil
    isServer = function() return server end
    isClient = function() return client == true end
    getActivatedMods = function() return {contains = function(_, name) return active and name == "SaucedCarts" end} end
    require = function(name) assert(name == "SaucedCarts/Core") end
    instanceof = function(item, kind) return kind == "InventoryContainer" and item.container == true end
    SaucedCarts = {safeIsCart = function(item) return item.cart == true end}
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
        function p:setVariable(name, value) self.vars[name] = value end
        function p:getTurnDelta() return self.sprinting and 0.75 or self.running and 0.8 or self.normal end
        function p:setTurnDelta(value) self.normal = value end
        function p:equip(weight, capacity)
            local cart = {container = true, cart = true, weight = weight or 0, capacity = capacity or 50, owner = self.inventory}
            function cart:getWorldItem() return self.world end
            function cart:getContainer() return self.owner end
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
require = originalRequire
