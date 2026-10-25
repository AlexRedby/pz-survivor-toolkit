require "PZSurvivorToolkit/Settings"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISTickBox"
require "ISUI/ISRichTextPanel"
require "ISUI/ISTextEntryBox"
local Client = require "PZSurvivorToolkit/VehicleDiagnosticsClient"
local Window = ISCollapsableWindow:derive("ToolkitVehicleDiagnostics")
local instance
local function text(id) return getText("UI_PZST_VehicleTrace_" .. id) end
Window.status = Client.localStatus
local function available(status) return status == "active" or status == "off" or status == "error" end
function Window:refresh()
    local status, server = Client.localStatus(), Client.pollServer()
    local pending = server.pending ~= nil
    local path = Client.localPath()
    if self.traceStatus == status and self.lastOperationError == self.operationError
        and self.serverTraceStatus == server.status and self.serverPending == pending
        and self.localLogPath == path and self.serverLogPath == server.path then return end
    self.traceStatus, self.lastOperationError, self.localLogPath = status, self.operationError, path
    self.serverTraceStatus, self.serverPending, self.serverLogPath = server.status, pending, server.path
    self.record:setSelected(1, status == "active")
    self.record:disableOption(text("Record"), not available(status))
    self.serverRecord:setSelected(1, server.status == "active")
    self.serverRecord:disableOption(text("ServerRecord"), pending or not available(server.status)
        or not Client.canControlServer())
    -- Native tooltips parse rich text. Text entries preserve literal path characters.
    self.localPathEntry:setText(path)
    self.serverPathEntry:setText(server.path)
    self.record.tooltip = text("Tip")
    self.serverRecord.tooltip = text("ServerTip")
    self.info.text = (self.operationError and (text("error") .. " <LINE> ") or "")
        .. text("Client") .. ": " .. text(status) .. " <LINE> "
        .. text("Server") .. ": " .. text(pending and "pending" or server.status)
        .. " <LINE> <LINE> " .. text("Help")
    self.info:paginate()
    self:setHeight(self.info.y + self.info:getHeight() + self:resizeWidgetHeight() + 12)
end
function Window:toggle(_, selected)
    self.operationError = not Client.setLocal(selected == true)
    self.traceStatus = nil
    self:refresh()
end
function Window:toggleServer(_, selected)
    Client.setServer(selected == true)
    self.serverTraceStatus = nil
    self:refresh()
end
function Window:createChildren()
    ISCollapsableWindow.createChildren(self)
    local height = getTextManager():getFontHeight(UIFont.Small) + 10
    self.record = ISTickBox:new(16, self:titleBarHeight() + 12, self.width - 32, height, "", self, Window.toggle)
    self.record:initialise(); self:addChild(self.record); self.record:addOption(text("Record"))
    local function pathEntry(y)
        local entry = ISTextEntryBox:new("", 16, y, self.width - 32, height)
        entry:initialise(); entry:instantiate(); self:addChild(entry); entry:setEditable(false)
        return entry
    end
    self.localPathEntry = pathEntry(self.record.y + height + 4)
    self.serverRecord = ISTickBox:new(16, self.localPathEntry.y + height + 8, self.width - 32, height, "", self, Window.toggleServer)
    self.serverRecord:initialise(); self:addChild(self.serverRecord); self.serverRecord:addOption(text("ServerRecord"))
    self.serverPathEntry = pathEntry(self.serverRecord.y + height + 4)
    self.info = ISRichTextPanel:new(12, self.serverPathEntry.y + height + 8, self.width - 24, 180)
    self.info:initialise(); self.info.background = false; self:addChild(self.info)
    self:refresh()
end
function Window:prerender()
    self:refresh()
    ISCollapsableWindow.prerender(self)
end
function Window:close()
    self.localPathEntry:unfocus(); self.serverPathEntry:unfocus()
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    instance = nil -- Both recordings continue until explicitly stopped.
end
function Window.show()
    if instance then instance:bringToTop(); return instance end
    local width = math.min(620, getCore():getScreenWidth() - 24)
    instance = Window:new((getCore():getScreenWidth() - width) / 2, 80, width, 340)
    instance.title = text("Title"); instance.resizable = false
    instance:initialise(); instance:instantiate(); instance:addToUIManager(); instance:bringToTop()
    return instance
end
local options = PZAPI.ModOptions:getOptions("PZSurvivorToolkit")
options:addTitle(text("Title"))
options:addButton("VehicleDiagnostics", text("Open"), text("Tip"), Window.show)
return Window
