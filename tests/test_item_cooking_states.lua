ItemType = {FOOD = "food", NORMAL = "normal"}
ItemTag = {ALREADY_COOKED = "alreadycooked"}
local States = dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/ItemCookingStates.lua")
local function script(cookable, kind, inherent)
    return {isItemType = function(_, expected) return expected == (kind or ItemType.FOOD) end,
        isIsCookable = function() return cookable end,
        hasTag = function(_, tag) return tag == ItemTag.ALREADY_COOKED and inherent == true end,
        InstanceItem = function() error("state inspection must never construct items") end}
end
local function item(definition)
    local value = {burnt = false, cooked = false, cookable = definition:isIsCookable()}
    value.getScriptItem = function() return definition end
    value.IsFood = function() return definition:isItemType(ItemType.FOOD) end
    value.isBurnt = function(self) return self.burnt end
    value.isCooked = function(self) return self.cooked end
    value.isCookable = function(self) return self.cookable end
    return value
end
local meat, fruit, weapon = script(true), script(false), script(true, ItemType.NORMAL)
local food = item(meat)
local function state(expected, definition, value)
    assert(States.read(definition, value) == expected, "unexpected cooking state: " .. tostring(expected))
end
state("raw", meat, food)
food.cooked = true
state("cooked", meat, food)
food.cookable = false
state("cooked", meat, food)
food.burnt = true
state("burnt", meat, food)
food.cooked = false
state("burnt", nil, food)
food.burnt = false
state(false, meat, food)
state(false, fruit, item(fruit))
local nonfood = item(weapon)
nonfood.burnt, nonfood.cooked = true, true
state(false, weapon, nonfood)
state(false, weapon)
state(false, fruit)
local current, possible = States.read(meat)
assert(current == nil and table.concat(possible, ",") == "raw,cooked,burnt",
    "script capability must never fabricate a current raw/cooked/burnt state")
local _, excluded = States.read(fruit)
assert(next(excluded) == nil, "ordinary fruit has no cooking states")
local toast = script(true, nil, true)
local inherent, toastStates = States.read(toast)
assert(inherent == "cooked" and table.concat(toastStates, ",") == "cooked,burnt",
    "native alreadycooked declaration must exclude raw previews")
local toastItem = item(toast)
state("raw", toast, toastItem) -- Physical flags remain authoritative before native update.
toastItem.cooked, toastItem.burnt = true, true
state("burnt", toast, toastItem)
local coldCooked = script(false, nil, true)
local _, coldStates = States.read(coldCooked)
assert(table.concat(coldStates, ",") == "cooked")

-- Partial isolated callers do not have all native Java methods/globals.
state(nil, nil)
state(nil, {})
state(nil, meat, {})
state(nil, meat, {isBurnt = function() return false end})
state("burnt", meat, {isBurnt = function() return true end})
state("cooked", meat, {isBurnt = function() return false end, isCooked = function() return true end})
local alias = item(meat)
alias.isIsCookable, alias.isCookable = alias.isCookable, nil
state("raw", meat, alias)
local fullType, fullTag = ItemType, ItemTag
local isolatedFood = item(meat)
isolatedFood.IsFood = function() return true end
ItemType, ItemTag = nil, nil
state(nil, meat)
state("raw", meat, isolatedFood)
ItemType, ItemTag = fullType, fullTag

if NativeActionRoot then
    local file = assert(io.open(NativeActionRoot .. "/../scripts/generated/items/food.txt"))
    local source = file:read("*a"); file:close()
    local blocks = {}
    for name, block in source:gmatch("item%s+([%w_]+)%s*(%b{})") do blocks[name] = block end
    local function native(name)
        local block = assert(blocks[name], "native fixture missing: " .. name)
        assert(block:match("ItemType%s*=%s*base:food"), "native fixture must be Food")
        return script(block:match("IsCookable%s*=%s*true") ~= nil, nil,
            block:find("base:alreadycooked", 1, true) ~= nil)
    end
    local steak, apple, slices = native("Steak"), native("Apple"), native("BreadSlices")
    state("raw", steak, item(steak))
    state(false, apple, item(apple))
    -- Native Food.update creates ReplaceOnCooked outputs and removes the source
    -- before setting its cooked flag. Do not infer state from replacement names.
    assert(blocks.BreadSlices:match("ReplaceOnCooked%s*=%s*Base.Toast"))
    state("raw", slices, item(slices))
    local sourceState, sourceStates = States.read(slices)
    assert(sourceState == nil and table.concat(sourceStates, ",") == "raw,cooked,burnt",
        "rotten replacement sources can still cook and burn without changing type")
    -- Native Food.update skips ReplaceOnCooked for a rotten source, allowing
    -- both flags below on BreadSlices itself. These live flags must survive.
    local rottenSlices = item(slices)
    rottenSlices.cooked = true
    state("cooked", slices, rottenSlices)
    rottenSlices.cooked, rottenSlices.burnt = false, true
    state("burnt", slices, rottenSlices)
    for _, name in ipairs({"Toast", "Baguette"}) do state("cooked", native(name)) end
    print("native B42.21 Food cookability, fruit, replacement and alreadycooked declarations checked")
else
    print("SKIP native cooking state declarations (NativeActionRoot not supplied)")
end
print("item cooking state tests passed")
