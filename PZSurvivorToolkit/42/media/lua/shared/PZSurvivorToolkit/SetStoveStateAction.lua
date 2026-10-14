require "TimedActions/ISToggleStoveAction"

PZSurvivorToolkitSetStoveState = ISToggleStoveAction:derive("PZSurvivorToolkitSetStoveState")

function PZSurvivorToolkitSetStoveState:isValid()
    local object, player = self.object, self.character
    if type(self.desired) ~= "boolean" or not object or not instanceof(object, "IsoStove")
        or object:getObjectIndex() == -1 or not player or player:isDead() then return false end
    local square, current = object:getSquare(), player:getCurrentSquare()
    if not square or not current or square:getZ() ~= current:getZ()
        or math.abs(square:getX() - current:getX()) > 1 or math.abs(square:getY() - current:getY()) > 1
        or not current:canReachTo(square) then return false end
    return not self.desired or (object:getContainer() and object:getContainer():isPowered()) == true
end

function PZSurvivorToolkitSetStoveState:complete()
    -- The server checks the requested state at commit, so duplicate requests cannot toggle it back.
    if self:isValid() and self.object:Activated() ~= self.desired then self.object:Toggle() end
    return true
end

function PZSurvivorToolkitSetStoveState:new(character, object, desired)
    local action = ISToggleStoveAction.new(self, character, object)
    action.desired = desired
    return action
end

return PZSurvivorToolkitSetStoveState
