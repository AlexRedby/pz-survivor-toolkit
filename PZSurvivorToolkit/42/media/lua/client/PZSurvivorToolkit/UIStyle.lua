require "PZSurvivorToolkit"

local UIStyle = {}
PZSurvivorToolkit.UIStyle = UIStyle
-- Kahlua indexes UTF-16 units; Lua test runtimes index UTF-8 bytes.
local utf8Strings = #"é" > 1

-- Cache complete results, not prefix widths: native glyph kerning/newlines can make
-- longer strings narrower. TextManager replaces font objects when fonts reload.
local cacheManager, fontCaches
local cacheEntries, cacheUnits = 0, 0
local MAX_ENTRIES, MAX_UNITS = 256, 65536

local function fitMeasured(manager, value, width, font, suffix)
    if manager:MeasureStringX(font, value) <= width then return value end
    while #value > 0 do
        local last = #value
        if utf8Strings then
            while last > 1 and value:byte(last) >= 128 and value:byte(last) < 192 do last = last - 1 end
        elseif last > 1 and value:byte(last) >= 56320 and value:byte(last) <= 57343 then last = last - 1 end
        value = value:sub(1, last - 1)
        if manager:MeasureStringX(font, value .. suffix) <= width then return value .. suffix end
    end
    return ""
end

function UIStyle.fit(value, width, font, suffix)
    font, suffix = font or UIFont.Small, suffix or "..."
    local manager = getTextManager()
    local actualFont = manager.getFontFromEnum and manager:getFontFromEnum(font)
    -- Unknown font lifetimes and NaN widths use live measurements.
    if not actualFont or width ~= width then return fitMeasured(manager, value, width, font, suffix) end
    if manager ~= cacheManager then
        cacheManager, fontCaches, cacheEntries, cacheUnits = manager, {}, 0, 0
    end
    local context = fontCaches[font]
    if context and context.font == actualFont then
        local widths = context.values[value]
        local suffixes = widths and widths[width]
        if suffixes and suffixes[suffix] ~= nil then return suffixes[suffix] end
    else
        context = {font = actualFont, values = {}}
        fontCaches[font] = context
    end
    local result = fitMeasured(manager, value, width, font, suffix)
    local units = #value + #suffix + #result
    if units > MAX_UNITS then return result end
    if cacheEntries >= MAX_ENTRIES or cacheUnits + units > MAX_UNITS then
        fontCaches, cacheEntries, cacheUnits = {}, 0, 0
        context = {font = actualFont, values = {}}
        fontCaches[font] = context
    end
    local widths = context.values[value]
    if not widths then widths = {}; context.values[value] = widths end
    local suffixes = widths[width]
    if not suffixes then suffixes = {}; widths[width] = suffixes end
    suffixes[suffix] = result
    cacheEntries, cacheUnits = cacheEntries + 1, cacheUnits + units
    return result
end

function UIStyle.button(button)
    button.backgroundColor = {r = 0.10, g = 0.085, b = 0.07, a = 0.82}
    button.backgroundColorMouseOver = {r = 0.55, g = 0.27, b = 0.09, a = 0.92}
    button.borderColor = {r = 0.42, g = 0.34, b = 0.25, a = 0.65}
    button.textColor = {r = 0.94, g = 0.90, b = 0.83, a = 1}
    return button
end

return UIStyle
