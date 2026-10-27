require "LootSorter_Util"
local Groups = require "PZSurvivorToolkit/ContainerGroups"

LootSorter.addOrReplaceHandler(Events.OnReceiveGlobalModData, "_onReceiveContainerGroups", function(key, value)
    if key ~= Groups.STORE or not Groups.receive(value) then return end
    if LootSorter._picker then LootSorter._picker.needRebuild = true end
end)

LootSorter.addOrReplaceHandler(Events.OnGameStart, "_onGameStartContainerGroups", function()
    Groups.resetReceived()
    LootSorter.removeHandler(Events.OnTick, "_containerGroupsRetry")
    if not isClient() then return end
    ModData.request(Groups.STORE)
    local retryAt = getTimestampMs() + (LootSorter.SYNC_RETRY_MS or 5000)
    LootSorter.addOrReplaceHandler(Events.OnTick, "_containerGroupsRetry", function()
        if getTimestampMs() < retryAt then return end
        LootSorter.removeHandler(Events.OnTick, "_containerGroupsRetry")
        if not Groups.synced() then ModData.request(Groups.STORE) end
    end)
end)

