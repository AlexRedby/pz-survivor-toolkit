require = function() end
PZSurvivorToolkit = {}
local style = TestUIStyle or dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/UIStyle.lua")
UIFont = {Small = 1}
getTextManager = function() return {MeasureStringX = function(_, font, value)
    assert(font == UIFont.Small)
    return #value
end} end

assert(style.fit("", 0) == "")
assert(style.fit("abc", 3) == "abc", "a full label needs no ellipsis")
assert(style.fit("abcdef", 4) == "a...")
assert(style.fit("abcdef", 3) == "...")
for _, width in ipairs({-1, 0, 1, 2}) do
    assert(style.fit("abcdef", width) == "", "even the ellipsis must fit")
end

-- The native harness injects intact Java strings, bypassing Kahlua's source-literal decoder.
local nbsp, emoji = TestNbsp or " ", TestEmoji or "😀"
for _, glyph in ipairs({TestAccent or "é", TestCyrillic or "Ж", TestCjk or "洗", emoji}) do
    assert(style.fit(glyph:rep(6), #glyph + 3) == glyph .. "...", "cut only at a complete character")
end
assert(style.fit("A" .. nbsp .. "Bxx", 4) == "A...", "Latin-1 units are not UTF-8 continuation bytes")
assert(style.fit("AAAA" .. emoji .. "xxxx", 6 + #emoji) == "AAAA...", "remove the whole emoji at a narrow boundary")
assert(style.fit("A" .. emoji .. "xxxx", 4 + #emoji) == "A" .. emoji .. "...", "keep the emoji when it fits")

-- Ask the font manager about rendered width, not just string length.
getTextManager = function() return {MeasureStringX = function(_, _, value)
    local _, wide = value:gsub("W", "")
    return #value + wide * 4
end} end
assert(style.fit("WWxyz", 9) == "W...")
print("UI text fit checks passed: width limits, measured glyphs and intact Unicode boundaries.")
