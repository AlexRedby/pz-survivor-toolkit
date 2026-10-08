local patched = {}
local function install(class, proximity)
    if not class or patched[class] then return end
    patched[class] = true
    local down, select, automatic = class.onBackpackMouseDown, class.selectContainer, class.selectButtonForContainer
    class.onBackpackMouseDown = function(self, ...)
        local previous = proximity.manualContainerOverride[self.player]
        local forced = proximity.isForceSelected[self.player]
        local result = down(self, ...)
        -- Keep choices in selectContainer, where native lock validation runs.
        -- Keep explicit Shift/globe force toggles, which clear the override.
        if self.onCharacter or proximity.isForceSelected[self.player] == forced then
            proximity.manualContainerOverride[self.player] = previous
        end
        return result
    end
    class.selectContainer = function(self, button, ...)
        local container = button and button.inventory
        local remember = container and not self.onCharacter and not self.toolkitAutomaticSelection
            and proximity.isEnabled and proximity.isForceSelected[self.player]
        local previous = proximity.manualContainerOverride[self.player]
        if remember then
            proximity.manualContainerOverride[self.player] = container:getType() ~= "proxInv" and container or nil
        end
        local result = select(self, button, ...)
        -- Native selection can reject a locked container without refreshing.
        if remember and self.inventoryPane.inventory ~= container
            and proximity.manualContainerOverride[self.player] == container then
            proximity.manualContainerOverride[self.player] = previous
        end
        return result
    end
    class.selectButtonForContainer = function(self, ...)
        -- Timed transfers use this path to show their source/destination briefly.
        local previous = self.toolkitAutomaticSelection
        self.toolkitAutomaticSelection = true
        local ok, result = pcall(automatic, self, ...)
        self.toolkitAutomaticSelection = previous
        if not ok then error(result, 0) end
        return result
    end
end

Events.OnGameStart.Add(function()
    if not getActivatedMods():contains("ProximityInventory") then return end
    local proximity = require "ProximityInventory/ProximityInventory"
    if not proximity.manualContainerOverride then return end
    local function installClasses()
        install(ISInventoryPage, proximity)
        install(CleanUI_Clean_ISInventoryPage, proximity)
        install(CleanUI_Vanilla_ISInventoryPage, proximity)
    end
    installClasses()
    if CleanUI_RegisterInventoryUiToggleCallback then
        CleanUI_RegisterInventoryUiToggleCallback(installClasses)
    end
end)
