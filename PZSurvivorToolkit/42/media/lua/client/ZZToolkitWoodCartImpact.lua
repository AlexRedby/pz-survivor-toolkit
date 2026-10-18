if isServer() and not isClient() or not getActivatedMods():contains("SaucedCarts") then return end
local instantDrop = require "SaucedCarts/CartState/InstantDrop"
local impacts = setmetatable({}, {__mode = "k"})

Events.OnAIStateChange.Add(function(player, state)
    if not player or not instanceof(player, "IsoPlayer") or not player:isLocalPlayer() or player:isNpc()
        or state ~= player:getCurrentState() then return end
    local name = state and player:getCurrentStateName()
    if name ~= "CollideWithWallState" then
        if name ~= "PlayerGetUpState" then impacts[player] = nil end
        return
    end
    if impacts[player] then return end
    impacts[player] = true
    local cart, inventory = player:getPrimaryHandItem(), player:getInventory()
    if player:isDead() or not player:getCurrentSquare() or not cart
        or cart:getFullType() ~= "SaucedWheelbarrow.WheelbarrowWood"
        or player:getSecondaryHandItem() ~= cart or cart:getWorldItem()
        or cart:getContainer() ~= inventory or not inventory:contains(cart) then return end

    local dropEnd = not isClient() and toolkitWoodCartDropPose and toolkitWoodCartDropBegin and toolkitWoodCartDropEnd
    if dropEnd then
        -- Emergency release must survive an unavailable presentation placement.
        pcall(function()
            local pose = toolkitWoodCartDropPose(player, cart)
            if pose then toolkitWoodCartDropBegin(player, cart, pose.x, pose.y, pose.z, pose.rotation) end
        end)
    end
    local ok, result = pcall(instantDrop.handle, player, cart)
    if dropEnd then
        local cleaned, cleanupError = pcall(dropEnd)
        if not cleaned and ok then error(cleanupError, 0) end
    end
    if not ok then error(result, 0) end
end)
