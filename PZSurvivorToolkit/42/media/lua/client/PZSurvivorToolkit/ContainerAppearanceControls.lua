require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISButton"
require "ISUI/ISColorPickerHSB"
local Appearance = require "PZSurvivorToolkit/ContainerAppearance"
local Controls = {}
local function text(key) return getText("UI_PZST_Container" .. key) end

function Controls.refresh(picker)
    local draft = picker.toolkitAppearance
    local texture = draft.icon and require("BetterContainers/Helpers").getIconTexture(draft.icon)
    picker.appearanceIcon:setImage(texture)
    picker.appearanceIcon:setTitle(texture and "" or text("Icon"))
    local color = draft.color
    picker.appearanceColor.backgroundColor = color and {r = color.r, g = color.g, b = color.b, a = 0.7}
        or {r = 0.2, g = 0.2, b = 0.2, a = 1}
end

function Controls.chooseIcon(picker)
    require("PZSurvivorToolkit/ContainerIconPicker").open(picker, function(icon)
        if picker.toolkitTagClosed then return end
        picker.toolkitAppearance.icon = icon
        picker.toolkitAppearanceTouched = true
        Controls.refresh(picker)
    end)
end

function Controls.chooseColor(picker)
    if picker.toolkitColorPicker then picker.toolkitColorPicker:removeSelf() end
    local color = picker.toolkitAppearance.color or {r = 0.4, g = 0.4, b = 0.4}
    local popup = ISColorPickerHSB:new(0, 0, ColorInfo.new(color.r, color.g, color.b, 1))
    popup:initialise()
    popup.keepOnScreen, popup.pickedTarget, popup.resetFocusTo = true, picker, picker
    popup:setX(picker.appearanceColor:getAbsoluteX())
    popup:setY(picker.appearanceColor:getAbsoluteY() + picker.appearanceColor:getHeight())
    popup:setPickedFunc(function(_, rgb)
        if picker.toolkitTagClosed then return end
        picker.toolkitAppearance.color = {r = rgb.r, g = rgb.g, b = rgb.b, a = 1}
        picker.toolkitAppearanceTouched = true
        Controls.refresh(picker)
        popup:removeSelf()
    end)
    popup:addToUIManager()
    popup:setInitialColor(ColorInfo.new(color.r, color.g, color.b, 1))
    picker.toolkitColorPicker = popup
    local player = getSpecificPlayer(picker.playerNum or 0)
    if player and player:getJoypadBind() ~= -1 then setJoypadFocus(picker.playerNum or 0, popup) end
end

function Controls.reset(picker)
    picker.toolkitAppearance, picker.toolkitAppearanceTouched = {}, true
    picker.appearanceName:setText("")
    Controls.refresh(picker)
end

function Controls.create(picker)
    if picker.targetKind == "preset" or not Appearance.available() then return end
    picker.toolkitAppearance = Appearance.read(picker.targetObj, picker.targetCI, getSpecificPlayer(picker.playerNum or 0)) or {}
    local color = picker.toolkitAppearance.color
    if color then
        -- Match BC's _normColor, including its legacy alpha scale, so editing a name/icon does
        -- not silently change the tint already rendered for this container.
        local scale = (color.r > 1 or color.g > 1 or color.b > 1 or (color.a or 1) > 1) and 255 or 1
        local function channel(value) return math.max(0, math.min(1, value / scale)) end
        picker.toolkitAppearance.color = {r = channel(color.r), g = channel(color.g), b = channel(color.b),
            a = color.a and channel(color.a) or 1}
    end
    picker.toolkitAppearanceInitialName = picker.toolkitAppearance.name or ""
    picker.appearanceLabel = ISLabel:new(10, 0, 24, text("Name"), 1, 1, 1, 1, UIFont.Small, true)
    picker.appearanceName = ISTextEntryBox:new(picker.toolkitAppearanceInitialName, 82, 0, 240, 24)
    picker.appearanceName.font = UIFont.Medium
    picker.appearanceName:setTooltip(text("NameHint"))
    picker.appearanceIcon = ISButton:new(10, 0, 100, 26, text("Icon"), picker, Controls.chooseIcon)
    picker.appearanceIcon:forceImageSize(22, 22)
    picker.appearanceIcon:setTooltip(text("Icon"))
    picker.appearanceColor = ISButton:new(120, 0, 100, 26, text("Color"), picker, Controls.chooseColor)
    picker.appearanceReset = ISButton:new(230, 0, 100, 26, text("ResetAppearance"), picker, Controls.reset)
    for _, child in ipairs({picker.appearanceLabel, picker.appearanceName, picker.appearanceIcon,
        picker.appearanceColor, picker.appearanceReset}) do
        child:initialise(); child:instantiate(); picker:addChild(child)
    end
    picker.appearanceName:setMaxTextLength(80)
    Controls.refresh(picker)
end

function Controls.layout(picker, top)
    if not picker.appearanceName then return top end
    local w, gap = picker:getWidth() - 20, 6
    local labelW = getTextManager():MeasureStringX(UIFont.Small, text("Name")) + 12
    picker.appearanceLabel:setY(top)
    picker.appearanceName:setX(10 + labelW); picker.appearanceName:setY(top)
    picker.appearanceName:setWidth(w - labelW)
    local bw = (w - gap * 2) / 3
    for index, child in ipairs({picker.appearanceIcon, picker.appearanceColor, picker.appearanceReset}) do
        child:setX(10 + (index - 1) * (bw + gap)); child:setY(top + 30); child:setWidth(bw)
    end
    return top + 64
end

function Controls.value(picker)
    if not picker.appearanceName then return nil end
    local name = picker.appearanceName:getInternalText() or ""
    if not picker.toolkitAppearanceTouched and name == picker.toolkitAppearanceInitialName then return nil end
    local value = picker.toolkitAppearance
    return {name = name, icon = value.icon, color = value.color}
end

function Controls.close(picker)
    if picker.toolkitIconPicker then picker.toolkitIconPicker:close() end
    if picker.toolkitColorPicker then picker.toolkitColorPicker:removeSelf(); picker.toolkitColorPicker = nil end
end

return Controls
