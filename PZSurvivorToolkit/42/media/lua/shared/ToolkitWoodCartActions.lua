if not getActivatedMods():contains("SaucedCarts") then return end
require "SaucedCarts/TimedActions/ISCartPickupAction"
require "TimedActions/ISUnequipAction"

-- These subclasses inherit the authoritative Sauced complete, including break/stairs handling.
ToolkitWoodCartPickup = ISCartPickupAction:derive("ToolkitWoodCartPickup")
ToolkitWoodCartPickup.Type = "ToolkitWoodCartPickup"
ToolkitWoodCartSetdown = ISUnequipAction:derive("ToolkitWoodCartSetdown")
ToolkitWoodCartSetdown.Type = "ToolkitWoodCartSetdown"

local function wooden(item)
    return item and item:getFullType() == "SaucedWheelbarrow.WheelbarrowWood"
end
local function finish(self)
    if not self.toolkitPresentation then return end
    self.toolkitPresentation = nil
    if toolkitWoodCartEnd then toolkitWoodCartEnd(self.character) end
    self.character:clearVariable("ToolkitWoodCartAction")
    self.character:clearVariable("ToolkitWoodCartProgress")
end
local function present(self, pickup)
    if isServer() or not toolkitWoodCartUpdate then return end
    local item = pickup and self:findItem() or self.item
    if not item then return end
    -- Retire the lower cart-idle layer while the action owns the pose, before its idle endpoint fades out.
    if not pickup then SaucedCarts.clearCartPose(self.character) end
    toolkitWoodCartUpdate(self.character, item, pickup, self:getJobDelta())
    self.character:setVariable("ToolkitWoodCartProgress", self:getJobDelta())
end
local function start(self, pickup)
    self.toolkitPresentation = true
    self.character:setVariable("ToolkitCartMotion", false)
    self:setActionAnim("ToolkitWoodCart")
    self.character:setVariable("ToolkitWoodCartAction", true)
    self:setOverrideHandModels(pickup and self:findItem() or self.item, nil)
    present(self, pickup)
end

function ToolkitWoodCartPickup:getDuration()
    return self.character:isTimedActionInstant() and 1 or 88
end
function ToolkitWoodCartPickup:start()
    start(self, true)
end
function ToolkitWoodCartPickup:waitToStart()
    local world = self:findWorldItem()
    if world and toolkitWoodCartStance then
        local stance = toolkitWoodCartStance(self.character, world)
        if stance then
            self.character:faceLocationF(stance.faceX, stance.faceY)
            -- Native shouldBeTurning can still read the previous twist on the first face request.
            return not stance.aligned or self.character:shouldBeTurning()
        end
    end
    return ISCartPickupAction.waitToStart(self)
end
function ToolkitWoodCartPickup:update()
    local item = self:findItem()
    if item then item:setJobDelta(self:getJobDelta()) end
    present(self, true)
    self.character:setMetabolicTarget(Metabolics.HeavyDomestic)
end
function ToolkitWoodCartPickup:stop()
    finish(self)
    return ISCartPickupAction.stop(self)
end
local function pickupVisual(self)
    local cart = self.character:getPrimaryHandItem()
    if ToolkitCartRefreshVisual and cart and cart:getID() == self.itemId then
        ToolkitCartRefreshVisual(self.character, self.action)
    end
end
function ToolkitWoodCartPickup:perform()
    finish(self)
    local result = ISCartPickupAction.perform(self)
    pickupVisual(self)
    return result
end
function ToolkitWoodCartPickup:complete()
    local result = ISCartPickupAction.complete(self)
    -- SP equips in complete, after perform; its exact finished native action is still in the stack here.
    pickupVisual(self)
    return result
end
function ToolkitWoodCartPickup:forceCancel()
    finish(self)
end

function ToolkitWoodCartSetdown:getDuration()
    return self.character:isTimedActionInstant() and 1 or 88
end
function ToolkitWoodCartSetdown:start()
    if not isServer() and toolkitWoodCartDropPose then
        local pose = toolkitWoodCartDropPose(self.character, self.item)
        if not pose then self:forceStop(); return end
        self.toolkitDropX, self.toolkitDropY, self.toolkitDropZ = pose.x, pose.y, pose.z
        self.toolkitDropRotation = pose.rotation
    end
    ISUnequipAction.start(self)
    start(self, false)
    if not isServer() and self.toolkitDropX and toolkitWoodCartSetdownPose then
        toolkitWoodCartSetdownPose(self.character, self.item, self.toolkitDropX, self.toolkitDropY,
            self.toolkitDropZ, self.toolkitDropRotation)
    end
end
function ToolkitWoodCartSetdown:update()
    ISUnequipAction.update(self)
    present(self, false)
end
function ToolkitWoodCartSetdown:stop()
    finish(self)
    local result = ISUnequipAction.stop(self)
    if ToolkitCartRefreshVisual and self.character:getPrimaryHandItem() == self.item then
        ToolkitCartRefreshVisual(self.character, self.action, true)
    end
    return result
end
function ToolkitWoodCartSetdown:perform()
    finish(self)
    return ISUnequipAction.perform(self)
end
function ToolkitWoodCartSetdown:forceCancel()
    finish(self)
end
function ToolkitWoodCartSetdown:complete()
    local prepared = self.toolkitDropX and toolkitWoodCartDropBegin
        and toolkitWoodCartDropBegin(self.character, self.item, self.toolkitDropX, self.toolkitDropY,
            self.toolkitDropZ, self.toolkitDropRotation)
    local ok, result = pcall(ISUnequipAction.complete, self)
    if prepared then toolkitWoodCartDropEnd() end
    if not ok then error(result) end
    return result
end

local originalNew = ISCartPickupAction.new
ISCartPickupAction.new = function(class, character, x, y, z, id)
    local action = originalNew(class, character, x, y, z, id)
    if toolkitWoodCartStance and not character:isTimedActionInstant() and wooden(action:findItem())
        and toolkitWoodCartStance(character, action:findWorldItem()) then
        setmetatable(action, ToolkitWoodCartPickup)
        action.maxTime = action:getDuration()
        action.stopOnWalk, action.stopOnRun, action.stopOnAim = true, true, true
    end
    return action
end

return {wooden = wooden, finish = finish}
