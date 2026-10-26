-- Test-profile evidence only: confirm the engine actually activated the pinned set.
local expected = require "PZOptimizerTrialExpectedMods"
Events.OnGameStart.Add(function()
    local ok, problem = pcall(function()
        local active = getActivatedMods()
        local wanted, missing, extra = {}, {}, {}
        for _, id in ipairs(expected.ids) do
            wanted[id] = true
            if not active:contains(id) then missing[#missing + 1] = id end
        end
        for index = 0, active:size() - 1 do
            local id = active:get(index)
            if not wanted[id] then extra[#extra + 1] = id end
        end
        if #missing > 0 or #extra > 0 then
            print("[OptimizerTrial] PACK_MISMATCH missing=" .. table.concat(missing, ",")
                .. " unexpected=" .. table.concat(extra, ","))
            return
        end
        print("[OptimizerTrial] pack active revision=" .. expected.revision .. " count=" .. #expected.ids)
    end)
    if not ok then print("[OptimizerTrial] PACK_MISMATCH error=" .. tostring(problem)) end
end)
