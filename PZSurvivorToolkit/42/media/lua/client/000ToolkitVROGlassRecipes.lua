local Glass = require "PZSurvivorToolkit/VehicleGlass"
if not Glass.active() then return end

local VRO = require "VRO/Core"
local source = require "VRO_Recipes"
local partLists = require "VRO_PartLists"
-- Remove source definitions before VRO appends them, and cover a late Toolkit load.
Glass.removeLuaRecipes(source.recipes, partLists)
Glass.removeLuaRecipes(VRO.Recipes, VRO.PartLists)
