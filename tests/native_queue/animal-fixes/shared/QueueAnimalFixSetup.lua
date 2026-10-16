require 'Definitions/animal/HutchDefinitions'
require 'Definitions/animal/AnimalPartsDefinitions'
require 'Definitions/animal/ButcheringUtil'

local Setup = {}

function Setup.hutchNear(player)
    local px, py, z = math.floor(player:getX()), math.floor(player:getY()), player:getSquare():getZ()
    -- The real hutch occupies a two by two footprint, including its slave objects.
    for radius = 2, 3 do
        for dx = -radius, radius do for dy = -radius, radius do
            if math.max(math.abs(dx), math.abs(dy)) == radius then
                local free = true
                for x = px + dx, px + dx + 1 do for y = py + dy - 1, py + dy do
                    local sq = getSquare(x, y, z)
                    if not sq or not sq:getFloor() or not sq:isFree(false)
                            or (x == px and y == py) then free = false end
                end end
                local sq = getSquare(px + dx, py + dy, z)
                if free and sq:DistToProper(player) <= 4 then
                    local def = HutchDefinitions.hutchs.hutchhen
                    return IsoHutch.new(sq, true, def.baseSprite, def, nil)
                end
            end
        end end
    end
    error('no loaded, free two by two hutch footprint within four tiles of startup spawn')
end

function Setup.hen(square)
    local breed = AnimalDefinitions.getDef('hen'):getBreedByName('rhodeisland')
    local hen = IsoAnimal.new(getCell(), square:getX(), square:getY(), square:getZ(), 'hen', breed)
    hen:setCurrentSquare(square)
    hen:setMaxSizeDebug()
    return hen
end

function Setup.corpse(square)
    local hen = Setup.hen(square)
    hen:setHealth(0)
    -- This is the engine death constructor used by native animal butchering code.
    local body = IsoDeadBody.new(hen, false)
    assert(body:getSquare() == square and body:getStaticMovingObjectIndex() >= 0,
        'engine did not add animal corpse to the ground')
    assert(body:isAnimal() and body:hasAnimalParts() and body:getModData().parts,
        'engine animal corpse has no native parts data')
    assert(body:getCarcassName() == 'henrhodeisland', 'unexpected native carcass definition')
    return body
end

function Setup.count(player, fullType)
    local count, items = 0, player:getInventory():getItems()
    for i = 0, items:size() - 1 do
        if items:get(i):getFullType() == fullType then count = count + 1 end
    end
    return count
end

return Setup
