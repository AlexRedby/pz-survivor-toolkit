if not getActivatedMods():contains("SaucedCarts") then return end
require "SaucedCarts/TimedActions/ISCartPickupAction"
require "TimedActions/ISUnequipAction"
require "TimedActions/ISDropWorldItemAction"

-- These subclasses inherit the authoritative Sauced complete, including break/stairs handling.
ToolkitWoodCartPickup = ISCartPickupAction:derive("ToolkitWoodCartPickup")
ToolkitWoodCartPickup.Type = "ToolkitWoodCartPickup"
ToolkitWoodCartSetdown = ISUnequipAction:derive("ToolkitWoodCartSetdown")
ToolkitWoodCartSetdown.Type = "ToolkitWoodCartSetdown"
ToolkitWoodCartDrop = ISDropWorldItemAction:derive("ToolkitWoodCartDrop")
ToolkitWoodCartDrop.Type = "ToolkitWoodCartDrop"

local function wooden(item)
    return item and item:getFullType() == "SaucedWheelbarrow.WheelbarrowWood"
end
local function retire(self)
    self.toolkitPresentation = nil
    self.character:clearVariable("ToolkitWoodCartAction")
    self.character:clearVariable("ToolkitWoodCartProgress")
end
local function finish(self)
    if not self.toolkitPresentation then return end
    if toolkitWoodCartEnd then toolkitWoodCartEnd(self.character) end
    retire(self)
end
local function stop(self, pickup, nativeStop)
    local item = pickup and self:findItem() or self.item
    local ok, result = pcall(nativeStop, self)
    if not ok then finish(self); error(result, 0) end
    if self.toolkitPresentation then
        if toolkitWoodCartCancel and toolkitWoodCartCancel(self.character, item, pickup, self.action) then
            retire(self)
        else
            finish(self)
        end
    end
    return result
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
    local item = pickup and self:findItem() or self.item
    -- An item override also installs its right-hand cart mask during the action's blend-in.
    self:setOverrideHandModelsString(item and item:getStaticModel() or nil, nil)
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
    return stop(self, true, ISCartPickupAction.stop)
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

local function setdownPose(self, pose, drop)
    if drop then
        local square = getCell():getGridSquare(math.floor(pose.x), math.floor(pose.y), pose.z)
        if not square then return false end
        self.sq = square
        self.xoffset, self.yoffset, self.zoffset = pose.x - square:getX(), pose.y - square:getY(), 0
        -- Native world-item construction randomizes exact zero offsets.
        if self.xoffset == 0 then self.xoffset = .00001 end
        if self.yoffset == 0 then self.yoffset = .00001 end
        self.rotation = pose.rotation
    end
    self.toolkitDropX, self.toolkitDropY, self.toolkitDropZ = pose.x, pose.y, pose.z
    self.toolkitDropRotation = pose.rotation
    return true
end

local function setdown(class, base)
    function class:getDuration()
        return self.character:isTimedActionInstant() and 1 or 88
    end
    function class:start()
        if not isServer() and toolkitWoodCartDropPose then
            local pose = toolkitWoodCartDropPose(self.character, self.item)
            if not pose then self:forceStop(); return end
            if not setdownPose(self, pose, base == ISDropWorldItemAction) then self:forceStop(); return end
        end
        base.start(self)
        start(self, false)
        if not isServer() and self.toolkitDropX and toolkitWoodCartSetdownPose then
            toolkitWoodCartSetdownPose(self.character, self.item, self.toolkitDropX, self.toolkitDropY,
                self.toolkitDropZ, self.toolkitDropRotation)
        end
    end
    function class:update()
        base.update(self)
        present(self, false)
    end
    function class:stop()
        local result = stop(self, false, base.stop)
        if ToolkitCartRefreshVisual and self.character:getPrimaryHandItem() == self.item then
            ToolkitCartRefreshVisual(self.character, self.action, true)
        end
        return result
    end
    function class:perform()
        finish(self)
        return base.perform(self)
    end
    function class:forceCancel()
        finish(self)
    end
    function class:complete()
        if base == ISDropWorldItemAction then
            -- Native drop transmits explicitly; bypass the unequip placement hook's automatic transmit.
            return base.complete(self)
        end
        local prepared = self.toolkitDropX and toolkitWoodCartDropBegin
            and toolkitWoodCartDropBegin(self.character, self.item, self.toolkitDropX, self.toolkitDropY,
                self.toolkitDropZ, self.toolkitDropRotation)
        local ok, result = pcall(base.complete, self)
        if prepared then toolkitWoodCartDropEnd() end
        if not ok then error(result) end
        return result
    end

end
setdown(ToolkitWoodCartSetdown, ISUnequipAction)
setdown(ToolkitWoodCartDrop, ISDropWorldItemAction)

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

return {wooden = wooden, finish = finish, setdownPose = setdownPose}
