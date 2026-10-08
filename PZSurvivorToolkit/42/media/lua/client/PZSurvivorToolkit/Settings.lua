require("PZAPI/ModOptions")

PZSurvivorToolkit = PZSurvivorToolkit or {}
PZSurvivorToolkit.Settings = PZSurvivorToolkit.Settings or {}

local Toolkit = PZSurvivorToolkit
local Settings = Toolkit.Settings

local DEFAULT_ENABLED = true
local DEFAULT_COLOR = { r = 1.0, g = 0.55, b = 0.05, a = 1.0 }
local DEFAULT_TOGGLE_KEY = Keyboard.KEY_F8
local DEFAULT_RADIUS = 15
local RADIUS_BY_INDEX = { 5, 10, 15, 20 }

local function notifySettingsChanged()
    if Toolkit.Highlighter and Toolkit.Highlighter.settingsChanged then
        Toolkit.Highlighter.settingsChanged()
    end
    if Toolkit.TVRadio then
        Toolkit.TVRadio.settingsChanged()
    end
end

local options = PZAPI.ModOptions:create(
    "PZSurvivorToolkit",
    getText("UI_options_PZSurvivorToolkit_name")
)

options:addTitle(getText("UI_options_PZSurvivorToolkit_title"))

local enabledOption = options:addTickBox(
    "Enabled",
    getText("UI_options_PZSurvivorToolkit_enabled"),
    DEFAULT_ENABLED,
    getText("UI_options_PZSurvivorToolkit_enabled_tooltip")
)

local sidebarOption = options:addTickBox(
    "ShowHighlightButton",
    getText("UI_options_PZSurvivorToolkit_sidebar_button"),
    true,
    getText("UI_options_PZSurvivorToolkit_sidebar_button_tooltip")
)

local colorOption = options:addColorPicker(
    "Color",
    getText("UI_options_PZSurvivorToolkit_color"),
    DEFAULT_COLOR.r,
    DEFAULT_COLOR.g,
    DEFAULT_COLOR.b,
    DEFAULT_COLOR.a,
    getText("UI_options_PZSurvivorToolkit_color_tooltip")
)

local toggleKeyOption = options:addKeyBind(
    "ToggleKey",
    getText("UI_options_PZSurvivorToolkit_toggle_key"),
    DEFAULT_TOGGLE_KEY,
    getText("UI_options_PZSurvivorToolkit_toggle_key_tooltip")
)

local radiusOption = options:addComboBox(
    "Radius",
    getText("UI_options_PZSurvivorToolkit_radius"),
    getText("UI_options_PZSurvivorToolkit_radius_tooltip")
)
radiusOption:addItem(getText("UI_options_PZSurvivorToolkit_radius_5"), false)
radiusOption:addItem(getText("UI_options_PZSurvivorToolkit_radius_10"), false)
radiusOption:addItem(getText("UI_options_PZSurvivorToolkit_radius_15"), true)
radiusOption:addItem(getText("UI_options_PZSurvivorToolkit_radius_20"), false)

options:addTitle(getText("UI_options_PZSurvivorToolkit_clothing_title"))
local clothingOption = options:addTickBox(
    "NeutralClothingComparisons",
    getText("UI_options_PZSurvivorToolkit_clothing_neutral"),
    true,
    getText("UI_options_PZSurvivorToolkit_clothing_neutral_tooltip")
)

local mediaWindowOption, vhsControlsOption
if getActivatedMods():contains("TVRadio_ReInvented") then
    options:addTitle(getText("UI_options_PZSurvivorToolkit_media_title"))
    mediaWindowOption = options:addTickBox(
        "KeepMediaWindowOpen",
        getText("UI_options_PZSurvivorToolkit_media_window"),
        true,
        getText("UI_options_PZSurvivorToolkit_media_window_tooltip")
    )
    mediaWindowOption.onChangeApply = notifySettingsChanged
    vhsControlsOption = options:addTickBox(
        "ImproveVHSControls",
        getText("UI_options_PZSurvivorToolkit_vhs_controls"),
        true,
        getText("UI_options_PZSurvivorToolkit_vhs_controls_tooltip")
    )
end

options.apply = function()
    notifySettingsChanged()
end

enabledOption.onChangeApply = notifySettingsChanged
colorOption.onChangeApply = notifySettingsChanged
toggleKeyOption.onChangeApply = notifySettingsChanged
radiusOption.onChangeApply = notifySettingsChanged

function Settings.showHighlightButton()
    return sidebarOption:getValue() == true
end

function Settings.neutralClothingComparisons()
    return clothingOption:getValue() == true
end

function Settings.keepMediaWindowOpen()
    return mediaWindowOption ~= nil and mediaWindowOption:getValue() == true
end

function Settings.improveVHSControls()
    return vhsControlsOption ~= nil and vhsControlsOption:getValue() == true
end

function Settings.isEnabled()
    if enabledOption and enabledOption.getValue then
        return enabledOption:getValue() == true
    end
    return DEFAULT_ENABLED
end

function Settings.getColor()
    local color = colorOption and colorOption.getValue and colorOption:getValue()
    if not color then
        return {
            r = DEFAULT_COLOR.r,
            g = DEFAULT_COLOR.g,
            b = DEFAULT_COLOR.b,
            a = DEFAULT_COLOR.a,
        }
    end
    return {
        r = tonumber(color.r) or DEFAULT_COLOR.r,
        g = tonumber(color.g) or DEFAULT_COLOR.g,
        b = tonumber(color.b) or DEFAULT_COLOR.b,
        a = tonumber(color.a) or DEFAULT_COLOR.a,
    }
end

function Settings.getRadius()
    local index = radiusOption and radiusOption.getValue and tonumber(radiusOption:getValue())
    return RADIUS_BY_INDEX[index or 3] or DEFAULT_RADIUS
end

function Settings.getToggleKey()
    local key = toggleKeyOption and toggleKeyOption.getValue and tonumber(toggleKeyOption:getValue())
    return key or DEFAULT_TOGGLE_KEY
end

function Settings.toggle()
    if not enabledOption or not enabledOption.setValue then
        return
    end
    enabledOption:setValue(not Settings.isEnabled())
    PZAPI.ModOptions:save()
    notifySettingsChanged()
end
