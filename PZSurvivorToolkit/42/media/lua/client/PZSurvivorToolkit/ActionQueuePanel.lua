require "PZSurvivorToolkit/ActionQueue"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"

local Toolkit = PZSurvivorToolkit
local Panel = ISCollapsableWindow:derive("PZSurvivorToolkitActionQueuePanel")
local List = ISScrollingListBox:derive("PZSurvivorToolkitActionList")
local panels = {}
-- Native queues are replaced between actions; their windows must not own the user's position.
local positions = {}
Toolkit.ActionQueuePanel = Panel

local function moveDecision(queue, action, target, after)
    local policy = Toolkit.ActionQueuePolicy
    if policy and policy.previewMove then return policy.previewMove(queue, action, target, after) end
    local reason = Toolkit.ActionQueue.moveReason(queue, action, target, after)
    return {allowed = reason == nil, reason = reason}
end

local function cancelDecision(queue, action, whole)
    local policy = Toolkit.ActionQueuePolicy
    if policy and policy.previewCancel then return policy.previewCancel(queue, action, whole) end
    local reason
    if whole then reason = Toolkit.ActionQueue.cancelOperationReason(queue, action)
    else reason = Toolkit.ActionQueue.cancelReason(queue, action) end
    return {allowed = reason == nil, reason = reason}
end

-- Keep only short-lived display text, never a permission, resource or snapshot.
-- The clock refreshes hints for external state changes without repeating their
-- dependency analysis at render frequency. Press/release always evaluate live.
local function preview(list, kind, action, target, after, whole)
    local queue = list.parent.queue
    local now = getTimestampMs and getTimestampMs()
    local saved = list.previewText
    if now and saved and now >= saved.at and now - saved.at < 250
        and saved.queue == queue and saved.current == queue.current and saved.count == #queue.queue
        and saved.generation == queue.toolkitOperationGeneration
        and saved.cancel == queue.toolkitCancel and saved.groupCancel == queue.toolkitGroupCancel
        and saved.kind == kind and saved.action == action and saved.target == target
        and saved.after == after and saved.whole == whole then return saved end
    local result = kind == "move" and moveDecision(queue, action, target, after)
        or cancelDecision(queue, action, whole)
    local text = {reason = result.reason, details = Toolkit.ActionQueueLabels.decisionDetails(result)}
    if now then
        text.at, text.queue, text.current, text.count = now, queue, queue.current, #queue.queue
        text.generation, text.cancel, text.groupCancel = queue.toolkitOperationGeneration, queue.toolkitCancel, queue.toolkitGroupCancel
        text.kind, text.action, text.target, text.after, text.whole = kind, action, target, after, whole
        list.previewText = text
    end
    return text
end

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
    self.pressedToggle = nil
    self.pressedOperation = nil
    self.dropRow = nil
    self.previewText = nil
end

function List:onMouseDown(x, y)
    self:clearGesture()
    local row = self:rowUnderMouse(x, y)
    if not row then return end
    if row.header and x < 22 then
        self.pressedToggle = row.operation
    elseif x >= self:cancelX() then
        if row.header or (Toolkit.ActionQueue.isCraftPlanAction(row.item) or Toolkit.ActionQueue.isDeferredWorldAction(row.item) or Toolkit.ActionQueue.isCraftAction(row.item)) then
            local reason, first, last = Toolkit.ActionQueue.cancelOperationReason(self.parent.queue, row.item)
            if not reason then
                self.pressedOperation = {item = row.item, operation = row.operation, members = {}}
                for i = first, last do
                    table.insert(self.pressedOperation.members, self.parent.queue.queue[i])
                end
            end
        elseif not Toolkit.ActionQueue.cancelReason(self.parent.queue, row.item) then
            self.pressedCancel = row.item
        end
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
    self.dropRow = row
    self.dropAfter = row and y > self:topOfItem(row.index) + row.height / 2
end

