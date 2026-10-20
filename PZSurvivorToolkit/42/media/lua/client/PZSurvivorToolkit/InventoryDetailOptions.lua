-- Adapted from Bravo Item Details v0.0.12 by Bravo.
-- Keep the persisted namespace/option IDs so existing preferences survive.
require "PZAPI/ModOptions"
local config = {}

local options = PZAPI.ModOptions:create("BravoItemDetails", "Toolkit Item Details")

options:addDescription("Choose what to display in the expanded view in the inventory")

options:addTickBox("showLabels", "Show labels", true, "Show labels (Condition/Nutrition/Remaining etc.)")
options:addTickBox("showBars", "Show progress bars", true, "Show progress bars (red to green bar)")
options:addTickBox("showNumeric", "Show numeric value", true, "Show the numeric value (x/y or x%%)")
options:addTickBox("showNutritionist", "Show Nutritionist food stats", true, "Show calories, carbs, proteins and fats (requires Nutritionist trait)")

options:addDescription("Sort Settings")

options:addTickBox("enableSort", "Enable Sorting of Stack-items", true, "Sort individual stacks depending on either condition, hunger, fluid amount or uses left.")
options:addTextEntry("maxSort", "Maximum Stack-items to sort", "50", "Maximum number of items in a stack to sort. Not recommmended to set this over 100 due to performance reasons. Default: 50")


local usesSortCombo = options:addComboBox("usesSortDir","Uses Sort Direction")
usesSortCombo:addItem("Descending",true)
usesSortCombo:addItem("Ascending",false)

local weaponSortCombo = options:addComboBox("weaponSortDir","Weapons/Tools Sort Direction")
weaponSortCombo:addItem("Descending",true)
weaponSortCombo:addItem("Ascending",false)

local vehicleSortCombo = options:addComboBox("vehicleSortDir","Vehicle parts Sort Direction")
vehicleSortCombo:addItem("Descending",true)
vehicleSortCombo:addItem("Ascending",false)

local clothesSortCombo = options:addComboBox("clothesSortDir","Clothes Sort Direction")
clothesSortCombo:addItem("Descending",true)
clothesSortCombo:addItem("Ascending",false)

local foodSortCombo = options:addComboBox("foodSortDir","Food Sort Direction")
foodSortCombo:addItem("Descending",true)
foodSortCombo:addItem("Ascending",false)

local fluidSortCombo = options:addComboBox("fluidSortDir","Fluid Sort Direction")
fluidSortCombo:addItem("Descending",true)
fluidSortCombo:addItem("Ascending",false)

-- This is a helper function that will automatically populate the "config" table.
--- Retrieve each option as: config."ID"
options.apply = function(self)
    for k,v in pairs(self.dict) do
        if v.type == "multipletickbox" then
            for i=1, #v.values do
                config[(k.."_"..tostring(i))] = v:getValue(i)
            end
        elseif v.type == "button" then
            -- do nothing
        else
            config[k] = v:getValue()
        end
    end
end

Events.OnMainMenuEnter.Add(function()
    options:apply()
end)

-- Defaults are needed before the first main-menu event; persisted values are
-- applied again after Mod Options has loaded the saved preferences.
options:apply()
return {config = config, options = options}