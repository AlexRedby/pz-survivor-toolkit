local scans, boot = 0
Events = {OnGameBoot = {Add = function(fn) boot = fn end}}
ItemType = {FOOD = "food", NORMAL = "normal"}
ResourceType = {Item = "item", Fluid = "fluid", Energy = "energy"}
CraftRecipeTag = {COOKING = "cooking"}
ComponentType = {FluidContainer = "fluid"}
toolkitRecipeOnCreate = function(recipe) return recipe.onCreate end
local function list(values)
    return {size = function() return #values end,
        get = function(_, i) scans = scans + 1; return values[i + 1] end}
end
local scripts = {}
local function script(name, kind)
    local value = {getFullName = function() return name end,
        getHungerChange = function() return 0 end,
        getThirstChange = function() return 0 end,
        getDisplayCategory = function() return "Food" end,
        getDisplayName = function() return name end,
        isItemType = function(_, expected) return expected == (kind or ItemType.FOOD) end}
    scripts[name] = value
    return value
end
local meat, vegetable, peanuts = script("Base.Steak"), script("Base.Carrots"), script("Base.Peanuts")
local flour, salt, sugar = script("Base.Flour2"), script("Base.Salt"), script("Base.Sugar")
local oil, honey, hops = script("Base.OilOlive"), script("Base.Honey"), script("Base.Hops")
local openCan, closedCan = script("Base.CannedSardinesOpen"), script("Base.CannedSardines")
local bread, batter, dish = script("Base.BreadSlices"), script("Base.CakeBatter"), script("Base.Cake")
local powder = script("Base.AnimalMilkPowder", "drainable")
local pot, knife, jar, fuel = script("Base.Pot", "normal"), script("Base.Knife", "normal"),
    script("Base.Jar", "normal"), script("Base.Charcoal", "normal")
local function evolved(base, ingredients, options)
    options = options or {}
    local choices = {}
    for _, definition in ipairs(ingredients) do
        choices[#choices + 1] = {getUse = function() return 5 end,
            getFullType = function() return definition:getFullName() end}
    end
    return {getBaseItem = function() return base:getFullName() end,
        getFullResultItem = function() return (options.result or dish):getFullName() end,
        isCookable = function() return options.cookable ~= false end,
        getPossibleItems = function() return list(choices) end}
end
local function input(choices, options)
    options = options or {}
    return {getResourceType = function() return options.resource or ResourceType.Item end,
        isKeep = function() return options.keep == true end,
        isTool = function() return options.tool == true end,
        isApplyOnTick = function() return options.tick == true end,
        getPossibleInputItems = function() return list(choices or {}) end,
        isDestroy = function() return options.destroy == true end}
end
local function output(choices, resource)
    return {getResourceType = function() return resource or ResourceType.Item end,
        getPossibleResultItems = function() return list(choices) end,
        getPossibleResultFluids = function() return list(choices) end}
end
local function recipe(inputs, outputs, options)
    options = options or {}
    return {getName = function() return options.name or "FixtureCookingRecipe" end,
        onCreate = options.onCreate,
        getInputs = function() return list(inputs) end, getOutputs = function() return list(outputs) end,
        hasTag = function(_, tag) return tag == CraftRecipeTag.COOKING and options.cooking ~= false end,
        getTimedActionScript = function()
            if options.action then return {getName = function() return options.action end} end
        end,
        getCategory = function() error("category is not cooking capability") end,
        getXPAwardCount = function() return options.xp and 1 or 0 end,
        getXPAward = function() return {getPerk = function() return {getId = function() return "Cooking" end} end,
            getAmount = function() return options.xp end} end,
        OnTestItem = function() error("recipe item predicate must never execute") end,
        OnCreate = function() error("recipe creation must never execute") end}
end
local function fluid(name, poison)
    return {name = name, isPoisonous = function() return poison == true end,
        getProperties = function() return {getHungerChange = function() return 0 end,
            getThirstChange = function() return -0.1 end} end}
