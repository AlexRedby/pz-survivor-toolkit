require "PZSurvivorToolkit/ActionQueue"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"

local Toolkit = PZSurvivorToolkit
local Panel = ISCollapsableWindow:derive("PZSurvivorToolkitActionQueuePanel")
local List = ISScrollingListBox:derive("PZSurvivorToolkitActionList")
local panels = {}
Toolkit.ActionQueuePanel = Panel

function List:cancelX()
    return self.width - 40
end

function List:rowUnderMouse(x, y)
    if x < 0 or x >= self.width - 14 or y + self:getYScroll() < 0
        or y + self:getYScroll() >= self.height or self:isMouseOverScrollBar() then return end
    return self.items[self:rowAt(x, y)]
end

function List:clearGesture()
    self.pressedCancel, self.dragAction, self.dragging, self.dropTarget = nil, nil, nil, nil
end

function List:onMouseDown(x, y)
    self:clearGesture()
    local row = self:rowUnderMouse(x, y)
    if not row then return end
    if x >= self:cancelX() then
        if not Toolkit.ActionQueue.cancelReason(self.parent.queue, row.item) then self.pressedCancel = row.item end
    else
        ISScrollingListBox.onMouseDown(self, x, y)
        if not Toolkit.ActionQueue.moveReason(self.parent.queue, row.item) then
            self.dragAction, self.dragX, self.dragY = row.item, x, y
        end
    end
    return true
end

function List:onMouseMove(dx, dy)
    ISScrollingListBox.onMouseMove(self, dx, dy)
    if not self.dragAction then return end
    local x, y = self:getMouseX(), self:getMouseY()
    self.dragging = self.dragging or math.abs(x - self.dragX) + math.abs(y - self.dragY) > 5
    local row = self:rowUnderMouse(x, y)
    self.dropTarget = row and row.item
    self.dropAfter = row and y > self:topOfItem(row.index) + row.height / 2
end

function List:onMouseUp(x, y)
    ISScrollingListBox.onMouseUp(self, x, y)
    local row = self:rowUnderMouse(x, y)
    if row and self.pressedCancel == row.item and x >= self:cancelX() then
        Toolkit.ActionQueue.cancel(self.parent.queue, row.item)
    elseif row and self.dragging then
        Toolkit.ActionQueue.move(self.parent.queue, self.dragAction, row.item,
            y > self:topOfItem(row.index) + row.height / 2)
    end
    self:clearGesture()
    return true
end

function List:onMouseUpOutside(x, y)
    ISScrollingListBox.onMouseUpOutside(self, x, y)
    self:clearGesture()
end

function Panel.icon(action)
    if action.craftRecipe and instanceof(action.craftRecipe, "CraftRecipe") then
        local icon = action.craftRecipe:getIconTexture()
        if icon then return icon end
    end
    local item = action.item or action.gun or action.magazine or action.weapon
    if item and instanceof(item, "InventoryItem") and item:getTex() then return item:getTex() end
    if action.Type == "ISWalkToTimedAction" or action.Type == "ISPathFindAction" then
        return getTexture("media/ui/craftingMenus/BuildProperty_Walking.png")
    end
    return getTexture("media/ui/Entity/Icon_Tools_48x48.png")
end

function Panel:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.closeButton:setVisible(false)
    local top = self:titleBarHeight() + 4
    self.list = List:new(8, top, self.width - 16, self.height - top - 12)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = math.max(32, getTextManager():getFontHeight(UIFont.Small) + 12)
    self.list.font = UIFont.Small
    self.list.doDrawItem = Panel.drawRow
    self.list.dragTexture = getTexture("media/ui/dragModIcon.png")
    self.list.cancelTexture = self.closeButtonTexture
    self:addChild(self.list)
end