function List:onMouseUp(x, y)
    ISScrollingListBox.onMouseUp(self, x, y)
    local row = self:rowUnderMouse(x, y)
    if row and row.header and self.pressedToggle == row.operation and x < 22 then
        self.parent.expanded[row.operation] = not self.parent.expanded[row.operation] or nil
        self.parent:update()
    elseif row and (row.header or (Toolkit.ActionQueue.isCraftPlanAction(row.item) or Toolkit.ActionQueue.isDeferredWorldAction(row.item) or Toolkit.ActionQueue.isCraftAction(row.item)))
        and self.pressedOperation and self.pressedOperation.item == row.item
        and self.pressedOperation.operation == row.operation and x >= self:cancelX() then
        Toolkit.ActionQueue.cancelOperation(self.parent.queue, row.item, self.pressedOperation.members)
    elseif row and not row.header and self.pressedCancel == row.item and x >= self:cancelX() then
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
    return Toolkit.ActionQueueLabels.icon(action)
end

function Panel.taskTitle(queue, first, last)
    return Toolkit.ActionQueueLabels.taskTitle(queue, first, last)
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
    self.list.doRepaintStencil = true
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
    if row.header and list.parent.currentIndex and list.parent.currentIndex >= row.first
        and list.parent.currentIndex <= row.last then
        action = queue.current
    end
    local current = queue.current == action
    local dragged = list.dragAction and list.dragAction.toolkitQueueOperation
    if list.selected == row.index or (list.dragging and dragged and action.toolkitQueueOperation == dragged) then
        list:drawRect(0, y, list.width, row.height, 0.3, 0.6, 0.6, 0.6)
    elseif alt then
        list:drawRect(0, y, list.width, row.height, 0.15, 0.5, 0.5, 0.5)
    end
    -- mouseoverselected can outlive a mouse leave or scroll. Use native hit
    -- testing plus current content coordinates before doing any policy work.
    local mouseRow = list:isMouseOver() and list:rowUnderMouse(list:getMouseX(), list:getMouseY())
    local hovered = mouseRow == row
    local cancelX = list:cancelX()
    local hover = hovered and list:getMouseX() >= cancelX
    local toggleHover = hovered and row.header and list:getMouseX() < 22
    local moveResult = hovered and not hover and not toggleHover and not list.dragging and preview(list, "move", action)
    local moveReason = moveResult and moveResult.reason
    local description = Toolkit.ActionQueueLabels.describe(action)
    local iconX, textX = row.header and 42 or 22, row.header and 72 or 52
    if row.header then
        list:drawText(list.parent.expanded[row.operation] and "-" or "+", 7, y + (row.height - 14) / 2,
            1, 1, 1, 1, UIFont.Small)
    end
    list:drawTextureScaledAspect(list.dragTexture, row.header and 23 or 3, y + (row.height - 16) / 2, 14, 16,
        moveReason and 0.2 or 0.8, 1, 1, 1)
    list:drawTextureScaledAspect(description.icon(), iconX, y + (row.height - 24) / 2, 24, 24, 1, 1, 1, 1)
    local prefix = tostring(row.first) .. ". "
    if current and action.action then
        local fitness = Toolkit.ActionQueueFitness and Toolkit.ActionQueueFitness.progress(action)
        local fraction = fitness and fitness.fraction or action:getJobDelta()
        prefix = "[" .. tostring(math.floor(fraction * 100)) .. "%] "
    end
    local top = math.max(0, y + list:getYScroll())
    local label = prefix .. description.title .. (description.target and ": " .. description.target or "")
    local remaining, count
    local right = cancelX - 4
    local clipHeight = math.min(row.height, list.height - top)
    local batch = Toolkit.ActionQueueBatch.progress(queue, row.item)
    if row.header then
        if batch then
            count = getText("UI_PZSurvivorToolkit_queue_" .. batch.unit
                .. (batch.total and "_progress" or "_completed"), batch.completed, batch.total)
            remaining = count
        else
            remaining = getText("UI_PZSurvivorToolkit_queue_remaining", row.last - row.first + 1)
            count = getText("UI_PZSurvivorToolkit_queue_steps", row.last - row.first + 1)
        end
        local countWidth = getTextManager():MeasureStringX(UIFont.Small, count)
        local titleWidth = math.max(0, right - textX - countWidth - 8)
        list:setStencilRect(textX, top, titleWidth, clipHeight)
        list:drawText(row.task, textX, y + 5, 0.85, 0.85, 0.85, 1, UIFont.Small)
        list:clearStencilRect()
        list:repaintStencilRect(textX, top, titleWidth, clipHeight)
    end
    list:setStencilRect(textX, top, right - textX, clipHeight)
    if row.header then
        list:drawTextRight(count, right, y + 5, 0.65, 0.65, 0.65, 1, UIFont.Small)
    end
    list:drawText(label, textX, row.header and y + row.height / 2 or y + (row.height - getTextManager():getFontHeight(UIFont.Small)) / 2,
        current and 1 or 0.85, current and 1 or 0.85, current and 1 or 0.85, 1, UIFont.Small)
    list:clearStencilRect()
    list:repaintStencilRect(textX, top, right - textX, clipHeight)
    local reason
    local operationCancel = row.header or (Toolkit.ActionQueue.isCraftPlanAction(row.item) or Toolkit.ActionQueue.isDeferredWorldAction(row.item) or Toolkit.ActionQueue.isCraftAction(row.item))
    local cancelResult = hover and not list.dragging and preview(list, "cancel", operationCancel and row.item or action, nil, nil, operationCancel)
    reason = cancelResult and cancelResult.reason
    list:drawRect(cancelX, y + 3, 24, row.height - 6, hover and 0.4 or 0.15, 0.7, 0.3, 0.3)
    list:drawTextureScaledAspect(list.cancelTexture, cancelX + 4, y + (row.height - 16) / 2, 16, 16,
        reason and 0.2 or 1, 1, 1, 1)
    local hint = toggleHover and (list.parent.expanded[row.operation] and (batch and "collapse_batch_tip" or "collapse_tip")
        or (batch and "expand_batch_tip" or "expand_tip"))
        or (hover and (reason or (operationCancel and "cancel_operation_tip" or "cancel_tip")) or (moveReason or "drag_tip"))
    row.tooltip = (row.task and row.task .. " <LINE> " or "")
        .. (remaining and remaining .. " <LINE> " or "") .. label
        .. " <LINE> " .. getText("UI_PZSurvivorToolkit_queue_" .. hint)
    local hintResult = hovered and (hover and cancelResult or moveResult)
    local decisionDetails = hintResult and hintResult.details
    if decisionDetails then row.tooltip = row.tooltip .. " <LINE> " .. decisionDetails end
    local token = row.operation or action.toolkitQueueOperation
    if token and token.toolkitPriorityReason then
        row.tooltip = row.tooltip .. " <LINE> " .. Toolkit.ActionQueueLabels.priorityWaiting(token.toolkitPriorityReason)
    end
    if hovered and description.details then row.tooltip = row.tooltip .. " <LINE> " .. description.details end
    if hovered and not batch and row.groupLast > row.groupFirst then
        row.tooltip = row.tooltip .. " <LINE> " .. getText("UI_PZSurvivorToolkit_queue_group", row.groupLast - row.groupFirst + 1)
    end
    local dropFirst, dropLast
    if list.dragging and list.dropRow and mouseRow == list.dropRow then
        dropFirst, dropLast = list.dropRow.groupFirst, list.dropRow.groupLast
    end
    local neighbor = list.items[row.index + (list.dropAfter and 1 or -1)]
    local boundary = list.dropAfter and row.last == dropLast or not list.dropAfter and row.first == dropFirst
    if dropFirst and boundary and (not neighbor or neighbor.first < dropFirst or neighbor.first > dropLast) then
        local dropResult = preview(list, "move", list.dragAction, list.dropTarget, list.dropAfter)
        local blocked = dropResult.reason
        if blocked then
            row.tooltip = row.tooltip .. " <LINE> " .. getText("UI_PZSurvivorToolkit_queue_" .. blocked)
            local blockedDetails = dropResult.details
            if blockedDetails then row.tooltip = row.tooltip .. " <LINE> " .. blockedDetails end
        end
        list:drawRect(0, y + (list.dropAfter and row.height - 2 or 0), cancelX + 24, 2, 1,
            blocked and 1 or 0.3, blocked and 0.3 or 1, 0.3)
    end
    return y + row.height
