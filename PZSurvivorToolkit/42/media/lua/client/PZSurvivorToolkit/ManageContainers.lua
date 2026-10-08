local mods = getActivatedMods()
if not mods:contains("manageContainers") or not mods:contains("CleanUI") then return end

local function registerHandler()
    local handler = ISInventoryWindowControlHandler_TransferAssignedContainers
    if not handler then return end
    local enhanced = CleanUI_Clean_ISInventoryWindowContainerControls or ISInventoryWindowContainerControls
    if enhanced then enhanced.AddHandler(handler) end
    if CleanUI_Vanilla_ISInventoryWindowContainerControls then
        CleanUI_Vanilla_ISInventoryWindowContainerControls.AddHandler(handler)
    end
end

Events.OnGameStart.Add(function()
    -- CleanUI's runtime-off inventory uses a separate, namespaced handler registry.
    if CleanUI_RegisterInventoryUiToggleCallback then
        require "CleanUI/Vanilla/CleanUI_Vanilla_ISInventoryWindowContainerControls"
        CleanUI_RegisterInventoryUiToggleCallback(registerHandler)
    end
    registerHandler()
end)
