require "PZSurvivorWishlist/UI"
require "PZSurvivorWishlist/Settings"
require "ISUI/ISEquippedItem"

local W = PZSurvivorWishlist
local function add(equipped)
    if getActivatedMods():contains("PZSurvivorToolkit") then return end
    if not equipped.invBtn then return end
    if equipped.pzswButton and equipped.pzswButton.parent == equipped then return end
    local size = math.max(24, math.floor((equipped.invBtn:getWidth() - 4) / 2))
    local num = equipped.chr:getPlayerNum()
    local maxY = getPlayerScreenTop(num) + getPlayerScreenHeight(num) - equipped:getAbsoluteY() - size - 6
    local y = math.max(0, math.min(equipped.invBtn:getY(), maxY))
    local button = ISButton:new(equipped:getWidth() + 6, y, size, size,
        "", equipped, function(target) W.UI.toggle(target.chr:getPlayerNum()) end)
    button:initialise()
    button:instantiate()
    button:setImage(getTexture("media/ui/Entity/Icon_Tools_48x48.png"))
    button:forceImageSize(size - 4, size - 4)
    button.backgroundColor.a = 0
    button.backgroundColorMouseOver = {r = 0.55, g = 0.27, b = 0.09, a = 0.92}
    button.borderColor = {r = 0.42, g = 0.34, b = 0.25, a = 0.65}
    button.isBaseBackgroundVisible, button.isBorderVisible = false, false
    button:ignoreWidthChange()
    button:ignoreHeightChange()
    equipped:addChild(button)
    equipped:addMouseOverToolTipItem(button, getText("UI_PZSW_Open"))
    equipped.pzswButton = button
    equipped:shrinkWrap(0, 0)
end
local original = ISEquippedItem.initialise
function ISEquippedItem:initialise(...)
    -- Sidebar scaling destroys and rebuilds native children.
    self.pzswButton = nil
    local result = original(self, ...)
    add(self)
    return result
end
Events.OnGameStart.Add(function()
    local data = getPlayerData(0)
    if data and data.equipped then add(data.equipped) end
end)
Events.OnKeyPressed.Add(function(key)
    if key == 0 or key ~= W.Settings.key() then return end
    if not getPlayer() or getPlayer():isDead() or getCore():isDoingTextEntry() then return end
    if MainOptions and MainOptions.instance and MainOptions.instance:isVisible() then return end
    W.UI.toggle(0)
end)
