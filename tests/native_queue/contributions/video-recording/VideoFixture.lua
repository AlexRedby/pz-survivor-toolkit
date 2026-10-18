local config = require 'ToolkitVideoConfig'
local entered, starting, started, recording, stopped, done = false, false, false, false, false, false
local since, repeated = 0, false
Events.OnMainMenuEnter.Add(function() entered = true end)
Events.OnPreUIDraw.Add(function()
    if not entered or starting or isIngameState() then return end
    starting = true
    assert(toolkitVideoStatus().state == 'idle')
    getCore():setOptionPauseOnFocusloss(false)
    getCore():setOptionVoiceEnable(false)
    getWorld():setGameMode('Sandbox')
    getWorld():setWorld('VideoFixture')
    getWorld():setMap('Muldraugh, KY')
    MainScreen.instance:setDefaultSandboxVars()
    getSandboxOptions():getOptionByName('Zombies'):setValue(6)
    getSandboxOptions():toLua()
    local current, active = ActiveMods.getById('currentGame'), getActivatedMods()
    current:getMods():clear()
    for i = 0, active:size()-1 do current:getMods():add(active:get(i)) end
    MainScreen.instance.createWorld = true
    MapSpawnSelect.instance.selectedRegion = {points={unemployed={{posX=10835,posY=10144,posZ=0}}}}
    MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'})
    MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
end)
Events.OnGameStart.Add(function() started = true; since = getTimestampMs(); setGameSpeed(1) end)
Events.OnTick.Add(function()
    if not started or done then return end
    if not recording and getTimestampMs()-since > 3000 then
        if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
        getPlayer():setGodMod(true)
        assert(toolkitVideoStart(config.output, config.ffmpeg))
        assert(not toolkitVideoStart(config.output, config.ffmpeg))
        recording = true
        since = getTimestampMs()
        print('[VIDEO_TEST] START')
    end
    if recording and not stopped and getTimestampMs()-since > 3500 then
        assert(toolkitVideoStop())
        assert(not toolkitVideoStop())
        stopped = true
        print('[VIDEO_TEST] STOP wallMs=' .. (getTimestampMs()-since))
    end
    if stopped then
        local s = toolkitVideoStatus()
        if s.state == 'completed' or s.state == 'failed' then
            done = true
            print('[VIDEO_TEST] RESULT state=' .. s.state .. ' file=' .. s.file
                .. ' frames=' .. s.frames .. ' seconds=' .. s.seconds .. ' captured=' .. s.captured
                .. ' dropped=' .. s.dropped .. ' width=' .. s.width .. ' height=' .. s.height .. ' error=' .. s.error)
            assert(s.state == 'completed', s.error)
            if not repeated then
                repeated = true
                done, stopped = false, false
                since = getTimestampMs()
                assert(toolkitVideoStart(config.output, config.ffmpeg))
                print('[VIDEO_TEST] RESTART')
            else
                print('[VIDEO_TEST] PASSED')
            end
        end
    end
end)
