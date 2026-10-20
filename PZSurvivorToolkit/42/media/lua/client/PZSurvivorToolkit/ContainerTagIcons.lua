local existing = PZSurvivorToolkit.ContainerTagIcons
if existing then return existing end

local Appearance = require "PZSurvivorToolkit/ContainerAppearance"
local Visuals = require "PZSurvivorToolkit/TagVisuals"
local Icons = {}
PZSurvivorToolkit.ContainerTagIcons = Icons
local installed = false

function Icons.install()
    if installed then return true end
    if not Appearance.available() then return false end
    local loaded, helpers = pcall(require, "BetterContainers/Helpers")
    if not loaded or type(helpers) ~= "table" or type(helpers.getIconTexture) ~= "function" then return false end
    local original = helpers.getIconTexture
    helpers.getIconTexture = function(icon, ...)
        if type(icon) == "table" and icon.kind == "pzst-tag" then
            local id = icon.value
            if type(id) ~= "string" or not id:find("%S") then return nil end
            return Visuals.get(id).texture
        end
        return original(icon, ...)
    end
    installed = true
    return true
end

-- Install before the first saved container is rendered, including when its editor never opens.
Icons.install()
Events.OnGameStart.Add(Icons.install)
return Icons
