local scans, boot = 0
Events = {OnGameBoot = {Add = function(fn) boot = fn end}}
ItemType = {NORMAL = "normal", DRAINABLE = "drainable"}
ResourceType = {Item = "item", Fluid = "fluid"}
toolkitRecipeOnCreate = function(recipe) return recipe.create end
toolkitRecipeHasItemTest = function(recipe) return recipe.tested end
local function list(values)
    return {size = function() return #values end,
        get = function(_, i) scans = scans + 1; return values[i + 1] end}
end
local scripts = {}
local function script(name, kind)
    local value = {tags = {}, getFullName = function() return name end,
        isItemType = function(_, expected) return expected == (kind or ItemType.NORMAL) end}
    scripts[#scripts + 1] = value
    return value
end
local glue, tape = script("Base.Glue", "drainable"), script("Base.Scotchtape")
local duct, wood = script("Base.DuctTape", "drainable"), script("Base.Woodglue", "drainable")
local epoxy, fiber = script("Base.Epoxy", "drainable"), script("Base.FiberglassTape", "drainable")
local ties, rags, denim = script("Base.Zipties"), script("Base.RippedSheets"), script("Base.DenimStrips")
local bat, scissors = script("Base.BaseballBat"), script("Base.Scissors")
local file, stone, gun = script("Base.File"), script("Base.Whetstone"), script("Base.Pistol")
local other = script("Mod.UnrelatedRepairSupply")
local function input(choices, options)
    options = options or {}
    return {getResourceType = function() return options.resource or ResourceType.Item end,
        isKeep = function() return options.keep == true end,
        isDamaged = function() return options.damaged == true end,
        isTool = function() return options.tool == true end,
        isApplyOnTick = function() return options.tick == true end,
        hasConsumeFromItem = function() return options.consume == true end,
        hasCreateToItem = function() return options.create == true end,
        isReplace = function() return options.replace == true end,
        getIntAmount = function() return options.amount or 1 end,
        getPossibleInputItems = function() return list(choices) end}
end
local function subject() return input({bat}, {keep = true, damaged = true}) end
local function recipe(name, inputs, handler, tested)
    return {getName = function() return name end, getInputs = function() return list(inputs) end,
        create = handler and "RecipeCodeOnCreate." .. handler, tested = tested or false,
        getCategory = function() error("repair UI category is not a supply role") end,
        OnCreate = function() error("repair callback must not execute") end,
        OnTest = function() error("repair predicate must not execute") end}
end
local recipes = list({
    recipe("FixWithGlue", {subject(), input({glue}, {amount = 2})}, "genericFixing"),
    recipe("FixWithAdhesiveTape", {subject(), input({tape}, {amount = 3})}, "genericFixing"),
    recipe("FixWithDuctTape", {subject(), input({duct})}, "genericBetterFixing"),
    recipe("FixWithWoodGlue", {subject(), input({wood})}, "genericBetterFixing"),
    recipe("FixWithZipties", {subject(), input({ties})}, "genericFixing"),
    recipe("FixWithEpoxy", {input({scissors}, {keep = true}), subject(), input({epoxy}), input({fiber})},
        "genericEvenBetterFixing"),
    recipe("FixWithEpoxyAndRags", {subject(), input({epoxy}), input({rags, denim}, {amount = 2})}, "genericFixing"),
    recipe("SharpenBlade", {input({bat}, {keep = true}), input({stone}, {keep = true})}, "sharpenBlade"),
    recipe("FixSaw", {subject(), input({file}, {keep = true})}, "sharpenBlade"),
    recipe("ModOtherRepair", {subject(), input({other})}, "genericFixing"),
})
local manager = {getAllCraftRecipes = function() return recipes end}
getScriptManager = function() return manager end
InventoryItemFactory = {CreateItem = function() error("tagging must not construct inventory items") end}
local repair = dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/ItemRepairTags.lua")
local function expect(definition, expected, item, variable)
    local actual, possible = repair.read(definition, item)
    assert(actual == expected, definition:getFullName() .. " repair supply role differs")
    if variable then assert(possible and #possible == 2 and possible[1] == false and possible[2] == true,
        "drainable script preview must include both remaining-use states")
    else assert(possible == nil, "fixed supply must not gain variable states") end
end
local function physical(uses, drainable)
    return {IsDrainable = function() return drainable ~= false end, getCurrentUses = function() return uses end}
end
for _, definition in ipairs({glue, duct, wood, epoxy, fiber}) do
    expect(definition, nil, nil, true)
    expect(definition, false, physical(0))
    -- The supply role survives having less than the recipe's required amount.
    expect(definition, true, physical(1))
    expect(definition, true, physical(12))
end
for _, definition in ipairs({tape, ties, rags, denim}) do
    expect(definition, true)
    expect(definition, true, physical(1, false))
end
for _, definition in ipairs({bat, scissors, file, stone, gun, other}) do expect(definition, nil) end
local before = scans
for _ = 1, 100 do expect(glue, true, physical(1)) end
assert(scans == before, "repeated repair tagging must not rescan the recipe catalog")

-- Current callback metadata controls native semantics; names and category alone
-- cannot prove arbitrary overridden or mod callbacks are repair operations.
for _, handler in ipairs({"ModReplacedHandler", "genericBetterFixing"}) do
    recipes = list({recipe("FixWithGlue", {subject(), input({glue})}, handler)})
    expect(glue, nil)
end
recipes = list({recipe("FixWithGlue", {subject(), input({glue})}, "genericFixing", true)})
expect(glue, nil)
recipes = list({recipe("FixWithGlue", {subject(), input({glue})}, "genericFixing")})
local createBridge, testBridge = toolkitRecipeOnCreate, toolkitRecipeHasItemTest
toolkitRecipeOnCreate = nil
expect(glue, nil)
toolkitRecipeOnCreate = createBridge
expect(glue, true, physical(1))
toolkitRecipeHasItemTest = function() return nil end
expect(glue, nil)
toolkitRecipeHasItemTest = testBridge
expect(glue, true, physical(1))
getScriptManager = function() return nil end
expect(glue, nil)
getScriptManager = function() return manager end
expect(glue, true, physical(1))

for _, options in ipairs({{keep = true}, {tool = true}, {tick = true}, {consume = true},
    {create = true}, {replace = true}, {amount = 0}}) do
    recipes = list({recipe("FixWithGlue", {subject(), input({glue}, options)}, "genericFixing")})
    expect(glue, nil)
end
for _, inputs in ipairs({{input({glue})}, {input({bat}, {damaged = true}), input({glue})},
    {subject(), subject(), input({glue})}, {subject(), input({glue}, {resource = ResourceType.Fluid})}}) do
    recipes = list({recipe("FixWithGlue", inputs, "genericFixing")})
    expect(glue, nil)
end
assert(type(boot) == "function")
boot()

-- Read the installed declarations into the same metadata fixtures. This checks
-- genuine supply choices and the normal (non-drainable) Scotchtape definition.
if NativeActionRoot then
    local generated = NativeActionRoot .. "/../scripts/generated/"
    for _, name in ipairs({"normal.txt", "drainable.txt", "weapon.txt"}) do
        local source = assert(io.open(generated .. "items/" .. name))
        local text = source:read("*a"); source:close()
        for nativeName, block in text:gmatch("item%s+([%w_]+)%s*(%b{})") do
            for _, definition in ipairs(scripts) do
                if definition:getFullName() == "Base." .. nativeName then
                    local kind = assert(block:match("ItemType%s*=%s*base:([%w_]+)"))
                    definition.isItemType = function(_, expected) return kind == expected end
                    for tag in (block:match("Tags%s*=%s*([^,]+)") or ""):gmatch("[%w_:]+") do
                        definition.tags[tag] = true
                    end
                end
            end
        end
    end
    local source = assert(io.open(generated .. "recipes/recipes_fixing.txt"))
    local text = source:read("*a"); source:close()
    local native = {}
    for name, block in text:gmatch("craftRecipe%s+([%w_]+)%s*(%b{})") do
        local inputs = {}
        for line in (block:match("inputs%s*(%b{})") or ""):gmatch("[^\r\n]+") do
            local amount, body = line:match("item%s+(%d+)%s+(.-),")
            if amount then
                local choices = {}
                local tags = body:match("tags%[(.-)%]")
                for _, definition in ipairs(scripts) do
                    local matches = false
                    for id in (tags or body:match("%[(.-)%]") or ""):gmatch("[^;]+") do
                        if tags and definition.tags[id] or not tags and definition:getFullName() == id then matches = true end
                    end
                    if matches then choices[#choices + 1] = definition end
                end
                inputs[#inputs + 1] = input(choices, {amount = tonumber(amount),
                    keep = body:find("mode:keep", 1, true) ~= nil,
                    damaged = body:find("IsDamaged", 1, true) ~= nil})
            end
        end
        native[#native + 1] = recipe(name, inputs, block:match("OnCreate%s*=%s*RecipeCodeOnCreate%.([%w_]+)"))
    end
    recipes = list(native)
    for _, definition in ipairs({glue, duct, wood, epoxy, fiber}) do expect(definition, nil, nil, true) end
    for _, definition in ipairs({tape, ties, rags, denim}) do expect(definition, true) end
    for _, definition in ipairs({bat, scissors, file, stone, gun, other}) do expect(definition, nil) end
    print("native B42.21 repair supply declarations checked")
else
    print("SKIP native repair declarations (NativeActionRoot not supplied)")
end
print("item repair supply tags tests passed")