end

function Panel:update()
    ISCollapsableWindow.update(self)
    local row = self.list.items[self.list.selected]
    local selected = row and row.item
    local selectedHeader = row and row.header
    self.expanded = self.expanded or {}
    local rows, live = {}, {}
    self.currentIndex = nil
    local i, tasks = 1, 0
    while i <= #self.queue.queue do
        local action = self.queue.queue[i]
        local token = action.toolkitQueueOperation
        local last = i
        while token and last < #self.queue.queue and self.queue.queue[last + 1].toolkitQueueOperation == token do
            last = last + 1
        end
        for index = i, last do
            if self.queue.queue[index] == self.queue.current then self.currentIndex = index end
        end
        if token then live[token] = true end
        local batch = Toolkit.ActionQueueBatch.progress(self.queue, action)
        local grouped = last > i or batch and (batch.lazy or batch.total and batch.total > 1 or batch.completed > 0)
        if grouped then
            rows[#rows + 1] = {item = action, operation = token, header = true, first = i, last = last,
                groupFirst = i, groupLast = last, task = Panel.taskTitle(self.queue, i, last)}
        end
        if not grouped or self.expanded[token] then
            for index = i, last do
                rows[#rows + 1] = {item = self.queue.queue[index], operation = token, first = index, last = index,
                    groupFirst = i, groupLast = last}
            end
        end
        tasks = tasks + 1
        i = last + 1
    end
    for token in pairs(self.expanded) do if not live[token] then self.expanded[token] = nil end end
    local changed = #self.list.items ~= #rows
    for index, nextRow in ipairs(rows) do
        local previous = self.list.items[index]
        if not previous or previous.item ~= nextRow.item or previous.header ~= nextRow.header
            or previous.operation ~= nextRow.operation or previous.first ~= nextRow.first or previous.last ~= nextRow.last
            or previous.task ~= nextRow.task then
            changed = true; break
        end
    end
    if changed then
        local scroll = self.list:getYScroll()
        self.list:clearGesture()
        self.list:clear()
        self.list.selected = -1
        local height = 0
        for index, nextRow in ipairs(rows) do
            self.list:addItem("", nextRow.item)
            local added = self.list.items[index]
            added.operation, added.header, added.first, added.last = nextRow.operation, nextRow.header, nextRow.first, nextRow.last
            added.groupFirst, added.groupLast = nextRow.groupFirst, nextRow.groupLast
            added.index, added.task = index, nextRow.task
            if nextRow.header then added.height = self.list.itemheight + getTextManager():getFontHeight(UIFont.Small) + 2 end
            height = height + added.height
            if nextRow.item == selected and nextRow.header == selectedHeader then self.list.selected = index end
        end
        self.list:setScrollHeight(height)
        self.list:setYScroll(scroll)
    end
    self.title = getText("UI_PZSurvivorToolkit_queue_title", tasks)
