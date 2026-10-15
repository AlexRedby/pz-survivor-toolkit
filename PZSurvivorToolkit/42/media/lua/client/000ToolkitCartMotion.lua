if isServer() and not isClient() or not getActivatedMods():contains("SaucedCarts") then return end
require "SaucedCarts/Core"

local states = setmetatable({}, {__mode = "k"})
local blocked = setmetatable({}, {__mode = "k"})
local visuals = setmetatable({}, {__mode = "k"})

local function setVisual(player, enabled)
    player:setVariable("ToolkitCartMotion", enabled)
    visuals[player] = enabled and true or nil
end

local function running(player)
    return player:isRunning() or player:isSprinting()
end

local function restore(player)
    local state = states[player]
    if state then
        -- getTurnDelta reports a different field during running/sprinting.
        if running(player) then state.pending = true; return end
        if math.abs(player:getTurnDelta() - state.applied) < 0.00001 then
            player:setTurnDelta(state.base)
        else
            blocked[player] = state.cart
        end
        states[player] = nil
    end
end

local function heldCart(player)
    local item = player:getPrimaryHandItem()
    if not item or player:getSecondaryHandItem() ~= item or not instanceof(item, "InventoryContainer")
        or not SaucedCarts.safeIsCart(item) or item:getWorldItem() or item:getContainer() ~= player:getInventory()
        or player:isDead() or player:isAiming() or player:isSneaking() or player:getVehicle()
        or player:getCharacterActions():size() > 0 or math.abs(player:getVariableFloat("WalkInjury", 0)) >= 0.15 then return end
    return item
end

local function update(player)
    local cart = heldCart(player)
    setVisual(player, cart ~= nil)
    if not player:isLocalPlayer() then return end
    if blocked[player] and (player:getPrimaryHandItem() ~= blocked[player] or player:getSecondaryHandItem() ~= blocked[player]) then
        blocked[player] = nil
    end
    if states[player] and states[player].pending and not running(player) then
        restore(player)
        return
    end
    if not cart then
        restore(player)
        return
    end
    if running(player) or blocked[player] then
        restore(player)
        return
    end
    local state = states[player]
    if state and state.cart ~= cart then restore(player); state = nil end
    local current = player:getTurnDelta()
    if state and math.abs(current - state.applied) >= 0.00001 then
        -- A different controller took ownership; leave its setting alone until release.
        states[player], blocked[player] = nil, cart
        return
    end
    if not state then
        if current <= 0 then return end
        state = {cart = cart, base = current, applied = current}
        states[player] = state
    end
    local inventory = cart:getInventory()
    local capacity = inventory:getEffectiveCapacity(player)
    local load = capacity > 0 and math.min(1, math.max(0, inventory:getCapacityWeight() / capacity)) or 0
    local target = state.base * (0.90 - 0.20 * load)
    local dt = math.max(0, math.min(0.1, getGameTime():getRealworldSecondsSinceLastUpdate()))
    state.applied = state.applied + (target - state.applied) * (1 - math.exp(-dt / 0.18))
    player:setTurnDelta(state.applied)
end

Events.OnPlayerUpdate.Add(update)
Events.OnPlayerDeath.Add(function(player)
    restore(player)
    blocked[player] = nil
    setVisual(player, false)
end)
Events.OnMainMenuEnter.Add(function()
    for player in pairs(states) do
        restore(player)
    end
    for player in pairs(visuals) do setVisual(player, false) end
    blocked = setmetatable({}, {__mode = "k"})
end)

-- Remote avatars can skip OnPlayerUpdate; only their visual gate needs updating.
if isClient() then
    local ticks = 0
    Events.OnTick.Add(function()
        ticks = ticks + 1
        if ticks % 10 ~= 0 then return end
        local players = getOnlinePlayers()
        if not players then return end
        for i = 0, players:size() - 1 do
            local player = players:get(i)
            if not player:isLocalPlayer() then setVisual(player, heldCart(player) ~= nil) end
        end
    end)
end
