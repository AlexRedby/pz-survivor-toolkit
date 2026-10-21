-- Exercise the real row renderer, including its column geometry and shared text helper.
PZSurvivorToolkit = {}
UIFont = {Small = "small", Medium = "manifest", Large = "wide-dots"}
local fonts = {[UIFont.Medium] = {}, [UIFont.Large] = {}}
local measurements = 0
local function measured(font, value)
    assert(font == UIFont.Medium or font == UIFont.Large, "Manifest must measure with list.font")
    local result, index = 0, 1
    while index <= #value do
        local first = value:byte(index)
        local size = first < 128 and 1 or first >= 240 and 4 or first >= 224 and 3 or first >= 192 and 2
        assert(size, "renderer received a partial Unicode character")
        for continuation = index + 1, index + size - 1 do
            local byte = value:byte(continuation)
            assert(byte and byte >= 128 and byte < 192, "renderer received a partial Unicode character")
        end
        result = result + (first == 46 and (font == UIFont.Large and 30 or 3) or size > 1 and 11 or 9)
        index = index + size
    end
    return result
end
local manager = {
    getFontFromEnum = function(_, font) return fonts[font] end,
    MeasureStringX = function(_, font, value)
        measurements = measurements + 1
        return measured(font, value)
    end,
}
getTextManager = function() return manager end
require = function() end
local style = dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/UIStyle.lua")
require = function(module)
    if module == "PZSurvivorToolkit/UIStyle" then return style end
    if module == "PZSurvivorToolkit/ItemCategories" then return {} end
end
isClient = function() return false end
Events = {OnTick = {}}
LootSorter = {
    _manifestXferHooked = true,
    addOrReplaceHandler = function() end,
    itemTexture = function() end,
}
local window
ISCollapsableWindowJoypad = {derive = function(_, name)
    assert(name == "LSManifestWindow")
    window = {}
    return window
end}
dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/LootSorter_Manifest.lua")
assert(window and window.drawRow, "the actual Manifest row renderer must load")

local drawn = {}
local list
list = {
    font = UIFont.Medium, itemheight = 24, selected = 0,
    getWidth = function() return 200 end,
    drawText = function(_, value, x, y, r, g, b, a, font)
        assert(font == list.font, "Manifest must draw with the measured font")
        drawn[#drawn + 1] = {text = value, x = x, width = measured(font, value)}
    end,
}
local row = {index = 1, item = {name = "😀éЖ洗abcd", cat = "CraftingMaterials", n = 123}}
local function draw()
    drawn = {}
    assert(window:drawRow(list, 7, row, false) == 31, "row height must remain unchanged")
    assert(#drawn == 3, "Manifest must draw name, category and count")
    assert(drawn[1].x == 28 and drawn[2].x == 80, "test must exercise the narrow name column")
    assert(drawn[1].x + drawn[1].width <= drawn[2].x - 4, "item name must stay inside its column")
    assert(drawn[2].width <= 90, "category must stay inside its column")
    assert(drawn[3].text == "123" and drawn[3].x + drawn[3].width == 177,
        "count must remain right-aligned before the scrollbar")
end
draw()
assert(drawn[1].text == "😀éЖ..", "name clipping must preserve Unicode and the Manifest two-dot suffix")
assert(drawn[2].text == "CraftingM..", "category clipping must use the shared helper with two dots")
local warm = measurements
draw()
assert(measurements == warm + 1, "unchanged rows should only remeasure the uncached count")

list.font = UIFont.Large
draw()
assert(drawn[1].text == "", "a suffix wider than the name column must not overflow it")
row.item.name, row.item.cat = "A", nil
draw()
assert(drawn[1].text == "A" and drawn[2].text == "", "short names and missing categories need no suffix")
print("Manifest text fitting passed: actual row drawing, font, two dots, Unicode, narrow columns and warm cache.")
