ComponentType = {FluidContainer = "fluid"}
FluidCategory = {Beverage = "Beverage", Alcoholic = "Alcoholic"}
local registry, registryReads = {}, 0
local function list(values)
    return {size = function() return #values end, get = function(_, i) return values[i + 1] end}
end
Fluid = {getAllFluids = function() registryReads = registryReads + 1; return list(registry) end,
    FluidsInitialized = function() return true end}
local function fluid(name, categories)
    local value = {name = name, isCategory = function(_, category) return categories[category] == true end}
    registry[#registry + 1] = value
    return value
end
local water = fluid("Water", {Beverage = true})
local tainted = fluid("TaintedWater", {Beverage = true, Hazardous = true})
local milk = fluid("CowMilk", {Beverage = true})
local whiskey = fluid("Whiskey", {Beverage = true, Alcoholic = true})
local medical = fluid("RubbingAlcohol", {Alcoholic = true, Medical = true})
local bleach = fluid("Bleach", {Hazardous = true})
local Tags = dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/ItemFluidTags.lua")
local function item(contents)
    local container = {
        isEmpty = function()
            for _, amount in pairs(contents) do if amount > 0 then return false end end
            return true
        end,
        isCategory = function(_, category)
            for value, amount in pairs(contents) do
                if amount > 0 and value:isCategory(category) then return true end
            end
            return false
        end,
        getSpecificFluidAmount = function(_, value) return contents[value] or 0 end,
        getPrimaryFluid = function() error("majority fluid must not decide content roles") end,
        getProperties = function() error("nutrition/poison does not decide content roles") end,
    }
    return {getFluidContainer = function() return container end}, container
end
local function script(entries, random, capacity)
    local choices = {}
    for _, entry in ipairs(entries or {}) do
        choices[#choices + 1] = {getFluid = function() return entry[1] end,
            getPercentage = function() return entry[2] end}
    end
    local component = {getInitialFluids = function() return list(choices) end,
        isInitialFluidsIsRandom = function() return random == true end,
        getCapacity = function() return capacity or 1 end,
        getInitialAmount = function() error("initial amount getter consumes RNG") end}
    return {getComponentScriptFor = function(_, kind)
        assert(kind == ComponentType.FluidContainer); return component
    end, getDisplayCategory = function() error("display category is not contents") end,
        OnCreate = function() error("tag reads must not execute callbacks") end}
end
local function expect(contents, expected)
    local state, possible, isFluid = Tags.read(nil, item(contents))
    assert(state == expected, "unexpected role: " .. tostring(state) .. " instead of " .. expected)
    assert(isFluid == true and #possible == 1 and possible[1] == expected)
end
expect({}, "none")
expect({[water] = 1}, "beverage")
expect({[tainted] = 1}, "beverage")
expect({[milk] = 1}, "beverage")
expect({[medical] = 1}, "none")
expect({[bleach] = 1}, "none")
expect({[water] = 0.001, [bleach] = 0.999}, "beverage")
assert(registryReads == 0, "ordinary nonalcoholic reads must not scan the fluid registry")
expect({[whiskey] = 1}, "alcoholic")
expect({[water] = 0.999, [whiskey] = 0.001}, "alcoholic")
expect({[whiskey] = 0.001, [bleach] = 0.999}, "alcoholic")
expect({[water] = 0.5, [medical] = 0.5}, "beverage")
expect({[whiskey] = 0, [water] = 1}, "beverage")

-- Each read observes refill, pouring out and a changed mixture immediately.
local contents = {[whiskey] = 1}
local live, container = item(contents)
local definition = script({{whiskey, 1}})
assert(Tags.read(definition, live) == "alcoholic")
contents[whiskey] = nil
assert(Tags.read(definition, live) == "none")
contents[water] = 1
assert(Tags.read(definition, live) == "beverage")
contents[water], contents[bleach] = nil, 1
assert(Tags.read(definition, live) == "none")
-- Script defaults cannot override an actual nonfluid item or missing APIs.
local state, possible, isFluid = Tags.read(definition, {getFluidContainer = function() end})
assert(state == nil and isFluid == false and #possible == 0)
state, possible, isFluid = Tags.read({getComponentScriptFor = function() end})
assert(state == nil and isFluid == false and #possible == 0)
state, possible, isFluid = Tags.read({})
assert(state == nil and isFluid == nil and #possible == 0)
container.isCategory = nil
assert(Tags.read(definition, live) == nil, "partial live metadata must remain unknown")
local allFluids = Fluid.getAllFluids
Fluid.getAllFluids = nil
assert(Tags.read(nil, item({[water] = 1, [medical] = 1})) == nil)
Fluid.getAllFluids = allFluids
Fluid.FluidsInitialized = function() return false end
assert(Tags.read(nil, item({[whiskey] = 1})) == nil)
Fluid.FluidsInitialized = function() return true end

local function preview(definition, expected)
    local actual, choices, fluidContainer = Tags.read(definition)
    assert(actual == nil, "a factory default is never current content evidence")
    assert(fluidContainer == true and table.concat(choices, ",") == expected,
        "unexpected preview possibilities: " .. table.concat(choices, ","))
end
preview(script({}), "none")
preview(script({{water, 1}}), "none,beverage")
preview(script({{whiskey, 1}}), "none,alcoholic")
preview(script({{medical, 1}}), "none")
preview(script({{water, 0.5}, {medical, 0.5}}), "none,beverage")
preview(script({{water, 0.99}, {whiskey, 0.01}}), "none,alcoholic")
preview(script({{whiskey, 1}, {water, 1}, {bleach, 1}}, true), "none,beverage,alcoholic")
preview(script({{whiskey, 0}, {water, 1}, {milk, 1}}, true), "none,beverage")
preview(script({{whiskey, 1}}, false, 0), "none")
preview(script({{nil, 1}}), "none")
print("fluid roles follow current components, preserve unknown/nonfluid states and inspect pure preview metadata")

-- Empty is observable independently of fluid identity, safety and factory fill.
for _, contents in ipairs({{}, {[water] = 1}, {[bleach] = 1}, {[tainted] = 0.000001}}) do
    local actual, vessel = item(contents)
    local roles = Tags.usage(nil, actual)
    assert(roles.empty == vessel:isEmpty(), 'Empty did not follow native current contents')
end
local measured = 0
local partial = {getFluidContainer = function()return {getAmount=function()return measured end}end}
assert(Tags.usage(nil,partial).empty == true)
measured = 0.000001
assert(Tags.usage(nil,partial).empty == false, 'trace contents were discarded')
for _, invalid in ipairs({-1, math.huge, 0/0}) do
    measured = invalid
    assert(Tags.usage(nil,partial).empty == nil, 'invalid amount became a known Empty state')
end
assert(Tags.usage(nil,{getFluidContainer=function()return {}end}).empty == nil)
assert(Tags.usage(definition,{getFluidContainer=function()end}).empty == nil)
assert(Tags.usage(definition,{}).empty == nil, 'missing live APIs fell back to script defaults')
local function checkEmptyPreview(definition, canFill)
    local current, states = Tags.usage(definition)
    assert(current.empty == nil, 'preview invented a current fill state')
    local empty, filled = false, false
    for _, state in ipairs(states) do
        if state.empty then
            empty = true
            assert(state.beverage == false and state.alcoholic == false
                and state.fuel == false and state.disinfectant == false,
                'Empty preview retained contents')
        elseif state.empty == false then filled = true end
    end
    assert(empty and filled == canFill, 'vessel preview lost an empty/filled possibility')
end
checkEmptyPreview(script({}), true)
checkEmptyPreview(script({{bleach,1}}), true)
checkEmptyPreview(script({{whiskey,1}}), true)
checkEmptyPreview(script({}, false, 0), false)
checkEmptyPreview(script({}, false, 0/0), false)
checkEmptyPreview({getComponentScriptFor=function()return {getCapacity=function()return 1 end}end}, true)
checkEmptyPreview({getComponentScriptFor=function()return {}end}, false)

-- Source-backed category and initial-fluid fixtures from installed B42.21.
-- These adapt declarations without constructing game objects or executing Lua
-- callbacks. Java getter semantics are independently verified with javap.
if NativeActionRoot then
    local generated = NativeActionRoot .. "/../scripts/generated/"
    local function read(path)
        local file = assert(io.open(generated .. path))
        local text = file:read("*a"); file:close(); return text
    end
    local definitions = {}
    registry = {}
    for _, filename in ipairs({"fluids.txt", "fluids_Beverages.txt", "fluids_Alcoholic.txt"}) do
        for name, block in read(filename):gmatch("fluid%s+([%w_]+)%s*(%b{})") do
            local categories = {}
            local categoryBlock = block:match("Categories%s*(%b{})") or ""
            for category in categoryBlock:gmatch("([%w_]+)%s*,") do categories[category] = true end
            definitions[name] = fluid(name, categories)
        end
    end
    local function native(name) return assert(definitions[name], "missing native fluid " .. name) end
    for _, name in ipairs({"Water", "TaintedWater", "CowMilk", "SheepMilk", "CarbonatedWater"}) do
        expect({[native(name)] = 1}, "beverage")
    end
    for _, name in ipairs({"Beer", "Whiskey", "Wine"}) do expect({[native(name)] = 1}, "alcoholic") end
    expect({[native("Bleach")] = 1}, "none")
    expect({[native("RubbingAlcohol")] = 1}, "none")
    expect({[native("Water")] = 0.1, [native("RubbingAlcohol")] = 0.9}, "beverage")
    expect({[native("Water")] = 0.1, [native("Bleach")] = 0.9}, "beverage")
    local wanted = {WaterBottle = "none,beverage", Whiskey = "none,alcoholic",
        BeerBottle = "none,alcoholic", Bleach = "none", BeerEmpty = "none"}
    for name, block in read("items/normal.txt"):gmatch("item%s+([%w_]+)%s*(%b{})") do
        if wanted[name] then
            local component = assert(block:match("component%s+FluidContainer%s*(%b{})"),
                "missing native container " .. name)
            local entries = {}
            for fluidName, percentage in component:gmatch("fluid%s*=%s*([%w_]+):([%d.]+)") do
                entries[#entries + 1] = {native(fluidName), tonumber(percentage)}
            end
            local definition = script(entries, component:match("PickRandomFluid%s*=%s*true") ~= nil,
                tonumber(component:match("Capacity%s*=%s*([%d.]+)")))
            preview(definition, wanted[name])
            checkEmptyPreview(definition, true)
            wanted[name] = nil
        end
    end
    assert(next(wanted) == nil, "native item fixture missing")
    print("native B42.21 fluid categories and bottle declarations checked")
else
    print("SKIP native fluid declaration check (NativeActionRoot not supplied)")
end
print("item fluid tags tests passed")
