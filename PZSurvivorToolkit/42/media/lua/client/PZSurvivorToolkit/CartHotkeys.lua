local Hotkeys = {}
local pending, captured
local cartTypes = {
    ISCartPickupAction = true, ToolkitWoodCartPickup = true,
    ISCartEquipAction = true, ISCartLoadCorpseAction = true,
    ToolkitWoodCartDrop = true, ToolkitWoodCartSetdown = true,
}

local function restore()
    if captured then
        if captured.player:isIgnoreContextKey() then
            captured.player:setIgnoreContextKey(captured.previous)
        end
        captured = nil
    end
end

function Hotkeys.reset()
    pending = nil
    restore()
end

-- Runs before SaucedCarts' registered key callback; it does not choose a target
-- or enqueue an action. The upstream producer remains authoritative.
function Hotkeys.beforePress(key, binding)
    -- A new press owns a new decision once updateUseKey consumed the previous
    -- release. Do not let the extra quiet frame swallow a rejected rapid tap.
    if captured and captured.quiet >= 1 then restore() end
    pending = nil
    if not binding or key ~= binding:getValue() or not getCore():isKey(KeybindId.INTERACT, key) then return end
    local player = getSpecificPlayer(0)
    if not player or player:isDead() or player:getVehicle() then return end
    local queue = ISTimedActionQueue.getTimedActionQueue(player).queue
    if #queue ~= 0 then return end
    pending = {player = player, key = key}
end

function Hotkeys.afterPress(key)
    local request = pending
    pending = nil
    if not request or request.key ~= key or request.player ~= getSpecificPlayer(0) then return end
    local player = request.player
    local accepted = false
    for _, action in ipairs(ISTimedActionQueue.getTimedActionQueue(player).queue) do
        if action.character == player and (cartTypes[action.Type]
            or action.toolkitWoodCartItem and SaucedCarts.isCart(action.toolkitWoodCartItem)
            or action.Type == "ISDropWorldItemAction" and action.item and SaucedCarts.isCart(action.item)) then
            accepted = true
            break
        end
    end
    if not accepted then return end
    if captured and captured.player ~= player then restore() end
    if not captured then
        captured = {player = player, key = key, previous = player:isIgnoreContextKey()}
    end
    captured.key, captured.quiet = key, 0
    captured.updated, captured.drained = false, false
    player:setIgnoreContextKey(true)
end

local function released(state)
    local player = state.player
    return not player:getVehicle() and not isKeyDown(state.key) and not player:isInteractButtonDown()
end

function Hotkeys.playerUpdate(player)
    if not captured then return end
    if captured.player ~= getSpecificPlayer(0) or captured.player:isDead() then restore(); return end
    if player ~= captured.player then return end
    -- SaucedCarts clears the flag when a drop removes the held cart. This
    -- callback runs after its update; retain ownership of this key gesture.
    player:setIgnoreContextKey(true)
    -- OnPlayerUpdate precedes updateUseKey. Only mark a candidate here.
    captured.updated = true
    captured.drained = released(captured)
end

function Hotkeys.tick()
    if not captured then return end
    if captured.player ~= getSpecificPlayer(0) or captured.player:isDead() then restore(); return end
    -- OnTick follows updateUseKey, which drains the native release while ignored.
    -- Paused/missing/in-vehicle updates must not advance this release barrier.
    if captured.updated and captured.drained and released(captured) then
        captured.quiet = captured.quiet + 1
    else
        captured.quiet = 0
    end
    captured.updated, captured.drained = false, false
    if captured.quiet >= 2 then restore() end
end

return Hotkeys
