ItemTag = {SHARPENABLE = "base:sharpenable"}
Attribute = {Sharpness = "Sharpness"}
ComponentType = {Attributes = "Attributes"}
InventoryItemFactory = {CreateItem = function() error("sharpening tagging constructed an item") end}
instanceItem = function() error("sharpening preview instantiated a script") end
ZombRand = function() error("sharpening tagging consumed random state") end
local Sharpening = dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/ItemSharpeningTags.lua")
local function attributes(sharpness)
    return {getAttribute = function(_, id)
        assert(id == Attribute.Sharpness, "reader requested an unrelated attribute")
        if sharpness == nil then return nil end
        return {getFloatValue = function() return sharpness end}
    end}
end
local function script(tagged, sharpness)
    return {hasTag = function(_, id) return id == ItemTag.SHARPENABLE and tagged end,
        getComponentScriptFor = function(_, id)
            assert(id == ComponentType.Attributes)
            if sharpness == false then return nil end
            return {getTemplateContainer = function() return attributes(sharpness) end}
        end,
        InstanceItem = function() error("sharpening preview ran OnCreate") end}
end
local function physical(definition, sharpness, maximum, broken)
    return {getScriptItem = function() return definition end,
        hasTag = function(_, id) return definition:hasTag(id) end,
        isBroken = function() return broken == true end,
        isFavorite = function() return true end,
        getAttributes = function() return attributes(sharpness) end,
        getMaxSharpness = function() return maximum end,
        getSharpness = function() error("native getSharpness can mutate the item") end,
        isSharpenable = function() error("native isSharpenable calls mutating getSharpness") end,
        isDull = function() error("dull threshold must not decide sharpening eligibility") end,
        setSharpness = function() error("tagging changed sharpness") end}
end
local function expect(definition, item, current, variable)
    local actual, possible = Sharpening.read(definition, item)
    assert(actual == current, "sharpening current state differs")
    if variable then
        assert(possible and #possible == 2 and possible[1] == false and possible[2] == true,
            "script preview must preserve both current sharpness states")
    else assert(possible == nil, "reader invented feasible script states") end
end
local blade, untagged, noAttribute = script(true, 1), script(false, 1), script(true)
expect(blade, nil, nil, true)
for _, sharpness in ipairs({0, 0.1, 1 / 3, 0.5, 0.99}) do
    expect(blade, physical(blade, sharpness, 1), true)
end
for _, sharpness in ipairs({1, 1.1}) do expect(blade, physical(blade, sharpness, 1), false) end
-- Overall/head condition changes native maximum; full sharpness is relative to
-- that maximum, including a broken head's zero maximum.
expect(blade, physical(blade, 0.49, 0.5), true)
expect(blade, physical(blade, 0.5, 0.5), false)
expect(blade, physical(blade, 0, 0), false)
-- Native getSharpness only clamps when raw > max, then setSharpness also
-- clamps to [0,1]. Compare a matrix including abnormal imported attributes.
for _, maximum in ipairs({-1, 0, 0.2, 1, 2}) do
    for _, raw in ipairs({-2, -1, 0, 0.1, 0.2, 0.8, 1, 1.5, 2, 3}) do
        local native = raw
        if native > maximum then native = math.max(0, math.min(1, maximum)) end
        expect(blade, physical(blade, raw, maximum), native < maximum)
    end
end
expect(blade, physical(blade, 0.2, 1, true), false)
expect(blade, physical(blade, nil, 1), false)
expect(nil, physical(blade, 0.9, 1), true)
expect(untagged, nil, false)
expect(untagged, physical(untagged, 0, 1), false)
expect(noAttribute, nil, false)
expect(script(true, false), nil, false)
expect(nil, nil, nil)
expect({}, nil, nil)

for _, method in ipairs({"isBroken", "getAttributes", "getMaxSharpness"}) do
    local item = physical(blade, 0.1, 1); item[method] = nil
    expect(blade, item, nil)
end
local item = physical(blade, 0.1, 1)
item.isBroken = function() end; expect(blade, item, nil)
item = physical(blade, 0.1, 1); item.getAttributes = function() return nil end
expect(blade, item, false)
item.getAttributes = function() return {} end; expect(blade, item, nil)
item.getAttributes = function() return {getAttribute = function() return {} end} end
expect(blade, item, nil)
for _, value in ipairs({"missing", 0 / 0}) do
    expect(blade, physical(blade, value, 1), nil)
    expect(blade, physical(blade, 0.1, value), nil)
end
local missing = script(true, 1); missing.getComponentScriptFor = nil
expect(missing, nil, nil)
missing.getComponentScriptFor = function() return {} end; expect(missing, nil, nil)
missing.getComponentScriptFor = function() return {getTemplateContainer = function() end} end
expect(missing, nil, nil)
missing.getComponentScriptFor = function() return {getTemplateContainer = function() return {} end} end
expect(missing, nil, nil)
local original = Attribute; Attribute = nil
expect(blade, nil, nil); expect(blade, physical(blade, 0.1, 1), nil)
Attribute = original
original = ComponentType; ComponentType = nil; expect(blade, nil, nil); ComponentType = original
original = ItemTag; ItemTag = nil; expect(blade, nil, nil); ItemTag = original
local _, possible = Sharpening.read(blade); possible[1] = true
expect(blade, nil, nil, true)
local originalNext = next; next = nil
expect(blade, nil, nil, true); expect(blade, physical(blade, 0.8, 1), true)
next = originalNext

if NativeActionRoot then
    local function read(path)
        local source = assert(io.open(path)); local text = source:read("*a"); source:close(); return text
    end
    local generated = NativeActionRoot .. "/../scripts/generated/"
    local native = {}
    for _, name in ipairs({"weapon.txt", "normal.txt"}) do
        for id, block in read(generated .. "items/" .. name):gmatch("item%s+([%w_]+)%s*(%b{})") do
            local tagged = (block:match("Tags%s*=%s*([^,]+)") or ""):find("base:sharpenable", 1, true) ~= nil
            -- Native Item.Load converts the top-level Sharpness declaration
            -- into its Attributes component template.
            native[id] = script(tagged, tonumber(block:match("Sharpness%s*=%s*([%d.]+)")))
        end
    end
    for _, id in ipairs({"KitchenKnife", "HuntingKnife", "Scissors", "Axe"}) do
        local definition = assert(native[id], "missing native " .. id)
        expect(definition, nil, nil, true)
        expect(definition, physical(definition, 0.8, 1), true)
        expect(definition, physical(definition, 1, 1), false)
        expect(definition, physical(definition, 0, 1, true), false)
    end
    for _, id in ipairs({"Saw", "File", "Whetstone", "Hammer"}) do expect(assert(native[id]), nil, false) end
    local count = 0
    for name, block in read(generated .. "recipes/recipes_fixing.txt"):gmatch("craftRecipe%s+([%w_]+)%s*(%b{})") do
        if name == "SharpenBlade" or name == "SharpenBladePoorlyWithFile" or name == "SharpenBladeWithGrindstone" then
            assert(block:find("tags[base:sharpenable] mode:keep flags[IsSharpenable]", 1, true),
                "native sharpening subject no longer matches tag/current-sharpness semantics")
            assert(not block:find("AllowDestroyedItem", 1, true), "native sharpening now permits broken subjects")
            count = count + 1
        end
    end
    assert(count == 3, "native sharpening recipe set changed")
    print("native B42 sharpening item and recipe declarations checked")
else print("SKIP native sharpening declarations (NativeActionRoot not supplied)") end
print("item sharpening tags tests passed")
