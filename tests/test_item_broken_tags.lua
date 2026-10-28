ItemType = {WEAPON = "base:weapon", CLOTHING = "base:clothing",
    ALARM_CLOCK_CLOTHING = "base:alarmclockclothing", NORMAL = "base:normal",
    FOOD = "base:food", DRAINABLE = "base:drainable", CONTAINER = "base:container"}
ItemTag = {WHETSTONE = "base:whetstone", SHOW_CONDITION = "base:showcondition"}
ResourceType = {Item = "Item", Fluid = "Fluid"}
local boot
Events = {OnGameBoot = {Add = function(callback) boot = callback end}}
InventoryItemFactory = {CreateItem = function() error("broken preview constructed an item") end}
instanceItem = function() error("broken preview instantiated a script") end
ZombRand = function() error("broken tagging consumed random state") end
local Broken = dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/ItemBrokenTags.lua")
local function definition(kind, maximum, tags, name)
    return {isItemType = function(_, value) return kind == value end,
        hasTag = function(_, value) return tags and tags[value] == true or false end,
        getFullName = function() return name end,
        getConditionMax = function() return maximum end,
        getConditionLowerChance = function() return 10 end,
        InstanceItem = function() error("broken preview ran OnCreate") end,
        getOnBreak = function() error("broken preview inspected unrelated callbacks") end}
end
local function physical(broken)
    return {isBroken = function() return broken end,
        getCondition = function() error("condition is not the stored broken flag") end,
        getConditionMax = function() error("current broken flag needs no maximum") end,
        getCurrentUses = function() error("empty is not broken") end,
        isRotten = function() error("rotten is not broken") end,
        isBurnt = function() error("burnt is not broken") end,
        getScriptItem = function() error("current broken flag needs no script") end,
        setBroken = function() error("broken tagging mutated the item") end}
end
local function expect(script, item, current, variable)
    local actual, possible = Broken.read(script, item)
    assert(actual == current, "broken current state differs")
    if variable then
        assert(possible and #possible == 2 and possible[1] == false and possible[2] == true,
            "known wear classes must preserve healthy/broken preview states")
    else assert(possible == nil, "reader invented feasible script states") end
end
for _, state in ipairs({false, true}) do
    expect(nil, physical(state), state)
    expect({}, physical(state), state)
end
for _, value in ipairs({0, 1, "false", "true"}) do expect(nil, physical(value), nil) end
expect(nil, physical(nil), nil)
expect(nil, {}, nil)
expect(nil, nil, nil)
expect({}, nil, nil)
for _, kind in ipairs({ItemType.WEAPON, ItemType.CLOTHING, ItemType.ALARM_CLOCK_CLOTHING}) do
    expect(definition(kind, 10), nil, nil, true)
    -- A missing native getter is unknown, even if the script is a known class.
    expect(definition(kind, 10), {}, nil)
    for _, maximum in ipairs({0, -1, math.huge, -math.huge, 0 / 0, "10"}) do
        expect(definition(kind, maximum), nil, nil)
    end
    expect(definition(kind), nil, nil)
end
-- Default ConditionMax=10 and ConditionLowerChance=10 occur on unrelated native
-- classes. They do not prove the existence of a condition-degradation path.
for _, kind in ipairs({ItemType.NORMAL, ItemType.FOOD, ItemType.DRAINABLE, ItemType.CONTAINER}) do
    expect(definition(kind, 10), nil, nil)
    expect(definition(kind, 10), physical(false), false)
    expect(definition(kind, 10), physical(true), true)
end
local whetstone = definition(ItemType.NORMAL, 20,
    {[ItemTag.WHETSTONE] = true, [ItemTag.SHOW_CONDITION] = true})
