require "PZSurvivorToolkit/VehicleDoors"
require "Vehicles/ISUI/ISVehicleDashboard"
require "ISUI/ISButton"

local Dashboard = {}
PZSurvivorToolkit.VehicleDoorDashboard = Dashboard
local Doors = PZSurvivorToolkit.VehicleDoors
local installed = {}

local DoorButton = ISButton:derive("PZSTVehicleDoorButton")
Dashboard.Button = DoorButton

function DoorButton:prerender()
    self:updateTooltip()
end

function DoorButton:render()
    local opacity = self.enable and ((self:isMouseOver() or self.joypadFocused) and 1 or 0.5) or 0.35
    local scale = self.pressed and self.enable and 0.96 or 1
    local margin = math.min(self:getWidth(), self:getHeight()) / 33
    local width, height = (self:getWidth() - margin * 2) * scale, (self:getHeight() - margin * 2) * scale
    local x, y = (self:getWidth() - width) / 2, (self:getHeight() - height) / 2
    local color = self.fillColor
    local radius = math.max(2, math.floor(math.min(width, height) * 3 / 31 + 0.5))
    -- Filled rounded tile, using the same idle/hover opacity as the neighboring shortcuts.
    self:drawRect(x, y + radius, width, height - radius * 2, opacity * 0.30, color.r, color.g, color.b)
    for row = 0, radius - 1 do
        local offset = radius - row - 0.5
        local inset = math.ceil(radius - math.sqrt(radius * radius - offset * offset))
        self:drawRect(x + inset, y + row, width - inset * 2, 1, opacity * 0.30, color.r, color.g, color.b)
        self:drawRect(x + inset, y + height - row - 1, width - inset * 2, 1, opacity * 0.30, color.r, color.g, color.b)
    end
    local iconWidth, iconHeight = width * 0.65, height * 0.65
    self:drawTextureScaledAspect(self.image, x + (width - iconWidth) / 2, y + (height - iconHeight) / 2,
        iconWidth, iconHeight, opacity, 0.04, 0.055, 0.04)
end

local function currentDoor(panel)
    local character, vehicle = panel.character, panel.vehicle
    if not character or not vehicle or character:isDead() or character:getVehicle() ~= vehicle then return end
    local seat = vehicle:getSeat(character)
    if seat < 0 then return end
    local part = vehicle:getPassengerDoor(seat)
    if part and part:getInventoryItem() and part:getDoor() then return part end
end

function Dashboard.click(panel)
    local part = currentDoor(panel)
    if part and not panel.__paxRetracted then Doors.close(panel.character, panel.vehicle, part) end
end

local function hideTooltip(button)
    if button.tooltipUI then
        button.tooltipUI:setVisible(false)
        button.tooltipUI:removeFromUIManager()
    end
end

function Dashboard.update(panel)
    local button = panel.pzstCloseDoorButton
    -- Native clearChildren leaves parent pointers intact; membership owns the control.
    if button and panel.children[button.ID] ~= button then
        hideTooltip(button)
        button = nil
    end
    if not button then
        local texture = getTexture("media/ui/vehicles/door.png")
        if not texture then return end
        button = DoorButton:new(0, 0, 28, 28, "", panel, Dashboard.click)
        button:initialise()
        button:instantiate()
        button:setImage(texture)
        panel:addChild(button)
        panel.pzstCloseDoorButton = button
    end
    local part = currentDoor(panel)
    local visible = part ~= nil and not panel.__paxRetracted
    local enabled = visible and Doors.canClose(panel.character, panel.vehicle, part)
    button:setVisible(visible)
    button:setEnable(enabled == true)
    button.tooltip = getText("ContextMenu_Close_door")
    button.fillColor = enabled and {r=201/255, g=155/255, b=56/255} or {r=0.32, g=0.33, b=0.34}
    if not visible then hideTooltip(button) end
end

function Dashboard.position(panel)
    local button, background = panel.pzstCloseDoorButton, panel.backgroundTex
    if not button or not background then return end
    local side = panel.__YourDashMoveSeatButton or panel.paxMoveSeatBtn
    if side and not side:getIsVisible() then side = nil end
    local width = side and side:getWidth() or 28
    local height = side and side:getHeight() or 28
    local gap = math.max(2, math.floor(width / 16))
    local x, y = background:getX() + background:getWidth() + gap, background:getY() + gap
    if side then
        x, y = side:getX(), side:getY() - height - gap
        -- A compact skin may have no room above its shortcuts; use an adjacent column.
        if y < background:getY() then x, y = side:getX() + side:getWidth() + gap, background:getY() end
    end
    button:setX(x)
    button:setY(y)
    button:setWidth(width)
    button:setHeight(height)
    panel:setWidth(math.max(panel:getWidth(), x + width))
end

local function installClass(class)
    if not class or installed[class] then return end
    installed[class] = true
    local create, prerender, render = class.createChildren, class.prerender, class.render
    function class:createChildren(...)
        create(self, ...)
        Dashboard.update(self)
    end
    function class:prerender(...)
        prerender(self, ...)
        Dashboard.update(self)
    end
    function class:render(...)
        render(self, ...)
        Dashboard.position(self)
    end
end

Events.OnGameStart.Add(function()
    installClass(ISVehicleDashboard)
    -- Realistic Dashboard owns a separate passenger class and render lifecycle.
    installClass(YourDashPassengerDashboard)
end)
return Dashboard
