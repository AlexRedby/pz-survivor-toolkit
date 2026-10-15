require "PZSurvivorToolkit"

local Toolkit = PZSurvivorToolkit
if Toolkit.PackagedFood then return Toolkit.PackagedFood end
local Food = {}
Toolkit.PackagedFood = Food
local original = RecipeCodeOnCreate and RecipeCodeOnCreate.openAndEat
local observer
local nativeRecipes = {
    OpenCannedFood = {hash = 4075612807, length = 1321},
    OpenCannedFood2 = {hash = 311923403, length = 388},
}

local function supported(recipe)
    if not observer or RecipeCodeOnCreate.openAndEat ~= observer or not recipe then return false end
    local name = recipe:getName()
    local expected = nativeRecipes[name]
    if not expected or recipe:getScriptObjectFullType() ~= "Base." .. name then return false end
    local bodies = recipe:getLoadedScriptBodies()
    if not bodies or bodies:size() ~= 2 or bodies:get(0) ~= "pz-vanilla" then return false end
    local source = bodies:get(1)
    if source == expected.verifiedBody then return true end
    local body = source:gsub("%s+", "")
    if #body ~= expected.length then return false end
    local a, b = 1, 0
    for i = 1, #body do
        a = (a + body:byte(i)) % 65521
        b = (b + a) % 65521
    end
    if b * 65536 + a ~= expected.hash then return false end
    expected.verifiedBody = source
    return true
end

function Food.supports(recipe)
    local ok, result = pcall(supported, recipe)
    return ok and result == true
end

function Food.recipe(item)
    if not item or not item.getOpeningRecipe then return nil end
    local name = item:getOpeningRecipe()
    if not name or name == "" then return nil end
    local recipe = getScriptManager():getCraftRecipe(name)
    if Food.supports(recipe) then return recipe end
end

local function opened(data, character)
    if isClient() or not character or data:getEatPercentage() > 0 then return end
    local recipe = data:getRecipe()
    if not Food.supports(recipe) then return end
    local consumed, created = data:getAllConsumedItems(), data:getAllCreatedItems()
    if consumed:size() ~= 1 or created:size() ~= 1 then return end
    local source, output = consumed:get(0), created:get(0)
    if not instanceof(source, "Food") or not instanceof(output, "Food") or source == output
        or data:getFirstInputItemWithFlag("Prop2") ~= source or Food.recipe(source) ~= recipe
        or not source:getScriptItem():isCantEat() then return end
    local outputs = recipe:getOutputs()
    if outputs:size() ~= 1 then return end
    local expected = outputs:get(0):getItem(data)
    if not expected or output:getFullType() ~= expected:getFullName() then return end
    local sourceID, outputID = source:getID(), output:getID()
    if type(sourceID) ~= "number" or type(outputID) ~= "number" or sourceID == outputID
        or sourceID ~= math.floor(sourceID) or outputID ~= math.floor(outputID) then return end
    local args = {sourceID = sourceID, outputID = outputID, recipe = recipe:getName(),
        outputType = output:getFullType()}
    if isServer() then
        if not instanceof(character, "IsoPlayer") then return end
        args.onlineID = character:getOnlineID()
        sendServerCommand(character, "PZSurvivorToolkitFood", "Opened", args)
    elseif Food.onOpened then
        Food.onOpened(character, args)
    end
end

local originalClass = original and getClassSimpleName and getClassSimpleName(original)
if originalClass == "LuaJavaInvoker" or originalClass == "MultiLuaJavaInvoker" then
    local function pack(...) return {n = select("#", ...), ...} end
    observer = function(data, character)
        local result = pack(original(data, character))
        -- A receipt observer must never interrupt the native crafting transaction.
        pcall(opened, data, character)
        return unpack(result, 1, result.n)
    end
    RecipeCodeOnCreate.openAndEat = observer
end

return Food
