local InventoryClasses = require "PZSurvivorToolkit/InventoryClasses"
require "ISUI/ISInventoryPane"

local function rowIdentity(row)
    if row and not instanceof(row, "InventoryItem") then return row.name or row end
    return row
end

local patched = {}
local function install(class)
    if not class or patched[class] then return end
    patched[class] = true
    local down, up, doubleClick = class.onMouseDown, class.onMouseUp, class.onMouseDoubleClick
    class.onMouseDown = function(self, ...)
        local identity = rowIdentity(self.items[self.mouseOverOption])
        self.toolkitPressedRow = nil
        local result = down(self, ...)
        if self.dragging and ISMouseDrag.draggingFocus == self then
            self.toolkitPressedRow = identity
        end
        return result
    end
    class.onMouseUp = function(self, x, y)
        local identity = self.toolkitPressedRow
        self.toolkitPressedRow = nil
        if identity and x == self.downX and y == self.downY and x >= self.column2
            and not isShiftKeyDown() and not isCtrlKeyDown() then
            -- Refresh can move the pressed item before native mouse-up selects its row again.
            self.mouseOverOption = 0
            for row, item in ipairs(self.items) do
                if rowIdentity(item) == identity then
                    self.mouseOverOption = row
                    break
                end
            end
        end
        self.toolkitLastClickRow = x == self.downX and y == self.downY and identity or nil
        return up(self, x, y)
    end
    class.onMouseDoubleClick = function(self, x, y)
        local identity = rowIdentity(self.items[self.mouseOverOption])
        if self.toolkitLastClickRow and identity ~= self.toolkitLastClickRow
            and not (self.vscroll and self:isMouseOverScrollBar()) then
            -- Two rapid clicks on different items are separate selections, even at the same pixel.
            self.previousMouseUp = nil
            return self:onMouseDown(x, y)
        end
        self.toolkitPressedRow = identity
        return doubleClick(self, x, y)
    end
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
    InventoryClasses.panes(install)
end
Events.OnGameStart.Add(installClasses)
InventoryClasses.onToggle(installClasses)
