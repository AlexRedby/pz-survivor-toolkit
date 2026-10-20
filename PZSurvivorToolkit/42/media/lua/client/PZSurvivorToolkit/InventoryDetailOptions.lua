-- Adapted from Bravo Item Details v0.0.12 by Bravo.
-- Keep the persisted namespace/option IDs so existing preferences survive.
require "PZAPI/ModOptions"
local Options = {}

local options = PZAPI.ModOptions:create("BravoItemDetails", "Toolkit Item Details")

options:addDescription("Choose what to display in the expanded view in the inventory")

Options.showLabels = options:addTickBox("showLabels", "Show labels", true, "Show labels (Condition/Nutrition/Remaining etc.)")
Options.showBars = options:addTickBox("showBars", "Show progress bars", true, "Show progress bars (red to green bar)")
Options.showNumeric = options:addTickBox("showNumeric", "Show numeric value", true, "Show the numeric value (x/y or x%%)")
Options.showNutritionist = options:addTickBox("showNutritionist", "Show Nutritionist food stats", true, "Show calories, carbs, proteins and fats (requires Nutritionist trait)")

options:addDescription("Sort Settings")

Options.enableSort = options:addTickBox("enableSort", "Enable Sorting of Stack-items", true, "Sort individual stacks depending on either condition, hunger, fluid amount or uses left.")
Options.maxSort = options:addTextEntry("maxSort", "Maximum Stack-items to sort", "50", "Maximum number of items in a stack to sort. Not recommmended to set this over 100 due to performance reasons. Default: 50")


Options.usesSortDir = options:addComboBox("usesSortDir","Uses Sort Direction")
Options.usesSortDir:addItem("Descending",true)
Options.usesSortDir:addItem("Ascending",false)

Options.weaponSortDir = options:addComboBox("weaponSortDir","Weapons/Tools Sort Direction")
Options.weaponSortDir:addItem("Descending",true)
Options.weaponSortDir:addItem("Ascending",false)

Options.vehicleSortDir = options:addComboBox("vehicleSortDir","Vehicle parts Sort Direction")
Options.vehicleSortDir:addItem("Descending",true)
Options.vehicleSortDir:addItem("Ascending",false)

Options.clothesSortDir = options:addComboBox("clothesSortDir","Clothes Sort Direction")
Options.clothesSortDir:addItem("Descending",true)
Options.clothesSortDir:addItem("Ascending",false)

Options.foodSortDir = options:addComboBox("foodSortDir","Food Sort Direction")
Options.foodSortDir:addItem("Descending",true)
Options.foodSortDir:addItem("Ascending",false)

Options.fluidSortDir = options:addComboBox("fluidSortDir","Fluid Sort Direction")
Options.fluidSortDir:addItem("Descending",true)
Options.fluidSortDir:addItem("Ascending",false)

return Options
