require "PZSurvivorWishlist/UI"
require "PZSurvivorWishlist/Settings"
require "ISUI/ISEquippedItem"

local W = PZSurvivorWishlist
local owner
local function detach()
    local button = owner and owner.pzswButton
    if button then
        if button.tooltipUI then
            button.tooltipUI:setVisible(false)
            button.tooltipUI:removeFromUIManager()
        end
        button:removeFromUIManager()
        owner.pzswButton = nil
    end
    owner = nil
end

local function attach()
    local player = getPlayer()
    local data = player and getPlayerData(player:getPlayerNum())
    local equipped = data and data.equipped
    if getActivatedMods():contains("PZSurvivorToolkit") then equipped = nil end
    if owner ~= equipped then detach(); owner = equipped end
    if not equipped or not equipped.invBtn then return end
    local size = math.max(24, math.floor((equipped.invBtn:getWidth() - 4) / 2))
    local num = equipped.chr:getPlayerNum()
    local maxY = getPlayerScreenTop(num) + getPlayerScreenHeight(num) - equipped:getAbsoluteY() - size - 6
    local y = equipped:getAbsoluteY() + math.max(0, math.min(equipped.invBtn:getY(), maxY))
    local button = equipped.pzswButton
    if not button then
        button = ISButton:new(0, 0, size, size, "", equipped,
            function(target) W.UI.toggle(target.chr:getPlayerNum()) end)
        button:initialise()
        button:instantiate()
        button:setImage(getTexture("media/ui/Entity/Icon_Tools_48x48.png"))
        button.backgroundColor.a = 0
        button.backgroundColorMouseOver = {r = 0.55, g = 0.27, b = 0.09, a = 0.92}
        button.borderColor = {r = 0.42, g = 0.34, b = 0.25, a = 0.65}
        button.isBaseBackgroundVisible, button.isBorderVisible = false, false
        button:ignoreWidthChange()
        button:ignoreHeightChange()
        button:setTooltip(getText("UI_PZSW_Open"))
        -- Keep the native sidebar's hit area clear of adjacent flyouts.
        button:addToUIManager()
        equipped.pzswButton = button
    end
    button:setX(equipped:getAbsoluteX() + equipped:getWidth() + 6)
    button:setY(y)
    button:setWidth(size)
    button:setHeight(size)
    button:forceImageSize(size - 4, size - 4)
    button:setEnable(not player:isDead())
    button:setVisible(equipped:getIsVisible())
    if not equipped:getIsVisible() and button.tooltipUI then
        button.tooltipUI:setVisible(false)
        button.tooltipUI:removeFromUIManager()
    end
end
Events.OnTickEvenPaused.Add(attach)
Events.OnMainMenuEnter.Add(detach)
Events.OnKeyPressed.Add(function(key)
    if key == 0 or key ~= W.Settings.key() then return end
    if not getPlayer() or getPlayer():isDead() or getCore():isDoingTextEntry() then return end
    if MainOptions and MainOptions.instance and MainOptions.instance:isVisible() then return end
    W.UI.toggle(0)
end)
