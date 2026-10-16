-- Disposable CartTestArea save only; load explicitly from the cart lab launcher.
local config=assert(CartMotionConfig,'CartMotionConfig required')
assert(config.disposable==true,'CartMotionConfig.disposable must be true')
local supplied=assert(config.area,'CartMotionConfig.area required')
for _,name in ipairs({'x','y','z','minX','minY','size','margin'}) do
 local value=supplied[name]
 assert(type(value)=='number' and value==value and value~=math.huge and value~=-math.huge,'CartMotionConfig.area.'..name..' must be finite')
end
for _,name in ipairs({'z','minX','minY','size','margin'}) do assert(supplied[name]%1==0,'Area grid values must be integers') end
assert(supplied.z>0 and supplied.size>=8 and supplied.size<=96 and supplied.margin>=1 and supplied.margin*2<supplied.size,'Invalid disposable pad dimensions')
assert(supplied.x>=supplied.minX+supplied.margin and supplied.x<supplied.minX+supplied.size-supplied.margin and supplied.y>=supplied.minY+supplied.margin and supplied.y<supplied.minY+supplied.size-supplied.margin,'Spawn must be inside pad margin')
assert(type(supplied.floorSprite)=='string' and supplied.floorSprite~='','CartMotionConfig.area.floorSprite required')
CartTestArea = {
    x=supplied.x, y=supplied.y, z=supplied.z,
    minX=supplied.minX, minY=supplied.minY, size=supplied.size, margin=supplied.margin,
    floorSprite=supplied.floorSprite,
    sandbox={Zombies=6, EnableVehicles=false, VehicleStoryChance=1, ZoneStoryChance=1, SurvivorHouseChance=1},
}
local area = CartTestArea

local function fail(reason, x, y, z)
    error('[CART_TEST_AREA] ' .. reason .. ' at ' .. x .. ',' .. y .. ',' .. z, 0)
end

local function checkSquare(square, player, x, y, building)
    if not square then
        if building then return end
        fail('square not loaded', x, y, area.z)
    end
    local floor = square:getFloor()
    if floor and floor:getSpriteName() ~= area.floorSprite then fail('unexpected floor', x, y, area.z) end
    if not building and (not floor or not square:TreatAsSolidFloor()) then fail('missing solid floor', x, y, area.z) end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        if objects:get(i) ~= floor then fail('unexpected tile object', x, y, area.z) end
    end
    if square:getWorldObjects():size() > 0 or square:getStaticMovingObjects():size() > 0 then
        fail('ground item or corpse', x, y, area.z)
    end
    local moving = square:getMovingObjects()
    for i = 0, moving:size() - 1 do
        if moving:get(i) ~= player then fail('unexpected actor', x, y, area.z) end
    end
    if square:isVehicleIntersecting() then fail('vehicle intersects pad', x, y, area.z) end
    if not building and not square:isFree(false) then fail('blocked square', x, y, area.z) end
end

function area.contains(x, y, z)
    return z == area.z and x >= area.minX + area.margin and x < area.minX + area.size - area.margin
        and y >= area.minY + area.margin and y < area.minY + area.size - area.margin
end

function area.checkPosition(player)
    local x, y, z = player:getX(), player:getY(), player:getZ()
    if not area.contains(x, y, z) then fail('outside safe pad bounds', x, y, z) end
    checkSquare(getCell():getGridSquare(math.floor(x), math.floor(y), area.z), player, math.floor(x), math.floor(y))
    return true
end

function area.check(player)
    assert(area.ready, '[CART_TEST_AREA] call prepare() before testing')
    for x = area.minX, area.minX + area.size - 1 do
        for y = area.minY, area.minY + area.size - 1 do
            local square = getCell():getGridSquare(x, y, area.z)
            checkSquare(square, player, x, y)
            -- Check native collision in both directions, including diagonal edges.
            for dx = -1, 1 do
                for dy = -1, 1 do
                    if (dx ~= 0 or dy ~= 0) and x + dx >= area.minX and x + dx < area.minX + area.size
                        and y + dy >= area.minY and y + dy < area.minY + area.size
                        and square:testCollideAdjacent(nil, dx, dy, 0) then
                        fail('blocked pad edge', x, y, area.z)
                    end
                end
            end
        end
    end
    if player then area.checkPosition(player) end
    return true
end

function area.prepare()
    assert(getWorld():getWorld() == 'CartTestArea', '[CART_TEST_AREA] refusing to modify a non-test save')
    assert(not isClient() and not isServer(), '[CART_TEST_AREA] single-player test save required')
    local cell, chunks = getCell(), {}
    -- Validate the complete footprint before the first edit; never clear existing world objects.
    for x = area.minX, area.minX + area.size - 1 do
        for y = area.minY, area.minY + area.size - 1 do
            local chunk = cell:getChunkForGridSquare(x, y, 0)
            if not chunk or not cell:getGridSquare(x, y, 0) then fail('ground chunk not loaded', x, y, 0) end
            chunks[chunk] = true
            checkSquare(cell:getGridSquare(x, y, area.z), nil, x, y, true)
        end
    end
    for x = area.minX, area.minX + area.size - 1 do
        for y = area.minY, area.minY + area.size - 1 do
            local square = cell:getGridSquare(x, y, area.z) or cell:createNewGridSquare(x, y, area.z, true)
            if not square then fail('cannot create square', x, y, area.z) end
            cell:setCacheGridSquare(x, y, area.z, square)
            if not square:getFloor() then assert(square:addFloor(area.floorSprite), '[CART_TEST_AREA] floor creation failed') end
        end
    end
    -- New upper squares and addFloor's lower neighbours must also reach the cell cache.
    for chunk in pairs(chunks) do cell:setCacheChunk(chunk) end
    area.ready = true
    area.check()
    print('[CART_TEST_AREA] READY '..area.size..'x'..area.size..' floor=' .. area.floorSprite .. ' start=' .. area.x .. ',' .. area.y .. ',' .. area.z)
    return area
end

return area
