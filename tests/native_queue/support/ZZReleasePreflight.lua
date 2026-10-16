local selection = require 'QueueTestSelection'

Events.OnGameStart.Add(function()
    local ok, problem = pcall(function()
        local count = 0
        for _, id in ipairs(selection.mods) do
            assert(getActivatedMods():contains(id), 'selected mod missing: ' .. id)
            count = count + 1
        end
        local option = assert(PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'))
        assert(option:getValue() == (selection.mode == 'toolkit'), 'queue option differs from selected mode')
        assert(PZSurvivorToolkit.Settings.actionQueue() == (selection.mode == 'toolkit'), 'queue mode not applied')
        print('[QUEUE_TEST] PREFLIGHT_COMPLETE mods=' .. count .. ' mode=' .. selection.mode)
    end)
    if not ok then print('[QUEUE_TEST] FAIL release preflight ' .. tostring(problem)) end
end)
