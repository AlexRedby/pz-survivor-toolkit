local selection = require 'QueueTestSelection'
local toolkit=false
for _,id in ipairs(selection.mods) do if id=='PZSurvivorToolkit' then toolkit=true end end
if toolkit then
    local option=assert(PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'))
    option:setValue(selection.mode=='toolkit')
end

Events.OnGameStart.Add(function()
    local ok, problem = pcall(function()
        local size=assert(selection.window_size, 'prepared window_size missing')
        local width,height=getCore():getScreenWidth(),getCore():getScreenHeight()
        print('[QUEUE_TEST] WINDOW_SIZE width='..width..' height='..height)
        assert(width==size[1] and height==size[2], 'window_size differs from prepared viewport: '..width..'x'..height)
        local count = 0
        for _, id in ipairs(selection.mods) do
            assert(getActivatedMods():contains(id), 'selected mod missing: ' .. id)
            count = count + 1
        end
        if toolkit then
            local option = assert(PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'))
            assert(option:getValue() == (selection.mode == 'toolkit'), 'queue option differs from selected mode')
            assert(PZSurvivorToolkit.Settings.actionQueue() == (selection.mode == 'toolkit'), 'queue mode not applied')
        end
        print('[QUEUE_TEST] '..(isClient() and 'NATIVE_CONNECTED' or 'TRUE_SP'))
        print('[QUEUE_TEST] PREFLIGHT_COMPLETE mods=' .. count .. ' mode=' .. selection.mode)
    end)
    if not ok then print('[QUEUE_TEST] FAIL release preflight ' .. tostring(problem)) end
end)
