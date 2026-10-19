local Codec = TestPresetCodec or dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/QuartermasterPresetCodec.lua')
local function empty(value)
    for _ in pairs(value) do return false end
    return true
end
local function equal(a, b)
    assert(type(a) == type(b), 'codec changed value type')
    if type(a) ~= 'table' then assert(a == b, 'codec changed value'); return end
    for key, value in pairs(a) do equal(value, b[key]) end
    for key in pairs(b) do assert(a[key] ~= nil, 'codec added a field') end
end
local function rejects(text)
    assert(not pcall(Codec.decode, text), 'codec accepted malformed input: ' .. tostring(text))
end
for _, text in ipairs({'', ' \t\r\n', 'return {}', 'return {version=2,presets={}}'}) do
    local presets, version = Codec.decode(text)
    assert(empty(presets) and version == (text:find('version', 1, true) and 2 or 1))
end
local name = TestPresetName or 'Кладовая "еда" \\ 食料 😀\nnext\t\0007'
local samples = {
    [name] = {cats = {['Food/snacks'] = true, [''] = true},
        items = {[TestPresetItem or 'Base.Тест'] = true, ['line\rbreak\n'] = true},
        gen = 1741000000000, rev = 17, createdBy = TestPresetOwner or 'Игрок 😀'},
    version = {cats = {}, items = {}},
    presets = {cats = {}, items = {}},
}
local encoded = Codec.encode(samples)
local decoded, version = Codec.decode(encoded)
assert(version == 2)
equal(samples, decoded)
assert(Codec.encode(decoded) == encoded, 'encoding is not canonical')
local maxInteger = 9007199254740991
equal(Codec.decode(Codec.encode({Max = {gen = maxInteger, rev = 0}})),
    {Max = {cats = {}, items = {}, gen = maxInteger, rev = 0}})
local legacy = 'return { ["version"] = {cats={Food=true}}, ["presets"] = {items={["Base.TinCan"]=true}} }'
decoded, version = Codec.decode(legacy)
assert(version == 1 and decoded.version.cats.Food and decoded.presets.items['Base.TinCan'])
assert(empty(decoded.version.items) and empty(decoded.presets.cats))
local controls = ''
for code = 0, 31 do controls = controls .. string.char(code) end
equal(Codec.decode(Codec.encode({[controls] = {cats = {[controls] = true}, items = {}}})),
    {[controls] = {cats = {[controls] = true}, items = {}}})
local slashes = {}
for code = 0, 127 do slashes[#slashes + 1] = '\\' .. string.char(code) end
slashes = table.concat(slashes) .. '\\'
local slashShape = {[slashes] = {cats = {[slashes] = true}, items = {}, createdBy = slashes}}
equal(Codec.decode(Codec.encode(slashShape)), slashShape)
if string.format('%q', '\\ ') == '"\\ "' then
    rejects('return {[' .. string.format('%q', '\\ ') .. ']={}}')
end
for _, text in ipairs({
    'garbage', 'return', 'return false', 'return nil', 'return {', 'return {} trailing',
    'return {}; os.remove("anything")', 'return {} return {}',
    'return {version=3,presets={}}', 'return {version=1,presets={}}',
    'return {version="2",presets={}}', 'return {version=2,presets=false}',
    'return {version=2,presets={},extra={}}', 'return {version=2,version=2,presets={}}',
    'return {A={},["A"]={}}', 'return {A={cats={},cats={}}}',
    'return {A={cats={Food=true,["Food"]=true}}}',
    'return {A={unknown=true}}', 'return {A={cats=false}}',
    'return {A={items={X=false}}}', 'return {A={items={X=1}}}',
    'return {A={items={[1]=true}}}', 'return {A=false}',
    'return {A={gen=-1}}', 'return {A={rev=0.5}}', 'return {A={gen=9007199254740992}}',
    'return {A={createdBy=false}}', 'return {A={gen="10"}}',
    'return {A={cats={} items={}}}', 'return {A={cats={},,items={}}}',
    'return {A={items={["bad\\999"]=true}}}', 'return {A={items={["bad\\q"]=true}}}',
    'return {A={items={["unterminated]=true}}}', 'return {A={items={["line\nbreak"]=true}}}',
    'return {A={items={X=(function() return true end)()}}}',
    'return {version=2,presets={A={cats={X={}}}}}',
}) do rejects(text) end
rejects(false); rejects(nil); rejects(string.rep(' ', 2000001))
assert(not pcall(Codec.encode, {A = {items = {X = false}}}), 'encoder silently cleaned invalid selections')
assert(not pcall(Codec.encode, {A = {rev = math.huge}}), 'encoder accepted infinity')
assert(not pcall(Codec.encode, {A = {gen = 0 / 0}}), 'encoder accepted NaN')
assert(not pcall(Codec.encode, {[string.rep('x', 2000001)] = {}}), 'encoder exceeded text limit')

-- Fixed examples of the old Quartermaster flat-map and version-2 file layouts.
-- Compatibility is with the saved bytes, not an otherwise unused second parser.
local legacyBody = '["Pantry"] = { cats = { ["Food"]=true, }, items = { ["Base.TinCan"]=true, }, gen = 41 },'
local legacyShape = {Pantry = {cats = {Food = true}, items = {["Base.TinCan"] = true}, gen = 41}}
local flat, flatVersion = Codec.decode('return { ' .. legacyBody .. ' }')
local wrapped, wrappedVersion = Codec.decode('return { version = 2, presets = { ' .. legacyBody .. ' } }')
equal(flat, legacyShape); equal(wrapped, legacyShape)
assert(flatVersion == 1 and wrappedVersion == 2)
print('Quartermaster preset codec passed: strict v1/v2, EOF, shape, bounds, escapes and metadata.')
