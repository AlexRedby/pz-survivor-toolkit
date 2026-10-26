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
        if selection.options and selection.options.optimizer_archive then
            local observed=assert(toolkitTestViewport, 'native viewport observer missing')(size[1],size[2])
            assert(observed[1]==size[1] and observed[2]==size[2], 'logical window differs from prepared size')
            assert(observed[7]==width and observed[8]==height, 'Core changed during viewport observation')
            assert(observed[3]==width and observed[4]==height, 'optimizer Core differs from actual framebuffer')
        else
            assert(width==size[1] and height==size[2], 'window_size differs from prepared viewport: '..width..'x'..height)
        end
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