function Panel.drawRow(list, y, row, alt)
    if y + list:getYScroll() + row.height < 0 or y + list:getYScroll() >= list.height then
        return y + row.height
    end
    local action, queue = row.item, list.parent.queue
    local current = queue.current == action
    local dragged = list.dragAction and list.dragAction.toolkitQueueOperation
    if list.selected == row.index or (list.dragging and dragged and action.toolkitQueueOperation == dragged) then
        list:drawRect(0, y, list.width, row.height, 0.3, 0.6, 0.6, 0.6)
    elseif alt then
        list:drawRect(0, y, list.width, row.height, 0.15, 0.5, 0.5, 0.5)
    end
    local moveReason = Toolkit.ActionQueue.moveReason(queue, action)
    list:drawTextureScaledAspect(list.dragTexture, 3, y + (row.height - 16) / 2, 14, 16,
        moveReason and 0.2 or 0.8, 1, 1, 1)
    list:drawTextureScaledAspect(Panel.icon(action), 22, y + (row.height - 24) / 2, 24, 24, 1, 1, 1, 1)
    local prefix = tostring(row.index) .. ". "
    if current and action.action then prefix = "[" .. tostring(math.floor(action:getJobDelta() * 100)) .. "%] " end
    local cancelX = list:cancelX()
    local top = math.max(0, y + list:getYScroll())
    list:setStencilRect(52, top, cancelX - 56, math.min(row.height, list.height - top))
    list:drawText(prefix .. Toolkit.ActionQueue.label(action), 52, y + (row.height - getTextManager():getFontHeight(UIFont.Small)) / 2,
        current and 1 or 0.85, current and 1 or 0.85, current and 1 or 0.85, 1, UIFont.Small)
    list:clearStencilRect()
    local reason = Toolkit.ActionQueue.cancelReason(queue, action)
    local hover = list.mouseoverselected == row.index and list:getMouseX() >= cancelX
    list:drawRect(cancelX, y + 3, 24, row.height - 6, hover and 0.4 or 0.15, 0.7, 0.3, 0.3)
    list:drawTextureScaledAspect(list.cancelTexture, cancelX + 4, y + (row.height - 16) / 2, 16, 16,
        reason and 0.2 or 1, 1, 1, 1)
    local hint = hover and (reason or "cancel_tip") or (moveReason or "drag_tip")
    row.tooltip = Toolkit.ActionQueue.label(action) .. " <LINE> " .. getText("UI_PZSurvivorToolkit_queue_" .. hint)
    local first, last = Toolkit.ActionQueueOperations.bounds(queue, action)
    if first and last > first then
        row.tooltip = row.tooltip .. " <LINE> " .. getText("UI_PZSurvivorToolkit_queue_group", last - first + 1)
    end
    local dropFirst, dropLast
    if list.dragging and list.dropTarget then
        dropFirst, dropLast = Toolkit.ActionQueueOperations.bounds(queue, list.dropTarget)
    end
    if row.index == (list.dropAfter and dropLast or dropFirst) then
        local blocked = Toolkit.ActionQueue.moveReason(queue, list.dragAction, list.dropTarget, list.dropAfter)
        list:drawRect(0, y + (list.dropAfter and row.height - 2 or 0), cancelX + 24, 2, 1,
            blocked and 1 or 0.3, blocked and 0.3 or 1, 0.3)
    end
    return y + row.height
end

function Panel:update()
    ISCollapsableWindow.update(self)
    local row = self.list.items[self.list.selected]
    local selected = row and row.item
    local changed = #self.list.items ~= #self.queue.queue
    for i, action in ipairs(self.queue.queue) do
        if not self.list.items[i] or self.list.items[i].item ~= action then changed = true; break end
    end
    if changed then
        local scroll = self.list:getYScroll()
        self.list:clearGesture()
        self.list:clear()
        self.list.selected = -1
        for i, action in ipairs(self.queue.queue) do
            self.list:addItem("", action)
            if action == selected then self.list.selected = i end
        end
        self.list:setYScroll(scroll)
    end
    self.title = getText("UI_PZSurvivorToolkit_queue_title", #self.queue.queue)
end

function Panel:onResize()
    ISCollapsableWindow.onResize(self)
    if not self.list then return end
    self.list:setWidth(self.width - 16)
    self.list:setHeight(self.height - self.list.y - 12)
    self.list:clearGesture()
end

function Panel.refresh()
    for playerNum = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(playerNum)
        local queue = player and ISTimedActionQueue.queues[player]
        local panel = panels[playerNum]
        if panel and panel.queue ~= queue then
            panel:removeFromUIManager()
            panels[playerNum], panel = nil, nil
        end
        local visible = Toolkit.Settings.actionQueue() and player and not player:isDead()
            and queue and #queue.queue > 0
        if visible and not panel then
            panel = Panel:new(getPlayerScreenLeft(playerNum) + math.max(80, getPlayerScreenWidth(playerNum) - 440),
                getPlayerScreenTop(playerNum) + math.max(40, getPlayerScreenHeight(playerNum) - 300), 360, 240)
            panel.queue, panel.playerNum = queue, playerNum
            panel.minimumWidth, panel.minimumHeight = 240, 160
            panel:initialise()
            panel:addToUIManager()
            panels[playerNum] = panel
        end
        if panel then
            panel:setVisible(visible == true)
            if not visible then
                panel.list:clearGesture()
                if #panel.list.items > 0 then panel.list:clear() end
            end
        end
    end
    for playerNum, panel in pairs(panels) do
        if playerNum >= getNumActivePlayers() then
            panel:removeFromUIManager()
            panels[playerNum] = nil
        end
    end
end

Events.OnTickEvenPaused.Add(Panel.refresh)
