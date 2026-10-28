local selection = require 'QueueTestSelection'
if not selection.options.base_walking.verify_toolkit_newmusic_control then return end

Events.OnClientCommand.Add(function(module, command, player)
    if module ~= 'BaseWalkingProfile' or command ~= 'newmusic-proof' then return end
    local ok, problem = pcall(function()
        local compat = assert(PZSurvivorToolkit.NewMusicCompatibility)
        assert(compat.sharedInstalled)
        assert(NMRuntimeConfig.getConvertVanillaCDsAndCDPlayersEnabled == compat.disabled)
        assert(NMRuntimeConfig.getConvertVanillaCDsAndCDPlayersEnabled() == false)
        assert(NMVanillaCDLootConverter.isEnabled() == false)
        local bomb = setmetatable({}, {__index=function() error('Disabled conversion inspected a container') end})
        assert(NMVanillaCDLootConverter.processContainer(bomb, {}) == nil)
        assert(SandboxVars.NewMusic.ConvertVanillaCDsAndCDPlayers == true)
    end)
    sendServerCommand(player, 'BaseWalkingProfile', 'newmusic-proof', {
        serverDisabled=ok, savedSettingEnabled=SandboxVars.NewMusic.ConvertVanillaCDsAndCDPlayers == true,
        error=not ok and tostring(problem) or nil,
    })
end)
