local Proof = require "PZSurvivorToolkit/SourceProof"
PZSurvivorToolkit = PZSurvivorToolkit or {}
if PZSurvivorToolkit.FoodGoalLabels then return PZSurvivorToolkit.FoodGoalLabels end
local Labels = {}
PZSurvivorToolkit.FoodGoalLabels = Labels
local installed

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function numberBefore(name, suffix)
    if type(name) ~= "string" or name:sub(-#suffix) ~= suffix then return end
    local value = tonumber(name:sub(1, #name - #suffix))
    if finite(value) then return value end
end

local function signedGoal(value, resource)
    return resource .. (value < 0 and "Deficit" or value > 0 and "Reserve" or "Balance")
end

local function portion(option, food)
    if option.notAvailable or type(option.onSelect) ~= "function" or not food
        or not food.getBaseHunger or not food.getHungChange then return "" end
    local ratio, base, remaining = option.param1, food:getBaseHunger(), food:getHungChange()
    if not finite(ratio) or ratio <= 0 or ratio > 1 or not finite(base)
        or not finite(remaining) or remaining >= 0 then return "" end
    base, remaining = math.abs(base), math.abs(remaining)
    -- EatSmart repairs an invalid original hunger value before dispatch.
    if base <= 0 or base + 0.000001 < remaining then base = remaining end
    local fraction = math.min(1, base * ratio / remaining)
    -- Native Eat consumes the final sub-.01 hunger remainder as well.
    if remaining * (1 - fraction) < 0.01 then fraction = 1 end
    if fraction < 0.01 then return " (<1%)" end
    return " (" .. tostring(math.floor(fraction * 100 + 0.5)) .. "%)"
end

local function rename(menu, previous, food, options)
    local calories = {}
    for _, goal in ipairs({{"4", "FullReserve", "calories-max"},
        {"5", "GainWeight", "calories-gain-weight"}, {"6", false, "calories-custom"}}) do
        if options:getOption(goal[1]):getValue() == true then calories[#calories + 1] = goal end
    end
    local calorieRows, rows = {}, {}
    for _, option in ipairs(menu.options) do
        if not previous[option] and option.ES_EatSmart then
            local value = numberBefore(option.name, " % " .. getText("Tooltip_food_Hunger"))
            if value then
                rows[#rows + 1] = {option, value == 0 and "Full" or "Snack"}
            else
                value = numberBefore(option.name, " " .. getText("Tooltip_food_Calories"))
                if value then
                    calorieRows[#calorieRows + 1] = {option, value}
                else
                    value = numberBefore(option.name, " " .. getText("Tooltip_food_Prots"))
                    if value then rows[#rows + 1] = {option, signedGoal(value, "Protein")} end
                end
            end
        end
    end
    -- Disabled EatSmart rows carry no goal metadata. The reviewed producer emits
    -- all enabled calorie goals in this order, even when their numbers coincide.
    if #calorieRows == #calories then
        for index, row in ipairs(calorieRows) do
            local goal, data = calories[index], row[1].param5
            if row[1].notAvailable or type(data) == "table" and data.goalType == goal[3] then
                rows[#rows + 1] = {row[1], goal[2] or signedGoal(row[2], "Energy")}
            end
        end
    end
    for _, row in ipairs(rows) do
        local option, key = row[1], row[2]
        local originalName = option.name
        option.name = getText("UI_PZST_FoodGoal_" .. key) .. portion(option, food)
        local tooltip = option.toolTip or ISInventoryPaneContextMenu.addToolTip()
        local reason = tooltip.description
        tooltip.description = getText("UI_PZST_FoodGoal_Target", originalName)
            .. (type(reason) == "string" and reason ~= "" and " <LINE> " .. reason or "")
        option.toolTip = tooltip
    end
    if #rows > 0 and menu.calcWidth and menu.setWidth then menu:setWidth(menu:calcWidth()) end
end

function Labels.install()
    if installed then return ES_subMenuEat == installed end
    local original = ES_subMenuEat
    if not Proof.closure(original, "ES_subMenuEat.lua")
        or not Proof.matches("media/lua/client/ISUI/ES_subMenuEat.lua", 2834352006, "EatSmartInt", true) then
        return false
    end
    installed = function(menu, items, foodItems, player, playerObj, openingRecipe)
        local previous = {}
        for _, option in ipairs(menu.options) do previous[option] = true end
        original(menu, items, foodItems, player, playerObj, openingRecipe)
        rename(menu, previous, foodItems and foodItems[1], PZAPI.ModOptions:getOptions("EatSmart"))
    end
    ES_subMenuEat = installed
    return true
end

Events.OnGameStart.Add(Labels.install)
return Labels
