require "ISUI/ISInventoryPane"

local patched = {}
local function install(class)
    if not class or patched[class] then return end
    patched[class] = true
    for _, name in ipairs({"onMouseMove", "onMouseMoveOutside"}) do
        local move = class[name]
        class[name] = function(self, ...)
            -- Refresh invokes mouse handlers before render rebuilds the row cache.
            if self.draggingMarquis and (#self.items == 0 or self.toolkitPendingMarquee) and #self.itemslist > 0 then
                self.toolkitPendingMarquee = name
                return
            end
            return move(self, ...)
        end
    end
    local refresh = class.refreshContainer
    class.refreshContainer = function(self, ...)
        if self.draggingMarquis then
            self.toolkitPendingMarquee = self:isMouseOver() and "onMouseMove" or "onMouseMoveOutside"
        end
        return refresh(self, ...)
    end
    local render = class.renderdetails
    class.renderdetails = function(self, doDragged, ...)
        -- Preserve the old row map for CleanUI's Shift-selection anchor capture.
        if doDragged == false and self.inventory:isDrawDirty() then
            self:refreshContainer()
        end
        local result = render(self, doDragged, ...)
        if doDragged == false and self.toolkitPendingMarquee then
            local name = self.toolkitPendingMarquee
            self.toolkitPendingMarquee = nil
            if self.draggingMarquis then self[name](self, 0, 0) end
        end
        return result
    end
end

local function installClasses()
    install(ISInventoryPane)
    install(CleanUI_Clean_ISInventoryPane)
    install(CleanUI_Vanilla_ISInventoryPane)
end
Events.OnGameStart.Add(installClasses)
if CleanUI_RegisterInventoryUiToggleCallback then
    CleanUI_RegisterInventoryUiToggleCallback(installClasses)
end
