ItemType = {NORMAL = "normal", CLOTHING = "clothing", CONTAINER = "container", WEAPON = "weapon"}
ItemTag = {BREAK_WHEN_WET = "base:breakwhenwet"}
local function list(values)
    return {size = function() return #values end, get = function(_, i) return values[i + 1] end}
end
BloodClothingType = {getCoveredParts = function(types) return types.parts end}
InventoryItemFactory = {CreateItem = function() error("laundry tagging constructed an item") end}
instanceItem = function() error("laundry tagging instantiated a script") end
ZombRand = function() error("laundry tagging consumed random state") end
local bridgeCalls = 0
toolkitItemLaundryDirty = function(item)
    bridgeCalls = bridgeCalls + 1
    if item.unknown then return nil end
    return item.blood or item.dirt
end
local Laundry = dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/ItemLaundryTags.lua")
local function script(kind, options)
    options = options or {}
    local types = list({"Shirt"}); types.parts = list({"Torso_Upper", "Torso_Lower"})
    return {kind = kind, types = types, options = options,
        isItemType = function(self, expected) return self.kind == expected end,
        getBloodClothingType = function(self) return self.types end,
        isHidden = function(self) return self.options.hidden == true end,
        hasTag = function(self, tag) return tag == ItemTag.BREAK_WHEN_WET and self.options.breakWhenWet == true end,
        InstanceItem = function() error("laundry preview ran OnCreate") end}
end
local function physical(definition, blood, dirt)
    return {definition = definition, blood = blood == true, dirt = dirt == true,
        getScriptItem = function(self) return self.definition end,
        IsClothing = function(self) return self.definition.kind == ItemType.CLOTHING end,
        IsInventoryContainer = function(self) return self.definition.kind == ItemType.CONTAINER end,
        isHidden = function(self) return self.definition:isHidden() end,
        hasTag = function(self, tag) return self.definition:hasTag(tag) end,
        hasBlood = function() error("native hasBlood may initialize random visual values") end,
        hasDirt = function() error("native hasDirt may initialize random visual values") end,
        getVisual = function() error("laundry tagging initialized visual state") end,
        -- High aggregate fields and localized names cannot override visual stains.
        getDirtiness = function() return 100 end, getBloodLevel = function() return 100 end,
        getName = function() return "Dirty Bloody Shirt" end}
end
local function expect(definition, item, expected, states, managed)
    local actual, alternatives, owner = Laundry.read(definition, item)
    assert(actual == expected, "laundry current state differs")
    assert(owner == managed, "laundry managed/unknown classification differs")
    if states then
        assert(alternatives and #alternatives == 2 and alternatives[1] == false and alternatives[2] == true,
            "laundry preview must preserve clean and dirty alternatives")
    else assert(alternatives == nil, "laundry invented feasible script states") end
end
local shirt, bag = script(ItemType.CLOTHING), script(ItemType.CONTAINER)
for _, definition in ipairs({shirt, bag}) do
    expect(definition, nil, nil, true, true)
    for _, stains in ipairs({{false, false}, {true, false}, {false, true}, {true, true}}) do
        expect(definition, physical(definition, stains[1], stains[2]), stains[1] or stains[2], false, true)
    end
    local item = physical(definition)
    expect(nil, item, false, false, true)
    item.dirt = true; expect(nil, item, true, false, true)
    item.dirt = false; item.blood = true; expect(nil, item, true, false, true)
    item.blood = false; expect(nil, item, false, false, true)
    item.unknown = true; expect(definition, item, nil, false, true)
    item.unknown = false; item.dirt = true; expect(definition, item, true, false, true)
    local bridge = toolkitItemLaundryDirty; toolkitItemLaundryDirty = nil
    expect(definition, item, nil, false, true)
    toolkitItemLaundryDirty = bridge
    item.isHidden = nil; expect(definition, item, nil, false, true)
end
for _, definition in ipairs({script(ItemType.NORMAL), script(ItemType.WEAPON)}) do
    expect(definition, nil, nil, false, false)
    expect(definition, physical(definition, true, true), nil, false, false)
end
expect(nil, nil, nil, false, nil)
expect({}, nil, nil, false, nil)
for _, kind in ipairs({ItemType.CLOTHING, ItemType.CONTAINER}) do
    local hidden = script(kind, {hidden = true})
    expect(hidden, nil, false, false, true)
    expect(hidden, physical(hidden, true, true), false, false, true)
    local noCoverage = script(kind); noCoverage.types = nil
    expect(noCoverage, nil, false, false, true)
    noCoverage.types = list({}); expect(noCoverage, nil, false, false, true)
    noCoverage.types = list({"Shirt"}); expect(noCoverage, nil, false, false, true)
    noCoverage.types.parts = list({}); expect(noCoverage, nil, false, false, true)
    noCoverage.getBloodClothingType = nil; expect(noCoverage, nil, nil, false, true)
    local missing = script(kind); missing.isHidden = nil
    expect(missing, nil, nil, false, true)
    missing.isHidden = function() end; expect(missing, nil, nil, false, true)
end
local fragile = script(ItemType.CLOTHING, {breakWhenWet = true})
local beforeFragile = bridgeCalls
expect(fragile, nil, false, false, true)
expect(fragile, physical(fragile, true, true), false, false, true)
assert(bridgeCalls == beforeFragile, "non-washable clothing read physical stain state")
local missingTag = script(ItemType.CLOTHING); missingTag.hasTag = nil
expect(missingTag, nil, nil, false, true)
missingTag.hasTag = function() end; expect(missingTag, nil, nil, false, true)
local original = BloodClothingType; BloodClothingType = nil
expect(shirt, nil, nil, false, true)
BloodClothingType = original
local _, alternatives = Laundry.read(shirt)
alternatives[1] = true
expect(shirt, nil, nil, true, true)
-- Kahlua supplies pairs but does not expose Lua's next global.
local originalNext = next; next = nil
expect(shirt, physical(shirt, false, true), true, false, true)
expect(shirt, nil, nil, true, true)
next = originalNext

if NativeActionRoot then
    local function read(path)
        local file = assert(io.open(path)); local text = file:read("*a"); file:close(); return text
    end
    local generated = NativeActionRoot .. "/../scripts/generated/items/"
    local native = {}
    for _, name in ipairs({"clothing.txt", "container.txt"}) do
        for id, block in read(generated .. name):gmatch("item%s+([%w_]+)%s*(%b{})") do
            local kind = block:match("ItemType%s*=%s*base:([%w_]+)")
            local definition = script(kind, {hidden = block:match("Hidden%s*=%s*true") ~= nil,
                breakWhenWet = block:find("base:breakwhenwet", 1, true) ~= nil})
            local locations = {}
            for location in (block:match("BloodLocation%s*=%s*([^,]+)") or ""):gmatch("[%w_]+") do
                locations[#locations + 1] = location
            end
            definition.types = list(locations)
            -- Coverage mapping itself is native Java; these declarations verify
            -- nonempty vs absent BloodLocation without constructing any items.
            definition.types.parts = list(locations)
            native[id] = definition
        end
    end
    expect(assert(native.Shirt_FormalWhite), nil, nil, true, true)
    expect(assert(native.Bag_Schoolbag), nil, nil, true, true)
    expect(assert(native.Glasses), nil, false, false, true)
    local fragileCount = 0
    for _, definition in pairs(native) do
        if definition.options.breakWhenWet then
            fragileCount = fragileCount + 1
            expect(definition, nil, false, false, true)
        end
    end
    assert(fragileCount > 0, "native declarations no longer identify break-when-wet clothing")
    local wash = read(NativeActionRoot .. "/shared/TimedActions/ISWashClothing.lua")
    assert(wash:find('instanceof(item, "Clothing") or instanceof(item, "InventoryContainer")', 1, true)
        and wash:find('BloodClothingType.getCoveredParts(item:getBloodClothingType())', 1, true)
        and wash:find('item:setBlood(coveredParts:get(j), 0)', 1, true)
        and wash:find('item:setDirt(coveredParts:get(j), 0)', 1, true), "native wash stain model changed")
    print("native B42.21 laundry declarations and covered-part washing source checked")
else print("SKIP native laundry source checks (NativeActionRoot not supplied)") end
print("laundry tags passed: clothing/bags, native stain predicates, exclusions, unknown metadata and script alternatives")
