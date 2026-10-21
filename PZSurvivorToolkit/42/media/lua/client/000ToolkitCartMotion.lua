if isServer() and not isClient() or not getActivatedMods():contains("SaucedCarts") then return end
require "SaucedCarts/Core"
require "TimedActions/WalkToTimedAction"
require "TimedActions/WalkToTimedActionF"
require "Vehicles/TimedActions/ISPathFindAction"

-- Host loads client Lua at the menu, before isClient() becomes true.
if addVariableToSyncList then
    addVariableToSyncList("ToolkitCartPose")
    addVariableToSyncList("ToolkitCartActionPose")
end

local pathActions = {}
for _, class in ipairs({ISWalkToTimedAction, ISWalkToTimedActionF, ISPathFindAction}) do
    pathActions[class.Type] = {class = class, start = class.start, update = class.update,
        stop = class.stop, perform = class.perform, isValid = class.isValid}
end

local function nativePathAction(action)
    if not action or not instanceof(action, "LuaTimedActionNew") then return false end
    local known = pathActions[action:getMetaType()]
    local object = action:getTable()
    if not known or not object or getmetatable(object) ~= known.class then return false end
    for _, name in ipairs({"start", "update", "stop", "perform", "isValid"}) do
        if object[name] ~= known[name] then return false end
    end
    return true
end

local states = setmetatable({}, {__mode = "k"})
local blocked = setmetatable({}, {__mode = "k"})
local visuals = setmetatable({}, {__mode = "k"})

local function wheelbarrow(item)
    local kind = item and item:getFullType()
    return kind == "SaucedWheelbarrow.WheelbarrowWood" or kind == "SaucedWheelbarrow.WheelbarrowMetal"
end

local function setVisual(player, enabled, cart)
    player:setVariable("ToolkitCartMotion", enabled)
    -- Derive this locally for owners and observers; it is not another network variable.
    player:setVariable("ToolkitCartWoodPivot", enabled and wheelbarrow(cart))
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

local function heldCart(player, finishingAction, stopped)
    local item = player:getPrimaryHandItem()
    if not item or player:getSecondaryHandItem() ~= item or not instanceof(item, "InventoryContainer")
        or not SaucedCarts.safeIsCart(item) or item:getWorldItem() or item:getContainer() ~= player:getInventory()
        or player:isDead() or player:isAiming() or player:isSneaking() or player:getVehicle()
        or math.abs(player:getVariableFloat("WalkInjury", 0)) >= 0.15 then return end
    local actions = player:getCharacterActions()
    -- Native complete/stop callbacks run before removing their exact action from the stack.
    if actions:size() > 0 and not (actions:size() == 1 and player:isLocalPlayer()
        and wheelbarrow(item) and nativePathAction(actions:get(0)))
        and not (finishingAction and actions:size() == 1
        and actions:get(0) == finishingAction and (finishingAction:finished()
            or stopped == true and not player:getVariableBoolean("IsPerformingAnAction"))) then return end
    return item
end

local function refreshRemoteModel(player, cart)
    if not cart or not isClient() or isServer() or player:isLocalPlayer()
        or player:getCharacterActions():size() ~= 0 or player:getVariableBoolean("IsPerformingAnAction")
        or player:getVariableBoolean("ToolkitWoodCartAction") then return end
    local kind = cart:getFullType()
    if kind ~= "SaucedCarts.ShoppingCart" and kind ~= "SaucedWheelbarrow.WheelbarrowWood"
        and kind ~= "SaucedWheelbarrow.WheelbarrowMetal" then return end
    if not SaucedCarts.getCartData or not SaucedCarts.calculateFillState
        or not SaucedCarts.buildCartModelName or not SaucedCarts.updateCartVisual then return end
    local data = SaucedCarts.getCartData(cart)
    if not data or not data.visualModels then return end
    local inventory = cart:getInventory()
    local capacity, weight = inventory:getEffectiveCapacity(player), inventory:getCapacityWeight()
    if type(capacity) ~= "number" or capacity ~= capacity or capacity <= 0 or capacity == math.huge
        or type(weight) ~= "number" or weight ~= weight or weight < 0 or weight == math.huge then return end
    local expected = SaucedCarts.buildCartModelName(cart, SaucedCarts.calculateFillState(cart, player))
    if type(expected) ~= "string" or expected == "" then return end
    local scripts = getScriptManager()
    local wanted = scripts:getModelScript(expected)
    local current = cart:getStaticModel()
    local actual = type(current) == "string" and scripts:getModelScript(current) or nil
    -- Native replication can update cargo/ModData while retaining the previous fill model.
    if wanted and actual ~= wanted then SaucedCarts.updateCartVisual(cart, player, true) end
end

function ToolkitCartRefreshVisual(player, finishingAction, stopped)
    local cart = heldCart(player, finishingAction, stopped)
    setVisual(player, cart ~= nil, cart)
    refreshRemoteModel(player, cart)
    return cart
end

local function update(player)
    local cart = ToolkitCartRefreshVisual(player)
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
local ticks = 0
Events.OnTick.Add(function()
    if not isClient() then return end
    ticks = ticks + 1
    if ticks % 10 ~= 0 then return end
    local players = getOnlinePlayers()
    if not players then return end
    for i = 0, players:size() - 1 do
        local player = players:get(i)
        if not player:isLocalPlayer() then ToolkitCartRefreshVisual(player) end
    end
end)
