local function list(items)
    return {size = function() return #items end, get = function(_, i) return items[i + 1] end}
end
local squares, loaded, edits, world = {}, true, 0, 'CartTestArea'
local function key(x, y, z) return x .. ',' .. y .. ',' .. z end
local function square()
    local sq = {objects = {}, moving = {}, static = {}, world = {}}
    function sq:getFloor() return self.floor end
    function sq:getObjects() return list(self.objects) end
    function sq:getMovingObjects() return list(self.moving) end
    function sq:getStaticMovingObjects() return list(self.static) end
    function sq:getWorldObjects() return list(self.world) end
    function sq:TreatAsSolidFloor() return self.floor ~= nil and not self.hole end
    function sq:isVehicleIntersecting() return self.vehicle == true end
    function sq:isFree() return not self.blocked end
    function sq:testCollideAdjacent() return self.edge == true end
    function sq:addFloor(sprite)
        self.floor = {getSpriteName = function() return sprite end}
        self.objects = {self.floor}; edits = edits + 1
        return self.floor
    end
    return sq
end
local chunk = {}
local cell = {}
function cell:getGridSquare(x, y, z)
    if z == 0 then return loaded and {} or nil end
    return squares[key(x, y, z)]
end
function cell:getChunkForGridSquare() return loaded and chunk or nil end
function cell:createNewGridSquare(x, y, z)
    local sq = square(); squares[key(x, y, z)] = sq
    return sq
end
function cell:setCacheGridSquare(x, y, z, sq) assert(squares[key(x, y, z)] == sq) end
function cell:setCacheChunk(value) assert(value == chunk) end
getCell = function() return cell end
getWorld = function() return {getWorld = function() return world end} end
isClient = function() return false end
isServer = function() return false end
CartMotionConfig = {disposable=true, area={x=3.5,y=3.5,z=7,minX=0,minY=0,size=8,margin=2,floorSprite='carpentry_02_57'}}
local area = dofile(ProjectRoot .. '/tests/native_queue/contributions/wooden_cart_motion/test-area.lua')
local player = {x = area.x, y = area.y, z = area.z}
function player:getX() return self.x end
function player:getY() return self.y end
function player:getZ() return self.z end
local function rejects(fn, reason)
    local ok, err = pcall(fn)
    assert(not ok and tostring(err):find(reason, 1, true), tostring(err))
end
world = 'RealSave'
rejects(area.prepare, 'non-test save')
world = 'CartTestArea'; loaded = false
rejects(area.prepare, 'ground chunk not loaded')
assert(edits == 0, 'preflight edited an invalid footprint')
loaded = true
local foreign = cell:createNewGridSquare(area.minX + area.size - 1, area.minY + area.size - 1, area.z)
foreign.objects = {{}}
rejects(area.prepare, 'unexpected tile object')
assert(edits == 0, 'preflight edited before finding the final obstacle')
foreign.objects = {}
area.prepare()
assert(edits == area.size * area.size and area.check(player))
local here = cell:getGridSquare(math.floor(area.x), math.floor(area.y), area.z)
here.moving = {player}
assert(area.check(player), 'player rejected himself')
here.hole = true
rejects(function() area.checkPosition(player) end, 'missing solid floor')
here.hole = false; here.objects[#here.objects + 1] = {}
rejects(function() area.check(player) end, 'unexpected tile object')
table.remove(here.objects); here.vehicle = true
rejects(function() area.checkPosition(player) end, 'vehicle intersects pad')
here.vehicle = false; here.moving[2] = {}
rejects(function() area.checkPosition(player) end, 'unexpected actor')
here.moving[2] = nil; here.edge = true
rejects(function() area.check(player) end, 'blocked pad edge')
here.edge = false; player.x = area.minX + 1.9
rejects(function() area.checkPosition(player) end, 'outside safe pad bounds')
player.x = area.x; player.z = 0
rejects(function() area.checkPosition(player) end, 'outside safe pad bounds')
print('PASS cart test area: save/load preflight, complete flat pad, holes, objects, vehicles, actors, edges, bounds')
