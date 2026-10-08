require "PZSurvivorToolkit/Settings"

local Toolkit = PZSurvivorToolkit
local TVRadio = {}
Toolkit.TVRadio = TVRadio

local function updateCloseButton(window)
    local button = window.closeButton
    if not button then return end
    local keepOpen = Toolkit.Settings.keepMediaWindowOpen()
    button:setVisible(keepOpen)
    if keepOpen then
        button:setX(window:getWidth() - button:getWidth() - 3)
        button:setY(3)
        button:bringToTop()
    end
end

function TVRadio.settingsChanged()
    local class = TVRadio.windowClass
    if not class then return end
    for _, instances in ipairs({class.instances, class.instancesIso}) do
        for _, window in pairs(instances) do updateCloseButton(window) end
    end
end

local function install()
    if not getActivatedMods():contains("TVRadio_ReInvented") or not ISRadioWindow then return end
    local class = ISRadioWindow
    if TVRadio.windowClass == class then return end
    TVRadio.windowClass = class
    local activate, prerender, outside = class.activate, class.prerender, class.onMouseDownOutside
    class.activate = function(...)
        local window = activate(...)
        if window then updateCloseButton(window) end
        return window
    end
    class.prerender = function(self, ...)
        local result = prerender(self, ...)
        updateCloseButton(self)
        return result
    end
    class.onMouseDownOutside = function(self, ...)
        if Toolkit.Settings.keepMediaWindowOpen() then return end
        return outside(self, ...)
    end
end

-- Both upstream mods replace the window class; wrap the final class after loading.
Events.OnGameStart.Add(install)
