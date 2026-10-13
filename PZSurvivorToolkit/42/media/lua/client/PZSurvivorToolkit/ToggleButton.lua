require "ISUI/ISButton"
require "ISUI/ISContextMenu"
require "PZSurvivorToolkit/Settings"
local UIStyle = require "PZSurvivorToolkit/UIStyle"

local Toolkit = PZSurvivorToolkit
local ToggleButton = ISButton:derive("PZSurvivorToolkitToggleButton")

function ToggleButton:update()
    local player = getPlayer()
    local available = player ~= nil and not player:isDead()
    if self.enable ~= available then
        self:setEnable(available)
        self.toggleKey = nil
    end
    local enabled, key = Toolkit.Settings.isEnabled(), Toolkit.Settings.getToggleKey()
    if self.highlightEnabled == enabled and self.toggleKey == key then return end
    self.highlightEnabled, self.toggleKey = enabled, key
    self.textureColor = enabled and available and {r=1,g=.72,b=.36,a=1} or {r=.55,g=.55,b=.55,a=1}
    local shortcut = key > 0 and getKeyName(key) or getText("UI_PZSurvivorToolkit_no_shortcut")
    self:setTooltip(getText(enabled and "UI_PZSurvivorToolkit_button_on" or "UI_PZSurvivorToolkit_button_off")
        .. "\n" .. getText("UI_PZSurvivorToolkit_button_tooltip", shortcut))
end

function ToggleButton:render()
    ISButton.render(self)
    if self.highlightEnabled then
        self:drawTextureScaledAspect(self.tickTexture, self:getWidth()-10, self:getHeight()-10, 9, 9, 1, 1, 1, 1)
    end
end

local function toggle(_, button)
    local player = getPlayer()
    if not player or player:isDead() then return end
    Toolkit.Settings.toggle()
    button:update()
end

local function openOptions()
    MainScreen.instance:setVisible(true)
    MainOptions.instance:toUI()
    MainOptions.instance:setVisible(true)
    MainOptions.instance.tabs:activateView(getText("UI_mainscreen_mods"))
    local control = PZAPI.ModOptions.Dict.PZSurvivorToolkit:getOption("Enabled").element
    control.parent:setYScroll(math.min(0, control:getHeight() * 3 - control:getY()))
end

local function tools(_, button)
    local player = getPlayer()
    if not player or player:isDead() then return end
    local num = player:getPlayerNum()
    local menu = ISContextMenu.get(num, button:getAbsoluteX()+button:getWidth(), button:getAbsoluteY())
    local wishlist = PZSurvivorWishlist
    if getActivatedMods():contains("PZSurvivorWishlist") and wishlist and wishlist.UI then
        menu:addOption(getText("UI_PZSW_Open"), num, wishlist.UI.toggle)
    end
    if Toolkit.ContextMenus and Toolkit.Settings.contextMenus() then
        menu:addOption(getText("UI_PZSurvivorToolkit_context_editor"), nil, Toolkit.ContextMenus.openEditor)
    end
    menu:addOption(getText("UI_PZSurvivorToolkit_tools_settings"), nil, openOptions)
end

local function icon(class, callback, texture)
    local button = class:new(0, 0, 24, 24, "", nil, callback)
    button:initialise()
    UIStyle.button(button)
    button.backgroundColor.a = 0
    button.isBaseBackgroundVisible, button.isBorderVisible = false, false
    button:setImage(getTexture(texture))
    button:ignoreWidthChange()
    button:ignoreHeightChange()
    button.toolkitSidebarControl = true
    -- Expanding the native sidebar to contain these icons intercepts flyout clicks (Cooking).
    button:addToUIManager()
    return button
end

local owner
local function remove(button)
    if not button then return end
    if button.tooltipUI then
        button.tooltipUI:setVisible(false)
        button.tooltipUI:removeFromUIManager()
    end
    button:removeFromUIManager()
end

local function detach()
    if not owner then return end
    remove(owner.toolkitHighlightButton)
    remove(owner.toolkitToolsButton)
    owner.toolkitHighlightButton, owner.toolkitToolsButton = nil, nil
    owner = nil
end

local function attach()
    local player = getPlayer()
    local data = player and getPlayerData(player:getPlayerNum())
    local sidebar = data and data.equipped
    if owner ~= sidebar then detach(); owner = sidebar end
    if not sidebar then return end
    local button = sidebar.toolkitHighlightButton
    if not Toolkit.Settings.showHighlightButton() and button then
        remove(button)
        sidebar.toolkitHighlightButton, button = nil, nil
    end
    if not sidebar.toolkitToolsButton then
        if player:isDead() then return end
        sidebar.toolkitToolsButton = icon(ISButton, tools, "media/ui/Entity/Icon_Tools_48x48.png")
        sidebar.toolkitToolsButton:setTooltip(getText("UI_PZSurvivorToolkit_tools_tooltip"))
    end
    if Toolkit.Settings.showHighlightButton() and not button and not player:isDead() then
        button = icon(ToggleButton, toggle, "Item_Flashlight2")
        button.tickTexture = getTexture("media/ui/inventoryPanes/Tickbox_Tick.png")
        sidebar.toolkitHighlightButton = button
    end
    local hub = sidebar.toolkitToolsButton
    hub:setEnable(not player:isDead())
    if button then button:update() end
    local nativeWidth = sidebar.invBtn and sidebar.invBtn:getWidth() or sidebar:getWidth()
    local size = math.max(24, math.floor((nativeWidth - 4) / 2))
    -- Beside Inventory stays clear of the default multiplayer chat below the sidebar.
    local x = sidebar:getAbsoluteX() + sidebar:getWidth() + 6
    local maxY = getPlayerScreenTop(player:getPlayerNum()) + getPlayerScreenHeight(player:getPlayerNum())
        - sidebar:getAbsoluteY() - size - 6
    local y = sidebar:getAbsoluteY() + math.max(0, math.min(sidebar.invBtn and sidebar.invBtn:getY() or 0, maxY))
    local function place(control, offset)
        control:setX(x+offset);control:setY(y);control:setWidth(size);control:setHeight(size)
        control:forceImageSize(size-4,size-4)
        control:setVisible(sidebar:getIsVisible())
        if not sidebar:getIsVisible() and control.tooltipUI then
            control.tooltipUI:setVisible(false)
            control.tooltipUI:removeFromUIManager()
        end
    end
    if button then place(button,0) end
    place(hub,button and size+4 or 0)
end

-- Native sidebar-size changes replace the panel; detached controls follow its lifetime.
Events.OnTickEvenPaused.Add(attach)
Events.OnMainMenuEnter.Add(detach)