end
local milk, water, petrol = fluid("Milk"), fluid("Water"), fluid("Petrol", true)
local function fluidInput(allowed, mode)
    local value = input({}, {resource = ResourceType.Fluid})
    value.containsFluid = function(_, candidate) return allowed[candidate] == true end
    value.isFluidExact = function() return mode == "exact" end
    value.isFluidPrimary = function() return mode == "primary" end
    value.isFluidMixture = function() return mode == "mixture" end
    value.isFluidAnything = function() return mode == "anything" end
    value.isFluidMatch = function(_, container)
        assert(container.native, "native predicate must receive a real fluid container")
        return allowed[container.fluid] == true
    end
    return value
end
local milkInput = fluidInput({[milk] = true}, "exact")
local craft = list({
    recipe({input({knife}, {keep = true}), input({batter}), input({pot}), input({fuel})}, {output({dish})}),
    recipe({input({vegetable}, {destroy = true}), input({jar}, {destroy = true})}, {output({dish})}),
    recipe({input({closedCan})}, {output({openCan})}, {action = "OpenTinCanWithKnife"}),
    recipe({input({closedCan})}, {output({openCan})}, {action = "OpenTinCan"}),
    recipe({input({hops})}, {output({dish})}, {cooking = false}),
    recipe({input({hops})}, {output({pot})}),
    recipe({input({hops}, {keep = true})}, {output({dish})}),
    recipe({input({hops}, {tool = true})}, {output({dish})}),
    recipe({input({hops}, {tick = true})}, {output({dish})}),
    recipe({milkInput}, {output({dish})}),
})
local chum, bait = script("Base.Chum"), script("Base.BaitFish")
local evolvedRecipes = list({evolved(pot, {meat, vegetable, peanuts, flour, salt, sugar, oil, honey, openCan}),
    evolved(bread, {}), evolved(chum, {bait}, {result = chum, cookable = false})})
local manager = {getAllCraftRecipes = function() return craft end,
    getAllEvolvedRecipesList = function() return evolvedRecipes end,
    getItem = function(_, name) return scripts[name] end}
getScriptManager = function() return manager end
local cooking = dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/ItemCookingTags.lua")
local function expect(definition, expected, item)
    assert(cooking.read(definition, item) == expected, definition:getFullName() .. " ingredient differs")
end
for _, definition in ipairs({meat, vegetable, peanuts, flour, salt, sugar, oil, honey, openCan, bread, batter}) do
    expect(definition, true)
end
for _, definition in ipairs({pot, knife, jar, fuel, hops, closedCan, dish, chum, bait}) do expect(definition, false) end
local before = scans
for _ = 1, 100 do expect(peanuts, true) end
assert(scans == before, "repeated classification must not rescan recipe catalogs")

-- Cooking XP can prove a cooking recipe without its UI tag; category alone cannot.
craft = list({recipe({input({hops})}, {output({dish})}, {cooking = false, xp = 3})})
expect(hops, true)
craft = list({recipe({input({hops})}, {output({dish})}, {cooking = false, xp = 0})})
expect(hops, false)
craft = list({recipe({milkInput}, {output({dish})})})

-- The two native milk recipes deliberately have no declared outputs and use a
-- Drainable powder. Read exact runtime callback metadata without executing it.
for _, name in ipairs({"MakeMilkFromPowderBucket", "MakeMilkFromPowderBottle"}) do
    craft = list({recipe({input({pot}, {keep = true}), input({powder}), input({fuel})}, {},
        {name = name, onCreate = "RecipeCodeOnCreate.makeMilkFromPowder"})})
    expect(powder, true)
    expect(pot, false)
    expect(fuel, false)
    local bridge = toolkitRecipeOnCreate
    toolkitRecipeOnCreate = nil
    expect(powder, false)
    toolkitRecipeOnCreate = bridge
    expect(powder, true)
    craft = list({recipe({input({powder})}, {}, {name = name, onCreate = "Mod.ReplacedMilkRecipe"})})
    expect(powder, false)
end
craft = list({recipe({input({powder})}, {},
    {name = "ModMilkFromPowder", onCreate = "RecipeCodeOnCreate.makeMilkFromPowder"})})
expect(powder, false)
craft = list({recipe({input({powder}, {keep = true})}, {},
    {name = "MakeMilkFromPowderBottle", onCreate = "RecipeCodeOnCreate.makeMilkFromPowder"})})
expect(powder, false)
craft = list({recipe({milkInput}, {output({dish})})})

