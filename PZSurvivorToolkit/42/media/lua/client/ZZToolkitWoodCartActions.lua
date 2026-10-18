if not getActivatedMods():contains("SaucedCarts") then return end
local transitions = require "ToolkitWoodCartActions"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/WalkToTimedActionF"

local fromWorld = ISCartPickupAction.FromWorldItem
ISCartPickupAction.FromWorldItem = function(character, world)
    local held = character:getPrimaryHandItem()
    if character:isTimedActionInstant() or held and held:isForceDropHeavyItem() then
        return fromWorld(character, world)
    end
    local stance
    if transitions.wooden(world:getItem()) then
        stance = toolkitWoodCartStance and toolkitWoodCartStance(character, world)
        if not stance or character:DistToSquared(stance.x, stance.y) < .05 * .05 then return fromWorld(character, world) end
    else
        local square = world:getSquare()
        if character:getSquare():canReachTo(square) then return fromWorld(character, world) end
        -- Sauced's ground callback queues pickup directly, whose validity requires an adjacent square.
        local adjacent = AdjacentFreeTileFinder.Find(square, character)
        if not adjacent then return fromWorld(character, world) end
        stance = {x = adjacent:getX() + .5, y = adjacent:getY() + .5}
    end
    local x, y, z, id = world:getSquare():getX(), world:getSquare():getY(), world:getSquare():getZ(), world:getItem():getID()
    local walk = ISWalkToTimedActionF:new(character, Vector3f.new(stance.x, stance.y, z))
    walk.toolkitWoodCartItem = world:getItem()
    local perform = walk.perform
    walk.perform = function(self)
        local action = ISCartPickupAction:new(character, x, y, z, id)
        if action:findWorldItem() == world then self:addAfter(action) end
        return perform(self)
    end
    return walk
end

Events.OnPlayerUpdate.Add(function(player)
    if toolkitWoodCartTick then toolkitWoodCartTick(player) end
end)
Events.OnPlayerDeath.Add(function(player)
    if toolkitWoodCartEnd then toolkitWoodCartEnd(player) end
end)
Events.OnMainMenuEnter.Add(function()
    if toolkitWoodCartEnd then toolkitWoodCartEnd(nil) end
end)

-- Change only cart action instances; ordinary equipment keeps its class and fingerprint.
local addToQueue = ISTimedActionQueue.addToQueue
ISTimedActionQueue.addToQueue = function(queue, action)
    local transfers = SaucedCarts.TransferRestrictions
    local drop = getmetatable(action) == ISDropWorldItemAction and not action.isPlaceItem and not action.isMultiple
        and action.sq == action.character:getCurrentSquare()
    local unequip = getmetatable(action) == ISUnequipAction
    if toolkitWoodCartUpdate and toolkitWoodCartDropPose and (unequip or drop)
        -- The native world-menu "Drop <name>" calls onUnEquip without a reason.
        and (action.reason == nil or action.reason == "drop" or action.reason == "place")
        and transitions.wooden(action.item)
        and not (transfers and transfers.hasPendingTransfer and transfers.hasPendingTransfer(action.item:getID()))
        and not action.character:isTimedActionInstant()
        and action.character:getPrimaryHandItem() == action.item
        and action.character:getSecondaryHandItem() == action.item then
        local pose = toolkitWoodCartDropPose(action.character, action.item)
        if pose and transitions.setdownPose(action, pose, drop) then
            setmetatable(action, drop and ToolkitWoodCartDrop or ToolkitWoodCartSetdown)
            action.maxTime = action:getDuration()
            action.stopOnWalk, action.stopOnRun, action.stopOnAim = true, true, true
        end
    end
    return addToQueue(queue, action)
end
