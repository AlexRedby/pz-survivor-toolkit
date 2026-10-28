-- Native bait capabilities. Read definitions and existing items only: never
-- create Food, execute item callbacks, or attach/consume a lure to test it.
local Bait = {}

local function both(a, b)
    if a == false or b == false then return false end
    if a == true and b == true then return true end
end

local function fullType(script, item)
    if item and item.getFullType then return item:getFullType() end
    if script and script.getFullName then return script:getFullName() end
end

local function foodType(script, item)
    if item and instanceof then return instanceof(item, "Food") end
    if script and script.isItemType and ItemType and ItemType.FOOD then
        return script:isItemType(ItemType.FOOD)
    end
end

local function fishDefinition(name)
    if not name or not Fishing or type(Fishing.lure) ~= "table" then return nil end
    local all = Fishing.lure.All
    if type(all) == "table" then
        for _ in pairs(all) do return all[name] ~= nil end
    end
    -- Native IndexAllLures runs at game/server start. Category declarations are
    -- already complete during script catalog construction before that event.
    local available = type(all) == "table"
    for key, values in pairs(Fishing.lure) do
        if key ~= "All" and type(values) == "table" then
            available = true
            if values[name] ~= nil then return true end
        end
    end
    if available then return false end
end

local function trapDefinition(name)
    if not name then return nil end
    if type(TrapAnimals) == "table" then
        -- Match native truthy membership, including a zero bait bonus: the
        -- trap's own bonus may still attract that animal. Other Food may enter
        -- the add-bait menu, but cannot attract any defined trap animal.
        for _, animal in ipairs(TrapAnimals) do
            if animal.baits and animal.baits[name] then return true end
        end
        return false
    end
    -- GameLoadingState loads server Lua in client VMs too. Before that phase
    -- TrapDefinition may be unavailable; retry the live registry next read.
end

local function notCooked(item)
    if item and item.isCooked then return not item:isCooked() end
end

local function trapFood(item)
    if not item then return nil end
    local extra, drink
    if item.haveExtraItems then extra = not item:haveExtraItems() end
    if item.getCustomMenuOption then drink = item:getCustomMenuOption() ~= "Drink" end
    return both(extra, drink)
end

-- Current roles and coherent script-preview alternatives. Food candidates need
-- a physical cooked/extra/menu state; declared defaults never become current
-- observations. Preview cooked constraints let callers combine cooking states
-- without inventing a cooked bait. Native fishing has no hunger minimum, and
-- useful trap membership bypasses the menu's generic -0.05 hunger threshold.
function Bait.read(script, item)
    script = script or item and item.getScriptItem and item:getScriptItem()
    local name, food = fullType(script, item), foodType(script, item)
    local fish, trap = fishDefinition(name), trapDefinition(name)
    local roles = {}
    if food == false then
        roles.fishBait, roles.trapBait = fish, false
    elseif food == true then
        roles.fishBait = both(fish, notCooked(item))
        roles.trapBait = both(trap, both(notCooked(item), trapFood(item)))
    else
        if fish == false then roles.fishBait = false end
        if trap == false then roles.trapBait = false end
    end
    local states = {}
    if not item and food == true and (fish ~= false or trap ~= false) then
        states[1] = {fishBait = fish, trapBait = trap, cooked = false}
        if trap == true then
            -- A raw bait can acquire evolved additions or a Drink menu action.
            states[#states + 1] = {fishBait = fish, trapBait = false, cooked = false}
        end
        states[#states + 1] = {fishBait = false, trapBait = false, cooked = true}
    end
    return roles, states
end

return Bait
