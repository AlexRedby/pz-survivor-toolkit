require "PZSurvivorToolkit"

local UIStyle = {}
PZSurvivorToolkit.UIStyle = UIStyle
-- Kahlua indexes UTF-16 units; Lua test runtimes index UTF-8 bytes.
local utf8Strings = #"é" > 1

function UIStyle.fit(value, width)
    local manager = getTextManager()
    if manager:MeasureStringX(UIFont.Small, value) <= width then return value end
    while #value > 0 do
        local last = #value
        if utf8Strings then
            while last > 1 and value:byte(last) >= 128 and value:byte(last) < 192 do last = last - 1 end
        elseif last > 1 and value:byte(last) >= 56320 and value:byte(last) <= 57343 then last = last - 1 end
        value = value:sub(1, last - 1)
        if manager:MeasureStringX(UIFont.Small, value .. "...") <= width then return value .. "..." end
    end
    return ""
end

function UIStyle.button(button)
    button.backgroundColor = {r = 0.10, g = 0.085, b = 0.07, a = 0.82}
    button.backgroundColorMouseOver = {r = 0.55, g = 0.27, b = 0.09, a = 0.92}
    button.borderColor = {r = 0.42, g = 0.34, b = 0.25, a = 0.65}
    button.textColor = {r = 0.94, g = 0.90, b = 0.83, a = 1}
    return button
end

return UIStyle
