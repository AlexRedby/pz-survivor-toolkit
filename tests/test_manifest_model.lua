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

local first=model.tagIdentity({food='remove',tool='add'})
assert(first==model.tagIdentity({tool='add',food='remove'}))
assert(first~=model.tagIdentity({food='add',tool='remove'}))
assert(model.tagIdentity({})=='')

-- Model capture keeps current state separate from possible script states.
local shared = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/'
local originalRequire = require
require = function(name)
    if name == 'PZSurvivorToolkit/ItemCategories' then return {prepareItem=function()end} end
    if name == 'PZSurvivorToolkit/TagCustomization' then return {itemDelta=function()return {}end} end
    if name == 'PZSurvivorToolkit/ItemCookingTags' then return {read=function()return false end} end
    if name == 'PZSurvivorToolkit/ItemCookingStates' then return {read=function(script,item)
        assert(script == item.script, 'capture omitted the physical item script')
        return item.state, {'raw','cooked','burnt'}
    end} end
    error(name)
end
local capture = dofile(shared .. 'PZSurvivorToolkit/ManifestModel.lua')
require = originalRequire
local value = {script={},getFullType=function()return 'Base.Steak'end,
    getDisplayCategory=function()return 'Food'end,getScriptItem=function(self)return self.script end}
local keys = {}
for _, state in ipairs({'raw','cooked','burnt',false}) do
    value.state = state
    local row = capture.item(value)
    assert(row.cookingState == state, 'snapshot lost captured cooking state, including false')
    assert(not keys[row.key], 'snapshot merged different current cooking states')
    keys[row.key] = true
end
value.state = nil
local unknown = capture.item(value)
assert(unknown.cookingState == nil and not keys[unknown.key],
    'snapshot inferred current cooking state from script possibilities')
assert(capture.item(value).key == unknown.key, 'unknown-state identity is unstable')
