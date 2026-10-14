if isClient() and not isServer() or not getActivatedMods():contains("SaucedCarts") then return end

local spawning = require "SaucedCarts/WorldSpawning"
local carts = SaucedCarts
if carts._toolkitSpawnPolicy then return end
if not spawning._onLoadChunk or not spawning._candidateBuildings or not spawning._chunkBuildingIndex then
    print("[PZ Survivor Toolkit] Cart spawn adapter unavailable; keeping upstream distribution.")
    return
end

local shopping = "SaucedCarts.ShoppingCart"
local wheelbarrows = {
    ["SaucedWheelbarrow.WheelbarrowWood"] = true,
    ["SaucedWheelbarrow.WheelbarrowMetal"] = true,
}
local shoppingRooms = {}
for _, name in ipairs({
    "gigamart", "grocery", "departmentstore", "grocerystorage", "warehouse", "storageunit",
    "departmentstorage", "producestorage", "housewarestore", "toolstore", "gardenstore",
    "furniturestore", "furniturestorage", "outdoorsupply", "carsupply", "generalstore",
    "electronicstore", "giftstore", "liquorstore", "petstore", "clothingstorage",
    "generalstorestorage", "camping", "campingstorage", "giftstorage", "outdoorsupply_storage",
    "clothingstore", "sportstore", "bookstore", "conveniencestore", "cornerstore", "pawnshop",
    "toystore", "pharmacy", "carsupplysport", "ww_toolstore", "ww_generalstore", "barbecuestore",
    "paintershop", "gunstore", "plazastore1", "leatherclothesstore", "baseballstore", "golfstore",
    "gasstore", "gas2go", "zippeestore", "artstore", "shoestore", "camerastore", "candystore",
    "comicstore", "musicstore", "knifestore", "tobaccostore", "toolstorestorage", "toystorestorage",
    "pharmacystorage", "electronicsstorage", "gunstorestorage", "sportstorage", "candystorage",
    "gasstorage", "loggingwarehouse", "cabinetshipping", "dogfoodshipping", "golfshipping",
    "jerkyshipping", "knifeshipping", "radioshipping",
}) do shoppingRooms[name] = true end

local entriesForRoom = carts.getSpawnEntriesForRoom
function carts.getSpawnEntriesForRoom(name)
    local entries = entriesForRoom(name)
    if not entries or shoppingRooms[name] then return entries end
    local filtered = {}
    for _, entry in ipairs(entries) do
        if entry.type ~= shopping then filtered[#filtered + 1] = entry end
    end
    return #filtered > 0 and filtered or nil
end

local activeChunk
local outdoorPool = carts.getOutdoorCartPool
function carts.getOutdoorCartPool()
    local pool = outdoorPool()
    if not activeChunk then return pool end
    local square = activeChunk:getGridSquare(0, 0, 0)
    if not square then return {} end
    local cx, cy = math.floor(square:getX() / 8), math.floor(square:getY() / 8)
    local nearby = {}
    -- Reuse the upstream building index; three chunks also cover adjacent parking lots.
    for x = cx - 3, cx + 3 do
        for y = cy - 3, cy + 3 do
            for _, key in ipairs(spawning._chunkBuildingIndex[x .. "," .. y] or {}) do
                for _, entry in ipairs(spawning._candidateBuildings[key].entries) do
                    nearby[entry.type] = true
                end
            end
        end
    end
    local filtered = {}
    for _, entry in ipairs(pool) do
        if entry.type ~= shopping and not wheelbarrows[entry.type] or nearby[entry.type] then
            filtered[#filtered + 1] = entry
        end
    end
    return filtered
end

local loadChunk = spawning._onLoadChunk
local function loadWithContext(chunk)
    local previous = activeChunk
    activeChunk = chunk
    local ok, result = pcall(loadChunk, chunk)
    activeChunk = previous
    if not ok then error(result) end
    return result
end
Events.LoadChunk.Remove(loadChunk)
Events.LoadChunk.Add(loadWithContext)
spawning._onLoadChunk = loadWithContext
carts._toolkitSpawnPolicy = true
