local function fixMacVideoPaths()
    if not getActivatedMods():contains("TVRadio_ReInvented") or not isSystemMacOS() or not RWMMergedTV then return end
    local mod = getModInfoByID("TVRadio_ReInvented")
    if not mod then return end
    local directory = mod:getVersionDir()
    if not directory or directory:sub(1, 1) ~= "/" then return end

    -- VideoTexture prepends the game's media/videos/ and bypasses mod file lookup.
    -- ponytail: at most 64 parent folders; use a native base-path API if one becomes exposed.
    for depth = 1, 64 do
        local path = string.rep("../", depth) .. directory:sub(2) .. "/media/videos/"
        if fileExists("media/videos/" .. path .. "TV_Static.bik") then
            function RWMMergedTV.getAllVideos()
                RWMMergedTV.videos = {}
                for _, name in ipairs({
                    "TV_200", "TV_201", "TV_203_C", "TV_203_S", "TV_203_W",
                    "TV_204", "TV_205", "TV_206", "TV_207", "TV_208", "TV_209",
                    "TV_210", "TV_Ad", "TV_Static", "VHS_CarZone", "VHS_Noise",
                }) do
                    local filename = name .. ".bik"
                    RWMMergedTV.videos[filename] = VideoTexture.getOrCreate(path .. filename, 160, 120, false)
                end
            end
            return
        end
    end
end

-- All client mods have loaded; replace the method before upstream OnGameStart calls it.
Events.OnGameBoot.Add(fixMacVideoPaths)
