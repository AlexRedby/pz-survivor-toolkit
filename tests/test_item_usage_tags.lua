package.path = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/shared/?.lua;" .. package.path
ComponentType = {FluidContainer = "fluid"}
FluidCategory = {Beverage = "beverage", Alcoholic = "alcoholic", Fuel = "fuel"}
ItemType = {DRAINABLE = "drainable"}
ItemTag = {CAN_BE_WASHED = "washable", IS_FIRE_FUEL = "firefuel",
    IS_FIRE_FUEL_SINGLE_USE = "singleuse"}
toolkitScriptBandagePower = function(script) return script.bandage or 0 end
toolkitScriptAlcoholPower = function(script) return script.alcohol or 0 end
local function list(values)
    return {size = function() return #values end, get = function(_, i) return values[i + 1] end}
end
local registry = {}
Fluid = {getAllFluids = function() return list(registry) end, FluidsInitialized = function() return true end}
local function fluid(name, categories, alcohol)
    local value = {name = name, isCategory = function(_, category) return categories[category] == true end,
        getProperties = function() return {getAlcohol = function() return alcohol or 0 end} end}
    registry[#registry + 1] = value
    return value
end
local water = fluid("Water", {beverage = true})
local beer = fluid("Beer", {beverage = true, alcoholic = true}, 0.05)
local whiskey = fluid("Whiskey", {beverage = true, alcoholic = true}, 0.4)
local medical = fluid("RubbingAlcohol", {alcoholic = true}, 1)
local petrol = fluid("Petrol", {fuel = true})
local bleach = fluid("Bleach", {})
local Usage = require "PZSurvivorToolkit/ItemUsageTags"
local function definition(options)
    options = options or {}
    local component
    if options.fluids then
        local entries = {}
        for _, value in ipairs(options.fluids) do
            entries[#entries + 1] = {getFluid = function() return value[1] end,
                getPercentage = function() return value[2] end}
        end
        component = {getCapacity = function() return options.capacity or 1 end,
            getInitialFluids = function() return list(entries) end,
            isInitialFluidsIsRandom = function() return options.random == true end,
            getInitialAmount = function() error("tag reads must not draw amount RNG") end}
    end
    return {bandage = options.bandage, alcohol = options.alcohol,
        getComponentScriptFor = function() return component end,
        getFullName = function() return options.name or "Example.Item" end,
        isItemType = function(_, kind) return kind == ItemType.DRAINABLE and options.drainable == true end,
        hasTag = function(_, tag) return (options.tags or {})[tag] == true end,
        getFireFuelRatio = function() return options.ratio or 0 end,
        getItemAfterCleaning = function() return options.cleaning end,
        OnCreate = function() error("tag reads must not execute callbacks") end}
end
local function live(options)
    options = options or {}
    local script, container = definition(options)
    if options.contents then
        local contents = options.contents
        local function amount()
            local result = 0
            for _, value in pairs(contents) do result = result + value end
            return result
        end
        container = {isEmpty = function() return amount() <= 0 end,
            getAmount = function() return amount() end,
            isCategory = function(_, category)
                for value, quantity in pairs(contents) do
                    if quantity > 0 and value:isCategory(category) then return true end
                end
                return false
            end,
            getSpecificFluidAmount = function(_, value) return contents[value] or 0 end,
            getProperties = function()
                local result = 0
                for value, quantity in pairs(contents) do result = result + value:getProperties():getAlcohol() * quantity end
                return {getAlcohol = function() return result end}
            end}
    end
    return {getScriptItem = function() return script end,
        getFluidContainer = function() return container end,
        getBandagePower = function() return options.bandage or 0 end,
        getAlcoholPower = function() return options.alcohol or 0 end,
        IsDrainable = function() return options.drainable == true end,
        hasTag = script.hasTag, getFireFuelRatio = script.getFireFuelRatio,
        getItemAfterCleaning = script.getItemAfterCleaning,
        getFullType = script.getFullName,
        getCurrentUses = function() return options.uses or 0 end,
        getCurrentUsesFloat = function() return options.usesFloat or options.uses or 0 end}, container
end
local function expect(options, expected, scriptOnly)
    local roles = Usage.read(scriptOnly and definition(options) or nil, not scriptOnly and live(options) or nil)
    for field, value in pairs(expected) do
        assert(roles[field] == value, field .. ": expected " .. tostring(value) .. ", got " .. tostring(roles[field]))
    end
    return roles
end
expect({bandage = 2}, {bandage = true, dirty = false})
expect({bandage = 0.5, tags = {washable = true}, cleaning = "Example.Clean"}, {bandage = true, dirty = true})
expect({bandage = 0, tags = {washable = true}, cleaning = "Example.Shirt"}, {bandage = false, dirty = false})
expect({bandage = 1, tags = {washable = true}}, {bandage = true, dirty = false})
expect({bandage = 1, cleaning = "Example.Clean"}, {bandage = true, dirty = false})
expect({bandage = -1}, {bandage = false, dirty = false})
expect({bandage = 0.5, tags = {washable = true}, cleaning = "Example.Clean"}, {bandage = true, dirty = true}, true)
expect({drainable = true, alcohol = 4}, {disinfectant = true})
expect({drainable = true, alcohol = 3.99}, {disinfectant = false})
expect({drainable = false, alcohol = 4}, {disinfectant = false})
expect({contents = {[water] = 1}}, {disinfectant = false, fuel = false})
expect({contents = {[beer] = 1}}, {disinfectant = false, fuel = false})
expect({contents = {[whiskey] = 0.15}}, {disinfectant = false})
expect({contents = {[whiskey] = 0.15001}}, {disinfectant = true})
expect({contents = {[medical] = 0.399, [water] = 0.601}}, {disinfectant = true})
expect({contents = {[medical] = 0.398, [water] = 0.602}}, {disinfectant = false})
expect({contents = {[medical] = 1}}, {disinfectant = true, beverage = false, alcoholic = false})
expect({contents = {[water] = 0.5, [medical] = 0.5}}, {disinfectant = true, beverage = true, alcoholic = false})
expect({contents = {[bleach] = 1}, drainable = true, alcohol = 4}, {disinfectant = false})
expect({contents = {}, drainable = true, alcohol = 4}, {disinfectant = false, fuel = false})
expect({contents = {[petrol] = 0.0001}}, {fuel = true})
expect({name = "Base.EmptyPetrolCan", contents = {}}, {fuel = false})
expect({name = "Base.EmptyPetrolCan", contents = {[water] = 1}}, {fuel = false})
expect({name = "Base.EmptyPetrol"}, {fuel = false})
expect({name = "Base.PropaneTankEmpty"}, {fuel = false})
expect({name = "Base.EmptyPetrol"}, {fuel = false}, true)
expect({name = "Base.PropaneTankEmpty"}, {fuel = false}, true)
expect({name = "Base.PropaneTank", drainable = true, usesFloat = 0.01}, {fuel = true})
expect({name = "Base.PropaneTank", drainable = true, usesFloat = 0}, {fuel = false})
expect({tags = {firefuel = true}, ratio = 2}, {fuel = true})
expect({ratio = 2}, {fuel = true})
expect({tags = {firefuel = true}, drainable = true, uses = 1}, {fuel = true})
expect({tags = {firefuel = true}, drainable = true, uses = 0}, {fuel = false})
expect({tags = {firefuel = true, singleuse = true}, drainable = true, uses = 0}, {fuel = true})
local roles = Usage.read({}, {})
assert(next(roles) == nil, "missing live data must not become script defaults")
roles = Usage.read(definition({fluids = {{whiskey, 1}}}), {IsDrainable = function() return false end})
assert(roles.disinfectant == nil and roles.fuel == nil, "missing live component data stays unknown")
local bandageHelper = toolkitScriptBandagePower
toolkitScriptBandagePower = nil
roles = Usage.read(definition({bandage = 2}))
assert(roles.bandage == nil and roles.dirty == nil)
toolkitScriptBandagePower = bandageHelper

local function preview(options)
    local current, states, isFluid = Usage.read(definition(options))
    if options.fluids then
        assert(isFluid == true and current.disinfectant == nil and current.fuel == nil)
    end
    return states
end
local states = preview({fluids = {{water, 1}, {whiskey, 1}, {petrol, 1}}, random = true})
local empty, alcoholic, fuel, disinfectant = false, false, false, false
for _, state in ipairs(states) do
    if not state.beverage and not state.fuel then empty = true end
    if state.alcoholic then alcoholic = true end
    if state.fuel then fuel = true; assert(not state.beverage and not state.disinfectant) end
    if state.disinfectant then disinfectant = true; assert(state.alcoholic and not state.fuel) end
    assert(not state.disinfectant or state.beverage, "random water cannot inherit disinfectant from whiskey")
end
assert(empty and alcoholic and fuel and disinfectant)
states = preview({fluids = {{water, 0.9}, {medical, 0.1}}})
for _, state in ipairs(states) do assert(not state.disinfectant and not state.alcoholic and not state.fuel) end
states = preview({fluids = {{medical, 1}}, capacity = 0.15})
for _, state in ipairs(states) do assert(not state.disinfectant) end
-- Missing fluid categories never become an asserted nonbeverage/nonfuel role
-- because another constituent happens to have complete metadata.
states = preview({fluids = {{{}, 0.5}, {water, 0.5}}})
assert(#states == 2 and states[2].beverage == nil and states[2].fuel == nil)
states = preview({fluids = {{petrol, 0.5}, {{}, 0.5}}})
assert(#states == 2 and states[2].fuel == true and states[2].beverage == nil)
states = preview({fluids = {{water, 0.5}, {medical, 0.5}}})
local mixedDisinfectant = false
for _, state in ipairs(states) do
    if state.disinfectant then mixedDisinfectant = true; assert(state.beverage and not state.alcoholic) end
end
assert(mixedDisinfectant, "preview concentration uses weighted per-unit fluid properties")
states = preview({name = "Base.PropaneTank", drainable = true})
assert(#states == 2 and states[1].fuel == false and states[2].fuel == true)
states = preview({tags = {firefuel = true}, drainable = true})
assert(#states == 2 and states[1].fuel == false and states[2].fuel == true)
local contents = {[whiskey] = 1}
local item = live({contents = contents})
assert(Usage.read(nil, item).disinfectant == true)
contents[whiskey], contents[water] = nil, 1
assert(Usage.read(nil, item).disinfectant == false)
contents[water], contents[petrol] = nil, 1
assert(Usage.read(nil, item).fuel == true)
contents[petrol] = nil
assert(Usage.read(nil, item).fuel == false)
local incomplete, container = live({contents = {[whiskey] = 1}})
container.getProperties = nil
assert(Usage.read(nil, incomplete).disinfectant == nil)

assert(Usage.encode({}) == nil and Usage.encode(nil) == nil)
assert(Usage.encode({bandage = true, disinfectant = false, fuel = true}) == "10?1")
local decoded = Usage.decode("10?1")
assert(decoded.bandage == true and decoded.disinfectant == false and decoded.dirty == nil and decoded.fuel == true)
for _, invalid in ipairs({false, 1010, "", "111", "11111", "10x1"}) do assert(next(Usage.decode(invalid)) == nil) end
assert(next(Usage.decode(nil)) == nil)

-- Source-backed fixtures keep medical thresholds, dirty cloth and native solid
-- fuel declarations aligned with the installed game without creating objects.
if NativeActionRoot then
    local function read(path)
        local file = assert(io.open(NativeActionRoot .. "/../" .. path))
        local text = file:read("*a"); file:close(); return text
    end
    local health = read("lua/client/XpSystem/ISUI/ISHealthPanel.lua")
    assert(health:find("item:getBandagePower() > 0", 1, true))
    assert(health:find("fluidContainer:getProperties():getAlcohol() / fluidContainer:getAmount() + 0.001 >= 0.4", 1, true))
    assert(health:find("fluidContainer:getAmount() > 0.15", 1, true))
    assert(health:find("item:getAlcoholPower() == 4.0", 1, true))
    local wanted = {Bandage = true, BandageDirty = true, RippedSheetsDirty = true,
        DenimStripsDirty = true, LeatherStripsDirty = true, Charcoal = true, CharcoalCrafted = true}
    for name, block in read("scripts/generated/items/normal.txt"):gmatch("item%s+([%w_]+)%s*(%b{})") do
        if wanted[name] then
            local tags = {}
            for native, localTag in pairs({isfirefuel = "firefuel", canbewashed = "washable"}) do
                if block:find("base:" .. native, 1, true) then tags[localTag] = true end
            end
            local options = {name = "Base." .. name, tags = tags,
                bandage = tonumber(block:match("BandagePower%s*=%s*([%d.]+)")),
                ratio = tonumber(block:match("FireFuelRatio%s*=%s*([%d.]+)")),
                cleaning = block:match("ItemAfterCleaning%s*=%s*([%w_.]+)")}
            if name:find("Dirty", 1, true) then expect(options, {bandage = true, dirty = true}, true)
            elseif name == "Bandage" then expect(options, {bandage = true, dirty = false}, true)
            else expect(options, {bandage = false, dirty = false, fuel = true}, true) end
            wanted[name] = nil
        end
    end
    assert(next(wanted) == nil, "native usage fixture missing")
    local bbq = read("lua/client/ISUI/ISBBQMenu.lua")
    assert(bbq:find('"Base.PropaneTank"', 1, true) and bbq:find("getCurrentUsesFloat() > 0", 1, true))
    print("native B42 medical predicates, dirty cloth, charcoal and propane metadata checked")
else print("SKIP native usage declaration check (NativeActionRoot not supplied)") end
print("item usage tags tests passed")
