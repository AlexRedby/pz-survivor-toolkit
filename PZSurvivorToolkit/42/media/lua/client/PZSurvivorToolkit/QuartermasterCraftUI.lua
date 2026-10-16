local UI = {}

local function placeTick(window)
    local header, tick = window.header, window.qmTick
    if not header or not tick or not header.buttonPanel or not header.buttonColumn then return end
    local cell = header:cellFor(tick)
    if not cell then
        local buttons = header.buttonPanel
        local buttonCell = header:cellFor(buttons)
        if not buttonCell then return end
        local column = header:addColumn(nil, false)
        column.minimumWidth = header.buttonColumn.minimumWidth
        header.buttonColumn.minimumWidth = tick:getWidth() + (header.padding or 6) * 2
        header.buttonColumn = column
        window:removeChild(tick)
        header:setElement(buttonCell.columnIndex, buttonCell.rowIndex, tick)
        header:setElement(header:columnCount() - 1, buttonCell.rowIndex, buttons)
        window:calculateLayout(window:getWidth(), window:getHeight())
        cell = header:cellFor(tick)
    end
    -- Quartermaster still writes window-relative coordinates each frame; restore the table's position.
    cell:setX(cell:getX())
    cell:setY(cell:getY())
end

function UI.install()
    if not LootSorter or not LootSorter._craftHooksAdded then return end
    for _, class in pairs({NC_HandcraftWindow, NC_EntityWindow}) do
        if not class.pzstQuartermasterLayout then
            class.pzstQuartermasterLayout = true
            local prerender = class.prerender
            function class:prerender()
                if prerender then prerender(self) end
                placeTick(self)
            end
        end
    end
end

local function afterGameStart()
    Events.OnTick.Remove(afterGameStart)
    UI.install()
end
-- Quartermaster installs its own wrappers in OnGameStart, in either mod load order.
Events.OnGameStart.Add(function() Events.OnTick.Add(afterGameStart) end)
return UI