local bottle = script("Base.MilkBottle", "normal")
local function defaults(definitions, random)
    local choices = {}
    for _, definition in ipairs(definitions) do
        choices[#choices + 1] = {getFluid = function() return definition[1] end,
            getPercentage = function() return definition[2] end}
    end
    return {getInitialFluids = function() return list(choices) end,
        isInitialFluidsIsRandom = function() return random == true end,
        getCapacity = function() return 1 end,
        getInitialAmount = function() error("initial amount getter draws game RNG") end}
end
local component = defaults({{milk, 1}})
bottle.getComponentScriptFor = function() return component end
expect(bottle, true)
local container = {native = true, fluid = milk, isEmpty = function(self) return self.empty end}
local item = {getFluidContainer = function() return container end}
expect(bottle, true, item)
container.empty = true
expect(bottle, false, item)
container.empty, container.fluid = false, petrol
expect(bottle, false, item)
component = defaults({})
expect(bottle, false)
component = defaults({{petrol, 1}})
expect(bottle, false)
component = defaults({{milk, 0.5}, {petrol, 0.5}}, true)
expect(bottle, nil)
component = defaults({{milk, 0.5}, {water, 0.5}})
expect(bottle, false)
milkInput.isFluidExact = function() return false end
milkInput.isFluidPrimary = function() return true end
component = defaults({{milk, 0.7}, {water, 0.3}})
expect(bottle, true)
component = defaults({{milk, 0.3}, {water, 0.7}})
expect(bottle, false)
milkInput.isFluidPrimary = function() return false end
milkInput.isFluidMixture = function() return true end
component = defaults({{milk, 1}})
expect(bottle, true)
component = defaults({{milk, 0.7}, {petrol, 0.3}})
expect(bottle, false)
assert(cooking.read(bottle, nil, true) == false, "old snapshots must not infer factory fluid contents")

-- Drinking-fluid recipe outputs qualify too; poisonous process fluids do not.
craft = list({recipe({input({hops})}, {output({milk}, ResourceType.Fluid)})})
expect(hops, true)
craft = list({recipe({input({hops})}, {output({petrol}, ResourceType.Fluid)})})
expect(hops, false)

-- Partial offline managers must not erase a legacy ingredient classification.
local complete = manager
manager = {getAllCraftRecipes = complete.getAllCraftRecipes}
expect(peanuts, nil)
manager = complete
assert(type(boot) == "function")
boot()
expect(peanuts, true)
craft = list({recipe({milkInput}, {output({dish})})})
component = defaults({{milk, 1}})

-- Exercise the real tag consumers and preview matcher with the same structural
-- recipe fixtures. Serialized rows deliberately have no InventoryItem proxy.
package.path = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/shared/?.lua;" .. package.path
package.loaded["PZSurvivorToolkit/ItemCookingTags"] = cooking
isClient = function() return false end
local world = {}
ModData = {getOrCreate = function() return world end}
PZSurvivorToolkit = {Settings = {itemTags = function() return true end}}
local Tags = require "PZSurvivorToolkit/ItemTags"
local Custom = require "PZSurvivorToolkit/TagCustomization"
local function physical(definition, delta)
    return {getScriptItem = function() return definition end,
        getFullType = function() return definition:getFullName() end,
        getDisplayCategory = function() return "Food" end,
        getName = function() return definition:getFullName() end,
        hasModData = function() return delta ~= nil end,
        getModData = function() return {[Custom.FIELD] = delta} end}
end
for _, definition in ipairs({peanuts, flour, salt, meat, vegetable, honey, oil, bread}) do
    local item = physical(definition)
    for _, tags in ipairs({Tags.forScriptItem(definition), Tags.forItem(item),
        Tags.forSnapshot(definition, definition:getFullName(), "Food")}) do
        assert(Tags.matches(tags, {"ingredient"}), definition:getFullName() .. " lost ingredient projection")
    end
end
for _, definition in ipairs({hops, closedCan, pot, fuel}) do
    assert(not Tags.matches(Tags.forItem(physical(definition)), {"ingredient"}),
        definition:getFullName() .. " inherited ingredient without cooking capability")
