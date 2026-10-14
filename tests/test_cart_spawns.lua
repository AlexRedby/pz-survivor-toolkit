local gate = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/server/000ToolkitCartSpawnCompatibility.lua"
local nativeRequire = require
local function event()
    local e = {handlers = {}}
    function e.Add(fn) e.handlers[#e.handlers + 1] = fn end
    function e.Remove(fn)
        for i = #e.handlers, 1, -1 do if e.handlers[i] == fn then table.remove(e.handlers, i) end end
    end
    function e.fire(...)
        for _, fn in ipairs(e.handlers) do fn(...) end
    end
    return e
end
isClient = function() return false end
isServer = function() return false end
getActivatedMods = function() return {contains = function() return false end} end
require = function() error("inactive spawn adapter loaded upstream") end
dofile(gate)
isClient = function() return true end
getActivatedMods = function() return {contains = function() return true end} end
dofile(gate)
print("PASS cart spawning: inactive without SaucedCarts and on pure MP clients")
if not SaucedCartsSource then
    require = nativeRequire
    print("SKIP cart generation requires installed SaucedCarts source")
    return
end

local shopping = "SaucedCarts.ShoppingCart"
local wood, metal = "SaucedWheelbarrow.WheelbarrowWood", "SaucedWheelbarrow.WheelbarrowMetal"
local function list(items)
    return {size = function() return #items end, get = function(_, i) return items[i + 1] end}
end
local function has(entries, kind)
    for _, entry in ipairs(entries or {}) do if entry.type == kind then return true end end
    return false
end
local function setup(mode, saved)
    isClient = function() return mode == "host" end
    isServer = function() return mode ~= "sp" end
    getActivatedMods = function() return {contains = function(_, id) return id == "SaucedCarts" end} end
    Events = {LoadChunk = event(), OnTick = event(), OnLoadedMapZones = event(), OnGameEnd = event()}
    local w = {created = {}, buildings = {}, data = saved or {}}
    ModData = {getOrCreate = function() return w.data end}
    SandboxVars = {SaucedCarts = {EnableMod = true, SpawnRate = 100, MaxCartsPerBuilding = 1, OutdoorSpawnDensity = 4}}
    IsoDirections = {N = 1, E = 2, S = 3, W = 4}
    ZombRand = function() return 0 end
    SaucedCarts = {debug = function() end, log = function() end, error = error,
        Config = {MAX_SPAWNS_PER_TICK = 100, SPAWN_TICK_INTERVAL = 1, MAX_SPAWN_QUEUE_SIZE = 500},
        applyMultipliers = function() end,
        CartLoot = {contextForRoom = function() return "tools" end,
            sandboxLootOptions = function() return {} end, decideCartLoad = function() return {tier = "empty"} end}}
    function w.square(x, y)
        local sq = {getX = function() return x end, getY = function() return y end, getZ = function() return 0 end,
            isFree = function() return true end, isBlockedTo = function() return false end,
            getWorldObjects = function() return list({}) end}
        function sq:getAdjacentSquare() return self end
        function sq:AddWorldInventoryItem(kind, _, _, _, _, sync)
            assert(sync == true, "native single-transmit spawn path changed")
            w.created[#w.created + 1] = {type = kind, x = x, y = y}
            return {getFullType = function() return kind end, getModData = function() return {} end,
                setStaticModel = function() end, setWorldStaticModel = function() end}
        end
        return sq
    end
    function w.chunk(x, y)
        return {wx = x, wy = y, getGridSquare = function(_, lx, ly) return w.square(x * 8 + lx, y * 8 + ly) end}
    end
    function w.building(x, y, names, residential)
        local rooms = {}
        for _, name in ipairs(names) do
            rooms[#rooms + 1] = {getName = function() return name end, getFreeSquare = function() return w.square(x, y) end}
        end
        local def = {getX = function() return x end, getY = function() return y end,
            getW = function() return 8 end, getH = function() return 8 end,
            getRooms = function() return list(rooms) end, isResidential = function() return residential == true end,
            isShop = function() return names[1] == "grocery" end}
        w.buildings[#w.buildings + 1] = def
        return def
    end
    getWorld = function() return {getMetaGrid = function() return {getBuildings = function() return list(w.buildings) end} end} end
    getVehicleZoneAt = function() return {getType = function() return "parkingstall" end} end
    local loaded = {}
    require = function(name)
        if loaded[name] then return loaded[name] end
        if name == "SaucedCarts/WorldSpawning" then
            loaded[name] = dofile(SaucedCartsSource .. "/../../server/SaucedCarts/WorldSpawning.lua")
            return loaded[name]
        end
        return true
    end
    dofile(SaucedCartsSource .. "/CartData.lua")
    dofile(SaucedCartsSource .. "/SpawnLocations.lua")
    if WheelbarrowSource then
        dofile(WheelbarrowSource)
    else
        for _, kind in ipairs({wood, metal}) do
            assert(SaucedCarts.registerCart(kind, {name = kind, spawnRooms = {
                {room = "shed", chance = 7}, {room = "farmstorage", chance = 25},
                {room = "gardenstore", chance = 25}, {room = "toolstore", chance = 15}, {room = "garagestorage", chance = 7}}}))
        end
    end
    SaucedCarts.resetOutdoorCartPool()
    w.upstreamPool = SaucedCarts.getOutdoorCartPool()
    assert(has(SaucedCarts.getSpawnEntriesForRoom("shed"), shopping)
        and has(SaucedCarts.getSpawnEntriesForRoom("farmstorage"), shopping), "upstream rural baseline changed")
    w.originalEntries = SaucedCarts.SpawnLocations.shed
    dofile(gate)
    w.spawning = SaucedCarts.WorldSpawning
    function w.run(x, y)
        Events.LoadChunk.fire(w.chunk(x, y)); Events.OnTick.fire()
    end
    return w
end

for _, mode in ipairs({"sp", "host", "server"}) do
    local w = setup(mode)
    for _, name in ipairs({"shed", "farmstorage", "garagestorage"}) do
        local entries = SaucedCarts.getSpawnEntriesForRoom(name)
        assert(not has(entries, shopping) and has(entries, wood) and has(entries, metal), name)
    end
    for _, name in ipairs({"grocery", "gigamart", "warehouse", "grocerystorage", "storageunit"}) do
        assert(has(SaucedCarts.getSpawnEntriesForRoom(name), shopping), name)
    end
    assert(SaucedCarts.getSpawnEntriesForRoom("lobby") == nil and SaucedCarts.getSpawnEntriesForRoom("storage") == nil)
    assert(has(w.originalEntries, shopping) and #w.upstreamPool == 3, "upstream tables were mutated")
    w.building(80, 80, {"shed"})
    w.building(240, 80, {"farmstorage"})
    w.building(400, 80, {"grocery"})
    w.building(560, 80, {"warehouse"})
    w.building(720, 80, {"garagestorage", "bedroom"}, true)
    -- Let LoadChunk build the real upstream index lazily, before its outdoor pass.
    for _, x in ipairs({10, 30, 50, 70}) do w.run(x, 10) end
    local counts = {[shopping] = 0, [wood] = 0, [metal] = 0}
    for _, item in ipairs(w.created) do
        counts[item.type] = counts[item.type] + 1
        if item.x < 320 then assert(item.type == wood or item.type == metal, "shopping cart appeared on farm/shed")
        else assert(item.type == shopping, "non-retail cart appeared at grocery/warehouse") end
    end
    assert(counts[shopping] > 0 and counts[wood] + counts[metal] > 0)
    assert(not w.spawning._candidateBuildings["720,80"], "residential filter bypassed")
    local before = #w.created
    w.run(51, 10) -- next-door parking chunk, outside grocery building
    assert(#w.created > before and w.created[#w.created].type == shopping, "shop parking lost shopping carts")
    before = #w.created
    w.run(31, 10) -- next-door parking chunk, outside farm building
    assert(#w.created > before and w.created[#w.created].type ~= shopping, "farm parking has no wheelbarrow")
    before = #w.created
    w.run(54, 10) -- farther than the three-chunk retail margin
    w.run(200, 200) -- isolated residential driveway
    assert(#w.created == before, "unrelated parking acquired known carts")
    w.run(51, 10); w.run(31, 10); w.run(10, 10)
    assert(#w.created == before, "chunk reload duplicated carts")
    assert(SaucedCarts.getOutdoorCartPool() == w.upstreamPool and #w.upstreamPool == 3, "outdoor context/cache leaked")
    local entries, handler = SaucedCarts.getSpawnEntriesForRoom, Events.LoadChunk.handlers[1]
    dofile(gate)
    assert(SaucedCarts.getSpawnEntriesForRoom == entries and Events.LoadChunk.handlers[1] == handler
        and #Events.LoadChunk.handlers == 1, "adapter registered twice")
    local second = setup(mode)
    second.building(80, 80, {"farmstorage"})
    SandboxVars.SaucedCarts.OutdoorSpawnDensity = 1
    ZombRand = function(n) return n == 50 and 49 or 0 end
    second.run(10, 10)
    assert(#second.created == 1 and second.created[1].type == metal, "metal wheelbarrow lost rural spawn")
    print("PASS cart spawning: actual upstream " .. mode .. " indoor policy, matching parking, residential guards, dedup and idempotence")
end

local w = setup("server")
w.building(80, 80, {"grocery"})
local rng = ZombRand
ZombRand = function() error("spawn fixture failure") end
assert(not pcall(function() w.run(10, 10) end), "upstream failure was swallowed")
ZombRand = rng
assert(SaucedCarts.getOutdoorCartPool() == w.upstreamPool, "failed handler leaked chunk context")
w.run(10, 10)
local before = #w.created
local saved = w.data
Events.OnGameEnd.fire()
w = setup("server", saved)
w.building(80, 80, {"grocery"})
w.run(10, 10)
assert(#w.created == 0 and before > 0, "existing save decisions were erased")
SaucedCarts.CartTypes["Other.HandTruck"] = {outdoorWeight = 100}
SaucedCarts.resetOutdoorCartPool()
w.run(200, 200)
assert(#w.created > 0 and w.created[1].type == "Other.HandTruck", "unknown addon distribution changed")
print("PASS cart spawning: error cleanup, saved decisions and unrelated addon pool preserved")
require = nativeRequire
