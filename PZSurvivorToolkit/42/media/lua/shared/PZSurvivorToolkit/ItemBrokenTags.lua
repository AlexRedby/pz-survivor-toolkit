-- Native broken state, independent of remaining uses, food quality or damage.
-- In B42 isBroken reads the stored flag; condition is not its replacement.
local Broken = {}
local catalog
local wearFlags = {"mayDegrade", "mayDegradeLight", "mayDegradeVeryLight", "mayDegradeHeavy"}

local function wearsInput(input)
    if not ResourceType or not input.getResourceType or input:getResourceType() ~= ResourceType.Item
        or not input.isKeep or input:isKeep() ~= true then return false end
    -- CraftRecipeData applies these four native damage checks to kept inputs.
    -- ToolLeft/ToolRight alone do not enter that branch. These getters only
    -- inspect InputFlag metadata; no recipe or item callback is evaluated.
    for _, method in ipairs(wearFlags) do
        if input[method] and input[method](input) == true then return true end
    end
    return false
end

local function indexRecipes(context)
    if not ResourceType or not ResourceType.Item then return nil end
    local manager = getScriptManager and getScriptManager()
    if not manager or not manager.getAllCraftRecipes then return nil end
    local recipes
    if context then recipes = context:recipes(manager, "getAllCraftRecipes")
    else recipes = manager:getAllCraftRecipes() end
    if not recipes then return nil end
    local count = recipes:size()
    if catalog and catalog.manager == manager and catalog.recipes == recipes and catalog.count == count then
        return catalog.byType
    end
    local byType, ready = {}, count > 0
    for i = 0, count - 1 do
        local recipe = recipes:get(i)
        local inputs = recipe.getInputs and recipe:getInputs()
        if not inputs then ready = false
        else
            for j = 0, inputs:size() - 1 do
                local input = inputs:get(j)
                if wearsInput(input) then
                    local choices = input.getPossibleInputItems and input:getPossibleInputItems()
                    -- Tag resolutions can still be empty early in boot. Use
                    -- known entries now, but never freeze an incomplete index.
                    if not choices or choices:size() == 0 then ready = false
                    else
                        for k = 0, choices:size() - 1 do
                            local script = choices:get(k)
                            local name = script and script.getFullName and script:getFullName()
                            if name then byType[name] = true else ready = false end
                        end
                    end
                end
            end
        end
    end
    if ready then catalog = {manager = manager, recipes = recipes, count = count, byType = byType} end
    return byType
end

local function supportsWear(script, context)
    -- These native classes have condition-degradation paths. ConditionMax and
    -- ConditionLowerChance alone cannot prove that: both default to 10 even on
    -- ordinary food, drainables and materials. Other classes need more evidence.
    if script.isItemType and ItemType then
        for _, name in ipairs({"WEAPON", "CLOTHING", "ALARM_CLOCK_CLOTHING"}) do
            if ItemType[name] and script:isItemType(ItemType[name]) == true then return true end
        end
    end
    -- Normal tools also wear through declarative native crafting input flags.
    -- SHOW_CONDITION by itself only requests a tooltip and proves no wear.
    local name = script.getFullName and script:getFullName()
    if not name then return false end
    local index = indexRecipes(context)
    return index and index[name] == true
end

-- Physical items always use the native flag, including modded item classes.
-- Scripts have no current flag. Known wear classes or native recipe wear flags
-- with a usable condition range expose healthy/broken alternatives. No item is
-- instantiated and no factory, RNG, OnCreate or OnBreak callback is executed.
function Broken.read(script, item, context)
    if item then
        if not item.isBroken then return nil end
        local broken = item:isBroken()
        if type(broken) == "boolean" then return broken end
        return nil
    end
    if not script or not script.getConditionMax then return nil end
    local maximum = script:getConditionMax()
    if type(maximum) == "number" and maximum > 0 and maximum < math.huge and supportsWear(script, context) then
        return nil, {false, true}
    end
    return nil
end

function Broken.invalidate() catalog = nil end
if Events and Events.OnGameBoot then Events.OnGameBoot.Add(Broken.invalidate) end

return Broken
