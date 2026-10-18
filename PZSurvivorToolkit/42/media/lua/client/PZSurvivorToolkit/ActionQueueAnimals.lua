require "PZSurvivorToolkit/ActionQueueOperations"
require "ISUI/Animal/ISAnimalContextMenu"

local Toolkit = PZSurvivorToolkit

local function notBroken(item)
    return not item:isBroken()
end

Events.OnGameStart.Add(function()
    local butcher = AnimalContextMenu.onButcherAnimal
    local function prepare(character, target)
        local body = target.body
        if character:isDead() or character:getVehicle() or not body:getSquare()
                or body:getStaticMovingObjectIndex() < 0 or not body:hasAnimalParts() then return end
        local knife = character:getInventory():getFirstTagEvalRecurse(ItemTag.BUTCHER_ANIMAL, notBroken)
        if knife then return butcher(body, character, knife) end
    end
    AnimalContextMenu.onButcherAnimal = function(body, character, knife)
        if not Toolkit.Settings.actionQueue() then return butcher(body, character, knife) end
        if not body or not character then return end
        return Toolkit.ActionQueueOperations.enqueue(character, prepare, {body = body},
            {fields = {toolkitWorldOperation = "butcher", body = body}})
    end
end)
