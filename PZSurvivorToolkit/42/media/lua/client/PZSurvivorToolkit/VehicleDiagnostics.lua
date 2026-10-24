require "PZSurvivorToolkit/Settings"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISTickBox"
require "ISUI/ISRichTextPanel"

local Window = ISCollapsableWindow:derive("ToolkitVehicleDiagnostics")
local instance
local function text(id) return getText("UI_PZST_VehicleTrace_" .. id) end

function Window.status()
    if type(toolkitVehicleTraceStatus) ~= "function" or type(toolkitVehicleTraceSet) ~= "function" then
        return "unavailable"
    end
    local ok, status = pcall(toolkitVehicleTraceStatus)
    if not ok then return "error" end
    if status == "active" or status == "off" or status == "expired" or status == "unsupported" then
        return status
    end
    return "error"
end

function Window:refresh()
    local status = Window.status()
    if self.traceStatus == status and self.lastOperationError == self.operationError then return end
    self.traceStatus, self.lastOperationError = status, self.operationError
    self.record:setSelected(1, status == "active")
    self.record:disableOption(text("Record"), status == "unavailable" or status == "unsupported" or status == "error")
    self.info.text = (self.operationError and (text("error") .. " <LINE> ") or "")
        .. text(status) .. " <LINE> <LINE> " .. text("Help")
    self.info:paginate()
    self:setHeight(self.info.y + self.info:getHeight() + self:resizeWidgetHeight() + 12)
end

function Window:toggle(_, selected)
    -- An expired recording can be started again explicitly; polling never renews it.
    if Window.status() == "expired" and selected then pcall(toolkitVehicleTraceSet, false) end
    local ok = type(toolkitVehicleTraceSet) == "function" and pcall(toolkitVehicleTraceSet, selected == true)
    -- A failed call can still have started the session. Keep the live checkbox
    -- truthful and allow retry when the getter remains available.
    self.operationError = not ok
    self.traceStatus = nil
    self:refresh()
end

function Window:createChildren()
    ISCollapsableWindow.createChildren(self)
    local height = getTextManager():getFontHeight(UIFont.Small) + 10
    self.record = ISTickBox:new(16, self:titleBarHeight() + 12, self.width - 32, height, "", self, Window.toggle)
    self.record:initialise()
    self:addChild(self.record)
    self.record:addOption(text("Record"))
    self.info = ISRichTextPanel:new(12, self.record.y + height + 8, self.width - 24, 180)
    self.info:initialise()
    self.info.background = false
    self:addChild(self.info)
    self:refresh()
end

function Window:prerender()
    self:refresh()
    ISCollapsableWindow.prerender(self)
end

function Window:close()
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    instance = nil -- Closing this window leaves the bounded recording running.
end

function Window.show()
    if instance then instance:bringToTop(); return instance end
    local width = math.min(620, getCore():getScreenWidth() - 24)
    instance = Window:new((getCore():getScreenWidth() - width) / 2, 80, width, 300)
    instance.title = text("Title")
    instance.resizable = false
    instance:initialise()
    instance:instantiate()
    instance:addToUIManager()
    instance:bringToTop()
    return instance
end

-- The checkbox is deliberately transient: Mod Options stores only this entry button.
local options = PZAPI.ModOptions:getOptions("PZSurvivorToolkit")
options:addTitle(text("Title"))
options:addButton("VehicleDiagnostics", text("Open"), text("Tip"), Window.show)
return Window
