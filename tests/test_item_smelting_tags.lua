local scans, boot = 0
Events = {OnGameBoot = {Add = function(fn) boot = fn end}}
ResourceType = {Item = "item", Fluid = "fluid"}
toolkitRecipeOnCreate = function(recipe) return recipe.create end
toolkitRecipeHasItemTest = function(recipe) return recipe.tested end
InventoryItemFactory = {CreateItem = function() error("classification must not create items") end}
local function list(values)
    return {size = function() return #values end,
        get = function(_, i) scans = scans + 1; return values[i + 1] end}
end
local scripts = {}
local function script(name)
    local value = {tags = {}, getFullName = function() return name end,
        getMetalValue = function() error("MetalValue does not prove a smelting recipe") end}
    scripts[#scripts + 1] = value
    return value
end
local bell, steel = script("Base.Bell"), script("Base.Kettle")
local ore, bloom, copper = script("Base.IronOre"), script("Base.IronBloom"), script("Base.CopperOre")
local nails, tin = script("Base.Nails"), script("Base.TinCanEmpty")
local glass, sand = script("Base.BrokenGlass"), script("Base.Sandbag")
local crucible, tongs = script("Base.CeramicCrucible"), script("Base.Tongs")
local charcoal, coke, lime = script("Base.Charcoal"), script("Base.Coke"), script("Base.Limestone")
local fire, gold, other = script("Base.Lighter"), script("Base.GoldScrap"), script("Mod.OtherSmelting")
local function input(choices, options)
    options = options or {}
    local value = {choices = choices}
    value.getResourceType = function() return options.resource or ResourceType.Item end
    value.getPossibleInputItems = function() return list(value.choices) end
    value.getIntAmount = function() return options.amount or 1 end
    value.isUsesPartialItem = function(_, definition)
        if options.itemCount or options.destroy or options.keep then return false end
        return options.partial == true or definition.drainable == true and (definition.useDelta or 1) < 1
    end
    for method, option in pairs({isKeep = "keep", isTool = "tool", isApplyOnTick = "tick",
        hasConsumeFromItem = "consume", hasCreateToItem = "create", isReplace = "replace"}) do
        local key = option
        value[method] = function() return options[key] == true end
    end
    value.doesItemPassRoutineStatusTests = function(_, item, ...)
        assert(select("#", ...) == 1 and ... == nil, "native routine predicate needs nullable character")
        return not item.broken or options.destroyed == true
    end
    for _, method in ipairs({"doesItemPassClothingTypeStatusTests", "doesItemPassSharpnessStatusTests",
        "doesItemPassDamageStatusTests", "doesItemPassIsOrNotEmptyAndFullTests", "doesItemPassFoodAndCookingTests"}) do
        local predicate = method
        value[method] = function(_, item, ...)
            assert(item and select("#", ...) == 0, "native status predicate accepts only an item")
            return not item.rejected and item.rejectMethod ~= predicate
        end
    end
    return value
end
local function recipe(name, inputs, handler, tested, modded)
    return {getName = function() return name end, getInputs = function() return list(inputs) end,
        isVanilla = function() return modded ~= true end,
        create = handler and "RecipeCodeOnCreate." .. handler, tested = tested or false,
        canUseItem = function() error("general recipe validation may consume/test items") end,
        OnCreate = function() error("recipe creation callback must not execute") end,
        OnTest = function() error("recipe item callback must not execute") end}
end
local function furnace(subject)
    return {input({crucible}, {keep = true}), input({tongs}, {keep = true}), input({charcoal}), subject}
end
local recipes = list({
    recipe("ExtractIronFromSmallItem", furnace(input({bell}, {destroyed = true}))),
    recipe("SmeltSmallSteelItem", furnace(input({steel}, {destroyed = true})), "smeltIronOrSteelSmall"),
    recipe("SmeltCopperOre", {input({charcoal}), input({copper})}),
    recipe("ExtractIronBloom", {input({charcoal}), input({ore})}),
    recipe("ExtractIronFromIronBloom", furnace(input({bloom}, {destroyed = true}))),
    recipe("ExtractIronFromSmallerItems", furnace(input({nails}, {amount = 10}))),
    recipe("SmeltSmallerSteelItem", furnace(input({tin}, {amount = 10})), "smeltIronOrSteelSmall"),
    recipe("MeltGlass", {input({crucible}), input({tongs}, {keep = true}), input({glass}, {amount = 6}),
        input({fire}), input({charcoal})}),
    recipe("MeltSand", {input({crucible}), input({tongs}, {keep = true}), input({sand}, {partial = true}),
        input({fire}), input({charcoal})}),
    recipe("ModSmelt", furnace(input({other}))),
})
local manager = {getAllCraftRecipes = function() return recipes end}
getScriptManager = function() return manager end
local smelting = dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/ItemSmeltingTags.lua")
local function expect(definition, expected, item, variable)
    local actual, states = smelting.read(definition, item)
    assert(actual == expected, definition:getFullName() .. " smelting role differs")
    if variable then assert(states and #states == 2 and states[1] == false and states[2] == true,
        "partial material preview must include empty/nonempty states")
    else assert(states == nil, "fixed material must not acquire variable states") end
end
for _, definition in ipairs({bell, steel, ore, bloom, copper, nails, tin, glass}) do expect(definition, true) end
for _, definition in ipairs({crucible, tongs, charcoal, coke, lime, fire, gold, other}) do expect(definition, nil) end
expect(bell, true, {broken = true})
expect(copper, false, {broken = true})
expect(bell, false, {rejected = true})
for _, method in ipairs({"doesItemPassClothingTypeStatusTests", "doesItemPassSharpnessStatusTests",
    "doesItemPassDamageStatusTests", "doesItemPassIsOrNotEmptyAndFullTests", "doesItemPassFoodAndCookingTests"}) do
    expect(bell, false, {rejectMethod = method})
end
expect(sand, nil, nil, true)
expect(sand, false, {getCurrentUses = function() return 0 end})
expect(sand, true, {getCurrentUses = function() return 1 end})
expect(sand, nil, {})
local before = scans
for _ = 1, 100 do expect(bell, true, {}) end
assert(scans == before, "repeated classification must not rescan recipes")

-- Unknown overrides and unusable input roles must not establish a capability.
recipes = list({recipe("ExtractIronFromSmallItem", furnace(input({charcoal})), nil, false, true)})
expect(charcoal, nil)
recipes = list({recipe("ExtractIronFromSmallItem", furnace(input({other})))})
expect(other, true) -- Native subject choices can include a mod's tagged item.
for _, handler in ipairs({"modReplacement", "smeltIronOrSteelLarge"}) do
    recipes = list({recipe("SmeltSmallSteelItem", furnace(input({steel})), handler)})
    expect(steel, nil)
end
recipes = list({recipe("ExtractIronFromSmallItem", furnace(input({bell})), nil, true)})
expect(bell, nil)
for _, options in ipairs({{keep = true}, {tool = true}, {tick = true}, {consume = true},
    {create = true}, {replace = true}, {amount = 0}, {resource = ResourceType.Fluid}}) do
    recipes = list({recipe("ExtractIronFromSmallItem", furnace(input({bell}, options)))})
    expect(bell, nil)
end
recipes = list({recipe("ExtractIronFromSmallItem", {input({bell})})})
expect(bell, nil)
recipes = list({recipe("ExtractIronFromSmallItem", furnace(input({bell})))})
local createBridge, testBridge = toolkitRecipeOnCreate, toolkitRecipeHasItemTest
toolkitRecipeOnCreate = nil
expect(bell, nil)
toolkitRecipeOnCreate = createBridge
toolkitRecipeHasItemTest = function() return nil end
expect(bell, nil)
toolkitRecipeHasItemTest = testBridge
expect(bell, true)
getScriptManager = function() return nil end
expect(bell, nil)
getScriptManager = function() return manager end

-- Same catalog/list identity and count may precede resolution of native tags.
local unresolved = input({})
recipes = list({recipe("ExtractIronFromSmallItem", furnace(unresolved))})
expect(bell, nil)
unresolved.choices = {bell}
expect(bell, true)
assert(type(boot) == "function")
unresolved.choices = {other}
expect(bell, true) -- Catalog remains stable until the native boot/reload boundary.
boot()
expect(bell, nil)
expect(other, true)

if NativeActionRoot then
    local generated = NativeActionRoot .. "/../scripts/generated/"
    for _, filename in ipairs({"normal.txt", "drainable.txt", "weapon.txt"}) do
        local source = assert(io.open(generated .. "items/" .. filename))
        local text = source:read("*a"); source:close()
        for name, block in text:gmatch("item%s+([%w_]+)%s*(%b{})") do
            for _, definition in ipairs(scripts) do
                if definition:getFullName() == "Base." .. name then
                    definition.drainable = block:match("ItemType%s*=%s*base:drainable") ~= nil
                    definition.useDelta = tonumber(block:match("UseDelta%s*=%s*([%d%.]+)"))
                    for tag in (block:match("Tags%s*=%s*([^,]+)") or ""):gmatch("[%w_:]+") do
                        definition.tags[tag] = true
                    end
                end
            end
        end
    end
    local native = {}
    for _, filename in ipairs({"recipes_blacksmith_furnaces_i.txt", "recipes_blacksmith_furnace_ii.txt",
        "recipes_blacksmith_ii.txt", "recipes_blacksmith_other_metals.txt"}) do
        local source = assert(io.open(generated .. "entities/blacksmith/craftRecipes/" .. filename))
        local text = source:read("*a"); source:close()
        for name, block in text:gmatch("craftRecipe%s+([%w_]+)%s*(%b{})") do
            local inputs = {}
            for line in (block:match("inputs%s*(%b{})") or ""):gmatch("[^\r\n]+") do
                local amount, body = line:match("item%s+(%d+)%s+(.-),")
                if amount then
                    local choices, tags = {}, body:match("tags%[(.-)%]")
                    for _, definition in ipairs(scripts) do
                        local matches = false
                        for id in (tags or body:match("%[(.-)%]") or ""):gmatch("[^;]+") do
                            id = id:gsub("^%d+:", "")
                            if tags and definition.tags[id] or not tags and definition:getFullName() == id then matches = true end
                        end
                        if matches then choices[#choices + 1] = definition end
                    end
                    inputs[#inputs + 1] = input(choices, {amount = tonumber(amount),
                        keep = body:find("mode:keep", 1, true) ~= nil,
                        destroy = body:find("mode:destroy", 1, true) ~= nil,
                        itemCount = body:find("ItemCount", 1, true) ~= nil,
                        destroyed = body:find("AllowDestroyedItem", 1, true) ~= nil})
                end
            end
            native[#native + 1] = recipe(name, inputs, block:match("OnCreate%s*=%s*RecipeCodeOnCreate%.([%w_]+)"))
        end
    end
    recipes = list(native)
    for _, definition in ipairs({bell, steel, ore, bloom, copper, nails, tin, glass}) do expect(definition, true) end
    expect(bell, true, {broken = true})
    expect(sand, nil, nil, true)
    expect(sand, false, {getCurrentUses = function() return 0 end})
    expect(sand, true, {getCurrentUses = function() return 1 end})
    -- Some tools are also genuine material subjects in a separate native recipe.
    -- These checks only exclude supplies that have no independently smeltable role.
    for _, definition in ipairs({crucible, charcoal, coke, lime, fire, gold, other}) do expect(definition, nil) end
    print("native B42.21 furnace material declarations checked")
else
    print("SKIP native furnace declarations (NativeActionRoot not supplied)")
end
print("item smelting tags tests passed")
