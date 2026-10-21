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

-- Repeated draw calls must reuse a complete result, with fresh results for each
-- font generation, manager, width and suffix. No monotonic-width assumption.
local calls, fontObject = 0, {}
local fonts = {[1] = fontObject, [2] = {}}
local manager = {
    getFontFromEnum = function(_, font) return fonts[font] end,
    MeasureStringX = function(_, font, value)
        calls = calls + 1
        return #value * font
    end,
}
getTextManager = function() return manager end
local label = ("x"):rep(2048)
assert(style.fit(label, 24) == ("x"):rep(21) .. "...")
assert(calls > 2000, "the cold path preserves exact native clipping")
local cold = calls
for _ = 1, 100 do assert(style.fit(label, 24) == ("x"):rep(21) .. "...") end
assert(calls == cold, "unchanged rendered labels must not measure every prefix again")
assert(style.fit(label, 23) == ("x"):rep(20) .. "...")
assert(style.fit(label, 24, 1, "..") == ("x"):rep(22) .. "..")
assert(style.fit(label, 24, 2) == ("x"):rep(9) .. "...")
assert(style.fit("abcdef", 1) == "")
local before = calls
assert(style.fit("abcdef", 1) == "" and calls == before, "cache empty results too")
fonts[1] = {}
assert(style.fit(label, 24) == ("x"):rep(21) .. "..." and calls > before, "font reload invalidates cached fits")
local replacement = {getFontFromEnum = manager.getFontFromEnum, MeasureStringX = manager.MeasureStringX}
getTextManager = function() return replacement end
before = calls
style.fit(label, 24)
assert(calls > before, "manager replacement invalidates results")
for i = 1, 300 do style.fit("entry" .. i, 100) end
before = calls
style.fit(label, 24)
assert(calls > before, "entry limit evicts old results")
-- Large keys cannot make a small entry-count cache retain unbounded text.
style.fit("anchor", 100)
for i = 1, 20 do style.fit(("x"):rep(4000) .. i, 5000) end
before = calls
style.fit("anchor", 100)
assert(calls > before, "text-storage budget evicts old results")

local mutableWidth = 1
getTextManager = function() return {MeasureStringX = function() return mutableWidth end} end
assert(style.fit("same", 2) == "same")
mutableWidth = 3
assert(style.fit("same", 2) == "", "unknown font lifetime must remain live")

-- Actual native font metrics need not be monotonic: LF resets the running x,
-- and Japanese Small has a negative extension for U+201A followed by U+2019.
-- Keep walking backwards until the first fitting complete prefix.
local widths = { ["abcd"] = 40, ["abc..."] = 11, ["ab..."] = 12, ["a..."] = 10,
    ["W\n..."] = 10, ["W..."] = 19, ["W\nx"] = 30 }
getTextManager = function() return {MeasureStringX = function(_, _, value) return widths[value] or 50 end} end
assert(style.fit("abcd", 11) == "abc...", "do not assume longer prefixes measure wider")
assert(style.fit("W\nx", 10) == "W\n...", "line breaks retain native measurement semantics")
getTextManager = function() return manager end
assert(style.fit("abcd", 0/0) == "", "NaN width must not become a cache table key")
print("UI text fit cache checks passed: warm draws, font lifetime, bounded storage and non-monotonic metrics.")
