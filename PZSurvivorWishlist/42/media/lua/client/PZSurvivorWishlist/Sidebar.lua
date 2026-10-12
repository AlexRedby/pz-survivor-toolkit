require "PZSurvivorWishlist/UI"
require "PZSurvivorWishlist/Settings"
require "ISUI/ISEquippedItem"

local W = PZSurvivorWishlist
local function add(equipped)
    if not equipped.invBtn then return end
    if equipped.pzswButton and equipped.pzswButton.parent == equipped then return end
    local bottom = 0
    for _, child in pairs(equipped:getChildren()) do
        if child.Type == "ISButton" then bottom = math.max(bottom, child:getBottom()) end
    end
    local button = ISButton:new(0, bottom + 10, equipped.invBtn:getWidth(), equipped.invBtn:getHeight(),
        getText("UI_PZSW_Sidebar"), equipped, function(target) W.UI.toggle(target.chr:getPlayerNum()) end)
    button:initialise()
    button:instantiate()
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