end
local liveBottle = physical(bottle)
container.empty, container.fluid = false, milk
liveBottle.getFluidContainer = function() return container end
assert(Tags.matches(Tags.forItem(liveBottle), {"ingredient"}), "current milk contents lost ingredient")
container.empty = true
assert(not Tags.matches(Tags.forItem(liveBottle), {"ingredient"}), "emptied milk bottle remained ingredient")
assert(Tags.matches(Tags.forScriptItem(bottle), {"ingredient"}), "script default milk capability missing")
assert(not Tags.matches(Tags.forSnapshot(bottle, "Base.MilkBottle", "Food"), {"ingredient"}),
    "old snapshot inferred current milk from factory defaults")
assert(Tags.matches(Tags.forSnapshot(bottle, "Base.MilkBottle", "Food", nil, nil, true), {"ingredient"}),
    "captured full milk snapshot lost ingredient")
assert(not Tags.matches(Tags.forSnapshot(bottle, "Base.MilkBottle", "Food", nil, nil, false), {"ingredient"}),
    "captured empty milk snapshot regained ingredient")
assert(Tags.matches(Tags.forSnapshot(bottle, "Base.MilkBottle", "Food", nil, {ingredient = "add"}, false), {"ingredient"}),
    "explicit snapshot override lost to captured capability")
world.types["base.peanuts"] = {ingredient = "remove"}
assert(not Tags.matches(Tags.forScriptItem(peanuts), {"ingredient"}), "type removal did not override capability")
assert(Tags.matches(Tags.forItem(physical(peanuts, {ingredient = "add"})), {"ingredient"}),
    "instance addition did not override type removal")
assert(Tags.matches(Tags.forSnapshot(peanuts, "Base.Peanuts", "Food", nil, {ingredient = "add"}), {"ingredient"}),
    "snapshot addition did not override type removal")
world.types["base.peanuts"] = nil
assert(Tags.matches(Tags.forItem(physical(hops, {ingredient = "add"})), {"ingredient"}),
    "manual ingredient assignment did not override automatic absence")
local ingredientRule = assert(Tags.normalizeRule({include = {"ingredient"}}))
assert(Tags.matchesScriptRule(peanuts, ingredientRule) and not Tags.matchesScriptRule(hops, ingredientRule),
    "ingredient rule preview differs from automatic script capability")

-- The real picker must preview script capabilities, rather than broad imported
-- categories (both scripts deliberately have the same native Food category).
local nativeRequire = require
ISCollapsableWindowJoypad = {derive = function() return {} end}
getText = function(key) return key end
require = function(name)
    if name:sub(1, 5) == "ISUI/" then return true end
    if name == "PZSurvivorToolkit/TagVisuals" or name == "PZSurvivorToolkit/UIStyle" then return {} end
    return nativeRequire(name)
