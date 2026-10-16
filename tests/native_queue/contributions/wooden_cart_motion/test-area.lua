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
    obstacles={}, obstacleEdges={},
    sandbox={Zombies=6, EnableVehicles=false, VehicleStoryChance=1, ZoneStoryChance=1, SurvivorHouseChance=1},
}
local area = CartTestArea

local function edge(x, y, dx, dy)
    return area.obstacleEdges[x..','..y..','..dx..','..dy] == true
end

local function expectedCollision(x, y, dx, dy)
    if dx == 0 or dy == 0 then return edge(x, y, dx, dy) end
    return edge(x,y,dx,0) or edge(x,y,0,dy) or edge(x+dx,y,0,dy) or edge(x,y+dy,dx,0)
end

local function fail(reason, x, y, z)
    error('[CART_TEST_AREA] ' .. reason .. ' at ' .. x .. ',' .. y .. ',' .. z, 0)
end

local function contains(objects, object)
    for i = 0, objects:size() - 1 do if objects:get(i) == object then return true end end
    return false
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
        local object = objects:get(i)
        if object ~= floor then
            local owned = area.obstacles and area.obstacles[object]
            if not owned or owned.x ~= x or owned.y ~= y or owned.z ~= area.z
                or object:getSquare() ~= square or object:getSpriteName() ~= owned.sprite then
                fail('unexpected tile object', x, y, area.z)
            end
        end
    end
    local special = square:getSpecialObjects()
    for i = 0, special:size() - 1 do
        local object = special:get(i)
        local owned = area.obstacles and area.obstacles[object]
        if not owned or owned.kind ~= 'door' or not contains(objects, object) then
            fail('unexpected special object', x, y, area.z)
        end
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
    local doors = false
    for object, owned in pairs(area.obstacles or {}) do
        if owned.kind == 'door' then
            doors = true
            local square = getCell():getGridSquare(owned.x, owned.y, owned.z)
            if not square or not contains(square:getObjects(), object) or not contains(square:getSpecialObjects(), object) then
                fail('missing fixture door', owned.x, owned.y, owned.z)
            end
            local opposite = getCell():getGridSquare(owned.x + (owned.axis == 'W' and -1 or 0), owned.y + (owned.axis == 'N' and -1 or 0), owned.z)
            local blocked = not owned.open
            -- This is the same closed/barricaded-door predicate used by native footprint queries.
            if object:isOpen() ~= owned.open or object:isBlocked() ~= blocked or not opposite
                or square:isDoorBlockedTo(opposite) ~= blocked or opposite:isDoorBlockedTo(square) ~= blocked then
                fail('fixture door state disagrees', owned.x, owned.y, owned.z)
            end
        end
    end
    for x = area.minX, area.minX + area.size - 1 do
        for y = area.minY, area.minY + area.size - 1 do
            local square = getCell():getGridSquare(x, y, area.z)
            checkSquare(square, player, x, y)
            -- Check native collision in both directions, including diagonal edges.
            for dx = -1, 1 do
                for dy = -1, 1 do
                    if (dx ~= 0 or dy ~= 0) and x + dx >= area.minX and x + dx < area.minX + area.size
                        and y + dy >= area.minY and y + dy < area.minY + area.size
                        then
                        local expected = expectedCollision(x, y, dx, dy)
                        local actual = square:testCollideAdjacent(nil, dx, dy, 0)
                        -- With a nil actor B42 skips special objects; query them without mutating player collision state.
                        if doors and not actual then
                            actual = square:testCollideSpecialObjects(getCell():getGridSquare(x + dx, y + dy, area.z)) ~= nil
                        end
                        if actual ~= expected then
                            fail(expected and 'missing fixture collision edge' or 'blocked pad edge', x, y, area.z)
                        end
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
