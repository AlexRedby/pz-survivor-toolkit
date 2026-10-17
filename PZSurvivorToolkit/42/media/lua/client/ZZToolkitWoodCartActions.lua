if not getActivatedMods():contains("SaucedCarts") then return end
local transitions = require "ToolkitWoodCartActions"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/WalkToTimedActionF"

local fromWorld = ISCartPickupAction.FromWorldItem
ISCartPickupAction.FromWorldItem = function(character, world)
    local held = character:getPrimaryHandItem()
    if not toolkitWoodCartStance or character:isTimedActionInstant() or not transitions.wooden(world:getItem())
        or held and held:isForceDropHeavyItem() then
        return fromWorld(character, world)
    end
    local stance = toolkitWoodCartStance(character, world)
    if not stance or character:DistTo(stance.x, stance.y) < .12 then return fromWorld(character, world) end
    local x, y, z, id = world:getSquare():getX(), world:getSquare():getY(), world:getSquare():getZ(), world:getItem():getID()
    local walk = ISWalkToTimedActionF:new(character, Vector3f.new(stance.x, stance.y, z))
    local perform = walk.perform
    walk.perform = function(self)
        local action = ISCartPickupAction:new(character, x, y, z, id)
        if action:findWorldItem() == world then self:addAfter(action) end
        return perform(self)
    end
    return walk
end

Events.OnPlayerDeath.Add(function(player)
    if toolkitWoodCartEnd then toolkitWoodCartEnd(player) end
end)
Events.OnMainMenuEnter.Add(function()
    if toolkitWoodCartEnd then toolkitWoodCartEnd(nil) end
end)

-- Change only cart action instances; ordinary equipment keeps its class and fingerprint.
local addToQueue = ISTimedActionQueue.addToQueue
ISTimedActionQueue.addToQueue = function(queue, action)
    if toolkitWoodCartUpdate and toolkitWoodCartDropPose and getmetatable(action) == ISUnequipAction
        and (action.reason == "drop" or action.reason == "place")
        and transitions.wooden(action.item)
        and not action.character:isTimedActionInstant()
        and action.character:getPrimaryHandItem() == action.item
        and action.character:getSecondaryHandItem() == action.item then
        local pose = toolkitWoodCartDropPose(action.character, action.item)
        if pose then
            action.toolkitDropX, action.toolkitDropY, action.toolkitDropZ = pose.x, pose.y, pose.z
            action.toolkitDropRotation = pose.rotation
            setmetatable(action, ToolkitWoodCartSetdown)
            action.maxTime = action:getDuration()
            action.stopOnWalk, action.stopOnRun, action.stopOnAim = true, true, true
        end
    end
    return addToQueue(queue, action)
end