end
local Picker = dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/TagRulePicker.lua")
local rows = {}
local preview = {clear = function() rows = {} end, addItem = function(_, name) rows[#rows + 1] = name end}
local picker = {sourceScriptItems = {peanuts, hops}, rule = ingredientRule, preview = preview}
Picker.refreshPreview(picker)
assert(picker.matchCount == 1 and rows[1] == "Base.Peanuts", "ingredient picker preview selected wrong scripts")
require = nativeRequire
print("ingredient script/live/snapshot overrides and rule preview passed")

-- Optional native declaration check follows the installed B42.21 item-to-evolved
-- links and an ordinary baking recipe. The fixture adapter never creates items
-- or executes native recipe callbacks.
if NativeActionRoot then
    local generated = NativeActionRoot .. "/../scripts/generated/"
    local function read(path)
        local file = assert(io.open(generated .. path))
        local content = file:read("*a"); file:close(); return content
    end
    local foodText, evolvedText = read("items/food.txt"), read("evolvedrecipes.txt")
    evolvedText = evolvedText .. read("recipes/recipes_fishing_evolvedrecipe.txt")
    local additions, nativeDefinitions = {}, {}
    for name, block in foodText:gmatch("item%s+([%w_]+)%s*(%b{})") do
        local definition = scripts["Base." .. name] or script("Base." .. name)
        local hunger = tonumber(block:match("HungerChange%s*=%s*([^,]+)")) or 0
        local thirst = tonumber(block:match("ThirstChange%s*=%s*([^,]+)")) or 0
        definition.getHungerChange = function() return hunger end
        definition.getThirstChange = function() return thirst end
        nativeDefinitions["Base." .. name] = definition
        local links = block:match("EvolvedRecipe%s*=%s*([^,]+)") or ""
        for evolvedName, use in links:gmatch("([^;:]+):(%d+)") do
            if tonumber(use) > 0 then
                additions[evolvedName] = additions[evolvedName] or {}
                additions[evolvedName][#additions[evolvedName] + 1] = definition
            end
        end
    end
    local nativeEvolved = {}
    for _, block in evolvedText:gmatch("evolvedrecipe%s+([%w_]+)%s*(%b{})") do
        local baseName = block:match("BaseItem%s*=%s*([%w_.]+)")
        local resultName = block:match("ResultItem%s*=%s*([%w_.]+)")
        local template = block:match("Template%s*=%s*([^,]+)")
        if template then template = template:match("^%s*(.-)%s*$") end
        local base = baseName and (nativeDefinitions[baseName] or scripts[baseName] or script(baseName, "normal"))
        if base and resultName and nativeDefinitions[resultName] then
            nativeEvolved[#nativeEvolved + 1] = evolved(base, additions[template] or {},
                {result = nativeDefinitions[resultName], cookable = block:match("Cookable%s*=%s*true") ~= nil})
        end
    end
    evolvedRecipes = list(nativeEvolved)
    local baking = read("recipes/recipes_baking.txt")
    local cakeBlock
    for name, block in baking:gmatch("craftRecipe%s+([%w_]+)%s*(%b{})") do
        if name == "PlaceCakeInBakingPan" then cakeBlock = block end
    end
    assert(cakeBlock and cakeBlock:find("Base.CakeBatter", 1, true) and cakeBlock:find("Base.CakePrep", 1, true))
    local cookingTag = cakeBlock:match("Tags%s*=%s*([^,]+)"):find("Cooking", 1, true) ~= nil
    local xp = tonumber(cakeBlock:match("xpAward%s*=%s*Cooking:(%d+)"))
    craft = list({recipe({input({batter}), input({pot}, {destroy = true})},
        {output({assert(nativeDefinitions["Base.CakePrep"])})}, {cooking = cookingTag, xp = xp})})
    local drainable = read("items/drainable.txt")
    local powderBlock
    for name, block in drainable:gmatch("item%s+([%w_]+)%s*(%b{})") do
        if name == "AnimalMilkPowder" then powderBlock = block end
    end
    assert(powderBlock and powderBlock:match("ItemType%s*=%s*base:drainable"),
        "native milk powder is a Drainable ingredient, not Food")
    local cookingText, nativeMilk = read("recipes/recipes_cooking.txt"), {}
    for name, block in cookingText:gmatch("craftRecipe%s+([%w_]+)%s*(%b{})") do
        if name == "MakeMilkFromPowderBucket" or name == "MakeMilkFromPowderBottle" then
            local callback = block:match("OnCreate%s*=%s*([^,]+)")
            assert(callback == "RecipeCodeOnCreate.makeMilkFromPowder" and block:match("outputs%s*{%s*}"))
            local amount = block:match("item%s+(%d+)%s+%[Base%.AnimalMilkPowder%]")
            assert(amount and tonumber(amount) > 0, "native milk recipe no longer consumes powder")
            nativeMilk[#nativeMilk + 1] = recipe({input({powder}), input({pot}, {keep = true})}, {},
                {name = name, onCreate = callback})
        end
    end
    assert(#nativeMilk == 2, "native milk recipe variants missing")
    local bakingRecipe = craft:get(0)
    nativeMilk[#nativeMilk + 1] = bakingRecipe
    craft = list(nativeMilk)
    cooking.invalidate()
    for _, definition in ipairs({meat, vegetable, peanuts, flour, sugar, salt, oil, honey, openCan, bread, batter, powder}) do
        expect(definition, true)
    end
    for _, definition in ipairs({hops, closedCan, pot, jar, fuel, chum, bait}) do expect(definition, false) end
    print("native B42.21 evolved food links, ordinary baking and callback-only milk declarations checked")
else
    print("SKIP native cooking declaration check (NativeActionRoot not supplied)")
end
print("item cooking tags tests passed")
