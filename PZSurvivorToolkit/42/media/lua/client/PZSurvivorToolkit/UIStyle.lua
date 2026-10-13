require "PZSurvivorToolkit"

local UIStyle = {}
PZSurvivorToolkit.UIStyle = UIStyle

function UIStyle.button(button)
    button.backgroundColor = {r = 0.10, g = 0.085, b = 0.07, a = 0.82}
    button.backgroundColorMouseOver = {r = 0.55, g = 0.27, b = 0.09, a = 0.92}
    button.borderColor = {r = 0.42, g = 0.34, b = 0.25, a = 0.65}
    button.textColor = {r = 0.94, g = 0.90, b = 0.83, a = 1}
    return button
end

return UIStyle
