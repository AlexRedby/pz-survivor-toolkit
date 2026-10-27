-- Pure Lua coverage: indexed membership, rather than stale reverse links, owns floor identity.
local function equal(actual, expected, message)
    assert(actual == expected, (message or "resolver values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
require = function() end
PZSurvivorToolkit = {}
instanceof = function(object, class) return object and object.classes and object.classes[class] == true end
local resolver = dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/TVDeviceResolver.lua")
local function list(values)
    local result = {values = values or {}, gets = 0, sizes = 0}
    function result:size() self.sizes = self.sizes + 1; return #self.values end
    function result:get(index) self.gets = self.gets + 1; return self.values[index + 1] end
    return result
end
local function item(id, fullType)
    return {classes = {InventoryItem = true}, id = id, fullType = fullType,
        getID = function(self) return self.id end, getFullType = function(self) return self.fullType end}
end
local function world(object)
    return {classes = {IsoWorldInventoryObject = true}, item = object, getItem = function(self) return self.item end}
end
local function square(worlds, objects)
    return {worlds = worlds or list(), objects = objects or list(),
        getWorldObjects = function(self) return self.worlds end, getObjects = function(self) return self.objects end}
end
local function fixture(path)
    local f = {item = item(7, "Base.RadioRed"), modData = {RadioItemID = 7}}
    f.world = world(f.item)
    f.list = list({{}, {}, f.world})
    f.square = square()
    f.square[path or "worlds"] = f.list
    f.data = {getDeviceName = function() return "personal radio" end}
    f.device = {classes = {IsoObject = true, IsoRadio = true},
        getModData = function() return f.modData end, getSquare = function() return f.square end,
        getProperties = function() return {get = function() end} end, getDeviceData = function() return f.data end}
    -- Deliberately stale after removal: these links must never establish live membership.
    f.item.getWorldItem = function() return f.world end
    f.world.getSquare = function() return f.square end
    return f
end
local count = 0
local function test(name, body) body(); count = count + 1; print("PASS TV resolver " .. name) end

test("both lists scan once, then validate constant indexed membership and live full type", function()
    for _, path in ipairs({"worlds", "objects"}) do
        local f = fixture(path)
        for i = 1, 128 do table.insert(f.list.values, 1, {}) end
        local fullType, binding = resolver.fullType(f.device)
        equal(fullType, "Base.RadioRed"); assert(binding)
        equal(f.list.gets, #f.list.values, "initial lookup must find the trailing item")
        local gets = f.list.gets
        for _ = 1, 100 do
            local nextType, nextBinding = resolver.fullType(f.device, binding)
            equal(nextType, "Base.RadioRed"); assert(nextBinding)
            binding = nextBinding
        end
        equal(f.list.gets - gets, 100, "stable lookup must read exactly one indexed member")
        f.item.fullType = "Base.RadioBlack"
        equal(resolver.fullType(f.device, binding), "Base.RadioBlack", "cache stores identity, not a full type")
    end
end)

test("insert, remove and reorder invalidate an index and resolve the live list", function()
    for _, mutation in ipairs({"insert", "remove", "reorder"}) do
        local f = fixture()
        local _, binding = resolver.fullType(f.device)
        if mutation == "insert" then table.insert(f.list.values, 1, {})
        elseif mutation == "remove" then table.remove(f.list.values, 1)
        else f.list.values[1], f.list.values[3] = f.list.values[3], f.list.values[1] end
        local fullType, refreshed = resolver.fullType(f.device, binding)
        equal(fullType, "Base.RadioRed"); assert(refreshed)
        local gets = f.list.gets
        equal(resolver.fullType(f.device, refreshed), fullType)
        equal(f.list.gets - gets, 1, "fresh index must become the new fast path")
    end
end)

test("same-ID wrapper, item and list replacements cannot reuse stale identity", function()
    for _, replacement in ipairs({"wrapper", "item", "list"}) do
        local f = fixture()
        local _, binding = resolver.fullType(f.device)
        local newItem = item(7, "Base.RadioBlack")
        if replacement == "wrapper" then f.list.values[3] = world(newItem)
        elseif replacement == "item" then f.world.item = newItem
        else f.square.worlds = list({world(newItem)}) end
        local fullType, refreshed = resolver.fullType(f.device, binding)
        equal(fullType, "Base.RadioBlack"); assert(refreshed)
        equal(resolver.fullType(f.device, refreshed), "Base.RadioBlack")
    end
end)

test("pickup rejects stale square and world reverse links, then retries arrival", function()
    local f = fixture()
    local _, binding = resolver.fullType(f.device)
    table.remove(f.list.values, 3)
    local fullType, missing = resolver.fullType(f.device, binding)
    equal(fullType, "Base.RadioMakeShift"); equal(missing, nil)
    f.list.values[#f.list.values + 1] = world(item(7, "Base.RadioBlack"))
    local arrived, fresh = resolver.fullType(f.device, missing)
    equal(arrived, "Base.RadioBlack"); assert(fresh)
end)

test("cached item's current ID must still match the device's RadioItemID", function()
    local f = fixture()
    local _, binding = resolver.fullType(f.device)
    f.item.id = 8
    local fullType, stale = resolver.fullType(f.device, binding)
    equal(fullType, "Base.RadioMakeShift"); equal(stale, nil)
    f.list.values[#f.list.values + 1] = world(item(7, "Base.RadioBlack"))
    equal(resolver.fullType(f.device, stale), "Base.RadioBlack")
end)

test("square, RadioItemID and device changes discard the previous binding", function()
    for _, change in ipairs({"square", "id", "device"}) do
        local f = fixture()
        local _, binding = resolver.fullType(f.device)
        local target = f.device
        if change == "square" then f.square = square(list({world(item(7, "Base.RadioBlack"))}))
        elseif change == "id" then
            f.modData.RadioItemID = 9
            f.list.values[#f.list.values + 1] = world(item(9, "Base.RadioBlack"))
        else target = fixture().device; target.getModData = function() return {} end end
        local fullType, fresh = resolver.fullType(target, binding)
        equal(fullType, change == "device" and "Base.RadioMakeShift" or "Base.RadioBlack")
        if change == "device" then equal(fresh, nil) else assert(fresh) end
    end
end)

test("fallback and misses are never cached and both list paths remain discoverable", function()
    local f = fixture()
    f.square.worlds = nil
    local fullType, binding = resolver.fullType(f.device)
    equal(fullType, "Base.RadioMakeShift"); equal(binding, nil)
    f.square.objects.values[1] = f.world
    fullType, binding = resolver.fullType(f.device, binding)
    equal(fullType, "Base.RadioRed"); assert(binding)
    f.square.objects.values = {}
    f.square.worlds = list({world(item(7, "Base.RadioBlack"))})
    equal(resolver.fullType(f.device, binding), "Base.RadioBlack")
end)

test("held, furniture and vehicle paths retain identity without floor bindings", function()
    local held = item(7, "Base.TvAntique")
    local car = {classes = {VehiclePart = true}, getInventoryItem = function() return held end}
    local furniture = fixture().device
    furniture.getModData = function() return {} end
    furniture.getProperties = function() return {get = function() return "TvWideScreen" end} end
    for _, case in ipairs({{held, "Base.TvAntique"}, {car, "Base.TvAntique"}, {furniture, "Base.TvWideScreen"}}) do
        local fullType, binding = resolver.fullType(case[1], {})
        equal(fullType, case[2]); equal(binding, nil)
    end
    equal(resolver.fullType(nil), nil)
end)

test("EN/RU callbacks restore translation scope, preserve results and expose current data", function()
    for _, language in ipairs({"EN", "RU"}) do
        getItemNameFromFullType = function(fullType) return language .. ":" .. fullType end
        local translated = getItemNameFromFullType
        local f = fixture()
        local result, binding, data = resolver.call(f.device, nil, function(argument)
            equal(argument, "argument"); equal(getItemNameFromFullType("Base.RadioRed"), "personal radio")
            return "result", "discarded result"
        end, "argument")
        equal(result, "result"); assert(binding); equal(data, f.data)
        equal(getItemNameFromFullType, translated)
        assert(not pcall(resolver.call, f.device, binding, function() error("callback failed") end))
        equal(getItemNameFromFullType, translated, "throwing callbacks must restore translations")
        local replacement = {getDeviceName = function() return "replacement data" end}
        f.data = replacement
        local _, _, currentData = resolver.call(f.device, binding, function()
            equal(getItemNameFromFullType("Base.RadioRed"), "replacement data")
        end)
        equal(currentData, replacement)
    end
end)

test("unresolved devices and missing data delegate callbacks without changing translations", function()
    local translated = getItemNameFromFullType
    local f = fixture()
    f.data = nil
    local result, _, data = resolver.call(f.device, nil, function()
        equal(getItemNameFromFullType, translated)
        return "no data"
    end)
    equal(result, "no data"); equal(data, nil)
    equal(resolver.call(nil, nil, function(value) return value end, "no device"), "no device")
    equal(getItemNameFromFullType, translated)
end)

print("Passed " .. count .. " TV device resolver tests.")
