local adapter = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/TVVideos.lua"
local boot, mac, directory, exists, calls = nil, true, "/Users/test/mods/TVRadio Reinvented/42", true, {}
local original = function() end
local active = true
getActivatedMods = function() return {contains = function(_, id) return active and id == "TVRadio_ReInvented" end} end
isSystemMacOS = function() return mac end
getModInfoByID = function(id)
    assert(id == "TVRadio_ReInvented")
    return directory and {getVersionDir = function() return directory end} or nil
end
Events = {OnGameBoot = {Add = function(fn) boot = fn end}}
local probes = 0
fileExists = function(path)
    probes = probes + 1
    return exists and path == "media/videos/" .. string.rep("../", 13) .. directory:sub(2) .. "/media/videos/TV_Static.bik"
end
VideoTexture = {getOrCreate = function(path, width, height, async)
    assert(width == 160 and height == 120 and async == false)
    calls[#calls + 1] = path
    return path
end}

-- Toolkit may load before the third-party class exists.
RWMMergedTV = nil
dofile(adapter)
boot()
assert(probes == 0)
RWMMergedTV = {getAllVideos = original}
-- Installed-but-disabled mod, even if its class or metadata is available.
active = false
boot()
assert(RWMMergedTV.getAllVideos == original and probes == 0)
active = true
mac = false
boot()
assert(RWMMergedTV.getAllVideos == original and probes == 0)
mac, directory = true, nil
boot()
assert(RWMMergedTV.getAllVideos == original)
directory = "relative/mod/42"
boot()
assert(RWMMergedTV.getAllVideos == original and probes == 0)
directory, exists = "/Users/test/mods/TVRadio Reinvented/42", false
boot()
assert(RWMMergedTV.getAllVideos == original and probes == 64)

exists, probes = true, 0
boot()
assert(RWMMergedTV.getAllVideos ~= original and probes == 13 and #calls == 0)
RWMMergedTV.getAllVideos()
assert(#calls == 16)
for _, path in ipairs(calls) do
    assert(path:sub(1, #string.rep("../", 13)) == string.rep("../", 13))
    assert(path:find("Users/test/mods/TVRadio Reinvented/42/media/videos/", 1, true))
end
assert(RWMMergedTV.videos["TV_203_W.bik"] and RWMMergedTV.videos["TV_Static.bik"])
local count = 0
for _ in pairs(RWMMergedTV.videos) do count = count + 1 end
assert(count == 16)
print("TV macOS video path checks passed.")
