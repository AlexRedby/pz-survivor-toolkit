-- The upstream catalog stays upstream; verify its calls still match the native path adapter.
if not TVSource then
    print("SKIP TV video source contract requires actual RWMMergedTV source")
    return
end
local prefix = "../../../../workshop/content/108600/3420581050/mods/TVRadio Reinvented/42/media/videos/"
local start, calls = nil, {}
require = function(name) assert(name == "RadioCom/RadioWindowModules/RWMPanel") end
RWMPanel = {derive = function() return {} end}
Events = {OnGameStart = {Add = function(fn) assert(not start); start = fn end}}
UIFont = {Large = 1}
getTextManager = function() return {getFontHeight = function() return 14 end} end
VideoTexture = {getOrCreate = function(path, width, height, async)
    assert(path:sub(1, #prefix) == prefix, "upstream video path changed; review the native adapter")
    local filename = path:sub(#prefix + 1)
    assert(filename:match("^[A-Za-z0-9_-]+%.bik$"), "upstream video filename requires native adapter review")
    assert(width == 160 and height == 120 and async == false)
    local texture = {path = path}
    calls[#calls + 1] = texture
    return texture
end}
assert(loadstring(TVSource))()
assert(type(start) == "function", "upstream video initialization was not registered")
for pass = 1, 2 do
    calls = {}
    start()
    local count, seen = 0, {}
    for filename, texture in pairs(RWMMergedTV.videos) do
        assert(texture.path == prefix .. filename, "catalog key and requested file differ")
        assert(not seen[texture], "catalog reuses a different video's texture")
        seen[texture], count = true, count + 1
    end
    assert(count > 0 and count == #calls, "upstream did not publish every requested video")
end
print("Actual upstream TV catalog and original initialization checks passed.")
