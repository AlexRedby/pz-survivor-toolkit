require = function() end
next = nil -- Native Kahlua does not provide next.
local function list(values)
    return {size = function() return #values end, get = function(_, index) return values[index + 1] end}
end
local bodies = {
OpenCannedFood = [[
craftRecipe OpenCannedFood
    {
        timedAction = OpenTinCan,
        time = 100,
        OnCreate = RecipeCodeOnCreate.openAndEat,
        Tags = InHandCraft;CanBeDoneInDark,
        category = Cooking,
        inputs
        {
            item 1 tags[base:canopener] mode:keep flags[MayDegradeLight],
            item 1 [Base.TinnedBeans;Base.CannedBolognese;Base.CannedCarrots2;Base.CannedChili;Base.CannedCorn;Base.CannedFruitCocktail;Base.CannedFruitBeverage;Base.CannedMilk;Base.CannedMushroomSoup;Base.CannedPeaches;Base.CannedPeas;Base.CannedPineapple;Base.CannedPotato2;Base.TinnedSoup;Base.CannedTomato2;Base.TunaTin;Base.Dogfood] mappers[canSorts] flags[Prop2;DontPutBack],
        }
        outputs
        {
            item 1 mapper:canSorts,
        }
        itemMapper canSorts
        {
            Base.OpenBeans = Base.TinnedBeans,
            Base.CannedBologneseOpen = Base.CannedBolognese,
            Base.CannedCarrotsOpen = Base.CannedCarrots2,
            Base.CannedChiliOpen = Base.CannedChili,
            Base.CannedCornOpen = Base.CannedCorn,
            Base.CannedFruitCocktailOpen = Base.CannedFruitCocktail,
            Base.CannedFruitBeverageOpen = Base.CannedFruitBeverage,
            Base.CannedMilkOpen = Base.CannedMilk,
            Base.CannedMushroomSoupOpen = Base.CannedMushroomSoup,
            Base.CannedPeachesOpen = Base.CannedPeaches,
            Base.CannedPeasOpen = Base.CannedPeas,
            Base.CannedPineappleOpen = Base.CannedPineapple,
            Base.CannedPotatoOpen = Base.CannedPotato2,
            Base.TinnedSoupOpen = Base.TinnedSoup,
            Base.CannedTomatoOpen = Base.CannedTomato2,
            Base.TunaTinOpen = Base.TunaTin,
            Base.DogfoodOpen = Base.Dogfood,
        }
    }
]],
OpenCannedFood2 = [[
craftRecipe OpenCannedFood2
    {
        timedAction = OpenTinCan,
        time = 10,
        OnCreate = RecipeCodeOnCreate.openAndEat,
        Tags = InHandCraft;CanBeDoneInDark,
        category = Cooking,
        inputs
        {
            item 1 [Base.CannedCornedBeef;Base.CannedSardines] mappers[canSorts] flags[Prop2;DontPutBack],
        }
        outputs
        {
            item 1 mapper:canSorts,
        }
        itemMapper canSorts
        {
            Base.CannedCornedBeefOpen = Base.CannedCornedBeef,
            Base.CannedSardinesOpen = Base.CannedSardines,
        }
    }
]],
}
local function read(path)
    if NativeReadText then return NativeReadText(path) end
    local file = assert(io.open(path)); local source = file:read("*a"); file:close(); return source
end
if NativeActionRoot then
    local source = read(NativeActionRoot .. "/../scripts/generated/recipes/recipes_cannedFood.txt")
    for name, fixture in pairs(bodies) do
        local body = source:match("craftRecipe%s+" .. name .. "%s*(%b{})")
        assert(body, "native canned recipe must be present")
        local actual = "craftRecipe " .. name .. body
        assert(actual:gsub("%s+", "") == fixture:gsub("%s+", ""), "fixture must match real native parsed body")
        bodies[name] = actual
    end
end
local client, server, originalCalls, received, sent = false, false, 0, {}, {}
isClient, isServer = function() return client end, function() return server end
instanceof = function(value, kind) return value and value.class == kind end
sendServerCommand = function(character, module, command, args)
    sent[#sent + 1] = {character = character, module = module, command = command, args = args}
end
PZSurvivorToolkit = {}
local character = {class = "IsoPlayer", getOnlineID = function() return 27 end}
local recipes = {}
local mappedOutput = {getFullName = function() return "Base.OpenBeans" end}
local outputScript = {getItem = function() return mappedOutput end}
for name, body in pairs(bodies) do
    local recipe = {name = name, bodies = {"pz-vanilla", body}}
    function recipe:getName() return self.name end
    function recipe:getScriptObjectFullType() return (self.module or "Base") .. "." .. self.name end
    function recipe:getLoadedScriptBodies() return list(self.bodies) end
    function recipe:getOutputs() return list({outputScript}) end
    recipes[name], recipes["Base." .. name] = recipe, recipe
end
getScriptManager = function() return {getCraftRecipe = function(_, name) return recipes[name] end} end
local function item(id, fullType, opening)
    return {class = "Food", getID = function() return id end,
        getFullType = function() return fullType end, getOpeningRecipe = function() return opening end,
        getScriptItem = function() return {isCantEat = function() return opening ~= nil end} end}
end
local sealed = item(101, "Base.TinnedBeans", "OpenCannedFood")
local opened = item(202, "Base.OpenBeans")
local recipe = recipes.OpenCannedFood
local data = {recipe = recipe, consumed = {sealed}, created = {opened}, prop2 = sealed, eatPercentage = 0}
function data:getEatPercentage() return self.eatPercentage end
function data:getRecipe() return self.recipe end
function data:getAllConsumedItems() return list(self.consumed) end
function data:getAllCreatedItems() return list(self.created) end
function data:getFirstInputItemWithFlag(flag) assert(flag == "Prop2"); return self.prop2 end
local nativeOriginal = function(actual, player)
    assert(actual == data and player == character)
    originalCalls = originalCalls + 1
    return "native", nil, 9
end
RecipeCodeOnCreate = {openAndEat = nativeOriginal}
local path = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/PackagedFood.lua"
local className = getClassSimpleName
getClassSimpleName = function(callback)
    if callback == nativeOriginal then return "LuaJavaInvoker" end
    if className then return className(callback) end
    return "LuaClosure"
end
local installedLua = function(...) return nativeOriginal(...) end
RecipeCodeOnCreate.openAndEat = installedLua
local rejected = assert(loadfile(path))()
assert(RecipeCodeOnCreate.openAndEat == installedLua and not rejected.supports(recipe) and not rejected.recipe(sealed),
    "a preinstalled Lua wrapper must remain untouched and cannot grant packaged permissions")
PZSurvivorToolkit.PackagedFood = nil
RecipeCodeOnCreate.openAndEat = nativeOriginal
local api = assert(loadfile(path))()
getClassSimpleName = className
local wrapped = RecipeCodeOnCreate.openAndEat
assert(assert(loadfile(path))() == api and RecipeCodeOnCreate.openAndEat == wrapped, "reload cannot stack wrappers")
for name in pairs(bodies) do assert(api.supports(recipes[name]), "exact native recipe body is supported") end
assert(not api.supports(nil) and not api.supports({}), "malformed recipes fail closed")
assert(api.recipe(sealed) == recipe and not api.recipe(opened) and not api.recipe(nil))
api.onOpened = function(player, args)
    assert(player == character)
    received[#received + 1] = args
end
local first, empty, last = wrapped(data, character)
assert(first == "native" and empty == nil and last == 9 and originalCalls == 1,
    "observer preserves native callback and its return tuple")
assert(#received == 1 and received[1].sourceID == 101 and received[1].outputID == 202
    and received[1].recipe == "OpenCannedFood" and received[1].outputType == "Base.OpenBeans")
local function rejects(change, undo)
    local before, nativeBefore = #received + #sent, originalCalls
    change(); wrapped(data, character); undo()
    assert(#received + #sent == before and originalCalls == nativeBefore + 1,
        "rejection emits no receipt and still runs the native callback")
end
rejects(function() data.eatPercentage = 50 end, function() data.eatPercentage = 0 end)
rejects(function() client = true end, function() client = false end)
rejects(function() data.consumed = {} end, function() data.consumed = {sealed} end)
rejects(function() data.consumed = {sealed, sealed} end, function() data.consumed = {sealed} end)
rejects(function() data.created = {} end, function() data.created = {opened} end)
rejects(function() data.created = {opened, opened} end, function() data.created = {opened} end)
rejects(function() data.created = {sealed} end, function() data.created = {opened} end)
local wrong = item(303, "Base.CannedCornOpen")
rejects(function() data.created = {wrong} end, function() data.created = {opened} end)
rejects(function() opened.class = "InventoryItem" end, function() opened.class = "Food" end)
rejects(function() sealed.class = "InventoryItem" end, function() sealed.class = "Food" end)
rejects(function() data.prop2 = wrong end, function() data.prop2 = sealed end)
local expectedOutput = mappedOutput
rejects(function() mappedOutput = nil end, function() mappedOutput = expectedOutput end)
local originalBody = recipe.bodies[2]
rejects(function() recipe.bodies[2] = originalBody:gsub("time = 100", "time = 101") end,
    function() recipe.bodies[2] = originalBody end)
rejects(function() recipe.bodies = {"pz-vanilla", originalBody, "merged-mod", "time = 5,"} end,
    function() recipe.bodies = {"pz-vanilla", originalBody} end)
rejects(function() recipe.bodies[1] = "another-mod" end, function() recipe.bodies[1] = "pz-vanilla" end)
rejects(function() recipe.module = "Mod" end, function() recipe.module = nil end)
local second = recipes.OpenCannedFood2
local sardines = item(401, "Base.CannedSardines", "Base.OpenCannedFood2")
local sardinesOpen = item(402, "Base.CannedSardinesOpen")
data.recipe, data.consumed, data.created, data.prop2 = second, {sardines}, {sardinesOpen}, sardines
mappedOutput = {getFullName = function() return "Base.CannedSardinesOpen" end}
wrapped(data, character)
assert(received[#received].sourceID == 401 and received[#received].outputID == 402
    and received[#received].recipe == "OpenCannedFood2", "tab-opening native recipe uses its exact source and output")
data.recipe, data.consumed, data.created, data.prop2 = recipe, {sealed}, {opened}, sealed
mappedOutput = expectedOutput
server = true
wrapped(data, character)
assert(#sent == 1 and sent[1].character == character and sent[1].module == "PZSurvivorToolkitFood"
    and sent[1].command == "Opened" and sent[1].args.onlineID == 27 and sent[1].args.sourceID == 101
    and sent[1].args.outputID == 202, "server emits only its authoritative native callback receipt")
rejects(function() character.class = "IsoGameCharacter" end, function() character.class = "IsoPlayer" end)
server = false
api.onOpened = function() error("observer failure") end
local nativeBefore = originalCalls
assert(pcall(wrapped, data, character) and originalCalls == nativeBefore + 1, "observer errors cannot fail native craft")
RecipeCodeOnCreate.openAndEat = function() end
assert(not api.supports(recipe) and not api.recipe(sealed), "changed wrapper ownership disables support")
wrapped(data, character)
assert(#sent == 1, "stale observer cannot emit after callback ownership changes")
PZSurvivorToolkit.PackagedFood = nil
RecipeCodeOnCreate = {openAndEat = nativeOriginal}
getClassSimpleName = nil
local unknownClass = assert(loadfile(path))()
assert(RecipeCodeOnCreate.openAndEat == nativeOriginal and not unknownClass.supports(recipe),
    "missing native callback class exposure must disable packaged permissions")
-- A different JavaFunction class is not a recipe method exposed by LuaJavaInvoker.
PZSurvivorToolkit.PackagedFood = nil
RecipeCodeOnCreate = {openAndEat = assert}
getClassSimpleName = function() return "BaseLib" end
local wrongClass = assert(loadfile(path))()
assert(RecipeCodeOnCreate.openAndEat == assert and not wrongClass.supports(recipe),
    "another JavaFunction class cannot acquire native opening permissions")
-- Stock exposure can group native Java overloads in a MultiLuaJavaInvoker.
PZSurvivorToolkit.PackagedFood = nil
RecipeCodeOnCreate = {openAndEat = nativeOriginal}
getClassSimpleName = function(value) return value == nativeOriginal and "MultiLuaJavaInvoker" or "LuaClosure" end
local overload = assert(loadfile(path))()
getClassSimpleName = className
assert(RecipeCodeOnCreate.openAndEat ~= nativeOriginal and overload.supports(recipe),
    "the native opening method remains supported when exposed as a Java overload group")
print("Packaged food receipt checks passed: native recipe fingerprints, exact IDs, callback preservation, rejection and server authority.")
