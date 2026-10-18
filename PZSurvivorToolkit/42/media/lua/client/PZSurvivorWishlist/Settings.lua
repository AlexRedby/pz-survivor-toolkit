require "PZSurvivorWishlist"
require "PZAPI/ModOptions"

local Settings = {}
PZSurvivorWishlist.Settings = Settings
local options = PZAPI.ModOptions:create("PZSurvivorWishlist", getText("UI_PZSW_Title"))
local rows = options:addTickBox("Rows", getText("UI_PZSW_OptionRows"), true)
local ground = options:addTickBox("Ground", getText("UI_PZSW_OptionGround"), true)
local crafting = options:addTickBox("Crafting", getText("UI_PZSW_OptionCrafting"), true)
local key = options:addKeyBind("OpenKey", getText("UI_PZSW_Open"), Keyboard.KEY_K)
local colour = options:addColorPicker("Color", getText("UI_PZSW_OptionColor"), 0.25, 0.85, 0.75, 1)
function Settings.rowsEnabled() return rows:getValue() end
function Settings.groundEnabled() return ground:getValue() end
function Settings.craftingEnabled() return crafting:getValue() end
function Settings.key() return key:getValue() end
function Settings.color() return colour:getValue() end
function options:apply()
    if PZSurvivorWishlist.Highlighter then PZSurvivorWishlist.Highlighter.settingsChanged() end
end
return Settings
