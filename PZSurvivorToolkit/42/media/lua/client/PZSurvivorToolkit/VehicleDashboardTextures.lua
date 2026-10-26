require "Vehicles/ISUI/ISVehicleDashboard"

PZSurvivorToolkit = PZSurvivorToolkit or {}
local Textures = {}
PZSurvivorToolkit.VehicleDashboardTextures = Textures
local installed = false

local function drawWear(panel, texture, alpha)
    -- B42 getWidthOrig() can synchronously read an unloaded PNG's header.
    -- Keep the pending texture and let the normal asset loader finish it.
    if not texture or not texture:isReady() then return end
    local width = texture:getWidthOrig()
    panel:drawTexture(texture, math.floor((panel.width - width) * 0.5), 0, alpha)
end

function Textures.renderWear(panel)
    local dash = panel.target or panel.parent
    if not dash or panel.width <= 0 or panel.height <= 0 then return end
    local alpha = (YourDash and YourDash.GetWearFxAlpha and YourDash.GetWearFxAlpha()) or 0.90
    if alpha <= 0 then return end
    -- Preserve the authored unscaled canvases, padding, alpha and layer order.
    drawWear(panel, dash.__crackTex, alpha)
    drawWear(panel, dash.__stainTex, alpha)
end

function Textures.bind(dash)
    local overlay = dash and dash.__YourDashGlassOverlay
    if overlay and overlay.__YourDashGlass then
        overlay.render = Textures.renderWear
    end
end

function Textures.install()
    if installed then return true end
    if not getActivatedMods():contains("RealisticDash") then return false end
    local ensure = ISVehicleDashboard._YourDashEnsureGlassOverlay
    if not ensure then return false end
    installed = true

    -- Bind on creation/recreation, without another per-frame dashboard hook.
    function ISVehicleDashboard:_YourDashEnsureGlassOverlay(...)
        ensure(self, ...)
        Textures.bind(self)
    end
    -- A loaded save may already have constructed a driver's dashboard.
    for player = 0, getNumActivePlayers() - 1 do
        Textures.bind(getPlayerVehicleDashboard(player))
    end
    return true
end

Events.OnGameStart.Add(Textures.install)
return Textures