end

function Panel:clearSnapshots()
    self.list:clearGesture()
    self.list:clear()
    self.expanded = {}
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
            positions[playerNum] = {x = panel:getX(), y = panel:getY()}
            panel:clearSnapshots()
            panel:removeFromUIManager()
            panels[playerNum], panel = nil, nil
        end
        local visible = Toolkit.Settings.actionQueue() and player and not player:isDead()
            and queue and #queue.queue > 0
        if visible and not panel then
            local position = positions[playerNum]
            local x = position and position.x or getPlayerScreenLeft(playerNum) + math.max(80, getPlayerScreenWidth(playerNum) - 440)
            local y = position and position.y or getPlayerScreenTop(playerNum) + math.max(40, getPlayerScreenHeight(playerNum) - 300)
            panel = Panel:new(x, y, 360, 240)
            panel.queue, panel.playerNum = queue, playerNum
            panel.minimumWidth, panel.minimumHeight = 240, 160
            panel:initialise()
            panel:addToUIManager()
            panels[playerNum] = panel
        end
        if panel then
            panel:setVisible(visible == true)
            if not visible then
                panel:clearSnapshots()
            end
        end
    end
    for playerNum, panel in pairs(panels) do
        if playerNum >= getNumActivePlayers() then
            positions[playerNum] = {x = panel:getX(), y = panel:getY()}
            panel:clearSnapshots()
            panel:removeFromUIManager()
            panels[playerNum] = nil
        end
    end
end

Events.OnTickEvenPaused.Add(Panel.refresh)
