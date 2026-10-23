local model = TestManifestModel
if not model then
    local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/'
    local originalRequire = require
    local loaded = {}
    require = function(name)
        assert(name:match('^PZSurvivorToolkit/'))
        if not loaded[name] then loaded[name] = dofile(root .. name .. '.lua') end
        return loaded[name]
    end
    model = dofile(root .. 'PZSurvivorToolkit/ManifestModel.lua')
    require = originalRequire
end
-- Native labels arrive from Java. Inject intact strings to bypass source-literal decoding.
local glyphs = {TestAccent or 'é', TestCyrillic or 'Ж', TestCjk or '洗',
    TestEmoji or '🧟', TestNbsp or ' '}
assert(model.text(nil) == nil and model.text(123) == nil)
assert(model.text('') == '' and model.text('abcdef',3) == 'abc')
for _, glyph in ipairs(glyphs) do
    assert(model.text(glyph:rep(600),512) == glyph:rep(math.floor(512 / #glyph)),
        'cap must retain complete characters, including Latin-1 code units')
    assert(model.text('a' .. glyph:rep(600),512) == 'a' .. glyph:rep(math.floor(511 / #glyph)),
        'cap must not split an off-boundary code point')
    assert(model.text(glyph) == glyph, 'short labels must remain intact')
end
local emoji = TestEmoji or '🧟'
assert(model.text('a' .. emoji, #emoji) == 'a', 'partial emoji must be removed completely')
assert(model.text('a' .. emoji, 1 + #emoji) == 'a' .. emoji, 'complete emoji must survive the cap')
assert(model.text(('x'):rep(513)) == ('x'):rep(512), 'default payload limit changed')
print('Manifest model text: native UTF16/Lua UTF8 caps preserve Cyrillic, emoji and Latin-1 boundaries.')
