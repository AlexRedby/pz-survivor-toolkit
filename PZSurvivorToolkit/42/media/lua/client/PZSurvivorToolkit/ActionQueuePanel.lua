require "PZSurvivorToolkit/ActionQueue"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"

local Toolkit = PZSurvivorToolkit
local Panel = ISCollapsableWindow:derive("PZSurvivorToolkitActionQueuePanel")
local panels = {}
Toolkit.ActionQueuePanel = Panel

function Panel:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.closeButton:setVisible(false)
    local top = self:titleBarHeight() + 4
    self.list = ISScrollingListBox:new(8, top, self.width - 16, self.height - top - 42)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = getTextManager():getFontHeight(UIFont.Small) + 12
    self.list.font = UIFont.Small
    self.list.doDrawItem = Panel.drawRow
    self:addChild(self.list)
    self.cancelButton = ISButton:new(8, self.height - 34, self.width - 16, 24,
        getText("UI_PZSurvivorToolkit_queue_cancel"), self, Panel.cancelSelected)
    self.cancelButton:initialise()
    self:addChild(self.cancelButton)
end

function Panel.drawRow(list, y, row, alt)
    if y + list:getYScroll() + row.height < 0 or y + list:getYScroll() >= list.height then
        return y + row.height
    end
    local action = row.item
    local current = list.parent.queue.current == action
    if list.selected == row.index then
        list:drawRect(0, y, list.width, row.height, 0.3, 0.6, 0.6, 0.6)
    elseif alt then
        list:drawRect(0, y, list.width, row.height, 0.15, 0.5, 0.5, 0.5)
    end
    local prefix = tostring(row.index) .. ". "
    if current and action.action then
        prefix = "[" .. tostring(math.floor(action:getJobDelta() * 100)) .. "%] "
    end
    list:drawText(prefix .. Toolkit.ActionQueue.label(action), 6, y + 5,
        current and 1 or 0.85, current and 1 or 0.85, current and 1 or 0.85, 1, UIFont.Small)
    return y + row.height
end

function Panel:cancelSelected()
    local row = self.list.items[self.list.selected]
    if row then Toolkit.ActionQueue.cancel(self.queue, row.item) end
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
        self.list:clear()
        self.list.selected = -1
        for i, action in ipairs(self.queue.queue) do
            self.list:addItem("", action)
            if action == selected then self.list.selected = i end
        end
        self.list:setYScroll(scroll)
    end
    row = self.list.items[self.list.selected]
    local reason = "select"
    if row then reason = Toolkit.ActionQueue.cancelReason(self.queue, row.item) end
    self.cancelButton:setEnable(reason == nil)
    self.cancelButton:setTooltip(getText("UI_PZSurvivorToolkit_queue_" .. (reason or "cancel_tip")))
    self.title = getText("UI_PZSurvivorToolkit_queue_title", #self.queue.queue)
end

function Panel:onResize()
    ISCollapsableWindow.onResize(self)
    if not self.list then return end
    self.list:setWidth(self.width - 16)
    self.list:setHeight(self.height - self.list.y - 42)
    self.cancelButton:setY(self.height - 34)
    self.cancelButton:setWidth(self.width - 16)
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
            if not visible and #panel.list.items > 0 then panel.list:clear() end
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
