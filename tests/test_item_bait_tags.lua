package.path = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/shared/?.lua;" .. package.path
ItemType = {FOOD = "food"}
instanceof = function(item, kind) return kind == "Food" and item.food == true end
instanceItem = function() error("bait reads must not construct native items") end
InventoryItemFactory = {CreateItem = instanceItem}
ZombRand = function() error("bait reads must not draw RNG") end
local Bait = require "PZSurvivorToolkit/ItemBaitTags"

local function definition(name, food)
    return {getFullName = function() return name end,
        isItemType = function(_, kind) return kind == ItemType.FOOD and food == true end,
        OnCreate = function() error("bait reads must not execute callbacks") end}
end
local function live(name, food, options)
    options = options or {}
    return {food = food, getScriptItem = function() return definition(name, food) end,
        getFullType = function() return name end,
        isCooked = function() return options.cooked == true end,
        isBurnt = function() return options.burnt == true end,
        isFrozen = function() return options.frozen == true end,
        haveExtraItems = function() return options.extra == true end,
        getCustomMenuOption = function() return options.menu end,
        getHungerChange = function() return options.hunger or -0.01 end,
        getHungChange = function() return options.hunger or -0.01 end}
end
local function expect(item, fish, trap)
    local roles, states = Bait.read(nil, item)
    assert(roles.fishBait == fish, "fish role for " .. item:getFullType())
    assert(roles.trapBait == trap, "trap role for " .. item:getFullType())
    assert(#states == 0, "physical reads have no hypothetical states")
end

Fishing, TrapAnimals = nil, nil
expect(live("Example.Bait", true), nil, nil)
expect(live("Example.Bait", true, {cooked = true}), false, false)
local typeHelper = instanceof
instanceof = nil
local roles = Bait.read({}, {})
assert(next(roles) == nil, "unavailable type/current metadata stays unknown")
instanceof = typeHelper
-- Kahlua exports pairs, but not Lua's next global.
next = nil
Fishing = {lure = {All = {}, Food = {["Example.Bait"] = {amountOfFoodHunger = 5}},
    Artificial = {["Example.Lure"] = {amountOfFoodHunger = -1}}}}
TrapAnimals = {{baits = {["Example.Bait"] = 35, ["Example.ZeroBonus"] = 0}}}
expect(live("Example.Bait", true), true, true)
expect(live("Example.ZeroBonus", true), false, true)
expect(live("Example.Lure", false), true, false)
expect(live("Example.OtherFood", true, {hunger = -1}), false, false)
expect(live("Example.Bait", true, {cooked = true}), false, false)
expect(live("Example.Bait", true, {extra = true}), true, false)
expect(live("Example.Bait", true, {menu = "Drink"}), true, false)
expect(live("Example.Bait", true, {hunger = 0, frozen = true, burnt = true}), true, true)
local incomplete = live("Example.Bait", true)
incomplete.isCooked = nil
expect(incomplete, nil, nil)
incomplete.isCooked = function() return false end
incomplete.haveExtraItems = nil
expect(incomplete, true, nil)
incomplete.getCustomMenuOption = function() return "Drink" end
expect(incomplete, true, false)

-- The aggregate is native authority once indexed. No negative lookup is cached,
-- so late game/server start and mod definition updates are visible next read.
Fishing.lure.All = {["Example.Lure"] = {}}
expect(live("Example.Bait", true), false, true)
Fishing.lure.All["Example.Bait"] = {}
expect(live("Example.Bait", true), true, true)
TrapAnimals = nil
expect(live("Example.Bait", true), true, nil)
TrapAnimals = {{baits = {["Example.Bait"] = 40}}}
expect(live("Example.Bait", true), true, true)
TrapAnimals[1].baits["Example.Bait"] = nil
expect(live("Example.Bait", true), true, false)
TrapAnimals[1].baits["Example.Bait"] = 40

local current, states = Bait.read(definition("Example.Bait", true))
assert(current.fishBait == nil and current.trapBait == nil, "script defaults are not current food state")
local raw, cooked, altered = false, false, false
for _, state in ipairs(states) do
    if state.cooked then
        cooked = true
        assert(state.fishBait == false and state.trapBait == false)
    elseif state.trapBait then
        raw = true; assert(state.fishBait == true)
    else altered = true; assert(state.fishBait == true) end
end
assert(raw and cooked and altered, "preview preserves cooking and food-addition coherence")
current, states = Bait.read(definition("Example.Lure", false))
assert(current.fishBait == true and current.trapBait == false and #states == 0)
current, states = Bait.read(definition("Example.OtherFood", true))
assert(current.fishBait == false and current.trapBait == false and #states == 0)

if NativeActionRoot then
    local function read(path)
        local file = assert(io.open(NativeActionRoot .. "/" .. path))
        local text = file:read("*a"); file:close(); return text
    end
    -- Load original declaration-only sections, without fish constructors,
    -- event registrations, item callbacks or any game object construction.
    local fishing = read("shared/Fishing/fishing_properties.lua")
    local declaration = assert(fishing:match("^(.-)Fishing%.lure%.All = {}"))
    local env = setmetatable({}, {__index = _G})
    env.Fishing, env.TrapAnimals = {}, {}
    local function evaluate(source)
        local chunk = assert(loadstring(source)); setfenv(chunk, env); return chunk()
    end
    evaluate(declaration)
    evaluate(read("server/Traps/TrapDefinition.lua"))
    Fishing, TrapAnimals = env.Fishing, env.TrapAnimals
    local menu = read("server/Traps/ISUI/ISTrapMenu.lua")
    local predicate = evaluate(assert(menu:match("^(.-)ISTrapMenu%.doTrapMenu")) .. "\nreturn baitPredicate")
    for _, name in ipairs({"Base.Worm", "Base.Maggots", "Base.BaitFish", "Base.Cheese", "Base.FishFillet", "Base.Steak"}) do
        assert(Bait.read(nil, live(name, true)).fishBait == true, "native fish lure " .. name)
        assert(Bait.read(nil, live(name, true, {cooked = true})).fishBait == false)
    end
    expect(live("Base.JigLure", false), true, false)
    expect(live("Base.Carrots", true), false, true)
    expect(live("Base.Worm", true), true, true)
    for _, options in ipairs({{}, {cooked = true}, {extra = true}, {menu = "Drink"},
        {hunger = 0}, {hunger = -0.049}, {frozen = true}, {burnt = true}}) do
        local item = live("Base.Cheese", true, options)
        assert(Bait.read(nil, item).trapBait == predicate(item), "matches native useful-bait food admission")
    end
    local generic = live("Example.OtherFood", true, {hunger = -0.05})
    assert(predicate(generic) and not Bait.read(nil, generic).trapBait,
        "generic food admission does not imply animal attraction")
    local inventory = read("client/ISUI/ISInventoryPaneContextMenu.lua")
    assert(inventory:find('Fishing.IsLure(item:getFullType()) and (not instanceof(item, "Food") or not item:isCooked())', 1, true))
    local attach = read("shared/TimedActions/Fishing/TimedActions/AIAttachLureAction.lua")
    assert(attach:find("amountOfFoodHunger == -1", 1, true))
    assert(attach:find("self.lure:getHungChange() + Fishing.lure.All[self.lure:getFullType()].amountOfFoodHunger / 100", 1, true))
    assert(attach:find("self.lure:getHungChange() >= 0", 1, true))
    local add = read("shared/Traps/TimedActions/ISAddBaitAction.lua")
    assert(add:find("math.min(-0.05 / bait:getHungChange(), 1.0)", 1, true))
    local catch = read("server/Traps/STrapGlobalObject.lua")
    assert(catch:find("v.baits[self.bait] and ZombRand(100)", 1, true))
    print("native B42 lure/trap definitions, admission and consumption checked")
else print("SKIP native bait source check (NativeActionRoot not supplied)") end
print("item bait tags tests passed")
