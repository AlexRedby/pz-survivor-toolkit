local InventoryClasses = {}

function InventoryClasses.panes(install, cleanFirst)
    if not cleanFirst then install(ISInventoryPane, ISInventoryPane ~= CleanUI_Vanilla_ISInventoryPane) end
    install(CleanUI_Clean_ISInventoryPane, true)
    install(CleanUI_Vanilla_ISInventoryPane, false)
    if cleanFirst then install(ISInventoryPane, ISInventoryPane ~= CleanUI_Vanilla_ISInventoryPane) end
end

function InventoryClasses.onToggle(callback)
    if type(CleanUI_RegisterInventoryUiToggleCallback) == "function" then
        CleanUI_RegisterInventoryUiToggleCallback(callback)
    end
end

return InventoryClasses