expect(whetstone, nil, nil)
expect(definition(ItemType.NORMAL, 20, {[ItemTag.SHOW_CONDITION] = true}), nil, nil)
expect(definition(ItemType.NORMAL, 20, {[ItemTag.WHETSTONE] = true}), nil, nil)
local weapon = definition(ItemType.WEAPON, 10)
local _, possible = Broken.read(weapon)
possible[1] = true
expect(weapon, nil, nil, true)
local originalNext = next
next = nil
expect(weapon, nil, nil, true)
expect(weapon, physical(true), true)
next = originalNext
local originalType = ItemType
ItemType = nil
expect(weapon, nil, nil)
expect(weapon, physical(false), false)
ItemType = originalType
weapon.getConditionMax = nil
expect(weapon, nil, nil)
weapon = definition(ItemType.WEAPON, 10)
weapon.isItemType = nil
expect(weapon, nil, nil)

local function list(values)
    return {size = function() return #values end, get = function(_, index) return values[index + 1] end}
end
local function input(choices, flag, kept, resource, tool)
    local result = {getResourceType = function() return resource or ResourceType.Item end,
        isKeep = function() return kept ~= false end,
        isTool = function() return tool == true end,
        getPossibleInputItems = function() return choices end}
    for _, method in ipairs({"mayDegrade", "mayDegradeLight", "mayDegradeVeryLight", "mayDegradeHeavy"}) do
        local id = method
        result[id] = function() return flag == id end
    end
    return result
end
local function recipe(inputs)
    return {getInputs = function() return list(inputs) end,
        getOnCreate = function() error("broken preview inspected callbacks") end,
        isVanilla = function() return false end}
end
local recipes = list({})
local manager = {getAllCraftRecipes = function() return recipes end}
getScriptManager = function() return manager end
local ordinary = definition(ItemType.NORMAL, 10, nil, "Mod.OrdinaryTool")
local unrelated = definition(ItemType.NORMAL, 10, {[ItemTag.SHOW_CONDITION] = true}, "Mod.Unrelated")
for _, flag in ipairs({"mayDegrade", "mayDegradeLight", "mayDegradeVeryLight", "mayDegradeHeavy"}) do
    recipes = list({recipe({input(list({ordinary}), flag)})})
    expect(ordinary, nil, nil, true)
    expect(unrelated, nil, nil)
end
recipes = list({recipe({input(list({ordinary}), "mayDegradeHeavy", false, nil, true)})})
expect(ordinary, nil, nil) -- Tool alone does not enter the native kept-input branch.
recipes = list({recipe({input(list({ordinary}), "mayDegradeLight", true, ResourceType.Fluid)})})
expect(ordinary, nil, nil)
recipes = list({recipe({input(list({ordinary}), nil)})})
expect(ordinary, nil, nil)
recipes = list({recipe({input(nil, "mayDegradeLight")})})
expect(ordinary, nil, nil)
local earlyInputs
recipes = list({{getInputs = function() return earlyInputs end}})
expect(ordinary, nil, nil)
earlyInputs = list({input(list({ordinary}), "mayDegradeLight")})
expect(ordinary, nil, nil, true)
local choices = {}
recipes = list({recipe({input(list(choices), "mayDegrade")})})
expect(ordinary, nil, nil)
choices[1] = ordinary
expect(ordinary, nil, nil, true) -- Empty early tag choices were not cached.
choices[1] = nil
expect(ordinary, nil, nil, true) -- A completed index is stable until invalidated.
assert(boot == Broken.invalidate, "broken index has no OnGameBoot invalidation")
boot()
expect(ordinary, nil, nil)
choices[1] = ordinary
expect(ordinary, nil, nil, true)
-- Manager identity and recipe count both bound the cache, even when the Java
-- list itself stays the same object.
local values = {recipe({input(list({ordinary}), "mayDegradeHeavy")})}
recipes = list(values)
expect(ordinary, nil, nil, true)
values[1] = recipe({input(list({unrelated}), "mayDegradeHeavy")})
values[2] = recipe({})
expect(ordinary, nil, nil)
expect(unrelated, nil, nil, true)
manager = {getAllCraftRecipes = function() return recipes end}
values[1] = recipe({input(list({ordinary}), "mayDegradeVeryLight")})
expect(ordinary, nil, nil, true)
expect(unrelated, nil, nil)
local originalNextRecipes = next
next = nil
boot()
expect(ordinary, nil, nil, true)
next = originalNextRecipes
local originalManager = getScriptManager
getScriptManager = nil
expect(ordinary, nil, nil)
expect(definition(ItemType.WEAPON, 10), nil, nil, true)
getScriptManager = originalManager
local originalResourceType = ResourceType
ResourceType = nil
expect(ordinary, nil, nil)
ResourceType = originalResourceType
expect(ordinary, nil, nil, true)

if NativeActionRoot then
    local function read(path)
        local source = assert(io.open(path)); local text = source:read("*a"); source:close(); return text
    end
    local generated = NativeActionRoot .. "/../scripts/generated/items/"
    local native, nativeTags = {}, {}
    for _, file in ipairs({"weapon", "clothing", "alarmclockclothing", "normal", "food", "drainable", "container"}) do
        for id, block in read(generated .. file .. ".txt"):gmatch("item%s+([%w_]+)%s*(%b{})") do
            -- Item's constructor supplies the same default maximum even for
            -- classes without known wear. Preserve it in all fixture scripts.
            local tags = {}
            for tag in (block:match("Tags%s*=%s*([^,]+)") or ""):gmatch("[^;%s]+") do tags[tag] = true end
            native[id] = definition(block:match("ItemType%s*=%s*([^,%s]+)"),
                tonumber(block:match("ConditionMax%s*=%s*([%d.]+)")) or 10, tags, "Base." .. id)
            nativeTags[id] = tags
        end
    end
    local nativeRecipes = {}
    for _, file in ipairs({"recipes_fixing", "recipes_carpentry", "recipes_farming"}) do
        local source = read(NativeActionRoot .. "/../scripts/generated/recipes/" .. file .. ".txt")
        for block in source:gmatch("craftRecipe%s+[%w_]+%s*(%b{})") do
            local inputs = {}
            for line in block:gmatch("[^\r\n]+") do
                local flag = line:match("MayDegrade[%w]*")
                if flag and line:find("mode:keep", 1, true) then
                    local choices, selected = {}, {}
                    for tags in line:gmatch("tags%[([^%]]+)%]") do
                        for tag in tags:gmatch("[^;]+") do
                            for id, available in pairs(nativeTags) do
                                if available[tag] then selected[id] = true end
                            end
                        end
                    end
                    for id in line:gmatch("Base%.([%w_]+)") do selected[id] = true end
                    for id in pairs(selected) do if native[id] then choices[#choices + 1] = native[id] end end
                    inputs[#inputs + 1] = input(list(choices), "m" .. flag:sub(2))
                end
            end
            nativeRecipes[#nativeRecipes + 1] = recipe(inputs)
        end
    end
    recipes = list(nativeRecipes)
    for _, id in ipairs({"Scissors", "KitchenKnife", "Hammer", "File", "Whetstone", "CrudeWhetstone",
        "Saw", "Tweezers", "Tshirt_DefaultTEXTURE_TINT", "WristWatch_Right_DigitalBlack"}) do
        expect(assert(native[id], "missing native " .. id), nil, nil, true)
    end
    local fixing = read(NativeActionRoot .. "/../scripts/generated/recipes/recipes_fixing.txt")
    local sharpen = assert(fixing:match("craftRecipe%s+SharpenBlade%s*(%b{})"))
    assert(sharpen:find("tags[base:whetstone] mode:keep flags[Prop1;MayDegradeLight]", 1, true),
        "native whetstone recipe no longer proves a wear path")
    for _, id in ipairs({"EngineParts", "Apple", "Battery", "Bag_Schoolbag", "SledgehammerHead"}) do
        local script = assert(native[id], "missing native " .. id)
        expect(script, nil, nil)
        -- An empty battery/container and rotten/burnt food keep the native
        -- stored flag; other item properties cannot invent a broken state.
        expect(script, physical(false), false)
    end
    print("native B42 broken-state preview declarations checked")
else print("SKIP native broken declarations (NativeActionRoot not supplied)") end
print("item broken tags tests passed")
