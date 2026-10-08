require "ISUI/ISButton"
require "PZSurvivorToolkit/Settings"

local Toolkit = PZSurvivorToolkit
local ToggleButton = ISButton:derive("PZSurvivorToolkitToggleButton")

function ToggleButton:update()
    local player = getPlayer()
    self:setEnable(player ~= nil and not player:isDead())
    local enabled, key = Toolkit.Settings.isEnabled(), Toolkit.Settings.getToggleKey()
    if self.highlightEnabled == enabled and self.toggleKey == key then return end
    self.highlightEnabled, self.toggleKey = enabled, key
    self:setTitle(getText(enabled and "UI_PZSurvivorToolkit_button_on" or "UI_PZSurvivorToolkit_button_off"))
    local shortcut = key > 0 and getKeyName(key) or getText("UI_PZSurvivorToolkit_no_shortcut")
    self:setTooltip(getText("UI_PZSurvivorToolkit_button_tooltip", shortcut))
end

local function toggle(_, button)
    local player = getPlayer()
    if not player or player:isDead() then return end
    Toolkit.Settings.toggle()
    button:update()
end

local function attach()
    local player = getPlayer()
    if not player then return end
    local data = getPlayerData(player:getPlayerNum())
    local sidebar = data and data.equipped
    if not sidebar then return end
    local button = sidebar.toolkitHighlightButton
    if not Toolkit.Settings.showHighlightButton() then
        if button then
            sidebar:removeChild(button)
            if sidebar:getWidth() == button.expandedWidth then sidebar:setWidth(button.sidebarWidth) end
            if sidebar:getHeight() == button:getBottom() then sidebar:setHeight(button.sidebarHeight) end
            sidebar.toolkitHighlightButton = nil
        end
        return
    end
    if player:isDead() or button then return end
    local width = math.max(sidebar:getWidth(),
        getTextManager():MeasureStringX(UIFont.Small, getText("UI_PZSurvivorToolkit_button_on")) + 10,
        getTextManager():MeasureStringX(UIFont.Small, getText("UI_PZSurvivorToolkit_button_off")) + 10)
    local height = getTextManager():getFontHeight(UIFont.Small) + 10
    button = ToggleButton:new(0, sidebar:getHeight() + 15, width, height, "", nil, toggle)
    button.sidebarWidth, button.sidebarHeight, button.expandedWidth = sidebar:getWidth(), sidebar:getHeight(), width
    button:initialise()
    sidebar:addChild(button)
    sidebar:setWidth(width)
    sidebar:setHeight(button:getBottom())
    sidebar.toolkitHighlightButton = button
    button:update()
end

-- Native sidebar-size changes replace the panel, including all its children.
Events.OnTickEvenPaused.Add(attach)
